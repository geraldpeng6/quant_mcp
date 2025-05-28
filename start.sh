#!/bin/bash

# 一键启动MCP服务器
# 此脚本会自动检查环境，安装依赖，并启动MCP服务器

# 默认参数
TRANSPORT="sse"  # 默认使用SSE传输协议
HOST="0.0.0.0"   # 默认绑定所有地址，不仅仅是localhost
PORT=8000
HTML_PORT=8081   # HTML服务器端口
FORCE_KILL=false # 是否强制杀掉占用端口的进程

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
    echo "  --html-port PORT          指定HTML服务器端口号 (默认: 8081)"
    echo "  --kill                    强制杀掉占用指定端口的进程"
    echo ""
    echo "示例:"
    echo "  $0                        # 使用默认设置启动 (SSE, 0.0.0.0:8000)"
    echo "  $0 -t stdio               # 使用STDIO传输协议启动"
    echo "  $0 -t streamable-http     # 使用Streamable HTTP传输协议启动"
    echo "  $0 -H 127.0.0.1 -p 9000   # 在127.0.0.1:9000上启动"
    echo "  $0 -p 8888 --kill         # 杀掉占用8888端口的进程并在该端口启动"
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
        --kill)
            FORCE_KILL=true
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

# 检查端口是否已被占用并处理
check_port() {
    local port=$1
    local force_kill=$2
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
        if [ "$force_kill" = true ]; then
            echo -e "${YELLOW}端口 $port 被进程 $pid 占用，尝试终止...${NC}"
            
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
                
                # 尝试查看进程信息
                echo -e "${YELLOW}尝试获取进程信息:${NC}"
                ps -f -p $pid
                
                # 如果是systemd服务，尝试识别
                if command -v systemctl &> /dev/null; then
                    echo -e "${YELLOW}检查是否是systemd服务:${NC}"
                    systemctl status | grep $pid
                fi
                
                exit 1
            else
                echo -e "${GREEN}成功释放端口 $port${NC}"
            fi
        else
            echo -e "${RED}错误: 端口 $port 已被进程 $pid 占用${NC}"
            echo -e "${YELLOW}提示: 使用 '$0 --kill' 选项来终止占用进程，或使用 '-p' 选项指定其他端口${NC}"
            exit 1
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
        
        # 排除私有IP（除非明确要求使用）
        if [[ $ip1 -eq 10 || 
               ($ip1 -eq 172 && $ip2 -ge 16 && $ip2 -le 31) || 
               ($ip1 -eq 192 && $ip2 -eq 168) ]]; then
            return 1
        fi
        
        return 0
    }
    
    echo -e "${YELLOW}尝试获取公网IP地址...${NC}"
    
    # 方法1: 直接使用dig查询
    if command -v dig >/dev/null 2>&1; then
        echo -e "${YELLOW}尝试使用dig获取IP...${NC}"
        IP=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
        if [[ -n "$IP" ]] && is_valid_ip "$IP"; then
            echo -e "${GREEN}成功使用dig获取IP: $IP${NC}"
            echo "$IP"
            return
        fi
    fi
    
    # 方法2: 使用外部服务
    echo -e "${YELLOW}尝试使用checkip.amazonaws.com获取IP...${NC}"
    IP=$(curl -s -m 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '\n')
    if [[ -n "$IP" ]] && is_valid_ip "$IP"; then
        echo -e "${GREEN}成功使用checkip.amazonaws.com获取IP: $IP${NC}"
        echo "$IP"
        return
    fi
    
    # 方法3: 使用外部服务备选
    echo -e "${YELLOW}尝试使用ifconfig.me获取IP...${NC}"
    IP=$(curl -s -m 5 https://ifconfig.me 2>/dev/null)
    if [[ -n "$IP" ]] && is_valid_ip "$IP"; then
        echo -e "${GREEN}成功使用ifconfig.me获取IP: $IP${NC}"
        echo "$IP"
        return
    fi
    
    # 方法4: 另一个备选服务
    echo -e "${YELLOW}尝试使用ipinfo.io获取IP...${NC}"
    IP=$(curl -s -m 5 https://ipinfo.io/ip 2>/dev/null)
    if [[ -n "$IP" ]] && is_valid_ip "$IP"; then
        echo -e "${GREEN}成功使用ipinfo.io获取IP: $IP${NC}"
        echo "$IP"
        return
    fi
    
    # 获取本地IP
    echo -e "${YELLOW}无法获取公网IP，尝试获取本地IP...${NC}"
    if command -v hostname >/dev/null 2>&1; then
        IP=$(hostname -I | awk '{print $1}')
        if [[ -n "$IP" ]] && [[ $IP != "127.0.0.1" ]]; then
            echo -e "${YELLOW}使用本地IP: $IP${NC}"
            echo "$IP"
            return
        fi
    fi
    
    # 如果所有方法都失败，返回localhost
    echo -e "${RED}无法获取有效IP，使用localhost${NC}"
    echo "localhost"
}

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

# 生成测试HTML文件
generate_test_html() {
    local PUBLIC_IP=$1
    local HTML_PORT=$2
    
    echo -e "${YELLOW}生成测试HTML文件...${NC}"
    
    # 确保目录存在
    mkdir -p data/charts
    
    # 生成HTML文件
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
            <p><strong>主机地址:</strong> ${PUBLIC_IP}</p>
            <p><strong>端口:</strong> ${HTML_PORT}</p>
            <p><strong>生成时间:</strong> <span id="time"></span></p>
            <p><strong>客户端IP:</strong> <span id="client-ip">正在获取...</span></p>
        </div>

        <script>
            document.getElementById('time').textContent = new Date().toLocaleString();

            // 尝试获取客户端IP
            fetch('https://api.ipify.org?format=json')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('client-ip').textContent = data.ip;
                })
                .catch(error => {
                    document.getElementById('client-ip').textContent = '无法获取';
                });
        </script>
    </div>
</body>
</html>
EOF

    echo -e "${GREEN}测试HTML文件已生成: data/charts/test.html${NC}"
    echo "http://${PUBLIC_IP}:${HTML_PORT}/charts/test.html"
}

# 配置Nginx
setup_nginx() {
    local PUBLIC_IP=$1
    local HTML_PORT=$2
    
    echo -e "${YELLOW}检查Nginx配置...${NC}"

    # 检查是否有root权限
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}注意: 未使用root权限运行，无法自动配置Nginx。${NC}"
        return
    fi

    # 检查Nginx是否已安装
    if ! command -v nginx &> /dev/null; then
        echo -e "${YELLOW}Nginx未安装，跳过Nginx配置。${NC}"
        return
    fi

    # 检查HTML端口是否被占用
    check_port $HTML_PORT $FORCE_KILL

    # 获取charts目录的绝对路径
    CHARTS_DIR=$(pwd)/data/charts

    # 生成Nginx配置
    echo -e "${YELLOW}生成Nginx配置...${NC}"

    # 创建配置文件
    cat > /etc/nginx/conf.d/mcp_html_server.conf << EOF
# MCP HTML服务器配置
server {
    listen ${HTML_PORT};
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
        alias ${CHARTS_DIR}/;

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

    # 测试Nginx配置
    echo -e "${YELLOW}测试Nginx配置...${NC}"
    nginx -t

    if [ $? -eq 0 ]; then
        # 重新加载Nginx配置
        echo -e "${YELLOW}重新加载Nginx配置...${NC}"
        nginx -s reload
        echo -e "${GREEN}Nginx配置成功!${NC}"
    else
        echo -e "${RED}Nginx配置测试失败，请检查配置文件。${NC}"
    fi
}

# 主函数
main() {
    echo -e "${YELLOW}准备启动MCP服务器，使用 $TRANSPORT 传输协议...${NC}"

    # 检查MCP服务器端口是否可用
    check_port $PORT $FORCE_KILL
    
    # 设置环境
    setup_venv

    # 确保必要的目录存在
    mkdir -p data/logs data/klines data/charts data/temp data/config data/backtest data/templates
    
    # 获取公网IP
    PUBLIC_IP=$(get_public_ip)
    echo -e "${GREEN}将使用IP: $PUBLIC_IP${NC}"
    
    # 删除可能存在的配置文件，强制使用脚本中的配置
    if [ -f "data/config/html_server.json" ]; then
        echo -e "${YELLOW}删除配置文件 data/config/html_server.json${NC}"
        rm -f data/config/html_server.json
    fi
    
    # 配置Nginx
    setup_nginx "$PUBLIC_IP" "$HTML_PORT"
    
    # 生成测试HTML文件
    TEST_URL=$(generate_test_html "$PUBLIC_IP" "$HTML_PORT")

    # 测试HTML文件是否可访问
    echo -e "${YELLOW}测试HTML文件是否可访问...${NC}"
    echo -e "${GREEN}测试HTML文件URL: $TEST_URL${NC}"
    echo -e "${YELLOW}尝试使用curl访问测试HTML文件...${NC}"
    curl -s -I "$TEST_URL" | head -n 1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}测试HTML文件可以成功访问!${NC}"
    else
        echo -e "${RED}无法访问测试HTML文件，请检查Nginx配置。${NC}"
    fi
    
    # 设置环境变量以影响Python中的IP检测
    export MCP_SERVER_HOST="$PUBLIC_IP"
    export MCP_ENV="production"

    # 根据传输协议选择不同的启动方式
    if [ "$TRANSPORT" == "stdio" ]; then
        echo -e "${GREEN}启动MCP服务器，使用STDIO传输协议${NC}"
        python server.py --transport stdio
    elif [ "$TRANSPORT" == "sse" ]; then
        echo -e "${GREEN}启动MCP服务器，使用SSE传输协议，地址: http://$PUBLIC_IP:$PORT/sse${NC}"
        python server.py --transport sse --host "$HOST" --port "$PORT"
    elif [ "$TRANSPORT" == "streamable-http" ]; then
        echo -e "${GREEN}启动MCP服务器，使用Streamable HTTP传输协议，地址: http://$PUBLIC_IP:$PORT/mcp${NC}"
        python server.py --transport streamable-http --host "$HOST" --port "$PORT"
    fi
}

# 执行主函数
main
