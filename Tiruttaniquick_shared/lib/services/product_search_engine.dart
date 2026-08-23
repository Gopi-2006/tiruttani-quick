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

/// High-performance Amazon-style multi-field product search & filtering engine.
class ProductSearchEngine {
  /// Filters and ranks products based on query, categories, active filter options, and sorting.
  static List<ProductModel> filterProducts({
    required List<ProductModel> products,
    required String rawQuery,
    List<CategoryModel>? categories,
    ProductFilterOptions filterOptions = ProductFilterOptions.empty,
    ProductSortOption sortOption = ProductSortOption.relevance,
  }) {
    final cleanQuery = rawQuery.trim().toLowerCase();
    
    // Build category ID -> Name mapping for category search matching
    final Map<String, String> categoryNames = {};
    if (categories != null) {
      for (final cat in categories) {
        categoryNames[cat.id.toLowerCase()] = cat.name.toLowerCase();
      }
    }

    final queryTokens = cleanQuery.isEmpty
        ? <String>[]
        : cleanQuery
            .split(RegExp(r'\s+'))
            .where((t) => t.isNotEmpty)
            .toList();

    // Step 1: Filter and score products matching the search query
    final List<_ScoredProduct> scoredItems = [];

    for (final product in products) {
      // Must be an active product
      if (!product.isActive) continue;

      double score = 0.0;

      if (queryTokens.isNotEmpty) {
        final matchResult = calculateMatchScore(
          product,
          cleanQuery,
          queryTokens,
          categoryNames,
        );

        if (!matchResult.matches) {
          continue;
        }
        score = matchResult.score;
      } else {
        // When query is empty, base score on default sortOrder
        score = (10000 - product.sortOrder).toDouble();
      }

      // Step 2: Apply Filters
      if (!matchesFilters(product, filterOptions)) {
        continue;
      }

      scoredItems.add(_ScoredProduct(product: product, score: score));
    }

    // Step 3: Apply Sorting
    _sortScoredProducts(scoredItems, sortOption);

    return scoredItems.map((item) => item.product).toList();
  }

  /// Calculates whether a product matches the query tokens and calculates its relevance score.
  static _MatchResult calculateMatchScore(
    ProductModel product,
    String cleanQuery,
    List<String> queryTokens,
    Map<String, String> categoryNames,
  ) {
    final String name = product.name.toLowerCase();
    final String nameTamil = product.nameTamil.toLowerCase();
    final String brand = product.brand.toLowerCase();
    final String categoryId = product.categoryId.toLowerCase();
    final String categoryName = (categoryNames[categoryId] ?? '').toLowerCase();
    final String subCategoryId = product.subCategoryId.toLowerCase();
    final String description = product.description.toLowerCase();
    final String longDescription = product.longDescription.toLowerCase();
    final String unit = product.unit.toLowerCase();

    final List<String> tags = product.tags.map((t) => t.toLowerCase()).toList();
    final List<String> keywords = product.searchKeywords.map((k) => k.toLowerCase()).toList();
    final List<String> variantNames = product.variants
        .map((v) => '${v.name} ${v.size} ${v.unitType}'.toLowerCase())
        .toList();

    // Check that EVERY query token is matched in at least one field
    for (final token in queryTokens) {
      bool tokenMatched = false;

      if (name.contains(token) ||
          nameTamil.contains(token) ||
          brand.contains(token) ||
          categoryId.contains(token) ||
          categoryName.contains(token) ||
          subCategoryId.contains(token) ||
          description.contains(token) ||
          longDescription.contains(token) ||
          unit.contains(token)) {
        tokenMatched = true;
      }

      if (!tokenMatched) {
        for (final tag in tags) {
          if (tag.contains(token)) {
            tokenMatched = true;
            break;
          }
        }
      }

      if (!tokenMatched) {
        for (final kw in keywords) {
          if (kw.contains(token)) {
            tokenMatched = true;
            break;
          }
        }
      }

      if (!tokenMatched) {
        for (final vt in variantNames) {
          if (vt.contains(token)) {
            tokenMatched = true;
            break;
          }
        }
      }

      if (!tokenMatched) {
        final tokenCompact = token.replaceAll(RegExp(r'\s+'), '');
        if (name.replaceAll(' ', '').contains(tokenCompact) ||
            unit.replaceAll(' ', '').contains(tokenCompact) ||
            variantNames.any((vt) => vt.replaceAll(' ', '').contains(tokenCompact))) {
          tokenMatched = true;
        }
      }

      if (!tokenMatched) {
        return const _MatchResult(matches: false, score: 0.0);
      }
    }

    // --- Amazon-Style Relevance Scoring Algorithm ---
    double score = 0.0;

    // 1. Exact Name Match (Highest priority)
    if (name == cleanQuery || (nameTamil.isNotEmpty && nameTamil == cleanQuery)) {
      score += 1000.0;
    }
    // 2. Product name starts with query
    else if (name.startsWith(cleanQuery) || (nameTamil.isNotEmpty && nameTamil.startsWith(cleanQuery))) {
      score += 750.0;
    }
    // 3. Product name contains query as a complete word (e.g. "rice" in "India Gate Rice")
    else if (RegExp(r'(^|\s)' + RegExp.escape(cleanQuery) + r'(\s|$)').hasMatch(name)) {
      score += 500.0;
    }
    // 4. Product name contains query as a substring (e.g. "ash" in "Aashirvaad", "tta" in "Atta")
    else if (name.contains(cleanQuery) || nameTamil.contains(cleanQuery)) {
      score += 350.0;
    }

    // Token-level Name matching boost
    int tokensInName = 0;
    for (final token in queryTokens) {
      if (name.contains(token) || nameTamil.contains(token)) {
        tokensInName++;
      }
    }
    if (queryTokens.isNotEmpty) {
      score += (tokensInName / queryTokens.length) * 200.0;
    }

    // 5. Brand Match
    if (brand.isNotEmpty) {
      if (brand == cleanQuery) {
        score += 300.0;
      } else if (brand.startsWith(cleanQuery)) {
        score += 200.0;
      } else if (brand.contains(cleanQuery)) {
        score += 150.0;
      }
    }

    // 6. Category Match
    if (categoryName.isNotEmpty) {
      if (categoryName == cleanQuery) {
        score += 220.0;
      } else if (categoryName.startsWith(cleanQuery)) {
        score += 160.0;
      } else if (categoryName.contains(cleanQuery)) {
        score += 110.0;
      }
    }

    // 7. Tags & Search Keywords Match
    for (final tag in tags) {
      if (tag == cleanQuery) {
        score += 90.0;
        break;
      } else if (tag.contains(cleanQuery)) {
        score += 45.0;
        break;
      }
    }
    for (final kw in keywords) {
      if (kw == cleanQuery) {
        score += 90.0;
        break;
      } else if (kw.contains(cleanQuery)) {
        score += 45.0;
        break;
      }
    }

    // 8. Variants Match
    for (final vn in variantNames) {
      if (vn.contains(cleanQuery)) {
        score += 60.0;
        break;
      }
    }

    // 9. Description Match
    if (description.contains(cleanQuery) || longDescription.contains(cleanQuery)) {
      score += 30.0;
    }

    return _MatchResult(matches: true, score: score);
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
        // Default rating sort (placeholder 4.5 baseline or custom rating when available)
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
