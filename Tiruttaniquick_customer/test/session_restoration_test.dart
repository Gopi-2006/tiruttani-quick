import 'package:flutter_test/flutter_test.dart';
import 'package:tiruttaniquick_customer/services/current_user_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Session Restoration & Privacy Persistence Tests', () {
    test('CurrentUserProvider defaults to unauthenticated if no user present', () {
      final provider = CurrentUserProvider();
      expect(provider.isAuthenticated, isFalse);
      expect(provider.role, equals('customer'));
    });

    test('CurrentUserProvider manages privacy policy state correctly', () async {
      final provider = CurrentUserProvider();
      expect(provider.privacyPolicyAccepted, isFalse);

      await provider.setPrivacyPolicyAccepted(true);
      expect(provider.privacyPolicyAccepted, isTrue);

      await provider.setPrivacyPolicyAccepted(false);
      expect(provider.privacyPolicyAccepted, isFalse);
    });
  });
}
