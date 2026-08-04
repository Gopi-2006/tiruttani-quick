import 'package:blinkit_shared/blinkit_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_textfield.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/utils/helpers.dart';

import '../../../services/current_user_provider.dart';
import '../../../services/service_area_provider.dart';
import '../../../services/settings_provider.dart';
import '../../../services/admob_service.dart';

import '../../../services/location_service.dart';

import '../../cart/presentation/cart_provider.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _pincodeController = TextEditingController(text: '600001');
  final _phoneController = TextEditingController();
  String? _selectedAddressId;
  final _firestore = FirestoreService();
  final _paymentService = PaymentService();
  String _paymentMethod = PaymentMethods.cod;
  String _selectedDeliverySlot = 'Morning (8 AM - 12 PM)';
  bool _loading = false;
  bool _showSuccessOverlay = false;
  String? _successOrderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = context.read<CurrentUserProvider>().profile;
      if (profile != null && profile.phone.isNotEmpty) {
        _phoneController.text = profile.phone;
      }
    });
  }

  @override
  void dispose() {
    _addressController.dispose();
    _landmarkController.dispose();
    _pincodeController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final currentUser = context.watch<CurrentUserProvider>();

    final isOnline = ConnectivityProvider.instance.isOnline;
    if (!isOnline) {
      return Scaffold(
        appBar: const CustomAppBar(title: AppStrings.checkoutTitle),
        body: OfflinePlaceholderWidget(
          onRetrySuccess: () {
            setState(() {});
          },
        ),
      );
    }

    return Stack(
      children: [
        Scaffold(
          appBar: const CustomAppBar(title: AppStrings.checkoutTitle),
          body: currentUser.firebaseUser == null
              ? const LoadingWidget()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(AppStrings.deliveryAddressHeader, style: TextStyle(fontSize: AppDimensions.fontSizeExtraLarge, fontWeight: FontWeight.bold)),
                            const SizedBox(height: AppDimensions.spacingNormal),
                            StreamBuilder<List<AddressModel>>(
                              stream: _firestore.addressesStream(currentUser.firebaseUser!.uid),
                              builder: (context, snapshot) {
                                final addresses = snapshot.data ?? [];
                                if (addresses.isEmpty) return const Text(Messages.noSavedAddresses);
                                return Column(
                                  children: addresses.map((address) {
                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedAddressId = address.id;
                                          _addressController.text = address.fullAddress;
                                          _landmarkController.text = address.landmark;
                                          _pincodeController.text = address.pincode;
                                          _phoneController.text = address.phone;
                                        });
                                      },
                                      child: Card(
                                        margin: const EdgeInsets.only(bottom: AppDimensions.marginSmall),
                                        color: _selectedAddressId == address.id ? AppColors.primary.withValues(alpha: 0.08) : null,
                                        child: ListTile(
                                          leading: const Icon(AppIcons.location),
                                          title: Text(address.label),
                                          subtitle: Text(address.fullAddress),
                                          trailing: address.isDefault ? const Icon(AppIcons.star, color: AppColors.orange) : null,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                            const SizedBox(height: AppDimensions.spacingMedium),
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppDimensions.spacingSmall),
                              child: Text(
                                context.translate('fillManuallyNote'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.muted,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            CustomTextField(
                              controller: _addressController,
                              maxLines: 3,
                              labelText: Labels.fullAddress,
                              prefixIcon: AppIcons.home,
                              suffixIcon: IconButton(
                                icon: const Icon(AppIcons.myLocation),
                                onPressed: _getCurrentLocation,
                              ),
                              validator: (value) => value == null || value.trim().length < 5 ? ValidationMessages.enterAddress : null,
                            ),
                            const SizedBox(height: AppDimensions.spacingNormal),
                            CustomTextField(
                              controller: _landmarkController,
                              labelText: Labels.landmark,
                              prefixIcon: AppIcons.place,
                            ),
                            const SizedBox(height: AppDimensions.spacingNormal),
                            CustomTextField(
                              controller: _pincodeController,
                              keyboardType: TextInputType.number,
                              labelText: Labels.pincode,
                              prefixIcon: AppIcons.pin,
                              validator: (value) => value == null || value.trim().length != 6 ? ValidationMessages.enterPincode : null,
                            ),
                            const SizedBox(height: AppDimensions.spacingNormal),
                            CustomTextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              labelText: Labels.phoneNumber,
                              prefixIcon: AppIcons.phone,
                              validator: (value) => value == null || value.trim().length < 10 ? ValidationMessages.enterPhone : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingMedium),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select Delivery Slot',
                              style: TextStyle(fontSize: AppDimensions.fontSizeExtraLarge, fontWeight: FontWeight.bold, color: AppColors.text),
                            ),
                            const SizedBox(height: AppDimensions.spacingNormal),
                            DropdownButtonFormField<String>(
                            initialValue: _selectedDeliverySlot,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Morning (8 AM - 12 PM)', child: Text('Morning (8 AM - 12 PM)')),
                                DropdownMenuItem(value: 'Afternoon (12 PM - 4 PM)', child: Text('Afternoon (12 PM - 4 PM)')),
                                DropdownMenuItem(value: 'Evening (4 PM - 8 PM)', child: Text('Evening (4 PM - 8 PM)')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedDeliverySlot = val;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingMedium),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(AppStrings.paymentMethodHeader, style: TextStyle(fontSize: AppDimensions.fontSizeExtraLarge, fontWeight: FontWeight.bold)),
                            const SizedBox(height: AppDimensions.spacingNormal),
                            RadioGroup<String>(
                              groupValue: _paymentMethod,
                              onChanged: _setPayment,
                              child: Column(
                                children: const [
                                  _PaymentOption(value: PaymentMethods.upi),
                                  _PaymentOption(value: PaymentMethods.card),
                                  _PaymentOption(value: PaymentMethods.cod),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingMedium),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                        child: Column(
                          children: [
                            _SummaryRow(label: AppStrings.itemsHeader, value: '${cartProvider.itemCount}'),
                            _SummaryRow(label: AppStrings.subtotalHeader, value: '₹${cartProvider.subtotal.toStringAsFixed(0)}'),
                            if (cartProvider.couponDiscount > 0)
                              _SummaryRow(
                                label: 'Coupon Discount',
                                value: '-₹${cartProvider.couponDiscount.toStringAsFixed(0)}',
                              ),
                            _SummaryRow(label: AppStrings.deliveryFeeHeader, value: cartProvider.deliveryFee == 0 ? AppStrings.freeLabel : '₹${cartProvider.deliveryFee.toStringAsFixed(0)}'),
                            const Divider(),
                            _SummaryRow(label: AppStrings.totalHeader, value: '₹${cartProvider.total.toStringAsFixed(0)}', bold: true),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingLarge),
                    CustomButton(
                      onPressed: _loading ? null : _placeOrder,
                      text: ButtonTexts.placeOrder,
                      loading: _loading,
                    ),
                  ],
                ),
              ),
            ),
        ),
        if (_showSuccessOverlay)
          OrderSuccessOverlay(
            onFinished: () {
              AdMobService().showInterstitialAd(
                onFinished: () {
                  if (mounted) {
                    context.go('${AppRoutes.myOrders}/$_successOrderId');
                  }
                },
              );
            },
          ),
      ],
    );
  }

  void _setPayment(String? value) {
    if (value != null) setState(() => _paymentMethod = value);
  }

  Future<void> _getCurrentLocation() async {
    try {
      final locationService = LocationService();
      final position = await locationService.getCurrentLocation();
      if (!mounted || position == null) return;

      final address = await locationService.getAddressFromPosition(position);
      if (!mounted) return;

      setState(() {
        _addressController.text = address;
        _selectedAddressId = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not get location')));
      }
    }
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;

    final pincodeText = _pincodeController.text.trim();
    final serviceArea = Provider.of<ServiceAreaProvider>(context, listen: false);
    final isAllowed = await serviceArea.isPincodeAllowed(pincodeText);
    if (!mounted) return;
    if (!isAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("We currently do not deliver to this pincode. Order placement blocked."),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final currentUser = context.read<CurrentUserProvider>();
    final cartProvider = context.read<CartProvider>();
    final user = currentUser.firebaseUser;
    if (user == null || cartProvider.items.isEmpty) return;

    setState(() => _loading = true);

    try {
      final paymentSuccess = await _paymentService.pay(
        method: _paymentMethod,
        amountPaise: (cartProvider.total * 100).round(),
        orderId: 'new-order',
      );

      if (!paymentSuccess) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment failed')));
        return;
      }

      final db = FirebaseFirestore.instance;
      final orderRef = db.collection('orders').doc();
      final now = DateTime.now();
      final orderNumber = 'CG${now.millisecond}${now.second}${now.minute}';
      final subtotal = cartProvider.subtotal;
      final deliveryFee = cartProvider.deliveryFee;
      final total = cartProvider.total;
      String deliveryAddressId;

      int totalProductsSold = 0;
      double totalDiscountAmount = 0.0;

      await db.runTransaction((transaction) async {
        DocumentSnapshot? addressDoc;
        if (_selectedAddressId != null) {
          final addressDocRef = db.collection('addresses').doc(_selectedAddressId);
          addressDoc = await transaction.get(addressDocRef);
        }

        final List<DocumentSnapshot> productSnapshots = [];
        for (final item in cartProvider.items) {
          final productRef = db.collection('products').doc(item.productId);
          final productSnapshot = await transaction.get(productRef);
          productSnapshots.add(productSnapshot);
        }

        if (_selectedAddressId != null && addressDoc != null) {
          final addressDocRef = db.collection('addresses').doc(_selectedAddressId);
          final addressData = addressDoc.data() as Map<String, dynamic>? ?? {};
          final updated = AddressModel(
            id: addressDoc.id,
            userId: user.uid,
            label: (addressData['label'] as String?) ?? 'Home',
            fullAddress: _addressController.text.trim(),
            landmark: _landmarkController.text.trim(),
            city: (addressData['city'] as String?) ?? AppConstants.city,
            state: (addressData['state'] as String?) ?? AppConstants.state,
            pincode: _pincodeController.text.trim(),
            phone: _phoneController.text.trim(),
            isDefault: true,
          );
          transaction.set(addressDocRef, updated.toMap());
          deliveryAddressId = addressDoc.id;
        } else {
          final addressRef = db.collection('addresses').doc();
          final address = AddressModel(
            id: addressRef.id,
            userId: user.uid,
            label: 'Home',
            fullAddress: _addressController.text.trim(),
            landmark: _landmarkController.text.trim(),
            city: AppConstants.city,
            state: AppConstants.state,
            pincode: _pincodeController.text.trim(),
            phone: _phoneController.text.trim(),
            isDefault: true,
          );
          transaction.set(addressRef, address.toMap());
          deliveryAddressId = addressRef.id;
        }

        final order = OrderModel(
          id: orderRef.id,
          orderNumber: orderNumber,
          customerId: user.uid,
          deliveryAddressId: deliveryAddressId,
          subtotal: subtotal,
          deliveryFee: deliveryFee,
          totalPrice: total,
          paymentMethod: _paymentMethod,
          paymentStatus: _paymentMethod == PaymentMethods.cod ? PaymentStatuses.pending : PaymentStatuses.paid,
          status: OrderStatuses.pending,
          statusIndex: OrderStatuses.index(OrderStatuses.pending),
          eta: now.add(const Duration(minutes: 30)),
          verificationCode: Helpers.generateVerificationCode(),
        );

        transaction.set(orderRef, order.toMap());

        for (int i = 0; i < cartProvider.items.length; i++) {
          final item = cartProvider.items.elementAt(i);
          final productSnapshot = productSnapshots[i];
          final productData = productSnapshot.data() as Map<String, dynamic>? ?? {};
          
          final bool variantsEnabled = productData['variantsEnabled'] as bool? ?? false;
          final productRef = db.collection('products').doc(item.productId);
          
          double purchasePrice = 0.0;
          double mrpVal = 0.0;

          if (variantsEnabled && item.variantId.isNotEmpty) {
            final List<dynamic> rawVariants = productData['variants'] as List<dynamic>? ?? [];
            final List<Map<String, dynamic>> variantsList = List<Map<String, dynamic>>.from(
              rawVariants.map((v) => Map<String, dynamic>.from(v as Map))
            );
            
            final int variantIndex = variantsList.indexWhere((v) => v['id'] == item.variantId);
            if (variantIndex == -1) {
              throw Exception('${productData['name'] ?? 'Product'} variant not found');
            }
            
            final variant = variantsList[variantIndex];
            final int currentStock = variant['stockQuantity'] as int? ?? 0;
            purchasePrice = (variant['purchasePrice'] as num?)?.toDouble() ?? 0.0;
            mrpVal = (variant['mrp'] as num?)?.toDouble() ?? (variant['price'] as num?)?.toDouble() ?? 0.0;
            
            if (currentStock < item.quantity) {
              throw Exception('${productData['name'] ?? 'Product'} (${variant['name']}) is out of stock');
            }
            
            variant['stockQuantity'] = currentStock - item.quantity;
            if (variant['stockQuantity'] <= 0) {
              variant['status'] = 'Out of Stock';
            }
            
            transaction.update(productRef, {'variants': variantsList});
          } else {
            final int stock = productData['stockQuantity'] as int? ?? 0;
            purchasePrice = (productData['purchasePrice'] as num?)?.toDouble() ?? 0.0;
            mrpVal = (productData['mrp'] as num?)?.toDouble() ?? (productData['price'] as num?)?.toDouble() ?? 0.0;

            if (stock < item.quantity) {
              throw Exception('${productData['name'] ?? 'Product'} is out of stock');
            }

            transaction.update(productRef, {
              'stockQuantity': FieldValue.increment(-item.quantity),
            });
          }

          final itemDiscount = (mrpVal > item.unitPrice) ? (mrpVal - item.unitPrice) : 0.0;
          totalDiscountAmount += itemDiscount * item.quantity;
          totalProductsSold += item.quantity;

          final String orderItemDocId = item.variantId.isNotEmpty ? '${item.productId}_${item.variantId}' : item.productId;

          transaction.set(
            orderRef.collection('order_items').doc(orderItemDocId),
            OrderItemModel(
              id: orderItemDocId,
              orderId: orderRef.id,
              productId: item.productId,
              productName: productData['name'] as String? ?? 'Product',
              unitPrice: item.unitPrice,
              quantity: item.quantity,
              variantId: item.variantId,
              variantName: item.variantName,
              selectedWeight: item.selectedWeight,
              purchasePrice: purchasePrice,
            ).toMap(),
          );
        }

        for (final item in cartProvider.items) {
          transaction.delete(db.collection('cart_items').doc(item.id));
        }
      });

      // Record banner conversion if there was an attributed banner click
      if (cartProvider.bannerIdClicked != null) {
        final bannerId = cartProvider.bannerIdClicked!;
        await FirestoreService().recordBannerConversion(
          bannerId,
          revenue: subtotal,
          productsSold: totalProductsSold,
          discountGiven: totalDiscountAmount,
        ).catchError((err) {
          debugPrint('[Analytics] Failed to record banner conversion: $err');
        });
        // Clear click state to prevent double attribution
        cartProvider.bannerIdClicked = null;
      }

      await cartProvider.clear();
      final admins = await _firestore.getAdmins();
      final customerName = currentUser.profile?.name ?? 'Customer';
      for (final admin in admins) {
        await _firestore.createNotification(
          userId: admin['id'] as String,
          title: 'New Order Received',
          body: 'Order #$orderNumber worth ₹${total.toStringAsFixed(0)} placed by $customerName',
          orderId: orderRef.id,
        );
      }
      if (!mounted) return;
      setState(() {
        _showSuccessOverlay = true;
        _successOrderId = orderRef.id;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _PaymentOption extends StatelessWidget {
  final String value;

  const _PaymentOption({required this.value});

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      title: Text(value == PaymentMethods.cod ? 'Cash/UPI on Delivery' : value),
      value: value,
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _SummaryRow({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: bold ? AppColors.text : AppColors.muted, fontWeight: bold ? FontWeight.bold : null)),
        Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
      ],
    );
  }
}

class OrderSuccessOverlay extends StatefulWidget {
  final VoidCallback onFinished;

  const OrderSuccessOverlay({super.key, required this.onFinished});

  @override
  State<OrderSuccessOverlay> createState() => _OrderSuccessOverlayState();
}

class _OrderSuccessOverlayState extends State<OrderSuccessOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _checkAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.bounceOut),
      ),
    );

    _checkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeInOut),
      ),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2500), () {
      widget.onFinished();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white.withValues(alpha: 0.95),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: CustomPaint(
                        size: const Size(60, 60),
                        painter: _CheckPainter(_checkAnimation.value),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: AppDimensions.spacingExtraLarge),
            const Text(
              Messages.orderPlacedTitle,
              style: TextStyle(
                fontSize: AppDimensions.fontSizeTitle,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingSmall),
            const Text(
              Messages.orderPlacedSuccessText,
              style: TextStyle(
                fontSize: AppDimensions.fontSizeLarge,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double progress;

  _CheckPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(size.width * 0.2, size.height * 0.5);
    path.lineTo(size.width * 0.45, size.height * 0.75);
    path.lineTo(size.width * 0.8, size.height * 0.3);

    final pathMetrics = path.computeMetrics().toList();
    if (pathMetrics.isNotEmpty) {
      final metric = pathMetrics.first;
      final extractPath = metric.extractPath(0.0, metric.length * progress);
      canvas.drawPath(extractPath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
