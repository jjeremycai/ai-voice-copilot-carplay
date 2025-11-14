# Deployment Fix: Root Directory Issue

## Problem

When deploying from the `backend` directory with `cd backend && railway up`, Railway fails with:
```
Could not find root directory: backend
```

## Root Cause

Railway service is configured with:
- **Root Directory**: `backend` (set in Railway dashboard)

When you run `railway up` from within the `backend` directory:
1. Railway uploads the current directory (`backend/`) as the root
2. Railway then looks for `backend/backend/` subdirectory
3. This doesn't exist, so deployment fails

## Solution

**Deploy from the repository root**, not from the backend directory:

```bash
# ✅ CORRECT: Deploy from repo root
cd /Users/jeremycai/Projects/shaw-app
railway up --detach

# ❌ WRONG: Don't deploy from backend directory
cd backend
railway up --detach  # This fails!
```

## Why This Works

When Railway is configured with Root Directory = `backend`:
- Railway expects the repo root as the working directory
- It then looks for the `backend/` subdirectory
- All files in `backend/` are available at build/runtime

## Updated Deployment Process

### For Node.js Service (combined service)

```bash
cd /Users/jeremycai/Projects/shaw-app
railway up --detach
```

Railway will:
1. Use repo root as base
2. Find `backend/` directory (as configured)
3. Use `backend/nixpacks.toml` for build
4. Run `backend/start.sh` on startup

### For Python Service (separate service)

1. **Configure in Railway Dashboard**:
   - Root Directory: `backend`
   - Nixpacks Config Path: `nixpacks-agent.toml`
   - Start Command: `bash start-agent.sh`

2. **Deploy from repo root**:
   ```bash
   cd /Users/jeremycai/Projects/shaw-app
   railway service python-service-name  # Link to Python service first
   railway up --detach
   ```

## Verification

After deployment, check logs:
```bash
railway logs --lines 100
```

Should see:
- ✅ Library detection working
- ✅ Agent starting successfully
- ✅ No "Could not find root directory" errors

