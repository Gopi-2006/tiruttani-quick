import crypto from 'node:crypto';
import { handleResult } from '../database.js';

export class ReceivingAccountRepository {
  /**
   * @param {import('../database.js').DatabaseAdapter} db
   */
  constructor(db) {
    this.db = db;
  }

  /**
   * Creates a new receiving UPI account.
   * If isActive is true, atomically deactivates any other active accounts for this merchant.
   * Enforces that maximum ONE VPA may be active per merchant.
   */
  create(data) {
    const id = data.id || crypto.randomUUID();
    const now = new Date().toISOString();
    const isActive = data.isActive !== undefined ? Boolean(data.isActive) : true;
    const isMerchantEnabled = data.isMerchantEnabled !== undefined ? Boolean(data.isMerchantEnabled) : true;

    if (this.db && this.db.dialect === 'postgres') {
      return this.db.transaction(async (txClient) => {
        const client = txClient || this.db;
        if (isActive) {
          await client.execute(`
            UPDATE payment_receiving_accounts
            SET is_active = false, updated_at = ?
            WHERE merchant_id = ?
          `, [now, data.merchantId]);
        }

        const sql = `
          INSERT INTO payment_receiving_accounts (
            id, merchant_id, upi_id, payee_name, is_merchant_enabled,
            is_active, is_slot_busy, current_active_session_id, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `;

        await client.execute(sql, [
          id,
          data.merchantId,
          data.upiId.trim(),
          data.payeeName.trim(),
          isMerchantEnabled,
          isActive,
          false,
          null,
          now,
          now
        ]);

        return this.findById(id, client);
      });
    }

    return this.db.transaction((txClient) => {
      const client = txClient || this.db;
      if (isActive) {
        client.execute(`
          UPDATE payment_receiving_accounts
          SET is_active = false, updated_at = ?
          WHERE merchant_id = ?
        `, [now, data.merchantId]);
      }

      const sql = `
        INSERT INTO payment_receiving_accounts (
          id, merchant_id, upi_id, payee_name, is_merchant_enabled,
          is_active, is_slot_busy, current_active_session_id, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `;

      client.execute(sql, [
        id,
        data.merchantId,
        data.upiId.trim(),
        data.payeeName.trim(),
        isMerchantEnabled,
        isActive,
        false,
        null,
        now,
        now
      ]);

      return this.findById(id, client);
    });
  }

  findById(id, db = this.db) {
    const res = db.queryOne('SELECT * FROM payment_receiving_accounts WHERE id = ?', [id]);
    return handleResult(db, res, r => (r ? this.mapRow(r) : null));
  }

  findByMerchantId(merchantId, db = this.db) {
    const res = db.query(
      'SELECT * FROM payment_receiving_accounts WHERE merchant_id = ? ORDER BY is_active DESC, created_at ASC',
      [merchantId]
    );
    return handleResult(db, res, r => this.mapRow(r));
  }

  findActiveForMerchant(merchantId, db = this.db) {
    const res = db.queryOne(
      'SELECT * FROM payment_receiving_accounts WHERE merchant_id = ? AND is_active = true LIMIT 1',
      [merchantId]
    );
    return handleResult(db, res, r => (r ? this.mapRow(r) : null));
  }

  /**
   * Atomically activates an account and deactivates all other accounts for this merchant.
   * Backend invariant: At most ONE VPA active per merchant.
   */
  activateAccount(merchantId, accountId) {
    if (this.db && this.db.dialect === 'postgres') {
      return this.db.transaction(async (txClient) => {
        const client = txClient || this.db;
        const now = new Date().toISOString();

        await client.execute(`
          UPDATE payment_receiving_accounts
          SET is_active = false, updated_at = ?
          WHERE merchant_id = ?
        `, [now, merchantId]);

        await client.execute(`
          UPDATE payment_receiving_accounts
          SET is_active = true, updated_at = ?
          WHERE id = ? AND merchant_id = ?
        `, [now, accountId, merchantId]);

        return this.findById(accountId, client);
      });
    }

    return this.db.transaction((txClient) => {
      const client = txClient || this.db;
      const now = new Date().toISOString();

      client.execute(`
        UPDATE payment_receiving_accounts
        SET is_active = false, updated_at = ?
        WHERE merchant_id = ?
      `, [now, merchantId]);

      client.execute(`
        UPDATE payment_receiving_accounts
        SET is_active = true, updated_at = ?
        WHERE id = ? AND merchant_id = ?
      `, [now, accountId, merchantId]);

      return this.findById(accountId, client);
    });
  }

  /**
   * Deactivates a specific account.
   */
  deactivateAccount(merchantId, accountId) {
    const now = new Date().toISOString();
    const res = this.db.execute(`
      UPDATE payment_receiving_accounts
      SET is_active = false, updated_at = ?
      WHERE id = ? AND merchant_id = ?
    `, [now, accountId, merchantId]);

    return handleResult(this.db, res, () => this.findById(accountId));
  }

  /**
   * Updates an existing account's details.
   */
  updateAccount(id, data) {
    if (this.db && this.db.dialect === 'postgres') {
      return this.db.transaction(async (txClient) => {
        const client = txClient || this.db;
        const existing = await this.findById(id, client);
        if (!existing) return null;

        const now = new Date().toISOString();
        const upiId = data.upiId !== undefined ? data.upiId.trim() : existing.upiId;
        const payeeName = data.payeeName !== undefined ? data.payeeName.trim() : existing.payeeName;
        const isMerchantEnabled = data.isMerchantEnabled !== undefined ? Boolean(data.isMerchantEnabled) : existing.isMerchantEnabled;

        if (data.isActive === true) {
          await client.execute(`
            UPDATE payment_receiving_accounts
            SET is_active = false, updated_at = ?
            WHERE merchant_id = ?
          `, [now, existing.merchantId]);

          await client.execute(`
            UPDATE payment_receiving_accounts
            SET upi_id = ?, payee_name = ?, is_merchant_enabled = ?, is_active = true, updated_at = ?
            WHERE id = ?
          `, [upiId, payeeName, isMerchantEnabled, now, id]);
        } else if (data.isActive === false) {
          await client.execute(`
            UPDATE payment_receiving_accounts
            SET upi_id = ?, payee_name = ?, is_merchant_enabled = ?, is_active = false, updated_at = ?
            WHERE id = ?
          `, [upiId, payeeName, isMerchantEnabled, now, id]);
        } else {
          await client.execute(`
            UPDATE payment_receiving_accounts
            SET upi_id = ?, payee_name = ?, is_merchant_enabled = ?, updated_at = ?
            WHERE id = ?
          `, [upiId, payeeName, isMerchantEnabled, now, id]);
        }

        return this.findById(id, client);
      });
    }

    return this.db.transaction((txClient) => {
      const client = txClient || this.db;
      const existing = this.findById(id, client);
      if (!existing) return null;

      const now = new Date().toISOString();
      const upiId = data.upiId !== undefined ? data.upiId.trim() : existing.upiId;
      const payeeName = data.payeeName !== undefined ? data.payeeName.trim() : existing.payeeName;
      const isMerchantEnabled = data.isMerchantEnabled !== undefined ? Boolean(data.isMerchantEnabled) : existing.isMerchantEnabled;

      if (data.isActive === true) {
        client.execute(`
          UPDATE payment_receiving_accounts
          SET is_active = false, updated_at = ?
          WHERE merchant_id = ?
        `, [now, existing.merchantId]);

        client.execute(`
          UPDATE payment_receiving_accounts
          SET upi_id = ?, payee_name = ?, is_merchant_enabled = ?, is_active = true, updated_at = ?
          WHERE id = ?
        `, [upiId, payeeName, isMerchantEnabled, now, id]);
      } else if (data.isActive === false) {
        client.execute(`
          UPDATE payment_receiving_accounts
          SET upi_id = ?, payee_name = ?, is_merchant_enabled = ?, is_active = false, updated_at = ?
          WHERE id = ?
        `, [upiId, payeeName, isMerchantEnabled, now, id]);
      } else {
        client.execute(`
          UPDATE payment_receiving_accounts
          SET upi_id = ?, payee_name = ?, is_merchant_enabled = ?, updated_at = ?
          WHERE id = ?
        `, [upiId, payeeName, isMerchantEnabled, now, id]);
      }

      return this.findById(id, client);
    });
  }

  /**
   * Deletes a receiving account.
   * Throws if the slot is currently busy.
   */
  deleteAccount(merchantId, accountId) {
    if (!accountId) {
      if (this.db && this.db.dialect === 'postgres') {
        return Promise.reject(new Error('Cannot delete account: accountId is required.'));
      }
      throw new Error('Cannot delete account: accountId is required.');
    }
    if (this.db && this.db.dialect === 'postgres') {
      return Promise.resolve(this.findById(accountId)).then(account => {
        if (!account || account.merchantId !== merchantId) {
          throw new Error(`Account not found or does not belong to merchant: ${accountId}`);
        }
        if (account.isSlotBusy || account.currentActiveSessionId) {
          throw new Error(`Cannot delete account ${account.upiId} because it has an active checkout session.`);
        }
        return this.db.execute('DELETE FROM payment_receiving_accounts WHERE id = ? AND merchant_id = ?', [accountId, merchantId]).then(() => true);
      });
    }

    const account = this.findById(accountId);
    if (!account || account.merchantId !== merchantId) {
      throw new Error(`Account not found or does not belong to merchant: ${accountId}`);
    }
    if (account.isSlotBusy || account.currentActiveSessionId) {
      throw new Error(`Cannot delete account ${account.upiId} because it has an active checkout session.`);
    }
    this.db.execute('DELETE FROM payment_receiving_accounts WHERE id = ? AND merchant_id = ?', [accountId, merchantId]);
    return true;
  }

  /**
   * Sets slot busy status and currently active session ID.
   */
  setSlotStatus(id, isBusy, activeSessionId = null) {
    const now = new Date().toISOString();
    const res = this.db.execute(`
      UPDATE payment_receiving_accounts
      SET is_slot_busy = ?, current_active_session_id = ?, updated_at = ?
      WHERE id = ?
    `, [Boolean(isBusy), activeSessionId, now, id]);

    return handleResult(this.db, res, () => this.findById(id));
  }

  /**
   * Updates or creates the active receiving UPI account for a merchant.
   */
  upsertActiveForMerchant(merchantId, upiId, payeeName = null, isMerchantEnabled = true) {
    const cleanUpi = upiId.trim();

    if (this.db && this.db.dialect === 'postgres') {
      return Promise.resolve(this.findActiveForMerchant(merchantId)).then(existing => {
        const now = new Date().toISOString();
        if (existing) {
          return this.db.execute(`
            UPDATE payment_receiving_accounts
            SET upi_id = ?, payee_name = COALESCE(?, payee_name), is_merchant_enabled = ?, updated_at = ?
            WHERE id = ?
          `, [cleanUpi, payeeName?.trim() || null, Boolean(isMerchantEnabled), now, existing.id]).then(() => this.findById(existing.id));
        } else {
          return this.create({
            merchantId,
            upiId: cleanUpi,
            payeeName: payeeName?.trim() || 'Merchant Store',
            isMerchantEnabled,
            isActive: true
          });
        }
      });
    }

    const existing = this.findActiveForMerchant(merchantId);
    const now = new Date().toISOString();
    if (existing) {
      this.db.execute(`
        UPDATE payment_receiving_accounts
        SET upi_id = ?, payee_name = COALESCE(?, payee_name), is_merchant_enabled = ?, updated_at = ?
        WHERE id = ?
      `, [cleanUpi, payeeName?.trim() || null, Boolean(isMerchantEnabled), now, existing.id]);
      return this.findById(existing.id);
    } else {
      return this.create({
        merchantId,
        upiId: cleanUpi,
        payeeName: payeeName?.trim() || 'Merchant Store',
        isMerchantEnabled,
        isActive: true
      });
    }
  }

  mapRow(row) {
    if (!row) return null;
    return {
      id: row.id,
      merchantId: row.merchant_id,
      upiId: row.upi_id,
      payeeName: row.payee_name,
      isMerchantEnabled: Boolean(row.is_merchant_enabled),
      isActive: Boolean(row.is_active),
      isSlotBusy: Boolean(row.is_slot_busy),
      currentActiveSessionId: row.current_active_session_id || null,
      createdAt: new Date(row.created_at),
      updatedAt: new Date(row.updated_at)
    };
  }
}
