import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/admob_config.dart';

class AdMobService {
  // Singleton Pattern
  static final AdMobService _instance = AdMobService._internal();
  factory AdMobService() => _instance;
  AdMobService._internal();

  bool _isInitialized = false;
  bool _isInitializing = false;
  
  // Interstitial Ad state
  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoading = false;
  int _interstitialRetryAttempt = 0;

  bool get isInitialized => _isInitialized;

  /// Logs messages only in debug mode
  void log(String message) {
    if (kDebugMode) {
      debugPrint('[AdMobService] $message');
    }
  }

  /// Entry point for initializing AdMob with the GDPR Consent Flow (UMP)
  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) {
      log('Initialization already in progress or completed.');
      return;
    }
    _isInitializing = true;
    log('Starting initialization with UMP consent gathering...');

    try {
      final params = ConsentRequestParameters();
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () async {
          ConsentInformation.instance.isConsentFormAvailable().then((isAvailable) {
            if (isAvailable) {
              _loadConsentForm();
            } else {
              log('Consent form not available. Direct SDK init.');
              _initSDK();
            }
          });
        },
        (FormError error) {
          log('Consent update request failed: ${error.message}. Direct SDK init.');
          _initSDK();
        },
      );
    } catch (e) {
      log('Error during consent check: $e. Fallback to direct SDK init.');
      _initSDK();
    }
  }

  void _loadConsentForm() {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) {
        ConsentInformation.instance.getConsentStatus().then((status) {
          if (status == ConsentStatus.required) {
            consentForm.show((FormError? error) {
              if (error != null) {
                log('Error showing consent form: ${error.message}');
              } else {
                log('Consent gathered successfully.');
              }
              _initSDK();
            });
          } else {
            log('Consent status not required ($status). Direct SDK init.');
            _initSDK();
          }
        });
      },
      (FormError error) {
        log('Failed to load consent form: ${error.message}. Direct SDK init.');
        _initSDK();
      },
    );
  }

  Future<void> _initSDK() async {
    try {
      log('Initializing MobileAds SDK...');
      await MobileAds.instance.initialize();
      _isInitialized = true;
      _isInitializing = false;
      log('AdMob SDK initialized successfully!');
      
      // Preload first interstitial ad
      loadInterstitialAd();
    } catch (e) {
      _isInitializing = false;
      log('AdMob SDK initialization failed: $e');
    }
  }

  /// Caches / preloads an Interstitial Ad
  void loadInterstitialAd() {
    if (!_isInitialized) {
      log('Cannot load interstitial: SDK not initialized.');
      return;
    }
    if (_isInterstitialLoading || _interstitialAd != null) {
      log('Interstitial ad already loading or cached.');
      return;
    }

    _isInterstitialLoading = true;
    log('Loading Interstitial Ad (Unit ID: ${AdMobConfig.orderSuccessInterstitialId})...');

    InterstitialAd.load(
      adUnitId: AdMobConfig.orderSuccessInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialLoading = false;
          _interstitialRetryAttempt = 0;
          log('Interstitial Ad loaded successfully.');

          // Set up screen content callbacks
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (ad) {
              log('Interstitial Ad showed.');
            },
            onAdDismissedFullScreenContent: (ad) {
              log('Interstitial Ad dismissed. Disposing ad and preloading next.');
              ad.dispose();
              _interstitialAd = null;
              loadInterstitialAd(); // Cache next
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              log('Interstitial Ad failed to show: ${error.message}');
              ad.dispose();
              _interstitialAd = null;
              loadInterstitialAd(); // Retry caching
            },
            onAdImpression: (ad) {
              log('Interstitial Ad impression recorded.');
            },
            onAdClicked: (ad) {
              log('Interstitial Ad clicked.');
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isInterstitialLoading = false;
          _interstitialAd = null;
          _interstitialRetryAttempt++;
          log('Interstitial Ad failed to load: ${error.message}');

          // Exponential backoff up to 5 attempts
          if (_interstitialRetryAttempt <= 5) {
            final delay = Duration(seconds: _interstitialRetryAttempt * 5);
            log('Retrying interstitial load in ${delay.inSeconds} seconds (attempt $_interstitialRetryAttempt)...');
            Future.delayed(delay, () => loadInterstitialAd());
          }
        },
      ),
    );
  }

  /// Shows the cached Interstitial Ad, executing [onFinished] when done (or if ad is unavailable)
  Future<void> showInterstitialAd({required VoidCallback onFinished}) async {
    if (!_isInitialized || _interstitialAd == null) {
      log('Interstitial ad not ready or SDK not initialized. Continuing flow normally.');
      onFinished();
      loadInterstitialAd(); // Attempt to load for next time
      return;
    }

    // Wrap callbacks dynamically to ensure onFinished runs on ad dismiss or fail
    final originalCallbacks = _interstitialAd!.fullScreenContentCallback;
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: originalCallbacks?.onAdShowedFullScreenContent,
      onAdImpression: originalCallbacks?.onAdImpression,
      onAdClicked: originalCallbacks?.onAdClicked,
      onAdDismissedFullScreenContent: (ad) {
        log('Interstitial Ad dismissed. Triggering onFinished callback.');
        ad.dispose();
        _interstitialAd = null;
        onFinished();
        loadInterstitialAd(); // Preload next
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        log('Interstitial Ad failed to show: ${error.message}. Triggering onFinished callback.');
        ad.dispose();
        _interstitialAd = null;
        onFinished();
        loadInterstitialAd(); // Reload
      },
    );

    log('Displaying Interstitial Ad...');
    try {
      await _interstitialAd!.show();
    } catch (e) {
      log('Error displaying interstitial ad: $e');
      _interstitialAd = null;
      onFinished();
      loadInterstitialAd();
    }
  }
}
