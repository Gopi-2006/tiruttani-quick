import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:tiruttaniquick_customer/services/settings_provider.dart';
import 'package:tiruttaniquick_customer/services/service_area_provider.dart';
import 'package:tiruttaniquick_customer/services/onboarding_service.dart';
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
        categoryId: 'cat_cleaning',
        unit: '250 ml',
        stockQuantity: 10,
        lowStockThreshold: 2,
        isActive: true,
        sortOrder: 1,
        brand: 'Vim',
        description: 'Lemon power dishwash gel',
        tags: ['dishwash', 'cleaning', 'gel'],
        searchKeywords: ['bar', 'soap', 'cleaner'],
      ),
      const ProductModel(
        id: 'p2',
        name: 'Urad Dal',
        nameTamil: 'உளுந்தம் பருப்பு',
        imageUrl: 'https://example.com/urad.png',
        price: 120.0,
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
        categoryId: 'cat_dairy',
        unit: '500 ml',
        stockQuantity: 15,
        lowStockThreshold: 3,
        isActive: true,
        sortOrder: 3,
        brand: 'Amul',
        tags: ['dairy', 'milk'],
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
    ];

    test('Partial English name match "vim" finds VIM DRP DISHWASH GEL', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'vim',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p1');
    });

    test('Partial name match "urad" finds Urad Dal', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'urad',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p2');
    });

    test('Brand search "amul" finds Fresh Cow Milk', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'amul',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p3');
    });

    test('Tamil name search "உளுந்தம்" finds Urad Dal', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'உளுந்தம்',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p2');
    });

    test('Category term search "cleaning" matches products in Cleaning category', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'cleaning',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p1');
    });

    test('Multi-token search "vim gel" matches VIM DRP DISHWASH GEL', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'vim gel',
        categories: sampleCategories,
      );
      expect(results.length, 1);
      expect(results.first.id, 'p1');
    });

    test('Empty query returns unmodifiable copy of all products', () {
      final results = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: '  ',
        categories: sampleCategories,
      );
      expect(results.length, 3);
    });
  });

  group('ProductModel Tests', () {
    test('ProductModel.fromFirestore parses correct fields (standard map)', () {
      final data = {
        'productName': 'Fresh Milk',
        'imageUrl': 'https://example.com/milk.png',
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

    test('ProductModel.fromFirestore falls back to alternative fields', () {
      final data = {
        'name': 'Apple',
        'price': 1.8,
        'categoryId': 'fruits',
      };

      final product = ProductModel.fromFirestore('prod_2', data);

      expect(product.name, 'Apple');
      expect(product.price, 1.8);
      expect(product.categoryId, 'fruits');
      expect(product.stockQuantity, 0); // Defaults
      expect(product.isOutOfStock, true);
    });

    test('ProductModel.fromFirestore is robust with null values', () {
      final product = ProductModel.fromFirestore('prod_3', {});
      expect(product.name, 'Product');
      expect(product.price, 0.0);
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

    test('ProductModel.toMap serializes fields correctly', () {
      final product = ProductModel(
        id: '1', name: 'Fresh Milk', imageUrl: 'img', price: 2.5, categoryId: 'dairy', unit: '1L',
        stockQuantity: 10, lowStockThreshold: 3, isActive: true, sortOrder: 2, brand: 'Amul', mrp: 3.0,
      );

      final map = product.toMap();
      expect(map['productName'], 'Fresh Milk');
      expect(map['name'], 'Fresh Milk');
      expect(map['imageUrl'], 'img');
      expect(map['sellingPrice'], 2.5);
      expect(map['price'], 2.5);
      expect(map['category'], 'dairy');
      expect(map['categoryId'], 'dairy');
      expect(map['brand'], 'Amul');
      expect(map['mrp'], 3.0);
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
}
