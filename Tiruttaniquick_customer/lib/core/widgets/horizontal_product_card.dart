import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

import '../../features/cart/presentation/cart_provider.dart';
import '../../services/current_user_provider.dart';
import '../../services/settings_provider.dart';
import '../../services/startup_provider.dart';
import 'animated_add_to_cart_button.dart';
import 'skeleton_loader.dart';

/// Amazon-style compact horizontal product card for search results and list views.
class HorizontalProductCard extends StatelessWidget {
  final ProductModel product;
  final ProductVariantModel? variant;
  final bool isDark;

  const HorizontalProductCard({
    super.key,
    required this.product,
    this.variant,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = isDark || Theme.of(context).brightness == Brightness.dark;
    final cartProvider = context.watch<CartProvider>();
    final currentUser = context.read<CurrentUserProvider>();
    final startup = context.watch<StartupProvider>();

    // Apply dynamic promotions / offers
    final decoratedProduct = startup.applyOffersToSingle(product);

    // Resolve active variant
    final ProductVariantModel? activeVariant = _resolveVariant(decoratedProduct);
    final bool isVariant = activeVariant != null;

    // Cart item lookup
    CartItemModel? cartItem;
    final currentVariantId = isVariant ? activeVariant.id : '';
    for (final item in cartProvider.items) {
      if (item.productId == decoratedProduct.id && item.variantId == currentVariantId) {
        cartItem = item;
        break;
      }
    }

    // Pricing
    final double displayPrice = isVariant ? activeVariant.price : decoratedProduct.price;
    final double mrpVal = isVariant
        ? activeVariant.mrp
        : (decoratedProduct.mrp > 0 ? decoratedProduct.mrp : decoratedProduct.price);
    final int discountPct =
        mrpVal > displayPrice ? (((mrpVal - displayPrice) / mrpVal) * 100).round() : 0;

    // Stock
    final bool isOutOfStock = isVariant ? activeVariant.isOutOfStock : decoratedProduct.isOutOfStock;

    // Variant count
    final int variantCount = decoratedProduct.variantsEnabled ? decoratedProduct.variants.length : 0;
    final bool hasMultipleVariants = variantCount > 1;

    // Image
    final String displayImage =
        (isVariant && activeVariant.imageUrl.isNotEmpty) ? activeVariant.imageUrl : decoratedProduct.imageUrl;
    final String displayBlurHash =
        (isVariant && activeVariant.blurHash.isNotEmpty) ? activeVariant.blurHash : decoratedProduct.blurHash;

    // Route navigation
    void navigateToDetail() {
      context.push('/product/${decoratedProduct.id}');
    }

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkSurface : AppColors.card,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(
          color: isDarkMode ? AppColors.darkBorder : AppColors.border,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.20 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: navigateToDetail,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left: Image Container with Badges ─────────────────────────
              SizedBox(
                width: 110,
                height: 115,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0xFF222222) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: AppNetworkImage(
                        imageUrl: displayImage,
                        blurHash: displayBlurHash,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        maxWidthDiskCache: 250,
                        maxHeightDiskCache: 250,
                        placeholder: (context, url) => const SkeletonBox(
                          width: double.infinity,
                          height: double.infinity,
                        ),
                        errorWidget: (context, url, error) => Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 32,
                            color: isDarkMode ? AppColors.darkMuted : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
                    // Discount Badge
                    if (discountPct > 0)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.orange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$discountPct% OFF',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    // Out of stock overlay
                    if (isOutOfStock)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              'Out of Stock',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Multi-variant tag
                    if (hasMultipleVariants && !isOutOfStock)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.90),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$variantCount Options',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // ── Right: Product Information & Add to Cart ──────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Brand and Rating Header Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (decoratedProduct.brand.isNotEmpty)
                              Flexible(
                                child: Text(
                                  decoratedProduct.brand.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              )
                            else
                              const SizedBox.shrink(),
                            // Rating Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: isDarkMode ? Colors.grey.shade800 : Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.amber.shade200,
                                  width: 0.5,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star, size: 10, color: Colors.amber),
                                  SizedBox(width: 2),
                                  Text(
                                    '4.5',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),

                        // Product Name
                        Text(
                          decoratedProduct.getLocalizedName(
                            context.watch<SettingsProvider>().languageCode,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            height: 1.2,
                            color: isDarkMode ? AppColors.white : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),

                        // Unit / Weight
                        Text(
                          isVariant ? activeVariant.name : decoratedProduct.unit,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDarkMode ? AppColors.darkMuted : AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Price and Add to Cart Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Price Column
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '₹${displayPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppColors.primary,
                                  ),
                                ),
                                if (mrpVal > displayPrice) ...[
                                  const SizedBox(width: 5),
                                  Text(
                                    '₹${mrpVal.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                      color: isDarkMode ? AppColors.darkMuted : AppColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            // Stock Status Text
                            Text(
                              isOutOfStock ? 'Out of Stock' : 'In Stock',
                              style: TextStyle(
                                color: isOutOfStock ? AppColors.error : AppColors.success,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),

                        // Add to Cart Button (Compact Width)
                        SizedBox(
                          width: 105,
                          child: AnimatedAddToCartButton(
                            product: decoratedProduct,
                            variant: activeVariant,
                            cartItem: cartItem,
                            isDark: isDarkMode,
                            onAdd: () {
                              if (currentUser.isAuthenticated) {
                                if (hasMultipleVariants) {
                                  navigateToDetail();
                                } else {
                                  cartProvider.add(decoratedProduct, variant: activeVariant);
                                }
                              } else {
                                _showLoginPrompt(context);
                              }
                            },
                            onIncrement: () {
                              if (cartItem != null) cartProvider.increment(cartItem);
                            },
                            onDecrement: () {
                              if (cartItem != null) cartProvider.decrement(cartItem);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ProductVariantModel? _resolveVariant(ProductModel currentProduct) {
    if (variant != null) return variant;
    if (!currentProduct.variantsEnabled || currentProduct.variants.isEmpty) return null;

    final inStock = currentProduct.variants.where((v) => !v.isOutOfStock).toList();
    if (inStock.isNotEmpty) {
      inStock.sort((a, b) => a.price.compareTo(b.price));
      return inStock.first;
    }
    return currentProduct.variants.first;
  }

  void _showLoginPrompt(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(Messages.loginRequiredDialog),
        content: const Text(Messages.loginRequiredToAddToCartPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(ButtonTexts.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go(AppRoutes.login);
            },
            child: const Text(ButtonTexts.login),
          ),
        ],
      ),
    );
  }
}
