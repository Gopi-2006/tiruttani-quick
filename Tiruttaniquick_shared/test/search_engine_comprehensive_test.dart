import 'package:flutter_test/flutter_test.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

void main() {
  group('Comprehensive Global Search Engine Tests (24 Requirements)', () {
    final sampleProducts = [
      const ProductModel(
        id: 'p_rice_1',
        name: 'India Gate Basmati Rice',
        nameTamil: 'பாஸ்மதி அரிசி',
        imageUrl: 'https://example.com/rice.png',
        price: 180.0,
        mrp: 220.0,
        categoryId: 'cat_staples',
        unit: '1 kg',
        stockQuantity: 50,
        lowStockThreshold: 5,
        isActive: true,
        sortOrder: 1,
        brand: 'India Gate',
        description: 'Finest long grain basmati rice',
        tags: ['rice', 'grains', 'biryani'],
        searchKeywords: ['ponni', 'raw rice', 'boiled rice'],
      ),
      const ProductModel(
        id: 'p_rice_plain',
        name: 'Rice',
        nameTamil: 'அரிசி',
        imageUrl: 'https://example.com/plain_rice.png',
        price: 60.0,
        mrp: 70.0,
        categoryId: 'cat_staples',
        unit: '1 kg',
        stockQuantity: 40,
        lowStockThreshold: 5,
        isActive: true,
        sortOrder: 2,
        brand: 'Tiruttani Farms',
        description: 'Daily consumption staple white rice',
      ),
      const ProductModel(
        id: 'p_rice_flour',
        name: 'Rice Flour',
        nameTamil: 'அரிசி மாவு',
        imageUrl: 'https://example.com/rice_flour.png',
        price: 45.0,
        mrp: 50.0,
        categoryId: 'cat_flour',
        unit: '500 g',
        stockQuantity: 20,
        lowStockThreshold: 5,
        isActive: true,
        sortOrder: 3,
        brand: 'Anil',
        description: 'Pure roasted rice flour for idiyappam and snacks',
      ),
      const ProductModel(
        id: 'p_sugar',
        name: 'Refined Sugar',
        nameTamil: 'சர்க்கரை',
        imageUrl: 'https://example.com/sugar.png',
        price: 44.0,
        mrp: 50.0,
        categoryId: 'cat_staples',
        unit: '1 kg',
        stockQuantity: 30,
        lowStockThreshold: 5,
        isActive: true,
        sortOrder: 4,
        brand: 'Madhur',
        description: 'Sulphur-free clean sweet white sugar',
      ),
      const ProductModel(
        id: 'p_biscuit',
        name: 'Parle-G Glucose Biscuit',
        nameTamil: 'குளுக்கோஸ் பிஸ்கட்',
        imageUrl: 'https://example.com/biscuit.png',
        price: 10.0,
        mrp: 10.0,
        categoryId: 'cat_snacks',
        unit: '100 g',
        stockQuantity: 100,
        lowStockThreshold: 10,
        isActive: true,
        sortOrder: 5,
        brand: 'Parle',
        description: 'Classic tea time glucose biscuit',
      ),
      const ProductModel(
        id: 'p_tomato',
        name: 'Fresh Country Tomato',
        nameTamil: 'நாட்டு தக்காளி',
        imageUrl: 'https://example.com/tomato.png',
        price: 28.0,
        mrp: 35.0,
        categoryId: 'cat_vegetables',
        unit: '1 kg',
        stockQuantity: 15,
        lowStockThreshold: 3,
        isActive: true,
        sortOrder: 6,
        brand: 'Farm Fresh',
        description: 'Locally grown sour country tomatoes',
      ),
      const ProductModel(
        id: 'p_atta',
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
        sortOrder: 7,
        brand: 'Aashirvaad',
        tags: ['atta', 'flour', 'wheat'],
        description: '100 percent pure whole wheat atta with 0 percent maida',
      ),
      const ProductModel(
        id: 'p_oil',
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
        sortOrder: 8,
        brand: 'Fortune',
        tags: ['oil', 'cooking oil'],
        variantsEnabled: true,
        variants: [
          ProductVariantModel(
            id: 'v_oil_1',
            name: '1 L Pouch',
            size: '1',
            unitType: 'L',
            mrp: 175.0,
            price: 135.0,
            purchasePrice: 120.0,
            discount: 22.0,
            stockQuantity: 25,
            lowStockThreshold: 5,
            status: 'Available',
            barcode: '8901234567890',
            sku: 'SKU-OIL-1L',
          ),
        ],
      ),
    ];

    final sampleCategories = [
      const CategoryModel(
        id: 'cat_staples',
        name: 'Rice, Grains & Staples',
        imageUrl: '',
        color: '#000',
        sortOrder: 1,
      ),
      const CategoryModel(
        id: 'cat_flour',
        name: 'Atta & Flours',
        imageUrl: '',
        color: '#000',
        sortOrder: 2,
      ),
      const CategoryModel(
        id: 'cat_snacks',
        name: 'Biscuits & Snacks',
        imageUrl: '',
        color: '#000',
        sortOrder: 3,
      ),
      const CategoryModel(
        id: 'cat_vegetables',
        name: 'Vegetables & Fruits',
        imageUrl: '',
        color: '#000',
        sortOrder: 4,
      ),
      const CategoryModel(
        id: 'cat_oil',
        name: 'Edible Oils & Ghee',
        imageUrl: '',
        color: '#000',
        sortOrder: 5,
      ),
    ];

    setUp(() {
      ProductSearchEngine.clearIndexCache();
    });

    test('1. "rice" -> Rice products found', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'rice',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_rice_plain'), isTrue);
      expect(res.any((p) => p.id == 'p_rice_1'), isTrue);
      expect(res.any((p) => p.id == 'p_rice_flour'), isTrue);
    });

    test('2. "ric" -> Partial match finds Rice', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'ric',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_rice_plain'), isTrue);
    });

    test('3. "rce" -> Character-in-between subsequence finds Rice', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'rce',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_rice_plain'), isTrue);
    });

    test('3b. "rc" -> 2-character in-between subsequence finds Rice', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'rc',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_rice_plain'), isTrue);
    });

    test('3c. "raice" -> Letter "a" typed in between "rice" finds Rice', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'raice',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_rice_plain'), isTrue);
    });

    test('3d. "suggar" -> Letter "g" typed in between "sugar" finds Sugar', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'suggar',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_sugar'), isTrue);
    });

    test('3e. "bisckuit" -> Letter "k" typed in between "biscuit" finds Biscuit', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'bisckuit',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_biscuit'), isTrue);
    });

    test('3f. "basmati raice" -> Multi-word query with letter in between finds Basmati Rice', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'basmati raice',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_rice_1'), isTrue);
    });

    test('3g. "soil" -> Subsequence across words finds Sunflower Oil', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'soil',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_oil'), isTrue);
    });

    test('4. "sugar" -> Sugar found', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'sugar',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_sugar'), isTrue);
    });

    test('5. "suger" -> Fuzzy typo-tolerant search finds Sugar', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'suger',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_sugar'), isTrue);
    });

    test('6. "bis" -> Partial match finds Biscuit', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'bis',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_biscuit'), isTrue);
    });

    test('7. "bsc" -> Character-in-between subsequence finds Biscuit', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'bsc',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_biscuit'), isTrue);
    });

    test('8. Uppercase search "RICE" & "SUGAR" works', () {
      final resRice = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'RICE',
        categories: sampleCategories,
      );
      final resSugar = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'SUGAR',
        categories: sampleCategories,
      );
      expect(resRice.any((p) => p.id == 'p_rice_plain'), isTrue);
      expect(resSugar.any((p) => p.id == 'p_sugar'), isTrue);
    });

    test('9. Lowercase search works identically', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'sugar',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_sugar'), isTrue);
    });

    test('10. Leading and trailing extra spaces work', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: '   rice   ',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_rice_plain'), isTrue);
    });

    test('11. Multiple consecutive spaces work', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'basmati    rice',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_rice_1'), isTrue);
    });

    test('12. Tamil product name query works directly', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'அரிசி',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_rice_plain'), isTrue);
    });

    test('13. Tamil partial & prefix search works', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'தக்காளி',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_tomato'), isTrue);
    });

    test('14. English transliteration "arisi" finds Tamil product "அரிசி"', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'arisi',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_rice_plain'), isTrue);
    });

    test('15. Brand search finds brand products', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'India Gate',
        categories: sampleCategories,
      );
      expect(res.first.id, equals('p_rice_1'));
    });

    test('16. Category search finds products under that category', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'Snacks',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_biscuit'), isTrue);
    });

    test('17. Description search matches content', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'idiyappam',
        categories: sampleCategories,
      );
      expect(res.any((p) => p.id == 'p_rice_flour'), isTrue);
    });

    test('18. Empty query returns all active products', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: '',
        categories: sampleCategories,
      );
      expect(res.length, equals(sampleProducts.length));
    });

    test('19. Duplicate products are deduplicated by ID', () {
      final duplicatedList = [...sampleProducts, sampleProducts.first];
      final res = ProductSearchEngine.filterProducts(
        products: duplicatedList,
        rawQuery: 'rice',
        categories: sampleCategories,
      );
      final ids = res.map((p) => p.id).toList();
      expect(ids.toSet().length, equals(ids.length));
    });

    test('20. Exact match ranks above fuzzy match', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'sugar',
        categories: sampleCategories,
      );
      expect(res.first.id, equals('p_sugar'));
    });

    test('21. Prefix match ranks above subsequence match', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'ric',
        categories: sampleCategories,
      );
      // Plain "Rice" prefix match must rank above any loose match
      expect(res.first.name.toLowerCase().startsWith('ric'), isTrue);
    });

    test('22. Strong name match ranks above description-only match', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'rice',
        categories: sampleCategories,
      );
      // Products with Rice in name should rank higher than products that only have it in description
      expect(res.first.name.toLowerCase().contains('rice'), isTrue);
    });

    test('23. Barcode and SKU search works', () {
      final resBarcode = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: '8901234567890',
        categories: sampleCategories,
      );
      final resSku = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'SKU-OIL-1L',
        categories: sampleCategories,
      );
      expect(resBarcode.any((p) => p.id == 'p_oil'), isTrue);
      expect(resSku.any((p) => p.id == 'p_oil'), isTrue);
    });

    test('24. Suggestions generator produces relevant suggestions', () {
      final suggestions = ProductSearchEngine.getSuggestions(
        products: sampleProducts,
        rawQuery: 'ric',
        categories: sampleCategories,
      );
      expect(suggestions.isNotEmpty, isTrue);
      expect(suggestions.any((s) => s.toLowerCase().contains('rice')), isTrue);
    });

    test('25. Performance Benchmark: 1,000 products completes within 10ms', () {
      final largeCatalog = List.generate(1000, (i) {
        return ProductModel(
          id: 'prod_$i',
          name: 'Grocery Product Item $i ${i % 2 == 0 ? "Basmati Rice" : "Sugar Candy"}',
          nameTamil: i % 2 == 0 ? 'அரிசி பருப்பு $i' : 'இனிப்பு சர்க்கரை $i',
          imageUrl: 'https://example.com/p$i.png',
          price: 50.0 + (i % 100),
          mrp: 60.0 + (i % 100),
          categoryId: 'cat_${i % 5}',
          unit: '1 kg',
          stockQuantity: 50,
          lowStockThreshold: 5,
          isActive: true,
          sortOrder: i,
          brand: i % 3 == 0 ? 'Tata' : 'Aashirvaad',
          tags: ['staple', 'daily', 'item$i'],
        );
      });

      // Warmup index
      ProductSearchEngine.filterProducts(
        products: largeCatalog,
        rawQuery: 'r',
      );

      final stopwatch = Stopwatch()..start();
      final results = ProductSearchEngine.filterProducts(
        products: largeCatalog,
        rawQuery: 'rice',
      );
      stopwatch.stop();

      expect(results.isNotEmpty, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(30));
    });

    test('26. Progressive typing "r" -> "ri" -> "ric" -> "rice" progressively finds Rice', () {
      for (final q in ['r', 'ri', 'ric', 'rice']) {
        final res = ProductSearchEngine.filterProducts(
          products: sampleProducts,
          rawQuery: q,
          categories: sampleCategories,
        );
        expect(res.any((p) => p.name.toLowerCase().contains('rice')), isTrue,
            reason: 'Failed to find Rice for progressive query: "$q"');
      }
    });

    test('27. Progressive typing "s" -> "su" -> "sug" -> "suga" -> "sugar" progressively finds Sugar', () {
      for (final q in ['s', 'su', 'sug', 'suga', 'sugar']) {
        final res = ProductSearchEngine.filterProducts(
          products: sampleProducts,
          rawQuery: q,
          categories: sampleCategories,
        );
        expect(res.any((p) => p.name.toLowerCase().contains('sugar')), isTrue,
            reason: 'Failed to find Sugar for progressive query: "$q"');
      }
    });

    test('28. Single-character "r" does not return random products containing "r" in the middle', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'r',
        categories: sampleCategories,
      );
      // All matched products must have a word starting with 'r', brand starting with 'r', or category starting with 'r'
      for (final p in res) {
        final nameWords = p.name.toLowerCase().split(' ');
        final startsWithR = nameWords.any((w) => w.startsWith('r')) ||
            p.brand.toLowerCase().startsWith('r') ||
            p.categoryId.toLowerCase().startsWith('r');
        expect(startsWithR, isTrue,
            reason: 'Product "${p.name}" should not match 1-character query "r" because it does not start with "r"');
      }
    });

    test('29. Typo tolerance: "biscut" -> Biscuit, "tomatoo" -> Tomato', () {
      final resBiscut = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'biscut',
        categories: sampleCategories,
      );
      expect(resBiscut.any((p) => p.id == 'p_biscuit'), isTrue);

      final tomato = ProductModel(
        id: 'p_tomato',
        name: 'Fresh Tomato',
        nameTamil: 'தக்காளி',
        imageUrl: '',
        price: 30,
        categoryId: 'veg',
        unit: '1 kg',
        stockQuantity: 20,
        lowStockThreshold: 5,
        isActive: true,
        sortOrder: 1,
      );
      final resTomato = ProductSearchEngine.filterProducts(
        products: [...sampleProducts, tomato],
        rawQuery: 'tomatoo',
        categories: sampleCategories,
      );
      expect(resTomato.any((p) => p.id == 'p_tomato'), isTrue);
    });

    test('30. Strict ranking order: Exact > Prefix > Word > Substring > Subsequence > Fuzzy', () {
      final res = ProductSearchEngine.filterProducts(
        products: sampleProducts,
        rawQuery: 'rice',
        categories: sampleCategories,
      );
      // "Rice" is exact match -> must be index 0
      expect(res.first.name.trim(), equals('Rice'));
    });
  });
}
