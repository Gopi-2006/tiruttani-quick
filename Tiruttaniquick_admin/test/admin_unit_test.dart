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
  });
}

