#!/bin/bash

# Set up library paths for LiveKit Python SDK
# Nixpacks installs libraries in various locations, we need to find them

echo "🔍 Locating C++ standard library..."

# Find libstdc++.so.6 in common locations
FOUND_LIB=""

# Check /root/.nix-profile/lib first (most common in Nixpacks)
if [ -f "/root/.nix-profile/lib/libstdc++.so.6" ]; then
  FOUND_LIB="/root/.nix-profile/lib"
  echo "✅ Found libstdc++.so.6 at: $FOUND_LIB"
fi

# Search recursively in /nix/store if not found
if [ -z "$FOUND_LIB" ]; then
  echo "🔍 Searching /nix/store recursively..."
  FOUND_LIB=$(find /nix/store -name "libstdc++.so.6" -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
  if [ -n "$FOUND_LIB" ]; then
    echo "✅ Found libstdc++.so.6 at: $FOUND_LIB"
  fi
fi

# Check standard system locations as fallback
if [ -z "$FOUND_LIB" ]; then
  for path in "/usr/lib" "/usr/lib/x86_64-linux-gnu"; do
    if [ -f "$path/libstdc++.so.6" ]; then
      FOUND_LIB="$path"
      echo "✅ Found libstdc++.so.6 at: $FOUND_LIB"
      break
    fi
  done
fi

# Set LD_LIBRARY_PATH
if [ -n "$FOUND_LIB" ]; then
  export LD_LIBRARY_PATH="$FOUND_LIB:${LD_LIBRARY_PATH:-}"
  echo "✅ LD_LIBRARY_PATH set to: $LD_LIBRARY_PATH"
else
  echo "⚠️  Warning: libstdc++.so.6 not found, using default library paths"
  echo "   LD_LIBRARY_PATH: ${LD_LIBRARY_PATH:-<not set>}"
fi

# Find Python executable (works with both Nixpacks and Metal)
PYTHON_CMD=""
if [ -f "/opt/venv/bin/python" ]; then
  PYTHON_CMD="/opt/venv/bin/python"
elif [ -f "backend/venv/bin/python" ]; then
  PYTHON_CMD="backend/venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_CMD=$(command -v python3)
elif command -v python >/dev/null 2>&1; then
  PYTHON_CMD=$(command -v python)
else
  echo "❌ Python not found! Available commands:"
  which -a python3 python 2>/dev/null || echo "  No python found"
  exit 1
fi

echo "🔍 Using Python: $PYTHON_CMD ($($PYTHON_CMD --version 2>&1 || echo 'version check failed'))"

# Verify Python can find the library (non-fatal, for debugging)
echo "🔍 Verifying Python library dependencies..."
$PYTHON_CMD -c "
import sys
import os
print(f'Python: {sys.executable}')
print(f'LD_LIBRARY_PATH: {os.environ.get(\"LD_LIBRARY_PATH\", \"<not set>\")}')
try:
    import livekit
    print('✅ LiveKit Python SDK imported successfully')
except Exception as e:
    print(f'⚠️  Warning: Failed to import LiveKit: {e}')
    print('   This may cause the agent worker to fail. Continuing anyway...')
" || echo "⚠️  Python library check had issues, but continuing..."

# Start both the web server and agent worker
echo "🚀 Starting web server and agent worker..."

# Verify LiveKit environment variables are set
echo "🔍 Verifying LiveKit environment variables..."
if [ -z "$LIVEKIT_URL" ] || [ -z "$LIVEKIT_API_KEY" ] || [ -z "$LIVEKIT_API_SECRET" ]; then
  echo "❌ ERROR: LiveKit environment variables are not set!"
  echo "   Required: LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET"
  echo "   Please set these in Railway dashboard or .env file"
  exit 1
fi
echo "✅ LiveKit environment variables are set"

# Start agent worker in background using virtual environment
echo "🚀 Starting agent worker..."
cd "$(dirname "$0")" || exit 1  # Ensure we're in the backend directory
$PYTHON_CMD agent.py start > /tmp/agent.log 2>&1 &
AGENT_PID=$!
echo "✅ Agent worker process started (PID: $AGENT_PID)"
echo "   Logs: /tmp/agent.log"

# Wait for agent to initialize and connect
echo "⏳ Waiting for agent worker to connect to LiveKit Cloud..."
sleep 5

# Check if agent process is still running
if ! kill -0 $AGENT_PID 2>/dev/null; then
  echo "❌ Agent worker process died. Last 30 lines of agent.log:"
  tail -30 /tmp/agent.log 2>/dev/null || echo "   (log file not found)"
  echo ""
  echo "❌ Exiting due to agent worker failure"
  exit 1
fi

# Check agent logs for connection success indicators
if grep -q "Connecting to LiveKit Cloud\|agent worker\|Agent name: agent" /tmp/agent.log 2>/dev/null; then
  echo "✅ Agent worker appears to be connecting (checking logs...)"
else
  echo "⚠️  Warning: Agent worker logs don't show expected connection messages"
  echo "   Last 20 lines of agent.log:"
  tail -20 /tmp/agent.log 2>/dev/null || echo "   (log file not found)"
fi

echo "✅ Agent worker is running (PID: $AGENT_PID)"
echo "   Monitor logs with: tail -f /tmp/agent.log"

# Start web server in foreground
echo "✅ Starting web server..."
npm start
