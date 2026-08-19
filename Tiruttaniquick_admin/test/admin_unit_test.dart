import 'package:flutter_test/flutter_test.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:tiruttaniquick_admin/services/current_user_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

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
  });
}

