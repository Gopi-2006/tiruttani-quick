const admin = require("firebase-admin");

/**
 * Security Cache Store
 * Stores rate limiting and lockout state in-memory.
 * Interface uses async/await to support drop-in replacement with Redis or Upstash clients.
 */
class SecurityCacheStore {
  constructor() {
    this.ipLogs = new Map(); // ip -> Array of timestamps
    this.failedAttempts = new Map(); // email -> { count: number, lockUntil: number | null, lastAttempt: number }
  }

  // --- IP Rate Limiting ---
  async getIpTimestamps(ip) {
    return this.ipLogs.get(ip) || [];
  }

  async setIpTimestamps(ip, timestamps) {
    this.ipLogs.set(ip, timestamps);
  }

  // --- Account Lockout ---
  async getFailedAttempts(email) {
    const record = this.failedAttempts.get(email);
    if (!record) {
      return { count: 0, lockUntil: null, lastAttempt: 0 };
    }
    return record;
  }

  async setFailedAttempts(email, record) {
    this.failedAttempts.set(email, record);
  }

  async clearFailedAttempts(email) {
    this.failedAttempts.delete(email);
  }
}

// Global instance of cache store (in-memory)
const securityCache = new SecurityCacheStore();

/**
 * IP-based Rate Limiter Middleware
 * Limits requests to max 10 requests per IP per minute.
 */
async function rateLimiterMiddleware(req, res, next) {
  try {
    const ip = req.ip || req.headers["x-forwarded-for"] || req.socket.remoteAddress || "unknown-ip";
    const now = Date.now();
    const windowMs = 60 * 1000; // 1 minute
    const maxRequests = 10;

    let timestamps = await securityCache.getIpTimestamps(ip);

    // Filter out timestamps outside the sliding 1-minute window
    timestamps = timestamps.filter((t) => now - t < windowMs);

    if (timestamps.length >= maxRequests) {
      console.warn(`Rate limit exceeded for IP: ${ip}`);
      return res.status(429).json({
        error: "Too many login attempts. Please try again in a minute."
      });
    }

    // Add current request timestamp and save
    timestamps.push(now);
    await securityCache.setIpTimestamps(ip, timestamps);
    
    next();
  } catch (error) {
    console.error("Error in rate limiting middleware:", error);
    // Fail-open for user experience, or fail-closed for security. Here we fail-open but log it.
    next();
  }
}

/**
 * Calculates progressive delay in milliseconds based on consecutive failures.
 * 1st attempt: 1s
 * 2nd attempt: 2s
 * 3rd attempt: 4s
 * 4th attempt: 8s
 * 5th attempt: 15s (capped)
 */
function getProgressiveDelayMs(count) {
  if (count <= 0) return 0;
  const delay = Math.pow(2, count - 1) * 1000;
  return Math.min(delay, 15000); // Cap delay at 15 seconds to prevent gateway timeout
}

/**
 * Sends a lockout notification email to the user with a reset link.
 */
async function sendLockoutEmail(email, resetLink) {
  console.log(`[Email Dispatch] Preparing account lockout notification email for: ${email}`);
  console.log(`[Email Dispatch] Reset/Unlock link: ${resetLink}`);

  try {
    // Attempt to use nodemailer if configuration is available (via env or runtime configs)
    // In production, configure nodemailer SMTP transporter, SendGrid, or Firebase trigger-email extension.
    const nodemailer = require("nodemailer");
    
    const smtpHost = process.env.SMTP_HOST;
    const smtpPort = process.env.SMTP_PORT || 587;
    const smtpUser = process.env.SMTP_USER;
    const smtpPass = process.env.SMTP_PASS;

    if (smtpHost && smtpUser && smtpPass) {
      const transporter = nodemailer.createTransport({
        host: smtpHost,
        port: smtpPort,
        secure: smtpPort === 465,
        auth: {
          user: smtpUser,
          pass: smtpPass,
        },
      });

      const mailOptions = {
        from: '"Blinkit Security" <security@blinkit-grocery.com>',
        to: email,
        subject: "Security Alert: Your account has been temporarily locked",
        html: `
          <div style="font-family: sans-serif; padding: 20px; line-height: 1.6;">
            <h2>Account Temporarily Locked</h2>
            <p>We detected multiple failed login attempts on your Blinkit account.</p>
            <p>To protect your security, your account has been locked for 15 minutes.</p>
            <p>You can unlock it immediately or reset your password using the link below:</p>
            <p style="margin: 20px 0;">
              <a href="${resetLink}" style="background-color: #e21b3c; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; font-weight: bold; display: inline-block;">
                Reset Password & Unlock Account
              </a>
            </p>
            <p>If you did not initiate this, please ignore this email or contact support.</p>
          </div>
        `,
      };

      await transporter.sendMail(mailOptions);
      console.log(`[Email Dispatch] Lockout notification email successfully sent via SMTP to ${email}`);
    } else {
      console.log(`[Email Dispatch] SMTP credentials not fully configured in env. Simulating email dispatch to: ${email}`);
    }
  } catch (error) {
    console.error(`[Email Dispatch] Failed to dispatch lockout email to ${email}:`, error);
  }
}

/**
 * Checks if the account is currently locked out.
 * If locked out, applies the progressive delay and returns true.
 */
async function checkAccountLockout(email, res) {
  const record = await securityCache.getFailedAttempts(email);
  const now = Date.now();

  if (record.lockUntil && now < record.lockUntil) {
    console.warn(`Blocked login attempt: Account for ${email} is locked until ${new Date(record.lockUntil).toISOString()}`);

    // Still apply a progressive delay (based on 5 attempts = 15s) to avoid timing analysis
    const delayMs = getProgressiveDelayMs(5);
    await new Promise((resolve) => setTimeout(resolve, delayMs));

    // NEVER reveal whether the lockout is due to too many attempts vs wrong password.
    // Return generic 401 Unauthorized with standard wrong credentials message.
    return res.status(401).json({
      error: "Invalid email or password."
    });
  }

  return null;
}

/**
 * Handles a failed login attempt.
 * Increments failed attempts, checks if lockout limit (5) is met,
 * triggers reset email notification, and sleeps for progressive delay.
 */
async function handleLoginFailure(email, res) {
  const record = await securityCache.getFailedAttempts(email);
  const now = Date.now();

  const newCount = record.count + 1;
  let lockUntil = record.lockUntil;

  if (newCount >= 5) {
    lockUntil = now + 15 * 60 * 1000; // 15 minutes lockout
    console.warn(`Account locked for ${email} due to 5 consecutive failures.`);

    // Generate genuine Firebase Auth password reset link
    try {
      const resetLink = await admin.auth().generatePasswordResetLink(email);
      // Fire-and-forget sending the email in background so login response timing is not further affected
      sendLockoutEmail(email, resetLink).catch(err => console.error("Error in background email task:", err));
    } catch (error) {
      console.error("Firebase generatePasswordResetLink failed (possibly user does not exist in Auth yet):", error.message);
    }
  }

  await securityCache.setFailedAttempts(email, {
    count: newCount,
    lockUntil: lockUntil,
    lastAttempt: now
  });

  // Calculate delay based on the attempt number (1st, 2nd, etc.)
  const delayMs = getProgressiveDelayMs(newCount);
  console.log(`Failed login #${newCount} for ${email}. Applying progressive delay of ${delayMs}ms.`);
  await new Promise((resolve) => setTimeout(resolve, delayMs));

  // Generic security message
  return res.status(401).json({
    error: "Invalid email or password."
  });
}

/**
 * Clears failed attempts upon a successful login.
 */
async function handleLoginSuccess(email) {
  await securityCache.clearFailedAttempts(email);
}

module.exports = {
  rateLimiterMiddleware,
  checkAccountLockout,
  handleLoginFailure,
  handleLoginSuccess,
  securityCache, // Exported to allow tests to clear or inspect cache
};
