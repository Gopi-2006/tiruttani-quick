# Tiruttani Quick — Cloudflare Notification Worker (Zero-Cost FCM Push Backend)

This Cloudflare Worker provides a **100% free server-side FCM push notification dispatcher** for the Tiruttani Quick platform, allowing full FCM HTTP v1 push notifications on the **Firebase Spark (Free)** plan without requiring Blaze plan or paid Cloud Functions.

---

## 1. Prerequisites & Free Tier Limits

- **Cloudflare Account**: Free plan includes **100,000 requests per day** (plenty for ~200+ users).
- **Firebase Project**: `blinkit-grocery-c3f5d` on Spark tier.

---

## 2. Obtain Firebase Service Account Key (One-Time Setup)

1. Open the [Firebase Console](https://console.firebase.google.com/).
2. Select your project (**blinkit-grocery-c3f5d**).
3. Click the **Gear Icon ⚙️** (Project Settings) → **Service accounts** tab.
4. Click **Generate new private key** → confirm by clicking **Generate key**.
5. A JSON file will download. It contains:
   - `project_id`
   - `client_email`
   - `private_key`

---

## 3. Configure Cloudflare Worker Secrets

From this directory (`cloudflare-notification-worker/`), run:

```bash
# 1. Set Firebase Project ID
npx wrangler secret put FIREBASE_PROJECT_ID
# Enter: blinkit-grocery-c3f5d

# 2. Set Firebase Client Email
npx wrangler secret put FIREBASE_CLIENT_EMAIL
# Enter client_email from your service account JSON (e.g. firebase-adminsdk-xxxxx@blinkit-grocery-c3f5d.iam.gserviceaccount.com)

# 3. Set Firebase Private Key
npx wrangler secret put FIREBASE_PRIVATE_KEY
# Paste the entire "private_key" string from the JSON file, including -----BEGIN PRIVATE KEY----- and -----END PRIVATE KEY-----
```

---

## 4. Deploy the Worker

```bash
npx wrangler deploy
```

After deployment, Cloudflare will output your public Worker URL, for example:
`https://tiruttani-quick-notification-worker.<your-subdomain>.workers.dev`

---

## 5. API Reference

### `POST /send-order-notification`
**Headers:**
- `Authorization: Bearer <FIREBASE_ADMIN_AUTH_ID_TOKEN>`
- `Content-Type: application/json`

**Body:**
```json
{
  "orderId": "ORD_123456",
  "orderNumber": "TQ1001",
  "customerId": "CUSTOMER_FIREBASE_UID",
  "status": "accepted",
  "tokens": [
    "fcm_device_registration_token_1",
    "fcm_device_registration_token_2"
  ]
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "orderId": "ORD_123456",
  "statusKey": "accepted",
  "delivered": 1,
  "failed": 0,
  "invalidTokens": []
}
```
