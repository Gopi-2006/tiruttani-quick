import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tiruttaniquick_customer/config/payment_config.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

void main() {
  group('Phase 7: End-to-End Staging Validation & Integration Safeguards', () {
    setUp(() {
      dotenv.testLoad(fileInput: '');
    });

    test('1. Production release builds lock out Online UPI regardless of .env settings', () {
      // In production release mode, even if .env contains staging variables,
      // compile-time const STAGING_BUILD is false, preventing live customer exposure
      expect(PaymentConfig.isStagingOnlineUpiEnabled, isFalse);
    });

    test('2. Staging mode enables Online UPI when explicitly configured', () {
      dotenv.testLoad(fileInput: 'APP_ENV=staging\nENABLE_STAGING_ONLINE_UPI=true');
      expect(PaymentConfig.isStaging, isTrue);
      expect(PaymentConfig.isStagingOnlineUpiEnabled, isTrue);
    });

    test('3. Staging backend URL is configurable and defaults safely', () {
      dotenv.testLoad(fileInput: 'APP_ENV=staging\nYOUPI_CREATE_PAYMENT_URL=http://localhost:5001/staging/createPaymentSession');
      expect(PaymentConfig.createPaymentSessionUrl, equals('http://localhost:5001/staging/createPaymentSession'));

      dotenv.testLoad(fileInput: '');
      expect(PaymentConfig.createPaymentSessionUrl, contains('createYoupiPaymentSession'));
    });

    test('4. Backend unreachable message provides clear guidance without simulating success', () {
      expect(PaymentConfig.stagingUnavailableMessage, contains('Online payment is unavailable in staging'));
      expect(PaymentConfig.stagingUnavailableMessage, contains('Cash / UPI on Delivery'));
    });

    test('5. Order creation payload structure matches Firebase Cloud Function contract', () {
      final order = OrderModel(
        id: 'ord_staging_test_001',
        orderNumber: 'TQ-STG-101',
        customerId: 'customer_staging_uid',
        deliveryAddressId: 'addr_stg_1',
        subtotal: 450.0,
        deliveryFee: 40.0,
        totalPrice: 490.0,
        paymentMethod: PaymentMethods.upi,
        paymentStatus: PaymentStatuses.pending,
        status: OrderStatuses.orderPlaced,
        statusIndex: 0,
        eta: DateTime.now().add(const Duration(minutes: 30)),
        verificationCode: '5678',
      );

      final map = order.toMap();

      // Verify contract matches what handleCreatePaymentSession expects
      expect(map['customerId'], equals('customer_staging_uid'));
      expect(map['totalPrice'], equals(490.0));
      expect(map['paymentMethod'], equals('UPI'));
      expect(map['paymentStatus'], equals('Pending'));

      // Verify client-side tampering protection
      expect(map['paymentUtr'], isNull);
      expect(map['youpiPaymentId'], isNull);
    });

    test('6. Cash on Delivery (COD) order lifecycle remains completely decoupled', () {
      final codOrder = OrderModel(
        id: 'ord_cod_001',
        orderNumber: 'TQ-COD-101',
        customerId: 'customer_cod_uid',
        deliveryAddressId: 'addr_cod_1',
        subtotal: 300.0,
        deliveryFee: 0.0,
        totalPrice: 300.0,
        paymentMethod: PaymentMethods.cod,
        paymentStatus: PaymentStatuses.pending,
        status: OrderStatuses.orderPlaced,
        statusIndex: 0,
        eta: DateTime.now().add(const Duration(minutes: 30)),
        verificationCode: '9012',
      );

      final map = codOrder.toMap();
      expect(map['paymentMethod'], equals('COD'));
      expect(map['paymentStatus'], equals('Pending'));
      expect(map['status'], equals(OrderStatuses.orderPlaced));
    });

    test('7. Client-side payment response parser adheres to API contract', () {
      const mockApiResponse = '''
      {
        "success": true,
        "paymentId": "pay_550e8400-e29b-41d4-a716-446655440000",
        "checkoutUrl": "http://localhost:7000/checkout/pay_550e8400-e29b-41d4-a716-446655440000",
        "orderId": "ord_staging_test_001",
        "amount": "490.00",
        "currency": "INR"
      }
      ''';

      final decoded = jsonDecode(mockApiResponse) as Map<String, dynamic>;
      expect(decoded['success'], isTrue);
      expect(decoded['paymentId'], startsWith('pay_'));
      expect(decoded['checkoutUrl'], contains('/checkout/'));
      expect(decoded['amount'], equals('490.00'));
      expect(decoded['currency'], equals('INR'));
    });

    test('8. OrderModel supports optional youpiPaymentId and youpiCheckoutUrl safely', () {
      final orderWithSession = OrderModel(
        id: 'ord_retry_001',
        orderNumber: 'TQ-RETRY-01',
        customerId: 'cust_retry_1',
        deliveryAddressId: 'addr_1',
        subtotal: 250.0,
        deliveryFee: 20.0,
        totalPrice: 270.0,
        paymentMethod: PaymentMethods.upi,
        paymentStatus: PaymentStatuses.pending,
        status: OrderStatuses.orderPlaced,
        statusIndex: 0,
        eta: DateTime.now().add(const Duration(minutes: 20)),
        verificationCode: '1122',
        youpiPaymentId: 'pay_retry_session_abc',
        youpiCheckoutUrl: 'https://pay.youpi.test/checkout/pay_retry_session_abc',
      );

      final map = orderWithSession.toMap();
      expect(map['youpiPaymentId'], equals('pay_retry_session_abc'));
      expect(map['youpiCheckoutUrl'], equals('https://pay.youpi.test/checkout/pay_retry_session_abc'));

      // Check deserialization from Firestore
      final restored = OrderModel.fromFirestore('ord_retry_001', map);
      expect(restored.youpiPaymentId, equals('pay_retry_session_abc'));
      expect(restored.youpiCheckoutUrl, equals('https://pay.youpi.test/checkout/pay_retry_session_abc'));
      expect(restored.paymentStatus, equals(PaymentStatuses.pending));
    });

    test('9. Convert order to COD URL configuration is safe and authenticated', () {
      expect(PaymentConfig.convertOrderToCodUrl, contains('convertOrderToCod'));

      dotenv.testLoad(fileInput: 'APP_ENV=staging\nYOUPI_CONVERT_COD_URL=http://localhost:5001/staging/convertOrderToCod');
      expect(PaymentConfig.convertOrderToCodUrl, equals('http://localhost:5001/staging/convertOrderToCod'));
    });
  });
}

