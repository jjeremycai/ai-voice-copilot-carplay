#!/bin/bash

# Start both the web server and agent worker
echo "🚀 Starting web server and agent worker..."

# Start agent worker in background
python agent.py &
AGENT_PID=$!
echo "✅ Agent worker started (PID: $AGENT_PID)"

# Start web server in foreground
npm start &
WEB_PID=$!
echo "✅ Web server started (PID: $WEB_PID)"

# Wait for both processes
wait -n

# Exit with status of process that exited first
exit $?
