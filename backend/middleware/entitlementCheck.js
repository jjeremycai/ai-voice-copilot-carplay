import db from '../database.js';

export const FREE_TIER_MINUTES = 15;

export async function checkEntitlement(deviceId) {
  const now = new Date();

  const entitlementStmt = db.prepare(`
    SELECT e.*
    FROM device_entitlements de
    JOIN entitlements e ON de.original_transaction_id = e.original_transaction_id
    WHERE de.device_id = ?
      AND e.status IN ('active', 'grace')
      AND (e.expires_at IS NULL OR e.expires_at > ?)
    ORDER BY e.expires_at DESC NULLS FIRST
    LIMIT 1
  `);

  const entitlement = await entitlementStmt.get(deviceId, now.toISOString());

  if (entitlement) {
    console.log(`✅ Active subscription found: ${entitlement.original_transaction_id}`);
    return {
      allowed: true,
      reason: 'subscription',
      originalTransactionId: entitlement.original_transaction_id,
      productId: entitlement.product_id,
      expiresAt: entitlement.expires_at
    };
  }

  const firstDayOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const lastDayOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59);

  let allowance = await db.prepare(`
    SELECT *
    FROM free_allowance
    WHERE device_id = ?
  `).get(deviceId);

  const needsReset = !allowance ||
    new Date(allowance.period_start) < firstDayOfMonth;

  if (needsReset) {
    const stmt = db.prepare(`
      INSERT INTO free_allowance (device_id, minutes_used, period_start, period_end, updated_at)
      VALUES (?, 0, ?, ?, ?)
      ON CONFLICT (device_id) DO UPDATE SET
        minutes_used = 0,
        period_start = EXCLUDED.period_start,
        period_end = EXCLUDED.period_end,
        updated_at = EXCLUDED.updated_at
    `);

    await stmt.run(
      deviceId,
      firstDayOfMonth.toISOString(),
      lastDayOfMonth.toISOString(),
      now.toISOString()
    );

    allowance = await db.prepare(`SELECT * FROM free_allowance WHERE device_id = ?`).get(deviceId);
  }

  if (allowance.minutes_used < FREE_TIER_MINUTES) {
    console.log(`✅ Free tier available: ${allowance.minutes_used}/${FREE_TIER_MINUTES} minutes used`);
    return {
      allowed: true,
      reason: 'free_tier',
      freeMinutesUsed: allowance.minutes_used,
      freeMinutesLimit: FREE_TIER_MINUTES
    };
  }

  console.log(`❌ Free tier exhausted: ${allowance.minutes_used}/${FREE_TIER_MINUTES} minutes used`);
  return {
    allowed: false,
    reason: 'limit_exceeded',
    freeMinutesUsed: allowance.minutes_used,
    freeMinutesLimit: FREE_TIER_MINUTES
  };
}

export async function incrementFreeTierUsage(deviceId, minutes) {
  const stmt = db.prepare(`
    UPDATE free_allowance
    SET minutes_used = minutes_used + ?,
        updated_at = ?
    WHERE device_id = ?
  `);

  await stmt.run(Math.ceil(minutes), new Date().toISOString(), deviceId);
}
