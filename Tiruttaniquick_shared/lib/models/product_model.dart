import 'package:cloud_firestore/cloud_firestore.dart';
import 'product_variant_model.dart';

class ProductModel {
  final String id;
  final String name;
  final String nameTamil;
  final String imageUrl;
  final double price;
  final String categoryId;
  final String unit;
  final int stockQuantity;
  final int lowStockThreshold;
  final bool isActive;
  final int sortOrder;
  final DateTime? createdAt;
  final String brand;
  final String description;
  final double mrp;
  final DateTime? updatedAt;
  
  // Advanced Variant Fields
  final bool variantsEnabled;
  final List<ProductVariantModel> variants;
  final String subCategoryId;
  final String ingredients;
  final List<String> productImages;
  final List<String> tags;

  // Flipkart Redesign Fields
  final int maxStock;
  final String longDescription;
  final String storageInstructions;
  final List<String> searchKeywords;
  final String metaTitle;
  final String metaDescription;
  final String slug;
  final bool isFeatured;
  final bool isTodayDeal;
  final bool isTrending;
  final bool isRecommended;
  final bool isBestSeller;
  final bool isNewArrival;
  final bool enableReviews;
  final bool enableWishlist;
  final String couponCode;
  final bool buyOneGetOne;
  final bool isFlashSale;
  final bool isComboOffer;
  final bool isLimitedTimeOffer;

  // Transient promotion fields
  final String? appliedOfferId;
  final String? appliedOfferTitle;
  final DateTime? appliedOfferEndsAt;
  final bool? appliedOfferCountdownEnabled;
  final String? appliedOfferType;

  const ProductModel({
    required this.id,
    required this.name,
    this.nameTamil = '',
    required this.imageUrl,
    required this.price,
    required this.categoryId,
    required this.unit,
    required this.stockQuantity,
    required this.lowStockThreshold,
    required this.isActive,
    required this.sortOrder,
    this.createdAt,
    this.brand = '',
    this.description = '',
    this.mrp = 0.0,
    this.updatedAt,
    this.variantsEnabled = false,
    this.variants = const [],
    this.subCategoryId = '',
    this.ingredients = '',
    this.productImages = const [],
    this.tags = const [],
    this.maxStock = 9999,
    this.longDescription = '',
    this.storageInstructions = '',
    this.searchKeywords = const [],
    this.metaTitle = '',
    this.metaDescription = '',
    this.slug = '',
    this.isFeatured = false,
    this.isTodayDeal = false,
    this.isTrending = false,
    this.isRecommended = false,
    this.isBestSeller = false,
    this.isNewArrival = false,
    this.enableReviews = true,
    this.enableWishlist = true,
    this.couponCode = '',
    this.buyOneGetOne = false,
    this.isFlashSale = false,
    this.isComboOffer = false,
    this.isLimitedTimeOffer = false,
    this.appliedOfferId,
    this.appliedOfferTitle,
    this.appliedOfferEndsAt,
    this.appliedOfferCountdownEnabled,
    this.appliedOfferType,
  });

  factory ProductModel.fromFirestore(String id, Map<String, dynamic> data) {
    final priceVal = (data['sellingPrice'] as num?)?.toDouble() ?? (data['price'] as num?)?.toDouble() ?? 0.0;
    
    // Parse variants
    final List<ProductVariantModel> parsedVariants = [];
    if (data['variants'] != null) {
      final List<dynamic> variantsList = data['variants'] as List<dynamic>;
      for (final v in variantsList) {
        if (v is Map) {
          parsedVariants.add(ProductVariantModel.fromMap(Map<String, dynamic>.from(v)));
        }
      }
    }

    return ProductModel(
      id: id,
      name: data['productName'] as String? ?? data['name'] as String? ?? 'Product',
      nameTamil: data['productNameTamil'] as String? ?? data['nameTamil'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      price: priceVal,
      categoryId: data['category'] as String? ?? data['categoryId'] as String? ?? '',
      unit: data['unit'] as String? ?? '',
      stockQuantity: data['stockQuantity'] as int? ?? 0,
      lowStockThreshold: data['lowStockThreshold'] as int? ?? 5,
      isActive: data['isActive'] as bool? ?? true,
      sortOrder: data['sortOrder'] as int? ?? 999,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : (data['createdAt'] is DateTime ? data['createdAt'] as DateTime : null),
      brand: data['brand'] as String? ?? '',
      description: data['description'] as String? ?? '',
      mrp: (data['mrp'] as num?)?.toDouble() ?? priceVal,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : (data['updatedAt'] is DateTime ? data['updatedAt'] as DateTime : null),
      variantsEnabled: data['variantsEnabled'] as bool? ?? false,
      variants: parsedVariants,
      subCategoryId: data['subCategoryId'] as String? ?? data['subCategory'] as String? ?? '',
      ingredients: data['ingredients'] as String? ?? '',
      productImages: List<String>.from(data['productImages'] ?? []),
      tags: List<String>.from(data['tags'] ?? []),
      maxStock: data['maxStock'] as int? ?? 9999,
      longDescription: data['longDescription'] as String? ?? '',
      storageInstructions: data['storageInstructions'] as String? ?? '',
      searchKeywords: List<String>.from(data['searchKeywords'] ?? []),
      metaTitle: data['metaTitle'] as String? ?? '',
      metaDescription: data['metaDescription'] as String? ?? '',
      slug: data['slug'] as String? ?? '',
      isFeatured: data['isFeatured'] as bool? ?? false,
      isTodayDeal: data['isTodayDeal'] as bool? ?? false,
      isTrending: data['isTrending'] as bool? ?? false,
      isRecommended: data['isRecommended'] as bool? ?? false,
      isBestSeller: data['isBestSeller'] as bool? ?? false,
      isNewArrival: data['isNewArrival'] as bool? ?? false,
      enableReviews: data['enableReviews'] as bool? ?? true,
      enableWishlist: data['enableWishlist'] as bool? ?? true,
      couponCode: data['couponCode'] as String? ?? '',
      buyOneGetOne: data['buyOneGetOne'] as bool? ?? false,
      isFlashSale: data['isFlashSale'] as bool? ?? false,
      isComboOffer: data['isComboOffer'] as bool? ?? false,
      isLimitedTimeOffer: data['isLimitedTimeOffer'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productName': name,
      'name': name,
      'productNameTamil': nameTamil,
      'nameTamil': nameTamil,
      'imageUrl': imageUrl,
      'sellingPrice': price,
      'price': price,
      'category': categoryId,
      'categoryId': categoryId,
      'brand': brand,
      'description': description,
      'unit': unit,
      'stockQuantity': stockQuantity,
      'lowStockThreshold': lowStockThreshold,
      'isActive': isActive,
      'sortOrder': sortOrder,
      'mrp': mrp,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': updatedAt ?? FieldValue.serverTimestamp(),
      'variantsEnabled': variantsEnabled,
      'variants': variants.map((v) => v.toMap()).toList(),
      'subCategoryId': subCategoryId,
      'subCategory': subCategoryId,
      'ingredients': ingredients,
      'productImages': productImages,
      'tags': tags,
      'maxStock': maxStock,
      'longDescription': longDescription,
      'storageInstructions': storageInstructions,
      'searchKeywords': searchKeywords,
      'metaTitle': metaTitle,
      'metaDescription': metaDescription,
      'slug': slug,
      'isFeatured': isFeatured,
      'isTodayDeal': isTodayDeal,
      'isTrending': isTrending,
      'isRecommended': isRecommended,
      'isBestSeller': isBestSeller,
      'isNewArrival': isNewArrival,
      'enableReviews': enableReviews,
      'enableWishlist': enableWishlist,
      'couponCode': couponCode,
      'buyOneGetOne': buyOneGetOne,
      'isFlashSale': isFlashSale,
      'isComboOffer': isComboOffer,
      'isLimitedTimeOffer': isLimitedTimeOffer,
    };
  }

  String getLocalizedName(String languageCode) {
    if (languageCode == 'ta' && nameTamil.isNotEmpty) {
      return nameTamil;
    }
    return name;
  }

  bool get isLowStock => stockQuantity > 0 && stockQuantity <= lowStockThreshold;
  bool get isOutOfStock => stockQuantity <= 0;

  ProductModel copyWith({
    String? id,
    String? name,
    String? nameTamil,
    String? imageUrl,
    double? price,
    String? categoryId,
    String? unit,
    int? stockQuantity,
    int? lowStockThreshold,
    bool? isActive,
    int? sortOrder,
    DateTime? createdAt,
    String? brand,
    String? description,
    double? mrp,
    DateTime? updatedAt,
    bool? variantsEnabled,
    List<ProductVariantModel>? variants,
    String? subCategoryId,
    String? ingredients,
    List<String>? productImages,
    List<String>? tags,
    int? maxStock,
    String? longDescription,
    String? storageInstructions,
    List<String>? searchKeywords,
    String? metaTitle,
    String? metaDescription,
    String? slug,
    bool? isFeatured,
    bool? isTodayDeal,
    bool? isTrending,
    bool? isRecommended,
    bool? isBestSeller,
    bool? isNewArrival,
    bool? enableReviews,
    bool? enableWishlist,
    String? couponCode,
    bool? buyOneGetOne,
    bool? isFlashSale,
    bool? isComboOffer,
    bool? isLimitedTimeOffer,
    String? appliedOfferId,
    String? appliedOfferTitle,
    DateTime? appliedOfferEndsAt,
    bool? appliedOfferCountdownEnabled,
    String? appliedOfferType,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      nameTamil: nameTamil ?? this.nameTamil,
      imageUrl: imageUrl ?? this.imageUrl,
      price: price ?? this.price,
      categoryId: categoryId ?? this.categoryId,
      unit: unit ?? this.unit,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      brand: brand ?? this.brand,
      description: description ?? this.description,
      mrp: mrp ?? this.mrp,
      updatedAt: updatedAt ?? this.updatedAt,
      variantsEnabled: variantsEnabled ?? this.variantsEnabled,
      variants: variants ?? this.variants,
      subCategoryId: subCategoryId ?? this.subCategoryId,
      ingredients: ingredients ?? this.ingredients,
      productImages: productImages ?? this.productImages,
      tags: tags ?? this.tags,
      maxStock: maxStock ?? this.maxStock,
      longDescription: longDescription ?? this.longDescription,
      storageInstructions: storageInstructions ?? this.storageInstructions,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      metaTitle: metaTitle ?? this.metaTitle,
      metaDescription: metaDescription ?? this.metaDescription,
      slug: slug ?? this.slug,
      isFeatured: isFeatured ?? this.isFeatured,
      isTodayDeal: isTodayDeal ?? this.isTodayDeal,
      isTrending: isTrending ?? this.isTrending,
      isRecommended: isRecommended ?? this.isRecommended,
      isBestSeller: isBestSeller ?? this.isBestSeller,
      isNewArrival: isNewArrival ?? this.isNewArrival,
      enableReviews: enableReviews ?? this.enableReviews,
      enableWishlist: enableWishlist ?? this.enableWishlist,
      couponCode: couponCode ?? this.couponCode,
      buyOneGetOne: buyOneGetOne ?? this.buyOneGetOne,
      isFlashSale: isFlashSale ?? this.isFlashSale,
      isComboOffer: isComboOffer ?? this.isComboOffer,
      isLimitedTimeOffer: isLimitedTimeOffer ?? this.isLimitedTimeOffer,
      appliedOfferId: appliedOfferId ?? this.appliedOfferId,
      appliedOfferTitle: appliedOfferTitle ?? this.appliedOfferTitle,
      appliedOfferEndsAt: appliedOfferEndsAt ?? this.appliedOfferEndsAt,
      appliedOfferCountdownEnabled: appliedOfferCountdownEnabled ?? this.appliedOfferCountdownEnabled,
      appliedOfferType: appliedOfferType ?? this.appliedOfferType,
    );
  }
}

