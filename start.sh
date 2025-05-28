#!/bin/bash

# 一键启动MCP服务器
# 此脚本会自动检查环境，安装依赖，并启动MCP服务器

# 默认参数
TRANSPORT="sse"  # 默认使用SSE传输协议
HOST="0.0.0.0"
PORT=8000

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                显示此帮助信息"
    echo "  -t, --transport TRANSPORT 指定传输协议 (stdio, sse, streamable-http) (默认: sse)"
    echo "  -H, --host HOST           指定主机地址 (默认: 0.0.0.0)"
    echo "  -p, --port PORT           指定端口号 (默认: 8000)"
    echo ""
    echo "示例:"
    echo "  $0                        # 使用默认设置启动 (SSE, 0.0.0.0:8000)"
    echo "  $0 -t stdio               # 使用STDIO传输协议启动"
    echo "  $0 -t streamable-http     # 使用Streamable HTTP传输协议启动"
    echo "  $0 -H 127.0.0.1 -p 9000   # 在127.0.0.1:9000上启动"
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

# 设置虚拟环境
setup_venv() {
    echo -e "${YELLOW}检查虚拟环境...${NC}"

    # 检查Python是否安装
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}错误: Python3未安装，请先安装Python3${NC}"
        exit 1
    fi

    # 检查pip是否安装
    if ! command -v pip3 &> /dev/null; then
        echo -e "${RED}错误: pip3未安装，请先安装pip3${NC}"
        exit 1
    fi

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
    echo -e "${YELLOW}检查依赖...${NC}"
    if [ -f "requirements.txt" ]; then
        echo -e "${YELLOW}安装依赖...${NC}"
        pip install -r requirements.txt
    else
        echo -e "${YELLOW}未找到 requirements.txt，尝试安装基本依赖...${NC}"
        pip install mcp
    fi

    echo -e "${GREEN}环境设置完成!${NC}"
}

# 检查并配置Nginx
setup_nginx() {
    echo -e "${YELLOW}检查Nginx配置...${NC}"

    # 检查是否有root权限
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}注意: 未使用root权限运行，无法自动配置Nginx。将使用Python生成测试HTML文件。${NC}"

        # 生成测试HTML文件
        python -c "
import sys
sys.path.append('.')
from utils.html_server import generate_test_html
url = generate_test_html()
print(f'测试HTML文件已生成，URL: {url}')
"
        return
    fi

    # 检查Nginx是否已安装
    if ! command -v nginx &> /dev/null; then
        echo -e "${YELLOW}Nginx未安装，跳过Nginx配置。${NC}"
        return
    fi

    # 获取charts目录的绝对路径
    CHARTS_DIR=$(pwd)/data/charts

    # 生成Nginx配置
    echo -e "${YELLOW}生成Nginx配置...${NC}"

    # 创建配置文件
    cat > /etc/nginx/conf.d/mcp_html_server.conf << EOF
# MCP HTML服务器配置
server {
    listen 80;
    server_name _;

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
        return 200 '<html><head><title>MCP HTML服务器</title></head><body><h1>MCP HTML服务器</h1><p>服务器运行正常</p></body></html>';
        add_header Content-Type text/html;
    }
}
EOF

    # 测试Nginx配置
    echo -e "${YELLOW}测试Nginx配置...${NC}"
    nginx -t

    if [ $? -eq 0 ]; then
        # 重新加载Nginx配置
        echo -e "${YELLOW}重新加载Nginx配置...${NC}"
        nginx -s reload
        echo -e "${GREEN}Nginx配置成功!${NC}"

        # 生成测试HTML文件
        python -c "
import sys
sys.path.append('.')
from utils.html_server import generate_test_html
url = generate_test_html()
print(f'测试HTML文件已生成，URL: {url}')
"
    else
        echo -e "${RED}Nginx配置测试失败，请检查配置文件。${NC}"
    fi
}

# 主函数
main() {
    echo -e "${YELLOW}准备启动MCP服务器，使用 $TRANSPORT 传输协议...${NC}"

    # 设置环境
    setup_venv

    # 确保必要的目录存在
    mkdir -p data/logs data/klines data/charts data/temp data/config data/backtest data/templates

    # 设置Nginx
    setup_nginx

    # 测试HTML文件是否可访问
    echo -e "${YELLOW}测试HTML文件是否可访问...${NC}"
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
        curl -s -I "$TEST_URL" | head -n 1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}测试HTML文件可以成功访问!${NC}"
        else
            echo -e "${RED}无法访问测试HTML文件，请检查Nginx配置。${NC}"
        fi
    else
        echo -e "${RED}无法获取测试HTML文件URL。${NC}"
    fi

    # 根据传输协议选择不同的启动方式
    if [ "$TRANSPORT" == "stdio" ]; then
        echo -e "${GREEN}启动MCP服务器，使用STDIO传输协议${NC}"
        python server.py --transport stdio
    elif [ "$TRANSPORT" == "sse" ]; then
        echo -e "${GREEN}启动MCP服务器，使用SSE传输协议，地址: http://$HOST:$PORT/sse${NC}"
        python server.py --transport sse --host "$HOST" --port "$PORT"
    elif [ "$TRANSPORT" == "streamable-http" ]; then
        echo -e "${GREEN}启动MCP服务器，使用Streamable HTTP传输协议，地址: http://$HOST:$PORT/mcp${NC}"
        python server.py --transport streamable-http --host "$HOST" --port "$PORT"
    fi
}

# 执行主函数
main
