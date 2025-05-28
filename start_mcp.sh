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
CURRENT_DIR="/home/ubuntu/quant_mcp"

# 激活虚拟环境
source "$CURRENT_DIR/.venv/bin/activate"

# 设置Python路径
export PYTHONPATH="$CURRENT_DIR:$PYTHONPATH"

# 启动服务器，明确指定主机为0.0.0.0
python "$CURRENT_DIR/server.py" --transport sse --host 0.0.0.0 --port 8000 