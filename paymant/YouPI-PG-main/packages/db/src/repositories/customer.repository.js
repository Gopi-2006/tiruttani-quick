import crypto from 'node:crypto';
import { hashPassword, verifyPassword, normalizeEmail, normalizeMobile, isValidEmail, isValidMobile, isValidPassword } from '@youpi/common';
import { handleResult } from '../database.js';

export class CustomerRepository {
  /**
   * @param {import('../database.js').Database} db
   */
  constructor(db) {
    this.db = db;
  }

  /**
   * Creates a new gateway customer.
   * @param {{
   *   id?: string,
   *   name?: string,
   *   fullName?: string,
   *   email?: string,
   *   mobileNumber?: string,
   *   phoneNumber?: string,
   *   password?: string,
   *   passwordHash?: string,
   *   status?: string
   * }} data
   */
  create(data) {
    const id = data.id || crypto.randomUUID();
    const name = String(data.name || data.fullName || '').trim();
    const mobileNumber = normalizeMobile(data.mobileNumber || data.phoneNumber);
    let email = normalizeEmail(data.email);
    const status = data.status || 'ACTIVE';

    if (!name) {
      throw new Error('Customer name is required.');
    }
    if (!mobileNumber || !isValidMobile(mobileNumber)) {
      throw new Error('Invalid mobile number format (must be a valid 10-digit number).');
    }
    if (!email) {
      email = `${mobileNumber}@customer.youpi.local`;
    } else if (!isValidEmail(email)) {
      throw new Error('Invalid email address format.');
    }

    let passwordHash = data.passwordHash || null;
    if (!passwordHash && data.password) {
      if (!isValidPassword(data.password)) {
        throw new Error('Password must be at least 6 characters long.');
      }
      passwordHash = hashPassword(data.password);
    }

    const otpCode = data.otpCode || null;
    const otpExpiresAt = data.otpExpiresAt || null;
    const isPhoneVerified = Boolean(data.isPhoneVerified);
    const now = new Date().toISOString();

    const sql = `
      INSERT INTO customers (id, name, email, mobile_number, password_hash, otp_code, otp_expires_at, is_phone_verified, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;

    const res = this.db.execute(sql, [
      id,
      name,
      email,
      mobileNumber,
      passwordHash,
      otpCode,
      otpExpiresAt,
      Boolean(isPhoneVerified),
      status,
      now,
      now
    ]);

    if (this.db && this.db.dialect === 'postgres') {
      return Promise.resolve(res).then(() => this.findById(id));
    }
    return this.findById(id);
  }

  /**
   * Finds customer by unique ID.
   * @param {string} id
   * @returns {any | null}
   */
  findById(id) {
    if (!id) return null;
    const res = this.db.queryOne('SELECT * FROM customers WHERE id = ?', [id]);
    return handleResult(this.db, res, r => this.mapRow(r));
  }

  /**
   * Finds customer by normalized email.
   * @param {string} email
   * @returns {any | null}
   */
  findByEmail(email) {
    const normalized = normalizeEmail(email);
    if (!normalized) return null;
    const res = this.db.queryOne('SELECT * FROM customers WHERE email = ?', [normalized]);
    return handleResult(this.db, res, r => this.mapRow(r));
  }

  /**
   * Finds customer by normalized mobile number.
   * @param {string} mobileNumber
   * @returns {any | null}
   */
  findByMobile(mobileNumber) {
    const normalized = normalizeMobile(mobileNumber);
    if (!normalized) return null;
    const clean10 = normalized.slice(-10);
    const res = this.db.queryOne(
      'SELECT * FROM customers WHERE mobile_number = ? OR mobile_number = ? OR mobile_number = ? OR mobile_number LIKE ?',
      [normalized, clean10, '+91' + clean10, '%' + clean10]
    );
    return handleResult(this.db, res, r => this.mapRow(r));
  }

  /**
   * Alias for backwards compatibility with tests and callers expecting findByPhone.
   * @param {string} arg1 merchantId or phoneNumber
   * @param {string} [arg2] optional phoneNumber if merchantId was first
   * @returns {any | null}
   */
  findByPhone(arg1, arg2) {
    const phone = arg2 || arg1;
    return this.findByMobile(phone);
  }

  /**
   * Finds customer by either email or mobile number identifier.
   * @param {string} identifier
   * @returns {any | null}
   */
  findByIdentifier(identifier) {
    if (!identifier) return null;
    const trimmed = String(identifier).trim();
    if (trimmed.includes('@')) {
      return this.findByEmail(trimmed);
    }
    const asMobile = this.findByMobile(trimmed);
    if (asMobile) return asMobile;
    return this.findByEmail(trimmed);
  }

  /**
   * Verifies customer login credentials using email or mobile + password.
   * @param {string|any} arg1 Identifier or merchantId
   * @param {string} arg2 Password or phoneNumber
   * @param {string} [arg3] Optional password if merchantId was first
   * @returns {any | null} Safe customer profile or null
   */
  verifyCredentials(arg1, arg2, arg3) {
    let identifier = arg1;
    let password = arg2;
    if (arg3 !== undefined) {
      identifier = arg2;
      password = arg3;
    }

    if (!identifier || !password) return null;

    const customer = this.findByIdentifier(identifier);
    if (!customer) return null;

    if (customer.status !== 'ACTIVE') return null;

    const isValid = verifyPassword(password, customer.passwordHash);
    if (!isValid) return null;

    // Update last_login_at
    const now = new Date().toISOString();
    try {
      this.db.execute('UPDATE customers SET last_login_at = ?, updated_at = ? WHERE id = ?', [now, now, customer.id]);
    } catch {}

    const { passwordHash, ...safeCustomer } = customer;
    safeCustomer.lastLoginAt = new Date(now);
    return safeCustomer;
  }

  /**
   * Stores WhatsApp OTP challenge for a customer mobile number.
   * @param {string} mobileNumber
   * @param {string} otpCode
   * @param {string} expiresAt ISO String
   * @returns {any | null}
   */
  setOtp(mobileNumber, otpCode, expiresAt) {
    const normalized = normalizeMobile(mobileNumber);
    if (!normalized) return null;
    const now = new Date().toISOString();
    this.db.execute(
      'UPDATE customers SET otp_code = ?, otp_expires_at = ?, updated_at = ? WHERE mobile_number = ?',
      [otpCode, expiresAt, now, normalized]
    );
    return this.findByMobile(normalized);
  }

  /**
   * Verifies WhatsApp OTP for customer login/signup.
   * Clears the OTP and marks phone as verified on success.
   * @param {string} mobileNumber
   * @param {string} otpCode
   * @returns {any | null}
   */
  verifyOtp(mobileNumber, otpCode) {
    const normalized = normalizeMobile(mobileNumber);
    if (!normalized || !otpCode) return null;
    const customer = this.findByMobile(normalized);
    if (!customer) return null;
    if (!customer.otpCode || customer.otpCode !== String(otpCode).trim()) {
      return null;
    }
    if (customer.otpExpiresAt && new Date() > customer.otpExpiresAt) {
      return null; // Expired
    }

    const now = new Date().toISOString();
    const res = this.db.execute(
      'UPDATE customers SET otp_code = NULL, otp_expires_at = NULL, is_phone_verified = true, last_login_at = ?, updated_at = ? WHERE id = ?',
      [now, now, customer.id]
    );
    if (this.db && this.db.dialect === 'postgres') {
      return Promise.resolve(res).then(() => this.findById(customer.id));
    }
    return this.findById(customer.id);
  }

  /**
   * Persists a pending OTP signup or login challenge across application containers.
   */
  saveOtpChallenge({ mobileNumber, otpCode, name = null, email = null, expiresAt }) {
    const clean = normalizeMobile(mobileNumber);
    if (!clean) return null;
    const now = new Date().toISOString();
    const sql = `
      INSERT INTO customer_otp_challenges (mobile_number, otp_code, name, email, attempts, locked_until, expires_at, created_at)
      VALUES (?, ?, ?, ?, 0, NULL, ?, ?)
      ON CONFLICT(mobile_number) DO UPDATE SET
        otp_code = excluded.otp_code,
        name = COALESCE(excluded.name, customer_otp_challenges.name),
        email = COALESCE(excluded.email, customer_otp_challenges.email),
        expires_at = excluded.expires_at,
        created_at = excluded.created_at
    `;
    const res = this.db.execute(sql, [clean, otpCode, name, email, expiresAt, now]);
    if (this.db && this.db.dialect === 'postgres') {
      return Promise.resolve(res).then(() => this.getOtpChallenge(clean));
    }
    return this.getOtpChallenge(clean);
  }

  /**
   * Retrieves pending OTP challenge.
   */
  getOtpChallenge(mobileNumber) {
    const clean = normalizeMobile(mobileNumber);
    if (!clean) return null;
    const res = this.db.queryOne('SELECT * FROM customer_otp_challenges WHERE mobile_number = ?', [clean]);
    return handleResult(this.db, res, r => ({
      mobileNumber: r.mobile_number,
      otpCode: r.otp_code,
      name: r.name,
      email: r.email,
      attempts: Number(r.attempts || 0),
      lockedUntil: r.locked_until ? (r.locked_until instanceof Date ? r.locked_until.getTime() : new Date(r.locked_until).getTime()) : null,
      expiresAt: r.expires_at instanceof Date ? r.expires_at.toISOString() : r.expires_at,
      createdAt: r.created_at instanceof Date ? r.created_at : new Date(r.created_at)
    }));
  }

  /**
   * Records a failed OTP verification attempt for brute-force rate limiting.
   */
  recordOtpFailure(mobileNumber) {
    const clean = normalizeMobile(mobileNumber);
    if (!clean) return null;
    const challengeRes = this.getOtpChallenge(clean);

    const updateChallenge = (challenge) => {
      const attempts = ((challenge?.attempts) || 0) + 1;
      let lockedUntil = null;
      if (attempts >= 5) {
        lockedUntil = new Date(Date.now() + 15 * 60 * 1000).toISOString();
      }
      this.db.execute(
        'UPDATE customer_otp_challenges SET attempts = ?, locked_until = ? WHERE mobile_number = ?',
        [attempts, lockedUntil, clean]
      );
      return { count: attempts, lockedUntil: lockedUntil ? new Date(lockedUntil).getTime() : null };
    };

    if (this.db && this.db.dialect === 'postgres') {
      return Promise.resolve(challengeRes).then(updateChallenge);
    }
    return updateChallenge(challengeRes);
  }

  /**
   * Clears completed OTP challenge upon successful verification.
   */
  clearOtpChallenge(mobileNumber) {
    const clean = normalizeMobile(mobileNumber);
    if (!clean) return true;
    const res = this.db.execute('DELETE FROM customer_otp_challenges WHERE mobile_number = ?', [clean]);
    if (this.db && this.db.dialect === 'postgres') {
      return Promise.resolve(res).then(() => true);
    }
    return true;
  }

  /**
   * Completely wipes all customer identity records.
   */
  clearAll() {
    this.db.execute('DELETE FROM customer_sessions');
    this.db.execute('DELETE FROM customers');
  }

  /**
   * Returns count of customers in the database.
   * @returns {number}
   */
  count() {
    const row = this.db.queryOne('SELECT COUNT(*) as c FROM customers');
    return row?.c || 0;
  }

  /**
   * Bans a customer by ID.
   * @param {string} id
   * @param {string} [reason]
   * @returns {any | null}
   */
  /**
   * Bans a customer by ID.
   * @param {string} id
   * @param {string} [reason='FRAUDULENT_PAYMENT_INJECTION']
   * @param {{ lastDevice?: string, deviceInfo?: string }} [options={}]
   * @returns {any | null}
   */
  banCustomer(id, reason = 'FRAUDULENT_PAYMENT_INJECTION', options = {}) {
    if (!id) return null;
    const now = new Date().toISOString();
    const lastDevice = options.lastDevice || options.deviceInfo || null;
    const res1 = this.db.execute(
      "UPDATE customers SET status = 'BANNED', ban_reason = ?, banned_at = ?, last_device = COALESCE(?, last_device), updated_at = ? WHERE id = ?",
      [reason, now, lastDevice, now, id]
    );

    const onUpdated = () => {
      const qRes = this.db.query(
        "SELECT id, receiving_account_id FROM payment_sessions WHERE customer_id = ? AND status IN ('INITIATED', 'QUEUED', 'ACTIVE', 'PROCESSING')",
        [id]
      );
      return handleResult(this.db, qRes, (rawSessions) => {
        const activeSessions = Array.isArray(rawSessions) ? rawSessions : (rawSessions?.rows || []);
        if (activeSessions.length > 0) {
          const isPg = this.db && this.db.dialect === 'postgres';
          const falseVal = isPg ? true : 0; // boolean or 0
          this.db.execute(
            "UPDATE payment_sessions SET status = 'EXPIRED', updated_at = ? WHERE customer_id = ? AND status IN ('INITIATED', 'QUEUED', 'ACTIVE', 'PROCESSING')",
            [now, id]
          );
          for (const s of activeSessions) {
            if (s.receiving_account_id) {
              this.db.execute(
                isPg
                  ? "UPDATE payment_receiving_accounts SET is_slot_busy = false, current_active_session_id = NULL WHERE id = ? AND current_active_session_id = ?"
                  : "UPDATE payment_receiving_accounts SET is_slot_busy = 0, current_active_session_id = NULL WHERE id = ? AND current_active_session_id = ?",
                [s.receiving_account_id, s.id]
              );
            }
          }
        }
        return this.findById(id);
      });
    };

    return handleResult(this.db, res1, onUpdated);
  }

  /**
   * Unbans a customer by ID.
   * @param {string} id
   * @returns {any | null}
   */
  unbanCustomer(id) {
    if (!id) return null;
    const now = new Date().toISOString();
    this.db.execute(
      "UPDATE customers SET status = 'ACTIVE', ban_reason = NULL, unbanned_at = ?, updated_at = ? WHERE id = ?",
      [now, now, id]
    );
    return this.findById(id);
  }

  /**
   * Checks if customer is banned.
   * @param {string} id
   * @returns {boolean}
   */
  isBanned(id) {
    if (!id) return false;
    const customer = this.findById(id);
    return customer?.status === 'BANNED';
  }

  /**
   * Creates and persists a security event record with complete forensic evidence.
   * @param {{
   *   id?: string,
   *   merchantId?: string,
   *   customerId?: string,
   *   paymentSessionId?: string,
   *   eventType: string,
   *   source?: string,
   *   sender?: string,
   *   deviceInfo?: string,
   *   rawMessage: string,
   *   normalizedMessage?: string,
   *   extractedAmount?: string,
   *   extractedReference?: string,
   *   parserResults?: any,
   *   verificationResults?: any,
   *   fraudReason: string,
   *   metadata?: any
   * }} data
   * @returns {any}
   */
  createSecurityEvent(data) {
    const id = data.id || crypto.randomUUID();
    const now = new Date().toISOString();
    const sql = `
      INSERT INTO security_events (
        id, merchant_id, customer_id, payment_session_id, event_type,
        source, sender, device_info, raw_message, normalized_message,
        extracted_amount, extracted_reference, parser_results, verification_results,
        fraud_reason, metadata, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;
    this.db.execute(sql, [
      id,
      data.merchantId || null,
      data.customerId || null,
      data.paymentSessionId || null,
      data.eventType || 'FRAUDULENT_PAYMENT_INJECTION',
      data.source || null,
      data.sender || null,
      data.deviceInfo || null,
      data.rawMessage || '',
      data.normalizedMessage || null,
      data.extractedAmount || null,
      data.extractedReference || null,
      typeof data.parserResults === 'object' ? JSON.stringify(data.parserResults) : (data.parserResults || '{}'),
      typeof data.verificationResults === 'object' ? JSON.stringify(data.verificationResults) : (data.verificationResults || '{}'),
      data.fraudReason || 'FRAUDULENT_PAYMENT_INJECTION',
      typeof data.metadata === 'object' ? JSON.stringify(data.metadata) : (data.metadata || '{}'),
      now
    ]);
    return this.db.queryOne('SELECT * FROM security_events WHERE id = ?', [id]);
  }

  /**
   * Finds all security events for customer or all security events.
   * @param {string} [customerId]
   * @param {number} [limit=100]
   * @returns {any[]}
   */
  /**
   * Finds all security events for customer or all security events.
   * @param {string} [customerId]
   * @param {number} [limit=100]
   * @returns {any[]}
   */
  getSecurityEvents(customerId = null, limit = 100) {
    const mapSecRow = (row) => {
      let meta = {};
      try { meta = typeof row.metadata === 'string' ? JSON.parse(row.metadata) : (row.metadata || {}); } catch {}
      return {
        ...row,
        customerId: row.customer_id,
        paymentSessionId: row.payment_session_id,
        eventType: row.event_type,
        rawMessage: row.raw_message,
        normalizedMessage: row.normalized_message,
        extractedAmount: row.extracted_amount,
        extractedReference: row.extracted_reference,
        fraudReason: row.fraud_reason,
        createdAt: row.created_at,
        metadata: meta,
        autoBanApplied: meta.autoBanApplied !== undefined ? Boolean(meta.autoBanApplied) : (row.event_type === 'FRAUDULENT_PAYMENT_INJECTION'),
        banSuppressed: meta.banSuppressed !== undefined ? Boolean(meta.banSuppressed) : false
      };
    };

    if (customerId) {
      const res = this.db.query(
        'SELECT * FROM security_events WHERE customer_id = ? ORDER BY created_at DESC LIMIT ?',
        [customerId, limit]
      );
      return handleResult(this.db, res, rows => (Array.isArray(rows) ? rows : (rows?.rows || [])).map(mapSecRow));
    }
    const res = this.db.query(
      'SELECT se.*, c.name as customer_name, c.email as customer_email, c.mobile_number as customer_phone FROM security_events se LEFT JOIN customers c ON se.customer_id = c.id ORDER BY se.created_at DESC LIMIT ?',
      [limit]
    );
    return handleResult(this.db, res, rows => (Array.isArray(rows) ? rows : (rows?.rows || [])).map(mapSecRow));
  }

  /**
   * Retrieves all banned customers with their latest security event and payment session details.
   * @param {string} [searchQuery='']
   * @returns {any[]}
   */
  findAllBanned(searchQuery = '') {
    const isPg = this.db && this.db.dialect === 'postgres';
    let sql = isPg ? `
      SELECT c.*,
             se.id as security_event_id,
             se.event_type,
             se.source as event_source,
             se.sender as event_sender,
             se.device_info as event_device_info,
             se.fraud_reason as event_fraud_reason,
             se.raw_message as event_raw_message,
             se.created_at as event_created_at,
             ps.id as session_id,
             ps.order_id,
             ps.amount_paise,
             ps.status as session_status
      FROM customers c
      LEFT JOIN LATERAL (
        SELECT * FROM security_events WHERE customer_id = c.id ORDER BY created_at DESC LIMIT 1
      ) se ON true
      LEFT JOIN payment_sessions ps ON ps.id = se.payment_session_id
      WHERE c.status = 'BANNED'
    ` : `
      SELECT c.*,
             se.id as security_event_id,
             se.event_type,
             se.source as event_source,
             se.sender as event_sender,
             se.device_info as event_device_info,
             se.fraud_reason as event_fraud_reason,
             se.raw_message as event_raw_message,
             se.created_at as event_created_at,
             ps.id as session_id,
             ps.order_id,
             ps.amount_paise,
             ps.status as session_status
      FROM customers c
      LEFT JOIN (
        SELECT * FROM security_events ORDER BY created_at DESC
      ) se ON se.customer_id = c.id
      LEFT JOIN payment_sessions ps ON ps.id = se.payment_session_id
      WHERE c.status = 'BANNED'
    `;
    const params = [];
    if (searchQuery && searchQuery.trim()) {
      const q = `%${searchQuery.trim()}%`;
      sql += ` AND (c.name LIKE ? OR c.email LIKE ? OR c.mobile_number LIKE ?)`;
      params.push(q, q, q);
    }
    if (!isPg) {
      sql += ` GROUP BY c.id`;
    }
    sql += ` ORDER BY COALESCE(c.banned_at, c.updated_at) DESC`;

    const res = this.db.query(sql, params);
    const mapBanned = r => ({
      id: r.id,
      name: r.name,
      email: r.email,
      phone: r.mobile_number,
      mobileNumber: r.mobile_number,
      status: r.status,
      bannedAt: r.banned_at || r.event_created_at || r.updated_at,
      banReason: r.ban_reason || r.event_fraud_reason || 'FRAUDULENT_PAYMENT_INJECTION',
      paymentSession: r.order_id ? `#${r.order_id}` : (r.payment_session_id || 'N/A'),
      orderId: r.order_id || null,
      sessionId: r.session_id || null,
      lastDevice: r.last_device || r.event_device_info || 'Device Web Client',
      source: r.event_source || 'SMS',
      securityEventId: r.security_event_id || null,
      rawMessage: r.event_raw_message || null
    });
    return handleResult(this.db, res, rows => (Array.isArray(rows) ? rows : (rows?.rows || [])).map(mapBanned));
  }

  /**
   * Retrieves complete ban evidence package for a specific customer.
   * @param {string} customerId
   * @returns {any | null}
   */
  async getBanEvidence(customerId) {
    const customer = await this.findById(customerId);
    if (!customer) return null;

    const rawEvents = await this.getSecurityEvents(customerId, 50);
    const events = Array.isArray(rawEvents) ? rawEvents : (rawEvents?.rows || []);
    const triggerEvent = events.find(e => e.eventType === 'FRAUDULENT_PAYMENT_INJECTION') || events[0] || null;

    let session = null;
    if (triggerEvent?.paymentSessionId || triggerEvent?.payment_session_id) {
      const sessId = triggerEvent.paymentSessionId || triggerEvent.payment_session_id;
      session = await this.db.queryOne('SELECT * FROM payment_sessions WHERE id = ?', [sessId]);
    } else {
      session = await this.db.queryOne('SELECT * FROM payment_sessions WHERE customer_id = ? ORDER BY created_at DESC LIMIT 1', [customerId]);
    }

    const allSessionsRaw = await this.db.query(
      'SELECT status, amount_paise FROM payment_sessions WHERE customer_id = ?',
      [customerId]
    );
    const allSessions = Array.isArray(allSessionsRaw) ? allSessionsRaw : (allSessionsRaw?.rows || []);
    const totalOrders = allSessions.length;
    const totalSpentPaise = allSessions
      .filter(s => s.status === 'SUCCESS')
      .reduce((sum, s) => sum + Number(s.amount_paise || 0), 0);

    const rawVerbatim = triggerEvent?.rawMessage || triggerEvent?.raw_message || 'No raw message preserved.';

    return {
      customer: {
        id: customer.id,
        name: customer.name,
        email: customer.email,
        phone: customer.mobileNumber,
        status: customer.status,
        createdAt: customer.createdAt,
        bannedAt: customer.bannedAt || triggerEvent?.createdAt || customer.updatedAt,
        banReason: customer.banReason || triggerEvent?.fraudReason || 'FRAUDULENT_PAYMENT_INJECTION',
        lastDevice: customer.lastDevice || triggerEvent?.device_info || 'Device Web Client',
        totalOrders,
        totalSpentPaise,
        totalSpentRupees: (totalSpentPaise / 100).toFixed(2)
      },
      banDetails: {
        banType: customer.banReason === 'MANUAL_BAN' ? 'MANUAL' : 'AUTOMATIC',
        triggerEvent: triggerEvent ? (triggerEvent.eventType || triggerEvent.event_type) : (customer.banReason || 'FRAUDULENT_PAYMENT_INJECTION'),
        triggerTimestamp: customer.bannedAt || triggerEvent?.createdAt || null,
        paymentSessionId: session ? session.id : (triggerEvent?.paymentSessionId || null),
        orderId: session ? session.order_id : null,
        sessionAmountPaise: session ? session.amount_paise : null,
        sessionAmountRupees: session ? (Number(session.amount_paise) / 100).toFixed(2) : null
      },
      rawEvidence: rawVerbatim,
      rawEvidenceObject: {
        rawMessage: rawVerbatim,
        normalizedMessage: triggerEvent?.normalizedMessage || triggerEvent?.normalized_message || null,
        extractedAmount: triggerEvent?.extractedAmount || triggerEvent?.extracted_amount || null,
        extractedReference: triggerEvent?.extractedReference || triggerEvent?.extracted_reference || null
      },
      observationMetadata: {
        source: triggerEvent?.source || 'SMS',
        sender: triggerEvent?.sender || customer.mobileNumber,
        receiver: 'SIM Slot #1',
        deviceId: triggerEvent?.device_info || customer.lastDevice || 'android-gateway'
      },
      discrepancyAnalysis: {
        customerPhone: customer.mobileNumber,
        observationSender: triggerEvent?.sender || customer.mobileNumber,
        registeredBankHeader: 'NO (Personal sender match)',
        sessionAmount: session ? `Rs ${(Number(session.amount_paise) / 100).toFixed(2)}` : 'N/A',
        messageAmount: triggerEvent?.extractedAmount || 'N/A',
        sessionRef: session?.id ? session.id.substring(0, 12) : 'N/A',
        messageRef: triggerEvent?.extractedReference || 'N/A',
        result: 'FRAUDULENT_PAYMENT_INJECTION confirmed.'
      },
      timeline: {
        sessionCreated: session?.created_at || null,
        fakeObservationReceived: triggerEvent?.createdAt || null,
        paymentRejected: triggerEvent?.createdAt || null,
        autoBanExecuted: customer.bannedAt || triggerEvent?.createdAt || null
      },
      session: session ? {
        id: session.id,
        orderId: session.order_id,
        amount: session.amount_paise ? `₹${(Number(session.amount_paise) / 100).toFixed(2)}` : null,
        amountPaise: session.amount_paise?.toString(),
        createdAt: session.created_at,
        state: session.status
      } : null,
      securityEvent: triggerEvent ? {
        id: triggerEvent.id,
        detectionTime: triggerEvent.createdAt,
        fraudReason: triggerEvent.fraudReason || triggerEvent.fraud_reason,
        source: triggerEvent.source,
        sender: triggerEvent.sender,
        deviceInfo: triggerEvent.device_info,
        eventType: triggerEvent.eventType || triggerEvent.event_type
      } : null,
      history: events.map(e => ({
        id: e.id,
        eventType: e.eventType || e.event_type,
        fraudReason: e.fraudReason || e.fraud_reason,
        source: e.source,
        sender: e.sender,
        timestamp: e.createdAt || e.created_at,
        rawMessage: e.rawMessage || e.raw_message
      }))
    };
  }

  /**
   * Maps SQLite row to camelCase domain model with backward-compatibility aliases.
   */
  mapRow(row) {
    if (!row) return null;
    return {
      id: row.id,
      name: row.name,
      fullName: row.name,
      email: row.email,
      mobileNumber: row.mobile_number,
      phoneNumber: row.mobile_number,
      passwordHash: row.password_hash,
      otpCode: row.otp_code || null,
      otpExpiresAt: row.otp_expires_at ? new Date(row.otp_expires_at) : null,
      isPhoneVerified: Boolean(row.is_phone_verified),
      status: row.status,
      banReason: row.ban_reason || null,
      bannedAt: row.banned_at ? new Date(row.banned_at) : null,
      unbannedAt: row.unbanned_at ? new Date(row.unbanned_at) : null,
      lastDevice: row.last_device || null,
      lastLoginAt: row.last_login_at ? new Date(row.last_login_at) : null,
      createdAt: row.created_at instanceof Date ? row.created_at : new Date(row.created_at),
      updatedAt: row.updated_at instanceof Date ? row.updated_at : new Date(row.updated_at)
    };
  }
}
