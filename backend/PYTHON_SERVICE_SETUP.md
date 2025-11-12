# Python Agent Service Setup for Railway

## Overview

You have TWO separate Railway services:
1. **Node.js Service** - Runs `server.js` (web API)
2. **Python Service** - Runs `agent.py` (LiveKit agent worker)

This guide is for configuring the **Python Service** to fix the `libstdc++.so.6` error.

## Files Created

1. **`start-agent.sh`** - Startup script for Python-only service
2. **`nixpacks-agent.toml`** - Nixpacks config for Python service (no Node.js)
3. **`railway-agent.json`** - Railway config for Python service

## Setup Steps

### Step 1: Identify Your Python Service

In Railway dashboard:
1. Go to your project
2. Find the service that runs ONLY the Python agent (not the Node.js server)
3. Note the service name (e.g., "shaw-agent" or "python-agent")

### Step 2: Configure the Python Service

**Option A: Via Railway Dashboard**

1. Go to your Python service in Railway
2. Go to **Settings** → **Source**
3. Set **Root Directory** to: `backend`
4. Go to **Settings** → **Build**
5. Set **Nixpacks Config Path** to: `nixpacks-agent.toml`
6. Go to **Settings** → **Deploy**
7. Set **Start Command** to: `bash start-agent.sh`

**Option B: Via Railway CLI**

```bash
cd /Users/jeremycai/Projects/shaw-app/backend

# Link to the Python service (replace SERVICE_NAME with your Python service name)
railway service SERVICE_NAME

# Set the nixpacks config path (if Railway supports it via CLI)
# Otherwise, set it in the dashboard
```

### Step 3: Ensure Files Are Committed

The Python service needs these files in the `backend` directory:
- `start-agent.sh` ✅
- `nixpacks-agent.toml` ✅
- `agent.py` ✅
- `requirements.txt` ✅

```bash
cd /Users/jeremycai/Projects/shaw-app
git add backend/start-agent.sh backend/nixpacks-agent.toml backend/railway-agent.json
git commit -m "Add Python agent service configuration for Railway"
git push origin main
```

### Step 4: Deploy

Railway will auto-deploy when you push, or manually trigger:

```bash
# If linked to Python service
cd backend
railway up --detach
```

### Step 5: Verify

Check logs for success indicators:

```bash
railway logs --lines 100
```

**Success indicators:**
- ✅ "Found libstdc++.so.6 at: ..."
- ✅ "LD_LIBRARY_PATH set to: ..."
- ✅ "LiveKit Python SDK imported successfully"
- ✅ "Starting LiveKit agent worker..."
- ✅ No `OSError: libstdc++.so.6` errors

## Differences from Node.js Service

| Node.js Service | Python Service |
|----------------|----------------|
| Runs `start.sh` | Runs `start-agent.sh` |
| Uses `nixpacks.toml` | Uses `nixpacks-agent.toml` |
| Installs Node.js + Python | Installs Python only |
| Starts both server + agent | Starts agent only |

## Troubleshooting

### Service Not Found
If you can't find the Python service:
1. Check Railway dashboard for all services
2. Look for a service with name containing "agent" or "python"
3. Or create a new service and configure it as Python-only

### Still Getting libstdc++.so.6 Error
1. Check logs to see where the library was found (or not found)
2. Verify `nixpacks-agent.toml` has `gcc` and `stdenv.cc.cc.lib`
3. Check that `LD_LIBRARY_PATH` is being set correctly in logs
4. Try the alternative solutions in `LIBSTDCPP_FIX.md`

## Next Steps

Once the Python service is working:
1. ✅ Python agent starts without errors
2. ✅ Agent connects to LiveKit
3. ✅ Agent joins rooms when dispatched
4. ✅ Voice conversations work end-to-end

