#!/bin/bash

# 部署和启动MCP服务器脚本
# 此脚本集成了部署和启动功能，同时处理Nginx配置

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
DEPLOY_MODE="local"  # 默认为本地模式

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                显示此帮助信息"
    echo "  -t, --transport TRANSPORT 指定传输协议 (stdio, sse, streamable-http) (默认: sse)"
    echo "  -H, --host HOST           指定主机地址 (默认: 0.0.0.0)"
    echo "  -p, --port PORT           指定端口号 (默认: 8000)"
    echo "  --html-port PORT          指定HTML服务器端口号 (默认: 8081)"
    echo "  -d, --deploy              部署模式，将安装依赖并配置系统服务"
    echo "  --production              生产环境模式，设置MCP_ENV=production"
    echo ""
    echo "示例:"
    echo "  $0                        # 使用默认设置启动 (SSE, 0.0.0.0:8000)"
    echo "  $0 -t stdio               # 使用STDIO传输协议启动"
    echo "  $0 -d                     # 部署模式，安装依赖并配置系统服务"
    echo "  $0 -d --production        # 生产环境部署"
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
        -d|--deploy)
            DEPLOY_MODE="deploy"
            shift
            ;;
        --production)
            export MCP_ENV="production"
            shift
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

# 检测操作系统
detect_os() {
    echo -e "${YELLOW}检测操作系统...${NC}"
    
    # 获取操作系统类型
    OS="$(uname -s)"
    case "${OS}" in
        Linux*)     MACHINE=Linux;;
        Darwin*)    MACHINE=Mac;;
        CYGWIN*)    MACHINE=Windows;;
        MINGW*)     MACHINE=Windows;;
        *)          MACHINE="UNKNOWN:${OS}"
    esac
    
    echo -e "${GREEN}操作系统: ${MACHINE}${NC}"
    return 0
}

# 检查依赖项
check_dependencies() {
    echo -e "${YELLOW}检查系统依赖项...${NC}"
    
    MISSING_DEPS=()
    
    # 检查Python
    if ! command -v python3 &> /dev/null; then
        MISSING_DEPS+=("python3")
    fi
    
    # 检查pip
    if ! command -v pip3 &> /dev/null; then
        MISSING_DEPS+=("pip3")
    fi
    
    # 检查Nginx
    if ! command -v nginx &> /dev/null; then
        MISSING_DEPS+=("nginx")
    fi
    
    # 处理缺少的依赖
    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        echo -e "${YELLOW}以下依赖项缺失: ${MISSING_DEPS[*]}${NC}"
        if [ "$DEPLOY_MODE" = "deploy" ]; then
            echo -e "${YELLOW}将安装缺少的依赖项...${NC}"
        else
            echo -e "${YELLOW}请安装缺少的依赖项或使用 -d 参数以自动安装${NC}"
            if [ "$MACHINE" = "Linux" ]; then
                echo -e "${YELLOW}可以使用以下命令安装依赖项:${NC}"
                echo -e "sudo apt-get update && sudo apt-get install -y ${MISSING_DEPS[*]}"
            elif [ "$MACHINE" = "Mac" ]; then
                echo -e "${YELLOW}可以使用以下命令安装依赖项:${NC}"
                echo -e "brew install ${MISSING_DEPS[*]}"
            fi
            if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
                exit 1
            fi
        fi
    else
        echo -e "${GREEN}所有依赖项已安装!${NC}"
    fi
    
    return 0
}

# 安装系统依赖
install_system_deps() {
    if [ "$DEPLOY_MODE" != "deploy" ]; then
        return 0
    fi
    
    echo -e "${YELLOW}安装系统依赖...${NC}"
    
    if [ "$MACHINE" = "Linux" ]; then
        # 更新包列表
        sudo apt-get update
        
        # 安装Python和pip
        sudo apt-get install -y python3 python3-pip python3-venv
        
        # 安装Nginx
        sudo apt-get install -y nginx
        
        # 安装其他依赖
        sudo apt-get install -y curl git
    elif [ "$MACHINE" = "Mac" ]; then
        # 检查Homebrew是否已安装
        if ! command -v brew &> /dev/null; then
            echo -e "${YELLOW}安装Homebrew...${NC}"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        
        # 安装Python和pip
        brew install python3
        
        # 安装Nginx
        brew install nginx
    else
        echo -e "${RED}不支持的操作系统: ${MACHINE}${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}系统依赖安装完成!${NC}"
    return 0
}

# 检查 uv 是否已安装
setup_uv() {
    echo -e "${YELLOW}检查 uv 是否已安装...${NC}"

    if ! command -v uv &> /dev/null; then
        echo -e "${YELLOW}uv 未安装，正在安装...${NC}"

        # 安装 uv
        curl -LsSf https://astral.sh/uv/install.sh | sh

        # 添加 uv 到 PATH
        if [[ ":$PATH:" != *":$HOME/.cargo/bin:"* ]]; then
            export PATH="$HOME/.cargo/bin:$PATH"
        fi

        echo -e "${GREEN}uv 安装完成!${NC}"
    else
        echo -e "${GREEN}uv 已安装!${NC}"
    fi
}

# 设置虚拟环境
setup_venv() {
    echo -e "${YELLOW}设置Python虚拟环境...${NC}"
    
    # 检查虚拟环境是否存在
    if [ ! -d ".venv" ]; then
        echo -e "${YELLOW}虚拟环境不存在，正在创建...${NC}"
        python3 -m venv .venv
    else
        echo -e "${GREEN}虚拟环境已存在!${NC}"
    fi
    
    # 激活虚拟环境
    echo -e "${YELLOW}激活虚拟环境...${NC}"
    source .venv/bin/activate
    
    # 检查依赖是否已安装
    echo -e "${YELLOW}安装依赖...${NC}"
    if [ -f "requirements.txt" ]; then
        if command -v uv &> /dev/null; then
            uv pip install -r requirements.txt
        else
            pip install -r requirements.txt
        fi
    else
        echo -e "${YELLOW}未找到 requirements.txt，尝试安装基本依赖...${NC}"
        pip install mcp
    fi
    
    echo -e "${GREEN}Python环境设置完成!${NC}"
    return 0
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
    "use_public_ip": true
}
EOF
        echo -e "${GREEN}HTML服务器配置文件已创建!${NC}"
    else
        # 更新现有配置
        python -c "
import json, os
config_file = 'data/config/html_server.json'
if os.path.exists(config_file):
    with open(config_file, 'r') as f:
        config = json.load(f)
    config['server_port'] = $HTML_PORT
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=4)
    print('已更新HTML服务器配置文件')
"
        echo -e "${YELLOW}HTML服务器配置文件已更新${NC}"
    fi
    
    return 0
}

# 配置Nginx
setup_nginx() {
    echo -e "${YELLOW}配置Nginx...${NC}"

    # 获取charts目录的绝对路径
    CHARTS_DIR=$(pwd)/data/charts
    
    # 检测操作系统和环境
    if [ "$MACHINE" = "Linux" ]; then
        if [ "$EUID" -ne 0 ] && [ "$DEPLOY_MODE" = "deploy" ]; then
            echo -e "${YELLOW}注意: 需要root权限配置Nginx${NC}"
            
            # 创建临时配置文件
            cat > mcp_html_server.conf << EOF
# MCP HTML服务器配置
server {
    listen $HTML_PORT;
    server_name _;
    
    # 允许跨域访问
    add_header 'Access-Control-Allow-Origin' '*';
    add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';

    # 禁止访问隐藏文件
    location ~ /\\. {
        deny all;
    }

    # 静态文件服务
    location /charts/ {
        alias $CHARTS_DIR/;

        # 只允许访问HTML文件
        location ~* \\.(html)$ {
            add_header Content-Type text/html;
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            # 允许跨域访问
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
        }

        # 禁止目录列表
        autoindex off;

        # 禁止访问其他类型的文件
        location ~* \\.(php|py|js|json|txt|log|ini|conf)$ {
            deny all;
        }
    }

    # 默认页面 - 生成一个测试页面
    location = / {
        return 200 '<html><head><title>MCP HTML服务器</title></head><body><h1>MCP HTML服务器</h1><p>服务器运行正常</p><p>当前时间: <span id="time"></span></p><script>document.getElementById("time").textContent = new Date().toLocaleString();</script></body></html>';
        add_header Content-Type text/html;
    }
}
EOF
            echo -e "${YELLOW}已创建Nginx配置文件: mcp_html_server.conf${NC}"
            echo -e "${YELLOW}请手动复制此文件到Nginx配置目录:${NC}"
            echo -e "${YELLOW}sudo cp mcp_html_server.conf /etc/nginx/conf.d/${NC}"
            echo -e "${YELLOW}然后重新加载Nginx:${NC}"
            echo -e "${YELLOW}sudo nginx -s reload${NC}"
        else
            # 直接配置Nginx
            if [ "$DEPLOY_MODE" = "deploy" ]; then
                # 部署模式，直接写入配置文件
                NGINX_CONF_DIR="/etc/nginx/conf.d"
                if [ ! -d "$NGINX_CONF_DIR" ]; then
                    sudo mkdir -p "$NGINX_CONF_DIR"
                fi
                
                sudo bash -c "cat > $NGINX_CONF_DIR/mcp_html_server.conf << EOF
# MCP HTML服务器配置
server {
    listen $HTML_PORT;
    server_name _;
    
    # 允许跨域访问
    add_header 'Access-Control-Allow-Origin' '*';
    add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';

    # 禁止访问隐藏文件
    location ~ /\\. {
        deny all;
    }

    # 静态文件服务
    location /charts/ {
        alias $CHARTS_DIR/;

        # 只允许访问HTML文件
        location ~* \\.(html)$ {
            add_header Content-Type text/html;
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            # 允许跨域访问
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
        }

        # 禁止目录列表
        autoindex off;

        # 禁止访问其他类型的文件
        location ~* \\.(php|py|js|json|txt|log|ini|conf)$ {
            deny all;
        }
    }

    # 默认页面 - 生成一个测试页面
    location = / {
        return 200 '<html><head><title>MCP HTML服务器</title></head><body><h1>MCP HTML服务器</h1><p>服务器运行正常</p><p>当前时间: <span id="time"></span></p><script>document.getElementById("time").textContent = new Date().toLocaleString();</script></body></html>';
        add_header Content-Type text/html;
    }
}
EOF"
                
                # 测试配置
                sudo nginx -t
                
                if [ $? -eq 0 ]; then
                    # 重新加载Nginx
                    sudo nginx -s reload
                    echo -e "${GREEN}Nginx配置已更新并重新加载${NC}"
                else
                    echo -e "${RED}Nginx配置测试失败，请检查配置文件${NC}"
                fi
            else
                # 非部署模式，使用Python生成配置
                python -c "
import sys
sys.path.append('.')
from utils.html_server import setup_nginx
success, message = setup_nginx()
print(message)
"
            fi
        fi
    elif [ "$MACHINE" = "Mac" ]; then
        # macOS配置
        NGINX_CONF_DIR="/opt/homebrew/etc/nginx/servers"
        if [ ! -d "$NGINX_CONF_DIR" ]; then
            mkdir -p "$NGINX_CONF_DIR"
        fi
        
        cat > "$NGINX_CONF_DIR/mcp_html_server.conf" << EOF
# MCP HTML服务器配置
server {
    listen $HTML_PORT;
    server_name _;
    
    # 允许跨域访问
    add_header 'Access-Control-Allow-Origin' '*';
    add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';

    # 禁止访问隐藏文件
    location ~ /\\. {
        deny all;
    }

    # 静态文件服务
    location /charts/ {
        alias $CHARTS_DIR/;

        # 只允许访问HTML文件
        location ~* \\.(html)$ {
            add_header Content-Type text/html;
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            # 允许跨域访问
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
        }

        # 禁止目录列表
        autoindex off;

        # 禁止访问其他类型的文件
        location ~* \\.(php|py|js|json|txt|log|ini|conf)$ {
            deny all;
        }
    }

    # 默认页面 - 生成一个测试页面
    location = / {
        return 200 '<html><head><title>MCP HTML服务器</title></head><body><h1>MCP HTML服务器</h1><p>服务器运行正常</p><p>当前时间: <span id="time"></span></p><script>document.getElementById("time").textContent = new Date().toLocaleString();</script></body></html>';
        add_header Content-Type text/html;
    }
}
EOF
        
        # 测试配置
        nginx -t
        
        if [ $? -eq 0 ]; then
            # 重新加载Nginx
            brew services reload nginx
            echo -e "${GREEN}Nginx配置已更新并重新加载${NC}"
        else
            echo -e "${RED}Nginx配置测试失败，请检查配置文件${NC}"
        fi
    else
        echo -e "${RED}不支持的操作系统: ${MACHINE}${NC}"
    fi
    
    echo -e "${GREEN}Nginx配置完成!${NC}"
    return 0
}

# 创建systemd服务（仅在Linux部署模式下）
create_systemd_service() {
    if [ "$MACHINE" != "Linux" ] || [ "$DEPLOY_MODE" != "deploy" ]; then
        return 0
    fi
    
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
    
    # 启动服务
    echo -e "${YELLOW}启动MCP服务...${NC}"
    sudo systemctl start mcp.service
    
    # 检查服务状态
    echo -e "${YELLOW}MCP服务状态:${NC}"
    sudo systemctl status mcp.service --no-pager
    
    return 0
}

# 生成测试HTML文件
generate_test_html() {
    echo -e "${YELLOW}生成测试HTML文件...${NC}"
    
    # 确保必要的目录存在
    mkdir -p data/logs data/klines data/charts data/temp data/config data/backtest data/templates
    
    # 生成测试HTML文件
    TEST_URL=$(python -c "
import sys
sys.path.append('.')
from utils.html_server import get_html_url
import os
test_path = os.path.abspath('data/charts/test.html')
if os.path.exists(test_path):
    url = get_html_url(test_path)
    print(url)
else:
    print('测试文件不存在，正在创建...')
    from utils.html_server import generate_test_html
    url = generate_test_html()
    print(url)
")
    
    if [ -n "$TEST_URL" ]; then
        echo -e "${GREEN}测试HTML文件URL: $TEST_URL${NC}"
        echo -e "${YELLOW}尝试使用curl访问测试HTML文件...${NC}"
        curl -s -I "$TEST_URL" | head -n 1 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}测试HTML文件可以成功访问!${NC}"
        else
            echo -e "${YELLOW}无法通过HTTP访问测试HTML文件，可能需要配置Nginx${NC}"
        fi
    else
        echo -e "${YELLOW}无法获取测试HTML文件URL${NC}"
    fi
    
    return 0
}

# 启动服务
start_mcp() {
    echo -e "${GREEN}启动MCP服务器，使用${TRANSPORT}传输协议${NC}"
    
    # 在Linux部署模式下，服务已经通过systemd启动
    if [ "$MACHINE" = "Linux" ] && [ "$DEPLOY_MODE" = "deploy" ]; then
        echo -e "${GREEN}MCP服务器已通过systemd启动${NC}"
        return 0
    fi
    
    # 根据传输协议选择不同的启动方式
    if [ "$TRANSPORT" = "stdio" ]; then
        python server.py --transport stdio
    elif [ "$TRANSPORT" = "sse" ]; then
        echo -e "${GREEN}启动MCP服务器，使用SSE传输协议，地址: http://$HOST:$PORT/sse${NC}"
        python server.py --transport sse --host "$HOST" --port "$PORT"
    elif [ "$TRANSPORT" = "streamable-http" ]; then
        echo -e "${GREEN}启动MCP服务器，使用Streamable HTTP传输协议，地址: http://$HOST:$PORT/mcp${NC}"
        python server.py --transport streamable-http --host "$HOST" --port "$PORT"
    fi
    
    return 0
}

# 显示服务信息
show_service_info() {
    echo -e "${YELLOW}获取服务信息...${NC}"
    
    # 获取服务器主机地址
    SERVER_HOST=$(python -c "
import sys
sys.path.append('.')
from utils.html_server import get_server_host
host = get_server_host()
print(host)
")
    
    echo -e "${GREEN}部署和启动完成!${NC}"
    echo -e "${GREEN}MCP服务器地址: http://$SERVER_HOST:$PORT${NC}"
    if [ "$TRANSPORT" = "sse" ]; then
        echo -e "${GREEN}MCP服务器SSE端点: http://$SERVER_HOST:$PORT/sse${NC}"
    elif [ "$TRANSPORT" = "streamable-http" ]; then
        echo -e "${GREEN}MCP服务器HTTP端点: http://$SERVER_HOST:$PORT/mcp${NC}"
    fi
    echo -e "${GREEN}HTML服务器地址: http://$SERVER_HOST:$HTML_PORT${NC}"
    echo -e "${GREEN}测试HTML页面: http://$SERVER_HOST:$HTML_PORT/charts/test.html${NC}"
    
    return 0
}

# 主函数
main() {
    if [ "$DEPLOY_MODE" = "deploy" ]; then
        echo -e "${YELLOW}开始部署MCP服务器...${NC}"
    else
        echo -e "${YELLOW}准备启动MCP服务器...${NC}"
    fi
    
    # 检测操作系统
    detect_os
    
    # 检查依赖项
    check_dependencies
    
    # 安装系统依赖
    install_system_deps
    
    # 设置uv (如果可用)
    setup_uv
    
    # 设置虚拟环境
    setup_venv
    
    # 配置HTML服务器
    setup_html_server
    
    # 配置Nginx
    setup_nginx
    
    # 创建systemd服务（仅在Linux部署模式下）
    create_systemd_service
    
    # 生成测试HTML文件
    generate_test_html
    
    # 启动服务
    start_mcp
    
    # 显示服务信息
    show_service_info
}

# 执行主函数
main 