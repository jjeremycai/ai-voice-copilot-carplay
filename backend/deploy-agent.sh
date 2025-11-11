#!/bin/bash
# Deploy LiveKit Agent to Cloud

set -e

cd "$(dirname "$0")"

echo "🚀 Deploying LiveKit Agent to Cloud..."
echo ""

# Check if lk CLI is installed
if ! command -v lk &> /dev/null; then
    echo "❌ LiveKit CLI not found. Installing..."
    brew install livekit-cli
fi

# Check if authenticated
echo "1️⃣  Checking authentication..."
if ! lk project list &> /dev/null; then
    echo "🔐 Opening browser to authenticate with LiveKit Cloud..."
    lk cloud auth
else
    echo "✅ Already authenticated"
fi

echo ""
echo "2️⃣  Creating agent configuration..."

# Check if livekit.toml exists
if [ ! -f "livekit.toml" ]; then
    echo "📝 Creating agent (this will prompt for details)..."
    echo ""
    echo "When prompted, enter:"
    echo "  - Agent name: shaw-voice-assistant"
    echo "  - Entry point: agent.py"
    echo "  - Region: us-east"
    echo ""
    lk agent create
else
    echo "✅ livekit.toml already exists"
fi

echo ""
echo "3️⃣  Deploying agent..."
lk agent deploy

echo ""
echo "✅ Agent deployed successfully!"
echo ""
echo "To view agent status:"
echo "  lk agent list"
echo ""
echo "To view agent logs:"
echo "  lk agent logs shaw-voice-assistant"
echo ""
echo "🎉 Your voice AI is now ready!"
echo "   Start a call from your iOS app to test it."
