import express from 'express';
import db, { usePostgres } from '../database.js';
import { verifyTransaction, parseAppStoreServerNotification, isConfigured } from '../services/appleStoreKit.js';

const router = express.Router();

const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'No token provided' });
  }

  req.userId = 'user-' + Buffer.from(token).toString('base64').slice(0, 10);
  req.deviceId = token;
  next();
};

router.post('/verify', authenticateToken, async (req, res) => {
  try {
    if (!isConfigured()) {
      console.warn('⚠️  Apple StoreKit not configured - allowing all transactions');
      return res.json({
        isActive: true,
        isInGrace: false,
        productId: req.body.productId || 'com.vanities.shaw.pro.month',
        originalTransactionId: 'dev-mode',
        expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString()
      });
    }

    const { transactionJWS, deviceId, appVersion, environment } = req.body;

    if (!transactionJWS || !deviceId) {
      return res.status(400).json({ error: 'Missing transactionJWS or deviceId' });
    }

    console.log(`📱 Verifying IAP for device: ${deviceId.substring(0, 20)}...`);

    const txData = await verifyTransaction(transactionJWS);

    const now = new Date();
    const stmt = db.prepare(`
      INSERT INTO entitlements (original_transaction_id, product_id, status, expires_at, environment, last_update_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT (original_transaction_id) DO UPDATE SET
        product_id = EXCLUDED.product_id,
        status = EXCLUDED.status,
        expires_at = EXCLUDED.expires_at,
        environment = EXCLUDED.environment,
        last_update_at = EXCLUDED.last_update_at
    `);

    await stmt.run(
      txData.originalTransactionId,
      txData.productId,
      txData.status,
      txData.expiresAt ? txData.expiresAt.toISOString() : null,
      txData.environment,
      now.toISOString()
    );

    const deviceStmt = db.prepare(`
      INSERT INTO device_entitlements (device_id, original_transaction_id, last_seen_at)
      VALUES (?, ?, ?)
      ON CONFLICT (device_id, original_transaction_id) DO UPDATE SET
        last_seen_at = EXCLUDED.last_seen_at
    `);

    await deviceStmt.run(deviceId, txData.originalTransactionId, now.toISOString());

    console.log(`✅ Entitlement verified: ${txData.originalTransactionId} - ${txData.status}`);

    res.json({
      isActive: txData.status === 'active' || txData.status === 'grace',
      isInGrace: txData.isInGrace,
      productId: txData.productId,
      originalTransactionId: txData.originalTransactionId,
      expiresAt: txData.expiresAt ? txData.expiresAt.toISOString() : null
    });
  } catch (error) {
    console.error('❌ IAP verification error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.post('/apple-asn', express.raw({ type: 'application/json' }), async (req, res) => {
  try {
    if (!isConfigured()) {
      console.log('⚠️  Apple StoreKit not configured - ignoring ASN');
      return res.status(200).send('OK');
    }

    const signedPayload = JSON.parse(req.body.toString()).signedPayload;

    const notification = await parseAppStoreServerNotification(signedPayload);

    console.log(`📬 ASN received: ${notification.notificationType}${notification.subtype ? ` (${notification.subtype})` : ''}`);

    const tx = notification.transaction;
    let newStatus = 'active';

    switch (notification.notificationType) {
      case 'DID_RENEW':
      case 'SUBSCRIBED':
      case 'DID_CHANGE_RENEWAL_STATUS':
        if (notification.subtype === 'AUTO_RENEW_ENABLED') {
          newStatus = 'active';
        }
        break;

      case 'EXPIRED':
      case 'GRACE_PERIOD_EXPIRED':
        newStatus = 'expired';
        break;

      case 'REFUND':
      case 'REVOKE':
        newStatus = 'revoked';
        break;

      default:
        console.log(`ℹ️  Unhandled notification type: ${notification.notificationType}`);
    }

    const stmt = db.prepare(`
      UPDATE entitlements
      SET status = ?,
          expires_at = ?,
          revoked_at = ?,
          last_update_at = ?
      WHERE original_transaction_id = ?
    `);

    await stmt.run(
      newStatus,
      tx.expiresAt ? tx.expiresAt.toISOString() : null,
      newStatus === 'revoked' ? new Date().toISOString() : null,
      new Date().toISOString(),
      tx.originalTransactionId
    );

    console.log(`✅ Updated entitlement ${tx.originalTransactionId} → ${newStatus}`);

    res.status(200).send('OK');
  } catch (error) {
    console.error('❌ ASN processing error:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;
