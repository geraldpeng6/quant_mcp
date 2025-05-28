#!/bin/bash

# EC2部署脚本
# 此脚本用于在EC2实例上部署MCP服务器

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 默认参数
TRANSPORT="sse"  # 默认使用SSE传输协议
HOST="0.0.0.0"
PORT=8000
HTML_PORT=8081

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                显示此帮助信息"
    echo "  -t, --transport TRANSPORT 指定传输协议 (stdio, sse, streamable-http) (默认: sse)"
    echo "  -H, --host HOST           指定主机地址 (默认: 0.0.0.0)"
    echo "  -p, --port PORT           指定端口号 (默认: 8000)"
    echo "  --html-port PORT          指定HTML服务器端口号 (默认: 8081)"
    echo ""
    echo "示例:"
    echo "  $0                        # 使用默认设置部署 (SSE, 0.0.0.0:8000)"
    echo "  $0 -t streamable-http     # 使用Streamable HTTP传输协议部署"
    echo "  $0 -p 9000 --html-port 9001   # 在端口9000上部署MCP服务器，在端口9001上部署HTML服务器"
    exit 0
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -t|--transport)
            TRANSPORT="$2"
            shift 2
            ;;
        -H|--host)
            HOST="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        --html-port)
            HTML_PORT="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}错误: 未知选项 $1${NC}"
            show_help
            ;;
    esac
done

# 检查传输协议是否有效
if [[ "$TRANSPORT" != "stdio" && "$TRANSPORT" != "sse" && "$TRANSPORT" != "streamable-http" ]]; then
    echo -e "${RED}错误: 无效的传输协议 '$TRANSPORT'${NC}"
    echo -e "${YELLOW}有效的传输协议: stdio, sse, streamable-http${NC}"
    exit 1
fi

# 检查是否在项目根目录
if [ ! -f "server.py" ]; then
    echo -e "${RED}错误: 请在项目根目录运行此脚本${NC}"
    exit 1
fi

# 安装系统依赖
install_system_deps() {
    echo -e "${YELLOW}安装系统依赖...${NC}"
    
    # 更新包列表
    sudo apt-get update
    
    # 安装Python和pip
    sudo apt-get install -y python3 python3-pip python3-venv
    
    # 安装Nginx
    sudo apt-get install -y nginx
    
    # 安装其他依赖
    sudo apt-get install -y curl git
    
    echo -e "${GREEN}系统依赖安装完成!${NC}"
}

# 设置虚拟环境
setup_venv() {
    echo -e "${YELLOW}设置Python虚拟环境...${NC}"
    
    # 创建虚拟环境
    python3 -m venv .venv
    
    # 激活虚拟环境
    source .venv/bin/activate
    
    # 安装依赖
    pip install -r requirements.txt
    
    echo -e "${GREEN}Python虚拟环境设置完成!${NC}"
}

# 配置HTML服务器
setup_html_server() {
    echo -e "${YELLOW}配置HTML服务器...${NC}"
    
    # 创建配置目录
    mkdir -p data/config
    
    # 创建HTML服务器配置文件
    if [ ! -f "data/config/html_server.json" ]; then
        cat > data/config/html_server.json << EOF
{
    "server_port": $HTML_PORT,
    "charts_dir": "data/charts",
    "use_ec2_metadata": true,
    "use_public_ip": true
}
EOF
        echo -e "${GREEN}HTML服务器配置文件已创建!${NC}"
    else
        echo -e "${YELLOW}HTML服务器配置文件已存在，跳过创建${NC}"
    fi
    
    # 设置环境变量
    export MCP_ENV="production"
    
    # 生成测试HTML文件
    python -c "
import sys
sys.path.append('.')
from utils.html_server import generate_test_html
url = generate_test_html()
print(f'测试HTML文件已生成，URL: {url}')
"
    
    echo -e "${GREEN}HTML服务器配置完成!${NC}"
}

# 配置Nginx
setup_nginx() {
    echo -e "${YELLOW}配置Nginx...${NC}"
    
    # 设置环境变量
    export MCP_ENV="production"
    
    # 使用Python脚本生成Nginx配置
    python -c "
import sys
sys.path.append('.')
from utils.html_server import setup_nginx
success, message = setup_nginx()
print(message)
"
    
    echo -e "${GREEN}Nginx配置完成!${NC}"
}

# 创建systemd服务
create_systemd_service() {
    echo -e "${YELLOW}创建systemd服务...${NC}"
    
    # 获取当前目录
    CURRENT_DIR=$(pwd)
    
    # 创建MCP服务文件
    sudo bash -c "cat > /etc/systemd/system/mcp.service << EOF
[Unit]
Description=MCP Server
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$CURRENT_DIR
Environment=MCP_ENV=production
Environment=MCP_SERVER_HOST=
ExecStart=$CURRENT_DIR/.venv/bin/python server.py --transport $TRANSPORT --host $HOST --port $PORT
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF"
    
    # 重新加载systemd配置
    sudo systemctl daemon-reload
    
    # 启用服务
    sudo systemctl enable mcp.service
    
    echo -e "${GREEN}systemd服务创建完成!${NC}"
}

# 启动服务
start_services() {
    echo -e "${YELLOW}启动服务...${NC}"
    
    # 启动Nginx
    sudo systemctl restart nginx
    
    # 启动MCP服务
    sudo systemctl start mcp.service
    
    # 检查服务状态
    echo -e "${YELLOW}Nginx状态:${NC}"
    sudo systemctl status nginx --no-pager
    
    echo -e "${YELLOW}MCP服务状态:${NC}"
    sudo systemctl status mcp.service --no-pager
    
    echo -e "${GREEN}服务已启动!${NC}"
}

# 显示服务信息
show_service_info() {
    echo -e "${YELLOW}获取服务信息...${NC}"
    
    # 获取公网IP - 一种方法成功即返回
    get_public_ip() {
        local IP=""
        
        # 方法1: 使用外部服务
        echo -e "${YELLOW}尝试使用checkip.amazonaws.com获取IP...${NC}"
        IP=$(curl -s -m 3 https://checkip.amazonaws.com 2>/dev/null)
        if [[ -n "$IP" && "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$IP"
            return
        fi
        
        # 方法2: 使用外部服务备选
        echo -e "${YELLOW}尝试使用ifconfig.me获取IP...${NC}"
        IP=$(curl -s -m 3 https://ifconfig.me 2>/dev/null)
        if [[ -n "$IP" && "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$IP"
            return
        fi
        
        # 方法3: 使用ip命令获取本地IP
        echo -e "${YELLOW}尝试使用ip命令获取IP...${NC}"
        if command -v ip >/dev/null 2>&1; then
            IP=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
            if [[ -n "$IP" ]]; then
                echo "$IP"
                return
            fi
        fi
        
        # 方法4: 使用ifconfig命令获取本地IP
        echo -e "${YELLOW}尝试使用ifconfig命令获取IP...${NC}"
        if command -v ifconfig >/dev/null 2>&1; then
            IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
            if [[ -n "$IP" ]]; then
                echo "$IP"
                return
            fi
        fi
        
        # 如果所有方法都失败，返回localhost
        echo "localhost"
    }
    
    PUBLIC_IP=$(get_public_ip)
    echo -e "${GREEN}成功获取IP: $PUBLIC_IP${NC}"
    
    echo -e "${GREEN}部署完成!${NC}"
    echo -e "${GREEN}MCP服务器地址: http://$PUBLIC_IP:$PORT${NC}"
    if [ "$TRANSPORT" == "sse" ]; then
        echo -e "${GREEN}MCP服务器SSE端点: http://$PUBLIC_IP:$PORT/sse${NC}"
    elif [ "$TRANSPORT" == "streamable-http" ]; then
        echo -e "${GREEN}MCP服务器HTTP端点: http://$PUBLIC_IP:$PORT/mcp${NC}"
    fi
    echo -e "${GREEN}HTML服务器地址: http://$PUBLIC_IP:$HTML_PORT${NC}"
    echo -e "${GREEN}测试HTML页面: http://$PUBLIC_IP:$HTML_PORT/charts/test.html${NC}"
}

# 主函数
main() {
    echo -e "${YELLOW}开始在EC2实例上部署MCP服务器...${NC}"
    
    # 安装系统依赖
    install_system_deps
    
    # 设置虚拟环境
    setup_venv
    
    # 配置HTML服务器
    setup_html_server
    
    # 配置Nginx
    setup_nginx
    
    # 创建systemd服务
    create_systemd_service
    
    # 启动服务
    start_services
    
    # 显示服务信息
    show_service_info
}

# 执行主函数
main
