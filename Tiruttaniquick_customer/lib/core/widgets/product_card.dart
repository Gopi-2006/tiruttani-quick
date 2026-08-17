import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../services/startup_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'animated_add_to_cart_button.dart';
import 'skeleton_loader.dart';

import '../../services/current_user_provider.dart';
import '../../features/cart/presentation/cart_provider.dart';
import '../../services/settings_provider.dart';

class ProductCard extends StatelessWidget {
  final ProductModel product;
  /// If provided, this specific variant is locked/pre-selected.
  /// Leave null to let the card pick the cheapest available variant automatically.
  final ProductVariantModel? variant;
  /// If true, renders the dark #1A1A1A surface card variant (featured/grid listings).
  final bool isDark;

  const ProductCard({
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

    // Dynamic Offer Decoration
    final decoratedProduct = startup.applyOffersToSingle(product);

    // Resolve the "display" variant – prefer cheapest available
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

    // Variant count
    final int variantCount = decoratedProduct.variantsEnabled ? decoratedProduct.variants.length : 0;
    final bool hasMultipleVariants = variantCount > 1;

    // Image
    final String displayImage =
        (isVariant && activeVariant.imageUrl.isNotEmpty) ? activeVariant.imageUrl : decoratedProduct.imageUrl;

    // Countdown Timer Settings
    final DateTime? offerEndsAt = isVariant ? activeVariant.appliedOfferEndsAt : decoratedProduct.appliedOfferEndsAt;
    final bool showCountdown = isVariant 
        ? (activeVariant.appliedOfferCountdownEnabled == true)
        : (decoratedProduct.appliedOfferCountdownEnabled == true);

    // Route – always open the product detail page
    void navigateToDetail() {
      context.push('/product/${decoratedProduct.id}');
    }

    return Container(
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
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: navigateToDetail,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Product image + badges ──────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppDimensions.cardRadius),
                    ),
                    child: (displayImage.trim().startsWith('http://') || displayImage.trim().startsWith('https://'))
                        ? CachedNetworkImage(
                            imageUrl: displayImage.trim(),
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                            maxWidthDiskCache: 250,
                            maxHeightDiskCache: 250,
                            placeholder: (context, url) => const SkeletonBox(
                              width: double.infinity,
                              height: double.infinity,
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: isDarkMode ? const Color(0xFF222222) : Colors.grey.shade50,
                              child: Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 36,
                                  color: isDarkMode ? AppColors.darkMuted : Colors.grey.shade400,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            color: isDarkMode ? const Color(0xFF222222) : Colors.grey.shade50,
                            child: Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 36,
                                color: isDarkMode ? AppColors.darkMuted : Colors.grey.shade400,
                              ),
                            ),
                          ),
                  ),
                  // Discount badge
                  if (discountPct > 0)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.orange,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$discountPct% OFF',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  // Rating badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.star, size: 10, color: Colors.white),
                          SizedBox(width: 2),
                          Text(
                            '4.5',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Variant count badge (bottom-left of image)
                  if (hasMultipleVariants)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$variantCount Options',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Product info ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand
                  if (decoratedProduct.brand.isNotEmpty)
                    Text(
                      decoratedProduct.brand.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  const SizedBox(height: 2),
                  // Product name
                  Text(
                    decoratedProduct.getLocalizedName(context.watch<SettingsProvider>().languageCode),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isDarkMode ? AppColors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Unit / size sub-label
                  Text(
                    isVariant ? activeVariant.name : decoratedProduct.unit,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDarkMode ? AppColors.darkMuted : AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Price and Countdown row (responsive wrap)
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // "Starting from" prefix when multiple variants exist
                          if (hasMultipleVariants)
                            Text(
                              'From ',
                              style: TextStyle(
                                color: isDarkMode ? AppColors.darkMuted : AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          Text(
                            '₹${displayPrice.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.primary, // Amber price tag
                            ),
                          ),
                          const SizedBox(width: 4),
                          if (mrpVal > displayPrice)
                            Text(
                              '₹${mrpVal.toStringAsFixed(0)}',
                              style: TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: isDarkMode ? AppColors.darkMuted : AppColors.muted,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                      if (offerEndsAt != null && showCountdown)
                        InlineProductCountdown(endDateTime: offerEndsAt),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Add-to-cart button
                  AnimatedAddToCartButton(
                    product: decoratedProduct,
                    variant: activeVariant,
                    cartItem: cartItem,
                    isDark: isDarkMode,
                    onAdd: () {
                      if (currentUser.isAuthenticated) {
                        // If multi-variant, open product detail to let user pick
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns the best variant to display.
  /// Priority: caller-supplied → cheapest in-stock → first variant → null.
  ProductVariantModel? _resolveVariant(ProductModel currentProduct) {
    if (variant != null) return variant;
    if (!currentProduct.variantsEnabled || currentProduct.variants.isEmpty) return null;

    // Prefer cheapest in-stock variant
    final inStock = currentProduct.variants.where((v) => !v.isOutOfStock).toList();
    if (inStock.isNotEmpty) {
      inStock.sort((a, b) => a.price.compareTo(b.price));
      return inStock.first;
    }
    // Fall back to first (even if OOS)
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

class InlineProductCountdown extends StatefulWidget {
  final DateTime endDateTime;
  const InlineProductCountdown({super.key, required this.endDateTime});

  @override
  State<InlineProductCountdown> createState() => _InlineProductCountdownState();
}

class _InlineProductCountdownState extends State<InlineProductCountdown> {
  late Timer _timer;
  late Duration _timeLeft;

  @override
  void initState() {
    super.initState();
    _calculateTimeLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _calculateTimeLeft();
        });
      }
    });
  }

  void _calculateTimeLeft() {
    _timeLeft = widget.endDateTime.difference(DateTime.now());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_timeLeft.isNegative) {
      return const SizedBox.shrink();
    }

    final hours = _timeLeft.inHours.toString().padLeft(2, '0');
    final minutes = (_timeLeft.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (_timeLeft.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.red.shade100, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: Colors.redAccent, size: 10),
          const SizedBox(width: 2),
          Text(
            '$hours:$minutes:$seconds',
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
            ),
          ),
        ],
      ),
    );
  }
}
