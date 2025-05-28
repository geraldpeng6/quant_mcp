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
HOST="0.0.0.0"   # 默认绑定到所有接口
PORT=8000
HTML_PORT=8081
DEPLOY_MODE="local"  # 默认为本地模式
REDEPLOY=false       # 默认不是重新部署模式

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
    echo "  -r, --redeploy            重新部署模式，重新配置并重启服务"
    echo ""
    echo "示例:"
    echo "  $0                        # 使用默认设置启动 (SSE, 0.0.0.0:8000)"
    echo "  $0 -t stdio               # 使用STDIO传输协议启动"
    echo "  $0 -d                     # 部署模式，安装依赖并配置系统服务"
    echo "  $0 -d --production        # 生产环境部署"
    echo "  $0 -r                     # 重新部署，重新配置并重启服务"
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
        -r|--redeploy)
            REDEPLOY=true
            DEPLOY_MODE="deploy"  # 重新部署隐含部署模式
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
        pip install -r requirements.txt
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

# 修补server.py文件，确保服务绑定到0.0.0.0
patch_server_py() {
    echo -e "${YELLOW}修补server.py文件，确保服务绑定到所有网络接口...${NC}"
    
    if [ ! -f "server.py" ]; then
        echo -e "${RED}错误: 找不到server.py文件${NC}"
        return 1
    fi
    
    # 创建备份
    cp server.py server.py.bak
    
    # 修补文件，确保服务总是监听0.0.0.0
    python3 -c "
import re, sys

with open('server.py', 'r') as f:
    content = f.read()

# 在run_server函数开始处添加检查，确保host是0.0.0.0
content = re.sub(
    r'(def run_server.*?\n\s+try:)',
    r'\\1\n        # 确保host是0.0.0.0以允许外部访问\n        if host != \"0.0.0.0\":\n            logger.warning(f\"主机地址已从 {host} 更改为 0.0.0.0 以允许外部访问\")\n            print(f\"警告: 主机地址已从 {host} 更改为 0.0.0.0 以允许外部访问\", file=sys.stderr)\n            host = \"0.0.0.0\"',
    content
)

# 修改SSE传输部分，强制使用0.0.0.0
content = re.sub(
    r'(elif transport == \'sse\':.+?\n\s+print.+?\n\s+logger.+?\n)',
    r'\\1\n            # 强制设置环境变量确保监听在0.0.0.0\n            os.environ[\"MCP_SSE_HOST\"] = \"0.0.0.0\"\n            os.environ[\"MCP_SSE_PORT\"] = str(port)',
    content
)

# 修改传参方式，明确指定0.0.0.0
content = re.sub(
    r'(if \'host\' in run_params and \'port\' in run_params:.+?\n\s+)mcp.run\(transport=transport, host=host, port=port\)',
    r'\\1mcp.run(transport=transport, host=\"0.0.0.0\", port=port)',
    content
)

# 修改streamable-http传输部分
content = re.sub(
    r'(elif transport == \'streamable-http\':.+?\n\s+print.+?\n\s+logger.+?\n)',
    r'\\1\n            # 强制设置环境变量确保监听在0.0.0.0\n            os.environ[\"MCP_HTTP_HOST\"] = \"0.0.0.0\"\n            os.environ[\"MCP_HTTP_PORT\"] = str(port)\n            os.environ[\"MCP_HTTP_PATH\"] = \"/mcp\"',
    content
)

content = re.sub(
    r'(if \'host\' in run_params and \'port\' in run_params and \'path\' in run_params:.+?\n\s+)mcp.run\(transport=transport, host=host, port=port, path=\'/mcp\'\)',
    r'\\1mcp.run(transport=transport, host=\"0.0.0.0\", port=port, path=\"/mcp\")',
    content
)

# 移除旧的环境变量设置代码(保留但不重复设置)
content = re.sub(
    r'(\s+# 旧版本API.+?\n)\s+os.environ\[\'MCP_SSE_HOST\'\] = host\n\s+os.environ\[\'MCP_SSE_PORT\'\] = str\(port\)',
    r'\\1',
    content
)

content = re.sub(
    r'(\s+# 旧版本API.+?\n)\s+os.environ\[\'MCP_HTTP_HOST\'\] = host\n\s+os.environ\[\'MCP_HTTP_PORT\'\] = str\(port\)\n\s+os.environ\[\'MCP_HTTP_PATH\'\] = \'/mcp\'',
    r'\\1',
    content
)

with open('server.py', 'w') as f:
    f.write(content)
"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}server.py文件修补成功!${NC}"
    else
        echo -e "${RED}server.py文件修补失败，恢复备份${NC}"
        mv server.py.bak server.py
        return 1
    fi
    
    return 0
}

# 创建适当的Nginx配置，避免冲突
setup_nginx_improved() {
    echo -e "${YELLOW}配置Nginx (改进版)...${NC}"

    # 获取charts目录的绝对路径
    CHARTS_DIR=$(pwd)/data/charts
    
    # 先停止现有Nginx服务，避免端口冲突
    if [ "$MACHINE" = "Linux" ]; then
        echo -e "${YELLOW}停止现有Nginx服务...${NC}"
        sudo systemctl stop nginx || true
    elif [ "$MACHINE" = "Mac" ]; then
        echo -e "${YELLOW}停止现有Nginx服务...${NC}"
        brew services stop nginx || true
    fi
    
    # 创建Nginx配置
    create_nginx_config() {
        local CONFIG_FILE=$1
        
        cat > "$CONFIG_FILE" << EOF
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

        # 允许所有文件类型以方便调试
        add_header Content-Type text/html;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        # 允许跨域访问
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';

        # 禁止目录列表
        autoindex off;
        
        # 文件权限
        client_body_temp_path /tmp;
        client_max_body_size 10m;
        # 确保nginx有足够权限
        dav_access user:rw group:rw all:r;
        
        # 关键修复：确保此处文件可以被访问
        allow all;
    }

    # MCP服务器代理 - 代理SSE请求到MCP服务器
    location /sse {
        proxy_pass http://127.0.0.1:$PORT/sse;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_buffering off;
    }

    # 默认页面 - 生成一个测试页面
    location = / {
        return 200 '<html><head><title>MCP HTML服务器</title></head><body><h1>MCP HTML服务器</h1><p>服务器运行正常</p><p>当前时间: <span id="time"></span></p><script>document.getElementById("time").textContent = new Date().toLocaleString();</script></body></html>';
        add_header Content-Type text/html;
    }
}
EOF
    }

    # 检测操作系统和环境
    if [ "$MACHINE" = "Linux" ]; then
        # 创建临时配置文件
        TEMP_CONF_FILE=$(mktemp)
        create_nginx_config "$TEMP_CONF_FILE"
        
        # 复制到Nginx配置目录
        NGINX_CONF_DIR="/etc/nginx/conf.d"
        sudo mkdir -p "$NGINX_CONF_DIR"
        sudo cp "$TEMP_CONF_FILE" "$NGINX_CONF_DIR/mcp_html_server.conf"
        rm "$TEMP_CONF_FILE"
        
        # 测试配置
        echo -e "${YELLOW}测试Nginx配置...${NC}"
        if sudo nginx -t; then
            # 重新加载Nginx
            echo -e "${YELLOW}启动Nginx服务...${NC}"
            sudo systemctl start nginx || sudo service nginx start
            echo -e "${GREEN}Nginx配置已更新并启动${NC}"
        else
            echo -e "${RED}Nginx配置测试失败，请检查配置文件${NC}"
        fi
    elif [ "$MACHINE" = "Mac" ]; then
        # macOS配置
        NGINX_CONF_DIR="/opt/homebrew/etc/nginx/servers"
        if [ ! -d "$NGINX_CONF_DIR" ]; then
            mkdir -p "$NGINX_CONF_DIR"
        fi
        
        create_nginx_config "$NGINX_CONF_DIR/mcp_html_server.conf"
        
        # 测试配置
        if nginx -t; then
            # 启动Nginx
            brew services start nginx
            echo -e "${GREEN}Nginx配置已更新并启动${NC}"
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
    
    # 确保服务绑定到0.0.0.0
    if [ "$HOST" != "0.0.0.0" ]; then
        echo -e "${YELLOW}警告: 在部署模式下，HOST将被设为0.0.0.0以允许外部访问${NC}"
        HOST="0.0.0.0"
    fi
    
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
Environment=MCP_SSE_HOST=0.0.0.0
Environment=MCP_SSE_PORT=$PORT
Environment=FASTMCP_HOST=0.0.0.0
ExecStart=$CURRENT_DIR/.venv/bin/python server.py --transport $TRANSPORT --host 0.0.0.0 --port $PORT
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF"
    
    # 不再创建单独的mcp-nginx服务，直接由系统管理Nginx
    
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
    
    # 直接创建测试HTML文件，避免依赖Python函数
    TEST_HTML_PATH="data/charts/test.html"
    cat > "$TEST_HTML_PATH" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>MCP测试页面</title>
    <meta charset="utf-8">
</head>
<body>
    <h1>MCP测试页面</h1>
    <p>这是一个测试页面，如果您能看到此内容，说明HTML服务器配置正确。</p>
    <p>当前时间: <span id="time"></span></p>
    <script>document.getElementById("time").textContent = new Date().toLocaleString();</script>
</body>
</html>
EOF
    
    # 修正文件权限
    chmod 755 data/charts
    chmod 644 "$TEST_HTML_PATH"
    
    # 如果是Linux，设置www-data权限
    if [ "$MACHINE" = "Linux" ]; then
        # 递归设置目录权限
        sudo chmod -R 755 data/charts
        # 递归设置文件权限
        find data/charts -type f -exec sudo chmod 644 {} \;
        # 设置目录所有者
        sudo chown -R www-data:www-data data/charts || echo "警告: 无法更改所有者，请手动执行: sudo chown -R www-data:www-data $(pwd)/data/charts"
        # 确保nginx用户可以访问整个路径
        sudo chmod 755 $(pwd)
        sudo chmod 755 $(pwd)/data
        
        # 确保nginx用户可以访问charts目录
        sudo chmod -R 755 data/charts
        sudo chmod a+r data/charts/*
    fi
    
    # 尝试获取服务器主机地址
    SERVER_HOST=$(python -c "
import sys
sys.path.append('.')
try:
    from utils.html_server import get_server_host
    host = get_server_host()
    print(host)
except Exception as e:
    print('localhost')
")
    
    TEST_URL="http://${SERVER_HOST}:${HTML_PORT}/charts/test.html"
    echo -e "${GREEN}测试HTML文件URL: $TEST_URL${NC}"
    
    echo -e "${YELLOW}尝试使用curl访问测试HTML文件...${NC}"
    curl -s -I "$TEST_URL" | head -n 1 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}测试HTML文件可以成功访问!${NC}"
    else
        echo -e "${YELLOW}无法通过HTTP访问测试HTML文件，可能需要配置Nginx${NC}"
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

# 重新部署函数 - 重新配置并重启服务
redeploy() {
    echo -e "${YELLOW}开始重新部署...${NC}"
    
    # 停止服务
    if [ "$MACHINE" = "Linux" ]; then
        echo -e "${YELLOW}停止现有服务...${NC}"
        sudo systemctl stop mcp.service || true
        sudo systemctl stop nginx || true
    elif [ "$MACHINE" = "Mac" ]; then
        echo -e "${YELLOW}停止brew服务...${NC}"
        brew services stop nginx || true
    fi
    
    # 修补server.py文件，确保绑定到0.0.0.0
    patch_server_py
    
    # 配置HTML服务器
    setup_html_server
    
    # 配置Nginx - 使用改进版函数
    setup_nginx_improved
    
    # 确保服务器绑定地址正确
    if [ "$HOST" != "0.0.0.0" ]; then
        echo -e "${YELLOW}在重新部署模式下将服务器绑定地址设为0.0.0.0${NC}"
        HOST="0.0.0.0"
    fi
    
    if [ "$MACHINE" = "Linux" ]; then
        # 重新创建systemd服务
        create_systemd_service
    else
        # 直接启动
        start_mcp
    fi
    
    echo -e "${GREEN}重新部署完成！${NC}"
    show_service_info
}

# 添加端口检查函数，在脚本结尾调用
check_ports() {
    echo -e "${YELLOW}检查端口监听状态...${NC}"
    
    if [ "$MACHINE" = "Linux" ]; then
        echo -e "${YELLOW}MCP服务器端口 ($PORT) 监听状态:${NC}"
        sudo netstat -tulpn | grep ":$PORT " || echo "端口 $PORT 未在监听!"
        
        echo -e "${YELLOW}HTML服务器端口 ($HTML_PORT) 监听状态:${NC}"
        sudo netstat -tulpn | grep ":$HTML_PORT " || echo "端口 $HTML_PORT 未在监听!"
        
        # 添加防火墙规则
        if command -v ufw &> /dev/null; then
            echo -e "${YELLOW}配置防火墙规则...${NC}"
            sudo ufw allow $PORT/tcp || true
            sudo ufw allow $HTML_PORT/tcp || true
        fi
    elif [ "$MACHINE" = "Mac" ]; then
        echo -e "${YELLOW}端口监听状态:${NC}"
        netstat -an | grep "LISTEN" | grep -E ":$PORT |:$HTML_PORT " || echo "端口未在监听!"
    fi
    
    return 0
}

# 主函数
main() {
    if [ "$REDEPLOY" = true ]; then
        redeploy
        return 0
    fi
    
    if [ "$DEPLOY_MODE" = "deploy" ]; then
        echo -e "${YELLOW}开始部署MCP服务器...${NC}"
    else
        echo -e "${YELLOW}准备启动MCP服务器...${NC}"
        
        # 即使在非部署模式下，也要提示可能需要配置的重要内容
        echo -e "${YELLOW}注意: 如需完全自动化安装和配置，请使用 -d 或 --deploy 参数${NC}"
        echo -e "${YELLOW}当前为本地模式，将尝试进行基本配置${NC}"
    fi
    
    # 检测操作系统
    detect_os
    
    # 检查依赖项
    check_dependencies
    
    # 安装系统依赖
    install_system_deps
    
    # 设置虚拟环境
    setup_venv
    
    # 修补server.py文件，确保绑定到0.0.0.0
    patch_server_py
    
    # 配置HTML服务器
    setup_html_server
    
    # 配置Nginx - 使用改进版函数
    setup_nginx_improved
    
    # 设置服务器绑定地址
    # 确保默认情况下绑定到所有接口，特别是在部署模式下
    if [ "$DEPLOY_MODE" = "deploy" ] && [ "$HOST" != "0.0.0.0" ]; then
        echo -e "${YELLOW}将服务器绑定地址设为0.0.0.0${NC}"
        HOST="0.0.0.0"
    fi
    
    # 创建systemd服务（仅在Linux部署模式下）
    create_systemd_service
    
    # 生成测试HTML文件
    generate_test_html
    
    # 启动服务
    start_mcp
    
    # 显示服务信息
    show_service_info
    
    # 检查端口监听状态
    check_ports
}

# 执行主函数
main 