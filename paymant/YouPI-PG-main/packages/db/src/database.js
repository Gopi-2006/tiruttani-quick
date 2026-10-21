import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import pg from 'pg';
import { runMigrations } from './migrate.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '../../..');

/**
 * Translates ? positional parameters to $1, $2, ... for PostgreSQL,
 * and normalizes SQLite boolean integers / datetime expressions to valid Postgres syntax.
 */
export function translateToPositionalParams(sql) {
  let s = sql;
  s = s.replace(/\bis_active\s*=\s*1\b/gi, 'is_active = true');
  s = s.replace(/\bis_active\s*=\s*0\b/gi, 'is_active = false');
  s = s.replace(/\bis_slot_busy\s*=\s*1\b/gi, 'is_slot_busy = true');
  s = s.replace(/\bis_slot_busy\s*=\s*0\b/gi, 'is_slot_busy = false');
  s = s.replace(/\bis_merchant_enabled\s*=\s*1\b/gi, 'is_merchant_enabled = true');
  s = s.replace(/\bis_merchant_enabled\s*=\s*0\b/gi, 'is_merchant_enabled = false');
  s = s.replace(/\bis_phone_verified\s*=\s*1\b/gi, 'is_phone_verified = true');
  s = s.replace(/\bis_phone_verified\s*=\s*0\b/gi, 'is_phone_verified = false');
  s = s.replace(/datetime\\?\(['"]now\\?['"],\s*\\?['"]-?(\d+)\s*(seconds?|minutes?|hours?|days?)\\?['"]\)/gi, "(NOW() - INTERVAL '$1 $2')");
  s = s.replace(/datetime\\?\(['"]now\\?['"]\)/gi, "NOW()");

  if (s.includes('$1') || !s.includes('?')) return s;
  let idx = 0;
  return s.replace(/\?/g, () => `$${++idx}`);
}

/**
 * Bridges synchronous SQLite results and asynchronous PostgreSQL Promises
 * so repositories support both seamlessly.
 */
export function handleResult(db, queryPromiseOrResult, mapFn) {
  const transform = (res) => {
    if (res === null || res === undefined) return null;
    if (!mapFn) return res;
    if (Array.isArray(res)) {
      try {
        const whole = mapFn(res);
        if (Array.isArray(whole)) return whole;
      } catch {}
      return res.map(mapFn);
    }
    return mapFn(res);
  };

  if (db && db.dialect === 'postgres') {
    return Promise.resolve(queryPromiseOrResult).then(transform);
  }
  return transform(queryPromiseOrResult);
}

/**
 * Checks if core tables exist and executes migrations if not yet initialized.
 * @param {DatabaseAdapter} db
 */
export function ensureDatabaseInitialized(db) {
  try {
    if (db.dialect === 'postgres') {
      const check = db.queryOne("SELECT count(*) as count FROM information_schema.tables WHERE table_name = 'merchants'");
      if (check && typeof check.then === 'function') {
        return check.then(row => {
          if (!row || Number(row.count) === 0) {
            return runMigrations(db);
          }
        }).catch(() => runMigrations(db));
      }
      return runMigrations(db);
    } else {
      const row = db.queryOne("SELECT count(*) as count FROM sqlite_master WHERE type='table' AND name='merchants'");
      if (!row || Number(row.count) === 0) {
        return runMigrations(db);
      }
    }
  } catch {
    return runMigrations(db);
  }
}

/**
 * SQLite Database Adapter wrapping native node:sqlite DatabaseSync.
 * Provides dual synchronous/asynchronous support for zero-dependency local execution and testing.
 */
export class SqliteDatabaseAdapter {
  get isPostgres() {
    return false;
  }

  constructor(options = {}) {
    this.dialect = 'sqlite';
    if (options.inMemory) {
      this.db = new DatabaseSync(':memory:');
    } else {
      let dbPath;
      if (options.dbPath) {
        dbPath = path.isAbsolute(options.dbPath)
          ? options.dbPath
          : path.resolve(process.cwd(), options.dbPath);
      } else if (process.env.SQLITE_DB_PATH) {
        dbPath = path.isAbsolute(process.env.SQLITE_DB_PATH)
          ? process.env.SQLITE_DB_PATH
          : path.resolve(repoRoot, process.env.SQLITE_DB_PATH);
      } else {
        dbPath = path.resolve(repoRoot, 'data/youpi_pg.sqlite');
      }
      const dir = path.dirname(dbPath);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
      this.db = new DatabaseSync(dbPath);
    }

    // Enable foreign keys, busy timeout, and WAL mode
    this.db.exec('PRAGMA foreign_keys = ON;');
    this.db.exec('PRAGMA busy_timeout = 5000;');
    try {
      this.db.exec('PRAGMA journal_mode = WAL;');
    } catch {}

    if (!options.inMemory && options.autoMigrate !== false) {
      ensureDatabaseInitialized(this);
    }
  }

  normalizeSql(sql) {
    return sql.replace(/\$\d+/g, '?');
  }

  normalizeParams(params = []) {
    if (!Array.isArray(params)) return params;
    return params.map(p => (typeof p === 'boolean' ? (p ? 1 : 0) : p));
  }

  execute(sql, params = []) {
    const normalized = this.normalizeSql(sql);
    const stmt = this.db.prepare(normalized);
    const res = stmt.run(...this.normalizeParams(params));
    return res;
  }

  run(sql, params = []) {
    return this.execute(sql, params);
  }

  query(sql, params = []) {
    const normalized = this.normalizeSql(sql);
    const stmt = this.db.prepare(normalized);
    const rows = stmt.all(...this.normalizeParams(params));
    return rows;
  }

  queryOne(sql, params = []) {
    const normalized = this.normalizeSql(sql);
    const stmt = this.db.prepare(normalized);
    const res = stmt.get(...this.normalizeParams(params));
    return res !== undefined ? res : null;
  }

  exec(sql) {
    this.db.exec(sql);
    return { changes: 0 };
  }

  get inTransaction() {
    return Boolean(this._inTransactionDepth && this._inTransactionDepth > 0);
  }

  transaction(callback) {
    if (this.inTransaction) {
      const savepoint = `sp_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
      this.db.exec(`SAVEPOINT ${savepoint};`);
      this._inTransactionDepth = (this._inTransactionDepth || 0) + 1;
      try {
        const result = callback(this);
        if (result && typeof result.then === 'function') {
          return result.then(
            res => {
              this.db.exec(`RELEASE SAVEPOINT ${savepoint};`);
              this._inTransactionDepth--;
              return res;
            },
            err => {
              try { this.db.exec(`ROLLBACK TO SAVEPOINT ${savepoint};`); } catch {}
              this._inTransactionDepth--;
              throw err;
            }
          );
        }
        this.db.exec(`RELEASE SAVEPOINT ${savepoint};`);
        this._inTransactionDepth--;
        return result;
      } catch (err) {
        try { this.db.exec(`ROLLBACK TO SAVEPOINT ${savepoint};`); } catch {}
        this._inTransactionDepth--;
        throw err;
      }
    }

    this.db.exec('BEGIN IMMEDIATE;');
    this._inTransactionDepth = 1;
    try {
      const result = callback(this);
      if (result && typeof result.then === 'function') {
        return result.then(
          res => {
            this.db.exec('COMMIT;');
            this._inTransactionDepth = 0;
            return res;
          },
          err => {
            try { this.db.exec('ROLLBACK;'); } catch {}
            this._inTransactionDepth = 0;
            throw err;
          }
        );
      }
      this.db.exec('COMMIT;');
      this._inTransactionDepth = 0;
      return result;
    } catch (err) {
      try { this.db.exec('ROLLBACK;'); } catch {}
      this._inTransactionDepth = 0;
      throw err;
    }
  }

  close() {
    this.db.close();
  }
}

/**
 * PostgreSQL Transaction Client for isolation within BEGIN ... COMMIT / ROLLBACK.
 */
export class PostgresTransactionAdapter {
  get isPostgres() {
    return true;
  }

  constructor(client) {
    this.client = client;
    this.dialect = 'postgres';
  }

  async query(sql, params = []) {
    const s = translateToPositionalParams(sql);
    const res = await this.client.query(s, params);
    return res.rows;
  }

  async queryOne(sql, params = []) {
    const rows = await this.query(sql, params);
    return rows[0] || null;
  }

  async execute(sql, params = []) {
    const s = translateToPositionalParams(sql);
    const res = await this.client.query(s, params);
    return { changes: res.rowCount || 0, lastInsertRowid: null };
  }

  async run(sql, params = []) {
    return this.execute(sql, params);
  }

  async exec(sql) {
    await this.client.query(sql);
  }

  async transaction(callback) {
    const savepoint = `sp_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    await this.client.query(`SAVEPOINT ${savepoint};`);
    try {
      const res = await callback(this);
      await this.client.query(`RELEASE SAVEPOINT ${savepoint};`);
      return res;
    } catch (err) {
      await this.client.query(`ROLLBACK TO SAVEPOINT ${savepoint};`);
      throw err;
    }
  }
}

/**
 * PostgreSQL Database Adapter backed by connection pool (pg.Pool).
 */
export class PostgresDatabaseAdapter {
  get isPostgres() {
    return true;
  }

  constructor(options = {}) {
    this.dialect = 'postgres';
    const connectionString = options.connectionString || process.env.DATABASE_URL;
    if (!connectionString) {
      throw new Error('PostgresDatabaseAdapter requires a connectionString or DATABASE_URL');
    }
    const isSslRequired = options.ssl !== undefined
      ? options.ssl
      : (process.env.DATABASE_SSL === 'true' || connectionString.includes('sslmode=require') || connectionString.includes('neon.tech') || connectionString.includes('supabase.co'));

    this.pool = new pg.Pool({
      connectionString,
      max: Number(process.env.DATABASE_POOL_MAX || options.max || 10),
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 15000,
      keepAlive: true,
      keepAliveInitialDelayMillis: 10000,
      ssl: isSslRequired ? { rejectUnauthorized: false } : false
    });

    this.pool.on('error', (err) => {
      console.warn('[PostgresPool] Background idle connection warning (recovering automatically):', err.message);
    });
  }

  async query(sql, params = []) {
    const s = translateToPositionalParams(sql);
    let lastErr;
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        const res = await this.pool.query(s, params);
        return res.rows;
      } catch (err) {
        lastErr = err;
        const isConnErr = err.code === 'ECONNRESET' ||
          err.message?.includes('Connection terminated') ||
          err.message?.includes('connection timeout') ||
          err.message?.includes('timeout');
        if (isConnErr && attempt < 2) {
          console.warn(`[Postgres] Connection dropped or timed out, retrying query (attempt ${attempt + 1})...`);
          await new Promise(r => setTimeout(r, 1000));
          continue;
        }
        throw err;
      }
    }
    throw lastErr;
  }

  async queryOne(sql, params = []) {
    const rows = await this.query(sql, params);
    return rows[0] || null;
  }

  async execute(sql, params = []) {
    const s = translateToPositionalParams(sql);
    let lastErr;
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        const res = await this.pool.query(s, params);
        return { changes: res.rowCount || 0, lastInsertRowid: null };
      } catch (err) {
        lastErr = err;
        const isConnErr = err.code === 'ECONNRESET' ||
          err.message?.includes('Connection terminated') ||
          err.message?.includes('connection timeout') ||
          err.message?.includes('timeout');
        if (isConnErr && attempt < 2) {
          console.warn(`[Postgres] Connection dropped or timed out, retrying execute (attempt ${attempt + 1})...`);
          await new Promise(r => setTimeout(r, 1000));
          continue;
        }
        throw err;
      }
    }
    throw lastErr;
  }

  async run(sql, params = []) {
    return this.execute(sql, params);
  }

  async exec(sql) {
    await this.pool.query(sql);
  }

  async transaction(callback) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const tx = new PostgresTransactionAdapter(client);
      const res = await callback(tx);
      await client.query('COMMIT');
      return res;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async close() {
    await this.pool.end();
  }
}

/**
 * Universal Database Factory & Exported Class.
 */
export class Database {
  constructor(options = {}) {
    const isProd = process.env.NODE_ENV === 'production';
    const useFallback = process.env.USE_SQLITE_FALLBACK === 'true';
    const isPg = Boolean(
      !options.inMemory &&
      options.dialect !== 'sqlite' &&
      (options.dialect === 'postgres' ||
        (process.env.DATABASE_URL && process.env.DATABASE_URL.startsWith('postgres') && (!useFallback || isProd)))
    );

    if (isProd && !isPg && !options.inMemory) {
      throw new Error(
        '[FATAL] Production database configuration error: DATABASE_URL must be a valid PostgreSQL connection string. ' +
        'Silent SQLite fallback is strictly prohibited in production mode.'
      );
    }

    if (isPg) {
      return new PostgresDatabaseAdapter(options);
    }
    return new SqliteDatabaseAdapter(options);
  }
}

let defaultDbInstance = null;

/**
 * Returns the singleton database instance.
 * @param {{ dbPath?: string, inMemory?: boolean }} [options={}]
 * @returns {SqliteDatabaseAdapter | PostgresDatabaseAdapter}
 */
export function getDatabase(options = {}) {
  if (!defaultDbInstance) {
    defaultDbInstance = new Database(options);
    ensureDatabaseInitialized(defaultDbInstance);
  }
  return defaultDbInstance;
}
