#!/bin/bash
set -e

# Cast Application - Startup Script
# Starts both WebSocket relay and Gleam server

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# WebSocket URL - can be overridden via environment
export WEBSOCKET_URL="${WEBSOCKET_URL:-ws://localhost:8080}"

npm i

echo -e "${GREEN}🚀 Starting Cast Application${NC}"
echo -e "${YELLOW}📡 WebSocket URL: $WEBSOCKET_URL${NC}"
echo ""

# Function to cleanup on exit
cleanup() {
  echo -e "${RED}🛑 Shutting down Cast...${NC}"

  # Kill all child processes
  jobs -p | xargs -r kill 2>/dev/null || true

  exit 0
}

# Trap signals
trap cleanup SIGINT SIGTERM

# Start WebSocket relay
echo -e "${GREEN}▶️  Starting WebSocket relay on port 8080...${NC}"
node websocket_relay.js &
WS_PID=$!
echo "   PID: $WS_PID"

# Wait a moment for WebSocket to start
sleep 2

# Check if WebSocket relay started successfully
if ! kill -0 $WS_PID 2>/dev/null; then
  echo -e "${RED}❌ WebSocket relay failed to start!${NC}"
  exit 1
fi

# Start Gleam server
echo -e "${GREEN}▶️  Starting Gleam server on port 6767...${NC}"
gleam run &
GLEAM_PID=$!
echo "   PID: $GLEAM_PID"

# Check if Gleam started successfully
sleep 2
if ! kill -0 $GLEAM_PID 2>/dev/null; then
  echo -e "${RED}❌ Gleam server failed to start!${NC}"
  kill $WS_PID
  exit 1
fi

echo ""
echo -e "${GREEN}✅ All services started successfully!${NC}"
echo -e "${GREEN}   📱 Access at: http://localhost:6767${NC}"
echo -e "${GREEN}   🔌 WebSocket at: $WEBSOCKET_URL${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"
echo ""

# Wait for all background jobs
wait
