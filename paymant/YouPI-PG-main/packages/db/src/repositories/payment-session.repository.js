import crypto from 'node:crypto';
import { PaymentStatus, PaymentMethod } from '@youpi/common';
import { handleResult } from '../database.js';

export class PaymentSessionRepository {
  /**
   * @param {import('../database.js').Database} db
   */
  constructor(db) {
    this.db = db;
  }

  create(data) {
    const id = data.id || crypto.randomUUID();
    const now = new Date().toISOString();
    const metadata = typeof data.metadata === 'object' ? JSON.stringify(data.metadata) : (data.metadata || '{}');

    const sql = `
      INSERT INTO payment_sessions (
        id, merchant_id, customer_id, receiving_account_id, order_id,
        amount_paise, currency, method, status, queue_position,
        return_url, idempotency_key, device_id, verification_level, verification_sources,
        verification_tag, metadata, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, '[]', 'UNVERIFIED', ?, ?, ?)
    `;

    const res = this.db.execute(sql, [
      id,
      data.merchantId,
      data.customerId || null,
      data.receivingAccountId || null,
      data.orderId,
      Number(data.amountPaise),
      data.currency || 'INR',
      data.method || PaymentMethod.UPI,
      data.status || PaymentStatus.INITIATED,
      data.queuePosition || 0,
      data.returnUrl || null,
      data.idempotencyKey || null,
      data.deviceId || null,
      metadata,
      now,
      now
    ]);

    return handleResult(this.db, res, () => this.findById(id));
  }

  findById(id, db = this.db) {
    const res = db.queryOne('SELECT * FROM payment_sessions WHERE id = ?', [id]);
    return handleResult(db, res, row => (row ? this.mapRow(row) : null));
  }

  findByOrderId(merchantId, orderId, db = this.db) {
    const res = db.queryOne(
      'SELECT * FROM payment_sessions WHERE merchant_id = ? AND order_id = ?',
      [merchantId, orderId]
    );
    return handleResult(db, res, row => (row ? this.mapRow(row) : null));
  }

  findByCustomerId(customerId, db = this.db) {
    const res = db.query(
      'SELECT * FROM payment_sessions WHERE customer_id = ? ORDER BY created_at DESC',
      [customerId]
    );
    return handleResult(db, res, rows => rows.map(r => this.mapRow(r)));
  }

  findByMerchantId(merchantId, limit = 50, db = this.db) {
    const res = db.query(
      'SELECT * FROM payment_sessions WHERE merchant_id = ? ORDER BY created_at DESC LIMIT ?',
      [merchantId, limit]
    );
    return handleResult(db, res, rows => rows.map(r => this.mapRow(r)));
  }

  /**
   * Atomic slot acquisition transaction for UPI payments.
   * Invariant: Only ONE active or processing session per receiving account.
   * If slot is free, session transitions to ACTIVE with 5:00 window.
   * If slot is occupied, session transitions to QUEUED with sequence position.
   */
  acquireSlotAtomic(sessionId, receivingAccountId, durationMs = 300000) {
    if (this.db && this.db.dialect === 'postgres') {
      return this.db.transaction(async (tx) => {
        const now = new Date();
        const nowIso = now.toISOString();

        // Concurrency lock for PostgreSQL
        await tx.queryOne('SELECT id FROM payment_receiving_accounts WHERE id = ? FOR UPDATE', [receivingAccountId]);

        let activeRow = await tx.queryOne(`
          SELECT id, status, expires_at, processing_expires_at
          FROM payment_sessions
          WHERE receiving_account_id = ? AND status IN (?, ?)
          LIMIT 1
        `, [receivingAccountId, PaymentStatus.ACTIVE, PaymentStatus.PROCESSING]);

        if (activeRow) {
          const isStale = (activeRow.status === PaymentStatus.ACTIVE && activeRow.expires_at && new Date(activeRow.expires_at) <= now) ||
            (activeRow.status === PaymentStatus.PROCESSING && activeRow.processing_expires_at && new Date(activeRow.processing_expires_at) <= now);
          if (isStale) {
            const terminalStatus = activeRow.status === PaymentStatus.PROCESSING ? PaymentStatus.FAILED : PaymentStatus.EXPIRED;
            await tx.execute(`
              UPDATE payment_sessions
              SET status = ?, completed_at = ?, updated_at = ?
              WHERE id = ?
            `, [terminalStatus, nowIso, nowIso, activeRow.id]);
            activeRow = null;
          }
        }

        // CRITICAL GUARD: If activeRow is THIS session itself, it's ALREADY ACTIVE! Do not demote to QUEUED!
        if (activeRow && activeRow.id === sessionId) {
          return {
            status: PaymentStatus.ACTIVE,
            queuePosition: 0,
            expiresAt: activeRow.expires_at ? new Date(activeRow.expires_at) : new Date(now.getTime() + durationMs)
          };
        }

        if (!activeRow) {
          // Slot is vacant! Grant ACTIVE slot
          const expiresAt = new Date(now.getTime() + durationMs).toISOString();

          await tx.execute(`
            UPDATE payment_sessions
            SET status = ?, slot_acquired_at = ?, expires_at = ?, queue_position = 0, updated_at = ?
            WHERE id = ?
          `, [PaymentStatus.ACTIVE, nowIso, expiresAt, nowIso, sessionId]);

          // Mark receiving account as busy
          await tx.execute(`
            UPDATE payment_receiving_accounts
            SET is_slot_busy = true, current_active_session_id = ?, updated_at = ?
            WHERE id = ?
          `, [sessionId, nowIso, receivingAccountId]);

          return {
            status: PaymentStatus.ACTIVE,
            queuePosition: 0,
            expiresAt: new Date(expiresAt)
          };
        } else {
          // Slot is busy! Place in QUEUED
          const existingSession = await this.findById(sessionId, tx);
          let queuePosition = existingSession?.queuePosition;
          if (!queuePosition || queuePosition <= 0) {
            const posRow = await tx.queryOne(`
              SELECT COALESCE(MAX(queue_position), 0) + 1 AS next_pos
              FROM payment_sessions
              WHERE receiving_account_id = ? AND status = ?
            `, [receivingAccountId, PaymentStatus.QUEUED]);

            queuePosition = posRow ? posRow.next_pos : 1;
          }

          await tx.execute(`
            UPDATE payment_sessions
            SET status = ?, queue_position = ?, updated_at = ?
            WHERE id = ?
          `, [PaymentStatus.QUEUED, queuePosition, nowIso, sessionId]);

          return {
            status: PaymentStatus.QUEUED,
            queuePosition,
            expiresAt: null
          };
        }
      });
    }

    // SQLite synchronous path
    return this.db.transaction((tx) => {
      const db = tx || this.db;
      const now = new Date();
      const nowIso = now.toISOString();

      let activeRow = db.queryOne(`
        SELECT id, status, expires_at, processing_expires_at
        FROM payment_sessions
        WHERE receiving_account_id = ? AND status IN (?, ?)
        LIMIT 1
      `, [receivingAccountId, PaymentStatus.ACTIVE, PaymentStatus.PROCESSING]);

      if (activeRow) {
        const isStale = (activeRow.status === PaymentStatus.ACTIVE && activeRow.expires_at && new Date(activeRow.expires_at) <= now) ||
          (activeRow.status === PaymentStatus.PROCESSING && activeRow.processing_expires_at && new Date(activeRow.processing_expires_at) <= now);
        if (isStale) {
          const terminalStatus = activeRow.status === PaymentStatus.PROCESSING ? PaymentStatus.FAILED : PaymentStatus.EXPIRED;
          db.execute(`
            UPDATE payment_sessions
            SET status = ?, completed_at = ?, updated_at = ?
            WHERE id = ?
          `, [terminalStatus, nowIso, nowIso, activeRow.id]);
          activeRow = null;
        }
      }

      // CRITICAL GUARD: If activeRow is THIS session itself, it's ALREADY ACTIVE! Do not demote to QUEUED!
      if (activeRow && activeRow.id === sessionId) {
        return {
          status: PaymentStatus.ACTIVE,
          queuePosition: 0,
          expiresAt: activeRow.expires_at ? new Date(activeRow.expires_at) : new Date(now.getTime() + durationMs)
        };
      }

      if (!activeRow) {
        // Slot is vacant! Grant ACTIVE slot
        const expiresAt = new Date(now.getTime() + durationMs).toISOString();

        db.execute(`
          UPDATE payment_sessions
          SET status = ?, slot_acquired_at = ?, expires_at = ?, queue_position = 0, updated_at = ?
          WHERE id = ?
        `, [PaymentStatus.ACTIVE, nowIso, expiresAt, nowIso, sessionId]);

        // Mark receiving account as busy
        db.execute(`
          UPDATE payment_receiving_accounts
          SET is_slot_busy = true, current_active_session_id = ?, updated_at = ?
          WHERE id = ?
        `, [sessionId, nowIso, receivingAccountId]);

        return {
          status: PaymentStatus.ACTIVE,
          queuePosition: 0,
          expiresAt: new Date(expiresAt)
        };
      } else {
        // Slot is busy! Place in QUEUED
        const existingSession = this.findById(sessionId, db);
        let queuePosition = existingSession?.queuePosition;
        if (!queuePosition || queuePosition <= 0) {
          const posRow = db.queryOne(`
            SELECT COALESCE(MAX(queue_position), 0) + 1 AS next_pos
            FROM payment_sessions
            WHERE receiving_account_id = ? AND status = ?
          `, [receivingAccountId, PaymentStatus.QUEUED]);

          queuePosition = posRow ? posRow.next_pos : 1;
        }

        db.execute(`
          UPDATE payment_sessions
          SET status = ?, queue_position = ?, updated_at = ?
          WHERE id = ?
        `, [PaymentStatus.QUEUED, queuePosition, nowIso, sessionId]);

        return {
          status: PaymentStatus.QUEUED,
          queuePosition,
          expiresAt: null
        };
      }
    });
  }

  /**
   * Transitions an ACTIVE session to PROCESSING upon customer clicking Payment Done.
   * Starts independent 30-second verification timer.
   */
  transitionToProcessing(sessionId, durationMs = 30000) {
    if (this.db && this.db.dialect === 'postgres') {
      return this.db.transaction(async (tx) => {
        const session = await this.findById(sessionId, tx);
        if (!session) throw new Error(`Session not found: ${sessionId}`);

        // Idempotency: if already processing, return existing
        if (session.status === PaymentStatus.PROCESSING) {
          return session;
        }

        if (session.status !== PaymentStatus.ACTIVE) {
          throw new Error(`Cannot transition to PROCESSING from status: ${session.status}`);
        }

        const now = new Date();
        const nowIso = now.toISOString();
        const processingExpiresAt = new Date(now.getTime() + durationMs).toISOString();

        await tx.execute(`
          UPDATE payment_sessions
          SET status = ?, processing_started_at = ?, processing_expires_at = ?, updated_at = ?
          WHERE id = ? AND status = ?
        `, [PaymentStatus.PROCESSING, nowIso, processingExpiresAt, nowIso, sessionId, PaymentStatus.ACTIVE]);

        return this.findById(sessionId, tx);
      });
    }

    return this.db.transaction((tx) => {
      const db = tx || this.db;
      const session = this.findById(sessionId, db);
      if (!session) throw new Error(`Session not found: ${sessionId}`);

      // Idempotency: if already processing, return existing
      if (session.status === PaymentStatus.PROCESSING) {
        return session;
      }

      if (session.status !== PaymentStatus.ACTIVE) {
        throw new Error(`Cannot transition to PROCESSING from status: ${session.status}`);
      }

      const now = new Date();
      const nowIso = now.toISOString();
      const processingExpiresAt = new Date(now.getTime() + durationMs).toISOString();

      db.execute(`
        UPDATE payment_sessions
        SET status = ?, processing_started_at = ?, processing_expires_at = ?, updated_at = ?
        WHERE id = ? AND status = ?
      `, [PaymentStatus.PROCESSING, nowIso, processingExpiresAt, nowIso, sessionId, PaymentStatus.ACTIVE]);

      return this.findById(sessionId, db);
    });
  }

  /**
   * Transitions session to terminal state (SUCCESS, FAILED, EXPIRED, CANCELLED).
   * Atomically releases receiving account slot.
   */
  transitionToTerminal(sessionId, targetStatus, options = {}) {
    if (this.db && this.db.dialect === 'postgres') {
      return this.db.transaction(async (tx) => {
        const session = await this.findById(sessionId, tx);
        if (!session) throw new Error(`Session not found: ${sessionId}`);

        const terminalStates = [
          PaymentStatus.SUCCESS,
          PaymentStatus.FAILED,
          PaymentStatus.EXPIRED,
          PaymentStatus.CANCELLED
        ];

        if (terminalStates.includes(session.status)) {
          return session;
        }

        const now = new Date().toISOString();
        const attributedObsId = options.attributedObservationId || session.attributedObservationId || null;

        let metadata = session.metadata || {};
        if (typeof metadata === 'string') {
          try { metadata = JSON.parse(metadata); } catch { metadata = {}; }
        }
        if (options.reason) {
          metadata = { ...metadata, cancelledReason: options.reason };
        }
        if (options.replacedByDeviceId) {
          metadata = { ...metadata, replacedByDeviceId: options.replacedByDeviceId };
        }
        if (options.replacedBySessionId) {
          metadata = { ...metadata, replacedBySessionId: options.replacedBySessionId };
        }

        await tx.execute(`
          UPDATE payment_sessions
          SET status = ?, completed_at = ?, attributed_observation_id = ?, metadata = ?, updated_at = ?
          WHERE id = ?
        `, [targetStatus, now, attributedObsId, JSON.stringify(metadata), now, sessionId]);

        if (session.receivingAccountId) {
          await tx.execute(`
            UPDATE payment_receiving_accounts
            SET is_slot_busy = false, current_active_session_id = NULL, updated_at = ?
            WHERE id = ? AND (current_active_session_id = ? OR current_active_session_id IS NULL)
          `, [now, session.receivingAccountId, sessionId]);
        }

        return this.findById(sessionId, tx);
      });
    }

    return this.db.transaction((tx) => {
      const db = tx || this.db;
      const session = this.findById(sessionId, db);
      if (!session) throw new Error(`Session not found: ${sessionId}`);

      // Terminal states are final
      const terminalStates = [
        PaymentStatus.SUCCESS,
        PaymentStatus.FAILED,
        PaymentStatus.EXPIRED,
        PaymentStatus.CANCELLED
      ];

      if (terminalStates.includes(session.status)) {
        return session; // already terminal, idempotent
      }

      const now = new Date().toISOString();
      const attributedObsId = options.attributedObservationId || session.attributedObservationId || null;

      let metadata = session.metadata || {};
      if (typeof metadata === 'string') {
        try { metadata = JSON.parse(metadata); } catch { metadata = {}; }
      }
      if (options.reason) {
        metadata = { ...metadata, cancelledReason: options.reason };
      }
      if (options.replacedByDeviceId) {
        metadata = { ...metadata, replacedByDeviceId: options.replacedByDeviceId };
      }
      if (options.replacedBySessionId) {
        metadata = { ...metadata, replacedBySessionId: options.replacedBySessionId };
      }

      db.execute(`
        UPDATE payment_sessions
        SET status = ?, completed_at = ?, attributed_observation_id = ?, metadata = ?, updated_at = ?
        WHERE id = ?
      `, [targetStatus, now, attributedObsId, JSON.stringify(metadata), now, sessionId]);

      // Release slot on receiving account if this session owned it
      if (session.receivingAccountId) {
        db.execute(`
          UPDATE payment_receiving_accounts
          SET is_slot_busy = false, current_active_session_id = NULL, updated_at = ?
          WHERE id = ? AND (current_active_session_id = ? OR current_active_session_id IS NULL)
        `, [now, session.receivingAccountId, sessionId]);
      }

      return this.findById(sessionId, db);
    });
  }

  findCurrentActiveOrProcessing(receivingAccountId, db = this.db) {
    const res = db.queryOne(`
      SELECT * FROM payment_sessions
      WHERE receiving_account_id = ? AND status IN (?, ?)
      LIMIT 1
    `, [receivingAccountId, PaymentStatus.ACTIVE, PaymentStatus.PROCESSING]);

    return handleResult(db, res, row => {
      if (!row) return null;
      const now = new Date();
      const isStale = (row.status === PaymentStatus.ACTIVE && row.expires_at && new Date(row.expires_at) <= now) ||
        (row.status === PaymentStatus.PROCESSING && row.processing_expires_at && new Date(row.processing_expires_at) <= now);
      if (isStale) {
        const terminalStatus = row.status === PaymentStatus.PROCESSING ? PaymentStatus.FAILED : PaymentStatus.EXPIRED;
        return handleResult(db, this.transitionToTerminal(row.id, terminalStatus), () => null);
      }
      return this.mapRow(row);
    });
  }

  findCurrentActiveOrProcessingForMerchant(merchantId, db = this.db) {
    if (!merchantId) return null;
    const res = db.queryOne(`
      SELECT * FROM payment_sessions
      WHERE merchant_id = ? AND status IN (?, ?)
      ORDER BY created_at DESC
      LIMIT 1
    `, [merchantId, PaymentStatus.ACTIVE, PaymentStatus.PROCESSING]);

    return handleResult(db, res, row => {
      if (!row) return null;
      const now = new Date();
      const isStale = (row.status === PaymentStatus.ACTIVE && row.expires_at && new Date(row.expires_at) <= now) ||
        (row.status === PaymentStatus.PROCESSING && row.processing_expires_at && new Date(row.processing_expires_at) <= now);
      if (isStale) {
        const terminalStatus = row.status === PaymentStatus.PROCESSING ? PaymentStatus.FAILED : PaymentStatus.EXPIRED;
        return handleResult(db, this.transitionToTerminal(row.id, terminalStatus), () => null);
      }
      return this.mapRow(row);
    });
  }

  findActiveForCustomer(customerId, excludeSessionId = null, db = this.db) {
    if (!customerId) return null;
    let query = `
      SELECT * FROM payment_sessions
      WHERE customer_id = ? AND status IN (?, ?, ?)
    `;
    const params = [customerId, PaymentStatus.ACTIVE, PaymentStatus.PROCESSING, PaymentStatus.QUEUED];
    if (excludeSessionId) {
      query += ` AND id != ? `;
      params.push(excludeSessionId);
    }
    query += ` ORDER BY created_at DESC LIMIT 1 `;
    const res = db.queryOne(query, params);

    return handleResult(db, res, row => {
      if (!row) return null;
      const now = new Date();
      const isStale = (row.status === PaymentStatus.ACTIVE && row.expires_at && new Date(row.expires_at) <= now) ||
        (row.status === PaymentStatus.PROCESSING && row.processing_expires_at && new Date(row.processing_expires_at) <= now);
      if (isStale) {
        const terminalStatus = row.status === PaymentStatus.PROCESSING ? PaymentStatus.FAILED : PaymentStatus.EXPIRED;
        return handleResult(db, this.transitionToTerminal(row.id, terminalStatus), () => null);
      }
      return this.mapRow(row);
    });
  }

  findActiveForDevice(deviceId, excludeSessionId = null, db = this.db) {
    if (!deviceId) return null;
    let query = `
      SELECT * FROM payment_sessions
      WHERE device_id = ? AND status IN (?, ?, ?)
    `;
    const params = [deviceId, PaymentStatus.ACTIVE, PaymentStatus.PROCESSING, PaymentStatus.QUEUED];
    if (excludeSessionId) {
      query += ` AND id != ? `;
      params.push(excludeSessionId);
    }
    query += ` ORDER BY created_at DESC LIMIT 1 `;
    const res = db.queryOne(query, params);

    return handleResult(db, res, row => {
      if (!row) return null;
      const now = new Date();
      const isStale = (row.status === PaymentStatus.ACTIVE && row.expires_at && new Date(row.expires_at) <= now) ||
        (row.status === PaymentStatus.PROCESSING && row.processing_expires_at && new Date(row.processing_expires_at) <= now);
      if (isStale) {
        const terminalStatus = row.status === PaymentStatus.PROCESSING ? PaymentStatus.FAILED : PaymentStatus.EXPIRED;
        return handleResult(db, this.transitionToTerminal(row.id, terminalStatus), () => null);
      }
      return this.mapRow(row);
    });
  }

  findConflictingActiveSession({ customerId = null, deviceId = null, excludeSessionId = null }, db = this.db) {
    if (!customerId && !deviceId) return null;
    let query = `
      SELECT * FROM payment_sessions
      WHERE status IN (?, ?, ?)
    `;
    const params = [PaymentStatus.ACTIVE, PaymentStatus.PROCESSING, PaymentStatus.QUEUED];
    if (excludeSessionId) {
      query += ` AND id != ? `;
      params.push(excludeSessionId);
    }
    if (customerId && deviceId) {
      query += ` AND (customer_id = ? OR device_id = ?) `;
      params.push(customerId, deviceId);
    } else if (customerId) {
      query += ` AND customer_id = ? `;
      params.push(customerId);
    } else {
      query += ` AND device_id = ? `;
      params.push(deviceId);
    }
    query += ` ORDER BY created_at DESC LIMIT 1 `;
    const res = db.queryOne(query, params);

    return handleResult(db, res, row => {
      if (!row) return null;
      const now = new Date();
      const isStale = (row.status === PaymentStatus.ACTIVE && row.expires_at && new Date(row.expires_at) <= now) ||
        (row.status === PaymentStatus.PROCESSING && row.processing_expires_at && new Date(row.processing_expires_at) <= now);
      if (isStale) {
        const terminalStatus = row.status === PaymentStatus.PROCESSING ? PaymentStatus.FAILED : PaymentStatus.EXPIRED;
        return handleResult(db, this.transitionToTerminal(row.id, terminalStatus), () => null);
      }
      return this.mapRow(row);
    });
  }

  findAllActiveOrPendingForCustomer(customerId, db = this.db) {
    if (!customerId) return [];
    const res = db.query(`
      SELECT * FROM payment_sessions
      WHERE customer_id = ? AND status IN (?, ?, ?, ?)
      ORDER BY created_at DESC
    `, [customerId, PaymentStatus.ACTIVE, PaymentStatus.PROCESSING, PaymentStatus.QUEUED, PaymentStatus.INITIATED]);
    return handleResult(db, res, rows => rows.map(r => this.mapRow(r)));
  }

  findQueuedSessions(receivingAccountId, db = this.db) {
    const res = db.query(`
      SELECT * FROM payment_sessions
      WHERE receiving_account_id = ? AND status = ?
      ORDER BY queue_position ASC, created_at ASC
    `, [receivingAccountId, PaymentStatus.QUEUED]);

    return handleResult(db, res, rows => rows.map(r => this.mapRow(r)));
  }

  getNextQueuedSession(receivingAccountId, db = this.db) {
    const res = db.queryOne(`
      SELECT * FROM payment_sessions
      WHERE receiving_account_id = ? AND status = ?
      ORDER BY queue_position ASC, created_at ASC
      LIMIT 1
    `, [receivingAccountId, PaymentStatus.QUEUED]);

    return handleResult(db, res, row => (row ? this.mapRow(row) : null));
  }

  /**
   * Re-indexes remaining queued sessions after a promotion.
   */
  reindexQueue(receivingAccountId) {
    if (this.db && this.db.dialect === 'postgres') {
      return Promise.resolve(this.findQueuedSessions(receivingAccountId)).then(async (queued) => {
        let pos = 1;
        for (const session of queued) {
          await this.db.execute(`
            UPDATE payment_sessions SET queue_position = ?, updated_at = ?
            WHERE id = ?
          `, [pos++, new Date().toISOString(), session.id]);
        }
      });
    }

    const queued = this.findQueuedSessions(receivingAccountId);
    let pos = 1;
    for (const session of queued) {
      this.db.execute(`
        UPDATE payment_sessions SET queue_position = ?, updated_at = ?
        WHERE id = ?
      `, [pos++, new Date().toISOString(), session.id]);
    }
  }

  findRecentlyExpiredOrFailed(receivingAccountId, sinceDate, db = this.db) {
    const res = db.query(`
      SELECT * FROM payment_sessions
      WHERE receiving_account_id = ?
        AND status IN (?, ?)
        AND updated_at >= ?
      ORDER BY updated_at DESC
      LIMIT 20
    `, [receivingAccountId, PaymentStatus.EXPIRED, PaymentStatus.FAILED, sinceDate.toISOString()]);

    return handleResult(db, res, rows => rows.map(r => this.mapRow(r)));
  }

  /**
   * Records observation confirmation, calculates 2-level verification tier (SMS + Gmail),
   * updates the verification tag, and transitions to SUCCESS if level >= 1 and shouldFinalize is true.
   */
  recordVerificationSource(sessionId, source, observationId, options = {}) {
    if (this.db && this.db.dialect === 'postgres') {
      return this.db.transaction(async (tx) => {
        const session = await this.findById(sessionId, tx);
        if (!session) throw new Error(`Payment session not found: ${sessionId}`);

        const sourcesSet = new Set(session.verificationSources || []);
        sourcesSet.add(source);
        const sources = Array.from(sourcesSet);

        const level = Math.min(2, sources.length);
        const sourceLabels = sources.map(s => {
          if (s === 'GOOGLE_MESSAGES') return 'SMS';
          if (s === 'GMAIL') return 'Gmail';
          return s;
        });

        let tag = `Single Verification (${sourceLabels.join(', ')})`;
        if (level >= 2) {
          tag = `Dual Verification (${sourceLabels.join(' + ')})`;
        }

        const shouldFinalize = options.finalizeSuccess !== false;
        const isFirstSuccess = shouldFinalize && session.status !== PaymentStatus.SUCCESS && level >= 1;
        const targetStatus = shouldFinalize && level >= 1 ? PaymentStatus.SUCCESS : session.status;
        const now = new Date().toISOString();

        await tx.execute(`
          UPDATE payment_sessions
          SET status = ?,
              verification_level = ?,
              verification_sources = ?,
              verification_tag = ?,
              attributed_observation_id = COALESCE(attributed_observation_id, ?),
              completed_at = COALESCE(completed_at, ?),
              updated_at = ?
          WHERE id = ?
        `, [
          targetStatus,
          level,
          JSON.stringify(sources),
          tag,
          observationId,
          targetStatus === PaymentStatus.SUCCESS ? now : null,
          now,
          sessionId
        ]);

        if (targetStatus === PaymentStatus.SUCCESS && session.receivingAccountId) {
          await tx.execute(`
            UPDATE payment_receiving_accounts
            SET is_slot_busy = false, current_active_session_id = NULL, updated_at = ?
            WHERE id = ? AND current_active_session_id = ?
          `, [now, session.receivingAccountId, sessionId]);
        }

        const updated = await this.findById(sessionId, tx);
        return {
          session: updated,
          level,
          sources,
          tag,
          isFirstSuccess
        };
      });
    }

    return this.db.transaction((tx) => {
      const db = tx || this.db;
      const session = this.findById(sessionId, db);
      if (!session) throw new Error(`Payment session not found: ${sessionId}`);

      // Read current verification sources
      const sourcesSet = new Set(session.verificationSources || []);
      sourcesSet.add(source);
      const sources = Array.from(sourcesSet);

      const level = Math.min(2, sources.length); // 1 or 2 (2-Layer Engine: SMS + Gmail)
      const sourceLabels = sources.map(s => {
        if (s === 'GOOGLE_MESSAGES') return 'SMS';
        if (s === 'GMAIL') return 'Gmail';
        return s;
      });

      let tag = `Single Verification (${sourceLabels.join(', ')})`;
      if (level >= 2) {
        tag = `Dual Verification (${sourceLabels.join(' + ')})`;
      }

      const shouldFinalize = options.finalizeSuccess !== false;
      const isFirstSuccess = shouldFinalize && session.status !== PaymentStatus.SUCCESS && level >= 1;
      const targetStatus = shouldFinalize && level >= 1 ? PaymentStatus.SUCCESS : session.status;
      const now = new Date().toISOString();

      db.execute(`
        UPDATE payment_sessions
        SET status = ?,
            verification_level = ?,
            verification_sources = ?,
            verification_tag = ?,
            attributed_observation_id = COALESCE(attributed_observation_id, ?),
            completed_at = COALESCE(completed_at, ?),
            updated_at = ?
        WHERE id = ?
      `, [
        targetStatus,
        level,
        JSON.stringify(sources),
        tag,
        observationId,
        targetStatus === PaymentStatus.SUCCESS ? now : null,
        now,
        sessionId
      ]);

      // If this transition made it terminal SUCCESS, release slot on receiving account
      if (targetStatus === PaymentStatus.SUCCESS && session.receivingAccountId) {
        db.execute(`
          UPDATE payment_receiving_accounts
          SET is_slot_busy = false, current_active_session_id = NULL, updated_at = ?
          WHERE id = ? AND current_active_session_id = ?
        `, [now, session.receivingAccountId, sessionId]);
      }

      const updated = this.findById(sessionId, db);
      return {
        session: updated,
        level,
        sources,
        tag,
        isFirstSuccess
      };
    });
  }

  bindDevice(sessionId, deviceId) {
    const now = new Date().toISOString();
    const res = this.db.execute(
      'UPDATE payment_sessions SET device_id = ?, updated_at = ? WHERE id = ?',
      [deviceId, now, sessionId]
    );
    return handleResult(this.db, res, () => this.findById(sessionId));
  }

  mapRow(row) {
    return {
      id: row.id,
      merchantId: row.merchant_id,
      customerId: row.customer_id,
      receivingAccountId: row.receiving_account_id,
      orderId: row.order_id,
      amountPaise: BigInt(row.amount_paise),
      currency: row.currency,
      method: row.method,
      status: row.status,
      queuePosition: row.queue_position,
      slotAcquiredAt: row.slot_acquired_at ? new Date(row.slot_acquired_at) : null,
      expiresAt: row.expires_at ? new Date(row.expires_at) : null,
      processingStartedAt: row.processing_started_at ? new Date(row.processing_started_at) : null,
      processingExpiresAt: row.processing_expires_at ? new Date(row.processing_expires_at) : null,
      completedAt: row.completed_at ? new Date(row.completed_at) : null,
      returnUrl: row.return_url,
      attributedObservationId: row.attributed_observation_id,
      idempotencyKey: row.idempotency_key,
      deviceId: row.device_id || null,
      verificationLevel: row.verification_level !== undefined && row.verification_level !== null ? Number(row.verification_level) : 0,
      verificationSources: JSON.parse(row.verification_sources || '[]'),
      verificationTag: row.verification_tag || 'UNVERIFIED',
      metadata: JSON.parse(row.metadata || '{}'),
      createdAt: new Date(row.created_at),
      updatedAt: new Date(row.updated_at)
    };
  }
}
