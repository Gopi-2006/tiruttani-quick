# Multi-stage production Dockerfile for Google Cloud Run (Zero-additional-budget deployment)
FROM node:22-alpine AS base

WORKDIR /app

# Install curl for container health check
RUN apk add --no-cache curl

# Copy workspace package manifests for cached dependency installation
COPY package.json package-lock.json ./
COPY packages/common/package.json ./packages/common/
COPY packages/db/package.json ./packages/db/
COPY packages/core/package.json ./packages/core/
COPY packages/merchant-sdk/package.json ./packages/merchant-sdk/
COPY apps/payment-api/package.json ./apps/payment-api/
COPY apps/checkout-portal/package.json ./apps/checkout-portal/
COPY apps/merchant-admin/package.json ./apps/merchant-admin/
COPY apps/control-center/package.json ./apps/control-center/
COPY apps/payment-help/package.json ./apps/payment-help/
COPY apps/coin-wallet-store/package.json ./apps/coin-wallet-store/
COPY apps/sms-observer/package.json ./apps/sms-observer/
COPY apps/gmail-observer/package.json ./apps/gmail-observer/
COPY apps/android-observer-app/package.json ./apps/android-observer-app/

# Install production dependencies
RUN npm ci --omit=dev

# Copy application source code
COPY . .

# Set production defaults
ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080

# Healthcheck
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://127.0.0.1:${PORT}/health || exit 1

# Start unified gateway (Checkout Portal + Payment API)
CMD ["node", "scripts/cloud-run-entrypoint.js"]
