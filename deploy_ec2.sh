#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 默认参数
TRANSPORT="sse"
HOST="0.0.0.0"
PORT=8000
HTML_PORT=8081
TIMEOUT=300

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--transport) TRANSPORT="$2"; shift 2 ;;
        -H|--host) HOST="$2"; shift 2 ;;
        -p|--port) PORT="$2"; shift 2 ;;
        --html-port) HTML_PORT="$2"; shift 2 ;;
        -T|--timeout) TIMEOUT="$2"; shift 2 ;;
        -r|--restart) RESTART_ONLY=true; shift ;;
        -c|--clean) CLEAN_ONLY=true; shift ;;
        -h|--help) show_help; ;;
        *) echo "未知选项: $1"; show_help; ;;
    esac
done

# 清理端口和进程
clean_all() {
    echo -e "${GREEN}清理端口和进程...${NC}"
    sudo systemctl stop mcp.service html-server.service nginx
    sleep 2
    sudo pkill -f "python.*server.py" || true
    sudo pkill -f "python.*html_server" || true
    sudo ss -tuln | grep -E "(80|$PORT|$HTML_PORT)"
}

# 配置HTML服务器
setup_html_server() {
    echo -e "${GREEN}配置HTML服务器...${NC}"
    
    # 创建配置目录
    mkdir -p data/config
    sudo chmod 755 /home/ubuntu
    
    # 创建HTML服务器配置文件
    cat > data/config/html_server.json << EOF
{
    "server_port": $HTML_PORT,
    "server_host": "0.0.0.0",
    "charts_dir": "data/charts",
    "use_ec2_metadata": true,
    "use_public_ip": true
}
EOF
    
    # 确保charts目录存在
    mkdir -p data/charts
    chmod -R 755 data/charts
    
    # 创建HTML服务器systemd服务
    sudo bash -c "cat > /etc/systemd/system/html-server.service << EOF
[Unit]
Description=HTML Server
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$(pwd)
Environment=MCP_ENV=production
# Use a wrapper script to determine and set the public IP
ExecStart=/bin/bash -c 'PUBLIC_IP=\$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com); if [ -n "\$PUBLIC_IP" ]; then export MCP_PUBLIC_IP=\$PUBLIC_IP; echo "HTML服务器使用公网IP: \$PUBLIC_IP"; else echo "警告: HTML服务器无法获取公网IP"; fi; exec $(pwd)/.venv/bin/python -m utils.html_server'
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF"
    
    sudo systemctl daemon-reload
    sudo systemctl enable html-server.service
}

# 配置Nginx
setup_nginx() {
    echo -e "${GREEN}配置Nginx...${NC}"
    
    # 移除所有可能冲突的配置
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo rm -f /etc/nginx/sites-enabled/quant_mcp
    
    # 创建简化的Nginx配置文件
    sudo bash -c "cat > /etc/nginx/sites-enabled/quant_mcp << EOF
server {
    listen 80 default_server;
    server_name _;

    # HTML服务直接转发
    location / {
        proxy_pass http://127.0.0.1:$HTML_PORT;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
    }

    # 静态文件目录
    location /charts/ {
        alias $(pwd)/data/charts/;
        autoindex on;
    }
    
    # MCP SSE endpoint
    location /sse {
        proxy_pass http://127.0.0.1:$PORT/sse;
        proxy_http_version 1.1;
        proxy_set_header Connection \"\";
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 86400s;
        chunked_transfer_encoding off;
    }

    # MCP API 终端点
    location ~ ^/(mcp|messages|tool|resource|prompt|sampler)/ {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
    }
}
EOF"

    # 测试Nginx配置
    sudo nginx -t
}

# 创建systemd服务
create_systemd_service() {
    echo -e "${GREEN}创建MCP服务...${NC}"
    
    # 创建启动脚本
    cat > $(pwd)/start_mcp.sh << EOF
#!/bin/bash
export MCP_SERVER_HOST=0.0.0.0
export MCP_SSE_HOST=0.0.0.0
export MCP_HTTP_HOST=0.0.0.0
export PYTHONPATH=$(pwd)
export UVICORN_HOST=0.0.0.0
export HOST=0.0.0.0
export UVICORN_TIMEOUT_KEEP_ALIVE=$TIMEOUT
export MCP_REQUEST_TIMEOUT=$TIMEOUT

# 设置MCP_PUBLIC_IP环境变量（用于HTML URL生成）
PUBLIC_IP=\$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)
if [ -n "\$PUBLIC_IP" ]; then
    export MCP_PUBLIC_IP=\$PUBLIC_IP
    echo "设置公网IP: \$PUBLIC_IP"
else
    echo "警告: 无法获取公网IP"
fi

cd $(pwd)
source .venv/bin/activate
echo "启动MCP服务器: $TRANSPORT $HOST $PORT (超时: ${TIMEOUT}秒)"
exec python server.py --transport $TRANSPORT --host $HOST --port $PORT --timeout $TIMEOUT
EOF

    chmod +x $(pwd)/start_mcp.sh
    
    # 创建MCP服务文件
    sudo bash -c "cat > /etc/systemd/system/mcp.service << EOF
[Unit]
Description=MCP Server
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$(pwd)
Environment=MCP_ENV=production
Environment=MCP_SERVER_HOST=0.0.0.0
Environment=MCP_SSE_HOST=0.0.0.0
Environment=MCP_HTTP_HOST=0.0.0.0
Environment=UVICORN_HOST=0.0.0.0
Environment=HOST=0.0.0.0
Environment=UVICORN_TIMEOUT_KEEP_ALIVE=$TIMEOUT
Environment=MCP_REQUEST_TIMEOUT=$TIMEOUT
# PUBLIC_IP is dynamically determined in the start script
ExecStart=$(pwd)/start_mcp.sh
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF"
    
    sudo systemctl daemon-reload
    sudo systemctl enable mcp.service
}

# 启动所有服务
start_services() {
    echo -e "${GREEN}启动所有服务...${NC}"
    
    # 停止所有服务
    sudo systemctl stop mcp.service html-server.service nginx
    sleep 2
    
    # 启动服务
    sudo systemctl start html-server.service
    sudo systemctl start mcp.service
    sudo systemctl restart nginx
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    echo -e "${GREEN}检查服务状态...${NC}"
    sudo systemctl status html-server.service --no-pager | grep Active:
    sudo systemctl status mcp.service --no-pager | grep Active:
    sudo systemctl status nginx --no-pager | grep Active:
    
    # 检查端口
    sudo ss -tuln | grep -E "(80|$PORT|$HTML_PORT)"
}

# 主函数
main() {
    echo -e "${GREEN}开始部署MCP服务器...${NC}"
    
    # 只清理
    if [ "$CLEAN_ONLY" = true ]; then
        clean_all
        exit 0
    fi
    
    # 只重启
    if [ "$RESTART_ONLY" = true ]; then
        start_services
        exit 0
    fi
    
    # 更新系统
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip python3-venv nginx curl git
    
    # 设置Python环境
    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
    
    # 配置服务
    setup_html_server
    setup_nginx
    create_systemd_service
    
    # 配置防火墙
    sudo ufw allow ssh
    sudo ufw allow $PORT/tcp
    sudo ufw allow $HTML_PORT/tcp
    sudo ufw allow 80/tcp
    if ! sudo ufw status | grep -q "Status: active"; then
        echo "y" | sudo ufw enable
    fi
    
    # 启动服务
    start_services
    
    # 显示服务信息
    PUBLIC_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)
    echo -e "${GREEN}部署完成!${NC}"
    echo -e "${GREEN}公网IP: $PUBLIC_IP${NC}"
    echo -e "${GREEN}MCP SSE端点: http://$PUBLIC_IP/sse${NC}"
    echo -e "${GREEN}HTML服务器: http://$PUBLIC_IP/${NC}"
    echo -e "${GREEN}测试页面: http://$PUBLIC_IP/charts/test.html${NC}"
    
    # 测试连接
    echo -e "${GREEN}测试SSE连接...${NC}"
    curl -v "http://127.0.0.1/sse" 2>&1 | grep -E "< HTTP|OK|event:"
}

# 执行主函数
main