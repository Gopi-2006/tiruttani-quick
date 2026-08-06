import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/admob_config.dart';
import '../core/theme/app_colors.dart';

class NativeAdManager {
  static final NativeAdManager instance = NativeAdManager._();
  NativeAdManager._();

  final List<NativeAd> _preloadedAds = [];
  bool _isPreloading = false;

  /// Returns true if there is a preloaded ad in the queue
  bool hasPreloadedAd() {
    return _preloadedAds.isNotEmpty;
  }

  /// Claims a preloaded ad from the queue, returning null if none are available
  NativeAd? getPreloadedAd() {
    if (_preloadedAds.isNotEmpty) {
      debugPrint('[NativeAdManager] Claiming preloaded native ad.');
      return _preloadedAds.removeAt(0);
    }
    return null;
  }

  /// Triggers preloading of a native ad in the background
  void preloadAd() {
    if (_isPreloading || _preloadedAds.length >= 2) return;
    _isPreloading = true;

    debugPrint('[NativeAdManager] Preloading next native ad in background...');

    final templateStyle = NativeTemplateStyle(
      templateType: TemplateType.medium,
      mainBackgroundColor: AppColors.card,
      cornerRadius: 16.0,
      callToActionTextStyle: NativeTemplateTextStyle(
        textColor: Colors.white,
        backgroundColor: AppColors.primary,
        style: NativeTemplateFontStyle.normal,
        size: 15.0,
      ),
      primaryTextStyle: NativeTemplateTextStyle(
        textColor: AppColors.text,
        style: NativeTemplateFontStyle.bold,
        size: 16.0,
      ),
      secondaryTextStyle: NativeTemplateTextStyle(
        textColor: AppColors.muted,
        style: NativeTemplateFontStyle.normal,
        size: 14.0,
      ),
      tertiaryTextStyle: NativeTemplateTextStyle(
        textColor: AppColors.muted,
        style: NativeTemplateFontStyle.normal,
        size: 12.0,
      ),
    );

    late final NativeAd ad;
    ad = NativeAd(
      adUnitId: AdMobConfig.productFeedNativeAdId,
      request: const AdRequest(),
      nativeTemplateStyle: templateStyle,
      listener: NativeAdListener(
        onAdLoaded: (loadedAd) {
          debugPrint('[NativeAdManager] Preloaded native ad loaded successfully.');
          debugPrint('[Analytics] Ad Loaded (Preloaded)');
          _preloadedAds.add(ad);
          _isPreloading = false;
          // Preload another one if queue size is small
          preloadAd();
        },
        onAdFailedToLoad: (failedAd, error) {
          debugPrint('[NativeAdManager] Preloaded native ad failed to load: ${error.message}');
          debugPrint('[Analytics] Ad Failed (Preloaded): ${error.message}');
          failedAd.dispose();
          _isPreloading = false;
        },
        onAdImpression: (impressedAd) {
          debugPrint('[Analytics] Ad Impression (Preloaded)');
        },
        onAdClicked: (clickedAd) {
          debugPrint('[Analytics] Ad Clicked (Preloaded)');
        },
      ),
    );

    ad.load();
  }

  /// Clean up and dispose of all cached preloaded ads
  void dispose() {
    debugPrint('[NativeAdManager] Disposing all preloaded ads.');
    for (final ad in _preloadedAds) {
      ad.dispose();
    }
    _preloadedAds.clear();
  }
}
