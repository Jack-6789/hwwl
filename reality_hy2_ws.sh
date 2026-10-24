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
    echo "                                                                                                                       "
    echo "                                ${message}                                                                             "
    echo "                                                                                                                       "
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

  /root/sbox/cloudflared-linux tunnel --url http://localhost:$vmess_port --no-autoupdate --edge-ip-version auto --protocol h2mux>argo.log 2>&1 &
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
  echo "Architecture: $arch"

  case ${arch} in
      x86_64) arch="amd64" ;;
      aarch64) arch="arm64" ;;
      armv7l) arch="armv7" ;;
  esac

  latest_version_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | grep -Po '"tag_name": "\K.*?(?=")' | sort -V | tail -n 1)
  latest_version=${latest_version_tag#v}
  echo "Latest version: $latest_version"

  package_name="sing-box-${latest_version}-linux-${arch}"
  url="https://github.com/SagerNet/sing-box/releases/download/${latest_version_tag}/${package_name}.tar.gz"

  curl -sLo "/root/${package_name}.tar.gz" "$url"
  tar -xzf "/root/${package_name}.tar.gz" -C /root
  mv "/root/${package_name}/sing-box" /root/sbox

  rm -r "/root/${package_name}.tar.gz" "/root/${package_name}"

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
  echo ""

  server_link="vless://$uuid@$server_ip:$current_listen_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$current_server_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#VLESS-$server_ip"

  echo "$server_link"
  echo ""
  echo ""

  show_notice "Reality 客户端通用参数"
  echo ""
  echo ""
  echo "服务器ip: $server_ip"
  echo "监听端口: $current_listen_port"
  echo "UUID: $uuid"
  echo "域名SNI: $current_server_name"
  echo "Public Key: $public_key"
  echo "Short ID: $short_id"
  echo ""
  echo ""

  hy_current_listen_port=$(jq -r '.inbounds[1].listen_port' /root/sbox/sbconfig_server.json)
  hy_current_server_name=$(openssl x509 -in /root/self-cert/cert.pem -noout -subject -nameopt RFC2253 | awk -F'=' '{print $NF}')
  hy_password=$(jq -r '.inbounds[1].users[0].password' /root/sbox/sbconfig_server.json)

  hy2_server_link="hysteria2://$hy_password@$server_ip:$hy_current_listen_port?insecure=1&sni=$hy_current_server_name#Hysteria2-$server_ip"

  show_notice "Hysteria2 通用链接"
  echo ""
  echo "$hy2_server_link"
  echo ""
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
  echo ""
  echo ""
  echo "以下为vmess链接，替换speed.cloudflare.com为自己的优选ip可获得极致体验"
  echo ""
  echo ""

  echo 'vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"sing-box-vmess-tls","tls":"tls","type":"none","v":"2"}' | base64 -w 0)
  echo ""
  echo ""
  echo -e "端口 443 可改为 2053 2083 2087 2096 8443"
  echo ""
  echo ""

  echo 'vmess://'$(echo '{"add":"speed.cloudflare.com","aid":"0","host":"'$argo'","id":"'$vmess_uuid'","net":"ws","path":"'$ws_path'","port":"80","ps":"sing-box-vmess","tls":"","type":"none","v":"2"}' | base64 -w 0)
  echo ""
  echo ""
  echo -e "端口 80 可改为 8080 8880 2052 2082 2086 2095"
  echo ""
  echo ""

  show_notice "Clash配置参数"
cat << EOF

port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
ipv6: true

dns:
  enable: true
  listen: :53
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 223.5.5.5
    - 8.8.8.8
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - tls://dns.google
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

proxies:
  - name: VLESS
    type: vless
    server: $server_ip
    port: $current_listen_port
    uuid: $uuid
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: $current_server_name
    client-fingerprint: chrome
    reality-opts:
      public-key: $public_key
      short-id: $short_id

  - name: Hysteria2
    type: hysteria2
    server: $server_ip
    port: $hy_current_listen_port
    password: $hy_password
    sni: $hy_current_server_name
    skip-cert-verify: true
    alpn:
      - h3

proxy-groups:
  - name: 线路选择
    type: select
    proxies:
      - 自动选择
      - VLESS
      - Hysteria2

  - name: 自动选择
    type: url-test
    proxies:
      - VLESS
      - Hysteria2
    url: "https://www.google.cn"
    interval: 300
    tolerance: 50

rules:
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,线路选择

EOF

}

uninstall_singbox() {
    echo "Uninstalling..."
    systemctl stop sing-box
    systemctl disable sing-box > /dev/null 2>&1

    rm /etc/systemd/system/sing-box.service
    rm /root/sbox/sbconfig_server.json
    rm /root/sbox/sing-box
    rm /root/sbox/cloudflared-linux
    rm /root/sbox/argo.txt.b64
    rm /root/sbox/public.key.b64
    rm /root/self-cert/private.key
    rm /root/self-cert/cert.pem
    rm -rf /root/self-cert/
    rm -rf /root/sbox/
    echo "DONE!"
}

install_base

if [ -f "/root/sbox/sbconfig_server.json" ] && \
   [ -f "/root/sbox/sing-box" ] && \
   [ -f "/root/sbox/public.key.b64" ] && \
   [ -f "/root/sbox/argo.txt.b64" ] && \
   [ -f "/etc/systemd/system/sing-box.service" ]; then

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
            systemctl stop sing-box
            systemctl disable sing-box > /dev/null 2>&1
            rm /etc/systemd/system/sing-box.service
            rm /root/sbox/sbconfig_server.json
            rm /root/sbox/sing-box
            rm /root/sbox/cloudflared-linux
            rm /root/sbox/argo.txt.b64
            rm /root/sbox/public.key.b64
            rm /root/self-cert/private.key
            rm /root/self-cert/cert.pem
            rm -rf /root/self-cert/
            rm -rf /root/sbox/
        ;;
        2)
            show_notice "开始修改reality端口和域名"

            current_listen_port=$(jq -r '.inbounds[0].listen_port' /root/sbox/sbconfig_server.json)
            read -p "请输入想要修改的端口号 (当前端口为 $current_listen_port): " listen_port
            listen_port=${listen_port:-$current_listen_port}

            current_server_name=$(jq -r '.inbounds[0].tls.server_name' /root/sbox/sbconfig_server.json)
            read -p "请输入想要使用的h2域名 (当前域名为 $current_server_name): " server_name
            server_name=${server_name:-$current_server_name}

            echo ""
            show_notice "开始修改hysteria2端口"
            echo ""

            hy_current_listen_port=$(jq -r '.inbounds[1].listen_port' /root/sbox/sbconfig_server.json)
            read -p "请输入想要修改的端口 (当前端口为 $hy_current_listen_port): " hy_listen_port
            hy_listen_port=${hy_listen_port:-$hy_current_listen_port}

            jq --arg listen_port "$listen_port" \
               --arg server_name "$server_name" \
               --arg hy_listen_port "$hy_listen_port" \
               '.inbounds[1].listen_port = ($hy_listen_port | tonumber)
                | .inbounds[0].listen_port = ($listen_port | tonumber)
                | .inbounds[0].tls.server_name = $server_name
                | .inbounds[0].tls.reality.handshake.server = $server_name' \
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
                echo "Configuration checked successfully. Starting sing-box service..."
                systemctl daemon-reload
                systemctl enable sing-box > /dev/null 2>&1
                systemctl start sing-box
                systemctl restart sing-box
            fi
            echo ""
            exit 1
        ;;
        6)
            regenarte_cloudflared_argo
            echo "重新启动完成，查看新的vmess客户端信息"
            show_client_configuration
            exit 1
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
echo "自动生成基本参数"
echo ""

key_pair=$(/root/sbox/sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')

echo "$public_key" | base64 > /root/sbox/public.key.b64

uuid=$(/root/sbox/sing-box generate uuid)
short_id=$(/root/sbox/sing-box generate rand --hex 8)

echo "uuid和短id 生成完成"
echo ""

read -p "请输入Reality端口 (默认8888，回车): " listen_port
listen_port=${listen_port:-8888}

read -p "请输入想要使用的域名 (默认itunes.apple.com，回车): " server_name
server_name=${server_name:-itunes.apple.com}

echo ""
echo "开始配置hysteria2"
echo ""

hy_password=$(/root/sbox/sing-box generate rand --hex 8)
read -p "请输入hysteria2监听端口 (默认8443，回车): " hy_listen_port
hy_listen_port=${hy_listen_port:-8443}

read -p "输入自签证书域名 (默认bing.com，回车): " hy_server_name
hy_server_name=${hy_server_name:-bing.com}

mkdir -p /root/self-cert/
openssl ecparam -genkey -name prime256v1 -out /root/self-cert/private.key
openssl req -new -x509 -days 36500 -key /root/self-cert/private.key -out /root/self-cert/cert.pem -subj "/CN
