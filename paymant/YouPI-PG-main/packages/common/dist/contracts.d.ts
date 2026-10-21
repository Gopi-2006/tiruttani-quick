import { PaymentStatus, PublicPaymentOutcome, PaymentMethod, ObserverSource, TicketStatus, SenderType } from './enums.js';
export interface CreatePaymentRequest {
    orderId: string;
    amount: string | number;
    currency?: string;
    returnUrl?: string;
    method?: PaymentMethod;
    customer?: {
        phoneNumber: string;
        fullName?: string;
    };
    metadata?: Record<string, unknown>;
}
export interface CreatePaymentResponse {
    paymentId: string;
    orderId: string;
    amount: string;
    amountPaise: string;
    currency: string;
    status: PaymentStatus;
    checkoutUrl: string;
}
export interface QueryPaymentResponse {
    paymentId: string;
    orderId: string;
    amount: string;
    currency: string;
    status: PublicPaymentOutcome | PaymentStatus;
    method: PaymentMethod;
    completedAt?: string;
    metadata?: Record<string, unknown>;
}
export interface CheckoutStateResponse {
    paymentId: string;
    orderId: string;
    merchantName: string;
    amount: string;
    amountPaise: string;
    currency: string;
    status: PaymentStatus;
    method: PaymentMethod;
    queuePosition: number;
    timeRemainingSeconds: number;
    upiUri?: string;
    payeeVpa?: string;
    payeeName?: string;
    canClickPaymentDone: boolean;
    branding: {
        appName: string;
        primaryColor: string;
        logoUrl?: string;
    };
}
export interface WebhookEventPayload {
    event: PublicPaymentOutcome;
    paymentId: string;
    orderId: string;
    amount: string;
    amountPaise: number;
    currency: string;
    method: PaymentMethod;
    completedAt?: string;
    metadata?: Record<string, unknown>;
}
export interface AndroidObservationPayload {
    deviceId: string;
    source: ObserverSource.ANDROID;
    amountPaise: number;
    observedAt: string;
    observationId?: string;
    senderVpa?: string;
    bankReferenceNumber?: string;
    rawNotification?: Record<string, unknown>;
}
export interface AndroidHeartbeatPayload {
    deviceId: string;
    timestamp: string;
    batteryLevel?: number;
    appVersion?: string;
}
export interface CustomerProfile {
    id: string;
    name: string;
    email: string;
    mobileNumber: string;
    status: string;
    lastLoginAt?: string | null;
    createdAt: string;
    updatedAt: string;
}
export interface CustomerRegisterRequest {
    name: string;
    email: string;
    mobileNumber: string;
    password: string;
}
export interface CustomerLoginRequest {
    identifier?: string;
    email?: string;
    mobileNumber?: string;
    password: string;
}
export interface CustomerSessionDto {
    id: string;
    customerId: string;
    token: string;
    expiresAt: string;
    isActive: boolean;
    createdAt: string;
}
/**
 * Normalizes an email address to trimmed lowercase.
 */
export declare function normalizeEmail(email: string | null | undefined): string;
/**
 * Validates email format with standard requirements.
 */
export declare function isValidEmail(email: string | null | undefined): boolean;
/**
 * Normalizes a mobile number to canonical 10 digits (stripping prefixes and country codes).
 */
export declare function normalizeMobile(mobile: string | null | undefined): string;
/**
 * Validates canonical Indian 10-digit mobile number format.
 */
export declare function isValidMobile(mobile: string | null | undefined): boolean;
/**
 * Validates password strength (minimum 6 characters).
 */
export declare function isValidPassword(password: string | null | undefined): boolean;
export interface SupportTicketSummary {
    id: string;
    subject: string;
    status: TicketStatus;
    paymentId?: string;
    createdAt: string;
    updatedAt: string;
}
export interface TicketMessageDto {
    id: string;
    ticketId: string;
    senderType: SenderType;
    senderId: string;
    message: string;
    createdAt: string;
}
//# sourceMappingURL=contracts.d.ts.map