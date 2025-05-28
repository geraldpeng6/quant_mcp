#!/bin/bash

# 生成MCP配置文件脚本

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 确保目录存在
mkdir -p data/config

# 检查配置文件是否已存在
if [ -f "data/config/mcp_config.json" ]; then
    echo -e "${YELLOW}MCP配置文件已存在，是否覆盖? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "${YELLOW}将覆盖现有配置文件...${NC}"
    else
        echo -e "${GREEN}操作已取消${NC}"
        exit 0
    fi
fi

# 检查示例文件是否存在
if [ ! -f "data/config/mcp_config.json.example" ]; then
    echo -e "${RED}错误: 示例配置文件 data/config/mcp_config.json.example 不存在${NC}"
    exit 1
fi

# 复制示例文件并提示成功
cp data/config/mcp_config.json.example data/config/mcp_config.json
echo -e "${GREEN}MCP配置文件已生成: data/config/mcp_config.json${NC}"
echo -e "${YELLOW}请根据需要编辑配置文件中的参数${NC}"
echo ""
echo -e "配置文件内容预览:"
echo "--------------------------"
cat data/config/mcp_config.json
echo "--------------------------"
echo ""
echo -e "${GREEN}配置完成后，可以使用 './deploy_start.sh' 启动服务器${NC}"

# 设置执行权限
chmod +x data/config/mcp_config.json

exit 0 