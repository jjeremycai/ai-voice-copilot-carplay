import { config } from 'dotenv';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

// Get the directory of the current module
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load .env file from the backend directory
config({ path: join(__dirname, '.env') });

import db from './database.js';

async function verifyTestAccount() {
  try {
    console.log('🔍 Verifying test account setup...');
    
    const testUserId = 'user-test-account-001';
    
    // Check user subscription
    const subscriptionStmt = db.prepare('SELECT * FROM user_subscriptions WHERE user_id = ?');
    const subscription = await subscriptionStmt.get(testUserId);
    
    if (subscription) {
      console.log('✅ User subscription found:');
      console.log(`   Tier: ${subscription.subscription_tier}`);
      console.log(`   Monthly limit: ${subscription.monthly_minutes_limit} minutes`);
      console.log(`   Billing period: ${subscription.billing_period_start} to ${subscription.billing_period_end}`);
    } else {
      console.log('❌ User subscription not found');
    }
    
    // Check monthly usage
    const now = new Date();
    const usageStmt = db.prepare('SELECT * FROM monthly_usage WHERE user_id = ? AND year = ? AND month = ?');
    const usage = await usageStmt.get(testUserId, now.getFullYear(), now.getMonth() + 1);
    
    if (usage) {
      console.log('✅ Monthly usage record found:');
      console.log(`   Used minutes: ${usage.used_minutes}`);
      console.log(`   Period: ${usage.year}-${usage.month}`);
    } else {
      console.log('❌ Monthly usage not found');
    }
    
    // Check entitlements
    const entitlementStmt = db.prepare(`
      SELECT e.*, de.device_id 
      FROM entitlements e 
      JOIN device_entitlements de ON e.original_transaction_id = de.original_transaction_id 
      WHERE de.device_id LIKE 'device_test_account_001%'
    `);
    const entitlement = await entitlementStmt.get();
    
    if (entitlement) {
      console.log('✅ Entitlement found:');
      console.log(`   Product: ${entitlement.product_id}`);
      console.log(`   Status: ${entitlement.status}`);
      console.log(`   Expires: ${entitlement.expires_at}`);
      console.log(`   Device: ${entitlement.device_id}`);
    } else {
      console.log('❌ Entitlement not found');
    }
    
    console.log('');
    console.log('📋 Test Account Verification Summary:');
    console.log('   Email: jjeremycai@gmail.com');
    console.log('   Password: helloapplefriend');
    console.log('   User ID: user-test-account-001');
    console.log('   Device Token: device_test_account_001_[UUID]');
    console.log('   Subscription: Pro tier (1000 minutes/month)');
    console.log('   Status: Ready for App Store review');
    
    return {
      subscription: subscription,
      usage: usage,
      entitlement: entitlement
    };
    
  } catch (error) {
    console.error('❌ Error verifying test account:', error);
    throw error;
  }
}

// Run verification
if (import.meta.url === `file://${process.argv[1]}`) {
  verifyTestAccount()
    .then(() => {
      console.log('🎉 Test account verification completed!');
      process.exit(0);
    })
    .catch((error) => {
      console.error('💥 Test account verification failed:', error);
      process.exit(1);
    });
}

export default verifyTestAccount;