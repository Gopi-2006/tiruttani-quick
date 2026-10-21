import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import crypto from 'node:crypto';
import { Database, CustomerRepository, CustomerSessionRepository, PaymentSessionRepository, MerchantRepository, ObservationRepository } from '@youpi/db';
import { PaymentStatus, ObservationAttributionStatus, ObserverSource } from '@youpi/common';
import { WebhookEngine, AttributionEngine, ObservationNormalizer } from '@youpi/core';
import { startServer as startPaymentApi } from '../index.js';

describe('Phase 1 Security Hardening Regression Suite', () => {
  let apiInstance;
  let baseUrl;
  let testDb;
  let merchantRepo;
  let sessionRepo;
  let customerRepo;
  let customerSessionRepo;
  let obsRepo;

  const merchantId = '00000000-0000-0000-0000-000000000001';
  const receivingAccountId = '00000000-0000-0000-0000-000000000002';
  const testSigningKey = 'test_secret_key_12345678901234567890';
  let deviceId;

  before(async () => {
    testDb = new Database({ inMemory: true });
    merchantRepo = new MerchantRepository(testDb);
    sessionRepo = new PaymentSessionRepository(testDb);
    customerRepo = new CustomerRepository(testDb);
    customerSessionRepo = new CustomerSessionRepository(testDb, customerRepo);
    obsRepo = new ObservationRepository(testDb);

    apiInstance = await startPaymentApi(6209, testDb);
    baseUrl = `http://localhost:${apiInstance.port}`;

    deviceId = crypto.randomUUID();
    testDb.execute(`
      INSERT INTO android_devices (id, merchant_id, device_name, device_model, signing_key_hash, is_active, last_heartbeat_at, created_at)
      VALUES (?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
    `, [deviceId, merchantId, 'Security-Test-Phone', 'Pixel 8', testSigningKey]);
  });

  after(async () => {
    if (apiInstance) await apiInstance.close();
    if (testDb) testDb.close();
  });

  beforeEach(() => {
    testDb.execute("UPDATE payment_sessions SET status = 'CANCELLED' WHERE status IN ('ACTIVE', 'PROCESSING', 'QUEUED')");
    testDb.execute('UPDATE payment_receiving_accounts SET is_slot_busy = 0, current_active_session_id = NULL WHERE id = ?', [receivingAccountId]);
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
      }, res => {
        let data = '';
        res.on('data', chunk => { data += chunk; });
        res.on('end', () => {
          let body;
          try {
            body = JSON.parse(data);
          } catch {
            body = data;
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
  // 1. ADMIN API SECURITY & AUTHORIZATION
  // =========================================================================
  describe('1. Admin API Authorization & Session Id Isolation', () => {
    test('Customer session tokens are strictly rejected from admin endpoints (403 Forbidden)', async () => {
      // Create customer and login session
      const cust = customerRepo.create({
        name: 'Normal Customer',
        email: 'customer@security.test',
        mobileNumber: '919999900001'
      });
      const custSession = customerSessionRepo.create({ customerId: cust.id });

      const res = await request('/api/v1/admin/queue', {
        headers: {
          'Authorization': `Bearer ${custSession.token}`
        }
      });

      assert.equal(res.status, 403);
      assert.ok(res.body.error.includes('Customer session tokens cannot access administrative'));
    });

    test('Invalid admin key is rejected with 401 Unauthorized', async () => {
      const res = await request('/api/v1/admin/queue', {
        headers: {
          'X-Admin-Key': 'completely-wrong-admin-secret-key'
        }
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
    });

    test('Possession of a payment session ID does NOT grant admin confirmation authority', async () => {
      // Create session
      const sess = sessionRepo.create({
        merchantId,
        orderId: `ORD-NOADMIN-${Date.now()}`,
        amountPaise: 50000n,
        receivingAccountId
      });

      // Customer attempts to call admin manual payment confirmation using their session ID as auth
      const res = await request('/api/v1/admin/counter-confirm', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${sess.id}`,
          'X-Session-Id': sess.id
        },
        body: { paymentId: sess.id, operatorId: sess.id }
      });

      // Must be rejected as unauthorized!
      assert.equal(res.status, 401);

      // Verify payment was NOT confirmed
      const check = sessionRepo.findById(sess.id);
      assert.notEqual(check.status, PaymentStatus.SUCCESS);
    });
  });

  // =========================================================================
  // 2. OBSERVER AUTHENTICATION & HMAC SIGNATURES
  // =========================================================================
  describe('2. Observer Authentication & Signature Verification', () => {
    test('Rejects Android observer event when X-Signature or X-Timestamp is missing (401)', async () => {
      const payload = {
        deviceId,
        events: [{
          sender: 'SBIUPI',
          body: 'A/c credited by Rs 500.00 Ref 123456789012',
          receivedAt: Date.now()
        }]
      };

      // Missing signature & timestamp
      const res1 = await request('/api/v1/pollers/android/events', {
        method: 'POST',
        headers: {
          'X-Device-Id': deviceId
        },
        body: payload
      });
      assert.equal(res1.status, 401);
      assert.ok(res1.body.error.includes('Missing required cryptographic authentication headers'));

      // Missing timestamp
      const res2 = await request('/api/v1/pollers/android/events', {
        method: 'POST',
        headers: {
          'X-Device-Id': deviceId,
          'X-Signature': 'fake_signature'
        },
        body: payload
      });
      assert.equal(res2.status, 401);
    });

    test('Rejects Android observer event with forged/invalid HMAC signature (401)', async () => {
      const payload = {
        deviceId,
        events: [{
          sender: 'SBIUPI',
          body: 'A/c credited by Rs 500.00 Ref 123456789012',
          receivedAt: Date.now()
        }]
      };
      const timestamp = Date.now().toString();

      const res = await request('/api/v1/pollers/android/events', {
        method: 'POST',
        headers: {
          'X-Device-Id': deviceId,
          'X-Timestamp': timestamp,
          'X-Signature': '0000000000000000000000000000000000000000000000000000000000000000'
        },
        body: payload
      });

      assert.equal(res.status, 401);
      assert.ok(res.body.error.includes('Invalid cryptographic HMAC signature'));
    });

    test('Rejects expired or drifted timestamp (> 60s) to prevent delayed replays', async () => {
      const payload = {
        deviceId,
        events: [{
          sender: 'SBIUPI',
          body: 'A/c credited by Rs 500.00 Ref 123456789012',
          receivedAt: Date.now()
        }]
      };
      // Timestamp from 5 minutes ago
      const staleTimestamp = (Date.now() - 300000).toString();
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac('sha256', testSigningKey)
        .update(`${rawBody}:${staleTimestamp}`)
        .digest('hex');

      const res = await request('/api/v1/pollers/android/events', {
        method: 'POST',
        headers: {
          'X-Device-Id': deviceId,
          'X-Timestamp': staleTimestamp,
          'X-Signature': signature
        },
        body: payload
      });

      assert.equal(res.status, 401);
      assert.ok(res.body.error.includes('drift exceeded'));
    });

    test('Rejects exact replayed observer event signatures (Replay Attack Prevention)', async () => {
      const payload = {
        deviceId,
        events: [{
          sender: 'SBIUPI',
          body: 'A/c credited by Rs 100.00 Ref 999988887777',
          receivedAt: Date.now()
        }]
      };
      const timestamp = Date.now().toString();
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac('sha256', testSigningKey)
        .update(`${rawBody}:${timestamp}`)
        .digest('hex');

      // First delivery: Valid
      const res1 = await request('/api/v1/pollers/android/events', {
        method: 'POST',
        headers: {
          'X-Device-Id': deviceId,
          'X-Timestamp': timestamp,
          'X-Signature': signature
        },
        body: payload
      });
      assert.equal(res1.status, 200);

      // Second delivery: Exact same signature replayed
      const res2 = await request('/api/v1/pollers/android/events', {
        method: 'POST',
        headers: {
          'X-Device-Id': deviceId,
          'X-Timestamp': timestamp,
          'X-Signature': signature
        },
        body: payload
      });
      assert.equal(res2.status, 401);
      assert.ok(res2.body.error.includes('Replayed observer event'));
    });
  });

  // =========================================================================
  // 3. REMOVAL OF HARDCODED PAIRING SECRET
  // =========================================================================
  describe('3. Pairing Secret Security', () => {
    test('Hardcoded pairing token is completely rejected', async () => {
      const res = await request('/api/v1/pollers/android/pair', {
        method: 'POST',
        body: {
          token: 'youpi_sms_pair_token_secure',
          deviceName: 'Attacker Device'
        }
      });

      assert.equal(res.status, 401);
      assert.ok(res.body.error.includes('Invalid or expired device pairing enrollment token'));
    });
  });

  // =========================================================================
  // 4. ATTEMPTS TO FORGE PAYMENT SUCCESS & CLIENT-SIDE CALLBACKS
  // =========================================================================
  describe('4. Anti-Forgery & Client-Side Verification Integrity', () => {
    test('Client-side payment-done only transitions to PROCESSING, never SUCCESS', async () => {
      const sess = sessionRepo.create({
        merchantId,
        orderId: `ORD-CLIENTDONE-${Date.now()}`,
        amountPaise: 25000n,
        receivingAccountId
      });
      sessionRepo.acquireSlotAtomic(sess.id, receivingAccountId, 300000);

      // Customer clicks "Payment Done"
      const res = await request(`/api/v1/checkout/${sess.id}/payment-done`, {
        method: 'POST'
      });

      assert.equal(res.status, 200);
      const after = sessionRepo.findById(sess.id);
      assert.equal(after.status, PaymentStatus.PROCESSING);
      assert.notEqual(after.status, PaymentStatus.SUCCESS);
    });

    test('trigger-hook telemetry cannot manipulate payment status to SUCCESS', async () => {
      const sess = sessionRepo.create({
        merchantId,
        orderId: `ORD-HOOK-${Date.now()}`,
        amountPaise: 35000n,
        receivingAccountId
      });
      sessionRepo.acquireSlotAtomic(sess.id, receivingAccountId, 300000);

      const res = await request(`/api/v1/checkout/${sess.id}/trigger-hook`, {
        method: 'POST',
        body: {
          action: 'PAYMENT_SUCCESS',
          status: 'SUCCESS',
          forceSettle: true
        }
      });

      assert.equal(res.status, 200);
      const after = sessionRepo.findById(sess.id);
      assert.equal(after.status, PaymentStatus.ACTIVE);
      assert.notEqual(after.status, PaymentStatus.SUCCESS);
    });
  });

  // =========================================================================
  // 5. DUPLICATE PAYMENT REFERENCES & AMOUNT MISMATCHES
  // =========================================================================
  describe('5. Duplicate Payment References (UTR) and Amount Validation', () => {
    test('Duplicate payment reference (UTR) cannot confirm a second payment session', () => {
      const attributionEngine = new AttributionEngine({
        sessionRepo,
        obsRepo,
        gracePeriodMs: 0
      });

      // Session 1: ₹500
      const sess1 = sessionRepo.create({
        merchantId,
        orderId: `ORD-UTR1-${Date.now()}`,
        amountPaise: 50000n,
        receivingAccountId
      });
      sessionRepo.acquireSlotAtomic(sess1.id, receivingAccountId, 300000);

      // Observer 1 confirms Session 1 with UTR: UTR_REUSE_TEST_123
      const obs1 = ObservationNormalizer.normalize({
        source: ObserverSource.SMS_GATEWAY,
        receivingAccountId,
        amountPaise: 50000n,
        bankReferenceNumber: 'UTR_REUSE_TEST_123',
        rawPayload: { text: 'Credited 500 UTR_REUSE_TEST_123' }
      });

      const res1 = attributionEngine.processObservation(obs1);
      assert.equal(res1.attributed, true);
      assert.equal(res1.paymentSessionId, sess1.id);
      assert.equal(sessionRepo.findById(sess1.id).status, PaymentStatus.SUCCESS);

      // Session 2: Another customer creates ₹500 session
      const sess2 = sessionRepo.create({
        merchantId,
        orderId: `ORD-UTR2-${Date.now()}`,
        amountPaise: 50000n,
        receivingAccountId
      });
      sessionRepo.acquireSlotAtomic(sess2.id, receivingAccountId, 300000);

      // Attacker attempts to replay same UTR_REUSE_TEST_123 to fulfill Session 2
      const obsReplay = ObservationNormalizer.normalize({
        source: ObserverSource.SMS_GATEWAY,
        receivingAccountId,
        amountPaise: 50000n,
        bankReferenceNumber: 'UTR_REUSE_TEST_123',
        rawPayload: { targetSessionId: sess2.id, text: 'Credited 500 UTR_REUSE_TEST_123' }
      });

      const res2 = attributionEngine.processObservation(obsReplay);

      // Must be rejected as DUPLICATE_IGNORED and NOT attributed to Session 2!
      assert.equal(res2.attributed, false);
      assert.equal(res2.duplicate, true);
      assert.equal(res2.outcomeStatus, ObservationAttributionStatus.DUPLICATE_IGNORED);

      // Session 2 must remain ACTIVE / not confirmed
      assert.notEqual(sessionRepo.findById(sess2.id).status, PaymentStatus.SUCCESS);
    });

    test('Incorrect payment amount is rejected and does not mark payment successful', () => {
      const attributionEngine = new AttributionEngine({
        sessionRepo,
        obsRepo,
        gracePeriodMs: 0
      });

      // Session expecting ₹500 (50000 paise)
      const sess = sessionRepo.create({
        merchantId,
        orderId: `ORD-AMT-${Date.now()}`,
        amountPaise: 50000n,
        receivingAccountId
      });
      sessionRepo.acquireSlotAtomic(sess.id, receivingAccountId, 300000);

      // Inbound observation is only for ₹200 (20000 paise)
      const obsUnderpaid = ObservationNormalizer.normalize({
        source: ObserverSource.SMS_GATEWAY,
        receivingAccountId,
        amountPaise: 20000n,
        bankReferenceNumber: 'UTR_UNDERPAID_999',
        rawPayload: { text: 'Credited 200' }
      });

      const res = attributionEngine.processObservation(obsUnderpaid);

      assert.equal(res.attributed, false);
      assert.equal(res.outcomeStatus, ObservationAttributionStatus.UNATTRIBUTED);

      // Session remains ACTIVE, never SUCCESS
      const check = sessionRepo.findById(sess.id);
      assert.equal(check.status, PaymentStatus.ACTIVE);
    });
  });

  // =========================================================================
  // 6. DUPLICATE WEBHOOK DELIVERY PREVENTION
  // =========================================================================
  describe('6. Duplicate Webhook Delivery Prevention & UTR Inclusion', () => {
    test('Prevents duplicate webhook delivery for already confirmed events and populates UTR', async () => {
      const webhookEngine = new WebhookEngine({
        db: testDb,
        merchantRepo
      });

      const testMerchant = merchantRepo.findById(merchantId);
      testMerchant.webhookUrl = 'http://127.0.0.1:9999/webhook-test';
      testMerchant.webhookSecret = 'sec_wh_test_123456';
      testDb.execute('UPDATE merchants SET webhook_url = ?, webhook_secret = ? WHERE id = ?', [
        testMerchant.webhookUrl,
        testMerchant.webhookSecret,
        merchantId
      ]);

      // Create observation with UTR
      const obs = obsRepo.create({
        receivingAccountId,
        source: ObserverSource.SMS_GATEWAY,
        amountPaise: 10000n,
        observedAt: new Date(),
        bankReferenceNumber: 'UTR_WH_TEST_777',
        fingerprintHash: `fp_${Date.now()}`
      });

      // Create session
      const sess = sessionRepo.create({
        merchantId,
        orderId: `ORD-WH-${Date.now()}`,
        amountPaise: 10000n,
        receivingAccountId
      });
      sessionRepo.transitionToTerminal(sess.id, PaymentStatus.SUCCESS);
      sessionRepo.recordVerificationSource(sess.id, ObserverSource.SMS_GATEWAY, obs.id, { finalizeSuccess: true });

      const updatedSess = sessionRepo.findById(sess.id);

      // Pre-seed a successful delivery in webhook_deliveries
      testDb.execute(`
        INSERT INTO webhook_deliveries (
          id, merchant_id, payment_id, event_type, payload, endpoint_url,
          response_status, is_successful, attempt_count, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, 200, 1, 1, datetime('now'))
      `, [
        crypto.randomUUID(),
        merchantId,
        sess.id,
        'SUCCESS',
        JSON.stringify({ paymentId: sess.id, event: 'SUCCESS', utr: 'UTR_WH_TEST_777' }),
        testMerchant.webhookUrl
      ]);

      // Call dispatch
      const dispatchResult = await webhookEngine.dispatch('SUCCESS', updatedSess);

      // Must be identified as already delivered without triggering network requests
      assert.equal(dispatchResult.delivered, true);
      assert.equal(dispatchResult.alreadyDelivered, true);
    });
  });

  // =========================================================================
  // 7. PAYMENT SIMULATION RESTRICTIONS
  // =========================================================================
  describe('7. Payment Simulation Safeguards', () => {
    test('Simulate observation endpoint is rejected in production or when simulation is disabled', async () => {
      const sess = sessionRepo.create({
        merchantId,
        orderId: `ORD-SIM-${Date.now()}`,
        amountPaise: 15000n,
        receivingAccountId
      });
      sessionRepo.acquireSlotAtomic(sess.id, receivingAccountId, 300000);

      // Set NODE_ENV to production temporarily
      const prevEnv = process.env.NODE_ENV;
      const prevAllow = process.env.ALLOW_PAYMENT_SIMULATION;
      try {
        process.env.NODE_ENV = 'production';
        process.env.ALLOW_PAYMENT_SIMULATION = 'false';

        const res = await request(`/api/v1/checkout/${sess.id}/simulate-observation`, {
          method: 'POST',
          body: {
            amountPaise: 15000,
            receivingAccountId
          }
        });

        assert.equal(res.status, 403);
        assert.equal(res.body.code, 'SIMULATION_DISABLED');
      } finally {
        process.env.NODE_ENV = prevEnv;
        if (prevAllow !== undefined) {
          process.env.ALLOW_PAYMENT_SIMULATION = prevAllow;
        } else {
          delete process.env.ALLOW_PAYMENT_SIMULATION;
        }
      }
    });
  });
});
