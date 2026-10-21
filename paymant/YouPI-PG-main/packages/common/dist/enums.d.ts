/**
 * Internal high-resolution payment session lifecycle states.
 */
export declare enum PaymentStatus {
    INITIATED = "INITIATED",
    QUEUED = "QUEUED",
    ACTIVE = "ACTIVE",
    PROCESSING = "PROCESSING",
    SUCCESS = "SUCCESS",
    FAILED = "FAILED",
    EXPIRED = "EXPIRED",
    CANCELLED = "CANCELLED"
}
/**
 * Public-facing payment outcomes consumed by external merchants.
 */
export declare enum PublicPaymentOutcome {
    SUCCESS = "SUCCESS",
    FAILED = "FAILED",
    EXPIRED = "EXPIRED",
    CANCELLED = "CANCELLED"
}
/**
 * Supported payment modalities.
 */
export declare enum PaymentMethod {
    UPI = "UPI",
    COD = "COD",
    CASH_COUNTER = "CASH_COUNTER",
    CARD_COUNTER = "CARD_COUNTER"
}
/**
 * Merchant gateway selling modes.
 */
export declare enum SellingMode {
    ONLINE = "ONLINE",
    OFFLINE = "OFFLINE"
}
/**
 * Observation channel sources feeding the payment detection engine (2-Layer: SMS + Gmail).
 * Android observer layer is completely removed.
 */
export declare enum ObserverSource {
    GMAIL = "GMAIL",
    GOOGLE_MESSAGES = "GOOGLE_MESSAGES",
    ANDROID_OBSERVER = "ANDROID_OBSERVER",
    SMS_GATEWAY = "SMS_GATEWAY",
    MANUAL_COUNTER = "MANUAL_COUNTER"
}
/**
 * Attribution status for raw observations.
 */
export declare enum ObservationAttributionStatus {
    UNATTRIBUTED = "UNATTRIBUTED",
    ATTRIBUTED = "ATTRIBUTED",
    LATE_UNMATCHED = "LATE_UNMATCHED",
    DUPLICATE_IGNORED = "DUPLICATE_IGNORED"
}
/**
 * Support ticket lifecycle states.
 */
export declare enum TicketStatus {
    OPEN = "OPEN",
    IN_PROGRESS = "IN_PROGRESS",
    RESOLVED = "RESOLVED",
    CLOSED = "CLOSED"
}
/**
 * Live chat message sender identity type.
 */
export declare enum SenderType {
    CUSTOMER = "CUSTOMER",
    ADMIN = "ADMIN"
}
/**
 * Audit log actor classifications.
 */
export declare enum AuditActorType {
    SYSTEM = "SYSTEM",
    CUSTOMER = "CUSTOMER",
    ADMIN = "ADMIN",
    OBSERVER = "OBSERVER"
}
//# sourceMappingURL=enums.d.ts.map