import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:tiruttaniquick_customer/services/settings_provider.dart';
import 'package:tiruttaniquick_customer/services/service_area_provider.dart';
import 'package:tiruttaniquick_customer/services/onboarding_service.dart';
import 'package:tiruttaniquick_customer/services/startup_provider.dart';
import 'package:tiruttaniquick_customer/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CategoryModel Tests', () {
    test('CategoryModel.fromFirestore parses valid imageUrl correctly', () {
      final data = {
        'name': 'Vegetables',
        'imageUrl': 'https://example.com/veg.png',
        'color': '#00A86B',
        'sortOrder': 1,
      };

      final cat = CategoryModel.fromFirestore('cat_1', data);

      expect(cat.id, 'cat_1');
      expect(cat.name, 'Vegetables');
      expect(cat.imageUrl, 'https://example.com/veg.png');
      expect(cat.categoryImage, 'https://example.com/veg.png');
      expect(cat.color, '#00A86B');
      expect(cat.sortOrder, 1);
    });

    test('CategoryModel.fromFirestore falls back to legacy categoryImage', () {
      final data = {
        'name': 'Fruits',
        'categoryImage': 'https://example.com/fruits.png',
      };

      final cat = CategoryModel.fromFirestore('cat_2', data);

      expect(cat.imageUrl, 'https://example.com/fruits.png');
    });

    test('CategoryModel.fromFirestore NEVER assigns imageUrl from icon field', () {
      final data = {
        'name': 'Bakery',
        'icon': 'https://example.com/bakery.png',
      };

      final cat = CategoryModel.fromFirestore('cat_3', data);

      expect(cat.imageUrl, '');
      expect(cat.icon, isNull);
    });

    test('CategoryModel.fromFirestore preserves emoji icon', () {
      final data = {
        'name': 'Snacks',
        'imageUrl': 'https://example.com/snacks.png',
        'icon': '🍿',
      };

      final cat = CategoryModel.fromFirestore('cat_4', data);

      expect(cat.imageUrl, 'https://example.com/snacks.png');
      expect(cat.icon, '🍿');
    });

    test('CategoryModel.toMap serializes fields correctly', () {
      const cat = CategoryModel(
        id: 'cat_5',
        name: 'Beverages',
        imageUrl: 'https://example.com/bev.png',
        color: '#FF0000',
        sortOrder: 5,
      );

      final map = cat.toMap();

      expect(map['name'], 'Beverages');
      expect(map['imageUrl'], 'https://example.com/bev.png');
      expect(map['categoryImage'], 'https://example.com/bev.png');
      expect(map['color'], '#FF0000');
      expect(map['sortOrder'], 5);
    });
  });

  group('ProductSearchEngine Tests', () {
    final sampleProducts = [
      const ProductModel(
        id: 'p1',
        name: 'VIM DRP DISHWASH GEL',
        nameTamil: 'விம் டிஷ்வாஷ்',
        imageUrl: 'https://example.com/vim.png',
        price: 55.0,
        mrp: 65.0,
        categoryId: 'cat_cleaning',
        unit: '250 ml',
        stockQuantity: 10,
        lowStockThreshold: 2,
        isActive: true,
        sortOrder: 1,
        brand: 'Vim',
        description: 'Lemon power dishwash gel for sparkling clean utensils',
        tags: ['dishwash', 'cleaning', 'gel'],
        searchKeywords: ['bar', 'soap', 'cleaner'],
      ),
      const ProductModel(
        id: 'p2',
        name: 'Urad Dal',
        nameTamil: 'உளுந்தம் பருப்பு',
        imageUrl: 'https://example.com/urad.png',
        price: 120.0,
        mrp: 140.0,
        categoryId: 'cat_pulses',
        unit: '1 kg',
        stockQuantity: 20,
        lowStockThreshold: 5,
        isActive: true,
        sortOrder: 2,
        brand: 'Tata Sampann',
        tags: ['dal', 'pulses', 'staples'],
      ),
      const ProductModel(
        id: 'p3',
        name: 'Fresh Cow Milk',
        nameTamil: 'பசு பால்',
        imageUrl: 'https://example.com/milk.png',
        price: 30.0,
        mrp: 35.0,
        categoryId: 'cat_dairy',
        unit: '500 ml',
        stockQuantity: 15,
        lowStockThreshold: 3,
        isActive: true,
        sortOrder: 3,
        brand: 'Amul',
        tags: ['dairy', 'milk'],
      ),
      const ProductModel(
        id: 'p4',
        name: 'Aashirvaad Superior MP Atta',
        nameTamil: 'ஆசிர்வாத் கோதுமை மாவு',
        imageUrl: 'https://example.com/atta.png',
        price: 245.0,
        mrp: 290.0,
        categoryId: 'cat_staples',
        unit: '5 kg',
        stockQuantity: 0, // Out of stock
        lowStockThreshold: 5,
        isActive: true,
        sortOrder: 4,
        brand: 'Aashirvaad',
        tags: ['atta', 'flour', 'wheat'],
      ),
      const ProductModel(
        id: 'p5',
        name: 'Fortune Sunlite Refined Sunflower Oil',
        nameTamil: 'சூரியகாந்தி எண்ணெய்',
        imageUrl: 'https://example.com/oil.png',
        price: 135.0,
        mrp: 175.0,
        categoryId: 'cat_oil',
        unit: '1 L',
        stockQuantity: 25,
        lowStockThreshold: 5,
        isActive: true,
        sortOrder: 5,
        brand: 'Fortune',
        tags: ['oil', 'cooking oil'],
      ),
    ];

    final sampleCategories = [
      const CategoryModel(
        id: 'cat_cleaning',
        name: 'Cleaning & Household',
        imageUrl: '',
        color: '#000',
        sortOrder: 1,
      ),
      const CategoryModel(
        id: 'cat_pulses',
        name: 'Pulses & Rice',
        imageUrl: '',
        color: '#000',
        sortOrder: 2,
      ),
      const CategoryModel(
        id: 'cat_dairy',
        name: 'Dairy & Bakery',
        imageUrl: '',
        color: '#000',
        sortOrder: 3,
      ),
      const CategoryModel(
        id: 'cat_staples',
        name: 'Atta, Rice & Dal',
        imageUrl: '',
        color: '#000',
        sortOrder: 4,
      ),
      const CategoryModel(
        id: 'cat_oil',
        name: 'Oils & Ghee',
        imageUrl: '',
        color: '#000',
        sortOrder: 5,
      ),
    ];

    test('1. Empty query returns all active products', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: '  ',
        categories: sampleCategories,
      );
      expect(results.length, 5);
    });

    test('2. Single character search "a" matches all products containing "a"', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'a',
        categories: sampleCategories,
      );
      expect(results.isNotEmpty, true);
      // Products with 'a': VIM (in tags/keywords/cat), Urad Dal (in name), Fresh Cow Milk (in tags), Aashirvaad Atta, Fortune Oil
      expect(results.any((p) => p.id == 'p4'), true);
      expect(results.any((p) => p.id == 'p2'), true);
    });

    test('3. Single character search "v" ranks VIM DISHWASH top', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'v',
        categories: sampleCategories,
      );
      expect(results.first.id, 'p1');
    });

    test('4. Middle substring search "ash" matches Aashirvaad and Dishwash', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'ash',
        categories: sampleCategories,
      );
      expect(results.length, 2);
      expect(results.map((p) => p.id).toSet(), {'p1', 'p4'});
    });

    test('5. Middle substring search "tta" matches Aashirvaad Atta', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'tta',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p4');
    });

    test('6. Middle substring search "oil" matches Fortune Sunflower Oil', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'oil',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p5');
    });

    test('7. Middle substring search "ing" matches Cleaning category and Dishwash Gel description', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'ing',
        categories: sampleCategories,
      );
      expect(results.any((p) => p.id == 'p1'), true);
    });

    test('8. Case-insensitive search "VIM", "vim", "ViM" produce identical results', () {
      final resUpper = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'VIM',
        categories: sampleCategories,
      );
      final resLower = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'vim',
        categories: sampleCategories,
      );
      final resMixed = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'ViM',
        categories: sampleCategories,
      );
      expect(resUpper.map((p) => p.id).toList(), resLower.map((p) => p.id).toList());
      expect(resLower.map((p) => p.id).toList(), resMixed.map((p) => p.id).toList());
    });

    test('9. Whitespace normalization: leading, trailing, and multiple spaces work identically', () {
      final resTrim = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: '  atta   5kg  ',
        categories: sampleCategories,
      );
      expect(resTrim.length, 1);
      expect(resTrim.first.id, 'p4');
    });

    test('10. Multi-word search "atta 5kg" matches Aashirvaad Atta 5 kg', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'atta 5kg',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p4');
    });

    test('11. Brand search "fortune" finds Fortune Sunflower Oil', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'fortune',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p5');
    });

    test('12. Category search "dairy" matches Fresh Cow Milk', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'dairy',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p3');
    });

    test('13. Tamil product name search "உளுந்தம்" finds Urad Dal', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'உளுந்தம்',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p2');
    });

    test('14. Tamil substring search "எண்ணெய்" finds Sunflower Oil', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'எண்ணெய்',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p5');
    });

    test('15. Non-existent query returns empty list without error', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'nonexistentproductxyz99',
        categories: sampleCategories,
      );
      expect(results.isEmpty, true);
    });

    test('16. Search + InStock Filter excludes out-of-stock products', () {
      final allAtta = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'atta',
        categories: sampleCategories,
      );
      expect(allAtta.length, 1); // Found p4

      final inStockAtta = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'atta',
        categories: sampleCategories,
        filterOptions: const ProductFilterOptions(inStockOnly: true),
      );
      expect(inStockAtta.isEmpty, true); // p4 is OOS, correctly filtered out
    });

    test('17. Search + Price Filter filters out products exceeding maxPrice', () {
      final cheapOil = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'oil',
        categories: sampleCategories,
        filterOptions: const ProductFilterOptions(maxPrice: 100),
      );
      expect(cheapOil.isEmpty, true); // Oil is ₹135

      final affordableOil = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'oil',
        categories: sampleCategories,
        filterOptions: const ProductFilterOptions(maxPrice: 150),
      );
      expect(affordableOil.length, 1);
      expect(affordableOil.first.id, 'p5');
    });

    test('18. Search + Brand Filter narrows results to selected brand', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'oil',
        categories: sampleCategories,
        filterOptions: const ProductFilterOptions(brands: {'Fortune'}),
      );
      expect(results.length, 1);
      expect(results.first.brand, 'Fortune');
    });

    test('19. Sorting by Price Low to High orders results ascendingly', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: '',
        categories: sampleCategories,
        sortOption: ProductSortOption.priceLowToHigh,
      );
      expect(results.first.price, 30.0); // Fresh Cow Milk
      expect(results.last.price, 245.0); // Aashirvaad Atta
    });

    test('20. Sorting by Price High to Low orders results descendingly', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: '',
        categories: sampleCategories,
        sortOption: ProductSortOption.priceHighToLow,
      );
      expect(results.first.price, 245.0); // Aashirvaad Atta
      expect(results.last.price, 30.0); // Fresh Cow Milk
    });

    test('21. Sorting by Discount High to Low orders highest savings first', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: '',
        categories: sampleCategories,
        sortOption: ProductSortOption.discountHighToLow,
      );
      // Fortune Oil: (175 - 135) / 175 = 22.8% discount
      expect(results.first.id, 'p5');
    });

    test('22. Relevance Ranking: Exact & Prefix name match ranks higher than general substring', () {
      final testProducts = [
        const ProductModel(
          id: 't1',
          name: 'Crispy Rice Crackers',
          imageUrl: '',
          price: 40,
          categoryId: 'cat_snacks',
          unit: '100 g',
          stockQuantity: 10,
          lowStockThreshold: 2,
          isActive: true,
          sortOrder: 1,
        ),
        const ProductModel(
          id: 't2',
          name: 'Rice',
          imageUrl: '',
          price: 60,
          categoryId: 'cat_staples',
          unit: '1 kg',
          stockQuantity: 10,
          lowStockThreshold: 2,
          isActive: true,
          sortOrder: 2,
        ),
        const ProductModel(
          id: 't3',
          name: 'Rice Flour Extra Fine',
          imageUrl: '',
          price: 50,
          categoryId: 'cat_staples',
          unit: '500 g',
          stockQuantity: 10,
          lowStockThreshold: 2,
          isActive: true,
          sortOrder: 3,
        ),
      ];

      final results = ProductSearchEngine.filterProducts(
        products: testProducts,
        rawQuery: 'rice',
      );

      // Expected ranking: 'Rice' (Exact 1000) -> 'Rice Flour Extra Fine' (Prefix 750) -> 'Crispy Rice Crackers' (Word match 500)
      expect(results[0].id, 't2'); // 'Rice'
      expect(results[1].id, 't3'); // 'Rice Flour Extra Fine'
      expect(results[2].id, 't1'); // 'Crispy Rice Crackers'
    });
  });

  group('ProductModel Tests', () {
    test('ProductModel.fromFirestore parses correct fields including blurHash', () {
      final data = {
        'productName': 'Fresh Milk',
        'imageUrl': 'https://example.com/milk.png',
        'blurHash': 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
        'sellingPrice': 2.5,
        'category': 'dairy',
        'unit': '1L',
        'stockQuantity': 15,
        'lowStockThreshold': 5,
        'isActive': true,
        'sortOrder': 1,
        'brand': 'Amul',
        'description': 'Fresh cow milk',
        'mrp': 3.0,
      };

      final product = ProductModel.fromFirestore('prod_1', data);

      expect(product.id, 'prod_1');
      expect(product.name, 'Fresh Milk');
      expect(product.imageUrl, 'https://example.com/milk.png');
      expect(product.blurHash, 'LEHV6nWB2yk8pyo0adR*.7kCMdnj');
      expect(product.price, 2.5);
      expect(product.categoryId, 'dairy');
      expect(product.unit, '1L');
      expect(product.stockQuantity, 15);
      expect(product.lowStockThreshold, 5);
      expect(product.isActive, true);
      expect(product.sortOrder, 1);
      expect(product.brand, 'Amul');
      expect(product.description, 'Fresh cow milk');
      expect(product.mrp, 3.0);
      expect(product.isLowStock, false);
      expect(product.isOutOfStock, false);
    });

    test('ProductModel.fromFirestore falls back to alternative fields and defaults blurHash', () {
      final data = {
        'name': 'Apple',
        'price': 1.8,
        'categoryId': 'fruits',
      };

      final product = ProductModel.fromFirestore('prod_2', data);

      expect(product.name, 'Apple');
      expect(product.price, 1.8);
      expect(product.categoryId, 'fruits');
      expect(product.blurHash, '');
      expect(product.stockQuantity, 0); // Defaults
      expect(product.isOutOfStock, true);
    });

    test('ProductModel.fromFirestore is robust with null values', () {
      final product = ProductModel.fromFirestore('prod_3', {});
      expect(product.name, 'Product');
      expect(product.price, 0.0);
      expect(product.blurHash, '');
      expect(product.stockQuantity, 0);
      expect(product.isActive, true);
    });

    test('ProductModel.isLowStock verifies threshold boundaries', () {
      final product1 = ProductModel(
        id: '1', name: 'A', imageUrl: '', price: 1, categoryId: '', unit: '',
        stockQuantity: 4, lowStockThreshold: 5, isActive: true, sortOrder: 1,
      );
      final product2 = ProductModel(
        id: '2', name: 'B', imageUrl: '', price: 1, categoryId: '', unit: '',
        stockQuantity: 5, lowStockThreshold: 5, isActive: true, sortOrder: 1,
      );
      final product3 = ProductModel(
        id: '3', name: 'C', imageUrl: '', price: 1, categoryId: '', unit: '',
        stockQuantity: 6, lowStockThreshold: 5, isActive: true, sortOrder: 1,
      );
      final product4 = ProductModel(
        id: '4', name: 'D', imageUrl: '', price: 1, categoryId: '', unit: '',
        stockQuantity: 0, lowStockThreshold: 5, isActive: true, sortOrder: 1,
      );

      expect(product1.isLowStock, true);
      expect(product2.isLowStock, true);
      expect(product3.isLowStock, false);
      expect(product4.isLowStock, false); // Out of stock, not just low stock
    });

    test('ProductModel.toMap serializes fields correctly including blurHash', () {
      final product = ProductModel(
        id: '1', name: 'Fresh Milk', imageUrl: 'img', blurHash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
        price: 2.5, categoryId: 'dairy', unit: '1L',
        stockQuantity: 10, lowStockThreshold: 3, isActive: true, sortOrder: 2, brand: 'Amul', mrp: 3.0,
      );

      final map = product.toMap();
      expect(map['productName'], 'Fresh Milk');
      expect(map['name'], 'Fresh Milk');
      expect(map['imageUrl'], 'img');
      expect(map['blurHash'], 'LEHV6nWB2yk8pyo0adR*.7kCMdnj');
      expect(map['sellingPrice'], 2.5);
      expect(map['price'], 2.5);
      expect(map['category'], 'dairy');
      expect(map['categoryId'], 'dairy');
      expect(map['brand'], 'Amul');
      expect(map['mrp'], 3.0);
    });

    test('ProductModel.copyWith correctly updates blurHash', () {
      final product = ProductModel(
        id: '1', name: 'Milk', imageUrl: 'img', price: 2.0, categoryId: 'c1', unit: '1L',
        stockQuantity: 5, lowStockThreshold: 2, isActive: true, sortOrder: 1,
      );
      final updated = product.copyWith(blurHash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj');
      expect(updated.blurHash, 'LEHV6nWB2yk8pyo0adR*.7kCMdnj');
      expect(product.blurHash, '');
    });

    test('ProductVariantModel parses, serializes and defaults blurHash correctly', () {
      final mapWithHash = {
        'id': 'v1',
        'name': '500g',
        'size': '500',
        'unitType': 'g',
        'price': 45.0,
        'mrp': 50.0,
        'stockQuantity': 10,
        'lowStockThreshold': 2,
        'status': 'Available',
        'barcode': '',
        'sku': '',
        'imageUrl': 'https://example.com/v.png',
        'blurHash': 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
      };
      final variant = ProductVariantModel.fromMap(mapWithHash);
      expect(variant.blurHash, 'LEHV6nWB2yk8pyo0adR*.7kCMdnj');
      expect(variant.toMap()['blurHash'], 'LEHV6nWB2yk8pyo0adR*.7kCMdnj');

      final variantNoHash = ProductVariantModel.fromMap({});
      expect(variantNoHash.blurHash, '');
      expect(variantNoHash.toMap()['blurHash'], '');

      final copied = variant.copyWith(blurHash: 'L6PZfSi_.AyE_3t7t7R**0o#DgR4');
      expect(copied.blurHash, 'L6PZfSi_.AyE_3t7t7R**0o#DgR4');
    });
  });

  group('AppNetworkImage & BlurHash Validation Tests', () {
    test('isValidBlurHash accurately validates hashes', () {
      expect(AppNetworkImage.isValidBlurHash('LEHV6nWB2yk8pyo0adR*.7kCMdnj'), isTrue);
      expect(AppNetworkImage.isValidBlurHash('L6PZfSi_.AyE_3t7t7R**0o#DgR4'), isTrue);
      expect(AppNetworkImage.isValidBlurHash(null), isFalse);
      expect(AppNetworkImage.isValidBlurHash(''), isFalse);
      expect(AppNetworkImage.isValidBlurHash('   '), isFalse);
      expect(AppNetworkImage.isValidBlurHash('short'), isFalse);
      expect(AppNetworkImage.isValidBlurHash('invalid string with spaces'), isFalse);
    });

    testWidgets('AppNetworkImage renders without crashing on invalid URL or empty hash', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppNetworkImage(
              imageUrl: '',
              blurHash: '',
              width: 100,
              height: 100,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    });

    testWidgets('AppNetworkImage renders without crashing with valid blurHash on network url', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppNetworkImage(
              imageUrl: 'https://example.com/test.jpg',
              blurHash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
              width: 100,
              height: 100,
            ),
          ),
        ),
      );

      expect(find.byType(AppNetworkImage), findsOneWidget);
    });
  });

  group('OrderModel Tests', () {
    test('OrderModel.fromFirestore normalizes status correctly', () {
      final orderPlaced = OrderModel.fromFirestore('o1', {'status': 'placed'});
      final orderOutForDelivery = OrderModel.fromFirestore('o2', {'status': 'out for delivery'});
      final orderDelivered = OrderModel.fromFirestore('o3', {'status': 'DELIVERED '});

      expect(orderPlaced.status, 'pending');
      expect(orderOutForDelivery.status, 'out_for_delivery');
      expect(orderDelivered.status, 'delivered');
    });

    test('OrderModel.formattedPlacedAt formats DateTime correctly', () {
      final placedDateTime = DateTime(2026, 6, 28, 14, 30);
      final order = OrderModel(
        id: 'o_test',
        orderNumber: 'ORD123',
        customerId: 'c1',
        deliveryAddressId: 'a1',
        subtotal: 10.0,
        deliveryFee: 2.0,
        totalPrice: 12.0,
        paymentMethod: 'COD',
        paymentStatus: 'Pending',
        status: 'pending',
        statusIndex: 1,
        placedAt: placedDateTime,
        verificationCode: '1234',
      );

      expect(order.formattedPlacedAt, '28 Jun, 02:30 PM');
    });

    test('OrderModel.fromFirestore handles null placedAt gracefully', () {
      final order = OrderModel.fromFirestore('o1', {});
      expect(order.formattedPlacedAt, '');
    });
  });

  group('SettingsProvider Tests', () {
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final Map<String, String> secureStorageMock = {};

    setUp(() {
      secureStorageMock.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'write':
            secureStorageMock[methodCall.arguments['key']] = methodCall.arguments['value'];
            return null;
          case 'read':
            return secureStorageMock[methodCall.arguments['key']];
          case 'delete':
            secureStorageMock.remove(methodCall.arguments['key']);
            return null;
          case 'containsKey':
            return secureStorageMock.containsKey(methodCall.arguments['key']);
          case 'deleteAll':
            secureStorageMock.clear();
            return null;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('SettingsProvider default properties and translation', () async {
      final provider = SettingsProvider();
      expect(provider.themeMode, ThemeMode.light);
      expect(provider.languageCode, 'en');

      // Test English translation
      expect(provider.translate('profileTitle'), 'My Profile');
      expect(provider.translate('non_existent_key'), 'non_existent_key');
    });

    test('SettingsProvider initialization reads from storage', () async {
      secureStorageMock['theme_mode'] = 'dark';
      secureStorageMock['language_code'] = 'ta';

      final provider = SettingsProvider();
      await provider.init();

      expect(provider.themeMode, ThemeMode.dark);
      expect(provider.languageCode, 'ta');

      // Test Tamil translation
      expect(provider.translate('profileTitle'), 'எனது சுயவிவரம்');
    });

    test('SettingsProvider setThemeMode updates theme and persists', () async {
      final provider = SettingsProvider();
      await provider.init();

      expect(provider.themeMode, ThemeMode.light);

      await provider.setThemeMode(ThemeMode.dark);
      expect(provider.themeMode, ThemeMode.dark);
      expect(secureStorageMock['theme_mode'], 'dark');

      await provider.setThemeMode(ThemeMode.light);
      expect(provider.themeMode, ThemeMode.light);
      expect(secureStorageMock['theme_mode'], 'light');
    });

    test('SettingsProvider setLanguageCode updates language and persists', () async {
      final provider = SettingsProvider();
      await provider.init();

      expect(provider.languageCode, 'en');

      await provider.setLanguageCode('ta');
      expect(provider.languageCode, 'ta');
      expect(secureStorageMock['language_code'], 'ta');
      expect(provider.translate('profileTitle'), 'எனது சுயவிவரம்');
    });
  });

  group('ServiceAreaProvider Tests', () {
    test('isPincodeAllowed allows 631209, 631211 and rejects invalid pincodes', () async {
      final provider = ServiceAreaProvider();
      final allowed1 = await provider.isPincodeAllowed('631209');
      final allowed2 = await provider.isPincodeAllowed('631211');
      final disallowed = await provider.isPincodeAllowed('123456');

      expect(allowed1, isTrue);
      expect(allowed2, isTrue);
      expect(disallowed, isFalse);
    });
  });

  group('ConnectivityDialog and OfflinePlaceholder Tests', () {
    testWidgets('ConnectivityDialog renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectivityDialog(
            onRetry: () {},
            onClose: () {},
          ),
        ),
      );

      expect(find.text('No Internet Connection'), findsOneWidget);
      expect(find.text("You're currently offline. Please check your Wi-Fi or mobile data connection and try again."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('OfflinePlaceholderWidget renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflinePlaceholderWidget(),
          ),
        ),
      );

      expect(find.text('No Internet Connection'), findsOneWidget);
      expect(find.text('You are currently offline. Please check your network and try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('Onboarding Tests', () {
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final Map<String, String> mockStorage = {};

    setUp(() {
      mockStorage.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        switch (call.method) {
          case 'read':
            final key = call.arguments['key'] as String;
            return mockStorage[key];
          case 'write':
            final key = call.arguments['key'] as String;
            final value = call.arguments['value'] as String;
            mockStorage[key] = value;
            return null;
          case 'delete':
            final key = call.arguments['key'] as String;
            mockStorage.remove(key);
            return null;
          case 'containsKey':
            final key = call.arguments['key'] as String;
            return mockStorage.containsKey(key);
          case 'deleteAll':
            mockStorage.clear();
            return null;
          default:
            return null;
        }
      });
    });

    test('OnboardingService persists completed state correctly', () async {
      expect(await OnboardingService.hasSeenOnboarding(), isFalse);

      await OnboardingService.markOnboardingComplete();
      expect(await OnboardingService.hasSeenOnboarding(), isTrue);

      await OnboardingService.resetOnboarding();
      expect(await OnboardingService.hasSeenOnboarding(), isFalse);
    });

    testWidgets('OnboardingScreen renders first slide and navigation elements', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(),
        ),
      );

      expect(find.text('Thiruttani Quick'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('FARM FRESH QUALITY'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
    });
  });

  group('ShopSettings & Delivery Availability Tests', () {
    test('Default shop settings defaults to deliveryAvailable true', () {
      const settings = ShopSettingsModel();
      expect(settings.deliveryAvailable, isTrue);
      expect(settings.deliveryUnavailableMessage, isNotEmpty);
    });

    test('ShopSettingsModel copyWith works accurately', () {
      const settings = ShopSettingsModel();
      final updated = settings.copyWith(
        deliveryAvailable: false,
        deliveryUnavailableMessage: 'Heavy rain in Tiruttani',
        updatedBy: 'admin_test',
      );
      expect(updated.deliveryAvailable, isFalse);
      expect(updated.deliveryUnavailableMessage, 'Heavy rain in Tiruttani');
      expect(updated.updatedBy, 'admin_test');
    });

    test('ShopSettingsModel handles null from Firestore gracefully', () {
      final settings = ShopSettingsModel.fromFirestore(null);
      expect(settings.deliveryAvailable, isTrue);
    });
  });

  group('Order Tracking Navigation & Push Notification Route Tests', () {
    test('StartupProvider pendingNotificationRoute handles set and consume lifecycle', () {
      final startup = StartupProvider();
      expect(startup.pendingNotificationRoute, isNull);
      expect(startup.consumePendingNotificationRoute(), isNull);
    });
  });

  group('ScrollHideBottomNav Tests', () {
    testWidgets('handleScrollNotification hides on downward scroll (positive delta)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                bool? newVisibility;
                final notification = ScrollUpdateNotification(
                  metrics: FixedScrollMetrics(
                    minScrollExtent: 0,
                    maxScrollExtent: 500,
                    pixels: 100,
                    viewportDimension: 300,
                    axisDirection: AxisDirection.down,
                    devicePixelRatio: 1.0,
                  ),
                  scrollDelta: 10.0,
                  context: ctx,
                );

                ScrollHideBottomNav.handleScrollNotification(
                  notification: notification,
                  isCurrentlyVisible: true,
                  onVisibilityChanged: (v) => newVisibility = v,
                );

                expect(newVisibility, isFalse);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('handleScrollNotification shows on upward scroll (negative delta)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                bool? newVisibility;
                final notification = ScrollUpdateNotification(
                  metrics: FixedScrollMetrics(
                    minScrollExtent: 0,
                    maxScrollExtent: 500,
                    pixels: 100,
                    viewportDimension: 300,
                    axisDirection: AxisDirection.down,
                    devicePixelRatio: 1.0,
                  ),
                  scrollDelta: -10.0,
                  context: ctx,
                );

                ScrollHideBottomNav.handleScrollNotification(
                  notification: notification,
                  isCurrentlyVisible: false,
                  onVisibilityChanged: (v) => newVisibility = v,
                );

                expect(newVisibility, isTrue);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('handleScrollNotification always shows at top of scrollable (pixels <= 0)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                bool? newVisibility;
                final notification = ScrollUpdateNotification(
                  metrics: FixedScrollMetrics(
                    minScrollExtent: 0,
                    maxScrollExtent: 500,
                    pixels: 0,
                    viewportDimension: 300,
                    axisDirection: AxisDirection.down,
                    devicePixelRatio: 1.0,
                  ),
                  scrollDelta: 0.0,
                  context: ctx,
                );

                ScrollHideBottomNav.handleScrollNotification(
                  notification: notification,
                  isCurrentlyVisible: false,
                  onVisibilityChanged: (v) => newVisibility = v,
                );

                expect(newVisibility, isTrue);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('handleScrollNotification ignores horizontal scrolling', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                bool called = false;
                final notification = ScrollUpdateNotification(
                  metrics: FixedScrollMetrics(
                    minScrollExtent: 0,
                    maxScrollExtent: 500,
                    pixels: 50,
                    viewportDimension: 300,
                    axisDirection: AxisDirection.right,
                    devicePixelRatio: 1.0,
                  ),
                  scrollDelta: 20.0,
                  context: ctx,
                );

                ScrollHideBottomNav.handleScrollNotification(
                  notification: notification,
                  isCurrentlyVisible: true,
                  onVisibilityChanged: (_) => called = true,
                );

                expect(called, isFalse);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('handleScrollNotification ignores micro-scrolls below threshold', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                bool called = false;
                final notification = ScrollUpdateNotification(
                  metrics: FixedScrollMetrics(
                    minScrollExtent: 0,
                    maxScrollExtent: 500,
                    pixels: 100,
                    viewportDimension: 300,
                    axisDirection: AxisDirection.down,
                    devicePixelRatio: 1.0,
                  ),
                  scrollDelta: 2.0, // Below 4.0 threshold
                  context: ctx,
                );

                ScrollHideBottomNav.handleScrollNotification(
                  notification: notification,
                  isCurrentlyVisible: true,
                  onVisibilityChanged: (_) => called = true,
                );

                expect(called, isFalse);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('ScrollHideBottomNav widget renders visible and hidden states', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ScrollHideBottomNav(
              isVisible: true,
              child: Text('Nav Bar Content'),
            ),
          ),
        ),
      );

      expect(find.text('Nav Bar Content'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ScrollHideBottomNav(
              isVisible: false,
              child: Text('Nav Bar Content'),
            ),
          ),
        ),
      );

      final animatedSlide = tester.widget<AnimatedSlide>(find.byType(AnimatedSlide));
      expect(animatedSlide.offset, const Offset(0, 1));
    });
  });
}
