import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';
import { getDatabase } from './database.js';
import { MerchantRepository } from './repositories/merchant.repository.js';
import { ReceivingAccountRepository } from './repositories/receiving-account.repository.js';
import { CustomerRepository } from './repositories/customer.repository.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function seedDefaults(db) {
  const isProd = process.env.NODE_ENV === 'production';
  const forceSync = process.env.FORCE_MERCHANT_CREDENTIAL_SYNC === 'true';

  // 1. Merchant API Key Validation & Hashing
  const defaultApiKey = process.env.YOUPI_MERCHANT_API_KEY || (isProd ? null : 'test_api_key_demo');
  if (isProd && !defaultApiKey) {
    throw new Error('[FATAL] Production configuration error: YOUPI_MERCHANT_API_KEY must be provided.');
  }
  const defaultApiKeyHash = defaultApiKey ? crypto.createHash('sha256').update(defaultApiKey).digest('hex') : null;

  // 2. Webhook Destination URL Validation (no silent localhost in production)
  const rawWebhookUrl = process.env.COIN_STORE_WEBHOOK_URL || process.env.YOUPI_WEBHOOK_URL;
  let webhookUrl = rawWebhookUrl;
  if (!webhookUrl) {
    if (isProd) {
      throw new Error('[FATAL] Production configuration error: Webhook destination URL (COIN_STORE_WEBHOOK_URL or YOUPI_WEBHOOK_URL) must be provided.');
    }
    webhookUrl = 'http://localhost:5000/api/webhook';
  } else if (isProd && (webhookUrl.includes('localhost') || webhookUrl.includes('127.0.0.1'))) {
    throw new Error('[FATAL] Production configuration error: Webhook destination URL cannot point to localhost in production.');
  }

  // 3. Webhook Signing Secret Validation
  const rawWebhookSecret = process.env.COIN_STORE_WEBHOOK_SECRET || process.env.YOUPI_WEBHOOK_SECRET;
  let webhookSecret = rawWebhookSecret;
  if (!webhookSecret) {
    if (isProd) {
      throw new Error('[FATAL] Production configuration error: Webhook signing secret (COIN_STORE_WEBHOOK_SECRET or YOUPI_WEBHOOK_SECRET) must be provided.');
    }
    webhookSecret = 'merchant_webhook_secret_for_wallet_store';
  }

  const merchantRepo = new MerchantRepository(db);
  const accountRepo = new ReceivingAccountRepository(db);
  const customerRepo = new CustomerRepository(db);

  if (db.dialect === 'postgres') {
    return (async () => {
      const existing = await merchantRepo.findAll();
      let defaultMerchant;
      if (!existing || existing.length === 0) {
        defaultMerchant = await merchantRepo.create({
          id: '00000000-0000-0000-0000-000000000001',
          businessName: 'YOUPI Demo Store',
          slug: 'demo-store',
          contactEmail: 'merchant@youpi.local',
          contactPhone: '9876543210',
          webhookUrl: webhookUrl,
          webhookSecret: webhookSecret,
          apiKeyHash: defaultApiKeyHash,
          branding: {
            appName: 'YOUPI PG',
            primaryColor: '#2563eb',
            logoUrl: null
          }
        });
      } else {
        defaultMerchant = existing[0];
        const updates = {};
        // Ordinary restarts preserve existing credentials.
        // Explicit rotation occurs only if forceSync=true or if existing field was uninitialized.
        if (defaultApiKeyHash && (!defaultMerchant.apiKeyHash || (forceSync && defaultMerchant.apiKeyHash !== defaultApiKeyHash))) {
          updates.apiKeyHash = defaultApiKeyHash;
        }
        if (webhookSecret && (!defaultMerchant.webhookSecret || (forceSync && defaultMerchant.webhookSecret !== webhookSecret))) {
          updates.webhookSecret = webhookSecret;
        }
        if (webhookUrl && (!defaultMerchant.webhookUrl || (forceSync && defaultMerchant.webhookUrl !== webhookUrl))) {
          updates.webhookUrl = webhookUrl;
        }
        if (Object.keys(updates).length > 0) {
          defaultMerchant = await merchantRepo.update(defaultMerchant.id, updates);
        }
      }

      const accounts = await accountRepo.findByMerchantId(defaultMerchant.id);
      if (!accounts || accounts.length === 0) {
        await accountRepo.create({
          id: '00000000-0000-0000-0000-000000000002',
          merchantId: defaultMerchant.id,
          upiId: 'merchant@upi',
          payeeName: defaultMerchant.businessName,
          isActive: true
        });
      }

      const existingCust = await customerRepo.findByMobile('9212339720');
      if (!existingCust) {
        await customerRepo.create({
          id: '00000000-0000-0000-0000-000000000002',
          name: 'Gaurav Mehra',
          email: 'gauravmehra09876@gmail.com',
          mobileNumber: '9212339720',
          isPhoneVerified: true
        });
      }

      return { db, defaultMerchant };
    })();
  }

  // SQLite Synchronous Seed Execution
  const existing = merchantRepo.findAll();
  let defaultMerchant;
  if (!existing || existing.length === 0) {
    defaultMerchant = merchantRepo.create({
      id: '00000000-0000-0000-0000-000000000001',
      businessName: 'YOUPI Demo Store',
      slug: 'demo-store',
      contactEmail: 'merchant@youpi.local',
      contactPhone: '9876543210',
      webhookUrl: webhookUrl,
      webhookSecret: webhookSecret,
      apiKeyHash: defaultApiKeyHash,
      branding: {
        appName: 'YOUPI PG',
        primaryColor: '#2563eb',
        logoUrl: null
      }
    });
  } else {
    defaultMerchant = existing[0];
    const updates = {};
    if (defaultApiKeyHash && (!defaultMerchant.apiKeyHash || (forceSync && defaultMerchant.apiKeyHash !== defaultApiKeyHash))) {
      updates.apiKeyHash = defaultApiKeyHash;
    }
    if (webhookSecret && (!defaultMerchant.webhookSecret || (forceSync && defaultMerchant.webhookSecret !== webhookSecret))) {
      updates.webhookSecret = webhookSecret;
    }
    if (webhookUrl && (!defaultMerchant.webhookUrl || (forceSync && defaultMerchant.webhookUrl !== webhookUrl))) {
      updates.webhookUrl = webhookUrl;
    }
    if (Object.keys(updates).length > 0) {
      defaultMerchant = merchantRepo.update(defaultMerchant.id, updates);
    }
  }

  const accounts = accountRepo.findByMerchantId(defaultMerchant.id);
  if (!accounts || accounts.length === 0) {
    accountRepo.create({
      id: '00000000-0000-0000-0000-000000000002',
      merchantId: defaultMerchant.id,
      upiId: 'merchant@upi',
      payeeName: defaultMerchant.businessName,
      isActive: true
    });
  }

  const existingCust = customerRepo.findByMobile('9212339720');
  if (!existingCust) {
    customerRepo.create({
      id: '00000000-0000-0000-0000-000000000002',
      name: 'Gaurav Mehra',
      email: 'gauravmehra09876@gmail.com',
      mobileNumber: '9212339720',
      isPhoneVerified: true
    });
  }

  return { db, defaultMerchant };
}

/**
 * Runs database migrations and applies base seeds.
 * Supports both PostgreSQL and SQLite dialects.
 * @param {import('./database.js').Database} [targetDb]
 */
export function runMigrations(targetDb) {
  const db = targetDb || getDatabase();

  if (db.dialect === 'postgres') {
    const schemaPath = path.join(__dirname, 'schema.sql');
    const schemaSql = fs.readFileSync(schemaPath, 'utf8');
    const execRes = db.exec(schemaSql);
    if (execRes && typeof execRes.then === 'function') {
      return execRes.then(() => seedDefaults(db));
    }
    return seedDefaults(db);
  }

  // SQLite Schema Migration Execution
  const schemaPath = path.join(__dirname, 'sqlite-schema.sql');
  const schemaSql = fs.readFileSync(schemaPath, 'utf8');

  // Detect if customers table has obsolete schema
  try {
    const tableInfo = db.query ? db.query("PRAGMA table_info(customers)") : [];
    const colNames = (tableInfo || []).map(c => c.name);
    const hasOldColumns = colNames.length > 0 && (
      !colNames.includes('email') ||
      colNames.includes('phone_number') ||
      colNames.includes('merchant_id') ||
      !colNames.includes('otp_code') ||
      tableInfo.some(c => c.name === 'password_hash' && c.notnull === 1)
    );
    if (hasOldColumns) {
      try { db.exec("PRAGMA foreign_keys = OFF;"); } catch {}
      try { db.exec("UPDATE payment_sessions SET customer_id = NULL WHERE customer_id IS NOT NULL;"); } catch {}
      try { db.exec("DELETE FROM ticket_messages;"); } catch {}
      try { db.exec("DELETE FROM support_tickets;"); } catch {}
      try { db.exec("DROP TABLE IF EXISTS customer_sessions;"); } catch {}
      try { db.exec("DROP TABLE IF EXISTS customers;"); } catch {}
      try { db.exec("PRAGMA foreign_keys = ON;"); } catch {}
    }
  } catch {
    try { db.exec("PRAGMA foreign_keys = OFF;"); } catch {}
    try { db.exec("DROP TABLE IF EXISTS customers;"); } catch {}
    try { db.exec("PRAGMA foreign_keys = ON;"); } catch {}
  }

  // Fallback alter columns if customers/sessions table exists without new columns
  try { db.exec("ALTER TABLE customers ADD COLUMN email TEXT;"); } catch {}
  try { db.exec("ALTER TABLE customers ADD COLUMN mobile_number TEXT;"); } catch {}
  try { db.exec("ALTER TABLE customers ADD COLUMN otp_code TEXT;"); } catch {}
  try { db.exec("ALTER TABLE customers ADD COLUMN otp_expires_at TEXT;"); } catch {}
  try { db.exec("ALTER TABLE customers ADD COLUMN is_phone_verified INTEGER DEFAULT 0;"); } catch {}
  try { db.exec("ALTER TABLE customers ADD COLUMN ban_reason TEXT;"); } catch {}
  try { db.exec("ALTER TABLE customers ADD COLUMN banned_at TEXT;"); } catch {}
  try { db.exec("ALTER TABLE customers ADD COLUMN unbanned_at TEXT;"); } catch {}
  try { db.exec("ALTER TABLE customers ADD COLUMN last_device TEXT;"); } catch {}
  try { db.exec("ALTER TABLE payment_sessions ADD COLUMN device_id TEXT;"); } catch {}
  try { db.exec("ALTER TABLE payment_sessions ADD COLUMN verification_level INTEGER DEFAULT 0;"); } catch {}
  try { db.exec("ALTER TABLE payment_sessions ADD COLUMN verification_sources TEXT DEFAULT '[]';"); } catch {}
  try { db.exec("ALTER TABLE payment_sessions ADD COLUMN verification_tag TEXT DEFAULT 'UNVERIFIED';"); } catch {}
  try { db.exec("ALTER TABLE merchants ADD COLUMN api_key_hash TEXT;"); } catch {}

  // Execute schema DDL
  db.exec(schemaSql);

  // Alter table columns if migrating existing databases
  try { db.exec("ALTER TABLE payment_sessions ADD COLUMN verification_level INTEGER DEFAULT 0;"); } catch {}
  try { db.exec("ALTER TABLE payment_sessions ADD COLUMN verification_sources TEXT DEFAULT '[]';"); } catch {}
  try { db.exec("ALTER TABLE payment_sessions ADD COLUMN verification_tag TEXT DEFAULT 'UNVERIFIED';"); } catch {}
  try { db.exec("ALTER TABLE payment_receiving_accounts ADD COLUMN is_merchant_enabled INTEGER NOT NULL DEFAULT 1;"); } catch {}
  try { db.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_single_active_vpa_per_merchant ON payment_receiving_accounts (merchant_id) WHERE is_active = 1;"); } catch {}
  try { db.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_email ON customers (email);"); } catch {}
  try { db.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_mobile ON customers (mobile_number);"); } catch {}
  try { db.exec("ALTER TABLE customers ADD COLUMN ban_reason TEXT;"); } catch {}
  try { db.exec("ALTER TABLE customers ADD COLUMN banned_at TEXT;"); } catch {}
  try { db.exec("ALTER TABLE customers ADD COLUMN unbanned_at TEXT;"); } catch {}
  try { db.exec("ALTER TABLE customers ADD COLUMN last_device TEXT;"); } catch {}
  try { db.exec("CREATE INDEX IF NOT EXISTS idx_customer_sessions_token ON customer_sessions (token, is_active);"); } catch {}
  try { db.exec("CREATE INDEX IF NOT EXISTS idx_customer_sessions_customer ON customer_sessions (customer_id);"); } catch {}
  try { db.exec("CREATE INDEX IF NOT EXISTS idx_security_events_customer ON security_events (customer_id);"); } catch {}
  try { db.exec("CREATE INDEX IF NOT EXISTS idx_security_events_session ON security_events (payment_session_id);"); } catch {}
  try { db.exec("CREATE INDEX IF NOT EXISTS idx_security_events_type ON security_events (event_type);"); } catch {}
  try { db.exec("ALTER TABLE payment_sessions ADD COLUMN device_id TEXT REFERENCES devices(id);"); } catch {}
  try { db.exec("ALTER TABLE merchants ADD COLUMN api_key_hash TEXT;"); } catch {}
  try { db.exec("CREATE INDEX IF NOT EXISTS idx_merchants_api_key_hash ON merchants (api_key_hash);"); } catch {}

  return seedDefaults(db);
}

/**
 * Completely wipes all customer identity records and active sessions,
 * reinitializing the customer identity store to a pristine state.
 * @param {import('./database.js').Database} [targetDb]
 */
export function reinitializeCustomerIdentity(targetDb) {
  const db = targetDb || getDatabase();
  try { db.exec("PRAGMA foreign_keys = OFF;"); } catch {}
  try { db.exec("UPDATE payment_sessions SET customer_id = NULL WHERE customer_id IS NOT NULL;"); } catch {}
  try { db.exec("DELETE FROM customer_sessions;"); } catch {}
  try { db.exec("DELETE FROM customers;"); } catch {}
  try { db.exec("PRAGMA foreign_keys = ON;"); } catch {}
  return { success: true, message: 'All old customer identity records wiped and reinitialized.' };
}

// Auto-run if executed directly as script
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  console.log('Running YOUPI PG database migrations...');
  const result = runMigrations();
  if (result && typeof result.then === 'function') {
    result.then(res => {
      console.log(`Migration completed successfully. Default merchant: ${res.defaultMerchant.businessName} (${res.defaultMerchant.id})`);
    });
  } else {
    console.log(`Migration completed successfully. Default merchant: ${result.defaultMerchant.businessName} (${result.defaultMerchant.id})`);
  }
}
