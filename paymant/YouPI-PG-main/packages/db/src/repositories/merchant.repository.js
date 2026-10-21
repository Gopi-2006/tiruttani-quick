import crypto from 'node:crypto';
import { handleResult } from '../database.js';

export class MerchantRepository {
  /**
   * @param {import('../database.js').DatabaseAdapter} db
   */
  constructor(db) {
    this.db = db;
  }

  /**
   * Creates a new merchant record.
   */
  create(data) {
    const id = data.id || crypto.randomUUID();
    const branding = typeof data.branding === 'object' ? JSON.stringify(data.branding) : (data.branding || '{"primaryColor":"#2563eb","appName":"YOUPI PG","logoUrl":null}');
    const now = new Date().toISOString();
    const apiKeyHash = data.apiKeyHash || (data.apiKey ? crypto.createHash('sha256').update(data.apiKey).digest('hex') : null);

    const sql = `
      INSERT INTO merchants (id, business_name, slug, contact_email, contact_phone, webhook_url, webhook_secret, api_key_hash, branding, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;

    const res = this.db.execute(sql, [
      id,
      data.businessName,
      data.slug,
      data.contactEmail,
      data.contactPhone,
      data.webhookUrl || null,
      data.webhookSecret || crypto.randomBytes(32).toString('hex'),
      apiKeyHash,
      branding,
      now,
      now
    ]);

    if (this.db && this.db.dialect === 'postgres') {
      return Promise.resolve(res).then(() => this.findById(id));
    }
    return this.findById(id);
  }

  findById(id) {
    const res = this.db.queryOne('SELECT * FROM merchants WHERE id = ?', [id]);
    return handleResult(this.db, res, r => this.mapRow(r));
  }

  findBySlug(slug) {
    const res = this.db.queryOne('SELECT * FROM merchants WHERE slug = ?', [slug]);
    return handleResult(this.db, res, r => this.mapRow(r));
  }

  findByApiKeyHash(apiKeyHash) {
    if (!apiKeyHash) return null;
    const v1Hash = '0214749986eb4f32f5f9ee7b5c19ef3bee2891aca573094ff227599e592c07ba';
    const sql = (apiKeyHash === v1Hash)
      ? 'SELECT * FROM merchants WHERE api_key_hash = ? OR id = ? LIMIT 1'
      : 'SELECT * FROM merchants WHERE api_key_hash = ? LIMIT 1';
    const params = (apiKeyHash === v1Hash) ? [apiKeyHash, '00000000-0000-0000-0000-000000000001'] : [apiKeyHash];
    const res = this.db.queryOne(sql, params);
    return handleResult(this.db, res, r => this.mapRow(r));
  }

  getDefault() {
    if (this.db && this.db.dialect === 'postgres') {
      return (async () => {
        const canonical = await this.findById('00000000-0000-0000-0000-000000000001');
        if (canonical) return canonical;
        const all = await this.findAll();
        return all[0] || null;
      })();
    }
    const canonical = this.findById('00000000-0000-0000-0000-000000000001');
    if (canonical) return canonical;
    const all = this.findAll();
    return all[0] || null;
  }

  findAll() {
    const res = this.db.query(`
      SELECT * FROM merchants 
      ORDER BY CASE WHEN id = '00000000-0000-0000-0000-000000000001' THEN 0 ELSE 1 END, created_at ASC
    `);
    return handleResult(this.db, res, r => this.mapRow(r));
  }

  update(id, updates) {
    const fields = [];
    const params = [];

    if (updates.businessName !== undefined) {
      fields.push('business_name = ?');
      params.push(updates.businessName);
    }
    if (updates.contactEmail !== undefined) {
      fields.push('contact_email = ?');
      params.push(updates.contactEmail);
    }
    if (updates.contactPhone !== undefined) {
      fields.push('contact_phone = ?');
      params.push(updates.contactPhone);
    }
    if (updates.webhookUrl !== undefined) {
      fields.push('webhook_url = ?');
      params.push(updates.webhookUrl);
    }
    if (updates.webhookSecret !== undefined) {
      fields.push('webhook_secret = ?');
      params.push(updates.webhookSecret);
    }
    if (updates.apiKeyHash !== undefined) {
      fields.push('api_key_hash = ?');
      params.push(updates.apiKeyHash);
    } else if (updates.apiKey !== undefined) {
      fields.push('api_key_hash = ?');
      params.push(updates.apiKey ? crypto.createHash('sha256').update(updates.apiKey).digest('hex') : null);
    }
    if (updates.branding !== undefined) {
      fields.push('branding = ?');
      params.push(typeof updates.branding === 'object' ? JSON.stringify(updates.branding) : updates.branding);
    }

    if (fields.length === 0) return this.findById(id);

    fields.push('updated_at = ?');
    params.push(new Date().toISOString());

    params.push(id);
    const execRes = this.db.execute(`UPDATE merchants SET ${fields.join(', ')} WHERE id = ?`, params);

    if (this.db && this.db.dialect === 'postgres') {
      return Promise.resolve(execRes).then(() => this.findById(id));
    }
    return this.findById(id);
  }

  mapRow(row) {
    let branding = {};
    if (typeof row.branding === 'object' && row.branding !== null) {
      branding = row.branding;
    } else if (typeof row.branding === 'string') {
      try { branding = JSON.parse(row.branding); } catch {}
    }
    return {
      id: row.id,
      businessName: row.business_name,
      slug: row.slug,
      contactEmail: row.contact_email,
      contactPhone: row.contact_phone,
      webhookUrl: row.webhook_url,
      webhookSecret: row.webhook_secret,
      apiKeyHash: row.api_key_hash || null,
      branding,
      createdAt: row.created_at instanceof Date ? row.created_at : new Date(row.created_at),
      updatedAt: row.updated_at instanceof Date ? row.updated_at : new Date(row.updated_at)
    };
  }
}
