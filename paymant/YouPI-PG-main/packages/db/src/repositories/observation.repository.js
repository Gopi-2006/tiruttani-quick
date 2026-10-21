import crypto from 'node:crypto';
import { ObservationAttributionStatus } from '@youpi/common';
import { handleResult } from '../database.js';

export class ObservationRepository {
  /**
   * @param {import('../database.js').Database} db
   */
  constructor(db) {
    this.db = db;
  }

  create(data) {
    const id = data.id || crypto.randomUUID();
    const now = new Date().toISOString();
    const rawPayload = typeof data.rawPayload === 'object' ? JSON.stringify(data.rawPayload) : (data.rawPayload || '{}');
    const observedAtIso = data.observedAt instanceof Date ? data.observedAt.toISOString() : new Date(data.observedAt).toISOString();

    const sql = `
      INSERT INTO payment_observations (
        id, receiving_account_id, source, amount_paise, observed_at,
        ingested_at, sender_vpa, bank_reference_number, fingerprint_hash,
        raw_payload, attribution_status, attributed_payment_id, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;

    const res = this.db.execute(sql, [
      id,
      data.receivingAccountId || null,
      data.source,
      Number(data.amountPaise),
      observedAtIso,
      now,
      data.senderVpa || null,
      data.bankReferenceNumber || null,
      data.fingerprintHash,
      rawPayload,
      data.attributionStatus || ObservationAttributionStatus.UNATTRIBUTED,
      data.attributedPaymentId || null,
      now
    ]);

    return handleResult(this.db, res, () => this.findById(id));
  }

  findById(id) {
    const res = this.db.queryOne('SELECT * FROM payment_observations WHERE id = ?', [id]);
    return handleResult(this.db, res, row => (row ? this.mapRow(row) : null));
  }

  findByFingerprint(fingerprintHash) {
    const res = this.db.queryOne('SELECT * FROM payment_observations WHERE fingerprint_hash = ?', [fingerprintHash]);
    return handleResult(this.db, res, row => (row ? this.mapRow(row) : null));
  }

  findUnattributed(receivingAccountId) {
    const res = this.db.query(`
      SELECT * FROM payment_observations
      WHERE receiving_account_id = ? AND attribution_status = ?
      ORDER BY observed_at ASC
    `, [receivingAccountId, ObservationAttributionStatus.UNATTRIBUTED]);

    return handleResult(this.db, res, rows => rows.map(r => this.mapRow(r)));
  }

  findByReceivingAccount(receivingAccountId, limit = 50) {
    const res = this.db.query(`
      SELECT * FROM payment_observations
      WHERE receiving_account_id = ?
      ORDER BY observed_at DESC
      LIMIT ?
    `, [receivingAccountId, limit]);

    return handleResult(this.db, res, rows => rows.map(r => this.mapRow(r)));
  }

  markAttributed(id, paymentId) {
    const res = this.db.execute(`
      UPDATE payment_observations
      SET attribution_status = ?, attributed_payment_id = ?
      WHERE id = ?
    `, [ObservationAttributionStatus.ATTRIBUTED, paymentId, id]);

    return handleResult(this.db, res, () => this.findById(id));
  }

  markDuplicate(id) {
    const res = this.db.execute(`
      UPDATE payment_observations
      SET attribution_status = ?
      WHERE id = ?
    `, [ObservationAttributionStatus.DUPLICATE_IGNORED, id]);

    return handleResult(this.db, res, () => this.findById(id));
  }

  markLateUnmatched(id) {
    const res = this.db.execute(`
      UPDATE payment_observations
      SET attribution_status = ?
      WHERE id = ?
    `, [ObservationAttributionStatus.LATE_UNMATCHED, id]);

    return handleResult(this.db, res, () => this.findById(id));
  }

  mapRow(row) {
    return {
      id: row.id,
      receivingAccountId: row.receiving_account_id,
      source: row.source,
      amountPaise: BigInt(row.amount_paise),
      observedAt: new Date(row.observed_at),
      ingestedAt: new Date(row.ingested_at),
      senderVpa: row.sender_vpa,
      bankReferenceNumber: row.bank_reference_number,
      fingerprintHash: row.fingerprint_hash,
      rawPayload: JSON.parse(row.raw_payload || '{}'),
      attributionStatus: row.attribution_status,
      attributedPaymentId: row.attributed_payment_id,
      createdAt: new Date(row.created_at)
    };
  }
}
