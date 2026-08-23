import 'package:flutter/material.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

/// Floating in-app banner displayed at the top of the Admin UI when active unacknowledged new orders arrive.
/// Provides immediate order visibility, quick actions, and automatically syncs with NewOrderAlertManager.
class NewOrderBannerListener extends StatelessWidget {
  final Widget child;
  final Function(String orderId) onViewOrder;

  const NewOrderBannerListener({
    super.key,
    required this.child,
    required this.onViewOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: NewOrderAlertManager.instance.activeOrdersNotifier,
              builder: (context, activeOrders, _) {
                if (activeOrders.isEmpty) {
                  return const SizedBox.shrink();
                }

                // Show the latest unacknowledged order
                final latestOrder = activeOrders.last;
                final orderId = latestOrder['orderId']?.toString() ?? '';
                final orderNumber = latestOrder['orderNumber']?.toString() ?? orderId;
                final totalAmount = latestOrder['totalAmount'] as num? ?? 0.0;
                final customerName = latestOrder['customerName']?.toString() ?? 'Customer';
                final queueCount = activeOrders.length;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Material(
                    elevation: 12,
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFF1E293B), // Dark slate
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFF59E0B), // Vibrant Amber
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF59E0B),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.notifications_active,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    '🔔 NEW ORDER RECEIVED',
                                    style: TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              if (queueCount > 1)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade600,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '+${queueCount - 1} more',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Order summary info
                          Text(
                            'Order #$orderNumber • ₹${totalAmount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Placed by $customerName',
                            style: TextStyle(
                              color: Colors.grey.shade300,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    NewOrderAlertManager.instance.acknowledgeOrder(orderId);
                                    onViewOrder(orderId);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF59E0B),
                                    foregroundColor: Colors.black87,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.visibility, size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        'View Order',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () {
                                  NewOrderAlertManager.instance.acknowledgeOrder(orderId);
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: BorderSide(color: Colors.grey.shade600),
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Dismiss'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
