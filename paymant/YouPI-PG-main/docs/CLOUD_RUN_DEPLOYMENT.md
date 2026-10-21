# Google Cloud Run Zero-Budget Deployment Guide

## 1. Architecture Overview

YOUPI-PG is architected for zero-additional-budget production deployment by utilizing:
1. **Google Cloud Run (Free Tier)**:
   - 2,000,000 requests per month free.
   - 180,000 vCPU-seconds and 360,000 GiB-seconds free per month.
   - Scale-to-zero (`--min-instances=0`) when idle to ensure $0.00 base cost.
2. **Free Managed PostgreSQL (Neon.tech / Supabase)**:
   - High-performance, serverless PostgreSQL with connection pooling.
   - SSL/TLS encryption strictly enforced (`sslmode=require`).
   - Automated schema migrations run idempotently on container boot.
3. **Unified Single-Container Gateway Architecture**:
   - `scripts/cloud-run-entrypoint.js` boots both the Payment Core REST API (internal `127.0.0.1:6100`) and the Checkout Portal (`0.0.0.0:$PORT`) inside the same container.
   - All external ingress (`/checkout/:id`, `/youpi.js`, `/api/*`, `/health`) is served through Cloud Run's single public `$PORT` (typically `8080`).
   - Zero inter-container networking overhead and zero extra service costs.

---

## 2. Required Production Environment Variables

| Variable | Description | Example / Recommended Value |
| :--- | :--- | :--- |
| `NODE_ENV` | Operating environment | `production` *(Enforces PostgreSQL & secure auth)* |
| `DATABASE_URL` | PostgreSQL connection string | `postgres://user:pass@ep-xyz.neon.tech/neondb?sslmode=require` |
| `PORT` | Public container HTTP port | Provided dynamically by Cloud Run (`8080`) |
| `ADMIN_API_KEY` | Dedicated Administrative Secret | Random 32+ hex string (`openssl rand -hex 32`) |
| `INITIAL_ADMIN_PASSWORD` | Merchant Dashboard Password | Strong password (min 12 chars) |
| `JWT_SECRET` | Token Signing Secret | Random 64+ hex string (`openssl rand -hex 32`) |
| `BASE_CHECKOUT_URL` | Public Gateway URL | `https://youpi-gateway-xyz.run.app` |
| `BASE_PAYMENT_API_URL` | Public Gateway URL | `https://youpi-gateway-xyz.run.app` |

> [!IMPORTANT]
> The database adapter contains a production safety guard: when `NODE_ENV=production`, `DATABASE_URL` **must** be a valid PostgreSQL connection string starting with `postgres://` or `postgresql://`. Silent SQLite fallback is strictly prohibited in production mode.

---

## 3. Step-by-Step Deployment Instructions

### Step 1: Provision Free PostgreSQL Database
1. Create a free account at [Neon.tech](https://neon.tech) or [Supabase](https://supabase.com).
2. Create a new project (e.g. `youpi-pg-prod`).
3. Copy the pooled connection string (with `sslmode=require`).

### Step 2: Authenticate and Configure Google Cloud CLI
```bash
# Authenticate with Google Cloud
gcloud auth login

# Set your active project
gcloud config set project YOUR_PROJECT_ID

# Enable Cloud Run and Cloud Build APIs
gcloud services enable run.googleapis.com cloudbuild.googleapis.com
```

### Step 3: Build and Push Container Image
Run from the repository root:
```bash
gcloud builds submit --tag gcr.io/YOUR_PROJECT_ID/youpi-gateway:latest
```

### Step 4: Deploy to Cloud Run (Zero-Cost Configuration)
```bash
gcloud run deploy youpi-gateway \
  --image gcr.io/YOUR_PROJECT_ID/youpi-gateway:latest \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --min-instances 0 \
  --max-instances 2 \
  --memory 512Mi \
  --cpu 1 \
  --timeout 60 \
  --set-env-vars NODE_ENV=production \
  --set-env-vars DATABASE_URL="YOUR_NEON_POSTGRES_CONNECTION_STRING" \
  --set-env-vars ADMIN_API_KEY="YOUR_GENERATED_ADMIN_KEY" \
  --set-env-vars INITIAL_ADMIN_PASSWORD="YOUR_GENERATED_ADMIN_PASSWORD" \
  --set-env-vars JWT_SECRET="YOUR_GENERATED_JWT_SECRET"
```

### Step 5: Post-Deployment Verification
Once deployed, Cloud Run will print the service URL (e.g. `https://youpi-gateway-xyz-uc.a.run.app`).

1. **Verify Health Endpoint**:
   ```bash
   curl -i https://YOUR_SERVICE_URL/health
   # Expected response: HTTP/2 200 {"status":"UP","service":"checkout-portal"}
   ```

2. **Verify SDK Delivery**:
   ```bash
   curl -i https://YOUR_SERVICE_URL/youpi.js
   # Expected response: HTTP/2 200 (JavaScript SDK bundle)
   ```

3. **Verify REST API Proxy**:
   ```bash
   curl -i https://YOUR_SERVICE_URL/api/v1/health
   # Expected response: HTTP/2 200 {"status":"UP","service":"payment-api", ...}
   ```

---

## 4. Local Development vs. Production Execution

| Capability | Local Development (`YOUPI_MODE=localhost`) | Cloud Run (`NODE_ENV=production`) |
| :--- | :--- | :--- |
| **Database** | Node built-in SQLite (`data/youpi_pg.sqlite`) | PostgreSQL with connection pooling (`pg.Pool`) |
| **Migrations** | Automatically creates tables via `sqlite-schema.sql` | Automatically creates tables via `schema.sql` |
| **Concurrency** | SQLite WAL mode transaction locking | PostgreSQL `FOR UPDATE` row locks |
| **Port Binding** | Multi-process: API on 6100, Checkout on 7000 | Unified entrypoint on `$PORT` |
| **Test Execution**| Fully synchronous in-memory testing (`npm test`) | 100% test compatibility across all 33 test suites |
