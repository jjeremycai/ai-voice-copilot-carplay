# Deploy LiveKit Agent to Cloud

## Quick Start (Run these commands in your terminal)

```bash
cd /Users/jeremycai/Projects/shaw-app/backend

# 1. Authenticate with LiveKit Cloud (opens browser)
lk cloud auth

# 2. Create and deploy the agent
lk agent create

# When prompted:
# - Agent name: shaw-voice-assistant
# - Entry point: agent.py
# - Region: us-east

# 3. Deploy the agent
lk agent deploy
```

## What This Does

1. **lk cloud auth** - Opens your browser to authenticate with LiveKit Cloud
2. **lk agent create** - Registers your agent and creates livekit.toml config
3. **lk agent deploy** - Builds Docker image and deploys to LiveKit Cloud

## After Deployment

Once deployed:
- Agent will automatically register as available
- When you start a call from iOS, backend calls createDispatch()
- LiveKit Cloud dispatches your agent to join the room
- Agent handles voice AI conversation

## Check Agent Status

```bash
# View deployed agents
lk agent list

# View agent logs
lk agent logs shaw-voice-assistant
```

## Environment Variables Needed

The agent needs these env vars (already in your .env):
- `LIVEKIT_URL` - Your LiveKit Cloud URL
- `LIVEKIT_API_KEY` - Your API key
- `LIVEKIT_API_SECRET` - Your API secret
- `OPENAI_API_KEY` - For LLM (if using OpenAI models)
- `CARTESIA_API_KEY` - For TTS (if using Cartesia voices)

LiveKit Cloud will automatically inject these from your project settings.
