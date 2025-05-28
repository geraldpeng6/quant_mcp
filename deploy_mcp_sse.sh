#!/bin/bash

# MCP SSE Deployment Script
# This script deploys the MCP server with SSE transport and tests it

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
PORT=8000
HOST=$(hostname -I | awk '{print $1}')
LOG_FILE="./data/logs/mcp_deployment_$(date +"%Y%m%d_%H%M%S").log"
TEST_SYMBOL="300888"
WAIT_TIME=5

# Create necessary directories
mkdir -p ./data/logs

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --port)
      PORT="$2"
      shift 2
      ;;
    --host)
      HOST="$2"
      shift 2
      ;;
    --wait)
      WAIT_TIME="$2"
      shift 2
      ;;
    --symbol)
      TEST_SYMBOL="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [--port PORT] [--host HOST] [--wait SECONDS] [--symbol SYMBOL]"
      echo "  --port PORT      Port to run the MCP server on (default: 8000)"
      echo "  --host HOST      Host to run the MCP server on (default: auto-detected)"
      echo "  --wait SECONDS   Time to wait for server startup (default: 5)"
      echo "  --symbol SYMBOL  Symbol to test the deployment with (default: 300888)"
      exit 0
      ;;
    *)
      echo "Unknown parameter: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo -e "${BLUE}===== MCP SSE Deployment Script =====${NC}"

# Check if Python and required packages are installed
echo -e "${YELLOW}Checking Python installation...${NC}"
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed. Please install Python 3 and try again.${NC}"
    exit 1
fi

# Check if server.py exists
if [ ! -f "server.py" ]; then
    echo -e "${RED}Error: server.py not found in the current directory.${NC}"
    exit 1
fi

# Check if test_mcp_deployment.sh exists and make it executable
if [ ! -f "test_mcp_deployment.sh" ]; then
    echo -e "${RED}Error: test_mcp_deployment.sh not found in the current directory.${NC}"
    exit 1
fi

chmod +x test_mcp_deployment.sh

# Function to kill the server process
kill_server() {
    if [ -n "$SERVER_PID" ]; then
        echo -e "${YELLOW}Stopping MCP server (PID: $SERVER_PID)...${NC}"
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
    fi
}

# Set up trap to kill the server on script exit
trap kill_server EXIT

# Start the MCP server with SSE transport in the background
echo -e "${YELLOW}Starting MCP server with SSE transport on port $PORT...${NC}"
echo -e "${YELLOW}Server logs will be saved to $LOG_FILE${NC}"

python3 server.py --transport sse --port $PORT --log-level INFO > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

# Check if server process is running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo -e "${RED}Error: Failed to start MCP server.${NC}"
    echo -e "${RED}Check the log file for details: $LOG_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}MCP server started with PID: $SERVER_PID${NC}"

# Wait for the server to initialize
echo -e "${YELLOW}Waiting $WAIT_TIME seconds for server to initialize...${NC}"
sleep $WAIT_TIME

# Check if server is still running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo -e "${RED}Error: MCP server crashed during initialization.${NC}"
    echo -e "${RED}Check the log file for details: $LOG_FILE${NC}"
    cat "$LOG_FILE" | tail -20
    exit 1
fi

# Run the test script
echo -e "${YELLOW}Testing MCP SSE deployment with symbol $TEST_SYMBOL...${NC}"
./test_mcp_deployment.sh --host "$HOST" --port "$PORT" --symbol "$TEST_SYMBOL" --timeout 10

# Check the test result
TEST_RESULT=$?
if [ $TEST_RESULT -eq 0 ]; then
    echo -e "${GREEN}MCP SSE deployment test passed successfully!${NC}"
    echo -e "${GREEN}The MCP server is running at http://$HOST:$PORT/sse${NC}"
    echo -e "${YELLOW}Server logs are saved at: $LOG_FILE${NC}"
    
    # Ask if user wants to keep the server running
    echo -e "${YELLOW}Do you want to keep the server running? [Y/n]${NC}"
    read -r KEEP_RUNNING
    
    if [[ "$KEEP_RUNNING" =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Stopping the server...${NC}"
        kill_server
        echo -e "${GREEN}Server stopped. Deployment completed.${NC}"
    else
        echo -e "${GREEN}Server is still running with PID: $SERVER_PID${NC}"
        echo -e "${YELLOW}To stop the server later, run: kill $SERVER_PID${NC}"
        
        # Detach the server process from this script
        disown $SERVER_PID
        trap - EXIT
    fi
else
    echo -e "${RED}MCP SSE deployment test failed.${NC}"
    echo -e "${RED}Check the server logs for details: $LOG_FILE${NC}"
    kill_server
    exit 1
fi

exit 0 