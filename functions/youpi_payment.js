const admin = require("firebase-admin");
const crypto = require("node:crypto");

/**
 * Configuration options for YouPI-PG integration.
 * In production, these are provided via Firebase Environment Configuration or Cloud Secret Manager.
 * In local development, they fall back to the running local YouPI-PG dev server.
 */
function getYoupiConfig() {
  return {
    apiBaseUrl: process.env.YOUPI_API_BASE_URL || "http://localhost:6100",
    merchantApiKey: process.env.YOUPI_MERCHANT_API_KEY || "ypg_live_ff10005ab2def7d43405c2e343a370328ccd8f21dc11f084",
    webhookSecret: process.env.YOUPI_WEBHOOK_SECRET || "test_webhook_secret_demo",
    replayWindowMs: Number(process.env.YOUPI_REPLAY_WINDOW_MS) || 5 * 60 * 1000 // 5 minutes
  };
}

/**
 * Validates that the request has a valid Firebase Auth bearer token.
 * Returns the decoded token payload { uid, email, ... } or null.
 */
async function authenticateFirebaseUser(req, authInstance = admin.auth()) {
  const authHeader = req.headers.authorization || req.headers.Authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return null;
  }
  const token = authHeader.split(" ")[1];
  if (!token) return null;

  try {
    const decoded = await authInstance.verifyIdToken(token);
    return decoded;
  } catch (err) {
    return null;
  }
}

/**
 * Secure Server-Side Endpoint: Creates a YouPI-PG payment session for a pending order.
 * - Authenticates the customer via Firebase Auth.
 * - Validates order ownership and pending state.
 * - Validates amount and currency.
 * - Calls YouPI-PG Core API with merchant credentials (never exposed to client).
 * - Stores YouPI session details on the Firestore order document.
 * - Returns only the checkout URL and safe details to client.
 */
async function handleCreatePaymentSession(req, res, { db = admin.firestore(), auth = admin.auth(), fetchFn = globalThis.fetch } = {}) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  // 1. Authenticate customer
  const user = await authenticateFirebaseUser(req, auth);
  if (!user || !user.uid) {
    return res.status(401).json({ error: "UNAUTHORIZED", message: "Valid Firebase authentication token required." });
  }

  const { orderId, idempotencyKey } = req.body || {};
  if (!orderId || typeof orderId !== "string") {
    return res.status(400).json({ error: "BAD_REQUEST", message: "orderId is required." });
  }

  // 2. Fetch and validate Firestore order
  const orderRef = db.collection("orders").doc(orderId);
  const orderSnap = await orderRef.get();

  if (!orderSnap.exists) {
    return res.status(404).json({ error: "NOT_FOUND", message: `Order #${orderId} does not exist.` });
  }

  const orderData = orderSnap.data();

  // Validate ownership
  if (orderData.customerId !== user.uid) {
    return res.status(403).json({ error: "FORBIDDEN", message: "You are not authorized to create payment for this order." });
  }

  // Validate state
  if (orderData.paymentStatus === "Paid") {
    return res.status(400).json({ error: "ALREADY_PAID", message: "This order has already been paid." });
  }

  if (orderData.paymentMethod !== "UPI" && orderData.paymentMethod !== "Online") {
    return res.status(400).json({ error: "INVALID_METHOD", message: `Order payment method is ${orderData.paymentMethod}, not UPI.` });
  }

  const totalPrice = Number(orderData.totalPrice);
  if (!Number.isFinite(totalPrice) || totalPrice <= 0) {
    return res.status(400).json({ error: "INVALID_AMOUNT", message: "Order total price must be greater than zero." });
  }

  // 2b. Check if an active, unexpired YouPI session already exists (Session Reuse / Duplicate tap prevention)
  let sessionTime = 0;
  if (typeof orderData.youpiSessionCreatedAt === "string") {
    sessionTime = new Date(orderData.youpiSessionCreatedAt).getTime();
  } else if (orderData.youpiCreatedAt) {
    if (typeof orderData.youpiCreatedAt.toDate === "function") {
      sessionTime = orderData.youpiCreatedAt.toDate().getTime();
    } else if (typeof orderData.youpiCreatedAt === "string") {
      sessionTime = new Date(orderData.youpiCreatedAt).getTime();
    } else if (typeof orderData.youpiCreatedAt._seconds === "number") {
      sessionTime = orderData.youpiCreatedAt._seconds * 1000;
    } else {
      // Sentinel object (e.g. FieldValue.serverTimestamp())
      sessionTime = Date.now();
    }
  }

  if (orderData.youpiPaymentId && orderData.youpiCheckoutUrl && sessionTime > 0) {
    const sessionAgeMs = Date.now() - sessionTime;
    const SESSION_EXPIRY_MS = 15 * 60 * 1000; // 15 minutes
    const isMatchingIdempotency = idempotencyKey && orderData.idempotencyKey === idempotencyKey;

    if ((sessionAgeMs < SESSION_EXPIRY_MS || isMatchingIdempotency) && orderData.paymentStatus === "Pending") {
      return res.status(200).json({
        success: true,
        reused: true,
        paymentId: orderData.youpiPaymentId,
        checkoutUrl: orderData.youpiCheckoutUrl,
        orderId: orderId,
        amount: totalPrice.toFixed(2),
        currency: "INR"
      });
    }
  }

  // 3. Dispatch session creation to YouPI-PG
  const config = getYoupiConfig();
  const youpiPayload = {
    orderId: orderData.orderNumber || orderId,
    amount: totalPrice.toFixed(2),
    currency: "INR",
    method: "UPI",
    autoActivate: true,
    metadata: {
      firestoreOrderId: orderId,
      customerId: user.uid
    }
  };

  try {
    const youpiRes = await fetchFn(`${config.apiBaseUrl}/api/v1/payments`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${config.merchantApiKey}`
      },
      body: JSON.stringify(youpiPayload)
    });

    const youpiData = await youpiRes.json();

    if (!youpiRes.ok || !youpiData.paymentId) {
      return res.status(502).json({
        error: "GATEWAY_ERROR",
        message: youpiData.error || "Failed to create payment session with YouPI gateway."
      });
    }

    // 4. Validate checkoutUrl in production
    const isProduction = process.env.NODE_ENV === "production";
    if (isProduction) {
      if (!youpiData.checkoutUrl.startsWith("https://") || youpiData.checkoutUrl.includes("localhost") || youpiData.checkoutUrl.includes("127.0.0.1")) {
        return res.status(502).json({
          error: "INSECURE_CHECKOUT_URL",
          message: "Production environment requires a secure HTTPS checkout URL. Localhost is not permitted."
        });
      }
    }

    // 5. Record YouPI payment session details against the Firestore order
    const sessionIsoString = new Date().toISOString();
    await orderRef.update({
      youpiPaymentId: youpiData.paymentId,
      youpiCheckoutUrl: youpiData.checkoutUrl,
      idempotencyKey: idempotencyKey || null,
      youpiSessionCreatedAt: sessionIsoString,
      youpiCreatedAt: admin.firestore?.FieldValue?.serverTimestamp
        ? admin.firestore.FieldValue.serverTimestamp()
        : sessionIsoString
    });

    // 6. Return safe payment details to client
    return res.status(200).json({
      success: true,
      paymentId: youpiData.paymentId,
      checkoutUrl: youpiData.checkoutUrl,
      orderId: orderId,
      amount: totalPrice.toFixed(2),
      currency: "INR"
    });
  } catch (err) {
    return res.status(500).json({ error: "INTERNAL_ERROR", message: err.message });
  }
}

/**
 * Secure Server-Side Webhook: Ingests signed payment notifications from YouPI-PG.
 * - Authenticates signature using HMAC-SHA256 (timing-safe).
 * - Enforces timestamp freshness (anti-replay window).
 * - Ensures idempotent execution via delivery ID tracking.
 * - Verifies order existence, matching amounts, and currencies.
 * - Atomically transitions paymentStatus in Firestore.
 * - Safeguards inventory: does NOT duplicate inventory deductions on success,
 *   and restores inventory on expiration or cancellation.
 */
async function handleYoupiWebhook(req, res, { db = admin.firestore() } = {}) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  const config = getYoupiConfig();

  // 1. Extract required headers
  const signatureHeader = req.headers["x-gateway-signature"] || req.headers["X-Gateway-Signature"];
  const timestampHeader = req.headers["x-gateway-timestamp"] || req.headers["X-Gateway-Timestamp"];
  const deliveryId = req.headers["x-gateway-delivery-id"] || req.headers["X-Gateway-Delivery-Id"];
  const eventHeader = req.headers["x-gateway-event"] || req.headers["X-Gateway-Event"];

  if (!signatureHeader || !timestampHeader || !deliveryId) {
    return res.status(401).json({
      error: "MISSING_AUTHENTICATION",
      message: "Webhook requires X-Gateway-Signature, X-Gateway-Timestamp, and X-Gateway-Delivery-Id headers."
    });
  }

  // 2. Anti-replay verification (5-minute tolerance window)
  const webhookTimestamp = Number(timestampHeader);
  const now = Date.now();
  if (!Number.isFinite(webhookTimestamp) || Math.abs(now - webhookTimestamp) > config.replayWindowMs) {
    return res.status(401).json({
      error: "REPLAY_WINDOW_EXPIRED",
      message: "Webhook timestamp is outside the acceptable freshness window."
    });
  }

  // 3. HMAC-SHA256 Signature Verification
  let rawBody = "";
  if (typeof req.rawBody === "string") {
    rawBody = req.rawBody;
  } else if (Buffer.isBuffer(req.rawBody)) {
    rawBody = req.rawBody.toString("utf8");
  } else {
    rawBody = JSON.stringify(req.body);
  }

  const expectedSignature = crypto
    .createHmac("sha256", config.webhookSecret)
    .update(rawBody)
    .digest("hex");

  const cleanReceived = signatureHeader.replace(/^sha256=/, "").trim();

  const expectedBuf = Buffer.from(expectedSignature, "utf8");
  const receivedBuf = Buffer.from(cleanReceived, "utf8");

  if (expectedBuf.length !== receivedBuf.length || !crypto.timingSafeEqual(expectedBuf, receivedBuf)) {
    return res.status(401).json({
      error: "INVALID_SIGNATURE",
      message: "HMAC signature verification failed."
    });
  }

  const payload = req.body || {};
  const event = (payload.event || eventHeader || "").toUpperCase();
  const paymentId = typeof payload.paymentId === "string" ? payload.paymentId.trim() : (payload.paymentId || "");
  const utr = payload.utr || null;

  // 4. Event Type Whitelist (Reject unknown / unsupported events)
  const SUPPORTED_EVENTS = ["SUCCESS", "EXPIRED", "FAILED", "CANCELLED"];
  if (!SUPPORTED_EVENTS.includes(event)) {
    return res.status(400).json({
      error: "UNSUPPORTED_EVENT",
      message: `Webhook event '${event}' is not supported.`
    });
  }

  // 5. Require valid paymentId for all payment events
  if (!paymentId || typeof paymentId !== "string" || !paymentId.trim()) {
    return res.status(400).json({
      error: "MISSING_PAYMENT_ID",
      message: "Webhook payload requires a valid paymentId."
    });
  }

  // 6. Fast-path Idempotency Check: verify if deliveryId was already processed
  const deliveryDocRef = db.collection("processed_webhooks").doc(deliveryId);
  const priorDelivery = await deliveryDocRef.get();
  if (priorDelivery.exists) {
    return res.status(200).json({
      success: true,
      message: "ALREADY_PROCESSED",
      deliveryId
    });
  }

  // 7. Locate target Firestore Order
  const targetOrderId = payload.metadata?.firestoreOrderId || payload.orderId;
  if (!targetOrderId) {
    return res.status(400).json({ error: "MISSING_ORDER_ID", message: "Cannot associate webhook with an order." });
  }

  // Try direct doc ID lookup first
  let orderRef = db.collection("orders").doc(targetOrderId);
  let orderSnap = await orderRef.get();

  // Fallback: lookup by orderNumber field
  if (!orderSnap.exists) {
    const qSnap = await db.collection("orders").where("orderNumber", "==", targetOrderId).limit(1).get();
    if (!qSnap.empty) {
      orderSnap = qSnap.docs[0];
      orderRef = orderSnap.ref;
    }
  }

  if (!orderSnap.exists) {
    return res.status(404).json({ error: "ORDER_NOT_FOUND", message: `Order ${targetOrderId} not found.` });
  }

  const orderData = orderSnap.data();

  // 8. Cross-Validate Order Details
  // If order is already linked to a youpiPaymentId, require exact match
  if (orderData.youpiPaymentId && orderData.youpiPaymentId !== paymentId) {
    return res.status(400).json({
      error: "PAYMENT_ID_MISMATCH",
      message: `Payment ID mismatch: order is linked to ${orderData.youpiPaymentId}, webhook reported ${paymentId}.`
    });
  }

  const orderTotalPaise = Math.round(Number(orderData.totalPrice || 0) * 100);
  const webhookPaise = Number(payload.amountPaise) || Math.round(Number(payload.amount || 0) * 100);

  if (Math.abs(orderTotalPaise - webhookPaise) > 1) { // 1 paisa rounding leeway
    return res.status(400).json({
      error: "AMOUNT_MISMATCH",
      message: `Order requires ₹${orderData.totalPrice}, but webhook reported ₹${payload.amount}.`
    });
  }

  if (payload.currency && payload.currency.toUpperCase() !== "INR") {
    return res.status(400).json({ error: "CURRENCY_MISMATCH", message: "Expected INR currency." });
  }

  // 9. Atomic Execution with Inventory & Notification Safeguards
  // Enforces Firestore transaction rules: ALL READS BEFORE ANY WRITES
  const txResult = await db.runTransaction(async (transaction) => {
    // Transactional Read 1: Check delivery document atomically to prevent concurrent race conditions
    const deliverySnap = await transaction.get(deliveryDocRef);
    if (deliverySnap.exists) {
      return { duplicate: true };
    }

    // Transactional Read 2: Order document
    const freshOrderSnap = await transaction.get(orderRef);
    if (!freshOrderSnap.exists) {
      return { orderNotFound: true };
    }
    const freshData = freshOrderSnap.data();

    // Verify payment ID match against fresh transactional data
    if (freshData.youpiPaymentId && freshData.youpiPaymentId !== paymentId) {
      return { paymentIdMismatch: true, expected: freshData.youpiPaymentId, actual: paymentId };
    }

    const timestampField = admin.firestore?.FieldValue?.serverTimestamp
      ? admin.firestore.FieldValue.serverTimestamp()
      : new Date().toISOString();

    if (event === "SUCCESS") {
      // If already Paid, idempotent no-op
      if (freshData.paymentStatus === "Paid") {
        transaction.set(deliveryDocRef, {
          deliveryId,
          paymentId,
          orderId: orderRef.id,
          event: "SUCCESS",
          status: "DUPLICATE_IGNORED",
          processedAt: timestampField
        });
        return { success: true, duplicate: true };
      }

      // If order is already CANCELLED or EXPIRED, do NOT revive it to Paid!
      // Instead, flag for merchant manual review / refund so goods are not shipped without inventory.
      if (freshData.status === "CANCELLED" || ["Cancelled", "Expired", "Failed"].includes(freshData.paymentStatus)) {
        transaction.update(orderRef, {
          latePaymentFlag: true,
          latePaymentUtr: utr,
          latePaymentId: paymentId,
          latePaymentAmount: payload.amount,
          latePaymentReceivedAt: timestampField,
          youpiWebhookDeliveryId: deliveryId
        });
        transaction.set(deliveryDocRef, {
          deliveryId,
          paymentId,
          orderId: orderRef.id,
          event: "SUCCESS",
          status: "LATE_PAYMENT_ON_CANCELLED_ORDER",
          processedAt: timestampField
        });
        return { success: true, latePayment: true };
      }

      // Update order to Paid
      // NOTE: Inventory was already decremented at checkout time! Do NOT decrement again.
      transaction.update(orderRef, {
        paymentStatus: "Paid",
        paymentMethod: "UPI",
        paymentUtr: utr,
        youpiPaymentId: paymentId,
        youpiWebhookDeliveryId: deliveryId,
        paidAt: timestampField
      });

      transaction.set(deliveryDocRef, {
        deliveryId,
        paymentId,
        orderId: orderRef.id,
        event: "SUCCESS",
        processedAt: timestampField
      });
      return { success: true };
    } else if (event === "EXPIRED" || event === "FAILED" || event === "CANCELLED") {
      // Never downgrade an already Paid order
      if (freshData.paymentStatus === "Paid") {
        transaction.set(deliveryDocRef, {
          deliveryId,
          paymentId,
          orderId: orderRef.id,
          event,
          status: "IGNORED_ALREADY_PAID",
          processedAt: timestampField
        });
        return { success: true, ignored: true };
      }

      // Transition payment status to terminal failure
      const terminalPaymentStatus = event === "EXPIRED" ? "Expired" : (event === "CANCELLED" ? "Cancelled" : "Failed");

      // Transactional Read 3: Collect items to restore BEFORE any writes occur
      const itemsToRestore = [];
      if (!freshData.inventoryRestored) {
        if (Array.isArray(freshData.items)) {
          for (const it of freshData.items) {
            if (it.productId && Number(it.quantity) > 0) {
              itemsToRestore.push({ productId: it.productId, quantity: Number(it.quantity) });
            }
          }
        }
        try {
          const orderItemsSnap = await db.collection("orders").doc(orderRef.id).collection("order_items").get();
          if (orderItemsSnap && orderItemsSnap.docs) {
            for (const itemDoc of orderItemsSnap.docs) {
              const it = itemDoc.data();
              if (it.productId && Number(it.quantity) > 0) {
                if (!itemsToRestore.some(x => x.productId === it.productId)) {
                  itemsToRestore.push({ productId: it.productId, quantity: Number(it.quantity) });
                }
              }
            }
          }
        } catch {
          // Subcollection read fallback
        }
      }

      // WRITES: Restore inventory for collected items
      for (const item of itemsToRestore) {
        const productRef = db.collection("products").doc(item.productId);
        const incField = admin.firestore?.FieldValue?.increment
          ? admin.firestore.FieldValue.increment(item.quantity)
          : item.quantity;
        transaction.update(productRef, {
          stockQuantity: incField
        });
      }

      transaction.update(orderRef, {
        paymentStatus: terminalPaymentStatus,
        status: "CANCELLED",
        inventoryRestored: true,
        cancelledAt: timestampField,
        cancellationReason: `Online payment ${event.toLowerCase()}`,
        youpiWebhookDeliveryId: deliveryId
      });

      transaction.set(deliveryDocRef, {
        deliveryId,
        paymentId,
        orderId: orderRef.id,
        event,
        inventoryRestored: true,
        processedAt: timestampField
      });
      return { success: true, cancelled: true };
    }
  });

  if (txResult?.duplicate) {
    return res.status(200).json({
      success: true,
      message: "ALREADY_PROCESSED",
      deliveryId
    });
  }

  if (txResult?.paymentIdMismatch) {
    return res.status(400).json({
      error: "PAYMENT_ID_MISMATCH",
      message: `Payment ID mismatch: order is linked to ${txResult.expected}, webhook reported ${txResult.actual}.`
    });
  }

  if (txResult?.orderNotFound) {
    return res.status(404).json({ error: "ORDER_NOT_FOUND", message: `Order ${targetOrderId} not found.` });
  }

  return res.status(200).json({
    success: true,
    processed: true,
    event,
    deliveryId,
    orderId: orderRef.id
  });
}

/**
 * Secure Server-Side Endpoint: Converts a pending online UPI order to Cash on Delivery (COD).
 * - Authenticates customer via Firebase Auth.
 * - Validates order ownership and existence.
 * - Rejects if order is already Paid, Cancelled, or Expired.
 * - Atomically switches paymentMethod to COD.
 * - Does NOT alter product inventory (stock remains safely reserved for the order).
 */
async function handleConvertOrderToCod(req, res, { db = admin.firestore(), auth = admin.auth() } = {}) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  // 1. Authenticate customer
  const user = await authenticateFirebaseUser(req, auth);
  if (!user || !user.uid) {
    return res.status(401).json({ error: "UNAUTHORIZED", message: "Valid Firebase authentication token required." });
  }

  const { orderId } = req.body || {};
  if (!orderId || typeof orderId !== "string") {
    return res.status(400).json({ error: "BAD_REQUEST", message: "orderId is required." });
  }

  const orderRef = db.collection("orders").doc(orderId);

  try {
    const result = await db.runTransaction(async (transaction) => {
      const orderSnap = await transaction.get(orderRef);
      if (!orderSnap.exists) {
        return { status: 404, body: { error: "NOT_FOUND", message: `Order #${orderId} does not exist.` } };
      }

      const orderData = orderSnap.data();

      // Validate ownership
      if (orderData.customerId !== user.uid) {
        return { status: 403, body: { error: "FORBIDDEN", message: "You are not authorized to update this order." } };
      }

      // Prohibit changing payment method after payment is completed
      if (orderData.paymentStatus === "Paid") {
        return { status: 400, body: { error: "ALREADY_PAID", message: "Cannot convert payment method on an already paid order." } };
      }

      // Prohibit changing payment method if order is cancelled or expired
      if (
        (orderData.status && orderData.status.toUpperCase() === "CANCELLED") ||
        ["Cancelled", "Expired", "Failed"].includes(orderData.paymentStatus)
      ) {
        return { status: 400, body: { error: "ORDER_TERMINAL", message: "Cannot convert payment method on a cancelled or expired order." } };
      }

      if (orderData.paymentMethod === "COD") {
        return { status: 200, body: { success: true, message: "Order is already Cash on Delivery.", orderId, paymentMethod: "COD" } };
      }

      const timestampField = admin.firestore?.FieldValue?.serverTimestamp
        ? admin.firestore.FieldValue.serverTimestamp()
        : new Date().toISOString();

      transaction.update(orderRef, {
        paymentMethod: "COD",
        paymentStatus: "Pending",
        convertedToCodAt: timestampField,
        previousPaymentMethod: orderData.paymentMethod
      });

      return { status: 200, body: { success: true, message: "Order converted to Cash on Delivery.", orderId, paymentMethod: "COD" } };
    });

    return res.status(result.status).json(result.body);
  } catch (err) {
    return res.status(500).json({ error: "INTERNAL_ERROR", message: err.message });
  }
}

/**
 * Restores product stock quantities for an order from either its items array
 * or the order_items subcollection.
 */
async function restoreOrderInventory(orderRef, orderData, db, transaction) {
  const productQuantities = new Map();

  // 1. Embedded items array (if present on order document)
  if (Array.isArray(orderData.items)) {
    for (const item of orderData.items) {
      if (item.productId && Number(item.quantity) > 0) {
        productQuantities.set(
          item.productId,
          (productQuantities.get(item.productId) || 0) + Number(item.quantity)
        );
      }
    }
  }

  // 2. Subcollection order_items (if present)
  try {
    const itemsSnap = await db.collection("orders").doc(orderRef.id).collection("order_items").get();
    if (itemsSnap && itemsSnap.docs) {
      for (const itemDoc of itemsSnap.docs) {
        const item = itemDoc.data();
        if (item.productId && Number(item.quantity) > 0) {
          productQuantities.set(
            item.productId,
            (productQuantities.get(item.productId) || 0) + Number(item.quantity)
          );
        }
      }
    }
  } catch (err) {
    // subcollection may not exist in mock/schema
  }

  for (const [productId, quantity] of productQuantities.entries()) {
    const productRef = db.collection("products").doc(productId);
    const incField = admin.firestore?.FieldValue?.increment
      ? admin.firestore.FieldValue.increment(quantity)
      : quantity;
    transaction.update(productRef, { stockQuantity: incField });
  }
}

/**
 * Scheduled / Background Task: Resolves abandoned or unpaid UPI orders.
 *
 * SAFETY RULES:
 * 1. Never cancel an order merely because a webhook is delayed: query the gateway directly to verify state.
 * 2. If the gateway confirms payment was SUCCESS, fulfill it to Paid instead of cancelling!
 * 3. If the gateway is unreachable, flag for reconciliation rather than blindly restoring stock.
 * 4. Only restore inventory once using an atomic transaction and inventoryRestored flag.
 */
async function handleCleanupUnpaidOrders({
  db = admin.firestore(),
  fetchFn = globalThis.fetch,
  olderThanMinutes = 30,
  ttlMs = olderThanMinutes * 60 * 1000,
  nowMs = Date.now()
} = {}) {
  const config = getYoupiConfig();

  const ordersSnap = await db.collection("orders")
    .where("paymentMethod", "==", "UPI")
    .where("paymentStatus", "==", "Pending")
    .get();

  const results = {
    evaluated: 0,
    examined: 0,
    cancelled: 0,
    reconciled: 0,
    fulfilledLatePayment: 0,
    flagged: 0,
    flaggedForReconciliation: 0,
    skipped: 0
  };

  for (const doc of ordersSnap.docs) {
    const orderData = doc.data();
    results.evaluated++;
    results.examined++;

    const rawDate = orderData.placedAt || orderData.createdAt;
    const placedDate = rawDate
      ? (typeof rawDate.toDate === "function" ? rawDate.toDate() : new Date(rawDate))
      : null;

    if (placedDate && (nowMs - placedDate.getTime()) < ttlMs) {
      results.skipped++;
      continue;
    }

    const orderRef = doc.ref;

    // CASE 1: No gateway session exists (payment was never initiated on gateway)
    if (!orderData.youpiPaymentId) {
      await db.runTransaction(async (transaction) => {
        const freshSnap = await transaction.get(orderRef);
        if (!freshSnap.exists) return;
        const fresh = freshSnap.data();
        if (fresh.paymentStatus !== "Pending" || (fresh.status && fresh.status.toUpperCase() === "CANCELLED")) return;

        if (!fresh.inventoryRestored) {
          await restoreOrderInventory(orderRef, fresh, db, transaction);
        }

        const timestampField = admin.firestore?.FieldValue?.serverTimestamp
          ? admin.firestore.FieldValue.serverTimestamp()
          : new Date().toISOString();

        transaction.update(orderRef, {
          status: "Cancelled",
          paymentStatus: "Expired",
          cancellationReason: "Abandoned: Payment session was never initiated",
          inventoryRestored: true,
          cancelledAt: timestampField
        });
      });
      results.cancelled++;
      continue;
    }

    // CASE 2: Gateway session exists - Query Gateway directly
    try {
      const gwRes = await fetchFn(`${config.apiBaseUrl}/api/v1/payments/${orderData.youpiPaymentId}`, {
        method: "GET",
        headers: {
          "Authorization": `Bearer ${config.merchantApiKey}`
        }
      });

      if (!gwRes.ok) {
        await orderRef.update({
          reconciliationRequired: true,
          reconciliationReason: `Gateway returned status ${gwRes.status} during unpaid order cleanup`,
          reconciliationFlaggedAt: admin.firestore?.FieldValue?.serverTimestamp
            ? admin.firestore.FieldValue.serverTimestamp()
            : new Date().toISOString()
        });
        results.flagged++;
        results.flaggedForReconciliation++;
        continue;
      }

      const gwData = await gwRes.json();
      const gwStatus = (gwData.status || "").toUpperCase();

      if (gwStatus === "SUCCESS") {
        await db.runTransaction(async (transaction) => {
          const freshSnap = await transaction.get(orderRef);
          if (!freshSnap.exists) return;
          const fresh = freshSnap.data();
          if (fresh.paymentStatus === "Paid") return;

          const timestampField = admin.firestore?.FieldValue?.serverTimestamp
            ? admin.firestore.FieldValue.serverTimestamp()
            : new Date().toISOString();

          transaction.update(orderRef, {
            status: "Accepted",
            paymentStatus: "Paid",
            paymentUtr: gwData.utr || null,
            paidAt: timestampField,
            reconciledByCleanup: true
          });
        });
        results.reconciled++;
        results.fulfilledLatePayment++;
      } else if (gwStatus === "EXPIRED" || gwStatus === "CANCELLED" || gwStatus === "FAILED") {
        await db.runTransaction(async (transaction) => {
          const freshSnap = await transaction.get(orderRef);
          if (!freshSnap.exists) return;
          const fresh = freshSnap.data();
          if (fresh.paymentStatus !== "Pending" || (fresh.status && fresh.status.toUpperCase() === "CANCELLED")) return;

          if (!fresh.inventoryRestored) {
            await restoreOrderInventory(orderRef, fresh, db, transaction);
          }

          const timestampField = admin.firestore?.FieldValue?.serverTimestamp
            ? admin.firestore.FieldValue.serverTimestamp()
            : new Date().toISOString();

          transaction.update(orderRef, {
            status: "Cancelled",
            paymentStatus: gwStatus === "EXPIRED" ? "Expired" : "Cancelled",
            cancellationReason: `Gateway session ${gwStatus.toLowerCase()}`,
            inventoryRestored: true,
            cancelledAt: timestampField
          });
        });
        results.cancelled++;
      } else {
        results.skipped++;
      }
    } catch (netErr) {
      await orderRef.update({
        reconciliationRequired: true,
        reconciliationReason: `Gateway network error during unpaid order cleanup: ${netErr.message}`,
        reconciliationFlaggedAt: admin.firestore?.FieldValue?.serverTimestamp
          ? admin.firestore.FieldValue.serverTimestamp()
          : new Date().toISOString()
      });
      results.flagged++;
      results.flaggedForReconciliation++;
    }
  }

  return results;
}

/**
 * Abstract Payment Gateway Provider Interface
 * Allows seamless switching between YouPI-PG (local/sandbox) and production aggregators.
 */
class PaymentGatewayProvider {
  async createPaymentSession(order) {
    throw new Error("createPaymentSession() must be implemented");
  }
  async verifyWebhook(req) {
    throw new Error("verifyWebhook() must be implemented");
  }
  async getPaymentStatus(paymentId) {
    throw new Error("getPaymentStatus() must be implemented");
  }
}

module.exports = {
  getYoupiConfig,
  authenticateFirebaseUser,
  handleCreatePaymentSession,
  handleYoupiWebhook,
  handleConvertOrderToCod,
  handleCleanupUnpaidOrders,
  PaymentGatewayProvider
};

