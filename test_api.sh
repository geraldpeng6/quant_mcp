#!/bin/bash

# Simple script to test MCP API endpoints
# This helps diagnose if the server is correctly handling requests

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

HOST="localhost"
PORT=8000
SYMBOL="300888"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --host)
      HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --symbol)
      SYMBOL="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [--host HOST] [--port PORT] [--symbol SYMBOL]"
      exit 0
      ;;
    *)
      echo "Unknown parameter: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo -e "${BLUE}===== MCP API Test Script =====${NC}"
echo -e "${YELLOW}Testing MCP server at ${HOST}:${PORT}${NC}"

# Test server availability with a simple GET request
echo -e "\n${YELLOW}Testing basic server connectivity...${NC}"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST}:${PORT}")

if [ "$HTTP_STATUS" = "000" ]; then
  echo -e "${RED}Error: Cannot connect to server at http://${HOST}:${PORT}${NC}"
  echo "Make sure the server is running."
  exit 1
else
  echo -e "${GREEN}Server is responding with HTTP status: ${HTTP_STATUS}${NC}"
fi

# Test SSE endpoint with OPTIONS request to check allowed methods
echo -e "\n${YELLOW}Testing SSE endpoint allowed methods...${NC}"
ALLOWED_METHODS=$(curl -s -X OPTIONS -i "http://${HOST}:${PORT}/sse" | grep -i "Allow:" || echo "No Allow header found")
echo -e "Allowed methods: ${ALLOWED_METHODS}"

# Create a JSON file for the query
TEMP_FILE=$(mktemp)
cat > "${TEMP_FILE}" << EOF
{
  "type": "mcp-message",
  "data": {
    "messages": [
      {
        "role": "user",
        "content": "查询股票${SYMBOL}的信息"
      }
    ],
    "client_info": {
      "mcp_config": {
        "quant_sse": {
          "token": "test_token",
          "user_id": "test_user",
          "auto_approve_tools": ["*"]
        }
      }
    }
  }
}
EOF

# Test SSE endpoint with POST request
echo -e "\n${YELLOW}Testing SSE endpoint with POST request...${NC}"
RESPONSE_FILE="${TEMP_FILE}.response"
curl -s -X POST "http://${HOST}:${PORT}/sse" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d @"${TEMP_FILE}" \
  --max-time 3 > "${RESPONSE_FILE}"

# Check the response
if [ -s "${RESPONSE_FILE}" ]; then
  echo -e "${GREEN}Received response from SSE endpoint${NC}"
  echo -e "${YELLOW}First 5 lines of response:${NC}"
  head -5 "${RESPONSE_FILE}"
else
  echo -e "${RED}No response received from SSE endpoint${NC}"
fi

# Test MCP endpoint (alternative endpoint that might be used)
echo -e "\n${YELLOW}Testing /mcp endpoint...${NC}"
MCP_RESPONSE="${TEMP_FILE}.mcp"
curl -s -X POST "http://${HOST}:${PORT}/mcp" \
  -H "Content-Type: application/json" \
  -d @"${TEMP_FILE}" \
  --max-time 3 > "${MCP_RESPONSE}"

if [ -s "${MCP_RESPONSE}" ]; then
  echo -e "${GREEN}Received response from /mcp endpoint${NC}"
  echo -e "${YELLOW}First 5 lines of response:${NC}"
  head -5 "${MCP_RESPONSE}"
else
  echo -e "${RED}No response received from /mcp endpoint${NC}"
fi

# Clean up
rm -f "${TEMP_FILE}" "${RESPONSE_FILE}" "${MCP_RESPONSE}"

echo -e "\n${BLUE}===== API Test Complete =====${NC}"
echo -e "${YELLOW}If all tests failed, verify that the server is properly configured for SSE or HTTP transport.${NC}"
echo -e "${YELLOW}You may need to run: python server.py --transport sse --port ${PORT} --log-level DEBUG${NC}"
echo -e "${YELLOW}Or: python server.py --transport streamable-http --port ${PORT} --log-level DEBUG${NC}" 