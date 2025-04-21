#!/bin/sh
# OpenWrt哪吒监控Agent一键安装脚本
# 作者：AI助手
# 版本：1.0.1

# 定义颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 打印带颜色的消息
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        print_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 获取系统架构
get_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l|armv6l)
            echo "arm"
            ;;
        mips)
            echo "mips"
            ;;
        mips64)
            echo "mips64"
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
}

# 安装必要的依赖
install_dependencies() {
    print_message "正在安装必要的依赖..."
    opkg update
    opkg install wget unzip
    if [ $? -ne 0 ]; then
        print_error "依赖安装失败"
        exit 1
    fi
}

# 获取用户输入
get_user_input() {
    local prompt="$1"
    local default="$2"
    local input
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " input
        input=${input:-$default}
    else
        read -p "$prompt: " input
    fi
    
    echo "$input"
}

# 配置Agent
configure_agent() {
    print_message "开始配置哪吒监控Agent..."
    
    # 获取服务器地址
    SERVER=$(get_user_input "请输入服务器地址")
    if [ -z "$SERVER" ]; then
        print_error "服务器地址不能为空"
        exit 1
    fi
    
    # 获取客户端密钥
    CLIENT_SECRET=$(get_user_input "请输入客户端密钥")
    if [ -z "$CLIENT_SECRET" ]; then
        print_error "客户端密钥不能为空"
        exit 1
    fi
    
    # 是否启用TLS
    TLS=$(get_user_input "是否启用TLS (y/n)" "n")
    case $TLS in
        [Yy]* ) TLS="true";;
        * ) TLS="false";;
    esac
    
    # 是否启用GPU监控
    GPU=$(get_user_input "是否启用GPU监控 (y/n)" "n")
    case $GPU in
        [Yy]* ) GPU="true";;
        * ) GPU="false";;
    esac
    
    # 是否启用温度监控
    TEMPERATURE=$(get_user_input "是否启用温度监控 (y/n)" "n")
    case $TEMPERATURE in
        [Yy]* ) TEMPERATURE="true";;
        * ) TEMPERATURE="false";;
    esac
}

# 检查IP是否在中国
check_ip_location() {
    local ip=$(curl -s ifconfig.me)
    local location=$(curl -s "http://ip-api.com/json/$ip" | grep -o '"countryCode":"[A-Z]*"' | cut -d'"' -f4)
    if [ "$location" = "CN" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# 检查网络连接
check_network() {
    print_message "正在检查网络连接..."
    local host=$(echo $SERVER | cut -d: -f1)
    if ! ping -c 1 -W 1 $host > /dev/null 2>&1; then
        print_error "无法连接到服务器，请检查网络连接"
        exit 1
    fi
    print_message "网络连接正常"
}

# 下载并安装Agent
install_agent() {
    local arch=$(get_arch)
    local is_china=$(check_ip_location)
    local download_url
    
    if [ "$is_china" = "true" ]; then
        download_url="https://github.zhoujie218.top/https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${arch}.zip"
    else
        download_url="https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${arch}.zip"
    fi
    
    local install_dir="/etc/nezha"
    
    print_message "正在创建安装目录..."
    mkdir -p $install_dir
    
    print_message "正在下载Agent..."
    wget -O $install_dir/nezha-agent.zip $download_url
    if [ $? -ne 0 ]; then
        print_error "下载失败，尝试使用备用地址..."
        # 如果下载失败，尝试使用备用地址
        if [ "$is_china" = "true" ]; then
            download_url="https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${arch}.zip"
        else
            download_url="https://github.zhoujie218.top/https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${arch}.zip"
        fi
        wget -O $install_dir/nezha-agent.zip $download_url
        if [ $? -ne 0 ]; then
            print_error "下载失败"
            exit 1
        fi
    fi
    
    print_message "正在解压文件..."
    unzip -o $install_dir/nezha-agent.zip -d $install_dir
    if [ $? -ne 0 ]; then
        print_error "解压失败"
        exit 1
    fi
    
    print_message "正在设置执行权限..."
    chmod +x $install_dir/nezha-agent
    
    # 创建配置文件
    print_message "正在创建配置文件..."
    cat > $install_dir/config.yml << EOF
server: "$SERVER"
client_secret: "$CLIENT_SECRET"
tls: $TLS
gpu: $GPU
temperature: $TEMPERATURE
debug: false
disable_auto_update: false
disable_command_execute: false
disable_force_update: false
disable_nat: false
disable_send_query: false
insecure_tls: false
ip_report_period: 1800
report_delay: 1
skip_connection_count: false
skip_procs_count: false
use_gitee_to_upgrade: false
use_ipv6_country_code: false
uuid: $(cat /proc/sys/kernel/random/uuid)
EOF
}

# 创建服务脚本
create_service() {
    local install_dir="/etc/nezha"
    
    print_message "正在创建服务脚本..."
    cat > /etc/init.d/nezha-service << EOF
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command $install_dir/nezha-agent
    procd_set_param args -c $install_dir/config.yml
    procd_set_param respawn
    procd_set_param respawn_retry 5
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall nezha-agent
}

restart() {
    stop
    sleep 2
    start
}
EOF
    
    chmod +x /etc/init.d/nezha-service
    /etc/init.d/nezha-service enable
    /etc/init.d/nezha-service start
    
    print_message "服务已启动并设置为开机自启"
}

# 显示安装信息
show_install_info() {
    print_message "安装完成！"
    print_message "安装目录: /etc/nezha"
    print_message "配置文件: /etc/nezha/config.yml"
    print_message "服务状态: $(/etc/init.d/nezha-agent status)"
    print_message "您可以通过以下命令管理服务："
    print_message "启动服务: /etc/init.d/nezha-agent start"
    print_message "停止服务: /etc/init.d/nezha-agent stop"
    print_message "重启服务: /etc/init.d/nezha-agent restart"
}

# 主函数
main() {
    print_message "开始安装哪吒监控Agent..."
    check_root
    install_dependencies
    configure_agent
    check_network
    install_agent
    create_service
    show_install_info
}

# 执行主函数
main 