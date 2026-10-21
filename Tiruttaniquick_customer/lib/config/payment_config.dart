import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration for payment handling in the Tiruttani Quick Customer app.
///
/// SAFETY CONSTRAINTS & AUDIT RULES:
/// 1. Online UPI is strictly disabled in production builds.
/// 2. Only dedicated staging builds with an explicit staging configuration
///    can enable Online UPI for testing.
/// 3. The client application NEVER marks an order as Paid. Only verified
///    server-side webhooks from YouPI-PG can update payment status.
/// 4. Cash / UPI on Delivery remains the reliable fallback in all environments.
class PaymentConfig {
  static String _getEnv(String key, String fallback) {
    if (dotenv.isInitialized) {
      final val = dotenv.env[key];
      if (val != null && val.trim().isNotEmpty) {
        return val.trim();
      }
    }
    return String.fromEnvironment(key, defaultValue: fallback);
  }

  /// Whether the app is running in an explicit staging environment.
  static bool get isStaging {
    const isStagingEnvConst = bool.fromEnvironment('STAGING_BUILD', defaultValue: false);
    if (isStagingEnvConst) return true;

    if (dotenv.isInitialized) {
      final env = (dotenv.env['APP_ENV'] ?? '').trim().toLowerCase();
      if (env == 'staging' || env == 'stg') return true;
    }
    return false;
  }

  /// Controls whether Online UPI is enabled for customer selection.
  ///
  /// CRITICAL RULES:
  /// - Online UPI is strictly DISABLED in production release builds.
  /// - Only enabled when [isStaging] is true AND [ENABLE_STAGING_ONLINE_UPI] is explicitly set to 'true'.
  static bool get isStagingOnlineUpiEnabled {
    // In production release mode, if not an explicit STAGING_BUILD, it is ALWAYS disabled.
    if (kReleaseMode && !const bool.fromEnvironment('STAGING_BUILD', defaultValue: false)) {
      return false;
    }

    const compileTimeFlag = bool.fromEnvironment('ENABLE_STAGING_ONLINE_UPI', defaultValue: false);
    if (isStaging && compileTimeFlag) {
      return true;
    }

    final explicitFlag = _getEnv('ENABLE_STAGING_ONLINE_UPI', 'false').toLowerCase() == 'true';
    return isStaging && explicitFlag;
  }

  /// Whether to use the local Firebase emulator suite.
  /// Strictly false by default unless USE_FIREBASE_EMULATOR is explicitly set to 'true'.
  static bool get useFirebaseEmulator {
    // Release builds must NEVER connect to an emulator
    if (kReleaseMode) return false;
    final explicitFlag = _getEnv('USE_FIREBASE_EMULATOR', 'false').toLowerCase() == 'true';
    const compileTimeFlag = bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false);
    return explicitFlag || compileTimeFlag;
  }

  /// Host address for the Firebase emulator.
  static String get firebaseEmulatorHost {
    final customHost = _getEnv('FIREBASE_EMULATOR_HOST', '');
    if (customHost.isNotEmpty) return customHost;
    if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
      return '10.0.2.2';
    }
    return '127.0.0.1';
  }

  /// Port for the Firestore emulator.
  static int get firestoreEmulatorPort => 8080;

  /// The Cloud Function endpoint for creating a YouPI-PG payment session.
  ///
  /// Defaults to the secure Firebase Cloud Function endpoint for the project.
  static String get createPaymentSessionUrl {
    final customUrl = _getEnv('YOUPI_CREATE_PAYMENT_URL', '');
    if (customUrl.isNotEmpty) {
      return customUrl;
    }

    if (useFirebaseEmulator) {
      return 'http://$firebaseEmulatorHost:5001/blinkit-grocery-c3f5d/us-central1/createYoupiPaymentSession';
    }

    // Default Firebase Function URL in us-central1 for blinkit-grocery-c3f5d
    return 'https://us-central1-blinkit-grocery-c3f5d.cloudfunctions.net/createYoupiPaymentSession';
  }

  /// The Cloud Function endpoint for converting a pending online order to Cash on Delivery.
  static String get convertOrderToCodUrl {
    final customUrl = _getEnv('YOUPI_CONVERT_COD_URL', '');
    if (customUrl.isNotEmpty) {
      return customUrl;
    }

    if (useFirebaseEmulator) {
      return 'http://$firebaseEmulatorHost:5001/blinkit-grocery-c3f5d/us-central1/convertOrderToCod';
    }

    return 'https://us-central1-blinkit-grocery-c3f5d.cloudfunctions.net/convertOrderToCod';
  }

  /// Friendly error message when staging payment backend is unreachable.
  static const String stagingUnavailableMessage =
      'Online payment is unavailable in staging. Please choose Cash / UPI on Delivery.';
}
