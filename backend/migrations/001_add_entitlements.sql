-- Shaw IAP Entitlements Schema
-- Run this migration on your PostgreSQL database

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
