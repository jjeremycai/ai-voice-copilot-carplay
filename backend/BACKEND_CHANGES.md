# Backend Implementation Summary

## Files Created

### 1. migrations/001_add_entitlements.sql
Database schema for entitlements, device linking, and free tier tracking.

**Tables Added:**
- `entitlements` - Apple subscription status
- `device_entitlements` - Device to subscription mapping
- `free_allowance` - Free tier usage (10 min/month per device)

**Columns Added to `sessions`:**
- `original_transaction_id`
- `entitlement_checked_at`

### 2. services/appleStoreKit.js
Apple App Store Connect API integration.

**Functions:**
- `verifyTransaction(transactionJWS)` - Verify Apple transaction
- `parseAppStoreServerNotification(signedPayload)` - Parse ASN webhook
- `generateAppStoreConnectToken()` - Generate JWT for Apple API
- `isConfigured()` - Check if Apple credentials are set

### 3. routes/iap.js
IAP endpoints for transaction verification and webhook.

**Endpoints:**
- `POST /iap/verify` - Verify Apple transaction, cache entitlement
- `POST /iap/apple-asn` - Apple Server Notifications webhook

**Dev Mode:**
If Apple credentials not set, `/iap/verify` returns success for all transactions (dev mode).

### 4. middleware/entitlementCheck.js
Entitlement checking logic for session gating.

**Functions:**
- `checkEntitlement(deviceId)` - Check if device has active subscription or free tier
- `incrementFreeTierUsage(deviceId, minutes)` - Track free tier usage

**Logic:**
1. Check for active subscription
2. If no subscription, check free tier (10 min/month)
3. Return allowed/denied with reason

### 5. DEPLOYMENT.md
Complete deployment guide with App Store Connect setup instructions.

## Files Modified

### server.js

**Imports Added:**
```javascript
import iapRoutes from './routes/iap.js';
import { checkEntitlement, incrementFreeTierUsage } from './middleware/entitlementCheck.js';
```

**Routes Added:**
```javascript
app.use('/iap', iapRoutes);
```

**POST /v1/sessions/start - Updated:**
- Added entitlement check before session creation
- Returns 402 if free tier exhausted and no subscription
- Stores `original_transaction_id` and `entitlement_checked_at` in session

**POST /v1/sessions/end - Updated:**
- Tracks free tier usage if session used free tier (no subscription)
- Increments minutes used for the device

**authenticateToken - Updated:**
- Added `req.deviceId = token` to pass device ID to entitlement check

## Dependencies Added

```bash
npm install jsonwebtoken node-jose
```

## Environment Variables Required

```bash
ASC_ISSUER_ID=your-issuer-id
ASC_KEY_ID=your-key-id
ASC_PRIVATE_KEY_P8=base64-encoded-private-key
ASC_ENV=Sandbox  # or Production
ASN_SHARED_SECRET=your-shared-secret
```

## How It Works

### Session Start Flow

1. User starts session via iOS app
2. iOS sends auth token (device ID) with request
3. Backend extracts device ID
4. Backend checks entitlement:
   - Active subscription? → Allow
   - No subscription but free tier available? → Allow
   - No subscription and free tier exhausted? → Deny (402)
5. If allowed, create session and store entitlement info
6. Return LiveKit credentials to iOS

### Session End Flow

1. User ends session with duration
2. Backend checks if session used subscription or free tier
3. If free tier, increment usage: `free_allowance.minutes_used += duration`
4. Next session start will check against updated usage

### IAP Verification Flow

1. iOS completes purchase via StoreKit 2
2. iOS sends transaction JWS to `/iap/verify`
3. Backend decodes and verifies JWS
4. Backend upserts `entitlements` table
5. Backend links device to entitlement in `device_entitlements`
6. Backend returns entitlement status to iOS
7. iOS caches locally (15-minute TTL)

### Apple Server Notifications Flow

1. Apple sends webhook to `/iap/apple-asn` on renewal/expiration/refund
2. Backend parses signed notification
3. Backend updates entitlement status in database
4. Next session start will see updated status

## Testing

### Dev Mode (No Apple Credentials)
- All transactions succeed
- Free tier still enforced (for testing gating)

### Sandbox Mode (With Apple Credentials)
- Real Apple API verification
- Use sandbox tester accounts
- Create test subscriptions in App Store Connect

### Production Mode
- Set `ASC_ENV=Production`
- Real subscriptions
- Real money

## Security

- JWT tokens generated with ES256 algorithm
- Transactions verified with Apple's public key
- Rate limiting recommended for `/iap/verify` (10 req/min per device)
- Shared secret validates ASN webhook authenticity
- No secrets logged (only masked tokens)

## Monitoring

### Key Metrics to Track

- Entitlement checks: allowed vs denied
- Free tier usage distribution
- Subscription verification success rate
- ASN webhook processing
- Session start failures (402 errors)
- Active subscriptions count by product ID

### Logs to Watch

- `✅ Active subscription found: {txId}`
- `✅ Free tier available: X/10 minutes used`
- `❌ Free tier exhausted: 10/10 minutes used`
- `🚫 Session blocked for device ... - limit_exceeded`
- `📊 Free tier usage incremented: X minutes`
- `✅ Entitlement verified: {txId} - active`
- `📬 ASN received: DID_RENEW`

## Troubleshooting

### "Provisioning profile doesn't include com.apple.developer.carplay-communication"
Pre-existing CarPlay entitlement issue. Not related to monetization. Temporarily remove CarPlay entitlements to test.

### "Apple StoreKit not configured - allowing all transactions"
Apple credentials not set. Backend is in dev mode. All transactions succeed, but free tier is still enforced.

### Session blocked with 402
Free tier exhausted. User needs to subscribe or wait for next month.

### ASN webhook not receiving events
1. Check URL in App Store Connect matches Railway URL
2. Verify Version 2 notifications enabled
3. Check shared secret matches
4. Look for errors in Railway logs

## Next Steps for Deployment

1. **Run Migration:**
   ```bash
   railway run psql -f migrations/001_add_entitlements.sql
   ```

2. **Set Environment Variables:**
   ```bash
   railway variables set ASC_ISSUER_ID=...
   railway variables set ASC_KEY_ID=...
   railway variables set ASC_PRIVATE_KEY_P8=...
   railway variables set ASC_ENV=Sandbox
   railway variables set ASN_SHARED_SECRET=...
   ```

3. **Deploy:**
   ```bash
   git push  # Railway auto-deploys
   ```

4. **Verify:**
   ```bash
   railway logs
   curl https://your-app.up.railway.app/health
   ```

5. **Test End-to-End:**
   - iOS app → Purchase subscription
   - iOS app → Start session (should work)
   - iOS app → End session
   - Railway logs → Check entitlement verified

## Complete! 🎉

Backend is fully implemented and ready for deployment. See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed setup instructions.
