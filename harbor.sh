#!/bin/bash
set -e

Harbor_VERSION=2.14.1
DOMAIN=$(hostname -I | awk '{print $1}')
HARBOR_ADMIN_PASSWORD=gl123

CERT_DIR=/data/cert
sudo mkdir -p $CERT_DIR

# ================== 主流程 ==================
main() {
   # RTC 时间同步
    check_rtc

    # 安装 Docker
    install_docker

    # 安装证书
    #generate_ssl

    # 安装Harbor
    install_harbor

    echo "访问地址：$DOMAIN"
    echo "用户名：admin"
    echo "密码：$HARBOR_ADMIN_PASSWORD"
}

# ================== 函数区 ===================
check_rtc() {
    echo "==== RTC 时间同步 ===="
    Time_threshold=5
    
    # 获取系统时间戳
    sys_ts=$(date +%s)
    echo "系统时间: ${sys_ts} 秒"

    # 获取 RTC 时间戳
    rtc_ts=$(date -d "$(timedatectl | grep "RTC time" | awk -F': ' '{print $2}')" +%s)
    echo "RTC时间: ${rtc_ts} 秒"

    # 计算差值
    diff=$(( sys_ts - rtc_ts ))
    abs_diff=${diff#-}

    echo "差值: ${abs_diff} 秒"

    # 判断差值是否过大
    if [ "$abs_diff" -gt "$Time_threshold" ]; then
        while true; do
            read -p "时间差过大，是否将系统时间同步为 RTC 时间？(y/n): " yn
            case $yn in
                [Yy] ) 
                    echo "正在同步系统时间..."
                    sudo date -s "@$rtc_ts"
                    echo "同步完成！"
                    break
                    ;;
                [Nn] )
                    echo "已取消同步。"
                    break
                    ;;
                * )
                    echo "输入无效，请输入 y 或 n。"
                    ;;
            esac
        done
    else
        echo "时间差正常。"
    fi
}

# ============ 1. 安装 Docker ============
install_docker() {
    echo "==== 检查 Docker 是否已安装 ===="

    if command -v docker &> /dev/null; then
        echo "Docker 已安装。"
        return
    fi

    echo "Docker 未安装，开始安装..."

    sudo apt update
    sudo apt install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-compose

    sudo systemctl enable docker
    sudo systemctl start docker

    echo "Docker 安装完成。"
}

# ============ 2. 自动生成自签名 SSL ============
generate_ssl() {
    echo ">>> 生成自签名 SSL 证书..."

    sudo openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout $CERT_DIR/harbor.key \
        -out $CERT_DIR/harbor.crt \
        -subj "/C=CN/ST=YourState/L=YourCity/O=YourOrg/CN=$DOMAIN"

    echo "证书路径："
    echo "  $CERT_DIR/harbor.crt"
    echo "  $CERT_DIR/harbor.key"
}

# ============ 3. 下载并配置 Harbor ============
install_harbor() {
    #Harbor官网：https://github.com/goharbor/harbor/releases
    if [ ! -f harbor-online-installer-v$Harbor_VERSION.tgz ]; then
        wget -nc https://github.com/goharbor/harbor/releases/download/v$Harbor_VERSION/harbor-online-installer-v$Harbor_VERSION.tgz
    fi

    tar -zxvf harbor-online-installer-v$Harbor_VERSION.tgz

    pushd harbor
    cp harbor.yml.tmpl harbor.yml
    sed -i "s/^hostname: .*/hostname: $DOMAIN/" harbor.yml
    sed -i "s/^harbor_admin_password: .*/harbor_admin_password: $HARBOR_ADMIN_PASSWORD/" harbor.yml
    sed -i "s/^  password: .*/  password: root123456/" harbor.yml

    # 禁用 HTTPS
    sed -i '/^https:$/,/^[^ ]/ s/^/#/' harbor.yml
    sudo ./install.sh
    popd
}

# ============ 调用主流程 ============
main
