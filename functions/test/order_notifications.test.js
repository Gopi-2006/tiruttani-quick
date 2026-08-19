const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { _test } = require("../index.js");
const {
  normalizeOrderStatus,
  buildNotificationPayload,
  handleOrderStatusUpdate,
} = _test;

describe("Order Status Normalization", () => {
  test("normalizes various accepted representations", () => {
    assert.equal(normalizeOrderStatus("accepted"), "accepted");
    assert.equal(normalizeOrderStatus("Accepted"), "accepted");
    assert.equal(normalizeOrderStatus("confirmed"), "accepted");
    assert.equal(normalizeOrderStatus("CONFIRMED"), "accepted");
  });

  test("normalizes packed status", () => {
    assert.equal(normalizeOrderStatus("packed"), "packed");
    assert.equal(normalizeOrderStatus("Packed"), "packed");
  });

  test("normalizes out for delivery status", () => {
    assert.equal(normalizeOrderStatus("out_for_delivery"), "out_for_delivery");
    assert.equal(normalizeOrderStatus("Out for Delivery"), "out_for_delivery");
    assert.equal(normalizeOrderStatus("outfordelivery"), "out_for_delivery");
  });

  test("normalizes delivered status", () => {
    assert.equal(normalizeOrderStatus("delivered"), "delivered");
    assert.equal(normalizeOrderStatus("Delivered"), "delivered");
  });

  test("normalizes cancelled status", () => {
    assert.equal(normalizeOrderStatus("cancelled"), "cancelled");
    assert.equal(normalizeOrderStatus("Cancelled"), "cancelled");
    assert.equal(normalizeOrderStatus("canceled"), "cancelled");
    assert.equal(normalizeOrderStatus("Canceled"), "cancelled");
  });

  test("normalizes pending status", () => {
    assert.equal(normalizeOrderStatus("pending"), "pending");
    assert.equal(normalizeOrderStatus("Pending"), "pending");
    assert.equal(normalizeOrderStatus("placed"), "pending");
  });
});

describe("FCM Notification Message & Custom Data Builder", () => {
  const orderId = "order_doc_123";
  const orderNumber = "TQ-9876";

  test("builds Accepted FCM notification", () => {
    const payload = buildNotificationPayload(orderId, orderNumber, "Accepted");
    assert.notEqual(payload, null);
    assert.equal(payload.title, "Order Accepted");
    assert.equal(payload.body, "Your Tiruttani Quick order #TQ-9876 has been accepted.");
    assert.equal(payload.canonicalStatus, "accepted");
    assert.deepEqual(payload.data, {
      type: "order_status",
      orderId: "order_doc_123",
      status: "accepted",
      screen: "order_tracking"
    });
  });

  test("builds Packed FCM notification", () => {
    const payload = buildNotificationPayload(orderId, orderNumber, "Packed");
    assert.notEqual(payload, null);
    assert.equal(payload.title, "Order Packed");
    assert.equal(payload.body, "Your Tiruttani Quick order #TQ-9876 has been packed and is ready.");
    assert.equal(payload.canonicalStatus, "packed");
    assert.deepEqual(payload.data, {
      type: "order_status",
      orderId: "order_doc_123",
      status: "packed",
      screen: "order_tracking"
    });
  });

  test("builds Out for Delivery FCM notification", () => {
    const payload = buildNotificationPayload(orderId, orderNumber, "Out for Delivery");
    assert.notEqual(payload, null);
    assert.equal(payload.title, "Out for Delivery");
    assert.equal(payload.body, "Your Tiruttani Quick order #TQ-9876 is on the way.");
    assert.equal(payload.canonicalStatus, "out_for_delivery");
    assert.deepEqual(payload.data, {
      type: "order_status",
      orderId: "order_doc_123",
      status: "out_for_delivery",
      screen: "order_tracking"
    });
  });

  test("builds Delivered FCM notification", () => {
    const payload = buildNotificationPayload(orderId, orderNumber, "Delivered");
    assert.notEqual(payload, null);
    assert.equal(payload.title, "Order Delivered");
    assert.equal(payload.body, "Your Tiruttani Quick order #TQ-9876 has been delivered.");
    assert.equal(payload.canonicalStatus, "delivered");
    assert.deepEqual(payload.data, {
      type: "order_status",
      orderId: "order_doc_123",
      status: "delivered",
      screen: "order_tracking"
    });
  });

  test("builds Cancelled FCM notification", () => {
    const payload = buildNotificationPayload(orderId, orderNumber, "Cancelled");
    assert.notEqual(payload, null);
    assert.equal(payload.title, "Order Cancelled");
    assert.equal(payload.body, "Your Tiruttani Quick order #TQ-9876 has been cancelled.");
    assert.equal(payload.canonicalStatus, "cancelled");
    assert.deepEqual(payload.data, {
      type: "order_status",
      orderId: "order_doc_123",
      status: "cancelled",
      screen: "order_tracking"
    });
  });

  test("does not build notification for pending status", () => {
    const payload = buildNotificationPayload(orderId, orderNumber, "pending");
    assert.equal(payload, null);
  });
});

describe("Duplicate Protection & Unrelated Field Filtering", () => {
  test("skips when status is unchanged (e.g. Accepted -> Accepted)", async () => {
    const before = { customerId: "user_1", status: "accepted", orderNumber: "101" };
    const after = { customerId: "user_1", status: "accepted", orderNumber: "101" };
    const result = await handleOrderStatusUpdate(before, after, "doc_101");
    assert.equal(result.skipped, true);
    assert.equal(result.reason, "status_unchanged");
  });

  test("skips when unrelated fields change without status change", async () => {
    const before = {
      customerId: "user_1",
      status: "packed",
      orderNumber: "101",
      deliveryAddressId: "addr_1",
      notes: "Original note",
    };
    const after = {
      customerId: "user_1",
      status: "packed",
      orderNumber: "101",
      deliveryAddressId: "addr_2", // Address changed
      notes: "Updated note",        // Note changed
      paymentStatus: "Completed",   // Payment field changed
    };
    const result = await handleOrderStatusUpdate(before, after, "doc_101");
    assert.equal(result.skipped, true);
    assert.equal(result.reason, "status_unchanged");
  });

  test("skips when missing customerId", async () => {
    const before = { status: "pending" };
    const after = { status: "accepted" };
    const result = await handleOrderStatusUpdate(before, after, "doc_102");
    assert.equal(result.skipped, true);
    assert.equal(result.reason, "missing_customer_id");
  });
});

describe("Multi-Customer Isolation & Targeting", () => {
  test("Order A status change targets Customer A exclusively", async () => {
    const beforeA = { customerId: "cust_A_uid", status: "pending", orderNumber: "ORD_A" };
    const afterA = { customerId: "cust_A_uid", status: "accepted", orderNumber: "ORD_A" };

    const resultA = await handleOrderStatusUpdate(beforeA, afterA, "order_A_id");
    assert.equal(resultA.skipped, false);
    assert.equal(resultA.customerId, "cust_A_uid");
    assert.equal(resultA.title, "Order Accepted");
    assert.equal(resultA.status, "accepted");
    assert.match(resultA.body, /ORD_A/);
  });

  test("Order B status change targets Customer B exclusively", async () => {
    const beforeB = { customerId: "cust_B_uid", status: "packed", orderNumber: "ORD_B" };
    const afterB = { customerId: "cust_B_uid", status: "out_for_delivery", orderNumber: "ORD_B" };

    const resultB = await handleOrderStatusUpdate(beforeB, afterB, "order_B_id");
    assert.equal(resultB.skipped, false);
    assert.equal(resultB.customerId, "cust_B_uid");
    assert.equal(resultB.title, "Out for Delivery");
    assert.equal(resultB.status, "out_for_delivery");
    assert.match(resultB.body, /ORD_B/);
  });
});
