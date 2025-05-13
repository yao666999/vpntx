#!/bin/bash
LIGHT_GREEN='\033[1;32m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
ADMIN_PASSWORD="Qaz123456!"
VPN_HUB="DEFAULT"
VPN_USER="pi"
VPN_PASSWORD="8888888888!"
DHCP_START="192.168.30.10"
DHCP_END="192.168.30.20"
DHCP_MASK="255.255.255.0"
DHCP_GW="192.168.30.1"
DHCP_DNS1="192.168.30.1"
DHCP_DNS2="8.8.8.8"
FRP_VERSION="v0.44.0"
FRPS_PORT="7000"
FRPS_UDP_PORT="7001"
FRPS_KCP_PORT="7002"
FRPS_DASHBOARD_PORT="31410"
FRPS_TOKEN="DFRN2vbG123"
FRPS_DASHBOARD_USER="admin"
FRPS_DASHBOARD_PWD="admin"
SILENT_MODE=true

log_info() {
    if [[ "$SILENT_MODE" == "true" ]]; then
        return
    fi
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_step() {
    echo -e "${YELLOW}[$1/$2] $3${NC}"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
    exit 1
}

log_sub_step() {
    if [[ "$SILENT_MODE" == "true" ]]; then
        return
    fi
    echo -e "${GREEN}[$1/$2]$3${NC}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 sudo 或 root 权限运行脚本"
    fi
}

uninstall_monitoring() {
    log_step "1" "6" "卸载系统监控服务..."    
    systemctl stop uniagent.service hostguard.service >/dev/null 2>&1
    systemctl disable uniagent.service hostguard.service >/dev/null 2>&1
    rm -f /etc/systemd/system/uniagent.service
    rm -f /etc/systemd/system/hostguard.service
    systemctl daemon-reexec >/dev/null 2>&1
    systemctl daemon-reload >/dev/null 2>&1
    pkill -9 uniagentd 2>/dev/null || true
    pkill -9 hostguard 2>/dev/null || true
    pkill -9 uniagent 2>/dev/null || true
    rm -rf /usr/local/uniagent
    rm -rf /usr/local/hostguard
    rm -rf /usr/local/uniag
    rm -rf /var/log/uniagent /etc/uniagent /usr/bin/uniagentd
    log_success "监控服务卸载完成"
}

uninstall_frps() {
    log_info "卸载旧版FRPS服务..."
    systemctl stop frps >/dev/null 2>&1
    systemctl disable frps >/dev/null 2>&1
    rm -f /etc/systemd/system/frps.service
    rm -rf /usr/local/frp /etc/frp
    systemctl daemon-reload >/dev/null 2>&1
}

install_dependencies() {
    log_step "2" "6" "安装编译工具和依赖..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || log_error "更新软件源失败"
    apt-get install -y -qq build-essential libreadline-dev zlib1g-dev wget >/dev/null 2>&1 || log_error "安装依赖失败"
    log_success "依赖安装完成"
}

install_softether() {
    log_step "3" "6" "安装SoftEther VPN..."
    if [ -d "/usr/local/vpnserver" ]; then
        /usr/local/vpnserver/vpnserver stop >/dev/null 2>&1
        rm -rf /usr/local/vpnserver
    fi
    cd /usr/local/ || log_error "无法进入/usr/local目录"
    log_info "下载SoftEther VPN..."
    wget https://www.softether-download.com/files/softether/v4.44-9807-rtm-2025.04.16-tree/Linux/SoftEther_VPN_Server/64bit_-_Intel_x64_or_AMD64/softether-vpnserver-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz >/dev/null 2>&1
    log_info "解压并编译SoftEther VPN..."
    tar -zxf softether-vpnserver-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz >/dev/null 2>&1 || log_error "解压SoftEther VPN失败"
    cd vpnserver || log_error "无法进入vpnserver目录"
    make -j$(nproc) >/dev/null 2>&1 || log_error "编译SoftEther VPN失败"
    log_info "启动VPN服务器..."
    /usr/local/vpnserver/vpnserver start >/dev/null 2>&1 || log_error "启动VPN服务器失败"
    sleep 3
    configure_vpn
    create_vpn_service
    log_success "SoftEther VPN安装与配置完成"
}

configure_vpn() {
    local VPNCMD="/usr/local/vpnserver/vpncmd"
    log_sub_step "设置管理密码..."
    ${VPNCMD} localhost /SERVER /CMD ServerPasswordSet ${ADMIN_PASSWORD} >/dev/null 2>&1
    log_sub_step "删除旧的HUB..."
    ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD HubDelete ${VPN_HUB} >/dev/null 2>&1 || true
    log_sub_step "创建新的HUB..."
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD HubCreate ${VPN_HUB} /PASSWORD:${ADMIN_PASSWORD} >/dev/null 2>&1
    log_sub_step "设置加密算法..."
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD ServerCipherSet ECDHE-RSA-AES128-GCM-SHA256 >/dev/null 2>&1
    log_sub_step "启用Secure NAT..."
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD SecureNatEnable >/dev/null 2>&1
    log_sub_step "设置SecureNAT..."
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD DhcpSet \
        /START:${DHCP_START} /END:${DHCP_END} /MASK:${DHCP_MASK} /EXPIRE:2000000 \
        /GW:${DHCP_GW} /DNS:${DHCP_DNS1} /DNS2:${DHCP_DNS2} /DOMAIN:none /LOG:no >/dev/null 2>&1
    log_sub_step "创建用户名..."
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} \
        /CMD UserCreate ${VPN_USER} /GROUP:none /REALNAME:none /NOTE:none >/dev/null 2>&1
    log_sub_step "创建用户密码..."
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} \
        /CMD UserPasswordSet ${VPN_USER} /PASSWORD:${VPN_PASSWORD} >/dev/null 2>&1
    log_sub_step "禁用所有日志..."
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD LogDisable packet >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD LogDisable security >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD LogDisable server >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD LogDisable bridge >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /HUB:${VPN_HUB} /CMD LogDisable connection >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD LogDisable >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD OpenVpnEnable false /PORTS:1194 >/dev/null 2>&1
    { sleep 1; echo; } | ${VPNCMD} localhost /SERVER /PASSWORD:${ADMIN_PASSWORD} /CMD SstpEnable false >/dev/null 2>&1
    rm -rf /usr/local/vpnserver/packet_log /usr/local/vpnserver/security_log /usr/local/vpnserver/server_log 
    mkdir -p /usr/local/vpnserver/packet_log /usr/local/vpnserver/security_log /usr/local/vpnserver/server_log
    chmod 700 /usr/local/vpnserver/packet_log /usr/local/vpnserver/security_log /usr/local/vpnserver/server_log
}

create_vpn_service() {
    log_info "创建VPN服务..."
    cat > /etc/systemd/system/vpn.service <<EOF
[Unit]
Description=SoftEther VPN Server
After=network.target
[Service]
Type=forking
ExecStart=/usr/local/vpnserver/vpnserver start
ExecStop=/usr/local/vpnserver/vpnserver stop
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable --now vpn >/dev/null 2>&1 || log_error "启用VPN服务失败"
}

install_frps() {
    log_step "4" "6" "安装FRPS服务..."
    uninstall_frps
    local FRP_NAME="frp_${FRP_VERSION#v}_linux_amd64"
    local FRP_FILE="${FRP_NAME}.tar.gz"
    cd /usr/local/ || {
        log_error "无法进入/usr/local目录"
        exit 1
    }
    log_info "下载FRPS（版本：${FRP_VERSION}）..."
    if ! wget "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${FRP_FILE}" -O "${FRP_FILE}" >/dev/null 2>&1; then
        log_error "FRPS下载失败，请检查版本号是否正确或网络连接"
        exit 1
    fi
    if ! tar -zxf "${FRP_FILE}" >/dev/null 2>&1; then
        log_error "FRPS解压失败，可能文件损坏或权限不足"
        rm -f "${FRP_FILE}"
        exit 1
    fi
    cd "${FRP_NAME}" || {
        log_error "无法进入解压目录：${FRP_NAME}"
        exit 1
    }
    mkdir -p /usr/local/frp || {
        log_error "无法创建目录：/usr/local/frp"
        exit 1
    }
    if ! cp frps /usr/local/frp/ >/dev/null 2>&1; then
        log_error "frps文件拷贝失败"
        exit 1
    fi
    chmod +x /usr/local/frp/frps
    mkdir -p /etc/frp || {
        log_error "无法创建配置目录：/etc/frp"
        exit 1
    }
    {
        echo "[common]"
        echo "bind_addr = 0.0.0.0"
        echo "bind_port = ${FRPS_PORT}"
        echo "bind_udp_port = ${FRPS_UDP_PORT}"
        echo "kcp_bind_port = ${FRPS_KCP_PORT}"
        echo "dashboard_addr = 0.0.0.0"
        echo "dashboard_port = ${FRPS_DASHBOARD_PORT}"
        echo "authentication_method = token"
        echo "token = ${FRPS_TOKEN}"
        echo "dashboard_user = ${FRPS_DASHBOARD_USER}"
        echo "dashboard_pwd = ${FRPS_DASHBOARD_PWD}"
        echo "log_level = silent"
        echo "disable_log_color = true"
    } > /etc/frp/frps.toml || {
        log_error "配置文件生成失败"
        exit 1
    }
    {
        echo "[Unit]"
        echo "Description=FRP Server"
        echo "After=network.target"
        echo "[Service]"
        echo "Type=simple"
        echo "ExecStart=/usr/local/frp/frps -c /etc/frp/frps.toml"
        echo "Restart=on-failure"
        echo "LimitNOFILE=1048576"
        echo "[Install]"
        echo "WantedBy=multi-user.target"
    } > /etc/systemd/system/frps.service || {
        log_error "服务文件生成失败"
        exit 1
    }
    if ! systemctl daemon-reload >/dev/null 2>&1; then
        log_error "服务重载失败"
        exit 1
    fi
    if ! systemctl enable --now frps >/dev/null 2>&1; then
        log_error "FRPS服务启动失败，请检查配置"
        systemctl status frps
        exit 1
    fi
    log_success "FRPS ${FRP_VERSION} 安装成功"
}

install_bbr() {
    log_step "5" "6" "安装并启动BBR+CAKE加速模块..."
    cd /usr/local/ || log_error "无法进入/usr/local目录"
    wget --no-check-certificate -q -O bbr.sh https://raw.githubusercontent.com/yao666999/vpntx/main/bbr.sh >/dev/null 2>&1 || log_error "下载BBR脚本失败"
    chmod +x bbr.sh
    echo -e "1\n" | bash bbr.sh >/dev/null 2>&1
    sleep 2
    echo -e "2\n" | bash bbr.sh >/dev/null 2>&1
    log_success "BBR+CAKE加速已安装并启动"
}

cleanup() {
    log_step "6" "6" "清理临时缓存文件..."
    rm -rf /usr/local/frp_* /usr/local/softether-vpnserver-v4* /usr/local/frp_*_linux_amd64
    rm -rf /usr/local/vpnserver/packet_log /usr/local/vpnserver/security_log /usr/local/vpnserver/server_log
    log_success "临时文件清理完成"
}

show_results() {
    echo -e "\n${YELLOW}>>> SoftEtherVPN & FRPS服务状态：${NC}"
    systemctl is-active vpn
    systemctl is-active frps
    echo -e "\n${YELLOW}>>> BBR加速状态：${NC}"
    sysctl net.ipv4.tcp_congestion_control | awk '{print $3}'
    echo -e "\n${YELLOW}>>> VPN信息：${NC}"
    echo -e "服务器地址: $(curl -s ifconfig.me || hostname -I | awk '{print $1}')"
    echo -e "VPN 服务密码: ${ADMIN_PASSWORD}"
    echo -e "VPN 用户名: ${VPN_USER}"
    echo -e "VPN 密码: ${VPN_PASSWORD}"
    echo -e "FRPS 密码: ${FRPS_TOKEN}"
}

main() {
    check_root
    uninstall_monitoring
    install_dependencies
    install_softether
    install_frps
    install_bbr
    cleanup
    show_results
}

# 调用main函数
main
