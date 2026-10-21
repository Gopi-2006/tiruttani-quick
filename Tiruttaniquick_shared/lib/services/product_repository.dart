import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/product_model.dart';
import 'firestore_service.dart';

/// In-memory cache for product catalog.
class ProductCache {
  List<ProductModel> _products = [];
  final Map<String, ProductModel> _productById = {};
  DateTime? _lastFetched;

  bool get hasData => _products.isNotEmpty;
  DateTime? get lastFetched => _lastFetched;

  /// Returns cached products, optionally filtered by active status and category.
  List<ProductModel> getProducts({
    bool includeInactive = false,
    String? categoryId,
  }) {
    Iterable<ProductModel> filtered = _products;
    if (!includeInactive) {
      filtered = filtered.where((p) => p.isActive);
    }
    if (categoryId != null && categoryId.isNotEmpty) {
      filtered = filtered.where((p) => p.categoryId == categoryId);
    }
    return List<ProductModel>.unmodifiable(filtered);
  }

  /// Looks up a single product by ID instantly in O(1).
  ProductModel? getProductById(String id) => _productById[id];

  /// Populates or replaces the entire product cache.
  void setProducts(List<ProductModel> products) {
    _products = List.from(products);
    _productById.clear();
    for (final p in _products) {
      _productById[p.id] = p;
    }
    _lastFetched = DateTime.now();
  }

  /// Inserts or updates a single product in cache (e.g. after Admin edit or stock update).
  void upsertProduct(ProductModel product) {
    _productById[product.id] = product;
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index >= 0) {
      _products[index] = product;
    } else {
      _products.add(product);
      _products.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
  }

  /// Removes a product from cache (e.g. after Admin deletion).
  void removeProduct(String productId) {
    _productById.remove(productId);
    _products.removeWhere((p) => p.id == productId);
  }

  /// Clears the cache completely.
  void clear() {
    _products.clear();
    _productById.clear();
    _lastFetched = null;
  }
}

/// Central Product Repository responsible for controlled fetching, caching,
/// in-flight deduplication, and manual refresh operations.
class ProductRepository {
  static ProductRepository? _instance;
  static ProductRepository get instance => _instance ??= ProductRepository();

  @visibleForTesting
  static void setMockInstance(ProductRepository mock) {
    _instance = mock;
  }

  final FirestoreService _firestore;
  final ProductCache _cache = ProductCache();

  /// Tracks active in-flight fetch requests to deduplicate concurrent calls.
  final Map<String, Future<List<ProductModel>>> _inFlightRequests = {};

  ProductRepository({FirestoreService? firestore})
      : _firestore = firestore ?? FirestoreService();

  ProductCache get cache => _cache;

  /// Loads initial products.
  /// - If cache contains products matching the request, returns them immediately (0 network calls).
  /// - If cache is empty, fetches once from Firestore and updates the cache.
  /// - Deduplicates simultaneous callers into the same shared Future.
  Future<List<ProductModel>> loadInitialProducts({
    bool includeInactive = false,
    String? categoryId,
  }) async {
    // 1. Check in-memory cache first
    if (_cache.hasData) {
      final cached = _cache.getProducts(
        includeInactive: includeInactive,
        categoryId: categoryId,
      );
      if (cached.isNotEmpty) {
        debugPrint('[PRODUCT] initial load SUCCESS (from cache, count: ${cached.length})');
        return cached;
      }
    }

    // 2. Cache miss -> fetch once from Firestore with in-flight deduplication
    debugPrint('[PRODUCT] initial load START (fetching from Firestore)');
    return _fetchAndCache(includeInactive: includeInactive, categoryId: categoryId);
  }

  /// Forces a fresh network fetch from Firestore.
  /// ONLY called on explicit user action:
  /// 1. Pull-to-refresh
  /// 2. User taps Refresh button
  /// 3. User taps Retry after an initial error
  Future<List<ProductModel>> refreshProducts({
    bool includeInactive = false,
    String? categoryId,
  }) async {
    debugPrint('[PRODUCT] manual refresh START (forced Firestore fetch)');
    return _fetchAndCache(
      includeInactive: includeInactive,
      categoryId: categoryId,
      isManualRefresh: true,
    );
  }

  /// Synchronously returns currently cached products without any network fetch.
  List<ProductModel> getCachedProducts({
    bool includeInactive = false,
    String? categoryId,
  }) {
    return _cache.getProducts(
      includeInactive: includeInactive,
      categoryId: categoryId,
    );
  }

  /// Synchronously retrieves a single product from cache, or null if not cached.
  ProductModel? getCachedProductById(String id) {
    return _cache.getProductById(id);
  }

  /// Fetches a single product document by ID if not in cache.
  Future<ProductModel?> loadProductDetails(String productId, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _cache.getProductById(productId);
      if (cached != null) {
        return cached;
      }
    }

    try {
      debugPrint('[PRODUCT] fetch START for product detail ID: $productId');
      final product = await _firestore.getProduct(productId);
      if (product != null) {
        _cache.upsertProduct(product);
        debugPrint('[PRODUCT] fetch SUCCESS for product detail ID: $productId');
      }
      return product;
    } catch (e) {
      debugPrint('[PRODUCT] fetch FAILED for product detail ID $productId: $e');
      rethrow;
    }
  }

  /// Directly updates an existing product or adds a new one in the cache.
  void updateCachedProduct(ProductModel product) {
    _cache.upsertProduct(product);
  }

  /// Directly removes a product from cache.
  void removeCachedProduct(String productId) {
    _cache.removeProduct(productId);
  }

  /// Shared execution with in-flight request deduplication.
  Future<List<ProductModel>> _fetchAndCache({
    required bool includeInactive,
    String? categoryId,
    bool isManualRefresh = false,
  }) async {
    final requestKey = 'includeInactive_$includeInactive';

    // If an identical fetch is already in flight, await it instead of firing another network query
    if (_inFlightRequests.containsKey(requestKey)) {
      debugPrint('[PRODUCT] Joining active in-flight request ($requestKey)');
      await _inFlightRequests[requestKey]!;
      return _cache.getProducts(includeInactive: includeInactive, categoryId: categoryId);
    }

    final future = _executeFetch(includeInactive: includeInactive, isManualRefresh: isManualRefresh);
    _inFlightRequests[requestKey] = future;

    try {
      final products = await future;
      _cache.setProducts(products);
      if (isManualRefresh) {
        debugPrint('[PRODUCT] manual refresh SUCCESS (count: ${products.length})');
      } else {
        debugPrint('[PRODUCT] fetch SUCCESS (count: ${products.length})');
      }
      return _cache.getProducts(includeInactive: includeInactive, categoryId: categoryId);
    } catch (e) {
      debugPrint('[PRODUCT] fetch FAILED: $e');
      rethrow;
    } finally {
      _inFlightRequests.remove(requestKey);
    }
  }

  Future<List<ProductModel>> _executeFetch({
    required bool includeInactive,
    required bool isManualRefresh,
  }) async {
    // Bounded fetch: max 500 products (plenty for grocery catalog, safe on memory & reads)
    return await _firestore.fetchProducts(
      includeInactive: includeInactive,
      limit: 500,
    );
  }
}
