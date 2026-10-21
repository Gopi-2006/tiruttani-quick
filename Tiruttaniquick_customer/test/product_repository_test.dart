import 'package:flutter_test/flutter_test.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

class MockFirestoreService extends FirestoreService {
  int fetchCallCount = 0;
  List<ProductModel> productsToReturn = [];

  @override
  Future<List<ProductModel>> fetchProducts({
    bool includeInactive = false,
    int limit = 200,
  }) async {
    fetchCallCount++;
    if (!includeInactive) {
      return productsToReturn.where((p) => p.isActive).toList();
    }
    return List.from(productsToReturn);
  }
}

void main() {
  group('ProductCache Tests', () {
    late ProductCache cache;

    final p1 = ProductModel(
      id: 'p1',
      name: 'Ponni Rice',
      imageUrl: 'https://example.com/rice.png',
      price: 60.0,
      categoryId: 'rice_cat',
      unit: '1 kg',
      stockQuantity: 10,
      lowStockThreshold: 5,
      sortOrder: 1,
      isActive: true,
    );

    final p2 = ProductModel(
      id: 'p2',
      name: 'Sunflower Oil',
      imageUrl: 'https://example.com/oil.png',
      price: 140.0,
      categoryId: 'oil_cat',
      unit: '1 L',
      stockQuantity: 5,
      lowStockThreshold: 2,
      sortOrder: 2,
      isActive: false,
    );

    setUp(() {
      cache = ProductCache();
    });

    test('Initial cache is empty', () {
      expect(cache.hasData, isFalse);
      expect(cache.getProducts(), isEmpty);
      expect(cache.getProductById('p1'), isNull);
    });

    test('setProducts populates cache and indexes by ID', () {
      cache.setProducts([p1, p2]);
      expect(cache.hasData, isTrue);
      expect(cache.getProducts(includeInactive: true).length, 2);
      expect(cache.getProducts(includeInactive: false).length, 1);
      expect(cache.getProductById('p1')?.name, 'Ponni Rice');
      expect(cache.getProductById('p2')?.name, 'Sunflower Oil');
    });

    test('Category filter returns correct items from cache', () {
      cache.setProducts([p1, p2]);
      final riceProducts = cache.getProducts(includeInactive: true, categoryId: 'rice_cat');
      expect(riceProducts.length, 1);
      expect(riceProducts.first.id, 'p1');

      final oilProducts = cache.getProducts(includeInactive: true, categoryId: 'oil_cat');
      expect(oilProducts.length, 1);
      expect(oilProducts.first.id, 'p2');
    });

    test('upsertProduct updates existing product or adds new', () {
      cache.setProducts([p1]);
      final updatedP1 = p1.copyWith(price: 65.0);
      cache.upsertProduct(updatedP1);

      expect(cache.getProductById('p1')?.price, 65.0);
      expect(cache.getProducts().length, 1);

      cache.upsertProduct(p2);
      expect(cache.getProductById('p2')?.id, 'p2');
      expect(cache.getProducts(includeInactive: true).length, 2);
    });

    test('removeProduct deletes from cache', () {
      cache.setProducts([p1, p2]);
      cache.removeProduct('p1');
      expect(cache.getProductById('p1'), isNull);
      expect(cache.getProducts(includeInactive: true).length, 1);
    });
  });

  group('ProductRepository Controlled Fetch & Caching Tests', () {
    late MockFirestoreService mockFirestore;
    late ProductRepository repository;

    final p1 = ProductModel(
      id: 'p1',
      name: 'Basmati Rice',
      imageUrl: 'https://example.com/basmati.png',
      price: 110.0,
      categoryId: 'rice_cat',
      unit: '1 kg',
      stockQuantity: 15,
      lowStockThreshold: 5,
      sortOrder: 1,
      isActive: true,
    );

    final p2 = ProductModel(
      id: 'p2',
      name: 'Toor Dal',
      imageUrl: 'https://example.com/dal.png',
      price: 130.0,
      categoryId: 'dal_cat',
      unit: '1 kg',
      stockQuantity: 20,
      lowStockThreshold: 5,
      sortOrder: 2,
      isActive: true,
    );

    setUp(() {
      mockFirestore = MockFirestoreService();
      mockFirestore.productsToReturn = [p1, p2];
      repository = ProductRepository(firestore: mockFirestore);
    });

    test('Initial load fetches from Firestore once and caches', () async {
      expect(mockFirestore.fetchCallCount, 0);

      final products = await repository.loadInitialProducts();
      expect(products.length, 2);
      expect(mockFirestore.fetchCallCount, 1);
      expect(repository.cache.hasData, isTrue);
    });

    test('Consecutive loadInitialProducts returns cached data with ZERO additional fetches', () async {
      await repository.loadInitialProducts();
      expect(mockFirestore.fetchCallCount, 1);

      // Call 2
      final secondCall = await repository.loadInitialProducts();
      expect(secondCall.length, 2);
      expect(mockFirestore.fetchCallCount, 1); // Remains 1, NO new fetch

      // Call 3
      final thirdCall = await repository.loadInitialProducts();
      expect(thirdCall.length, 2);
      expect(mockFirestore.fetchCallCount, 1); // Still 1!
    });

    test('Concurrent in-flight calls are deduplicated into single network fetch', () async {
      final results = await Future.wait([
        repository.loadInitialProducts(),
        repository.loadInitialProducts(),
        repository.loadInitialProducts(),
      ]);

      expect(mockFirestore.fetchCallCount, 1); // Exactly 1 fetch
      expect(results[0].length, 2);
      expect(results[1].length, 2);
      expect(results[2].length, 2);
    });

    test('refreshProducts performs explicit network fetch and updates cache', () async {
      await repository.loadInitialProducts();
      expect(mockFirestore.fetchCallCount, 1);

      // Add a third product to mock backend
      final p3 = ProductModel(
        id: 'p3',
        name: 'Refined Sugar',
        imageUrl: 'https://example.com/sugar.png',
        price: 45.0,
        categoryId: 'sugar_cat',
        unit: '1 kg',
        stockQuantity: 30,
        lowStockThreshold: 5,
        sortOrder: 3,
        isActive: true,
      );
      mockFirestore.productsToReturn = [p1, p2, p3];

      // Explicit manual refresh
      final refreshed = await repository.refreshProducts();
      expect(mockFirestore.fetchCallCount, 2); // Exactly 2 now
      expect(refreshed.length, 3);
      expect(repository.getCachedProductById('p3')?.name, 'Refined Sugar');
    });

    test('getCachedProducts and getCachedProductById perform 0 network fetches', () async {
      await repository.loadInitialProducts();
      expect(mockFirestore.fetchCallCount, 1);

      final cachedList = repository.getCachedProducts();
      expect(cachedList.length, 2);

      final cachedItem = repository.getCachedProductById('p1');
      expect(cachedItem?.name, 'Basmati Rice');

      // Still only 1 network fetch
      expect(mockFirestore.fetchCallCount, 1);
    });
  });
}
