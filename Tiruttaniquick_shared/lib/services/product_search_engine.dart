import '../models/product_model.dart';
import '../models/category_model.dart';

/// High-performance multi-field product search engine.
class ProductSearchEngine {
  /// Filters a list of products based on a search query and optional category metadata.
  /// 
  /// Multi-field matching supported:
  /// - Product name (English & Tamil)
  /// - Brand name
  /// - Category ID & Category Name
  /// - Subcategory ID
  /// - Product tags & search keywords
  /// - Product description
  /// - Variant titles & units
  static List<ProductModel> filterProducts({
    required List<ProductModel> products,
    required String rawQuery,
    List<CategoryModel>? categories,
  }) {
    final cleanQuery = rawQuery.trim().toLowerCase();
    if (cleanQuery.isEmpty) return List.unmodifiable(products);

    // Split query into tokens (e.g. "vim soap" -> ["vim", "soap"])
    final queryTokens = cleanQuery
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
        
    if (queryTokens.isEmpty) return List.unmodifiable(products);

    // Build category ID -> Name mapping for category search matching
    final Map<String, String> categoryNames = {};
    if (categories != null) {
      for (final cat in categories) {
        categoryNames[cat.id.toLowerCase()] = cat.name.toLowerCase();
      }
    }

    return products.where((product) {
      return matchesQuery(product, queryTokens, categoryNames);
    }).toList();
  }

  /// Determines if a single product matches all query tokens.
  static bool matchesQuery(
    ProductModel product,
    List<String> queryTokens,
    Map<String, String> categoryNames,
  ) {
    final String name = product.name.toLowerCase();
    final String nameTamil = product.nameTamil.toLowerCase();
    final String brand = product.brand.toLowerCase();
    final String categoryId = product.categoryId.toLowerCase();
    final String categoryName = categoryNames[categoryId] ?? '';
    final String subCategoryId = product.subCategoryId.toLowerCase();
    final String description = product.description.toLowerCase();
    final String longDescription = product.longDescription.toLowerCase();
    final String unit = product.unit.toLowerCase();

    final List<String> tags = product.tags.map((t) => t.toLowerCase()).toList();
    final List<String> keywords = product.searchKeywords.map((k) => k.toLowerCase()).toList();
    final List<String> variantTexts = product.variants
        .map((v) => '${v.name} ${v.size} ${v.unitType}'.toLowerCase())
        .toList();

    // Check each query token: every token must be matched in at least one field
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
        for (final vt in variantTexts) {
          if (vt.contains(token)) {
            tokenMatched = true;
            break;
          }
        }
      }

      if (!tokenMatched) {
        return false;
      }
    }

    return true;
  }
}
