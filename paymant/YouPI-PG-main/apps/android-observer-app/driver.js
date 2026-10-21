import { generateHmac } from '@youpi/common';

/**
 * Android Observer Simulator / Driver.
 * Emulates the native Android Kotlin application for headless testing,
 * CI/CD verification, and local development.
 */
export class AndroidObserverDriver {
  /**
   * @param {{
   *   apiBaseUrl?: string,
   *   deviceName?: string,
   *   deviceModel?: string
   * }} options
   */
  constructor(options = {}) {
    this.apiBaseUrl = (options.apiBaseUrl || process.env.BASE_PAYMENT_API_URL || 'http://localhost:6100').replace(/\/+$/, '');
    this.deviceName = options.deviceName || 'Pixel 8 Pro';
    this.deviceModel = options.deviceModel || 'Google Pixel';

    this.deviceId = null;
    this.signingKey = null;
    this.heartbeatTimer = null;
    this.outbox = Array.isArray(options.outbox) ? [...options.outbox] : [];
    this.maxRetries = options.maxRetries || 5;
  }

  /**
   * Pairs device with self-hosted gateway using enrollment token.
   * @param {string} enrollmentToken
   * @param {string} [merchantId]
   */
  async pair(enrollmentToken, merchantId = null) {
    const url = `${this.apiBaseUrl}/api/v1/pollers/android/pair`;
    const payload = {
      enrollmentToken,
      deviceName: this.deviceName,
      deviceModel: this.deviceModel,
      merchantId
    };

    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    if (!res.ok) {
      const err = await res.text();
      throw new Error(`Device pairing failed [HTTP ${res.status}]: ${err}`);
    }

    const data = await res.json();
    this.deviceId = data.deviceId;
    this.signingKey = data.signingKey;

    return data;
  }

  /**
   * Submits a signed payment observation to backend.
   * @param {{
   *   amount: string | number,
   *   amountPaise?: bigint | number,
   *   receivingAccountId?: string,
   *   observedAt?: Date | string,
   *   utr?: string,
   *   senderVpa?: string,
   *   notificationText?: string,
   *   timestampOverride?: number
   * }} obs
   */
  async submitObservation(obs) {
    if (!this.deviceId || !this.signingKey) {
      throw new Error('Device must be paired before submitting observations.');
    }

    const url = `${this.apiBaseUrl}/api/v1/pollers/android/events`;
    const timestamp = (obs.timestampOverride !== undefined ? obs.timestampOverride : Date.now()).toString();

    const bodyObj = {
      deviceId: this.deviceId,
      receivingAccountId: obs.receivingAccountId || '00000000-0000-0000-0000-000000000002',
      amount: obs.amount,
      amountPaise: obs.amountPaise !== undefined ? obs.amountPaise.toString() : undefined,
      observedAt: (obs.observedAt instanceof Date ? obs.observedAt : new Date(obs.observedAt || Date.now())).toISOString(),
      bankReferenceNumber: obs.utr,
      senderVpa: obs.senderVpa,
      rawNotification: {
        title: 'Payment Received',
        text: obs.notificationText || `Received Rs ${obs.amount} via UPI`,
        package: 'com.phonepe.app'
      }
    };

    const bodyString = JSON.stringify(bodyObj);
    const sigPayload = `${bodyString}:${timestamp}`;
    const signature = generateHmac(sigPayload, this.signingKey);

    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Device-Id': this.deviceId,
        'X-Timestamp': timestamp,
        'X-Signature': signature
      },
      body: bodyString
    });

    const respText = await res.text();
    let respJson;
    try {
      respJson = JSON.parse(respText);
    } catch {
      respJson = { raw: respText };
    }

    return {
      status: res.status,
      body: respJson
    };
  }

  /**
   * Submits heartbeat to backend.
   */
  async sendHeartbeat() {
    if (!this.deviceId) throw new Error('Cannot send heartbeat: device not paired.');
    const url = `${this.apiBaseUrl}/api/v1/pollers/android/heartbeat`;

    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Device-Id': this.deviceId
      },
      body: JSON.stringify({ deviceId: this.deviceId, timestamp: Date.now() })
    });

    return await res.json();
  }

  startHeartbeat(intervalMs = 60000) {
    if (this.heartbeatTimer) return;
    this.heartbeatTimer = setInterval(() => {
      this.sendHeartbeat().catch(() => {});
    }, intervalMs);
  }

  stopHeartbeat() {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  /**
   * Enqueues an observation into the offline outbox without storing raw SMS text.
   * @param {object} obs
   */
  queueToOutbox(obs) {
    const entry = {
      eventId: obs.eventId || `evt_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`,
      amount: String(obs.amount),
      amountPaise: obs.amountPaise !== undefined ? obs.amountPaise.toString() : undefined,
      receivingAccountId: obs.receivingAccountId,
      observedAt: obs.observedAt ? (obs.observedAt instanceof Date ? obs.observedAt.toISOString() : obs.observedAt) : new Date().toISOString(),
      utr: obs.utr,
      senderVpa: obs.senderVpa,
      retryCount: obs.retryCount || 0,
      createdAt: obs.createdAt || Date.now()
    };
    this.outbox.push(entry);
    return entry;
  }

  getOutbox() {
    return [...this.outbox];
  }

  clearOutbox() {
    this.outbox = [];
  }

  /**
   * Flushes outbox queue. Retries pending events with fresh X-Timestamp
   * while preserving original observedAt and bankReferenceNumber.
   */
  async flushOutbox() {
    const remaining = [];
    const results = [];

    for (const item of this.outbox) {
      if (item.retryCount >= this.maxRetries) {
        results.push({ eventId: item.eventId, status: 'EXHAUSTED', error: 'Max retries exceeded' });
        continue;
      }

      try {
        const res = await this.submitObservation({
          amount: item.amount,
          amountPaise: item.amountPaise,
          receivingAccountId: item.receivingAccountId,
          observedAt: item.observedAt,
          utr: item.utr,
          senderVpa: item.senderVpa,
          notificationText: `Payment received: ${item.amount}`
        });

        if (res.status === 200 || res.body?.accepted || res.body?.status === 'ALREADY_PROCESSED') {
          results.push({ eventId: item.eventId, status: 'DELIVERED', response: res.body });
        } else {
          item.retryCount += 1;
          remaining.push(item);
          results.push({ eventId: item.eventId, status: 'RETRY_PENDING', httpStatus: res.status });
        }
      } catch (err) {
        item.retryCount += 1;
        remaining.push(item);
        results.push({ eventId: item.eventId, status: 'FAILED_RETRY_SCHEDULED', error: err.message });
      }
    }

    this.outbox = remaining;
    return results;
  }

  /**
   * Attempts immediate delivery, falling back to offline outbox if offline.
   * @param {object} obs
   */
  async submitObservationWithOutbox(obs) {
    try {
      const res = await this.submitObservation(obs);
      if (res.status === 200 && (res.body?.accepted || res.body?.status === 'ALREADY_PROCESSED')) {
        return { delivered: true, outbox: false, response: res };
      }
      const queued = this.queueToOutbox(obs);
      return { delivered: false, outbox: true, entry: queued, response: res };
    } catch (networkErr) {
      const queued = this.queueToOutbox(obs);
      return { delivered: false, outbox: true, entry: queued, error: networkErr.message };
    }
  }
}
