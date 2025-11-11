# CloudKit Setup Guide

Complete guide to enabling iCloud sync for session transcripts.

## Step 1: Enable Capabilities in Xcode

### Enable iCloud + CloudKit

1. **Open project in Xcode**
   ```bash
   open Shaw.xcodeproj
   ```

2. **Select the Shaw target**
   - Click on the project in the navigator (top-left)
   - Select "Shaw" under TARGETS

3. **Go to Signing & Capabilities tab**
   - Click the tab at the top of the main editor

4. **Add iCloud capability**
   - Click `+ Capability` button
   - Search for "iCloud"
   - Select "iCloud"

5. **Configure iCloud**
   - Check ✅ **CloudKit**
   - Uncheck ❌ Key-value storage (not needed)
   - Uncheck ❌ iCloud Documents (not needed)
   - Container: Should show `iCloud.$(CFBundleIdentifier)` automatically

### Enable Sign in with Apple

1. **Add capability**
   - Click `+ Capability` button again
   - Search for "Sign in with Apple"
   - Select "Sign in with Apple"

2. **That's it!** No additional configuration needed

## Step 2: Configure CloudKit Schema

You need to create the `Session` record type in CloudKit Dashboard.

### Option A: Automatic (First Run)

The app will create the schema automatically on first session save. Just:
1. Build and run the app
2. Start a test call
3. CloudKit will auto-create the schema from the code

### Option B: Manual (Recommended for Production)

1. **Go to CloudKit Dashboard**
   - Visit: https://icloud.developer.apple.com/dashboard
   - Sign in with your Apple Developer account
   - Select your app's container

2. **Create Session Record Type**
   - Click "Schema" in sidebar
   - Click "Record Types"
   - Click "+" to add new type
   - Name it: `Session`

3. **Add Fields to Session**

   | Field Name | Type | Indexed | Required |
   |------------|------|---------|----------|
   | `startTime` | Date/Time | ✅ Yes | ✅ Yes |
   | `endTime` | Date/Time | ❌ No | ❌ No |
   | `duration` | Int(64) | ❌ No | ✅ Yes |
   | `context` | String | ✅ Yes | ✅ Yes |
   | `title` | String | ❌ No | ❌ No |
   | `summary` | String | ❌ No | ❌ No |
   | `model` | String | ✅ Yes | ❌ No |
   | `voice` | String | ❌ No | ❌ No |
   | `transcript` | String | ❌ No | ❌ No |

4. **Add Indexes** (for faster queries)
   - Click "Indexes" tab
   - Add index on: `startTime` (descending)
   - Add index on: `context`
   - Add index on: `model`

5. **Save Schema**
   - Click "Save Changes"
   - Click "Deploy to Production"

## Step 3: Test CloudKit Integration

### Verify Setup

1. **Build and run app**
   ```bash
   # In Xcode: Product → Run (⌘R)
   ```

2. **Check iCloud status**
   - App should print: "Syncing via iCloud"
   - If not signed into iCloud on simulator/device, it will show: "iCloud unavailable - using backend only"

3. **Test cross-device sync**
   - Start a call on device A
   - Open app on device B (same iCloud account)
   - Session should appear within 5-10 seconds

### Troubleshooting

**"iCloud unavailable" message:**
- On Simulator: Settings → Apple ID → Sign in with your Apple ID
- On Device: Settings → [Your Name] → iCloud → Make sure iCloud Drive is ON

**Schema errors:**
- Check CloudKit Dashboard for validation errors
- Make sure all field names match exactly (case-sensitive)
- Redeploy schema if needed

**Sessions not syncing:**
- Check you're signed into same iCloud account on all devices
- Check Settings → [Your Name] → iCloud → Show All → Shaw → Make sure it's ON
- Try toggling iCloud sync off and back on for the app

## Step 4: Backend Integration

The app is already configured to write to both CloudKit and your backend. No additional backend changes needed.

### How It Works

```
User starts call
    ↓
HybridSessionLogger
    ├─→ CloudKit (for sync)
    └─→ Backend (for billing)

User views history
    ↓
Try CloudKit first (instant, offline)
    ├─→ Success: Show sessions
    └─→ Fail: Fallback to backend
```

### Verify Both Sources

Check that sessions are being saved to both:

1. **CloudKit Dashboard**
   - Go to: https://icloud.developer.apple.com/dashboard
   - Select container → Data → Production
   - Query `Session` records - should see your test sessions

2. **Backend Database**
   ```bash
   # SSH to Railway and check SQLite
   sqlite3 data/sessions.db "SELECT * FROM sessions;"
   ```

## Step 5: Sign in with Apple Setup

### Configure App ID

1. **Go to Apple Developer Portal**
   - Visit: https://developer.apple.com
   - Go to: Certificates, Identifiers & Profiles

2. **Edit your App ID**
   - Find your app's identifier
   - Make sure "Sign in with Apple" is checked
   - Save

3. **That's it!** Sign in with Apple should now work

### Test Authentication

1. **Run app**
2. **On first launch**, user will see "Sign in with Apple" button
3. **Tap to sign in** → Face ID/Touch ID prompt
4. **Grant permission** → User is authenticated
5. **Sessions sync automatically** across all devices with same Apple ID

## Step 6: Production Checklist

Before launching to users:

- [ ] CloudKit schema deployed to **Production** (not Development)
- [ ] iCloud capability enabled in Xcode
- [ ] Sign in with Apple enabled in App ID
- [ ] Tested on real device (not just simulator)
- [ ] Tested cross-device sync (iPhone → iPad)
- [ ] Backend still receiving sessions (for billing)
- [ ] Usage stats working from backend

## CloudKit Limits (Free Tier)

Your app gets for FREE:
- **10 GB** of asset storage
- **100 MB** of database storage per user
- **2 GB** of transfer per day
- Unlimited users
- Unlimited API requests

**Estimate for your app:**
- Average session: ~50 KB (10 min conversation)
- User can store: ~2,000 sessions before hitting 100 MB limit
- That's **333+ hours** of conversations per user!

## Monitoring & Analytics

### CloudKit Telemetry

View usage in CloudKit Dashboard:
- Dashboard → Telemetry
- See: Requests, Storage, Errors
- Track: Active users, Data transfer

### Backend Analytics

Backend still tracks:
- Usage minutes (for billing)
- Active sessions
- API calls
- Model usage

Both systems work together - best of both worlds!

## Support

If you have issues:
1. Check CloudKit Console logs
2. Check Xcode console for CloudKit errors
3. Verify iCloud account is active
4. Make sure entitlements are correct

---

**Next Steps:** Just build and run! The app will handle CloudKit setup automatically.
