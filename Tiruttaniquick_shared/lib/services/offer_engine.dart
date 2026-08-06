import '../models/product_model.dart';
import '../models/product_variant_model.dart';
import '../models/banner_model.dart';
import '../models/offer_model.dart';
import '../models/flash_sale_model.dart';

class OfferEngine {
  /// Applies active promotions to a list of products.
  static List<ProductModel> applyOffersToProducts(
    List<ProductModel> products, {
    required List<BannerModel> activeBanners,
    required List<OfferModel> activeOffers,
    required List<FlashSaleModel> activeFlashSales,
  }) {
    final now = DateTime.now();
    
    // Filter active promotions
    final validBanners = activeBanners.where((b) => b.isActive && now.isAfter(b.startDateTime) && now.isBefore(b.endDateTime)).toList();
    final validOffers = activeOffers.where((o) => o.isActive && now.isAfter(o.startDateTime) && now.isBefore(o.endDateTime)).toList();
    final validFlashSales = activeFlashSales.where((f) => f.isActive && now.isAfter(f.startDateTime) && now.isBefore(f.endDateTime)).toList();

    return products.map((product) {
      return applyOffersToProduct(
        product,
        validBanners: validBanners,
        validOffers: validOffers,
        validFlashSales: validFlashSales,
      );
    }).toList();
  }

  /// Applies active promotions to a single product and its variants.
  static ProductModel applyOffersToProduct(
    ProductModel product, {
    required List<BannerModel> validBanners,
    required List<OfferModel> validOffers,
    required List<FlashSaleModel> validFlashSales,
  }) {
    // 1. Process variants first (if enabled)
    List<ProductVariantModel> updatedVariants = [];
    if (product.variantsEnabled && product.variants.isNotEmpty) {
      updatedVariants = product.variants.map((variant) {
        return _applyOffersToVariant(
          product: product,
          variant: variant,
          validBanners: validBanners,
          validOffers: validOffers,
          validFlashSales: validFlashSales,
        );
      }).toList();
    }

    // 2. Process the product itself
    final appliedPromotion = _findBestPromotionForProduct(
      product: product,
      validBanners: validBanners,
      validOffers: validOffers,
      validFlashSales: validFlashSales,
    );

    if (appliedPromotion == null) {
      // If product has updated variants, sync price to the first variant
      if (updatedVariants.isNotEmpty) {
        final firstVar = updatedVariants.first;
        return product.copyWith(
          price: firstVar.price,
          mrp: firstVar.mrp,
          variants: updatedVariants,
          appliedOfferId: firstVar.appliedOfferId,
          appliedOfferTitle: firstVar.appliedOfferTitle,
          appliedOfferEndsAt: firstVar.appliedOfferEndsAt,
          appliedOfferCountdownEnabled: firstVar.appliedOfferCountdownEnabled,
          appliedOfferType: firstVar.appliedOfferType,
        );
      }
      return product;
    }

    // Determine base MRP
    final double originalMrp = product.mrp > 0 ? product.mrp : product.price;
    final double discountedPrice = _calculateDiscount(
      originalPrice: originalMrp,
      discountType: appliedPromotion.discountType,
      discountValue: appliedPromotion.discountValue,
    );

    final updatedProduct = product.copyWith(
      price: discountedPrice,
      mrp: originalMrp,
      variants: updatedVariants,
      appliedOfferId: appliedPromotion.id,
      appliedOfferTitle: appliedPromotion.title,
      appliedOfferEndsAt: appliedPromotion.endDateTime,
      appliedOfferCountdownEnabled: appliedPromotion.countdownEnabled,
      appliedOfferType: appliedPromotion.promoType,
    );

    return updatedProduct;
  }

  /// Internal: Apply promotions to a specific product variant
  static ProductVariantModel _applyOffersToVariant({
    required ProductModel product,
    required ProductVariantModel variant,
    required List<BannerModel> validBanners,
    required List<OfferModel> validOffers,
    required List<FlashSaleModel> validFlashSales,
  }) {
    final appliedPromotion = _findBestPromotionForVariant(
      product: product,
      variant: variant,
      validBanners: validBanners,
      validOffers: validOffers,
      validFlashSales: validFlashSales,
    );

    if (appliedPromotion == null) {
      return variant;
    }

    final double originalMrp = variant.mrp > 0 ? variant.mrp : variant.price;
    final double discountedPrice = _calculateDiscount(
      originalPrice: originalMrp,
      discountType: appliedPromotion.discountType,
      discountValue: appliedPromotion.discountValue,
    );

    return variant.copyWith(
      price: discountedPrice,
      mrp: originalMrp,
      discount: originalMrp > 0 ? (((originalMrp - discountedPrice) / originalMrp) * 100).roundToDouble() : 0.0,
      appliedOfferId: appliedPromotion.id,
      appliedOfferTitle: appliedPromotion.title,
      appliedOfferEndsAt: appliedPromotion.endDateTime,
      appliedOfferCountdownEnabled: appliedPromotion.countdownEnabled,
      appliedOfferType: appliedPromotion.promoType,
    );
  }

  /// Calculates discounted price based on type and value
  static double _calculateDiscount({
    required double originalPrice,
    required String discountType,
    required double discountValue,
  }) {
    double price = originalPrice;
    final type = discountType.toLowerCase();
    
    if (type == 'percentage') {
      price = originalPrice * (1 - discountValue / 100);
    } else if (type == 'flat') {
      price = originalPrice - discountValue;
    }
    
    return price.clamp(0.0, double.infinity);
  }

  /// Find the best promotion (highest priority) matching the product.
  static _ResolvedPromo? _findBestPromotionForProduct({
    required ProductModel product,
    required List<BannerModel> validBanners,
    required List<OfferModel> validOffers,
    required List<FlashSaleModel> validFlashSales,
  }) {
    final List<_ResolvedPromo> candidates = [];

    // 1. Check flash sales
    for (final fs in validFlashSales) {
      if (_matchesCriteria(product: product, targetType: fs.targetType, targetIds: fs.targetIds)) {
        candidates.add(_ResolvedPromo(
          id: fs.id,
          title: fs.title,
          discountType: fs.discountType,
          discountValue: fs.discountValue,
          priority: 5, // Flash sale has highest priority
          endDateTime: fs.endDateTime,
          countdownEnabled: true, // Flash sales always have countdowns
          promoType: 'Flash Sale',
        ));
      }
    }

    // 2. Check offers
    for (final offer in validOffers) {
      if (_matchesCriteria(product: product, targetType: offer.targetType, targetIds: offer.targetIds)) {
        candidates.add(_ResolvedPromo(
          id: offer.id,
          title: offer.title,
          discountType: offer.discountType,
          discountValue: offer.discountValue,
          priority: _resolvePriority(offer.priority, offer.offerType),
          endDateTime: offer.endDateTime,
          countdownEnabled: offer.countdownEnabled,
          promoType: offer.offerType,
        ));
      }
    }

    // 3. Check banners (banners can also carry offers)
    for (final banner in validBanners) {
      if (banner.discountValue > 0 &&
          _matchesCriteria(product: product, targetType: banner.targetType, targetIds: banner.targetIds)) {
        candidates.add(_ResolvedPromo(
          id: banner.id,
          title: banner.title,
          discountType: banner.discountType,
          discountValue: banner.discountValue,
          priority: _resolvePriority(banner.priority, banner.bannerType),
          endDateTime: banner.endDateTime,
          countdownEnabled: banner.countdownEnabled,
          promoType: banner.bannerType,
        ));
      }
    }

    if (candidates.isEmpty) return null;

    // Sort by priority descending
    candidates.sort((a, b) => b.priority.compareTo(a.priority));
    return candidates.first;
  }

  /// Find the best promotion (highest priority) matching a variant.
  static _ResolvedPromo? _findBestPromotionForVariant({
    required ProductModel product,
    required ProductVariantModel variant,
    required List<BannerModel> validBanners,
    required List<OfferModel> validOffers,
    required List<FlashSaleModel> validFlashSales,
  }) {
    final List<_ResolvedPromo> candidates = [];

    // 1. Check flash sales
    for (final fs in validFlashSales) {
      if (_matchesCriteria(product: product, variantId: variant.id, targetType: fs.targetType, targetIds: fs.targetIds)) {
        candidates.add(_ResolvedPromo(
          id: fs.id,
          title: fs.title,
          discountType: fs.discountType,
          discountValue: fs.discountValue,
          priority: 5,
          endDateTime: fs.endDateTime,
          countdownEnabled: true,
          promoType: 'Flash Sale',
        ));
      }
    }

    // 2. Check offers
    for (final offer in validOffers) {
      if (_matchesCriteria(product: product, variantId: variant.id, targetType: offer.targetType, targetIds: offer.targetIds)) {
        candidates.add(_ResolvedPromo(
          id: offer.id,
          title: offer.title,
          discountType: offer.discountType,
          discountValue: offer.discountValue,
          priority: _resolvePriority(offer.priority, offer.offerType),
          endDateTime: offer.endDateTime,
          countdownEnabled: offer.countdownEnabled,
          promoType: offer.offerType,
        ));
      }
    }

    // 3. Check banners
    for (final banner in validBanners) {
      if (banner.discountValue > 0 &&
          _matchesCriteria(product: product, variantId: variant.id, targetType: banner.targetType, targetIds: banner.targetIds)) {
        candidates.add(_ResolvedPromo(
          id: banner.id,
          title: banner.title,
          discountType: banner.discountType,
          discountValue: banner.discountValue,
          priority: _resolvePriority(banner.priority, banner.bannerType),
          endDateTime: banner.endDateTime,
          countdownEnabled: banner.countdownEnabled,
          promoType: banner.bannerType,
        ));
      }
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => b.priority.compareTo(a.priority));
    return candidates.first;
  }

  /// Checks if a product/variant matches target criteria.
  static bool _matchesCriteria({
    required ProductModel product,
    String? variantId,
    required String targetType,
    required List<String> targetIds,
  }) {
    final type = targetType.toLowerCase();

    if (type == 'entire store' || type == 'entire_store') {
      return true;
    }
    
    if (targetIds.isEmpty) return false;

    if (type == 'selected products' || type == 'selected_products' || type == 'products') {
      return targetIds.contains(product.id);
    }
    
    if (type == 'selected categories' || type == 'selected_categories' || type == 'categories') {
      return targetIds.contains(product.categoryId);
    }
    
    if (type == 'selected brands' || type == 'selected_brands' || type == 'brands') {
      final brandNorm = product.brand.trim().toLowerCase();
      return targetIds.any((id) => id.trim().toLowerCase() == brandNorm);
    }

    if (type == 'selected variants' || type == 'selected_variants' || type == 'variants') {
      if (variantId != null) {
        return targetIds.contains(variantId);
      }
      // If variantId is null (checking product level), match if product has any variant in targetIds
      if (product.variantsEnabled && product.variants.isNotEmpty) {
        return product.variants.any((v) => targetIds.contains(v.id));
      }
      return false;
    }

    if (type == 'selected collections' || type == 'selected_collections' || type == 'collections') {
      // Matches tags/collections
      return product.tags.any((tag) => targetIds.any((id) => id.trim().toLowerCase() == tag.trim().toLowerCase()));
    }

    return false;
  }

  /// Helper to resolve priority score.
  static int _resolvePriority(int explicitPriority, String type) {
    int typePriority = 0;
    final t = type.toLowerCase();
    
    if (t.contains('flash')) {
      typePriority = 5;
    } else if (t.contains('festival')) {
      typePriority = 4;
    } else if (t.contains('product')) {
      typePriority = 3;
    } else if (t.contains('category')) {
      typePriority = 2;
    } else if (t.contains('brand')) {
      typePriority = 1;
    }
    
    return explicitPriority > typePriority ? explicitPriority : typePriority;
  }
}

class _ResolvedPromo {
  final String id;
  final String title;
  final String discountType;
  final double discountValue;
  final int priority;
  final DateTime endDateTime;
  final bool countdownEnabled;
  final String promoType;

  _ResolvedPromo({
    required this.id,
    required this.title,
    required this.discountType,
    required this.discountValue,
    required this.priority,
    required this.endDateTime,
    required this.countdownEnabled,
    required this.promoType,
  });
}
