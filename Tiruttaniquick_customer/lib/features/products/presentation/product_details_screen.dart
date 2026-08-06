import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../services/startup_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/product_card.dart';
import '../../../services/current_user_provider.dart';
import '../../cart/presentation/cart_provider.dart';
import '../../../services/settings_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────

class ProductDetailsScreen extends StatefulWidget {
  final String productId;
  final String? selectedBarcode;
  final String? selectedVariantId;

  const ProductDetailsScreen({
    super.key,
    required this.productId,
    this.selectedBarcode,
    this.selectedVariantId,
  });

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  ProductVariantModel? _selectedVariant;
  bool _initializedVariant = false;

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _launchReviewForm(BuildContext context) async {
    final Uri url = Uri.parse(AppConstants.reviewGoogleFormUrl);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open review link: $e')),
        );
      }
    }
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

  // ── Variant bottom-sheet ──────────────────────────────────────────────────

  void _showVariantSheet(BuildContext context, ProductModel product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _VariantBottomSheet(
          product: product,
          selectedVariant: _selectedVariant,
          onVariantSelected: (v) {
            setState(() => _selectedVariant = v);
            Navigator.pop(context);
          },
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final firestore = context.read<FirestoreService>();
    final cartProvider = context.watch<CartProvider>();
    final currentUser = context.read<CurrentUserProvider>();

    return StreamBuilder<ProductModel>(
      stream: firestore.productStream(widget.productId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (!ConnectivityProvider.instance.isOnline) {
            return Scaffold(
              appBar: const CustomAppBar(title: 'Offline'),
              body: OfflinePlaceholderWidget(
                onRetrySuccess: () {},
              ),
            );
          }
          return const Scaffold(
            appBar: CustomAppBar(title: 'Loading...'),
            body: Center(child: LoadingWidget()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.isActive) {
          if (!ConnectivityProvider.instance.isOnline && (!snapshot.hasData || snapshot.hasError)) {
            return Scaffold(
              appBar: const CustomAppBar(title: 'Offline'),
              body: OfflinePlaceholderWidget(
                onRetrySuccess: () {},
              ),
            );
          }
          return const Scaffold(
            appBar: CustomAppBar(title: 'Unavailable'),
            body: Center(
              child: Text(
                'This product is currently unavailable.',
                style: TextStyle(fontSize: 16, color: AppColors.muted),
              ),
            ),
          );
        }

        final rawProduct = snapshot.data!;
        final product = context.watch<StartupProvider>().applyOffersToSingle(rawProduct);

        // ── Variant init (runs once) ────────────────────────────────────
        if (!_initializedVariant) {
          _initializedVariant = true;
          if (product.variantsEnabled && product.variants.isNotEmpty) {
            if (widget.selectedBarcode != null && widget.selectedBarcode!.isNotEmpty) {
              final match = product.variants.where((v) => v.barcode == widget.selectedBarcode);
              _selectedVariant = match.isNotEmpty ? match.first : product.variants.first;
            } else if (widget.selectedVariantId != null && widget.selectedVariantId!.isNotEmpty) {
              final match = product.variants.where((v) => v.id == widget.selectedVariantId);
              _selectedVariant = match.isNotEmpty ? match.first : product.variants.first;
            } else {
              // Pick cheapest in-stock
              final inStock = product.variants.where((v) => !v.isOutOfStock).toList()
                ..sort((a, b) => a.price.compareTo(b.price));
              _selectedVariant = inStock.isNotEmpty ? inStock.first : product.variants.first;
            }
          }
        }

        // ── Derived state ───────────────────────────────────────────────
        final bool isVariant = product.variantsEnabled && _selectedVariant != null;
        final ProductVariantModel? currentVariant = isVariant 
            ? product.variants.firstWhere((v) => v.id == _selectedVariant!.id, orElse: () => _selectedVariant!)
            : null;

        final double displayPrice = isVariant ? currentVariant!.price : product.price;
        final double mrpVal = isVariant
            ? currentVariant!.mrp
            : (product.mrp > 0 ? product.mrp : product.price);
        final int discountPct =
            mrpVal > displayPrice ? (((mrpVal - displayPrice) / mrpVal) * 100).round() : 0;

        final String displayImage =
            (isVariant && currentVariant!.imageUrl.isNotEmpty)
                ? currentVariant.imageUrl
                : product.imageUrl;

        // Stock
        bool isOutOfStock = false;
        String stockText = 'In Stock';
        Color stockColor = AppColors.primary;
        if (isVariant && currentVariant != null) {
          isOutOfStock = currentVariant.isOutOfStock;
          if (isOutOfStock) {
            stockText = 'Out of Stock';
            stockColor = AppColors.error;
          } else if (currentVariant.isLowStock) {
            stockText = 'Only ${currentVariant.stockQuantity} left';
            stockColor = AppColors.orange;
          }
        } else {
          isOutOfStock = product.isOutOfStock;
          if (isOutOfStock) {
            stockText = 'Out of Stock';
            stockColor = AppColors.error;
          } else if (product.isLowStock) {
            stockText = 'Only ${product.stockQuantity} left';
            stockColor = AppColors.orange;
          }
        }

        // Cart item
        CartItemModel? cartItem;
        final currentVariantId = product.variantsEnabled ? (_selectedVariant?.id ?? '') : '';
        for (final item in cartProvider.items) {
          if (item.productId == product.id && item.variantId == currentVariantId) {
            cartItem = item;
            break;
          }
        }

        final langCode = context.watch<SettingsProvider>().languageCode;

        return Scaffold(
          appBar: CustomAppBar(
            title: product.getLocalizedName(langCode),
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero Image ──────────────────────────────────────────
                Hero(
                  tag: 'product-img-${product.id}',
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                    child: Container(
                      key: ValueKey(displayImage),
                      width: double.infinity,
                      height: 280,
                      color: Colors.white,
                      child: Center(
                        child: CachedNetworkImage(
                          imageUrl: displayImage,
                          fit: BoxFit.contain,
                          height: 240,
                          placeholder: (ctx, url) => const Center(
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          ),
                          errorWidget: (ctx, url, e) => const Icon(AppIcons.eco, size: 64, color: AppColors.primary),
                        ),
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Brand ─────────────────────────────────────────
                      if (product.brand.isNotEmpty)
                        Text(
                          product.brand.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      const SizedBox(height: 4),

                      // ── Name + Discount badge ─────────────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              product.getLocalizedName(langCode),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          if (discountPct > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.orange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$discountPct% OFF',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ── Price row ─────────────────────────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '₹${displayPrice.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text,
                            ),
                          ),
                          if (mrpVal > displayPrice) ...[
                            const SizedBox(width: 8),
                            Text(
                              '₹${mrpVal.toStringAsFixed(0)}',
                              style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: AppColors.muted,
                                fontSize: 16,
                              ),
                            ),
                          ],
                          const Spacer(),
                          _StockBadge(text: stockText, color: stockColor),
                        ],
                      ),
                      
                      // Live Countdown Banner for Active Promotions
                      if (isVariant ? (currentVariant?.appliedOfferEndsAt != null && currentVariant?.appliedOfferCountdownEnabled == true) : (product.appliedOfferEndsAt != null && product.appliedOfferCountdownEnabled == true)) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200, width: 0.8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (isVariant ? currentVariant?.appliedOfferTitle : product.appliedOfferTitle) ?? 'Special Deal',
                                      style: TextStyle(
                                        color: Colors.orange.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const Text(
                                      'Grab this limited-time offer!',
                                      style: TextStyle(
                                        color: Colors.black54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              LargeProductCountdown(
                                endDateTime: (isVariant ? currentVariant!.appliedOfferEndsAt : product.appliedOfferEndsAt)!,
                              ),
                            ],
                          ),
                        ),
                      ],

                      // ── Delivery estimate ─────────────────────────────
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.flash_on_rounded, color: AppColors.primary, size: 16),
                          const SizedBox(width: 4),
                          const Text(
                            'Delivery in ',
                            style: TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                          Text(
                            '30 – 60 min',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const Divider(height: 28),

                      // ── Variant Selector ──────────────────────────────
                      if (product.variantsEnabled && product.variants.isNotEmpty)
                        _VariantSelector(
                          product: product,
                          selectedVariant: _selectedVariant,
                          onVariantSelected: (v) => setState(() => _selectedVariant = v),
                          onShowAll: () => _showVariantSheet(context, product),
                        ),

                      if (product.variantsEnabled && product.variants.isNotEmpty)
                        const Divider(height: 28),

                      // ── Description ───────────────────────────────────
                      const Text(
                        'Product Description',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        product.description.isNotEmpty
                            ? product.description
                            : 'This is a premium product sourced directly from the best brands to offer high quality. Carefully packaged and sealed under hygienic conditions. Best suited for daily home consumption at Ranuka Store.',
                        style: const TextStyle(fontSize: 14, color: AppColors.text, height: 1.5),
                      ),

                      // ── Ingredients ───────────────────────────────────
                      if (product.ingredients.isNotEmpty) ...[
                        const Divider(height: 28),
                        const Text(
                          'Ingredients',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          product.ingredients,
                          style: const TextStyle(fontSize: 14, color: AppColors.text, height: 1.5),
                        ),
                      ],

                      const Divider(height: 28),

                      // ── Related Products ──────────────────────────────
                      const Text(
                        'Related Products',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<List<ProductModel>>(
                        stream: firestore.productsStream(categoryId: product.categoryId),
                        builder: (context, snap) {
                          if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
                          final related = snap.data!.where((p) => p.id != product.id).toList();
                          if (related.isEmpty) return const SizedBox.shrink();
                          return SizedBox(
                            height: 230,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: related.length,
                              separatorBuilder: (context, index) => const SizedBox(width: 12),
                              itemBuilder: (context, i) => SizedBox(
                                width: 145,
                                child: ProductCard(product: related[i]),
                              ),
                            ),
                          );
                        },
                      ),

                      const Divider(height: 28),

                      // ── Reviews ───────────────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Customer Reviews',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 20),
                              const SizedBox(width: 4),
                              const Text('4.6', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(width: 4),
                              Text(
                                '(18)',
                                style: TextStyle(color: AppColors.muted.withAlpha(200), fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Write Review
                      Card(
                        color: AppColors.primary.withAlpha(12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppColors.primary.withAlpha(38)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Have you tried this product?',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Share your feedback to help other Ranuka Store shoppers.',
                                style: TextStyle(color: AppColors.muted, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () => _launchReviewForm(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.rate_review, size: 18),
                                label: const Text('Write a Review'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      _buildReviewItem(
                        author: 'Ramesh K.',
                        rating: 5,
                        comment: 'Fresh quality and lightning-fast delivery in Tiruttani! Loved the packaging.',
                        date: '1 day ago',
                      ),
                      _buildReviewItem(
                        author: 'Saraswathi A.',
                        rating: 4,
                        comment: 'Good products, helpful slot delivery options. Recommend Ranuka Store.',
                        date: '5 days ago',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Sticky bottom bar ───────────────────────────────────────────
          bottomNavigationBar: _BottomActionBar(
            product: product,
            selectedVariant: _selectedVariant,
            cartItem: cartItem,
            isOutOfStock: isOutOfStock,
            onAddToCart: () {
              if (currentUser.isAuthenticated) {
                if (cartItem == null) {
                  cartProvider.add(product, variant: isVariant ? _selectedVariant : null);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('✓ Added to Cart!'),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              } else {
                _showLoginPrompt(context);
              }
            },
            onBuyNow: () {
              if (currentUser.isAuthenticated) {
                if (cartItem == null) {
                  cartProvider.add(product, variant: isVariant ? _selectedVariant : null);
                }
                context.push(AppRoutes.cart);
              } else {
                _showLoginPrompt(context);
              }
            },
            onIncrement: cartItem != null ? () => cartProvider.increment(cartItem!) : null,
            onDecrement: cartItem != null ? () => cartProvider.decrement(cartItem!) : null,
          ),
        );
      },
    );
  }

  Widget _buildReviewItem({
    required String author,
    required int rating,
    required String comment,
    required String date,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.primary.withAlpha(25),
                child: Text(
                  author[0].toUpperCase(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 8),
              Text(author, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Text(date, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: List.generate(
              5,
              (i) => Icon(i < rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 13),
            ),
          ),
          const SizedBox(height: 4),
          Text(comment, style: const TextStyle(color: AppColors.text, fontSize: 12)),
          const SizedBox(height: 6),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Variant Selector (inline chips + "See All" link)
// ─────────────────────────────────────────────────────────────────────────────

class _VariantSelector extends StatelessWidget {
  final ProductModel product;
  final ProductVariantModel? selectedVariant;
  final ValueChanged<ProductVariantModel> onVariantSelected;
  final VoidCallback onShowAll;

  const _VariantSelector({
    required this.product,
    required this.selectedVariant,
    required this.onVariantSelected,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final variants = product.variants;
    const maxVisible = 4;
    final showSeeAll = variants.length > maxVisible;
    final visible = showSeeAll ? variants.take(maxVisible).toList() : variants;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Text(
              'Select Variant',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
            ),
            const Spacer(),
            if (showSeeAll)
              TextButton(
                onPressed: onShowAll,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'See all ${variants.length} →',
                  style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Chip row
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...visible.map((v) => _VariantChip(
                  variant: v,
                  isSelected: selectedVariant?.id == v.id,
                  onTap: v.isOutOfStock ? null : () => onVariantSelected(v),
                )),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single Variant Chip (Flipkart style)
// ─────────────────────────────────────────────────────────────────────────────

class _VariantChip extends StatelessWidget {
  final ProductVariantModel variant;
  final bool isSelected;
  final VoidCallback? onTap;

  const _VariantChip({required this.variant, required this.isSelected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool oos = variant.isOutOfStock;

    Color borderColor;
    Color bgColor;
    Color textColor;

    if (oos) {
      borderColor = Colors.grey.shade300;
      bgColor = Colors.grey.shade100;
      textColor = Colors.grey.shade400;
    } else if (isSelected) {
      borderColor = AppColors.primary;
      bgColor = AppColors.primary.withValues(alpha: 0.08);
      textColor = AppColors.primary;
    } else {
      borderColor = AppColors.border;
      bgColor = Colors.white;
      textColor = AppColors.text;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              variant.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: textColor,
                decoration: oos ? TextDecoration.lineThrough : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              oos ? 'Out of Stock' : '₹${variant.price.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 12,
                color: oos ? Colors.grey.shade400 : (isSelected ? AppColors.primary : AppColors.muted),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Variant Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _VariantBottomSheet extends StatelessWidget {
  final ProductModel product;
  final ProductVariantModel? selectedVariant;
  final ValueChanged<ProductVariantModel> onVariantSelected;

  const _VariantBottomSheet({
    required this.product,
    required this.selectedVariant,
    required this.onVariantSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // List
          LimitedBox(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: product.variants.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final v = product.variants[i];
                final bool isSelected = selectedVariant?.id == v.id;
                final bool oos = v.isOutOfStock;
                final double savePct = v.mrp > v.price && v.mrp > 0
                    ? (((v.mrp - v.price) / v.mrp) * 100)
                    : 0;

                return GestureDetector(
                  onTap: oos ? null : () => onVariantSelected(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary.withValues(alpha: 0.06) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : Colors.grey.shade200,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Variant image
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: v.imageUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: v.imageUrl,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.contain,
                                  errorWidget: (ctx, url, err) => _VariantPlaceholder(),
                                )
                              : _VariantPlaceholder(),
                        ),
                        const SizedBox(width: 12),
                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: oos ? Colors.grey : AppColors.text,
                                  decoration: oos ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    '₹${v.price.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: oos ? Colors.grey : AppColors.text,
                                    ),
                                  ),
                                  if (v.mrp > v.price) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '₹${v.mrp.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        decoration: TextDecoration.lineThrough,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                  if (savePct > 0) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.orange,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${savePct.round()}% OFF',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                oos
                                    ? 'Out of Stock'
                                    : (v.stockQuantity <= (v.lowStockThreshold > 0 ? v.lowStockThreshold : 5)
                                        ? 'Only ${v.stockQuantity} left'
                                        : 'In Stock'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: oos
                                      ? AppColors.error
                                      : (v.stockQuantity <= (v.lowStockThreshold > 0 ? v.lowStockThreshold : 5)
                                          ? AppColors.orange
                                          : AppColors.primary),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Selection indicator
                        if (isSelected)
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, color: Colors.white, size: 14),
                          )
                        else if (!oos)
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300, width: 1.5),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _VariantPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      color: Colors.grey.shade100,
      child: const Icon(AppIcons.eco, color: AppColors.primary, size: 28),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Action Bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  final ProductModel product;
  final ProductVariantModel? selectedVariant;
  final CartItemModel? cartItem;
  final bool isOutOfStock;
  final VoidCallback onAddToCart;
  final VoidCallback onBuyNow;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  const _BottomActionBar({
    required this.product,
    required this.selectedVariant,
    required this.cartItem,
    required this.isOutOfStock,
    required this.onAddToCart,
    required this.onBuyNow,
    this.onIncrement,
    this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final int qty = cartItem?.quantity ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // ── Add to Cart / quantity ──────────────────────────────────
            Expanded(
              child: isOutOfStock
                  ? OutlinedButton(
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.grey, width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Out of Stock',
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    )
                  : qty > 0
                      ? // Inline quantity control
                        Container(
                          height: 50,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.primary, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              InkWell(
                                onTap: onDecrement,
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                                child: Container(
                                  width: 44,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.remove, color: AppColors.primary, size: 20),
                                ),
                              ),
                              Text(
                                '$qty',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  color: AppColors.primary,
                                ),
                              ),
                              InkWell(
                                onTap: onIncrement,
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                                child: Container(
                                  width: 44,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.add, color: AppColors.primary, size: 20),
                                ),
                              ),
                            ],
                          ),
                        )
                      : OutlinedButton(
                          onPressed: onAddToCart,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primary, width: 2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Add to Cart',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
            ),
            const SizedBox(width: 12),

            // ── Buy Now ─────────────────────────────────────────────────
            Expanded(
              child: ElevatedButton(
                onPressed: isOutOfStock ? null : onBuyNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isOutOfStock ? Colors.grey : AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: const Text(
                  'Buy Now',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stock Badge
// ─────────────────────────────────────────────────────────────────────────────

class _StockBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _StockBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

class LargeProductCountdown extends StatefulWidget {
  final DateTime endDateTime;
  const LargeProductCountdown({super.key, required this.endDateTime});

  @override
  State<LargeProductCountdown> createState() => _LargeProductCountdownState();
}

class _LargeProductCountdownState extends State<LargeProductCountdown> {
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.redAccent.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '$hours:$minutes:$seconds',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFamily: 'Courier',
        ),
      ),
    );
  }
}
