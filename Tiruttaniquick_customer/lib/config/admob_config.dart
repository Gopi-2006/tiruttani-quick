import 'package:flutter_dotenv/flutter_dotenv.dart';

class AdMobConfig {
  static String _getEnv(String key, String fallback) {
    if (dotenv.isInitialized) {
      final val = dotenv.env[key];
      if (val != null && val.trim().isNotEmpty) {
        return val.trim();
      }
    }
    return String.fromEnvironment(key, defaultValue: fallback);
  }

  // App IDs
  static String get androidAppId => _getEnv(
        'ADMOB_ANDROID_APP_ID',
        'ca-app-pub-3940256099942544~3347511713', // Google Android test app ID
      );

  static String get iosAppId => _getEnv(
        'ADMOB_IOS_APP_ID',
        'ca-app-pub-3940256099942544~1458002511', // Google iOS test app ID
      );

  // Banner Ads
  static String get homeBannerId => _getEnv(
        'ADMOB_HOME_BANNER_ID',
        'ca-app-pub-3940256099942544/6300978111',
      );

  static String get categoryBannerId => _getEnv(
        'ADMOB_CATEGORY_BANNER_ID',
        'ca-app-pub-3940256099942544/6300978111',
      );

  static String get offersBannerId => _getEnv(
        'ADMOB_OFFERS_BANNER_ID',
        'ca-app-pub-3940256099942544/6300978111',
      );

  // Interstitial Ad
  static String get orderSuccessInterstitialId => _getEnv(
        'ADMOB_ORDER_SUCCESS_INTERSTITIAL_ID',
        'ca-app-pub-3940256099942544/1033173712',
      );

  // Additional Screen Banner Ads
  static String get searchBannerId => _getEnv(
        'ADMOB_SEARCH_BANNER_ID',
        'ca-app-pub-3940256099942544/6300978111',
      );

  static String get cartBannerId => _getEnv(
        'ADMOB_CART_BANNER_ID',
        'ca-app-pub-3940256099942544/6300978111',
      );

  static String get ordersBannerId => _getEnv(
        'ADMOB_ORDERS_BANNER_ID',
        'ca-app-pub-3940256099942544/6300978111',
      );

  static String get productReviewsBannerId => _getEnv(
        'ADMOB_PRODUCT_REVIEWS_BANNER_ID',
        'ca-app-pub-3940256099942544/6300978111',
      );

  static String get myProfileBannerId => _getEnv(
        'ADMOB_MY_PROFILE_BANNER_ID',
        'ca-app-pub-3940256099942544/6300978111',
      );

  static String get settingsBannerId => _getEnv(
        'ADMOB_SETTINGS_BANNER_ID',
        'ca-app-pub-3940256099942544/6300978111',
      );

  // Native Ad
  static String get productFeedNativeAdId => _getEnv(
        'ADMOB_PRODUCT_FEED_NATIVE_AD_ID',
        'ca-app-pub-3940256099942544/2247696110',
      );
}
