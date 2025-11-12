#!/bin/bash

# Python Agent Worker Startup Script for Railway
# This script is for a Python-only Railway service that runs just the agent

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

# Verify Python can find the library
echo "🔍 Verifying Python library dependencies..."
/opt/venv/bin/python -c "
import sys
import os
print(f'Python: {sys.executable}')
print(f'LD_LIBRARY_PATH: {os.environ.get(\"LD_LIBRARY_PATH\", \"<not set>\")}')
try:
    import livekit
    print('✅ LiveKit Python SDK imported successfully')
except Exception as e:
    print(f'❌ Failed to import LiveKit: {e}')
    import sys
    sys.exit(1)
" || {
  echo "❌ Python library check failed - cannot start agent"
  exit 1
}

# Start the agent worker
echo "🚀 Starting LiveKit agent worker..."
exec /opt/venv/bin/python agent.py

