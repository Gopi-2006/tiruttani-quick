const { test, describe, before, after } = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {
  handleCreatePaymentSession,
  handleYoupiWebhook
} = require("../youpi_payment");

// In-Memory Mock Firestore matching the production Firestore structure with subcollections
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

describe("Live YouPI-PG Local Gateway E2E Flow Validation", () => {
  const GATEWAY_URL = "http://localhost:6100";
  const CHECKOUT_URL = "http://localhost:7000";
  const WEBHOOK_SECRET = process.env.YOUPI_WEBHOOK_SECRET || "test_webhook_secret_demo";
  const MERCHANT_API_KEY = process.env.YOUPI_MERCHANT_API_KEY || "ypg_live_ff10005ab2def7d43405c2e343a370328ccd8f21dc11f084";

  let liveGatewayOnline = false;
  let apiInstance = null;
  let portalInstance = null;
  let startedOwnApi = false;
  let startedOwnPortal = false;

  before(async () => {
    process.env.YOUPI_API_BASE_URL = GATEWAY_URL;
    process.env.YOUPI_WEBHOOK_SECRET = WEBHOOK_SECRET;
    process.env.YOUPI_MERCHANT_API_KEY = MERCHANT_API_KEY;
    process.env.USE_SQLITE_FALLBACK = "true";
    process.env.NODE_ENV = "development";
    process.env.BASE_CHECKOUT_URL = "http://localhost:7000/checkout";

    // 1. Check if Payment API is already running
    try {
      const res = await fetch(`${GATEWAY_URL}/health`, { signal: AbortSignal.timeout(1000) });
      if (res.ok) liveGatewayOnline = true;
    } catch {
      liveGatewayOnline = false;
    }

    if (!liveGatewayOnline) {
      try {
        const { startServer } = await import("../../paymant/YouPI-PG-main/apps/payment-api/src/index.js");
        apiInstance = await startServer(6100);
        startedOwnApi = true;
        for (let i = 0; i < 25; i++) {
          try {
            const hRes = await fetch(`${GATEWAY_URL}/health`, { signal: AbortSignal.timeout(500) });
            if (hRes.ok) {
              liveGatewayOnline = true;
              break;
            }
          } catch {}
          await new Promise(r => setTimeout(r, 200));
        }
      } catch (err) {
        console.error("Failed to auto-start Payment API for E2E tests:", err);
      }
    }

    // 2. Check if Checkout Portal is already running
    let portalOnline = false;
    try {
      const pRes = await fetch(`${CHECKOUT_URL}/health`, { signal: AbortSignal.timeout(1000) });
      if (pRes.ok) portalOnline = true;
    } catch {
      portalOnline = false;
    }

    if (!portalOnline) {
      try {
        const { startCheckoutServer } = await import("../../paymant/YouPI-PG-main/apps/checkout-portal/src/index.js");
        portalInstance = await startCheckoutServer(7000);
        startedOwnPortal = true;
        for (let i = 0; i < 25; i++) {
          try {
            const hRes = await fetch(`${CHECKOUT_URL}/health`, { signal: AbortSignal.timeout(500) });
            if (hRes.ok) break;
          } catch {}
          await new Promise(r => setTimeout(r, 200));
        }
      } catch (err) {
        console.error("Failed to auto-start Checkout Portal for E2E tests:", err);
      }
    }
  });

  after(async () => {
    if (startedOwnApi && apiInstance && typeof apiInstance.close === "function") {
      try {
        await apiInstance.close();
      } catch (e) {
        console.error("Error closing test Payment API:", e);
      }
    }
    if (startedOwnPortal && portalInstance && typeof portalInstance.close === "function") {
      try {
        await portalInstance.close();
      } catch (e) {
        console.error("Error closing test Checkout Portal:", e);
      }
    }
  });

  test("1. Gateway Health: Payment Core API responds on port 6100", async () => {
    assert.equal(liveGatewayOnline, true, "Payment API must be running on port 6100");
    const res = await fetch(`${GATEWAY_URL}/health`);
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.status, "UP");
    assert.equal(data.service, "payment-api");
  });

  test("2. Checkout Portal Health: Portal responds on port 7000", async () => {
    const res = await fetch(`${CHECKOUT_URL}/health`);
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.status, "UP");
    assert.equal(data.service, "checkout-portal");
  });

  test("3. Live Payment Session Creation via real running YouPI API", async () => {
    const mockDb = new MockFirestore();
    const mockAuth = {
      verifyIdToken: async (token) => {
        if (token === "valid_cust_token") {
          return { uid: "live_test_cust_001", email: "customer@test.local" };
        }
        throw new Error("Invalid token");
      }
    };

    // Seed synthetic pending order
    const syntheticOrderId = `LIVE-E2E-${Date.now()}`;
    await mockDb.collection("orders").doc(syntheticOrderId).set({
      orderNumber: syntheticOrderId,
      customerId: "live_test_cust_001",
      totalPrice: 199.00,
      paymentMethod: "UPI",
      paymentStatus: "Pending"
    });

    const req = {
      method: "POST",
      headers: { authorization: "Bearer valid_cust_token" },
      body: { orderId: syntheticOrderId }
    };
    const res = createMockRes();

    // Call handleCreatePaymentSession which performs a real fetch to http://localhost:6100/api/v1/payments
    await handleCreatePaymentSession(req, res, { db: mockDb, auth: mockAuth, fetchFn: globalThis.fetch });

    assert.equal(res.statusCode, 200);
    assert.equal(res.body.success, true);
    assert.ok(res.body.paymentId, "Must return a valid paymentId");
    assert.ok(res.body.checkoutUrl.startsWith("http://localhost:7000/checkout/"), "Checkout URL must point to checkout portal");
    assert.equal(res.body.amount, "199.00");
    assert.equal(res.body.currency, "INR");

    // Verify Firestore order was linked
    const orderSnap = await mockDb.collection("orders").doc(syntheticOrderId).get();
    const orderData = orderSnap.data();
    assert.equal(orderData.youpiPaymentId, res.body.paymentId);
    assert.equal(orderData.youpiCheckoutUrl, res.body.checkoutUrl);

    // Verify the checkout portal actually serves the checkout page for this payment ID
    const portalRes = await fetch(res.body.checkoutUrl);
    assert.equal(portalRes.status, 200, "Checkout portal must render the checkout page (200)");
    const portalHtml = await portalRes.text();
    assert.ok(portalHtml.includes("YOUPI") || portalHtml.includes("checkout"), "Portal HTML must render payment interface");
  });

  test("4. Webhook Lifecycle: Valid signed SUCCESS marks order Paid", async () => {
    const mockDb = new MockFirestore();
    const orderId = `WH-SUCCESS-${Date.now()}`;
    await mockDb.collection("orders").doc(orderId).set({
      orderNumber: orderId,
      customerId: "cust_wh_1",
      totalPrice: 299.00,
      paymentMethod: "UPI",
      paymentStatus: "Pending",
      youpiPaymentId: "pay_live_test_1"
    });

    const payload = {
      event: "SUCCESS",
      paymentId: "pay_live_test_1",
      orderId: orderId,
      utr: "123456789012",
      amount: "299.00",
      amountPaise: 29900,
      currency: "INR"
    };

    const rawBody = JSON.stringify(payload);
    const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");
    const deliveryId = `deliv-success-${Date.now()}`;

    const req = {
      method: "POST",
      headers: {
        "x-gateway-signature": `sha256=${signature}`,
        "x-gateway-timestamp": Date.now().toString(),
        "x-gateway-delivery-id": deliveryId,
        "x-gateway-event": "SUCCESS"
      },
      rawBody,
      body: payload
    };
    const res = createMockRes();

    await handleYoupiWebhook(req, res, { db: mockDb });

    assert.equal(res.statusCode, 200);
    assert.equal(res.body.success, true);

    const updated = (await mockDb.collection("orders").doc(orderId).get()).data();
    assert.equal(updated.paymentStatus, "Paid");
    assert.equal(updated.paymentUtr, "123456789012");
  });

  test("5. Webhook Security: Invalid HMAC signature is rejected (401)", async () => {
    const mockDb = new MockFirestore();
    const payload = { event: "SUCCESS", paymentId: "pay_bad", orderId: "ORD-1", amount: "100.00" };
    const rawBody = JSON.stringify(payload);

    const req = {
      method: "POST",
      headers: {
        "x-gateway-signature": "sha256=invalid_tampered_signature_hex",
        "x-gateway-timestamp": Date.now().toString(),
        "x-gateway-delivery-id": "deliv-bad-sig",
        "x-gateway-event": "SUCCESS"
      },
      rawBody,
      body: payload
    };
    const res = createMockRes();

    await handleYoupiWebhook(req, res, { db: mockDb });
    assert.equal(res.statusCode, 401);
    assert.equal(res.body.error, "INVALID_SIGNATURE");
  });

  test("6. Webhook Security: Expired timestamp (>5 min) is rejected (401)", async () => {
    const mockDb = new MockFirestore();
    const payload = { event: "SUCCESS", paymentId: "pay_replay", orderId: "ORD-1", amount: "100.00" };
    const rawBody = JSON.stringify(payload);
    const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

    const req = {
      method: "POST",
      headers: {
        "x-gateway-signature": `sha256=${signature}`,
        "x-gateway-timestamp": (Date.now() - 10 * 60 * 1000).toString(), // 10 minutes ago
        "x-gateway-delivery-id": "deliv-stale",
        "x-gateway-event": "SUCCESS"
      },
      rawBody,
      body: payload
    };
    const res = createMockRes();

    await handleYoupiWebhook(req, res, { db: mockDb });
    assert.equal(res.statusCode, 401);
    assert.equal(res.body.error, "REPLAY_WINDOW_EXPIRED");
  });

  test("7. Webhook Security: Duplicate delivery ID is acknowledged idempotently without double-processing", async () => {
    const mockDb = new MockFirestore();
    const deliveryId = "deliv-duplicate-idempotency-check";
    // Mark delivery as already processed
    await mockDb.collection("processed_webhooks").doc(deliveryId).set({
      processedAt: new Date().toISOString(),
      event: "SUCCESS"
    });

    const payload = { event: "SUCCESS", paymentId: "pay_dup", orderId: "ORD-DUP", amount: "100.00" };
    const rawBody = JSON.stringify(payload);
    const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

    const req = {
      method: "POST",
      headers: {
        "x-gateway-signature": `sha256=${signature}`,
        "x-gateway-timestamp": Date.now().toString(),
        "x-gateway-delivery-id": deliveryId,
        "x-gateway-event": "SUCCESS"
      },
      rawBody,
      body: payload
    };
    const res = createMockRes();

    await handleYoupiWebhook(req, res, { db: mockDb });
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.message, "ALREADY_PROCESSED");
  });

  test("8. Webhook Security: Late SUCCESS after CANCELLED is flagged without reviving order", async () => {
    const mockDb = new MockFirestore();
    const orderId = `ORD-CANCELLED-${Date.now()}`;
    await mockDb.collection("orders").doc(orderId).set({
      orderNumber: orderId,
      customerId: "cust_cancelled_1",
      totalPrice: 150.00,
      paymentMethod: "UPI",
      paymentStatus: "Cancelled",
      status: "CANCELLED",
      youpiPaymentId: "pay_late_success"
    });

    const payload = {
      event: "SUCCESS",
      paymentId: "pay_late_success",
      orderId: orderId,
      utr: "999888777666",
      amount: "150.00",
      amountPaise: 15000,
      currency: "INR"
    };

    const rawBody = JSON.stringify(payload);
    const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

    const req = {
      method: "POST",
      headers: {
        "x-gateway-signature": `sha256=${signature}`,
        "x-gateway-timestamp": Date.now().toString(),
        "x-gateway-delivery-id": `deliv-late-${Date.now()}`,
        "x-gateway-event": "SUCCESS"
      },
      rawBody,
      body: payload
    };
    const res = createMockRes();

    await handleYoupiWebhook(req, res, { db: mockDb });

    assert.equal(res.statusCode, 200);

    // Must NOT revive to Paid
    const order = (await mockDb.collection("orders").doc(orderId).get()).data();
    assert.equal(order.status, "CANCELLED");
    assert.equal(order.paymentStatus, "Cancelled");
    assert.equal(order.latePaymentFlag, true);
    assert.equal(order.latePaymentUtr, "999888777666");
  });

  test("9. Webhook Lifecycle: CANCELLED event transitions order to cancelled and restores inventory once", async () => {
    const mockDb = new MockFirestore();
    const orderId = `ORD-EXPIRE-${Date.now()}`;
    await mockDb.collection("orders").doc(orderId).set({
      orderNumber: orderId,
      customerId: "cust_exp_1",
      totalPrice: 200.00,
      paymentMethod: "UPI",
      paymentStatus: "Pending",
      status: "ORDER_PLACED",
      youpiPaymentId: "pay_expire_1"
    });

    // Seed order_items subcollection
    await mockDb.collection("orders").doc(orderId).collection("order_items").doc("item1").set({
      productId: "PROD-A",
      quantity: 2
    });
    await mockDb.collection("orders").doc(orderId).collection("order_items").doc("item2").set({
      productId: "PROD-B",
      quantity: 1
    });

    // Seed products with initial stock
    await mockDb.collection("products").doc("PROD-A").set({ stockQuantity: 8 });
    await mockDb.collection("products").doc("PROD-B").set({ stockQuantity: 4 });

    const payload = {
      event: "EXPIRED",
      paymentId: "pay_expire_1",
      orderId: orderId,
      amount: "200.00",
      amountPaise: 20000,
      currency: "INR"
    };

    const rawBody = JSON.stringify(payload);
    const signature = crypto.createHmac("sha256", WEBHOOK_SECRET).update(rawBody).digest("hex");

    const req = {
      method: "POST",
      headers: {
        "x-gateway-signature": `sha256=${signature}`,
        "x-gateway-timestamp": Date.now().toString(),
        "x-gateway-delivery-id": `deliv-exp-${Date.now()}`,
        "x-gateway-event": "EXPIRED"
      },
      rawBody,
      body: payload
    };
    const res = createMockRes();

    await handleYoupiWebhook(req, res, { db: mockDb });

    assert.equal(res.statusCode, 200);

    const order = (await mockDb.collection("orders").doc(orderId).get()).data();
    assert.equal(order.status, "CANCELLED");
    assert.equal(order.paymentStatus, "Expired");
    assert.equal(order.inventoryRestored, true);

    const prodA = (await mockDb.collection("products").doc("PROD-A").get()).data();
    const prodB = (await mockDb.collection("products").doc("PROD-B").get()).data();
    assert.equal(prodA.stockQuantity, 10, "Stock of PROD-A must be restored (8 + 2)");
    assert.equal(prodB.stockQuantity, 5, "Stock of PROD-B must be restored (4 + 1)");
  });

  test("10. Gateway Outage Resilience: Safe failure without corrupting order", async () => {
    const mockDb = new MockFirestore();
    const mockAuth = {
      verifyIdToken: async () => ({ uid: "cust_outage", email: "cust@outage.local" })
    };

    const orderId = `ORD-OUTAGE-${Date.now()}`;
    await mockDb.collection("orders").doc(orderId).set({
      customerId: "cust_outage",
      totalPrice: 100.00,
      paymentMethod: "UPI",
      paymentStatus: "Pending"
    });

    // Simulate gateway outage with rejecting fetch
    const failingFetch = async () => { throw new Error("connect ECONNREFUSED 127.0.0.1:9999"); };

    const req = {
      method: "POST",
      headers: { authorization: "Bearer token" },
      body: { orderId }
    };
    const res = createMockRes();

    await handleCreatePaymentSession(req, res, { db: mockDb, auth: mockAuth, fetchFn: failingFetch });

    assert.equal(res.statusCode, 500);
    assert.equal(res.body.error, "INTERNAL_ERROR");

    // Order must remain untouched in Pending state
    const order = (await mockDb.collection("orders").doc(orderId).get()).data();
    assert.equal(order.paymentStatus, "Pending");
    assert.equal(order.youpiPaymentId, undefined);
  });
});
