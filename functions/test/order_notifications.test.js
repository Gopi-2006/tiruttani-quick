const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const { _test } = require("../index.js");
const {
  normalizeOrderStatus,
  buildNotificationPayload,
  handleOrderStatusUpdate,
  handleOrderCreated,
} = _test;

class MockFirestore {
  constructor() {
    this.collections = new Map();
  }
  collection(name) {
    if (!this.collections.has(name)) {
      this.collections.set(name, new Map());
    }
    const store = this.collections.get(name);
    return {
      where: (field, op, val) => {
        const queryDocs = () => {
          const matchingDocs = [];
          for (const [docId, docData] of store.entries()) {
            if (op === "==" && docData[field] === val) {
              matchingDocs.push({
                id: docId,
                data: () => ({ ...docData }),
              });
            }
          }
          return matchingDocs;
        };
        return {
          get: async () => {
            const docs = queryDocs();
            return {
              empty: docs.length === 0,
              docs,
            };
          },
          limit: (num) => {
            return {
              get: async () => {
                const docs = queryDocs();
                return {
                  empty: docs.length === 0,
                  docs: docs.slice(0, num),
                };
              },
            };
          },
        };
      },
      limit: (num) => {
        return {
          get: async () => {
            const matchingDocs = [];
            for (const [docId, docData] of store.entries()) {
              matchingDocs.push({
                id: docId,
                data: () => ({ ...docData }),
              });
            }
            return {
              empty: matchingDocs.length === 0,
              forEach: (cb) => matchingDocs.slice(0, num).forEach(cb),
              docs: matchingDocs.slice(0, num),
            };
          },
        };
      },
      doc: (id) => {
        const docId = id || `mock_doc_${Date.now()}`;
        return {
          id: docId,
          get: async () => {
            const data = store.get(docId);
            return {
              exists: !!data,
              id: docId,
              data: () => (data ? { ...data } : undefined),
            };
          },
          set: async (val) => {
            store.set(docId, { ...val });
          },
          update: async (val) => {
            const existing = store.get(docId) || {};
            store.set(docId, { ...existing, ...val });
          },
          collection: (subName) => this.collection(`${name}/${docId}/${subName}`),
        };
      },
    };
  }
  async runTransaction(updateFn) {
    const tx = {
      get: async (docRef) => await docRef.get(),
      set: (docRef, val) => docRef.set(val),
      update: (docRef, val) => docRef.update(val),
    };
    return await updateFn(tx);
  }
}

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
      deliveryOtp: "",
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
      deliveryOtp: "",
      screen: "order_tracking"
    });
  });

  test("builds Out for Delivery FCM notification without OTP", () => {
    const payload = buildNotificationPayload(orderId, orderNumber, "Out for Delivery");
    assert.notEqual(payload, null);
    assert.equal(payload.title, "Out for Delivery");
    assert.equal(payload.body, "Your Tiruttani Quick order #TQ-9876 is on the way.");
    assert.equal(payload.canonicalStatus, "out_for_delivery");
    assert.deepEqual(payload.data, {
      type: "order_status",
      orderId: "order_doc_123",
      status: "out_for_delivery",
      deliveryOtp: "",
      screen: "order_tracking"
    });
  });

  test("builds Out for Delivery FCM notification with OTP", () => {
    const payload = buildNotificationPayload(orderId, orderNumber, "Out for Delivery", "654321");
    assert.notEqual(payload, null);
    assert.equal(payload.title, "Out for Delivery");
    assert.equal(payload.body, "Your Tiruttani Quick order #TQ-9876 is on the way. Delivery OTP: 654321");
    assert.equal(payload.canonicalStatus, "out_for_delivery");
    assert.deepEqual(payload.data, {
      type: "order_status",
      orderId: "order_doc_123",
      status: "out_for_delivery",
      deliveryOtp: "654321",
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
      deliveryOtp: "",
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
      deliveryOtp: "",
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

describe("Admin New Order FCM Notifications (onOrderCreated)", () => {
  test("handleOrderCreated skips gracefully when no admin tokens exist", async () => {
    const orderData = {
      orderNumber: "TQ_NEW_001",
      totalPrice: 500,
      customerId: "cust_123",
      status: "pending",
    };
    const result = await _test.handleOrderCreated(orderData, "order_new_001");
    assert.equal(result.skipped, true);
    assert.equal(result.reason, "no_admin_tokens");
    assert.equal(result.orderId, "order_new_001");
  });
});

describe("Server-Side Idempotency & Duplicate Cancellation Deduplication", () => {
  const orderId = "TQ261021113341515HAIR";
  const customerId = "cust_gopi_101";

  test("1. Duplicate cancellation event: second event is suppressed via document-level lastNotifiedStatus", async () => {
    const mockDb = new MockFirestore();
    const before = { status: "pending", customerId, orderNumber: orderId };
    const after = {
      status: "cancelled",
      customerId,
      orderNumber: orderId,
      lastNotifiedStatus: "cancelled", // Marked notified by client/earlier step
    };

    const result = await handleOrderStatusUpdate(before, after, orderId, { db: mockDb });
    assert.equal(result.skipped, true);
    assert.equal(result.reason, "already_notified");
    assert.equal(result.status, "cancelled");
    assert.equal(result.eventId, `order_status_${orderId}_cancelled_${customerId}`);
  });

  test("2. Cloud Function retries: persistent notification_idempotency collection prevents double dispatch", async () => {
    const mockDb = new MockFirestore();
    const before = { status: "packed", customerId, orderNumber: orderId };
    const after = { status: "cancelled", customerId, orderNumber: orderId };

    // Seed mock customer token
    await mockDb.collection("users").doc(customerId).set({
      fcmToken: "mock_fcm_token_1234567890",
    });

    // Attempt 1: First invocation processes and reserves notification_idempotency
    const attempt1 = await handleOrderStatusUpdate(before, after, orderId, {
      db: mockDb,
      eventId: "cloud_fn_event_uuid_111",
    });
    assert.equal(attempt1.skipped, false);
    assert.equal(attempt1.status, "cancelled");
    assert.equal(attempt1.title, "Order Cancelled");

    // Verify idempotency record exists in persistent store
    const logicalEventId = `order_status_${orderId}_cancelled_${customerId}`;
    const idempDoc = await mockDb.collection("notification_idempotency").doc(logicalEventId).get();
    assert.equal(idempDoc.exists, true);
    assert.equal(idempDoc.data().status, "cancelled");
    assert.equal(idempDoc.data().customerId, customerId);

    // Attempt 2: Simulated Cloud Function retry with same event
    const attempt2 = await handleOrderStatusUpdate(before, after, orderId, {
      db: mockDb,
      eventId: "cloud_fn_event_uuid_111",
    });
    assert.equal(attempt2.skipped, true);
    assert.equal(attempt2.reason, "already_notified");
    assert.equal(attempt2.status, "cancelled");
    assert.equal(attempt2.eventId, logicalEventId);
  });

  test("3. Preserves legitimate different status transitions on the same order", async () => {
    const mockDb = new MockFirestore();
    await mockDb.collection("users").doc(customerId).set({
      fcmToken: "mock_fcm_token_1234567890",
    });

    // Transition 1: pending -> accepted
    const res1 = await handleOrderStatusUpdate(
      { status: "pending", customerId, orderNumber: orderId },
      { status: "accepted", customerId, orderNumber: orderId },
      orderId,
      { db: mockDb }
    );
    assert.equal(res1.skipped, false);
    assert.equal(res1.status, "accepted");
    assert.equal(res1.title, "Order Accepted");

    // Transition 2: accepted -> packed (must NOT be suppressed)
    const res2 = await handleOrderStatusUpdate(
      { status: "accepted", customerId, orderNumber: orderId },
      { status: "packed", customerId, orderNumber: orderId },
      orderId,
      { db: mockDb }
    );
    assert.equal(res2.skipped, false);
    assert.equal(res2.status, "packed");
    assert.equal(res2.title, "Order Packed");

    // Transition 3: packed -> out_for_delivery (must NOT be suppressed)
    const res3 = await handleOrderStatusUpdate(
      { status: "packed", customerId, orderNumber: orderId },
      { status: "out_for_delivery", customerId, orderNumber: orderId },
      orderId,
      { db: mockDb }
    );
    assert.equal(res3.skipped, false);
    assert.equal(res3.status, "out_for_delivery");
    assert.equal(res3.title, "Out for Delivery");

    // Transition 4: out_for_delivery -> cancelled (must NOT be suppressed)
    const res4 = await handleOrderStatusUpdate(
      { status: "out_for_delivery", customerId, orderNumber: orderId },
      { status: "cancelled", customerId, orderNumber: orderId },
      orderId,
      { db: mockDb }
    );
    assert.equal(res4.skipped, false);
    assert.equal(res4.status, "cancelled");
    assert.equal(res4.title, "Order Cancelled");
  });

  test("4. Multi-recipient isolation: Cancellation on Customer A does not suppress Cancellation on Customer B", async () => {
    const mockDb = new MockFirestore();
    const custA = "customer_AAA";
    const custB = "customer_BBB";

    await mockDb.collection("users").doc(custA).set({ fcmToken: "tok_A_1234567890" });
    await mockDb.collection("users").doc(custB).set({ fcmToken: "tok_B_1234567890" });

    // Customer A cancelled
    const resA = await handleOrderStatusUpdate(
      { status: "pending", customerId: custA, orderNumber: "ORD_AAA" },
      { status: "cancelled", customerId: custA, orderNumber: "ORD_AAA" },
      "ORD_AAA",
      { db: mockDb }
    );
    assert.equal(resA.skipped, false);
    assert.equal(resA.customerId, custA);
    assert.equal(resA.title, "Order Cancelled");

    // Customer B cancelled (independent order & customer: must process successfully)
    const resB = await handleOrderStatusUpdate(
      { status: "pending", customerId: custB, orderNumber: "ORD_BBB" },
      { status: "cancelled", customerId: custB, orderNumber: "ORD_BBB" },
      "ORD_BBB",
      { db: mockDb }
    );
    assert.equal(resB.skipped, false);
    assert.equal(resB.customerId, custB);
    assert.equal(resB.title, "Order Cancelled");
  });

  test("5. Repeated status update with array notifiedStatuses suppresses redundant trigger", async () => {
    const mockDb = new MockFirestore();
    const before = { status: "pending", customerId, orderNumber: orderId };
    const after = {
      status: "cancelled",
      customerId,
      orderNumber: orderId,
      notifiedStatuses: ["accepted", "cancelled"],
    };

    const result = await handleOrderStatusUpdate(before, after, orderId, { db: mockDb });
    assert.equal(result.skipped, true);
    assert.equal(result.reason, "already_notified");
  });
});

describe("Delivery Partner Assignment Notifications (Bug 2 Fix)", () => {
  const orderId = "TQ261021113341515HAIR";
  const customerId = "cust_gopi_101";

  test("1. buildNotificationPayload produces non-empty title and body with partner name", () => {
    const payload = buildNotificationPayload(orderId, "TQ-9876", "delivery_partner_assigned", null, "Ravi Kumar");
    assert.notEqual(payload, null);
    assert.equal(payload.title, "Delivery Partner Assigned");
    assert.equal(payload.body, "Ravi Kumar has been assigned to deliver your order #TQ-9876.");
    assert.equal(payload.canonicalStatus, "delivery_partner_assigned");
    assert.equal(payload.data.type, "delivery_partner_assigned");
    assert.equal(payload.data.deliveryPersonName, "Ravi Kumar");
    assert.equal(payload.body.includes("undefined"), false);
    assert.equal(payload.body.includes("null"), false);
  });

  test("2. buildNotificationPayload handles missing partner name gracefully without empty text", () => {
    const payload = buildNotificationPayload(orderId, "TQ-9876", "delivery_partner_assigned", null, "");
    assert.notEqual(payload, null);
    assert.equal(payload.title, "Delivery Partner Assigned");
    assert.equal(payload.body, "A delivery partner has been assigned to your order #TQ-9876.");
    assert.equal(payload.body.includes("undefined"), false);
    assert.equal(payload.body.includes("null"), false);
  });

  test("3. Delivery assignment notification does NOT expose customer or partner phone numbers in body", () => {
    const payload = buildNotificationPayload(orderId, "TQ-9876", "delivery_partner_assigned", null, "Suresh");
    assert.equal(payload.body.includes("9876543210"), false);
    assert.equal(payload.body.includes("phone"), false);
  });

  test("4. handleOrderStatusUpdate triggers delivery_partner_assigned when partner assigned with status unchanged", async () => {
    const mockDb = new MockFirestore();
    await mockDb.collection("users").doc(customerId).set({
      fcmToken: "mock_customer_token_12345",
    });

    const before = {
      status: "packed",
      customerId,
      orderNumber: "TQ-9876",
      deliveryPersonName: null,
      deliveryPersonPhone: null,
    };
    const after = {
      status: "packed",
      customerId,
      orderNumber: "TQ-9876",
      deliveryPersonName: "Ravi Kumar",
      deliveryPersonPhone: "9876543210",
    };

    const result = await handleOrderStatusUpdate(before, after, orderId, { db: mockDb });
    assert.equal(result.skipped, false);
    assert.equal(result.status, "delivery_partner_assigned");
    assert.equal(result.title, "Delivery Partner Assigned");
    assert.equal(result.body, "Ravi Kumar has been assigned to deliver your order #TQ-9876.");
    assert.equal(result.deliveryPersonName, "Ravi Kumar");

    // Verify idempotency record written to persistent store
    const expectedEventId = `order_delivery_assigned_${orderId}_Ravi Kumar_${customerId}`;
    const idempDoc = await mockDb.collection("notification_idempotency").doc(expectedEventId).get();
    assert.equal(idempDoc.exists, true);
    assert.equal(idempDoc.data().deliveryPersonName, "Ravi Kumar");
    assert.equal(idempDoc.data().status, "delivery_partner_assigned");

    // Second execution (simulated retry) is suppressed as already_notified
    const retryResult = await handleOrderStatusUpdate(before, after, orderId, { db: mockDb });
    assert.equal(retryResult.skipped, true);
    assert.equal(retryResult.reason, "already_notified");
  });

  test("5. Multi-recipient: Notifies assigned delivery partner when registered without notifying customer twice", async () => {
    const mockDb = new MockFirestore();
    const partnerPhone = "9876543210";
    const partnerUid = "partner_user_uuid_777";

    await mockDb.collection("users").doc(customerId).set({
      fcmToken: "cust_token_12345",
    });
    await mockDb.collection("users").doc(partnerUid).set({
      phone: partnerPhone,
      fcmToken: "partner_token_67890",
    });

    const before = {
      status: "packed",
      customerId,
      orderNumber: "TQ-9876",
      deliveryPersonName: "",
    };
    const after = {
      status: "packed",
      customerId,
      orderNumber: "TQ-9876",
      deliveryPersonName: "Ravi Kumar",
      deliveryPersonPhone: partnerPhone,
    };

    const result = await handleOrderStatusUpdate(before, after, orderId, { db: mockDb });
    assert.equal(result.skipped, false);
    assert.equal(result.customerId, customerId);

    // Verify partner idempotency lock was created
    const partnerEventId = `order_delivery_assigned_dp_${orderId}_${partnerUid}`;
    const partnerIdemp = await mockDb.collection("notification_idempotency").doc(partnerEventId).get();
    assert.equal(partnerIdemp.exists, true);
    assert.equal(partnerIdemp.data().partnerUid, partnerUid);
  });

  test("6. Anti-collision: Does NOT dispatch partner notification if partner phone belongs to customer", async () => {
    const mockDb = new MockFirestore();
    const phone = "9876543210";

    // Customer has this phone number
    await mockDb.collection("users").doc(customerId).set({
      phone: phone,
      fcmToken: "cust_token_12345",
    });

    const before = { status: "packed", customerId, orderNumber: "TQ-9876" };
    const after = {
      status: "packed",
      customerId,
      orderNumber: "TQ-9876",
      deliveryPersonName: "Self Delivery",
      deliveryPersonPhone: phone,
    };

    const result = await handleOrderStatusUpdate(before, after, orderId, { db: mockDb });
    assert.equal(result.skipped, false);

    // Partner event should NOT exist because partnerUid == customerId
    const selfPartnerEventId = `order_delivery_assigned_dp_${orderId}_${customerId}`;
    const idempDoc = await mockDb.collection("notification_idempotency").doc(selfPartnerEventId).get();
    assert.equal(idempDoc.exists, false);
  });
});

describe("Admin New Order Deduplication & Idempotency", () => {
  const newOrderId = "TQ261021140405116VFTW";

  test("1. First new order creation dispatches exactly once and creates idempotency record", async () => {
    const mockDb = new MockFirestore();
    await mockDb.collection("users").doc("admin_1").set({
      role: "Admin",
      fcmToken: "admin_fcm_token_123456",
    });

    const orderData = {
      orderNumber: "TQ-116",
      totalPrice: 450,
      customerId: "cust_test_1",
    };

    const result = await handleOrderCreated(orderData, newOrderId, { db: mockDb });
    assert.equal(result.skipped, false);
    assert.equal(result.orderId, newOrderId);
    assert.equal(result.tokenCount, 1);

    // Verify idempotency record exists in notification_idempotency collection
    const idempDoc = await mockDb.collection("notification_idempotency").doc(`order_new_${newOrderId}`).get();
    assert.equal(idempDoc.exists, true);
    assert.equal(idempDoc.data().status, "new_order");
    assert.equal(idempDoc.data().orderId, newOrderId);

    // Verify order document in orders collection was marked notified
    const orderDoc = await mockDb.collection("orders").doc(newOrderId).get();
    assert.equal(orderDoc.exists, true);
    assert.equal(orderDoc.data().lastNotifiedStatus, "new_order");
  });

  test("2. Cloud Function retry or duplicate trigger skips via persistent idempotency lock", async () => {
    const mockDb = new MockFirestore();
    await mockDb.collection("users").doc("admin_1").set({
      role: "Admin",
      fcmToken: "admin_fcm_token_123456",
    });

    // Simulate prior dispatch recorded in notification_idempotency
    await mockDb.collection("notification_idempotency").doc(`order_new_${newOrderId}`).set({
      orderId: newOrderId,
      status: "new_order",
      dispatchedAt: new Date(),
    });

    const orderData = {
      orderNumber: "TQ-116",
      totalPrice: 450,
      customerId: "cust_test_1",
    };

    const result = await handleOrderCreated(orderData, newOrderId, { db: mockDb });
    assert.equal(result.skipped, true);
    assert.equal(result.reason, "already_notified");
  });

  test("3. Order document with lastNotifiedStatus: 'new_order' skips immediately (client already sent)", async () => {
    const mockDb = new MockFirestore();
    const orderData = {
      orderNumber: "TQ-116",
      totalPrice: 450,
      customerId: "cust_test_1",
      lastNotifiedStatus: "new_order",
      notifiedStatuses: ["new_order"],
    };

    const result = await handleOrderCreated(orderData, newOrderId, { db: mockDb });
    assert.equal(result.skipped, true);
    assert.equal(result.reason, "already_notified");
  });

  test("4. Full Lifecycle: Single notification per status transition (Accepted -> Packed -> Out for Delivery -> Delivered)", async () => {
    const mockDb = new MockFirestore();
    const customerId = "cust_lifecycle_99";
    await mockDb.collection("users").doc(customerId).set({
      fcmToken: "cust_fcm_lifecycle_token",
    });

    const orderId = "ORD_LIFECYCLE_100";

    // 1. Placed -> Accepted
    const res1 = await handleOrderStatusUpdate(
      { status: "order_placed", customerId, orderNumber: "TQ-100" },
      { status: "accepted", customerId, orderNumber: "TQ-100" },
      orderId,
      { db: mockDb }
    );
    assert.equal(res1.skipped, false);
    assert.equal(res1.status, "accepted");

    // 1b. Duplicate Accepted trigger skips
    const res1b = await handleOrderStatusUpdate(
      { status: "order_placed", customerId, orderNumber: "TQ-100" },
      { status: "accepted", customerId, orderNumber: "TQ-100" },
      orderId,
      { db: mockDb }
    );
    assert.equal(res1b.skipped, true);
    assert.equal(res1b.reason, "already_notified");

    // 2. Accepted -> Packed
    const res2 = await handleOrderStatusUpdate(
      { status: "accepted", customerId, orderNumber: "TQ-100" },
      { status: "packed", customerId, orderNumber: "TQ-100" },
      orderId,
      { db: mockDb }
    );
    assert.equal(res2.skipped, false);
    assert.equal(res2.status, "packed");

    // 3. Packed -> Out for Delivery
    const res3 = await handleOrderStatusUpdate(
      { status: "packed", customerId, orderNumber: "TQ-100" },
      { status: "out_for_delivery", customerId, orderNumber: "TQ-100", deliveryPersonName: "Karthik" },
      orderId,
      { db: mockDb }
    );
    assert.equal(res3.skipped, false);
    assert.equal(res3.status, "out_for_delivery");
    assert.ok(res3.deliveryOtp);

    // 4. Out for Delivery -> Delivered
    const res4 = await handleOrderStatusUpdate(
      { status: "out_for_delivery", customerId, orderNumber: "TQ-100", deliveryPersonName: "Karthik" },
      { status: "delivered", customerId, orderNumber: "TQ-100", deliveryPersonName: "Karthik" },
      orderId,
      { db: mockDb }
    );
    assert.equal(res4.skipped, false);
    assert.equal(res4.status, "delivered");

    // 4b. Duplicate Delivered trigger skips
    const res4b = await handleOrderStatusUpdate(
      { status: "out_for_delivery", customerId, orderNumber: "TQ-100" },
      { status: "delivered", customerId, orderNumber: "TQ-100" },
      orderId,
      { db: mockDb }
    );
    assert.equal(res4b.skipped, true);
    assert.equal(res4b.reason, "already_notified");
  });
});

describe("Advanced Reliability: Concurrent Leases, FCM Retries & Payload Validation", () => {
  const orderId = "ORD_ADV_RELIABILITY_999";
  const customerId = "cust_adv_user_1";

  test("1. Concurrent in-flight lease prevents duplicate concurrent dispatch", async () => {
    const mockDb = new MockFirestore();
    const logicalEventId = `order_status_${orderId}_accepted_${customerId}`;

    // Seed active in-flight lease held by another worker
    await mockDb.collection("notification_idempotency").doc(logicalEventId).set({
      eventId: logicalEventId,
      state: "sending",
      leaseExpiresAt: new Date(Date.now() + 60000), // expires in 60s
      attempts: 1,
    });

    const result = await handleOrderStatusUpdate(
      { status: "pending", customerId, orderNumber: "TQ-999" },
      { status: "accepted", customerId, orderNumber: "TQ-999" },
      orderId,
      { db: mockDb }
    );

    assert.equal(result.skipped, true);
    assert.equal(result.reason, "in_progress");
  });

  test("2. Expired in-flight lease is successfully re-acquired for safe retry", async () => {
    const mockDb = new MockFirestore();
    const logicalEventId = `order_status_${orderId}_accepted_${customerId}`;

    // Seed expired lease from a crashed worker (expired 10s ago)
    await mockDb.collection("notification_idempotency").doc(logicalEventId).set({
      eventId: logicalEventId,
      state: "sending",
      leaseExpiresAt: new Date(Date.now() - 10000),
      attempts: 1,
    });

    await mockDb.collection("users").doc(customerId).set({
      fcmToken: "mock_fcm_token_recovered",
    });

    const result = await handleOrderStatusUpdate(
      { status: "pending", customerId, orderNumber: "TQ-999" },
      { status: "accepted", customerId, orderNumber: "TQ-999" },
      orderId,
      { db: mockDb }
    );

    assert.equal(result.skipped, false);
    assert.equal(result.status, "accepted");

    // Verify lease was promoted to sent
    const idempDoc = await mockDb.collection("notification_idempotency").doc(logicalEventId).get();
    assert.equal(idempDoc.data().state, "sent");
    assert.equal(idempDoc.data().attempts, 2);
  });

  test("3. FCM dispatch failure marks state as failed and subsequent retry succeeds", async () => {
    const mockDb = new MockFirestore();
    const logicalEventId = `order_status_${orderId}_packed_${customerId}`;

    await mockDb.collection("users").doc(customerId).set({
      fcmToken: "mock_fcm_token_retry",
    });

    // Attempt 1 with failing messaging service
    const failingMessaging = {
      send: async () => {
        throw new Error("FCM_NETWORK_UNREACHABLE_TIMEOUT");
      },
    };

    const res1 = await handleOrderStatusUpdate(
      { status: "accepted", customerId, orderNumber: "TQ-999" },
      { status: "packed", customerId, orderNumber: "TQ-999" },
      orderId,
      { db: mockDb, messaging: failingMessaging }
    );

    // Should indicate dispatch failed
    assert.equal(res1.fcmResult.success, false);

    // Verify document marked failed
    const idempDoc1 = await mockDb.collection("notification_idempotency").doc(logicalEventId).get();
    assert.equal(idempDoc1.data().state, "failed");
    assert.equal(idempDoc1.data().lastError, "FCM_NETWORK_UNREACHABLE_TIMEOUT");

    // Attempt 2 with recovered messaging service
    const workingMessaging = {
      send: async () => "projects/tiruttani-quick/messages/success_123",
    };

    const res2 = await handleOrderStatusUpdate(
      { status: "accepted", customerId, orderNumber: "TQ-999" },
      { status: "packed", customerId, orderNumber: "TQ-999" },
      orderId,
      { db: mockDb, messaging: workingMessaging }
    );

    assert.equal(res2.skipped, false);
    assert.equal(res2.status, "packed");
    assert.equal(res2.fcmResult.success, true);

    // Verify state transitioned to sent
    const idempDoc2 = await mockDb.collection("notification_idempotency").doc(logicalEventId).get();
    assert.equal(idempDoc2.data().state, "sent");
    assert.equal(idempDoc2.data().attempts, 2);
  });

  test("4. Empty or whitespace delivery partner name does not produce blank title or body", async () => {
    const mockDb = new MockFirestore();

    const before = {
      status: "packed",
      customerId,
      orderNumber: "TQ-999",
      deliveryPersonName: null,
    };
    const after = {
      status: "packed",
      customerId,
      orderNumber: "TQ-999",
      deliveryPersonName: "   ", // only whitespace
    };

    const result = await handleOrderStatusUpdate(before, after, orderId, { db: mockDb });
    // Status is unchanged and clean partner name is empty -> ignored safely
    assert.equal(result.skipped, true);
    assert.equal(result.reason, "status_unchanged");
  });
});
