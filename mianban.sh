#!/bin/bash

# 检查是否为root用户
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要root权限运行" 
   exit 1
fi

# 更新系统
apt update && apt upgrade -y

# 安装必要的依赖
apt install -y curl wget unzip

# 下载并安装xray-ui
echo "正在下载 xray-ui 安装脚本..."
curl -Ls https://raw.githubusercontent.com/vaxilu/xray-ui/master/install.sh -o install.sh

# 检查是否成功下载安装脚本
if [ ! -f install.sh ]; then
    echo "错误：安装脚本下载失败！请检查网络或源地址。"
    exit 1
fi

echo "正在执行 xray-ui 安装脚本..."
bash install.sh

# 检查 xray-ui 服务是否安装成功
if ! systemctl is-active --quiet xray-ui;
then
    echo "错误：xray-ui 服务安装或启动失败！"
    exit 1
fi

# 修改面板端口为7006
echo "正在修改面板端口为7006..."
sed -i 's/54321/7006/g' /etc/xray-ui/xray-ui.db

# 重启xray-ui服务以应用端口更改
echo "正在重启 xray-ui 服务..."
systemctl restart xray-ui

# 设置开机自启
echo "正在设置开机自启..."
systemctl enable xray-ui

echo "\n----------------------------------------"
echo "xray-ui 面板安装及配置完成！"
echo "面板地址: http://服务器IP:7006"
echo "默认用户名: admin"
echo "默认密码: admin"
echo "\n请确保您的服务器防火墙和云服务提供商的安全组已开放 TCP 端口 7006。"
echo "首次登录后请立即修改默认密码。"
echo "----------------------------------------"
