#!/bin/bash

# MCP服务器一键部署脚本
# 此脚本用于一键部署MCP服务器，包括安装依赖、配置服务和启动服务

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
    echo "MCP服务器一键部署脚本"
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help                显示此帮助信息"
    echo "  -t, --transport TRANSPORT 指定传输协议 (stdio, sse, streamable-http) (默认: sse)"
    echo "  -H, --host HOST           指定主机地址 (默认: 0.0.0.0)"
    echo "  -p, --port PORT           指定端口号 (默认: 8000)"
    echo "  --html-port PORT          指定HTML服务器端口号 (默认: 8081)"
    echo "  --start                   仅启动服务，不进行完整部署"
    echo "  --troubleshoot            运行故障诊断"
    echo ""
    echo "示例:"
    echo "  $0                        # 使用默认设置部署 (SSE, 0.0.0.0:8000)"
    echo "  $0 -t streamable-http     # 使用Streamable HTTP传输协议部署"
    echo "  $0 -p 9000 --html-port 9001   # 在端口9000上部署MCP服务器，在端口9001上部署HTML服务器"
    echo "  $0 --start                # 仅启动服务，不进行完整部署"
    echo "  $0 --troubleshoot         # 运行故障诊断"
    exit 0
}

# 解析命令行参数
TROUBLESHOOT=false
START_ONLY=false

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
        --start)
            START_ONLY=true
            shift 1
            ;;
        --troubleshoot)
            TROUBLESHOOT=true
            shift 1
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
    echo -e "${YELLOW}检查系统依赖...${NC}"
    
    # 检查Python是否已安装
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version)
        echo -e "${GREEN}已安装Python: $PYTHON_VERSION${NC}"
    else
        echo -e "${YELLOW}Python未安装，正在安装...${NC}"
        sudo apt-get update
        sudo apt-get install -y python3 python3-pip python3-venv
    fi
    
    # 检查pip是否已安装
    if command -v pip3 &> /dev/null; then
        PIP_VERSION=$(pip3 --version)
        echo -e "${GREEN}已安装pip: $PIP_VERSION${NC}"
    else
        echo -e "${YELLOW}pip未安装，正在安装...${NC}"
        sudo apt-get update
        sudo apt-get install -y python3-pip
    fi
    
    # 检查Nginx是否已安装
    if command -v nginx &> /dev/null; then
        NGINX_VERSION=$(nginx -v 2>&1)
        echo -e "${GREEN}已安装Nginx: $NGINX_VERSION${NC}"
    else
        echo -e "${YELLOW}Nginx未安装，正在安装...${NC}"
        sudo apt-get update
        sudo apt-get install -y nginx
    fi
    
    # 检查curl是否已安装
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}curl未安装，正在安装...${NC}"
        sudo apt-get install -y curl
    fi
    
    # 检查git是否已安装
    if ! command -v git &> /dev/null; then
        echo -e "${YELLOW}git未安装，正在安装...${NC}"
        sudo apt-get install -y git
    fi
    
    echo -e "${GREEN}系统依赖检查完成!${NC}"
    return 0
}

# 设置虚拟环境
setup_venv() {
    echo -e "${YELLOW}检查Python虚拟环境...${NC}"
    
    # 检查虚拟环境是否存在
    if [ -d ".venv" ]; then
        echo -e "${GREEN}虚拟环境已存在${NC}"
        
        # 检查是否需要更新依赖
        if [ -f "requirements.txt" ]; then
            echo -e "${YELLOW}检查是否需要更新依赖...${NC}"
            
            # 询问用户是否更新依赖
            read -p "是否更新依赖? (y/n): " update_deps
            if [[ "$update_deps" == "y" || "$update_deps" == "Y" ]]; then
                # 激活虚拟环境
                source .venv/bin/activate
                
                # 安装或更新依赖
                pip install -r requirements.txt
                
                echo -e "${GREEN}依赖已更新!${NC}"
            else
                echo -e "${YELLOW}跳过依赖更新${NC}"
            fi
        else
            echo -e "${YELLOW}未找到requirements.txt，跳过依赖更新${NC}"
        fi
    else
        echo -e "${YELLOW}虚拟环境不存在，正在创建...${NC}"
        
        # 创建虚拟环境
        python3 -m venv .venv
        
        # 激活虚拟环境
        source .venv/bin/activate
        
        # 安装依赖
        if [ -f "requirements.txt" ]; then
            echo -e "${YELLOW}安装依赖...${NC}"
            pip install -r requirements.txt
        else
            echo -e "${YELLOW}未找到requirements.txt，安装基本依赖...${NC}"
            pip install mcp uvicorn fastapi
        fi
        
        echo -e "${GREEN}虚拟环境创建完成!${NC}"
    fi
    
    # 激活虚拟环境以确保后续操作使用正确的Python环境
    source .venv/bin/activate
    
    echo -e "${GREEN}Python虚拟环境设置完成!${NC}"
    return 0
}

# 配置HTML服务器
setup_html_server() {
    echo -e "${YELLOW}配置HTML服务器...${NC}"
    
    # 创建配置目录
    mkdir -p data/config data/charts
    
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
        echo -e "${YELLOW}HTML服务器配置文件已存在，尝试更新配置...${NC}"
        # 使用临时文件进行替换，确保不会损坏原始文件
        cat > data/config/html_server.json.new << EOF
{
    "server_port": $HTML_PORT,
    "charts_dir": "data/charts",
    "use_ec2_metadata": true,
    "use_public_ip": true
}
EOF
        mv data/config/html_server.json.new data/config/html_server.json
        echo -e "${GREEN}HTML服务器配置文件已更新!${NC}"
    fi
    
    # 设置环境变量
    export MCP_ENV="production"
    
    # 生成测试HTML文件
    echo -e "${YELLOW}生成测试HTML文件...${NC}"
    
    # 直接创建测试HTML文件，不依赖Python脚本
    cat > data/charts/test.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>MCP HTML服务器测试</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }
        .container { max-width: 800px; margin: 0 auto; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }
        .success { color: green; }
        .info { color: blue; }
        .server-info { background-color: #f8f9fa; padding: 10px; border-radius: 5px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>MCP HTML服务器测试</h1>
        <p class="success">如果您看到此页面，说明HTML服务器配置成功。</p>

        <div class="server-info">
            <h2>服务器信息</h2>
            <p><strong>主机地址:</strong> <span id="server-ip">$PUBLIC_IP</span></p>
            <p><strong>端口:</strong> <span id="server-port">$HTML_PORT</span></p>
            <p><strong>生成时间:</strong> <span id="time"></span></p>
        </div>

        <script>
            document.getElementById('time').textContent = new Date().toLocaleString();
        </script>
    </div>
</body>
</html>
EOF
    
    # 尝试使用Python脚本生成更高级的测试HTML文件
    python -c "
import sys
sys.path.append('.')
try:
    from utils.html_server import generate_test_html
    url = generate_test_html()
    print(f'高级测试HTML文件已生成，URL: {url}')
except Exception as e:
    print(f'警告: 无法使用Python脚本生成高级测试HTML文件: {e}')
    print('已使用基本HTML文件作为备用')
"
    
    echo -e "${GREEN}HTML服务器配置完成!${NC}"
}

# 配置Nginx
setup_nginx() {
    echo -e "${YELLOW}配置Nginx...${NC}"
    
    # 检查Nginx是否已安装
    if ! command -v nginx &> /dev/null; then
        echo -e "${YELLOW}警告: Nginx未安装，尝试安装Nginx...${NC}"
        sudo apt-get install -y nginx || {
            echo -e "${RED}错误: 无法安装Nginx，跳过Nginx配置${NC}"
            return 1
        }
    fi
    
    # 设置环境变量
    export MCP_ENV="production"
    
    # 使用Python脚本生成Nginx配置
    python -c "
import sys
sys.path.append('.')
from utils.html_server import setup_nginx
success, message = setup_nginx()
print(message)
" || {
        echo -e "${RED}错误: Nginx配置失败，尝试手动配置${NC}"
        
        # 获取当前目录和charts目录
        CURRENT_DIR=$(pwd)
        CHARTS_DIR="$CURRENT_DIR/data/charts"
        
        # 确保目录存在
        mkdir -p $CHARTS_DIR
        
        # 创建备用Nginx配置
        cat > nginx_conf_template.txt << EOF
server {
    listen $HTML_PORT;
    server_name _;

    # 允许跨域访问
    add_header 'Access-Control-Allow-Origin' '*';
    add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';

    # 静态文件服务
    location /charts/ {
        alias $CHARTS_DIR/;
        autoindex off;
    }

    # 默认页面
    location = / {
        return 200 '<html><head><title>MCP HTML服务器</title></head><body><h1>MCP HTML服务器</h1><p>服务器运行正常</p></body></html>';
        add_header Content-Type text/html;
    }
}
EOF
        
        # 复制配置文件到Nginx目录
        sudo cp nginx_conf_template.txt /etc/nginx/conf.d/mcp_html_server.conf
        
        # 测试Nginx配置
        sudo nginx -t && {
            echo -e "${GREEN}Nginx手动配置成功!${NC}"
            sudo systemctl reload nginx
        } || {
            echo -e "${RED}Nginx手动配置失败，跳过Nginx配置${NC}"
            return 1
        }
    }
    
    echo -e "${GREEN}Nginx配置完成!${NC}"
    return 0
}

# 配置Nginx反向代理
setup_nginx_proxy() {
    echo -e "${YELLOW}配置Nginx反向代理...${NC}"
    
    # 获取当前目录
    CURRENT_DIR=$(pwd)
    
    # 创建反向代理配置
    cat > /tmp/mcp_proxy.conf << EOF
server {
    listen $PORT;
    server_name _;

    # 允许跨域访问
    add_header 'Access-Control-Allow-Origin' '*';
    add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';

    # SSE端点代理
    location /sse {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 36000s;
    }

    # MCP端点代理
    location /mcp {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_buffering off;
        proxy_cache off;
    }

    # 其他路径代理
    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
    }
}
EOF
    
    # 复制配置文件到Nginx目录
    sudo cp /tmp/mcp_proxy.conf /etc/nginx/conf.d/mcp_proxy.conf
    
    # 确保Nginx配置有效
    sudo nginx -t && {
        echo -e "${GREEN}Nginx反向代理配置成功!${NC}"
        sudo systemctl reload nginx
    } || {
        echo -e "${RED}Nginx反向代理配置失败，请检查配置!${NC}"
        return 1
    }
    
    echo -e "${GREEN}Nginx反向代理配置完成!${NC}"
    return 0
}

# 检查端口是否已被占用
check_port() {
    local port=$1
    local force_kill=${2:-false}
    local pid

    echo -e "${YELLOW}检查端口 $port 是否可用...${NC}"
    
    # 使用ss命令或lsof查找占用端口的进程
    if command -v ss &> /dev/null; then
        pid=$(ss -tunlp | grep ":$port " | awk '{print $7}' | grep -o 'pid=[0-9]*' | cut -d= -f2)
    elif command -v lsof &> /dev/null; then
        pid=$(lsof -ti:$port)
    else
        echo -e "${YELLOW}警告: 无法检查端口占用，未找到ss或lsof命令${NC}"
        return
    fi
    
    if [ -n "$pid" ]; then
        echo -e "${RED}错误: 端口 $port 已被进程 $pid 占用${NC}"
        echo -e "${YELLOW}尝试终止占用进程...${NC}"
        
        # 尝试正常终止
        kill $pid 2>/dev/null
        sleep 2
        
        # 检查进程是否仍在运行
        if ps -p $pid > /dev/null; then
            echo -e "${YELLOW}进程未响应正常终止信号，尝试强制终止...${NC}"
            kill -9 $pid 2>/dev/null
            sleep 1
        fi
        
        # 再次检查端口
        if command -v ss &> /dev/null; then
            pid=$(ss -tunlp | grep ":$port " | awk '{print $7}' | grep -o 'pid=[0-9]*' | cut -d= -f2)
        elif command -v lsof &> /dev/null; then
            pid=$(lsof -ti:$port)
        fi
        
        if [ -n "$pid" ]; then
            echo -e "${RED}错误: 无法释放端口 $port，仍被进程 $pid 占用${NC}"
            exit 1
        else
            echo -e "${GREEN}成功释放端口 $port${NC}"
        fi
    else
        echo -e "${GREEN}端口 $port 可用${NC}"
    fi
}

# 获取公网IP - 直接在脚本中实现，不依赖配置文件
get_public_ip() {
    local IP=""
    
    # 检查IP是否有效（非占位符/保留IP）
    is_valid_ip() {
        local ip=$1
        # 检查是否是有效的IP格式
        if ! [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            return 1
        fi
        
        # 排除常见测试/示例IP
        if [[ $ip == "123.45.67.89" || $ip == "1.2.3.4" || $ip == "0.0.0.0" ]]; then
            return 1
        fi
        
        # 排除回环地址
        if [[ $ip == "127."* ]]; then
            return 1
        fi
        
        # 排除保留IP范围
        local ip1 ip2 ip3 ip4
        IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$ip"
        
        # 排除私有IP
        if [[ $ip1 -eq 10 || 
               ($ip1 -eq 172 && $ip2 -ge 16 && $ip2 -le 31) || 
               ($ip1 -eq 192 && $ip2 -eq 168) ]]; then
            return 1
        fi
        
        return 0
    }
    
    # 方法1: 直接使用dig查询
    if command -v dig >/dev/null 2>&1; then
        echo -e "${YELLOW}尝试使用dig获取IP...${NC}"
        IP=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
        if [[ -n "$IP" ]] && is_valid_ip "$IP"; then
            echo "$IP"
            return
        fi
    fi
    
    # 方法2: 使用外部服务
    echo -e "${YELLOW}尝试使用checkip.amazonaws.com获取IP...${NC}"
    IP=$(curl -s -m 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '\n')
    if [[ -n "$IP" ]] && is_valid_ip "$IP"; then
        echo "$IP"
        return
    fi
    
    # 方法3: 使用外部服务备选
    echo -e "${YELLOW}尝试使用ifconfig.me获取IP...${NC}"
    IP=$(curl -s -m 5 https://ifconfig.me 2>/dev/null)
    if [[ -n "$IP" ]] && is_valid_ip "$IP"; then
        echo "$IP"
        return
    fi
    
    # 方法4: 另一个备选服务
    echo -e "${YELLOW}尝试使用ipinfo.io获取IP...${NC}"
    IP=$(curl -s -m 5 https://ipinfo.io/ip 2>/dev/null)
    if [[ -n "$IP" ]] && is_valid_ip "$IP"; then
        echo "$IP"
        return
    fi
    
    # 获取本地IP
    echo -e "${YELLOW}无法获取公网IP，尝试获取本地IP...${NC}"
    if command -v hostname >/dev/null 2>&1; then
        IP=$(hostname -I | awk '{print $1}')
        if [[ -n "$IP" ]] && [[ $IP != "127.0.0.1" ]]; then
            echo "$IP"
            return
        fi
    fi
    
    # 如果所有方法都失败，返回localhost
    echo "localhost"
}

# 创建systemd服务
create_systemd_service() {
    echo -e "${YELLOW}创建systemd服务...${NC}"
    
    # 获取当前目录
    CURRENT_DIR=$(pwd)
    
    # 创建启动脚本，避免在systemd文件中使用复杂的内联Python
    cat > "$CURRENT_DIR/start_mcp.sh" << EOF
#!/bin/bash
# 设置必要的环境变量
export MCP_ENV="production"
export MCP_SERVER_HOST="0.0.0.0"
export UVICORN_HOST="0.0.0.0"
export HOST="0.0.0.0"
export BIND="0.0.0.0"

# Uvicorn特定环境变量
export UVICORN_INTERFACE="0.0.0.0"
export UVICORN_BIND="0.0.0.0"
export UVICORN_WORKERS=2

# 当前目录
CURRENT_DIR="$CURRENT_DIR"

# 激活虚拟环境
source "\$CURRENT_DIR/.venv/bin/activate"

# 设置Python路径
export PYTHONPATH="\$CURRENT_DIR:\$PYTHONPATH"

# 尝试使用不同的方法启动服务器
if [ -f "\$CURRENT_DIR/patch_uvicorn.py" ]; then
    # 使用补丁启动
    python "\$CURRENT_DIR/patch_uvicorn.py"
else
    # 直接启动
    python "\$CURRENT_DIR/server.py" --transport "$TRANSPORT" --host 0.0.0.0 --port $PORT
fi
EOF
    
    # 使启动脚本可执行
    chmod +x "$CURRENT_DIR/start_mcp.sh"
    
    # 创建更简单的systemd服务文件
    sudo bash -c "cat > /etc/systemd/system/mcp.service << EOF
[Unit]
Description=MCP Server
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$CURRENT_DIR
ExecStart=$CURRENT_DIR/start_mcp.sh
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
    sudo systemctl restart nginx || {
        echo -e "${RED}错误: 无法启动Nginx服务${NC}"
        return 1
    }
    
    # 启动MCP服务
    sudo systemctl start mcp.service || {
        echo -e "${RED}错误: 无法启动MCP服务${NC}"
        return 1
    }
    
    # 检查服务状态
    echo -e "${YELLOW}Nginx状态:${NC}"
    sudo systemctl status nginx --no-pager
    
    echo -e "${YELLOW}MCP服务状态:${NC}"
    sudo systemctl status mcp.service --no-pager
    
    echo -e "${GREEN}服务已启动!${NC}"
    return 0
}

# 显示服务信息
show_service_info() {
    echo -e "${YELLOW}获取服务信息...${NC}"
    
    # 获取公网IP - 检测真实IP，排除占位符IP
    PUBLIC_IP=$(get_public_ip)
    echo -e "${GREEN}成功获取IP: $PUBLIC_IP${NC}"
    
    echo -e "${GREEN}部署完成!${NC}"
    echo -e "${GREEN}MCP服务器地址: http://$PUBLIC_IP:$PORT${NC}"
    if [ "$TRANSPORT" == "sse" ]; then
        echo -e "${GREEN}MCP服务器SSE端点: http://$PUBLIC_IP:$PORT/sse${NC}"
    elif [ "$TRANSPORT" == "streamable-http" ]; then
        echo -e "${GREEN}MCP服务器HTTP端点: http://$PUBLIC_IP:$PORT/mcp${NC}"
    elif [ "$TRANSPORT" == "stdio" ]; then
        echo -e "${GREEN}MCP服务器使用STDIO传输协议，无网络端点${NC}"
    fi
    echo -e "${GREEN}HTML服务器地址: http://$PUBLIC_IP:$HTML_PORT${NC}"
    echo -e "${GREEN}测试HTML页面: http://$PUBLIC_IP:$HTML_PORT/charts/test.html${NC}"
}

# 配置防火墙
setup_firewall() {
    echo -e "${YELLOW}配置防火墙...${NC}"
    
    # 检查是否安装了ufw
    if command -v ufw &> /dev/null; then
        echo -e "${YELLOW}使用UFW配置防火墙...${NC}"
        
        # 允许SSH连接
        sudo ufw allow ssh
        
        # 允许MCP服务端口
        sudo ufw allow $PORT/tcp
        
        # 允许HTML服务端口
        sudo ufw allow $HTML_PORT/tcp
        
        # 如果防火墙未启用，则启用它
        if sudo ufw status | grep -q "inactive"; then
            echo -e "${YELLOW}启用UFW防火墙...${NC}"
            echo "y" | sudo ufw enable
        fi
        
        echo -e "${GREEN}UFW防火墙配置完成!${NC}"
    elif command -v iptables &> /dev/null; then
        echo -e "${YELLOW}使用iptables配置防火墙...${NC}"
        
        # 允许SSH连接
        sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        
        # 允许MCP服务端口
        sudo iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
        
        # 允许HTML服务端口
        sudo iptables -A INPUT -p tcp --dport $HTML_PORT -j ACCEPT
        
        # 保存iptables规则
        if command -v netfilter-persistent &> /dev/null; then
            sudo netfilter-persistent save
        elif command -v iptables-save &> /dev/null; then
            sudo iptables-save > /etc/iptables/rules.v4
        else
            echo -e "${YELLOW}警告: 无法保存iptables规则，可能在重启后失效${NC}"
        fi
        
        echo -e "${GREEN}iptables防火墙配置完成!${NC}"
    else
        echo -e "${YELLOW}警告: 未找到支持的防火墙工具 (ufw 或 iptables)${NC}"
    fi
    
    echo -e "${YELLOW}请确保AWS安全组允许端口 $PORT 和 $HTML_PORT 的入站流量${NC}"
}

# 检查并创建auth.json
setup_auth_config() {
    echo -e "${YELLOW}检查认证配置文件...${NC}"
    
    # 创建配置目录
    mkdir -p data/config
    
    # 如果auth.json不存在，提示用户创建
    if [ ! -f "data/config/auth.json" ]; then
        echo -e "${YELLOW}认证配置文件不存在，需要创建${NC}"
        
        # 询问用户是否创建示例配置
        read -p "是否创建示例配置文件? (y/n): " create_example
        
        if [[ "$create_example" == "y" || "$create_example" == "Y" ]]; then
            cat > data/config/auth.json << EOF
{
    "api_keys": {
        "openai": "",
        "anthropic": "",
        "google": "",
        "mistral": "",
        "xorbits": "",
        "cohere": ""
    },
    "proxy": {
        "http": "",
        "https": ""
    }
}
EOF
            echo -e "${GREEN}创建了示例配置文件 data/config/auth.json${NC}"
            echo -e "${YELLOW}请编辑配置文件并添加你的API密钥${NC}"
            
            # 询问用户是否立即编辑
            read -p "是否现在编辑配置文件? (y/n): " edit_now
            if [[ "$edit_now" == "y" || "$edit_now" == "Y" ]]; then
                # 检查可用的编辑器
                if command -v nano &> /dev/null; then
                    nano data/config/auth.json
                elif command -v vim &> /dev/null; then
                    vim data/config/auth.json
                else
                    echo -e "${YELLOW}未找到适合的编辑器，请稍后手动编辑配置文件${NC}"
                fi
            fi
        else
            echo -e "${YELLOW}请在部署后手动创建认证配置文件${NC}"
        fi
    else
        echo -e "${GREEN}认证配置文件已存在${NC}"
    fi
    
    echo -e "${GREEN}认证配置检查完成!${NC}"
    return 0
}

# 运行故障诊断
run_troubleshooting() {
    echo -e "${YELLOW}运行故障诊断...${NC}"
    
    # 检查服务状态
    echo -e "${YELLOW}检查服务状态:${NC}"
    sudo systemctl status mcp --no-pager
    sudo systemctl status nginx --no-pager
    
    # 检查端口是否开放
    echo -e "${YELLOW}检查端口是否开放:${NC}"
    if command -v ss &> /dev/null; then
        ss -tulpn | grep -E ":($PORT|$HTML_PORT)"
    elif command -v netstat &> /dev/null; then
        netstat -tulpn | grep -E ":($PORT|$HTML_PORT)"
    fi
    
    # 检查日志
    echo -e "${YELLOW}检查MCP服务日志 (最后10行):${NC}"
    sudo journalctl -u mcp -n 10 --no-pager
    
    echo -e "${YELLOW}检查Nginx日志 (最后10行):${NC}"
    sudo tail -n 10 /var/log/nginx/error.log 2>/dev/null || echo "无法读取Nginx错误日志"
    
    # 检查防火墙
    echo -e "${YELLOW}检查防火墙状态:${NC}"
    if command -v ufw &> /dev/null; then
        sudo ufw status
    elif command -v iptables &> /dev/null; then
        sudo iptables -L -n
    fi
    
    # 测试连接性
    echo -e "${YELLOW}测试本地连接性:${NC}"
    curl -s -I "http://localhost:$PORT/ping" || echo "无法连接到MCP服务器端口"
    curl -s -I "http://localhost:$HTML_PORT" || echo "无法连接到HTML服务器端口"
    
    # 如果仍然无法访问，提供解决方案
    echo -e "${YELLOW}如果仍然无法从外部访问服务，请尝试以下解决方案:${NC}"
    echo -e "1. 执行以下命令重启服务:"
    echo -e "   sudo systemctl restart mcp"
    echo -e "   sudo systemctl restart nginx"
    echo -e "2. 检查server.py文件，确保没有硬编码的主机地址 (127.0.0.1)"
    echo -e "3. 如果使用了反向代理，检查配置是否正确"
    echo -e "4. 尝试修改MCP服务定义:"
    echo -e "   sudo nano /etc/systemd/system/mcp.service"
    echo -e "   修改ExecStart行，确保使用0.0.0.0作为主机"
    echo -e "   sudo systemctl daemon-reload"
    echo -e "   sudo systemctl restart mcp"
    
    echo -e "${GREEN}故障诊断完成!${NC}"
}

# 快速启动
quick_start() {
    echo -e "${YELLOW}快速启动MCP服务器...${NC}"
    
    # 激活虚拟环境（如果存在）
    if [ -d ".venv" ]; then
        source .venv/bin/activate
    else
        echo -e "${YELLOW}警告: 虚拟环境不存在，可能导致启动失败${NC}"
        echo -e "${YELLOW}请先使用完整部署命令: $0${NC}"
        return 1
    fi
    
    # 获取公网IP
    PUBLIC_IP=$(get_public_ip)
    echo -e "${GREEN}获取IP: $PUBLIC_IP${NC}"
    
    # 设置环境变量
    export MCP_ENV="production"
    export MCP_SERVER_HOST="$PUBLIC_IP"
    
    # 检查并启动Nginx
    if systemctl is-active --quiet nginx; then
        echo -e "${GREEN}Nginx已运行${NC}"
    else
        echo -e "${YELLOW}启动Nginx...${NC}"
        sudo systemctl start nginx
    fi
    
    # 检查并重启MCP服务
    if systemctl is-active --quiet mcp; then
        echo -e "${YELLOW}重启MCP服务...${NC}"
        sudo systemctl restart mcp
    else
        echo -e "${YELLOW}启动MCP服务...${NC}"
        sudo systemctl start mcp
    fi
    
    # 显示服务状态
    echo -e "${YELLOW}MCP服务状态:${NC}"
    sudo systemctl status mcp --no-pager
    
    # 显示服务信息
    echo -e "${GREEN}MCP服务器已启动!${NC}"
    echo -e "${GREEN}MCP服务器地址: http://$PUBLIC_IP:$PORT${NC}"
    if [ "$TRANSPORT" == "sse" ]; then
        echo -e "${GREEN}MCP服务器SSE端点: http://$PUBLIC_IP:$PORT/sse${NC}"
    elif [ "$TRANSPORT" == "streamable-http" ]; then
        echo -e "${GREEN}MCP服务器HTTP端点: http://$PUBLIC_IP:$PORT/mcp${NC}"
    fi
    echo -e "${GREEN}HTML服务器地址: http://$PUBLIC_IP:$HTML_PORT${NC}"
    echo -e "${GREEN}测试HTML页面: http://$PUBLIC_IP:$HTML_PORT/charts/test.html${NC}"
    
    return 0
}

# 修补server.py文件
patch_server_py() {
    echo -e "${YELLOW}检查并修补server.py文件...${NC}"
    
    # 检查server.py是否存在
    if [ ! -f "server.py" ]; then
        echo -e "${RED}错误: server.py文件不存在!${NC}"
        return 1
    fi
    
    # 检查是否已经修补过
    if grep -q "patch_uvicorn" server.py; then
        echo -e "${GREEN}server.py已经修补过，跳过修补${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}备份原始server.py文件...${NC}"
    cp server.py server.py.bak
    
    echo -e "${YELLOW}修补server.py文件...${NC}"
    
    # 查找适合插入补丁的位置
    IMPORT_LINE=$(grep -n "import os" server.py | head -1 | cut -d: -f1)
    
    if [ -n "$IMPORT_LINE" ]; then
        # 创建补丁内容
        PATCH=$(cat << 'EOF'

# 在导入FastMCP之后，导入前设置环境变量
os.environ['UVICORN_HOST'] = '0.0.0.0'  # 强制Uvicorn绑定到0.0.0.0

# 导入monkey patch函数
import importlib
import types

# FastMCP内部可能使用的Uvicorn启动函数打补丁
def patch_uvicorn():
    """打补丁修复Uvicorn的绑定地址问题"""
    try:
        # 尝试找到uvicorn模块
        uvicorn = importlib.import_module('uvicorn')
        
        # 保存原始运行函数
        original_run = uvicorn.run
        
        # 创建一个包装函数，强制host为0.0.0.0
        def patched_run(*args, **kwargs):
            # 强制设置host为0.0.0.0
            kwargs['host'] = '0.0.0.0'
            return original_run(*args, **kwargs)
        
        # 替换原始函数
        uvicorn.run = patched_run
        print("成功打补丁修复Uvicorn绑定地址")
    except Exception as e:
        print(f"打补丁失败: {e}")

# 应用补丁
patch_uvicorn()

EOF
)
        
        # 插入补丁代码
        sed -i "${IMPORT_LINE}a\\${PATCH}" server.py
        
        # 修改run_server函数，添加环境变量设置
        RUN_SERVER_LINE=$(grep -n "def run_server" server.py | head -1 | cut -d: -f1)
        
        if [ -n "$RUN_SERVER_LINE" ]; then
            # 确定插入位置
            TRY_LINE=$(grep -n "try:" server.py | awk -v start="$RUN_SERVER_LINE" '$1 > start {print $1}' | head -1 | cut -d: -f1)
            
            if [ -n "$TRY_LINE" ]; then
                # 创建环境变量设置代码
                ENV_PATCH=$(cat << 'EOF'
    # 强制设置环境变量
    os.environ['UVICORN_HOST'] = host
    os.environ['HOST'] = host
    os.environ['BIND'] = host
    
EOF
)
                
                # 插入环境变量设置代码
                sed -i "${TRY_LINE}a\\${ENV_PATCH}" server.py
                
                echo -e "${GREEN}成功修补server.py文件!${NC}"
            else
                echo -e "${YELLOW}无法找到适合插入环境变量设置的位置，跳过此部分修补${NC}"
            fi
        else
            echo -e "${YELLOW}无法找到run_server函数，跳过此部分修补${NC}"
        fi
    else
        echo -e "${YELLOW}无法找到适合插入补丁的位置，使用替代方法...${NC}"
        
        # 创建替代补丁
        cat > patch_uvicorn.py << 'EOF'
#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
Uvicorn绑定补丁
用于修复Uvicorn绑定到127.0.0.1的问题
"""

import sys
import os

# 设置环境变量
os.environ['UVICORN_HOST'] = '0.0.0.0'
os.environ['HOST'] = '0.0.0.0'
os.environ['BIND'] = '0.0.0.0'

# 确保导入补丁
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# 打补丁
def patch_uvicorn():
    try:
        import importlib
        uvicorn = importlib.import_module('uvicorn')
        
        # 保存原始运行函数
        original_run = uvicorn.run
        
        # 创建一个包装函数，强制host为0.0.0.0
        def patched_run(*args, **kwargs):
            # 强制设置host为0.0.0.0
            kwargs['host'] = '0.0.0.0'
            return original_run(*args, **kwargs)
        
        # 替换原始函数
        uvicorn.run = patched_run
        print("成功打补丁修复Uvicorn绑定地址")
    except Exception as e:
        print(f"打补丁失败: {e}")

# 应用补丁
patch_uvicorn()

# 导入原始模块
import server
EOF
        
        chmod +x patch_uvicorn.py
        echo -e "${GREEN}创建了替代补丁文件: patch_uvicorn.py${NC}"
        echo -e "${YELLOW}请通过 'python patch_uvicorn.py' 启动服务器${NC}"
    fi
    
    return 0
}

# 主函数
main() {
    echo -e "${YELLOW}开始部署MCP服务器...${NC}"
    
    # 安装系统依赖
    install_system_deps || {
        echo -e "${RED}错误: 系统依赖安装失败，终止部署${NC}"
        exit 1
    }
    
    # 设置虚拟环境
    setup_venv || {
        echo -e "${RED}错误: 虚拟环境设置失败，终止部署${NC}"
        exit 1
    }
    
    # 获取公网IP - 在调用其他函数前获取，确保所有函数都能使用
    PUBLIC_IP=$(get_public_ip)
    if [ "$PUBLIC_IP" == "localhost" ]; then
        echo -e "${YELLOW}警告: 无法获取公网IP，将使用localhost进行部署${NC}"
        # 使用localhost继续，但这可能导致一些功能无法正常工作
    else
        echo -e "${GREEN}成功获取IP: $PUBLIC_IP${NC}"
    fi
    
    # 导出IP到环境变量，以便Python脚本使用
    export MCP_SERVER_HOST="$PUBLIC_IP"
    export MCP_ENV="production"
    
    # 修补server.py文件
    patch_server_py || {
        echo -e "${YELLOW}警告: server.py文件修补失败，服务可能无法从外部访问${NC}"
    }
    
    # 检查并创建auth.json
    setup_auth_config || {
        echo -e "${YELLOW}警告: 认证配置有问题，但将继续部署${NC}"
    }
    
    # 配置HTML服务器
    setup_html_server || {
        echo -e "${YELLOW}警告: HTML服务器配置有问题，但将继续部署${NC}"
    }
    
    # 配置Nginx
    setup_nginx || {
        echo -e "${YELLOW}警告: Nginx配置有问题，但将继续部署${NC}"
    }
    
    # 配置Nginx反向代理
    setup_nginx_proxy || {
        echo -e "${YELLOW}警告: Nginx反向代理配置有问题，可能无法从外部访问MCP服务${NC}"
    }
    
    # 检查端口是否可用
    check_port $PORT true || {
        echo -e "${RED}错误: 无法使用端口 $PORT，终止部署${NC}"
        exit 1
    }
    
    check_port $HTML_PORT true || {
        echo -e "${YELLOW}警告: 无法使用HTML端口 $HTML_PORT，HTML服务可能无法正常工作${NC}"
    }
    
    # 配置防火墙
    setup_firewall || {
        echo -e "${YELLOW}警告: 防火墙配置有问题，但将继续部署${NC}"
    }
    
    # 创建systemd服务
    create_systemd_service || {
        echo -e "${RED}错误: systemd服务创建失败，终止部署${NC}"
        exit 1
    }
    
    # 启动服务
    start_services || {
        echo -e "${RED}错误: 服务启动失败，终止部署${NC}"
        exit 1
    }
    
    # 显示服务信息
    show_service_info
    
    # 验证服务是否正常运行
    echo -e "${YELLOW}验证服务是否正常运行...${NC}"
    if curl -s "http://localhost:$PORT/ping" | grep -q "pong"; then
        echo -e "${GREEN}MCP服务器正常运行!${NC}"
    else
        echo -e "${YELLOW}警告: 无法验证MCP服务器是否正常运行，运行故障诊断...${NC}"
        run_troubleshooting
    fi
    
    echo -e "${GREEN}部署过程完成!${NC}"
    echo -e "${YELLOW}如果遇到访问问题，请执行 'sudo $0 --troubleshoot' 运行故障诊断${NC}"
    echo -e "${YELLOW}快速启动服务请使用 'sudo $0 --start'${NC}"
}

# 如果只是运行故障诊断，则跳过部署过程
if [ "$TROUBLESHOOT" = true ]; then
    echo -e "${YELLOW}运行故障诊断模式...${NC}"
    run_troubleshooting
    exit 0
fi

# 如果只是启动服务，则跳过部署过程
if [ "$START_ONLY" = true ]; then
    echo -e "${YELLOW}运行快速启动模式...${NC}"
    quick_start
    exit 0
fi

# 执行主函数
main
