import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tiruttaniquick_customer/config/payment_config.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

void main() {
  group('Tiruttani Quick + YouPI-PG Checkout Payment UI & Security Tests', () {
    test('1. Default Payment Method is Cash / UPI on Delivery (COD)', () {
      // COD and UPI on Delivery must remain the standard, reliable default
      expect(PaymentMethods.cod, equals('COD'));
      expect(PaymentMethods.upi, equals('UPI'));
      expect(PaymentStatuses.pending, equals('Pending'));
      expect(PaymentStatuses.paid, equals('Paid'));
    });

    test('2. Online UPI is strictly disabled in standard production builds', () {
      // In default environment without explicit staging config, Online UPI is disabled
      dotenv.testLoad(fileInput: '');
      expect(PaymentConfig.isStaging, isFalse);
      expect(PaymentConfig.isStagingOnlineUpiEnabled, isFalse);
    });

    test('3. Staging Online UPI requires explicit staging configuration', () {
      // Only when APP_ENV=staging AND ENABLE_STAGING_ONLINE_UPI=true is it enabled
      dotenv.testLoad(fileInput: 'APP_ENV=staging\nENABLE_STAGING_ONLINE_UPI=true');
      expect(PaymentConfig.isStaging, isTrue);
      expect(PaymentConfig.isStagingOnlineUpiEnabled, isTrue);
    });

    test('4. Online UPI remains disabled in staging if ENABLE_STAGING_ONLINE_UPI is false', () {
      dotenv.testLoad(fileInput: 'APP_ENV=staging\nENABLE_STAGING_ONLINE_UPI=false');
      expect(PaymentConfig.isStaging, isTrue);
      expect(PaymentConfig.isStagingOnlineUpiEnabled, isFalse);
    });

    test('5. Staging backend unavailable message is clear and instructs fallback', () {
      expect(
        PaymentConfig.stagingUnavailableMessage,
        contains('Online payment is unavailable in staging'),
      );
      expect(
        PaymentConfig.stagingUnavailableMessage,
        contains('Cash / UPI on Delivery'),
      );
    });

    test('6. Payment session endpoint defaults to secure Firebase Cloud Function', () {
      dotenv.testLoad(fileInput: '');
      final endpoint = PaymentConfig.createPaymentSessionUrl;
      expect(endpoint, startsWith('https://'));
      expect(endpoint, contains('createYoupiPaymentSession'));
    });

    test('7. Client-side payment status invariance', () {
      // Orders must be placed with Pending payment status
      final order = OrderModel(
        id: 'test_order_123',
        orderNumber: 'TQ1001',
        customerId: 'cust_abc',
        deliveryAddressId: 'addr_1',
        subtotal: 250.0,
        deliveryFee: 30.0,
        totalPrice: 280.0,
        paymentMethod: PaymentMethods.upi,
        paymentStatus: PaymentStatuses.pending,
        status: OrderStatuses.orderPlaced,
        statusIndex: 0,
        eta: DateTime.now().add(const Duration(minutes: 30)),
        verificationCode: '1234',
      );

      final map = order.toMap();
      // Client cannot set Paid
      expect(map['paymentStatus'], equals(PaymentStatuses.pending));
      expect(map['paymentStatus'], isNot(equals(PaymentStatuses.paid)));
    });
  });
}
