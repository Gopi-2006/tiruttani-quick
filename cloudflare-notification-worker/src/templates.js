/**
 * Order status notification templates and payload builders for Tiruttani Quick.
 */

export const NOTIFICATION_STATUSES = {
  ACCEPTED: 'accepted',
  PACKED: 'packed',
  OUT_FOR_DELIVERY: 'out_for_delivery',
  DELIVERED: 'delivered',
  CANCELLED: 'cancelled',
  TEST: 'test',
};

/**
 * Normalizes status strings from various formats (e.g. 'Order Accepted', 'out_for_delivery', 'Confirmed')
 * into standardized internal notification status keys.
 */
export function normalizeStatus(rawStatus) {
  if (!rawStatus || typeof rawStatus !== 'string') return null;
  const s = rawStatus.toLowerCase().trim();

  if (s === 'test') {
    return NOTIFICATION_STATUSES.TEST;
  }
  if (s.includes('accept') || s.includes('confirm') || s === 'accepted' || s === 'confirmed') {
    return NOTIFICATION_STATUSES.ACCEPTED;
  }
  if (s.includes('pack') || s === 'packed') {
    return NOTIFICATION_STATUSES.PACKED;
  }
  if (s.includes('out') || s.includes('delivery') && !s.includes('delivered') || s === 'out_for_delivery') {
    return NOTIFICATION_STATUSES.OUT_FOR_DELIVERY;
  }
  if (s.includes('deliver') || s === 'delivered') {
    return NOTIFICATION_STATUSES.DELIVERED;
  }
  if (s.includes('cancel') || s === 'cancelled') {
    return NOTIFICATION_STATUSES.CANCELLED;
  }
  return null;
}

/**
 * Generates user-facing title and body for each status.
 */
export function getNotificationContent(statusKey, orderId, orderNumber) {
  const displayId = orderNumber || (orderId ? (orderId.length > 8 ? orderId.substring(0, 8) : orderId) : '');
  const idText = displayId ? ` #${displayId}` : '';

  switch (statusKey) {
    case NOTIFICATION_STATUSES.ACCEPTED:
      return {
        title: 'Order Accepted',
        body: `Your Tiruttani Quick order${idText} has been accepted.`,
      };
    case NOTIFICATION_STATUSES.PACKED:
      return {
        title: 'Order Packed',
        body: `Your Tiruttani Quick order${idText} has been packed and is ready.`,
      };
    case NOTIFICATION_STATUSES.OUT_FOR_DELIVERY:
      return {
        title: 'Out for Delivery',
        body: `Your Tiruttani Quick order${idText} is on the way.`,
      };
    case NOTIFICATION_STATUSES.DELIVERED:
      return {
        title: 'Order Delivered',
        body: `Your Tiruttani Quick order${idText} has been delivered.`,
      };
    case NOTIFICATION_STATUSES.CANCELLED:
      return {
        title: 'Order Cancelled',
        body: `Your Tiruttani Quick order${idText} has been cancelled.`,
      };
    case NOTIFICATION_STATUSES.TEST:
      return {
        title: 'Tiruttani Quick Test',
        body: 'FCM notification is working successfully.',
      };
    default:
      return {
        title: 'Order Status Updated',
        body: `Your Tiruttani Quick order${idText} status has been updated.`,
      };
  }
}

/**
 * Builds the FCM HTTP v1 JSON message structure for an individual registration token.
 */
export function buildFcmV1Message({ token, statusKey, orderId, orderNumber }) {
  const content = getNotificationContent(statusKey, orderId, orderNumber);

  return {
    message: {
      token: token,
      notification: {
        title: content.title,
        body: content.body,
      },
      data: {
        type: statusKey === 'test' ? 'test' : 'order_status',
        orderId: String(orderId || ''),
        status: String(statusKey || ''),
        screen: statusKey === 'test' ? 'home' : 'order_tracking',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: {
          channel_id: 'orders_channel',
          sound: 'default',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
          default_sound: true,
          default_vibrate_timings: true,
          notification_priority: 'PRIORITY_HIGH',
        },
      },
    },
  };
}

/**
 * Builds the FCM HTTP v1 JSON message structure for an Admin New Order Alert.
 * Targets the 'admin_new_orders' high-priority notification channel with custom alert sound.
 */
export function buildAdminNewOrderFcmMessage({ token, orderId, orderNumber, totalAmount, customerName }) {
  const displayNum = orderNumber || (orderId ? (orderId.length > 8 ? orderId.substring(0, 8) : orderId) : '');
  const title = 'New Order Received';
  const amountStr = totalAmount ? ` worth ₹${Number(totalAmount).toFixed(0)}` : '';
  const body = `New order #${displayNum}${amountStr} placed by ${customerName || 'Customer'}.`;

  return {
    message: {
      token: token,
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: 'new_order',
        orderId: String(orderId || ''),
        orderNumber: String(displayNum || ''),
        screen: 'admin_dashboard',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: {
          channel_id: 'admin_new_orders_v2',
          sound: 'new_order_alert',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
          default_sound: false,
          default_vibrate_timings: true,
          notification_priority: 'PRIORITY_HIGH',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'new_order_alert.wav',
            badge: 1,
          },
        },
      },
    },
  };
}

