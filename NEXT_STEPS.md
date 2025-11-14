# Next Steps: Complete Railway Deployment Setup

## ✅ What We've Done

1. ✅ Fixed `libstdc++.so.6` library path issue with dynamic detection
2. ✅ Created Railway configs at repo root (`railway.json`, `nixpacks.toml`)
3. ✅ Created `start.sh` wrapper at root
4. ✅ Cleaned up duplicate config files
5. ✅ Committed all changes to git

## 🔧 What You Need to Do Now

### Step 1: Verify Railway Dashboard Settings

1. Go to Railway Dashboard → Your Service → **Settings** → **Source**
2. Check **Root Directory** field:
   - Should be: `.` (dot) or empty
   - If it says `backend`, change it to `.` and save

### Step 2: Deploy

**Option A: Via GitHub (Recommended)**
```bash
# Already pushed, Railway should auto-deploy
# Check Railway dashboard for deployment status
```

**Option B: Via CLI**
```bash
cd /Users/jeremycai/Projects/shaw-app
railway up --detach
```

### Step 3: Verify Deployment

Check logs for success indicators:
```bash
railway logs --lines 100
```

**Look for:**
- ✅ "Found libstdc++.so.6 at: ..."
- ✅ "LD_LIBRARY_PATH set to: ..."
- ✅ "LiveKit Python SDK imported successfully"
- ✅ "Agent worker is running (PID: ...)"
- ✅ "Server running on http://localhost:3000"

**Should NOT see:**
- ❌ "Could not find root directory"
- ❌ "Script start.sh not found"
- ❌ "OSError: libstdc++.so.6"

### Step 4: Test the Service

1. **Health Check**:
   ```bash
   curl https://shaw.up.railway.app/health
   ```

2. **Test from iOS App**:
   - Start a call
   - Verify agent joins and responds

## 🎯 Expected Result

- ✅ Deployment succeeds
- ✅ Both Node.js server and Python agent start
- ✅ No library path errors
- ✅ Voice conversations work end-to-end

## 🐛 If Something Fails

1. **Check Railway logs**: `railway logs --lines 100`
2. **Verify Root Directory**: Must be `.` in dashboard
3. **Check config files**: `railway.json` and `nixpacks.toml` should be at repo root
4. **Verify start.sh**: Should exist at repo root and be executable

## 📝 Summary

**Current State**: All code is ready, configs are clean, just need to:
1. Verify Root Directory = `.` in Railway dashboard
2. Deploy (GitHub auto-deploy or CLI)
3. Verify it works

That's it! 🚀

