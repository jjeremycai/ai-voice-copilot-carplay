# TTS Connection Limit Fix

## Problem

You received a warning that your project reached 4/5 concurrent TTS connections on LiveKit. Even though you're using a self-hosted agent, **this still matters** because your agent was using **LiveKit Inference** for TTS, which counts against the connection limit.

## Root Cause

In `agent.py`, the hybrid mode was using LiveKit Inference for TTS:
```python
tts=voice  # LiveKit Inference TTS (string descriptor)
```

When you pass a string descriptor like `"cartesia/sonic-3:voice-id"`, it routes through LiveKit Inference, which has a 5 concurrent connection limit on the Build plan.

## Solution

The agent has been updated to use the **Cartesia plugin directly** instead of LiveKit Inference when a Cartesia API key is available. This bypasses the LiveKit Inference TTS connection limit entirely.

### Changes Made

1. **Added Cartesia plugin import**: `from livekit.plugins import cartesia`
2. **Created `create_tts_from_voice_descriptor()` function**: Parses voice descriptors and creates plugin instances when possible
3. **Updated hybrid mode**: Now uses the plugin if available, falls back to LiveKit Inference otherwise

### What You Need to Do

**Ensure `CARTESIA_API_KEY` is set in your Railway Python Agent Service** (not the Node.js backend service).

Since you mentioned you already have the Cartesia key, verify it's set in the correct service:

1. Go to Railway dashboard → Your project
2. Find the **Python Agent Service** (the one that runs `agent.py`, not `server.js`)
3. Go to **Variables** tab
4. Verify `CARTESIA_API_KEY` is set (if not, add it)
5. **Redeploy the agent service** to pick up the code changes

### How It Works Now

- **If `CARTESIA_API_KEY` is set**: Uses Cartesia plugin directly → **Does NOT count against LiveKit Inference limit** ✅
- **If `CARTESIA_API_KEY` is NOT set**: Falls back to LiveKit Inference → **Counts against limit** ⚠️

### Benefits

- ✅ No more TTS connection limit warnings
- ✅ Direct connection to Cartesia (potentially faster)
- ✅ You pay Cartesia directly (may be cheaper depending on usage)
- ✅ Graceful fallback if API key is missing

### For ElevenLabs Voices

Currently, ElevenLabs voices still use LiveKit Inference. To bypass the limit for ElevenLabs as well, you would need to:
1. Install the ElevenLabs plugin: `livekit-agents[elevenlabs]`
2. Add `ELEVENLABS_API_KEY` environment variable
3. Update `create_tts_from_voice_descriptor()` to support ElevenLabs format

## Testing

After redeploying the agent service with the updated code, check your agent logs:

```bash
# View Railway agent service logs
railway logs --service <your-python-agent-service-name> --lines 50
```

**Success indicators:**
- ✅ `🎤 Using Cartesia plugin directly (bypasses LiveKit Inference TTS limit)`
- ✅ `📢 Using TTS plugin directly (does NOT count against LiveKit Inference limit)`

**If you see:**
- ⚠️ `CARTESIA_API_KEY not set, falling back to LiveKit Inference` → The key isn't set in the Python agent service
- ⚠️ `Using LiveKit Inference TTS (counts against connection limit)` → The key isn't being read properly

## Important Notes

1. **Two Separate Services**: You have a Node.js backend service AND a Python agent service. The `CARTESIA_API_KEY` must be set in the **Python agent service**, not the backend service.

2. **Redeploy Required**: After setting the environment variable, you need to redeploy the agent service for it to pick up the new code that uses the plugin.

3. **Check Logs**: The agent logs will clearly show which TTS method is being used, so you can verify it's working correctly.

