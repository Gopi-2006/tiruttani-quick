import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

import '../firebase_options.dart';
import '../core/router/app_router.dart';
import 'current_user_provider.dart';
import 'service_area_provider.dart';
import 'admob_service.dart';

class StartupProvider extends ChangeNotifier {
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  List<CategoryModel> _categories = [];
  List<CategoryModel> get categories => _categories;

  final List<Map<String, dynamic>> _promotions = [];
  List<Map<String, dynamic>> get promotions => _promotions;

  List<ProductModel> _products = [];
  List<ProductModel> get products => _products;

  List<BannerModel> _banners = [];
  List<BannerModel> get banners => _banners;

  List<OfferModel> _offers = [];
  List<OfferModel> get offers => _offers;

  List<FlashSaleModel> _flashSales = [];
  List<FlashSaleModel> get flashSales => _flashSales;

  StreamSubscription? _bannersSub;
  StreamSubscription? _offersSub;
  StreamSubscription? _flashSalesSub;

  DocumentSnapshot? _lastDocument;
  bool _hasMoreProducts = true;
  bool get hasMoreProducts => _hasMoreProducts;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  /// Start the initialization process in the background.
  Future<void> runInitialization(BuildContext context) async {
    if (_isInitialized) return;

    try {
      debugPrint('[Startup Log] Phase 1: High Priority - Ensuring Firebase Core is initialized...');
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
          debugPrint('[Startup Log] Firebase initialized inside runInitialization.');
        } else {
          debugPrint('[Startup Log] Firebase core is already initialized from main().');
        }
      } catch (e) {
        debugPrint('[Startup Log] Error ensuring Firebase initialization: $e');
      }

      // Register background message handler immediately after core initialization
      try {
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
        debugPrint('[Startup Log] Background messaging handler registered.');
      } catch (e) {
        debugPrint('[Startup Log] Failed to register background messaging handler: $e');
      }

      debugPrint('[Startup Log] Checking connectivity status...');
      if (!ConnectivityProvider.instance.isOnline) {
        debugPrint('[Startup Log] Device is offline, waiting for internet connection...');
        await ConnectivityProvider.instance.onConnectivityChanged
            .firstWhere((online) => online)
            .timeout(const Duration(seconds: 3), onTimeout: () => true);
        debugPrint('[Startup Log] Resuming data initialization.');
      }

      debugPrint('[Startup Log] Phase 2: Running Concurrent Startup Data Tasks...');
      // Run high, medium, and low priority tasks concurrently with safety timeouts and error suppression
      await Future.wait([
        _waitForAuth().catchError((e) => debugPrint('[Startup Log] Auth check error: $e')),
        serviceAreaProvider.initServiceArea().timeout(const Duration(seconds: 3), onTimeout: () {
          debugPrint('[Startup Log] Service area check timed out');
        }).catchError((e) => debugPrint('[Startup Log] Service area error: $e')),
        _fetchCategories().timeout(const Duration(seconds: 4), onTimeout: () {
          debugPrint('[Startup Log] Categories fetch timed out');
        }).catchError((e) => debugPrint('[Startup Log] Categories fetch error: $e')),
        _fetchBanners().timeout(const Duration(seconds: 4), onTimeout: () {
          debugPrint('[Startup Log] Banners fetch timed out');
        }).catchError((e) => debugPrint('[Startup Log] Banners fetch error: $e')),
        _fetchOffers().timeout(const Duration(seconds: 4), onTimeout: () {
          debugPrint('[Startup Log] Offers fetch timed out');
        }).catchError((e) => debugPrint('[Startup Log] Offers fetch error: $e')),
        _fetchFlashSales().timeout(const Duration(seconds: 4), onTimeout: () {
          debugPrint('[Startup Log] Flash sales fetch timed out');
        }).catchError((e) => debugPrint('[Startup Log] Flash sales fetch error: $e')),
        _fetchFirstPageProducts().timeout(const Duration(seconds: 4), onTimeout: () {
          debugPrint('[Startup Log] Products fetch timed out');
        }).catchError((e) => debugPrint('[Startup Log] Products fetch error: $e')),
        _initBackgroundServices().timeout(const Duration(seconds: 4), onTimeout: () {
          debugPrint('[Startup Log] Background services init timed out');
        }).catchError((e) => debugPrint('[Startup Log] Background services error: $e')),
      ]);

      // Start real-time subscriptions for real-time price changes
      _startMarketingSubscriptions();

      debugPrint('[Startup Log] Phase 3: Start Pre-caching Images (Medium Priority)...');
      // Precache images in the background (does not block splash finish)
      if (context.mounted) {
        precacheStartupImages(context);
      }

      _isInitialized = true;
      notifyListeners();
      debugPrint('[Startup Log] All Initialization Steps Completed Successfully!');
    } catch (e, stack) {
      debugPrint('[Startup Log] Initialization Exception Caught: $e\n$stack');
      // Set initialized to true anyway to avoid trapping user on splash screen
      _isInitialized = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _bannersSub?.cancel();
    _offersSub?.cancel();
    _flashSalesSub?.cancel();
    super.dispose();
  }

  void _startMarketingSubscriptions() {
    final firestore = FirestoreService();
    
    _bannersSub?.cancel();
    _bannersSub = firestore.bannersStream(includeInactive: false).listen((data) {
      _banners = data;
      _reapplyOffersToAllCachedProducts();
      notifyListeners();
    });

    _offersSub?.cancel();
    _offersSub = firestore.offersStream(includeInactive: false).listen((data) {
      _offers = data;
      _reapplyOffersToAllCachedProducts();
      notifyListeners();
    });

    _flashSalesSub?.cancel();
    _flashSalesSub = firestore.flashSalesStream(includeInactive: false).listen((data) {
      _flashSales = data;
      _reapplyOffersToAllCachedProducts();
      notifyListeners();
    });
  }

  void _reapplyOffersToAllCachedProducts() {
    _products = applyOffers(_products);
  }

  List<ProductModel> applyOffers(List<ProductModel> productList) {
    return OfferEngine.applyOffersToProducts(
      productList,
      activeBanners: _banners,
      activeOffers: _offers,
      activeFlashSales: _flashSales,
    );
  }

  ProductModel applyOffersToSingle(ProductModel product) {
    return OfferEngine.applyOffersToProduct(
      product,
      validBanners: _banners,
      validOffers: _offers,
      validFlashSales: _flashSales,
    );
  }

  /// Wait for authentication and user profile loading to complete.
  Future<void> _waitForAuth() async {
    currentUserProvider.init();
    if (!currentUserProvider.loading) return;

    final completer = Completer<void>();
    void listener() {
      if (!currentUserProvider.loading) {
        currentUserProvider.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }
    currentUserProvider.addListener(listener);
    try {
      await completer.future.timeout(const Duration(seconds: 4));
    } catch (_) {
      currentUserProvider.removeListener(listener);
    }
  }

  /// Fetch categories list from Firestore.
  Future<void> _fetchCategories() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('categories')
          .orderBy('sortOrder')
          .get();
      _categories = snapshot.docs
          .map((doc) => CategoryModel.fromFirestore(doc.id, doc.data()))
          .toList();
    } catch (e) {
      debugPrint('[Startup] Error fetching categories: $e');
    }
  }

  Future<void> _fetchBanners() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('banners')
          .orderBy('displayOrder')
          .get();
      _banners = snapshot.docs
          .map((doc) => BannerModel.fromFirestore(doc.id, doc.data()))
          .where((banner) => banner.isActive)
          .toList();
    } catch (e) {
      debugPrint('[Startup] Error fetching banners: $e');
    }
  }

  Future<void> _fetchOffers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('offers')
          .get();
      _offers = snapshot.docs
          .map((doc) => OfferModel.fromFirestore(doc.id, doc.data()))
          .where((offer) => offer.isActive)
          .toList();
    } catch (e) {
      debugPrint('[Startup] Error fetching offers: $e');
    }
  }

  Future<void> _fetchFlashSales() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('flash_sales')
          .get();
      _flashSales = snapshot.docs
          .map((doc) => FlashSaleModel.fromFirestore(doc.id, doc.data()))
          .where((sale) => sale.isActive)
          .toList();
    } catch (e) {
      debugPrint('[Startup] Error fetching flash sales: $e');
    }
  }

  /// Fetch the first page of products (15 items) from Firestore.
  Future<void> _fetchFirstPageProducts() async {
    try {
      final query = FirebaseFirestore.instance
          .collection('products')
          .orderBy('sortOrder')
          .limit(15);
      final snapshot = await query.get();
      if (snapshot.docs.isNotEmpty) {
        _lastDocument = snapshot.docs.last;
        final list = snapshot.docs
            .map((doc) => ProductModel.fromFirestore(doc.id, doc.data()))
            .toList();
        final activeList = list.where((p) => p.isActive).toList();
        _products = applyOffers(activeList);
        _hasMoreProducts = snapshot.docs.length >= 15;
      } else {
        _hasMoreProducts = false;
      }
    } catch (e) {
      debugPrint('[Startup] Error fetching first page of products: $e');
    }
  }

  /// Load subsequent pages of products for infinite scroll.
  Future<void> loadNextPageProducts() async {
    if (_isLoadingMore || !_hasMoreProducts) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      var query = FirebaseFirestore.instance
          .collection('products')
          .orderBy('sortOrder');

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }
      query = query.limit(10);

      final snapshot = await query.get();
      if (snapshot.docs.isNotEmpty) {
        _lastDocument = snapshot.docs.last;
        final list = snapshot.docs
            .map((doc) => ProductModel.fromFirestore(doc.id, doc.data()))
            .toList();
        final newProducts = list.where((p) => p.isActive).toList();
        _products.addAll(applyOffers(newProducts));
        _hasMoreProducts = snapshot.docs.length >= 10;
      } else {
        _hasMoreProducts = false;
      }
    } catch (e) {
      debugPrint('[Startup] Error loading next product page: $e');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Pre-cache banner and product images.
  void precacheStartupImages(BuildContext context) {
    if (!context.mounted) return;

    // Precache banner images
    for (final banner in _banners) {
      if (banner.imageUrl.isNotEmpty) {
        precacheImage(CachedNetworkImageProvider(banner.imageUrl), context).catchError((e) {
          debugPrint('[Startup] Failed to pre-cache banner: ${banner.imageUrl}, error: $e');
        });
      }
    }

    // Precache product thumbnail images
    for (final product in _products) {
      if (product.imageUrl.isNotEmpty) {
        precacheImage(
          CachedNetworkImageProvider(product.imageUrl),
          context,
        ).catchError((e) {
          debugPrint('[Startup] Failed to pre-cache product thumbnail: ${product.imageUrl}, error: $e');
        });
      }
    }
  }

  /// Initialize AdMob and background notifications (Low priority/Asynchronous services).
  Future<void> _initBackgroundServices() async {
    // 1. Initialize AdMob
    try {
      debugPrint('[Startup Log] Sub-step 1: Initializing AdMob SDK...');
      AdMobService().initialize();
    } catch (e) {
      debugPrint('[Startup Log] AdMob initialization non-fatal error: $e');
    }

    // 2. Initialize App Check with safety fallback
    try {
      debugPrint('[Startup Log] Sub-step 2: Activating Firebase App Check...');
      await FirebaseAppCheck.instance.activate(
        androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
      ).catchError((e, stack) {
        debugPrint('[Startup Log] Firebase App Check activation catchError: $e');
      });
      debugPrint('[Startup Log] Firebase App Check activated.');
    } catch (e, stack) {
      debugPrint('[Startup Log] Firebase App Check activation non-fatal error: $e\n$stack');
    }

    // 3. Initialize NotificationService
    try {
      debugPrint('[Startup Log] Sub-step 3: Initializing Notification Service...');
      await NotificationService.instance.initialize(
        onNotificationTap: (payload) {
          debugPrint('[Startup Log] Notification Tapped: $payload');
          final type = payload['type'] ?? '';
          final screen = payload['screen'] ?? '';
          final orderId = payload['orderId'] ?? '';

          if (screen == 'order_tracking' || type == 'order') {
            if (orderId.isNotEmpty) {
              router.push('${AppRoutes.myOrders}/$orderId');
            }
          } else if (type == 'promotion' || screen == 'home') {
            router.go(AppRoutes.home);
          }
        },
      );

      debugPrint('[Startup Log] Notification Service initialized.');
    } catch (e, stack) {
      debugPrint('[Startup Log] Notification Service initialization non-fatal error: $e\n$stack');
    }
  }
}

final startupProvider = StartupProvider();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('[Background Messaging Error] $e');
  }
}
