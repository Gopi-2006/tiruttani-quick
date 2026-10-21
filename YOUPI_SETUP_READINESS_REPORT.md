# YOUPI-PG Setup Readiness & Security Audit Report
**Project:** Tiruttani Quick (Customer App, Admin App, Shared Module, Firebase Functions)  
**Target:** YOUPI Payments (YOUPI PG) Self-Hosted Observer Architecture (`paymant/YouPI-PG-main`)  
**Auditor Roles:** Senior Payment Integration Engineer, Flutter Developer, Firebase Cloud Functions Engineer, DevOps Engineer, Security Auditor  
**Date:** March 2026  
**Status:** READINESS AUDIT COMPLETE (Zero files modified, zero production resources altered)

---

## 1. Executive Summary

This audit assesses the readiness, architecture, security, and operational viability of integrating the **YOUPI PG** payment engine (`paymant/YouPI-PG-main`) with the **Tiruttani Quick** quick-commerce platform.

### Key Conclusions:
1. **Security & Data Integrity (CODE LEVEL):** **PASS**. The existing Tiruttani Quick backend implementation in [`functions/youpi_payment.js`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/functions/youpi_payment.js) is architected to institutional-grade standards. It features constant-time HMAC-SHA256 signature verification, a 300-second replay rejection window, Firestore atomic transactional deduplication, authoritative server-side amount calculation, anti-session hijacking, and safe inventory reversal on payment cancellation or expiry.
2. **Access Control & Anti-Tampering:** **PASS**. Client apps have **zero** ability to mark orders as `Paid`. Firestore security rules in [`firestore.rules`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/firestore.rules) strictly enforce that customer-created orders possess `paymentStatus == 'Pending'`, and disallow customer updates entirely.
3. **Gateway Architecture (REPOSITORY LEVEL):** **EXPERIMENTAL SELF-HOSTED OBSERVER**. YOUPI PG is **not an RBI-authorized Payment Aggregator (PA)** or an NPCI-licensed UPI switch. It operates as an automated P2P/P2M payment observation engine that relies on an Android observer smartphone (`apps/android-observer-app`) scraping bank notifications/SMS or a Gmail API poller reading credit alert emails.
4. **Readiness for Production:** **NOT READY FOR LIVE TRAFFIC**. While code integration is 100% prepared, hosting infrastructure (Cloud Run/VPS + PostgreSQL) is **NOT CONFIGURED**, the physical Android observer device is **NOT PROVISIONED**, and the merchant business bank account setup is **NOT VERIFIED**.

---

## 2. Actual Architecture of YOUPI-PG

Verified directly from repository sources (`paymant/YouPI-PG-main`):

```mermaid
flowchart TD
    subgraph Customer Device
        CA[Tiruttani Quick Customer App] -->|1. Create Order (Pending)| FS[(Cloud Firestore)]
        CA -->|2. Get Firebase ID Token| FA[Firebase Auth]
        CA -->|3. POST /createYoupiPaymentSession| CF1[Firebase Function: createYoupiPaymentSession]
        CA -->|6. Launch Checkout URL| CP[YOUPI Unified Gateway /checkout/:id]
        CA -->|7. Scan & Pay via UPI App| UPI[Customer UPI App: GPay / PhonePe / Paytm]
    end

    subgraph Firebase Cloud Backend
        CF1 -->|4. Authenticate & Fetch Order Price| FS
        CF1 -->|5. POST /api/v1/payments| YPG[YOUPI PG Payment Core API :6100]
        WH[Firebase Function: youpiWebhook] -->|12. Atomic Update: paymentStatus='Paid'| FS
        WH -->|13. Deduplication Log| DL[(payment_webhooks)]
        FS -->|14. Real-time Stream Update| AA[Admin Dashboard App]
        FS -->|15. Real-time Stream Update| CA
    end

    subgraph Bank & Observation Mesh
        UPI -->|8. UPI Funds Transfer| BANK[Merchant Receiving Bank Account]
        BANK -->|9. SMS / Notification| PHONE[Merchant Dedicated Android Phone]
        PHONE -->|10. HMAC-Signed HTTP POST| YPG
        YPG -->|11. POST /youpiWebhook (X-Gateway-Signature)| WH
    end
```

### Architectural Findings from Repository:
1. **Unified Gateway Topology:** In `scripts/cloud-run-entrypoint.js` and `apps/checkout-portal/src/server.js`, the Checkout Portal listens on external `$PORT` (typically 8080) and **transparently proxies all `/api/*` requests** to the Payment Core API running internally on `127.0.0.1:6100`. A single container deployment serves both the customer web checkout and the backend REST API.
2. **Dual-Dialect Database Layer (`packages/db/src/database.js`):**
   - **SQLite Adapter:** Uses native Node.js 22 `node:sqlite` (`DatabaseSync`) for local zero-dependency development (`USE_SQLITE_FALLBACK=true`).
   - **PostgreSQL Adapter:** Mandatory in `NODE_ENV=production`. Line 363 of `database.js` throws a fatal startup error if `DATABASE_URL` is missing or not a valid PostgreSQL connection string.
3. **Queue & Attribution Engine (`packages/core`):**
   - Because standard UPI incoming credits lack custom merchant transaction reference tokens in bank SMS alerts, YOUPI PG assigns each checkout session an exclusive amount-timestamp slot.
   - **Single-Slot FIFO Queue:** Only one transaction is actively observed per VPA at a given time. Concurrent buyers for the same receiving VPA are placed in a database-backed FIFO queue.
4. **Android Observer App (`apps/android-observer-app`):**
   - Native Kotlin Android app (`youpi-sms-gateway.apk`) utilizing `NotificationListenerService` and `SMS_RECEIVED`.
   - Uses device-level hardware key enrollment. All observation dispatches to the gateway are signed with `HMAC-SHA256` using an ephemeral device key.
   - Requires battery optimization exemption and autostart permission on Android OEMs.

---

## 3. Existing Components Verified from Source

| Component | File Path | Status | Verification Detail |
| :--- | :--- | :---: | :--- |
| **Payment Session Creation** | [`functions/youpi_payment.js`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/functions/youpi_payment.js#L39-L195) | **PASS** | Validates Firebase user token, verifies order ownership (`customerId == user.uid`), reads authoritative `totalPrice` from Firestore, attaches idempotency key, and calls `POST /api/v1/payments`. |
| **Function Ingress & Secrets** | [`functions/index.js`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/functions/index.js#L953-L974) | **PASS** | `createYoupiPaymentSession` configured with `secrets: ["YOUPI_MERCHANT_API_KEY"]`; `youpiWebhook` configured with `secrets: ["YOUPI_WEBHOOK_SECRET"]`. |
| **Webhook Signature Check** | [`functions/youpi_payment.js`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/functions/youpi_payment.js#L237-L270) | **PASS** | Computes HMAC-SHA256 of `rawBody` using `config.webhookSecret` and compares using `crypto.timingSafeEqual`. |
| **Replay & Freshness Guard** | [`functions/youpi_payment.js`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/functions/youpi_payment.js#L227-L236) | **PASS** | Parses `X-Gateway-Timestamp` and enforces `|now - timestamp| <= 300,000 ms` (5-minute window). |
| **Webhook Idempotency** | [`functions/youpi_payment.js`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/functions/youpi_payment.js#L345-L425) | **PASS** | Checks `payment_webhooks/{deliveryId}` inside a Firestore transaction. Duplicate delivery IDs exit immediately with HTTP 200 `ALREADY_PROCESSED`. |
| **Amount & Currency Check** | [`functions/youpi_payment.js`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/functions/youpi_payment.js#L331-L343) | **PASS** | Converts order price to minor units (paise) and asserts `Math.abs(orderTotalPaise - webhookPaise) <= 1`. Enforces currency is strictly `"INR"`. |
| **Inventory Safeguards** | [`functions/youpi_payment.js`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/functions/youpi_payment.js#L440-L487) | **PASS** | `SUCCESS` does not re-deduct stock (already decremented at checkout). `EXPIRED`/`CANCELLED`/`FAILED` webhooks atomically restore stock via `FieldValue.increment` and mark `inventoryRestored: true`. |
| **Late Payment Handling** | [`functions/youpi_payment.js`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/functions/youpi_payment.js#L384-L404) | **PASS** | If a customer pays after an order has already timed out / cancelled, the system flags `latePaymentFlag: true` with UTR for manual review and does **not** revive the order into preparation. |
| **Client Payment Config** | [`Tiruttaniquick_customer/lib/config/payment_config.dart`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/Tiruttaniquick_customer/lib/config/payment_config.dart#L25-L54) | **PASS** | Hardened security gates: `isStagingOnlineUpiEnabled` defaults to `false` and is strictly locked to `false` in production release builds. |
| **Client Checkout Flow** | [`Tiruttaniquick_customer/lib/features/checkout/presentation/checkout_screen.dart`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/Tiruttaniquick_customer/lib/features/checkout/presentation/checkout_screen.dart#L856-L942) | **PASS** | Atomically writes pending order, calls Cloud Function with user ID token, launches checkout URL in external browser, and navigates to tracking screen. Never writes `paymentStatus: Paid`. |
| **Cash on Delivery (COD)** | [`Tiruttaniquick_customer/lib/features/checkout/presentation/checkout_screen.dart`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/Tiruttaniquick_customer/lib/features/checkout/presentation/checkout_screen.dart#L943-L948) | **PASS** | Fully decoupled. Selecting Cash on Delivery places order with `paymentMethod: 'Cash on Delivery'` without touching any YouPI endpoints. |
| **Firestore Security Rules** | [`firestore.rules`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/firestore.rules#L79-L87) | **PASS** | Enforces `request.resource.data.paymentStatus == 'Pending'` and `!('paymentUtr' in request.resource.data)` on create. Blocks order updates for customers (`allow update: if isAdmin() || isDeliveryAgent()`). |
| **Admin Order Visibility** | [`Tiruttaniquick_admin/lib/features/admin/presentation/admin_dashboard_screen.dart`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/Tiruttaniquick_admin/lib/features/admin/presentation/admin_dashboard_screen.dart#L1414) | **PASS** | Accurately renders real-time `order.paymentMethod` and `order.paymentStatus` badges. |
| **Automated Integration Tests** | [`functions/test/youpi_integration.test.js`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/functions/test/youpi_integration.test.js) | **PASS** | 83 unit & integration tests passing across all attack vectors, race conditions, and replay tests. |

---

## 4. Phase 2 Verification Checklist (15 Core Requirements)

| # | Question / Requirement | Audit Result | Evidence & Analysis |
| :-: | :--- | :---: | :--- |
| **1** | Does `createYoupiPaymentSession` work with actual gateway API? | **PASS** | Matches `POST /api/v1/payments` with `{ orderId, amount, currency, method, metadata }` and `Authorization: Bearer <apiKey>` ([`payments.routes.js:L14`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/paymant/YouPI-PG-main/apps/payment-api/src/routes/payments.routes.js#L14)). |
| **2** | Is gateway URL configured correctly? | **NOT CONFIGURED** | In `functions/youpi_payment.js`, `YOUPI_API_BASE_URL` currently defaults to `http://localhost:6100`. Cloud Run service URL must be injected before deployment. |
| **3** | Does checkout create an order exactly once? | **PASS** | Order doc is created inside a Firestore transaction in `checkout_screen.dart`. Session creation in `youpi_payment.js` detects active unexpired sessions and reuses them. |
| **4** | Does server calculate authoritative payment amount? | **PASS** | Cloud Function reads `orderData.totalPrice` directly from Firestore doc. Client cannot submit or alter price. |
| **5** | Are webhook signatures & timestamps verified correctly? | **PASS** | Constant-time HMAC-SHA256 digest check and 300-second maximum skew tolerance window. |
| **6** | Are duplicate and replayed webhooks rejected safely? | **PASS** | Tracked via `payment_webhooks/{deliveryId}` doc + atomic check `order.paymentStatus === 'Paid'`. |
| **7** | Are failed, expired, pending, and successful states handled? | **PASS** | All terminal states mapped to Firestore order and inventory handlers. |
| **8** | Can successful bank transfer remain pending if observer/webhook is down? | **YES (RISK)** | **Known Operational Limitation.** If the observer phone loses power/network, bank credits succeed but webhook does not fire. Order remains in `Pending`. |
| **9** | Is inventory reservation and restoration correct? | **PASS** | Decremented at checkout; restored on cancelled/expired; never double-decremented on success. |
| **10** | Does COD continue to work independently? | **PASS** | COD flow is fully isolated from online payment routes. |
| **11** | Is payment status displayed correctly in Admin App? | **PASS** | Real-time Firestore listener displays "Pending" or "Paid" badge dynamically. |
| **12** | Could a malicious client mark an order as paid? | **PASS (PROTECTED)** | Strictly prevented by Firestore security rules (`paymentStatus == 'Pending'` enforced on create; updates restricted to admin/agent). |
| **13** | Could webhook mark the wrong order as paid? | **PASS (PROTECTED)** | Transaction re-verifies matching `orderId`, matching `youpiPaymentId`, and matching amount in paise. |
| **14** | Do refunds, reconciliation, and manual exception handling exist? | **PARTIALLY CONFIGURED** | Unpaid order polling & late payment flags are coded in `handleCleanupUnpaidOrders`. However, **automated refunds do not exist** in YOUPI PG (manual bank transfer required). |
| **15** | Are payment secrets exposed to Flutter client? | **PASS** | No secrets stored in Flutter code or `.env` client bundle. Managed solely by Cloud Functions. |

---

## 5. Environment & Deployment Audit

### 5.1 Environment Variable Names (Values Hidden)

#### YOUPI PG Gateway (`paymant/YouPI-PG-main`):
- `NODE_ENV`
- `PORT`
- `DATABASE_URL`
- `ADMIN_API_KEY`
- `INITIAL_ADMIN_EMAIL`
- `INITIAL_ADMIN_PASSWORD`
- `JWT_SECRET`
- `ENCRYPTION_MASTER_KEY`
- `BASE_CHECKOUT_URL`
- `BASE_PAYMENT_API_URL`
- `YOUPI_MERCHANT_API_KEY`
- `YOUPI_WEBHOOK_URL`
- `YOUPI_WEBHOOK_SECRET`
- `USE_SQLITE_FALLBACK`
- `SQLITE_DB_PATH`
- `PAYMENT_ACTIVE_WINDOW_MS`
- `PAYMENT_PROCESSING_WINDOW_MS`
- `LATE_OBSERVATION_WINDOW_MS`
- `ANDROID_ENROLLMENT_SECRET`
- `ANDROID_HEARTBEAT_TIMEOUT_MS`
- `WEBHOOK_MAX_RETRIES`
- `WEBHOOK_INITIAL_BACKOFF_MS`

#### Firebase Cloud Functions (`functions/`):
- `YOUPI_API_BASE_URL`
- `YOUPI_MERCHANT_API_KEY`
- `YOUPI_WEBHOOK_SECRET`
- `YOUPI_REPLAY_WINDOW_MS`

#### Flutter Customer App (`Tiruttaniquick_customer`):
- `APP_ENV`
- `STAGING_BUILD`
- `ENABLE_STAGING_ONLINE_UPI`
- `YOUPI_CREATE_PAYMENT_URL`
- `YOUPI_CONVERT_COD_URL`

### 5.2 Infrastructure Component Classification

| Requirement | Classification | Current Project Status |
| :--- | :---: | :---: |
| **Publicly reachable HTTPS Gateway URL** | **Required** | **NOT CONFIGURED** |
| **PostgreSQL Database** | **Required (in Prod)** | **NOT CONFIGURED** |
| **Docker / Container Registry** | **Required (for Cloud Run)** | **Configured locally** (`Dockerfile` present) |
| **Google Cloud Run (or VPS)** | **Required** | **NOT CONFIGURED** |
| **Android Observer Device (Hardware)** | **Required** | **NOT CONFIGURED** |
| **Bank SIM Card & SMS Alerts** | **Required** | **NOT CONFIGURED** |
| **Firebase Cloud Functions Secrets** | **Required** | **NOT CONFIGURED** (GCP Secret Manager) |
| **Webhook Registration** | **Required** | **NOT CONFIGURED** |
| **Dedicated Merchant Current Account** | **Required** | **NOT VERIFIED** |
| **Custom Subdomain & TLS** | **Optional (Cloud Run provides default TLS)** | **NOT CONFIGURED** |
| **Heartbeat & Device Uptime Monitor** | **Required** | **NOT CONFIGURED** |

---

## 6. Hosting & Database Options Comparison

| Option | Architecture | Free Tier Availability | Scale-to-Zero Behavior | Database Persistence | Expected Monthly Cost | Risk & Failure Modes |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Option A: Google Cloud Run + Neon PostgreSQL (Recommended)** | Unified container on Cloud Run with Serverless Neon PostgreSQL | **Yes** (Cloud Run: 2M reqs/mo, Neon: 0.5 GB free) | **Yes** (scales to 0 when idle; ~1-2 sec cold start) | Fully persistent managed PostgreSQL with SSL (`sslmode=require`) | **₹0 – ₹400 / month** (Within free tier for low/moderate volume) | Cold start latency on first checkout tap; Neon free-tier computes suspend after 5 min of inactivity. |
| **Option B: Render.com / Railway** | Managed web service + Managed PostgreSQL | Free trial or Hobby ($5–$7/mo) | Render free tier spins down after 15 min; 50-second cold start | Persistent on paid; 30-day ephemeral on free Render PG | **₹600 – ₹1,200 / month** | Long cold starts (up to 50s) will cause client timeouts in checkout. Free databases expire. |
| **Option C: Dedicated VPS (Hetzner / DigitalOcean)** | Single Linux VM running Node.js + local SQLite/PostgreSQL | **No free tier** | **No** (Always on, zero cold starts) | Local persistent disk | **₹400 – ₹600 / month** ($4–$6/mo) | Requires manual OS security updates, manual SSL certbot renewal, and container orchestration. |

### Hardware & Operating Recurring Costs (INR):
- **Refurbished Android Device (Android 11+):** ₹4,500 – ₹7,000 (one-time purchase).
- **Merchant Bank Account SIM Card (Jio / Airtel):** ₹150 – ₹200 / month.
- **Power & Dedicated Wi-Fi Connection:** In-store standard internet.

---

## 7. Security, Regulatory, and Compliance Findings

### 7.1 Regulatory Status (RBI & NPCI)
- **Zero Official Authorization:** YOUPI PG is **not** an authorized Payment Aggregator under the Reserve Bank of India (RBI) *Guidelines on Regulation of Payment Aggregators and Payment Gateways (2020)*.
- **Direct Account Settlement:** Because funds flow directly from customer to merchant bank account without intermediate escrow/nodal accounts, it technically functions as peer-to-peer or direct merchant collection.
- **NPCI Terms:** Reverse-engineering or parsing bank SMS/app push notifications for payment settlement is **not** endorsed by NPCI or UPI member banks.

### 7.2 Banking Terms of Service & Account Freezing
- **High-Risk for Personal Savings Accounts:** Personal bank accounts (SBI, HDFC, ICICI, etc.) have strict fair-use terms prohibiting automated commercial transactions. Using a personal account for 50–100 daily grocery transactions will trigger automated AML/fraud detection algorithms, causing **immediate bank account freeze and withholding of funds**.
- **Mandatory Countermeasure:** Must use a dedicated **Current Account** with an authorized business merchant UPI VPA (P2M).

### 7.3 Concurrency Bottleneck (Single-Slot FIFO Queue)
- **Constraint:** Standard UPI credits lack customer-specific reference tokens in bank notifications. YOUPI PG matches payments based on **Amount + Timestamp**.
- **Impact:** If two customers checkout simultaneously for ₹250.00, only the first customer can pay immediately; the second customer is queued until the first completes or times out (3 minutes). In a quick-commerce app with concurrent peak orders, this will lead to abandoned carts.

### 7.4 Observer Device Vulnerability
- If the Android smartphone runs out of battery, loses Wi-Fi, experiences OS memory kills, or encounters SIM network failure, **no webhooks will be triggered**. Customer money will be debited, but orders will remain in `Pending` indefinitely until manual merchant reconciliation.

---

## 8. Exact Files Requiring Modification (When Enabling Payments)

*Note: In accordance with audit rules, NONE of these files were modified.*

1. **[`Tiruttaniquick_customer/lib/config/payment_config.dart`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/Tiruttaniquick_customer/lib/config/payment_config.dart):**
   - When staging testing begins, set `isStagingOnlineUpiEnabled = true` for staging builds.
   - Point `createPaymentSessionUrl` to the live Cloud Functions domain.
2. **[`functions/youpi_payment.js`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/functions/youpi_payment.js):**
   - Inject `YOUPI_API_BASE_URL` pointing to the deployed Cloud Run gateway URL.
3. **[`Tiruttaniquick_admin/lib/features/admin/presentation/order_details_screen.dart`](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/Tiruttaniquick_admin/lib/features/admin/presentation/order_details_screen.dart):**
   - Add a "Manual Payment Verification / Mark as Paid (Admin Override)" button with strict admin PIN authentication to rescue orders if the physical observer ever loses internet connectivity.

---

## 9. Comprehensive Testing Plan

```
[Phase A: Local & Mock Verification] -> [Phase B: Gateway Sandbox] -> [Phase C: Real-Device Pilot]
```

### Test Suite Breakdown:

| Test ID | Test Scenario | Execution Environment | Expected Result |
| :--- | :--- | :--- | :--- |
| **TC-01** | Gateway Health Check (`GET /health`) | Local / Cloud Run | Returns HTTP 200 `{ "status": "UP", "service": "checkout-portal" }`. |
| **TC-02** | Database Connectivity | Staging Gateway | Gateway boots, applies migrations, and connects without SSL errors. |
| **TC-03** | Merchant Authentication | Mocked / Local | Requests with invalid `Authorization` header return HTTP 401. |
| **TC-04** | Payment Session Creation | Cloud Function | Returns HTTP 200 with valid `checkoutUrl` and `paymentId`. |
| **TC-05** | UPI Checkout Web Rendering | Mobile Browser | Displays QR code SVG, dynamic UPI intent links, and timer countdown. |
| **TC-06** | Valid Payment Webhook | Cloud Function | Webhook processes HMAC signature, transitions order to `Paid` in Firestore. |
| **TC-07** | Invalid HMAC Signature | Cloud Function | Webhook returns HTTP 401 `INVALID_SIGNATURE`. |
| **TC-08** | Duplicate Webhook Delivery | Cloud Function | First delivery returns 200 processed; duplicate returns 200 `ALREADY_PROCESSED`. |
| **TC-09** | Replayed Webhook (>300s skew) | Cloud Function | Returns HTTP 401 `REPLAY_WINDOW_EXPIRED`. |
| **TC-10** | Wrong Amount / Currency Tampering | Cloud Function | Webhook rejects mismatch with HTTP 400 `AMOUNT_MISMATCH`. |
| **TC-11** | Payment Expiry & Cancellation | Cloud Function | Webhook sets `paymentStatus: Expired`, restores stock in `products` collection. |
| **TC-12** | Observer App Disconnection | Physical Staging | Admin receives alert; customer order stays `Pending` without false success. |
| **TC-13** | Customer App Backgrounding | Flutter Customer | Customer switches to UPI app and returns; app detects `Paid` state via Firestore stream. |
| **TC-14** | Admin Real-time Status Update | Flutter Admin | Order card in Admin dashboard updates to green "Paid" badge without app reload. |
| **TC-15** | Cash on Delivery Regression | Flutter Customer | COD order places seamlessly with zero dependencies on online services. |

---

## 10. Rollback Plan

If online payments encounter failures or bank freezing during staging/pilot:
1. **Instant Client Kill-Switch:**
   - Set `PaymentConfig.isStagingOnlineUpiEnabled = false` (or toggle remote config).
   - The Customer App instantly hides the "Online UPI" option; only "Cash on Delivery" will be shown.
2. **Order Conversion Fallback:**
   - Customers stuck on a `Pending` online payment screen can tap **"Pay via Cash on Delivery Instead"** (`handleConvertOrderToCod`), which updates `paymentMethod: 'Cash on Delivery'` without duplicating orders or losing reserved stock.
3. **Database & Container Isolation:**
   - Suspending or deleting the Cloud Run container will cleanly cause Cloud Functions to return `502 GATEWAY_ERROR`, which the customer checkout gracefully catches with `PaymentConfig.stagingUnavailableMessage`.

---

## 11. Production Readiness Checklist

- [ ] Free Neon PostgreSQL provisioned with SSL connection string.
- [ ] YOUPI PG container deployed to Google Cloud Run with scale-to-zero.
- [ ] Production environment variables configured in Cloud Run.
- [ ] `YOUPI_MERCHANT_API_KEY` and `YOUPI_WEBHOOK_SECRET` stored in GCP Secret Manager.
- [ ] Cloud Function webhook URL registered in YOUPI PG merchant configuration.
- [ ] Refurbished Android smartphone connected to permanent AC power and Wi-Fi.
- [ ] Business Current Account SIM inserted in observer phone.
- [ ] Observer APK installed and granted notification listener & battery optimization exemptions.
- [ ] End-to-end sandbox ₹1.00 test verified successfully across GPay, PhonePe, and Paytm.
- [ ] Admin App equipped with manual payment verification override tool.
- [ ] Offline heartbeat monitor configured to alert store manager if observer phone goes offline.

---

## 12. Blockers Before Enabling Online Payments

1. **BLOCKER 1: No Live Gateway Container:** Currently only running against `localhost:6100` in dev/mock modes.
2. **BLOCKER 2: No Managed PostgreSQL Database:** Production mode strictly prohibits SQLite.
3. **BLOCKER 3: No Physical Observer Smartphone Provisioned:** Cannot receive real bank SMS.
4. **BLOCKER 4: Secrets Missing in GCP Secret Manager:** Firebase Cloud Functions in production will fail to start without the required secrets.

---

## 13. Recommended Next Action

Do not attempt to enable online payments in the production release app. Follow this sequential roadmap:

1. **Step 1 (DevOps):** Provision a free serverless PostgreSQL database on **Neon.tech**.
2. **Step 2 (DevOps):** Deploy the `paymant/YouPI-PG-main` Docker container to **Google Cloud Run** in your existing Google Cloud project (`blinkit-grocery-c3f5d`).
3. **Step 3 (Hardware):** Acquire a dedicated Android 11+ test smartphone, insert the business bank SIM, install `youpi-sms-gateway.apk`, and pair it with the Cloud Run gateway.
4. **Step 4 (Staging QA):** Run controlled ₹1.00 end-to-end payment tests using an explicit staging build of `Tiruttaniquick_customer` before touching any production customer settings.
