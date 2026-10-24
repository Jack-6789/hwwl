#!/bin/bash

print_with_delay() {
    text="$1"
    delay="$2"
    for ((i = 0; i < ${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}

show_notice() {
    local message="$1"
    echo "#######################################################################################################################"
    echo ""
    echo "                                ${message}"
    echo ""
    echo "#######################################################################################################################"
}

print_with_delay "sing-reality-hy2-box" 0.05
echo ""
echo ""

install_base(){
  if ! command -v jq &> /dev/null; then
      echo "jq is not installed. Installing..."
      if [ -n "$(command -v apt)" ]; then
          apt update > /dev/null 2>&1
          apt install -y jq > /dev/null 2>&1
      elif [ -n "$(command -v yum)" ]; then
          yum install -y epel-release
          yum install -y jq
      elif [ -n "$(command -v dnf)" ]; then
          dnf install -y jq
      else
          echo "Cannot install jq. Please install jq manually and rerun the script."
          exit 1
      fi
  fi
}

regenarte_cloudflared_argo(){
  pid=$(pgrep -f cloudflared)
  if [ -n "$pid" ]; then
    kill "$pid"
  fi

  vmess_port=$(jq -r '.inbounds[2].listen_port' /root/sbox/sbconfig_server.json)

  /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux > argo.log 2>&1 &
  sleep 2
  clear
  echo 等待cloudflare argo生成地址
  sleep 5

  argo=$(cat argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
  echo "$argo" | base64 > /root/sbox/argo.txt.b64
  rm -rf argo.log
}

download_singbox(){
  arch=$(uname -m)
  case ${arch} in
      x86_64) arch="amd64" ;;
      aarch64) arch="arm64" ;;
      armv7l) arch="armv7" ;;
  esac

  latest_version_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | grep -Po '"tag_name": "\K.*?(?=")' | sort -V | tail -n 1)
  latest_version=${latest_version_tag#v}

  package_name="sing-box-${latest_version}-linux-${arch}"
  url="https://github.com/SagerNet/sing-box/releases/download/${latest_version_tag}/${package_name}.tar.gz"

  curl -sLo "/root/${package_name}.tar.gz" "$url"
  tar -xzf "/root/${package_name}.tar.gz" -C /root
  mv "/root/${package_name}/sing-box" /root/sbox

  rm -r "/root/${package_name}.tar.gz" "/root/${package_name}"

  chown root:root /root/sbox/sing-box
  chmod +x /root/sbox/sing-box
}

download_cloudflared(){
  arch=$(uname -m)
  case ${arch} in
      x86_64) cf_arch="amd64" ;;
      aarch64) cf_arch="arm64" ;;
      armv7l) cf_arch="arm" ;;
  esac

  cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
  curl -sLo "/root/sbox/cloudflared-linux" "$cf_url"
  chmod +x /root/sbox/cloudflared-linux
}

show_client_configuration() {
  current_listen_port=$(jq -r '.inbounds[0].listen_port' /root/sbox/sbconfig_server.json)
  current_server_name=$(jq -r '.inbounds[0].tls.server_name' /root/sbox/sbconfig_server.json)
  uuid=$(jq -r '.inbounds[0].users[0].uuid' /root/sbox/sbconfig_server.json)
  public_key=$(base64 --decode /root/sbox/public.key.b64)
  short_id=$(jq -r '.inbounds[0].tls.reality.short_id[0]' /root/sbox/sbconfig_server.json)
  server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)

  echo ""
  echo ""
  show_notice "VLESS 通用链接"
  echo ""
  server_link="vless://$uuid@$server_ip:$current_listen_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$current_server_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#VLESS-$server_ip"
  echo "$server_link"
  echo ""

  show_notice "Reality 客户端通用参数"
  echo "服务器ip: $server_ip"
  echo "监听端口: $current_listen_port"
  echo "UUID: $uuid"
  echo "域名SNI: $current_server_name"
  echo "Public Key: $public_key"
  echo "Short ID: $short_id"
  echo ""

  hy_current_listen_port=$(jq -r '.inbounds[1].listen_port' /root/sbox/sbconfig_server.json)
  hy_current_server_name=$(openssl x509 -in /root/self-cert/cert.pem -noout -subject -nameopt RFC2253 | awk -F'=' '{print $NF}')
  hy_password=$(jq -r '.inbounds[1].users[0].password' /root/sbox/sbconfig_server.json)

  hy2_server_link="hysteria2://$hy_password@$server_ip:$hy_current_listen_port?insecure=1&sni=$hy_current_server_name#Hysteria2-$server_ip"

  show_notice "Hysteria2 通用链接"
  echo "$hy2_server_link"
  echo ""

  show_notice "Hysteria2 客户端通用参数"
  echo "服务器ip: $server_ip"
  echo "端口号: $hy_current_listen_port"
  echo "password: $hy_password"
  echo "域名SNI: $hy_current_server_name"
  echo "跳过证书验证: True"
  echo ""

  show_notice "Hysteria2 客户端yaml文件"
cat << EOF
server: $server_ip:$hy_current_listen_port
auth: $hy_password
tls:
  sni: $hy_current_server_name
  insecure: true
fastOpen: true
socks5:
  listen: 127.0.0.1:5080
EOF

  argo=$(base64 --decode /root/sbox/argo.txt.b64)
  vmess_uuid=$(jq -r '.inbounds[2].users[0].uuid' /root/sbox/sbconfig_server.json)
  ws_path=$(jq -r '.inbounds[2].transport.path' /root/sbox/sbconfig_server.json)

  show_notice "vmess ws 通用链接参数"
  echo "vmess TLS 443"
  echo 'vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"sing-box-vmess-tls","tls":"tls","type":"none","v":"2"}' | base64 -w 0)
  echo ""
  echo "vmess 80"
  echo 'vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"80","ps":"sing-box-vmess","tls":"","type":"none","v":"2"}' | base64 -w 0)
  echo ""
}

uninstall_singbox() {
  echo "Uninstalling..."
  systemctl stop sing-box
  systemctl disable sing-box > /dev/null 2>&1

  rm /etc/systemd/system/sing-box.service
  rm -rf /root/sbox/
  rm -rf /root/self-cert/
  echo "DONE!"
}

install_base

if [ -f "/root/sbox/sbconfig_server.json" ] && [ -f "/root/sbox/sing-box" ] && [ -f "/root/sbox/public.key.b64" ] && [ -f "/root/sbox/argo.txt.b64" ] && [ -f "/etc/systemd/system/sing-box.service" ]; then
    echo "sing-box-reality-hysteria2已经安装"
    echo ""
    echo "请选择选项:"
    echo ""
    echo "1. 重新安装"
    echo "2. 修改配置"
    echo "3. 显示客户端配置"
    echo "4. 卸载"
    echo "5. 更新sing-box内核"
    echo "6. 手动重启cloudflared"
    echo ""
    read -p "Enter your choice (1-6): " choice

    case $choice in
        1)
          show_notice "Reinstalling..."
          uninstall_singbox
        ;;
        2)
          show_notice "开始修改reality端口和域名"
          current_listen_port=$(jq -r '.inbounds[0].listen_port' /root/sbox/sbconfig_server.json)
          read -p "请输入想要修改的端口号 (当前端口为 $current_listen_port): " listen_port
          listen_port=${listen_port:-$current_listen_port}

          current_server_name=$(jq -r '.inbounds[0].tls.server_name' /root/sbox/sbconfig_server.json)
          read -p "请输入想要使用的h2域名 (当前域名为 $current_server_name): " server_name
          server_name=${server_name:-$current_server_name}

          hy_current_listen_port=$(jq -r '.inbounds[1].listen_port' /root/sbox/sbconfig_server.json)
          read -p "请输入想要修改的hysteria2端口 (当前端口为 $hy_current_listen_port): " hy_listen_port
          hy_listen_port=${hy_listen_port:-$hy_current_listen_port}

          jq --arg listen_port "$listen_port" --arg server_name "$server_name" --arg hy_listen_port "$hy_listen_port" \
          '.inbounds[1].listen_port = ($hy_listen_port | tonumber) |
           .inbounds[0].listen_port = ($listen_port | tonumber) |
           .inbounds[0].tls.server_name = $server_name |
           .inbounds[0].tls.reality.handshake.server = $server_name' \
           /root/sbox/sbconfig_server.json > /root/sb_modified.json

          mv /root/sb_modified.json /root/sbox/sbconfig_server.json
          systemctl restart sing-box
          show_client_configuration
          exit 0
        ;;
      3)
          show_client_configuration
          exit 0
      ;;
      4)
          uninstall_singbox
          exit 0
      ;;
      5)
          show_notice "Update Sing-box..."
          download_singbox
          if /root/sbox/sing-box check -c /root/sbox/sbconfig_server.json; then
              systemctl daemon-reload
              systemctl enable sing-box > /dev/null 2>&1
              systemctl restart sing-box
          fi
          exit 0
      ;;
      6)
          regenarte_cloudflared_argo
          show_client_configuration
          exit 0
      ;;
      *)
          echo "Invalid choice. Exiting."
          exit 1
      ;;
    esac
fi

mkdir -p "/root/sbox/"

download_singbox
download_cloudflared

echo "开始配置Reality"
echo ""
key_pair=$(/root/sbox/sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
echo "$public_key" | base64 > /root/sbox/public.key.b64

uuid=$(/root/sbox/sing-box generate uuid)
short_id=$(/root/sbox/sing-box generate rand --hex 8)

read -p "请输入Reality端口 (默认8888，回车): " listen_port
listen_port=${listen_port:-8888}

read -p "请输入想要使用的域名 (默认itunes.apple.com，回车): " server_name
server_name=${server_name:-itunes.apple.com}

echo "开始配置hysteria2"
hy_password=$(/root/sbox/sing-box generate rand --hex 8)
read -p "请输入hysteria2监听端口 (默认8443，回车): " hy_listen_port
hy_listen_port=${hy_listen_port:-8443}

read -p "输入自签证书域名 (默认bing.com，回车): " hy_server_name
hy_server_name=${hy_server_name:-bing.com}

mkdir -p /root/self-cert/
openssl ecparam -genkey -name prime256v1 -out /root/self-cert/private.key
openssl req -new -x509 -days 36500 -key /root/self-cert/private.key -out /root/self-cert/cert.pem -subj "/CN=${hy_server_name}"

echo "开始配置vmess"
vmess_uuid=$(/root/sbox/sing-box generate uuid)
read -p "请输入vmess端口 (默认15555，回车): " vmess_port
vmess_port=${vmess_port:-15555}

read -p "ws路径 (默认随机生成，回车): " ws_path
ws_path=${ws_path:-$(/root/sbox/sing-box generate rand --hex 6)}

pid=$(pgrep -f cloudflared)
if [ -n "$pid" ]; then
  kill "$pid"
fi

/root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux > argo.log 2>&1 &
sleep 2
clear
echo 等待cloudflare argo生成地址
sleep 5

argo=$(cat argo.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
echo "$argo" | base64 > /root/sbox/argo.txt.b64
rm -rf argo.log

server_ip=$(curl -s4m8 ip.sb -k) || server_ip=$(curl -s6m8 ip.sb -k)

jq -n \
  --arg listen_port "$listen_port" \
  --arg vmess_port "$vmess_port" \
  --arg vmess_uuid "$vmess_uuid" \
  --arg ws_path "$ws_path" \
  --arg server_name "$server_name" \
  --arg private_key "$private_key" \
  --arg short_id "$short_id" \
  --arg uuid "$uuid" \
  --arg hy_listen_port "$hy_listen_port" \
  --arg hy_password "$hy_password" \
  --arg server_ip "$server_ip" \
'{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ($listen_port | tonumber),
      "users": [
        {
          "uuid": $uuid,
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": $server_name,
        "reality": {
          "enabled": true,
          "handshake": {
            "server": $server_name,
            "server_port": 443
          },
          "private_key": $private_key,
          "short_id": [$short_id]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ($hy_listen_port | tonumber),
      "users": [
        {
          "password": $hy_password
        }
      ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "/root/self-cert/cert.pem",
        "key_path": "/root/self-cert/private.key"
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "::",
      "listen_port": ($vmess_port | tonumber),
      "users": [
        {
          "uuid": $vmess_uuid,
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": $ws_path
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "inbound": ["vless-in", "hy2-in", "vmess-in"],
        "outbound": "direct"
      }
    ],
    "final": "direct"
  }
}' > /root/sbox/sbconfig_server.json

cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing
