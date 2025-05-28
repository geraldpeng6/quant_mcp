#!/bin/bash

# 量化交易助手 MCP 服务器部署脚本

# 设置颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 输出带颜色的信息
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查Python3是否安装
check_python() {
    info "检查Python3安装..."
    if command -v python3 &>/dev/null; then
        PYTHON_CMD="python3"
        success "检测到Python3: $(python3 --version)"
    elif command -v python &>/dev/null && [[ $(python --version 2>&1) == *"Python 3"* ]]; then
        PYTHON_CMD="python"
        success "检测到Python: $(python --version)"
    else
        error "未检测到Python3，请先安装Python3"
        exit 1
    fi
}

# 检查pip是否安装
check_pip() {
    info "检查pip安装..."
    if command -v pip3 &>/dev/null; then
        PIP_CMD="pip3"
        success "检测到pip3: $(pip3 --version)"
    elif command -v pip &>/dev/null; then
        PIP_CMD="pip"
        success "检测到pip: $(pip --version)"
    else
        warning "未检测到pip，尝试安装pip..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update && sudo apt-get install -y python3-pip
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            brew install python3-pip
        else
            error "不支持的操作系统，请手动安装pip"
            exit 1
        fi

        if command -v pip3 &>/dev/null; then
            PIP_CMD="pip3"
            success "pip3安装成功"
        else
            error "pip3安装失败，请手动安装"
            exit 1
        fi
    fi
}

# 安装依赖
install_dependencies() {
    info "安装Python依赖..."
    if [ -f "requirements.txt" ]; then
        $PIP_CMD install -r requirements.txt
        success "依赖安装完成"
    else
        warning "未找到requirements.txt文件，安装基本依赖..."
        $PIP_CMD install mcp paho-mqtt pandas numpy requests
        success "基本依赖安装完成"
    fi
}

# 创建必要的目录
create_directories() {
    info "创建必要的目录..."
    mkdir -p data/logs
    mkdir -p data/klines
    mkdir -p data/charts
    mkdir -p data/temp
    mkdir -p data/config
    mkdir -p data/backtest
    mkdir -p data/templates
    success "目录创建完成"
}

# 部署服务器
deploy_server() {
    info "开始部署服务器..."
    
    # 确保deploy_helper.py是可执行的
    chmod +x deploy_helper.py
    
    # 运行部署助手
    $PYTHON_CMD deploy_helper.py setup
    if [ $? -eq 0 ]; then
        success "服务器配置完成"
    else
        error "服务器配置失败"
    fi
}

# 启动服务器
start_server() {
    info "启动MCP服务器..."
    
    # 运行启动命令
    if [ "$1" == "--detach" ]; then
        info "后台运行服务器..."
        nohup $PYTHON_CMD deploy_helper.py start sse 8000 > data/logs/nohup.log 2>&1 &
        PID=$!
        echo $PID > data/logs/server.pid
        success "服务器已在后台启动，PID: $PID"
    else
        $PYTHON_CMD deploy_helper.py start sse 8000
    fi
}

# 停止服务器
stop_server() {
    info "停止MCP服务器..."
    if [ -f "data/logs/server.pid" ]; then
        PID=$(cat data/logs/server.pid)
        if ps -p $PID > /dev/null; then
            kill $PID
            success "服务器已停止，PID: $PID"
        else
            warning "服务器进程不存在，PID: $PID"
        fi
        rm data/logs/server.pid
    else
        warning "未找到服务器PID文件"
        # 尝试查找并杀死Python进程
        PIDS=$(ps aux | grep "[p]ython.*server.py" | awk '{print $2}')
        if [ -n "$PIDS" ]; then
            kill $PIDS
            success "已杀死服务器进程: $PIDS"
        else
            warning "未找到正在运行的服务器进程"
        fi
    fi
}

# 显示状态
show_status() {
    info "检查服务器状态..."
    
    # 运行状态命令
    $PYTHON_CMD deploy_helper.py info
}

# 主函数
main() {
    if [ "$1" == "install" ]; then
        check_python
        check_pip
        install_dependencies
        create_directories
    elif [ "$1" == "setup" ]; then
        check_python
        create_directories
        deploy_server
    elif [ "$1" == "start" ]; then
        check_python
        start_server "$2"
    elif [ "$1" == "stop" ]; then
        stop_server
    elif [ "$1" == "restart" ]; then
        stop_server
        sleep 2
        start_server "$2"
    elif [ "$1" == "status" ]; then
        check_python
        show_status
    elif [ "$1" == "deploy" ]; then
        check_python
        check_pip
        install_dependencies
        create_directories
        deploy_server
        start_server "$2"
    else
        echo "用法: $0 [命令]"
        echo "可用命令:"
        echo "  install  - 安装依赖"
        echo "  setup    - 配置服务器"
        echo "  start    - 启动服务器 (添加 --detach 选项在后台运行)"
        echo "  stop     - 停止服务器"
        echo "  restart  - 重启服务器 (添加 --detach 选项在后台运行)"
        echo "  status   - 显示服务器状态"
        echo "  deploy   - 完整部署 (安装 + 配置 + 启动)"
    fi
}

# 执行主函数
main "$@" 