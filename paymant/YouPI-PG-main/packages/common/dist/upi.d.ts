export interface BuildUpiUriOptions {
    payeeVpa: string;
    payeeName: string;
    amountPaise: bigint;
    transactionRef: string;
    transactionNote?: string;
    currency?: string;
}
/**
 * Validates whether a given string is a syntactically valid UPI Virtual Payment Address (VPA).
 * Format: username@bank
 */
export declare function isValidVpa(vpa: string): boolean;
/**
 * Builds a canonical upi://pay URI dynamically from server-validated parameters.
 * Amount is derived exclusively from server-side integer paise.
 */
export declare function buildUpiUri(options: BuildUpiUriOptions): string;
export interface BuildUpiIntentUriOptions extends BuildUpiUriOptions {
    packageName: string;
}
/**
 * Builds an Android intent URI for launching a specific UPI application.
 * Format: intent://pay?<UPI_PARAMS>#Intent;scheme=upi;package=<PACKAGE>;end
 */
export declare function buildUpiIntentUri(options: BuildUpiIntentUriOptions): string;
//# sourceMappingURL=upi.d.ts.map