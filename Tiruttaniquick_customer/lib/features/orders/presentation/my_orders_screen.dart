import 'dart:async';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/admob_config.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../services/current_user_provider.dart';
import '../../../widgets/banner_ad_widget.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController.addListener(() {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted) {
          setState(() {
            _searchQuery = _searchController.text.trim();
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _launchReviewForm() async {
    final Uri url = Uri.parse(AppConstants.reviewGoogleFormUrl);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open review link: $e')),
        );
      }
    }
  }

  Future<void> _refreshOrders() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {});
    }
  }

  List<OrderModel> _filterOrders(List<OrderModel> orders, int tabIndex) {
    List<OrderModel> filtered = orders;

    // Filter by tab
    if (tabIndex == 1) {
      // Ongoing: pending, confirmed, packed, out_for_delivery
      filtered = filtered.where((o) =>
          o.status != OrderStatuses.delivered && o.status != OrderStatuses.cancelled).toList();
    } else if (tabIndex == 2) {
      // Delivered
      filtered = filtered.where((o) => o.status == OrderStatuses.delivered).toList();
    } else if (tabIndex == 3) {
      // Cancelled
      filtered = filtered.where((o) => o.status == OrderStatuses.cancelled).toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((o) {
        final orderNum = o.orderNumber.toLowerCase();
        final status = _getDisplayStatus(o.status).toLowerCase();
        final date = o.formattedPlacedAt.toLowerCase();
        final id = o.id.toLowerCase();
        return orderNum.contains(q) || status.contains(q) || date.contains(q) || id.contains(q);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<CurrentUserProvider>();
    final firestore = context.read<FirestoreService>();

    if (currentUser.firebaseUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My Orders', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text)),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.paddingLarge),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(AppIcons.ordersOutlined, size: AppDimensions.iconSizeExtraLarge, color: AppColors.muted),
                const SizedBox(height: AppDimensions.spacingMedium),
                const Text(
                  Messages.loginRequiredToOrders,
                  style: TextStyle(fontSize: AppDimensions.fontSizeExtraLarge, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppDimensions.spacingSmall),
                const Text(
                  Messages.loginToTrackOrdersText,
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
        ),
        bottomNavigationBar: BannerAdWidget(adUnitId: AdMobConfig.ordersBannerId),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search order ID, status...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: AppColors.muted, fontSize: 15),
                ),
                style: const TextStyle(fontSize: 16, color: AppColors.text),
              )
            : const Text(
                'My Orders',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: AppColors.primary,
              size: 24,
            ),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              labelColor: AppColors.primary,
              unselectedLabelColor: const Color(0xFF6C757D),
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              tabs: const [
                Tab(text: 'All Orders'),
                Tab(text: 'Ongoing'),
                Tab(text: 'Delivered'),
                Tab(text: 'Cancelled'),
              ],
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<OrderModel>>(
        stream: firestore.userOrdersStream(currentUser.firebaseUser!.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
            if (!ConnectivityProvider.instance.isOnline) {
              return OfflinePlaceholderWidget(
                onRetrySuccess: _refreshOrders,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => const OrderSkeletonCard(),
            );
          }

          final allOrders = snapshot.data ?? [];

          return TabBarView(
            controller: _tabController,
            children: List.generate(4, (tabIndex) {
              final orders = _filterOrders(allOrders, tabIndex);

              if (orders.isEmpty) {
                return RefreshIndicator(
                  onRefresh: _refreshOrders,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                      EmptyState(
                        message: _searchQuery.isNotEmpty
                            ? 'No orders matching "$_searchQuery"'
                            : _getEmptyMessageForTab(tabIndex),
                        icon: AppIcons.inbox,
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: _refreshOrders,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return _OrderCard(
                      order: order,
                      onReview: _launchReviewForm,
                    );
                  },
                ),
              );
            }),
          );
        },
      ),
      bottomNavigationBar: BannerAdWidget(adUnitId: AdMobConfig.ordersBannerId),
    );
  }

  String _getEmptyMessageForTab(int tabIndex) {
    switch (tabIndex) {
      case 1:
        return 'No ongoing orders right now';
      case 2:
        return 'No delivered orders yet';
      case 3:
        return 'No cancelled orders';
      default:
        return Messages.noOrders;
    }
  }
}

class _OrderCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onReview;

  const _OrderCard({
    required this.order,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusTextColor(order.status);
    final statusBgColor = _getStatusBgColor(order.status);
    final displayStatus = _getDisplayStatus(order.status);

    return InkWell(
      onTap: () => context.push('${AppRoutes.myOrders}/${order.id}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEFEFEF), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Order ID & Status Badge + Chevron
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Order ID',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF888888),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.orderNumber,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusBgColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        displayStatus,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: Color(0xFF9CA3AF),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Date & Time
            Text(
              order.formattedPlacedAt,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 12),

            // Total & View Details Button Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                    children: [
                      const TextSpan(text: 'Total: '),
                      TextSpan(
                        text: '₹${order.totalPrice.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: statusColor == AppColors.error
                              ? AppColors.primary
                              : statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => context.push('${AppRoutes.myOrders}/${order.id}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 18,
                          color: statusColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'View Details',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Visual Progress Tracker (if not cancelled)
            if (order.status != OrderStatuses.cancelled) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              const SizedBox(height: 14),
              _OrderStepProgressTracker(order: order),
            ],

            // Review button if delivered
            if (order.status == OrderStatuses.delivered) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onReview,
                    icon: const Icon(Icons.rate_review_outlined, size: 16),
                    label: const Text('Review Order', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderStepProgressTracker extends StatelessWidget {
  final OrderModel order;

  const _OrderStepProgressTracker({required this.order});

  @override
  Widget build(BuildContext context) {
    // 4 Steps: Placed, Confirmed, Out for Delivery, Delivered
    final int currentStepIndex = _calculateStepIndex(order.status);

    final steps = [
      _StepInfo('Placed', Icons.local_mall_outlined, order.placedAt),
      _StepInfo('Confirmed', Icons.shopping_bag_outlined, order.confirmedAt ?? order.placedAt),
      _StepInfo('Out for Delivery', Icons.local_shipping_outlined, order.outForDeliveryAt),
      _StepInfo('Delivered', Icons.check, order.deliveredAt),
    ];

    return Row(
      children: List.generate(steps.length * 2 - 1, (index) {
        if (index.isOdd) {
          // Connecting Line
          final stepBeforeIndex = index ~/ 2;
          final isCompleted = stepBeforeIndex < currentStepIndex;

          return Expanded(
            child: Container(
              height: 2,
              color: isCompleted ? AppColors.primary : const Color(0xFFE5E7EB),
            ),
          );
        }

        // Step Node
        final stepIndex = index ~/ 2;
        final step = steps[stepIndex];
        final isReached = stepIndex <= currentStepIndex;
        final isCurrent = stepIndex == currentStepIndex;

        return Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isReached ? AppColors.primary : const Color(0xFFE5E7EB),
              ),
              child: Icon(
                stepIndex == 3 && isReached ? Icons.check : step.icon,
                size: 16,
                color: isReached ? Colors.white : const Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              step.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                color: isReached ? const Color(0xFF1F2937) : const Color(0xFF9CA3AF),
              ),
            ),
            if (step.timestamp != null && isReached) ...[
              const SizedBox(height: 2),
              Text(
                DateFormat('dd MMM, hh:mm a').format(step.timestamp!),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 8.5,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }

  int _calculateStepIndex(String status) {
    switch (status) {
      case OrderStatuses.pending:
        return 0;
      case OrderStatuses.confirmed:
      case OrderStatuses.packed:
        return 1;
      case OrderStatuses.outForDelivery:
        return 2;
      case OrderStatuses.delivered:
        return 3;
      default:
        return 0;
    }
  }
}

class _StepInfo {
  final String title;
  final IconData icon;
  final DateTime? timestamp;

  _StepInfo(this.title, this.icon, this.timestamp);
}

Color _getStatusTextColor(String status) {
  switch (status) {
    case OrderStatuses.delivered:
      return const Color(0xFF1E7E34); // Green
    case OrderStatuses.outForDelivery:
      return const Color(0xFF0369A1); // Sky blue
    case OrderStatuses.cancelled:
      return const Color(0xFFD32F2F); // Red
    case OrderStatuses.pending:
    case OrderStatuses.confirmed:
    case OrderStatuses.packed:
    default:
      return const Color(0xFFD97706); // Amber / Orange
  }
}

Color _getStatusBgColor(String status) {
  switch (status) {
    case OrderStatuses.delivered:
      return const Color(0xFFE8F5E9);
    case OrderStatuses.outForDelivery:
      return const Color(0xFFE0F2FE);
    case OrderStatuses.cancelled:
      return const Color(0xFFFFEBEE);
    case OrderStatuses.pending:
    case OrderStatuses.confirmed:
    case OrderStatuses.packed:
    default:
      return const Color(0xFFFFF8E1);
  }
}

String _getDisplayStatus(String status) {
  switch (status) {
    case OrderStatuses.delivered:
      return 'Delivered';
    case OrderStatuses.outForDelivery:
      return 'Out for Delivery';
    case OrderStatuses.cancelled:
      return 'Cancelled';
    case OrderStatuses.pending:
      return 'Processing';
    case OrderStatuses.confirmed:
      return 'Confirmed';
    case OrderStatuses.packed:
      return 'Packed';
    default:
      return status.isNotEmpty ? status[0].toUpperCase() + status.substring(1) : 'Processing';
  }
}
