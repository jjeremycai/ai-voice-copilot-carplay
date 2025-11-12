# GitHub Deployments vs Railway CLI: Why They Behave Differently

## The Key Difference

### GitHub Deployments (Auto-Deploy on Push)
When Railway is connected to GitHub and auto-deploys:

1. **Railway clones the entire repository** from GitHub using git
2. **Repository root** becomes the working directory (full git structure)
3. **Root Directory setting** (`backend`) is applied relative to repo root
4. Railway looks for `backend/` subdirectory ✅ **FOUND**
5. Build and deploy from `backend/` directory

**Result**: ✅ Works perfectly

### Railway CLI (`railway up`) - The Problem
When you run `railway up` from the CLI, **even from repo root**, it fails:

**Why CLI Deployments Fail:**
1. **Railway CLI uploads files differently** than GitHub
   - CLI may create a tarball/zip of current directory
   - May not preserve full directory structure the same way
   - May not respect Root Directory setting from dashboard
   
2. **Root Directory setting may not apply**:
   - Dashboard setting (`backend`) might only work for GitHub deployments
   - CLI might ignore dashboard Root Directory setting
   - CLI might expect files to be in the uploaded root

3. **File structure differences**:
   - GitHub: Full repo structure with `.git` metadata
   - CLI: Just files from current directory, possibly flattened

**Result**: ❌ Fails with "Could not find root directory: backend"

**Even when run from repo root**, CLI deployments fail because:
- Railway CLI doesn't respect the Root Directory dashboard setting
- CLI uploads work differently than GitHub clones
- The service expects files in a specific structure that CLI doesn't provide

## Visual Explanation

### GitHub Deployment Flow
```
GitHub Repo (cloned by Railway)
├── backend/          ← Railway finds this (Root Directory = "backend")
│   ├── agent.py
│   ├── start.sh
│   └── ...
├── Models/
├── Screens/
└── ...
```

### Railway CLI from Backend Directory (FAILS)
```
What Railway sees (uploaded from backend/):
├── agent.py          ← Railway is already IN backend/
├── start.sh
└── ...

Railway then looks for: backend/backend/  ❌ Doesn't exist!
```

### Railway CLI from Repo Root (WORKS)
```
What Railway sees (uploaded from repo root):
├── backend/          ← Railway finds this (Root Directory = "backend")
│   ├── agent.py
│   └── ...
├── Models/
└── ...

Railway looks for: backend/  ✅ Found!
```

## Why This Happens

**The Root Directory setting in Railway dashboard appears to only work for GitHub deployments:**

- **GitHub**: Clones full repo → Root Directory setting (`backend`) is respected ✅
- **CLI**: Uploads files directly → Root Directory setting may be ignored ❌
- **CLI behavior**: Railway CLI seems to upload files and expect them to be in the root, regardless of dashboard settings

**This is a Railway platform limitation** - the Root Directory setting doesn't apply to CLI deployments the same way it does for GitHub deployments.

## Solution

### ✅ Use GitHub Deployments (Recommended)

**GitHub deployments are the reliable way** to deploy when using Root Directory settings:

```bash
# Just push to GitHub - Railway auto-deploys
git add .
git commit -m "Your changes"
git push origin main
```

Railway will automatically:
1. Clone the repo
2. Respect Root Directory setting
3. Deploy successfully

### ⚠️ Railway CLI Limitation

**Railway CLI doesn't respect Root Directory dashboard settings** - this appears to be a platform limitation.

**Workaround options** (if you must use CLI):

1. **Change Root Directory in dashboard to `.` (root)**:
   - Then deploy from backend directory
   - But this breaks GitHub deployments

2. **Use Railway's config-as-code** (if supported):
   - Add `rootDirectory` to `railway.json`
   - May work better with CLI

3. **Deploy via Railway Dashboard**:
   - Use "Redeploy" button instead of CLI
   - Uses GitHub source, respects settings

**Best Practice**: Use GitHub deployments for consistency and reliability.

## Why GitHub Deployments Always Work

GitHub deployments always work because:
1. Railway always clones the full repository
2. The repository root is always the starting point
3. Root Directory settings are always relative to repo root
4. No ambiguity about what "backend" means

## Best Practice

**For consistency**, always deploy from the repository root when using CLI:

```bash
cd /Users/jeremycai/Projects/shaw-app
railway up --detach
```

This matches how GitHub deployments work and avoids the root directory confusion.

## Summary

| Deployment Method | Root Directory Setting | Result | Notes |
|------------------|----------------------|--------|-------|
| GitHub (auto-deploy) | `backend` (from dashboard) | ✅ Works | Respects dashboard setting |
| CLI from repo root | `backend` (from dashboard) | ❌ Fails | Dashboard setting ignored |
| CLI from backend/ | `backend` (from dashboard) | ❌ Fails | Dashboard setting ignored |
| Dashboard Redeploy | `backend` (from dashboard) | ✅ Works | Uses GitHub source |

**Key Finding**: Railway CLI (`railway up`) **does not respect the Root Directory dashboard setting**. This is a platform limitation.

**Recommendation**: Use GitHub deployments (push to main branch) for reliable deployments that respect all dashboard settings.

