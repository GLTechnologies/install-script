#!/bin/bash

set -e

# ====== 配置参数 ======
# 配置 RTC
Time_threshold=5

# Jenkins
JENKINS_HOME_DIR="/opt/jenkins_home"
JENKINS_IMAGE="jenkins/jenkins:lts"
JENKINS_PORT=8080

# Jenkins 生成管理员密码
MAX_RETRY=30	    # 定义检查最大次数
WAIT_INTERVAL=1   # 每次等待间隔（秒）
password_found=false

# Harbor
while true; do
    read -p "请输入 Harbor 域名或 IP (例如 harbor.example.com 或 192.168.1.1): " HARBOR_DOMAIN

    # 如果为空，不允许
    if [ -z "$HARBOR_DOMAIN" ]; then
        echo "❌ 输入为空，请重新输入。"
        continue
    fi

    # 二次确认
    while true; do
        read -p "你输入的是 [$HARBOR_DOMAIN]，是否确认？(y/n): " yn
        case $yn in
            [Yy] )
                echo "✔ Harbor 域名已确认：$HARBOR_DOMAIN"
                break 2   # 跳出两层循环
                ;;
            [Nn] )
                echo "❗ 请重新输入 Harbor 域名。"
                break     # 仅跳出确认循环，继续重新输入
                ;;
            * )
                echo "⚠ 输入无效，请按 y 或 n。"
                ;;
        esac
    done
done

# ================== 主流程 ==================
main() {
    check_rtc
    install_docker

    sudo apt install -y nano

    install_jenkins
    config_docker

    sudo systemctl restart docker
}
# ================== 函数区 ===================
check_rtc() {
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

install_jenkins() {
    echo "Docker 安装 Jenkins..."
    sudo mkdir -p "$JENKINS_HOME_DIR"
    sudo chown -R 1000:1000 "$JENKINS_HOME_DIR"
    sudo chmod 755 "$JENKINS_HOME_DIR"

    sudo docker stop jenkins >/dev/null 2>&1 || true
    sudo docker rm jenkins >/dev/null 2>&1 || true

    sudo docker run -d \
      --name jenkins \
      --restart unless-stopped \
      -p "$JENKINS_PORT:8080" \
      -p 50000:50000 \
      -u root \
      -v "$JENKINS_HOME_DIR":/var/jenkins_home \
      -v /var/run/docker.sock:/var/run/docker.sock \
      "$JENKINS_IMAGE"
}

config_docker() {
    # ====== Jenkins 访问 Docker 容器 ======
    echo "Jenkins 安装 docker.io"
    sudo docker exec -u 0 -it jenkins apt-get update
    sudo docker exec -u 0 -it jenkins apt-get install -y docker.io

    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "insecure-registries": ["$HARBOR_DOMAIN"]
}
EOF

    # ====== 等待 Jenkins 初始化并生成初始管理员密码 ======
    echo "等待 Jenkins 初始化并生成初始管理员密码..."
    for i in $(seq 1 $MAX_RETRY); do
        if sudo docker exec jenkins test -f /var/jenkins_home/secrets/initialAdminPassword; then
            echo -e "\n初始管理员密码:"
            sudo docker exec -it jenkins cat /var/jenkins_home/secrets/initialAdminPassword
            password_found=true
            break
        else
            echo -ne "正在等待 Jenkins 生成密码... 已等待 $((i * WAIT_INTERVAL)) 秒\r"
            sleep $WAIT_INTERVAL
        fi
    done

    if [ "$password_found" = false ]; then
        echo "❌ 超时：20 秒内未生成 initialAdminPassword"
        echo "请检查：sudo docker logs jenkins"
    fi
}

# ============ 调用主流程 ============
main
