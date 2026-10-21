/**
 * Encrypts plaintext string using AES-256-GCM.
 * Output format: iv_hex:authTag_hex:cipher_hex
 */
export declare function encrypt(plaintext: string, masterKeyHex: string): string;
/**
 * Decrypts an AES-256-GCM ciphertext payload.
 */
export declare function decrypt(encryptedPayload: string, masterKeyHex: string): string;
/**
 * Generates an HMAC-SHA256 signature for webhooks and device authentication.
 */
export declare function generateHmac(data: string, secret: string): string;
/**
 * Timing-safe HMAC signature verification.
 */
export declare function verifyHmac(data: string, secret: string, expectedSignature: string): boolean;
/**
 * Generates a cryptographically secure random hex string.
 */
export declare function generateRandomToken(bytes?: number): string;
/**
 * Hashes a password using PBKDF2 with SHA-512 and salt.
 * Format: iterations:salt_hex:hash_hex
 */
export declare function hashPassword(password: string): string;
/**
 * Verifies a password against a stored PBKDF2 hash.
 */
export declare function verifyPassword(password: string, storedHash: string): boolean;
//# sourceMappingURL=crypto.d.ts.map