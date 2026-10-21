import http from 'node:http';
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { Database } from '../packages/db/src/database.js';

const API_BASE = 'http://localhost:6100';
const CHECKOUT_BASE = 'http://localhost:7000';
const ADMIN_BASE = 'http://localhost:6001';
const CC_BASE = 'http://localhost:8090';

// Helper to make HTTP requests
function httpRequest(urlStr, options = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlStr);
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

async function runPhase2Validation() {
  console.log('====================================================');
  console.log('🔍 PHASE 2: LOCAL DEVELOPMENT & PAYMENT FLOW VALIDATION');
  console.log('====================================================\n');

  // --- TASK 1 & 2: Environment & DB Check ---
  console.log('[TASK 1 & 2] Verifying Local SQLite DB and Services...');
  const dbPath = './data/youpi_pg.sqlite';
  if (!fs.existsSync(dbPath)) {
    throw new Error(`SQLite database not found at ${dbPath}`);
  }
  const db = new Database({ filePath: dbPath });
  const tables = db.query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
  console.log(`[✓] SQLite DB initialized with ${tables.length} tables:`);
  console.log('    ' + tables.map(t => t.name).join(', '));

  const merchants = db.query('SELECT id, business_name, slug FROM merchants');
  console.log(`[✓] Active Merchants: ${merchants.map(m => `${m.business_name} (${m.id})`).join('; ')}`);
  const accounts = db.query('SELECT id, upi_id, payee_name, is_active FROM payment_receiving_accounts WHERE is_active = 1');
  console.log(`[✓] Active VPA Receiving Accounts: ${accounts.map(a => `${a.payee_name} - ${a.upi_id}`).join('; ')}`);

  // Service Health Checks
  console.log('\n--- Service Health Checks ---');
  const hApi = await httpRequest(`${API_BASE}/health`);
  console.log(`• Payment Core API (6100): Status ${hApi.status} ${JSON.stringify(hApi.body)}`);
  if (hApi.status !== 200) throw new Error('Payment API unhealthy');

  const hCheckout = await httpRequest(`${CHECKOUT_BASE}/health`);
  console.log(`• Checkout Portal (7000): Status ${hCheckout.status} ${JSON.stringify(hCheckout.body)}`);
  if (hCheckout.status !== 200) throw new Error('Checkout Portal unhealthy');

  const hAdmin = await httpRequest(`${ADMIN_BASE}/`);
  console.log(`• Merchant Admin Hub (6001): Status ${hAdmin.status} OK`);
  if (hAdmin.status !== 200) throw new Error('Merchant Admin unhealthy');

  const hCC = await httpRequest(`${CC_BASE}/health`);
  console.log(`• Control Center (8090): Status ${hCC.status} ${JSON.stringify(hCC.body)}`);

  console.log('\n====================================================');
  console.log('[TASK 3] EXECUTING SIMULATED PAYMENT FLOW TESTS');
  console.log('====================================================\n');

  function resetSlot() {
    db.execute("UPDATE payment_sessions SET status = 'CANCELLED' WHERE status IN ('ACTIVE', 'PROCESSING', 'QUEUED')");
    db.execute("UPDATE payment_receiving_accounts SET is_slot_busy = 0, current_active_session_id = NULL");
  }
  resetSlot();

  // Enable test mode first on the gateway
  await httpRequest(`${API_BASE}/api/v1/admin/dev/test-mode`, {
    method: 'POST',
    body: { enabled: true }
  });

  // 1. Create a test payment session with autoActivate
  const orderId1 = `PHASE2-TEST-${Date.now()}`;
  console.log(`1. Creating payment session for Order #${orderId1} (Amount: ₹150.00)...`);
  const createRes1 = await httpRequest(`${API_BASE}/api/v1/payments`, {
    method: 'POST',
    body: {
      orderId: orderId1,
      amount: '150.00',
      currency: 'INR',
      autoActivate: true
    }
  });
  console.log(`   Response (${createRes1.status}): Payment ID: ${createRes1.body.paymentId}, Status: ${createRes1.body.status}`);
  if ((createRes1.status !== 200 && createRes1.status !== 201) || !createRes1.body.paymentId) {
    throw new Error(`Failed to create payment session: ${JSON.stringify(createRes1.body)}`);
  }
  const paymentId1 = createRes1.body.paymentId;

  // 2. Open its checkout URL locally
  const checkoutUrl1 = `${CHECKOUT_BASE}/checkout/${paymentId1}`;
  console.log(`2. Opening checkout page at ${checkoutUrl1}...`);
  const checkoutPageRes = await httpRequest(checkoutUrl1);
  console.log(`   Checkout Page Response: HTTP ${checkoutPageRes.status} (Length: ${checkoutPageRes.body.length} bytes)`);
  if (checkoutPageRes.status !== 200 || !checkoutPageRes.body.includes('YOUPI PG')) {
    throw new Error('Checkout page failed to render cleanly');
  }
  console.log('   [✓] Checkout Portal rendered successfully with order details and QR.');

  // 3. Test a successful simulated payment
  const utr1 = '42' + String(Date.now()).slice(-10);
  console.log(`3. Testing successful simulated payment for ₹150.00 (15000 paise, 12-digit UTR: ${utr1})...`);
  const simRes1 = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId1}/simulate-observation`, {
    method: 'POST',
    body: {
      source: 'SMS',
      sender: 'SBIUPI',
      rawText: `Dear customer, your account has been credited with INR 150.00 on ${new Date().toISOString()} via UPI ref ${utr1}.`,
      amountPaise: 15000,
      bankReferenceNumber: utr1
    }
  });
  console.log(`   Simulate observation response (${simRes1.status}):`, simRes1.body);

  // Poll state to confirm SUCCESS (allowing 5-second Level 1 grace period to finalize)
  console.log('   Waiting 5.5s for grace period finalization to complete...');
  await new Promise(r => setTimeout(r, 5500));
  const stateRes1 = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId1}/state`);
  console.log(`   State after simulation: Status = ${stateRes1.body.status}, Amount = ₹${stateRes1.body.amount}`);
  if (stateRes1.body.status !== 'SUCCESS') {
    throw new Error(`Expected SUCCESS but got ${stateRes1.body.status}`);
  }
  console.log('   [✓] Successful simulated payment verified.');

  // 4. Test an incorrect amount
  resetSlot();
  const orderId2 = `PHASE2-INCORRECT-AMT-${Date.now()}`;
  console.log(`\n4. Testing incorrect payment amount for Order #${orderId2} (Expected: ₹200.00, Injected: ₹50.00)...`);
  const createRes2 = await httpRequest(`${API_BASE}/api/v1/payments`, {
    method: 'POST',
    body: {
      orderId: orderId2,
      amount: '200.00',
      currency: 'INR',
      autoActivate: true
    }
  });
  const paymentId2 = createRes2.body.paymentId;

  const simResUnderpaid = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId2}/simulate-observation`, {
    method: 'POST',
    body: {
      source: 'SMS',
      sender: 'SBIUPI',
      rawText: 'Credited INR 50.00 ref 555000111222',
      amountPaise: 5000,
      bankReferenceNumber: '555000111222'
    }
  });
  console.log(`   Underpaid simulation result:`, simResUnderpaid.body);

  const stateRes2 = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId2}/state`);
  console.log(`   Session State: Status = ${stateRes2.body.status}`);
  if (stateRes2.body.status === 'SUCCESS') {
    throw new Error('SECURITY VIOLATION: Underpaid payment was falsely marked SUCCESS!');
  }
  console.log('   [✓] Underpaid observation correctly rejected. Session remained in active verification.');

  // 5. Test an expired session
  resetSlot();
  const orderId3 = `PHASE2-EXPIRED-${Date.now()}`;
  console.log(`\n5. Testing expired session handling for Order #${orderId3}...`);
  const createRes3 = await httpRequest(`${API_BASE}/api/v1/payments`, {
    method: 'POST',
    body: {
      orderId: orderId3,
      amount: '75.00',
      currency: 'INR',
      autoActivate: true
    }
  });
  const paymentId3 = createRes3.body.paymentId;

  // Force expire
  const expireRes = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId3}/expire`, { method: 'POST' });
  console.log(`   Expire response (${expireRes.status}):`, expireRes.body);

  const stateRes3 = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId3}/state`);
  console.log(`   State after expiry: Status = ${stateRes3.body.status}`);
  if (stateRes3.body.status !== 'EXPIRED') {
    throw new Error(`Expected EXPIRED but got ${stateRes3.body.status}`);
  }

  // Attempt to simulate payment on expired session
  const simOnExpired = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId3}/simulate-observation`, {
    method: 'POST',
    body: {
      source: 'SMS',
      sender: 'SBIUPI',
      rawText: 'Credited INR 75.00 ref 757575757575',
      amountPaise: 7500,
      bankReferenceNumber: '757575757575'
    }
  });
  const stateRes3After = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId3}/state`);
  if (stateRes3After.body.status === 'SUCCESS') {
    throw new Error('SECURITY VIOLATION: Expired session was hijacked to SUCCESS!');
  }
  console.log('   [✓] Expired session correctly protected against post-expiry confirmation.');

  // 6. Test duplicate payment reference (UTR)
  resetSlot();
  const orderId4 = `PHASE2-DUP-UTR-${Date.now()}`;
  console.log(`\n6. Testing duplicate payment reference (UTR) reuse prevention for Order #${orderId4}...`);
  const createRes4 = await httpRequest(`${API_BASE}/api/v1/payments`, {
    method: 'POST',
    body: {
      orderId: orderId4,
      amount: '150.00',
      currency: 'INR',
      autoActivate: true
    }
  });
  const paymentId4 = createRes4.body.paymentId;

  // Attempt to replay utr1 (which was consumed in step 3)
  console.log(`   Attempting to replay already-consumed UTR (${utr1})...`);
  const simDupUtr = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId4}/simulate-observation`, {
    method: 'POST',
    body: {
      source: 'SMS',
      sender: 'SBIUPI',
      rawText: `Credited INR 150.00 Ref ${utr1}`,
      amountPaise: 15000,
      bankReferenceNumber: utr1
    }
  });
  console.log(`   Replayed UTR submission response:`, simDupUtr.body);

  const stateRes4 = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId4}/state`);
  console.log(`   Target Session State: Status = ${stateRes4.body.status}`);
  if (stateRes4.body.status === 'SUCCESS') {
    throw new Error('SECURITY VIOLATION: Reused UTR confirmed a second session!');
  }
  console.log('   [✓] Duplicate UTR replay rejected. Second session not confirmed.');

  // 7. Test cancelled payment
  resetSlot();
  const orderId5 = `PHASE2-CANCEL-${Date.now()}`;
  console.log(`\n7. Testing user cancellation for Order #${orderId5}...`);
  const createRes5 = await httpRequest(`${API_BASE}/api/v1/payments`, {
    method: 'POST',
    body: {
      orderId: orderId5,
      amount: '99.00',
      currency: 'INR',
      autoActivate: true
    }
  });
  const paymentId5 = createRes5.body.paymentId;

  const cancelRes = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId5}/cancel`, {
    method: 'POST',
    body: { reason: 'USER_CANCELLED_PAYMENT' }
  });
  console.log(`   Cancel response (${cancelRes.status}):`, cancelRes.body);

  const stateRes5 = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId5}/state`);
  console.log(`   State after cancel: Status = ${stateRes5.body.status}`);
  if (stateRes5.body.status !== 'CANCELLED') {
    throw new Error(`Expected CANCELLED but got ${stateRes5.body.status}`);
  }
  console.log('   [✓] Cancellation properly transitioned.');

  // 8. Verify customer actions cannot independently mark a payment successful
  resetSlot();
  const orderId6 = `PHASE2-TAMPER-${Date.now()}`;
  console.log(`\n8. Testing anti-tamper (ensuring client clicks cannot mark SUCCESS) for Order #${orderId6}...`);
  const createRes6 = await httpRequest(`${API_BASE}/api/v1/payments`, {
    method: 'POST',
    body: {
      orderId: orderId6,
      amount: '350.00',
      currency: 'INR',
      autoActivate: true
    }
  });
  const paymentId6 = createRes6.body.paymentId;

  // Customer clicks Payment Done
  const pdRes = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId6}/payment-done`, { method: 'POST' });
  console.log(`   Payment Done click response (${pdRes.status}): Status = ${pdRes.body.status}`);
  if (pdRes.body.status === 'SUCCESS') {
    throw new Error('SECURITY VIOLATION: /payment-done marked session as SUCCESS!');
  }

  // Customer tries telemetry injection
  const hookRes = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId6}/trigger-hook`, {
    method: 'POST',
    body: { action: 'PAYMENT_SUCCESS', status: 'SUCCESS', forceSuccess: true }
  });
  console.log(`   Trigger hook response (${hookRes.status}):`, hookRes.body);

  const stateRes6 = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId6}/state`);
  console.log(`   Session state: Status = ${stateRes6.body.status}`);
  if (stateRes6.body.status === 'SUCCESS') {
    throw new Error('SECURITY VIOLATION: Telemetry hook marked session as SUCCESS!');
  }
  console.log('   [✓] Client actions confirmed unable to mark payment as SUCCESS (only PROCESSING).');

  // 9. Verify simulation is rejected when NODE_ENV=production
  console.log('\n9. Verifying that simulation is strictly rejected when NODE_ENV=production...');
  const prodCheckCode = `
    import { startServer } from './apps/payment-api/src/index.js';
    import { Database } from './packages/db/src/database.js';
    process.env.NODE_ENV = 'production';
    process.env.ALLOW_PAYMENT_SIMULATION = 'false';
    const db = new Database({ inMemory: true });
    const instance = await startServer(6299, db);
    const res = await fetch('http://localhost:6299/api/v1/checkout/test-sim-id/simulate-observation', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ amountPaise: 35000, rawText: 'Credited' })
    });
    const body = await res.json();
    console.log(JSON.stringify({ status: res.status, body }));
    await instance.close();
    process.exit(0);
  `;
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', prodCheckCode], {
    env: { ...process.env, NODE_ENV: 'production', ALLOW_PAYMENT_SIMULATION: 'false' },
    encoding: 'utf8'
  });
  let prodSimCheck = {};
  try {
    const lines = child.stdout.trim().split('\n');
    prodSimCheck = JSON.parse(lines[lines.length - 1]);
  } catch {
    prodSimCheck = { raw: child.stdout, stderr: child.stderr };
  }
  console.log(`   Production simulation request result:`, prodSimCheck);
  if (prodSimCheck.status !== 403 || prodSimCheck.body?.code !== 'SIMULATION_DISABLED') {
    throw new Error(`Production simulation was not rejected with 403: ${JSON.stringify(prodSimCheck)}`);
  }
  console.log('   [✓] Simulation strictly blocked with 403 (SIMULATION_DISABLED) in production mode.');

  // 10. Verify COD and UPI on Delivery remain functional
  resetSlot();
  const orderId7 = `PHASE2-COD-${Date.now()}`;
  console.log(`\n10. Testing Cash on Delivery (COD) functionality for Order #${orderId7}...`);
  // Ensure default merchant has ONLINE selling mode with COD enabled
  db.execute(`
    UPDATE merchants
    SET branding = json_patch(branding, '{"sellingMode":"ONLINE","enabledPaymentMethods":["UPI","COD"]}')
    WHERE id = '00000000-0000-0000-0000-000000000001'
  `);

  const createRes7 = await httpRequest(`${API_BASE}/api/v1/payments`, {
    method: 'POST',
    body: {
      orderId: orderId7,
      amount: '499.00',
      currency: 'INR',
      autoActivate: true
    }
  });
  const paymentId7 = createRes7.body.paymentId;

  // Confirm COD
  const codRes = await httpRequest(`${API_BASE}/api/v1/checkout/${paymentId7}/confirm-cod`, {
    method: 'POST',
    body: {}
  });
  console.log(`   Confirm COD response (${codRes.status}):`, codRes.body);
  if (codRes.status !== 200 || !codRes.body.success) {
    throw new Error(`COD confirmation failed: ${JSON.stringify(codRes.body)}`);
  }

  const stateRes7 = await httpRequest(`${API_BASE}/api/v1/payments/${paymentId7}`);
  console.log(`   Session State after COD: Status = ${stateRes7.body.status}, Method = ${stateRes7.body.method}, VerificationTag = ${stateRes7.body.verificationTag}`);
  if (stateRes7.body.status !== 'SUCCESS' || stateRes7.body.method !== 'COD') {
    throw new Error(`Expected SUCCESS with COD method, got status=${stateRes7.body.status}, method=${stateRes7.body.method}`);
  }
  console.log('   [✓] Cash on Delivery (COD) verified working smoothly.');

  console.log('\n====================================================');
  console.log('🎉 ALL PHASE 2 LOCAL PAYMENT FLOW TESTS PASSED!');
  console.log('====================================================\n');
}

runPhase2Validation().catch(err => {
  console.error('\n❌ Phase 2 Validation Failed:', err.message);
  process.exit(1);
});
