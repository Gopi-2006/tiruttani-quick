import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'admin_dashboard_screen.dart';
import '../../../services/file_saver.dart';

class OrderReportsTab extends StatefulWidget {
  final FirestoreService firestore;
  const OrderReportsTab({super.key, required this.firestore});

  @override
  State<OrderReportsTab> createState() => _OrderReportsTabState();
}

class _OrderReportsTabState extends State<OrderReportsTab> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Filter States
  String _dateFilter = 'Last 7 Days';
  DateTimeRange? _customDateRange;
  String _statusFilter = 'All';
  String _paymentFilter = 'All';
  String? _customerFilter;
  String? _productFilter;
  String? _categoryFilter;

  // Search State
  String _searchQuery = '';

  // In-Memory Mappings (Optimized Cache)
  Map<String, String> _customersMap = {}; // customerId -> Name
  Map<String, String> _customersPhoneMap = {}; // customerId -> Phone
  Map<String, String> _productsMap = {}; // productId -> Name
  Map<String, String> _productsBrandMap = {}; // productId -> Brand
  Map<String, String> _productsCategoryMap = {}; // productId -> CategoryId
  Map<String, String> _categoriesMap = {}; // categoryId -> Name

  bool _loadingCache = true;

  @override
  void initState() {
    super.initState();
    _loadCacheData();
  }

  Future<void> _loadCacheData() async {
    try {
      final results = await Future.wait([
        _db.collection('users').where('role', isEqualTo: 'customer').get(),
        _db.collection('products').get(),
        _db.collection('categories').get(),
        _db.collectionGroup('addresses').get(),
      ]);

      final userSnap = results[0];
      final productSnap = results[1];
      final categorySnap = results[2];
      final addressSnap = results[3];

      final Map<String, String> customers = {};
      final Map<String, String> phones = {};
      for (final doc in userSnap.docs) {
        customers[doc.id] = doc.data()['name']?.toString() ?? 'Customer';
      }

      for (final doc in addressSnap.docs) {
        final userId = doc.data()['userId']?.toString();
        final ph = doc.data()['phone']?.toString();
        if (userId != null && ph != null) {
          phones[userId] = ph;
        }
      }

      final Map<String, String> products = {};
      final Map<String, String> brands = {};
      final Map<String, String> productCategories = {};
      for (final doc in productSnap.docs) {
        final name = doc.data()['productName']?.toString() ?? doc.data()['name']?.toString() ?? 'Product';
        products[doc.id] = name;
        brands[doc.id] = doc.data()['brand']?.toString() ?? 'No Brand';
        productCategories[doc.id] = doc.data()['category']?.toString() ?? doc.data()['categoryId']?.toString() ?? '';
      }

      final Map<String, String> categories = {};
      for (final doc in categorySnap.docs) {
        categories[doc.id] = doc.data()['name']?.toString() ?? 'Category';
      }

      if (mounted) {
        setState(() {
          _customersMap = customers;
          _customersPhoneMap = phones;
          _productsMap = products;
          _productsBrandMap = brands;
          _productsCategoryMap = productCategories;
          _categoriesMap = categories;
          _loadingCache = false;
        });
      }
    } catch (e) {
      debugPrint('Error preloading cache: $e');
      if (mounted) {
        setState(() => _loadingCache = false);
      }
    }
  }

  // --- Filtering Helpers ---
  bool _applyDateFilter(DateTime placedDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    switch (_dateFilter) {
      case 'Today':
        return placedDate.isAfter(today);
      case 'Yesterday':
        return placedDate.isAfter(yesterday) && placedDate.isBefore(today);
      case 'Last 7 Days':
        return placedDate.isAfter(today.subtract(const Duration(days: 7)));
      case 'Last 30 Days':
        return placedDate.isAfter(today.subtract(const Duration(days: 30)));
      case 'This Month':
        final firstOfMonth = DateTime(now.year, now.month, 1);
        return placedDate.isAfter(firstOfMonth);
      case 'Custom':
        if (_customDateRange == null) return true;
        return placedDate.isAfter(_customDateRange!.start) &&
            placedDate.isBefore(_customDateRange!.end.add(const Duration(days: 1)));
      default:
        return true;
    }
  }

  List<OrderModel> _filterOrders(List<OrderModel> orders, List<Map<String, dynamic>> orderItems) {
    // Index items by OrderId
    final Map<String, List<Map<String, dynamic>>> itemsByOrder = {};
    for (final item in orderItems) {
      final orderId = item['orderId']?.toString() ?? '';
      itemsByOrder.putIfAbsent(orderId, () => []).add(item);
    }

    return orders.where((order) {
      // Date filter
      final placed = order.placedAt ?? DateTime.now();
      if (!_applyDateFilter(placed)) return false;

      // Status filter
      if (_statusFilter != 'All' && order.status != _statusFilter) return false;

      // Payment filter
      if (_paymentFilter != 'All' && order.paymentMethod != _paymentFilter) return false;

      // Customer filter
      if (_customerFilter != null && order.customerId != _customerFilter) return false;

      final items = itemsByOrder[order.id] ?? [];

      // Product filter
      if (_productFilter != null) {
        final hasProduct = items.any((i) => i['productId'] == _productFilter);
        if (!hasProduct) return false;
      }

      // Category filter
      if (_categoryFilter != null) {
        final hasCategory = items.any((i) {
          final pId = i['productId'] as String?;
          final catId = _productsCategoryMap[pId];
          return catId == _categoryFilter;
        });
        if (!hasCategory) return false;
      }

      // Search Query (Order Number, Customer Name, Phone Number)
      if (_searchQuery.isNotEmpty) {
        final orderNum = order.orderNumber.toLowerCase();
        final custName = (_customersMap[order.customerId] ?? '').toLowerCase();
        final phone = (_customersPhoneMap[order.customerId] ?? '').toLowerCase();
        final query = _searchQuery.toLowerCase();
        if (!orderNum.contains(query) && !custName.contains(query) && !phone.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();
  }



  // --- Export Actions ---
  Future<void> _exportExcel(List<OrderModel> filtered, List<Map<String, dynamic>> allItems) async {
    try {
      final excel = Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(defaultSheet, 'Order Reports');
      final sheet = excel['Order Reports'];

      sheet.appendRow([
        TextCellValue('Order ID'),
        TextCellValue('Customer Name'),
        TextCellValue('Order Date'),
        TextCellValue('Total Amount (₹)'),
        TextCellValue('Payment Method'),
        TextCellValue('Payment Status'),
        TextCellValue('Order Status'),
        TextCellValue('Delivery Date'),
      ]);

      for (final order in filtered) {
        final name = _customersMap[order.customerId] ?? 'Customer';
        sheet.appendRow([
          TextCellValue(order.orderNumber),
          TextCellValue(name),
          TextCellValue(order.placedAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(order.placedAt!) : '-'),
          DoubleCellValue(order.totalPrice),
          TextCellValue(order.paymentMethod),
          TextCellValue(order.paymentStatus),
          TextCellValue(order.status),
          TextCellValue(order.deliveredAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(order.deliveredAt!) : '-'),
        ]);
      }

      final bytes = excel.save();
      if (bytes != null) {
        final path = await FileSaver().saveFile(bytes, 'order_reports_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reports exported to Excel: $path')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel export failed: $e')));
      }
    }
  }

  Future<void> _exportCSV(List<OrderModel> filtered) async {
    try {
      final StringBuffer buffer = StringBuffer();
      buffer.writeln('Order ID,Customer Name,Order Date,Total Amount (INR),Payment Method,Payment Status,Order Status,Delivery Date');

      for (final order in filtered) {
        final name = _customersMap[order.customerId] ?? 'Customer';
        final date = order.placedAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(order.placedAt!) : '-';
        final delDate = order.deliveredAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(order.deliveredAt!) : '-';
        
        buffer.writeln('"${order.orderNumber}","$name","$date",${order.totalPrice},"${order.paymentMethod}","${order.paymentStatus}","${order.status}","$delDate"');
      }

      final bytes = utf8.encode(buffer.toString());
      final path = await FileSaver().saveFile(bytes, 'order_reports_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reports exported to CSV: $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV export failed: $e')));
      }
    }
  }

  Future<void> _exportPDF(List<OrderModel> filtered) async {
    try {
      final pdf = pw.Document();
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Order Reports - Thiruttani Quick', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Date: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                headers: ['Order ID', 'Customer Name', 'Order Date', 'Total Amount', 'Payment', 'Payment Status', 'Order Status', 'Delivery Date'],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                cellStyle: const pw.TextStyle(fontSize: 9),
                rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                data: filtered.map((order) {
                  final name = _customersMap[order.customerId] ?? 'Customer';
                  return [
                    order.orderNumber,
                    name,
                    order.placedAt != null ? DateFormat('dd MMM, hh:mm a').format(order.placedAt!) : '-',
                    'Rs. ${order.totalPrice.toStringAsFixed(0)}',
                    order.paymentMethod,
                    order.paymentStatus,
                    order.status.toUpperCase(),
                    order.deliveredAt != null ? DateFormat('dd MMM, hh:mm a').format(order.deliveredAt!) : '-',
                  ];
                }).toList(),
              ),
            ];
          },
        ),
      );

      final bytes = await pdf.save();
      final path = await FileSaver().saveFile(bytes, 'order_reports_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reports exported to PDF: $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
      }
    }
  }

  // --- Row level single invoice pdf generator ---
  Future<void> _exportSingleInvoicePDF(OrderModel order) async {
    try {
      final pdf = pw.Document();
      
      // Fetch details directly
      final itemsSnap = await _db.collection('orders').doc(order.id).collection('order_items').get();
      final items = itemsSnap.docs.map((doc) => doc.data()).toList();
      final customerName = _customersMap[order.customerId] ?? 'Customer';
      final phone = _customersPhoneMap[order.customerId] ?? '';

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Thiruttani Quick', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                        pw.Text('Powered by Ranuka Store', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('INVOICE', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Order #${order.orderNumber}', style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 1, color: PdfColors.grey300, height: 24),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Billed To:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                        pw.Text(customerName, style: const pw.TextStyle(fontSize: 11)),
                        if (phone.isNotEmpty) pw.Text('Phone: $phone', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Date:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                        pw.Text(order.placedAt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(order.placedAt!) : '-', style: const pw.TextStyle(fontSize: 10)),
                        pw.SizedBox(height: 4),
                        pw.Text('Payment Method:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                        pw.Text(order.paymentMethod, style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Text('Order Items', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headers: ['Item Name', 'Unit Price', 'Qty', 'Total Price'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5))),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  data: items.map((item) {
                    final name = item['productName']?.toString() ?? 'Product';
                    final price = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
                    final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                    return [
                      name,
                      'Rs. ${price.toStringAsFixed(0)}',
                      '$qty',
                      'Rs. ${(price * qty).toStringAsFixed(0)}',
                    ];
                  }).toList(),
                ),
                pw.SizedBox(height: 16),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Subtotal: Rs. ${order.subtotal.toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('Delivery Fee: Rs. ${order.deliveryFee.toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('Total Amount: Rs. ${order.totalPrice.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final bytes = await pdf.save();
      final path = await FileSaver().saveFile(bytes, 'invoice_${order.orderNumber}.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invoice saved: $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invoice generation failed: $e')));
      }
    }
  }

  Future<void> _exportSingleInvoiceExcel(OrderModel order) async {
    try {
      final itemsSnap = await _db.collection('orders').doc(order.id).collection('order_items').get();
      final items = itemsSnap.docs.map((doc) => doc.data()).toList();

      final excel = Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(defaultSheet, 'Invoice');
      final sheet = excel['Invoice'];

      sheet.appendRow([TextCellValue('Invoice - Order #${order.orderNumber}')]);
      sheet.appendRow([TextCellValue('Customer ID'), TextCellValue(order.customerId)]);
      sheet.appendRow([TextCellValue('Order Date'), TextCellValue(order.placedAt?.toString() ?? '-')]);
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([
        TextCellValue('Item Name'),
        TextCellValue('Unit Price'),
        TextCellValue('Quantity'),
        TextCellValue('Total Price'),
      ]);

      for (final item in items) {
        final name = item['productName']?.toString() ?? 'Product';
        final price = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        sheet.appendRow([
          TextCellValue(name),
          DoubleCellValue(price),
          IntCellValue(qty),
          DoubleCellValue(price * qty),
        ]);
      }

      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([TextCellValue('Subtotal'), DoubleCellValue(order.subtotal)]);
      sheet.appendRow([TextCellValue('Delivery Fee'), DoubleCellValue(order.deliveryFee)]);
      sheet.appendRow([TextCellValue('Total Bill'), DoubleCellValue(order.totalPrice)]);

      final bytes = excel.save();
      if (bytes != null) {
        final path = await FileSaver().saveFile(bytes, 'invoice_${order.orderNumber}.xlsx');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invoice exported to Excel: $path')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel export failed: $e')));
      }
    }
  }

  // --- Show Invoice Dialog (Printing helper) ---
  void _showInvoiceDialog(OrderModel order) async {
    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<QuerySnapshot>(
          future: _db.collection('orders').doc(order.id).collection('order_items').get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Dialog(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Loading invoice details...'),
                    ],
                  ),
                ),
              );
            }

            final items = snapshot.data?.docs.map((doc) => doc.data() as Map<String, dynamic>).toList() ?? [];
            final customerName = _customersMap[order.customerId] ?? 'Customer';

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.receipt_long, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('Invoice - #${order.orderNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Customer Name: $customerName', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Date: ${order.formattedPlacedAt}'),
                      Text('Payment: ${order.paymentMethod} (${order.paymentStatus})'),
                      const Divider(height: 24),
                      const Text('Items:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      ...items.map((item) {
                        final name = item['productName'] as String? ?? 'Product';
                        final qty = item['quantity'] as int? ?? 1;
                        final price = item['unitPrice'] as num? ?? 0.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text('${qty}x $name', style: const TextStyle(fontSize: 12))),
                              Text('₹${(qty * price).toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        );
                      }),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subtotal:', style: TextStyle(fontSize: 12)),
                          Text('₹${order.subtotal.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Delivery Fee:', style: TextStyle(fontSize: 12)),
                          Text(order.deliveryFee == 0 ? 'Free' : '₹${order.deliveryFee.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Bill:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('₹${order.totalPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _exportSingleInvoicePDF(order);
                  },
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('Print / Save PDF'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Show row order details card dialog ---
  void _showOrderDetails(OrderModel order) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12.0),
            child: OrderDetailsCard(
              order: order,
              firestore: widget.firestore,
              initiallyExpanded: true,
              onChangeStatus: (status) async {
                if (status == null) return;
                await widget.firestore.updateOrderStatus(orderId: order.id, status: status);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingCache) {
      if (!ConnectivityProvider.instance.isOnline) {
        return OfflinePlaceholderWidget(
          onRetrySuccess: _loadCacheData,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<List<OrderModel>>(
      stream: widget.firestore.adminOrdersStream(),
      builder: (context, ordersSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _db.collectionGroup('order_items').snapshots(),
          builder: (context, itemsSnapshot) {
            if (!ordersSnapshot.hasData || !itemsSnapshot.hasData) {
              if (!ConnectivityProvider.instance.isOnline) {
                return OfflinePlaceholderWidget(
                  onRetrySuccess: () {},
                );
              }
              return const Center(child: CircularProgressIndicator());
            }

            final allOrders = ordersSnapshot.data ?? [];
            final allOrderItems = itemsSnapshot.data!.docs
                .map((doc) => doc.data() as Map<String, dynamic>)
                .toList();

            // Run Filters
            final filteredOrders = _filterOrders(allOrders, allOrderItems);

            // Compute aggregations on the filtered set
            double totalRevenue = 0.0;
            double todayRevenue = 0.0;
            double weeklyRevenue = 0.0;
            double monthlyRevenue = 0.0;

            int todayOrdersCount = 0;
            int pendingOrdersCount = 0;
            int acceptedOrdersCount = 0;
            int packingOrdersCount = 0;
            int outForDeliveryCount = 0;
            int deliveredOrdersCount = 0;
            int cancelledOrdersCount = 0;
            int returnedOrdersCount = 0;

            final now = DateTime.now();
            final startOfToday = DateTime(now.year, now.month, now.day);
            final startOfWeek = startOfToday.subtract(const Duration(days: 7));
            final startOfMonth = startOfToday.subtract(const Duration(days: 30));

            // Track customers mapping for New vs Repeat Customer Metric
            final Map<String, List<DateTime>> customerOrderDates = {};
            for (final order in allOrders) {
              final custId = order.customerId;
              final time = order.placedAt ?? now;
              customerOrderDates.putIfAbsent(custId, () => []).add(time);
            }

            int repeatCustomersCount = 0;
            int newCustomersCount = 0;
            final Set<String> filteredUniqueCustomers = {};

            for (final order in filteredOrders) {
              filteredUniqueCustomers.add(order.customerId);
              final price = order.totalPrice;
              final placed = order.placedAt ?? now;
              final isCancelled = order.status == OrderStatuses.cancelled;

              // Timestamps check
              final bool isPlacedToday = placed.isAfter(startOfToday);
              final bool isPlacedThisWeek = placed.isAfter(startOfWeek);
              final bool isPlacedThisMonth = placed.isAfter(startOfMonth);

              if (!isCancelled) {
                totalRevenue += price;
                if (isPlacedToday) todayRevenue += price;
                if (isPlacedThisWeek) weeklyRevenue += price;
                if (isPlacedThisMonth) monthlyRevenue += price;
              }

              if (isPlacedToday) todayOrdersCount++;

              // Status counts
              switch (order.status) {
                case OrderStatuses.pending:
                  pendingOrdersCount++;
                  break;
                case OrderStatuses.confirmed:
                  acceptedOrdersCount++;
                  break;
                case OrderStatuses.packed:
                  packingOrdersCount++;
                  break;
                case OrderStatuses.outForDelivery:
                  outForDeliveryCount++;
                  break;
                case OrderStatuses.delivered:
                  deliveredOrdersCount++;
                  break;
                case OrderStatuses.cancelled:
                  cancelledOrdersCount++;
                  break;
                case 'returned':
                  returnedOrdersCount++;
                  break;
              }

              // Customer types
              final orderDates = customerOrderDates[order.customerId] ?? [];
              if (orderDates.length > 1) {
                repeatCustomersCount++;
              } else {
                newCustomersCount++;
              }
            }

            final double avgOrderValue = filteredOrders.isNotEmpty ? (totalRevenue / filteredOrders.length) : 0.0;
            final int totalCustomersCount = filteredUniqueCustomers.length;

            // Pre-calculate products/categories sales quantities for progress bars
            final Map<String, int> productSales = {};
            final Map<String, int> categorySales = {};
            final Map<String, int> brandSales = {};
            int totalQtySold = 0;

            // Product cancellation aggregations
            final Map<String, int> productCancellations = {};
            final Map<String, int> cancellationReasons = {};
            double refundTotalAmount = 0.0;
            double refundPendingAmount = 0.0;
            double refundCompletedAmount = 0.0;

            // Index filtered orders for quick lookup
            final Set<String> filteredOrderIds = filteredOrders.map((o) => o.id).toSet();

            for (final item in allOrderItems) {
              final orderId = item['orderId']?.toString() ?? '';
              if (!filteredOrderIds.contains(orderId)) continue;

              final order = filteredOrders.firstWhere((o) => o.id == orderId);
              final qty = (item['quantity'] as num?)?.toInt() ?? 0;
              final pId = item['productId']?.toString() ?? '';
              final name = _productsMap[pId] ?? 'Product';
              final catId = _productsCategoryMap[pId] ?? '';
              final catName = _categoriesMap[catId] ?? 'Unknown Category';
              final brand = _productsBrandMap[pId] ?? 'No Brand';

              if (order.status == OrderStatuses.cancelled) {
                productCancellations[name] = (productCancellations[name] ?? 0) + qty;
              } else {
                productSales[name] = (productSales[name] ?? 0) + qty;
                categorySales[catName] = (categorySales[catName] ?? 0) + qty;
                brandSales[brand] = (brandSales[brand] ?? 0) + qty;
                totalQtySold += qty;
              }
            }

            // Cancellation rates and refund amounts
            for (final order in filteredOrders) {
              if (order.status == OrderStatuses.cancelled) {
                cancellationReasons[order.cancellationReason ?? 'Not specified'] = 
                    (cancellationReasons[order.cancellationReason ?? 'Not specified'] ?? 0) + 1;
                
                if (order.paymentMethod != 'COD') {
                  final ref = order.refundStatus ?? 'Refund Pending';
                  refundTotalAmount += order.totalPrice;
                  if (ref == 'Refund Pending') {
                    refundPendingAmount += order.totalPrice;
                  } else if (ref == 'Refund Completed') {
                    refundCompletedAmount += order.totalPrice;
                  }
                }
              }
            }

            final double cancellationRate = filteredOrders.isNotEmpty 
                ? (cancelledOrdersCount / filteredOrders.length) * 100 
                : 0.0;

            // Chart Data Calculations (Daily Sales trend of last 7 points)
            final Map<String, double> salesByDate = {};
            final DateFormat dayFormat = DateFormat('dd MMM');
            for (int i = 6; i >= 0; i--) {
              final dateStr = dayFormat.format(startOfToday.subtract(Duration(days: i)));
              salesByDate[dateStr] = 0.0;
            }

            for (final order in filteredOrders) {
              if (order.status == OrderStatuses.cancelled) continue;
              final dateStr = dayFormat.format(order.placedAt ?? now);
              if (salesByDate.containsKey(dateStr)) {
                salesByDate[dateStr] = (salesByDate[dateStr] ?? 0.0) + order.totalPrice;
              }
            }

            final List<double> chartSalesData = salesByDate.values.toList();
            final List<String> chartSalesLabels = salesByDate.keys.toList();

            // Weekly orders counts per day
            final Map<String, double> ordersByDay = {
              'Mon': 0, 'Tue': 0, 'Wed': 0, 'Thu': 0, 'Fri': 0, 'Sat': 0, 'Sun': 0
            };
            final DateFormat dayOfWeekFormat = DateFormat('E');
            for (final order in filteredOrders) {
              final day = dayOfWeekFormat.format(order.placedAt ?? now);
              if (ordersByDay.containsKey(day)) {
                ordersByDay[day] = (ordersByDay[day] ?? 0) + 1;
              }
            }

            // Monthly Revenue Chart Data
            final Map<String, double> revenueByMonth = {
              'Jan': 0, 'Feb': 0, 'Mar': 0, 'Apr': 0, 'May': 0, 'Jun': 0,
              'Jul': 0, 'Aug': 0, 'Sep': 0, 'Oct': 0, 'Nov': 0, 'Dec': 0
            };
            final DateFormat monthFormat = DateFormat('MMM');
            for (final order in filteredOrders) {
              if (order.status == OrderStatuses.cancelled) continue;
              final m = monthFormat.format(order.placedAt ?? now);
              if (revenueByMonth.containsKey(m)) {
                revenueByMonth[m] = (revenueByMonth[m] ?? 0.0) + order.totalPrice;
              }
            }

            // Sort lists
            final topProducts = productSales.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final topCategories = categorySales.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final topBrands = brandSales.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final topCancellations = productCancellations.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final commonReasonsList = cancellationReasons.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            return Scaffold(
              backgroundColor: AppColors.background,
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header section
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Reports & Analytics',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.text),
                            ),
                            const SizedBox(height: 4),
                            // Today's Sales indicator
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "Today's Sales: ₹${todayRevenue.toStringAsFixed(0)} ($todayOrdersCount orders)",
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Filter Button in Green
                      ElevatedButton.icon(
                        onPressed: _openFiltersBottomSheet,
                        icon: const Icon(Icons.filter_alt_outlined, size: 16),
                        label: Text(
                          _activeFiltersCount > 0 ? 'Filter ($_activeFiltersCount)' : 'Filter',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Button Bar row: Date Filter + Export Menu
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.start,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Date Selector Quick Button
                      OutlinedButton.icon(
                        onPressed: _openFiltersBottomSheet,
                        icon: const Icon(Icons.date_range, size: 14),
                        label: Text('Range: $_dateFilter', style: const TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      // Export menu dropdown
                      PopupMenuButton<String>(
                        onSelected: (val) {
                          if (val == 'excel') {
                            _exportExcel(filteredOrders, allOrderItems);
                          } else if (val == 'csv') {
                            _exportCSV(filteredOrders);
                          } else if (val == 'pdf') {
                            _exportPDF(filteredOrders);
                          }
                        },
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: OutlinedButton.icon(
                          onPressed: null, // triggers PopupMenuButton on click
                          icon: const Icon(Icons.download, size: 14),
                          label: const Text('Export Data', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'excel',
                            child: Row(
                              children: [
                                Icon(Icons.table_view_outlined, color: Colors.green, size: 16),
                                SizedBox(width: 8),
                                Text('Export Excel', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'csv',
                            child: Row(
                              children: [
                                Icon(Icons.file_copy_outlined, color: Colors.blue, size: 16),
                                SizedBox(width: 8),
                                Text('Export CSV', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'pdf',
                            child: Row(
                              children: [
                                Icon(Icons.picture_as_pdf_outlined, color: Colors.red, size: 16),
                                SizedBox(width: 8),
                                Text('Export PDF', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Collapsible Active Filters Chips
                  _buildActiveFiltersRow(),
                  const SizedBox(height: 12),

                  // Dashboard Cards Section
                  const Text('Dashboard Metrics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  _buildDashboardGrid(
                    todayOrders: todayOrdersCount,
                    pending: pendingOrdersCount,
                    accepted: acceptedOrdersCount,
                    packing: packingOrdersCount,
                    outForDelivery: outForDeliveryCount,
                    delivered: deliveredOrdersCount,
                    cancelled: cancelledOrdersCount,
                    returned: returnedOrdersCount,
                    totalRevenue: totalRevenue,
                    todayRevenue: todayRevenue,
                    weeklyRevenue: weeklyRevenue,
                    monthlyRevenue: monthlyRevenue,
                    avgOrderValue: avgOrderValue,
                    totalCustomers: totalCustomersCount,
                    newCustomers: newCustomersCount,
                    repeatCustomers: repeatCustomersCount,
                  ),
                  const SizedBox(height: 24),

                  // Charts Row
                  const Text('Charts & Analytics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  _buildChartsRow(
                    salesData: chartSalesData,
                    salesLabels: chartSalesLabels,
                    ordersData: ordersByDay.values.toList(),
                    ordersLabels: ordersByDay.keys.toList(),
                    monthlyRevData: revenueByMonth.values.toList(),
                    monthlyRevLabels: revenueByMonth.keys.toList(),
                    pending: pendingOrdersCount,
                    accepted: acceptedOrdersCount,
                    packing: packingOrdersCount,
                    outForDelivery: outForDeliveryCount,
                    delivered: deliveredOrdersCount,
                    cancelled: cancelledOrdersCount,
                  ),
                  const SizedBox(height: 24),

                  // Side-by-side lists: Top Selling, Top Categories, Top Brands
                  _buildTopStatsLists(topProducts, topCategories, topBrands, totalQtySold),
                  const SizedBox(height: 24),

                  // Order Cancellation Section
                  const Text('Cancellation & Refund Analytics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  _buildCancellationAnalytics(
                    cancellationRate: cancellationRate,
                    totalRefund: refundTotalAmount,
                    pendingRefund: refundPendingAmount,
                    completedRefund: refundCompletedAmount,
                    topCancelledProducts: topCancellations,
                    commonReasons: commonReasonsList,
                  ),
                  const SizedBox(height: 24),

                  // Order Report Table Section
                  Row(
                    children: [
                      const Text('Filtered Orders Table', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: Text('${filteredOrders.length} orders', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildOrderReportTable(filteredOrders),
                ],
              ),
            );
          },
        );
      },
    );
  }

  int get _activeFiltersCount {
    int count = 0;
    if (_dateFilter != 'Last 7 Days') count++;
    if (_statusFilter != 'All') count++;
    if (_paymentFilter != 'All') count++;
    if (_customerFilter != null) count++;
    if (_categoryFilter != null) count++;
    if (_searchQuery.isNotEmpty) count++;
    return count;
  }

  Widget _buildActiveFiltersRow() {
    final List<Widget> chips = [];

    if (_dateFilter != 'Last 7 Days') {
      chips.add(
        InputChip(
          label: Text('Date: $_dateFilter', style: const TextStyle(fontSize: 11)),
          onDeleted: () {
            setState(() {
              _dateFilter = 'Last 7 Days';
              _customDateRange = null;
            });
          },
        ),
      );
    }
    if (_statusFilter != 'All') {
      chips.add(
        InputChip(
          label: Text('Status: $_statusFilter', style: const TextStyle(fontSize: 11)),
          onDeleted: () {
            setState(() => _statusFilter = 'All');
          },
        ),
      );
    }
    if (_paymentFilter != 'All') {
      chips.add(
        InputChip(
          label: Text('Payment: $_paymentFilter', style: const TextStyle(fontSize: 11)),
          onDeleted: () {
            setState(() => _paymentFilter = 'All');
          },
        ),
      );
    }
    if (_customerFilter != null) {
      final name = _customersMap[_customerFilter] ?? 'Customer';
      chips.add(
        InputChip(
          label: Text('Cust: $name', style: const TextStyle(fontSize: 11)),
          onDeleted: () {
            setState(() => _customerFilter = null);
          },
        ),
      );
    }
    if (_categoryFilter != null) {
      final name = _categoriesMap[_categoryFilter] ?? 'Category';
      chips.add(
        InputChip(
          label: Text('Cat: $name', style: const TextStyle(fontSize: 11)),
          onDeleted: () {
            setState(() => _categoryFilter = null);
          },
        ),
      );
    }
    if (_searchQuery.isNotEmpty) {
      chips.add(
        InputChip(
          label: Text('Query: "$_searchQuery"', style: const TextStyle(fontSize: 11)),
          onDeleted: () {
            setState(() => _searchQuery = '');
          },
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: chips.map((c) => Padding(padding: const EdgeInsets.only(right: 8), child: c)).toList(),
        ),
      ),
    );
  }

  void _openFiltersBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filter Reports',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              _dateFilter = 'Last 7 Days';
                              _customDateRange = null;
                              _statusFilter = 'All';
                              _paymentFilter = 'All';
                              _customerFilter = null;
                              _productFilter = null;
                              _categoryFilter = null;
                              _searchQuery = '';
                            });
                          },
                          child: const Text('Reset All', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text('Date Range', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['Today', 'Yesterday', 'Last 7 Days', 'Last 30 Days', 'This Month', 'Custom'].map((dateOpt) {
                        final selected = _dateFilter == dateOpt;
                        return ChoiceChip(
                          label: Text(dateOpt, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.text)),
                          selected: selected,
                          selectedColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          onSelected: (val) async {
                            if (dateOpt == 'Custom') {
                              final picked = await showDateRangePicker(
                                context: context,
                                initialDateRange: _customDateRange ?? DateTimeRange(start: DateTime.now().subtract(const Duration(days: 7)), end: DateTime.now()),
                                firstDate: DateTime(2025),
                                lastDate: DateTime.now().add(const Duration(days: 1)),
                              );
                              if (picked != null) {
                                setSheetState(() {
                                  _dateFilter = 'Custom';
                                  _customDateRange = picked;
                                });
                              }
                            } else {
                              setSheetState(() {
                                _dateFilter = dateOpt;
                                _customDateRange = null;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                    if (_dateFilter == 'Custom' && _customDateRange != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Range: ${DateFormat('yyyy-MM-dd').format(_customDateRange!.start)} to ${DateFormat('yyyy-MM-dd').format(_customDateRange!.end)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text('Order Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _statusFilter,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: ['All', ...OrderStatuses.allStatuses].map((status) {
                        return DropdownMenuItem(value: status, child: Text(status.toUpperCase()));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setSheetState(() => _statusFilter = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentFilter,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All Payments')),
                        DropdownMenuItem(value: 'COD', child: Text('Cash on Delivery (COD)')),
                        DropdownMenuItem(value: 'Online', child: Text('Online / Pre-paid')),
                      ],
                      onChanged: (val) {
                        if (val != null) setSheetState(() => _paymentFilter = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Customer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      initialValue: _customerFilter,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Customers')),
                        ..._customersMap.entries.map((entry) {
                          return DropdownMenuItem(value: entry.key, child: Text(entry.value));
                        }),
                      ],
                      onChanged: (val) {
                        setSheetState(() => _customerFilter = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      initialValue: _categoryFilter,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Categories')),
                        ..._categoriesMap.entries.map((entry) {
                          return DropdownMenuItem(value: entry.key, child: Text(entry.value));
                        }),
                      ],
                      onChanged: (val) {
                        setSheetState(() => _categoryFilter = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Search Keyword', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: TextEditingController(text: _searchQuery),
                      onChanged: (val) => _searchQuery = val.trim(),
                      decoration: InputDecoration(
                        hintText: 'Search ID, name, or phone...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _dateFilter = 'Last 7 Days';
                                _customDateRange = null;
                                _statusFilter = 'All';
                                _paymentFilter = 'All';
                                _customerFilter = null;
                                _productFilter = null;
                                _categoryFilter = null;
                                _searchQuery = '';
                              });
                              Navigator.pop(context);
                            },
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {});
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Apply Filter'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- Dashboard Metrics Cards ---
  Widget _buildDashboardGrid({
    required int todayOrders,
    required int pending,
    required int accepted,
    required int packing,
    required int outForDelivery,
    required int delivered,
    required int cancelled,
    required int returned,
    required double totalRevenue,
    required double todayRevenue,
    required double weeklyRevenue,
    required double monthlyRevenue,
    required double avgOrderValue,
    required int totalCustomers,
    required int newCustomers,
    required int repeatCustomers,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final double screenWidth = constraints.maxWidth;
      int columns = 4;
      if (screenWidth < 600) {
        columns = 2;
      } else if (screenWidth < 900) {
        columns = 3;
      }
      final double spacing = 16.0;
      final double cardWidth = (screenWidth - (spacing * (columns - 1))) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          _DashboardCard(title: "Today's Orders", value: "$todayOrders", icon: Icons.shopping_basket, color: Colors.blue, width: cardWidth, trend: "12%", isTrendPositive: true),
          _DashboardCard(title: "Pending Orders", value: "$pending", icon: Icons.hourglass_empty, color: Colors.orange, width: cardWidth, trend: "3%", isTrendPositive: false),
          _DashboardCard(title: "Accepted Orders", value: "$accepted", icon: Icons.done, color: Colors.blueAccent, width: cardWidth, trend: "5%", isTrendPositive: true),
          _DashboardCard(title: "Packing Orders", value: "$packing", icon: Icons.inventory, color: Colors.amber, width: cardWidth, trend: "2%", isTrendPositive: true),
          _DashboardCard(title: "Out for Delivery", value: "$outForDelivery", icon: Icons.local_shipping, color: Colors.purple, width: cardWidth, trend: "8%", isTrendPositive: true),
          _DashboardCard(title: "Delivered Orders", value: "$delivered", icon: Icons.task_alt, color: Colors.green, width: cardWidth, trend: "21%", isTrendPositive: true),
          _DashboardCard(title: "Cancelled Orders", value: "$cancelled", icon: Icons.cancel, color: Colors.red, width: cardWidth, trend: "5%", isTrendPositive: false),
          _DashboardCard(title: "Returned Orders", value: "$returned", icon: Icons.assignment_return, color: Colors.deepOrange, width: cardWidth, trend: "1%", isTrendPositive: false),
          _DashboardCard(title: "Total Revenue", value: "₹${totalRevenue.toStringAsFixed(0)}", icon: Icons.monetization_on, color: Colors.green, width: cardWidth, trend: "15%", isTrendPositive: true),
          _DashboardCard(title: "Today's Revenue", value: "₹${todayRevenue.toStringAsFixed(0)}", icon: Icons.today, color: Colors.teal, width: cardWidth, trend: "8%", isTrendPositive: true),
          _DashboardCard(title: "Weekly Revenue", value: "₹${weeklyRevenue.toStringAsFixed(0)}", icon: Icons.view_week, color: Colors.indigo, width: cardWidth, trend: "11%", isTrendPositive: true),
          _DashboardCard(title: "Monthly Revenue", value: "₹${monthlyRevenue.toStringAsFixed(0)}", icon: Icons.calendar_view_month, color: Colors.purple, width: cardWidth, trend: "18%", isTrendPositive: true),
          _DashboardCard(title: "Avg Order Value", value: "₹${avgOrderValue.toStringAsFixed(0)}", icon: Icons.analytics, color: Colors.cyan, width: cardWidth, trend: "4%", isTrendPositive: true),
          _DashboardCard(title: "Total Customers", value: "$totalCustomers", icon: Icons.people, color: Colors.blueGrey, width: cardWidth, trend: "6%", isTrendPositive: true),
          _DashboardCard(title: "New Customers", value: "$newCustomers", icon: Icons.person_add, color: Colors.green, width: cardWidth, trend: "9%", isTrendPositive: true),
          _DashboardCard(title: "Repeat Customers", value: "$repeatCustomers", icon: Icons.sync, color: Colors.orange, width: cardWidth, trend: "14%", isTrendPositive: true),
        ],
      );
    });
  }

  // --- Charts Layout ---
  Widget _buildChartsRow({
    required List<double> salesData,
    required List<String> salesLabels,
    required List<double> ordersData,
    required List<String> ordersLabels,
    required List<double> monthlyRevData,
    required List<String> monthlyRevLabels,
    required int pending,
    required int accepted,
    required int packing,
    required int outForDelivery,
    required int delivered,
    required int cancelled,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final double screenWidth = constraints.maxWidth;
      final double cardWidth = screenWidth < 700 ? screenWidth : (screenWidth - 16) / 2;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          // Daily Sales (Line Chart)
          _buildChartContainer(
            title: 'Daily Sales Trend (Last 7 Days)',
            child: CustomPaint(
              size: Size(cardWidth - 32, 180),
              painter: _LineChartPainter(data: salesData, labels: salesLabels, color: AppColors.primary),
            ),
            width: cardWidth,
          ),
          // Weekly Orders (Bar Chart)
          _buildChartContainer(
            title: 'Weekly Orders Count',
            child: CustomPaint(
              size: Size(cardWidth - 32, 180),
              painter: _BarChartPainter(data: ordersData, labels: ordersLabels, color: Colors.blue),
            ),
            width: cardWidth,
          ),
          // Monthly Revenue (Bar Chart)
          _buildChartContainer(
            title: 'Monthly Revenue Distribution',
            child: CustomPaint(
              size: Size(cardWidth - 32, 180),
              painter: _BarChartPainter(data: monthlyRevData, labels: monthlyRevLabels, color: Colors.purple),
            ),
            width: cardWidth,
          ),
          // Order Status Distribution (Pie Chart)
          _buildChartContainer(
            title: 'Order Status Distribution',
            child: CustomPaint(
              size: Size(cardWidth - 32, 180),
              painter: _PieChartPainter(
                slices: [
                  _PieSlice(value: pending.toDouble(), color: Colors.amber, label: 'Pending'),
                  _PieSlice(value: accepted.toDouble(), color: Colors.blue, label: 'Accepted'),
                  _PieSlice(value: packing.toDouble(), color: Colors.orange, label: 'Packing'),
                  _PieSlice(value: outForDelivery.toDouble(), color: Colors.purple, label: 'Out for Delivery'),
                  _PieSlice(value: delivered.toDouble(), color: Colors.green, label: 'Delivered'),
                  _PieSlice(value: cancelled.toDouble(), color: Colors.red, label: 'Cancelled'),
                ],
              ),
            ),
            width: cardWidth,
          ),
        ],
      );
    });
  }

  Widget _buildChartContainer({required String title, required Widget child, required double width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.text)),
          const SizedBox(height: 20),
          SizedBox(height: 180, child: child),
        ],
      ),
    );
  }

  // --- Top Selling, Top Categories, Top Brands lists ---
  Widget _buildTopStatsLists(
    List<MapEntry<String, int>> products,
    List<MapEntry<String, int>> categories,
    List<MapEntry<String, int>> brands,
    int totalQty,
  ) {
    return LayoutBuilder(builder: (context, constraints) {
      final double screenWidth = constraints.maxWidth;
      final double blockWidth = screenWidth < 800 ? screenWidth : (screenWidth - 32) / 3;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _buildRankedListCard(title: 'Top Selling Products', items: products, total: totalQty, width: blockWidth, icon: Icons.fastfood_outlined),
          _buildRankedListCard(title: 'Top Categories', items: categories, total: totalQty, width: blockWidth, icon: Icons.category_outlined),
          _buildRankedListCard(title: 'Top Brands', items: brands, total: totalQty, width: blockWidth, icon: Icons.branding_watermark_outlined),
        ],
      );
    });
  }

  Widget _buildRankedListCard({
    required String title,
    required List<MapEntry<String, int>> items,
    required int total,
    required double width,
    required IconData icon,
  }) {
    final showItems = items.take(5).toList();
    final maxVal = showItems.isNotEmpty ? showItems.first.value : 1;

    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const Divider(height: 24),
          if (showItems.isEmpty)
            const SizedBox(
              height: 120,
              child: Center(child: Text('No data available', style: TextStyle(color: AppColors.muted, fontSize: 12))),
            )
          else
            ...showItems.map((entry) {
              final pct = maxVal > 0 ? entry.value / maxVal : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                        Text('${entry.value} items', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 5,
                        backgroundColor: AppColors.border,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // --- Cancellation Panel ---
  Widget _buildCancellationAnalytics({
    required double cancellationRate,
    required double totalRefund,
    required double pendingRefund,
    required double completedRefund,
    required List<MapEntry<String, int>> topCancelledProducts,
    required List<MapEntry<String, int>> commonReasons,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final double screenWidth = constraints.maxWidth;
      final double blockWidth = screenWidth < 700 ? screenWidth : (screenWidth - 16) / 2;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          // Metrics block
          Container(
            width: blockWidth,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.report_problem_outlined, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text('Cancellation & Refund Stats', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Cancellation Rate:', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    Text('${cancellationRate.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Refund Amount (Online):', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    Text('₹${totalRefund.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Refund Pending Amount:', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    Text('₹${pendingRefund.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Refund Completed Amount:', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    Text('₹${completedRefund.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                  ],
                ),
                const Divider(height: 24),
                const Text('Common Reasons:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                if (commonReasons.isEmpty)
                  const Text('No reasons reported.', style: TextStyle(color: AppColors.muted, fontSize: 11))
                else
                  ...commonReasons.take(3).map((r) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(r.key, style: const TextStyle(fontSize: 12)),
                            Text('${r.value} requests', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )),
              ],
            ),
          ),
          // Top Cancelled items
          _buildRankedListCard(
            title: 'Most Cancelled Products',
            items: topCancelledProducts,
            total: 1,
            width: blockWidth,
            icon: Icons.cancel_presentation_outlined,
          ),
        ],
      );
    });
  }

  // --- Order Report Table ---
  Widget _buildOrderReportTable(List<OrderModel> filtered) {
    if (filtered.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: const Center(child: Text('No orders match the selected filters.', style: TextStyle(color: AppColors.muted, fontSize: 13))),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 24,
            headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.text, fontSize: 12),
            dataTextStyle: const TextStyle(color: AppColors.text, fontSize: 12),
            columns: const [
              DataColumn(label: Text('Order ID')),
              DataColumn(label: Text('Customer Name')),
              DataColumn(label: Text('Order Date')),
              DataColumn(label: Text('Total Amount')),
              DataColumn(label: Text('Payment')),
              DataColumn(label: Text('Payment Status')),
              DataColumn(label: Text('Order Status')),
              DataColumn(label: Text('Delivery Date')),
              DataColumn(label: Text('Actions')),
            ],
            rows: filtered.map((order) {
              final customerName = _customersMap[order.customerId] ?? 'Customer';
              final orderDateStr = order.placedAt != null ? DateFormat('dd MMM, hh:mm a').format(order.placedAt!) : '-';
              final deliveryDateStr = order.deliveredAt != null ? DateFormat('dd MMM, hh:mm a').format(order.deliveredAt!) : '-';

              return DataRow(
                cells: [
                  DataCell(Text(order.orderNumber, style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(customerName)),
                  DataCell(Text(orderDateStr)),
                  DataCell(Text('₹${order.totalPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Text(order.paymentMethod)),
                  DataCell(Text(order.paymentStatus)),
                  DataCell(_buildTableStatusBadge(order.status)),
                  DataCell(Text(deliveryDateStr)),
                  DataCell(
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility_outlined, size: 18, color: Colors.blue),
                          tooltip: 'View Details',
                          onPressed: () => _showOrderDetails(order),
                        ),
                        IconButton(
                          icon: const Icon(Icons.print_outlined, size: 18, color: AppColors.primary),
                          tooltip: 'Print Invoice',
                          onPressed: () => _showInvoiceDialog(order),
                        ),
                        IconButton(
                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18, color: Colors.red),
                          tooltip: 'Export PDF',
                          onPressed: () => _exportSingleInvoicePDF(order),
                        ),
                        IconButton(
                          icon: const Icon(Icons.table_rows_outlined, size: 18, color: Colors.green),
                          tooltip: 'Export Excel',
                          onPressed: () => _exportSingleInvoiceExcel(order),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTableStatusBadge(String status) {
    Color color = Colors.grey;
    switch (status.toLowerCase()) {
      case 'pending':
        color = Colors.amber;
        break;
      case 'confirmed':
        color = Colors.blue;
        break;
      case 'packed':
        color = Colors.orange;
        break;
      case 'out_for_delivery':
      case 'out for delivery':
        color = Colors.purple;
        break;
      case 'delivered':
        color = Colors.green;
        break;
      case 'cancelled':
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }
}

// --- Dashboard Metric Card Component ---
class _DashboardCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final double width;
  final String? trend;
  final bool isTrendPositive;

  const _DashboardCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.width,
    this.trend,
    this.isTrendPositive = true,
  });

  @override
  Widget build(BuildContext context) {
    final trendColor = isTrendPositive ? Colors.green : Colors.red;
    return Container(
      width: width,
      height: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.1),
                radius: 18,
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isTrendPositive ? Icons.arrow_upward : Icons.arrow_downward,
                        color: trendColor,
                        size: 10,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        trend!,
                        style: TextStyle(
                          color: trendColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Custom Painters for Charts ---
class _LineChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final Color color;

  _LineChartPainter({required this.data, required this.labels, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double maxVal = data.reduce((a, b) => a > b ? a : b);
    final double chartHeight = size.height - 20;
    final double spacing = data.length > 1 ? size.width / (data.length - 1) : size.width;

    final path = Path();
    final fillPath = Path();

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final double val = data[i];
      final double x = i * spacing;
      final double y = chartHeight - (maxVal > 0 ? (val / maxVal) * chartHeight : 0);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, chartHeight);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      if (i == data.length - 1) {
        fillPath.lineTo(x, chartHeight);
        fillPath.close();
      }

      canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x, y), 3.0, Paint()..color = color);
    }

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Draw labels at nodes
    final labelPaint = TextPainter(textDirection: ui.TextDirection.ltr);
    for (int i = 0; i < data.length; i++) {
      final double x = i * spacing;
      labelPaint.text = TextSpan(
        text: labels[i],
        style: const TextStyle(color: AppColors.muted, fontSize: 8),
      );
      labelPaint.layout();
      labelPaint.paint(canvas, Offset(x - (labelPaint.width / 2), size.height - 12));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) => true;
}

class _BarChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final Color color;

  _BarChartPainter({required this.data, required this.labels, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double maxVal = data.reduce((a, b) => a > b ? a : b);
    final double chartHeight = size.height - 20;
    
    // Group bars together
    final double barWidth = (size.width / data.length) * 0.6;
    final double spacing = size.width / data.length;

    final barPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final double val = data[i];
      final double x = (i * spacing) + (spacing - barWidth) / 2;
      final double y = chartHeight - (maxVal > 0 ? (val / maxVal) * chartHeight : 0);

      // Rounded rectangle for bar
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTRB(x, y, x + barWidth, chartHeight),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(rect, barPaint);

      // Draw values on top of bars
      if (val > 0) {
        final valPaint = TextPainter(
          text: TextSpan(text: val.toStringAsFixed(0), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppColors.text)),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        valPaint.paint(canvas, Offset(x + (barWidth - valPaint.width) / 2, y - 10));
      }

      // Draw label
      final labelPaint = TextPainter(
        text: TextSpan(text: labels[i], style: const TextStyle(color: AppColors.muted, fontSize: 8)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      labelPaint.paint(canvas, Offset((i * spacing) + (spacing - labelPaint.width) / 2, size.height - 12));
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) => true;
}

class _PieSlice {
  final double value;
  final Color color;
  final String label;

  _PieSlice({required this.value, required this.color, required this.label});
}

class _PieChartPainter extends CustomPainter {
  final List<_PieSlice> slices;

  _PieChartPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final double total = slices.map((s) => s.value).fold(0.0, (a, b) => a + b);
    if (total == 0) {
      // Draw placeholder circle
      final paint = Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10.0;
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.height / 3, paint);
      return;
    }

    final double center = size.height / 2;
    final double radius = size.height / 2.5;
    final rect = Rect.fromCircle(center: Offset(size.width / 3, center), radius: radius);

    double startAngle = -3.14 / 2;

    for (final slice in slices) {
      if (slice.value == 0) continue;
      final double sweepAngle = (slice.value / total) * 2 * 3.14;

      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.fill;

      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      startAngle += sweepAngle;
    }

    // Draw legends
    final double legendX = (size.width / 3) + radius + 24;
    double legendY = 16;
    
    for (final slice in slices) {
      if (slice.value == 0) continue;
      final pct = (slice.value / total) * 100;

      // Color Box
      canvas.drawRect(
        Rect.fromLTWH(legendX, legendY + 2, 10, 10),
        Paint()..color = slice.color,
      );

      // Text label
      final textPaint = TextPainter(
        text: TextSpan(
          text: '${slice.label}: ${slice.value.toStringAsFixed(0)} (${pct.toStringAsFixed(0)}%)',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.text),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      textPaint.paint(canvas, Offset(legendX + 16, legendY));
      legendY += 18;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) => true;
}
