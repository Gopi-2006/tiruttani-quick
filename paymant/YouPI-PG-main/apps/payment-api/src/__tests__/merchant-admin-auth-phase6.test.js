import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import crypto from 'node:crypto';
import { Database, MerchantRepository, ReceivingAccountRepository, PaymentSessionRepository } from '@youpi/db';
import { PaymentStatus } from '@youpi/common';
import { createPaymentApp, startServer as startPaymentApi } from '../index.js';

describe('Phase 6 Security Hardening: Merchant Auth, Admin Auth & Webhook Secret Protection', () => {
  let apiInstance;
  let baseUrl;
  let testDb;
  let merchantRepo;
  let accountRepo;
  let sessionRepo;

  const defaultMerchantId = '00000000-0000-0000-0000-000000000001';
  const defaultApiKey = 'test_api_key_demo';
  const defaultApiKeyHash = crypto.createHash('sha256').update(defaultApiKey).digest('hex');

  const merchantBId = '00000000-0000-0000-0000-000000000099';
  const merchantBApiKey = 'sec_merchant_b_api_key_8899';
  const merchantBApiKeyHash = crypto.createHash('sha256').update(merchantBApiKey).digest('hex');
  const merchantBWebhookSecret = 'sec_wh_merchant_b_private_secret_9988';

  const dedicatedAdminKey = 'adm_secure_master_password_4455';

  before(async () => {
    // Set dedicated admin key for this test environment
    process.env.ADMIN_API_KEY = dedicatedAdminKey;
    process.env.ENFORCE_ADMIN_AUTH = 'true';

    testDb = new Database({ inMemory: true });
    merchantRepo = new MerchantRepository(testDb);
    accountRepo = new ReceivingAccountRepository(testDb);
    sessionRepo = new PaymentSessionRepository(testDb);

    apiInstance = await startPaymentApi(6219, testDb);
    baseUrl = `http://localhost:${apiInstance.port}`;

    // Seed Merchant B with distinct hashed API key and webhook secret
    merchantRepo.create({
      id: merchantBId,
      businessName: 'Merchant B Electronics',
      slug: 'merchant-b-store',
      contactEmail: 'merchantb@store.local',
      contactPhone: '9123456789',
      webhookUrl: 'http://localhost:5000/api/webhook/b',
      webhookSecret: merchantBWebhookSecret,
      apiKeyHash: merchantBApiKeyHash
    });

    accountRepo.create({
      id: '00000000-0000-0000-0000-000000000098',
      merchantId: merchantBId,
      upiId: 'merchantb@upi',
      payeeName: 'Merchant B Electronics',
      isActive: true
    });
  });

  after(async () => {
    delete process.env.ADMIN_API_KEY;
    delete process.env.ENFORCE_ADMIN_AUTH;
    delete process.env.ENFORCE_MERCHANT_AUTH;
    if (apiInstance) await apiInstance.close();
    if (testDb) testDb.close();
  });

  function request(path, options = {}) {
    return new Promise((resolve, reject) => {
      const url = new URL(path, baseUrl);
      const headers = {
        'Content-Type': 'application/json',
        ...(options.headers || {})
      };

      const req = http.request(url, {
        method: options.method || 'GET',
        headers
      }, (res) => {
        let raw = '';
        res.on('data', chunk => { raw += chunk; });
        res.on('end', () => {
          let body = null;
          try {
            body = JSON.parse(raw);
          } catch {
            body = raw;
          }
          resolve({ status: res.statusCode, headers: res.headers, body });
        });
      });

      req.on('error', reject);
      if (options.body) {
        req.write(typeof options.body === 'string' ? options.body : JSON.stringify(options.body));
      }
      req.end();
    });
  }

  // =========================================================================
  // TASK 1: MERCHANT API AUTHENTICATION & HASHED STORAGE
  // =========================================================================
  describe('Task 1: Merchant API Authentication', () => {
    test('1.1: Accepts valid API key via Authorization: Bearer <key>', async () => {
      const res = await request('/api/v1/payments', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${defaultApiKey}`
        },
        body: {
          orderId: 'AUTH-TEST-ORD-01',
          amount: '199.00'
        }
      });

      assert.equal(res.status, 201);
      assert.ok(res.body.paymentId);
      assert.equal(res.body.orderId, 'AUTH-TEST-ORD-01');
    });

    test('1.2: Accepts valid API key via X-API-Key header', async () => {
      const res = await request('/api/v1/payments', {
        method: 'POST',
        headers: {
          'x-api-key': merchantBApiKey
        },
        body: {
          orderId: 'AUTH-TEST-ORD-02',
          amount: '299.00'
        }
      });

      assert.equal(res.status, 201);
      assert.ok(res.body.paymentId);
      assert.equal(res.body.orderId, 'AUTH-TEST-ORD-02');
    });

    test('1.3: Rejects invalid merchant API key with 401 Unauthorized', async () => {
      const res = await request('/api/v1/payments', {
        method: 'POST',
        headers: {
          'Authorization': 'Bearer invalid_garbage_api_key_9999'
        },
        body: {
          orderId: 'AUTH-TEST-ORD-03',
          amount: '199.00'
        }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.error, 'Unauthorized: Invalid merchant API key.');
    });

    test('1.4: Rejects missing merchant credentials when enforcement is enabled', async () => {
      process.env.ENFORCE_MERCHANT_AUTH = 'true';
      try {
        const res = await request('/api/v1/payments', {
          method: 'POST',
          body: {
            orderId: 'AUTH-TEST-ORD-04',
            amount: '199.00'
          }
        });

        assert.equal(res.status, 401);
        assert.equal(res.body.error, 'Unauthorized: Merchant API key required.');
      } finally {
        delete process.env.ENFORCE_MERCHANT_AUTH;
      }
    });

    test('1.5: Database stores only SHA-256 hashed API keys and NEVER plaintext API keys', () => {
      const rowA = testDb.queryOne('SELECT api_key_hash FROM merchants WHERE id = ?', [defaultMerchantId]);
      assert.ok(rowA);
      assert.equal(rowA.api_key_hash, defaultApiKeyHash);
      assert.notEqual(rowA.api_key_hash, defaultApiKey);

      const rowB = testDb.queryOne('SELECT api_key_hash FROM merchants WHERE id = ?', [merchantBId]);
      assert.ok(rowB);
      assert.equal(rowB.api_key_hash, merchantBApiKeyHash);
      assert.notEqual(rowB.api_key_hash, merchantBApiKey);

      // Verify that plaintext key does not exist anywhere in the merchants table
      const leakCheck = testDb.query('SELECT * FROM merchants WHERE id = ?', [merchantBId])[0];
      const serialized = JSON.stringify(leakCheck);
      assert.equal(serialized.includes(merchantBApiKey), false, 'Plaintext API key must not be present in merchant row');
    });

    test('1.6: Cross-merchant access denial: Merchant A cannot create a session claiming Merchant B ID', async () => {
      const res = await request('/api/v1/payments', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${defaultApiKey}`,
          'x-merchant-id': merchantBId
        },
        body: {
          orderId: 'AUTH-TEST-ORD-CROSS-01',
          amount: '500.00'
        }
      });

      assert.equal(res.status, 403);
      assert.equal(res.body.error, 'Forbidden: Merchant ID does not match authenticated API key credentials.');
    });

    test('1.7: Cross-merchant access denial: Merchant B cannot create a session claiming Default Merchant ID', async () => {
      const res = await request('/api/v1/payments', {
        method: 'POST',
        headers: {
          'x-api-key': merchantBApiKey
        },
        body: {
          merchantId: defaultMerchantId,
          orderId: 'AUTH-TEST-ORD-CROSS-02',
          amount: '500.00'
        }
      });

      assert.equal(res.status, 403);
      assert.equal(res.body.error, 'Forbidden: Merchant ID does not match authenticated API key credentials.');
    });

    test('1.8: Demo API key is strictly rejected in production', async () => {
      const prevEnv = process.env.NODE_ENV;
      process.env.NODE_ENV = 'production';
      try {
        const res = await request('/api/v1/payments', {
          method: 'POST',
          headers: {
            'Authorization': 'Bearer test_api_key_demo'
          },
          body: {
            orderId: 'PROD-DEMO-REJECT-ORD',
            amount: '100.00'
          }
        });
        assert.equal(res.status, 401);
        assert.equal(res.body.error, 'Unauthorized: Demo API key cannot be used in production.');
      } finally {
        process.env.NODE_ENV = prevEnv;
      }
    });

    test('1.9: API key rotation generates new secure key, revokes old key, and stores only hash', async () => {
      // 1. Rotate Merchant B's key via admin endpoint
      const rotateRes = await request(`/api/v1/admin/merchants/${merchantBId}/rotate-api-key`, {
        method: 'POST',
        headers: {
          'x-admin-key': dedicatedAdminKey
        }
      });

      assert.equal(rotateRes.status, 200);
      assert.equal(rotateRes.body.success, true);
      assert.ok(rotateRes.body.apiKey);
      const newlyProvisionedKey = rotateRes.body.apiKey;
      assert.ok(newlyProvisionedKey.startsWith('mkey_'));

      // 2. Old key is immediately revoked
      const oldKeyRes = await request('/api/v1/payments', {
        method: 'POST',
        headers: {
          'x-api-key': merchantBApiKey
        },
        body: {
          orderId: 'OLD-KEY-TEST-ORD',
          amount: '200.00'
        }
      });
      assert.equal(oldKeyRes.status, 401);
      assert.equal(oldKeyRes.body.error, 'Unauthorized: Invalid merchant API key.');

      // 3. New key is immediately active and works
      const newKeyRes = await request('/api/v1/payments', {
        method: 'POST',
        headers: {
          'x-api-key': newlyProvisionedKey
        },
        body: {
          orderId: 'NEW-KEY-TEST-ORD',
          amount: '250.00'
        }
      });
      assert.equal(newKeyRes.status, 201);
      assert.ok(newKeyRes.body.paymentId);

      // 4. Verify DB stores only the SHA-256 hash of the new key
      const expectedNewHash = crypto.createHash('sha256').update(newlyProvisionedKey).digest('hex');
      const bRow = testDb.queryOne('SELECT api_key_hash FROM merchants WHERE id = ?', [merchantBId]);
      assert.equal(bRow.api_key_hash, expectedNewHash);
      assert.notEqual(bRow.api_key_hash, newlyProvisionedKey);
    });

    test('1.10: Cross-merchant access denial on payment status and COD endpoints', async () => {
      // Create session for Merchant A
      const createRes = await request('/api/v1/payments', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${defaultApiKey}`
        },
        body: {
          orderId: 'MERCHANT-A-PRIVATE-ORD',
          amount: '800.00',
          method: 'COD'
        }
      });
      assert.equal(createRes.status, 201);
      const paymentId = createRes.body.paymentId;

      // Merchant B attempts to inspect Merchant A's payment status using Merchant B's key
      // Get the currently active key for Merchant B
      const bMerchant = merchantRepo.findById(merchantBId);
      const tempKey = 'sec_temp_inspect_b_key';
      merchantRepo.update(merchantBId, { apiKey: tempKey });

      const inspectRes = await request(`/api/v1/payments/${paymentId}`, {
        headers: {
          'x-api-key': tempKey
        }
      });
      assert.equal(inspectRes.status, 403);
      assert.equal(inspectRes.body.error, 'Forbidden: You do not own this payment session.');

      // Merchant B attempts to fetch COD customer info for Merchant A's payment
      const codRes = await request(`/api/v1/payments/${paymentId}/cod`, {
        headers: {
          'x-api-key': tempKey
        }
      });
      assert.equal(codRes.status, 403);
      assert.equal(codRes.body.error, 'Forbidden: You do not own this payment session.');
    });
  });

  // =========================================================================
  // TASK 2: ADMIN AUTHENTICATION
  // =========================================================================
  describe('Task 2: Admin Authentication', () => {
    test('2.1: Rejects merchant webhook secret used as admin credential (CRITICAL FIX)', async () => {
      // Attempt to access admin endpoint using Merchant B webhook secret
      const res = await request('/api/v1/admin/all-settings', {
        headers: {
          'x-admin-key': merchantBWebhookSecret
        }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error, 'Unauthorized: Invalid administrative credentials.');
    });

    test('2.2: Rejects default merchant webhook secret as admin credential', async () => {
      const defaultWhSecret = 'merchant_webhook_secret_for_wallet_store';
      const res = await request('/api/v1/admin/merchant-settings', {
        headers: {
          'x-admin-key': defaultWhSecret
        }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
    });

    test('2.3: Accepts valid dedicated ADMIN_API_KEY via x-admin-key', async () => {
      const res = await request('/api/v1/admin/all-settings', {
        headers: {
          'x-admin-key': dedicatedAdminKey
        }
      });

      assert.equal(res.status, 200);
      assert.ok(res.body.merchantId);
      assert.equal(res.body.businessName, 'YOUPI Demo Store');
    });

    test('2.4: Accepts valid dedicated ADMIN_API_KEY via Authorization: Bearer', async () => {
      const res = await request('/api/v1/admin/merchant-settings', {
        headers: {
          'Authorization': `Bearer ${dedicatedAdminKey}`
        }
      });

      assert.equal(res.status, 200);
      assert.ok(res.body.merchantId);
    });

    test('2.5: Rejects missing admin credentials when ENFORCE_ADMIN_AUTH is true', async () => {
      const res = await request('/api/v1/admin/all-settings');
      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error, 'Unauthorized: Valid administrative credentials required.');
    });

    test('2.6: Server startup checks: Throws fatal error in production when dedicated admin credentials missing', () => {
      const origNodeEnv = process.env.NODE_ENV;
      const origAdminKey = process.env.ADMIN_API_KEY;
      const origAdminPwd = process.env.INITIAL_ADMIN_PASSWORD;
      const origJwtSecret = process.env.JWT_SECRET;

      try {
        process.env.NODE_ENV = 'production';
        delete process.env.ADMIN_API_KEY;
        delete process.env.INITIAL_ADMIN_PASSWORD;
        delete process.env.JWT_SECRET;

        assert.throws(() => {
          createPaymentApp(new Database({ inMemory: true }));
        }, /Production startup aborted: Missing required dedicated administrative credentials/);
      } finally {
        process.env.NODE_ENV = origNodeEnv;
        if (origAdminKey) process.env.ADMIN_API_KEY = origAdminKey;
        if (origAdminPwd) process.env.INITIAL_ADMIN_PASSWORD = origAdminPwd;
        if (origJwtSecret) process.env.JWT_SECRET = origJwtSecret;
      }
    });
  });

  // =========================================================================
  // TASK 3: WEBHOOK SECRET EXPOSURE PREVENTION
  // =========================================================================
  describe('Task 3: Webhook Secret Exposure Prevention', () => {
    test('3.1: GET /api/v1/admin/merchant-settings never returns raw webhookSecret', async () => {
      const res = await request('/api/v1/admin/merchant-settings', {
        headers: {
          'x-admin-key': dedicatedAdminKey
        }
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.webhookSecret, undefined, 'webhookSecret must not be present in GET settings response');
      assert.equal(res.body.webhookSecretConfigured, true);
    });

    test('3.2: GET /api/v1/admin/all-settings never returns raw webhookSecret', async () => {
      const res = await request('/api/v1/admin/all-settings', {
        headers: {
          'x-admin-key': dedicatedAdminKey
        }
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.webhookSecret, undefined, 'webhookSecret must not be present in GET all-settings response');
      assert.equal(res.body.webhookSecretConfigured, true);
    });

    test('3.3: POST /api/v1/admin/merchant-settings accepts updates without echoing secret in response', async () => {
      const newSecret = 'sec_brand_new_rotated_secret_998877';
      const res = await request('/api/v1/admin/merchant-settings', {
        method: 'POST',
        headers: {
          'x-admin-key': dedicatedAdminKey
        },
        body: {
          webhookUrl: 'https://myshop.com/events/wh',
          webhookSecret: newSecret
        }
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.webhookUrl, 'https://myshop.com/events/wh');
      assert.equal(res.body.webhookSecret, undefined, 'Submitted secret must not be echoed back in response');
      assert.equal(res.body.webhookSecretConfigured, true);

      // Verify that the secret was indeed updated in the database
      const row = testDb.queryOne('SELECT webhook_secret FROM merchants WHERE id = ?', [defaultMerchantId]);
      assert.equal(row.webhook_secret, newSecret);
    });

    test('3.4: POST /api/v1/admin/all-settings accepts updates without echoing secret in response', async () => {
      const newSecret2 = 'sec_another_rotated_secret_112233';
      const res = await request('/api/v1/admin/all-settings', {
        method: 'POST',
        headers: {
          'x-admin-key': dedicatedAdminKey
        },
        body: {
          webhookSecret: newSecret2
        }
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.webhookSecret, undefined, 'Submitted secret must not be echoed back in response');
      assert.equal(res.body.webhookSecretConfigured, true);

      const row = testDb.queryOne('SELECT webhook_secret FROM merchants WHERE id = ?', [defaultMerchantId]);
      assert.equal(row.webhook_secret, newSecret2);
    });
  });

  // =========================================================================
  // TASK 4: PRESERVE FLOWS (COD, CHECKOUT, TERMINAL STATE)
  // =========================================================================
  describe('Task 4: Preservation of Core Invariants', () => {
    test('4.1: Preserves Cash on Delivery payment creation and COD info lookup', async () => {
      const createCodRes = await request('/api/v1/payments', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${defaultApiKey}`
        },
        body: {
          orderId: 'COD-PRESERVE-ORD-01',
          amount: '750.00',
          method: 'COD'
        }
      });

      assert.equal(createCodRes.status, 201);
      assert.ok(createCodRes.body.paymentId);
      assert.equal(createCodRes.body.status, PaymentStatus.INITIATED);

      // Query COD info via GET /api/v1/orders/:orderId/cod
      const codInfoRes = await request('/api/v1/orders/COD-PRESERVE-ORD-01/cod', {
        headers: {
          'Authorization': `Bearer ${defaultApiKey}`
        }
      });

      assert.equal(codInfoRes.status, 200);
      assert.equal(codInfoRes.body.isCod, true);
      assert.equal(codInfoRes.body.amount, '750.00');

      // Also verify physical counter cash payment starts as ACTIVE
      const createCashRes = await request('/api/v1/payments', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${defaultApiKey}`
        },
        body: {
          orderId: 'CASH-PRESERVE-ORD-01',
          amount: '120.00',
          method: 'CASH_COUNTER'
        }
      });
      assert.equal(createCashRes.status, 201);
      assert.equal(createCashRes.body.status, PaymentStatus.ACTIVE);
    });

    test('4.2: Preserves idempotency on duplicate payment creation', async () => {
      const res1 = await request('/api/v1/payments', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${defaultApiKey}`
        },
        body: {
          orderId: 'IDEMP-TEST-ORD-01',
          amount: '350.00'
        }
      });
      assert.equal(res1.status, 201);

      // Re-send same order
      const res2 = await request('/api/v1/payments', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${defaultApiKey}`
        },
        body: {
          orderId: 'IDEMP-TEST-ORD-01',
          amount: '350.00'
        }
      });

      assert.equal(res2.status, 200);
      assert.equal(res2.body.paymentId, res1.body.paymentId);
      assert.equal(res2.body.activeSessionDetected, true);
    });
  });
});
