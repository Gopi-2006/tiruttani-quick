import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/loading_widget.dart';

class OrderTrackingScreen extends StatelessWidget {
  final String orderId;

  const OrderTrackingScreen({super.key, required this.orderId});

  Future<void> _launchReviewForm(BuildContext context) async {
    final Uri url = Uri.parse(AppConstants.reviewGoogleFormUrl);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open review link: $e')),
        );
      }
    }
  }

  void _startCancelFlow(BuildContext context, OrderModel order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Order?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to cancel this order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Order', style: TextStyle(color: AppColors.primary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _CancelOrderDialog(order: order),
      );
    }
  }

  Future<void> _callDeliveryPerson(BuildContext context, String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final Uri phoneUri = Uri(scheme: 'tel', path: cleanPhone);
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open phone dialer')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening dialer: $e')),
        );
      }
    }
  }

  void _handleBack(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack(context);
      },
      child: Scaffold(
        appBar: CustomAppBar(
          title: AppStrings.orderTrackingTitle,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => _handleBack(context),
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('orders').doc(orderId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LoadingWidget();
            if (!snapshot.data!.exists) return const Center(child: Text('Order not found'));

            final order = OrderModel.fromFirestore(snapshot.data!.id, snapshot.data!.data() as Map<String, dynamic>);
            final currentUserId = FirebaseAuth.instance.currentUser?.uid;
            if (currentUserId != null && order.customerId.isNotEmpty && order.customerId != currentUserId) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppDimensions.paddingLarge),
                  child: Text(
                    'Unauthorized: This order belongs to another account.',
                    style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final bool isCancelable = order.status == OrderStatuses.pending ||
                order.status == OrderStatuses.confirmed ||
                order.status == OrderStatuses.packed;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.paddingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(order.orderNumber, style: const TextStyle(fontSize: AppDimensions.fontSizeHeader, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(order.formattedPlacedAt, style: const TextStyle(color: AppColors.muted)),
                          const SizedBox(height: AppDimensions.spacingMedium),
                          _StatusStepper(order: order),
                        ],
                      ),
                    ),
                  ),
                  if (order.deliveryPersonName != null &&
                      order.deliveryPersonName!.trim().isNotEmpty &&
                      order.deliveryPersonPhone != null &&
                      order.deliveryPersonPhone!.trim().isNotEmpty &&
                      order.status != OrderStatuses.cancelled) ...[
                    _DeliveryPartnerCard(
                      order: order,
                      onCall: () => _callDeliveryPerson(context, order.deliveryPersonPhone!),
                    ),
                  ],
                  if (isCancelable) ...[
                    const SizedBox(height: AppDimensions.spacingMedium),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _startCancelFlow(context, order),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusNormal),
                          ),
                        ),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text(
                          'Cancel Order',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                  if (order.status == OrderStatuses.cancelled) ...[
                    const SizedBox(height: AppDimensions.spacingMedium),
                    Card(
                      color: AppColors.error.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppColors.error, width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.error_outline, color: AppColors.error),
                                SizedBox(width: 8),
                                Text(
                                  'Order Cancelled',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _SummaryRow(
                              label: 'Reason',
                              value: order.cancellationReason ?? 'Not specified',
                            ),
                            _SummaryRow(
                              label: 'Cancelled By',
                              value: order.cancelledBy ?? 'Customer',
                            ),
                            _SummaryRow(
                              label: 'Cancelled At',
                              value: order.cancelledAt != null
                                  ? DateFormat('dd MMM, hh:mm a').format(order.cancelledAt!)
                                  : 'N/A',
                            ),
                            if (order.paymentMethod != 'COD') ...[
                              _SummaryRow(
                                label: 'Refund Status',
                                value: order.refundStatus ?? 'Refund Pending',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (order.status == OrderStatuses.outForDelivery || order.status == OrderStatuses.delivered) ...[
                    Builder(
                      builder: (context) {
                        final displayOtp = (order.deliveryOtp != null && order.deliveryOtp!.isNotEmpty)
                            ? order.deliveryOtp!
                            : order.verificationCode;
                        if (displayOtp.isEmpty) return const SizedBox.shrink();

                        return Column(
                          children: [
                            const SizedBox(height: AppDimensions.spacingMedium),
                            Card(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppDimensions.borderRadiusLarge),
                                side: const BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(AppIcons.vpnKey, color: AppColors.primary),
                                        const SizedBox(width: AppDimensions.spacingSmall),
                                        Expanded(
                                          child: Text(
                                            Messages.deliveryVerificationCodeHeader,
                                            style: const TextStyle(
                                              fontSize: AppDimensions.fontSizeLarge,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppDimensions.spacingNormal),
                                    Center(
                                      child: Text(
                                        displayOtp,
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 6,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: AppDimensions.spacingSmall),
                                    const Text(
                                      Messages.provideVerificationCodePrompt,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: AppDimensions.fontSizeSmall,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                  if (order.status == OrderStatuses.delivered) ...[
                    const SizedBox(height: AppDimensions.spacingMedium),
                    Card(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusLarge),
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.38), width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.star, color: Colors.amber, size: 28),
                                Icon(Icons.star, color: Colors.amber, size: 28),
                                Icon(Icons.star, color: Colors.amber, size: 28),
                                Icon(Icons.star, color: Colors.amber, size: 28),
                                Icon(Icons.star, color: Colors.amber, size: 28),
                              ],
                            ),
                            const SizedBox(height: AppDimensions.spacingSmall),
                            const Text(
                              'How was your experience?',
                              style: TextStyle(
                                fontSize: AppDimensions.fontSizeLarge,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Your feedback helps us make Quick Grocery better!',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: AppDimensions.fontSizeSmall,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppDimensions.spacingMedium),
                            ElevatedButton.icon(
                              onPressed: () => _launchReviewForm(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppDimensions.borderRadiusNormal),
                                ),
                              ),
                              icon: const Icon(Icons.rate_review, size: 18),
                              label: const Text('Write a Review'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppDimensions.spacingMedium),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(AppStrings.orderSummaryHeader, style: TextStyle(fontSize: AppDimensions.fontSizeExtraLarge, fontWeight: FontWeight.bold)),
                          const Divider(),
                          _SummaryRow(label: Labels.payment, value: order.paymentMethod == 'COD' ? 'Cash/UPI on Delivery' : order.paymentMethod),
                          _SummaryRow(label: Labels.paymentStatus, value: order.paymentStatus),
                          _SummaryRow(label: AppStrings.totalHeader, value: '₹${order.totalPrice.toStringAsFixed(0)}'),
                          _SummaryRow(label: Labels.eta, value: order.eta != null ? 'Around ${order.eta!.hour}:${order.eta!.minute.toString().padLeft(2, '0')}' : '30 min'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CancelOrderDialog extends StatefulWidget {
  final OrderModel order;
  const _CancelOrderDialog({required this.order});

  @override
  State<_CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<_CancelOrderDialog> {
  String? _selectedReason;
  final _otherReasonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final List<String> _reasons = [
    'Ordered by mistake',
    'Found a better price',
    'Delivery taking too long',
    'Changed my mind',
    'Wrong address',
    'Duplicate order',
    'Other',
  ];

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel Order?', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Please select a reason for cancellation:',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: _selectedReason,
                onChanged: (val) {
                  setState(() {
                    _selectedReason = val;
                  });
                },
                child: Column(
                  children: _reasons.map((reason) {
                    return RadioListTile<String>(
                      title: Text(reason, style: const TextStyle(fontSize: 14)),
                      value: reason,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.error,
                    );
                  }).toList(),
                ),
              ),
              if (_selectedReason == 'Other') ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _otherReasonController,
                  decoration: const InputDecoration(
                    labelText: 'Specify reason',
                    hintText: 'Enter cancellation reason...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  validator: (value) {
                    if (_selectedReason == 'Other' && (value == null || value.trim().isEmpty)) {
                      return 'Please specify your reason';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Keep Order', style: TextStyle(color: AppColors.primary)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitCancellation,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('Cancel Order'),
        ),
      ],
    );
  }

  Future<void> _submitCancellation() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a cancellation reason.')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final finalReason = _selectedReason == 'Other'
          ? _otherReasonController.text.trim()
          : _selectedReason!;

      final firestore = context.read<FirestoreService>();
      
      // Execute cancel order in Firestore transaction
      await firestore.cancelOrder(
        orderId: widget.order.id,
        customerId: widget.order.customerId,
        reason: finalReason,
        cancelledBy: 'Customer',
      );

      // Create notification for Customer
      await firestore.createNotification(
        userId: widget.order.customerId,
        title: 'Order Cancelled Successfully',
        body: 'Your order #${widget.order.orderNumber} has been cancelled.',
        orderId: widget.order.id,
      );

      // Online payment check
      final isOnlinePayment = widget.order.paymentMethod != 'COD';
      if (isOnlinePayment) {
        await firestore.createNotification(
          userId: widget.order.customerId,
          title: 'Refund Initiated',
          body: 'Refund for order #${widget.order.orderNumber} has been initiated.',
          orderId: widget.order.id,
        );
      }

      // Create notifications for Admins
      final admins = await firestore.getAdmins();
      for (final admin in admins) {
        final adminId = admin['id'] as String?;
        if (adminId != null) {
          await firestore.createNotification(
            userId: adminId,
            title: 'Customer Cancelled Order',
            body: 'Order #${widget.order.orderNumber} was cancelled by the customer.',
            orderId: widget.order.id,
          );
        }
      }

      if (mounted) {
        Navigator.pop(context, true); // Dismiss dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel order: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

class _StatusStepper extends StatelessWidget {
  final OrderModel order;

  const _StatusStepper({required this.order});

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('dd MMM, hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    if (order.status == OrderStatuses.cancelled) {
      // Canceled Timeline
      final steps = [
        _StepData(
          label: 'Order Placed',
          active: true,
          color: Colors.green,
          time: _formatTime(order.placedAt),
          icon: Icons.check,
        ),
        _StepData(
          label: 'Accepted',
          active: order.confirmedAt != null,
          color: Colors.blue,
          time: _formatTime(order.confirmedAt),
          icon: Icons.check,
        ),
        _StepData(
          label: 'Packing',
          active: order.packedAt != null,
          color: Colors.orange,
          time: _formatTime(order.packedAt),
          icon: Icons.check,
        ),
        _StepData(
          label: 'Cancelled',
          active: true,
          color: Colors.red,
          time: _formatTime(order.cancelledAt),
          icon: Icons.cancel_outlined,
        ),
      ];

      return _buildTimeline(steps);
    } else {
      // Normal Timeline
      final steps = [
        _StepData(
          label: 'Order Placed',
          active: order.statusIndex >= 1,
          color: Colors.green,
          time: _formatTime(order.placedAt),
          icon: Icons.check,
        ),
        _StepData(
          label: 'Accepted',
          active: order.statusIndex >= 2,
          color: Colors.blue,
          time: _formatTime(order.confirmedAt),
          icon: Icons.check,
        ),
        _StepData(
          label: 'Packing',
          active: order.statusIndex >= 3,
          color: Colors.orange,
          time: _formatTime(order.packedAt),
          icon: Icons.check,
        ),
        _StepData(
          label: 'Out for Delivery',
          active: order.statusIndex >= 4,
          color: Colors.purple,
          time: _formatTime(order.outForDeliveryAt),
          icon: Icons.local_shipping,
        ),
        _StepData(
          label: 'Delivered',
          active: order.statusIndex >= 5,
          color: Colors.green,
          time: _formatTime(order.deliveredAt),
          icon: Icons.sports_motorsports,
        ),
      ];

      return _buildTimeline(steps);
    }
  }

  Widget _buildTimeline(List<_StepData> steps) {
    return Column(
      children: List.generate(steps.length, (index) {
        final step = steps[index];
        final showLine = index < steps.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: step.active ? step.color : AppColors.border,
                    child: Icon(
                      step.icon,
                      size: 16,
                      color: step.active ? Colors.white : AppColors.muted,
                    ),
                  ),
                  if (showLine)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: step.active && (index + 1 < steps.length && steps[index + 1].active)
                            ? steps[index + 1].color
                            : AppColors.border,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppDimensions.spacingNormal),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppDimensions.paddingMedium),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.label,
                        style: TextStyle(
                          fontWeight: step.active ? FontWeight.bold : FontWeight.normal,
                          color: step.active ? AppColors.text : AppColors.muted,
                          fontSize: 14,
                        ),
                      ),
                      if (step.time.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          step.time,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _StepData {
  final String label;
  final bool active;
  final Color color;
  final String time;
  final IconData icon;

  _StepData({
    required this.label,
    required this.active,
    required this.color,
    required this.time,
    required this.icon,
  });
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryPartnerCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback? onCall;

  const _DeliveryPartnerCard({required this.order, this.onCall});

  @override
  Widget build(BuildContext context) {
    final name = order.deliveryPersonName?.trim() ?? '';
    final phone = order.deliveryPersonPhone?.trim() ?? '';

    if (name.isEmpty || phone.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: AppDimensions.spacingMedium),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusLarge),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.25), width: 1.2),
          ),
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.paddingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delivery_dining,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Delivery Partner',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            'Assigned for your delivery',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.phone, size: 14, color: AppColors.muted),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  phone,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (onCall != null && phone.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: onCall,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusNormal),
                          ),
                        ),
                        icon: const Icon(Icons.call, size: 16),
                        label: const Text(
                          'Call',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

  
