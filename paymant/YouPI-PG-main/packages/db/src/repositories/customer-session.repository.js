import crypto from 'node:crypto';
import { handleResult } from '../database.js';

export class CustomerSessionRepository {
  /**
   * @param {import('../database.js').Database} db
   * @param {import('./customer.repository.js').CustomerRepository} [customerRepo]
   */
  constructor(db, customerRepo = null) {
    this.db = db;
    this.customerRepo = customerRepo;
  }

  /**
   * Creates an active server-authoritative session for an authenticated customer.
   * @param {{
   *   customerId: string,
   *   ipAddress?: string,
   *   userAgent?: string,
   *   ttlHours?: number
   * }} data
   */
  create(data) {
    const id = crypto.randomUUID();
    const token = `csess_${crypto.randomBytes(32).toString('hex')}`;
    const ttlHours = data.ttlHours || 720; // 30 days default
    const now = new Date();
    const expiresAt = new Date(now.getTime() + ttlHours * 3600 * 1000);

    const sql = `
      INSERT INTO customer_sessions (id, customer_id, token, expires_at, is_active, ip_address, user_agent, created_at, updated_at)
      VALUES (?, ?, ?, ?, true, ?, ?, ?, ?)
    `;

    const res = this.db.execute(sql, [
      id,
      data.customerId,
      token,
      expiresAt.toISOString(),
      data.ipAddress || null,
      data.userAgent || null,
      now.toISOString(),
      now.toISOString()
    ]);

    const resultObj = {
      id,
      customerId: data.customerId,
      token,
      expiresAt,
      isActive: true,
      createdAt: now
    };

    return handleResult(this.db, res, () => resultObj);
  }

  /**
   * Validates a session token and retrieves associated customer profile.
   * @param {string} token
   * @returns {{ session: any, customer: any } | null}
   */
  findByToken(token) {
    if (!token || typeof token !== 'string') return null;

    const res = this.db.queryOne(
      'SELECT * FROM customer_sessions WHERE token = ? AND is_active = true',
      [token]
    );

    return handleResult(this.db, res, row => {
      if (!row) return null;

      const expiresAt = new Date(row.expires_at);
      if (expiresAt.getTime() <= Date.now()) {
        try {
          this.db.execute('UPDATE customer_sessions SET is_active = false, updated_at = ? WHERE id = ?', [
            new Date().toISOString(),
            row.id
          ]);
        } catch {}
        return null;
      }

      const session = {
        id: row.id,
        customerId: row.customer_id,
        token: row.token,
        expiresAt,
        isActive: Boolean(row.is_active),
        createdAt: new Date(row.created_at)
      };

      if (this.customerRepo) {
        const custRes = this.customerRepo.findById(row.customer_id);
        return handleResult(this.db, custRes, customer => {
          if (!customer || customer.status !== 'ACTIVE') return null;
          return { session, customer };
        });
      }

      const custRes = this.db.queryOne('SELECT * FROM customers WHERE id = ?', [row.customer_id]);
      return handleResult(this.db, custRes, custRow => {
        if (!custRow) return null;
        const customer = {
          id: custRow.id,
          name: custRow.name,
          email: custRow.email,
          mobileNumber: custRow.mobile_number,
          status: custRow.status,
          createdAt: new Date(custRow.created_at),
          updatedAt: new Date(custRow.updated_at)
        };
        if (customer.status !== 'ACTIVE') return null;
        return { session, customer };
      });
    });
  }

  /**
   * Revokes a session token (logout).
   * @param {string} token
   * @returns {boolean}
   */
  revokeToken(token) {
    if (!token) return false;
    const now = new Date().toISOString();
    const res = this.db.execute(
      'UPDATE customer_sessions SET is_active = false, updated_at = ? WHERE token = ?',
      [now, token]
    );
    return handleResult(this.db, res, () => true);
  }

  /**
   * Revokes all active sessions for a customer.
   * @param {string} customerId
   */
  revokeAllForCustomer(customerId) {
    if (!customerId) return;
    const now = new Date().toISOString();
    const res = this.db.execute(
      'UPDATE customer_sessions SET is_active = false, updated_at = ? WHERE customer_id = ?',
      [now, customerId]
    );
    return handleResult(this.db, res, () => undefined);
  }

  /**
   * Returns count of currently active sessions.
   * @returns {number}
   */
  countActive() {
    const res = this.db.queryOne(
      'SELECT COUNT(*) as c FROM customer_sessions WHERE is_active = true AND expires_at > ?',
      [new Date().toISOString()]
    );
    return handleResult(this.db, res, row => Number(row?.c || 0));
  }
}
