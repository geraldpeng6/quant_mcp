#!/bin/bash

# 量化交易助手一键部署脚本
# 用于在Ubuntu服务器上部署量化交易助手Web服务

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 记录脚本执行日志
LOG_FILE="deployment_$(date +%Y%m%d%H%M%S).log"
exec > >(tee -i $LOG_FILE)
exec 2>&1

# 函数：显示帮助信息
show_help() {
    echo -e "${BLUE}量化交易助手部署脚本${NC}"
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  -p, --port PORT         设置Nginx监听端口（默认: 80）"
    echo "  -s, --server-port PORT  设置MCP服务器端口（默认: 8000）"
    echo "  --no-nginx              不安装和配置Nginx"
    echo ""
}

# 解析命令行参数
NGINX_PORT=80
SERVER_PORT=8000
INSTALL_NGINX=true

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) show_help; exit 0 ;;
        -p|--port) NGINX_PORT="$2"; shift ;;
        -s|--server-port) SERVER_PORT="$2"; shift ;;
        --no-nginx) INSTALL_NGINX=false ;;
        *) echo "未知参数: $1"; show_help; exit 1 ;;
    esac
    shift
done

# 函数：检测错误并退出
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: $1${NC}"
        echo "部署失败。详情请查看日志文件: $LOG_FILE"
        exit 1
    fi
}

# 函数：输出分隔线
print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# 函数：检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查是否为Ubuntu系统
print_section "检查系统环境"
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        echo -e "${YELLOW}警告: 该脚本设计用于Ubuntu，当前系统为 $ID $VERSION_ID${NC}"
        read -p "是否继续? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "部署已取消"
            exit 1
        fi
    else
        echo -e "${GREEN}检测到Ubuntu $VERSION_ID${NC}"
    fi
else
    echo -e "${YELLOW}警告: 无法确定操作系统类型${NC}"
    read -p "是否继续? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "部署已取消"
        exit 1
    fi
fi

# 获取当前目录（量化交易助手项目目录）
PROJECT_DIR=$(pwd)
echo "项目目录: $PROJECT_DIR"

# 更新系统包
print_section "更新系统包"
sudo apt-get update
check_error "系统包更新失败"

sudo apt-get upgrade -y
check_error "系统包升级失败"

# 安装基本依赖
print_section "安装基本依赖"
sudo apt-get install -y build-essential curl wget git python3 python3-pip python3-venv
check_error "基本依赖安装失败"

# 检查Python版本
print_section "检查Python版本"
if command_exists python3; then
    PYTHON_VERSION=$(python3 --version)
    echo -e "${GREEN}已安装: $PYTHON_VERSION${NC}"
    
    # 检查Python版本是否>=3.8
    PY_MAJOR=$(python3 -c "import sys; print(sys.version_info.major)")
    PY_MINOR=$(python3 -c "import sys; print(sys.version_info.minor)")
    
    if [ "$PY_MAJOR" -lt 3 ] || ([ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 8 ]); then
        echo -e "${YELLOW}警告: 推荐使用Python 3.8或更高版本，当前版本为 $PY_MAJOR.$PY_MINOR${NC}"
        
        # 安装Python 3.8或更高版本
        echo "安装Python 3.10..."
        sudo apt-get install -y software-properties-common
        sudo add-apt-repository -y ppa:deadsnakes/ppa
        sudo apt-get update
        sudo apt-get install -y python3.10 python3.10-venv python3.10-dev
        
        # 更新默认Python
        sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1
        check_error "Python 3.10安装失败"
        
        PYTHON_VERSION=$(python3 --version)
        echo -e "${GREEN}已安装新版本: $PYTHON_VERSION${NC}"
    fi
else
    echo -e "${RED}错误: Python 3未安装${NC}"
    exit 1
fi

# 安装python3-venv（用于创建虚拟环境）
print_section "安装Python虚拟环境依赖"
sudo apt-get install -y python3-venv python3-full
check_error "Python虚拟环境依赖安装失败"

# 安装uv包管理器
print_section "安装uv包管理器"
if ! command_exists uv; then
    curl -sSf https://astral.sh/uv/install.sh | sh
    check_error "uv安装失败"
    export PATH="$HOME/.cargo/bin:$PATH"
    # 确保当前会话可以使用uv
    if ! command_exists uv; then
        source "$HOME/.cargo/env"
    fi
    echo -e "${GREEN}uv已安装${NC}"
else
    echo -e "${GREEN}uv已安装${NC}"
    # 更新uv到最新版本
    curl -sSf https://astral.sh/uv/install.sh | sh
fi

# 创建Python虚拟环境
print_section "创建Python虚拟环境"
if [ ! -d "$PROJECT_DIR/.venv" ]; then
    # 使用uv创建虚拟环境
    uv venv "$PROJECT_DIR/.venv"
    check_error "uv虚拟环境创建失败"
    echo -e "${GREEN}使用uv创建的虚拟环境已创建${NC}"
else
    echo -e "${GREEN}虚拟环境已存在${NC}"
fi

# 激活虚拟环境
source "$PROJECT_DIR/.venv/bin/activate"
check_error "虚拟环境激活失败"

# 安装项目依赖
print_section "安装项目依赖"
# 使用uv安装依赖，速度更快
echo -e "${GREEN}使用uv安装依赖...${NC}"
uv pip sync "$PROJECT_DIR/requirements.txt"
check_error "uv依赖安装失败"

# 显示已安装的包
echo -e "${BLUE}已安装的包:${NC}"
uv pip list

# 创建必要的目录和配置文件
print_section "创建必要的目录和配置文件"
mkdir -p "$PROJECT_DIR/data/logs"
mkdir -p "$PROJECT_DIR/data/klines"
mkdir -p "$PROJECT_DIR/data/charts"
mkdir -p "$PROJECT_DIR/data/temp"
mkdir -p "$PROJECT_DIR/data/config"
mkdir -p "$PROJECT_DIR/data/backtest"
mkdir -p "$PROJECT_DIR/data/templates"
mkdir -p "$PROJECT_DIR/public"

# 检查auth.json配置文件
if [ ! -f "$PROJECT_DIR/data/config/auth.json" ]; then
    # 如果不存在，创建一个示例文件
    echo '{
  "token": "your_token_here",
  "user_id": "your_user_id_here"
}' > "$PROJECT_DIR/data/config/auth.json.example"
    
    echo -e "${YELLOW}警告: 认证配置文件不存在，已创建示例文件 data/config/auth.json.example${NC}"
    echo -e "${YELLOW}请填写正确的认证信息后，复制为 data/config/auth.json${NC}"
else
    echo -e "${GREEN}认证配置文件已存在${NC}"
fi

# 创建测试用HTML文件
print_section "创建测试HTML文件"
cat > "$PROJECT_DIR/public/index.html" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>量化交易助手</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 0;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            border-radius: 10px;
            box-shadow: 0 4px 10px rgba(0,0,0,0.1);
            padding: 2rem;
            max-width: 800px;
            width: 100%;
            text-align: center;
        }
        h1 {
            color: #333;
            margin-bottom: 1rem;
        }
        .status {
            margin: 2rem 0;
            padding: 1rem;
            background-color: #f8f9fa;
            border-radius: 5px;
        }
        .success {
            color: #28a745;
        }
        .error {
            color: #dc3545;
        }
        button {
            background-color: #007bff;
            color: white;
            border: none;
            padding: 0.5rem 1rem;
            border-radius: 5px;
            cursor: pointer;
            transition: background-color 0.3s;
        }
        button:hover {
            background-color: #0069d9;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>量化交易助手</h1>
        <p>欢迎使用量化交易助手！</p>
        <div class="status">
            <h2>服务器状态</h2>
            <div id="server-status">正在检查服务器状态...</div>
        </div>
        <div class="status">
            <h2>服务器信息</h2>
            <div id="server-info">
                <p>服务器IP: <span id="server-ip">检查中...</span></p>
                <p>服务器端口: <span id="server-port">${SERVER_PORT}</span></p>
                <p>Nginx端口: <span id="nginx-port">${NGINX_PORT}</span></p>
            </div>
        </div>
        <button id="check-status">刷新状态</button>
    </div>

    <script>
        // 检查服务器状态
        function checkServerStatus() {
            const statusEl = document.getElementById('server-status');
            const ipEl = document.getElementById('server-ip');
            
            statusEl.innerHTML = '正在检查服务器状态...';
            statusEl.className = '';
            
            // 检查服务器IP
            fetch('/api/server-info')
                .then(response => response.json())
                .then(data => {
                    ipEl.textContent = data.ip || '未知';
                    return fetch('/api/status');
                })
                .then(response => {
                    if (response.ok) {
                        return response.json();
                    } else {
                        throw new Error('服务器状态检查失败');
                    }
                })
                .then(data => {
                    statusEl.textContent = '服务器运行正常 ✓';
                    statusEl.className = 'success';
                })
                .catch(error => {
                    statusEl.textContent = '服务器连接失败 ✗';
                    statusEl.className = 'error';
                    console.error('错误:', error);
                });
        }

        // 页面加载后检查状态
        document.addEventListener('DOMContentLoaded', checkServerStatus);
        
        // 点击按钮刷新状态
        document.getElementById('check-status').addEventListener('click', checkServerStatus);
    </script>
</body>
</html>
EOF

# 创建API接口脚本
cat > "$PROJECT_DIR/public/api/status" << EOF
#!/usr/bin/env python3
print("Content-type: application/json")
print("")
print('{"status":"ok","timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}')
EOF

mkdir -p "$PROJECT_DIR/public/api"
cat > "$PROJECT_DIR/public/api/server-info" << EOF
#!/usr/bin/env python3
import socket
import json
import os
import sys

print("Content-type: application/json")
print("")

try:
    # 获取主机名
    hostname = socket.gethostname()
    
    # 尝试获取本地IP
    local_ip = socket.gethostbyname(hostname)
    
    # 尝试获取公网IP
    public_ip = "未知"
    try:
        import urllib.request
        public_ip = urllib.request.urlopen('https://api.ipify.org').read().decode('utf8')
    except:
        pass
    
    # 输出JSON
    result = {
        "hostname": hostname,
        "local_ip": local_ip,
        "ip": public_ip,
        "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    }
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

chmod +x "$PROJECT_DIR/public/api/status"
chmod +x "$PROJECT_DIR/public/api/server-info"

# 安装和配置Nginx（如果需要）
if [ "$INSTALL_NGINX" = true ]; then
    print_section "安装和配置Nginx"
    
    # 检查Nginx是否已安装
    if ! command_exists nginx; then
        sudo apt-get install -y nginx
        check_error "Nginx安装失败"
    else
        echo -e "${GREEN}Nginx已安装${NC}"
    fi
    
    # 创建Nginx配置文件
    NGINX_CONF="/etc/nginx/sites-available/quantmcp"
    sudo tee $NGINX_CONF > /dev/null << EOF
server {
    listen ${NGINX_PORT};
    server_name _;
    
    root ${PROJECT_DIR}/public;
    index index.html;
    
    # 静态文件
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # API端点
    location /api/ {
        gzip off;
        fastcgi_pass unix:/var/run/fcgiwrap.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
    
    # MCP服务器代理
    location /mcp {
        proxy_pass http://127.0.0.1:${SERVER_PORT}/mcp;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_read_timeout 300;
    }
    
    # SSE服务器代理
    location /sse {
        proxy_pass http://127.0.0.1:${SERVER_PORT}/sse;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_read_timeout 300;
    }
    
    # 防止访问隐藏文件
    location ~ /\. {
        deny all;
    }
}
EOF
    
    # 安装fcgiwrap（用于执行CGI脚本）
    sudo apt-get install -y fcgiwrap
    check_error "fcgiwrap安装失败"
    
    # 启用站点配置
    sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # 检查Nginx配置
    sudo nginx -t
    check_error "Nginx配置测试失败"
    
    # 重启Nginx
    sudo systemctl restart nginx
    check_error "Nginx重启失败"
    
    # 确保Nginx开机启动
    sudo systemctl enable nginx
    check_error "设置Nginx开机启动失败"
    
    echo -e "${GREEN}Nginx已配置完成，监听端口: ${NGINX_PORT}${NC}"
else
    echo -e "${YELLOW}跳过Nginx安装和配置${NC}"
fi

# 创建一个简单的systemd服务文件
print_section "创建系统服务"
SERVICE_FILE="/etc/systemd/system/quantmcp.service"
sudo tee $SERVICE_FILE > /dev/null << EOF
[Unit]
Description=Quant MCP Server
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=${PROJECT_DIR}
ExecStart=${PROJECT_DIR}/.venv/bin/python ${PROJECT_DIR}/server.py --transport streamable-http --port ${SERVER_PORT}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 重新加载systemd配置
sudo systemctl daemon-reload
check_error "systemd配置重载失败"

# 启动服务
print_section "启动服务"
sudo systemctl start quantmcp
check_error "服务启动失败"

# 设置开机启动
sudo systemctl enable quantmcp
check_error "设置服务开机启动失败"

# 测试服务
print_section "测试服务"
sleep 5 # 等待服务启动

# 检查服务状态
SERVICE_STATUS=$(sudo systemctl is-active quantmcp)
if [ "$SERVICE_STATUS" = "active" ]; then
    echo -e "${GREEN}量化交易助手服务已成功启动${NC}"
else
    echo -e "${RED}服务启动失败，状态: $SERVICE_STATUS${NC}"
    sudo systemctl status quantmcp
    exit 1
fi

# 获取服务器IP
SERVER_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=$(curl -s https://api.ipify.org || echo "未知")

# 测试Nginx配置
if [ "$INSTALL_NGINX" = true ]; then
    # 测试Nginx是否运行
    NGINX_STATUS=$(sudo systemctl is-active nginx)
    if [ "$NGINX_STATUS" = "active" ]; then
        echo -e "${GREEN}Nginx服务运行正常${NC}"
        
        # 测试端口是否开放
        if command_exists nc; then
            if nc -z localhost $NGINX_PORT; then
                echo -e "${GREEN}Nginx端口 $NGINX_PORT 已开放${NC}"
            else
                echo -e "${RED}错误: Nginx端口 $NGINX_PORT 未开放${NC}"
            fi
        else
            sudo apt-get install -y netcat
            if nc -z localhost $NGINX_PORT; then
                echo -e "${GREEN}Nginx端口 $NGINX_PORT 已开放${NC}"
            else
                echo -e "${RED}错误: Nginx端口 $NGINX_PORT 未开放${NC}"
            fi
        fi
        
        # 测试防火墙规则
        if command_exists ufw; then
            if sudo ufw status | grep -q "Status: active"; then
                # 如果防火墙处于活动状态，检查端口是否允许
                if ! sudo ufw status | grep -q "$NGINX_PORT/tcp.*ALLOW"; then
                    echo -e "${YELLOW}警告: 防火墙可能阻止了 $NGINX_PORT 端口访问${NC}"
                    read -p "是否允许Nginx端口通过防火墙? (y/n) " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        sudo ufw allow $NGINX_PORT/tcp
                        echo -e "${GREEN}已将 $NGINX_PORT 端口添加到防火墙允许列表${NC}"
                    fi
                else
                    echo -e "${GREEN}防火墙已允许 $NGINX_PORT 端口访问${NC}"
                fi
            else
                echo -e "${GREEN}防火墙未启用，无需配置防火墙规则${NC}"
            fi
        fi
    else
        echo -e "${RED}错误: Nginx服务未运行，状态: $NGINX_STATUS${NC}"
    fi
fi

# 部署摘要
print_section "部署摘要"
echo -e "量化交易助手部署完成！"
echo -e "项目目录: ${PROJECT_DIR}"
echo -e "本地IP: ${SERVER_IP}"
echo -e "公网IP: ${PUBLIC_IP}"

if [ "$INSTALL_NGINX" = true ]; then
    echo -e "Nginx状态: $(sudo systemctl is-active nginx)"
    echo -e "Nginx端口: ${NGINX_PORT}"
    echo -e "网站URL: http://${PUBLIC_IP}:${NGINX_PORT}/"
fi

echo -e "MCP服务器状态: $(sudo systemctl is-active quantmcp)"
echo -e "MCP服务器端口: ${SERVER_PORT}"
echo -e "MCP服务器URL: http://${PUBLIC_IP}:${SERVER_PORT}/mcp"
echo -e "SSE服务器URL: http://${PUBLIC_IP}:${SERVER_PORT}/sse"

echo -e "\n${GREEN}部署完成！${NC} 部署日志已保存至 $LOG_FILE" 