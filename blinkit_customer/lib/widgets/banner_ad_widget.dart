import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/admob_service.dart';

class BannerAdWidget extends StatefulWidget {
  final String adUnitId;

  const BannerAdWidget({super.key, required this.adUnitId});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  int _retryAttempt = 0;
  AdSize? _adSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initAdaptiveSize();
  }
  void _initAdaptiveSize() async {
    try {
      final orientation = MediaQuery.of(context).orientation;
      final width = MediaQuery.of(context).size.width.truncate();
      
      final adaptiveSize = await AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
        orientation,
        width,
      );

      if (adaptiveSize != null && adaptiveSize != _adSize && mounted) {
        setState(() {
          _adSize = adaptiveSize;
        });
        _loadAd();
      }
    } catch (e) {
      AdMobService().log('Error computing adaptive banner size: $e');
      if (_adSize == null && mounted) {
        setState(() {
          _adSize = AdSize.banner;
        });
        _loadAd();
      }
    }
  }

  void _loadAd() {
    // Wait until AdMob SDK initialization completes
    if (!AdMobService().isInitialized) {
      Future.delayed(const Duration(seconds: 1), _loadAd);
      return;
    }

    // Dispose existing ad if size changed
    _bannerAd?.dispose();
    _bannerAd = null;
    setState(() {
      _isLoaded = false;
    });

    final targetSize = _adSize ?? AdSize.banner;
    AdMobService().log('Loading Banner Ad of size: $targetSize (Unit ID: ${widget.adUnitId})...');

    _bannerAd = BannerAd(
      adUnitId: widget.adUnitId,
      size: targetSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          AdMobService().log('Banner Ad loaded successfully.');
          if (mounted) {
            setState(() {
              _isLoaded = true;
              _retryAttempt = 0;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          AdMobService().log('Banner Ad failed to load: ${error.message}');
          ad.dispose();
          _bannerAd = null;
          if (mounted) {
            setState(() {
              _isLoaded = false;
            });
          }

          // Exponential backoff retry
          _retryAttempt++;
          if (_retryAttempt <= 5) {
            final delay = Duration(seconds: _retryAttempt * 5);
            AdMobService().log('Retrying banner load in ${delay.inSeconds} seconds (attempt $_retryAttempt)...');
            Future.delayed(delay, () {
              if (mounted) _loadAd();
            });
          }
        },
        onAdOpened: (ad) => AdMobService().log('Banner Ad opened.'),
        onAdClosed: (ad) => AdMobService().log('Banner Ad closed.'),
        onAdImpression: (ad) => AdMobService().log('Banner Ad impression recorded.'),
        onAdClicked: (ad) => AdMobService().log('Banner Ad clicked.'),
      ),
    );

    _bannerAd!.load();
  }

  @override
  void dispose() {
    AdMobService().log('Disposing Banner Ad resources.');
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bannerAd != null && _isLoaded) {
      return Container(
        alignment: Alignment.center,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    }

    // Centered loading placeholder
    return Container(
      height: (_adSize?.height ?? 50).toDouble(),
      width: double.infinity,
      color: Colors.transparent,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
