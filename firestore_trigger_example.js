/**
 * Firebase Cloud Functions triggers for Blinkit Grocery Platform notifications.
 * Language: Node.js (JavaScript / ES6)
 *
 * This file serves as a production-ready example of how to implement the backend trigger
 * notifications using Firebase Cloud Functions (v2) and Firebase Admin SDK.
 *
 * To deploy these, place them inside your firebase functions directory (functions/index.js)
 * and run: firebase deploy --only functions
 */

const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

// Initialize Admin SDK
admin.initializeApp();

/**
 * 1. ORDER STATUS CHANGE TRIGGER (Customer Notifications)
 * Triggers when an order document in the 'orders' collection is updated.
 * Automatically resolves the customer's FCM token and sends status notification.
 */
exports.onOrderStatusUpdated = onDocumentUpdated("orders/{orderId}", async (event) => {
  const newValue = event.data.after.data();
  const oldValue = event.data.before.data();

  // If status did not change, skip execution
  if (newValue.status === oldValue.status) {
    return;
  }

  const customerId = newValue.customerId;
  const status = newValue.status; // pending, confirmed, packed, out_for_delivery, delivered
  const orderNumber = newValue.orderNumber || event.params.orderId;

  // Resolve notification content based on status
  let title = "";
  let body = "";

  switch (status) {
    case "pending":
      title = "Order Placed Successfully";
      body = `Your order #${orderNumber} has been received.`;
      break;
    case "confirmed":
      title = "Order Confirmed";
      body = `Your order #${orderNumber} is being prepared.`;
      break;
    case "packed":
      title = "Order Packed";
      body = `Your order #${orderNumber} has been packed.`;
      break;
    case "out_for_delivery":
      title = "Out for Delivery";
      body = `Your groceries for order #${orderNumber} are on the way.`;
      break;
    case "delivered":
      title = "Order Delivered";
      body = `Your order #${orderNumber} has been delivered successfully.`;
      break;
    default:
      // Status not handled or custom alerts
      return;
  }

  try {
    // Fetch the customer profile to obtain fcmToken
    const userDoc = await admin.firestore().collection("users").doc(customerId).get();
    if (!userDoc.exists) {
      console.log(`User document not found for ID: ${customerId}`);
      return;
    }

    const userData = userDoc.data();
    const fcmToken = userData.fcmToken;

    if (!fcmToken) {
      console.log(`No FCM token registered for customer: ${customerId}`);
      return;
    }

    // Build the FCM payload
    const message = {
      token: fcmToken,
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: "order",
        orderId: event.params.orderId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        notification: {
          channelId: "orders_channel",
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

    // Send the notification
    const response = await admin.messaging().send(message);
    console.log(`Successfully sent order status notification to ${customerId}. Response:`, response);
  } catch (error) {
    console.error("Error sending order status notification:", error);
  }
});

/**
 * 2. NEW ORDER CREATED TRIGGER (Admin Alerts)
 * Triggers when a new order is added to the 'orders' collection.
 * Notifies all users with the 'admin' role.
 */
exports.onOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  const orderData = event.data.data();
  const orderNumber = orderData.orderNumber || event.params.orderId;

  try {
    // Fetch all admins from Firestore
    const adminsSnapshot = await admin
      .firestore()
      .collection("users")
      .where("role", "==", "admin")
      .get();

    const adminTokens = [];
    adminsSnapshot.forEach((doc) => {
      const data = doc.data();
      if (data.fcmToken) {
        adminTokens.push(data.fcmToken);
      }
    });

    if (adminTokens.length === 0) {
      console.log("No registered admin FCM tokens found.");
      return;
    }

    // Send multicast message to all admin tokens
    const message = {
      tokens: adminTokens,
      notification: {
        title: "New Order Received",
        body: `A customer has placed order #${orderNumber}.`,
      },
      data: {
        type: "admin",
        orderId: event.params.orderId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        notification: {
          channelId: "admin_channel",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`Multicast sent to admins. Success count: ${response.successCount}, Failure count: ${response.failureCount}`);
  } catch (error) {
    console.error("Error sending new order alert to admins:", error);
  }
});

/**
 * 3. PRODUCT LOW STOCK TRIGGER (Admin Alerts)
 * Triggers when a product document in the 'products' collection is updated.
 * Automatically alerts admins if the stock falls below a threshold (e.g. 5 units).
 */
exports.onProductStockUpdated = onDocumentUpdated("products/{productId}", async (event) => {
  const newValue = event.data.after.data();
  const oldValue = event.data.before.data();

  const stockThreshold = 5;

  // Check if stock decreased and fell below threshold
  if (newValue.stockQuantity < stockThreshold && oldValue.stockQuantity >= stockThreshold) {
    try {
      // Fetch all admins
      const adminsSnapshot = await admin
        .firestore()
        .collection("users")
        .where("role", "==", "admin")
        .get();

      const adminTokens = [];
      adminsSnapshot.forEach((doc) => {
        const data = doc.data();
        if (data.fcmToken) {
          adminTokens.push(data.fcmToken);
        }
      });

      if (adminTokens.length === 0) {
        return;
      }

      const message = {
        tokens: adminTokens,
        notification: {
          title: "Low Stock Alert",
          body: `Product '${newValue.name}' is running low on stock (${newValue.stockQuantity} remaining).`,
        },
        data: {
          type: "admin",
          productId: event.params.productId,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          notification: {
            channelId: "admin_channel",
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(`Low stock alerts sent. Success: ${response.successCount}`);
    } catch (error) {
      console.error("Error sending low stock notification:", error);
    }
  }
});

/**
 * 4. NEW CUSTOMER REGISTRATION TRIGGER (Admin Alerts)
 * Triggers when a new user joins.
 * Alerts admins of registration.
 */
exports.onCustomerRegistered = onDocumentCreated("users/{userId}", async (event) => {
  const userData = event.data.data();

  // Only trigger if the registered role is customer
  if (userData.role !== "customer") {
    return;
  }

  const customerName = userData.name || "A new user";

  try {
    const adminsSnapshot = await admin
      .firestore()
      .collection("users")
      .where("role", "==", "admin")
      .get();

    const adminTokens = [];
    adminsSnapshot.forEach((doc) => {
      const data = doc.data();
      if (data.fcmToken) {
        adminTokens.push(data.fcmToken);
      }
    });

    if (adminTokens.length === 0) {
      return;
    }

    const message = {
      tokens: adminTokens,
      notification: {
        title: "New Customer Joined",
        body: `${customerName} has registered a new account.`,
      },
      data: {
        type: "admin",
        userId: event.params.userId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        notification: {
          channelId: "admin_channel",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`New registration alert sent to admins. Success: ${response.successCount}`);
  } catch (error) {
    console.error("Error sending registration notification:", error);
  }
});
