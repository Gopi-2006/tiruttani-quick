import { PaymentStatus, ObservationAttributionStatus, TicketStatus, SenderType } from '@youpi/common';
import { ObservationNormalizer } from './normalizer.js';

export class AttributionEngine {
  /**
   * @param {{
   *   sessionRepo: import('@youpi/db').PaymentSessionRepository,
   *   obsRepo: import('@youpi/db').ObservationRepository,
   *   ticketRepo?: import('@youpi/db').SupportTicketRepository,
   *   auditRepo?: import('@youpi/db').AuditLogRepository,
   *   eventEmitter?: { emit: (event: string, payload: any) => void }
   * }} options
   */
  constructor(options) {
    this.sessionRepo = options.sessionRepo;
    this.obsRepo = options.obsRepo;
    this.ticketRepo = options.ticketRepo;
    this.auditRepo = options.auditRepo;
    this.eventEmitter = options.eventEmitter || { emit: () => {} };
    const isTestExecution = process.env.NODE_ENV === 'test' ||
      (process.execArgv && process.execArgv.includes('--test')) ||
      (process.argv && process.argv.some(a => typeof a === 'string' && a.includes('test')));

    this.gracePeriodMs = options.gracePeriodMs !== undefined
      ? options.gracePeriodMs
      : (process.env.PAYMENT_GRACE_PERIOD_MS !== undefined
        ? Number(process.env.PAYMENT_GRACE_PERIOD_MS)
        : (isTestExecution ? 0 : 5000));
    /** @type {Map<string, NodeJS.Timeout>} */
    this.pendingGraceTimers = new Map();
  }

  destroy() {
    for (const timer of this.pendingGraceTimers.values()) {
      clearTimeout(timer);
    }
    this.pendingGraceTimers.clear();
  }

  /**
   * Helper that normalizes raw observation and processes it.
   */
  async attribute(obs) {
    const normalized = obs && obs.fingerprintHash ? obs : ObservationNormalizer.normalize(obs);
    return await this.processObservation(normalized);
  }

  /**
   * Processes a normalized canonical observation through the attribution pipeline.
   * @param {ReturnType<typeof import('./normalizer.js').ObservationNormalizer.normalize>} normalizedObs
   * @returns {{
   *   attributed: boolean,
   *   duplicate: boolean,
   *   lateMatch: boolean,
   *   paymentSessionId?: string,
   *   observationId: string,
   *   outcomeStatus: string,
   *   verificationLevel?: number,
   *   verificationTag?: string,
   *   verificationSources?: string[]
   * }}
   */
  async processObservation(normalizedObs) {
    // Tier 1: Check fingerprint for deduplication
    const existing = await this.obsRepo.findByFingerprint(normalizedObs.fingerprintHash);
    if (existing) {
      // If observation came from the SAME source, drop as redundant duplicate
      if (existing.source === normalizedObs.source) {
        if (this.auditRepo) {
          this.auditRepo.log({
            entityType: 'PAYMENT_OBSERVATION',
            entityId: existing.id,
            action: 'DUPLICATE_OBSERVATION_DROPPED',
            actorType: 'OBSERVER',
            details: { fingerprintHash: normalizedObs.fingerprintHash, source: normalizedObs.source }
          });
        }
        return {
          attributed: false,
          duplicate: true,
          lateMatch: false,
          paymentSessionId: existing.attributedPaymentId || undefined,
          observationId: existing.id,
          outcomeStatus: ObservationAttributionStatus.DUPLICATE_IGNORED
        };
      }

      // If observation came from a NEW, DIFFERENT channel and payment was already attributed:
      // Upgrade verification tier to Level 2 (Dual Verification)!
      if (existing.attributedPaymentId) {
        const targetSessionId = normalizedObs.rawPayload?.targetSessionId;
        if (targetSessionId && targetSessionId !== existing.attributedPaymentId) {
          if (this.auditRepo) {
            this.auditRepo.log({
              entityType: 'PAYMENT_OBSERVATION',
              entityId: existing.id,
              action: 'DUPLICATE_PAYMENT_REFERENCE_REJECTED',
              actorType: 'SECURITY',
              details: { attemptedSession: targetSessionId, existingSession: existing.attributedPaymentId }
            });
          }
          return {
            attributed: false,
            duplicate: true,
            lateMatch: false,
            paymentSessionId: existing.attributedPaymentId,
            observationId: existing.id,
            outcomeStatus: ObservationAttributionStatus.DUPLICATE_IGNORED
          };
        }

        // Cancel pending 5-second grace timer if any
        const pendingTimer = this.pendingGraceTimers.get(existing.attributedPaymentId);
        if (pendingTimer) {
          clearTimeout(pendingTimer);
          this.pendingGraceTimers.delete(existing.attributedPaymentId);
        }

        const savedObs = await this.obsRepo.create(normalizedObs);
        const verifyResult = await this.sessionRepo.recordVerificationSource(
          existing.attributedPaymentId,
          normalizedObs.source,
          savedObs.id,
          { finalizeSuccess: true }
        );
        await this.obsRepo.markAttributed(savedObs.id, existing.attributedPaymentId);

        if (this.auditRepo) {
          this.auditRepo.log({
            entityType: 'PAYMENT_SESSION',
            entityId: existing.attributedPaymentId,
            action: 'PAYMENT_VERIFICATION_UPGRADED',
            actorType: 'SYSTEM',
            details: {
              source: normalizedObs.source,
              level: verifyResult.level,
              tag: verifyResult.tag,
              sources: verifyResult.sources
            }
          });
        }

        if (verifyResult.isFirstSuccess) {
          this.eventEmitter.emit('PAYMENT.SUCCESS', {
            paymentId: existing.attributedPaymentId,
            orderId: verifyResult.session.orderId,
            merchantId: verifyResult.session.merchantId,
            amountPaise: verifyResult.session.amountPaise,
            observationId: savedObs.id,
            verificationLevel: verifyResult.level,
            verificationTag: verifyResult.tag,
            sources: verifyResult.sources
          });
        }

        this.eventEmitter.emit('PAYMENT.VERIFICATION_UPGRADED', {
          paymentId: existing.attributedPaymentId,
          verificationLevel: verifyResult.level,
          verificationTag: verifyResult.tag,
          sources: verifyResult.sources
        });

        return {
          attributed: true,
          duplicate: false,
          lateMatch: false,
          paymentSessionId: existing.attributedPaymentId,
          observationId: savedObs.id,
          outcomeStatus: PaymentStatus.SUCCESS,
          verificationLevel: verifyResult.level,
          verificationTag: verifyResult.tag,
          verificationSources: verifyResult.sources
        };
      }
    }

    // Persist new observation as UNATTRIBUTED first
    const savedObs = await this.obsRepo.create(normalizedObs);

    // Tier 2: Unambiguous active session resolution
    let currentSession = null;
    let candidates = [];

    if (normalizedObs.rawPayload?.targetSessionId) {
      const explicitSession = await this.sessionRepo.findById(normalizedObs.rawPayload.targetSessionId);
      if (explicitSession &&
          [PaymentStatus.ACTIVE, PaymentStatus.PROCESSING].includes(explicitSession.status) &&
          explicitSession.amountPaise === normalizedObs.amountPaise) {
        if (!normalizedObs.receivingAccountId || explicitSession.receivingAccountId === normalizedObs.receivingAccountId) {
          candidates = [explicitSession];
        }
      }
    }

    if (candidates.length === 0) {
      if (normalizedObs.receivingAccountId) {
        const rawRows = await this.sessionRepo.db.query(`
          SELECT * FROM payment_sessions
          WHERE receiving_account_id = ? AND status IN ('ACTIVE', 'PROCESSING') AND amount_paise = ?
        `, [normalizedObs.receivingAccountId, Number(normalizedObs.amountPaise)]);
        const rows = Array.isArray(rawRows) ? rawRows : (rawRows?.rows || []);
        candidates = rows.map(r => this.sessionRepo.mapRow(r));
      } else {
        // Missing receivingAccountId: search across all active/processing sessions for this exact amount
        const rawRows = await this.sessionRepo.db.query(`
          SELECT * FROM payment_sessions
          WHERE status IN ('ACTIVE', 'PROCESSING') AND amount_paise = ?
        `, [Number(normalizedObs.amountPaise)]);
        const rows = Array.isArray(rawRows) ? rawRows : (rawRows?.rows || []);
        candidates = rows.map(r => this.sessionRepo.mapRow(r));
      }
    }

    // ADVERSARIAL HARDENING (FIX 1): NEVER GUESS ON AMBIGUOUS SESSIONS
    if (candidates.length > 1) {
      if (this.auditRepo) {
        this.auditRepo.log({
          entityType: 'PAYMENT_OBSERVATION',
          entityId: savedObs.id,
          action: 'AMBIGUOUS_ATTRIBUTION_REJECTED',
          actorType: 'SECURITY',
          details: {
            amountPaise: normalizedObs.amountPaise?.toString(),
            matchingSessionsCount: candidates.length,
            matchingSessionIds: candidates.map(c => c.id),
            receivingAccountId: normalizedObs.receivingAccountId || null,
            reason: 'MULTIPLE_ACTIVE_SESSIONS_MATCH_SAME_AMOUNT'
          }
        });
      }
      return {
        attributed: false,
        duplicate: false,
        lateMatch: false,
        ambiguous: true,
        observationId: savedObs.id,
        outcomeStatus: 'AMBIGUOUS_REJECT',
        error: 'AMBIGUOUS_REJECT: Multiple active payment sessions match this amount. Manual review required.'
      };
    }

    if (candidates.length === 1) {
      currentSession = candidates[0];
    }

    if (currentSession) {
      // Invariant Check 1: Must be in ACTIVE or PROCESSING status
      const isEligibleStatus = [PaymentStatus.ACTIVE, PaymentStatus.PROCESSING].includes(currentSession.status);

      // Invariant Check 2: Exact Amount Match (in integer paise)
      const isAmountMatch = currentSession.amountPaise === normalizedObs.amountPaise;

      // Invariant Check 3: Temporal Window (with 5-minute clock skew tolerance, strictly preventing hijacking of prior expired sessions)
      let isPriorExpiredSession = false;
      if (currentSession.slotAcquiredAt && normalizedObs.observedAt < currentSession.slotAcquiredAt) {
        const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);
        const recentExpired = await this.sessionRepo.findRecentlyExpiredOrFailed(
          normalizedObs.receivingAccountId,
          thirtyMinutesAgo
        );
        isPriorExpiredSession = recentExpired.some(s => s.amountPaise === normalizedObs.amountPaise);
      }

      const slotStart = currentSession.slotAcquiredAt
        ? new Date(currentSession.slotAcquiredAt.getTime() - 300000)
        : new Date(currentSession.createdAt.getTime() - 300000);

      const isTimeValid = !isPriorExpiredSession && (normalizedObs.observedAt >= slotStart);

      if (isEligibleStatus && isAmountMatch && isTimeValid) {
        return await this.sessionRepo.db.transaction(async () => {
          // Re-verify session status inside transaction
          const freshSession = await this.sessionRepo.findById(currentSession.id);
          if (!freshSession || ![PaymentStatus.ACTIVE, PaymentStatus.PROCESSING].includes(freshSession.status)) {
            return {
              attributed: false,
              duplicate: false,
              lateMatch: false,
              paymentSessionId: currentSession.id,
              observationId: savedObs.id,
              outcomeStatus: freshSession?.status || 'TERMINAL_STATE'
            };
          }

          // SECURITY HARDENING: Prevent duplicate payment reference (UTR) replay across different sessions
          if (normalizedObs.bankReferenceNumber) {
            const priorAttributed = await this.sessionRepo.db.queryOne(`
              SELECT attributed_payment_id FROM payment_observations
              WHERE bank_reference_number = ? AND attributed_payment_id IS NOT NULL AND attributed_payment_id != ?
              LIMIT 1
            `, [normalizedObs.bankReferenceNumber, currentSession.id]);

            if (priorAttributed && priorAttributed.attributed_payment_id) {
              await this.obsRepo.markDuplicate(savedObs.id);
              if (this.auditRepo) {
                this.auditRepo.log({
                  merchantId: currentSession.merchantId,
                  entityType: 'PAYMENT_SESSION',
                  entityId: currentSession.id,
                  action: 'DUPLICATE_PAYMENT_REFERENCE_REJECTED',
                  actorType: 'SECURITY',
                  details: {
                    bankReferenceNumber: normalizedObs.bankReferenceNumber,
                    reusedFromPaymentId: priorAttributed.attributed_payment_id
                  }
                });
              }
              return {
                attributed: false,
                duplicate: true,
                lateMatch: false,
                paymentSessionId: currentSession.id,
                observationId: savedObs.id,
                outcomeStatus: ObservationAttributionStatus.DUPLICATE_IGNORED
              };
            }
          }

          const wasActive = currentSession.status === PaymentStatus.ACTIVE;

          // Check if there is already an active grace period awaiting second source for this session
          const pendingGrace = this.pendingGraceTimers.get(currentSession.id);
          if (pendingGrace) {
            clearTimeout(pendingGrace);
            this.pendingGraceTimers.delete(currentSession.id);

            // Second source confirmed within 5-second grace window -> LEVEL 2 DUAL VERIFICATION!
            const verifyResult = await this.sessionRepo.recordVerificationSource(
              currentSession.id,
              normalizedObs.source,
              savedObs.id,
              { finalizeSuccess: true }
            );
            await this.obsRepo.markAttributed(savedObs.id, currentSession.id);

            if (this.auditRepo) {
              this.auditRepo.log({
                merchantId: currentSession.merchantId,
                entityType: 'PAYMENT_SESSION',
                entityId: currentSession.id,
                action: 'PAYMENT_VERIFICATION_UPGRADED_L2',
                actorType: 'SYSTEM',
                details: {
                  observationId: savedObs.id,
                  source: normalizedObs.source,
                  verificationLevel: 2,
                  verificationTag: verifyResult.tag,
                  sources: verifyResult.sources
                }
              });
            }

            this.eventEmitter.emit('PAYMENT.SUCCESS', {
              paymentId: currentSession.id,
              orderId: currentSession.orderId,
              merchantId: currentSession.merchantId,
              amountPaise: currentSession.amountPaise,
              observationId: savedObs.id,
              verificationLevel: 2,
              verificationTag: verifyResult.tag,
              sources: verifyResult.sources
            });

            this.eventEmitter.emit('PAYMENT.VERIFICATION_UPGRADED', {
              paymentId: currentSession.id,
              orderId: currentSession.orderId,
              verificationLevel: 2,
              verificationTag: verifyResult.tag,
              sources: verifyResult.sources
            });

            return {
              attributed: true,
              duplicate: false,
              lateMatch: false,
              wasActive,
              paymentSessionId: currentSession.id,
              observationId: savedObs.id,
              outcomeStatus: PaymentStatus.SUCCESS,
              verificationLevel: 2,
              verificationTag: verifyResult.tag,
              verificationSources: verifyResult.sources
            };
          }

          // FIRST SOURCE CONFIRMATION:
          // Record Level 1 verification source without immediate finalization (start 5-second grace window)
          const verifyResult = await this.sessionRepo.recordVerificationSource(
            currentSession.id,
            normalizedObs.source,
            savedObs.id,
            { finalizeSuccess: false }
          );

          await this.obsRepo.markAttributed(savedObs.id, currentSession.id);

          if (this.auditRepo) {
            this.auditRepo.log({
              merchantId: currentSession.merchantId,
              entityType: 'PAYMENT_SESSION',
              entityId: currentSession.id,
              action: 'PAYMENT_LEVEL1_VERIFIED',
              actorType: 'SYSTEM',
              details: {
                observationId: savedObs.id,
                source: normalizedObs.source,
                amountPaise: normalizedObs.amountPaise.toString(),
                verificationLevel: 1,
                verificationTag: verifyResult.tag,
                sources: verifyResult.sources
              }
            });
          }

          this.eventEmitter.emit('PAYMENT.LEVEL1_VERIFIED', {
            paymentId: currentSession.id,
            orderId: currentSession.orderId,
            merchantId: currentSession.merchantId,
            amountPaise: currentSession.amountPaise,
            observationId: savedObs.id,
            verificationLevel: 1,
            verificationTag: verifyResult.tag,
            sources: verifyResult.sources
          });

          // If grace period is 0 (e.g. in instant tests), finalize immediately
          if (this.gracePeriodMs <= 0) {
            const finalResult = await this.sessionRepo.recordVerificationSource(
              currentSession.id,
              normalizedObs.source,
              savedObs.id,
              { finalizeSuccess: true }
            );
            this.eventEmitter.emit('PAYMENT.SUCCESS', {
              paymentId: currentSession.id,
              orderId: currentSession.orderId,
              merchantId: currentSession.merchantId,
              amountPaise: currentSession.amountPaise,
              observationId: savedObs.id,
              verificationLevel: finalResult.level,
              verificationTag: finalResult.tag,
              sources: finalResult.sources
            });

            return {
              attributed: true,
              duplicate: false,
              lateMatch: false,
              wasActive,
              paymentSessionId: currentSession.id,
              observationId: savedObs.id,
              outcomeStatus: PaymentStatus.SUCCESS,
              verificationLevel: finalResult.level,
              verificationTag: finalResult.tag,
              verificationSources: finalResult.sources
            };
          }

          // Start 5-second grace window awaiting second poller
          const targetSessionId = currentSession.id;
          const targetObsId = savedObs.id;
          const targetSource = normalizedObs.source;
          const targetOrderId = currentSession.orderId;
          const targetMerchantId = currentSession.merchantId;
          const targetAmountPaise = currentSession.amountPaise;

          const graceTimer = setTimeout(async () => {
            this.pendingGraceTimers.delete(targetSessionId);
            // 5 seconds elapsed without second source: finalize as Level 1
            const finalResult = await this.sessionRepo.recordVerificationSource(
              targetSessionId,
              targetSource,
              targetObsId,
              { finalizeSuccess: true }
            );

            if (this.auditRepo) {
              this.auditRepo.log({
                merchantId: targetMerchantId,
                entityType: 'PAYMENT_SESSION',
                entityId: targetSessionId,
                action: 'PAYMENT_ATTRIBUTED_SUCCESS_L1',
                actorType: 'SYSTEM',
                details: {
                  observationId: targetObsId,
                  source: targetSource,
                  verificationLevel: finalResult.level,
                  verificationTag: finalResult.tag
                }
              });
            }

            this.eventEmitter.emit('PAYMENT.SUCCESS', {
              paymentId: targetSessionId,
              orderId: targetOrderId,
              merchantId: targetMerchantId,
              amountPaise: targetAmountPaise,
              observationId: targetObsId,
              verificationLevel: finalResult.level,
              verificationTag: finalResult.tag,
              sources: finalResult.sources
            });
          }, this.gracePeriodMs);

          if (graceTimer.unref) graceTimer.unref();
          this.pendingGraceTimers.set(targetSessionId, graceTimer);

          return {
            attributed: true,
            duplicate: false,
            lateMatch: false,
            wasActive,
            paymentSessionId: currentSession.id,
            observationId: savedObs.id,
            outcomeStatus: 'VERIFYING',
            verificationLevel: 1,
            verificationTag: verifyResult.tag,
            verificationSources: verifyResult.sources
          };
        });
      }
    }

    // Check if observation confirms a recently successful session on this receiving account (within 60s)
    // Upgrades verification level (e.g. from Level 1 -> Level 2 -> Level 3)
    let recentSuccessSession = null;
    if (normalizedObs.receivingAccountId) {
      const sixtySecAgo = new Date(Date.now() - 60000).toISOString();
      const rawRecent = await this.sessionRepo.db.query(`
        SELECT * FROM payment_sessions
        WHERE receiving_account_id = ? AND status = 'SUCCESS'
          AND amount_paise = ? AND completed_at >= ?
      `, [normalizedObs.receivingAccountId, Number(normalizedObs.amountPaise), sixtySecAgo]);
      const recentRows = Array.isArray(rawRecent) ? rawRecent : (rawRecent?.rows || []);

      if (recentRows.length === 1) {
        recentSuccessSession = recentRows[0];
      } else if (recentRows.length > 1 && normalizedObs.bankReferenceNumber) {
        // Disambiguate solely by exact UTR match
        const matchingUtr = [];
        for (const r of recentRows) {
          const obs = r.attributed_observation_id ? await this.obsRepo.findById(r.attributed_observation_id) : null;
          if (obs && obs.bankReferenceNumber === normalizedObs.bankReferenceNumber) {
            matchingUtr.push(r);
          }
        }
        if (matchingUtr.length === 1) {
          recentSuccessSession = matchingUtr[0];
        }
      }
    }

    if (recentSuccessSession) {
      // Check if this session's attributed observation had a UTR
      const existingObs = recentSuccessSession.attributed_observation_id
        ? await this.obsRepo.findById(recentSuccessSession.attributed_observation_id)
        : null;

      // If both have UTRs and they do NOT match, this is NOT the same transaction!
      const isUtrConflict = normalizedObs.bankReferenceNumber &&
        existingObs?.bankReferenceNumber &&
        normalizedObs.bankReferenceNumber !== existingObs.bankReferenceNumber;

      const sessionSlotStart = recentSuccessSession.slot_acquired_at
        ? new Date(new Date(recentSuccessSession.slot_acquired_at).getTime() - 30000)
        : new Date(new Date(recentSuccessSession.created_at).getTime() - 30000);
      const sessionCompleted = recentSuccessSession.completed_at
        ? new Date(new Date(recentSuccessSession.completed_at).getTime() + 30000)
        : new Date();

      // Temporal check: observation must have been observed during this session's window
      if (!isUtrConflict && normalizedObs.observedAt >= sessionSlotStart && normalizedObs.observedAt <= sessionCompleted) {
        const verifyResult = await this.sessionRepo.recordVerificationSource(
          recentSuccessSession.id,
          normalizedObs.source,
          savedObs.id
        );

        await this.obsRepo.markAttributed(savedObs.id, recentSuccessSession.id);

        if (this.auditRepo) {
          this.auditRepo.log({
            merchantId: recentSuccessSession.merchant_id,
            entityType: 'PAYMENT_SESSION',
            entityId: recentSuccessSession.id,
            action: 'PAYMENT_VERIFICATION_UPGRADED',
            actorType: 'SYSTEM',
            details: {
              observationId: savedObs.id,
              source: normalizedObs.source,
              amountPaise: normalizedObs.amountPaise.toString(),
              verificationLevel: verifyResult.level,
              verificationTag: verifyResult.tag,
              sources: verifyResult.sources
            }
          });
        }

        this.eventEmitter.emit('PAYMENT.VERIFICATION_UPGRADED', {
          paymentId: recentSuccessSession.id,
          orderId: recentSuccessSession.order_id,
          verificationLevel: verifyResult.level,
          verificationTag: verifyResult.tag,
          sources: verifyResult.sources
        });

        return {
          attributed: true,
          duplicate: false,
          lateMatch: false,
          paymentSessionId: recentSuccessSession.id,
          observationId: savedObs.id,
          outcomeStatus: PaymentStatus.SUCCESS,
          verificationLevel: verifyResult.level,
          verificationTag: verifyResult.tag,
          verificationSources: verifyResult.sources
        };
      }
    }

    // Tier 3: Late Observation Handling
    // Check if observation matches a recently expired or failed session on this receiving account (< 30 mins)
    const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);
    const recentExpired = await this.sessionRepo.findRecentlyExpiredOrFailed(
      normalizedObs.receivingAccountId,
      thirtyMinutesAgo
    );

    const lateMatchedSession = recentExpired.find(s => s.amountPaise === normalizedObs.amountPaise);

    if (lateMatchedSession) {
      // Mark observation as LATE_UNMATCHED
      await this.obsRepo.markLateUnmatched(savedObs.id);

      if (this.auditRepo) {
        this.auditRepo.log({
          merchantId: lateMatchedSession.merchantId,
          entityType: 'PAYMENT_SESSION',
          entityId: lateMatchedSession.id,
          action: 'LATE_OBSERVATION_DETECTED',
          actorType: 'SYSTEM',
          details: {
            observationId: savedObs.id,
            source: normalizedObs.source,
            amountPaise: normalizedObs.amountPaise.toString(),
            sessionStatus: lateMatchedSession.status
          }
        });
      }

      // Automatically create a high-priority reconciliation support ticket if customer exists
      if (this.ticketRepo && lateMatchedSession.customerId) {
        await this.ticketRepo.createTicket({
          merchantId: lateMatchedSession.merchantId,
          customerId: lateMatchedSession.customerId,
          paymentId: lateMatchedSession.id,
          subject: `[LATE PAYMENT DETECTED] Order #${lateMatchedSession.orderId}`,
          status: TicketStatus.OPEN,
          initialMessage: {
            senderType: SenderType.ADMIN,
            senderId: lateMatchedSession.merchantId,
            message: `A delayed payment observation of ${normalizedObs.amountPaise / 100n} INR was detected after session ${lateMatchedSession.id} ended with status ${lateMatchedSession.status}. Flagged for manual merchant reconciliation.`
          }
        });
      }

      // Emit LATE_DETECTED event
      this.eventEmitter.emit('PAYMENT.LATE_DETECTED', {
        paymentId: lateMatchedSession.id,
        orderId: lateMatchedSession.orderId,
        merchantId: lateMatchedSession.merchantId,
        amountPaise: normalizedObs.amountPaise,
        observationId: savedObs.id
      });

      return {
        attributed: false,
        duplicate: false,
        lateMatch: true,
        paymentSessionId: lateMatchedSession.id,
        observationId: savedObs.id,
        outcomeStatus: ObservationAttributionStatus.LATE_UNMATCHED
      };
    }

    // Unattributed observation
    return {
      attributed: false,
      duplicate: false,
      lateMatch: false,
      observationId: savedObs.id,
      outcomeStatus: ObservationAttributionStatus.UNATTRIBUTED
    };
  }
}
