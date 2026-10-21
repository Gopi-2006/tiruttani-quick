import http from 'node:http';
import { Database, runMigrations } from '@youpi/db';
import { startServer as startPaymentApi } from '../apps/payment-api/src/index.js';
import { CheckoutServer } from '../apps/checkout-portal/src/server.js';

async function main() {
  console.log('====================================================');
  console.log('🚀 YOUPI PG — GOOGLE CLOUD RUN PRODUCTION RUNNER');
  console.log('====================================================');

  const publicPort = Number(process.env.PORT || 8080);
  const internalApiPort = 6100;
  process.env.PAYMENT_API_PORT = String(internalApiPort);

  // 1. Database Initialization & Migration (PostgreSQL)
  console.log('[Runner] Initializing production database connection...');
  const db = new Database();
  console.log(`[Runner] Database connected. Dialect: ${db.dialect}`);

  console.log('[Runner] Applying database schema migrations...');
  const migrationRes = await Promise.resolve(runMigrations(db));
  console.log(`[Runner] Migrations applied. Default merchant: ${migrationRes?.defaultMerchant?.slug || 'ready'}`);

  const gatewayUrl = process.env.PUBLIC_GATEWAY_URL ||
    process.env.CHECKOUT_PORTAL_URL ||
    process.env.BASE_CHECKOUT_URL ||
    `http://0.0.0.0:${publicPort}`;

  // 2. Start Payment API on internal port 6100
  console.log(`[Runner] Starting Payment API on 127.0.0.1:${internalApiPort}...`);
  const paymentApi = await startPaymentApi(internalApiPort, db, {
    checkoutBaseUrl: gatewayUrl
  });
  console.log(`[Runner] Payment API listening internally on port ${paymentApi.port}`);

  // 3. Start Checkout Portal on Cloud Run's external $PORT
  console.log(`[Runner] Starting Unified Gateway & Checkout Portal on 0.0.0.0:${publicPort}...`);
  const checkoutServer = new CheckoutServer({
    apiBaseUrl: '' // relative base for client browser requests
  });

  const portalApp = checkoutServer.createServer();
  const portalInstance = await new Promise((resolve, reject) => {
    portalApp.once('error', reject);
    portalApp.listen(publicPort, '0.0.0.0', () => resolve(portalApp));
  });

  console.log(`[Runner] Unified Gateway successfully listening on external port ${publicPort}`);
  console.log('====================================================');
  console.log(`✔ Ready to accept traffic at http://0.0.0.0:${publicPort}`);
  console.log('====================================================');

  // Graceful shutdown
  const shutdown = async (signal) => {
    console.log(`\n[Runner] Received ${signal}. Gracefully shutting down...`);
    try {
      portalInstance.close();
      await paymentApi.close();
      if (typeof db.close === 'function') {
        await db.close();
      }
      console.log('[Runner] Shutdown complete.');
      process.exit(0);
    } catch (err) {
      console.error('[Runner] Error during shutdown:', err);
      process.exit(1);
    }
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

main().catch(err => {
  console.error('[FATAL] Cloud Run entrypoint failed to start:', err);
  process.exit(1);
});
