# Database Migration Instructions

## Quick Command (If Railway CLI is installed)

```bash
cd backend
railway run psql $DATABASE_URL -f migrations/001_add_entitlements.sql
```

## Step-by-Step Instructions

### Option 1: Using Railway CLI (Recommended)

**1. Install Railway CLI (if not installed):**
```bash
npm install -g @railway/cli
```

**2. Login to Railway:**
```bash
railway login
```

**3. Link to your project:**
```bash
cd backend
railway link
```
Select your Shaw backend project from the list.

**4. Run the migration:**
```bash
railway run psql $DATABASE_URL -f migrations/001_add_entitlements.sql
```

**5. Verify tables were created:**
```bash
railway run psql $DATABASE_URL -c "\dt"
```

You should see:
- `entitlements`
- `device_entitlements`
- `free_allowance`
- `sessions` (with new columns)

---

### Option 2: Using Railway Dashboard

**1. Go to Railway Dashboard:**
- Open https://railway.app
- Select your Shaw backend project
- Click on your PostgreSQL database

**2. Open the "Query" tab**

**3. Copy and paste the SQL below:**

```sql
-- Entitlements table (source of truth for Apple subscription status)
CREATE TABLE IF NOT EXISTS entitlements (
  original_transaction_id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  status TEXT NOT NULL, -- 'active', 'grace', 'expired', 'revoked'
  expires_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  environment TEXT NOT NULL, -- 'Sandbox' | 'Production'
  last_update_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Link devices to entitlements (supports multi-device)
CREATE TABLE IF NOT EXISTS device_entitlements (
  device_id TEXT NOT NULL,
  original_transaction_id TEXT NOT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (device_id, original_transaction_id),
  FOREIGN KEY (original_transaction_id) REFERENCES entitlements(original_transaction_id) ON DELETE CASCADE
);

-- Free tier usage tracking (10 minutes/month per device)
CREATE TABLE IF NOT EXISTS free_allowance (
  device_id TEXT PRIMARY KEY,
  minutes_used INTEGER NOT NULL DEFAULT 0,
  period_start TIMESTAMPTZ NOT NULL,
  period_end TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add entitlement context to sessions
ALTER TABLE sessions
  ADD COLUMN IF NOT EXISTS original_transaction_id TEXT,
  ADD COLUMN IF NOT EXISTS entitlement_checked_at TIMESTAMPTZ;

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_entitlements_status_expires ON entitlements(status, expires_at);
CREATE INDEX IF NOT EXISTS idx_device_entitlements_device ON device_entitlements(device_id);
CREATE INDEX IF NOT EXISTS idx_free_allowance_period ON free_allowance(period_start, period_end);
```

**4. Click "Execute" or "Run"**

**5. Verify in the "Data" tab:**
- You should see the new tables listed

---

### Option 3: Using psql Command Line

**1. Get your DATABASE_URL:**
```bash
railway variables get DATABASE_URL
```

Copy the URL (format: `postgresql://user:password@host:port/database`)

**2. Connect with psql:**
```bash
psql "postgresql://user:password@host:port/database" -f migrations/001_add_entitlements.sql
```

Replace the URL with your actual DATABASE_URL from step 1.

**3. Verify:**
```bash
psql "postgresql://user:password@host:port/database" -c "\dt"
```

---

## Verification Checklist

After running the migration, verify these tables exist:

- [ ] `entitlements` - Stores Apple subscription status
- [ ] `device_entitlements` - Links devices to subscriptions
- [ ] `free_allowance` - Tracks free tier usage (10 min/month)

And these columns were added to `sessions`:

- [ ] `original_transaction_id` - Which subscription was used
- [ ] `entitlement_checked_at` - When entitlement was checked

**Quick verification command:**
```bash
railway run psql $DATABASE_URL -c "
  SELECT column_name
  FROM information_schema.columns
  WHERE table_name = 'sessions'
    AND column_name IN ('original_transaction_id', 'entitlement_checked_at');
"
```

Should return both column names.

---

## Troubleshooting

### "railway: command not found"
Install Railway CLI: `npm install -g @railway/cli`

### "relation already exists"
Tables already created - this is fine! The migration uses `IF NOT EXISTS`.

### "column already exists"
Columns already added - this is fine! The migration uses `IF NOT EXISTS`.

### "cannot connect to database"
1. Check your Railway project is running
2. Verify DATABASE_URL is set: `railway variables get DATABASE_URL`
3. Try reconnecting: `railway link` and select your project

### "permission denied"
Make sure you're logged in: `railway login`

---

## What the Migration Does

### Creates 3 New Tables:

**1. entitlements**
- Stores the source of truth for Apple subscriptions
- Tracks status: active, grace, expired, revoked
- Records expiration dates and environment (Sandbox/Production)

**2. device_entitlements**
- Links device IDs to subscription IDs
- Enables multi-device support (same subscription on multiple devices)
- Tracks when device last verified entitlement

**3. free_allowance**
- Tracks free tier usage per device
- 10 minutes/month limit
- Auto-resets on 1st of each month

### Updates Existing Table:

**sessions** - Adds 2 columns:
- `original_transaction_id` - Links session to Apple transaction
- `entitlement_checked_at` - Timestamp of entitlement verification

---

## Need Help?

**Contact your dev team with:**
- This file (RUN_MIGRATION.md)
- The migration SQL file: `migrations/001_add_entitlements.sql`
- Access to Railway dashboard

**Or ping me if you need help!**
