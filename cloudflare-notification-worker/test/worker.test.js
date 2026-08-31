import test from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeStatus,
  getNotificationContent,
  buildFcmV1Message,
  buildAdminNewOrderFcmMessage,
  NOTIFICATION_STATUSES,
} from '../src/templates.js';
import worker from '../src/index.js';

test('Status normalizer correctly normalizes various status casing and formats', () => {
  assert.equal(normalizeStatus('Pending'), null); // pending doesn't trigger customer push
  assert.equal(normalizeStatus('accepted'), NOTIFICATION_STATUSES.ACCEPTED);
  assert.equal(normalizeStatus('Order Accepted'), NOTIFICATION_STATUSES.ACCEPTED);
  assert.equal(normalizeStatus('Confirmed'), NOTIFICATION_STATUSES.ACCEPTED);
  assert.equal(normalizeStatus('packed'), NOTIFICATION_STATUSES.PACKED);
  assert.equal(normalizeStatus('Order Packed'), NOTIFICATION_STATUSES.PACKED);
  assert.equal(normalizeStatus('out_for_delivery'), NOTIFICATION_STATUSES.OUT_FOR_DELIVERY);
  assert.equal(normalizeStatus('Out For Delivery'), NOTIFICATION_STATUSES.OUT_FOR_DELIVERY);
  assert.equal(normalizeStatus('delivered'), NOTIFICATION_STATUSES.DELIVERED);
  assert.equal(normalizeStatus('Order Delivered'), NOTIFICATION_STATUSES.DELIVERED);
  assert.equal(normalizeStatus('cancelled'), NOTIFICATION_STATUSES.CANCELLED);
  assert.equal(normalizeStatus('Order Cancelled'), NOTIFICATION_STATUSES.CANCELLED);
  assert.equal(normalizeStatus('unknown_status'), null);
});

test('Notification content generator produces required customer copy', () => {
  const acc = getNotificationContent(NOTIFICATION_STATUSES.ACCEPTED, 'ord123', 'TQ1001');
  assert.equal(acc.title, 'Order Accepted');
  assert.equal(acc.body, 'Your Tiruttani Quick order #TQ1001 has been accepted.');

  const pac = getNotificationContent(NOTIFICATION_STATUSES.PACKED, 'ord123', 'TQ1001');
  assert.equal(pac.title, 'Order Packed');
  assert.equal(pac.body, 'Your Tiruttani Quick order #TQ1001 has been packed and is ready.');

  const out = getNotificationContent(NOTIFICATION_STATUSES.OUT_FOR_DELIVERY, 'ord123', 'TQ1001');
  assert.equal(out.title, 'Out for Delivery 🚚');
  assert.equal(out.body, 'Your Tiruttani Quick order #TQ1001 is on the way.');

  const outWithOtp = getNotificationContent(NOTIFICATION_STATUSES.OUT_FOR_DELIVERY, 'ord123', 'TQ1001', '584920');
  assert.equal(outWithOtp.title, 'Out for Delivery 🚚');
  assert.equal(outWithOtp.body, 'Your Tiruttani Quick order #TQ1001 is on the way. Delivery OTP: 584920');

  const outWithPartner = getNotificationContent(NOTIFICATION_STATUSES.OUT_FOR_DELIVERY, 'ord123', 'TQ1001', '584920', 'Ravi');
  assert.equal(outWithPartner.title, 'Out for Delivery 🚚');
  assert.equal(outWithPartner.body, 'Ravi is delivering your order. Delivery OTP: 584920');

  const del = getNotificationContent(NOTIFICATION_STATUSES.DELIVERED, 'ord123', 'TQ1001');
  assert.equal(del.title, 'Order Delivered');
  assert.equal(del.body, 'Your Tiruttani Quick order #TQ1001 has been delivered.');

  const can = getNotificationContent(NOTIFICATION_STATUSES.CANCELLED, 'ord123', 'TQ1001');
  assert.equal(can.title, 'Order Cancelled');
  assert.equal(can.body, 'Your Tiruttani Quick order #TQ1001 has been cancelled.');
});

test('FCM HTTP v1 message builder generates valid Android High Priority structure', () => {
  const msg = buildFcmV1Message({
    token: 'fcm_test_token_12345',
    statusKey: NOTIFICATION_STATUSES.OUT_FOR_DELIVERY,
    orderId: 'order_abc_999',
    orderNumber: 'TQ999',
    deliveryOtp: '849201',
  });

  assert.equal(msg.message.token, 'fcm_test_token_12345');
  assert.equal(msg.message.notification.title, 'Out for Delivery 🚚');
  assert.equal(msg.message.notification.body, 'Your Tiruttani Quick order #TQ999 is on the way. Delivery OTP: 849201');
  assert.equal(msg.message.data.type, 'order_status');
  assert.equal(msg.message.data.orderId, 'order_abc_999');
  assert.equal(msg.message.data.status, 'out_for_delivery');
  assert.equal(msg.message.data.deliveryOtp, '849201');
  assert.equal(msg.message.data.screen, 'order_tracking');
  assert.equal(msg.message.android.priority, 'HIGH');
  assert.equal(msg.message.android.notification.channel_id, 'tq_order_status_v4');
  assert.equal(msg.message.android.notification.click_action, 'FLUTTER_NOTIFICATION_CLICK');
});

test('Worker GET /health returns 200 and service metadata', async () => {
  const req = new Request('http://localhost/health', { method: 'GET' });
  const res = await worker.fetch(req, { ENVIRONMENT: 'test' });
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.equal(data.status, 'ok');
  assert.equal(data.service, 'tiruttani-quick-notification-worker');
});

test('Worker OPTIONS preflight returns 204 with CORS headers', async () => {
  const req = new Request('http://localhost/send-order-notification', { method: 'OPTIONS' });
  const res = await worker.fetch(req, {});
  assert.equal(res.status, 204);
  assert.equal(res.headers.get('Access-Control-Allow-Origin'), '*');
});

test('Worker rejects unauthenticated requests with 401', async () => {
  const req = new Request('http://localhost/send-order-notification', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ orderId: '123', status: 'accepted' }),
  });
  const res = await worker.fetch(req, {});
  assert.equal(res.status, 401);
  const body = await res.json();
  assert.match(body.error, /Unauthorized/);
});

test('Worker returns 404 on unknown route', async () => {
  const req = new Request('http://localhost/invalid-route', { method: 'GET' });
  const res = await worker.fetch(req, {});
  assert.equal(res.status, 404);
});

test('Multi-customer isolation: Customer A and B payloads target distinct tokens strictly', () => {
  const msgA = buildFcmV1Message({
    token: 'token_customer_A_device_1',
    statusKey: NOTIFICATION_STATUSES.ACCEPTED,
    orderId: 'ORDER_A',
    orderNumber: 'TQA100',
  });
  const msgB = buildFcmV1Message({
    token: 'token_customer_B_device_2',
    statusKey: NOTIFICATION_STATUSES.ACCEPTED,
    orderId: 'ORDER_B',
    orderNumber: 'TQB200',
  });

  assert.equal(msgA.message.token, 'token_customer_A_device_1');
  assert.equal(msgA.message.data.orderId, 'ORDER_A');
  assert.notEqual(msgA.message.token, msgB.message.token);
  assert.notEqual(msgA.message.data.orderId, msgB.message.data.orderId);

  assert.equal(msgB.message.token, 'token_customer_B_device_2');
  assert.equal(msgB.message.data.orderId, 'ORDER_B');
});

test('All 5 production order transitions construct valid payload titles and bodies', () => {
  const statuses = [
    { key: NOTIFICATION_STATUSES.ACCEPTED, title: 'Order Accepted', bodyContains: 'has been accepted' },
    { key: NOTIFICATION_STATUSES.PACKED, title: 'Order Packed', bodyContains: 'has been packed' },
    { key: NOTIFICATION_STATUSES.OUT_FOR_DELIVERY, title: 'Out for Delivery 🚚', bodyContains: 'is on the way' },
    { key: NOTIFICATION_STATUSES.DELIVERED, title: 'Order Delivered', bodyContains: 'has been delivered' },
    { key: NOTIFICATION_STATUSES.CANCELLED, title: 'Order Cancelled', bodyContains: 'has been cancelled' },
  ];

  for (const s of statuses) {
    const content = getNotificationContent(s.key, 'ORD_999', 'TQ999');
    assert.equal(content.title, s.title);
    assert.match(content.body, new RegExp(s.bodyContains));

    const msg = buildFcmV1Message({
      token: 'tok_123',
      statusKey: s.key,
      orderId: 'ORD_999',
      orderNumber: 'TQ999',
    });
    assert.equal(msg.message.data.type, 'order_status');
    assert.equal(msg.message.data.orderId, 'ORD_999');
    assert.equal(msg.message.data.status, s.key);
  }
});

test('Admin New Order FCM message builder generates high priority payload with custom audio channel', () => {
  const msg = buildAdminNewOrderFcmMessage({
    token: 'admin_device_token_99',
    orderId: 'ORDER_NEW_777',
    orderNumber: 'TQ777',
    totalAmount: 450.50,
    customerName: 'Gopi',
    customerId: 'CUST_123',
  });

  assert.equal(msg.message.token, 'admin_device_token_99');
  assert.equal(msg.message.notification.title, 'New Order Received');
  assert.equal(msg.message.notification.body, 'New order #TQ777 worth ₹451 placed by Gopi.');
  assert.equal(msg.message.data.type, 'new_order');
  assert.equal(msg.message.data.orderId, 'ORDER_NEW_777');
  assert.equal(msg.message.data.orderNumber, 'TQ777');
  assert.equal(msg.message.data.customerId, 'CUST_123');
  assert.equal(msg.message.data.status, 'pending');
  assert.equal(msg.message.data.screen, 'admin_dashboard');
  assert.equal(msg.message.android.priority, 'HIGH');
  assert.equal(msg.message.android.notification.channel_id, 'tq_new_orders_v4');
  assert.equal(msg.message.android.notification.sound, 'order_received');
  assert.equal(msg.message.android.notification.default_sound, false);
});

test('Worker POST /send-admin-new-order-notification rejects unauthenticated requests with 401', async () => {
  const req = new Request('http://localhost/send-admin-new-order-notification', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ orderId: 'ORDER_123', tokens: ['tok1'] }),
  });
  const res = await worker.fetch(req, {});
  assert.equal(res.status, 401);
  const body = await res.json();
  assert.match(body.error, /Unauthorized/);
});


