#!/bin/bash

# Script to start the MCP server with streamable-http transport
# This focuses on properly configuring the server for HTTP transport

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
PORT=8000
LOG_LEVEL="INFO"
LOG_FILE="./mcp_http_$(date +"%Y%m%d_%H%M%S").log"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --port)
      PORT="$2"
      shift 2
      ;;
    --log-level)
      LOG_LEVEL="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [--port PORT] [--log-level LEVEL]"
      echo "  --port PORT        Port to run the MCP server on (default: 8000)"
      echo "  --log-level LEVEL  Log level: DEBUG, INFO, WARNING, ERROR (default: INFO)"
      exit 0
      ;;
    *)
      echo "Unknown parameter: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo -e "${BLUE}===== Starting MCP Server with HTTP Transport =====${NC}"

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed. Please install Python 3 and try again.${NC}"
    exit 1
fi

# Check if server.py exists
if [ ! -f "server.py" ]; then
    echo -e "${RED}Error: server.py not found in the current directory.${NC}"
    exit 1
fi

# Create data directories (don't fail if they already exist or can't be created)
echo -e "${YELLOW}Creating necessary directories...${NC}"
mkdir -p data/logs data/klines data/charts data/temp data/config data/backtest data/templates 2>/dev/null || true

# Set environment variables for HTTP server
export MCP_HTTP_HOST="0.0.0.0"
export MCP_HTTP_PORT="$PORT"
export MCP_HTTP_PATH="/mcp"

# Get local IP for display purposes
LOCAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")

echo -e "${YELLOW}Starting MCP server with streamable-http transport on port $PORT...${NC}"
echo -e "${YELLOW}Server logs will be saved to $LOG_FILE${NC}"
echo -e "${YELLOW}Server will be accessible at:${NC}"
echo -e "${GREEN}http://$LOCAL_IP:$PORT/mcp${NC}"
echo -e "${GREEN}http://localhost:$PORT/mcp${NC}"

echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"

# Start the server directly (not in background) to see output
python3 server.py --transport streamable-http --port $PORT --host "0.0.0.0" --log-level $LOG_LEVEL | tee "$LOG_FILE"

# This section will only execute if the server exits
echo -e "${RED}Server has stopped running.${NC}"
echo -e "${YELLOW}Logs were saved to: $LOG_FILE${NC}" 