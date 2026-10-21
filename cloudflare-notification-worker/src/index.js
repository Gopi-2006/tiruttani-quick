/**
 * Cloudflare Worker for Tiruttani Quick Push Notifications.
 * Dispatches FCM HTTP v1 notifications on order status changes without requiring Firebase Blaze plan.
 */

import { verifyFirebaseAuthToken } from './auth.js';
import { normalizeStatus } from './templates.js';
import { sendFcmNotification, sendAdminNewOrderNotification } from './fcm.js';

// Standard CORS headers
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders,
    },
  });
}

// In-worker TTL deduplication cache for order status dispatches
export const processedOrderStatusDispatches = new Map();
const DISPATCH_DEDUP_TTL_MS = 5 * 60 * 1000; // 5 minutes

export function checkAndRecordDispatchIdempotency(eventId) {
  const now = Date.now();
  // Prune expired entries if map grows large
  if (processedOrderStatusDispatches.size > 1000) {
    for (const [key, ts] of processedOrderStatusDispatches.entries()) {
      if (now - ts > DISPATCH_DEDUP_TTL_MS) {
        processedOrderStatusDispatches.delete(key);
      }
    }
  }

  if (processedOrderStatusDispatches.has(eventId)) {
    const prevTs = processedOrderStatusDispatches.get(eventId);
    if (now - prevTs < DISPATCH_DEDUP_TTL_MS) {
      return false; // Already dispatched recently!
    }
  }

  processedOrderStatusDispatches.set(eventId, now);
  return true;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders,
      });
    }

    // Health check route
    if (request.method === 'GET' && (url.pathname === '/' || url.pathname === '/health')) {
      return jsonResponse({
        status: 'ok',
        service: 'tiruttani-quick-notification-worker',
        environment: env.ENVIRONMENT || 'production',
        timestamp: new Date().toISOString(),
      });
    }

    // Customer order status notification dispatch endpoint
    if (request.method === 'POST' && url.pathname === '/send-order-notification') {
      try {
        // 1. Validate Authorization Header
        const authHeader = request.headers.get('Authorization') || '';
        if (!authHeader.startsWith('Bearer ')) {
          return jsonResponse({ error: 'Unauthorized: Missing or invalid Bearer token' }, 401);
        }

        const idToken = authHeader.substring(7).trim();

        // 2. Validate Firebase Project Configuration & Secrets
        const projectId = env.FIREBASE_PROJECT_ID;
        const clientEmail = env.FIREBASE_CLIENT_EMAIL;
        const privateKey = env.FIREBASE_PRIVATE_KEY;

        if (!projectId || !clientEmail || !privateKey) {
          return jsonResponse(
            { error: 'Server configuration error: Missing Firebase service credentials in Worker environment' },
            500
          );
        }

        const allowedEmails = (env.ALLOWED_ADMIN_EMAILS || 'gopim2006@gmail.com')
          .split(',')
          .map((e) => e.trim())
          .filter(Boolean);

        // 3. Verify Admin Authentication via Firebase ID Token
        let authenticatedUser;
        try {
          authenticatedUser = await verifyFirebaseAuthToken(idToken, projectId, allowedEmails);
        } catch (authErr) {
          return jsonResponse({ error: `Authentication failed: ${authErr.message}` }, 401);
        }

        // 4. Parse & Validate Payload
        let body;
        try {
          body = await request.json();
        } catch (_) {
          return jsonResponse({ error: 'Invalid JSON request body' }, 400);
        }

        const { orderId, orderNumber, customerId, status, tokens, deliveryOtp, deliveryPersonName, eventId } = body;

        if (!orderId) {
          return jsonResponse({ error: 'Missing required field: orderId' }, 400);
        }
        if (!status) {
          return jsonResponse({ error: 'Missing required field: status' }, 400);
        }

        const statusKey = normalizeStatus(status);
        if (!statusKey) {
          return jsonResponse({
            error: `Unsupported status "${status}". Allowed: accepted, packed, out_for_delivery, delivered, cancelled, delivery_partner_assigned`,
          }, 400);
        }

        const logicalEventId = eventId || `order_status_${orderId}_${statusKey}_${customerId || ''}`;

        // Idempotency check: ignore duplicate dispatches for the exact same order status event
        if (!checkAndRecordDispatchIdempotency(logicalEventId)) {
          return jsonResponse({
            success: true,
            orderId,
            statusKey,
            eventId: logicalEventId,
            message: 'Duplicate order status notification request ignored (idempotent)',
            delivered: 0,
            failed: 0,
            skipped: true,
            reason: 'duplicate_request_idempotent',
          });
        }

        // Validate Tokens
        const tokenList = Array.isArray(tokens)
          ? tokens
          : (tokens ? [tokens] : []);

        if (tokenList.length === 0) {
          return jsonResponse({
            success: true,
            statusKey,
            orderId,
            eventId: logicalEventId,
            message: 'No FCM registration tokens provided for customer; notification skipped.',
            delivered: 0,
            failed: 0,
          });
        }

        // 5. Send FCM Notification via Google OAuth2 & HTTP v1
        const result = await sendFcmNotification({
          projectId,
          clientEmail,
          privateKey,
          tokens: tokenList,
          statusKey,
          orderId,
          orderNumber: orderNumber || orderId.substring(0, 8),
          deliveryOtp: deliveryOtp || '',
          deliveryPersonName: deliveryPersonName || '',
          eventId: logicalEventId,
        });

        return jsonResponse({
          success: true,
          orderId,
          statusKey,
          eventId: logicalEventId,
          delivered: result.delivered,
          failed: result.failed,
          invalidTokens: result.invalidTokens,
          results: result.results,
          callerUid: authenticatedUser.uid,
        });
      } catch (err) {
        return jsonResponse({ error: `Internal Server Error: ${err.message}` }, 500);
      }
    }

    // Admin new order alert notification dispatch endpoint
    if (request.method === 'POST' && url.pathname === '/send-admin-new-order-notification') {
      try {
        // 1. Validate Authorization Header
        const authHeader = request.headers.get('Authorization') || '';
        if (!authHeader.startsWith('Bearer ')) {
          return jsonResponse({ error: 'Unauthorized: Missing or invalid Bearer token' }, 401);
        }

        const idToken = authHeader.substring(7).trim();

        // 2. Validate Firebase Project Configuration & Secrets
        const projectId = env.FIREBASE_PROJECT_ID;
        const clientEmail = env.FIREBASE_CLIENT_EMAIL;
        const privateKey = env.FIREBASE_PRIVATE_KEY;

        if (!projectId || !clientEmail || !privateKey) {
          return jsonResponse(
            { error: 'Server configuration error: Missing Firebase service credentials in Worker environment' },
            500
          );
        }

        // 3. Verify Caller is Authenticated in Firebase Project
        let authenticatedUser;
        try {
          authenticatedUser = await verifyFirebaseAuthToken(idToken, projectId, []);
        } catch (authErr) {
          return jsonResponse({ error: `Authentication failed: ${authErr.message}` }, 401);
        }

        // 4. Parse & Validate Payload
        let body;
        try {
          body = await request.json();
        } catch (_) {
          return jsonResponse({ error: 'Invalid JSON request body' }, 400);
        }

        const { orderId, orderNumber, totalAmount, customerName, customerId, tokens, eventId } = body;

        if (!orderId) {
          return jsonResponse({ error: 'Missing required field: orderId' }, 400);
        }

        const logicalEventId = eventId || `order_new_${orderId}`;

        // Idempotency check: ignore duplicate dispatches for the exact same new order alert
        if (!checkAndRecordDispatchIdempotency(logicalEventId)) {
          return jsonResponse({
            success: true,
            orderId,
            eventId: logicalEventId,
            message: 'Duplicate admin new order notification request ignored (idempotent)',
            delivered: 0,
            failed: 0,
            skipped: true,
            reason: 'duplicate_request_idempotent',
          });
        }

        // Validate Admin Tokens
        const tokenList = Array.isArray(tokens)
          ? tokens
          : (tokens ? [tokens] : []);

        if (tokenList.length === 0) {
          return jsonResponse({
            success: true,
            orderId,
            message: 'No admin FCM tokens registered; notification skipped.',
            delivered: 0,
            failed: 0,
          });
        }

        // 5. Send High-Priority FCM Alert to Admin Devices
        const result = await sendAdminNewOrderNotification({
          projectId,
          clientEmail,
          privateKey,
          tokens: tokenList,
          orderId,
          orderNumber: orderNumber || orderId.substring(0, 8),
          totalAmount: totalAmount || 0,
          customerName: customerName || 'Customer',
          customerId: customerId || '',
        });

        return jsonResponse({
          success: true,
          orderId,
          delivered: result.delivered,
          failed: result.failed,
          invalidTokens: result.invalidTokens,
          results: result.results,
          callerUid: authenticatedUser.uid,
        });
      } catch (err) {
        return jsonResponse({ error: `Internal Server Error: ${err.message}` }, 500);
      }
    }

    return jsonResponse({ error: 'Not Found' }, 404);
  },
};
