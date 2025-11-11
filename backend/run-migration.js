import { config } from 'dotenv';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { readFileSync } from 'fs';
import pkg from 'pg';
const { Pool } = pkg;

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load .env file
config({ path: join(__dirname, '.env') });

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) {
  console.error('❌ DATABASE_URL not found. Make sure you have a .env file or run with: railway run node run-migration.js');
  process.exit(1);
}

console.log('🔄 Connecting to database...');

const pool = new Pool({
  connectionString: databaseUrl,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

async function runMigration() {
  const client = await pool.connect();

  try {
    console.log('✅ Connected to database');
    console.log('📝 Reading migration file...');

    const migrationSQL = readFileSync(join(__dirname, 'migrations', '001_add_entitlements.sql'), 'utf-8');

    console.log('🚀 Running migration...');

    await client.query(migrationSQL);

    console.log('✅ Migration completed successfully!');
    console.log('\n📊 Verifying tables...');

    const result = await client.query(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name IN ('entitlements', 'device_entitlements', 'free_allowance')
      ORDER BY table_name;
    `);

    console.log('\n✅ Tables created:');
    result.rows.forEach(row => {
      console.log(`   ✓ ${row.table_name}`);
    });

    const columnsResult = await client.query(`
      SELECT column_name
      FROM information_schema.columns
      WHERE table_name = 'sessions'
        AND column_name IN ('original_transaction_id', 'entitlement_checked_at')
      ORDER BY column_name;
    `);

    console.log('\n✅ Columns added to sessions:');
    columnsResult.rows.forEach(row => {
      console.log(`   ✓ ${row.column_name}`);
    });

    console.log('\n🎉 All done! Database is ready for monetization.');

  } catch (error) {
    console.error('❌ Migration failed:', error.message);
    console.error('\nFull error:', error);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

runMigration();
