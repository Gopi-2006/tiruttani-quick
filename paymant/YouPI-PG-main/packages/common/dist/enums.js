/**
 * Internal high-resolution payment session lifecycle states.
 */
export var PaymentStatus;
(function (PaymentStatus) {
    PaymentStatus["INITIATED"] = "INITIATED";
    PaymentStatus["QUEUED"] = "QUEUED";
    PaymentStatus["ACTIVE"] = "ACTIVE";
    PaymentStatus["PROCESSING"] = "PROCESSING";
    PaymentStatus["SUCCESS"] = "SUCCESS";
    PaymentStatus["FAILED"] = "FAILED";
    PaymentStatus["EXPIRED"] = "EXPIRED";
    PaymentStatus["CANCELLED"] = "CANCELLED";
})(PaymentStatus || (PaymentStatus = {}));
/**
 * Public-facing payment outcomes consumed by external merchants.
 */
export var PublicPaymentOutcome;
(function (PublicPaymentOutcome) {
    PublicPaymentOutcome["SUCCESS"] = "SUCCESS";
    PublicPaymentOutcome["FAILED"] = "FAILED";
    PublicPaymentOutcome["EXPIRED"] = "EXPIRED";
    PublicPaymentOutcome["CANCELLED"] = "CANCELLED";
})(PublicPaymentOutcome || (PublicPaymentOutcome = {}));
/**
 * Supported payment modalities.
 */
export var PaymentMethod;
(function (PaymentMethod) {
    PaymentMethod["UPI"] = "UPI";
    PaymentMethod["COD"] = "COD";
    PaymentMethod["CASH_COUNTER"] = "CASH_COUNTER";
    PaymentMethod["CARD_COUNTER"] = "CARD_COUNTER";
})(PaymentMethod || (PaymentMethod = {}));
/**
 * Merchant gateway selling modes.
 */
export var SellingMode;
(function (SellingMode) {
    SellingMode["ONLINE"] = "ONLINE";
    SellingMode["OFFLINE"] = "OFFLINE";
})(SellingMode || (SellingMode = {}));
/**
 * Observation channel sources feeding the payment detection engine (2-Layer: SMS + Gmail).
 * Android observer layer is completely removed.
 */
export var ObserverSource;
(function (ObserverSource) {
    ObserverSource["GMAIL"] = "GMAIL";
    ObserverSource["GOOGLE_MESSAGES"] = "GOOGLE_MESSAGES";
    ObserverSource["ANDROID_OBSERVER"] = "ANDROID_OBSERVER";
    ObserverSource["SMS_GATEWAY"] = "SMS_GATEWAY";
    ObserverSource["MANUAL_COUNTER"] = "MANUAL_COUNTER";
})(ObserverSource || (ObserverSource = {}));
/**
 * Attribution status for raw observations.
 */
export var ObservationAttributionStatus;
(function (ObservationAttributionStatus) {
    ObservationAttributionStatus["UNATTRIBUTED"] = "UNATTRIBUTED";
    ObservationAttributionStatus["ATTRIBUTED"] = "ATTRIBUTED";
    ObservationAttributionStatus["LATE_UNMATCHED"] = "LATE_UNMATCHED";
    ObservationAttributionStatus["DUPLICATE_IGNORED"] = "DUPLICATE_IGNORED";
})(ObservationAttributionStatus || (ObservationAttributionStatus = {}));
/**
 * Support ticket lifecycle states.
 */
export var TicketStatus;
(function (TicketStatus) {
    TicketStatus["OPEN"] = "OPEN";
    TicketStatus["IN_PROGRESS"] = "IN_PROGRESS";
    TicketStatus["RESOLVED"] = "RESOLVED";
    TicketStatus["CLOSED"] = "CLOSED";
})(TicketStatus || (TicketStatus = {}));
/**
 * Live chat message sender identity type.
 */
export var SenderType;
(function (SenderType) {
    SenderType["CUSTOMER"] = "CUSTOMER";
    SenderType["ADMIN"] = "ADMIN";
})(SenderType || (SenderType = {}));
/**
 * Audit log actor classifications.
 */
export var AuditActorType;
(function (AuditActorType) {
    AuditActorType["SYSTEM"] = "SYSTEM";
    AuditActorType["CUSTOMER"] = "CUSTOMER";
    AuditActorType["ADMIN"] = "ADMIN";
    AuditActorType["OBSERVER"] = "OBSERVER";
})(AuditActorType || (AuditActorType = {}));
//# sourceMappingURL=enums.js.map