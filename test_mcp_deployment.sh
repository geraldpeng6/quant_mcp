#!/bin/bash

# Test MCP deployment script
# Tests if the SSE MCP server is properly deployed by querying symbol 300888

# Default values
HOST="localhost"
PORT="8000"
SYMBOL="300888"
TIMEOUT=5

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

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
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    *)
      echo "Unknown parameter: $1"
      echo "Usage: $0 [--host hostname] [--port port] [--symbol symbol] [--timeout seconds]"
      exit 1
      ;;
  esac
done

echo -e "${YELLOW}Testing MCP SSE deployment for symbol ${SYMBOL} at http://${HOST}:${PORT}/sse${NC}"

# Create a temporary file for the response
TEMP_FILE=$(mktemp)

# Prepare the JSON request
cat > "${TEMP_FILE}.json" << EOF
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

# Function to test connection
test_connection() {
  if command -v nc >/dev/null 2>&1; then
    nc -z -w1 "$HOST" "$PORT" >/dev/null 2>&1
    return $?
  elif command -v timeout >/dev/null 2>&1; then
    timeout 1 bash -c "</dev/tcp/$HOST/$PORT" >/dev/null 2>&1
    return $?
  else
    # Fallback to curl with a quick timeout
    curl -s --connect-timeout 1 "http://$HOST:$PORT" >/dev/null 2>&1
    return $?
  fi
}

# Check if the server is running
if ! test_connection; then
  echo -e "${RED}Error: Cannot connect to MCP server at ${HOST}:${PORT}${NC}"
  echo "Make sure the server is running with: python server.py --transport sse --port ${PORT}"
  rm -f "${TEMP_FILE}" "${TEMP_FILE}.json"
  exit 1
fi

echo "Connection to MCP server successful, sending query..."

# Send the request to the SSE endpoint and capture the response
curl -s -X POST "http://${HOST}:${PORT}/sse" \
  -H "Content-Type: application/json" \
  -H "Accept: text/event-stream" \
  -d @"${TEMP_FILE}.json" \
  --max-time "$TIMEOUT" > "${TEMP_FILE}" &

CURL_PID=$!

# Wait for some data or timeout
WAITED=0
INTERVAL=1  # Using integer value to avoid arithmetic issues

# Wait for the curl process to complete or timeout
for ((i=1; i<=$TIMEOUT; i++)); do
  if ! kill -0 $CURL_PID 2>/dev/null; then
    break
  fi
  
  if [ -s "${TEMP_FILE}" ]; then
    # Check if we have a complete response
    if grep -q "data: {\"type\":\"mcp-message\",\"data\":{\"done\":true" "${TEMP_FILE}"; then
      break
    fi
  fi
  
  sleep 1
done

# If curl is still running, kill it
if kill -0 $CURL_PID 2>/dev/null; then
  kill $CURL_PID 2>/dev/null
fi

# Check for response content
if [ ! -s "${TEMP_FILE}" ]; then
  echo -e "${RED}Error: No response received from MCP server within timeout period${NC}"
  rm -f "${TEMP_FILE}" "${TEMP_FILE}.json"
  exit 1
fi

# Extract and analyze the response
echo "Response received, analyzing..."

# Check for error messages
if grep -q "\"error\":" "${TEMP_FILE}"; then
  echo -e "${RED}Error detected in response:${NC}"
  grep "\"error\":" "${TEMP_FILE}" | head -1
  rm -f "${TEMP_FILE}" "${TEMP_FILE}.json"
  exit 1
fi

# Check if we have stock info in the response
if grep -q "${SYMBOL}" "${TEMP_FILE}" && grep -q "stock_info\|股票信息\|证券名称\|股票代码\|当前价格\|涨跌幅" "${TEMP_FILE}"; then
  echo -e "${GREEN}Success: MCP SSE deployment is working correctly!${NC}"
  echo -e "${GREEN}Received valid response containing information for symbol ${SYMBOL}${NC}"
  
  # Show brief extract of response
  echo -e "${YELLOW}Response excerpt:${NC}"
  grep -A 5 "${SYMBOL}" "${TEMP_FILE}" | head -10
  
  RESULT=0
else
  echo -e "${RED}Error: Response doesn't contain expected stock information for symbol ${SYMBOL}${NC}"
  echo -e "${YELLOW}Response excerpt:${NC}"
  head -20 "${TEMP_FILE}"
  
  RESULT=1
fi

# Clean up temporary files
rm -f "${TEMP_FILE}" "${TEMP_FILE}.json"

exit $RESULT 