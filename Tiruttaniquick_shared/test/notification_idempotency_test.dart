import 'package:flutter_test/flutter_test.dart';
import 'package:tiruttaniquick_shared/services/notification_service.dart';

void main() {
  group('NotificationService Client Idempotency & Collapse Tags', () {
    final service = NotificationService.instance;

    setUp(() {
      service.resetRecentEventsForTesting();
    });

    test('1. calculateNotificationId generates deterministic stable ID for same orderId', () {
      const orderId = 'TQ261021113341515HAIR';
      final id1 = NotificationService.calculateNotificationId(orderId);
      final id2 = NotificationService.calculateNotificationId(orderId);

      expect(id1, equals(id2));
      expect(id1, isNonNegative);
      expect(id1, lessThan(100000));
    });

    test('2. calculateCollapseTag generates Android shade collapse tag', () {
      const orderId = 'TQ261021113341515HAIR';
      final tag = NotificationService.calculateCollapseTag(orderId);
      expect(tag, equals('order_TQ261021113341515HAIR'));

      final nullTag = NotificationService.calculateCollapseTag(null);
      expect(nullTag, isNull);

      final emptyTag = NotificationService.calculateCollapseTag('');
      expect(emptyTag, isNull);
    });

    test('3. checkAndRecordEventDeduplication suppresses duplicate event within window', () {
      const eventId = 'order_status_TQ261021113341515HAIR_cancelled_cust_123';

      // First delivery: not duplicate
      final isDup1 = service.checkAndRecordEventDeduplication(eventId);
      expect(isDup1, isFalse);
      expect(service.isEventRecentlyHandled(eventId), isTrue);

      // Second delivery (simulated duplicate FCM push / local callback): duplicate!
      final isDup2 = service.checkAndRecordEventDeduplication(eventId);
      expect(isDup2, isTrue);

      // Third delivery: duplicate!
      final isDup3 = service.checkAndRecordEventDeduplication(eventId);
      expect(isDup3, isTrue);
    });

    test('4. Preserves legitimate status transitions for the same order', () {
      const orderId = 'TQ261021113341515HAIR';

      final eventAccepted = 'order_status_${orderId}_accepted_cust_123';
      final eventPacked = 'order_status_${orderId}_packed_cust_123';
      final eventOutForDelivery = 'order_status_${orderId}_out_for_delivery_cust_123';
      final eventCancelled = 'order_status_${orderId}_cancelled_cust_123';

      // Every distinct status change must be processed
      expect(service.checkAndRecordEventDeduplication(eventAccepted), isFalse);
      expect(service.checkAndRecordEventDeduplication(eventPacked), isFalse);
      expect(service.checkAndRecordEventDeduplication(eventOutForDelivery), isFalse);
      expect(service.checkAndRecordEventDeduplication(eventCancelled), isFalse);

      // But a repeat of the cancelled event is suppressed
      expect(service.checkAndRecordEventDeduplication(eventCancelled), isTrue);
    });

    test('5. Multi-recipient / Multi-order isolation', () {
      const eventCustA = 'order_status_ORD_111_cancelled_cust_A';
      const eventCustB = 'order_status_ORD_222_cancelled_cust_B';

      expect(service.checkAndRecordEventDeduplication(eventCustA), isFalse);
      expect(service.checkAndRecordEventDeduplication(eventCustB), isFalse);

      // Duplicates for Cust A suppressed, but independent events untouched
      expect(service.checkAndRecordEventDeduplication(eventCustA), isTrue);
    });

    test('6. Delivery partner assignment event deduplication', () {
      const partnerEvent = 'order_delivery_assigned_ORD_111_Ravi_Kumar_cust_A';
      expect(service.checkAndRecordEventDeduplication(partnerEvent), isFalse);
      expect(service.checkAndRecordEventDeduplication(partnerEvent), isTrue);
    });
  });
}

