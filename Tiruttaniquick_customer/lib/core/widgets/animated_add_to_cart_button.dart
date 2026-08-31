import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/cart/presentation/cart_provider.dart';
import '../../services/current_user_provider.dart';

class AnimatedAddToCartButton extends StatefulWidget {
  final ProductModel product;
  final ProductVariantModel? variant;
  final CartItemModel? cartItem;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool isDark;

  const AnimatedAddToCartButton({
    super.key,
    required this.product,
    this.variant,
    required this.cartItem,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    this.isDark = false,
  });

  @override
  State<AnimatedAddToCartButton> createState() => _AnimatedAddToCartButtonState();
}

class _AnimatedAddToCartButtonState extends State<AnimatedAddToCartButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.15), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.15, end: 1.0), weight: 50),
    ]).animate(
      CurvedAnimation(
        parent: _bounceController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _triggerBounce() {
    _bounceController.reset();
    _bounceController.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedAddToCartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldQty = oldWidget.cartItem?.quantity ?? 0;
    final newQty = widget.cartItem?.quantity ?? 0;
    if (oldQty != newQty) {
      _triggerBounce();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final currentUser = context.watch<CurrentUserProvider>();
    final qty = widget.cartItem?.quantity ?? 0;
    final isOutOfStock = widget.variant != null
        ? widget.variant!.isOutOfStock
        : widget.product.isOutOfStock;

    // While the cart is still loading (first-login race window), show a small
    // spinner inside the ADD button only if user is logged in and cart is initializing.
    final bool cartInitializing = currentUser.isAuthenticated && !cartProvider.isCartReady && qty == 0;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 48, // Touch target minimum 48dp
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: qty > 0 ? AppColors.primary : Colors.transparent,
          border: Border.all(
            color: isOutOfStock ? AppColors.muted : AppColors.primary,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: qty == 0
              ? InkWell(
                  key: const ValueKey('add_btn_active'),
                  // Disable tap while cart is initializing or out of stock
                  onTap: (isOutOfStock || cartInitializing) ? null : widget.onAdd,
                  borderRadius: BorderRadius.circular(24),
                  child: Center(
                    child: cartInitializing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : Text(
                            isOutOfStock ? 'OUT' : 'ADD',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isOutOfStock ? AppColors.muted : AppColors.primary,
                              fontSize: AppDimensions.fontSizeLarge,
                            ),
                          ),
                  ),
                )
              : Row(
                  key: const ValueKey('qty_controls'),
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, color: AppColors.white),
                      onPressed: widget.onDecrement,
                      tooltip: 'Decrease quantity',
                    ),
                    Text(
                      '$qty',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.white,
                        fontSize: AppDimensions.fontSizeLarge,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: AppColors.white),
                      onPressed: widget.onIncrement,
                      tooltip: 'Increase quantity',
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
