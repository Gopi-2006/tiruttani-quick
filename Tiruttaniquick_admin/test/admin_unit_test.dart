import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:tiruttaniquick_admin/services/current_user_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter_ringtone_player'),
    (MethodCall methodCall) async => null,
  );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers'),
    (MethodCall methodCall) async => 1,
  );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('xyz.luan/audioplayers.global'),
    (MethodCall methodCall) async => 1,
  );

  group('Admin Notification & Channels Unit Tests', () {
    test('NotificationSenderService endpoints and URL normalization', () {
      final sender = NotificationSenderService.instance;
      expect(sender.workerEndpoint, contains('workers.dev'));
      sender.setWorkerEndpoint('https://custom-worker.dev/');
      expect(sender.workerEndpoint, equals('https://custom-worker.dev'));
      // Reset back
      sender.setWorkerEndpoint('https://tiruttani-quick-notification-worker.tirttani-quick.workers.dev');
      expect(sender.workerEndpoint, equals('https://tiruttani-quick-notification-worker.tirttani-quick.workers.dev'));
    });

    test('sendOrderStatusNotification handles empty parameters gracefully without throwing', () async {
      final result = await NotificationSenderService.instance.sendOrderStatusNotification(
        orderId: '',
        status: '',
        customerId: '',
      );
      expect(result, isFalse);
    });

    test('sendNewOrderNotificationToAdmins handles empty parameters gracefully without throwing', () async {
      final result = await NotificationSenderService.instance.sendNewOrderNotificationToAdmins(
        orderId: '',
        orderNumber: '',
        totalAmount: 0.0,
      );
      expect(result, isFalse);
    });

    test('CurrentUserProvider persists privacy policy acceptance across sessions', () async {
      final provider = CurrentUserProvider();
      await provider.setPrivacyPolicyAccepted(true);
      expect(provider.privacyPolicyAccepted, isTrue);

      await provider.setPrivacyPolicyAccepted(false);
      expect(provider.privacyPolicyAccepted, isFalse);
    });

    test('CurrentUserProvider reset resets session state correctly', () {
      final provider = CurrentUserProvider();
      provider.reset();
      expect(provider.firebaseUser, isNull);
      expect(provider.profile, isNull);
      expect(provider.loading, isFalse);
      expect(provider.isAuthenticated, isFalse);
    });

    test('CurrentUserProvider initComplete resolves and handles initialization lifecycle', () async {
      final provider = CurrentUserProvider();
      await provider.init();
      await provider.initComplete;
      expect(provider.loading, isFalse);
    });

    test('ShopSettingsModel serializes and deserializes correctly', () {
      const defaultSettings = ShopSettingsModel();
      expect(defaultSettings.deliveryAvailable, isTrue);

      final map = {
        'deliveryAvailable': false,
        'deliveryUnavailableMessage': 'Shop closed for maintenance',
        'updatedBy': 'admin-123',
      };

      final customSettings = ShopSettingsModel.fromFirestore(map);
      expect(customSettings.deliveryAvailable, isFalse);
      expect(customSettings.deliveryUnavailableMessage, equals('Shop closed for maintenance'));
      expect(customSettings.updatedBy, equals('admin-123'));

      final toMapResult = customSettings.toMap();
      expect(toMapResult['deliveryAvailable'], isFalse);
      expect(toMapResult['deliveryUnavailableMessage'], equals('Shop closed for maintenance'));
      expect(toMapResult['updatedBy'], equals('admin-123'));
    });

    test('NewOrderAlertManager single order start and stop lifecycle', () {
      final manager = NewOrderAlertManager.instance;
      manager.resetForTesting();

      expect(manager.isAlertActive, isFalse);
      expect(manager.activeOrderIds.isEmpty, isTrue);

      // Trigger new order
      manager.handleNewOrderReceived(
        orderId: 'TQ_ORDER_001',
        orderNumber: 'TQ1001',
        totalAmount: 350.0,
        customerName: 'Gopi',
      );

      expect(manager.isAlertActive, isTrue);
      expect(manager.isOrderAlertActive('TQ_ORDER_001'), isTrue);
      expect(manager.activeOrderIds.contains('TQ_ORDER_001'), isTrue);
      expect(manager.activeOrdersNotifier.value.length, equals(1));

      // Acknowledge order
      manager.acknowledgeOrder('TQ_ORDER_001');

      expect(manager.isAlertActive, isFalse);
      expect(manager.isOrderAlertActive('TQ_ORDER_001'), isFalse);
      expect(manager.activeOrderIds.isEmpty, isTrue);
      expect(manager.activeOrdersNotifier.value.isEmpty, isTrue);
    });

    test('NewOrderAlertManager duplicate protection ignores duplicate FCM triggers', () {
      final manager = NewOrderAlertManager.instance;
      manager.resetForTesting();

      // Trigger same order twice
      manager.handleNewOrderReceived(
        orderId: 'TQ_ORDER_DUP',
        orderNumber: 'TQ2002',
        totalAmount: 500.0,
      );
      manager.handleNewOrderReceived(
        orderId: 'TQ_ORDER_DUP',
        orderNumber: 'TQ2002',
        totalAmount: 500.0,
      );

      expect(manager.activeOrderIds.length, equals(1));
      expect(manager.activeOrdersNotifier.value.length, equals(1));

      manager.acknowledgeOrder('TQ_ORDER_DUP');
      expect(manager.isAlertActive, isFalse);
    });

    test('NewOrderAlertManager handles multiple orders and preserves alert until all acknowledged', () {
      final manager = NewOrderAlertManager.instance;
      manager.resetForTesting();

      // Order A arrives
      manager.handleNewOrderReceived(orderId: 'ORDER_A', orderNumber: 'TQA');
      expect(manager.isAlertActive, isTrue);
      expect(manager.activeOrderIds.length, equals(1));

      // Order B arrives before Order A is viewed
      manager.handleNewOrderReceived(orderId: 'ORDER_B', orderNumber: 'TQB');
      expect(manager.isAlertActive, isTrue);
      expect(manager.activeOrderIds.length, equals(2));

      // Admin acknowledges Order A
      manager.acknowledgeOrder('ORDER_A');
      // Alert must CONTINUE because Order B is still unacknowledged!
      expect(manager.isAlertActive, isTrue);
      expect(manager.isOrderAlertActive('ORDER_A'), isFalse);
      expect(manager.isOrderAlertActive('ORDER_B'), isTrue);
      expect(manager.activeOrderIds.length, equals(1));

      // Admin acknowledges Order B
      manager.acknowledgeOrder('ORDER_B');
      // Alert must now STOP completely
      expect(manager.isAlertActive, isFalse);
      expect(manager.activeOrderIds.isEmpty, isTrue);
    });

    test('NewOrderAlertManager acknowledgeAll silences all active orders', () {
      final manager = NewOrderAlertManager.instance;
      manager.resetForTesting();

      manager.handleNewOrderReceived(orderId: 'ORDER_1', orderNumber: 'TQ1');
      manager.handleNewOrderReceived(orderId: 'ORDER_2', orderNumber: 'TQ2');
      manager.handleNewOrderReceived(orderId: 'ORDER_3', orderNumber: 'TQ3');

      expect(manager.activeOrderIds.length, equals(3));
      expect(manager.isAlertActive, isTrue);

      manager.acknowledgeAll();

      expect(manager.activeOrderIds.isEmpty, isTrue);
      expect(manager.isAlertActive, isFalse);
    });

    test('OrderModel backward compatibility: legacy orders without delivery person parse safely', () {
      final legacyMap = {
        'orderNumber': 'TQ_LEGACY_001',
        'customerId': 'CUST_101',
        'deliveryAddressId': 'ADDR_101',
        'subtotal': 250.0,
        'deliveryFee': 25.0,
        'totalPrice': 275.0,
        'paymentMethod': 'COD',
        'paymentStatus': 'Pending',
        'status': 'out_for_delivery',
        'statusIndex': 3,
        'verificationCode': 'ABC123',
      };

      final order = OrderModel.fromFirestore('LEGACY_ORDER_1', legacyMap);
      expect(order.id, equals('LEGACY_ORDER_1'));
      expect(order.deliveryPersonName, isNull);
      expect(order.deliveryPersonPhone, isNull);
      expect(order.toMap().containsKey('deliveryPersonName'), isFalse);
      expect(order.toMap().containsKey('deliveryPersonPhone'), isFalse);
    });

    test('OrderModel with delivery person serializes and deserializes correctly', () {
      final orderMap = {
        'orderNumber': 'TQ_DELIVERY_001',
        'customerId': 'CUST_202',
        'deliveryAddressId': 'ADDR_202',
        'subtotal': 500.0,
        'deliveryFee': 0.0,
        'totalPrice': 500.0,
        'paymentMethod': 'UPI',
        'paymentStatus': 'Completed',
        'status': 'out_for_delivery',
        'statusIndex': 3,
        'verificationCode': 'XYZ789',
        'deliveryOtp': '654321',
        'deliveryPersonName': 'Ravi Kumar',
        'deliveryPersonPhone': '9876543210',
      };

      final order = OrderModel.fromFirestore('ORDER_DELIVERY_1', orderMap);
      expect(order.deliveryPersonName, equals('Ravi Kumar'));
      expect(order.deliveryPersonPhone, equals('9876543210'));

      final serialized = order.toMap();
      expect(serialized['deliveryPersonName'], equals('Ravi Kumar'));
      expect(serialized['deliveryPersonPhone'], equals('9876543210'));

      // Test copyWith for edit & remove
      final edited = order.copyWith(deliveryPersonName: 'Arun', deliveryPersonPhone: '9698046731');
      expect(edited.deliveryPersonName, equals('Arun'));
      expect(edited.deliveryPersonPhone, equals('9698046731'));
    });

    test('Indian mobile number validation handles valid and invalid phone numbers accurately', () {
      final indianPhoneRegex = RegExp(r'^[6-9]\d{9}$');

      // Valid Indian 10-digit mobile numbers
      expect(indianPhoneRegex.hasMatch('9876543210'), isTrue);
      expect(indianPhoneRegex.hasMatch('6382910472'), isTrue);
      expect(indianPhoneRegex.hasMatch('7012345678'), isTrue);
      expect(indianPhoneRegex.hasMatch('8901234567'), isTrue);

      // Invalid formats
      expect(indianPhoneRegex.hasMatch('123'), isFalse);
      expect(indianPhoneRegex.hasMatch('98765'), isFalse);
      expect(indianPhoneRegex.hasMatch('abcdef1234'), isFalse);
      expect(indianPhoneRegex.hasMatch('0876543210'), isFalse); // starts with 0
      expect(indianPhoneRegex.hasMatch('5987654321'), isFalse); // starts with 5
      expect(indianPhoneRegex.hasMatch('98765432100'), isFalse); // 11 digits
    });

    test('Phone dialer URI generation normalizes and produces valid tel URL', () {
      final phone = '+91 98765-43210';
      final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
      final uri = Uri(scheme: 'tel', path: clean);

      expect(uri.toString(), equals('tel:+919876543210'));
      expect(uri.scheme, equals('tel'));
    });

    test('sendOrderStatusNotification accepts optional deliveryPersonName and deliveryOtp', () async {
      final result = await NotificationSenderService.instance.sendOrderStatusNotification(
        orderId: 'ORDER_PUSH_TEST',
        status: 'out_for_delivery',
        customerId: '',
        orderNumber: 'TQ999',
        deliveryOtp: '123456',
        deliveryPersonName: 'Ravi',
      );
      // Fails gracefully because customerId is empty without crashing
      expect(result, isFalse);
    });
  });
}

