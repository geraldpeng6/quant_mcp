#!/bin/bash

# 安装和启动 MCP 服务器脚本
# 该脚本会安装必要的依赖并启动 MCP 服务器

# 颜色代码
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 默认配置
PORT=8000
TRANSPORT="sse"
LOG_LEVEL="DEBUG"
PYTHON_CMD="python3"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case $1 in
    --port)
      PORT="$2"
      shift 2
      ;;
    --transport)
      TRANSPORT="$2"
      shift 2
      ;;
    --log-level)
      LOG_LEVEL="$2"
      shift 2
      ;;
    --help)
      echo "用法: $0 [--port PORT] [--transport TYPE] [--log-level LEVEL]"
      echo "  --port PORT         运行 MCP 服务器的端口 (默认: 8000)"
      echo "  --transport TYPE    传输类型: stdio, sse, streamable-http (默认: sse)"
      echo "  --log-level LEVEL   日志级别: DEBUG, INFO, WARNING, ERROR (默认: DEBUG)"
      exit 0
      ;;
    *)
      echo "未知参数: $1"
      echo "使用 --help 查看使用信息"
      exit 1
      ;;
  esac
done

echo -e "${BLUE}===== MCP 服务器安装和启动脚本 =====${NC}"

# 检查 Python 是否安装
echo -e "${YELLOW}检查 Python 安装...${NC}"
if ! command -v $PYTHON_CMD &> /dev/null; then
    echo -e "${RED}错误: Python 3 未安装。请安装 Python 3 并重试。${NC}"
    exit 1
fi

echo -e "${GREEN}Python 已安装: $($PYTHON_CMD --version)${NC}"

# 创建虚拟环境（如果不存在）
if [ ! -d "venv" ]; then
    echo -e "${YELLOW}创建 Python 虚拟环境...${NC}"
    $PYTHON_CMD -m venv venv || {
        echo -e "${RED}创建虚拟环境失败。尝试安装 venv 模块...${NC}"
        sudo apt-get update && sudo apt-get install -y python3-venv
        $PYTHON_CMD -m venv venv || {
            echo -e "${RED}创建虚拟环境仍然失败。尝试不使用虚拟环境继续...${NC}"
        }
    }
fi

# 如果虚拟环境存在，则激活它
if [ -d "venv" ]; then
    echo -e "${YELLOW}激活虚拟环境...${NC}"
    source venv/bin/activate || {
        echo -e "${RED}激活虚拟环境失败。尝试不使用虚拟环境继续...${NC}"
    }
fi

# 检查和安装 MCP 包
echo -e "${YELLOW}检查 MCP 包安装...${NC}"
if ! $PYTHON_CMD -c "import mcp" &> /dev/null; then
    echo -e "${YELLOW}安装 MCP 包...${NC}"
    $PYTHON_CMD -m pip install -U mcp || {
        echo -e "${RED}安装 MCP 包失败。${NC}"
        echo -e "${YELLOW}尝试从源代码安装...${NC}"
        
        if ! command -v git &> /dev/null; then
            echo -e "${YELLOW}安装 git...${NC}"
            sudo apt-get update && sudo apt-get install -y git
        fi
        
        if [ ! -d "mcp" ]; then
            git clone https://github.com/mayfield/mcp.git || {
                echo -e "${RED}克隆 MCP 仓库失败。${NC}"
                exit 1
            }
        fi
        
        cd mcp
        $PYTHON_CMD -m pip install -e . || {
            echo -e "${RED}从源代码安装 MCP 失败。${NC}"
            cd ..
            exit 1
        }
        cd ..
    }
else
    echo -e "${GREEN}MCP 包已安装${NC}"
fi

# 检查依赖项
echo -e "${YELLOW}安装其他可能需要的依赖项...${NC}"
$PYTHON_CMD -m pip install fastapi uvicorn sse-starlette

# 创建必要的目录
echo -e "${YELLOW}创建必要的目录...${NC}"
mkdir -p data/logs data/klines data/charts data/temp data/config data/backtest data/templates 2>/dev/null || true

# 设置环境变量
if [ "$TRANSPORT" = "sse" ]; then
    export MCP_SSE_HOST="0.0.0.0"
    export MCP_SSE_PORT="$PORT"
elif [ "$TRANSPORT" = "streamable-http" ]; then
    export MCP_HTTP_HOST="0.0.0.0"
    export MCP_HTTP_PORT="$PORT"
    export MCP_HTTP_PATH="/mcp"
fi

# 获取本地 IP 地址用于显示
LOCAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")

echo -e "${YELLOW}启动 MCP 服务器，传输类型: $TRANSPORT，端口: $PORT...${NC}"
if [ "$TRANSPORT" = "sse" ]; then
    echo -e "${YELLOW}服务器将在以下地址可访问:${NC}"
    echo -e "${GREEN}http://$LOCAL_IP:$PORT/sse${NC}"
    echo -e "${GREEN}http://localhost:$PORT/sse${NC}"
elif [ "$TRANSPORT" = "streamable-http" ]; then
    echo -e "${YELLOW}服务器将在以下地址可访问:${NC}"
    echo -e "${GREEN}http://$LOCAL_IP:$PORT/mcp${NC}"
    echo -e "${GREEN}http://localhost:$PORT/mcp${NC}"
fi

echo -e "${YELLOW}按 Ctrl+C 停止服务器${NC}"

# 启动服务器
$PYTHON_CMD server.py --transport $TRANSPORT --port $PORT --host "0.0.0.0" --log-level $LOG_LEVEL

# 如果服务器退出，显示消息
echo -e "${RED}服务器已停止运行。${NC}" 