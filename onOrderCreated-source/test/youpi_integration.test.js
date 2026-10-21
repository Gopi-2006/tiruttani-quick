const { test, describe, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const {
  handleCreatePaymentSession,
  handleYoupiWebhook,
  handleConvertOrderToCod,
  handleCleanupUnpaidOrders
} = require("../youpi_payment");

// In-Memory Mock Firestore Implementation for fast, deterministic, offline testing
class MockFirestore {
  constructor() {
    this.collections = new Map();
  }

  collection(name) {
    if (!this.collections.has(name)) {
      this.collections.set(name, new Map());
    }
    const store = this.collections.get(name);

    const createQuery = (filters = []) => {
      return {
        where: (field, op, value) => {
          return createQuery([...filters, { field, op, value }]);
        },
        limit: (n) => ({
          get: async () => {
            const res = await createQuery(filters).get();
            const docs = res.docs.slice(0, n);
            return { docs, empty: docs.length === 0 };
          }
        }),
        get: async () => {
          const docs = [];
          for (const [id, data] of store.entries()) {
            let matches = true;
            for (const f of filters) {
              if (f.op === "==" && data[f.field] !== f.value) {
                matches = false;
                break;
              }
            }
            if (matches) {
              docs.push({
                id,
                ref: this.collection(name).doc(id),
                data: () => ({ ...data })
              });
            }
          }
          return { docs, empty: docs.length === 0 };
        }
      };
    };

    return {
      doc: (id) => {
        const docId = id || `mock_doc_${Date.now()}_${Math.random()}`;
        return {
          id: docId,
          get: async () => {
            const data = store.get(docId);
            return {
              exists: !!data,
              id: docId,
              data: () => (data ? { ...data } : undefined)
            };
          },
          set: async (val) => {
            store.set(docId, { ...val });
          },
          update: async (val) => {
            const existing = store.get(docId) || {};
            const updated = { ...existing };
            for (const [k, v] of Object.entries(val)) {
              if (v && typeof v === "object" && ("operand" in v || v.constructor?.name?.includes("Increment"))) {
                updated[k] = (Number(updated[k]) || 0) + Number(v.operand || 0);
              } else {
                updated[k] = v;
              }
            }
            store.set(docId, updated);
          },
          collection: (subName) => this.collection(`${name}/${docId}/${subName}`)
        };
      },
      ...createQuery()
    };
  }

  async runTransaction(updateFn) {
    const tx = {
      get: async (docRef) => await docRef.get(),
      update: (docRef, val) => docRef.update(val),
      set: (docRef, val) => docRef.set(val)
    };
    return await updateFn(tx);
  }
}

// Mock Response Helper
function createMockRes() {
  const res = {
    statusCode: 200,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(data) {
      this.body = data;
      return this;
    }
  };
  return res;
}

describe("YouPI-PG + Tiruttani Quick Integration Test Suite", () => {
  let mockDb;
  let mockAuth;
  const WEBHOOK_SECRET = "test_webhook_secret_demo";
  const MERCHANT_API_KEY = "test_api_key_demo";

  beforeEach(() => {
    mockDb = new MockFirestore();
    mockAuth = {
      verifyIdToken: async (token) => {
        if (token === "valid_cust_token") {
          return { uid: "customer_123", email: "customer@example.com" };
        }
        if (token === "other_cust_token") {
          return { uid: "customer_999", email: "other@example.com" };
        }
        throw new Error("Invalid token");
      }
    };
    process.env.YOUPI_WEBHOOK_SECRET = WEBHOOK_SECRET;
    process.env.YOUPI_MERCHANT_API_KEY = MERCHANT_API_KEY;
  });

  // ─── 1. PAYMENT SESSION CREATION TESTS ─────────────────────────────────────
  describe("1. Payment Session Creation", () => {
    test("Successfully creates a YouPI payment session for a valid pending order", async () => {
      // Seed pending order
      await mockDb.collection("orders").doc("ORD-101").set({
        orderNumber: "TQ26001",
        customerId: "customer_123",
        totalPrice: 250.00,
        paymentMethod: "UPI",
        paymentStatus: "Pending"
      });

      const mockFetch = async (url, opts) => {
        assert.match(url, /\/api\/v1\/payments$/);
        assert.equal(opts.headers.Authorization, `Bearer ${MERCHANT_API_KEY}`);
        const parsedBody = JSON.parse(opts.body);
        assert.equal(parsedBody.amount, "250.00");
        assert.equal(parsedBody.orderId, "TQ26001");
        return {
          ok: true,
          json: async () => ({
            paymentId: "youpi_pay_abc123",
            checkoutUrl: "http://localhost:7000/checkout/youpi_pay_abc123"
          })
        };
      };

      const req = {
        method: "POST",
        headers: { authorization: "Bearer valid_cust_token" },
        body: { orderId: "ORD-101" }
      };
      const res = createMockRes();

      await handleCreatePaymentSession(req, res, { db: mockDb, auth: mockAuth, fetchFn: mockFetch });

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.paymentId, "youpi_pay_abc123");
      assert.equal(res.body.checkoutUrl, "http://localhost:7000/checkout/youpi_pay_abc123");

      // Verify session stored on order
      const order = (await mockDb.collection("orders").doc("ORD-101").get()).data();
      assert.equal(order.youpiPaymentId, "youpi_pay_abc123");
    });

    test("Rejects session creation if customer does not own the order (Anti-Hijacking)", async () => {
      await mockDb.collection("orders").doc("ORD-102").set({
        orderNumber: "TQ26002",
        customerId: "customer_123", // Owned by 123
        totalPrice: 150.00,
        paymentMethod: "UPI",
        paymentStatus: "Pending"
      });

      const req = {
        method: "POST",
        headers: { authorization: "Bearer other_cust_token" }, // Requested by 999
        body: { orderId: "ORD-102" }
      };
      const res = createMockRes();

      await handleCreatePaymentSession(req, res, { db: mockDb, auth: mockAuth });
      assert.equal(res.statusCode, 403);
      assert.equal(res.body.error, "FORBIDDEN");
    });
  });

  // ─── 2. WRONG AMOUNT & WRONG ORDER ID TESTS ──────────────────────────────
  describe("2. Wrong Amount and Wrong Order ID Validation", () => {
    test("Rejects session creation for nonexistent order ID", async () => {
      const req = {
        method: "POST",
        headers: { authorization: "Bearer valid_cust_token" },
        body: { orderId: "NON_EXISTENT_ORDER" }
      };
      const res = createMockRes();

      await handleCreatePaymentSession(req, res, { db: mockDb, auth: mockAuth });
      assert.equal(res.statusCode, 404);
      assert.equal(res.body.error, "NOT_FOUND");
    });

    test("Rejects session creation if order total price is zero or negative", async () => {
      await mockDb.collection("orders").doc("ORD-ZERO").set({
        customerId: "customer_123",
        totalPrice: 0.00,
        paymentMethod: "UPI",
        paymentStatus: "Pending"
      });

      const req = {
        method: "POST",
        headers: { authorization: "Bearer valid_cust_token" },
        body: { orderId: "ORD-ZERO" }
      };
      const res = createMockRes();

      await handleCreatePaymentSession(req, res, { db: mockDb, auth: mockAuth });
      assert.equal(res.statusCode, 400);
      assert.equal(res.body.error, "INVALID_AMOUNT");
    });

    test("Webhook rejects payment confirmation if amount does not match order amount", async () => {
      await mockDb.collection("orders").doc("ORD-AMT").set({
        orderNumber: "ORD-AMT",
        customerId: "customer_123",
        totalPrice: 500.00, // Expected ₹500.00
        paymentMethod: "UPI",
        paymentStatus: "Pending"
      });

      const payload = {
        event: "SUCCESS",
        paymentId: "pay_test_001",
        orderId: "ORD-AMT",
        amount: "50.00", // Tampered ₹50.00 injected
        amountPaise: 5000,
        currency: "INR"
      };

      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

      const req = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-wrong-amt-1",
          "x-gateway-event": "SUCCESS"
        },
        rawBody,
        body: payload
      };
      const res = createMockRes();

      await handleYoupiWebhook(req, res, { db: mockDb });

      assert.equal(res.statusCode, 400);
      assert.equal(res.body.error, "AMOUNT_MISMATCH");

      // Verify order remained Pending (never marked Paid)
      const order = (await mockDb.collection("orders").doc("ORD-AMT").get()).data();
      assert.equal(order.paymentStatus, "Pending");
    });
  });

  // ─── 3. INVALID WEBHOOK SIGNATURE TESTS ──────────────────────────────────
  describe("3. Invalid Webhook Signature", () => {
    test("Rejects webhook with forged or mismatched HMAC signature", async () => {
      const payload = {
        event: "SUCCESS",
        paymentId: "pay_forged",
        orderId: "ORD-101",
        amount: "250.00",
        amountPaise: 25000
      };
      const rawBody = JSON.stringify(payload);
      const forgedSig = crypto.createHmac("sha256", "wrong_attacker_secret").update(rawBody).digest("hex");

      const req = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${forgedSig}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-forged-1"
        },
        rawBody,
        body: payload
      };
      const res = createMockRes();

      await handleYoupiWebhook(req, res, { db: mockDb });
      assert.equal(res.statusCode, 401);
      assert.equal(res.body.error, "INVALID_SIGNATURE");
    });

    test("Rejects webhook missing required authentication headers", async () => {
      const req = {
        method: "POST",
        headers: {},
        body: { event: "SUCCESS" }
      };
      const res = createMockRes();

      await handleYoupiWebhook(req, res, { db: mockDb });
      assert.equal(res.statusCode, 401);
      assert.equal(res.body.error, "MISSING_AUTHENTICATION");
    });
  });

  // ─── 4. DUPLICATE / REPLAYED WEBHOOK TESTS ───────────────────────────────
  describe("4. Duplicate and Replayed Webhooks", () => {
    test("Rejects stale replayed webhook older than the 5-minute freshness window", async () => {
      const payload = { event: "SUCCESS", paymentId: "pay_old", orderId: "ORD-101", amount: "250.00" };
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

      const tenMinutesAgo = Date.now() - 10 * 60 * 1000;

      const req = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": tenMinutesAgo.toString(),
          "x-gateway-delivery-id": "deliv-stale-1"
        },
        rawBody,
        body: payload
      };
      const res = createMockRes();

      await handleYoupiWebhook(req, res, { db: mockDb });
      assert.equal(res.statusCode, 401);
      assert.equal(res.body.error, "REPLAY_WINDOW_EXPIRED");
    });

    test("Idempotently acknowledges duplicate delivery without re-processing", async () => {
      await mockDb.collection("orders").doc("ORD-IDEMP").set({
        orderNumber: "ORD-IDEMP",
        totalPrice: 300.00,
        paymentStatus: "Pending"
      });

      const payload = {
        event: "SUCCESS",
        paymentId: "pay_idemp",
        orderId: "ORD-IDEMP",
        amount: "300.00",
        amountPaise: 30000,
        currency: "INR",
        utr: "123456789012"
      };
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

      const req = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "delivery-unique-123"
        },
        rawBody,
        body: payload
      };

      // First delivery
      const res1 = createMockRes();
      await handleYoupiWebhook(req, res1, { db: mockDb });
      assert.equal(res1.statusCode, 200);
      assert.equal(res1.body.processed, true);

      // Verify order marked Paid
      const order1 = (await mockDb.collection("orders").doc("ORD-IDEMP").get()).data();
      assert.equal(order1.paymentStatus, "Paid");
      assert.equal(order1.paymentUtr, "123456789012");

      // Second delivery (duplicate retry)
      const res2 = createMockRes();
      await handleYoupiWebhook(req, res2, { db: mockDb });
      assert.equal(res2.statusCode, 200);
      assert.equal(res2.body.message, "ALREADY_PROCESSED");
    });

    test("Handles concurrent duplicate webhook deliveries atomically", async () => {
      await mockDb.collection("orders").doc("ORD-CONCUR-IDEMP").set({
        orderNumber: "ORD-CONCUR-IDEMP",
        totalPrice: 200.00,
        paymentStatus: "Pending"
      });

      const payload = {
        event: "SUCCESS",
        paymentId: "pay_concur_1",
        orderId: "ORD-CONCUR-IDEMP",
        amount: "200.00",
        amountPaise: 20000,
        currency: "INR"
      };
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

      const reqA = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-concur-idemp-1"
        },
        rawBody,
        body: payload
      };
      const reqB = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-concur-idemp-1"
        },
        rawBody,
        body: payload
      };
      const resA = createMockRes();
      const resB = createMockRes();

      await Promise.all([
        handleYoupiWebhook(reqA, resA, { db: mockDb }),
        handleYoupiWebhook(reqB, resB, { db: mockDb })
      ]);

      assert.equal(resA.statusCode, 200);
      assert.equal(resB.statusCode, 200);

      const order = (await mockDb.collection("orders").doc("ORD-CONCUR-IDEMP").get()).data();
      assert.equal(order.paymentStatus, "Paid");
    });

    test("Rejects webhook missing paymentId with 400 MISSING_PAYMENT_ID", async () => {
      await mockDb.collection("orders").doc("ORD-NO-PAYID").set({
        orderNumber: "ORD-NO-PAYID",
        totalPrice: 100.00,
        paymentStatus: "Pending"
      });

      const payload = {
        event: "SUCCESS",
        orderId: "ORD-NO-PAYID",
        amount: "100.00",
        amountPaise: 10000,
        currency: "INR"
      };
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

      const req = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-no-payid-1"
        },
        rawBody,
        body: payload
      };
      const res = createMockRes();

      await handleYoupiWebhook(req, res, { db: mockDb });
      assert.equal(res.statusCode, 400);
      assert.equal(res.body.error, "MISSING_PAYMENT_ID");
    });

    test("Rejects webhook with unknown or unsupported event with 400 UNSUPPORTED_EVENT", async () => {
      await mockDb.collection("orders").doc("ORD-UNSUPPORTED-EVT").set({
        orderNumber: "ORD-UNSUPPORTED-EVT",
        totalPrice: 100.00,
        paymentStatus: "Pending"
      });

      const payload = {
        event: "UNKNOWN_CHARGE",
        paymentId: "pay_unknown_evt",
        orderId: "ORD-UNSUPPORTED-EVT",
        amount: "100.00",
        amountPaise: 10000,
        currency: "INR"
      };
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

      const req = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-unknown-evt-1"
        },
        rawBody,
        body: payload
      };
      const res = createMockRes();

      await handleYoupiWebhook(req, res, { db: mockDb });
      assert.equal(res.statusCode, 400);
      assert.equal(res.body.error, "UNSUPPORTED_EVENT");
    });
  });

  // ─── 5. PAYMENT CANCELLATION AND EXPIRY TESTS ────────────────────────────
  describe("5. Payment Cancellation and Expiry Handling", () => {
    test("Transitions order to CANCELLED and marks paymentStatus to Expired/Failed", async () => {
      await mockDb.collection("orders").doc("ORD-EXP").set({
        orderNumber: "ORD-EXP",
        totalPrice: 180.00,
        paymentStatus: "Pending",
        status: "ORDER_PLACED"
      });

      const payload = {
        event: "EXPIRED",
        paymentId: "pay_exp",
        orderId: "ORD-EXP",
        amount: "180.00",
        amountPaise: 18000
      };
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

      const req = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-exp-1"
        },
        rawBody,
        body: payload
      };
      const res = createMockRes();

      await handleYoupiWebhook(req, res, { db: mockDb });
      assert.equal(res.statusCode, 200);

      const order = (await mockDb.collection("orders").doc("ORD-EXP").get()).data();
      assert.equal(order.paymentStatus, "Expired");
      assert.equal(order.status, "CANCELLED");
    });
  });

  // ─── 6. DUPLICATE INVENTORY UPDATES PREVENTION ───────────────────────────
  describe("6. Inventory Protection", () => {
    test("Does NOT double-deduct inventory when payment succeeds", async () => {
      // Seed product with initial stock
      await mockDb.collection("products").doc("PROD-1").set({
        name: "Aashirvaad Atta",
        stockQuantity: 45 // Stock already decremented from 50 to 45 at checkout
      });

      await mockDb.collection("orders").doc("ORD-INV").set({
        orderNumber: "ORD-INV",
        totalPrice: 200.00,
        paymentStatus: "Pending"
      });

      const payload = {
        event: "SUCCESS",
        paymentId: "pay_inv",
        orderId: "ORD-INV",
        amount: "200.00",
        amountPaise: 20000
      };
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

      const req = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-inv-1"
        },
        rawBody,
        body: payload
      };
      const res = createMockRes();

      await handleYoupiWebhook(req, res, { db: mockDb });

      // Verify product stock was NOT deducted again
      const prod = (await mockDb.collection("products").doc("PROD-1").get()).data();
      assert.equal(prod.stockQuantity, 45); // Unchanged!
    });
  });

  // ─── 7. PRESERVES COD AND UPI-ON-DELIVERY ─────────────────────────────────
  describe("7. COD and UPI-on-Delivery Compatibility", () => {
    test("Cash on Delivery orders remain completely independent of online webhook flows", async () => {
      await mockDb.collection("orders").doc("ORD-COD").set({
        orderNumber: "ORD-COD",
        customerId: "customer_123",
        totalPrice: 499.00,
        paymentMethod: "COD",
        paymentStatus: "Pending",
        status: "ORDER_PLACED"
      });

      // Customer app creates session request for COD
      const req = {
        method: "POST",
        headers: { authorization: "Bearer valid_cust_token" },
        body: { orderId: "ORD-COD" }
      };
      const res = createMockRes();

      await handleCreatePaymentSession(req, res, { db: mockDb, auth: mockAuth });
      // COD orders should be rejected by the online UPI session creator
      assert.equal(res.statusCode, 400);
      assert.equal(res.body.error, "INVALID_METHOD");

      // Verify COD order remains safely in Pending state
      const codOrder = (await mockDb.collection("orders").doc("ORD-COD").get()).data();
      assert.equal(codOrder.paymentMethod, "COD");
      assert.equal(codOrder.paymentStatus, "Pending");
    });
  });

  // ─── 8. CUSTOMER / ADMIN STATUS SYNCHRONIZATION ──────────────────────────
  describe("8. Customer/Admin Payment Status Synchronization", () => {
    test("Updates order payment status so customer and admin see Paid state immediately", async () => {
      await mockDb.collection("orders").doc("ORD-SYNC").set({
        orderNumber: "ORD-SYNC",
        customerId: "customer_123",
        totalPrice: 199.00,
        paymentStatus: "Pending",
        status: "ORDER_PLACED"
      });

      const payload = {
        event: "SUCCESS",
        paymentId: "pay_sync",
        orderId: "ORD-SYNC",
        amount: "199.00",
        amountPaise: 19900,
        utr: "998877665544"
      };
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

      const req = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-sync-1"
        },
        rawBody,
        body: payload
      };
      const res = createMockRes();

      await handleYoupiWebhook(req, res, { db: mockDb });

      const updatedOrder = (await mockDb.collection("orders").doc("ORD-SYNC").get()).data();
      assert.equal(updatedOrder.paymentStatus, "Paid");
      assert.equal(updatedOrder.paymentUtr, "998877665544");
      assert.equal(updatedOrder.youpiWebhookDeliveryId, "deliv-sync-1");
    });
  });

  // ─── 9. ADVANCED SECURITY & HARDENING VERIFICATION ────────────────────────
  describe("9. Advanced Security & Hardening Controls", () => {
    test("Rejects webhook when paymentId mismatches the order's linked session", async () => {
      await mockDb.collection("orders").doc("ORD-MISMATCH").set({
        orderNumber: "ORD-MISMATCH",
        customerId: "customer_123",
        totalPrice: 150.00,
        paymentStatus: "Pending",
        youpiPaymentId: "legit_payment_session_111"
      });

      const payload = {
        event: "SUCCESS",
        paymentId: "unrelated_session_999", // Mismatch
        orderId: "ORD-MISMATCH",
        amount: "150.00",
        amountPaise: 15000
      };
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

      const req = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-mismatch-1"
        },
        rawBody,
        body: payload
      };
      const res = createMockRes();

      await handleYoupiWebhook(req, res, { db: mockDb });
      assert.equal(res.statusCode, 400);
      assert.equal(res.body.error, "PAYMENT_ID_MISMATCH");
    });

    test("Does NOT revive an already CANCELLED order to Paid (flags as late payment)", async () => {
      await mockDb.collection("orders").doc("ORD-ALREADY-CANCELLED").set({
        orderNumber: "ORD-ALREADY-CANCELLED",
        customerId: "customer_123",
        totalPrice: 200.00,
        paymentStatus: "Cancelled",
        status: "CANCELLED"
      });

      const payload = {
        event: "SUCCESS",
        paymentId: "pay_late_success",
        orderId: "ORD-ALREADY-CANCELLED",
        amount: "200.00",
        amountPaise: 20000,
        utr: "555566667777"
      };
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

      const req = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-late-1"
        },
        rawBody,
        body: payload
      };
      const res = createMockRes();

      await handleYoupiWebhook(req, res, { db: mockDb });
      assert.equal(res.statusCode, 200);

      // Verify order is still Cancelled, but flagged for admin refund
      const order = (await mockDb.collection("orders").doc("ORD-ALREADY-CANCELLED").get()).data();
      assert.equal(order.status, "CANCELLED");
      assert.equal(order.paymentStatus, "Cancelled");
      assert.equal(order.latePaymentFlag, true);
      assert.equal(order.latePaymentUtr, "555566667777");
    });

    test("Multiple cancel/expire webhooks only restore product inventory once", async () => {
      await mockDb.collection("products").doc("PROD-MULTI").set({
        name: "Sugar 1kg",
        stockQuantity: 20
      });

      // Seed order with order_items
      await mockDb.collection("orders").doc("ORD-MULTI-RESTORE").set({
        orderNumber: "ORD-MULTI-RESTORE",
        totalPrice: 100.00,
        paymentStatus: "Pending",
        status: "ORDER_PLACED"
      });
      await mockDb.collection("orders/ORD-MULTI-RESTORE/order_items").doc("item1").set({
        productId: "PROD-MULTI",
        quantity: 5
      });

      const payload = {
        event: "EXPIRED",
        paymentId: "pay_multi_exp",
        orderId: "ORD-MULTI-RESTORE",
        amount: "100.00",
        amountPaise: 10000
      };
      const rawBody = JSON.stringify(payload);
      const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

      // First webhook
      const req1 = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${signature}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-restore-1"
        },
        rawBody,
        body: payload
      };
      const res1 = createMockRes();
      await handleYoupiWebhook(req1, res1, { db: mockDb });

      const prodAfter1 = (await mockDb.collection("products").doc("PROD-MULTI").get()).data();
      assert.equal(prodAfter1.stockQuantity, 25); // Restored from 20 to 25

      // Second webhook (e.g. CANCELLED following EXPIRED)
      const payload2 = { ...payload, event: "CANCELLED" };
      const rawBody2 = JSON.stringify(payload2);
      const sig2 = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody2).digest("hex");
      const req2 = {
        method: "POST",
        headers: {
          "x-gateway-signature": `sha256=${sig2}`,
          "x-gateway-timestamp": Date.now().toString(),
          "x-gateway-delivery-id": "deliv-restore-2"
        },
        rawBody: rawBody2,
        body: payload2
      };
      const res2 = createMockRes();
      await handleYoupiWebhook(req2, res2, { db: mockDb });

      const prodAfter2 = (await mockDb.collection("products").doc("PROD-MULTI").get()).data();
      assert.equal(prodAfter2.stockQuantity, 25); // Still 25! Not double-restored to 30!
    });

    test("Rejects insecure or localhost checkout URLs when NODE_ENV=production", async () => {
      await mockDb.collection("orders").doc("ORD-INSECURE-URL").set({
        orderNumber: "ORD-INSECURE-URL",
        customerId: "customer_123",
        totalPrice: 120.00,
        paymentMethod: "UPI",
        paymentStatus: "Pending"
      });

      const originalEnv = process.env.NODE_ENV;
      process.env.NODE_ENV = "production";

      const mockFetchInsecure = async () => ({
        ok: true,
        json: async () => ({
          paymentId: "pay_insecure_123",
          checkoutUrl: "http://localhost:7000/checkout/pay_insecure_123" // Insecure http://localhost
        })
      });

      const req = {
        method: "POST",
        headers: { authorization: "Bearer valid_cust_token" },
        body: { orderId: "ORD-INSECURE-URL" }
      };
      const res = createMockRes();

      await handleCreatePaymentSession(req, res, { db: mockDb, auth: mockAuth, fetchFn: mockFetchInsecure });

      process.env.NODE_ENV = originalEnv;

      assert.equal(res.statusCode, 502);
      assert.equal(res.body.error, "INSECURE_CHECKOUT_URL");
    });

    test("Gracefully handles YouPI Gateway API outage/network failure without corrupting order", async () => {
      await mockDb.collection("orders").doc("ORD-OUTAGE").set({
        orderNumber: "ORD-OUTAGE",
        customerId: "customer_123",
        totalPrice: 200.00,
        paymentMethod: "UPI",
        paymentStatus: "Pending"
      });

      const mockFetchNetworkFailure = async () => {
        throw new Error("ECONNREFUSED: Connection refused to YouPI Gateway API");
      };

      const req = {
        method: "POST",
        headers: { authorization: "Bearer valid_cust_token" },
        body: { orderId: "ORD-OUTAGE" }
      };
      const res = createMockRes();

      await handleCreatePaymentSession(req, res, { db: mockDb, auth: mockAuth, fetchFn: mockFetchNetworkFailure });

      assert.equal(res.statusCode, 500);
      assert.equal(res.body.error, "INTERNAL_ERROR");

      // Verify order is unharmed and remains in Pending state
      const order = (await mockDb.collection("orders").doc("ORD-OUTAGE").get()).data();
      assert.equal(order.paymentStatus, "Pending");
      assert.equal(order.youpiPaymentId, undefined);
    });
  });

  // ─── 10. PHASE 8: PAYMENT RETRY & SESSION LIFECYCLE ───────────────────────
  describe("10. Phase 8: Payment Retry & Session Lifecycle", () => {
    test("Reuses existing active valid YouPI session when available", async () => {
      await mockDb.collection("orders").doc("ORD-RETRY-ACTIVE").set({
        orderNumber: "ORD-RETRY-ACTIVE",
        customerId: "customer_123",
        totalPrice: 350.00,
        paymentMethod: "UPI",
        paymentStatus: "Pending",
        youpiPaymentId: "youpi_existing_session_001",
        youpiCheckoutUrl: "https://pay.example.com/checkout/youpi_existing_session_001",
        youpiSessionCreatedAt: new Date(Date.now() - 2 * 60 * 1000).toISOString() // 2 minutes ago (fresh)
      });

      let gatewayCalled = false;
      const mockFetch = async () => {
        gatewayCalled = true;
        return { ok: true, json: async () => ({}) };
      };

      const req = {
        method: "POST",
        headers: { authorization: "Bearer valid_cust_token" },
        body: { orderId: "ORD-RETRY-ACTIVE" }
      };
      const res = createMockRes();

      await handleCreatePaymentSession(req, res, { db: mockDb, auth: mockAuth, fetchFn: mockFetch });

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.paymentId, "youpi_existing_session_001");
      assert.equal(res.body.checkoutUrl, "https://pay.example.com/checkout/youpi_existing_session_001");
      assert.equal(gatewayCalled, false, "Did not create a duplicate session; reused existing valid session");
    });

    test("Requests fresh session when previous session is expired", async () => {
      await mockDb.collection("orders").doc("ORD-RETRY-EXPIRED").set({
        orderNumber: "ORD-RETRY-EXPIRED",
        customerId: "customer_123",
        totalPrice: 420.00,
        paymentMethod: "UPI",
        paymentStatus: "Pending",
        youpiPaymentId: "youpi_old_expired_session",
        youpiCheckoutUrl: "https://pay.example.com/checkout/youpi_old_expired_session",
        youpiSessionCreatedAt: new Date(Date.now() - 30 * 60 * 1000).toISOString() // 30 mins ago (expired)
      });

      let gatewayCalled = false;
      const mockFetch = async (url) => {
        assert.match(url, /\/api\/v1\/payments$/);
        gatewayCalled = true;
        return {
          ok: true,
          json: async () => ({
            paymentId: "youpi_fresh_session_002",
            checkoutUrl: "https://pay.example.com/checkout/youpi_fresh_session_002"
          })
        };
      };

      const req = {
        method: "POST",
        headers: { authorization: "Bearer valid_cust_token" },
        body: { orderId: "ORD-RETRY-EXPIRED" }
      };
      const res = createMockRes();

      await handleCreatePaymentSession(req, res, { db: mockDb, auth: mockAuth, fetchFn: mockFetch });

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.paymentId, "youpi_fresh_session_002");
      assert.equal(gatewayCalled, true, "Created a fresh session because the previous one was expired");

      const updated = (await mockDb.collection("orders").doc("ORD-RETRY-EXPIRED").get()).data();
      assert.equal(updated.youpiPaymentId, "youpi_fresh_session_002");
    });

    test("Handles duplicate retry taps concurrently without double session creation", async () => {
      await mockDb.collection("orders").doc("ORD-CONCURRENT").set({
        orderNumber: "ORD-CONCURRENT",
        customerId: "customer_123",
        totalPrice: 199.00,
        paymentMethod: "UPI",
        paymentStatus: "Pending"
      });

      let fetchCount = 0;
      const mockFetch = async () => {
        fetchCount++;
        return {
          ok: true,
          json: async () => ({
            paymentId: `youpi_session_${fetchCount}`,
            checkoutUrl: `https://pay.example.com/checkout/youpi_session_${fetchCount}`
          })
        };
      };

      const req1 = { method: "POST", headers: { authorization: "Bearer valid_cust_token" }, body: { orderId: "ORD-CONCURRENT" } };
      const res1 = createMockRes();
      await handleCreatePaymentSession(req1, res1, { db: mockDb, auth: mockAuth, fetchFn: mockFetch });

      // Immediate second tap:
      const req2 = { method: "POST", headers: { authorization: "Bearer valid_cust_token" }, body: { orderId: "ORD-CONCURRENT" } };
      const res2 = createMockRes();
      await handleCreatePaymentSession(req2, res2, { db: mockDb, auth: mockAuth, fetchFn: mockFetch });

      assert.equal(res1.statusCode, 200);
      assert.equal(res2.statusCode, 200);
      assert.equal(res1.body.paymentId, res2.body.paymentId, "Both taps resolve to the same payment session");
      assert.equal(fetchCount, 1, "Only 1 session created at gateway");
    });
  });

  // ─── 11. PHASE 8: SAFE CONVERSION TO COD ──────────────────────────────────
  describe("11. Phase 8: Safe Conversion to COD", () => {
    test("Successfully converts eligible pending UPI order to COD", async () => {
      await mockDb.collection("products").doc("PROD-COD-TEST").set({
        stockQuantity: 40
      });
      await mockDb.collection("orders").doc("ORD-CONVERT-1").set({
        orderNumber: "ORD-CONVERT-1",
        customerId: "customer_123",
        totalPrice: 280.00,
        paymentMethod: "UPI",
        paymentStatus: "Pending",
        status: "Pending",
        items: [{ productId: "PROD-COD-TEST", quantity: 2 }]
      });

      const req = {
        method: "POST",
        headers: { authorization: "Bearer valid_cust_token" },
        body: { orderId: "ORD-CONVERT-1" }
      };
      const res = createMockRes();

      await handleConvertOrderToCod(req, res, { db: mockDb, auth: mockAuth });

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.paymentMethod, "COD");

      const order = (await mockDb.collection("orders").doc("ORD-CONVERT-1").get()).data();
      assert.equal(order.paymentMethod, "COD");
      assert.equal(order.paymentStatus, "Pending");

      // Verify product stock is untouched (no double deduction, no restoration)
      const prod = (await mockDb.collection("products").doc("PROD-COD-TEST").get()).data();
      assert.equal(prod.stockQuantity, 40);
    });

    test("Rejects conversion to COD if order is already Paid", async () => {
      await mockDb.collection("orders").doc("ORD-PAID-ALREADY").set({
        customerId: "customer_123",
        paymentMethod: "UPI",
        paymentStatus: "Paid",
        status: "Accepted"
      });

      const req = {
        method: "POST",
        headers: { authorization: "Bearer valid_cust_token" },
        body: { orderId: "ORD-PAID-ALREADY" }
      };
      const res = createMockRes();

      await handleConvertOrderToCod(req, res, { db: mockDb, auth: mockAuth });

      assert.equal(res.statusCode, 400);
      assert.equal(res.body.error, "ALREADY_PAID");
    });

    test("Rejects conversion to COD if order is Cancelled", async () => {
      await mockDb.collection("orders").doc("ORD-CANCELLED-ALREADY").set({
        customerId: "customer_123",
        paymentMethod: "UPI",
        paymentStatus: "Failed",
        status: "Cancelled"
      });

      const req = {
        method: "POST",
        headers: { authorization: "Bearer valid_cust_token" },
        body: { orderId: "ORD-CANCELLED-ALREADY" }
      };
      const res = createMockRes();

      await handleConvertOrderToCod(req, res, { db: mockDb, auth: mockAuth });

      assert.equal(res.statusCode, 400);
      assert.equal(res.body.error, "ORDER_TERMINAL");
    });

    test("Rejects conversion to COD if customer does not own order", async () => {
      await mockDb.collection("orders").doc("ORD-HIJACK-COD").set({
        customerId: "customer_123",
        paymentMethod: "UPI",
        paymentStatus: "Pending",
        status: "Pending"
      });

      const req = {
        method: "POST",
        headers: { authorization: "Bearer other_cust_token" }, // Not owner
        body: { orderId: "ORD-HIJACK-COD" }
      };
      const res = createMockRes();

      await handleConvertOrderToCod(req, res, { db: mockDb, auth: mockAuth });

      assert.equal(res.statusCode, 403);
      assert.equal(res.body.error, "FORBIDDEN");
    });

    test("Idempotent repeated conversion to COD succeeds without corruption", async () => {
      await mockDb.collection("orders").doc("ORD-REPEAT-COD").set({
        customerId: "customer_123",
        paymentMethod: "COD",
        paymentStatus: "Pending",
        status: "Pending"
      });

      const req = {
        method: "POST",
        headers: { authorization: "Bearer valid_cust_token" },
        body: { orderId: "ORD-REPEAT-COD" }
      };
      const res = createMockRes();

      await handleConvertOrderToCod(req, res, { db: mockDb, auth: mockAuth });

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.message, "Order is already Cash on Delivery.");
    });
  });

  // ─── 12. PHASE 8: UNPAID ORDER CLEANUP SCHEDULED JOB ─────────────────────
  describe("12. Phase 8: Unpaid Order Cleanup Scheduled Job", () => {
    test("Skips orders younger than cutoff threshold", async () => {
      await mockDb.collection("orders").doc("ORD-RECENT").set({
        orderNumber: "ORD-RECENT",
        paymentMethod: "UPI",
        paymentStatus: "Pending",
        status: "Pending",
        createdAt: new Date(Date.now() - 5 * 60 * 1000).toISOString() // 5 minutes old
      });

      const results = await handleCleanupUnpaidOrders({
        db: mockDb,
        olderThanMinutes: 30,
        fetchFn: async () => ({ ok: true, json: async () => ({}) })
      });

      assert.equal(results.examined, 1);
      assert.equal(results.cancelled, 0);
      assert.equal(results.reconciled, 0);

      const order = (await mockDb.collection("orders").doc("ORD-RECENT").get()).data();
      assert.equal(order.status, "Pending"); // Still pending
    });

    test("Cancels and restores inventory for old orders without a gateway session", async () => {
      await mockDb.collection("products").doc("PROD-CLEANUP-1").set({
        stockQuantity: 10
      });
      await mockDb.collection("orders").doc("ORD-NO-SESSION").set({
        orderNumber: "ORD-NO-SESSION",
        paymentMethod: "UPI",
        paymentStatus: "Pending",
        status: "Pending",
        createdAt: new Date(Date.now() - 45 * 60 * 1000).toISOString(), // 45 minutes old
        items: [{ productId: "PROD-CLEANUP-1", quantity: 3 }]
      });

      const results = await handleCleanupUnpaidOrders({
        db: mockDb,
        olderThanMinutes: 30,
        fetchFn: async () => ({ ok: true, json: async () => ({}) })
      });

      assert.equal(results.cancelled, 1);

      const order = (await mockDb.collection("orders").doc("ORD-NO-SESSION").get()).data();
      assert.equal(order.status, "Cancelled");
      assert.equal(order.paymentStatus, "Expired");
      assert.equal(order.inventoryRestored, true);

      // Verify stock restored exactly once (10 + 3 = 13)
      const prod = (await mockDb.collection("products").doc("PROD-CLEANUP-1").get()).data();
      assert.equal(prod.stockQuantity, 13);
    });

    test("When gateway session is SUCCESS, marks Paid instead of cancelling (Late payment / delayed webhook)", async () => {
      await mockDb.collection("products").doc("PROD-CLEANUP-2").set({
        stockQuantity: 50
      });
      await mockDb.collection("orders").doc("ORD-GATEWAY-SUCCESS").set({
        orderNumber: "ORD-GATEWAY-SUCCESS",
        paymentMethod: "UPI",
        paymentStatus: "Pending",
        status: "Pending",
        youpiPaymentId: "pay_gw_success_123",
        createdAt: new Date(Date.now() - 40 * 60 * 1000).toISOString(),
        items: [{ productId: "PROD-CLEANUP-2", quantity: 5 }]
      });

      const mockFetchGateway = async (url) => {
        assert.match(url, /\/api\/v1\/payments\/pay_gw_success_123$/);
        return {
          ok: true,
          json: async () => ({
            status: "SUCCESS",
            paymentId: "pay_gw_success_123"
          })
        };
      };

      const results = await handleCleanupUnpaidOrders({
        db: mockDb,
        olderThanMinutes: 30,
        fetchFn: mockFetchGateway
      });

      assert.equal(results.reconciled, 1);
      assert.equal(results.cancelled, 0);

      const order = (await mockDb.collection("orders").doc("ORD-GATEWAY-SUCCESS").get()).data();
      assert.equal(order.paymentStatus, "Paid");
      assert.equal(order.status, "Accepted");

      // Verify stock was NOT restored (remains 50)
      const prod = (await mockDb.collection("products").doc("PROD-CLEANUP-2").get()).data();
      assert.equal(prod.stockQuantity, 50);
    });

    test("When gateway session is EXPIRED, cancels order and restores inventory", async () => {
      await mockDb.collection("products").doc("PROD-CLEANUP-3").set({
        stockQuantity: 20
      });
      await mockDb.collection("orders").doc("ORD-GATEWAY-EXPIRED").set({
        orderNumber: "ORD-GATEWAY-EXPIRED",
        paymentMethod: "UPI",
        paymentStatus: "Pending",
        status: "Pending",
        youpiPaymentId: "pay_gw_expired_456",
        createdAt: new Date(Date.now() - 35 * 60 * 1000).toISOString(),
        items: [{ productId: "PROD-CLEANUP-3", quantity: 4 }]
      });

      const mockFetchGateway = async (url) => {
        assert.match(url, /\/api\/v1\/payments\/pay_gw_expired_456$/);
        return {
          ok: true,
          json: async () => ({
            status: "EXPIRED",
            paymentId: "pay_gw_expired_456"
          })
        };
      };

      const results = await handleCleanupUnpaidOrders({
        db: mockDb,
        olderThanMinutes: 30,
        fetchFn: mockFetchGateway
      });

      assert.equal(results.cancelled, 1);

      const order = (await mockDb.collection("orders").doc("ORD-GATEWAY-EXPIRED").get()).data();
      assert.equal(order.status, "Cancelled");
      assert.equal(order.paymentStatus, "Expired");
      assert.equal(order.inventoryRestored, true);

      // Verify stock restored: 20 + 4 = 24
      const prod = (await mockDb.collection("products").doc("PROD-CLEANUP-3").get()).data();
      assert.equal(prod.stockQuantity, 24);
    });

    test("When gateway API is unreachable, does NOT blindly cancel; flags for reconciliation", async () => {
      await mockDb.collection("products").doc("PROD-CLEANUP-4").set({
        stockQuantity: 15
      });
      await mockDb.collection("orders").doc("ORD-GATEWAY-UNREACHABLE").set({
        orderNumber: "ORD-GATEWAY-UNREACHABLE",
        paymentMethod: "UPI",
        paymentStatus: "Pending",
        status: "Pending",
        youpiPaymentId: "pay_gw_down_789",
        createdAt: new Date(Date.now() - 40 * 60 * 1000).toISOString(),
        items: [{ productId: "PROD-CLEANUP-4", quantity: 2 }]
      });

      const mockFetchNetworkErr = async () => {
        throw new Error("ETIMEDOUT: Gateway unreachable");
      };

      const results = await handleCleanupUnpaidOrders({
        db: mockDb,
        olderThanMinutes: 30,
        fetchFn: mockFetchNetworkErr
      });

      assert.equal(results.flagged, 1);
      assert.equal(results.cancelled, 0);

      const order = (await mockDb.collection("orders").doc("ORD-GATEWAY-UNREACHABLE").get()).data();
      assert.equal(order.reconciliationRequired, true);
      assert.equal(order.status, "Pending"); // NOT cancelled!
      assert.equal(order.inventoryRestored, undefined); // Stock NOT restored blindly!

      // Stock stays intact
      const prod = (await mockDb.collection("products").doc("PROD-CLEANUP-4").get()).data();
      assert.equal(prod.stockQuantity, 15);
    });

    test("Guarantees inventory restoration exactly once even if cleanup runs multiple times", async () => {
      await mockDb.collection("products").doc("PROD-CLEANUP-5").set({
        stockQuantity: 8
      });
      await mockDb.collection("orders").doc("ORD-IDEMPOTENT-CLEANUP").set({
        orderNumber: "ORD-IDEMPOTENT-CLEANUP",
        paymentMethod: "UPI",
        paymentStatus: "Pending",
        status: "Pending",
        createdAt: new Date(Date.now() - 50 * 60 * 1000).toISOString(),
        items: [{ productId: "PROD-CLEANUP-5", quantity: 2 }]
      });

      // Pass 1:
      await handleCleanupUnpaidOrders({ db: mockDb, olderThanMinutes: 30 });
      const prod1 = (await mockDb.collection("products").doc("PROD-CLEANUP-5").get()).data();
      assert.equal(prod1.stockQuantity, 10); // 8 + 2 = 10

      // Pass 2:
      await handleCleanupUnpaidOrders({ db: mockDb, olderThanMinutes: 30 });
      const prod2 = (await mockDb.collection("products").doc("PROD-CLEANUP-5").get()).data();
      assert.equal(prod2.stockQuantity, 10); // Still 10! Not double restored to 12!
    });
  });
});

