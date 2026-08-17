import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

class OnboardingService {
  static const String _seenOnboardingKey = 'has_seen_onboarding_v1';
  static final SecureStorageService _storage = SecureStorageService();

  /// Check if the user has already completed or skipped the onboarding flow.
  static Future<bool> hasSeenOnboarding() async {
    try {
      final value = await _storage.read(_seenOnboardingKey).timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => null,
      );
      return value == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Mark onboarding as completed so it will not be shown again on subsequent launches.
  static Future<void> markOnboardingComplete() async {
    try {
      await _storage.write(_seenOnboardingKey, 'true');
    } catch (_) {}
  }

  /// Reset onboarding flag (for testing or settings reset if requested).
  static Future<void> resetOnboarding() async {
    try {
      await _storage.delete(_seenOnboardingKey);
    } catch (_) {}
  }
}
