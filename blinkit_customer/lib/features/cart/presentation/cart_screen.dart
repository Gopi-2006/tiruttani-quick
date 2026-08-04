import 'package:blinkit_shared/blinkit_shared.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../services/settings_provider.dart';

import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_widget.dart';

import '../../../services/current_user_provider.dart';
import 'cart_provider.dart';
import '../../../config/admob_config.dart';
import '../../../widgets/banner_ad_widget.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  /// Tracks how long we've been waiting for cart to initialise.
  /// After [_cartLoadTimeoutSeconds] we show a timeout/retry UI.
  static const int _cartLoadTimeoutSeconds = 10;
  int _secondsWaited = 0;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    // Note: CartProvider self-initialises via CurrentUserProvider binding
    // established in main.dart. Do NOT call cartProvider.init() here to
    // avoid duplicate Firestore reads (race condition fix).
    _startTimeoutWatcher();
  }

  void _startTimeoutWatcher() {
    Future.delayed(const Duration(seconds: 1), _tick);
  }

  void _tick() {
    if (!mounted) return;
    final cartProvider = context.read<CartProvider>();
    if (cartProvider.isCartReady) return; // Cart loaded — stop watching

    _secondsWaited++;
    if (_secondsWaited >= _cartLoadTimeoutSeconds) {
      setState(() => _timedOut = true);
    } else {
      Future.delayed(const Duration(seconds: 1), _tick);
    }
  }

  void _retry() {
    final currentUser = context.read<CurrentUserProvider>();
    final cartProvider = context.read<CartProvider>();
    if (currentUser.firebaseUser != null) {
      setState(() {
        _timedOut = false;
        _secondsWaited = 0;
      });
      cartProvider.init(currentUser.firebaseUser!.uid);
      _startTimeoutWatcher();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<CurrentUserProvider>();
    final cartProvider = context.watch<CartProvider>();

    Widget bodyWidget;

    if (!currentUser.isAuthenticated) {
      bodyWidget = Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(AppIcons.shoppingCartOutlined, size: AppDimensions.iconSizeExtraLarge, color: AppColors.muted),
              const SizedBox(height: AppDimensions.spacingMedium),
              const Text(
                Messages.loginRequiredToCart,
                style: TextStyle(fontSize: AppDimensions.fontSizeExtraLarge, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppDimensions.spacingSmall),
              const Text(
                Messages.loginToProceedText,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: AppDimensions.spacingLarge),
              CustomButton(
                onPressed: () => context.go(AppRoutes.login),
                text: ButtonTexts.login,
              ),
            ],
          ),
        ),
      );
    } else if (_timedOut) {
      // Cart load timed out — show retry instead of infinite spinner
      bodyWidget = Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.muted),
              const SizedBox(height: AppDimensions.spacingMedium),
              const Text(
                'Cart took too long to load.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppDimensions.spacingSmall),
              const Text(
                'Please check your connection and retry.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: AppDimensions.spacingLarge),
              CustomButton(
                onPressed: _retry,
                text: 'Retry',
              ),
            ],
          ),
        ),
      );
    } else if (!ConnectivityProvider.instance.isOnline && !cartProvider.isCartReady) {
      bodyWidget = OfflinePlaceholderWidget(
        onRetrySuccess: _retry,
      );
    } else if (!cartProvider.isCartReady) {
      // Cart is loading — show spinner (only before first successful load)
      bodyWidget = const LoadingWidget();
    } else if (cartProvider.items.isEmpty) {
      bodyWidget = const EmptyState(
        message: Messages.cartEmpty,
        icon: AppIcons.shoppingCartOutlined,
      );
    } else {
      bodyWidget = Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(AppDimensions.paddingMedium),
              itemCount: cartProvider.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppDimensions.spacingNormal),
              itemBuilder: (context, index) {
                final item = cartProvider.items.elementAt(index);
                return _CartItemTile(item: item);
              },
            ),
          ),
          _CartSummary(provider: cartProvider),
        ],
      );
    }

    return Scaffold(
      appBar: const CustomAppBar(title: AppStrings.cartTitle),
      body: bodyWidget,
      bottomNavigationBar: BannerAdWidget(adUnitId: AdMobConfig.cartBannerId),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItemModel item;

  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final product = cartProvider.getProduct(item.productId);
    final langCode = context.watch<SettingsProvider>().languageCode;

    // Resolve variant-specific image (if variant is in the product cache)
    String imageUrl = product?.imageUrl ?? '';
    if (item.variantId.isNotEmpty && product != null && product.variantsEnabled) {
      final matchedVariant = product.variants.where((v) => v.id == item.variantId);
      if (matchedVariant.isNotEmpty && matchedVariant.first.imageUrl.isNotEmpty) {
        imageUrl = matchedVariant.first.imageUrl;
      }
    }

    final String productName =
        product?.getLocalizedName(langCode) ?? 'Product';
    final String variantLabel = item.variantName.isNotEmpty ? item.variantName : (item.selectedWeight.isNotEmpty ? item.selectedWeight : '');
    final String subtitle = variantLabel.isNotEmpty
        ? '$variantLabel • ₹${item.unitPrice.toStringAsFixed(0)}'
        : '₹${item.unitPrice.toStringAsFixed(0)}';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Product image
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, url, err) => _CartImagePlaceholder(),
                    )
                  : _CartImagePlaceholder(),
            ),
            const SizedBox(width: 12),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${(item.unitPrice * item.quantity).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            // Quantity controls
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => cartProvider.decrement(item),
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: const Icon(AppIcons.remove, size: 16, color: AppColors.primary),
                    ),
                  ),
                  Text(
                    '${item.quantity}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
                  ),
                  InkWell(
                    onTap: () => cartProvider.increment(item),
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: const Icon(AppIcons.add, size: 16, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      color: Colors.grey.shade100,
      child: const Icon(AppIcons.eco, color: AppColors.primary, size: 30),
    );
  }
}

class _CartSummary extends StatefulWidget {
  final CartProvider provider;

  const _CartSummary({required this.provider});

  @override
  State<_CartSummary> createState() => _CartSummaryState();
}

class _CartSummaryState extends State<_CartSummary> {
  final _couponController = TextEditingController();
  String _couponError = '';

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return Container(
      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.cardRadiusNormal)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Coupon Section
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.local_offer_outlined, color: AppColors.orange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Apply Coupon (RANUKA10, TIRUTTANI20)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.text),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            controller: _couponController,
                            decoration: InputDecoration(
                              hintText: 'Enter code',
                              hintStyle: const TextStyle(fontSize: 12),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      provider.couponCode.isNotEmpty
                          ? TextButton(
                              onPressed: () {
                                provider.clearCoupon();
                                _couponController.clear();
                                setState(() {
                                  _couponError = '';
                                });
                              },
                              child: const Text('Clear', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                            )
                          : ElevatedButton(
                              onPressed: () {
                                final val = _couponController.text.trim();
                                if (val == 'RANUKA10' || val == 'TIRUTTANI20') {
                                  provider.applyCoupon(val);
                                  setState(() {
                                    _couponError = '';
                                  });
                                } else {
                                  setState(() {
                                    _couponError = 'Invalid coupon code';
                                  });
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: const Text('Apply'),
                            ),
                    ],
                  ),
                  if (_couponError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Text(_couponError, style: const TextStyle(color: Colors.red, fontSize: 11)),
                    ),
                  if (provider.couponCode.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        'Coupon Applied: ${provider.couponCode} (₹${provider.couponDiscount.toStringAsFixed(0)} Saved!)',
                        style: const TextStyle(color: AppColors.darkGreen, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SummaryRow(label: AppStrings.subtotalHeader, value: '₹${provider.subtotal.toStringAsFixed(0)}'),
            const SizedBox(height: 6),
            if (provider.couponDiscount > 0) ...[
              _SummaryRow(
                label: 'Coupon Discount',
                value: '-₹${provider.couponDiscount.toStringAsFixed(0)}',
                isPromo: true,
              ),
              const SizedBox(height: 6),
            ],
            _SummaryRow(label: AppStrings.deliveryFeeHeader, value: provider.deliveryFee == 0 ? AppStrings.freeLabel : '₹${provider.deliveryFee.toStringAsFixed(0)}'),
            const Divider(height: 20),
            _SummaryRow(label: AppStrings.totalHeader, value: '₹${provider.total.toStringAsFixed(0)}', bold: true),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: CustomButton(
                onPressed: provider.items.isEmpty ? null : () => context.push(AppRoutes.checkout),
                text: ButtonTexts.proceedToCheckout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool isPromo;

  const _SummaryRow({required this.label, required this.value, this.bold = false, this.isPromo = false});

  @override
  Widget build(BuildContext context) {
    Color valColor = bold ? AppColors.text : (isPromo ? AppColors.darkGreen : AppColors.text);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: bold ? AppColors.text : AppColors.muted, fontWeight: bold ? FontWeight.bold : null)),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: valColor,
          ),
        ),
      ],
    );
  }
}
