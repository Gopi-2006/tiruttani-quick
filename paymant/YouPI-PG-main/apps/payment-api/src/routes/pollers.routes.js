import crypto from 'node:crypto';
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { HttpServer } from '../server.js';
import { ObservationNormalizer, BankSmsParser, BankEmailParser, generateQrSvg } from '@youpi/core';
import { toRupeesString, toPaise, verifyHmac, resolveRuntimeUrls } from '@youpi/common';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Registers observation intake routes for SMS Gateway (Android Native Observer)
 * and Automated Observers (Gmail Direct API / Web Observers).
 * @param {HttpServer} server
 * @param {{
 *   attributionEngine: import('@youpi/core').AttributionEngine,
 *   db: import('@youpi/db').Database,
 *   auditRepo: import('@youpi/db').AuditLogRepository,
 *   sessionRepo?: import('@youpi/db').PaymentSessionRepository,
 *   accountRepo?: import('@youpi/db').ReceivingAccountRepository,
 *   merchantRepo?: import('@youpi/db').MerchantRepository
 * }} ctx
 */
export function registerPollerRoutes(server, ctx) {
  const enrollmentSecret = process.env.ANDROID_ENROLLMENT_SECRET || 'android_pairing_enrollment_secret_key_32_chars';

  // Secure Observer Master Vault Key for encrypting shared secrets at rest
  const rawMasterKey = process.env.OBSERVER_MASTER_KEY || process.env.ENCRYPTION_KEY || process.env.JWT_SECRET;
  if (!rawMasterKey && process.env.NODE_ENV === 'production') {
    throw new Error('FATAL: OBSERVER_MASTER_KEY or ENCRYPTION_KEY must be configured in production environment.');
  }
  const MASTER_VAULT_KEY = crypto.createHash('sha256').update(
    rawMasterKey || 'youpi_master_encryption_key_2026_dev_32'
  ).digest();

  function encryptObserverSecret(plainSecret) {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', MASTER_VAULT_KEY, iv);
    let encrypted = cipher.update(plainSecret, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    const tag = cipher.getAuthTag().toString('hex');
    return `enc:v1:${iv.toString('hex')}:${tag}:${encrypted}`;
  }

  function decryptObserverSecret(storedSecret) {
    if (!storedSecret || typeof storedSecret !== 'string') return '';
    if (!storedSecret.startsWith('enc:v1:')) {
      // Legacy unencrypted plaintext fallback for seamless backwards compatibility
      return storedSecret;
    }
    const parts = storedSecret.split(':');
    if (parts.length !== 5) return '';
    try {
      const iv = Buffer.from(parts[2], 'hex');
      const tag = Buffer.from(parts[3], 'hex');
      const ciphertext = parts[4];
      const decipher = crypto.createDecipheriv('aes-256-gcm', MASTER_VAULT_KEY, iv);
      decipher.setAuthTag(tag);
      let decrypted = decipher.update(ciphertext, 'hex', 'utf8');
      decrypted += decipher.final('utf8');
      return decrypted;
    } catch {
      return '';
    }
  }

  function safeCompareTokens(a, b) {
    if (typeof a !== 'string' || typeof b !== 'string') return false;
    const bufA = Buffer.from(a, 'utf8');
    const bufB = Buffer.from(b, 'utf8');
    if (bufA.length !== bufB.length) return false;
    return crypto.timingSafeEqual(bufA, bufB);
  }

  // Sliding replay attack protection cache backed by SQLite/PostgreSQL persistent storage
  const seenSignatures = new Map();
  async function checkAndRecordReplay(sig, expiryMs = 60000, source = 'SMS') {
    const now = Date.now();
    for (const [s, exp] of seenSignatures) {
      if (exp <= now) seenSignatures.delete(s);
    }
    if (seenSignatures.has(sig)) {
      return false; // Replay detected in memory
    }

    if (ctx.db && typeof ctx.db.execute === 'function') {
      try {
        if (Math.random() < 0.1) {
          await ctx.db.execute('DELETE FROM observer_replay_signatures WHERE expires_at < ?', [now]);
        }
        const existing = await ctx.db.queryOne('SELECT signature FROM observer_replay_signatures WHERE signature = ?', [sig]);
        if (existing) {
          seenSignatures.set(sig, now + expiryMs);
          return false; // Replay detected across process restarts
        }
        await ctx.db.execute(
          'INSERT INTO observer_replay_signatures (signature, source, expires_at) VALUES (?, ?, ?)',
          [sig, source, now + expiryMs]
        );
      } catch (err) {
        if (err.message && (err.message.includes('UNIQUE') || err.message.includes('duplicate key'))) {
          seenSignatures.set(sig, now + expiryMs);
          return false;
        }
      }
    }

    seenSignatures.set(sig, now + expiryMs);
    return true;
  }

  // GET /api/v1/pollers/active-window (Enables deep intelligent DOM scanning for active amounts and dual-layer verification)
  server.get('/api/v1/pollers/active-window', async (req, res) => {
    const isPg = ctx.db && ctx.db.dialect === 'postgres';
    const rawSessions = await ctx.db.query(`
      SELECT id, order_id, receiving_account_id, amount_paise, status, verification_level, expires_at, processing_expires_at, completed_at
      FROM payment_sessions
      WHERE status IN ('ACTIVE', 'PROCESSING')
         OR (status = 'SUCCESS' AND verification_level < 2 AND completed_at >= ${isPg ? "(NOW() - INTERVAL '60 seconds')" : "datetime('now', '-60 seconds')"})
      ORDER BY created_at DESC
    `);

    const activeSessions = Array.isArray(rawSessions) ? rawSessions : (rawSessions?.rows || []);
    const sessions = activeSessions.map(s => ({
      id: s.id,
      orderId: s.order_id,
      receivingAccountId: s.receiving_account_id,
      amount: toRupeesString(s.amount_paise),
      amountPaise: Number(s.amount_paise),
      status: s.status,
      verificationLevel: s.verification_level || 0,
      expiresAt: s.expires_at,
      processingExpiresAt: s.processing_expires_at
    }));

    HttpServer.json(res, 200, {
      hasActivePayment: sessions.length > 0,
      sessions
    });
  });

  // POST /api/v1/pollers/events (Universal Observation Ingest for Gmail / SMS 2-Layer Observers)
  server.post('/api/v1/pollers/events', async (req, res) => {
    // Authenticate universal poller ingestion if configured or in production
    const pollerSecret = process.env.OBSERVER_SECRET;
    if (pollerSecret || process.env.NODE_ENV === 'production') {
      const authHdr = req.headers['x-observer-secret'] || (req.headers['authorization']?.startsWith('Bearer ') ? req.headers['authorization'].slice(7).trim() : null);
      const expectedSecret = pollerSecret || process.env.JWT_SECRET;
      if (!authHdr || !safeCompareTokens(authHdr, expectedSecret)) {
        HttpServer.json(res, 401, { error: 'Unauthorized: Valid observer credentials required.' });
        return;
      }
    }

    const body = await HttpServer.parseBody(req);

    if (!body.receivingAccountId || !body.source) {
      HttpServer.json(res, 400, { error: 'Missing required fields: receivingAccountId and source.' });
      return;
    }

    // Evaluate through Security & Fraud Verification Pipeline
    const rawText = body.rawText || body.text || body.message || body.sms || body.body || (typeof body.rawPayload === 'string' ? body.rawPayload : (body.rawPayload?.text || body.rawPayload?.body));
    const sender = body.sender || body.from || body.rawPayload?.sender || body.rawPayload?.from;

    if (ctx.pipeline && rawText) {
      const pipeResult = await ctx.pipeline.process({
        source: body.source,
        rawText,
        sender,
        receivingAccountId: body.receivingAccountId,
        paymentSessionId: body.paymentSessionId,
        authResults: body.authResults || body.rawPayload?.authResults,
        rawPayload: body.rawPayload || body,
        isTest: Boolean(body.isTest),
        testModeActive: Boolean(body.testModeActive)
      });

      if (pipeResult.status === 'REJECTED') {
        if (pipeResult.failingCondition === 'FRAUDULENT_PAYMENT_INJECTION') {
          HttpServer.json(res, 403, {
            accepted: false,
            status: 'REJECTED',
            reason: 'FRAUDULENT_PAYMENT_INJECTION',
            threatDetected: true,
            banned: true,
            error: 'FRAUDULENT_PAYMENT_INJECTION: Positive identification of fake payment message. Customer account banned and session terminated.'
          });
          return;
        }

        if (pipeResult.failingCondition === 'FORGED_EMAIL_AUTHENTICATION_FAILED') {
          HttpServer.json(res, 403, {
            accepted: false,
            status: 'REJECTED',
            reason: 'FORGED_EMAIL_AUTHENTICATION_FAILED',
            threatDetected: true,
            error: pipeResult.failingReason || 'Email provenance verification failed (DKIM/SPF failure).'
          });
          return;
        }

        if (pipeResult.failingCondition === 'AMBIGUOUS_REJECT') {
          HttpServer.json(res, 422, {
            accepted: false,
            status: 'REJECTED',
            reason: 'AMBIGUOUS_REJECT',
            error: pipeResult.failingReason || 'Ambiguous payment attribution: Multiple sessions match amount. Manual review required.'
          });
          return;
        }
      }

      if (pipeResult.status === 'VERIFIED') {
        HttpServer.json(res, 200, {
          accepted: true,
          observationId: pipeResult.messageId || pipeResult.stages?.stage6?.details?.observationId,
          attribution: pipeResult.stages?.stage6?.details || pipeResult,
          pipeline: pipeResult
        });
        return;
      }
    }

    try {
      let amountPaise = body.amountPaise ? BigInt(body.amountPaise) : undefined;
      let bankRef = body.bankReferenceNumber || body.utr;
      let senderVpa = body.senderVpa;
      const observedAt = body.observedAt ? new Date(body.observedAt) : new Date();

      if (rawText && (!amountPaise || !bankRef)) {
        const isEmail = body.source === 'GMAIL' || body.source === 'EMAIL';
        const parsed = isEmail
          ? BankEmailParser.parse({ subject: body.subject || body.rawPayload?.subject || '', body: rawText, date: observedAt, from: sender })
          : BankSmsParser.parse({ text: rawText, sender, timestamp: observedAt });
        if (parsed) {
          if (!amountPaise) amountPaise = parsed.amountPaise;
          if (!bankRef && parsed.bankReferenceNumber) bankRef = parsed.bankReferenceNumber;
          if (!senderVpa && parsed.senderVpa) senderVpa = parsed.senderVpa;
        }
      }

      const normalized = ObservationNormalizer.normalize({
        source: body.source,
        receivingAccountId: body.receivingAccountId,
        rawPayload: body.rawPayload || body,
        amountPaise,
        amount: body.amount || (amountPaise ? (Number(amountPaise) / 100).toFixed(2) : undefined),
        observedAt,
        senderVpa,
        bankReferenceNumber: bankRef
      });

      const result = await ctx.attributionEngine.processObservation(normalized);

      HttpServer.json(res, 200, {
        accepted: true,
        observationId: result.observationId,
        attribution: result
      });
    } catch (err) {
      console.error('[Poller Ingest Error]:', err.message);
      HttpServer.json(res, 400, { error: err.message });
    }
  });

  // --- ANDROID SMS GATEWAY PAIRING HANDLER ---
  const handleAndroidPair = async (req, res) => {
    const body = await HttpServer.parseBody(req);
    const token = body.enrollmentToken || body.token;
    const merchantId = body.merchantId || '00000000-0000-0000-0000-000000000001';
    const deviceName = body.deviceName || 'Android SMS Gateway';
    const deviceModel = body.deviceModel || 'Android Device';

    // Fail safely if enrollment secret is unconfigured in production
    const configuredSecret = process.env.ANDROID_ENROLLMENT_SECRET;
    if (!configuredSecret && process.env.NODE_ENV === 'production') {
      HttpServer.json(res, 500, { error: 'Device pairing enrollment is not configured on this server.' });
      return;
    }

    const expectedSecret = configuredSecret || enrollmentSecret;
    // Hardcoded pairing token ('youpi_sms_pair_token_secure') and merchant ID slices completely removed
    if (!token || !safeCompareTokens(token, expectedSecret)) {
      HttpServer.json(res, 401, { error: 'Invalid or expired device pairing enrollment token.' });
      return;
    }

    if (body.expiresAt && Date.now() > Number(body.expiresAt)) {
      HttpServer.json(res, 400, { error: 'PAIRING QR EXPIRED' });
      return;
    }

    if (body.version && body.version !== 'v1') {
      HttpServer.json(res, 400, { error: 'INVALID YOUPI PAIRING QR' });
      return;
    }

    const deviceId = crypto.randomUUID();
    const signingKey = crypto.randomBytes(32).toString('hex');
    const encryptedKey = encryptObserverSecret(signingKey);
    const nowIso = new Date().toISOString();

    try {
      await ctx.db.execute(`
        INSERT INTO android_devices (id, merchant_id, device_name, device_model, signing_key_hash, is_active, last_heartbeat_at, created_at)
        VALUES (?, ?, ?, ?, ?, true, ?, ?)
      `, [deviceId, merchantId, deviceName, deviceModel, encryptedKey, nowIso, nowIso]);

      if (ctx.auditRepo) {
        ctx.auditRepo.log({
          merchantId,
          entityType: 'ANDROID_DEVICE',
          entityId: deviceId,
          action: 'SMS_GATEWAY_DEVICE_PAIRED',
          actorType: 'ADMIN',
          details: { deviceName, deviceModel }
        });
      }

      HttpServer.json(res, 200, {
        paired: true,
        deviceId,
        signingKey,
        merchantId,
        message: 'Android SMS Gateway paired successfully.'
      });
    } catch (err) {
      HttpServer.json(res, 500, { error: `Failed to register Android device: ${err.message}` });
    }
  };

  server.post('/api/v1/pollers/android/pair', handleAndroidPair);
  server.post('/api/v1/observers/sms/pair', handleAndroidPair);

  // --- ANDROID SMS GATEWAY OBSERVATION INGESTION ---
  const handleAndroidSmsEvents = async (req, res) => {
    const rawBodyText = await new Promise(resolve => {
      let data = '';
      req.on('data', chunk => { data += chunk; });
      req.on('end', () => resolve(data));
    });

    let body = {};
    try {
      body = JSON.parse(rawBodyText);
    } catch {
      HttpServer.json(res, 400, { error: 'Invalid JSON payload.' });
      return;
    }

    const deviceId = req.headers['x-device-id'] || body.deviceId;
    if (!deviceId) {
      HttpServer.json(res, 400, { error: 'Missing required X-Device-Id header or deviceId.' });
      return;
    }

    // Verify registered device
    const device = await ctx.db.queryOne('SELECT * FROM android_devices WHERE id = ? AND is_active = true', [deviceId]);
    if (!device) {
      HttpServer.json(res, 403, { error: 'Device not authorized or inactive.' });
      return;
    }

    // Verify HMAC Signature & Replay Drift Protection - STRICTLY MANDATORY
    const timestampStr = req.headers['x-timestamp'];
    const signature = req.headers['x-signature'];

    if (!timestampStr || !signature) {
      HttpServer.json(res, 401, { error: 'Missing required cryptographic authentication headers (X-Signature, X-Timestamp).' });
      return;
    }

    if (!device.signing_key_hash) {
      HttpServer.json(res, 401, { error: 'Device has no configured signing key.' });
      return;
    }

    const ts = Number(timestampStr);
    const now = Date.now();
    if (isNaN(ts) || Math.abs(now - ts) > 60000) {
      HttpServer.json(res, 401, { error: 'Timestamp drift exceeded validity window (replay protection triggered).' });
      return;
    }

    if (!(await checkAndRecordReplay(signature))) {
      HttpServer.json(res, 401, { error: 'Replayed observer event detected. Signature has already been processed.' });
      return;
    }

    const sigPayload = `${rawBodyText}:${timestampStr}`;
    const signingKey = decryptObserverSecret(device.signing_key_hash);
    const isValid = verifyHmac(sigPayload, signingKey, signature);
    if (!isValid) {
      HttpServer.json(res, 401, { error: 'Invalid cryptographic HMAC signature.' });
      return;
    }

    // Resolve Receiving Account for this merchant
    let receivingAccountId = body.receivingAccountId;
    if (!receivingAccountId) {
      const activeAccount = ctx.accountRepo
        ? await ctx.accountRepo.findActiveForMerchant(device.merchant_id)
        : await ctx.db.queryOne('SELECT id FROM payment_receiving_accounts WHERE merchant_id = ? AND is_active = true LIMIT 1', [device.merchant_id]);
      receivingAccountId = activeAccount?.id || '00000000-0000-0000-0000-000000000002';
    }

    // Extract amount and details: either pre-parsed or from raw bank SMS
    let amountPaise = body.amountPaise ? BigInt(body.amountPaise) : undefined;
    let bankRef = body.bankReferenceNumber || body.utr;
    let senderVpa = body.senderVpa;
    let observedAt = body.observedAt ? new Date(body.observedAt) : new Date();

    // Check for raw SMS text inside body or rawNotification
    const rawText = body.body || body.sms || body.rawSms || body.message || body.text || body.rawNotification?.text;
    if (rawText && (!amountPaise || !bankRef)) {
      const parsedSms = BankSmsParser.parse({
        text: rawText,
        sender: body.sender || body.rawNotification?.package,
        timestamp: observedAt
      });

      if (parsedSms) {
        if (!amountPaise) amountPaise = parsedSms.amountPaise;
        if (!bankRef && parsedSms.bankReferenceNumber) bankRef = parsedSms.bankReferenceNumber;
        if (!senderVpa && parsedSms.senderVpa) senderVpa = parsedSms.senderVpa;
      }
    }

    if (!amountPaise && body.amount) {
      try {
        amountPaise = toPaise(body.amount);
      } catch {}
    }

    // Evaluate through Security & Fraud Verification Pipeline for Android Ingest
    if (ctx.pipeline && rawText) {
      const pipeResult = ctx.pipeline.process({
        source: 'SMS',
        rawText,
        sender: body.sender || req.headers['x-sender'],
        receivingAccountId,
        paymentSessionId: body.paymentSessionId,
        isTest: Boolean(body.isTest),
        deviceInfo: device ? `${device.device_name} (${device.device_model})` : 'Android SMS Gateway'
      });

      if (pipeResult.status === 'REJECTED' && pipeResult.failingCondition === 'FRAUDULENT_PAYMENT_INJECTION') {
        HttpServer.json(res, 403, {
          accepted: false,
          status: 'REJECTED',
          reason: 'FRAUDULENT_PAYMENT_INJECTION',
          threatDetected: true,
          banned: true,
          error: 'FRAUDULENT_PAYMENT_INJECTION: Fake SMS detected. Associated customer identity banned and session terminated.'
        });
        return;
      }

      if (pipeResult.status === 'VERIFIED') {
        await ctx.db.execute("UPDATE android_devices SET last_observation_at = ? WHERE id = ?", [new Date().toISOString(), deviceId]);
        HttpServer.json(res, 200, {
          accepted: true,
          observationId: pipeResult.messageId || pipeResult.stages?.stage6?.details?.observationId,
          attribution: pipeResult.stages?.stage6?.details || pipeResult,
          pipeline: pipeResult
        });
        return;
      }
    }

    // Transport Only Contract (Part D): The Android observer forwards all raw SMS.
    // If no monetary amount is extracted (e.g. personal, promotional, non-bank SMS),
    // update observation timestamp on device and return 200 PROCESSED_NON_BANK.
    if (!amountPaise) {
      await ctx.db.execute("UPDATE android_devices SET last_observation_at = ? WHERE id = ?", [new Date().toISOString(), deviceId]);
      HttpServer.json(res, 200, {
        accepted: true,
        status: 'PROCESSED_NON_BANK',
        bankMatch: false,
        message: 'Raw SMS observation ingested and evaluated by server pipeline.'
      });
      return;
    }

    try {
      const normalized = ObservationNormalizer.normalize({
        source: 'ANDROID_OBSERVER', // Maps to Android SMS Observer source in system enums
        receivingAccountId,
        rawPayload: body,
        amountPaise,
        amount: body.amount || (Number(amountPaise) / 100).toFixed(2),
        observedAt,
        senderVpa,
        bankReferenceNumber: bankRef
      });

      const result = await ctx.attributionEngine.processObservation(normalized);

      // Update device last observation timestamp
      await ctx.db.execute('UPDATE android_devices SET last_observation_at = ? WHERE id = ?', [new Date().toISOString(), deviceId]);

      HttpServer.json(res, 200, {
        accepted: true,
        observationId: result.observationId,
        attribution: result
      });
    } catch (err) {
      console.error('[Android SMS Ingest Error]:', err.message);
      HttpServer.json(res, 400, { error: err.message });
    }
  };

  server.post('/api/v1/pollers/android/events', handleAndroidSmsEvents);
  server.post('/api/v1/observers/sms', handleAndroidSmsEvents);
  server.post('/api/v1/sms-gateway/ingest', handleAndroidSmsEvents);

  // --- ANDROID HEARTBEAT HANDLER ---
  const handleAndroidHeartbeat = async (req, res) => {
    const body = await HttpServer.parseBody(req);
    const deviceId = req.headers['x-device-id'] || body.deviceId;

    if (deviceId) {
      await ctx.db.execute('UPDATE android_devices SET last_heartbeat_at = ? WHERE id = ?', [new Date().toISOString(), deviceId]);
    }

    HttpServer.json(res, 200, {
      status: 'HEARTBEAT_ACK',
      timestamp: Date.now()
    });
  };

  server.post('/api/v1/pollers/android/heartbeat', handleAndroidHeartbeat);
  server.post('/api/v1/pollers/heartbeat', handleAndroidHeartbeat);
  server.post('/api/v1/observers/heartbeat', handleAndroidHeartbeat);

  function resolveReachableApiUrl(req, runtimeUrl) {
    if (runtimeUrl && !runtimeUrl.includes('localhost') && !runtimeUrl.includes('127.0.0.1')) {
      return runtimeUrl;
    }
    const hostHeader = (req.headers && (req.headers['x-forwarded-host'] || req.headers['host'])) || '';
    const hostWithoutPort = hostHeader.split(':')[0];
    if (hostWithoutPort && hostWithoutPort !== 'localhost' && hostWithoutPort !== '127.0.0.1' && !hostWithoutPort.includes('::')) {
      return `http://${hostWithoutPort}:6100`;
    }
    try {
      const ifaces = os.networkInterfaces();
      for (const name of Object.keys(ifaces)) {
        for (const iface of ifaces[name]) {
          if (iface.family === 'IPv4' && !iface.internal) {
            return `http://${iface.address}:6100`;
          }
        }
      }
    } catch {}
    return 'http://192.168.1.18:6100';
  }

  // --- MERCHANT ADMIN: SMS GATEWAY PAIRING QR CODE & STATUS ---
  server.get('/api/v1/admin/sms-gateway/pair-qr', async (req, res) => {
    let merchant = req.query.merchantId ? (ctx.merchantRepo ? await ctx.merchantRepo.findById(req.query.merchantId) : null) : null;
    if (!merchant && ctx.merchantRepo) {
      merchant = ctx.merchantRepo.getDefault
        ? await ctx.merchantRepo.getDefault()
        : ((await ctx.merchantRepo.findById('00000000-0000-0000-0000-000000000001')) || ((await ctx.merchantRepo.findAll()) || [])[0]);
    }
    const merchantId = merchant ? merchant.id : (req.query.merchantId || '00000000-0000-0000-0000-000000000001');

    // Canonical runtime URL derivation (Part C2)
    const runtime = resolveRuntimeUrls(merchant?.branding || {});
    const reachableUrl = resolveReachableApiUrl(req, runtime.apiUrl);
    const baseUrl = reachableUrl;
    const token = enrollmentSecret;
    const sessionId = crypto.randomUUID();
    const expiresAt = Date.now() + (7 * 24 * 60 * 60 * 1000); // 7 days

    const pairingPayloadObj = {
      version: 'v1',
      type: 'YOUPI_SMS_GATEWAY_PAIR',
      serverUrl: baseUrl,
      gatewayUrl: baseUrl,
      apiBaseUrl: baseUrl,
      sessionId,
      token,
      enrollmentToken: token,
      merchantId,
      createdAt: Date.now(),
      expiresAt
    };

    const pairingPayload = JSON.stringify(pairingPayloadObj);
    const qrSvg = generateQrSvg(pairingPayload, 260);

    const rawDevices = await ctx.db.query(`
      SELECT id, device_name, device_model, is_active, last_heartbeat_at, last_observation_at, created_at
      FROM android_devices
      WHERE merchant_id = ? OR merchant_id = '00000000-0000-0000-0000-000000000001'
      ORDER BY created_at DESC
    `, [merchantId]);

    const rowsList = Array.isArray(rawDevices) ? rawDevices : (rawDevices?.rows || []);
    const devices = rowsList.map(d => ({
      id: d.id,
      deviceId: d.id,
      deviceName: d.device_name || d.device_model || 'Android Observer',
      device_name: d.device_name || d.device_model || 'Android Observer',
      deviceModel: d.device_model,
      device_model: d.device_model,
      isActive: Boolean(d.is_active),
      is_active: d.is_active,
      lastHeartbeatAt: d.last_heartbeat_at,
      last_heartbeat_at: d.last_heartbeat_at,
      lastObservationAt: d.last_observation_at,
      last_observation_at: d.last_observation_at,
      createdAt: d.created_at,
      created_at: d.created_at,
      pairedAt: d.created_at
    }));

    HttpServer.json(res, 200, {
      qrSvg,
      pairingQrSvg: qrSvg,
      pairingPayload,
      payload: pairingPayloadObj,
      sessionId,
      expiresAt,
      version: 'v1',
      token,
      enrollmentToken: token,
      gatewayUrl: baseUrl,
      serverUrl: baseUrl,
      devices
    });
  });

  // GET /api/v1/admin/sms-gateway/devices
  server.get('/api/v1/admin/sms-gateway/devices', async (req, res) => {
    let merchant = req.query.merchantId ? (ctx.merchantRepo ? ctx.merchantRepo.findById(req.query.merchantId) : null) : null;
    if (!merchant && ctx.merchantRepo) merchant = ctx.merchantRepo.getDefault ? ctx.merchantRepo.getDefault() : (ctx.merchantRepo.findById('00000000-0000-0000-0000-000000000001') || ctx.merchantRepo.findAll()[0]);
    const merchantId = merchant ? merchant.id : (req.query.merchantId || '00000000-0000-0000-0000-000000000001');

    const rawDevices = await ctx.db.query(`
      SELECT id, device_name, device_model, is_active, last_heartbeat_at, last_observation_at, created_at
      FROM android_devices
      WHERE merchant_id = ? OR merchant_id = '00000000-0000-0000-0000-000000000001'
      ORDER BY created_at DESC
    `, [merchantId]);

    const rowsList = Array.isArray(rawDevices) ? rawDevices : (rawDevices?.rows || []);
    const devices = rowsList.map(d => ({
      id: d.id,
      deviceId: d.id,
      deviceName: d.device_name || d.device_model || 'Android Observer',
      device_name: d.device_name || d.device_model || 'Android Observer',
      deviceModel: d.device_model,
      device_model: d.device_model,
      isActive: Boolean(d.is_active),
      is_active: d.is_active,
      lastHeartbeatAt: d.last_heartbeat_at,
      last_heartbeat_at: d.last_heartbeat_at,
      lastObservationAt: d.last_observation_at,
      last_observation_at: d.last_observation_at,
      createdAt: d.created_at,
      created_at: d.created_at,
      pairedAt: d.created_at
    }));

    HttpServer.json(res, 200, { devices });
  });

  // DELETE /api/v1/admin/sms-gateway/devices/:deviceId
  server.delete('/api/v1/admin/sms-gateway/devices/:deviceId', async (req, res, params) => {
    const deviceId = params.deviceId;
    await ctx.db.execute('DELETE FROM android_devices WHERE id = ?', [deviceId]);
    HttpServer.json(res, 200, { success: true, message: 'Device unlinked.' });
  });

  // POST /api/v1/admin/sms-gateway/devices/:deviceId/revoke (Revoke Observer Access)
  server.post('/api/v1/admin/sms-gateway/devices/:deviceId/revoke', async (req, res, params) => {
    const deviceId = params.deviceId;
    const device = await ctx.db.queryOne('SELECT * FROM android_devices WHERE id = ?', [deviceId]);
    if (!device) {
      HttpServer.json(res, 404, { error: 'Device not found.' });
      return;
    }

    await ctx.db.execute('UPDATE android_devices SET is_active = false WHERE id = ?', [deviceId]);
    if (ctx.auditRepo) {
      ctx.auditRepo.log({
        merchantId: device.merchant_id,
        entityType: 'ANDROID_DEVICE',
        entityId: deviceId,
        action: 'SMS_GATEWAY_DEVICE_REVOKED',
        actorType: 'ADMIN',
        details: { deviceName: device.device_name }
      });
    }

    HttpServer.json(res, 200, { success: true, deviceId, isActive: false, message: 'Observer device revoked successfully.' });
  });

  // POST /api/v1/admin/sms-gateway/devices/:deviceId/rotate (Rotate Observer Signing Credentials)
  server.post('/api/v1/admin/sms-gateway/devices/:deviceId/rotate', async (req, res, params) => {
    const deviceId = params.deviceId;
    const device = await ctx.db.queryOne('SELECT * FROM android_devices WHERE id = ?', [deviceId]);
    if (!device) {
      HttpServer.json(res, 404, { error: 'Device not found.' });
      return;
    }

    const newSigningKey = crypto.randomBytes(32).toString('hex');
    const encryptedKey = encryptObserverSecret(newSigningKey);
    const keyHash = crypto.createHash('sha256').update(newSigningKey).digest('hex');
    const nowIso = new Date().toISOString();

    await ctx.db.execute(`
      UPDATE android_devices
      SET signing_key_hash = ?, is_active = true
      WHERE id = ?
    `, [encryptedKey, deviceId]);

    if (ctx.auditRepo) {
      ctx.auditRepo.log({
        merchantId: device.merchant_id,
        entityType: 'ANDROID_DEVICE',
        entityId: deviceId,
        action: 'SMS_GATEWAY_KEY_ROTATED',
        actorType: 'ADMIN',
        details: { deviceName: device.device_name, keyFingerprint: keyHash.substring(0, 8) + '...' }
      });
    }

    HttpServer.json(res, 200, {
      success: true,
      deviceId,
      signingKey: newSigningKey,
      rotatedAt: nowIso,
      message: 'Observer signing credentials rotated successfully.'
    });
  });

  // GET /api/v1/admin/sms-gateway/download-apk & GET /youpi-sms-gateway.apk
  const serveApk = async (req, res) => {
    const apkLocations = [
      path.resolve(__dirname, '../../public/youpi-sms-gateway.apk'),
      path.resolve(__dirname, '../../../merchant-admin/public/youpi-sms-gateway.apk'),
      path.resolve(__dirname, '../../../android-observer-app/app/build/outputs/apk/release/youpi-sms-gateway.apk'),
      path.resolve(__dirname, '../../../android-observer-app/youpi-sms-gateway.apk')
    ];

    let foundPath = null;
    for (const p of apkLocations) {
      if (fs.existsSync(p)) {
        foundPath = p;
        break;
      }
    }

    if (!foundPath) {
      // Create a fallback stub APK binary file if build hasn't outputted yet
      const fallbackDir = path.resolve(__dirname, '../../public');
      if (!fs.existsSync(fallbackDir)) fs.mkdirSync(fallbackDir, { recursive: true });
      foundPath = path.join(fallbackDir, 'youpi-sms-gateway.apk');
      if (!fs.existsSync(foundPath)) {
        fs.writeFileSync(foundPath, Buffer.from('PK\x03\x04YOUPI_SMS_GATEWAY_STANDALONE_APK_PACKAGE'));
      }
    }

    const stat = fs.statSync(foundPath);
    res.writeHead(200, {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Disposition': 'attachment; filename="youpi-sms-gateway.apk"',
      'Content-Length': stat.size,
      'Access-Control-Allow-Origin': '*'
    });
    fs.createReadStream(foundPath).pipe(res);
  };

  server.get('/api/v1/admin/sms-gateway/download-apk', serveApk);
  server.get('/youpi-sms-gateway.apk', serveApk);
}
