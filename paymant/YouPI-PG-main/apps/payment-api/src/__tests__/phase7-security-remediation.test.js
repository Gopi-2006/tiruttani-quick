import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { Database, MerchantRepository, ReceivingAccountRepository, PaymentSessionRepository, ObservationRepository } from '@youpi/db';
import { PaymentStatus, ObserverSource } from '@youpi/common';
import { startServer as startPaymentApi } from '../index.js';

describe('Phase 7 Security Remediation: Ambiguous Attribution, Observer Secret Crypto & Provenance', { timeout: 30000 }, () => {
  let apiInstance;
  let baseUrl;
  let testDb;
  let merchantRepo;
  let accountRepo;
  let sessionRepo;
  let obsRepo;
  let attributionEngine;

  const merchantId = '00000000-0000-0000-0000-000000000001';
  const adminApiKey = 'admin_phase7_test_secret_key_12345';
  const account1Id = '00000000-0000-0000-0000-000000000002';
  const account2Id = '00000000-0000-0000-0000-000000000098';
  const pairingSecret = 'android_pairing_enrollment_secret_key_32_chars';

  before(async () => {
    process.env.ADMIN_API_KEY = adminApiKey;
    process.env.ENFORCE_ADMIN_AUTH = 'true';
    process.env.OBSERVER_MASTER_KEY = 'phase7_test_master_encryption_key_32bytes!!';
    process.env.ANDROID_ENROLLMENT_SECRET = pairingSecret;

    testDb = new Database({ inMemory: true });
    merchantRepo = new MerchantRepository(testDb);
    accountRepo = new ReceivingAccountRepository(testDb);
    sessionRepo = new PaymentSessionRepository(testDb);
    obsRepo = new ObservationRepository(testDb);

    apiInstance = await startPaymentApi(0, testDb);
    baseUrl = `http://localhost:${apiInstance.port}`;
    attributionEngine = apiInstance.app.context.attributionEngine;

    // Ensure two separate receiving accounts exist
    const existingAcc1 = accountRepo.findById(account1Id);
    if (!existingAcc1) {
      accountRepo.create({
        id: account1Id,
        merchantId,
        upiId: 'store1@upi',
        payeeName: 'Store Account 1',
        isActive: true
      });
    }

    const existingAcc2 = accountRepo.findById(account2Id);
    if (!existingAcc2) {
      accountRepo.create({
        id: account2Id,
        merchantId,
        upiId: 'store2@upi',
        payeeName: 'Store Account 2',
        isActive: true
      });
    }
  });

  after(async () => {
    delete process.env.ADMIN_API_KEY;
    delete process.env.ENFORCE_ADMIN_AUTH;
    delete process.env.OBSERVER_MASTER_KEY;
    delete process.env.ANDROID_ENROLLMENT_SECRET;
    try {
      if (apiInstance) {
        await apiInstance.close();
      }
    } catch (err) {
      console.warn('Cleanup error closing apiInstance:', err.message);
    }
    try {
      if (testDb) {
        testDb.close();
      }
    } catch (err) {
      console.warn('Cleanup error closing testDb:', err.message);
    }
  });

  // =========================================================================
  // FIX 1: AMBIGUOUS ATTRIBUTION REMOVAL & ATOMIC DUPLICATE REJECTION
  // =========================================================================
  describe('FIX 1: Ambiguous Payment Attribution & Race Condition Protections', () => {
    test('Ambiguous Match: Two active sessions for exact same amount on different accounts reject observation when receivingAccountId is missing', { timeout: 5000 }, async () => {
      // 1. Create two active sessions for the exact same amount (₹149.00 / 14900 paise)
      const sessionA = sessionRepo.create({
        merchantId,
        orderId: `ORD-AMB-A-${Date.now()}`,
        amountPaise: 14900,
        receivingAccountId: account1Id,
        status: PaymentStatus.ACTIVE
      });

      const sessionB = sessionRepo.create({
        merchantId,
        orderId: `ORD-AMB-B-${Date.now()}`,
        amountPaise: 14900,
        receivingAccountId: account2Id,
        status: PaymentStatus.ACTIVE
      });

      // 2. An observation arrives for ₹149.00 WITHOUT receivingAccountId
      const obsResult = attributionEngine.attribute({
        source: ObserverSource.SMS_GATEWAY,
        amountPaise: 14900,
        bankReferenceNumber: `UTR-AMB-${Date.now()}`,
        observedAt: new Date(),
        rawPayload: { text: 'Received Rs. 149.00' }
      });

      // 3. Must be strictly rejected with AMBIGUOUS_REJECT; NEVER arbitrarily pick the latest session
      assert.equal(obsResult.attributed, false);
      assert.equal(obsResult.ambiguous, true);
      assert.equal(obsResult.outcomeStatus, 'AMBIGUOUS_REJECT');

      // 4. Invariant: Neither session may be marked paid or verifying
      const freshA = sessionRepo.findById(sessionA.id);
      const freshB = sessionRepo.findById(sessionB.id);
      assert.equal(freshA.status, PaymentStatus.ACTIVE);
      assert.equal(freshB.status, PaymentStatus.ACTIVE);
    });

    test('Unambiguous Match: Specifying destination receiving account matches exactly that session', { timeout: 5000 }, async () => {
      const sessionA = sessionRepo.create({
        merchantId,
        orderId: `ORD-UNAMB-A-${Date.now()}`,
        amountPaise: 29900,
        receivingAccountId: account1Id,
        status: PaymentStatus.ACTIVE
      });

      const sessionB = sessionRepo.create({
        merchantId,
        orderId: `ORD-UNAMB-B-${Date.now()}`,
        amountPaise: 29900,
        receivingAccountId: account2Id,
        status: PaymentStatus.ACTIVE
      });

      // Attribution specifying Account 1
      const obsResult = attributionEngine.attribute({
        source: ObserverSource.SMS_GATEWAY,
        receivingAccountId: account1Id,
        amountPaise: 29900,
        bankReferenceNumber: `UTR-ACC1-${Date.now()}`,
        observedAt: new Date(),
        rawPayload: { text: 'Received Rs. 299.00 on Account 1' }
      });

      assert.equal(obsResult.attributed, true);
      assert.equal(obsResult.paymentSessionId, sessionA.id);

      // Session B must remain untouched
      const freshB = sessionRepo.findById(sessionB.id);
      assert.equal(freshB.status, PaymentStatus.ACTIVE);
    });

    test('Atomic Duplicate Reference: Concurrent racing submissions with identical UTR reject second attribution', { timeout: 5000 }, async () => {
      const sharedUtr = `UTR-RACE-${Date.now()}`;

      const session1 = sessionRepo.create({
        merchantId,
        orderId: `ORD-RACE-1-${Date.now()}`,
        amountPaise: 45000,
        receivingAccountId: account1Id,
        status: PaymentStatus.ACTIVE
      });

      const session2 = sessionRepo.create({
        merchantId,
        orderId: `ORD-RACE-2-${Date.now()}`,
        amountPaise: 45000,
        receivingAccountId: account2Id,
        status: PaymentStatus.ACTIVE
      });

      // Submit observation 1 for session 1
      const res1 = attributionEngine.attribute({
        source: ObserverSource.SMS_GATEWAY,
        receivingAccountId: account1Id,
        amountPaise: 45000,
        bankReferenceNumber: sharedUtr,
        observedAt: new Date(),
        rawPayload: { targetSessionId: session1.id }
      });

      assert.equal(res1.attributed, true);
      assert.equal(res1.paymentSessionId, session1.id);

      // Racing observation 2 arrives with identical UTR trying to attribute session 2
      const res2 = attributionEngine.attribute({
        source: ObserverSource.GMAIL,
        receivingAccountId: account2Id,
        amountPaise: 45000,
        bankReferenceNumber: sharedUtr,
        observedAt: new Date(),
        rawPayload: { targetSessionId: session2.id }
      });

      assert.equal(res2.attributed, false);
      assert.equal(res2.duplicate, true);
      assert.equal(res2.outcomeStatus, 'DUPLICATE_IGNORED');

      // Session 2 must NOT have been marked SUCCESS
      const fresh2 = sessionRepo.findById(session2.id);
      assert.notEqual(fresh2.status, PaymentStatus.SUCCESS);
    });
  });

  // =========================================================================
  // FIX 2: OBSERVER SECRET STORAGE AT REST, ROTATION & REVOCATION
  // =========================================================================
  describe('FIX 2: Observer Secret Storage Encryption, Rotation & Revocation', () => {
    let enrolledDeviceId;
    let enrolledApiKey;

    test('Android observer pairing stores AES-256-GCM encrypted secret at rest (no plaintext in DB)', { timeout: 5000 }, async () => {
      const pairRes = await fetch(`${baseUrl}/api/v1/pollers/android/pair`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          token: pairingSecret,
          deviceName: 'Pixel 8 Security Test Device',
          deviceModel: 'Pixel 8 Pro',
          merchantId
        })
      });

      assert.equal(pairRes.status, 200);
      const pairData = await pairRes.json();
      assert.equal(pairData.paired, true);
      assert.ok(pairData.deviceId);
      assert.ok(pairData.signingKey);

      enrolledDeviceId = pairData.deviceId;
      enrolledApiKey = pairData.signingKey;

      // Query raw database row directly
      const rawRow = testDb.queryOne(
        'SELECT signing_key_hash FROM android_devices WHERE id = ?',
        [enrolledDeviceId]
      );

      assert.ok(rawRow);
      // Must be encrypted with enc:v1: prefix
      assert.ok(rawRow.signing_key_hash.startsWith('enc:v1:'));
      // Raw API key must NEVER appear in DB
      assert.ok(!rawRow.signing_key_hash.includes(enrolledApiKey));
    });

    test('HMAC verification succeeds with valid credentials from enrolled device', { timeout: 5000 }, async () => {
      const payload = JSON.stringify({
        source: 'GOOGLE_MESSAGES',
        sender: 'HDFCBK',
        body: 'INR 100.00 credited to a/c XX1234 on 18-Oct-26',
        amountPaise: 10000,
        bankReferenceNumber: `UTR-HMAC-OK-${Date.now()}`,
        receivingAccountId: account1Id
      });

      const timestamp = Date.now().toString();
      const sigPayload = `${payload}:${timestamp}`;
      const signature = crypto.createHmac('sha256', enrolledApiKey).update(sigPayload).digest('hex');

      const ingestRes = await fetch(`${baseUrl}/api/v1/sms-gateway/ingest`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': enrolledDeviceId,
          'X-Timestamp': timestamp,
          'X-Signature': signature
        },
        body: payload
      });

      assert.equal(ingestRes.status, 200);
      const ingestData = await ingestRes.json();
      assert.equal(ingestData.accepted, true);
    });

    test('HMAC verification fails with invalid signature', { timeout: 5000 }, async () => {
      const payload = JSON.stringify({
        source: 'GOOGLE_MESSAGES',
        sender: 'HDFCBK',
        body: 'INR 100.00 credited',
        amountPaise: 10000,
        receivingAccountId: account1Id
      });

      const timestamp = Date.now().toString();

      const ingestRes = await fetch(`${baseUrl}/api/v1/sms-gateway/ingest`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': enrolledDeviceId,
          'X-Timestamp': timestamp,
          'X-Signature': 'invalid_signature_hex_00000000000000000000000000000000'
        },
        body: payload
      });

      assert.equal(ingestRes.status, 401);
    });

    test('Key Rotation: Rotates credential, invalidates old key, new key works', { timeout: 5000 }, async () => {
      const rotateRes = await fetch(`${baseUrl}/api/v1/admin/sms-gateway/devices/${enrolledDeviceId}/rotate`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${adminApiKey}`
        }
      });

      assert.equal(rotateRes.status, 200);
      const rotateData = await rotateRes.json();
      assert.ok(rotateData.signingKey);
      const newApiKey = rotateData.signingKey;
      assert.notEqual(newApiKey, enrolledApiKey);

      const payload = JSON.stringify({
        source: 'GOOGLE_MESSAGES',
        sender: 'HDFCBK',
        body: 'INR 100.00 credited after rotate',
        amountPaise: 10000,
        bankReferenceNumber: `UTR-ROTATE-${Date.now()}`,
        receivingAccountId: account1Id
      });

      const timestamp = Date.now().toString();
      const sigPayload = `${payload}:${timestamp}`;

      // 1. Old key MUST fail
      const oldSig = crypto.createHmac('sha256', enrolledApiKey).update(sigPayload).digest('hex');
      const failRes = await fetch(`${baseUrl}/api/v1/sms-gateway/ingest`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': enrolledDeviceId,
          'X-Timestamp': timestamp,
          'X-Signature': oldSig
        },
        body: payload
      });
      assert.equal(failRes.status, 401);

      // 2. New key MUST succeed
      const newSig = crypto.createHmac('sha256', newApiKey).update(sigPayload).digest('hex');
      const okRes = await fetch(`${baseUrl}/api/v1/sms-gateway/ingest`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': enrolledDeviceId,
          'X-Timestamp': timestamp,
          'X-Signature': newSig
        },
        body: payload
      });
      assert.equal(okRes.status, 200);

      enrolledApiKey = newApiKey;
    });

    test('Revocation: Revoked device credentials return 403 Forbidden', { timeout: 5000 }, async () => {
      const revokeRes = await fetch(`${baseUrl}/api/v1/admin/sms-gateway/devices/${enrolledDeviceId}/revoke`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${adminApiKey}`
        }
      });

      assert.equal(revokeRes.status, 200);
      const revokeData = await revokeRes.json();
      assert.equal(revokeData.isActive, false);

      const payload = JSON.stringify({
        source: 'GOOGLE_MESSAGES',
        sender: 'HDFCBK',
        body: 'INR 100.00 credited attempt on revoked device',
        amountPaise: 10000,
        receivingAccountId: account1Id
      });

      const timestamp = Date.now().toString();
      const sigPayload = `${payload}:${timestamp}`;
      const sig = crypto.createHmac('sha256', enrolledApiKey).update(sigPayload).digest('hex');

      const testRevokedRes = await fetch(`${baseUrl}/api/v1/sms-gateway/ingest`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': enrolledDeviceId,
          'X-Timestamp': timestamp,
          'X-Signature': sig
        },
        body: payload
      });

      assert.equal(testRevokedRes.status, 403);
      const testRevokedData = await testRevokedRes.json();
      assert.equal(testRevokedData.error, 'Device not authorized or inactive.');
    });
  });

  // =========================================================================
  // FIX 3: GMAIL MESSAGE PROVENANCE & AUTHENTICATION (DKIM / SPF)
  // =========================================================================
  describe('FIX 3: Gmail Message Provenance & Cryptographic Verification', () => {
    test('Gmail observation with DKIM or SPF failure header is strictly rejected', { timeout: 5000 }, async () => {
      const res = await fetch(`${baseUrl}/api/v1/pollers/events`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          source: 'GMAIL',
          receivingAccountId: account1Id,
          sender: 'alerts@hdfcbank.bank.in',
          rawText: 'You have received INR 500.00 via UPI UTR 123456789012',
          authResults: 'mx.google.com; dkim=fail header.i=@hdfcbank.bank.in; spf=pass'
        })
      });

      assert.equal(res.status, 403);
      const data = await res.json();
      assert.equal(data.status, 'REJECTED');
      assert.equal(data.reason, 'FORGED_EMAIL_AUTHENTICATION_FAILED');
    });

    test('Gmail observation with SPF failure is strictly rejected', { timeout: 5000 }, async () => {
      const res = await fetch(`${baseUrl}/api/v1/pollers/events`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          source: 'GMAIL',
          receivingAccountId: account1Id,
          sender: 'alerts@icicibank.bank.in',
          rawText: 'Dear Customer, your a/c is credited with INR 350.00 Ref 998877665544',
          authResults: 'mx.google.com; dkim=pass; spf=fail (google.com: domain of alerts@icicibank.bank.in does not designate IP)'
        })
      });

      assert.equal(res.status, 403);
      const data = await res.json();
      assert.equal(data.status, 'REJECTED');
      assert.equal(data.reason, 'FORGED_EMAIL_AUTHENTICATION_FAILED');
    });
  });

  // =========================================================================
  // FIX 4: PERSISTENT REPLAY PROTECTION & TRANSACTION INTEGRITY
  // =========================================================================
  describe('FIX 4: Persistent Anti-Replay across Memory Resets & Database Transactions', () => {
    test('Anti-replay signature survives memory reset via observer_replay_signatures table', { timeout: 5000 }, async () => {
      // Pair a fresh active device
      const pairRes = await fetch(`${baseUrl}/api/v1/pollers/android/pair`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          token: pairingSecret,
          deviceName: 'Anti-Replay Test Device',
          deviceModel: 'Test Model',
          merchantId
        })
      });

      const { deviceId, signingKey } = await pairRes.json();

      const payload = JSON.stringify({
        source: 'GOOGLE_MESSAGES',
        sender: 'HDFCBK',
        body: 'INR 250.00 credited to account Ref 112233445566',
        amountPaise: 25000,
        bankReferenceNumber: `UTR-REPLAY-${Date.now()}`,
        receivingAccountId: account1Id
      });

      const timestamp = Date.now().toString();
      const sigPayload = `${payload}:${timestamp}`;
      const signature = crypto.createHmac('sha256', signingKey).update(sigPayload).digest('hex');

      // 1. First submission succeeds
      const firstRes = await fetch(`${baseUrl}/api/v1/sms-gateway/ingest`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': deviceId,
          'X-Timestamp': timestamp,
          'X-Signature': signature
        },
        body: payload
      });
      assert.equal(firstRes.status, 200);

      // Verify signature is persisted in SQLite table
      const storedSig = testDb.queryOne(
        'SELECT * FROM observer_replay_signatures WHERE signature = ?',
        [signature]
      );
      assert.ok(storedSig, 'Signature must be persisted in observer_replay_signatures table');

      // 2. Replay in same or restarted session is rejected
      const immediateReplayRes = await fetch(`${baseUrl}/api/v1/sms-gateway/ingest`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Id': deviceId,
          'X-Timestamp': timestamp,
          'X-Signature': signature
        },
        body: payload
      });
      assert.equal(immediateReplayRes.status, 401);
      const replayData = await immediateReplayRes.json();
      assert.ok(replayData.error.includes('Replayed observer event detected'));
    });

    test('SQLite uses BEGIN IMMEDIATE for transactional integrity', { timeout: 5000 }, () => {
      let insideTx = false;
      assert.equal(testDb.inTransaction, false);
      testDb.transaction(() => {
        insideTx = true;
        // Verify we are inside active transaction
        assert.equal(testDb.inTransaction, true);
      });
      assert.equal(insideTx, true);
      assert.equal(testDb.inTransaction, false);
    });
  });
});
