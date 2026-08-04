import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../config/admob_config.dart';
import '../../services/native_ad_manager.dart';
import '../theme/app_colors.dart';
import 'skeleton_loader.dart';

class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key});

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _nativeAd;
  bool _isLoading = true;
  bool _isFailed = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    // 1. Check if we have a preloaded ad available in the pool
    final preloaded = NativeAdManager.instance.getPreloadedAd();
    if (preloaded != null) {
      setState(() {
        _nativeAd = preloaded;
        _isLoading = false;
      });
      // Start loading a new one to replenish the cache pool
      NativeAdManager.instance.preloadAd();
      return;
    }

    // 2. Fallback to direct load if pool is empty
    debugPrint('[NativeAdCard] Pool empty, loading native ad directly...');
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

    _nativeAd = NativeAd(
      adUnitId: AdMobConfig.productFeedNativeAdId,
      request: const AdRequest(),
      nativeTemplateStyle: templateStyle,
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            debugPrint('[Analytics] Ad Loaded successfully');
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[NativeAdCard] Direct ad load failed: ${error.message}');
          debugPrint('[Analytics] Ad Failed to Load: ${error.message}');
          if (mounted) {
            setState(() {
              _isFailed = true;
              _isLoading = false;
            });
          }
          ad.dispose();
        },
        onAdImpression: (ad) {
          debugPrint('[Analytics] Ad Impression recorded');
        },
        onAdClicked: (ad) {
          debugPrint('[Analytics] Ad Clicked');
        },
      ),
    );

    _nativeAd!.load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFailed) {
      return const SizedBox.shrink();
    }

    if (_isLoading || _nativeAd == null) {
      // Custom loading skeleton matching standard Medium Template structure
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        height: 320,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SkeletonBox(width: 40, height: 40, borderRadius: 20),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 120, height: 16),
                    SizedBox(height: 6),
                    SkeletonBox(width: 80, height: 12),
                  ],
                ),
              ],
            ),
            Spacer(),
            SkeletonBox(width: double.infinity, height: 160),
            Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SkeletonBox(width: 150, height: 14),
                SkeletonBox(width: 100, height: 36, borderRadius: 8),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 320,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AdWidget(ad: _nativeAd!),
      ),
    );
  }
}
