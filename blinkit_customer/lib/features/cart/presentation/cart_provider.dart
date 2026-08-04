import 'package:blinkit_shared/blinkit_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ignore: depend_on_referenced_packages
import '../../../services/current_user_provider.dart';

/// [CartProvider] manages the in-memory cart state and synchronises it to
/// Firestore in the background.
///
/// **Race-condition fixes (v2)**:
/// - Self-initializes reactively when [CurrentUserProvider] transitions from
///   loading → authenticated instead of relying on the widget tree to call init.
/// - Concurrent [init] calls are dropped via [_isInitializing] guard.
/// - [add] queues itself if the cart is still initializing (first-login fix).
/// - Exposes [isCartReady] so the UI can disable ADD while loading.
class CartProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Internal state ──────────────────────────────────────────────────────────
  String? _userId;
  bool _loading = false;
  bool _isInitializing = false; // Guard against concurrent init calls
  bool _cartReady = false; // True once first init completes for current user

  final Map<String, CartItemModel> _items = {};
  final Map<String, ProductModel> _productsCache = {};

  // Pending ADD operations queued while the cart is still initialising
  final List<_PendingAdd> _pendingAdds = [];

  // ── Coupon state ────────────────────────────────────────────────────────────
  String _couponCode = '';
  double _couponDiscount = 0.0;
  String? bannerIdClicked;

  // ── Public getters ──────────────────────────────────────────────────────────
  bool get loading => _loading;

  /// True once the cart has been fully loaded for the current user.
  /// The ADD button should be disabled while this is false.
  bool get isCartReady => _cartReady;

  Iterable<CartItemModel> get items => _items.values;
  int get itemCount => _items.values.fold(0, (total, item) => total + item.quantity);
  ProductModel? getProduct(String productId) => _productsCache[productId];

  String get couponCode => _couponCode;
  double get couponDiscount => _couponDiscount;

  double get subtotal {
    return _items.values.fold(0, (total, item) => total + item.subtotal);
  }

  double get deliveryFee {
    if (_items.isEmpty) return 0;
    return subtotal >= AppConstants.freeDeliveryAbove ? 0.0 : AppConstants.deliveryFee.toDouble();
  }

  double get total => (subtotal + deliveryFee - _couponDiscount).clamp(0.0, double.infinity);

  // ── User-binding ────────────────────────────────────────────────────────────

  /// Attach this cart to a [CurrentUserProvider] so it self-initialises
  /// whenever the auth state resolves. Called once from [main.dart] or from
  /// the top-level widget after providers are created.
  void bindToUserProvider(CurrentUserProvider userProvider) {
    userProvider.addListener(() => _onUserProviderChanged(userProvider));
    // Fire immediately in case the provider is already resolved
    _onUserProviderChanged(userProvider);
  }

  void _onUserProviderChanged(CurrentUserProvider userProvider) {
    // Still loading auth state — do nothing yet
    if (userProvider.loading) {
      debugPrint('[CartProvider] Auth still loading — waiting...');
      return;
    }

    final uid = userProvider.firebaseUser?.uid;

    if (uid == null) {
      // User signed out
      debugPrint('[CartProvider] No user — clearing cart.');
      _clearLocalState();
      return;
    }

    if (uid == _userId && _cartReady) {
      // Same user, already loaded
      debugPrint('[CartProvider] Cart already loaded for uid=$uid.');
      return;
    }

    // New user or first load — initialise
    debugPrint('[CartProvider] Auth resolved for uid=$uid. Initialising cart...');
    init(uid);
  }

  void _clearLocalState() {
    _userId = null;
    _cartReady = false;
    _loading = false;
    _isInitializing = false;
    _items.clear();
    _productsCache.clear();
    _couponCode = '';
    _couponDiscount = 0.0;
    _pendingAdds.clear();
    notifyListeners();
  }

  // ── Initialisation ──────────────────────────────────────────────────────────

  /// Load the cart for [userId] from Firestore.
  /// Safe to call multiple times — concurrent calls are dropped.
  Future<void> init(String userId) async {
    // Guard: prevent concurrent initialisation
    if (_isInitializing) {
      debugPrint('[CartProvider] init() already in progress — skipping duplicate call.');
      return;
    }

    // Guard: already loaded for this user
    if (_userId == userId && _cartReady) {
      debugPrint('[CartProvider] Cart already ready for uid=$userId.');
      return;
    }

    debugPrint('[CartProvider] Starting cart init for uid=$userId...');
    _isInitializing = true;
    _userId = userId;
    _cartReady = false;
    _loading = true;
    notifyListeners();

    try {
      final snapshot = await _db
          .collection('cart_items')
          .where('userId', isEqualTo: userId)
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('[CartProvider] Firestore cart fetch timed out after 10s.');
              throw Exception('Cart load timed out. Please check your connection.');
            },
          );

      _items.clear();
      _productsCache.clear();

      for (final doc in snapshot.docs) {
        final item = CartItemModel.fromFirestore(doc.id, doc.data());
        final key = item.variantId.isNotEmpty ? '${item.productId}_${item.variantId}' : item.productId;
        _items[key] = item;
      }

      // Batch-fetch product details for all cart items
      if (_items.isNotEmpty) {
        final productIds = _items.values.map((item) => item.productId).toSet().toList();
        await Future.wait(productIds.map((pid) async {
          try {
            final doc = await _db.collection('products').doc(pid).get();
            if (doc.exists) {
              _productsCache[pid] = ProductModel.fromFirestore(doc.id, doc.data()!);
            }
          } catch (e) {
            debugPrint('[CartProvider] Failed to fetch product $pid: $e');
          }
        }));
      }

      debugPrint('[CartProvider] Cart loaded. ${_items.length} item(s) for uid=$userId.');
    } catch (e) {
      debugPrint('[CartProvider] Cart init error: $e');
      // Even on error, mark ready so the UI shows empty cart / error state
    } finally {
      _loading = false;
      _isInitializing = false;
      _cartReady = true;
      notifyListeners();
    }

    // Flush any ADD operations that arrived while we were initialising
    _flushPendingAdds();
  }

  // ── Pending-add queue ───────────────────────────────────────────────────────

  void _flushPendingAdds() {
    if (_pendingAdds.isEmpty) return;
    debugPrint('[CartProvider] Flushing ${_pendingAdds.length} queued ADD operation(s)...');
    final snapshot = List<_PendingAdd>.from(_pendingAdds);
    _pendingAdds.clear();
    for (final pending in snapshot) {
      add(pending.product, variant: pending.variant);
    }
  }

  // ── Coupon ──────────────────────────────────────────────────────────────────

  void applyCoupon(String code) {
    final normalized = code.trim().toUpperCase();
    if (normalized == 'RANUKA10') {
      _couponCode = 'RANUKA10';
      _couponDiscount = subtotal * 0.10;
    } else if (normalized == 'TIRUTTANI20') {
      _couponCode = 'TIRUTTANI20';
      _couponDiscount = subtotal * 0.20;
    } else {
      _couponCode = '';
      _couponDiscount = 0.0;
    }
    notifyListeners();
  }

  void clearCoupon() {
    _couponCode = '';
    _couponDiscount = 0.0;
    notifyListeners();
  }

  // ── Cart operations ─────────────────────────────────────────────────────────

  Future<void> add(ProductModel product, {ProductVariantModel? variant}) async {
    final userId = _userId;
    if (userId == null) {
      debugPrint('[CartProvider] add() called but _userId is null — user not logged in.');
      return;
    }

    // Queue the operation if the cart is still initialising (first-login race fix)
    if (_isInitializing || !_cartReady) {
      debugPrint('[CartProvider] Cart not ready — queuing ADD for product ${product.id}.');
      _pendingAdds.add(_PendingAdd(product: product, variant: variant));
      return;
    }

    final String variantId = variant?.id ?? '';
    final String variantName = variant?.name ?? '';
    final String selectedWeight = variant != null ? variant.name : product.unit;
    final double selectedPrice = variant != null ? variant.price : product.price;
    final int stock = variant != null ? variant.stockQuantity : product.stockQuantity;

    if (stock <= 0) {
      debugPrint('[CartProvider] add() blocked — out of stock for product ${product.id}.');
      return;
    }

    _productsCache[product.id] = product;
    final String key = variantId.isNotEmpty ? '${product.id}_$variantId' : product.id;
    final existing = _items[key];

    if (existing != null) {
      if (existing.quantity >= stock) return;
      final updated = CartItemModel(
        id: existing.id,
        userId: existing.userId,
        productId: existing.productId,
        quantity: existing.quantity + 1,
        unitPrice: existing.unitPrice,
        variantId: variantId,
        variantName: variantName,
        selectedWeight: selectedWeight,
      );

      // Optimistic UI update (<10ms)
      _items[key] = updated;
      notifyListeners();

      // Background Firestore sync
      _syncIncrement(existing.id, onError: () {
        // Roll back on failure
        _items[key] = existing;
        notifyListeners();
      });
    } else {
      final docRef = _db.collection('cart_items').doc();
      final newItem = CartItemModel(
        id: docRef.id,
        userId: userId,
        productId: product.id,
        quantity: 1,
        unitPrice: selectedPrice,
        variantId: variantId,
        variantName: variantName,
        selectedWeight: selectedWeight,
      );

      // Optimistic UI update (<10ms)
      _items[key] = newItem;
      notifyListeners();

      // Background Firestore sync
      try {
        await docRef.set(newItem.toMap());
        debugPrint('[CartProvider] Firestore write success for product ${product.id}.');
      } catch (e) {
        debugPrint('[CartProvider] Firestore write FAILED for product ${product.id}: $e');
        // Retry once
        try {
          await docRef.set(newItem.toMap());
          debugPrint('[CartProvider] Firestore write retry succeeded for product ${product.id}.');
        } catch (retryErr) {
          debugPrint('[CartProvider] Firestore write retry also FAILED: $retryErr — rolling back.');
          _items.remove(key);
          notifyListeners();
        }
      }
    }
  }

  Future<void> _syncIncrement(String docId, {required VoidCallback onError}) async {
    try {
      await _db.collection('cart_items').doc(docId).update({
        'quantity': FieldValue.increment(1),
      });
      debugPrint('[CartProvider] Firestore increment success for docId=$docId.');
    } catch (e) {
      debugPrint('[CartProvider] Firestore increment FAILED for docId=$docId: $e');
      // Retry once
      try {
        await _db.collection('cart_items').doc(docId).update({
          'quantity': FieldValue.increment(1),
        });
      } catch (_) {
        onError();
      }
    }
  }

  Future<void> increment(CartItemModel item) async {
    final userId = _userId;
    if (userId == null || !_cartReady) return;

    final String key = item.variantId.isNotEmpty ? '${item.productId}_${item.variantId}' : item.productId;
    final cartItem = _items[key];
    if (cartItem == null) return;

    // Check stock from cache
    final cachedProduct = _productsCache[item.productId];
    int stock = 9999;
    if (cachedProduct != null) {
      stock = cachedProduct.stockQuantity;
      if (item.variantId.isNotEmpty && cachedProduct.variantsEnabled) {
        final vList = cachedProduct.variants.where((v) => v.id == item.variantId);
        if (vList.isNotEmpty) stock = vList.first.stockQuantity;
      }
    }

    if (cartItem.quantity >= stock) return;

    final updated = CartItemModel(
      id: cartItem.id,
      userId: cartItem.userId,
      productId: cartItem.productId,
      quantity: cartItem.quantity + 1,
      unitPrice: cartItem.unitPrice,
      variantId: cartItem.variantId,
      variantName: cartItem.variantName,
      selectedWeight: cartItem.selectedWeight,
    );

    // Optimistic update
    _items[key] = updated;
    notifyListeners();

    _syncIncrement(cartItem.id, onError: () {
      _items[key] = cartItem;
      notifyListeners();
    });
  }

  Future<void> decrement(CartItemModel item) async {
    final userId = _userId;
    if (userId == null || !_cartReady) return;

    final String key = item.variantId.isNotEmpty ? '${item.productId}_${item.variantId}' : item.productId;
    final cartItem = _items[key];
    if (cartItem == null) return;

    if (cartItem.quantity <= 1) {
      // Remove item
      _items.remove(key);
      notifyListeners();

      try {
        await _db.collection('cart_items').doc(cartItem.id).delete();
        debugPrint('[CartProvider] Deleted item docId=${cartItem.id}.');
      } catch (e) {
        debugPrint('[CartProvider] Delete FAILED for docId=${cartItem.id}: $e');
        // Restore on failure
        _items[key] = cartItem;
        notifyListeners();
      }
    } else {
      final updated = CartItemModel(
        id: cartItem.id,
        userId: cartItem.userId,
        productId: cartItem.productId,
        quantity: cartItem.quantity - 1,
        unitPrice: cartItem.unitPrice,
        variantId: cartItem.variantId,
        variantName: cartItem.variantName,
        selectedWeight: cartItem.selectedWeight,
      );

      // Optimistic update
      _items[key] = updated;
      notifyListeners();

      try {
        await _db.collection('cart_items').doc(cartItem.id).update({
          'quantity': FieldValue.increment(-1),
        });
      } catch (e) {
        debugPrint('[CartProvider] Decrement sync FAILED for docId=${cartItem.id}: $e');
        // Retry once
        try {
          await _db.collection('cart_items').doc(cartItem.id).update({
            'quantity': FieldValue.increment(-1),
          });
        } catch (_) {
          _items[key] = cartItem;
          notifyListeners();
        }
      }
    }
  }

  Future<void> remove(CartItemModel item) async {
    if (_userId == null || !_cartReady) return;

    final String key = item.variantId.isNotEmpty ? '${item.productId}_${item.variantId}' : item.productId;
    _items.remove(key);
    notifyListeners();

    try {
      await _db.collection('cart_items').doc(item.id).delete();
    } catch (e) {
      debugPrint('[CartProvider] Remove FAILED for docId=${item.id}: $e');
    }
  }

  Future<void> clear() async {
    final userId = _userId;
    if (userId == null) return;

    final snapshot = await _db
        .collection('cart_items')
        .where('userId', isEqualTo: userId)
        .get();

    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
    _items.clear();
    notifyListeners();
  }
}

// ── Internal helper ─────────────────────────────────────────────────────────

class _PendingAdd {
  final ProductModel product;
  final ProductVariantModel? variant;
  const _PendingAdd({required this.product, this.variant});
}
