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

    # 创建必要的目录
    mkdir -p data/config
    mkdir -p data/charts
    mkdir -p data/logs
    mkdir -p data/templates

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

    # 设置正确的文件权限
    CURRENT_DIR=$(pwd)
    CHARTS_DIR="$CURRENT_DIR/data/charts"

    # 确保目录有正确的权限
    sudo chmod -R 755 "$CHARTS_DIR"

    # 确保test.html文件有正确的权限
    if [ -f "$CHARTS_DIR/test.html" ]; then
        sudo chmod 644 "$CHARTS_DIR/test.html"
    fi

    # 确保Nginx用户可以访问这些文件
    NGINX_USER=$(ps aux | grep -E 'nginx.*master' | grep -v grep | awk '{print $1}')
    if [ -z "$NGINX_USER" ]; then
        NGINX_USER="www-data"  # 默认Nginx用户
    fi

    echo -e "${YELLOW}Nginx运行用户: $NGINX_USER${NC}"

    # 将Nginx用户添加到当前用户组
    sudo usermod -a -G $(whoami) $NGINX_USER

    # 确保目录路径上的所有目录都有执行权限
    # 处理root用户的特殊情况
    if [ "$NGINX_USER" = "root" ]; then
        # root用户的主目录通常是/root而不是/home/root
        sudo chmod 755 /root 2>/dev/null || true
    else
        # 非root用户，尝试设置/home/username
        sudo chmod 755 /home/$NGINX_USER 2>/dev/null || true
    fi

    # 始终设置当前工作目录的权限
    sudo chmod 755 "$CURRENT_DIR"
    sudo chmod 755 "$CURRENT_DIR/data"

    echo -e "${GREEN}HTML服务器配置完成!${NC}"
}

# 配置Nginx
setup_nginx() {
    echo -e "${YELLOW}配置Nginx...${NC}"

    # 设置环境变量
    export MCP_ENV="production"

    # 获取当前目录
    CURRENT_DIR=$(pwd)
    CHARTS_DIR="$CURRENT_DIR/data/charts"

    # 创建Nginx配置文件
    sudo bash -c "cat > /etc/nginx/conf.d/mcp_html_server.conf << EOF
# MCP HTML服务器配置
server {
    listen $HTML_PORT;
    server_name _;

    # 允许跨域访问
    add_header 'Access-Control-Allow-Origin' '*';
    add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';

    # 禁止访问隐藏文件
    location ~ /\\\\. {
        deny all;
    }

    # 静态文件服务
    location /charts/ {
        alias $CHARTS_DIR/;

        # 只允许访问HTML文件
        location ~* \\\\.(html)\$ {
            add_header Content-Type text/html;
            add_header Cache-Control 'no-cache, no-store, must-revalidate';
            # 允许跨域访问
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
        }

        # 禁止目录列表
        autoindex off;

        # 禁止访问其他类型的文件
        location ~* \\\\.(php|py|js|json|txt|log|ini|conf)\$ {
            deny all;
        }
    }

    # 默认页面
    location = / {
        return 200 '<html><head><title>MCP HTML服务器</title></head><body><h1>MCP HTML服务器</h1><p>服务器运行正常</p><p>当前时间: <span id=\"time\"></span></p><script>document.getElementById(\"time\").textContent = new Date().toLocaleString();</script></body></html>';
        add_header Content-Type text/html;
    }
}
EOF"

    # 测试Nginx配置
    sudo nginx -t

    # 重启Nginx
    sudo systemctl restart nginx

    # 确保防火墙允许HTML服务器端口
    if command -v ufw &> /dev/null; then
        echo -e "${YELLOW}配置防火墙规则...${NC}"
        sudo ufw allow $HTML_PORT/tcp
        echo -e "${GREEN}防火墙规则已添加!${NC}"
    fi

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

    # 等待服务启动
    sleep 3

    # 检查服务状态
    echo -e "${YELLOW}Nginx状态:${NC}"
    sudo systemctl status nginx --no-pager

    echo -e "${YELLOW}MCP服务状态:${NC}"
    sudo systemctl status mcp.service --no-pager

    # 检查Nginx是否正在监听端口
    echo -e "${YELLOW}检查Nginx端口:${NC}"
    
    # 先尝试使用ss命令（大多数现代Linux发行版都有）
    if command -v ss &> /dev/null; then
        echo -e "${YELLOW}使用ss命令检查:${NC}"
        sudo ss -tulpn | grep nginx
    # 再尝试使用lsof命令
    elif command -v lsof &> /dev/null; then
        echo -e "${YELLOW}使用lsof命令检查:${NC}"
        sudo lsof -i -P -n | grep nginx
    # 最后尝试使用netstat命令
    elif command -v netstat &> /dev/null; then
        echo -e "${YELLOW}使用netstat命令检查:${NC}"
        sudo netstat -tulpn | grep nginx
    # 如果都不可用，尝试安装net-tools
    else
        echo -e "${YELLOW}未找到网络检查工具，尝试安装net-tools...${NC}"
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y net-tools
            if command -v netstat &> /dev/null; then
                echo -e "${GREEN}net-tools安装成功，使用netstat检查:${NC}"
                sudo netstat -tulpn | grep nginx
            else
                echo -e "${RED}无法安装网络检查工具，跳过端口检查${NC}"
            fi
        elif command -v yum &> /dev/null; then
            sudo yum install -y net-tools
            if command -v netstat &> /dev/null; then
                echo -e "${GREEN}net-tools安装成功，使用netstat检查:${NC}"
                sudo netstat -tulpn | grep nginx
            else
                echo -e "${RED}无法安装网络检查工具，跳过端口检查${NC}"
            fi
        else
            echo -e "${RED}未找到包管理器，无法安装网络检查工具，跳过端口检查${NC}"
            echo -e "${YELLOW}可以使用以下命令手动检查Nginx配置:${NC}"
            echo -e "${YELLOW}sudo nginx -T | grep listen${NC}"
        fi
    fi

    # 测试HTML服务器
    echo -e "${YELLOW}测试HTML服务器...${NC}"
    CURRENT_DIR=$(pwd)
    CHARTS_DIR="$CURRENT_DIR/data/charts"
    TEST_HTML="$CHARTS_DIR/test.html"

    # 确保test.html文件存在并有正确的权限
    if [ -f "$TEST_HTML" ]; then
        echo -e "${GREEN}测试文件存在: $TEST_HTML${NC}"
        
        # 查看Nginx错误日志以便诊断
        echo -e "${YELLOW}检查Nginx错误日志:${NC}"
        sudo tail -n 10 /var/log/nginx/error.log
        
        # 诊断Nginx配置
        echo -e "${YELLOW}检查Nginx配置:${NC}"
        sudo nginx -T | grep -A 10 "charts/"
        
        # 修正文件权限问题
        echo -e "${YELLOW}设置正确的文件权限...${NC}"
        
        # 确保charts目录存在并可访问
        sudo mkdir -p "$CHARTS_DIR"
        
        # 设置目录所有权和权限，确保Nginx可以访问
        sudo chmod -R 755 "$CURRENT_DIR"
        sudo chmod -R 755 "$CURRENT_DIR/data"
        sudo chmod -R 755 "$CHARTS_DIR"
        sudo chmod 644 "$TEST_HTML"
        
        # 如果Nginx作为root运行，这通常不是权限问题，可能是配置问题
        NGINX_USER=$(ps aux | grep -E 'nginx.*master' | grep -v grep | awk '{print $1}')
        if [ "$NGINX_USER" = "root" ]; then
            echo -e "${YELLOW}Nginx作为root运行，修改所有权...${NC}"
            # 对于root用户，设置文件所有权为root
            sudo chown -R root:root "$CHARTS_DIR"
        else
            echo -e "${YELLOW}Nginx作为$NGINX_USER运行，修改所有权...${NC}"
            # 对于非root用户，设置文件所有权为Nginx用户
            sudo chown -R $NGINX_USER:$NGINX_USER "$CHARTS_DIR"
        fi
        
        # 显示文件权限以便诊断
        echo -e "${YELLOW}文件权限:${NC}"
        ls -la "$CHARTS_DIR"
        ls -la "$TEST_HTML"
        
        # 重新配置Nginx
        echo -e "${YELLOW}更新Nginx配置...${NC}"
        
        # 创建更简单的Nginx配置，专注于解决403问题
        sudo bash -c "cat > /etc/nginx/conf.d/mcp_html_server.conf << EOF
# MCP HTML服务器配置
server {
    listen $HTML_PORT;
    server_name _;
    
    # 启用调试日志
    error_log /var/log/nginx/mcp_error.log debug;
    
    # 允许跨域访问
    add_header 'Access-Control-Allow-Origin' '*';
    add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
    
    # 静态文件服务 - 使用绝对路径
    location /charts/ {
        alias $CHARTS_DIR/;
        autoindex off;
        
        # 允许访问所有文件类型
        types { text/html html htm; }
        default_type text/html;
        
        # 调试信息
        add_header X-Debug-Path \$request_filename;
        add_header X-Alias-Path $CHARTS_DIR/;
        
        # 禁用访问限制
        allow all;
    }
    
    # 默认页面
    location = / {
        return 200 '<html><head><title>MCP HTML服务器</title></head><body><h1>MCP HTML服务器</h1><p>服务器运行正常</p></body></html>';
        add_header Content-Type text/html;
    }
}
EOF"
        
        # 测试Nginx配置
        sudo nginx -t
        
        # 重启Nginx
        sudo systemctl restart nginx
        
        # 确保防火墙允许HTML服务器端口
        if command -v ufw &> /dev/null; then
            sudo ufw allow $HTML_PORT/tcp
        fi
        
        # 等待Nginx重启
        sleep 3
        
        # 再次尝试访问
        echo -e "${YELLOW}再次测试HTML文件访问...${NC}"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$HTML_PORT/charts/test.html)
        if [ "$HTTP_CODE" == "200" ]; then
            echo -e "${GREEN}测试HTML文件可以成功访问!${NC}"
        else
            echo -e "${RED}测试HTML文件仍然无法访问，状态码: $HTTP_CODE${NC}"
            echo -e "${YELLOW}查看详细错误日志:${NC}"
            sudo tail -n 20 /var/log/nginx/mcp_error.log
            sudo tail -n 20 /var/log/nginx/error.log
            
            # 创建测试用的简单HTML文件
            echo -e "${YELLOW}创建简单测试文件...${NC}"
            echo "<html><body><h1>测试页面</h1><p>这是一个测试页面</p></body></html>" | sudo tee "$CHARTS_DIR/simple_test.html" > /dev/null
            sudo chmod 644 "$CHARTS_DIR/simple_test.html"
            
            # 再次尝试访问简单测试文件
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$HTML_PORT/charts/simple_test.html)
            if [ "$HTTP_CODE" == "200" ]; then
                echo -e "${GREEN}简单测试HTML文件可以成功访问!${NC}"
            else
                echo -e "${RED}简单测试HTML文件仍然无法访问，状态码: $HTTP_CODE${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}测试文件不存在，尝试重新生成...${NC}"
        # 重新生成测试HTML文件
        export MCP_ENV="production"
        python -c "
import sys
sys.path.append('.')
from utils.html_server import generate_test_html
url = generate_test_html()
print(f'测试HTML文件已生成，URL: {url}')
"
        # 设置正确的权限
        if [ -f "$TEST_HTML" ]; then
            sudo chmod 644 "$TEST_HTML"
            echo -e "${GREEN}测试文件已重新生成: $TEST_HTML${NC}"
        fi
    fi

    echo -e "${GREEN}服务已启动!${NC}"
}

# 显示服务信息
show_service_info() {
    echo -e "${YELLOW}获取服务信息...${NC}"

    # 获取公网IP (使用通用方法)
    PUBLIC_IP=""
    
    # 尝试多种通用外部服务获取公网IP
    IP_SERVICES=(
        "ifconfig.me"
        "checkip.amazonaws.com"
        "ipinfo.io/ip"
        "api.ipify.org"
        "icanhazip.com"
        "ident.me"
        "ipecho.net/plain"
    )
    
    for service in "${IP_SERVICES[@]}"; do
        echo -e "${YELLOW}尝试从 $service 获取公网IP...${NC}"
        IP_RESULT=$(curl -s $service 2>/dev/null)
        
        # 验证返回结果是否为有效IP格式
        if [[ $IP_RESULT =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            PUBLIC_IP=$IP_RESULT
            echo -e "${GREEN}成功从 $service 获取IP: $PUBLIC_IP${NC}"
            break
        fi
    done
    
    # 如果外部服务都失败，尝试本地网络接口
    if [ -z "$PUBLIC_IP" ]; then
        echo -e "${YELLOW}尝试获取本地IP...${NC}"
        PUBLIC_IP=$(hostname -I | awk '{print $1}')
        echo -e "${YELLOW}使用本地IP: $PUBLIC_IP (注意：这可能不是公网IP)${NC}"
    fi

    # 如果仍无法获取，提示手动输入
    if [ -z "$PUBLIC_IP" ] || [[ "$PUBLIC_IP" == *"DOCTYPE"* ]] || [[ "$PUBLIC_IP" == *"Unauthorized"* ]]; then
        echo -e "${RED}无法自动获取公网IP地址，请手动输入:${NC}"
        read -p "请输入服务器的公网IP地址: " PUBLIC_IP
    fi
    
    # 显示警告如果可能不是公网IP
    if [[ $PUBLIC_IP =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.) ]]; then
        echo -e "${RED}警告: $PUBLIC_IP 似乎是内网IP地址，外部网络可能无法访问!${NC}"
    fi

    echo -e "${GREEN}部署完成!${NC}"
    echo -e "${GREEN}MCP服务器地址: http://$PUBLIC_IP:$PORT${NC}"
    if [ "$TRANSPORT" == "sse" ]; then
        echo -e "${GREEN}MCP服务器SSE端点: http://$PUBLIC_IP:$PORT/sse${NC}"
    elif [ "$TRANSPORT" == "streamable-http" ]; then
        echo -e "${GREEN}MCP服务器HTTP端点: http://$PUBLIC_IP:$PORT/mcp${NC}"
    fi
    echo -e "${GREEN}HTML服务器地址: http://$PUBLIC_IP:$HTML_PORT${NC}"
    echo -e "${GREEN}测试HTML页面: http://$PUBLIC_IP:$HTML_PORT/charts/test.html${NC}"

    # 检查EC2安全组设置
    echo -e "${YELLOW}重要提示:${NC}"
    echo -e "${YELLOW}1. 请确保EC2安全组已开放以下端口:${NC}"
    echo -e "${YELLOW}   - $PORT (MCP服务器端口)${NC}"
    echo -e "${YELLOW}   - $HTML_PORT (HTML服务器端口)${NC}"
    echo -e "${YELLOW}2. 如果无法从外部访问，请检查:${NC}"
    echo -e "${YELLOW}   - EC2安全组设置${NC}"
    echo -e "${YELLOW}   - 防火墙规则: sudo ufw status${NC}"
    echo -e "${YELLOW}   - Nginx错误日志: sudo tail -f /var/log/nginx/error.log${NC}"
    echo -e "${YELLOW}   - MCP服务日志: sudo journalctl -u mcp.service -f${NC}"

    # 测试外部访问
    echo -e "${YELLOW}测试外部访问...${NC}"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$PUBLIC_IP:$HTML_PORT/charts/test.html)
    if [ "$HTTP_CODE" == "200" ]; then
        echo -e "${GREEN}测试HTML文件可以从公网IP成功访问!${NC}"
    else
        echo -e "${YELLOW}无法从公网IP访问测试HTML文件，状态码: $HTTP_CODE${NC}"
        echo -e "${YELLOW}这可能是因为EC2安全组未开放$HTML_PORT端口，请检查EC2安全组设置。${NC}"
    fi

    # 显示管理命令
    echo -e "${YELLOW}管理命令:${NC}"
    echo -e "${YELLOW}启动服务: sudo systemctl start mcp.service${NC}"
    echo -e "${YELLOW}停止服务: sudo systemctl stop mcp.service${NC}"
    echo -e "${YELLOW}重启服务: sudo systemctl restart mcp.service${NC}"
    echo -e "${YELLOW}查看服务状态: sudo systemctl status mcp.service${NC}"
    echo -e "${YELLOW}查看服务日志: sudo journalctl -u mcp.service -f${NC}"
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
