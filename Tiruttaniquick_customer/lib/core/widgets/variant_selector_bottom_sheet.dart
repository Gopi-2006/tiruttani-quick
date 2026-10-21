import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

import '../../features/cart/presentation/cart_provider.dart';
import '../../services/current_user_provider.dart';
import '../../services/settings_provider.dart';
import 'animated_add_to_cart_button.dart';

/// Clean, modern bottom sheet allowing customers to view, select, and add
/// product variants directly from Home / Search / Category cards without
/// opening the full Product Details screen.
class VariantSelectorBottomSheet extends StatelessWidget {
  final ProductModel product;

  const VariantSelectorBottomSheet({
    super.key,
    required this.product,
  });

  static Future<void> show(BuildContext context, ProductModel product) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VariantSelectorBottomSheet(product: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final langCode = context.watch<SettingsProvider>().languageCode;
    final cartProvider = context.watch<CartProvider>();
    final currentUser = context.read<CurrentUserProvider>();

    final variants = product.variants;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header: Product thumbnail & name
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AppNetworkImage(
                  imageUrl: product.imageUrl,
                  blurHash: product.blurHash,
                  width: 50,
                  height: 50,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => Container(
                    width: 50,
                    height: 50,
                    color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                    child: const Icon(Icons.shopping_bag_outlined, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.getLocalizedName(langCode),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Select Option (${variants.length} available)',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkMuted : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Variants List
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: variants.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final variant = variants[index];
                final cartItem = cartProvider.getCartItem(product.id, variant.id);
                final qty = cartItem?.quantity ?? 0;
                final discountPct = (variant.mrp > variant.price && variant.mrp > 0)
                    ? (((variant.mrp - variant.price) / variant.mrp) * 100).round()
                    : 0;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? (qty > 0 ? AppColors.primary.withValues(alpha: 0.12) : const Color(0xFF222222))
                        : (qty > 0 ? AppColors.primary.withValues(alpha: 0.06) : Colors.grey.shade50),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: qty > 0
                          ? AppColors.primary
                          : (isDark ? AppColors.darkBorder : AppColors.border),
                      width: qty > 0 ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Variant info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  variant.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : AppColors.textPrimary,
                                  ),
                                ),
                                if (discountPct > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  '₹${variant.price.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                                if (variant.mrp > variant.price) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '₹${variant.mrp.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      decoration: TextDecoration.lineThrough,
                                      color: isDark ? AppColors.darkMuted : AppColors.muted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Add / Stepper
                      SizedBox(
                        width: 105,
                        child: AnimatedAddToCartButton(
                          product: product,
                          variant: variant,
                          cartItem: cartItem,
                          isDark: isDark,
                          onAdd: () {
                            if (currentUser.isAuthenticated) {
                              cartProvider.add(product, variant: variant);
                            } else {
                              Navigator.pop(context);
                              _showLoginPrompt(context);
                            }
                          },
                          onIncrement: () {
                            if (cartItem != null) {
                              cartProvider.increment(cartItem);
                            }
                          },
                          onDecrement: () {
                            if (cartItem != null) {
                              cartProvider.decrement(cartItem);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static void _showLoginPrompt(BuildContext context) {
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
