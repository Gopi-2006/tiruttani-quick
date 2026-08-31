/**
 * Google OAuth2 & FCM HTTP v1 Dispatcher for Cloudflare Workers.
 * Uses Web Crypto API for RSA-SHA256 (RS256) JWT assertion signing.
 */

import { buildFcmV1Message, buildAdminNewOrderFcmMessage } from './templates.js';

// Cached OAuth2 Access Token in Cloudflare Worker memory
let cachedAccessToken = null;
let tokenExpiry = 0;

/**
 * Base64URL encoder helper
 */
function base64UrlEncode(strOrBytes) {
  let base64;
  if (typeof strOrBytes === 'string') {
    base64 = btoa(unescape(encodeURIComponent(strOrBytes)));
  } else {
    let binary = '';
    const bytes = new Uint8Array(strOrBytes);
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    base64 = btoa(binary);
  }
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * Imports PKCS#8 RSA private key into Web Crypto CryptoKey.
 */
async function importPrivateKey(pemKey) {
  // Normalize PEM string (handle escaped newlines from environment secrets)
  const cleanedPem = pemKey
    .replace(/\\n/g, '\n')
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');

  const binary = atob(cleanedPem);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }

  return await crypto.subtle.importKey(
    'pkcs8',
    bytes.buffer,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  );
}

/**
 * Generates an OAuth 2.0 Access Token using a Service Account RS256 JWT assertion.
 */
export async function getGoogleOAuth2AccessToken({ clientEmail, privateKey }) {
  const now = Math.floor(Date.now() / 1000);

  // Return cached token if valid (with 5-minute safety buffer)
  if (cachedAccessToken && now < tokenExpiry - 300) {
    return cachedAccessToken;
  }

  const header = {
    alg: 'RS256',
    typ: 'JWT',
  };

  const payload = {
    iss: clientEmail,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600, // 1 hour
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const unsignedToken = `${encodedHeader}.${encodedPayload}`;

  const cryptoKey = await importPrivateKey(privateKey);
  const signatureBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(unsignedToken)
  );

  const signature = base64UrlEncode(signatureBuffer);
  const assertionJwt = `${unsignedToken}.${signature}`;

  // Exchange assertion JWT for Google OAuth2 access token
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: assertionJwt,
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`OAuth2 token request failed (${response.status}): ${errorBody}`);
  }

  const data = await response.json();
  cachedAccessToken = data.access_token;
  tokenExpiry = now + (data.expires_in || 3600);

  return cachedAccessToken;
}

function safeToken(token) {
  if (!token || typeof token !== 'string') return '';
  return token.length > 8 ? `...${token.substring(token.length - 8)}` : token;
}

/**
 * Dispatches an FCM HTTP v1 push notification to one or multiple device registration tokens.
 *
 * @param {object} params
 * @param {string} params.projectId
 * @param {string} params.clientEmail
 * @param {string} params.privateKey
 * @param {string[]} params.tokens
 * @param {string} params.statusKey
 * @param {string} params.orderId
 * @param {string} params.orderNumber
 * @returns {Promise<{ delivered: number, failed: number, invalidTokens: string[], results: object[] }>}
 */
export async function sendFcmNotification({
  projectId,
  clientEmail,
  privateKey,
  tokens,
  statusKey,
  orderId,
  orderNumber,
  deliveryOtp,
  deliveryPersonName,
}) {
  if (!tokens || tokens.length === 0) {
    return { delivered: 0, failed: 0, invalidTokens: [], results: [] };
  }

  // Deduplicate tokens
  const uniqueTokens = Array.from(new Set(tokens.filter(Boolean)));
  if (uniqueTokens.length === 0) {
    return { delivered: 0, failed: 0, invalidTokens: [], results: [] };
  }

  const accessToken = await getGoogleOAuth2AccessToken({ clientEmail, privateKey });
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const results = [];
  let delivered = 0;
  let failed = 0;
  const invalidTokens = [];

  // Dispatch concurrently
  await Promise.all(
    uniqueTokens.map(async (token) => {
      const messageBody = buildFcmV1Message({
        token,
        statusKey,
        orderId,
        orderNumber,
        deliveryOtp,
        deliveryPersonName,
      });

      try {
        const res = await fetch(fcmUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify(messageBody),
        });

        if (res.ok) {
          delivered++;
          console.log(`[FCM Dispatch] type: "order_status", orderId: "${orderId}", role: "customer", targetTokens: ${uniqueTokens.length}, token: "${safeToken(token)}", status: ${res.status}, errorCode: "NONE"`);
          results.push({ token: safeToken(token), success: true });
        } else {
          failed++;
          const errData = await res.json().catch(() => ({}));
          const errorCode = errData?.error?.details?.[0]?.errorCode || errData?.error?.status || 'UNKNOWN_ERROR';

          console.warn(`[FCM Dispatch Error] type: "order_status", orderId: "${orderId}", role: "customer", targetTokens: ${uniqueTokens.length}, token: "${safeToken(token)}", status: ${res.status}, errorCode: "${errorCode}"`);

          // Check if token is invalid or unregistered
          if (
            errorCode === 'UNREGISTERED' ||
            errorCode === 'INVALID_ARGUMENT' ||
            res.status === 404
          ) {
            invalidTokens.push(token);
          }

          results.push({
            token: safeToken(token),
            success: false,
            status: res.status,
            error: errData?.error?.message || `HTTP ${res.status}`,
            errorCode,
          });
        }
      } catch (err) {
        failed++;
        console.error(`[FCM Network Error] type: "order_status", orderId: "${orderId}", token: "${safeToken(token)}", error: "${err.message}"`);
        results.push({
          token: safeToken(token),
          success: false,
          error: err.message,
        });
      }
    })
  );

  return {
    delivered,
    failed,
    invalidTokens,
    results,
  };
}

/**
 * Dispatches an FCM HTTP v1 push notification for an Admin New Order Alert.
 */
export async function sendAdminNewOrderNotification({
  projectId,
  clientEmail,
  privateKey,
  tokens,
  orderId,
  orderNumber,
  totalAmount,
  customerName,
  customerId,
}) {
  if (!tokens || tokens.length === 0) {
    return { delivered: 0, failed: 0, invalidTokens: [], results: [] };
  }

  const uniqueTokens = Array.from(new Set(tokens.filter(Boolean)));
  if (uniqueTokens.length === 0) {
    return { delivered: 0, failed: 0, invalidTokens: [], results: [] };
  }

  const accessToken = await getGoogleOAuth2AccessToken({ clientEmail, privateKey });
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const results = [];
  let delivered = 0;
  let failed = 0;
  const invalidTokens = [];

  await Promise.all(
    uniqueTokens.map(async (token) => {
      const messageBody = buildAdminNewOrderFcmMessage({
        token,
        orderId,
        orderNumber,
        totalAmount,
        customerName,
        customerId,
      });

      try {
        const res = await fetch(fcmUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify(messageBody),
        });

        if (res.ok) {
          delivered++;
          console.log(`[FCM Dispatch] type: "new_order", orderId: "${orderId}", role: "admin", targetTokens: ${uniqueTokens.length}, token: "${safeToken(token)}", status: ${res.status}, errorCode: "NONE"`);
          results.push({ token: safeToken(token), success: true });
        } else {
          failed++;
          const errData = await res.json().catch(() => ({}));
          const errorCode = errData?.error?.details?.[0]?.errorCode || errData?.error?.status || 'UNKNOWN_ERROR';

          console.warn(`[FCM Dispatch Error] type: "new_order", orderId: "${orderId}", role: "admin", targetTokens: ${uniqueTokens.length}, token: "${safeToken(token)}", status: ${res.status}, errorCode: "${errorCode}"`);

          if (
            errorCode === 'UNREGISTERED' ||
            errorCode === 'INVALID_ARGUMENT' ||
            res.status === 404
          ) {
            invalidTokens.push(token);
          }

          results.push({
            token: safeToken(token),
            success: false,
            status: res.status,
            error: errData?.error?.message || `HTTP ${res.status}`,
            errorCode,
          });
        }
      } catch (err) {
        failed++;
        console.error(`[FCM Network Error] type: "new_order", orderId: "${orderId}", token: "${safeToken(token)}", error: "${err.message}"`);
        results.push({
          token: safeToken(token),
          success: false,
          error: err.message,
        });
      }
    })
  );

  return {
    delivered,
    failed,
    invalidTokens,
    results,
  };
}

