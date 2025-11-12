# Agent Join Issue - Current Diagnosis

## Summary

**Agent dispatch succeeds** (`AD_3PkTWFrKkvSQ`) but **agent never joins the room**.

## Evidence from Logs

### ✅ What's Working
1. Backend server starts successfully
2. Agent worker process starts (PID: 9)
3. Agent dispatch API call succeeds
4. Client connects to LiveKit room successfully
5. Client publishes audio track

### ❌ What's NOT Working
1. **Agent worker logs are missing** - No logs showing:
   - `🚀 Starting LiveKit Agent Worker`
   - `📋 Agent name for dispatch: agent`
   - `🔌 Connecting to LiveKit Cloud...`
   - `🎙️  Agent entrypoint called!`

2. **Agent never joins room** - Verification fails:
   - Room exists but no agent participant found
   - Dispatch ID created but agent doesn't receive it

3. **API bug** - Fixed but old code still running:
   - `roomService.getRoom is not a function` (now fixed to use `listRooms()`)

## Root Cause Hypothesis

The agent worker process starts but **is not connecting to LiveKit Cloud** or **not receiving dispatches**.

Possible reasons:
1. **Agent worker crashes silently** after startup
2. **Agent worker not connecting** to LiveKit Cloud (network/auth issue)
3. **Agent worker not registered** with correct agent name
4. **Agent worker running but not listening** for dispatches

## How to Check LiveKit Cloud Logs

### Option 1: LiveKit Cloud Dashboard (BEST)
1. Go to https://cloud.livekit.io/
2. Select project: `bunnyai` or `bunnyai2`
3. Go to **Agents** section
4. Check:
   - Are there any deployed agents?
   - Are there running agent instances?
   - View agent logs in dashboard

### Option 2: LiveKit CLI
```bash
cd backend

# List all agents
lk agent list

# View agent logs (if deployed to cloud)
lk agent logs shaw-voice-assistant

# Check recent dispatches
lk dispatch list
```

### Option 3: Railway Logs (After Fix)
After deploying the logging fix, Railway logs should show:
- Agent worker startup messages
- Connection to LiveKit Cloud
- Entrypoint calls when dispatches received

## Next Steps

1. **Check LiveKit Cloud Dashboard** - See if agent is deployed/running
2. **Wait for Railway redeploy** - New logging will show agent worker output
3. **Verify agent name** - Must match between dispatch (`'agent'`) and worker
4. **Check if agent worker is actually running** - PID 9 might have crashed

## Files Changed

- ✅ `backend/livekit.js` - Fixed API bug (`listRooms()` instead of `getRoom()`)
- ✅ `backend/start.sh` - Fixed logging (stream to stdout with `tee`)
- ✅ `backend/agent.py` - Already using LiveKit Inference

## Expected Behavior After Fix

When you start a session, you should see in Railway logs:
```
🚀 Starting LiveKit Agent Worker
📋 Agent name for dispatch: agent
🔌 Connecting to LiveKit Cloud...
🎙️  Agent entrypoint called!
   Room name: room-abc123
   Job ID: job-xyz
```

If you DON'T see the entrypoint being called, the agent worker is not receiving dispatches.

