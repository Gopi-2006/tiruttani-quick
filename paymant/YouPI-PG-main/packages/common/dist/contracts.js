/**
 * Normalizes an email address to trimmed lowercase.
 */
export function normalizeEmail(email) {
    if (!email || typeof email !== 'string')
        return '';
    return email.trim().toLowerCase();
}
/**
 * Validates email format with standard requirements.
 */
export function isValidEmail(email) {
    const norm = normalizeEmail(email);
    if (!norm)
        return false;
    return /^[^\s@]+@[^\s@]+\.[a-zA-Z]{2,}$/.test(norm);
}
/**
 * Normalizes a mobile number to canonical 10 digits (stripping prefixes and country codes).
 */
export function normalizeMobile(mobile) {
    if (!mobile)
        return '';
    const cleaned = String(mobile).replace(/\D/g, '');
    if (cleaned.length >= 10) {
        return cleaned.slice(-10);
    }
    return cleaned;
}
/**
 * Validates canonical Indian 10-digit mobile number format.
 */
export function isValidMobile(mobile) {
    const norm = normalizeMobile(mobile);
    return /^[6-9]\d{9}$/.test(norm);
}
/**
 * Validates password strength (minimum 6 characters).
 */
export function isValidPassword(password) {
    return typeof password === 'string' && password.length >= 6;
}
//# sourceMappingURL=contracts.js.map