#!/bin/bash
# Start both Node.js server and Python LiveKit agent

set -e

echo "🚀 Starting services..."

# Start Node.js server in background
echo "📦 Starting Node.js server..."
npm start &
NODE_PID=$!

# Wait for Node.js server to be ready
sleep 5

# Start Python LiveKit agent
echo "🤖 Starting LiveKit agent..."
python3 agent.py &
AGENT_PID=$!

# Wait for both processes
wait $NODE_PID $AGENT_PID
