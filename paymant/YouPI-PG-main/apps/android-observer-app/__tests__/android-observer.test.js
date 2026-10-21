import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { Database } from '@youpi/db';
import { startServer as startPaymentApi } from '../../../apps/payment-api/src/index.js';
import { AndroidObserverDriver } from '../driver.js';
import { PaymentStatus } from '@youpi/common';
import { BankSmsParser } from '@youpi/core';

describe('Android Payment Observer Integration Tests', () => {
  let apiInstance;
  let driver;
  let testDb;

  before(async () => {
    testDb = new Database({ inMemory: true });
    apiInstance = await startPaymentApi(6217, testDb);
    driver = new AndroidObserverDriver({
      apiBaseUrl: `http://localhost:${apiInstance.port}`,
      deviceName: 'Pixel 8 Pro Tester',
      deviceModel: 'Pixel 8 Pro'
    });
  });

  after(async () => {
    driver.stopHeartbeat();
    await apiInstance.close();
    testDb.close();
  });

  test('rejects pairing with invalid enrollment token', async () => {
    await assert.rejects(
      () => driver.pair('invalid_token_123'),
      /Device pairing failed/
    );
  });

  test('successfully pairs Android device with valid enrollment token', async () => {
    const enrollmentSecret = process.env.ANDROID_ENROLLMENT_SECRET || 'android_pairing_enrollment_secret_key_32_chars';
    const pairResult = await driver.pair(enrollmentSecret);

    assert.ok(pairResult.paired);
    assert.ok(pairResult.deviceId);
    assert.ok(pairResult.signingKey);

    assert.equal(driver.deviceId, pairResult.deviceId);
    assert.equal(driver.signingKey, pairResult.signingKey);
  });

  test('sends heartbeat acknowledging liveness', async () => {
    const hbResult = await driver.sendHeartbeat();
    assert.equal(hbResult.status, 'HEARTBEAT_ACK');
    assert.ok(hbResult.timestamp);
  });

  test('rejects observation with expired/drifted timestamp (Replay Protection)', async () => {
    // Timestamp 2 minutes in the past (> 60s drift)
    const oldTimestamp = Date.now() - 120000;
    const res = await driver.submitObservation({
      amount: '200.00',
      timestampOverride: oldTimestamp
    });

    assert.equal(res.status, 401);
    assert.ok(res.body.error.includes('validity window'));
  });

  test('submits valid HMAC-signed observation and confirms payment in Payment API', async () => {
    // 1. Create and activate a payment session for ₹350
    const session = apiInstance.app.context.sessionRepo.create({
      merchantId: '00000000-0000-0000-0000-000000000001',
      receivingAccountId: '00000000-0000-0000-0000-000000000002',
      orderId: 'ANDR-ORD-350',
      amountPaise: 35000n
    });

    apiInstance.app.context.queueEngine.enqueueOrActivate(session.id, '00000000-0000-0000-0000-000000000002');
    apiInstance.app.context.timingEngine.handlePaymentDone(session.id);

    // 2. Android observer submits observation for ₹350
    const res = await driver.submitObservation({
      amount: '350.00',
      receivingAccountId: '00000000-0000-0000-0000-000000000002',
      utr: 'UTR-ANDR-9876',
      senderVpa: 'customer@paytm',
      notificationText: 'Payment of ₹350 received from customer@paytm on PhonePe'
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.accepted, true);
    assert.equal(res.body.attribution.attributed, true);
    assert.equal(res.body.attribution.paymentSessionId, session.id);
    assert.equal(res.body.attribution.outcomeStatus, PaymentStatus.SUCCESS);

    // 3. Verify session in DB updated to SUCCESS
    const updated = apiInstance.app.context.sessionRepo.findById(session.id);
    assert.equal(updated.status, PaymentStatus.SUCCESS);
  });

  describe('Observer Offline Reliability & Outbox Queueing', () => {
    test('enqueues failed observation to outbox without storing raw SMS text', async () => {
      const offlineDriver = new AndroidObserverDriver({
        apiBaseUrl: 'http://127.0.0.1:59999'
      });
      offlineDriver.deviceId = driver.deviceId;
      offlineDriver.signingKey = driver.signingKey;

      const obs = {
        amount: '450.00',
        amountPaise: 45000n,
        receivingAccountId: '00000000-0000-0000-0000-000000000002',
        utr: 'UTR-OFFLINE-001',
        senderVpa: 'payer@upi',
        observedAt: new Date().toISOString()
      };

      const result = await offlineDriver.submitObservationWithOutbox(obs);
      assert.equal(result.delivered, false);
      assert.equal(result.outbox, true);

      const outbox = offlineDriver.getOutbox();
      assert.equal(outbox.length, 1);
      assert.equal(outbox[0].amount, '450.00');
      assert.equal(outbox[0].utr, 'UTR-OFFLINE-001');
      assert.equal(outbox[0].rawNotification, undefined, 'Must NEVER store raw notification body');
    });

    test('flushes outbox successfully after network reconnection', async () => {
      // 1. Create a payment session for ₹450
      const session = apiInstance.app.context.sessionRepo.create({
        merchantId: '00000000-0000-0000-0000-000000000001',
        receivingAccountId: '00000000-0000-0000-0000-000000000002',
        orderId: 'ORD-OUTBOX-450',
        amountPaise: 45000n
      });
      apiInstance.app.context.queueEngine.enqueueOrActivate(session.id, '00000000-0000-0000-0000-000000000002');
      apiInstance.app.context.timingEngine.handlePaymentDone(session.id);

      // 2. Queue into driver outbox
      driver.clearOutbox();
      driver.queueToOutbox({
        amount: '450.00',
        amountPaise: 45000n,
        receivingAccountId: '00000000-0000-0000-0000-000000000002',
        utr: 'UTR-OUTBOX-450',
        senderVpa: 'payer@upi',
        observedAt: new Date().toISOString()
      });

      assert.equal(driver.getOutbox().length, 1);

      // 3. Flush outbox to online Payment API
      const flushResults = await driver.flushOutbox();
      assert.equal(flushResults.length, 1);
      assert.equal(flushResults[0].status, 'DELIVERED');
      assert.equal(driver.getOutbox().length, 0, 'Outbox must be empty after successful flush');

      // 4. Verify session settled to SUCCESS
      const updated = apiInstance.app.context.sessionRepo.findById(session.id);
      assert.equal(updated.status, PaymentStatus.SUCCESS);
    });

    test('preserves outbox state across driver/app restart', async () => {
      const savedOutbox = [{
        eventId: 'evt_restart_1',
        amount: '120.00',
        amountPaise: '12000',
        receivingAccountId: '00000000-0000-0000-0000-000000000002',
        utr: 'UTR-RESTART-120',
        senderVpa: 'user@paytm',
        observedAt: new Date().toISOString(),
        retryCount: 1,
        createdAt: Date.now() - 5000
      }];

      const restoredDriver = new AndroidObserverDriver({
        apiBaseUrl: `http://localhost:${apiInstance.port}`,
        outbox: savedOutbox
      });
      restoredDriver.deviceId = driver.deviceId;
      restoredDriver.signingKey = driver.signingKey;

      assert.equal(restoredDriver.getOutbox().length, 1);
      assert.equal(restoredDriver.getOutbox()[0].eventId, 'evt_restart_1');
    });

    test('discards event when retry count exceeds max bounds (5 retries)', async () => {
      driver.clearOutbox();
      driver.queueToOutbox({
        amount: '999.00',
        retryCount: 5
      });

      const results = await driver.flushOutbox();
      assert.equal(results.length, 1);
      assert.equal(results[0].status, 'EXHAUSTED');
      assert.equal(driver.getOutbox().length, 0, 'Exhausted event must be discarded');
    });

    test('duplicate delivery does not double-settle or corrupt payment session', async () => {
      const session = apiInstance.app.context.sessionRepo.create({
        merchantId: '00000000-0000-0000-0000-000000000001',
        receivingAccountId: '00000000-0000-0000-0000-000000000002',
        orderId: 'ORD-DUP-275',
        amountPaise: 27500n
      });
      apiInstance.app.context.queueEngine.enqueueOrActivate(session.id, '00000000-0000-0000-0000-000000000002');
      apiInstance.app.context.timingEngine.handlePaymentDone(session.id);

      const obs = {
        amount: '275.00',
        receivingAccountId: '00000000-0000-0000-0000-000000000002',
        utr: 'UTR-DUP-275',
        senderVpa: 'payer@phonepe'
      };

      const res1 = await driver.submitObservation(obs);
      assert.equal(res1.status, 200);
      assert.equal(res1.body.accepted, true);

      const res2 = await driver.submitObservation(obs);
      assert.equal(res2.status, 200);

      const updated = apiInstance.app.context.sessionRepo.findById(session.id);
      assert.equal(updated.status, PaymentStatus.SUCCESS);
    });
  });

  describe('Table-Driven Bank Notification & SMS Parsing Suite', () => {
    const testCases = [
      {
        name: 'SBI Credit SMS',
        text: 'Dear SBI User, your A/C ending 4567 is credited by Rs 499.00 on 20-Oct-26 by UPI/629182739182/Ref.',
        expectedCredit: true,
        expectedPaise: 49900n,
        expectedUtr: '629182739182'
      },
      {
        name: 'HDFC Credit SMS with comma amount',
        text: 'HDFC Bank: Rs 1,250.00 credited to a/c XX1234 on 20-Oct-26 by UPI. Ref no 998877665544.',
        expectedCredit: true,
        expectedPaise: 125000n,
        expectedUtr: '998877665544'
      },
      {
        name: 'ICICI Credit SMS with INR symbol',
        text: 'ICICI Bank: INR 350.50 deposited in a/c XX8899 on 20-Oct-26. UTR: 112233445566.',
        expectedCredit: true,
        expectedPaise: 35050n,
        expectedUtr: '112233445566'
      },
      {
        name: 'PhonePe Notification with rupee symbol and sender VPA',
        text: 'Payment of ₹150 received from customer@okhdfcbank on PhonePe.',
        expectedCredit: true,
        expectedPaise: 15000n,
        expectedVpa: 'customer@okhdfcbank'
      },
      {
        name: 'Debit Notification (Must be rejected)',
        text: 'Rs 500.00 debited from your A/C ending 1234 on 20-Oct-26.',
        expectedCredit: false
      },
      {
        name: 'Missing UTR (Extracts amount without reference number)',
        text: 'Your A/C is credited with Rs 200 on 20-Oct-26.',
        expectedCredit: true,
        expectedPaise: 20000n,
        expectedUtr: undefined
      },
      {
        name: 'Malformed Amount (Must be rejected)',
        text: 'Payment of Rs. credited to your account on 20-Oct-26',
        expectedCredit: false
      },
      {
        name: 'Unsupported Non-Payment SMS (Must be rejected)',
        text: 'Your daily OTP for SBI net banking is 492019. Do not share with anyone.',
        expectedCredit: false
      },
      {
        name: 'Tamil Credit Notification (ரூ. symbol)',
        text: 'உங்கள் கணக்கு XX1234-ல் ரூ. 250.00 வரவு வைக்கப்பட்டது. UPI Ref 123456789012',
        expectedCredit: true,
        expectedPaise: 25000n,
        expectedUtr: '123456789012'
      },
      {
        name: 'Tamil Credit Notification (ரூபாய் word)',
        text: 'ரூபாய் 500.00 உங்கள் வங்கிக் கணக்கில் வரவு வைக்கப்பட்டது. UTR: 987654321098',
        expectedCredit: true,
        expectedPaise: 50000n,
        expectedUtr: '987654321098'
      },
      {
        name: 'Tamil Debit Notification (பற்று - Must be rejected)',
        text: 'உங்கள் கணக்கு XX1234-ல் ரூ. 500 பற்று வைக்கப்பட்டது.',
        expectedCredit: false
      }
    ];

    for (const tc of testCases) {
      test(`BankSmsParser: ${tc.name}`, () => {
        const parsed = BankSmsParser.parse({ text: tc.text });
        if (!tc.expectedCredit) {
          assert.equal(parsed, null, `Expected ${tc.name} to be rejected (null)`);
        } else {
          assert.ok(parsed, `Expected ${tc.name} to parse successfully`);
          assert.equal(parsed.amountPaise, tc.expectedPaise, `Amount mismatch for ${tc.name}`);
          if (tc.expectedUtr !== undefined) {
            assert.equal(parsed.bankReferenceNumber, tc.expectedUtr, `UTR mismatch for ${tc.name}`);
          }
          if (tc.expectedVpa !== undefined) {
            assert.equal(parsed.senderVpa, tc.expectedVpa, `VPA mismatch for ${tc.name}`);
          }
        }
      });
    }

    test('Security Invariant: Ambiguous attribution is rejected when amount matches multiple sessions without UTR', () => {
      const session1 = apiInstance.app.context.sessionRepo.create({
        merchantId: '00000000-0000-0000-0000-000000000001',
        receivingAccountId: '00000000-0000-0000-0000-000000000002',
        orderId: 'ORD-AMBIG-1',
        amountPaise: 9900n
      });
      const session2 = apiInstance.app.context.sessionRepo.create({
        merchantId: '00000000-0000-0000-0000-000000000001',
        receivingAccountId: '00000000-0000-0000-0000-000000000002',
        orderId: 'ORD-AMBIG-2',
        amountPaise: 9900n
      });

      assert.notEqual(session1.id, session2.id);
    });
  });
});
