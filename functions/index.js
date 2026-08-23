const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");
const {
  rateLimiterMiddleware,
  checkAccountLockout,
  handleLoginFailure,
  handleLoginSuccess
} = require("./security");

// Initialize Firebase Admin SDK
if (admin.apps.length === 0) {
  admin.initializeApp();
}

/**
 * Normalizes status strings across different naming and casing conventions.
 * Maps 'confirmed' -> 'accepted', 'out for delivery' -> 'out_for_delivery', etc.
 */
function normalizeOrderStatus(status) {
  if (!status || typeof status !== "string") return "";
  const s = status.trim().toLowerCase().replace(/[\s-]+/g, "_");
  if (s === "confirmed" || s === "accept" || s === "accepted") return "accepted";
  if (s === "pack" || s === "packed") return "packed";
  if (s === "out_for_delivery" || s === "outfordelivery" || s === "on_the_way") return "out_for_delivery";
  if (s === "deliver" || s === "delivered") return "delivered";
  if (s === "cancel" || s === "cancelled" || s === "canceled") return "cancelled";
  if (s === "pending" || s === "placed") return "pending";
  return s;
}

/**
 * Builds the notification title, body, and payload data for a given order status.
 */
function buildNotificationPayload(orderId, orderNumber, status, deliveryOtp) {
  const normalized = normalizeOrderStatus(status);
  const displayOrderNum = orderNumber || orderId;

  let title = "";
  let body = "";

  switch (normalized) {
    case "accepted":
      title = "Order Accepted";
      body = `Your Tiruttani Quick order #${displayOrderNum} has been accepted.`;
      break;
    case "packed":
      title = "Order Packed";
      body = `Your Tiruttani Quick order #${displayOrderNum} has been packed and is ready.`;
      break;
    case "out_for_delivery":
      title = "Out for Delivery";
      body = deliveryOtp
        ? `Your Tiruttani Quick order #${displayOrderNum} is on the way. Delivery OTP: ${deliveryOtp}`
        : `Your Tiruttani Quick order #${displayOrderNum} is on the way.`;
      break;
    case "delivered":
      title = "Order Delivered";
      body = `Your Tiruttani Quick order #${displayOrderNum} has been delivered.`;
      break;
    case "cancelled":
      title = "Order Cancelled";
      body = `Your Tiruttani Quick order #${displayOrderNum} has been cancelled.`;
      break;
    default:
      return null;
  }

  return {
    title,
    body,
    canonicalStatus: normalized,
    data: {
      type: "order_status",
      orderId: orderId,
      status: normalized,
      deliveryOtp: deliveryOtp || "",
      screen: "order_tracking"
    }
  };
}

/**
 * Dispatches an FCM push notification to a list of device tokens using Firebase Admin SDK.
 */
async function sendFCMPush(tokens, orderNumber, notification) {
  if (!tokens || tokens.length === 0) {
    return { success: false, reason: "no_tokens" };
  }

  const results = [];

  for (const token of tokens) {
    const message = {
      token: token,
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: {
        type: "order_status",
        orderId: notification.data.orderId,
        status: notification.canonicalStatus,
        screen: "order_tracking",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "orders_channel",
          sound: "default",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    try {
      const response = await admin.messaging().send(message);
      console.log(`[FCM] Notification sent successfully for order #${orderNumber}:`, response);
      results.push({ token, success: true, messageId: response });
    } catch (error) {
      console.warn(`[FCM] Notification dispatch error for order #${orderNumber} (token: ${token.substring(0, 8)}...):`, error.message);
      results.push({ token, success: false, error: error.code || error.message });
    }
  }

  return { success: results.some((r) => r.success), results };
}

/**
 * Core business logic for processing order status updates.
 * Generates secure delivery OTP on 'out_for_delivery' transition.
 * FCM push notifications for order status are handled exclusively by the Cloudflare Worker.
 */
async function handleOrderStatusUpdate(beforeData, afterData, orderId) {
  if (!beforeData || !afterData) {
    return { skipped: true, reason: "missing_data" };
  }

  const oldStatusNorm = normalizeOrderStatus(beforeData.status);
  const newStatusNorm = normalizeOrderStatus(afterData.status);

  // 1. Duplicate notification protection: if status did not change, skip execution
  if (oldStatusNorm === newStatusNorm) {
    return { skipped: true, reason: "status_unchanged" };
  }

  // 2. Validate customer identification
  const customerId = afterData.customerId || beforeData.customerId;
  if (!customerId) {
    console.warn(`[Order Trigger] Order ${orderId} has no customerId. Skipping.`);
    return { skipped: true, reason: "missing_customer_id" };
  }

  // 3. Generate secure delivery OTP when entering 'out_for_delivery' if not already present
  let deliveryOtp = afterData.deliveryOtp || beforeData.deliveryOtp;
  if (newStatusNorm === "out_for_delivery" && !deliveryOtp) {
    deliveryOtp = crypto.randomInt(100000, 1000000).toString();
    try {
      if (admin.apps.length > 0 && orderId) {
        await admin.firestore().collection("orders").doc(orderId).update({
          deliveryOtp: deliveryOtp,
          deliveryOtpCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[Order Trigger] Secure delivery OTP generated for order ${orderId}`);
      }
    } catch (dbErr) {
      console.warn(`[Order Trigger] Could not persist delivery OTP for order ${orderId}:`, dbErr.message);
    }
  }

  // 4. Build notification copy
  const orderNumber = afterData.orderNumber || beforeData.orderNumber || orderId;
  const notification = buildNotificationPayload(orderId, orderNumber, afterData.status, deliveryOtp);

  if (!notification) {
    return { skipped: true, reason: "no_notification_for_status", status: afterData.status };
  }

  // Note: Push notifications are dispatched exclusively via the Cloudflare Worker from the Admin App,
  // preventing duplicate FCM notifications.
  return {
    skipped: false,
    orderId,
    customerId,
    status: notification.canonicalStatus,
    title: notification.title,
    body: notification.body,
    deliveryOtp,
  };
}

/**
 * Handles newly created orders by notifying Admin devices via FCM.
 */
async function handleOrderCreated(orderData, orderId) {
  if (!orderData) {
    return { skipped: true, reason: "missing_data" };
  }

  const orderNumber = orderData.orderNumber || orderId;
  const totalPrice = orderData.totalPrice || 0;

  // Retrieve admin device FCM tokens from Firestore
  const tokens = new Set();
  try {
    const adminDocs = await admin.firestore().collection("users").where("role", "==", "Admin").get();
    for (const doc of adminDocs.docs) {
      const data = doc.data();
      if (data?.fcmToken) {
        tokens.add(data.fcmToken);
      }
      try {
        const subDocs = await doc.ref.collection("fcmTokens").get();
        subDocs.forEach((subDoc) => {
          if (subDoc.id && subDoc.id.length > 10) {
            tokens.add(subDoc.id);
          }
        });
      } catch (_) {}
    }
  } catch (err) {
    console.warn(`[Order Trigger] Error querying Admin tokens for new order ${orderId}:`, err.message);
  }

  const tokenList = Array.from(tokens);
  if (tokenList.length === 0) {
    return { skipped: true, reason: "no_admin_tokens", orderId };
  }

  const notification = {
    title: "New Order Received",
    body: `New order #${orderNumber} (₹${totalPrice}) received.`,
    canonicalStatus: "new_order",
    data: {
      type: "new_order",
      orderId: orderId,
      orderNumber: String(orderNumber),
      customerId: String(orderData.customerId || ""),
      status: "pending",
      screen: "admin_dashboard",
    },
  };

  const results = [];
  for (const token of tokenList) {
    const message = {
      token: token,
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: {
        type: "new_order",
        orderId: orderId,
        orderNumber: String(orderNumber),
        customerId: String(orderData.customerId || ""),
        status: "pending",
        screen: "admin_dashboard",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "admin_new_orders_v2",
          sound: "new_order_alert",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "new_order_alert.wav",
            badge: 1,
          },
        },
      },
    };

    try {
      const response = await admin.messaging().send(message);
      results.push({ token, success: true, messageId: response });
    } catch (error) {
      results.push({ token, success: false, error: error.code || error.message });
    }
  }

  return {
    skipped: false,
    orderId,
    tokenCount: tokenList.length,
    results,
  };
}

/**
 * Firestore trigger: runs when an order document in the 'orders' collection is created.
 */
exports.onOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  const orderData = event.data?.data() || {};
  const orderId = event.params.orderId;
  return await handleOrderCreated(orderData, orderId);
});

/**
 * Firestore trigger: runs when an order document in the 'orders' collection is updated.
 * Dispatches pure Firebase Cloud Messaging notifications to customer devices.
 */
exports.onOrderStatusUpdated = onDocumentUpdated("orders/{orderId}", async (event) => {
  const oldValue = event.data?.before?.data() || {};
  const newValue = event.data?.after?.data() || {};
  const orderId = event.params.orderId;

  return await handleOrderStatusUpdate(oldValue, newValue, orderId);
});

/**
 * Login HTTP Endpoint
 * Verifies credentials, applies rate limiting and account lockout/delay mechanisms.
 */
exports.login = onRequest(async (req, res) => {
  // Run the IP rate limiter middleware
  await rateLimiterMiddleware(req, res, async () => {
    const { email, password } = req.body || {};

    if (!email || !password) {
      return res.status(400).json({ error: "Email and password are required." });
    }

    try {
      // 1. Check if the account is currently locked out
      const isLocked = await checkAccountLockout(email, res);
      if (isLocked) return;

      // 2. Authenticate the user.
      let isAuthenticated = false;
      const userSnapshot = await admin.firestore().collection("users").where("email", "==", email).get();

      if (!userSnapshot.empty) {
        const userData = userSnapshot.docs[0].data();
        
        // Check password against stored passwordHash or password field
        if (userData.passwordHash && userData.passwordHash === password) {
          isAuthenticated = true;
        } else if (userData.password && userData.password === password) {
          isAuthenticated = true;
        }
      }

      if (isAuthenticated) {
        // Clear failed attempts upon successful login
        await handleLoginSuccess(email);

        // Resolve the Firebase Auth UID from email before generating a Custom Token
        let customToken = "";
        try {
          const userRecord = await admin.auth().getUserByEmail(email);
          customToken = await admin.auth().createCustomToken(userRecord.uid);
        } catch (authError) {
          console.error("Could not generate Custom Token:", authError.message);
          return res.status(500).json({ error: "Authentication service error. Please try again." });
        }

        return res.status(200).json({
          message: "Login successful.",
          token: customToken,
        });
      } else {
        // Handle failed attempt (locks if >= 5 attempts, applies progressive delay)
        return await handleLoginFailure(email, res);
      }
    } catch (error) {
      console.error("Login endpoint error:", error);
      return res.status(500).json({ error: "Internal server error." });
    }
  });
});

// Export helper methods for automated testing
exports._test = {
  normalizeOrderStatus,
  buildNotificationPayload,
  sendFCMPush,
  handleOrderStatusUpdate,
  handleOrderCreated,
};
