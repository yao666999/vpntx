#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"

# 检查当前用户是否为 root 用户
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 用户身份运行此脚本"
  exit
fi

check_bbr_status() {
  kernel_version=$(uname -r | awk -F "-" '{print $1}')
  echo -e "当前内核版本: ${kernel_version}"
  net_congestion_control=$(cat /proc/sys/net/ipv4/tcp_congestion_control | awk '{print $1}')
  net_qdisc=$(cat /proc/sys/net/core/default_qdisc | awk '{print $1}')
  echo -e "当前拥塞控制算法: ${net_congestion_control}"
  echo -e "当前队列算法: ${net_qdisc}"
  
  if [[ "${net_congestion_control}" == "bbr" && "${net_qdisc}" == "cake" ]]; then
    echo -e "${Info} BBR+CAKE 已启用"
  else
    echo -e "${Error} BBR+CAKE 未启用"
  fi
}

remove_config() {
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.d/99-sysctl.conf
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.d/99-sysctl.conf
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
  sysctl --system
}

startbbrcake() {
  remove_config
  echo "net.core.default_qdisc=cake" >>/etc/sysctl.d/99-sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >>/etc/sysctl.d/99-sysctl.conf
  sysctl --system
  echo -e "${Info}BBR+cake修改成功，重启生效！"
}

check_kernel_headers() {
  if [[ "${OS_type}" == "CentOS" ]]; then
    if [[ $(rpm -qa | grep kernel-headers | wc -l) == 0 ]]; then
      echo -e "${Error} 未安装kernel-headers"
      echo -e "${Info} 开始安装..."
      yum install -y kernel-headers
    else
      echo -e "${Info} 已安装kernel-headers"
    fi
  elif [[ "${OS_type}" == "Debian" ]]; then
    apt-get update
    apt-get install -y linux-headers-$(uname -r)
    echo -e "${Info} 已安装kernel-headers"
  fi
}

check_os_type() {
  if [[ -f /etc/redhat-release ]]; then
    OS_type="CentOS"
  elif cat /etc/issue | grep -q -E -i "debian|ubuntu"; then
    OS_type="Debian"
  else
    echo -e "${Error} 不支持当前系统 !" && exit 1
  fi
}

check_kernel_version() {
  kernel_version=$(uname -r | awk -F "-" '{print $1}')
  echo -e "当前内核版本: ${kernel_version}"
  
  if version_ge ${kernel_version} 4.9; then
    echo -e "${Info} 当前内核版本 >= 4.9，可以使用BBR"
  else
    echo -e "${Error} 当前内核版本 < 4.9，不能使用BBR，请更换内核" && exit 1
  fi
}

version_ge() {
  test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"
}

install_bbr() {
  check_os_type
  check_kernel_version
  check_kernel_headers
  startbbrcake
  
  echo -e "${Info} BBR+CAKE安装完成，请重启系统"
  read -p "是否现在重启系统? [Y/n] :" yn
  [ -z "${yn}" ] && yn="y"
  if [[ $yn == [Yy] ]]; then
    echo -e "${Info} 系统重启中..."
    reboot
  fi
}

main() {
  echo -e "=============================================="
  echo -e "              BBR+CAKE 加速脚本               "
  echo -e "=============================================="
  echo -e " ${Green_font_prefix}1.${Font_color_suffix} 安装 BBR+CAKE"
  echo -e " ${Green_font_prefix}2.${Font_color_suffix} 查看 BBR+CAKE 状态"
  echo -e " ${Green_font_prefix}0.${Font_color_suffix} 退出脚本"
  echo -e "=============================================="
  
  read -p " 请输入数字 [0-2]:" num
  case "$num" in
    1)
      install_bbr
      ;;
    2)
      check_bbr_status
      ;;
    0)
      exit 0
      ;;
    *)
      echo -e "${Error} 请输入正确数字 [0-2]"
      main
      ;;
  esac
}

main
