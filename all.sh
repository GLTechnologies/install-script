#!/bin/bash

# gitlab 配置工具脚本
# 支持换源、删除订阅弹窗、硬盘管理等功能
# 适用于 Proxmox VE 9.0 (基于 Debian 13)
# Auther:Maple 二次修改使用请不要删除此段注释

# 版本信息
CURRENT_VERSION="1.0.0"
VERSION_FILE_URL="https://raw.githubusercontent.com/GLTechnologies/install-script/main/VERSION"
UPDATE_FILE_URL="https://raw.githubusercontent.com/GLTechnologies/install-script/main/UPDATE"

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

# UI 界面一致性常量
UI_BORDER="═════════════════════════════════════════════════"
UI_DIVIDER="═════════════════════════════════════════════════"
UI_FOOTER="═════════════════════════════════════════════════"
UI_HEADER="═════════════════════════════════════════════════"
UI_FOOTER_SHORT="═════════════════════════════════════════════════"

# 自动更新网络检测配置
CF_TRACE_URL="https://www.cloudflare.com/cdn-cgi/trace"
GITHUB_MIRROR_PREFIX="https://ghfast.top/"
USE_MIRROR_FOR_UPDATE=0
USER_COUNTRY_CODE=""

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

# 显示横幅
show_banner() {
    clear
    cat << 'EOF'
 ███████╗ ██╗         ████████╗ ██████╗  ██████╗ ██╗     ███████╗
██╔═════╝ ██║         ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝
██║  ███╗ ██║            ██║   ██║   ██║██║   ██║██║     ███████╗
██║  ╚██║ ██║            ██║   ██║   ██║██║   ██║██║     ╚════██║
╚██████╔╝ ███████╗       ██║   ╚██████╔╝╚██████╔╝███████╗███████║
 ╚═════╝  ╚══════╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝
EOF
}

show_banner_description() {
    echo "═════════════════════════════════════════════════"
    echo "gitlab 一键脚本"
    echo "让每个人都能体验虚拟化技术的的便利。"
    echo "作者: XGL & 提交PR的你们"
    echo "当前版本: $CURRENT_VERSION | 最新版本: $remote_version"
    echo "═════════════════════════════════════════════════"
    echo
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "需要超级管理员权限才能运行哦"
        echo "请使用以下命令重新运行："
        echo "sudo bash $0"
        exit 1
    fi
}

# 检查调试模式
check_debug_mode() {
    for arg in "$@"; do
        if [[ "$arg" == "--debug" ]]; then
            log_warn "警告：您正在使用调试模式！"
            log_warn "此模式将跳过 PVE 系统版本检测"
            log_warn "仅在开发和测试环境中使用"
            log_warn "在非 PVE (Debian 系) 系统上使用可能导致系统损坏"
            echo "您确定要继续吗？输入 'yes' 确认，其他任意键退出: "
            read -r confirm
            if [[ "$confirm" != "yes" ]]; then
                log_info "已取消操作，退出脚本"
                exit 0
            fi
            DEBUG_MODE=true
            log_success "已启用调试模式"
            return
        fi
    done
    DEBUG_MODE=false
}

# 检查 PVE 版本
check_pve_version() {
    # 如果在调试模式下，跳过 PVE 版本检测
    if [[ "$DEBUG_MODE" == "true" ]]; then
        log_warn "调试模式：跳过 PVE 版本检测"
        log_tips "请注意：您正在非 PVE 系统上运行此脚本，某些功能可能无法正常工作"
        return
    fi
    
    if ! command -v pveversion &> /dev/null; then
        log_error "咦？这里好像不是 PVE 环境呢"
        log_warn "请在 Proxmox VE 系统上运行此脚本"
        exit 1
    fi
    
    local pve_version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    log_info "太好了！检测到 PVE 版本: $pve_version"
}

# 检测当前系统版本
check_system_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        #echo "PRETTY_NAME: $PRETTY_NAME"

        if [ "$ID" != "ubuntu" ]; then
            echo "当前系统是 $ID"
            exit 1
        fi
    else
        echo "/etc/os-release 文件不存在"
    fi
}

# 标准化暂停函数
pause_function() {
    echo -n "按任意键继续... "
    read -n 1 -s input
    if [[ -n ${input} ]]; then
        echo -e "\b"
    fi
}

show_menu_footer() {
    echo "${UI_FOOTER}"
}

# 通过 Cloudflare Trace 检测地区，决定是否启用镜像源
detect_network_region() {
    local timeout=5
    USER_COUNTRY_CODE=""
    USE_MIRROR_FOR_UPDATE=0

    if ! command -v curl &> /dev/null; then
        return 1
    fi

    local trace_output
    trace_output=$(curl -s --connect-timeout $timeout --max-time $timeout "$CF_TRACE_URL" 2>/dev/null)
    if [[ -z "$trace_output" ]]; then
        return 1
    fi

    local loc
    loc=$(echo "$trace_output" | awk -F= '/^loc=/{print $2}' | tr -d '\r')
    if [[ -z "$loc" ]]; then
        return 1
    fi

    USER_COUNTRY_CODE="$loc"
    if [[ "$USER_COUNTRY_CODE" == "CN" ]]; then
        USE_MIRROR_FOR_UPDATE=1
    fi

    return 0
}

check_update() {
    log_info "正在检查更新..."

    download_file() {
        local url="$1"
        local timeout=10
        
        if command -v curl &> /dev/null; then
            curl -s --connect-timeout $timeout --max-time $timeout "$url" 2>/dev/null
        elif command -v wget &> /dev/null; then
            wget -q -T $timeout -O - "$url" 2>/dev/null
        else
            echo ""
        fi
    }

    # 显示进度提示
    echo -ne "[....] 正在检查更新...\033[0K\r"

    local prefer_mirror=0
    local preferred_version_url="$VERSION_FILE_URL"
    local preferred_update_url="$UPDATE_FILE_URL"
    local mirror_version_url="${GITHUB_MIRROR_PREFIX}${VERSION_FILE_URL}"
    local mirror_update_url="${GITHUB_MIRROR_PREFIX}${UPDATE_FILE_URL}"

    if detect_network_region; then
        prefer_mirror=$USE_MIRROR_FOR_UPDATE
        if [[ $prefer_mirror -eq 1 ]]; then
            log_info "当前地区为： $USER_COUNTRY_CODE，使用镜像源检查更新...请等待 3 秒"
            # log_info "检测到中国大陆网络环境，将优先使用镜像源检查更新"
            preferred_version_url="$mirror_version_url"
            preferred_update_url="$mirror_update_url"
        else
            if [[ -n "$USER_COUNTRY_CODE" ]]; then
                log_info "检测到当前地区为: $USER_COUNTRY_CODE，将使用 GitHub 源检查更新"
            fi
        fi
    else
        log_warn "无法获取网络地区信息，默认使用 GitHub 源检查更新"
    fi
    
    remote_content=$(download_file "$preferred_version_url")

    if [ -z "$remote_content" ]; then
        if [[ $prefer_mirror -eq 1 ]]; then
            log_warn "镜像源连接失败，尝试使用 GitHub 源..."
            remote_content=$(download_file "$VERSION_FILE_URL")
        else
            log_warn "GitHub 连接失败，尝试使用镜像源..."
            remote_content=$(download_file "$mirror_version_url")
        fi
    fi

    # 清除进度显示
    echo -ne "\033[0K\r"

    # 如果下载失败
    if [ -z "$remote_content" ]; then
        log_warn "网络连接失败，跳过版本检查"
        echo "提示：您可以手动访问以下地址检查更新："
        echo "https://github.com/GLTechnologies/install-script"
        echo "按回车键继续..."
        read -r
        return
    fi

    # 提取版本号和更新日志
    remote_version=$(echo "$remote_content" | head -1 | tr -d '[:space:]')
    version_changelog=$(echo "$remote_content" | tail -n +2)

    if [ -z "$remote_version" ]; then
        log_warn "获取的版本信息格式不正确"
        return
    fi

    detailed_changelog=$(download_file "$preferred_update_url")

    if [ -z "$detailed_changelog" ]; then
        if [[ $prefer_mirror -eq 1 ]]; then
            log_warn "镜像源更新日志获取失败，尝试使用 GitHub 源..."
            detailed_changelog=$(download_file "$UPDATE_FILE_URL")
        else
            log_warn "GitHub 更新日志获取失败，尝试使用镜像源..."
            detailed_changelog=$(download_file "$mirror_update_url")
        fi
    fi

    # 比较版本
    if [ "$(printf '%s\n' "$remote_version" "$CURRENT_VERSION" | sort -V | tail -n1)" != "$CURRENT_VERSION" ]; then
        echo "----------------------------------------------"
        echo "发现新版本！推荐更新哦，新增功能和修复BUG喵"
        echo "当前版本: $CURRENT_VERSION"
        echo "最新版本: $remote_version"
        echo "更新内容："
        
        # 如果获取到了详细的更新日志，则显示详细内容，否则显示从VERSION文件中获取的内容
        if [ -n "$detailed_changelog" ]; then
            echo "$detailed_changelog"
        else
            # 格式化显示版本文件中的更新内容
            if [ -n "$version_changelog" ] && [ "$version_changelog" != "$remote_version" ]; then
                echo "$version_changelog"
            else
                echo "  - 请查看项目页面获取详细更新内容"
            fi
        fi
        
        echo "----------------------------------------------"
        echo "请访问项目页面获取最新版本："
        echo "https://github.com/GLTechnologies/install-script"
        echo "按回车键继续..."
        read -r
    else
        log_success "当前已是最新版本 ($CURRENT_VERSION) 放心用吧"
    fi
}

execute() {
    log_step "执行命令: $*"
    command "$@"
    ret=$?
    if [ $ret -ne 0 ]; then
        log_error "命令失败 (exit=$ret): $*"
        return $ret
    fi
    log_success "命令执行成功"
    return 0
}

is_valid_ipv4() {
    local ip=$1
    local IFS=.
    local -a octets

    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    read -ra octets <<< "$ip"
    for o in "${octets[@]}"; do
        ((o >= 0 && o <= 255)) || return 1
    done

    return 0
}

syncRTC() {
    Time_threshold=5

    clear

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
    clear
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
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # docker自启动
    sudo systemctl enable docker
    sudo systemctl start docker
}

# shellcheck disable=SC2120
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

install_jenkins() {
    clear

}

bar() {
    local percent=$1
    local width=20

    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))

    # 颜色判断
    if [ "$percent" -ge 80 ]; then
        color=${RED}    # 红
    elif [ "$percent" -ge 60 ]; then
        color=${YELLOW} # 黄
    else
        color=${GREEN}  # 绿
    fi
    reset=${NC}

    printf "["
    printf "${color}"
    printf "%0.s█" $(seq 1 $filled)
    printf "${reset}"
    printf "%0.s-" $(seq 1 $empty)
    printf "] %3d%%" "$percent"
}

# ============================== 主菜单 ==============================
options=(
    "监控面板"
    "更换软件源"
    "管理 Docker 容器"
    "管理 Gitlab"
    "管理 Jenkins"
    "退出"
)
actions=(
    "monitor_panel"
    "update_source"
    "docker_manage"
    "gitlab_manage"
    "jenkins_manage"
    "exit"
)
selected=0

monitor_panel() {
    clear
    echo "正在加载中，请稍后..."
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        HAS_DOCKER=1
    else
        HAS_DOCKER=0
    fi

    iface=$(ip route | awk '/default/ {print $5; exit}')
    [ -z "$iface" ] && iface=lo

    rx_prev=$(cat /sys/class/net/$iface/statistics/rx_bytes)
    tx_prev=$(cat /sys/class/net/$iface/statistics/tx_bytes)

    #printf "\033[?25l"          # 隐藏光标
    #trap 'printf "\033[?25h"' EXIT

    while true; do
        printf "\033[H"         # 不闪屏刷新
        read -rsn1 -t 1 && break

        now=$(date "+%Y-%m-%d %H:%M:%S")

        # ===== HOST CPU =====
        cpu_idle=$(top -bn1 | awk -F',' '/Cpu/ {print $4}' | awk '{print $1}')
        cpu_used=$(awk -v idle="$cpu_idle" 'BEGIN {printf "%.1f", 100 - idle}')

        # ===== HOST MEM =====
        mem_total=$(free -h | awk '/Mem:/ {print $2}')
        mem_used=$(free -h | awk '/Mem:/ {print $3}')
        mem_avail=$(free -h | awk '/Mem:/ {print $7}')
        mem_pct=$(free | awk '/Mem/ {printf "%.1f", $3/$2*100}')

        # ===== HOST DISK =====
        disk=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')

        # ===== HOST LOAD =====
        load=$(uptime | awk -F'load average:' '{print $2}')

        # ===== HOST NETWORK =====
        rx_now=$(cat /sys/class/net/$iface/statistics/rx_bytes)
        tx_now=$(cat /sys/class/net/$iface/statistics/tx_bytes)
        rx_rate=$(( (rx_now - rx_prev) / 1024 ))
        tx_rate=$(( (tx_now - tx_prev) / 1024 ))
        rx_prev=$rx_now
        tx_prev=$tx_now

        # ===== HOST HEADER =====
        # 百分比转整数
        cpu_i=${cpu_used%.*}
        mem_i=${mem_pct%.*}
        cat <<EOF
================ HOST PANEL =================
Time: $now
EOF

printf "CPU Usage : "
bar "$cpu_i"
echo

printf "Memory    : "
bar "$mem_i"
printf "  (%s / %s, Avail: %s)\n" "$mem_used" "$mem_total" "$mem_avail"

cat <<EOF
Disk (/ ) : $disk
Load Avg  : $load
Network   : RX ${rx_rate} KB/s | TX ${tx_rate} KB/s
EOF

        # ===== DOCKER PANEL（有 Docker 才显示）=====
        if [ "$HAS_DOCKER" -eq 1 ]; then
            echo
            echo "[DOCKER CONTAINERS]"
            printf "%-18s %-8s %-25s %-8s\n" \
                "NAME" "CPU%" "MEM USAGE / LIMIT" "MEM%"

            docker stats --no-stream --format \
              "{{.Name}} {{.CPUPerc}} {{.MemUsage}} {{.MemPerc}}" |
            while read -r name cpu mem mempct; do
                printf "%-18s %-8s %-25s %-8s\n" \
                    "$name" "$cpu" "$mem" "$mempct"
            done
        fi

        echo
        echo "============================================"
        echo "Press ENTER to quit"
    done
}

update_source() {
    echo "1"
}

docker_manage() {
    while true; do
        clear
        echo "==== 检查 Docker Engine 状态 ===="

        if command -v dockerd >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^docker\.service'; then

            if systemctl is-active --quiet docker; then
                echo -e "${CYAN}Docker Engine 已安装，且正在运行${NC}"
            else
                echo -e "${CYAN}Docker Engine 已安装，但未运行${NC}"
            fi
            break
        else
            read -rsn1 -p "Docker 未安装，是否安装？(y/n): " yn
            case "$yn" in
                y|Y)
                    echo
                    echo "开始安装 Docker..."
                    install_docker
                    ;;
                n|N)
                    echo "已取消安装"
                    return
                    ;;
                *)
                    echo "请输入 y 或 n"
                    ;;
            esac
        fi
    done

    docker_menu_loop
}

gitlab_manage() {
    clear
    if ! command -v dockerd >/dev/null 2>&1 || ! systemctl list-unit-files | grep -q '^docker\.service'; then
        echo -e "${RED}当前未安装 Docker，请前往安装后重试！${NC}"
        read -rsn1 -p "按任意键继续..."
        return
    fi

    while true; do
        clear
        if command docker inspect gitlab >/dev/null 2>&1; then
            echo "GitLab 已安装"
            break
        else
            read -rsn1 -p "GitLab 未安装，是否安装？(y/n): " yn
            case "$yn" in
                y|Y)
                    echo
                    echo "开始安装 GitLab..."
                    local default_ip
                    default_ip=$(hostname -I | awk '{print $1}')

                    read -rp "请输入 GitLab 域名/IP（回车默认本机 IP:$default_ip）: " input
                    while true; do
                        if [ -n "$input" ]; then
                            # 自定义域名/IP
                            read -rsn1 -p "当前 Gitlab 域名/IP [$input]，是否继续？(y/n): " yn
                            case "$yn" in
                                y|Y)
                                    install_gitlab --hostname "$input"
                                    echo -e "Gitlab网址: ${CYAN}$input${NC}"
                                    read -rsn1 -p "按任意键继续..."
                                    break
                                    ;;
                                n|N)
                                    echo "已取消安装"
                                    break
                                    ;;
                                *)
                                    echo
                                    echo "请输入 y 或 n"
                                    ;;
                            esac
                        else
                            # 默认使用本机 IP
                            echo -e "使用本机 IP:$default_ip"
                            install_gitlab
                            echo -e "Gitlab网址: ${CYAN}$default_ip${NC}"
                            read -rsn1 -p "按任意键继续..."
                            break
                        fi
                    done
                    ;;
                n|N)
                    echo "已取消安装"
                    return
                    ;;
                *)
                    echo "请输入 y 或 n"
                    ;;
            esac
        fi
    done

    gitlab_menu_loop
}

jenkins_manage() {
    clear
    if ! command -v dockerd >/dev/null 2>&1 || ! systemctl list-unit-files | grep -q '^docker\.service'; then
        echo -e "${RED}当前未安装 Docker，请前往安装后重试！${NC}"
        read -rsn1 -p "按任意键继续..."
        return
    fi

    while true; do
        clear
        if command docker inspect jenkins >/dev/null 2>&1; then
            echo "Jenkins 已安装"
            break
        else
            read -rsn1 -p "Jenkins 未安装，是否安装？(y/n): " yn
            case "$yn" in
                y|Y)
                    echo
                    echo "开始安装 Jenkins..."
                    install_jenkins
                    ;;
                n|N)
                    echo "已取消安装"
                    return
                    ;;
                *)
                    echo "请输入 y 或 n"
                    ;;
            esac
        fi
    done
}

gitlab() {
    echo "gitlab"
}

main_menu() {
    # 隐藏光标
    printf "\033[?25l"
    #保存光标位置
    printf "\033[s"
    #回到菜单起始处(第13行)
    printf "\033[13;1H"

    echo "请选择您需要的功能:"
    for i in "${!options[@]}"; do
        if [ "$i" -eq "$selected" ]; then
            printf "${CYAN}> %s${NC}\n" "${options[$i]}"
        else
            printf "  %s\n" "${options[$i]}"
        fi
    done
    show_menu_footer
    echo "使用 ↑↓ 选择，Enter 确认"

    # 恢复光标位置
    printf "\033[u"
}

main_menu_loop() {
   show_banner
   show_banner_description
    main_menu
    while true; do
        read -rsn1 key

        if [ "$key" = $'\x1b' ]; then
            read -rsn2 key
            case "$key" in
                "[A") selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} )) ;;
                "[B") selected=$(( (selected + 1) % ${#options[@]} )) ;;
                "[D")
                    ;;
                "[C")
                    # 判断是否为退出选项
                    if [[ "${actions[$selected]}" == "exit" ]]; then
                        printf "\033[?25h"   # 恢复光标
                        clear
                        echo -e "${GREEN}已退出脚本.${NC}"
                        exit 0
                    fi
                    "${actions[$selected]}"
                    show_banner
                    show_banner_description
                    main_menu
                    ;;
            esac
            main_menu
        elif [ "$key" = "" ]; then
            # 判断是否为退出选项
            if [[ "${actions[$selected]}" == "exit" ]]; then
                printf "\033[?25h"   # 恢复光标
                clear
                echo -e "${GREEN}已退出脚本.${NC}"
                exit 0
            fi
            "${actions[$selected]}"
            show_banner
            show_banner_description
            main_menu
        fi
    done 
}

# ============================== docker 菜单 ==============================
docker_options=(
    "查看所有容器"
    "启动容器"
    "停止容器"
    "删除容器"
    "返回主菜单"
)
docker_actions=(
    "container_list"
    "container_start"
    "container_stop"
    "container_remove"
    "return_main"
)
docker_selected=0

container_list() {
    clear
    execute docker ps
    read -rsn1 -p "按任意键继续..."

    docker_menu_loop
}

container_start() {
    docker_container_start_menu_loop
}

container_stop() {
    docker_container_stop_menu_loop
}

container_remove() {
    docker_container_remove_menu_loop
}

docker_menu() {
    # 隐藏光标
    printf "\033[?25l"
    #保存光标位置
    printf "\033[s"
    #回到菜单起始处(第13行)
    printf "\033[8;1H"

    echo "Docker容器管理:"
    for i in "${!docker_options[@]}"; do
        if [ "$i" -eq "$docker_selected" ]; then
            printf "${CYAN}> %s${NC}\n" "${docker_options[$i]}"
        else
            printf "  %s\n" "${docker_options[$i]}"
        fi
    done
    show_menu_footer
    echo "使用 ↑↓ 选择，Enter 确认"

    # 恢复光标位置
    printf "\033[u"
}

docker_menu_loop() {
    show_banner
    echo "${UI_DIVIDER}"
    docker_menu
    while true; do
        read -rsn1 key

        if [ "$key" = $'\x1b' ]; then
            read -rsn2 key
            case "$key" in
                "[A") docker_selected=$(( (docker_selected - 1 + ${#docker_options[@]}) % ${#docker_options[@]} )) ;;
                "[B") docker_selected=$(( (docker_selected + 1) % ${#docker_options[@]} )) ;;
                "[D")
                    main_menu_loop
                    ;;
                "[C")
                    case "${docker_actions[$docker_selected]}" in
                        "return_main")
                            main_menu_loop
                            ;;
                        *)
                            ${docker_actions[$docker_selected]}
                            ;;
                    esac
                    ;;
            esac
            docker_menu
        elif [ "$key" = "" ]; then
            case "${docker_actions[$docker_selected]}" in
                "return_main")
                    main_menu_loop
                    ;;
                *)
                    ${docker_actions[$docker_selected]}
                    ;;
            esac
        fi
    done
}

# ============================== docker 菜单（启动容器） ==============================
docker_container_start_options=()
docker_container_start_selected=0

load_docker_stopped_containers() {
    mapfile -t docker_container_start_options < <(
        docker ps -a -f status=exited --format "{{.Names}}"
    )

    if [ ${#docker_container_start_options[@]} -eq 0 ]; then
        docker_container_start_options=("（暂无可启动的容器）")
    fi

    docker_container_start_selected=0
}

docker_container_start_menu() {
    printf "\033[?25l"
    printf "\033[s"
    printf "\033[8;1H"

    echo "请选择要启动的 Docker 容器: "
    for i in "${!docker_container_start_options[@]}"; do
        if [ "$i" -eq "$docker_container_start_selected" ]; then
            printf "${CYAN}> %s${NC}\n" "${docker_container_start_options[$i]}"
        else
            printf "  %s\n" "${docker_container_start_options[$i]}"
        fi
    done
    show_menu_footer
    echo "Enter 启动容器 | ← 返回"

    printf "\033[u"
}

docker_container_start_menu_loop() {
    load_docker_stopped_containers
    show_banner
    echo "${UI_DIVIDER}"
    docker_container_start_menu

    while true; do
        read -rsn1 key

        if [ "$key" = $'\x1b' ]; then
            read -rsn2 key
            case "$key" in
                "[A") docker_container_start_selected=$(( (docker_container_start_selected - 1 + ${#docker_container_start_options[@]}) % ${#docker_container_start_options[@]} )) ;;
                "[B") docker_container_start_selected=$(( (docker_container_start_selected + 1) % ${#docker_container_start_options[@]} )) ;;
                "[D")
                    docker_menu_loop
                    ;;
                "[C")
                    ;;
            esac
            docker_container_start_menu
        elif [ "$key" = "" ]; then
            local container="${docker_container_start_options[$docker_container_start_selected]}"
            if [[ "$container" != "（暂无可启动的容器）" ]]; then
                clear
                execute docker start "$container"

                load_docker_stopped_containers

                show_banner
                echo "${UI_DIVIDER}"
                docker_container_start_menu
            fi
        fi
    done
}

# ============================== docker 菜单（停止容器） ==============================
docker_container_stop_options=()
docker_container_stop_selected=0
load_docker_running_containers() {
    mapfile -t docker_container_stop_options < <(docker ps --format "{{.Names}}")

    if [ ${#docker_container_stop_options[@]} -eq 0 ]; then
        docker_container_stop_options=("（暂无运行中的容器）")
    fi

    docker_container_stop_selected=0
}

docker_container_stop_menu() {
    # 隐藏光标
    printf "\033[?25l"
    #保存光标位置
    printf "\033[s"
    #回到菜单起始处(第13行)
    printf "\033[8;1H"

    echo "请选择要停止的 Docker 容器: "
    for i in "${!docker_container_stop_options[@]}"; do
        if [ "$i" -eq "$docker_container_stop_selected" ]; then
            printf "${CYAN}> %s${NC}\n" "${docker_container_stop_options[$i]}"
        else
            printf "  %s\n" "${docker_container_stop_options[$i]}"
        fi
    done
    show_menu_footer
    echo "Enter 停止容器 | ← 返回"

    # 恢复光标位置
    printf "\033[u"
}

docker_container_stop_menu_loop() {
    load_docker_running_containers
    show_banner
    echo "${UI_DIVIDER}"
    docker_container_stop_menu

    while true; do
        read -rsn1 key

        if [ "$key" = $'\x1b' ]; then
            read -rsn2 key
            case "$key" in
                "[A") docker_container_stop_selected=$(( (docker_container_stop_selected - 1 + ${#docker_container_stop_options[@]}) % ${#docker_container_stop_options[@]} )) ;;
                "[B") docker_container_stop_selected=$(( (docker_container_stop_selected + 1) % ${#docker_container_stop_options[@]} )) ;;
                "[D")
                    docker_menu_loop
                    ;;
                "[C")
                    ;;
            esac
            docker_container_stop_menu
        elif [ "$key" = "" ]; then
            local container="${docker_container_stop_options[$docker_container_stop_selected]}"
            if [[ "$container" != "（暂无运行中的容器）" ]]; then
                clear
                execute docker stop "$container"

                load_docker_running_containers

                show_banner
                echo "${UI_DIVIDER}"
                docker_container_stop_menu
            fi
        fi
    done
}

# ============================== docker 菜单（删除容器） ==============================
docker_container_remove_options=()
docker_container_remove_selected=0

load_docker_all_containers() {
    mapfile -t docker_container_remove_options < <(
        docker ps -a --format "{{.Names}}"
    )

    if [ ${#docker_container_remove_options[@]} -eq 0 ]; then
        docker_container_remove_options=("（暂无可删除的容器）")
    fi

    docker_container_remove_selected=0
}

docker_container_remove_menu() {
    printf "\033[?25l"
    printf "\033[s"
    printf "\033[8;1H"

    echo "请选择要删除的 Docker 容器: "
    for i in "${!docker_container_remove_options[@]}"; do
        if [ "$i" -eq "$docker_container_remove_selected" ]; then
            printf "${CYAN}> %s${NC}\n" "${docker_container_remove_options[$i]}"
        else
            printf "  %s\n" "${docker_container_remove_options[$i]}"
        fi
    done
    show_menu_footer
    echo "Enter 删除容器 | ← 返回"

    printf "\033[u"
}

docker_container_remove_menu_loop() {
    load_docker_all_containers
    show_banner
    echo "${UI_DIVIDER}"
    docker_container_remove_menu

    while true; do
        read -rsn1 key

        if [ "$key" = $'\x1b' ]; then
            read -rsn2 key
            case "$key" in
                "[A") docker_container_remove_selected=$(( (docker_container_remove_selected - 1 + ${#docker_container_remove_options[@]}) % ${#docker_container_remove_options[@]} )) ;;
                "[B") docker_container_remove_selected=$(( (docker_container_remove_selected + 1) % ${#docker_container_remove_options[@]} )) ;;
                "[D")
                    docker_menu_loop
                    ;;
                "[C")
                    ;;
            esac
            docker_container_remove_menu
        elif [ "$key" = "" ]; then
            local container="${docker_container_remove_options[$docker_container_remove_selected]}"
            if [[ "$container" != "（暂无可删除的容器）" ]]; then
                clear
                execute docker rm -f "$container"

                load_docker_all_containers

                show_banner
                echo "${UI_DIVIDER}"
                docker_container_remove_menu
            fi
        fi
    done
}

# ============================== gitlab 菜单 ==============================
gitlab_options=(
    "启动 GitLab"
    "停止 GitLab"
    "查看 GitLab 状态"
    "查看访问地址 / 初始密码"
    "备份 GitLab"
    "还原 GitLab"
    "卸载 GitLab"
    "返回主菜单"
)
gitlab_actions=(
    "gitlab_start"
    "gitlab_stop"
    "gitlab_status"
    "gitlab_address_pwd"
    "gitlab_backup"
    "gitlab_restore"
    "gitlab_uninstall"
    "return_main"
)
gitlab_selected=0

gitlab_start() {
    clear
    execute docker start gitlab
    read -rsn1 -p "按任意键继续..."

    clear
    show_banner
    echo "${UI_DIVIDER}"
    gitlab_menu
}

gitlab_stop() {
    clear
    execute docker stop gitlab
    read -rsn1 -p "按任意键继续..."

    clear
    show_banner
    echo "${UI_DIVIDER}"
    gitlab_menu
}

gitlab_status() {
    clear
    echo "========== GitLab 状态 =========="
    echo

    # 检查容器是否存在
    if ! docker inspect gitlab >/dev/null 2>&1; then
        echo -e "${RED}❌ GitLab 容器未安装${NC}"
        read -rsn1 -p "按任意键返回..."
        clear
        show_banner
        echo "${UI_DIVIDER}"
        gitlab_menu
        return
    fi

    # 容器运行状态
    status=$(docker inspect --format '{{.State.Status}}' gitlab)
    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' gitlab)

    echo -e "📦 容器名称: ${CYAN}gitlab${NC}"
    echo -e "▶ 运行状态: ${CYAN}$status${NC}"
    echo -e "❤ 健康状态: ${CYAN}$health${NC}"
    echo

    # 如果在运行，查看 GitLab 内部服务
    if [ "$status" = "running" ]; then
        echo "🔧 GitLab 内部服务状态："
        docker exec gitlab gitlab-ctl status
        #watch -n 1 docker exec gitlab gitlab-ctl status
    else
        echo -e "${YELLOW}⚠ GitLab 容器未运行，无法查看内部服务状态${NC}"
    fi

    echo
    read -rsn1 -p "按任意键继续..."

    clear
    show_banner
    echo "${UI_DIVIDER}"
    gitlab_menu
}

gitlab_address_pwd() {
    clear

    # 查找 GitLab 容器
    container=$(docker ps --format "{{.Names}}" | grep -i gitlab | head -n 1)

    if [ -z "$container" ]; then
        echo "❌ 未找到正在运行的 GitLab 容器"
        read -rsn1 -p "按任意键返回..."

        clear
        show_banner
        echo "${UI_DIVIDER}"
        gitlab_menu
        return
    fi

    echo "📦 GitLab 容器: $container"
    echo ""

    # 访问地址
    url=$(docker exec "$container" \
        bash -c "grep '^external_url' /etc/gitlab/gitlab.rb 2>/dev/null | awk -F\"'\" '{print \$2}'")

    if [ -n "$url" ]; then
        echo "🌐 访问地址: $url"
    else
        # 2️⃣ 通过端口映射推断访问地址
        host_ip=$(hostname -I | awk '{print $1}')
        port=$(docker port "$container" 80/tcp 2>/dev/null | awk -F: '{print $2}')

        if [ -n "$port" ]; then
            echo -e "🌐 访问地址: ${CYAN}http://$host_ip:$port${NC}"
            echo "ℹ️ external_url 未配置，已根据端口映射推断"
        else
            echo "🌐 访问地址: 无法确定（未映射 80 端口）"
        fi
    fi

    echo ""

    # 初始 root 密码
    if docker exec "$container" test -f /etc/gitlab/initial_root_password; then
        password=$(docker exec "$container" \
            bash -c "grep 'Password:' /etc/gitlab/initial_root_password | awk '{print \$2}'")
        echo -e "🔐 初始 root 密码: ${CYAN}$password${NC}"
        echo "⚠️ 该密码仅首次有效，24 小时后自动删除"
    else
        echo "🔐 初始 root 密码: 已失效或已被删除"
        echo "👉 可使用 rails 控制台重置："
        echo "   docker exec -it $container gitlab-rails console"
    fi

    echo ""
    read -rsn1 -p "按任意键继续..."

    clear
    show_banner
    echo "${UI_DIVIDER}"
    gitlab_menu
}

gitlab_backup() {
    clear
    echo "🚧 备份功能尚未实现"
    read -rsn1 -p "按任意键继续..."

    clear
    show_banner
    echo "${UI_DIVIDER}"
    gitlab_menu
}

gitlab_restore() {
    clear
    echo "🚧 还原功能尚未实现"
    read -rsn1 -p "按任意键继续..."

    clear
    show_banner
    echo "${UI_DIVIDER}"
    gitlab_menu
}

gitlab_uninstall() {
    while true; do
        clear
        read -rsn1 -p "确认卸载 GitLab？(y/n): " yn
        echo
        case "$yn" in
            y|Y)
                echo "GitLab 卸载中，请稍后..."
                docker stop gitlab
                docker rm gitlab
                echo "GitLab 已卸载"
                break
                ;;
            n|N)
                echo "已取消安装"
                break
                ;;
            *)
                echo "请输入 y 或 n"
                ;;
        esac
    done

    read -rsn1 -p "按任意键继续..."
    clear
    show_banner
    echo "${UI_DIVIDER}"
    gitlab_menu
}

gitlab_menu() {
    # 隐藏光标
    printf "\033[?25l"
    #保存光标位置
    printf "\033[s"
    #回到菜单起始处(第13行)
    printf "\033[8;1H"

    echo "Gitlab管理:"
    for i in "${!gitlab_options[@]}"; do
        if [ "$i" -eq "$gitlab_selected" ]; then
            printf "${CYAN}> %s${NC}\n" "${gitlab_options[$i]}"
        else
            printf "  %s\n" "${gitlab_options[$i]}"
        fi
    done
    show_menu_footer
    echo "使用 ↑↓ 选择，Enter 确认"

    # 恢复光标位置
    printf "\033[u"
}

gitlab_menu_loop() {
    show_banner
    echo "${UI_DIVIDER}"
    gitlab_menu
    while true; do
        read -rsn1 key

        if [ "$key" = $'\x1b' ]; then
            read -rsn2 key
            case "$key" in
                "[A") gitlab_selected=$(( (gitlab_selected - 1 + ${#gitlab_options[@]}) % ${#gitlab_options[@]} )) ;;
                "[B") gitlab_selected=$(( (gitlab_selected + 1) % ${#gitlab_options[@]} )) ;;
                "[D")
                    main_menu_loop
                    ;;
                "[C")
                    case "${gitlab_actions[$gitlab_selected]}" in
                        "return_main")
                            main_menu_loop
                            ;;
                        *)
                            ${gitlab_actions[$gitlab_selected]}
                            ;;
                    esac
                    ;;
            esac
            gitlab_menu
        elif [ "$key" = "" ]; then
            case "${gitlab_actions[$gitlab_selected]}" in
                "return_main")
                    main_menu_loop
                    ;;
                *)
                    ${gitlab_actions[$gitlab_selected]}
                    ;;
            esac
        fi
    done
}
# ============================== 主流程 ==============================

main() {
    #check_root
    # 同步RTC
    syncRTC
    check_debug_mode "$@"
    check_system_version

    # 检查更新
    check_update

    # 主菜单
    main_menu_loop
}

# 运行主程序
main "$@"