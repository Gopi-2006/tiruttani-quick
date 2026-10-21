import { ObserverSource, ObservationAttributionStatus } from './enums.js';
export interface CanonicalObservation {
    id: string;
    receivingAccountId: string;
    source: ObserverSource;
    amountPaise: bigint;
    observedAt: Date;
    ingestedAt: Date;
    senderVpa?: string;
    bankReferenceNumber?: string;
    fingerprintHash: string;
    attributionStatus: ObservationAttributionStatus;
    attributedPaymentId?: string;
    rawPayload: Record<string, unknown>;
}
export interface IngestObservationInput {
    receivingAccountId: string;
    source: ObserverSource;
    amountPaise: bigint;
    observedAt: Date;
    senderVpa?: string;
    bankReferenceNumber?: string;
    rawPayload?: Record<string, unknown>;
}
/**
 * Calculates a deterministic fingerprint for an observation to prevent duplicate processing.
 * If bankReferenceNumber exists, it hashes receivingAccount + amount + referenceNumber.
 * Otherwise, it hashes receivingAccount + amount + 60-second time bucket.
 */
export declare function calculateObservationFingerprint(input: {
    receivingAccountId: string;
    amountPaise: bigint;
    source?: string;
    bankReferenceNumber?: string;
    observedAt: Date;
}): string;
//# sourceMappingURL=observation.d.ts.map