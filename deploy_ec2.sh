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
    echo "  --troubleshoot            运行故障诊断"
    echo ""
    echo "示例:"
    echo "  $0                        # 使用默认设置部署 (SSE, 0.0.0.0:8000)"
    echo "  $0 -t streamable-http     # 使用Streamable HTTP传输协议部署"
    echo "  $0 -p 9000 --html-port 9001   # 在端口9000上部署MCP服务器，在端口9001上部署HTML服务器"
    echo "  $0 --troubleshoot         # 运行故障诊断"
    exit 0
}

# 解析命令行参数
TROUBLESHOOT=false

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
Environment=\"MCP_ENV=production\"
Environment=\"MCP_SERVER_HOST=$PUBLIC_IP\"
Environment=\"UVICORN_HOST=0.0.0.0\"
ExecStart=$CURRENT_DIR/.venv/bin/python -c \"
import os
os.environ['HOST'] = '0.0.0.0'
os.environ['BIND'] = '0.0.0.0'
import sys
sys.path.insert(0, '$CURRENT_DIR')
from server import main
main(host='0.0.0.0', port=$PORT, transport='$TRANSPORT')
\"
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

# 主函数
main() {
    echo -e "${YELLOW}开始在EC2实例上部署MCP服务器...${NC}"
    
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
    
    # 配置HTML服务器
    setup_html_server || {
        echo -e "${YELLOW}警告: HTML服务器配置有问题，但将继续部署${NC}"
    }
    
    # 配置Nginx
    setup_nginx || {
        echo -e "${YELLOW}警告: Nginx配置有问题，但将继续部署${NC}"
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
}

# 如果只是运行故障诊断，则跳过部署过程
if [ "$TROUBLESHOOT" = true ]; then
    echo -e "${YELLOW}运行故障诊断模式...${NC}"
    run_troubleshooting
    exit 0
fi

# 执行主函数
main
