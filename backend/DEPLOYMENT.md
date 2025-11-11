# Shaw Backend Deployment Guide

## Environment Variables

Add these to your Railway project:

### Required - LiveKit (Already Configured)
```bash
LIVEKIT_API_KEY=your-api-key
LIVEKIT_API_SECRET=your-secret
LIVEKIT_URL=wss://your-project.livekit.cloud
```

### Required - OpenAI
```bash
OPENAI_API_KEY=your-openai-key
```

### Required - Database
```bash
DATABASE_URL=postgresql://user:pass@host:port/database
```

### Required - Apple App Store Connect (NEW)
```bash
# Get these from App Store Connect
ASC_ISSUER_ID=your-issuer-id
ASC_KEY_ID=your-key-id
ASC_PRIVATE_KEY_P8=base64-encoded-private-key

# Use 'Sandbox' for development, 'Production' for live
ASC_ENV=Sandbox

# Shared secret from App Store Connect (for webhook verification)
ASN_SHARED_SECRET=your-shared-secret
```

## Setting Up Apple App Store Connect

### 1. Generate API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to Users and Access → Keys → App Store Connect API
3. Click "+" to create a new key
4. Select "App Manager" role
5. Download the `.p8` file (save it securely!)
6. Note the Issuer ID and Key ID displayed

### 2. Convert P8 to Base64

```bash
base64 -i AuthKey_YOUR_KEY_ID.p8 | tr -d '\n'
```

Copy the output and set it as `ASC_PRIVATE_KEY_P8`.

### 3. Configure Server Notifications

1. Go to your app in App Store Connect
2. Navigate to App Information → App Store Server Notifications
3. Set Production URL: `https://shaw.up.railway.app/iap/apple-asn`
4. Set Sandbox URL: `https://shaw.up.railway.app/iap/apple-asn`
5. Enable Version 2 notifications
6. Copy the Shared Secret and set it as `ASN_SHARED_SECRET`

### 4. Create Subscription Products

1. In App Store Connect, go to your app → Subscriptions
2. Create Subscription Group: "Shaw Pro"
3. Add two products:
   - **Monthly**: `com.vanities.shaw.pro.month` - $9.99/month
   - **Yearly**: `com.vanities.shaw.pro.year` - $79.99/year

## Database Migration

Run the migration to add entitlement tables:

```bash
# Connect to your Railway PostgreSQL
railway run psql -f migrations/001_add_entitlements.sql
```

Or manually execute the SQL from `migrations/001_add_entitlements.sql`.

### New Tables Created

- `entitlements` - Apple subscription status (source of truth)
- `device_entitlements` - Links devices to subscriptions
- `free_allowance` - Tracks 10 min/month free tier per device

### Columns Added to `sessions`

- `original_transaction_id` - Links session to Apple subscription
- `entitlement_checked_at` - Timestamp of entitlement check

## Testing the Backend

### 1. Health Check

```bash
curl https://your-app.up.railway.app/health
```

### 2. Test IAP Verification (Dev Mode)

If Apple credentials are not set, the backend allows all transactions:

```bash
curl -X POST https://your-app.up.railway.app/iap/verify \
  -H "Authorization: Bearer device_test_123" \
  -H "Content-Type: application/json" \
  -d '{
    "transactionJWS": "fake-jws",
    "deviceId": "device_test_123",
    "appVersion": "1.0.0",
    "environment": "Sandbox"
  }'
```

### 3. Test Session Start with Entitlement

```bash
curl -X POST https://your-app.up.railway.app/v1/sessions/start \
  -H "Authorization: Bearer device_test_123" \
  -H "Content-Type: application/json" \
  -d '{
    "context": "phone",
    "realtime": true
  }'
```

Expected responses:
- **200** - Session started (has subscription or free tier available)
- **402** - Entitlement required (free tier exhausted)

```json
{
  "error": "ENTITLEMENT_REQUIRED",
  "message": "Subscription required. Free tier limit reached (10 min/month).",
  "freeMinutesUsed": 10,
  "freeMinutesLimit": 10
}
```

## Railway Deployment

### Set Environment Variables

```bash
railway variables set ASC_ISSUER_ID=your-issuer-id
railway variables set ASC_KEY_ID=your-key-id
railway variables set ASC_PRIVATE_KEY_P8=your-base64-key
railway variables set ASC_ENV=Sandbox
railway variables set ASN_SHARED_SECRET=your-shared-secret
```

### Deploy

Railway automatically deploys on push. Or manually:

```bash
railway up
```

### Verify Deployment

```bash
railway logs
```

Look for:
- ✅ PostgreSQL tables created/verified
- ✅ Loaded .env file successfully
- ✅ LiveKit configuration is valid
- 🚀 Server running on http://localhost:3000

## Security Notes

- **Never commit** `.env` file or `.p8` files to git
- Store credentials in Railway secrets only
- Use `ASC_ENV=Sandbox` for development
- Switch to `ASC_ENV=Production` for live release
- Rate limit `/iap/verify` in production (10 req/min per device)

## API Endpoints

### IAP Endpoints

- **POST /iap/verify** - Verify Apple transaction and cache entitlement
- **POST /iap/apple-asn** - Apple Server Notifications webhook (v2)

### Session Endpoints (Updated)

- **POST /v1/sessions/start** - Now checks entitlements before allowing session
- **POST /v1/sessions/end** - Tracks free tier usage if no subscription

## Troubleshooting

### "Apple StoreKit not configured - allowing all transactions"

This warning means the backend is in **dev mode** and will allow all sessions. Set the Apple credentials to enable real entitlement checking.

### "Session blocked - limit_exceeded"

Free tier is exhausted (10 minutes used this month). User needs to subscribe.

### "ASN processing error"

Check that:
1. Shared secret matches App Store Connect
2. URL is set correctly in App Store Connect
3. Version 2 notifications are enabled

### Database Migration Issues

If tables don't exist:
```bash
railway run psql -c "SELECT tablename FROM pg_tables WHERE schemaname='public';"
```

Should show: `entitlements`, `device_entitlements`, `free_allowance`

## Monitoring

Track these metrics:
- Entitlement checks (allowed vs denied)
- Free tier usage distribution
- Subscription verification rate
- ASN webhook processing success/failure
- Session start failures (402 errors)

## Support

For issues:
1. Check Railway logs: `railway logs`
2. Verify environment variables: `railway variables`
3. Test endpoints with curl
4. Check database tables exist
5. Verify App Store Connect configuration
