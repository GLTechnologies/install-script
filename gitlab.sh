#!/bin/bash

set -e

# ====== 配置参数 ======
HOSTNAME=$(hostname -I | awk '{print $1}')
# =====================

# ====== RTC 时间同步 ======
# ====== 配置 RTC 参数 ======
Time_threshold=5
# =====================

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
# =====================

echo "==== 检查 Docker 是否已安装 ===="
if ! command -v docker &> /dev/null
then
    echo "Docker 未安装，开始安装..."

    # Add Docker's official GPG key:
    echo "Add Docker's official GPG key:"
    sudo apt update
    sudo apt install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo "Add the repository to Apt sources:"
    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update

    # Install the Docker packages:
    echo "Install the Docker packages:"
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # docker自启动
    echo "docker自启动"
    sudo systemctl enable docker
    sudo systemctl start docker

    echo "Docker 安装完成。"
else
    echo "Docker 已安装。"
fi
# =====================

sudo apt install -y nano

# =====================

echo "新建 gitlab 文件"
sudo mkdir -p /srv/gitlab/config
sudo mkdir -p /srv/gitlab/logs
sudo mkdir -p /srv/gitlab/data

#sudo chmod -R 777 /srv/gitlab
sudo chown -R 1000:1000 /srv/gitlab

# 启动 GitLab
echo "Docker 安装 gitlab..."
sudo docker run -d \
  --hostname "$HOSTNAME" \
  --publish 443:443 \
  --publish 80:80 \
  --publish 2222:22 \
  --name gitlab \
  --restart always \
  --volume /srv/gitlab/config:/etc/gitlab \
  --volume /srv/gitlab/logs:/var/log/gitlab \
  --volume /srv/gitlab/data:/var/opt/gitlab \
  gitlab/gitlab-ce:latest

# ====== 等待 gitlab 初始化并生成初始管理员密码 ======

# ====== 配置参数 ======
MAX_RETRY=30	    # 定义检查最大次数
WAIT_INTERVAL=1   # 每次等待间隔（秒）
password_found=false
# =====================

echo "等待 Jenkins 初始化并生成初始管理员密码..."
for i in $(seq 1 $MAX_RETRY); do
    if sudo docker exec gitlab test -f /etc/gitlab/initial_root_password; then
        echo -e "\n初始管理员密码:"
        sudo docker exec -it gitlab cat /etc/gitlab/initial_root_password
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
