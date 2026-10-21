import '../models/product_model.dart';
import '../models/category_model.dart';

/// Available sorting options for product listings and search results.
enum ProductSortOption {
  relevance('Relevance'),
  priceLowToHigh('Price: Low to High'),
  priceHighToLow('Price: High to Low'),
  discountHighToLow('Discount: High to Low'),
  ratingHighToLow('Customer Rating'),
  newest('Newest Arrivals');

  final String label;
  const ProductSortOption(this.label);
}

/// Comprehensive filter options for product search and category browsing.
class ProductFilterOptions {
  final Set<String> categoryIds;
  final Set<String> brands;
  final double? minPrice;
  final double? maxPrice;
  final bool inStockOnly;
  final double? minRating;
  final int? minDiscount;
  final String? weight;

  const ProductFilterOptions({
    this.categoryIds = const {},
    this.brands = const {},
    this.minPrice,
    this.maxPrice,
    this.inStockOnly = false,
    this.minRating,
    this.minDiscount,
    this.weight,
  });

  bool get hasActiveFilters =>
      categoryIds.isNotEmpty ||
      brands.isNotEmpty ||
      minPrice != null ||
      maxPrice != null ||
      inStockOnly ||
      minRating != null ||
      minDiscount != null ||
      (weight != null && weight!.isNotEmpty);

  int get activeFilterCount {
    int count = 0;
    if (categoryIds.isNotEmpty) count += categoryIds.length;
    if (brands.isNotEmpty) count += brands.length;
    if (minPrice != null || maxPrice != null) count += 1;
    if (inStockOnly) count += 1;
    if (minRating != null) count += 1;
    if (minDiscount != null) count += 1;
    if (weight != null && weight!.isNotEmpty) count += 1;
    return count;
  }

  ProductFilterOptions copyWith({
    Set<String>? categoryIds,
    Set<String>? brands,
    double? minPrice,
    double? maxPrice,
    bool? inStockOnly,
    double? minRating,
    int? minDiscount,
    String? weight,
  }) {
    return ProductFilterOptions(
      categoryIds: categoryIds ?? this.categoryIds,
      brands: brands ?? this.brands,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      inStockOnly: inStockOnly ?? this.inStockOnly,
      minRating: minRating ?? this.minRating,
      minDiscount: minDiscount ?? this.minDiscount,
      weight: weight ?? this.weight,
    );
  }

  static const ProductFilterOptions empty = ProductFilterOptions();
}

/// Utility for normalizing text for query matching.
class SearchNormalizer {
  static final RegExp _multiSpaceRegex = RegExp(r'\s+');
  static final RegExp _punctuationRegex = RegExp(r'''[.,\/#!$%\^&\*;:{}=\-_`~()?'"\[\]<>|@+\\]''');

  /// Cleans query/product text: lowercases, converts punctuation to space,
  /// collapses whitespace, and trims.
  static String normalize(String input) {
    if (input.isEmpty) return '';
    final lower = input.toLowerCase();
    final noPunct = lower.replaceAll(_punctuationRegex, ' ');
    return noPunct.replaceAll(_multiSpaceRegex, ' ').trim();
  }

  /// Compact representation with all spaces and punctuation removed.
  /// Example: "Basmati Rice 5kg" -> "basmatirice5kg"
  static String compact(String input) {
    if (input.isEmpty) return '';
    final lower = input.toLowerCase();
    final noPunct = lower.replaceAll(_punctuationRegex, '');
    return noPunct.replaceAll(_multiSpaceRegex, '');
  }

  /// Splits normalized text into individual word tokens.
  static List<String> tokenize(String input) {
    final norm = normalize(input);
    if (norm.isEmpty) return const [];
    return norm.split(' ').where((t) => t.isNotEmpty).toList();
  }
}

/// Pre-indexed product entry for fast in-memory search across keystrokes.
class SearchIndexEntry {
  final ProductModel product;
  final String normName;
  final String compactName;
  final List<String> nameTokens;

  final String normNameTamil;
  final String compactNameTamil;
  final List<String> nameTamilTokens;

  final String normBrand;
  final String normCategory;
  final String normSubCategory;
  final String normDescription;
  final List<String> normKeywords;
  final List<String> normTags;
  final List<String> normVariantTexts;
  final List<String> barcodes;
  final List<String> skus;
  final Set<String> aliases;

  final bool isOutOfStock;

  SearchIndexEntry({
    required this.product,
    required this.normName,
    required this.compactName,
    required this.nameTokens,
    required this.normNameTamil,
    required this.compactNameTamil,
    required this.nameTamilTokens,
    required this.normBrand,
    required this.normCategory,
    required this.normSubCategory,
    required this.normDescription,
    required this.normKeywords,
    required this.normTags,
    required this.normVariantTexts,
    required this.barcodes,
    required this.skus,
    required this.aliases,
    required this.isOutOfStock,
  });

  factory SearchIndexEntry.fromProduct(ProductModel p, Map<String, String> categoryNames) {
    final normName = SearchNormalizer.normalize(p.name);
    final compactName = SearchNormalizer.compact(p.name);
    final nameTokens = SearchNormalizer.tokenize(p.name);

    final normNameTamil = SearchNormalizer.normalize(p.nameTamil);
    final compactNameTamil = SearchNormalizer.compact(p.nameTamil);
    final nameTamilTokens = SearchNormalizer.tokenize(p.nameTamil);

    final normBrand = SearchNormalizer.normalize(p.brand);
    final catName = categoryNames[p.categoryId.toLowerCase()] ?? p.categoryId;
    final normCategory = SearchNormalizer.normalize(catName);
    final normSubCategory = SearchNormalizer.normalize(p.subCategoryId);

    final normDescription = SearchNormalizer.normalize('${p.description} ${p.longDescription}');

    final normKeywords = p.searchKeywords.map(SearchNormalizer.normalize).where((k) => k.isNotEmpty).toList();
    final normTags = p.tags.map(SearchNormalizer.normalize).where((t) => t.isNotEmpty).toList();

    final List<String> normVariantTexts = [];
    final List<String> barcodes = [];
    final List<String> skus = [];

    if (p.id.trim().isNotEmpty) {
      skus.add(p.id.trim().toLowerCase());
      skus.add(SearchNormalizer.compact(p.id));
    }

    if (p.unit.isNotEmpty) {
      normVariantTexts.add(SearchNormalizer.normalize(p.unit));
    }

    bool hasAvailableVariant = false;
    for (final v in p.variants) {
      final vText = SearchNormalizer.normalize('${v.name} ${v.size} ${v.unitType}');
      if (vText.isNotEmpty) normVariantTexts.add(vText);
      if (v.barcode.trim().isNotEmpty) {
        barcodes.add(v.barcode.trim().toLowerCase());
        barcodes.add(SearchNormalizer.compact(v.barcode));
        barcodes.add(SearchNormalizer.normalize(v.barcode));
      }
      if (v.sku.trim().isNotEmpty) {
        skus.add(v.sku.trim().toLowerCase());
        skus.add(SearchNormalizer.compact(v.sku));
        skus.add(SearchNormalizer.normalize(v.sku));
      }
      if (!v.isOutOfStock) hasAvailableVariant = true;
    }

    final bool isStockOut = p.variantsEnabled && p.variants.isNotEmpty
        ? !hasAvailableVariant
        : p.isOutOfStock;

    // Build automated aliases based on Tamil and English grocery staples
    final Set<String> aliases = {};
    for (final token in nameTokens) {
      final found = ProductSearchEngine.getAliasesForToken(token);
      aliases.addAll(found);
    }
    for (final token in nameTamilTokens) {
      final found = ProductSearchEngine.getAliasesForToken(token);
      aliases.addAll(found);
    }

    return SearchIndexEntry(
      product: p,
      normName: normName,
      compactName: compactName,
      nameTokens: nameTokens,
      normNameTamil: normNameTamil,
      compactNameTamil: compactNameTamil,
      nameTamilTokens: nameTamilTokens,
      normBrand: normBrand,
      normCategory: normCategory,
      normSubCategory: normSubCategory,
      normDescription: normDescription,
      normKeywords: normKeywords,
      normTags: normTags,
      normVariantTexts: normVariantTexts,
      barcodes: barcodes,
      skus: skus,
      aliases: aliases,
      isOutOfStock: isStockOut,
    );
  }
}

/// High-performance grocery search engine with multi-field matching,
/// character-in-between subsequence search, typo tolerance, Tamil transliteration,
/// and relevance ranking.
class ProductSearchEngine {
  // Built-in grocery transliteration dictionary for Tamil Nadu grocery commerce.
  static final Map<String, List<String>> _tamilGroceryDictionary = {
    'arisi': ['அரிசி', 'rice'],
    'rice': ['அரிசி', 'arisi'],
    'paruppu': ['பருப்பு', 'dhal', 'dal', 'pulses'],
    'dal': ['பருப்பு', 'dhal', 'paruppu', 'pulses'],
    'dhal': ['பருப்பு', 'dal', 'paruppu', 'pulses'],
    'thakkali': ['தக்காளி', 'tomato'],
    'tomato': ['தக்காளி', 'thakkali'],
    'vengayam': ['வெங்காயம்', 'onion'],
    'onion': ['வெங்காயம்', 'vengayam'],
    'urulaikizhangu': ['உருளைக்கிழங்கு', 'potato', 'aloo'],
    'potato': ['உருளைக்கிழங்கு', 'urulaikizhangu', 'aloo'],
    'aloo': ['உருளைக்கிழங்கு', 'potato'],
    'ennai': ['எண்ணெய்', 'oil'],
    'oil': ['எண்ணெய்', 'ennai'],
    'uppu': ['உப்பு', 'salt'],
    'salt': ['உப்பு', 'uppu'],
    'sakkarai': ['சர்க்கரை', 'sugar', 'cheeni'],
    'sugar': ['சர்க்கரை', 'sakkarai', 'cheeni'],
    'cheeni': ['சர்க்கரை', 'sugar'],
    'paal': ['பால்', 'milk'],
    'milk': ['பால்', 'paal'],
    'thayir': ['தயிர்', 'curd', 'yogurt'],
    'curd': ['தயிர்', 'thayir', 'yogurt'],
    'nei': ['நெய்', 'ghee'],
    'ghee': ['நெய்', 'nei'],
    'muttai': ['முட்டை', 'egg', 'eggs'],
    'egg': ['முட்டை', 'muttai'],
    'eggs': ['முட்டை', 'muttai'],
    'maavu': ['மாவு', 'flour', 'atta'],
    'atta': ['மாவு', 'wheat', 'flour', 'maavu'],
    'flour': ['மாவு', 'atta', 'maavu'],
    'vendakkai': ['வெண்டைக்காய்', 'ladies finger', 'okra'],
    'okra': ['வெண்டைக்காய்', 'ladies finger', 'vendakkai'],
    'milagai': ['மிளகாய்', 'chilli', 'chili', 'pepper'],
    'chilli': ['மிளகாய்', 'milagai'],
    'chili': ['மிளகாய்', 'milagai'],
    'inji': ['இஞ்சி', 'ginger'],
    'ginger': ['இஞ்சி', 'inji'],
    'poondu': ['பூண்டு', 'garlic'],
    'garlic': ['பூண்டு', 'poondu'],
    'kadugu': ['கடுகு', 'mustard'],
    'mustard': ['கடுகு', 'kadugu'],
    'seeragam': ['சீரகம்', 'cumin', 'jeera'],
    'cumin': ['சீரகம்', 'seeragam', 'jeera'],
    'jeera': ['சீரகம்', 'cumin', 'seeragam'],
    'manjal': ['மஞ்சள்', 'turmeric'],
    'turmeric': ['மஞ்சள்', 'manjal'],
    'vendhayam': ['வெந்தயம்', 'fenugreek'],
    'fenugreek': ['வெந்தயம்', 'vendhayam'],
    'theel': ['தேநீர்', 'tea'],
    'tea': ['தேநீர்', 'theel'],
    'kaapi': ['காபி', 'coffee'],
    'coffee': ['காபி', 'kaapi'],
    'biscuit': ['பிஸ்கட்', 'biscuits', 'cookie', 'cookies'],
    'biscuits': ['பிஸ்கட்', 'biscuit'],
    'soap': ['சோப்', 'சோப்பு', 'sope', 'bar', 'detergent'],
    'sope': ['soap', 'soaps', 'soappu', 'சோப்', 'சோப்பு'],
    'soappu': ['சோப்', 'சோப்பு', 'soap', 'sope'],
    'shampoo': ['ஷாம்பு'],
    'detergent': ['டிடர்ஜென்ட்', 'washing powder', 'soap', 'rin', 'surf', 'tide', 'ariel'],
    'rin': ['rin refresh', 'detergent', 'detergent powder', 'washing powder'],
    'surf': ['surf excel', 'detergent', 'washing powder'],
    'ariel': ['detergent', 'washing powder'],
    'tide': ['detergent', 'washing powder'],
    'masala': ['மசாலா', 'spices'],
    'spices': ['மசாலா', 'masala'],
    // Nuts, Dry Fruits & Staples
    'badam': ['badham', 'almond', 'almonds', 'badaam', 'பாதாம்'],
    'badham': ['badam', 'almond', 'almonds', 'badaam', 'பாதாம்'],
    'almond': ['almonds', 'badam', 'badham', 'badaam', 'பாதாம்'],
    'almonds': ['almond', 'badam', 'badham', 'badaam', 'பாதாம்'],
    'cashew': ['cashews', 'kaju', 'mundhiri', 'முந்திரி'],
    'cashews': ['cashew', 'kaju', 'mundhiri', 'முந்திரி'],
    'kaju': ['cashew', 'cashews', 'mundhiri', 'முந்திரி'],
    'mundhiri': ['cashew', 'cashews', 'kaju', 'முந்திரி'],
    'pista': ['pistachio', 'pistachios', 'பிஸ்தா'],
    'pistachio': ['pista', 'pistachios', 'பிஸ்தா'],
    'pistachios': ['pista', 'pistachio', 'பிஸ்தா'],
    'raisin': ['raisins', 'kishmish', 'kismis', 'draksha', 'உலர் திராட்சை'],
    'raisins': ['raisin', 'kishmish', 'kismis', 'draksha', 'உலர் திராட்சை'],
    'kishmish': ['raisin', 'raisins', 'kismis', 'உலர் திராட்சை'],
    'kismis': ['raisin', 'raisins', 'kishmish', 'உலர் திராட்சை'],
    'peanut': ['peanuts', 'groundnut', 'groundnuts', 'kadala', 'வேர்க்கடலை'],
    'peanuts': ['peanut', 'groundnut', 'groundnuts', 'kadala', 'வேர்க்கடலை'],
    'groundnut': ['peanut', 'peanuts', 'groundnuts', 'kadala', 'வேர்க்கடலை'],
    'groundnuts': ['groundnut', 'peanut', 'peanuts', 'kadala', 'வேர்க்கடலை'],
    'walnut': ['walnuts', 'அக்ரூட்'],
    'walnuts': ['walnut', 'அக்ரூட்'],
    'dates': ['date', 'pericham pazham', 'பேரீச்சம்பழம்'],
    'moong': ['moong dal', 'paasi paruppu', 'pasi paruppu', 'பாசிப்பருப்பு'],
    'toor': ['toor dal', 'thuvaram paruppu', 'துவரம் பருப்பு'],
    'chana': ['chana dal', 'kadalai paruppu', 'kondakadalai', 'கொண்டைக்கடலை'],
    'urad': ['urad dal', 'ulundhu', 'உளுந்து'],
    'noodle': ['noodles', 'maggi', 'pasta', 'நூடுல்ஸ்'],
    'noodles': ['noodle', 'maggi', 'pasta', 'நூடுல்ஸ்'],
    'pasta': ['noodle', 'noodles', 'maggi', 'பாஸ்தா'],
    'maggi': ['noodles', 'noodle', 'instant noodles'],
  };

  // Cached in-memory search index
  static List<SearchIndexEntry>? _cachedIndex;
  static int _cachedProductHashCode = 0;

  /// Retrieves grocery aliases for a token with singular/plural support.
  static List<String> getAliasesForToken(String token) {
    final norm = SearchNormalizer.normalize(token);
    if (norm.isEmpty) return const [];

    final direct = _tamilGroceryDictionary[norm];
    if (direct != null) return direct;

    // Check singular form (e.g. "almonds" -> "almond")
    if (norm.endsWith('s') && norm.length > 2) {
      final singular = norm.substring(0, norm.length - 1);
      final sMatch = _tamilGroceryDictionary[singular];
      if (sMatch != null) return sMatch;
    }

    // Check plural form (e.g. "almond" -> "almonds")
    final pluralMatch = _tamilGroceryDictionary['${norm}s'];
    if (pluralMatch != null) return pluralMatch;

    // Check if token matches a Tamil word or variant in values
    final List<String> reverseMatches = [];
    for (final entry in _tamilGroceryDictionary.entries) {
      if (entry.value.contains(norm)) {
        reverseMatches.add(entry.key);
        reverseMatches.addAll(entry.value);
      }
    }
    return reverseMatches;
  }

  /// Builds or retrieves the cached in-memory search index.
  static List<SearchIndexEntry> getOrBuildIndex(
    List<ProductModel> products,
    Map<String, String> categoryNames,
  ) {
    // Quick cache validation by product count and first/last id
    int currentHash = products.length;
    if (products.isNotEmpty) {
      currentHash = Object.hash(products.length, products.first.id, products.last.id);
    }

    if (_cachedIndex != null && _cachedProductHashCode == currentHash && _cachedIndex!.length == products.length) {
      return _cachedIndex!;
    }

    final newIndex = products
        .map((p) => SearchIndexEntry.fromProduct(p, categoryNames))
        .toList(growable: false);

    _cachedIndex = newIndex;
    _cachedProductHashCode = currentHash;
    return newIndex;
  }

  /// Invalidate search index cache if products modified
  static void clearIndexCache() {
    _cachedIndex = null;
    _cachedProductHashCode = 0;
  }

  /// Filters and ranks products based on query, categories, active filter options, and sorting.
  static List<ProductModel> filterProducts({
    required List<ProductModel> products,
    required String rawQuery,
    List<CategoryModel>? categories,
    ProductFilterOptions filterOptions = ProductFilterOptions.empty,
    ProductSortOption sortOption = ProductSortOption.relevance,
    bool includeInactive = false,
  }) {
    final cleanQuery = SearchNormalizer.normalize(rawQuery);
    final compactQuery = SearchNormalizer.compact(rawQuery);

    // Build category ID -> Name mapping
    final Map<String, String> categoryNames = {};
    if (categories != null) {
      for (final cat in categories) {
        categoryNames[cat.id.toLowerCase()] = cat.name.toLowerCase();
      }
    }

    final index = getOrBuildIndex(products, categoryNames);
    final queryTokens = cleanQuery.isEmpty
        ? const <String>[]
        : cleanQuery.split(' ').where((t) => t.isNotEmpty).toList();

    final List<_ScoredProduct> scoredItems = [];
    final Set<String> seenProductIds = {};

    for (final entry in index) {
      final product = entry.product;

      // Honor active flag unless caller explicitly requests inactive (e.g. Admin)
      if (!includeInactive && !product.isActive) continue;

      // Deduplication safeguard
      if (seenProductIds.contains(product.id)) continue;

      double score = 0.0;

      if (cleanQuery.isNotEmpty) {
        final matchResult = calculateMatchScore(
          entry,
          cleanQuery,
          compactQuery,
          queryTokens,
          rawQuery,
        );

        if (!matchResult.matches) {
          continue;
        }
        score = matchResult.score;

        // In-stock boost to prioritize available products
        if (!entry.isOutOfStock) {
          score += 25.0;
        }
      } else {
        // When query is empty, base score on default sortOrder
        score = (10000 - product.sortOrder).toDouble();
      }

      // Apply Filters
      if (!matchesFilters(product, filterOptions)) {
        continue;
      }

      seenProductIds.add(product.id);
      scoredItems.add(_ScoredProduct(product: product, score: score));
    }

    // Apply Sorting
    _sortScoredProducts(scoredItems, sortOption);

    return scoredItems.map((item) => item.product).toList();
  }

  /// Calculates whether an indexed product matches the search query and assigns
  /// an Amazon/Blinkit-grade relevance score with strict tier ordering:
  /// EXACT > PREFIX > WORD > SUBSTRING > SUBSEQUENCE > FUZZY > SECONDARY
  static _MatchResult calculateMatchScore(
    SearchIndexEntry entry,
    String cleanQuery,
    String compactQuery,
    List<String> queryTokens,
    String rawQuery,
  ) {
    final qLen = cleanQuery.length;
    final rawLower = rawQuery.trim().toLowerCase();
    double tierScore = 0.0;
    bool matched = false;

    // ==========================================
    // TIER 1: EXACT FULL PRODUCT NAME MATCH (10,000 pts)
    // ==========================================
    if (entry.normName == cleanQuery) {
      final lenBonus = (1.0 - (cleanQuery.length / entry.normName.length).clamp(0.0, 1.0)) * 50.0;
      tierScore = 10000.0 + lenBonus;
      matched = true;
    } else if (entry.normNameTamil.isNotEmpty && entry.normNameTamil == cleanQuery) {
      tierScore = 9500.0;
      matched = true;
    }

    // ==========================================
    // TIER 2: BARCODE & SKU EXACT MATCH (9,000 pts)
    // ==========================================
    if (!matched) {
      if (entry.barcodes.any((b) => b == rawLower || b == compactQuery || b == cleanQuery) ||
          entry.skus.any((s) => s == rawLower || s == compactQuery || s == cleanQuery)) {
        tierScore = 9000.0;
        matched = true;
      }
    }

    // ==========================================
    // TIER 3: PRODUCT NAME PREFIX MATCH (8,000 pts)
    // "ric" -> "Rice" (ranks higher than longer titles)
    // ==========================================
    if (!matched) {
      if (entry.normName.startsWith(cleanQuery)) {
        final completeness = (cleanQuery.length / entry.normName.length).clamp(0.0, 1.0);
        tierScore = 8000.0 + (completeness * 500.0);
        matched = true;
      } else if (entry.normNameTamil.isNotEmpty && entry.normNameTamil.startsWith(cleanQuery)) {
        final completeness = (cleanQuery.length / entry.normNameTamil.length).clamp(0.0, 1.0);
        tierScore = 7500.0 + (completeness * 500.0);
        matched = true;
      }
    }

    // ==========================================
    // TIER 4: WORD PREFIX MATCH IN PRODUCT NAME (7,000 pts)
    // e.g. "ric" matches word "Rice" in "India Gate Basmati Rice"
    // ==========================================
    if (!matched) {
      for (final t in entry.nameTokens) {
        if (t.startsWith(cleanQuery)) {
          final completeness = (cleanQuery.length / t.length).clamp(0.0, 1.0);
          tierScore = 7000.0 + (completeness * 200.0);
          matched = true;
          break;
        }
      }
      if (!matched && entry.normNameTamil.isNotEmpty) {
        for (final t in entry.nameTamilTokens) {
          if (t.startsWith(cleanQuery)) {
            final completeness = (cleanQuery.length / t.length).clamp(0.0, 1.0);
            tierScore = 6700.0 + (completeness * 200.0);
            matched = true;
            break;
          }
        }
      }
    }

    // ==========================================
    // TIER 5: EXACT WORD MATCH IN PRODUCT NAME (6,500 pts)
    // ==========================================
    if (!matched) {
      if (entry.nameTokens.contains(cleanQuery)) {
        tierScore = 6500.0;
        matched = true;
      } else if (entry.nameTamilTokens.contains(cleanQuery)) {
        tierScore = 6200.0;
        matched = true;
      }
    }

    // ==========================================
    // TIER 6: SUBSTRING MATCH IN PRODUCT NAME (5,000 pts)
    // ==========================================
    if (!matched && cleanQuery.length >= 2) {
      if (entry.normName.contains(cleanQuery)) {
        tierScore = 5000.0;
        matched = true;
      } else if (entry.normNameTamil.isNotEmpty && entry.normNameTamil.contains(cleanQuery)) {
        tierScore = 4500.0;
        matched = true;
      }
    }

    // ==========================================
    // TIER 7: COMPACT SPACING-TOLERANT MATCH (4,000 pts)
    // "basmatirice" <-> "basmati rice"
    // ==========================================
    if (!matched && compactQuery.length >= 3) {
      if (entry.compactName == compactQuery) {
        tierScore = 4800.0;
        matched = true;
      } else if (entry.compactName.contains(compactQuery)) {
        tierScore = 4000.0;
        matched = true;
      } else if (entry.compactNameTamil.isNotEmpty && entry.compactNameTamil.contains(compactQuery)) {
        tierScore = 3800.0;
        matched = true;
      }
    }

    // ==========================================
    // TIER 8: BARCODE & SKU PREFIX MATCH (4,200 pts)
    // ==========================================
    if (!matched) {
      if (entry.barcodes.any((b) => b.startsWith(compactQuery) || b.startsWith(cleanQuery) || b.startsWith(rawLower)) ||
          entry.skus.any((s) => s.startsWith(compactQuery) || s.startsWith(cleanQuery) || s.startsWith(rawLower))) {
        tierScore = 4200.0;
        matched = true;
      }
    }

    // ==========================================
    // TIER 9: BRAND MATCH (2,000 - 3,500 pts)
    // ==========================================
    if (!matched && entry.normBrand.isNotEmpty) {
      if (entry.normBrand == cleanQuery) {
        tierScore = 3500.0;
        matched = true;
      } else if (cleanQuery.length >= 2 && entry.normBrand.startsWith(cleanQuery)) {
        tierScore = 3000.0;
        matched = true;
      } else if (cleanQuery.length >= 2 && entry.normBrand.contains(cleanQuery)) {
        tierScore = 2000.0;
        matched = true;
      }
    }

    // ==========================================
    // TIER 10: CATEGORY MATCH (1,200 - 2,800 pts)
    // ==========================================
    if (!matched && entry.normCategory.isNotEmpty) {
      if (entry.normCategory == cleanQuery) {
        tierScore = 2800.0;
        matched = true;
      } else if (cleanQuery.length >= 2 && entry.normCategory.startsWith(cleanQuery)) {
        tierScore = 2300.0;
        matched = true;
      } else if (cleanQuery.length >= 2 && entry.normCategory.contains(cleanQuery)) {
        tierScore = 1200.0;
        matched = true;
      }
    }

    // ==========================================
    // TIER 11: TRANSLITERATION / ALIASES MATCH (2,100 - 2,500 pts)
    // e.g. "arisi" -> "அரிசி" / "rice", "badam" / "badham" -> "almonds"
    // ==========================================
    if (!matched) {
      if (entry.aliases.contains(cleanQuery) ||
          (cleanQuery.length >= 2 && entry.aliases.any((a) => a == cleanQuery || a.startsWith(cleanQuery)))) {
        tierScore = 2500.0;
        matched = true;
      } else if (cleanQuery.length >= 3 && entry.aliases.any((a) => _isFuzzyMatch(cleanQuery, a))) {
        tierScore = 2100.0;
        matched = true;
      }
    }

    // ==========================================
    // TIER 12: KEYWORDS & TAGS MATCH (1,500 - 2,200 pts)
    // ==========================================
    if (!matched) {
      for (final kw in entry.normKeywords) {
        if (kw == cleanQuery || (cleanQuery.length >= 2 && kw.startsWith(cleanQuery))) {
          tierScore = 2200.0;
          matched = true;
          break;
        } else if (cleanQuery.length >= 2 && kw.contains(cleanQuery)) {
          tierScore = 1600.0;
          matched = true;
          break;
        }
      }
      if (!matched) {
        for (final tag in entry.normTags) {
          if (tag == cleanQuery || (cleanQuery.length >= 2 && tag.startsWith(cleanQuery))) {
            tierScore = 2000.0;
            matched = true;
            break;
          } else if (cleanQuery.length >= 2 && tag.contains(cleanQuery)) {
            tierScore = 1500.0;
            matched = true;
            break;
          }
        }
      }
    }

    // ==========================================
    // TIER 13: SUBSEQUENCE / IN-BETWEEN MATCHING (800 - 1,200 pts)
    // e.g. "rce" -> "rice", "bsc" -> "biscuit", "tma" -> "tomato"
    // Also matches 2-letter in-between queries (e.g. "rc" -> "rice", "sg" -> "sugar", "tm" -> "tomato")
    // and compact full-name subsequence (e.g. "soil" -> "sunfloweroil", "ibr" -> "indiagatebasmatirice")
    // ==========================================
    if (!matched && qLen >= 2) {
      for (final nameToken in entry.nameTokens) {
        if (qLen == 2) {
          // For 2 characters, ensure first char matches token start
          if (nameToken.startsWith(cleanQuery[0])) {
            final subMatch = _matchSubsequence(cleanQuery, nameToken);
            if (subMatch.matches) {
              tierScore = 1100.0 * subMatch.scoreMultiplier;
              matched = true;
              break;
            }
          }
        } else {
          final subMatch = _matchSubsequence(cleanQuery, nameToken);
          if (subMatch.matches) {
            tierScore = 1200.0 * subMatch.scoreMultiplier;
            matched = true;
            break;
          }
        }
      }

      // Check subsequence across the full compact name only for queries of length >= 4 with sufficient density
      if (!matched && compactQuery.length >= 4) {
        final subMatch = _matchSubsequence(compactQuery, entry.compactName);
        if (subMatch.matches && subMatch.scoreMultiplier >= 0.35) {
          tierScore = 1050.0 * subMatch.scoreMultiplier;
          matched = true;
        }
      }
    }

    // ==========================================
    // TIER 14: TYPO-TOLERANT FUZZY SEARCH (600 - 1,000 pts)
    // Handles inserted, deleted, or substituted letters in between the word
    // e.g. "raice" -> "rice", "suggar" / "sugear" -> "sugar", "bisckuit" -> "biscuit", "oiil" -> "oil"
    // ==========================================
    if (!matched && qLen >= 3) {
      for (final nameToken in entry.nameTokens) {
        if (_isFuzzyMatch(cleanQuery, nameToken)) {
          final dist = levenshteinDistance(cleanQuery, nameToken);
          tierScore = (dist <= 1 ? 1000.0 : 600.0);
          matched = true;
          break;
        }
      }
      if (!matched && entry.normBrand.isNotEmpty && _isFuzzyMatch(cleanQuery, entry.normBrand)) {
        tierScore = 700.0;
        matched = true;
      }
      if (!matched && entry.normCategory.isNotEmpty && _isFuzzyMatch(cleanQuery, entry.normCategory)) {
        tierScore = 600.0;
        matched = true;
      }
    }

    // ==========================================
    // TIER 15: VARIANTS (e.g. "500g", "1kg") (500 pts)
    // ==========================================
    if (!matched && cleanQuery.length >= 2) {
      for (final v in entry.normVariantTexts) {
        if (v.contains(cleanQuery)) {
          tierScore = 500.0;
          matched = true;
          break;
        }
      }
    }

    // ==========================================
    // TIER 16: DESCRIPTION MATCH (200 pts)
    // ==========================================
    if (!matched && cleanQuery.length >= 2 && entry.normDescription.contains(cleanQuery)) {
      tierScore = 200.0;
      matched = true;
    }

    // Multi-word query token matching and boost
    double multiWordBonus = 0.0;
    if (queryTokens.length > 1) {
      int matchedTokensCount = 0;
      for (final token in queryTokens) {
        final tokenMatches = (token.length >= 2 && entry.normName.contains(token)) ||
            (token.length == 1 && entry.normName.startsWith(token)) ||
            (token.length >= 2 && entry.normNameTamil.contains(token)) ||
            (token.length >= 2 && entry.normBrand.contains(token)) ||
            (token.length >= 2 && entry.normCategory.contains(token)) ||
            (token.length >= 2 && entry.normKeywords.any((k) => k.contains(token))) ||
            (token.length >= 2 && entry.normTags.any((t) => t.contains(token))) ||
            (token.length >= 2 && entry.normVariantTexts.any((v) => v.contains(token))) ||
            entry.aliases.contains(token) ||
            (token.length >= 3 && entry.nameTokens.any((t) => _isFuzzyMatch(token, t) || _matchSubsequence(token, t).matches)) ||
            (token.length == 2 && entry.nameTokens.any((t) => t.startsWith(token[0]) && _matchSubsequence(token, t).matches));

        if (tokenMatches) {
          matchedTokensCount++;
        }
      }
      if (matchedTokensCount > 0) {
        multiWordBonus = (matchedTokensCount / queryTokens.length) * 350.0;
        if (matchedTokensCount >= (queryTokens.length / 2).ceil()) {
          matched = true;
          if (tierScore == 0.0) {
            tierScore = 1500.0 + multiWordBonus;
          }
        }
      }
    }

    if (!matched) {
      return const _MatchResult(matches: false, score: 0.0);
    }

    return _MatchResult(matches: true, score: tierScore + multiWordBonus);
  }

  /// Determines if query is a valid subsequence of target string, returning
  /// density information so tighter subsequences score higher.
  static _SubsequenceResult _matchSubsequence(String query, String target) {
    if (query.isEmpty || target.isEmpty || query.length > target.length) {
      return const _SubsequenceResult(matches: false, scoreMultiplier: 0.0);
    }

    int qIdx = 0;
    int firstMatchIdx = -1;
    int lastMatchIdx = -1;

    for (int i = 0; i < target.length; i++) {
      if (target.codeUnitAt(i) == query.codeUnitAt(qIdx)) {
        if (firstMatchIdx == -1) firstMatchIdx = i;
        lastMatchIdx = i;
        qIdx++;
        if (qIdx == query.length) break;
      }
    }

    if (qIdx == query.length) {
      final span = lastMatchIdx - firstMatchIdx + 1;
      final density = query.length / span;
      final startBonus = (firstMatchIdx == 0) ? 0.2 : 0.0;
      final multiplier = (density * 0.8 + startBonus).clamp(0.2, 1.0);
      return _SubsequenceResult(matches: true, scoreMultiplier: multiplier);
    }

    return const _SubsequenceResult(matches: false, scoreMultiplier: 0.0);
  }

  /// Checks whether two strings are a typo match using Levenshtein distance.
  static bool _isFuzzyMatch(String query, String target) {
    if (query.length < 3) return false;
    final int maxDist = query.length <= 5 ? 1 : 2;
    if ((query.length - target.length).abs() > maxDist) return false;

    final dist = levenshteinDistance(query, target, maxDistance: maxDist);
    return dist <= maxDist;
  }

  /// Fast Levenshtein distance computation with early-exit threshold.
  static int levenshteinDistance(String s1, String s2, {int maxDistance = 2}) {
    if (s1 == s2) return 0;
    if ((s1.length - s2.length).abs() > maxDistance) return maxDistance + 1;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> prev = List<int>.generate(s2.length + 1, (i) => i);
    List<int> curr = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      curr[0] = i + 1;
      int minRow = curr[0];

      for (int j = 0; j < s2.length; j++) {
        final cost = (s1.codeUnitAt(i) == s2.codeUnitAt(j)) ? 0 : 1;
        final insertion = curr[j] + 1;
        final deletion = prev[j + 1] + 1;
        final substitution = prev[j] + cost;

        int minVal = insertion < deletion ? insertion : deletion;
        if (substitution < minVal) minVal = substitution;

        curr[j + 1] = minVal;
        if (minVal < minRow) minRow = minVal;
      }

      if (minRow > maxDistance) return maxDistance + 1;

      for (int j = 0; j <= s2.length; j++) {
        prev[j] = curr[j];
      }
    }

    return prev[s2.length];
  }

  /// Generates real-time search suggestions based on the user's current query.
  static List<String> getSuggestions({
    required List<ProductModel> products,
    required String rawQuery,
    List<CategoryModel>? categories,
    int limit = 6,
  }) {
    final cleanQuery = SearchNormalizer.normalize(rawQuery);
    if (cleanQuery.isEmpty) return const [];

    final matchedProducts = filterProducts(
      products: products,
      rawQuery: rawQuery,
      categories: categories,
      sortOption: ProductSortOption.relevance,
    );

    final List<String> suggestions = [];
    final Set<String> seen = {};

    for (final p in matchedProducts) {
      final name = p.name.trim();
      if (name.isNotEmpty && seen.add(name.toLowerCase())) {
        suggestions.add(name);
        if (suggestions.length >= limit) break;
      }
    }

    return suggestions;
  }

  /// Determines whether a product satisfies all active filter conditions.
  static bool matchesFilters(ProductModel product, ProductFilterOptions filter) {
    if (!filter.hasActiveFilters) return true;

    // 1. Category Filter
    if (filter.categoryIds.isNotEmpty) {
      if (!filter.categoryIds.contains(product.categoryId)) {
        return false;
      }
    }

    // 2. Brand Filter
    if (filter.brands.isNotEmpty) {
      final productBrand = product.brand.trim().toLowerCase();
      bool brandMatched = false;
      for (final b in filter.brands) {
        if (productBrand == b.trim().toLowerCase()) {
          brandMatched = true;
          break;
        }
      }
      if (!brandMatched) return false;
    }

    // Price calculation considering cheapest variant if enabled
    double effectivePrice = product.price;
    double mrp = product.mrp > 0 ? product.mrp : product.price;
    bool isOutOfStock = product.isOutOfStock;

    if (product.variantsEnabled && product.variants.isNotEmpty) {
      final availableVariants = product.variants.where((v) => !v.isOutOfStock).toList();
      if (availableVariants.isNotEmpty) {
        availableVariants.sort((a, b) => a.price.compareTo(b.price));
        effectivePrice = availableVariants.first.price;
        mrp = availableVariants.first.mrp > 0 ? availableVariants.first.mrp : effectivePrice;
        isOutOfStock = false;
      } else {
        effectivePrice = product.variants.first.price;
        mrp = product.variants.first.mrp;
        isOutOfStock = true;
      }
    }

    // 3. In Stock Only Filter
    if (filter.inStockOnly && isOutOfStock) {
      return false;
    }

    // 4. Min Price Filter
    if (filter.minPrice != null && effectivePrice < filter.minPrice!) {
      return false;
    }

    // 5. Max Price Filter
    if (filter.maxPrice != null && effectivePrice > filter.maxPrice!) {
      return false;
    }

    // 6. Min Discount Filter
    if (filter.minDiscount != null && filter.minDiscount! > 0) {
      final discountPct = mrp > effectivePrice
          ? (((mrp - effectivePrice) / mrp) * 100).round()
          : 0;
      if (discountPct < filter.minDiscount!) {
        return false;
      }
    }

    // 7. Weight / Unit Filter
    if (filter.weight != null && filter.weight!.isNotEmpty) {
      final w = filter.weight!.toLowerCase();
      final unit = product.unit.toLowerCase();
      final variantUnits = product.variants.map((v) => '${v.name} ${v.size} ${v.unitType}'.toLowerCase()).toList();
      if (!unit.contains(w) && !variantUnits.any((vu) => vu.contains(w))) {
        return false;
      }
    }

    return true;
  }

  /// Sorts scored products in place according to the chosen sort option.
  static void _sortScoredProducts(
    List<_ScoredProduct> items,
    ProductSortOption sortOption,
  ) {
    switch (sortOption) {
      case ProductSortOption.relevance:
        items.sort((a, b) {
          final scoreComparison = b.score.compareTo(a.score);
          if (scoreComparison != 0) return scoreComparison;
          return a.product.sortOrder.compareTo(b.product.sortOrder);
        });
        break;

      case ProductSortOption.priceLowToHigh:
        items.sort((a, b) {
          final priceA = a.product.variantsEnabled && a.product.variants.isNotEmpty
              ? a.product.variants.map((v) => v.price).reduce((min, val) => val < min ? val : min)
              : a.product.price;
          final priceB = b.product.variantsEnabled && b.product.variants.isNotEmpty
              ? b.product.variants.map((v) => v.price).reduce((min, val) => val < min ? val : min)
              : b.product.price;
          return priceA.compareTo(priceB);
        });
        break;

      case ProductSortOption.priceHighToLow:
        items.sort((a, b) {
          final priceA = a.product.variantsEnabled && a.product.variants.isNotEmpty
              ? a.product.variants.map((v) => v.price).reduce((max, val) => val > max ? val : max)
              : a.product.price;
          final priceB = b.product.variantsEnabled && b.product.variants.isNotEmpty
              ? b.product.variants.map((v) => v.price).reduce((max, val) => val > max ? val : max)
              : b.product.price;
          return priceB.compareTo(priceA);
        });
        break;

      case ProductSortOption.discountHighToLow:
        items.sort((a, b) {
          final discA = _calculateMaxDiscount(a.product);
          final discB = _calculateMaxDiscount(b.product);
          return discB.compareTo(discA);
        });
        break;

      case ProductSortOption.ratingHighToLow:
        items.sort((a, b) => b.score.compareTo(a.score));
        break;

      case ProductSortOption.newest:
        items.sort((a, b) {
          final timeA = a.product.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final timeB = b.product.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return timeB.compareTo(timeA);
        });
        break;
    }
  }

  static int _calculateMaxDiscount(ProductModel product) {
    if (product.variantsEnabled && product.variants.isNotEmpty) {
      int maxDisc = 0;
      for (final v in product.variants) {
        final mrp = v.mrp > 0 ? v.mrp : v.price;
        final disc = mrp > v.price ? (((mrp - v.price) / mrp) * 100).round() : 0;
        if (disc > maxDisc) maxDisc = disc;
      }
      return maxDisc;
    }
    final mrp = product.mrp > 0 ? product.mrp : product.price;
    return mrp > product.price ? (((mrp - product.price) / mrp) * 100).round() : 0;
  }
}

class _ScoredProduct {
  final ProductModel product;
  final double score;

  const _ScoredProduct({required this.product, required this.score});
}

class _MatchResult {
  final bool matches;
  final double score;

  const _MatchResult({required this.matches, required this.score});
}

class _SubsequenceResult {
  final bool matches;
  final double scoreMultiplier;

  const _SubsequenceResult({required this.matches, required this.scoreMultiplier});
}
