import { test, describe, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { Database, runMigrations, MerchantRepository } from '../index.js';

describe('Merchant Credential Hardening & Rotation Tests', () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    delete process.env.YOUPI_MERCHANT_API_KEY;
    delete process.env.COIN_STORE_WEBHOOK_URL;
    delete process.env.COIN_STORE_WEBHOOK_SECRET;
    delete process.env.YOUPI_WEBHOOK_URL;
    delete process.env.YOUPI_WEBHOOK_SECRET;
    delete process.env.FORCE_MERCHANT_CREDENTIAL_SYNC;
    delete process.env.NODE_ENV;
  });

  afterEach(() => {
    for (const key of Object.keys(process.env)) {
      if (!(key in originalEnv)) {
        delete process.env[key];
      }
    }
    Object.assign(process.env, originalEnv);
  });

  test('1. Initial merchant receives SHA-256 hash of YOUPI_MERCHANT_API_KEY and configured webhook credentials', () => {
    const rawApiKey = 'stage_test_api_key_xyz_12345';
    const rawWebhookSecret = 'stage_test_webhook_secret_abc_67890';
    const rawWebhookUrl = 'https://us-central1-blinkit-grocery-c3f5d.cloudfunctions.net/youpiWebhook';

    process.env.YOUPI_MERCHANT_API_KEY = rawApiKey;
    process.env.COIN_STORE_WEBHOOK_SECRET = rawWebhookSecret;
    process.env.COIN_STORE_WEBHOOK_URL = rawWebhookUrl;

    const db = new Database({ inMemory: true });
    const { defaultMerchant } = runMigrations(db);

    const expectedApiKeyHash = crypto.createHash('sha256').update(rawApiKey).digest('hex');

    assert.ok(defaultMerchant);
    assert.equal(defaultMerchant.apiKeyHash, expectedApiKeyHash);
    assert.equal(defaultMerchant.webhookSecret, rawWebhookSecret);
    assert.equal(defaultMerchant.webhookUrl, rawWebhookUrl);

    // Verify plaintext API key is NEVER stored
    assert.equal(defaultMerchant.apiKey, undefined);

    db.close();
  });

  test('2. Ordinary restarts PRESERVE existing credentials even if environment changes', () => {
    const initialKey = 'initial_key_111';
    const initialSecret = 'initial_secret_111';
    const initialUrl = 'https://mygateway.com/webhook-initial';

    process.env.YOUPI_MERCHANT_API_KEY = initialKey;
    process.env.COIN_STORE_WEBHOOK_SECRET = initialSecret;
    process.env.COIN_STORE_WEBHOOK_URL = initialUrl;

    const db = new Database({ inMemory: true });
    const { defaultMerchant: firstBoot } = runMigrations(db);
    const initialHash = firstBoot.apiKeyHash;

    // Simulate subsequent restart with different environment variables
    process.env.YOUPI_MERCHANT_API_KEY = 'accidental_different_key_222';
    process.env.COIN_STORE_WEBHOOK_SECRET = 'accidental_different_secret_222';
    process.env.COIN_STORE_WEBHOOK_URL = 'https://mygateway.com/webhook-changed';

    // Run migration again on existing database (simulating restart)
    const { defaultMerchant: restartBoot } = runMigrations(db);

    // Credentials must NOT have changed
    assert.equal(restartBoot.apiKeyHash, initialHash);
    assert.equal(restartBoot.webhookSecret, initialSecret);
    assert.equal(restartBoot.webhookUrl, initialUrl);

    db.close();
  });

  test('3. Missing YOUPI_MERCHANT_API_KEY in production throws fatal error', () => {
    process.env.NODE_ENV = 'production';
    process.env.COIN_STORE_WEBHOOK_URL = 'https://mygateway.com/webhook';
    process.env.COIN_STORE_WEBHOOK_SECRET = 'my_secure_secret';

    const db = new Database({ inMemory: true });

    assert.throws(
      () => runMigrations(db),
      /YOUPI_MERCHANT_API_KEY must be provided/
    );

    db.close();
  });

  test('4. Missing webhook URL in production throws fatal error', () => {
    process.env.NODE_ENV = 'production';
    process.env.YOUPI_MERCHANT_API_KEY = 'prod_api_key_xyz';
    process.env.COIN_STORE_WEBHOOK_SECRET = 'my_secure_secret';

    const db = new Database({ inMemory: true });

    assert.throws(
      () => runMigrations(db),
      /Webhook destination URL .* must be provided/
    );

    db.close();
  });

  test('5. Localhost webhook URL in production throws fatal error', () => {
    process.env.NODE_ENV = 'production';
    process.env.YOUPI_MERCHANT_API_KEY = 'prod_api_key_xyz';
    process.env.COIN_STORE_WEBHOOK_URL = 'http://localhost:5000/api/webhook';
    process.env.COIN_STORE_WEBHOOK_SECRET = 'my_secure_secret';

    const db = new Database({ inMemory: true });

    assert.throws(
      () => runMigrations(db),
      /cannot point to localhost in production/
    );

    db.close();
  });

  test('6. Missing webhook secret in production throws fatal error', () => {
    process.env.NODE_ENV = 'production';
    process.env.YOUPI_MERCHANT_API_KEY = 'prod_api_key_xyz';
    process.env.COIN_STORE_WEBHOOK_URL = 'https://mygateway.com/webhook';

    const db = new Database({ inMemory: true });

    assert.throws(
      () => runMigrations(db),
      /Webhook signing secret .* must be provided/
    );

    db.close();
  });

  test('7. Explicit credential rotation succeeds when FORCE_MERCHANT_CREDENTIAL_SYNC=true', () => {
    const key1 = 'first_key_version';
    const secret1 = 'first_secret_version';
    const url1 = 'https://service.com/webhook1';

    process.env.YOUPI_MERCHANT_API_KEY = key1;
    process.env.COIN_STORE_WEBHOOK_SECRET = secret1;
    process.env.COIN_STORE_WEBHOOK_URL = url1;

    const db = new Database({ inMemory: true });
    runMigrations(db);

    // Now intentionally rotate with new secret version
    const key2 = 'second_rotated_key_version';
    const secret2 = 'second_rotated_secret_version';
    const url2 = 'https://service.com/webhook2';

    process.env.YOUPI_MERCHANT_API_KEY = key2;
    process.env.COIN_STORE_WEBHOOK_SECRET = secret2;
    process.env.COIN_STORE_WEBHOOK_URL = url2;
    process.env.FORCE_MERCHANT_CREDENTIAL_SYNC = 'true';

    const { defaultMerchant: rotatedMerchant } = runMigrations(db);
    const expectedNewHash = crypto.createHash('sha256').update(key2).digest('hex');

    assert.equal(rotatedMerchant.apiKeyHash, expectedNewHash);
    assert.equal(rotatedMerchant.webhookSecret, secret2);
    assert.equal(rotatedMerchant.webhookUrl, url2);

    db.close();
  });
});
