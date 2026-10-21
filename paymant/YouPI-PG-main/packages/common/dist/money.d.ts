/**
 * Financial utilities enforcing integer minor units (paise).
 * Floating-point representation is forbidden in financial calculations.
 * 1 INR = 100 paise.
 */
/**
 * Converts a rupee amount (string or number) into integer paise (bigint).
 * Throws an error if invalid, negative, zero, or exceeds 2 decimal places.
 */
export declare function toPaise(rupees: string | number): bigint;
/**
 * Formats integer paise into a standard decimal string ("200.00").
 */
export declare function toRupeesString(paise: bigint | number): string;
/**
 * Formats integer paise into a localized INR display string ("₹200.00").
 */
export declare function formatINR(paise: bigint | number): string;
//# sourceMappingURL=money.d.ts.map