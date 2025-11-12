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
elif command -v python3 &> /dev/null; then
  PYTHON_CMD="python3"
else
  PYTHON_CMD="python"
fi

echo "🔍 Using Python: $PYTHON_CMD"

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

# Start agent worker in background using virtual environment
echo "🚀 Starting agent worker..."
$PYTHON_CMD agent.py start > /tmp/agent.log 2>&1 &
AGENT_PID=$!
echo "✅ Agent worker process started (PID: $AGENT_PID)"

# Wait a moment to check if agent started successfully
sleep 3
if ! kill -0 $AGENT_PID 2>/dev/null; then
  echo "❌ Agent worker failed to start. Last 20 lines of agent.log:"
  tail -20 /tmp/agent.log 2>/dev/null || echo "   (log file not found)"
  echo ""
  echo "❌ Exiting due to agent worker failure"
  exit 1
fi
echo "✅ Agent worker is running (PID: $AGENT_PID)"

# Start web server in foreground
echo "✅ Starting web server..."
npm start
