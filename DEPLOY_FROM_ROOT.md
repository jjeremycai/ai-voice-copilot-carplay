# Deploying from Repo Root - Practical Solution

## Overview

Yes, you can deploy from the repo root! This makes both GitHub and CLI deployments work consistently.

## Changes Made

### 1. Created `railway.json` at repo root
- Points to `backend/start.sh` for start command
- References `nixpacks.toml` at root

### 2. Created `nixpacks.toml` at repo root
- All build commands `cd backend` before running
- Installs Node.js and Python dependencies in backend/
- Creates venv at `/opt/venv` (absolute path, works from anywhere)

### 3. Railway Dashboard Configuration

**Update Railway Dashboard Settings:**

1. Go to your Railway service → **Settings** → **Source**
2. Change **Root Directory** from `backend` to `.` (dot = root)
3. Save changes

**Alternative**: Leave Root Directory empty or set to `/`

## How It Works

### Build Phase (nixpacks.toml)
```bash
cd backend && npm ci          # Install Node.js deps
cd backend && python3 -m venv /opt/venv  # Create venv (absolute path)
cd backend && /opt/venv/bin/pip install -r requirements.txt
```

### Runtime Phase (start.sh)
```bash
bash backend/start.sh  # Runs from repo root, script handles paths
```

The `start.sh` script uses absolute paths (`/opt/venv/bin/python`) so it works regardless of where it's called from.

## Benefits

✅ **CLI deployments work**: `railway up` from repo root now works  
✅ **GitHub deployments work**: Still works with Root Directory = `.`  
✅ **Consistent behavior**: Both methods work the same way  
✅ **No path confusion**: Clear separation between repo root and backend code

## Deployment Commands

### From Repo Root (Now Works!)
```bash
cd /Users/jeremycai/Projects/shaw-app
railway up --detach
```

### GitHub (Still Works)
```bash
git push origin main
# Railway auto-deploys
```

## Verification

After updating Railway dashboard Root Directory to `.`:

1. **Deploy via CLI**:
   ```bash
   cd /Users/jeremycai/Projects/shaw-app
   railway up --detach
   ```

2. **Check logs**:
   ```bash
   railway logs --lines 50
   ```

3. **Should see**:
   - ✅ Build commands running in `backend/`
   - ✅ Library detection working
   - ✅ Agent and server starting successfully

## Important Notes

- **Root Directory in Dashboard**: Must be set to `.` (or empty) for this to work
- **Paths in scripts**: Use absolute paths (`/opt/venv`) or relative from repo root (`backend/`)
- **Backend files**: Stay in `backend/` directory - no need to move anything

## If You Want to Keep Backend Root Directory

If you prefer to keep Root Directory = `backend` in dashboard:
- **GitHub deployments**: Will continue to work ✅
- **CLI deployments**: Will continue to fail ❌
- **Workaround**: Always use GitHub deployments (push to main)

The root deployment approach is more flexible and works for both methods.

