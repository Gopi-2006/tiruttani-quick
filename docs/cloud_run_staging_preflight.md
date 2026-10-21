# Cloud Run Staging Preflight Audit Report: YouPI-PG

**Date:** October 20, 2026  
**Target:** `paymant/YouPI-PG-main` container deployment to Google Cloud Run  
**Secret Status:** `YOUPI_DATABASE_URL` created in Google Cloud Secret Manager  
**Scope:** Architectural preflight verification (no deployment, zero secret values exposed)

---

## 1. Exact Docker Image Build Command

The Docker build must be executed from the `paymant/YouPI-PG-main` root where `Dockerfile` resides.

### Option A: Direct Local Docker Build
```bash
cd "paymant/YouPI-PG-main"
docker build -t gcr.io/blinkit-grocery-c3f5d/youpi-gateway:staging -f Dockerfile .
```

### Option B: Google Cloud Build (Recommended for Cloud Run)
```bash
cd "paymant/YouPI-PG-main"
gcloud builds submit --tag gcr.io/blinkit-grocery-c3f5d/youpi-gateway:staging .
```
*(Or targeting Artifact Registry: `us-central1-docker.pkg.dev/blinkit-grocery-c3f5d/youpi-pg/youpi-gateway:staging`)*

**Dockerfile Verification Details:**
- Based on `node:22-alpine` ([Dockerfile#L2](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/paymant/YouPI-PG-main/Dockerfile#L2)).
- Installs `curl` for container health probes ([Dockerfile#L7](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/paymant/YouPI-PG-main/Dockerfile#L7)).
- Copies package manifests across workspaces and executes `npm ci --omit=dev`.
- Sets `PORT=8080` and `NODE_ENV=production`.
- Starts the unified runner: `CMD ["node", "scripts/cloud-run-entrypoint.js"]`.

---

## 2. Required Environment Variable NAMES for Staging

The following environment variable **names** must be defined for Cloud Run:

| Variable Name | Required / Optional | Purpose |
| :--- | :---: | :--- |
| `NODE_ENV` | **REQUIRED** | Set to `production` (enforces PostgreSQL and disables test/sqlite fallbacks). |
| `DATABASE_URL` | **REQUIRED** | Mapped from secret `YOUPI_DATABASE_URL:latest`. |
| `PORT` | **AUTOMATIC** | Provided dynamically by Cloud Run runtime (`8080`). |
| `YOUPI_MERCHANT_API_KEY` | **REQUIRED** | Merchant API key hash seeded into PostgreSQL `merchants` table on startup. |
| `COIN_STORE_WEBHOOK_URL` | **REQUIRED** | Webhook destination URL (`https://us-central1-blinkit-grocery-c3f5d.cloudfunctions.net/youpiWebhook`). |
| `COIN_STORE_WEBHOOK_SECRET` | **REQUIRED** | HMAC-SHA256 signing secret matching Firebase Cloud Function's `YOUPI_WEBHOOK_SECRET`. |
| `BASE_CHECKOUT_URL` | **REQUIRED** | Public HTTPS service URL of Cloud Run (e.g. `https://<service-url>/checkout`). |
| `BASE_PAYMENT_API_URL` | **REQUIRED** | Public HTTPS service URL of Cloud Run (e.g. `https://<service-url>`). |
| `ADMIN_API_KEY` | **OPTIONAL** | Dedicated admin key for control center & internal management routes. |
| `JWT_SECRET` | **OPTIONAL** | Secret used for customer/merchant token signing. |

---

## 3. How `DATABASE_URL` Is Read by the PostgreSQL Database Module

- **Source Location:** [packages/db/src/database.js](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/paymant/YouPI-PG-main/packages/db/src/database.js#L286-L300)
- **Ingestion Logic:**
  1. `PostgresDatabaseAdapter` reads the connection string strictly from `options.connectionString || process.env.DATABASE_URL`.
  2. Automatic SSL detection:
     ```javascript
     const isSslRequired = options.ssl !== undefined
       ? options.ssl
       : (process.env.DATABASE_SSL === 'true' || 
          connectionString.includes('sslmode=require') || 
          connectionString.includes('neon.tech') || 
          connectionString.includes('supabase.co'));
     ```
  3. Initializes a connection pool via `pg.Pool` with SSL rejection disabled (`rejectUnauthorized: false` for managed serverless PostgreSQL compatibility).
- **Production Safety Enforcer:** [packages/db/src/database.js#L363-L368](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/paymant/YouPI-PG-main/packages/db/src/database.js#L363-L368):
  If `NODE_ENV === 'production'` and `DATABASE_URL` is missing or does not start with `postgres://` or `postgresql://`, the adapter **immediately aborts container boot** with a fatal error:
  > `[FATAL] Production database configuration error: DATABASE_URL must be a valid PostgreSQL connection string. Silent SQLite fallback is strictly prohibited in production mode.`
- **Critical Secret Mapping Rule:**
  Because the secret in Secret Manager is named `YOUPI_DATABASE_URL` but the code reads `process.env.DATABASE_URL`, Cloud Run must mount it via:
  ```bash
  --set-secrets DATABASE_URL=YOUPI_DATABASE_URL:latest
  ```

---

## 4. How Database Migrations and Merchant Seeding Are Performed

- **Invocation:** [scripts/cloud-run-entrypoint.js#L20-L22](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/paymant/YouPI-PG-main/scripts/cloud-run-entrypoint.js#L20-L22)
  On container startup, before listening on any port, the runner invokes:
  ```javascript
  const migrationRes = await Promise.resolve(runMigrations(db));
  ```
- **Execution Mechanism in PostgreSQL:** [packages/db/src/migrate.js#L150-L158](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/paymant/YouPI-PG-main/packages/db/src/migrate.js#L150-L158)
  1. Reads `packages/db/src/schema.sql` (PostgreSQL DDL containing tables for `merchants`, `payment_receiving_accounts`, `payment_sessions`, `payment_observations`, `audit_logs`, `webhook_deliveries`, `customers`).
  2. Executes `db.exec(schemaSql)` against PostgreSQL (`CREATE TABLE IF NOT EXISTS`).
  3. Calls `seedDefaults(db)`:
     - Checks if a merchant exists in `merchants`.
     - If empty, creates `defaultMerchant` (`id: 00000000-0000-0000-0000-000000000001`, slug: `demo-store`).
     - Computes SHA-256 hash of `process.env.YOUPI_MERCHANT_API_KEY` and sets `apiKeyHash`.
     - Assigns `webhookUrl: process.env.COIN_STORE_WEBHOOK_URL`.
     - Assigns `webhookSecret: process.env.COIN_STORE_WEBHOOK_SECRET`.
     - Seeds default active UPI receiving account (`merchant@upi`).

---

## 5. Whether Cloud Run Entrypoint Starts Both Payment API and Checkout Portal Correctly

- **Verification:** **YES — VERIFIED VIA CODE INSPECTION**
- **Evidence in [scripts/cloud-run-entrypoint.js](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/paymant/YouPI-PG-main/scripts/cloud-run-entrypoint.js#L11-L44):**
  1. **Internal Payment API:** Starts on `127.0.0.1:6100` (`startPaymentApi(internalApiPort, db)`).
  2. **External Checkout Portal:** Starts on `0.0.0.0:$PORT` (`portalApp.listen(publicPort, '0.0.0.0')`).
  3. **Internal Proxy:** In [apps/checkout-portal/src/server.js#L149-L175](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/paymant/YouPI-PG-main/apps/checkout-portal/src/server.js#L149-L175), any request arriving at the public container on `/api/*` is transparently proxied to `127.0.0.1:6100`.
  4. Both the hosted checkout page (`/checkout/:id`), SDK (`/youpi.js`), and REST API endpoints (`/api/v1/payments`, `/api/v1/checkout/*`) are accessible through the single Cloud Run external port.

---

## 6. Health-Check URL and Expected Response

The container exposes two health endpoints:

### Primary Public Health Check (Used by Dockerfile & Cloud Run)
- **URL:** `GET /health` (Port 8080)
- **Handler:** [apps/checkout-portal/src/server.js#L142-L146](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/paymant/YouPI-PG-main/apps/checkout-portal/src/server.js#L142-L146)
- **Status Code:** `200 OK`
- **Response Headers:** `Content-Type: application/json`
- **Expected Body:**
  ```json
  {"status":"UP","service":"checkout-portal"}
  ```

### Payment Core API Health Check (Proxied Endpoint)
- **URL:** `GET /api/v1/health` (Port 8080)
- **Handler:** [apps/payment-api/src/index.js#L404-L413](file:///c:/Users/gopim/Desktop/Play%20console%20app/blinkit_grocery_flutter/paymant/YouPI-PG-main/apps/payment-api/src/index.js#L404-L413)
- **Status Code:** `200 OK`
- **Response Headers:** `Content-Type: application/json`
- **Expected Body:**
  ```json
  {
    "status": "UP",
    "service": "payment-api",
    "timestamp": "2026-10-20T...",
    "recoveryStats": { ... }
  }
  ```

---

## 7. Additional Secrets Required by the Service

Beyond `YOUPI_DATABASE_URL`, YouPI-PG requires two additional matching secrets to pair with Tiruttani Quick's Firebase Cloud Functions:

1. **`YOUPI_MERCHANT_API_KEY`:**
   - Must match the secret configured in Firebase Functions (`createYoupiPaymentSession`).
   - If omitted during container initial seeding, `apiKeyHash` in PostgreSQL is set to `null`, causing payment session creation requests to be rejected with `401 Unauthorized`.
2. **`YOUPI_WEBHOOK_SECRET` (passed as `COIN_STORE_WEBHOOK_SECRET`):**
   - Must match the secret configured in Firebase Functions (`youpiWebhook`).
   - If omitted during container initial seeding, YouPI-PG auto-generates a random string, causing Firebase's HMAC signature verification to fail (`401 INVALID_SIGNATURE`).

---

## 8. Correct Cloud Run Service Account Permissions for `YOUPI_DATABASE_URL`

Cloud Run accesses Secret Manager secrets using its configured runtime Service Account.

- **Default Compute Service Account:**  
  `<PROJECT_NUMBER>-compute@developer.gserviceaccount.com`
- **Required IAM Role:**  
  **`roles/secretmanager.secretAccessor`** ("Secret Manager Secret Accessor")

### Exact IAM Grant Command:
```bash
gcloud secrets add-iam-policy-binding YOUPI_DATABASE_URL \
  --project=blinkit-grocery-c3f5d \
  --member="serviceAccount:<PROJECT_NUMBER>-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```
*(If deploying with a dedicated service account e.g. `youpi-runner@blinkit-grocery-c3f5d.iam.gserviceaccount.com`, grant the role to that account instead).*

---

## 9. Missing Prerequisites for Safe Staging Deployment

Before deploying the Cloud Run container and testing online payments, the following 5 prerequisites must be completed:

1. **Secret Accessor IAM Binding:**  
   Ensure the Cloud Run service account has `roles/secretmanager.secretAccessor` granted on `YOUPI_DATABASE_URL`.
2. **PostgreSQL Network Reachability:**  
   Confirm the PostgreSQL database specified in `YOUPI_DATABASE_URL` permits connections from Google Cloud Run (public IP with SSL or via Cloud SQL VPC Connector).
3. **Container Secret / Environment Mapping:**  
   The Cloud Run deployment command must map `DATABASE_URL` from the Secret Manager secret:
   ```bash
   --set-secrets DATABASE_URL=YOUPI_DATABASE_URL:latest
   ```
4. **Merchant Seeding Variables:**  
   Pass `YOUPI_MERCHANT_API_KEY`, `COIN_STORE_WEBHOOK_SECRET`, and `COIN_STORE_WEBHOOK_URL` during initial deployment so the seeded merchant database record matches Firebase Cloud Functions.
5. **Firebase Cloud Functions Ingress:**  
   Deploy Firebase Function `youpiWebhook` with `roles/run.invoker` for `allUsers` so the Cloud Run webhook engine can deliver payment notifications.
