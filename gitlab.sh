#!/bin/bash

# 版本信息
VERSION="1.0.0"

# 颜色定义 - 保持一致性
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
ORANGE='\033[0;33m'  
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${CYAN}[INFO]${NC} $1" | tee -a /var/log/pve-tools.log
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${ORANGE}[WARN]${NC} $1" | tee -a /var/log/pve-tools.log
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${RED}[ERROR]${NC} $1" | tee -a /var/log/pve-tools.log >&2
}

log_step() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${MAGENTA}[STEP]${NC} $1" | tee -a /var/log/pve-tools.log
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${GREEN}[SUCCESS]${NC} $1" | tee -a /var/log/pve-tools.log
}

log_tips(){
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${MAGENTA}[TIPS]${NC} $1" | tee -a /var/log/pve-tools.log
}

install_gitlab() {
    clear
    local HOSTNAME=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            *)
                echo "未知参数: $1"
                return 1
                ;;
        esac
    done

    if [ -z "$HOSTNAME" ]; then
        HOSTNAME=$(hostname -I | awk '{print $1}')
    fi

    echo "使用 GitLab 主机名: $HOSTNAME"

    sudo mkdir -p /srv/gitlab/{config,logs,data}
    sudo chown -R 1000:1000 /srv/gitlab

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
    local MAX_RETRY=30	    # 定义检查最大次数
    local WAIT_INTERVAL=1   # 每次等待间隔（秒）
    local password_found=false

    echo "等待 Jenkins 初始化并生成初始管理员密码..."
    for i in $(seq 1 $MAX_RETRY); do
        if sudo docker exec gitlab test -f /etc/gitlab/initial_root_password; then
            echo "初始管理员密码已生成"
            sudo docker exec -it gitlab cat /etc/gitlab/initial_root_password
            password_found=true
            break
        else
            echo -ne "正在等待 Jenkins 生成密码... 已等待 $((i * WAIT_INTERVAL)) 秒\r"
            sleep $WAIT_INTERVAL
        fi
    done

    if [ "$password_found" = false ]; then
        echo -e "${RED}❌ 超时：20 秒内未生成 initialAdminPassword${NC}"
        echo -e "${RED}请检查：sudo docker logs jenkins${NC}"
    fi
}

config_docker() {
    enable docker
    start docker
    restart docker
}

linuxmirrors_install_docker() {

    bash <(curl -sSL https://linuxmirrors.cn/docker.sh) \
    --source download.docker.com \
    --source-registry registry.hub.docker.com \
    --protocol https \
    --use-intranet-source false \
    --install-latest true \
    --close-firewall false \
    --ignore-backup-tips

    config_docker

}

install_add_docker() {
	echo -e "${BLUE}正在安装docker环境...${WHITE}"
	if command -v apt &>/dev/null || command -v yum &>/dev/null || command -v dnf &>/dev/null; then
		linuxmirrors_install_docker
	else
		install docker docker-compose
		config_docker

	fi
	sleep 2
}


install_docker() {
	if ! command -v docker &>/dev/null; then
		install_add_docker
	fi
}


# ============================== 主流程 ==============================

main() {
    install_docker
    install_gitlab
}

# 运行主程序
main
