import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:intl/intl.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'add_edit_product_screen.dart';
import 'marketing_tab.dart';
import 'reports_screen.dart';
import '../../../services/file_saver.dart';
import '../../../services/current_user_provider.dart';

import '../../../core/widgets/custom_textfield.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_widget.dart';



class AdminDeliveryAvailabilityButton extends StatelessWidget {
  const AdminDeliveryAvailabilityButton({super.key});

  @override
  Widget build(BuildContext context) {
    final firestore = context.read<FirestoreService>();
    return StreamBuilder<ShopSettingsModel>(
      stream: firestore.shopSettingsStream(),
      builder: (context, snapshot) {
        final settings = snapshot.data ?? const ShopSettingsModel();
        final isAvailable = settings.deliveryAvailable;

        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _toggleDeliveryAvailability(context, firestore, isAvailable, settings),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isAvailable
                      ? const Color(0xFF10B981).withValues(alpha: 0.12)
                      : const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAvailable ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isAvailable ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isAvailable ? '🟢 Delivery ON' : '🔴 Delivery OFF',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isAvailable ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleDeliveryAvailability(
    BuildContext context,
    FirestoreService firestore,
    bool currentStatus,
    ShopSettingsModel settings,
  ) async {
    final nextStatus = !currentStatus;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(nextStatus ? 'Turn on delivery?' : 'Turn off delivery?'),
        content: Text(
          nextStatus
              ? 'Customers will be able to place new orders.'
              : 'Customers will not be able to place new orders while delivery is unavailable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: nextStatus ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(nextStatus ? 'Turn On Delivery' : 'Turn Off Delivery'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        await firestore.updateDeliveryAvailability(
          deliveryAvailable: nextStatus,
          adminUid: user.uid,
          unavailableMessage: settings.deliveryUnavailableMessage,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(nextStatus ? 'Delivery is now available.' : 'Delivery is now unavailable.'),
              backgroundColor: nextStatus ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update delivery status: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _currentTab = 0;
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPrivacyPolicy();
    });
  }

  void _checkPrivacyPolicy() {
    final userProvider = context.read<CurrentUserProvider>();
    if (userProvider.isAuthenticated && !userProvider.privacyPolicyAccepted && !_isDialogShowing) {
      _isDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final accepted = await _showPrivacyPolicyDialog(context);
        _isDialogShowing = false;
        if (accepted) {
          await userProvider.setPrivacyPolicyAccepted(true);
        } else {
          // Never log out the admin user when privacy dialog is declined or dismissed!
          // The Firebase session remains fully intact.
          debugPrint('[AdminDashboard] Privacy policy pending acceptance.');
        }
      });
    }
  }

  Future<bool> _showPrivacyPolicyDialog(BuildContext context) async {
    bool accepted = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Privacy Policy Agreement'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'To continue using the application, you must review and agree to our Privacy Policy terms.',
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final url = Uri.parse('https://ranuka-stores.neocities.org/');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: const Text(
                      'Read Privacy Policy',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.primary,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: accepted,
                        activeColor: AppColors.primary,
                        onChanged: (val) {
                          setState(() {
                            accepted = val ?? false;
                          });
                        },
                      ),
                      const Expanded(
                        child: Text('I agree to the Privacy Policy terms.'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Decline'),
                ),
                ElevatedButton(
                  onPressed: accepted
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade200,
                  ),
                  child: const Text('Accept'),
                ),
              ],
            );
          },
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.read<FirestoreService>();

    final tabs = [
      OrderReportsTab(firestore: firestore),
      _OrdersTab(firestore: firestore),
      _CatalogTab(firestore: firestore),
      _CustomersTab(firestore: firestore),
      const MarketingTab(),
    ];

    return Scaffold(
      appBar: _currentTab == 2
          ? null
          : AppBar(
              title: Text(
                _getTabTitle(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                const AdminDeliveryAvailabilityButton(),
                if (_currentTab == 1)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                    tooltip: 'Remove All Orders',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete All Orders'),
                          content: const Text(
                            'Are you sure you want to delete all orders? This will permanently delete all order documents and their items, and cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                              child: const Text('Delete All'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        if (!context.mounted) return;
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                        try {
                          await firestore.deleteAllOrders();
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('All orders removed successfully')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to delete orders: $e')),
                            );
                          }
                        }
                      }
                    },
                  ),
                IconButton(
                  icon: const Icon(AppIcons.logout),
                  tooltip: ButtonTexts.logout,
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null) {
                      await NotificationService.instance.clearToken(user.uid);
                    }
                    await AuthRepository().signOut();
                    currentUserProvider.reset();
                    if (context.mounted) {
                      context.go(AppRoutes.login);
                    }
                  },
                ),
              ],
            ),
      body: tabs[_currentTab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (index) => setState(() => _currentTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.ordersOutlined),
            selectedIcon: Icon(AppIcons.orders),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Catalog',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: 'Marketing',
          ),
        ],
      ),
    );
  }

  String _getTabTitle() {
    return switch (_currentTab) {
      0 => 'Reports & Analytics',
      1 => 'Order Management',
      2 => 'Catalog',
      3 => 'Customer Directory',
      4 => 'Marketing & Campaigns',
      _ => 'Admin Dashboard',
    };
  }

}

// Unused _AnalyticsTab removed to avoid warnings.

class SalesReportRow {
  final String productName;
  final String variantName;
  final String weight;
  final int quantitySold;
  final double revenue;
  final double profit;
  final int remainingStock;

  SalesReportRow({
    required this.productName,
    required this.variantName,
    required this.weight,
    required this.quantitySold,
    required this.revenue,
    required this.profit,
    required this.remainingStock,
  });
}

class _SalesReportSection extends StatefulWidget {
  const _SalesReportSection();

  @override
  State<_SalesReportSection> createState() => _SalesReportSectionState();
}

class _SalesReportSectionState extends State<_SalesReportSection> {
  late Future<List<SalesReportRow>> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture = _buildReportData();
  }

  Future<List<SalesReportRow>> _buildReportData() async {
    final db = FirebaseFirestore.instance;
    
    // 1. Get current products
    final productsSnap = await db.collection('products').get();
    final Map<String, Map<String, dynamic>> catalogItems = {};
    
    for (final doc in productsSnap.docs) {
      final data = doc.data();
      final product = ProductModel.fromFirestore(doc.id, data);
      if (product.variantsEnabled && product.variants.isNotEmpty) {
        for (final v in product.variants) {
          catalogItems['${product.id}_${v.id}'] = {
            'productName': product.name,
            'variantName': v.name,
            'weight': v.name, // variant name represents weight/size
            'remainingStock': v.stockQuantity,
            'purchasePrice': v.purchasePrice,
            'sellingPrice': v.price,
          };
        }
      } else {
        catalogItems['${product.id}_'] = {
          'productName': product.name,
          'variantName': '-',
          'weight': product.unit,
          'remainingStock': product.stockQuantity,
          'purchasePrice': 0.0, // fallback
          'sellingPrice': product.price,
        };
      }
    }

    // 2. Get order items
    final orderItemsSnap = await db.collectionGroup('order_items').get();
    
    // Aggregate sales
    final Map<String, Map<String, dynamic>> salesMap = {};
    for (final doc in orderItemsSnap.docs) {
      final data = doc.data();
      final pId = data['productId'] as String? ?? '';
      final vId = data['variantId'] as String? ?? '';
      final key = '${pId}_$vId';
      
      final qty = (data['quantity'] as num?)?.toInt() ?? 0;
      final price = (data['price'] as num?)?.toDouble() ?? 0.0;
      
      double pPrice = (data['purchasePrice'] as num?)?.toDouble() ?? 0.0;
      if (pPrice == 0.0) {
        pPrice = catalogItems[key]?['purchasePrice'] as double? ?? 0.0;
      }
      
      final itemRevenue = price * qty;
      final itemProfit = (price - pPrice) * qty;
      
      if (salesMap.containsKey(key)) {
        salesMap[key]!['quantitySold'] = (salesMap[key]!['quantitySold'] as int) + qty;
        salesMap[key]!['revenue'] = (salesMap[key]!['revenue'] as double) + itemRevenue;
        salesMap[key]!['profit'] = (salesMap[key]!['profit'] as double) + itemProfit;
      } else {
        salesMap[key] = {
          'quantitySold': qty,
          'revenue': itemRevenue,
          'profit': itemProfit,
        };
      }
    }

    // 3. Combine catalog and sales map to build final rows
    final List<SalesReportRow> rows = [];
    
    catalogItems.forEach((key, catInfo) {
      final sales = salesMap[key];
      rows.add(SalesReportRow(
        productName: catInfo['productName'] as String,
        variantName: catInfo['variantName'] as String,
        weight: catInfo['weight'] as String,
        quantitySold: sales != null ? sales['quantitySold'] as int : 0,
        revenue: sales != null ? sales['revenue'] as double : 0.0,
        profit: sales != null ? sales['profit'] as double : 0.0,
        remainingStock: catInfo['remainingStock'] as int,
      ));
    });
    
    salesMap.forEach((key, salesInfo) {
      if (!catalogItems.containsKey(key)) {
        rows.add(SalesReportRow(
          productName: 'Deleted Product ($key)',
          variantName: '-',
          weight: '-',
          quantitySold: salesInfo['quantitySold'] as int,
          revenue: salesInfo['revenue'] as double,
          profit: salesInfo['profit'] as double,
          remainingStock: 0,
        ));
      }
    });

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Detailed Product Sales Report',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    setState(() {
                      _reportFuture = _buildReportData();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<SalesReportRow>>(
              future: _reportFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Error loading report: ${snapshot.error}'),
                  );
                }
                
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No sales data available.'),
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 16,
                    columns: const [
                      DataColumn(label: Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Variant Name', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Weight/Size', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Qty Sold', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Revenue', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Profit', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Stock', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: rows.map((r) {
                      return DataRow(
                        cells: [
                          DataCell(Text(r.productName)),
                          DataCell(Text(r.variantName)),
                          DataCell(Text(r.weight)),
                          DataCell(Text('${r.quantitySold}')),
                          DataCell(Text('₹${r.revenue.toStringAsFixed(0)}')),
                          DataCell(Text('₹${r.profit.toStringAsFixed(0)}')),
                          DataCell(
                            Text(
                              '${r.remainingStock}',
                              style: TextStyle(
                                color: r.remainingStock == 0 
                                    ? Colors.red 
                                    : (r.remainingStock <= 5 ? Colors.orange : Colors.green),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}



// -------------------------------------------------------------
// ORDERS TAB
// -------------------------------------------------------------
class _OrdersTab extends StatefulWidget {
  final FirestoreService firestore;

  const _OrdersTab({required this.firestore});

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  Set<String>? _knownOrderIds;
  String _searchQuery = '';

  Future<String?> _getCustomerId(String orderId) async {
    final doc = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
    return doc.data()?['customerId'] as String?;
  }

  Widget _buildOrderList(List<OrderModel> ordersList) {
    if (ordersList.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text(
            'No orders in this status.',
            style: TextStyle(color: AppColors.muted, fontSize: 14),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: ordersList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = ordersList[index];
        return OrderDetailsCard(
          order: order,
          firestore: widget.firestore,
          onChangeStatus: (status) async {
            if (status == null) return;
            final customerId = order.customerId.isNotEmpty
                ? order.customerId
                : (await _getCustomerId(order.id) ?? '');

            final Map<String, dynamic> extra = {};
            String? deliveryOtp = order.deliveryOtp;

            if (status == OrderStatuses.delivered) {
              extra['deliveredAt'] = FieldValue.serverTimestamp();
            } else if (status == OrderStatuses.confirmed) {
              extra['confirmedAt'] = FieldValue.serverTimestamp();
            } else if (status == OrderStatuses.packed) {
              extra['packedAt'] = FieldValue.serverTimestamp();
            } else if (status == OrderStatuses.outForDelivery) {
              extra['outForDeliveryAt'] = FieldValue.serverTimestamp();
              if (deliveryOtp == null || deliveryOtp.isEmpty) {
                final random = math.Random.secure();
                deliveryOtp = (100000 + random.nextInt(900000)).toString();
                extra['deliveryOtp'] = deliveryOtp;
                extra['deliveryOtpCreatedAt'] = FieldValue.serverTimestamp();
              }
            }

            if (customerId.isNotEmpty) {
              final notifTitle = status == OrderStatuses.outForDelivery
                  ? 'Out for Delivery'
                  : 'Order Status Updated';
              final notifBody = (status == OrderStatuses.outForDelivery && deliveryOtp != null && deliveryOtp.isNotEmpty)
                  ? 'Order #${order.orderNumber} is on the way. Delivery OTP: $deliveryOtp'
                  : 'Order #${order.orderNumber} is now $status';

              await widget.firestore.createNotification(
                userId: customerId,
                title: notifTitle,
                body: notifBody,
                orderId: order.id,
              );

              // Dispatch Push Notification via Cloudflare Worker (FCM HTTP v1)
              NotificationSenderService.instance.sendOrderStatusNotification(
                orderId: order.id,
                orderNumber: order.orderNumber,
                customerId: customerId,
                status: status,
                deliveryOtp: deliveryOtp,
              );
            }

            // Acknowledge and stop any repeating new-order alert when status is updated
            NewOrderAlertManager.instance.acknowledgeOrder(order.id);

            await widget.firestore.updateOrderStatus(
              orderId: order.id,
              status: status,
              extra: extra,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderModel>>(
      stream: widget.firestore.adminOrdersStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
          if (!ConnectivityProvider.instance.isOnline) {
            return OfflinePlaceholderWidget(
              onRetrySuccess: () {},
            );
          }
          return const LoadingWidget();
        }

        final allOrders = snapshot.data ?? [];

        if (_knownOrderIds == null) {
          _knownOrderIds = allOrders.map((o) => o.id).toSet();
        } else {
          final currentIds = allOrders.map((o) => o.id).toSet();
          final newIds = currentIds.difference(_knownOrderIds!);
          if (newIds.isNotEmpty) {
            _knownOrderIds!.addAll(newIds);
          }
        }

        final filteredOrders = allOrders.where((o) {
          if (_searchQuery.isEmpty) return true;
          return o.orderNumber.toLowerCase().contains(_searchQuery) ||
                 o.verificationCode.toLowerCase().contains(_searchQuery);
        }).toList();

        final pendingOrders = filteredOrders.where((o) => o.status == OrderStatuses.pending).toList();
        final activeOrders = filteredOrders.where((o) => 
          o.status == OrderStatuses.confirmed || 
          o.status == OrderStatuses.packed || 
          o.status == OrderStatuses.outForDelivery
        ).toList();
        final deliveredOrders = filteredOrders.where((o) => o.status == OrderStatuses.delivered).toList();
        final cancelledOrders = filteredOrders.where((o) => o.status == OrderStatuses.cancelled).toList();

        return DefaultTabController(
          length: 4,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    labelText: 'Search Orders',
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by Order Number or Verification Code...',
                  ),
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.muted,
                indicatorColor: AppColors.primary,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Pending'),
                        if (pendingOrders.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Badge(label: Text('${pendingOrders.length}')),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Active'),
                        if (activeOrders.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Badge(
                            backgroundColor: Colors.blue,
                            label: Text('${activeOrders.length}'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Tab(text: 'Delivered'),
                  const Tab(text: 'Cancelled'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildOrderList(pendingOrders),
                    _buildOrderList(activeOrders),
                    _buildOrderList(deliveredOrders),
                    _buildOrderList(cancelledOrders),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class OrderDetailsCard extends StatefulWidget {
  final OrderModel order;
  final FirestoreService firestore;
  final ValueChanged<String?> onChangeStatus;
  final bool initiallyExpanded;

  const OrderDetailsCard({
    super.key,
    required this.order,
    required this.firestore,
    required this.onChangeStatus,
    this.initiallyExpanded = false,
  });

  @override
  State<OrderDetailsCard> createState() => OrderDetailsCardState();
}

class OrderDetailsCardState extends State<OrderDetailsCard> {
  Future<Map<String, dynamic>>? _detailsFuture;
  String? _currentStatus;
  bool _isExpanded = false;
  bool _detailsLoaded = false;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.order.status;
    _isExpanded = widget.initiallyExpanded;
    if (_isExpanded) {
      NewOrderAlertManager.instance.acknowledgeOrder(widget.order.id);
      _detailsFuture = _fetchDetails();
      _detailsLoaded = true;
    }
  }

  @override
  void didUpdateWidget(covariant OrderDetailsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.status != widget.order.status) {
      setState(() {
        _currentStatus = widget.order.status;
      });
    }

    if (oldWidget.order.id != widget.order.id || 
        oldWidget.order.deliveryAddressId != widget.order.deliveryAddressId) {
      if (_isExpanded) {
        setState(() {
          _detailsFuture = _fetchDetails();
          _detailsLoaded = true;
        });
      } else {
        _detailsLoaded = false;
        _detailsFuture = null;
      }
    }
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        NewOrderAlertManager.instance.acknowledgeOrder(widget.order.id);
        if (!_detailsLoaded) {
          _detailsFuture = _fetchDetails();
          _detailsLoaded = true;
        }
      }
    });
  }

  Future<bool> _showVerificationDialog(BuildContext context, OrderModel order) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          scrollable: true,
          title: const Text(Messages.enterVerificationCodeTitle),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(Messages.getVerificationCodeHint),
                const SizedBox(height: AppDimensions.spacingMedium),
                CustomTextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4),
                  labelText: '',
                  hintText: 'A7K9P2',
                  validator: (value) {
                    if (value == null || value.trim().length != 6) {
                      return ValidationMessages.enterVerificationCode;
                    }
                    final input = value.trim().toUpperCase();
                    final expectedCode = order.verificationCode.trim().toUpperCase();
                    final expectedOtp = (order.deliveryOtp ?? '').trim().toUpperCase();

                    final isValid = (expectedOtp.isNotEmpty && input == expectedOtp) ||
                        (expectedCode.isNotEmpty && input == expectedCode);

                    if (!isValid) {
                      return ValidationMessages.invalidVerificationCode;
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(ButtonTexts.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text(ButtonTexts.verifyHandover),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<Map<String, dynamic>> _fetchDetails() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('users').doc(widget.order.customerId).get(),
      db.collection('addresses').doc(widget.order.deliveryAddressId).get(),
      db.collection('orders').doc(widget.order.id).collection('order_items').get(),
    ]);

    final customerSnap = results[0] as DocumentSnapshot;
    final addressSnap = results[1] as DocumentSnapshot;
    final itemsSnap = results[2] as QuerySnapshot;

    final customerData = customerSnap.exists ? (customerSnap.data() as Map<String, dynamic>? ?? {}) : <String, dynamic>{};
    final addressData = addressSnap.exists ? (addressSnap.data() as Map<String, dynamic>? ?? {}) : <String, dynamic>{};

    return {
      'customerName': customerData['name'] as String? ?? 'Customer',
      'customerEmail': customerData['email'] as String? ?? '',
      'address': addressData['fullAddress'] as String? ?? 'No address',
      'landmark': addressData['landmark'] as String? ?? '',
      'city': addressData['city'] as String? ?? 'Thiruttani',
      'state': addressData['state'] as String? ?? 'Tamil Nadu',
      'phone': addressData['phone'] as String? ?? '',
      'pincode': addressData['pincode'] as String? ?? '',
      'latitude': (addressData['latitude'] as num?)?.toDouble(),
      'longitude': (addressData['longitude'] as num?)?.toDouble(),
      'items': itemsSnap.docs.map((doc) => doc.data()).toList(),
    };
  }

  Future<void> _launchMap({
    double? latitude,
    double? longitude,
    String? address,
    String? landmark,
    String? city,
    String? pincode,
  }) async {
    final bool hasCoords = latitude != null &&
        longitude != null &&
        latitude != 0.0 &&
        longitude != 0.0;

    final List<String> addressParts = [
      if (address != null && address.trim().isNotEmpty) address.trim(),
      if (landmark != null && landmark.trim().isNotEmpty) landmark.trim(),
      if (city != null && city.trim().isNotEmpty) city.trim(),
      if (pincode != null && pincode.trim().isNotEmpty) pincode.trim(),
      'Tamil Nadu',
    ];

    final String query = addressParts.isNotEmpty
        ? addressParts.join(', ')
        : 'Thiruttani, Tamil Nadu';

    // 1. Google Maps Web/App Universal Intent URL
    final Uri googleMapsUrl = hasCoords
        ? Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitude,$longitude')
        : Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}');

    // 2. Native Geo URI scheme
    final Uri geoUri = hasCoords
        ? Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude(${Uri.encodeComponent('Customer Delivery Location')})')
        : Uri.parse('geo:0,0?q=${Uri.encodeComponent(query)}');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
        return;
      }
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        return;
      }
      await launchUrl(googleMapsUrl, mode: LaunchMode.platformDefault);
    } catch (e) {
      debugPrint('[OrderDetailsCard] Error launching maps: $e');
      try {
        await launchUrl(googleMapsUrl, mode: LaunchMode.platformDefault);
      } catch (err) {
        debugPrint('[OrderDetailsCard] Fallback maps launch error: $err');
      }
    }
  }

  Future<void> _launchDialer(String phoneNumber) async {
    final url = Uri.parse('tel:${phoneNumber.trim()}');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        debugPrint('Could not launch dialer URL: $url');
      }
    } catch (e) {
      debugPrint('Error launching dialer: $e');
    }
  }

  Future<void> _handleApproveRefund(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Refund?'),
        content: Text('Are you sure you want to approve and complete the refund of ₹${widget.order.totalPrice.toStringAsFixed(0)} for Order #${widget.order.orderNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.firestore.updateRefundStatus(
          orderId: widget.order.id,
          refundStatus: 'Refund Completed',
        );
        await widget.firestore.createNotification(
          userId: widget.order.customerId,
          title: 'Refund Completed',
          body: 'Your refund of ₹${widget.order.totalPrice.toStringAsFixed(0)} has been completed successfully.',
          orderId: widget.order.id,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Refund approved and completed successfully.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to approve refund: $e')),
          );
        }
      }
    }
  }

  Future<void> _handleRejectRefund(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Refund?'),
        content: Text('Are you sure you want to reject the refund for Order #${widget.order.orderNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.firestore.updateRefundStatus(
          orderId: widget.order.id,
          refundStatus: 'Refund Failed',
        );
        await widget.firestore.createNotification(
          userId: widget.order.customerId,
          title: 'Refund Failed',
          body: 'Your refund request for order #${widget.order.orderNumber} was rejected or failed.',
          orderId: widget.order.id,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Refund rejected.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to reject refund: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _toggleExpand,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary row (always visible)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.order.orderNumber,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.order.formattedPlacedAt,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${widget.order.totalPrice.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.order.paymentMethod} (${widget.order.paymentStatus})',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Status Badge & Chevron Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatusBadge(widget.order.status),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.muted,
                  ),
                ],
              ),
              
              // Expanded details
              if (_isExpanded) ...[
                const Divider(height: 24),
                FutureBuilder<Map<String, dynamic>>(
                  future: _detailsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: LoadingWidget(size: 24)),
                      );
                    }

                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Error loading details: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      );
                    }

                    final details = snapshot.data!;
                    final items = details['items'] as List<dynamic>;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Customer Info',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                        ),
                        const SizedBox(height: 6),
                        Text('${details['customerName']} (${details['customerEmail']})', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        InkWell(
                          onTap: () => _launchDialer(details['phone'] as String? ?? ''),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              children: [
                                const Icon(Icons.phone_outlined, size: 16, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'Phone: ${details['phone']}',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    decoration: TextDecoration.underline,
                                    decorationColor: AppColors.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _launchMap(
                                latitude: details['latitude'] as double?,
                                longitude: details['longitude'] as double?,
                                address: details['address'] as String?,
                                landmark: details['landmark'] as String?,
                                city: details['city'] as String?,
                                pincode: details['pincode'] as String?,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.location_on,
                                            size: 18,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Text(
                                            'Delivery Address',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.directions, size: 14, color: Colors.white),
                                              SizedBox(width: 4),
                                              Text(
                                                'Open Map',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      details['address'] as String? ?? 'No address provided',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    if ((details['landmark'] as String? ?? '').trim().isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Landmark: ${details['landmark']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                    if ((details['pincode'] as String? ?? '').trim().isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Pincode: ${details['pincode']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 24),
                        const Text(
                          'Product Bill',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                        ),
                        const SizedBox(height: 6),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: items.length,
                          itemBuilder: (context, idx) {
                            final item = items[idx];
                            final name = item['productName'] as String? ?? 'Product';
                            final qty = item['quantity'] as int? ?? 1;
                            final price = item['unitPrice'] as num? ?? 0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Text('• ${qty}x $name', style: const TextStyle(fontSize: 13)),
                                  const Spacer(),
                                  Text('₹${(qty * price).toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            );
                          },
                        ),
                        const Divider(height: 16),
                        Row(
                          children: [
                            const Text('Delivery fee', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                            const Spacer(),
                            Text(widget.order.deliveryFee == 0 ? 'Free' : '₹${widget.order.deliveryFee.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text('Total Bill', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text('₹${widget.order.totalPrice.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 24),
                if (widget.order.status == OrderStatuses.cancelled) ...[
                  // Cancellation details
                  const Text(
                    'Cancellation Info',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<Map<String, dynamic>>(
                    future: _detailsFuture,
                    builder: (context, snapshot) {
                      final details = snapshot.data;
                      final phone = details != null ? details['phone'] as String? ?? '' : '';
                      
                      final isOnline = widget.order.paymentMethod != 'COD';
                      final refStatus = widget.order.refundStatus ?? 'Refund Pending';

                      Color refundColor = Colors.grey;
                      if (refStatus == 'Refund Completed' || refStatus == 'Refund Approved') {
                        refundColor = Colors.green;
                      } else if (refStatus == 'Refund Failed') {
                        refundColor = Colors.red;
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Cancelled By:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                              Text(widget.order.cancelledBy ?? 'Customer', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Cancellation Reason:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                              Expanded(
                                child: Text(
                                  widget.order.cancellationReason ?? 'Not specified',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Cancelled Time:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                              Text(
                                widget.order.cancelledAt != null 
                                    ? DateFormat('dd MMM, hh:mm a').format(widget.order.cancelledAt!) 
                                    : 'N/A', 
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Refund Status:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: refundColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isOnline ? refStatus : 'COD (No Refund)',
                                  style: TextStyle(color: refundColor, fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: phone.isNotEmpty ? () => _launchDialer(phone) : null,
                                  icon: const Icon(Icons.phone, size: 16),
                                  label: const Text('Contact Customer', style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: const BorderSide(color: AppColors.primary),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                              if (isOnline && refStatus == 'Refund Pending') ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _handleApproveRefund(context),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                    child: const Text('Approve Refund', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _handleRejectRefund(context),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                    child: const Text('Reject Refund', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ] else ...[
                  // Normal order status selector
                  GestureDetector(
                    onTap: () {}, // Prevent collapse when tapping dropdown/actions
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_currentStatus),
                      initialValue: _currentStatus,
                      decoration: const InputDecoration(
                        labelText: 'Update Order Status',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: OrderStatuses.allStatuses.map((status) {
                        return DropdownMenuItem(value: status, child: Text(status));
                      }).toList(),
                      onChanged: (status) async {
                        if (status == null) return;
                        if (status == OrderStatuses.delivered) {
                          final verified = await _showVerificationDialog(context, widget.order);
                          if (!verified) {
                            setState(() {
                              _currentStatus = widget.order.status;
                            });
                            return;
                          }
                        }
                        widget.onChangeStatus(status);
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    Color textColor;
    switch (status.toLowerCase()) {
      case 'pending':
        color = Colors.amber.shade100;
        textColor = Colors.amber.shade900;
        break;
      case 'confirmed':
        color = Colors.blue.shade100;
        textColor = Colors.blue.shade900;
        break;
      case 'packed':
        color = Colors.purple.shade100;
        textColor = Colors.purple.shade900;
        break;
      case 'out_for_delivery':
      case 'out for delivery':
        color = Colors.cyan.shade100;
        textColor = Colors.cyan.shade900;
        break;
      case 'delivered':
        color = Colors.green.shade100;
        textColor = Colors.green.shade900;
        break;
      case 'cancelled':
        color = Colors.red.shade100;
        textColor = Colors.red.shade900;
        break;
      default:
        color = Colors.grey.shade100;
        textColor = Colors.grey.shade900;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// PRODUCTS TAB
// -------------------------------------------------------------
class _ProductsTab extends StatefulWidget {
  final FirestoreService firestore;

  const _ProductsTab({super.key, required this.firestore});




  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  final bool _isLoadingMore = false;
  String _searchQuery = '';
  final _nameController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _priceController = TextEditingController();
  final _unitController = TextEditingController();
  final _stockController = TextEditingController();
  final _categoryController = TextEditingController();

  // New basic information controllers
  final _tamilNameController = TextEditingController();
  final _brandController = TextEditingController();
  final _subCategoryController = TextEditingController();
  final _ingredientsController = TextEditingController();
  final _productImagesController = TextEditingController();
  final _tagsController = TextEditingController();

  // Redesign state variables
  final ScrollController _scrollController = ScrollController();
  int _displayLimit = 20;
  String _activeQuickFilter = 'all';
  String? _selectedCategory;
  String? _selectedBrand;
  bool _isMultiSelectMode = false;
  final Set<String> _selectedProductIds = {};
  bool _showSearchBar = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
          setState(() {
            _displayLimit += 20;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _imageUrlController.dispose();
    _priceController.dispose();
    _unitController.dispose();
    _stockController.dispose();
    _categoryController.dispose();
    _tamilNameController.dispose();
    _brandController.dispose();
    _subCategoryController.dispose();
    _ingredientsController.dispose();
    _productImagesController.dispose();
    _tagsController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showProductDialog({ProductModel? product}) {
    Navigator.of(context).push<bool>(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => AddEditProductScreen(
          product: product,
          firestore: widget.firestore,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    ).then((result) {
      if (result == true) {
        setState(() {});
      }
    });
  }

  //Redesign Supporting Methods
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _duplicateProduct(ProductModel product) async {
    final cloned = ProductModel(
      id: '',
      name: '${product.name} (Copy)',
      nameTamil: product.nameTamil.isNotEmpty ? '${product.nameTamil} (நகல்)' : '',
      imageUrl: product.imageUrl,
      price: product.price,
      categoryId: product.categoryId,
      unit: product.unit,
      stockQuantity: product.stockQuantity,
      lowStockThreshold: product.lowStockThreshold,
      isActive: false,
      sortOrder: product.sortOrder + 1,
      brand: product.brand,
      description: product.description,
      mrp: product.mrp,
      variantsEnabled: product.variantsEnabled,
      variants: product.variants.map((v) => ProductVariantModel(
        id: '${DateTime.now().millisecondsSinceEpoch}_${v.id}',
        name: v.name,
        size: v.size,
        unitType: v.unitType,
        mrp: v.mrp,
        price: v.price,
        purchasePrice: v.purchasePrice,
        discount: v.discount,
        stockQuantity: v.stockQuantity,
        lowStockThreshold: v.lowStockThreshold,
        status: v.status,
        barcode: v.barcode.isNotEmpty ? '${v.barcode}_copy' : '',
        sku: v.sku.isNotEmpty ? '${v.sku}_copy' : '',
        imageUrl: v.imageUrl,
      )).toList(),
      subCategoryId: product.subCategoryId,
      ingredients: product.ingredients,
      productImages: List.from(product.productImages),
      tags: List.from(product.tags),
    );

    try {
      await widget.firestore.addProduct(cloned);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Duplicated "${product.name}" successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showErrorDialog('Cloning Failed', e.toString());
    }
  }

  void _showQuickStockUpdateDialog(ProductModel product) {
    final Map<String, int> adjustments = {};
    final Map<String, int> initialStocks = {};
    String reason = 'Restock';

    if (product.variantsEnabled && product.variants.isNotEmpty) {
      for (final v in product.variants) {
        adjustments[v.id] = 0;
        initialStocks[v.id] = v.stockQuantity;
      }
    } else {
      adjustments[''] = 0;
      initialStocks[''] = product.stockQuantity;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quick Stock Update', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 4),
                Text(product.name, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.85,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Adjust Quantities:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 8),
                    if (product.variantsEnabled && product.variants.isNotEmpty)
                      ...product.variants.map((v) {
                        final adj = adjustments[v.id] ?? 0;
                        final current = initialStocks[v.id] ?? 0;
                        final result = current + adj;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('${v.name} (${v.size}${v.unitType})', style: const TextStyle(fontWeight: FontWeight.w500)),
                              ),
                              Text('Current: $current -> ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              Text('$result', style: TextStyle(fontWeight: FontWeight.bold, color: result < 0 ? Colors.red : Colors.green)),
                              const SizedBox(width: 8),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.orange, size: 24),
                                onPressed: () {
                                  dialogSetState(() {
                                    adjustments[v.id] = adj - 1;
                                  });
                                },
                              ),
                              const SizedBox(width: 8),
                              Text('$adj', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(width: 8),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 24),
                                onPressed: () {
                                  dialogSetState(() {
                                    adjustments[v.id] = adj + 1;
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      })
                    else
                      Builder(builder: (context) {
                        final adj = adjustments[''] ?? 0;
                        final current = initialStocks[''] ?? 0;
                        final result = current + adj;
                        return Row(
                          children: [
                            Expanded(
                              child: Text('Stock (${product.unit})', style: const TextStyle(fontWeight: FontWeight.w500)),
                            ),
                            Text('Current: $current -> ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            Text('$result', style: TextStyle(fontWeight: FontWeight.bold, color: result < 0 ? Colors.red : Colors.green)),
                            const SizedBox(width: 8),
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.orange, size: 24),
                              onPressed: () {
                                dialogSetState(() {
                                  adjustments[''] = adj - 1;
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            Text('$adj', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: 8),
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 24),
                              onPressed: () {
                                dialogSetState(() {
                                  adjustments[''] = adj + 1;
                                });
                              },
                            ),
                          ],
                        );
                      }),
                    const Divider(height: 24),
                    DropdownButtonFormField<String>(
                      initialValue: reason,
                      decoration: const InputDecoration(labelText: 'Reason for Adjustment'),
                      items: const [
                        DropdownMenuItem(value: 'Restock', child: Text('🟢 Restock / Purchase')),
                        DropdownMenuItem(value: 'Inventory Count Adjustment', child: Text('📋 Stock Take / Adjust')),
                        DropdownMenuItem(value: 'Damaged Goods', child: Text('⚠️ Damaged Goods')),
                        DropdownMenuItem(value: 'Customer Return', child: Text('↩️ Customer Return')),
                        DropdownMenuItem(value: 'Expired', child: Text('❌ Expired')),
                      ],
                      onChanged: (val) {
                        if (val != null) reason = val;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    if (product.variantsEnabled && product.variants.isNotEmpty) {
                      final updatedVariants = product.variants.map((v) {
                        final adj = adjustments[v.id] ?? 0;
                        final newQty = (v.stockQuantity + adj).clamp(0, 99999);
                        return ProductVariantModel(
                          id: v.id,
                          name: v.name,
                          size: v.size,
                          unitType: v.unitType,
                          mrp: v.mrp,
                          price: v.price,
                          purchasePrice: v.purchasePrice,
                          discount: v.discount,
                          stockQuantity: newQty,
                          lowStockThreshold: v.lowStockThreshold,
                          status: newQty <= 0 ? 'Out of Stock' : 'Available',
                          barcode: v.barcode,
                          sku: v.sku,
                          imageUrl: v.imageUrl,
                        );
                      }).toList();

                      final totalStock = updatedVariants.fold(0, (acc, v) => acc + v.stockQuantity);
                      final lowestPrice = updatedVariants.fold(double.infinity, (min, v) => v.price < min ? v.price : min);
                      final lowestMrp = updatedVariants.fold(double.infinity, (min, v) => v.mrp < min ? v.mrp : min);

                      final updatedProduct = ProductModel(
                        id: product.id,
                        name: product.name,
                        nameTamil: product.nameTamil,
                        imageUrl: product.imageUrl,
                        price: lowestPrice == double.infinity ? product.price : lowestPrice,
                        categoryId: product.categoryId,
                        unit: product.unit,
                        stockQuantity: totalStock,
                        lowStockThreshold: product.lowStockThreshold,
                        isActive: product.isActive,
                        sortOrder: product.sortOrder,
                        brand: product.brand,
                        description: product.description,
                        mrp: lowestMrp == double.infinity ? product.mrp : lowestMrp,
                        variantsEnabled: product.variantsEnabled,
                        variants: updatedVariants,
                        subCategoryId: product.subCategoryId,
                        ingredients: product.ingredients,
                        productImages: product.productImages,
                        tags: product.tags,
                      );

                      await widget.firestore.updateProduct(updatedProduct);
                    } else {
                      final adj = adjustments[''] ?? 0;
                      final newQty = (product.stockQuantity + adj).clamp(0, 99999);
                      final updatedProduct = ProductModel(
                        id: product.id,
                        name: product.name,
                        nameTamil: product.nameTamil,
                        imageUrl: product.imageUrl,
                        price: product.price,
                        categoryId: product.categoryId,
                        unit: product.unit,
                        stockQuantity: newQty,
                        lowStockThreshold: product.lowStockThreshold,
                        isActive: product.isActive,
                        sortOrder: product.sortOrder,
                        brand: product.brand,
                        description: product.description,
                        mrp: product.mrp,
                        variantsEnabled: product.variantsEnabled,
                        variants: product.variants,
                        subCategoryId: product.subCategoryId,
                        ingredients: product.ingredients,
                        productImages: product.productImages,
                        tags: product.tags,
                      );
                      await widget.firestore.updateProduct(updatedProduct);
                    }

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Stock updated successfully ($reason)'), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    _showErrorDialog('Stock Update Failed', e.toString());
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBulkCategoryChangeDialog() {
    String? newCategory;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Category (Bulk)', style: TextStyle(fontWeight: FontWeight.bold)),
        content: StreamBuilder<List<CategoryModel>>(
          stream: widget.firestore.categoriesStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
            }
            final categories = snapshot.data ?? [];
            return DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Select New Category'),
              items: categories.map((cat) => DropdownMenuItem(value: cat.id, child: Text(cat.name))).toList(),
              onChanged: (val) => newCategory = val,
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (newCategory == null) return;
              Navigator.pop(context);
              
              final db = FirebaseFirestore.instance;
              final batch = db.batch();
              for (final id in _selectedProductIds) {
                batch.update(db.collection('products').doc(id), {
                  'category': newCategory,
                  'categoryId': newCategory,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
              }
              await batch.commit();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Category updated in bulk.'), backgroundColor: Colors.green),
                );
                setState(() {
                  _isMultiSelectMode = false;
                  _selectedProductIds.clear();
                });
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showBulkBrandChangeDialog() {
    final brandCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign Brand (Bulk)', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: brandCtrl,
          decoration: const InputDecoration(labelText: 'Brand Name', hintText: 'e.g. Aashirvaad'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newBrand = brandCtrl.text.trim();
              if (newBrand.isEmpty) return;
              Navigator.pop(context);
              
              final db = FirebaseFirestore.instance;
              final batch = db.batch();
              for (final id in _selectedProductIds) {
                batch.update(db.collection('products').doc(id), {
                  'brand': newBrand,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
              }
              await batch.commit();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Brand assigned in bulk.'), backgroundColor: Colors.green),
                );
                setState(() {
                  _isMultiSelectMode = false;
                  _selectedProductIds.clear();
                });
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showBulkOfferDialog() {
    final offerCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply Offer / Discount (Bulk)', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: offerCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Discount Percentage (%)', hintText: 'e.g. 10'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final pct = double.tryParse(offerCtrl.text) ?? 0.0;
              if (pct <= 0 || pct > 100) return;
              Navigator.pop(context);
              
              final db = FirebaseFirestore.instance;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator()),
              );

              try {
                for (final id in _selectedProductIds) {
                  await db.runTransaction((transaction) async {
                    final ref = db.collection('products').doc(id);
                    final snap = await transaction.get(ref);
                    if (snap.exists) {
                      final product = ProductModel.fromFirestore(snap.id, snap.data() as Map<String, dynamic>);
                      if (product.variantsEnabled && product.variants.isNotEmpty) {
                        final updatedVariants = product.variants.map((v) {
                          final newPrice = v.mrp * (1 - pct / 100);
                          return ProductVariantModel(
                            id: v.id,
                            name: v.name,
                            size: v.size,
                            unitType: v.unitType,
                            mrp: v.mrp,
                            price: newPrice,
                            purchasePrice: v.purchasePrice,
                            discount: pct,
                            stockQuantity: v.stockQuantity,
                            lowStockThreshold: v.lowStockThreshold,
                            status: v.status,
                            barcode: v.barcode,
                            sku: v.sku,
                            imageUrl: v.imageUrl,
                          );
                        }).toList();

                        final lowestPrice = updatedVariants.fold(double.infinity, (min, item) => item.price < min ? item.price : min);
                        transaction.update(ref, {
                          'variants': updatedVariants.map((item) => item.toMap()).toList(),
                          'sellingPrice': lowestPrice == double.infinity ? product.price : lowestPrice,
                          'price': lowestPrice == double.infinity ? product.price : lowestPrice,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                      } else {
                        final newPrice = product.mrp * (1 - pct / 100);
                        transaction.update(ref, {
                          'sellingPrice': newPrice,
                          'price': newPrice,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                      }
                    }
                  });
                }
                
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Discount offers applied to selected products.'), backgroundColor: Colors.green),
                  );
                  setState(() {
                    _isMultiSelectMode = false;
                    _selectedProductIds.clear();
                  });
                }
              } catch (e) {
                if (context.mounted) Navigator.pop(context);
                _showErrorDialog('Bulk Offer Failed', e.toString());
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showBulkStockUpdateDialog() {
    final stockCtrl = TextEditingController();
    String direction = 'Add';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) => AlertDialog(
          title: const Text('Bulk Stock Update', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('Operation: '),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Add'),
                    selected: direction == 'Add',
                    onSelected: (val) => dialogSetState(() => direction = 'Add'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Remove'),
                    selected: direction == 'Remove',
                    onSelected: (val) => dialogSetState(() => direction = 'Remove'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: stockCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity to Adjust'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final qty = int.tryParse(stockCtrl.text) ?? 0;
                if (qty <= 0) return;
                Navigator.pop(context);

                final db = FirebaseFirestore.instance;
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );

                try {
                  final modifier = direction == 'Add' ? qty : -qty;

                  for (final id in _selectedProductIds) {
                    await db.runTransaction((transaction) async {
                      final ref = db.collection('products').doc(id);
                      final snap = await transaction.get(ref);
                      if (snap.exists) {
                        final product = ProductModel.fromFirestore(snap.id, snap.data() as Map<String, dynamic>);
                        if (product.variantsEnabled && product.variants.isNotEmpty) {
                          final updatedVariants = product.variants.map((v) {
                            final newQty = (v.stockQuantity + modifier).clamp(0, 99999);
                            return ProductVariantModel(
                              id: v.id,
                              name: v.name,
                              size: v.size,
                              unitType: v.unitType,
                              mrp: v.mrp,
                              price: v.price,
                              purchasePrice: v.purchasePrice,
                              discount: v.discount,
                              stockQuantity: newQty,
                              lowStockThreshold: v.lowStockThreshold,
                              status: newQty <= 0 ? 'Out of Stock' : 'Available',
                              barcode: v.barcode,
                              sku: v.sku,
                              imageUrl: v.imageUrl,
                            );
                          }).toList();

                          final totalStock = updatedVariants.fold(0, (acc, item) => acc + item.stockQuantity);
                          transaction.update(ref, {
                            'variants': updatedVariants.map((item) => item.toMap()).toList(),
                            'stockQuantity': totalStock,
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                        } else {
                          final newQty = (product.stockQuantity + modifier).clamp(0, 99999);
                          transaction.update(ref, {
                            'stockQuantity': newQty,
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                        }
                      }
                    });
                  }
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Stock levels adjusted in bulk successfully.'), backgroundColor: Colors.green),
                    );
                    setState(() {
                      _isMultiSelectMode = false;
                      _selectedProductIds.clear();
                    });
                  }
                } catch (e) {
                  if (context.mounted) Navigator.pop(context);
                  _showErrorDialog('Bulk Stock Update Failed', e.toString());
                }
              },
              child: const Text('Adjust'),
            ),
          ],
        ),
      ),
    );
  }

  void _showVariantEditDialog(ProductModel product, ProductVariantModel? variant, {required VoidCallback onSaveSuccess}) {
    final isEdit = variant != null;
    final nameCtrl = TextEditingController(text: variant?.name);
    final sizeCtrl = TextEditingController(text: variant?.size);
    final unitCtrl = TextEditingController(text: variant?.unitType ?? 'g');
    final mrpCtrl = TextEditingController(text: variant?.mrp.toString() ?? '0.0');
    final priceCtrl = TextEditingController(text: variant?.price.toString() ?? '0.0');
    final costCtrl = TextEditingController(text: variant?.purchasePrice.toString() ?? '0.0');
    final stockCtrl = TextEditingController(text: variant?.stockQuantity.toString() ?? '0');
    final minStockCtrl = TextEditingController(text: variant?.lowStockThreshold.toString() ?? '5');
    final barcodeCtrl = TextEditingController(text: variant?.barcode);
    final skuCtrl = TextEditingController(text: variant?.sku);
    final imageCtrl = TextEditingController(text: variant?.imageUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Edit Variant' : 'Add Variant'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Variant Name (e.g. 500g Pack)')),
                Row(
                  children: [
                    Expanded(child: TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Weight/Size'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'Unit Type (e.g. g, kg)'))),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: TextField(controller: mrpCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'MRP (₹)'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling Price (₹)'))),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cost Price (₹)'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Initial Stock'))),
                  ],
                ),
                TextField(controller: minStockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Low Stock Alert Threshold')),
                TextField(controller: barcodeCtrl, decoration: const InputDecoration(labelText: 'Barcode Scanner Value')),
                TextField(controller: skuCtrl, decoration: const InputDecoration(labelText: 'SKU Code')),
                TextField(controller: imageCtrl, decoration: const InputDecoration(labelText: 'Variant Image URL (Optional)')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final mrp = double.tryParse(mrpCtrl.text) ?? 0.0;
              final price = double.tryParse(priceCtrl.text) ?? 0.0;
              final discount = mrp > price && mrp > 0 ? (((mrp - price) / mrp) * 100).roundToDouble() : 0.0;
              
              final newV = ProductVariantModel(
                id: variant?.id ?? '${DateTime.now().millisecondsSinceEpoch}_${product.variants.length}',
                name: nameCtrl.text.trim(),
                size: sizeCtrl.text.trim(),
                unitType: unitCtrl.text.trim(),
                mrp: mrp,
                price: price,
                purchasePrice: double.tryParse(costCtrl.text) ?? 0.0,
                discount: discount,
                stockQuantity: int.tryParse(stockCtrl.text) ?? 0,
                lowStockThreshold: int.tryParse(minStockCtrl.text) ?? 5,
                status: (int.tryParse(stockCtrl.text) ?? 0) <= 0 ? 'Out of Stock' : 'Available',
                barcode: barcodeCtrl.text.trim(),
                sku: skuCtrl.text.trim(),
                imageUrl: imageCtrl.text.trim(),
              );

              final List<ProductVariantModel> updatedVariants = List.from(product.variants);
              if (isEdit) {
                final index = updatedVariants.indexWhere((v) => v.id == variant.id);
                if (index != -1) updatedVariants[index] = newV;
              } else {
                updatedVariants.add(newV);
              }

              final totalStock = updatedVariants.fold(0, (acc, v) => acc + v.stockQuantity);
              final lowestPrice = updatedVariants.fold(double.infinity, (min, v) => v.price < min ? v.price : min);
              final lowestMrp = updatedVariants.fold(double.infinity, (min, v) => v.mrp < min ? v.mrp : min);

              final updatedProduct = ProductModel(
                id: product.id,
                name: product.name,
                nameTamil: product.nameTamil,
                imageUrl: product.imageUrl,
                price: lowestPrice == double.infinity ? product.price : lowestPrice,
                categoryId: product.categoryId,
                unit: product.unit,
                stockQuantity: totalStock,
                lowStockThreshold: product.lowStockThreshold,
                isActive: product.isActive,
                sortOrder: product.sortOrder,
                brand: product.brand,
                description: product.description,
                mrp: lowestMrp == double.infinity ? product.mrp : lowestMrp,
                variantsEnabled: product.variantsEnabled,
                variants: updatedVariants,
                subCategoryId: product.subCategoryId,
                ingredients: product.ingredients,
                productImages: product.productImages,
                tags: product.tags,
              );

              try {
                await widget.firestore.updateProduct(updatedProduct);
                onSaveSuccess();
              } catch (e) {
                _showErrorDialog('Variant Save Failed', e.toString());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showProductDetailsBottomSheet(ProductModel product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StreamBuilder<ProductModel>(
          stream: widget.firestore.productStream(product.id),
          initialData: product,
          builder: (context, snapshot) {
            final activeProduct = snapshot.data ?? product;
            
            final List<String> imageUrls = [];
            if (activeProduct.imageUrl.isNotEmpty) imageUrls.add(activeProduct.imageUrl);
            imageUrls.addAll(activeProduct.productImages.where((url) => url.isNotEmpty && url != activeProduct.imageUrl));

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                      height: 4,
                      width: 40,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              activeProduct.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Color(0xFF16A34A)),
                            onPressed: () {
                              Navigator.pop(context);
                              _showProductDialog(product: activeProduct);
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (imageUrls.isNotEmpty)
                            SizedBox(
                              height: 180,
                              child: PageView.builder(
                                itemCount: imageUrls.length,
                                itemBuilder: (context, index) {
                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.network(
                                        imageUrls[index], 
                                        fit: BoxFit.contain, 
                                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 80, color: Colors.grey)
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          else
                            Container(
                              height: 180,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: const Icon(Icons.eco, size: 100, color: Colors.grey),
                            ),
                          const SizedBox(height: 16),
                          
                          Row(
                            children: [
                              Expanded(
                                child: _buildDetailTile('Brand', activeProduct.brand.isEmpty ? 'Generic' : activeProduct.brand, Icons.branding_watermark_outlined),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildDetailTile('Category', activeProduct.categoryId.isEmpty ? 'General' : activeProduct.categoryId, Icons.category_outlined),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (activeProduct.nameTamil.isNotEmpty) ...[
                            _buildDetailTile('Tamil Name', activeProduct.nameTamil, Icons.translate_outlined),
                            const SizedBox(height: 12),
                          ],
                          
                          if (activeProduct.subCategoryId.isNotEmpty) ...[
                            _buildDetailTile('Sub Category', activeProduct.subCategoryId, Icons.subdirectory_arrow_right),
                            const SizedBox(height: 12),
                          ],
                          if (activeProduct.description.isNotEmpty) ...[
                            _buildDetailTile('Description', activeProduct.description, Icons.description_outlined, maxLines: 4),
                            const SizedBox(height: 12),
                          ],
                          if (activeProduct.ingredients.isNotEmpty) ...[
                            _buildDetailTile('Ingredients', activeProduct.ingredients, Icons.restaurant_menu, maxLines: 4),
                            const SizedBox(height: 12),
                          ],

                          if (activeProduct.tags.isNotEmpty) ...[
                            const Text('Tags', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: activeProduct.tags.map((tag) => Chip(
                                label: Text(tag, style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: Colors.grey.shade100,
                              )).toList(),
                            ),
                            const SizedBox(height: 16),
                          ],

                          const Divider(height: 24),
                          
                          if (!activeProduct.variantsEnabled) ...[
                            const Text('Pricing & Inventory', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
                            const SizedBox(height: 8),
                            Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  children: [
                                    _buildInfoRow('Selling Price', '₹${activeProduct.price}'),
                                    _buildInfoRow('MRP', '₹${activeProduct.mrp}'),
                                    _buildInfoRow('Unit Type', activeProduct.unit),
                                    _buildInfoRow('Stock level', '${activeProduct.stockQuantity} Units'),
                                  ],
                                ),
                              ),
                            ),
                          ] else ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Variants Management', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
                                TextButton.icon(
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Add Variant', style: TextStyle(fontSize: 12)),
                                  onPressed: () {
                                    _showVariantEditDialog(activeProduct, null, onSaveSuccess: () {});
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...activeProduct.variants.map((v) {
                              return Card(
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('${v.name} (${v.size}${v.unitType})', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit, size: 18, color: Colors.blueGrey),
                                                onPressed: () {
                                                  _showVariantEditDialog(activeProduct, v, onSaveSuccess: () {});
                                                },
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                                onPressed: () async {
                                                  final confirm = await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) => AlertDialog(
                                                      title: const Text('Remove Variant?'),
                                                      content: Text('Remove variant "${v.name}" from this product?'),
                                                      actions: [
                                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(context, true),
                                                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                                                          child: const Text('Delete'),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (confirm == true) {
                                                    final updatedVariants = activeProduct.variants.where((item) => item.id != v.id).toList();
                                                    final totalStock = updatedVariants.fold(0, (acc, item) => acc + item.stockQuantity);
                                                    final lowestPrice = updatedVariants.fold(double.infinity, (min, item) => item.price < min ? item.price : min);
                                                    final lowestMrp = updatedVariants.fold(double.infinity, (min, item) => item.mrp < min ? item.mrp : min);

                                                    final updatedProduct = ProductModel(
                                                      id: activeProduct.id,
                                                      name: activeProduct.name,
                                                      nameTamil: activeProduct.nameTamil,
                                                      imageUrl: activeProduct.imageUrl,
                                                      price: lowestPrice == double.infinity ? activeProduct.price : lowestPrice,
                                                      categoryId: activeProduct.categoryId,
                                                      unit: activeProduct.unit,
                                                      stockQuantity: totalStock,
                                                      lowStockThreshold: activeProduct.lowStockThreshold,
                                                      isActive: activeProduct.isActive,
                                                      sortOrder: activeProduct.sortOrder,
                                                      brand: activeProduct.brand,
                                                      description: activeProduct.description,
                                                      mrp: lowestMrp == double.infinity ? activeProduct.mrp : lowestMrp,
                                                      variantsEnabled: activeProduct.variantsEnabled,
                                                      variants: updatedVariants,
                                                      subCategoryId: activeProduct.subCategoryId,
                                                      ingredients: activeProduct.ingredients,
                                                      productImages: activeProduct.productImages,
                                                      tags: activeProduct.tags,
                                                    );
                                                    await widget.firestore.updateProduct(updatedProduct);
                                                  }
                                                },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      _buildInfoRow('Selling Price', '₹${v.price}'),
                                      _buildInfoRow('MRP', '₹${v.mrp}'),
                                      _buildInfoRow('Cost Price', '₹${v.purchasePrice}'),
                                      _buildInfoRow('Stock level', '${v.stockQuantity} Units'),
                                      if (v.barcode.isNotEmpty) _buildInfoRow('Barcode', v.barcode),
                                      if (v.sku.isNotEmpty) _buildInfoRow('SKU', v.sku),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                          const Divider(height: 24),
                          
                          const Text('Sales Performance (Simulated)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
                                  child: const Column(
                                    children: [
                                      Text('Total Qty Sold', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                      SizedBox(height: 4),
                                      Text('142 Units', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                                  child: const Column(
                                    children: [
                                      Text('Total Revenue', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                      SizedBox(height: 4),
                                      Text('₹18,460', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDetailTile(String label, String value, IconData icon, {int maxLines = 1}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF16A34A)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showProductLongPressActionsBottomSheet(ProductModel product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
                ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: product.imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: product.imageUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Icon(Icons.eco, size: 30),
                          )
                        : Container(
                            width: 44,
                            height: 44,
                            color: Colors.grey.shade100,
                            child: const Icon(Icons.eco, size: 24, color: Colors.grey),
                          ),
                  ),
                  title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(product.brand.isEmpty ? 'Generic Product' : product.brand, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.remove_red_eye_outlined, color: Colors.blue),
                  title: const Text('View Details'),
                  onTap: () {
                    Navigator.pop(context);
                    _showProductDetailsBottomSheet(product);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: Colors.green),
                  title: const Text('Edit Product'),
                  onTap: () {
                    Navigator.pop(context);
                    _showProductDialog(product: product);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_outlined, color: Colors.teal),
                  title: const Text('Quick Stock Update'),
                  onTap: () {
                    Navigator.pop(context);
                    _showQuickStockUpdateDialog(product);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_outlined, color: Colors.amber),
                  title: const Text('Duplicate Product'),
                  onTap: () {
                    Navigator.pop(context);
                    _duplicateProduct(product);
                  },
                ),
                ListTile(
                  leading: Icon(product.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.orange),
                  title: Text(product.isActive ? 'Hide (Disable) Product' : 'Show (Enable) Product'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.firestore.toggleProductActive(product.id, !product.isActive);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete Product'),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteProductWithConfirmation(product);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _deleteProductWithConfirmation(ProductModel product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product?'),
        content: Text('Remove "${product.name}" permanently? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.firestore.deleteProduct(product.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product "${product.name}" deleted.'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  void _showCategoryFilterDialog(List<ProductModel> allProducts) {
    final categories = allProducts.map((p) => p.categoryId).toSet().where((c) => c.isNotEmpty).toList();
    if (categories.isEmpty) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Filter by Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      title: const Text('All Categories', style: TextStyle(fontWeight: FontWeight.bold)),
                      selected: _selectedCategory == null,
                      onTap: () {
                        setState(() {
                          _selectedCategory = null;
                        });
                        Navigator.pop(context);
                      },
                    ),
                    ...categories.map((catId) => ListTile(
                      title: Text(catId),
                      selected: _selectedCategory == catId,
                      onTap: () {
                        setState(() {
                          _selectedCategory = catId;
                        });
                        Navigator.pop(context);
                      },
                    )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBrandFilterDialog(List<ProductModel> allProducts) {
    final brands = allProducts.map((p) => p.brand).toSet().where((b) => b.isNotEmpty).toList();
    if (brands.isEmpty) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Filter by Brand', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      title: const Text('All Brands', style: TextStyle(fontWeight: FontWeight.bold)),
                      selected: _selectedBrand == null,
                      onTap: () {
                        setState(() {
                          _selectedBrand = null;
                        });
                        Navigator.pop(context);
                      },
                    ),
                    ...brands.map((brand) => ListTile(
                      title: Text(brand),
                      selected: _selectedBrand == brand,
                      onTap: () {
                        setState(() {
                          _selectedBrand = brand;
                        });
                        Navigator.pop(context);
                      },
                    )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<ProductModel> _applyFiltersAndSearch(List<ProductModel> allProducts) {
    List<ProductModel> filtered = List.from(allProducts);

    switch (_activeQuickFilter) {
      case 'low_stock':
        filtered = filtered.where((p) => p.isLowStock || (p.variantsEnabled && p.variants.any((v) => v.stockQuantity <= v.lowStockThreshold))).toList();
        break;
      case 'out_of_stock':
        filtered = filtered.where((p) => p.isOutOfStock || (p.variantsEnabled && p.variants.every((v) => v.stockQuantity <= 0))).toList();
        break;
      case 'offers':
        filtered = filtered.where((p) {
          if (p.variantsEnabled && p.variants.isNotEmpty) {
            return p.variants.any((v) => v.discount > 0);
          }
          return p.mrp > p.price;
        }).toList();
        break;
      case 'recent':
        filtered.sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
        break;
    }

    if (_selectedCategory != null) {
      filtered = filtered.where((p) => p.categoryId == _selectedCategory).toList();
    }
    if (_selectedBrand != null) {
      filtered = filtered.where((p) => p.brand.toLowerCase() == _selectedBrand!.toLowerCase()).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((p) {
        final matchesName = p.name.toLowerCase().contains(_searchQuery) || p.nameTamil.toLowerCase().contains(_searchQuery);
        final matchesBrand = p.brand.toLowerCase().contains(_searchQuery);
        final matchesBarcode = p.variantsEnabled
            ? p.variants.any((v) => v.barcode.contains(_searchQuery))
            : false;
        return matchesName || matchesBrand || matchesBarcode;
      }).toList();
    }

    return filtered;
  }

  Future<void> _exportSelectedProducts(List<ProductModel> allProducts) async {
    final selected = allProducts.where((p) => _selectedProductIds.contains(p.id)).toList();
    if (selected.isEmpty) return;

    try {
      final excel = Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(defaultSheet, 'Products Export');
      final sheet = excel['Products Export'];

      sheet.appendRow([
        TextCellValue('Product Name'),
        TextCellValue('Variant Name'),
        TextCellValue('Weight'),
        TextCellValue('Unit'),
        TextCellValue('Barcode'),
        TextCellValue('SKU'),
        TextCellValue('MRP'),
        TextCellValue('Selling Price'),
        TextCellValue('Purchase Price'),
        TextCellValue('Stock'),
        TextCellValue('Minimum Stock'),
        TextCellValue('Status'),
      ]);

      for (final product in selected) {
        if (product.variantsEnabled && product.variants.isNotEmpty) {
          for (final v in product.variants) {
            sheet.appendRow([
              TextCellValue(product.name),
              TextCellValue(v.name),
              TextCellValue(v.size),
              TextCellValue(v.unitType),
              TextCellValue(v.barcode),
              TextCellValue(v.sku),
              DoubleCellValue(v.mrp),
              DoubleCellValue(v.price),
              DoubleCellValue(v.purchasePrice),
              IntCellValue(v.stockQuantity),
              IntCellValue(v.lowStockThreshold),
              TextCellValue(v.status),
            ]);
          }
        } else {
          sheet.appendRow([
            TextCellValue(product.name),
            TextCellValue('Standard'),
            TextCellValue(product.unit.replaceAll(RegExp(r'[^0-9]'), '')),
            TextCellValue(product.unit.replaceAll(RegExp(r'[0-9\s]'), '')),
            TextCellValue(''),
            TextCellValue(''),
            DoubleCellValue(product.mrp),
            DoubleCellValue(product.price),
            DoubleCellValue(0.0),
            IntCellValue(product.stockQuantity),
            IntCellValue(product.lowStockThreshold),
            TextCellValue(product.isActive ? 'Available' : 'Disabled'),
          ]);
        }
      }

      final bytes = excel.save();
      if (bytes != null) {
        final path = await FileSaver().saveFile(bytes, 'products_export.xlsx');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Products exported successfully to $path'), backgroundColor: Colors.green),
          );
          setState(() {
            _isMultiSelectMode = false;
            _selectedProductIds.clear();
          });
        }
      }
    } catch (e) {
      _showErrorDialog('Export Failed', e.toString());
    }
  }

  Future<void> _bulkDeleteSelected() async {
    final count = _selectedProductIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count Products?'),
        content: const Text('Are you sure you want to permanently delete the selected products? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        final db = FirebaseFirestore.instance;
        final batch = db.batch();
        for (final id in _selectedProductIds) {
          batch.delete(db.collection('products').doc(id));
        }
        await batch.commit();

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$count products deleted successfully.'), backgroundColor: Colors.green),
          );
          setState(() {
            _isMultiSelectMode = false;
            _selectedProductIds.clear();
          });
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        _showErrorDialog('Delete Failed', e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProductModel>>(
      stream: widget.firestore.productsStream(includeInactive: true),
      builder: (context, snapshot) {
        final allProducts = snapshot.data ?? [];
        final filteredProducts = _applyFiltersAndSearch(allProducts);
        
        final displayedProducts = filteredProducts.take(_displayLimit).toList();

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
              onPressed: () {
                if (_isMultiSelectMode) {
                  setState(() {
                    _isMultiSelectMode = false;
                    _selectedProductIds.clear();
                  });
                } else {
                  Navigator.maybePop(context);
                }
              },
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isMultiSelectMode ? '${_selectedProductIds.length} Selected' : 'Products',
                  style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 20),
                ),
                if (!_isMultiSelectMode)
                  Text(
                    'Total Products: ${allProducts.length}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
            actions: _isMultiSelectMode
                ? [
                    IconButton(
                      icon: const Icon(Icons.select_all, color: Color(0xFF1E293B)),
                      tooltip: 'Select All',
                      onPressed: () {
                        setState(() {
                          if (_selectedProductIds.length == filteredProducts.length) {
                            _selectedProductIds.clear();
                          } else {
                            _selectedProductIds.addAll(filteredProducts.map((p) => p.id));
                          }
                        });
                      },
                    ),
                  ]
                : [
                    IconButton(
                      icon: Icon(_showSearchBar ? Icons.search_off : Icons.search, color: const Color(0xFF1E293B)),
                      tooltip: 'Search',
                      onPressed: () {
                        setState(() {
                          _showSearchBar = !_showSearchBar;
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.filter_alt_outlined, color: Color(0xFF1E293B)),
                      tooltip: 'Filter Options',
                      onPressed: () {
                        _showCategoryFilterDialog(allProducts);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.upload_file_rounded, color: Color(0xFF16A34A)),
                      tooltip: 'Import Excel',
                      onPressed: () => context.push(AppRoutes.adminImportProducts),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Color(0xFF1E293B)),
                      onSelected: (val) {
                        if (val == 'export') {
                          setState(() {
                            _selectedProductIds.addAll(filteredProducts.map((p) => p.id));
                            _exportSelectedProducts(allProducts);
                          });
                        } else if (val == 'bulk') {
                          setState(() {
                            _isMultiSelectMode = true;
                          });
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'export', child: Text('Export Catalog to Excel')),
                        const PopupMenuItem(value: 'bulk', child: Text('Enable Bulk Selection')),
                      ],
                    ),
                  ],
          ),
          floatingActionButton: _isMultiSelectMode
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _showProductDialog(),
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add Product', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
          body: Column(
            children: [
              // Search Bar
              if (_showSearchBar)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: TextField(
                      onChanged: (val) => setState(() {
                        _searchQuery = val.trim().toLowerCase();
                        _displayLimit = 20; // reset scroll limit on new search
                      }),
                      decoration: const InputDecoration(
                        hintText: 'Search by product name, barcode or brand...',
                        prefixIcon: Icon(Icons.search, color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                  ),
                ),

              // Quick Filter horizontal chips
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  children: [
                    _buildFilterChip('all', 'All Products', Icons.inventory_2_outlined),
                    _buildFilterChip('low_stock', 'Low Stock', Icons.warning_amber_rounded, badgeColor: Colors.orange),
                    _buildFilterChip('out_of_stock', 'Out of Stock', Icons.error_outline_rounded, badgeColor: Colors.red),
                    _buildFilterChip('offers', 'Offers / Discounts', Icons.local_offer_outlined),
                    _buildFilterChip('recent', 'Recently Added', Icons.fiber_new_outlined),
                    
                    // Category Active Chip
                    if (_selectedCategory != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: InputChip(
                          avatar: const Icon(Icons.category_outlined, size: 16),
                          label: Text('Category: $_selectedCategory', style: const TextStyle(fontWeight: FontWeight.w600)),
                          onDeleted: () => setState(() => _selectedCategory = null),
                          deleteIconColor: Colors.red,
                        ),
                      ),

                    // Brand Active Chip
                    if (_selectedBrand != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: InputChip(
                          avatar: const Icon(Icons.branding_watermark_outlined, size: 16),
                          label: Text('Brand: $_selectedBrand', style: const TextStyle(fontWeight: FontWeight.w600)),
                          onDeleted: () => setState(() => _selectedBrand = null),
                          deleteIconColor: Colors.red,
                        ),
                      ),
                    
                    if (_selectedCategory == null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ActionChip(
                          avatar: const Icon(Icons.category, size: 16),
                          label: const Text('Categories'),
                          onPressed: () => _showCategoryFilterDialog(allProducts),
                        ),
                      ),
                    if (_selectedBrand == null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ActionChip(
                          avatar: const Icon(Icons.branding_watermark, size: 16),
                          label: const Text('Brands'),
                          onPressed: () => _showBrandFilterDialog(allProducts),
                        ),
                      ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Main Products List
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData
                    ? (!ConnectivityProvider.instance.isOnline
                        ? OfflinePlaceholderWidget(
                            onRetrySuccess: () {},
                          )
                        : const LoadingWidget())
                    : filteredProducts.isEmpty
                        ? Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  const Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No products available',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try adjusting your search queries or category filters.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey.shade500),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () => _showProductDialog(),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Product'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: displayedProducts.length + (_isLoadingMore || _displayLimit < filteredProducts.length ? 1 : 0),
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              if (index >= displayedProducts.length) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              final product = displayedProducts[index];
                              final isSelected = _selectedProductIds.contains(product.id);

                              // Pricing layout mapping
                              final mrpText = product.variantsEnabled && product.variants.isNotEmpty
                                  ? '₹${product.variants.map((v) => v.mrp).reduce((a, b) => a < b ? a : b).toStringAsFixed(0)}'
                                  : '₹${product.mrp.toStringAsFixed(0)}';
                              final priceText = '₹${product.price.toStringAsFixed(0)}';
                              
                              final int discount = product.mrp > product.price 
                                  ? (((product.mrp - product.price) / product.mrp) * 100).round() 
                                  : 0;

                              // Stock status determinations
                              bool isOut = product.stockQuantity <= 0;
                              bool isLow = product.isLowStock;
                              if (product.variantsEnabled && product.variants.isNotEmpty) {
                                isOut = product.variants.every((v) => v.stockQuantity <= 0);
                                isLow = product.variants.any((v) => v.stockQuantity <= v.lowStockThreshold);
                              }

                              Color statusColor = Colors.green;
                              String statusText = 'In Stock';
                              if (isOut) {
                                statusColor = Colors.red;
                                statusText = 'Out of Stock';
                              } else if (isLow) {
                                statusColor = Colors.orange;
                                statusText = 'Low Stock';
                              }

                              return Card(
                                elevation: 0,
                                margin: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: isSelected 
                                        ? const Color(0xFF16A34A) 
                                        : (product.isActive ? Colors.grey.shade200 : Colors.grey.shade300),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                color: product.isActive ? Colors.white : Colors.grey.shade50,
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onLongPress: () {
                                    if (_isMultiSelectMode) {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedProductIds.remove(product.id);
                                          if (_selectedProductIds.isEmpty) {
                                            _isMultiSelectMode = false;
                                          }
                                        } else {
                                          _selectedProductIds.add(product.id);
                                        }
                                      });
                                    } else {
                                      _showProductLongPressActionsBottomSheet(product);
                                    }
                                  },
                                  onTap: () {
                                    if (_isMultiSelectMode) {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedProductIds.remove(product.id);
                                          if (_selectedProductIds.isEmpty) {
                                            _isMultiSelectMode = false;
                                          }
                                        } else {
                                          _selectedProductIds.add(product.id);
                                        }
                                      });
                                    } else {
                                      _showProductDetailsBottomSheet(product);
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Image
                                            Stack(
                                              children: [
                                                product.imageUrl.isNotEmpty
                                                    ? ClipRRect(
                                                        borderRadius: BorderRadius.circular(12),
                                                        child: Image.network(product.imageUrl, width: 90, height: 90, fit: BoxFit.cover),
                                                      )
                                                    : Container(
                                                        width: 90,
                                                        height: 90,
                                                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                                                        child: const Icon(Icons.eco, size: 40, color: Colors.grey),
                                                      ),
                                                if (_isMultiSelectMode)
                                                  Positioned(
                                                    top: 2,
                                                    left: 2,
                                                    child: Container(
                                                      width: 20,
                                                      height: 20,
                                                      decoration: BoxDecoration(
                                                        color: isSelected ? const Color(0xFF16A34A) : Colors.white.withValues(alpha: 0.8),
                                                        shape: BoxShape.circle,
                                                        border: Border.all(color: const Color(0xFF16A34A), width: 1.5),
                                                      ),
                                                      child: isSelected 
                                                          ? const Icon(Icons.check, size: 14, color: Colors.white) 
                                                          : null,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(width: 12),
                                            // Content
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          product.name,
                                                          maxLines: 2,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                                                        ),
                                                      ),
                                                      if (!product.isActive)
                                                        Container(
                                                          margin: const EdgeInsets.only(left: 4),
                                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
                                                          child: const Text('HIDDEN', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black54)),
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${product.brand.isEmpty ? 'Generic' : product.brand} | ${product.categoryId.isEmpty ? 'General' : product.categoryId} | Supplier: Ranuka Stores',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: statusColor.withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Container(
                                                              width: 6,
                                                              height: 6,
                                                              decoration: BoxDecoration(
                                                                color: statusColor,
                                                                shape: BoxShape.circle,
                                                              ),
                                                            ),
                                                            const SizedBox(width: 6),
                                                            Text(
                                                              '$statusText (${product.stockQuantity})',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.bold,
                                                                color: statusColor,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        product.variantsEnabled && product.variants.isNotEmpty 
                                                            ? product.variants.first.name 
                                                            : product.unit,
                                                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  if (product.variantsEnabled && product.variants.isNotEmpty)
                                                    InkWell(
                                                      onTap: () {
                                                        _showProductDetailsBottomSheet(product);
                                                      },
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green.shade50,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Container(
                                                              width: 6,
                                                              height: 6,
                                                              decoration: const BoxDecoration(
                                                                color: Color(0xFF16A34A),
                                                                shape: BoxShape.circle,
                                                              ),
                                                            ),
                                                            const SizedBox(width: 6),
                                                            Text(
                                                              '🟢 ${product.variants.length} Variants',
                                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        const Divider(height: 8),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          alignment: WrapAlignment.spaceBetween,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'MRP: $mrpText',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade400,
                                                    fontSize: 11,
                                                    decoration: TextDecoration.lineThrough,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  priceText,
                                                  style: const TextStyle(
                                                    color: Color(0xFF16A34A),
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                if (discount > 0) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFF97316),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      '$discount% OFF',
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                _buildCardActionButton(Icons.remove_red_eye_outlined, 'View', () {
                                                  _showProductDetailsBottomSheet(product);
                                                }),
                                                const SizedBox(width: 4),
                                                _buildCardActionButton(Icons.edit_outlined, 'Edit', () {
                                                  _showProductDialog(product: product);
                                                }),
                                                PopupMenuButton<String>(
                                                  icon: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(minWidth: 150),
                                                  onSelected: (val) {
                                                    if (val == 'variants') {
                                                      _showProductDetailsBottomSheet(product);
                                                    } else if (val == 'stock') {
                                                      _showQuickStockUpdateDialog(product);
                                                    } else if (val == 'duplicate') {
                                                      _duplicateProduct(product);
                                                    } else if (val == 'share') {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('Sharing link for "${product.name}"...')),
                                                      );
                                                    } else if (val == 'barcode') {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('Printing barcode for "${product.name}"...')),
                                                      );
                                                    } else if (val == 'disable') {
                                                      widget.firestore.updateProduct(product.copyWith(isActive: !product.isActive));
                                                    } else if (val == 'delete') {
                                                      _deleteProductWithConfirmation(product);
                                                    }
                                                  },
                                                  itemBuilder: (context) => [
                                                    const PopupMenuItem(value: 'variants', child: Text('Manage Variants')),
                                                    const PopupMenuItem(value: 'stock', child: Text('Update Stock')),
                                                    const PopupMenuItem(value: 'duplicate', child: Text('Duplicate Product')),
                                                    const PopupMenuItem(value: 'share', child: Text('Share Link')),
                                                    const PopupMenuItem(value: 'barcode', child: Text('Print Barcode')),
                                                    PopupMenuItem(value: 'disable', child: Text(product.isActive ? 'Disable Product' : 'Enable Product')),
                                                    const PopupMenuItem(value: 'delete', child: Text('Delete Product', style: TextStyle(color: Colors.red))),
                                                  ],
                                                ),
                                              ],
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
            ],
          ),
          bottomNavigationBar: _isMultiSelectMode
              ? Container(
                  color: Colors.grey.shade100,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildBulkActionButton(Icons.delete_outline, 'Delete', Colors.red, () {
                        _bulkDeleteSelected();
                      }),
                      _buildBulkActionButton(Icons.download_rounded, 'Export', Colors.blue, () {
                        _exportSelectedProducts(allProducts);
                      }),
                      _buildBulkActionButton(Icons.trending_up, 'Stock', Colors.teal, () {
                        _showBulkStockUpdateDialog();
                      }),
                      _buildBulkActionButton(Icons.category_outlined, 'Category', Colors.purple, () {
                        _showBulkCategoryChangeDialog();
                      }),
                      _buildBulkActionButton(Icons.branding_watermark_outlined, 'Brand', Colors.blueGrey, () {
                        _showBulkBrandChangeDialog();
                      }),
                      _buildBulkActionButton(Icons.local_offer_outlined, 'Offer', const Color(0xFFF97316), () {
                        _showBulkOfferDialog();
                      }),
                    ],
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildFilterChip(String filterId, String label, IconData icon, {Color? badgeColor}) {
    final isSelected = _activeQuickFilter == filterId;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        selected: isSelected,
        avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey.shade700),
        label: Text(label),
        selectedColor: const Color(0xFF16A34A),
        checkmarkColor: Colors.white,
        backgroundColor: Colors.grey.shade100,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        onSelected: (val) {
          setState(() {
            _activeQuickFilter = filterId;
            _displayLimit = 20;
          });
        },
      ),
    );
  }

  Widget _buildCardActionButton(IconData icon, String label, VoidCallback onTap) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Colors.blueGrey,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 16, color: Colors.grey.shade600),
      label: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
      onPressed: onTap,
    );
  }

  Widget _buildBulkActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(8),
          icon: Icon(icon, color: color),
          onPressed: onTap,
        ),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade800, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// -------------------------------------------------------------
// -------------------------------------------------------------
// CATALOG TAB (Combines Products and Categories)
// -------------------------------------------------------------
class _CatalogTab extends StatefulWidget {
  final FirestoreService firestore;

  const _CatalogTab({required this.firestore});


  @override
  State<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<_CatalogTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<_ProductsTabState> _productsKey = GlobalKey<_ProductsTabState>();
  final GlobalKey<_CategoriesTabState> _categoriesKey = GlobalKey<_CategoriesTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _confirmDeleteAllProducts() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Products'),
        content: const Text(
          'Are you sure you want to delete all products? This will permanently delete all product documents and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      try {
        await widget.firestore.deleteAllProducts();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All products removed successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete products: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Catalog',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          const AdminDeliveryAvailabilityButton(),
          if (_tabController.index == 0) ...[
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              tooltip: 'Remove All Products',
              onPressed: _confirmDeleteAllProducts,
            ),
            IconButton(
              icon: const Icon(Icons.upload_file_rounded),
              tooltip: 'Import Products from Excel',
              onPressed: () => context.push(AppRoutes.adminImportProducts),
            ),
          ],
          IconButton(
            icon: const Icon(AppIcons.logout),
            tooltip: ButtonTexts.logout,
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                await NotificationService.instance.clearToken(user.uid);
              }
              await AuthRepository().signOut();
              currentUserProvider.reset();
              if (context.mounted) {
                context.go(AppRoutes.login);
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: isDark ? AppColors.darkCard : AppColors.card,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelColor: AppColors.primary,
              unselectedLabelColor: isDark ? AppColors.darkMuted : AppColors.muted,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Products'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.category_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Categories'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ProductsTab(key: _productsKey, firestore: widget.firestore),
          _CategoriesTab(key: _categoriesKey, firestore: widget.firestore),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _productsKey.currentState?._showProductDialog(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Product'),
            )
          : FloatingActionButton.extended(
              onPressed: () => _categoriesKey.currentState?.showCategoryDialog(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Category'),
            ),
    );
  }
}

// -------------------------------------------------------------
// CATEGORIES TAB
// -------------------------------------------------------------
class _CategoriesTab extends StatefulWidget {
  final FirestoreService firestore;

  const _CategoriesTab({super.key, required this.firestore});

  @override
  State<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<_CategoriesTab> with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryImageController = TextEditingController();
  final _colorController = TextEditingController();
  final _sortOrderController = TextEditingController();

  String? _editingCategoryId;
  String _searchQuery = '';

  static const List<String> _presetColors = [
    '#00A86B', // Emerald Green
    '#FF6B35', // Accent Orange
    '#3B82F6', // Blue
    '#F59E0B', // Amber
    '#8B5CF6', // Purple
    '#EC4899', // Pink
    '#10B981', // Teal
    '#64748B', // Slate
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _nameController.dispose();
    _categoryImageController.dispose();
    _colorController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  void showCategoryDialog({CategoryModel? category}) {
    final isEdit = category != null;
    if (isEdit) {
      _editingCategoryId = category.id;
      _nameController.text = category.name;
      _categoryImageController.text = category.categoryImage;
      _colorController.text = category.color;
      _sortOrderController.text = category.sortOrder.toString();
    } else {
      _editingCategoryId = null;
      _nameController.clear();
      _categoryImageController.clear();
      _colorController.text = '#00A86B';
      _sortOrderController.text = '0';
    }

    final imageUrlNotifier = ValueNotifier<String>(_categoryImageController.text.trim());
    final colorNotifier = ValueNotifier<String>(_colorController.text.trim());

    void onImageChanged() {
      imageUrlNotifier.value = _categoryImageController.text.trim();
    }

    void onColorChanged() {
      colorNotifier.value = _colorController.text.trim();
    }

    _categoryImageController.addListener(onImageChanged);
    _colorController.addListener(onColorChanged);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          backgroundColor: isDark ? AppColors.darkCard : AppColors.card,
          child: SafeArea(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.category_rounded,
                              color: AppColors.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEdit ? 'Edit Category' : 'Add Category',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? AppColors.darkText : AppColors.text,
                                  ),
                                ),
                                Text(
                                  isEdit ? 'Update category details and image' : 'Create new product category',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? AppColors.darkMuted : AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(dialogContext),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Category Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Category Name*',
                          hintText: 'e.g. Fresh Dairy & Milk',
                          prefixIcon: Icon(Icons.label_outline_rounded),
                        ),
                        validator: (v) => v?.trim().isEmpty ?? true ? 'Category name is required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Category Image URL
                      TextFormField(
                        controller: _categoryImageController,
                        decoration: const InputDecoration(
                          labelText: 'Category Image URL*',
                          hintText: 'https://images.unsplash.com/...',
                          prefixIcon: Icon(Icons.image_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Category image URL is required';
                          }
                          final uri = Uri.tryParse(v.trim());
                          if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
                            return 'Invalid Image URL';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Live Image Preview Box (Targeted Rebuild Only)
                      ValueListenableBuilder<String>(
                        valueListenable: imageUrlNotifier,
                        builder: (context, imgUrl, _) {
                          return Container(
                            height: 120,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkBackground : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? AppColors.darkBorder : AppColors.border,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: imgUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: imgUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => const Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: const [
                                          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 28),
                                          SizedBox(height: 4),
                                          Text(
                                            'Invalid Image URL',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.error,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_photo_alternate_outlined,
                                          size: 32,
                                          color: isDark ? AppColors.darkMuted : AppColors.muted,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Live Image Preview',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? AppColors.darkMuted : AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Theme Color Selection
                      Text(
                        'Theme Color',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkText : AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Color Swatches (Targeted Rebuild Only)
                      ValueListenableBuilder<String>(
                        valueListenable: colorNotifier,
                        builder: (context, currentColor, _) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _presetColors.map((hex) {
                                final hexColor = _parseColor(hex);
                                final isSelected = currentColor.trim().toUpperCase() == hex.toUpperCase();
                                return GestureDetector(
                                  onTap: () {
                                    _colorController.text = hex;
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: hexColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected ? Colors.black : Colors.transparent,
                                        width: isSelected ? 2.5 : 1,
                                      ),
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                                        : null,
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _colorController,
                        decoration: const InputDecoration(
                          labelText: 'Custom Hex Color',
                          hintText: '#00A86B',
                          prefixIcon: Icon(Icons.palette_outlined),
                        ),
                        validator: (v) => v?.trim().isEmpty ?? true ? 'Color is required' : null,
                      ),
                      const SizedBox(height: 14),

                      // Sort Order
                      TextFormField(
                        controller: _sortOrderController,
                        decoration: const InputDecoration(
                          labelText: 'Display Sort Order',
                          hintText: '0',
                          prefixIcon: Icon(Icons.sort_rounded),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) => v?.trim().isEmpty ?? true ? 'Sort order required' : null,
                      ),
                      const SizedBox(height: 24),

                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => _saveCategory(dialogContext),
                            child: Text(isEdit ? 'Update Category' : 'Save Category'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      _categoryImageController.removeListener(onImageChanged);
      _colorController.removeListener(onColorChanged);
      imageUrlNotifier.dispose();
      colorNotifier.dispose();
    });
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }
    } catch (_) {}
    return AppColors.primary;
  }

  void _saveCategory(BuildContext dialogContext) async {
    if (!_formKey.currentState!.validate()) return;

    final db = FirebaseFirestore.instance;
    final name = _nameController.text.trim();
    final imgUrl = _categoryImageController.text.trim();
    final color = _colorController.text.trim();
    final sortVal = int.tryParse(_sortOrderController.text) ?? 0;

    final catId = _editingCategoryId ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

    final data = {
      'name': name,
      'imageUrl': imgUrl,
      'categoryImage': imgUrl,
      'color': color,
      'sortOrder': sortVal,
    };

    if (_editingCategoryId == null) {
      await db.collection('categories').doc(catId).set(data);
    } else {
      await db.collection('categories').doc(_editingCategoryId).update(data);
    }

    if (dialogContext.mounted) Navigator.pop(dialogContext);
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<List<CategoryModel>>(
      stream: widget.firestore.categoriesStream(),
      builder: (context, catSnapshot) {
        if (catSnapshot.connectionState == ConnectionState.waiting || !catSnapshot.hasData) {
          if (!ConnectivityProvider.instance.isOnline) {
            return OfflinePlaceholderWidget(
              onRetrySuccess: () {},
            );
          }
          return const LoadingWidget();
        }

        final allCategories = catSnapshot.data ?? [];
        final filteredCategories = allCategories.where((c) {
          if (_searchQuery.isEmpty) return true;
          return c.name.toLowerCase().contains(_searchQuery);
        }).toList();

        return StreamBuilder<List<ProductModel>>(
          stream: widget.firestore.productsStream(),
          builder: (context, prodSnapshot) {
            final products = prodSnapshot.data ?? [];

            // Map product count per category
            final Map<String, int> productCounts = {};
            for (final p in products) {
              if (p.categoryId.isNotEmpty) {
                productCounts[p.categoryId] = (productCounts[p.categoryId] ?? 0) + 1;
              }
            }

            return Column(
              children: [
                // Category Search Field
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search categories by name...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => _searchQuery = ''),
                            )
                          : null,
                    ),
                  ),
                ),
                Expanded(
                  child: filteredCategories.isEmpty
                      ? EmptyState(
                          message: _searchQuery.isNotEmpty ? 'No Matching Categories' : 'No Categories Found',
                          subtitle: 'Create categories to group products for customers.',
                          icon: Icons.category_outlined,
                          action: ElevatedButton.icon(
                            onPressed: () => showCategoryDialog(),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Category'),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisCount = constraints.maxWidth > 800 ? 3 : (constraints.maxWidth > 550 ? 2 : 1);
                            if (crossAxisCount > 1) {
                              return GridView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  childAspectRatio: 2.6,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                ),
                                itemCount: filteredCategories.length,
                                itemBuilder: (context, index) {
                                  final category = filteredCategories[index];
                                  final count = productCounts[category.id] ?? 0;
                                  return _buildCategoryCard(category, count, isDark);
                                },
                              );
                            }

                            return ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: filteredCategories.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final category = filteredCategories[index];
                                final count = productCounts[category.id] ?? 0;
                                return _buildCategoryCard(category, count, isDark);
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryCard(CategoryModel category, int productCount, bool isDark) {
    final catImage = category.imageUrl;
    final isValidUrl = catImage.isNotEmpty &&
        (catImage.startsWith('http://') || catImage.startsWith('https://'));

    debugPrint(
      '[AdminCategoryCard] Name: "${category.name}" | imageUrl: "$catImage" | Rendering: ${isValidUrl ? "CachedNetworkImage" : "Fallback Icon"}',
    );

    return Card(
      elevation: isDark ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Left: Category Image
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 56,
                height: 56,
                color: isDark ? AppColors.darkBackground : Colors.grey.shade100,
                child: isValidUrl
                    ? CachedNetworkImage(
                        imageUrl: catImage,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(
                            Icons.shopping_cart_outlined,
                            color: AppColors.primary,
                            size: 28,
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.shopping_cart_outlined,
                          color: AppColors.primary,
                          size: 28,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),

            // Center: Category Name, Product count, Theme color tag
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkText : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$productCount ${productCount == 1 ? 'Product' : 'Products'}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _parseColor(category.color),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Right: Actions (Edit & Delete)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.info, size: 20),
                  tooltip: 'Edit Category',
                  onPressed: () => showCategoryDialog(category: category),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                  tooltip: 'Delete Category',
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Category?'),
                        content: Text('Remove "${category.name}" category? Products in this category will remain untouched.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await FirebaseFirestore.instance.collection('categories').doc(category.id).delete();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


// -------------------------------------------------------------
// CUSTOMERS TAB
// -------------------------------------------------------------
class _CustomersTab extends StatefulWidget {
  final FirestoreService firestore;

  const _CustomersTab({required this.firestore});

  @override
  State<_CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<_CustomersTab> {
  String _searchQuery = '';
  String _selectedRoleFilter = 'all';

  Future<bool?> _showConfirmDialog(BuildContext context, String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showAddAdminDialog(BuildContext context) {
    final inputController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add / Promote Admin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Search for an existing user by email or phone number to grant them Admin privileges.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: inputController,
              decoration: const InputDecoration(
                labelText: 'User Email or Phone',
                hintText: 'e.g. name@example.com or 9876543210',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = inputController.text.trim();
              if (val.isEmpty) return;

              // Dismiss keyboard & show loading
              FocusScope.of(context).unfocus();
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator()),
              );

              try {
                final db = FirebaseFirestore.instance;
                // Query by email
                QuerySnapshot query = await db
                    .collection('users')
                    .where('email', isEqualTo: val)
                    .get();

                // Query by phone if email query is empty
                if (query.docs.isEmpty) {
                  query = await db
                      .collection('users')
                      .where('phone', isEqualTo: val)
                      .get();
                }

                if (query.docs.isNotEmpty) {
                  final docId = query.docs.first.id;
                  await db.collection('users').doc(docId).update({'role': 'Admin'});

                  if (context.mounted) {
                    Navigator.pop(context); // Dismiss loading
                    Navigator.pop(context); // Dismiss dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Successfully promoted $val to Admin.')),
                    );
                  }
                } else {
                  if (context.mounted) {
                    Navigator.pop(context); // Dismiss loading
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No registered user found with that email or phone number.')),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context); // Dismiss loading
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('Promote'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            decoration: const InputDecoration(
              labelText: 'Search Directory',
              prefixIcon: Icon(AppIcons.search),
              hintText: 'Search by name, email or phone...',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _selectedRoleFilter == 'all',
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedRoleFilter = 'all');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Customers'),
                        selected: _selectedRoleFilter == 'Customer',
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedRoleFilter = 'Customer');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Admins'),
                        selected: _selectedRoleFilter == 'Admin',
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedRoleFilter = 'Admin');
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showAddAdminDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Admin'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: db.collection('users').limit(200).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
                if (!ConnectivityProvider.instance.isOnline) {
                  return OfflinePlaceholderWidget(
                    onRetrySuccess: () {},
                  );
                }
                return const LoadingWidget();
              }

              final docs = snapshot.data?.docs ?? [];
              final users = docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return {
                  'id': doc.id,
                  'name': data['name'] as String? ?? 'User',
                  'phone': data['phone'] as String? ?? '',
                  'email': data['email'] as String? ?? '',
                  'role': data['role'] as String? ?? 'Customer',
                };
              }).where((c) {
                // Search filter
                final matchesSearch = _searchQuery.isEmpty ||
                    c['name']!.toLowerCase().contains(_searchQuery) ||
                    c['phone']!.toLowerCase().contains(_searchQuery) ||
                    c['email']!.toLowerCase().contains(_searchQuery);

                if (!matchesSearch) return false;

                // Role filter
                if (_selectedRoleFilter == 'all') return true;
                return c['role']!.toLowerCase() == _selectedRoleFilter.toLowerCase();
              }).toList();

              if (users.isEmpty) {
                return const Center(child: Text('No users found.'));
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: users.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final user = users[index];
                  final bool isAdmin = user['role']!.toLowerCase() == 'admin';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isAdmin ? Colors.amber.shade100 : Colors.blue.shade100,
                      child: Text(
                        user['name']![0].toUpperCase(),
                        style: TextStyle(
                          color: isAdmin ? Colors.amber.shade900 : Colors.blue.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(user['name']!),
                        if (isAdmin) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ADMIN',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text('Phone: ${user['phone']}\nEmail: ${user['email']}'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) async {
                        if (value == 'orders') {
                          _showCustomerOrders(context, user['id']!, user['name']!);
                        } else if (value == 'promote') {
                          final confirm = await _showConfirmDialog(
                            context,
                            'Promote to Admin',
                            'Are you sure you want to promote ${user['name']} to Admin?',
                          );
                          if (confirm == true) {
                            await db.collection('users').doc(user['id']).update({'role': 'Admin'});
                          }
                        } else if (value == 'demote') {
                          final confirm = await _showConfirmDialog(
                            context,
                            'Demote to Customer',
                            'Are you sure you want to demote ${user['name']} to a regular Customer?',
                          );
                          if (confirm == true) {
                            await db.collection('users').doc(user['id']).update({'role': 'Customer'});
                          }
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'orders',
                          child: Row(
                            children: [
                              Icon(Icons.shopping_bag_outlined, size: 20),
                              SizedBox(width: 8),
                              Text('View Orders'),
                            ],
                          ),
                        ),
                        if (!isAdmin)
                          const PopupMenuItem(
                            value: 'promote',
                            child: Row(
                              children: [
                                Icon(Icons.admin_panel_settings, color: Colors.green, size: 20),
                                SizedBox(width: 8),
                                Text('Make Admin'),
                              ],
                            ),
                          ),
                        if (isAdmin)
                          const PopupMenuItem(
                            value: 'demote',
                            child: Row(
                              children: [
                                Icon(Icons.person_outline, color: Colors.red, size: 20),
                                SizedBox(width: 8),
                                Text('Make Customer'),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCustomerOrders(BuildContext context, String customerId, String customerName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    "$customerName's Orders",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: StreamBuilder<List<OrderModel>>(
                    stream: widget.firestore.userOrdersStream(customerId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const LoadingWidget();
                      }

                      final orders = snapshot.data ?? [];
                      if (orders.isEmpty) {
                        return const Center(child: Text('No orders from this customer yet.'));
                      }

                      return ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: orders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final order = orders[index];
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: ListTile(
                              title: Text(order.orderNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Placed on: ${order.formattedPlacedAt}\nStatus: ${order.status}'),
                              trailing: Text('₹${order.totalPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}


