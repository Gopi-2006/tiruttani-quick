import crypto from 'node:crypto';
import assert from 'node:assert/strict';

const GATEWAY_BASE = 'http://localhost:6100';
const CHECKOUT_BASE = 'http://localhost:7000';
const FUNCTIONS_BASE = 'http://127.0.0.1:5001/blinkit_grocery_c3f5d/us_central1'.replace(/_/g, '-');
const API_KEY = 'test_api_key_demo';
const WEBHOOK_SECRET = 'test_webhook_secret_demo';

console.log('====================================================');
console.log('🧪 LOCAL STAGING PAYMENT LIFECYCLE VERIFICATION');
console.log('====================================================');

const results = [];
function record(name, passed, detail) {
  results.push({ name, passed, detail });
  const icon = passed ? '✅' : '❌';
  console.log(`${icon} [${passed ? 'PASS' : 'FAIL'}] ${name}: ${detail}`);
}

async function runTests() {
  // Test 1: Gateway API Health
  try {
    const res = await fetch(`${GATEWAY_BASE}/health`);
    const data = await res.json();
    assert.equal(res.status, 200);
    assert.equal(data.status, 'UP');
    record('Gateway Health', true, `Status ${res.status}, UP`);
  } catch (err) {
    record('Gateway Health', false, err.message);
  }

  // Test 2: Checkout Portal Health
  try {
    const res = await fetch(`${CHECKOUT_BASE}/health`);
    const data = await res.json();
    assert.equal(res.status, 200);
    assert.equal(data.status, 'UP');
    record('Checkout Portal Health', true, `Status ${res.status}, UP`);
  } catch (err) {
    record('Checkout Portal Health', false, err.message);
  }

  // Test 3: Gateway Authentication Rejection (Invalid API Key)
  try {
    const res = await fetch(`${GATEWAY_BASE}/api/v1/payments`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer invalid_forged_merchant_key'
      },
      body: JSON.stringify({ amount: '100.00', orderId: 'UNAUTH-01' })
    });
    assert.equal(res.status, 401);
    const data = await res.json();
    assert.match(data.error, /Unauthorized/i);
    record('Gateway Auth Rejection', true, `HTTP 401 returned for forged API key`);
  } catch (err) {
    record('Gateway Auth Rejection', false, err.message);
  }

  // Test 4: Synthetic Payment Session Creation
  let createdPaymentId = null;
  let checkoutUrl = null;
  try {
    const res = await fetch(`${GATEWAY_BASE}/api/v1/payments`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${API_KEY}`
      },
      body: JSON.stringify({
        amount: '299.00',
        orderId: 'TQ-STAGING-SYNTH-001',
        currency: 'INR',
        method: 'UPI'
      })
    });
    const data = await res.json();
    assert.ok(res.status === 200 || res.status === 201, `Status ${res.status}`);
    assert.ok(data.paymentId, 'Has paymentId');
    assert.equal(data.status, 'INITIATED');
    assert.ok(data.checkoutUrl.startsWith(CHECKOUT_BASE));
    createdPaymentId = data.paymentId;
    checkoutUrl = data.checkoutUrl;
    record('Payment Session Creation', true, `Created ${createdPaymentId}, Status: ${data.status}, Checkout: ${checkoutUrl}`);
  } catch (err) {
    record('Payment Session Creation', false, err.message);
  }

  // Test 5: Checkout Portal Session Rendering
  try {
    const res = await fetch(checkoutUrl);
    assert.equal(res.status, 200);
    const html = await res.text();
    assert.ok(html.includes('299.00') || html.includes('checkout') || html.includes('UPI'));
    record('Checkout Portal Rendering', true, `HTTP 200 HTML rendered for session ${createdPaymentId}`);
  } catch (err) {
    record('Checkout Portal Rendering', false, err.message);
  }

  // Test 6: Gateway Payment State Direct Verification (GET /api/v1/payments/:id)
  try {
    const res = await fetch(`${GATEWAY_BASE}/api/v1/payments/${createdPaymentId}`, {
      headers: { 'Authorization': `Bearer ${API_KEY}` }
    });
    const data = await res.json();
    assert.equal(res.status, 200);
    assert.equal(data.id || data.paymentId, createdPaymentId);
    assert.equal(data.status, 'INITIATED');
    record('Gateway Direct Verification', true, `Verified payment status is INITIATED directly via Gateway API`);
  } catch (err) {
    record('Gateway Direct Verification', false, err.message);
  }

  // Test 7: Firebase Emulator Webhook — Forged Signature Rejection
  try {
    const fakePayload = JSON.stringify({ event: 'SUCCESS', paymentId: createdPaymentId, amount: '299.00' });
    const res = await fetch(`${FUNCTIONS_BASE}/youpiWebhook`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-gateway-signature': 'sha256=0000000000000000000000000000000000000000000000000000000000000000',
        'x-gateway-timestamp': Date.now().toString(),
        'x-gateway-delivery-id': 'deliv-forged-001'
      },
      body: fakePayload
    });
    assert.equal(res.status, 401);
    const data = await res.json();
    assert.equal(data.error, 'INVALID_SIGNATURE');
    record('Forged Signature Rejection', true, `Functions emulator rejected forged HMAC signature with 401 INVALID_SIGNATURE`);
  } catch (err) {
    record('Forged Signature Rejection', false, err.message);
  }

  // Test 8: Firebase Emulator Webhook — Stale Timestamp Replay Protection
  try {
    const stalePayload = JSON.stringify({ event: 'SUCCESS', paymentId: createdPaymentId, amount: '299.00' });
    const staleTime = (Date.now() - 10 * 60 * 1000).toString(); // 10 minutes ago
    const sig = crypto.createHmac('sha256', WEBHOOK_SECRET).update(stalePayload).digest('hex');
    const res = await fetch(`${FUNCTIONS_BASE}/youpiWebhook`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-gateway-signature': `sha256=${sig}`,
        'x-gateway-timestamp': staleTime,
        'x-gateway-delivery-id': 'deliv-stale-001'
      },
      body: stalePayload
    });
    assert.equal(res.status, 401);
    const data = await res.json();
    assert.equal(data.error, 'REPLAY_WINDOW_EXPIRED');
    record('Stale Webhook Replay Protection', true, `Functions emulator rejected 10-minute old webhook with 401 REPLAY_WINDOW_EXPIRED`);
  } catch (err) {
    record('Stale Webhook Replay Protection', false, err.message);
  }

  // Test 9: Firebase Emulator Webhook — Missing Headers Rejection
  try {
    const res = await fetch(`${FUNCTIONS_BASE}/youpiWebhook`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ event: 'SUCCESS' })
    });
    assert.equal(res.status, 401);
    const data = await res.json();
    assert.equal(data.error, 'MISSING_AUTHENTICATION');
    record('Missing Headers Rejection', true, `Functions emulator rejected missing auth headers with 401 MISSING_AUTHENTICATION`);
  } catch (err) {
    record('Missing Headers Rejection', false, err.message);
  }

  // Test 10: Firebase Emulator Convert to COD — Unauthenticated Rejection
  try {
    const res = await fetch(`${FUNCTIONS_BASE}/convertOrderToCod`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ orderId: 'ORDER-STG-NOAUTH' })
    });
    assert.equal(res.status, 401);
    const data = await res.json();
    assert.equal(data.error, 'UNAUTHORIZED');
    record('Convert to COD Auth Guard', true, `Functions emulator rejected unauthenticated request with 401 UNAUTHORIZED`);
  } catch (err) {
    record('Convert to COD Auth Guard', false, err.message);
  }

  // Test 11: Firebase Emulator Create Session — Unauthenticated Rejection
  try {
    const res = await fetch(`${FUNCTIONS_BASE}/createYoupiPaymentSession`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ orderId: 'ORDER-STG-NOAUTH' })
    });
    assert.equal(res.status, 401);
    const data = await res.json();
    assert.equal(data.error, 'UNAUTHORIZED');
    record('Create Session Auth Guard', true, `Functions emulator rejected unauthenticated session request with 401 UNAUTHORIZED`);
  } catch (err) {
    record('Create Session Auth Guard', false, err.message);
  }

  // Test 12: Gateway Outage / Resilience Check
  try {
    // Non-existent payment lookup returns 404 cleanly without crashing gateway
    const res = await fetch(`${GATEWAY_BASE}/api/v1/payments/non-existent-uuid-12345`, {
      headers: { 'Authorization': `Bearer ${API_KEY}` }
    });
    assert.equal(res.status, 404);
    record('Gateway Resilience', true, `Non-existent session lookup returns 404 NOT_FOUND safely without crashing`);
  } catch (err) {
    record('Gateway Resilience', false, err.message);
  }

  // Summary
  console.log('\n====================================================');
  const allPassed = results.every(r => r.passed);
  console.log(`SUMMARY: ${results.filter(r => r.passed).length}/${results.length} PASSED`);
  console.log(`OVERALL: ${allPassed ? '🟢 ALL STAGING LIFECYCLE TESTS PASSED' : '🔴 SOME TESTS FAILED'}`);
  console.log('====================================================');
}

runTests().catch(err => {
  console.error('Fatal execution error:', err);
  process.exit(1);
});
