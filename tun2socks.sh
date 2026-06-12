#!/bin/bash

# ==============================================================================
# Script Name:  ocserv-socks5-forwarder.sh
# Description:  Automated script to route ocserv VPN traffic through a SOCKS5 
#               proxy using tun2socks and policy routing.
# Author:       SheepKeeperS
# ==============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 必须以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须使用 root 用户运行此脚本。${NC}" 
   exit 1
fi

# 解析命令行参数 (支持无人值守安装/卸载)
ACTION=""
PARAM_SUBNET=""
PARAM_PROXY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--install)
            ACTION="install"
            shift
            ;;
        -u|--uninstall)
            ACTION="uninstall"
            shift
            ;;
        --subnet)
            PARAM_SUBNET="$2"
            shift 2
            ;;
        --proxy)
            PARAM_PROXY="$2"
            shift 2
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  -i, --install              命令行一键安装模式"
            echo "  -u, --uninstall            命令行一键卸载模式"
            echo "  --subnet <CIDR>            指定 ocserv 分配子网 (例如 10.10.10.0/24)"
            echo "  --proxy <SOCKS5_URL>       指定 SOCKS5 代理串 (例如 socks5://user:pass@ip:port)"
            echo "  -h, --help                 显示本帮助页面"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

show_menu() {
    clear
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN}      ocserv -> SOCKS5 流量一键管理面板${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e " ${GREEN}1.${NC} 安装与配置 tun2socks 中转服务"
    echo -e " ${GREEN}2.${NC} 卸载并清理 tun2socks 服务"
    echo -e " ${GREEN}3.${NC} 查看运行状态与当前配置"
    echo -e " ${GREEN}4.${NC} 重启中转服务"
    echo -e " ${GREEN}5.${NC} 停止中转服务"
    echo -e " ${GREEN}6.${NC} 查看中转服务实时运行日志"
    echo -e " ${RED}0.${NC} 退出脚本"
    echo -e "${GREEN}=================================================${NC}"
    read -p " 请选择操作 [0-6, 默认 1]: " OPTION
    OPTION=${OPTION:-"1"}
}

check_status() {
    echo -e "\n${YELLOW}▶ 正在获取 tun2socks 运行状态...${NC}"
    
    # 1. 检查 Systemd 服务状态
    if systemctl is-active --quiet tun2socks; then
        echo -e "服务状态: ${GREEN}运行中 (Active)${NC}"
    else
        echo -e "服务状态: ${RED}已停止 (Inactive)${NC}"
    fi
    
    # 2. 检查网络接口 tun0
    if ip link show dev tun0 >/dev/null 2>&1; then
        echo -e "网络接口: ${GREEN}tun0 已启用${NC}"
        ip addr show dev tun0 | grep "inet " | awk '{print "  内部 IP: "$2}'
    else
        echo -e "网络接口: ${RED}tun0 未启用 (或未创建)${NC}"
    fi
    
    # 3. 检查策略路由规则
    echo -e "策略路由规则 (Table 200):"
    local rules; rules=$(ip rule show | grep "lookup 200")
    if [[ -n "$rules" ]]; then
        echo -e "${GREEN}$rules${NC}"
    else
        echo -e "${RED}无活动路由规则 (流量不会被分流)${NC}"
    fi
    
    # 4. 检查路由表 200 详情
    echo -e "路由表 200 详情:"
    local routes; routes=$(ip route show table 200)
    if [[ -n "$routes" ]]; then
        echo -e "${GREEN}$routes${NC}"
    else
        echo -e "${RED}无路由条目${NC}"
    fi
    
    # 5. 检查代理地址 (对密码部分脱敏处理)
    if [[ -f /etc/systemd/system/tun2socks.service ]]; then
        local proxy_line; proxy_line=$(grep "ExecStart=" /etc/systemd/system/tun2socks.service | grep -o "\-proxy [^ ]*")
        if [[ -n "$proxy_line" ]]; then
            local proxy_url; proxy_url=${proxy_line#-proxy }
            if [[ "$proxy_url" =~ :[^@]+@ ]]; then
                proxy_url=$(echo "$proxy_url" | sed -E 's/:([^@:]+)@/:******@/')
            fi
            echo -e "中继落地 SOCKS5: ${YELLOW}$proxy_url${NC}"
        fi
    fi
}

restart_service() {
    echo -e "\n${YELLOW}=> 正在重启 tun2socks 中转服务...${NC}"
    systemctl restart tun2socks
    if systemctl is-active --quiet tun2socks; then
        echo -e "${GREEN}服务重启成功！${NC}"
    else
        echo -e "${RED}服务重启失败，请选择选项 6 查看运行日志以排查错误。${NC}"
    fi
}

stop_service() {
    echo -e "\n${YELLOW}=> 正在停止 tun2socks 中转服务...${NC}"
    systemctl stop tun2socks
    if ! systemctl is-active --quiet tun2socks; then
        echo -e "${GREEN}服务已成功停止，相关策略路由已自动清除。${NC}"
    else
        echo -e "${RED}停止服务失败。${NC}"
    fi
}

view_logs() {
    echo -e "\n${YELLOW}=> 正在显示实时日志 (按 Ctrl+C 退出日志查看)...${NC}\n"
    journalctl -u tun2socks -f -n 50
}

uninstall_service() {
    echo -e "\n${YELLOW}=> 正在卸载并清理 tun2socks 服务...${NC}"
    
    # 停止并禁用 Systemd 服务
    if systemctl is-active --quiet tun2socks || systemctl is-enabled --quiet tun2socks 2>/dev/null; then
        systemctl stop tun2socks 2>/dev/null || true
        systemctl disable tun2socks 2>/dev/null || true
    fi
    
    # 清理残留路由和接口
    if [[ -f /etc/tun2socks-down.sh ]]; then
        bash /etc/tun2socks-down.sh 2>/dev/null || true
    fi
    
    # 删除配置文件与服务文件
    rm -f /etc/systemd/system/tun2socks.service
    rm -f /etc/tun2socks-up.sh
    rm -f /etc/tun2socks-down.sh
    rm -f /usr/local/bin/tun2socks
    
    systemctl daemon-reload
    echo -e "${GREEN}卸载完成！策略路由规则、虚拟网卡接口及服务均已彻底清除。${NC}"
}

install_service() {
    # 1. 收集用户输入配置并实施验证
    if [[ -n "$PARAM_SUBNET" && -n "$PARAM_PROXY" ]]; then
        # 无人值守命令行模式
        OCSERV_SUBNET="$PARAM_SUBNET"
        SOCKS_PROXY="$PARAM_PROXY"
        if [[ ! "$OCSERV_SUBNET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            echo -e "${RED}错误: 子网段格式错误！${NC}"
            exit 1
        fi
    else
        # 交互式菜单模式
        echo -e "\n${YELLOW}▶ 配置中转网络与落地代理信息${NC}"
        
        # 网段校验
        while true; do
            read -p "请输入 ocserv 客户端分配的网段 (默认 10.10.10.0/24): " OCSERV_SUBNET
            OCSERV_SUBNET=${OCSERV_SUBNET:-"10.10.10.0/24"}
            if [[ "$OCSERV_SUBNET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                break
            else
                echo -e "${RED}输入格式错误！必须为 CIDR 格式，例如 10.10.10.0/24${NC}"
            fi
        done

        # 落地 IP 校验
        while true; do
            read -p "请输入 SOCKS5 落地 IP 或域名 (必填): " SOCKS_IP
            SOCKS_IP=$(echo "$SOCKS_IP" | tr -d '[:space:]')
            if [[ -n "$SOCKS_IP" ]]; then
                break
            fi
        done

        # 落地端口校验
        while true; do
            read -p "请输入 SOCKS5 端口 (必填, 1-65535): " SOCKS_PORT
            SOCKS_PORT=$(echo "$SOCKS_PORT" | tr -d '[:space:]')
            if [[ "$SOCKS_PORT" =~ ^[0-9]+$ ]] && [ "$SOCKS_PORT" -ge 1 ] && [ "$SOCKS_PORT" -le 65535 ]; then
                break
            else
                echo -e "${RED}请输入有效的端口号！${NC}"
            fi
        done

        read -p "请输入 SOCKS5 账号 (无认证请直接回车): " SOCKS_USER
        read -p "请输入 SOCKS5 密码 (无认证请直接回车): " SOCKS_PASS

        # 动态拼接 SOCKS5 代理 URL
        if [[ -n "$SOCKS_USER" && -n "$SOCKS_PASS" ]]; then
            SOCKS_PROXY="socks5://${SOCKS_USER}:${SOCKS_PASS}@${SOCKS_IP}:${SOCKS_PORT}"
        else
            SOCKS_PROXY="socks5://${SOCKS_IP}:${SOCKS_PORT}"
        fi
    fi

    echo -e "\n${YELLOW}开始安装与配置，请稍候...${NC}\n"

    # 2. 开启系统内核转发
    echo "=> 开启 IPv4 转发..."
    mkdir -p /etc/sysctl.d
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-tun2socks.conf
    sysctl --system >/dev/null 2>&1 || sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

    # 3. 安装依赖与 tun2socks
    echo "=> 检查并安装必要组件 (unzip, wget)..."
    install_dep() {
        local cmd=$1
        local apt_pkg=$2
        local yum_pkg=$3
        if ! command -v "$cmd" >/dev/null 2>&1; then
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update -qq && apt-get install -y "$apt_pkg" >/dev/null 2>&1
            elif command -v yum >/dev/null 2>&1; then
                yum install -y "$yum_pkg" >/dev/null 2>&1
            fi
        fi
    }
    install_dep "unzip" "unzip" "unzip"
    install_dep "wget" "wget" "wget"

    # 4. 自动识别 CPU 架构并下载对应版本的 tun2socks v2.6.0
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) TUN_ARCH="amd64" ;;
        aarch64|arm64) TUN_ARCH="arm64" ;;
        armv7l) TUN_ARCH="armv7" ;;
        i386|i686) TUN_ARCH="386" ;;
        *) echo -e "${RED}不支持的 CPU 架构: $ARCH${NC}"; exit 1 ;;
    esac

    echo "=> 正在下载并安装 tun2socks v2.6.0 ($TUN_ARCH)..."
    TUN2SOCKS_URL="https://github.com/xjasonlyu/tun2socks/releases/download/v2.6.0/tun2socks-linux-${TUN_ARCH}.zip"
    
    # 优先采用带进度的下载，失败则尝试带国内代理的镜像源 fallback
    if ! wget --show-progress -O /tmp/tun2socks.zip "$TUN2SOCKS_URL"; then
        echo -e "${YELLOW}官方链接下载失败，正在切换 ghproxy 国内加速源下载...${NC}"
        TUN2SOCKS_URL="https://ghproxy.cn/https://github.com/xjasonlyu/tun2socks/releases/download/v2.6.0/tun2socks-linux-${TUN_ARCH}.zip"
        wget --show-progress -O /tmp/tun2socks.zip "$TUN2SOCKS_URL" || {
            echo -e "${RED}错误: 下载 tun2socks 失败，请检查 VPS 网络连接。${NC}"
            exit 1
        }
    fi

    unzip -qo /tmp/tun2socks.zip -d /tmp/ || {
        echo -e "${RED}错误: 解压失败。${NC}"
        exit 1
    }
    
    # 动态匹配解压出的文件并移动
    mv "/tmp/tun2socks-linux-${TUN_ARCH}" /usr/local/bin/tun2socks 2>/dev/null || mv /tmp/tun2socks* /usr/local/bin/tun2socks || {
        echo -e "${RED}错误: 无法部署 tun2socks 执行程序。${NC}"
        exit 1
    }
    chmod +x /usr/local/bin/tun2socks
    rm -f /tmp/tun2socks.zip

    # 5. 创建网络接口启动与清理脚本 (强化鲁棒性)
    echo "=> 写入策略路由脚本..."

    # 清理脚本：使用 lookup 200 动态匹配规则，防止多余或旧网段规则残留
    cat << 'EOT' > /etc/tun2socks-down.sh
#!/bin/bash
# 1. 递归删除所有指向路由表 200 的策略路由规则，防止残留与冲突
while ip rule show | grep -q "lookup 200"; do
    ip rule del table 200 2>/dev/null || break
done

# 2. 清空路由表 200
ip route flush table 200 2>/dev/null || true

# 3. 删除 Forward 链转发规则
iptables -D FORWARD -i vpns+ -o tun0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i tun0 -o vpns+ -j ACCEPT 2>/dev/null || true

# 4. 关闭并卸载虚拟网卡设备 tun0
ip link set dev tun0 down 2>/dev/null || true
ip tuntap del mode tun dev tun0 2>/dev/null || true
EOT
    chmod +x /etc/tun2socks-down.sh

    # 启动脚本：在应用新规则前首先运行 Down 脚本，确保干净无冲突的环境
    cat << EOT > /etc/tun2socks-up.sh
#!/bin/bash
# 1. 启动前进行全套清理，防范多重 interface/rule 冲突
/etc/tun2socks-down.sh 2>/dev/null || true

# 2. 创建 tun 设备并赋予小范围的 B 类掩码，防止干扰常用 IP 段
ip tuntap add mode tun dev tun0
ip addr add 172.23.45.1/30 dev tun0
ip link set dev tun0 up

# 3. 配置策略路由与防火墙放行规则
ip rule add from ${OCSERV_SUBNET} table 200
ip route add default dev tun0 table 200
iptables -I FORWARD -i vpns+ -o tun0 -j ACCEPT
iptables -I FORWARD -i tun0 -o vpns+ -j ACCEPT
EOT
    chmod +x /etc/tun2socks-up.sh

    # 6. 配置 Systemd 守护进程
    echo "=> 配置 systemd 服务..."
    cat << EOT > /etc/systemd/system/tun2socks.service
[Unit]
Description=tun2socks - Route ocserv traffic to Socks5
After=network.target

[Service]
Type=simple
User=root
ExecStartPre=/etc/tun2socks-up.sh
ExecStart=/usr/local/bin/tun2socks -device tun0 -proxy ${SOCKS_PROXY} -loglevel warning
ExecStopPost=/etc/tun2socks-down.sh
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOT

    # 7. 启动并设置开机自启
    echo "=> 启动 tun2socks 服务..."
    systemctl daemon-reload
    systemctl enable tun2socks >/dev/null 2>&1
    systemctl restart tun2socks

    # 8. 完成提示
    if systemctl is-active --quiet tun2socks; then
        echo -e "\n${GREEN}=================================================${NC}"
        echo -e "${GREEN}安装与配置完成！${NC}"
        echo -e "tun2socks 已经在后台运行并设置了开机自启。"
        check_status
        echo -e "${GREEN}=================================================${NC}"
    else
        echo -e "\n${RED}服务启动可能遇到问题，请使用 systemctl status tun2socks 或选择选项 6 检查日志。${NC}"
    fi
}

# 流程分支：命令行无人值守 vs 交互式菜单
if [[ -n "$ACTION" ]]; then
    case "$ACTION" in
        install)
            install_service
            ;;
        uninstall)
            uninstall_service
            ;;
    esac
else
    # 交互式管理面板循环
    while true; do
        show_menu
        case "$OPTION" in
            1)
                install_service
                ;;
            2)
                uninstall_service
                ;;
            3)
                check_status
                ;;
            4)
                restart_service
                ;;
            5)
                stop_service
                ;;
            6)
                view_logs
                ;;
            0)
                echo "已退出脚本。"
                exit 0
                ;;
            *)
                echo -e "${RED}无效输入，请输入 0-6 之间的数字。${NC}"
                ;;
        esac
        echo -e "\n按任意键返回主菜单..."
        read -n 1 -s
    done
fi
