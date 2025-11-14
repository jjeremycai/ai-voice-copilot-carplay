import { config } from 'dotenv';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import crypto from 'crypto';

// Get the directory of the current module
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load .env file from the backend directory
config({ path: join(__dirname, '.env') });

import db, { usePostgres } from './database.js';

async function setupTestAccount() {
  try {
    console.log('🚀 Setting up test account for App Store review...');
    
    // Test account credentials from user
    const testEmail = 'jjeremycai@gmail.com';
    const testPassword = 'helloapplefriend';
    const testUserId = 'user-test-account-001';
    
    // Create a consistent device token for the test account
    const deviceToken = 'device_test_account_001_' + crypto.randomUUID();
    
    console.log(`📧 Email: ${testEmail}`);
    console.log(`🔑 Password: ${testPassword}`);
    console.log(`🆔 User ID: ${testUserId}`);
    console.log(`📱 Device Token: ${deviceToken.substring(0, 20)}...`);
    
    // Set up user subscription (Pro tier for full access)
    const now = new Date();
    const billingPeriodStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
    const billingPeriodEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59).toISOString();
    
    // Insert or update user subscription
    const subscriptionStmt = db.prepare(`
      INSERT INTO user_subscriptions (user_id, subscription_tier, monthly_minutes_limit, billing_period_start, billing_period_end, updated_at)
      VALUES (?, 'pro', 1000, ?, ?, ?)
      ON CONFLICT (user_id) DO UPDATE SET
        subscription_tier = 'pro',
        monthly_minutes_limit = 1000,
        updated_at = ?
    `);
    
    await subscriptionStmt.run(
      testUserId,
      billingPeriodStart,
      billingPeriodEnd,
      now.toISOString(),
      now.toISOString()
    );
    
    // Initialize monthly usage for this month
    const usageId = `usage-${crypto.randomUUID()}`;
    const usageStmt = db.prepare(`
      INSERT INTO monthly_usage (id, user_id, year, month, used_minutes)
      VALUES (?, ?, ?, ?, 0)
      ON CONFLICT (user_id, year, month) DO NOTHING
    `);
    
    await usageStmt.run(
      usageId,
      testUserId,
      now.getFullYear(),
      now.getMonth() + 1
    );
    
    // Create a mock entitlement for Pro access (for App Store review)
    const entitlementId = `entitlement-${crypto.randomUUID()}`;
    const entitlementStmt = db.prepare(`
      INSERT INTO entitlements (original_transaction_id, product_id, status, expires_at, environment, last_update_at, created_at)
      VALUES (?, 'com.shaw.pro.monthly', 'active', ?, 'Production', ?, ?)
    `);
    
    const expiresAt = new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000).toISOString(); // 1 year from now
    
    await entitlementStmt.run(
      entitlementId,
      expiresAt,
      now.toISOString(),
      now.toISOString()
    );
    
    // Link device to entitlement
    const deviceEntitlementStmt = db.prepare(`
      INSERT INTO device_entitlements (device_id, original_transaction_id, last_seen_at)
      VALUES (?, ?, ?)
      ON CONFLICT (device_id, original_transaction_id) DO UPDATE SET
        last_seen_at = ?
    `);
    
    await deviceEntitlementStmt.run(
      deviceToken,
      entitlementId,
      now.toISOString(),
      now.toISOString()
    );
    
    console.log('✅ Test account setup complete!');
    console.log('');
    console.log('📋 Test Account Summary:');
    console.log(`   Email: ${testEmail}`);
    console.log(`   Password: ${testPassword}`);
    console.log(`   User ID: ${testUserId}`);
    console.log(`   Device Token: ${deviceToken}`);
    console.log(`   Subscription: Pro tier (1000 minutes/month)`);
    console.log(`   Entitlement: Active until ${expiresAt}`);
    console.log('');
    console.log('🔧 For App Store Review:');
    console.log('   - Use email/password login in the app');
    console.log('   - Or use device token for automatic authentication');
    console.log('   - Account has Pro subscription with full access');
    console.log('   - No usage limits during review period');
    
    // Return the test account details
    return {
      email: testEmail,
      password: testPassword,
      userId: testUserId,
      deviceToken: deviceToken,
      entitlementId: entitlementId
    };
    
  } catch (error) {
    console.error('❌ Error setting up test account:', error);
    throw error;
  }
}

// Run the setup
if (import.meta.url === `file://${process.argv[1]}`) {
  setupTestAccount()
    .then(() => {
      console.log('🎉 Test account setup script completed successfully!');
      process.exit(0);
    })
    .catch((error) => {
      console.error('💥 Test account setup failed:', error);
      process.exit(1);
    });
}

export default setupTestAccount;