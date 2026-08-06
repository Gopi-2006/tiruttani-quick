import 'dart:async';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/empty_state.dart';
import 'create_banner_screen.dart';


class MarketingTab extends StatefulWidget {
  const MarketingTab({super.key});

  @override
  State<MarketingTab> createState() => _MarketingTabState();
}

class _MarketingTabState extends State<MarketingTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Container(
          color: isDark ? AppColors.darkCard : AppColors.card,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.primary,
            unselectedLabelColor: isDark ? AppColors.darkMuted : AppColors.muted,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: const [
              Tab(text: 'Banners'),
              Tab(text: 'Offers'),
              Tab(text: 'Flash Sales'),
              Tab(text: 'Coupons'),
              Tab(text: 'Analytics'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _BannerManagerView(firestoreService: _firestoreService),
          _OfferManagerView(firestoreService: _firestoreService),
          _FlashSaleManagerView(firestoreService: _firestoreService),
          _CouponManagerView(firestoreService: _firestoreService),
          _BannerAnalyticsView(firestoreService: _firestoreService),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. BANNER MANAGER VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _BannerManagerView extends StatefulWidget {
  final FirestoreService firestoreService;
  const _BannerManagerView({required this.firestoreService});

  @override
  State<_BannerManagerView> createState() => _BannerManagerViewState();
}

class _BannerManagerViewState extends State<_BannerManagerView> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<List<BannerModel>>(
      stream: widget.firestoreService.bannersStream(includeInactive: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final banners = snapshot.data ?? [];
        if (banners.isEmpty) {
          return EmptyState(
            message: 'No Promotional Banners',
            subtitle: 'Create banners to showcase daily deals, offers, and categories.',
            icon: Icons.campaign_outlined,
            action: ElevatedButton.icon(
              onPressed: () => _showAddEditBannerDialog(null),
              icon: const Icon(Icons.add),
              label: const Text('Add First Banner'),
            ),
          );
        }

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddEditBannerDialog(null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create Banner'),
          ),
          body: Column(
            children: [
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.swap_vert_rounded, size: 18, color: AppColors.primary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Drag items up/down to reorder how banners appear on customer app home screen.',
                        style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(left: 12, right: 12, bottom: 80),
                  itemCount: banners.length,
                  onReorderItem: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final item = banners.removeAt(oldIndex);
                    banners.insert(newIndex, item);
                    await widget.firestoreService.updateBannersOrder(banners);
                  },
                  itemBuilder: (context, index) {
                    final banner = banners[index];
                    final isActive = banner.isActive && banner.isCurrentlyActive;

                    return Card(
                      key: ValueKey(banner.id),
                      margin: const EdgeInsets.only(bottom: 14),
                      elevation: isDark ? 2 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isDark ? AppColors.darkBorder : AppColors.border,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Banner Image Header
                          Stack(
                            children: [
                              AspectRatio(
                                aspectRatio: 16 / 7,
                                child: banner.imageUrl.isNotEmpty
                                    ? Image.network(
                                        banner.imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                                          child: const Center(
                                            child: Icon(Icons.broken_image_outlined, size: 40, color: AppColors.muted),
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: AppColors.primary.withValues(alpha: 0.1),
                                        child: const Center(
                                          child: Icon(Icons.image_outlined, size: 40, color: AppColors.primary),
                                        ),
                                      ),
                              ),
                              // Status Chip Badge
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isActive ? AppColors.success : AppColors.error,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    isActive ? 'ACTIVE' : 'INACTIVE / EXPIRED',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                              // Drag reorder handle
                              Positioned(
                                top: 10,
                                left: 10,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.drag_indicator, color: Colors.white, size: 18),
                                ),
                              ),
                            ],
                          ),

                          // Banner Details Section
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  banner.title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? AppColors.darkText : AppColors.text,
                                  ),
                                ),
                                if (banner.subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    banner.subtitle,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? AppColors.darkMuted : AppColors.muted,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                const Divider(height: 1),
                                const SizedBox(height: 12),

                                // Target & Schedule info
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.touch_app_outlined, size: 15, color: AppColors.primary),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Action: ${banner.actionType}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.schedule_rounded, size: 15, color: AppColors.muted),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Schedule: ${DateFormat('dd MMM').format(banner.startDateTime)} - ${DateFormat('dd MMM').format(banner.endDateTime)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? AppColors.darkMuted : AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Actions Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _showAddEditBannerDialog(banner),
                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                      label: const Text('Edit'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    OutlinedButton.icon(
                                      onPressed: () => _confirmDeleteBanner(banner.id),
                                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                      label: const Text('Delete'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.error,
                                        side: const BorderSide(color: AppColors.error),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
      },
    );
  }

  void _showAddEditBannerDialog(BannerModel? banner) {
    Navigator.push(
      context,
      PageRouteBuilder(
        fullscreenDialog: true,
        pageBuilder: (context, animation, secondaryAnimation) => CreateBannerScreen(banner: banner),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  void _confirmDeleteBanner(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Banner'),
        content: const Text('Are you sure you want to delete this promotional banner?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await widget.firestoreService.deleteBanner(id);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. OFFER MANAGER VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _OfferManagerView extends StatefulWidget {
  final FirestoreService firestoreService;
  const _OfferManagerView({required this.firestoreService});

  @override
  State<_OfferManagerView> createState() => _OfferManagerViewState();
}

class _OfferManagerViewState extends State<_OfferManagerView> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OfferModel>>(
      stream: widget.firestoreService.offersStream(includeInactive: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final offers = snapshot.data ?? [];
        if (offers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('No standalone offers created yet.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showAddEditOfferDialog(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add First Offer'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                )
              ],
            ),
          );
        }

        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddEditOfferDialog(null),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add),
          ),
          body: ListView.builder(
            itemCount: offers.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final offer = offers[index];
              final isActive = offer.isActive && offer.isCurrentlyActive;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  title: Text(offer.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'Scope: ${offer.targetType} (${offer.targetIds.join(', ')})\n'
                    'Value: ${offer.discountValue}${offer.discountType == 'percentage' ? '%' : '₹'} Off\n'
                    'Schedule: ${DateFormat('dd MMM hh:mm a').format(offer.startDateTime)} to ${DateFormat('dd MMM hh:mm a').format(offer.endDateTime)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isActive ? 'Active' : 'Inactive/Expired',
                          style: TextStyle(color: isActive ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showAddEditOfferDialog(offer),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDeleteOffer(offer.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showAddEditOfferDialog(OfferModel? offer) {
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController(text: offer?.title ?? '');
    final discountAmountController = TextEditingController(text: offer?.discountValue.toString() ?? '10');
    String discountType = offer?.discountType ?? 'percentage';
    String targetScope = offer?.targetType ?? 'Entire Store';
    final targetDetailsController = TextEditingController(text: offer?.targetIds.join(', ') ?? '');
    
    DateTime startDateTime = offer?.startDateTime ?? DateTime.now();
    DateTime endDateTime = offer?.endDateTime ?? DateTime.now().add(const Duration(days: 7));
    bool isActive = offer?.isActive ?? true;
    bool countdownEnabled = offer?.countdownEnabled ?? false;
    int priority = offer?.priority ?? 1;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickDateTime(bool isStart) async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: isStart ? startDateTime : endDateTime,
                firstDate: DateTime(2025),
                lastDate: DateTime(2030),
              );
              if (pickedDate != null) {
                if (!context.mounted) return;
                final pickedTime = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(isStart ? startDateTime : endDateTime),
                );
                if (pickedTime != null) {
                  setDialogState(() {
                    final dt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
                    if (isStart) {
                      startDateTime = dt;
                    } else {
                      endDateTime = dt;
                    }
                  });
                }
              }
            }

            return AlertDialog(
              title: Text(offer == null ? 'Create Offer' : 'Edit Offer'),
              content: SizedBox(
                width: 450,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: titleController,
                          decoration: const InputDecoration(labelText: 'Offer Title/Name*'),
                          validator: (v) => v == null || v.isEmpty ? 'Title required' : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: discountType,
                                decoration: const InputDecoration(labelText: 'Discount Type'),
                                items: const [
                                  DropdownMenuItem(value: 'percentage', child: Text('Percentage (%)')),
                                  DropdownMenuItem(value: 'flat', child: Text('Flat Cash (₹)')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => discountType = val);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: discountAmountController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Discount Value*'),
                                validator: (v) => v == null || double.tryParse(v) == null ? 'Invalid discount value' : null,
                              ),
                            ),
                          ],
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: targetScope,
                          decoration: const InputDecoration(labelText: 'Target Scope'),
                          items: const [
                            DropdownMenuItem(value: 'Entire Store', child: Text('Entire Store')),
                            DropdownMenuItem(value: 'Products', child: Text('Select Products')),
                            DropdownMenuItem(value: 'Categories', child: Text('Select Categories')),
                            DropdownMenuItem(value: 'Brands', child: Text('Select Brands')),
                            DropdownMenuItem(value: 'Variants', child: Text('Select Variants')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => targetScope = val);
                            }
                          },
                        ),
                        if (targetScope != 'Entire Store')
                          TextFormField(
                            controller: targetDetailsController,
                            decoration: const InputDecoration(
                              labelText: 'Target Detail IDs/Names',
                              hintText: 'comma separated list e.g. milk, egg',
                              helperText: 'Enter matching categories, products, or brands.',
                            ),
                            validator: (v) => targetScope != 'Entire Store' && (v == null || v.isEmpty) ? 'Detail targets required' : null,
                          ),
                        DropdownButtonFormField<int>(
                          initialValue: priority,
                          decoration: const InputDecoration(labelText: 'Priority Level (Conflict Resolution)'),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('Low Priority (1)')),
                            DropdownMenuItem(value: 2, child: Text('Category Offer (2)')),
                            DropdownMenuItem(value: 3, child: Text('Product Offer (3)')),
                            DropdownMenuItem(value: 4, child: Text('Festival Offer (4)')),
                            DropdownMenuItem(value: 5, child: Text('High/Flash Sale (5)')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => priority = val);
                            }
                          },
                        ),
                        const Divider(height: 24),
                        const Text('Scheduling', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => pickDateTime(true),
                                child: Text('Start: ${DateFormat('dd MMM hh:mm a').format(startDateTime)}', style: const TextStyle(fontSize: 11)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => pickDateTime(false),
                                child: Text('End: ${DateFormat('dd MMM hh:mm a').format(endDateTime)}', style: const TextStyle(fontSize: 11)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('Show Countdown Timer'),
                          value: countdownEnabled,
                          activeThumbColor: AppColors.primary,
                          onChanged: (val) => setDialogState(() => countdownEnabled = val),
                        ),
                        SwitchListTile(
                          title: const Text('Enable Offer'),
                          value: isActive,
                          activeThumbColor: AppColors.primary,
                          onChanged: (val) => setDialogState(() => isActive = val),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() ?? false) {
                      final discountAmt = double.parse(discountAmountController.text);
                      final detailsList = targetDetailsController.text.split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();

                      final newOffer = OfferModel(
                        id: offer?.id ?? '',
                        title: titleController.text.trim(),
                        offerType: discountType == 'percentage' ? 'Percentage Discount' : 'Flat Discount',
                        discountType: discountType,
                        discountValue: discountAmt,
                        targetType: targetScope,
                        targetIds: detailsList,
                        priority: priority,
                        startDateTime: startDateTime,
                        endDateTime: endDateTime,
                        isActive: isActive,
                        countdownEnabled: countdownEnabled,
                      );

                      if (offer == null) {
                        await widget.firestoreService.addOffer(newOffer);
                      } else {
                        await widget.firestoreService.updateOffer(newOffer);
                      }
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteOffer(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Offer'),
        content: const Text('Are you sure you want to delete this discount offer?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await widget.firestoreService.deleteOffer(id);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. FLASH SALE MANAGER VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _FlashSaleManagerView extends StatefulWidget {
  final FirestoreService firestoreService;
  const _FlashSaleManagerView({required this.firestoreService});

  @override
  State<_FlashSaleManagerView> createState() => _FlashSaleManagerViewState();
}

class _FlashSaleManagerViewState extends State<_FlashSaleManagerView> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FlashSaleModel>>(
      stream: widget.firestoreService.flashSalesStream(includeInactive: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final sales = snapshot.data ?? [];
        if (sales.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('No flash sales scheduled yet.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showAddEditFlashSaleDialog(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Flash Sale'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                )
              ],
            ),
          );
        }

        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddEditFlashSaleDialog(null),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add),
          ),
          body: ListView.builder(
            itemCount: sales.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final sale = sales[index];
              final isActive = sale.isActive && sale.isCurrentlyActive;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  title: Text(sale.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'Targets: ${sale.targetIds.join(', ')} (${sale.targetType})\n'
                    'Discount: ${sale.discountValue}${sale.discountType == 'percentage' ? '%' : '₹'} Off\n'
                    'Active: ${DateFormat('dd MMM hh:mm a').format(sale.startDateTime)} to ${DateFormat('dd MMM hh:mm a').format(sale.endDateTime)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isActive ? 'Active' : 'Inactive/Expired',
                          style: TextStyle(color: isActive ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showAddEditFlashSaleDialog(sale),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDeleteFlashSale(sale.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showAddEditFlashSaleDialog(FlashSaleModel? sale) {
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController(text: sale?.title ?? '');
    final discountAmountController = TextEditingController(text: sale?.discountValue.toString() ?? '15');
    String discountType = sale?.discountType ?? 'percentage';
    String targetScope = sale?.targetType ?? 'Products';
    final targetDetailsController = TextEditingController(text: sale?.targetIds.join(', ') ?? '');

    DateTime startDateTime = sale?.startDateTime ?? DateTime.now();
    DateTime endDateTime = sale?.endDateTime ?? DateTime.now().add(const Duration(hours: 4));
    bool isActive = sale?.isActive ?? true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickDateTime(bool isStart) async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: isStart ? startDateTime : endDateTime,
                firstDate: DateTime(2025),
                lastDate: DateTime(2030),
              );
              if (pickedDate != null) {
                if (!context.mounted) return;
                final pickedTime = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(isStart ? startDateTime : endDateTime),
                );
                if (pickedTime != null) {
                  setDialogState(() {
                    final dt = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
                    if (isStart) {
                      startDateTime = dt;
                    } else {
                      endDateTime = dt;
                    }
                  });
                }
              }
            }

            return AlertDialog(
              title: Text(sale == null ? 'Schedule Flash Sale' : 'Edit Flash Sale'),
              content: SizedBox(
                width: 450,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: titleController,
                          decoration: const InputDecoration(labelText: 'Campaign Name/Title*'),
                          validator: (v) => v == null || v.isEmpty ? 'Title required' : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: discountType,
                                decoration: const InputDecoration(labelText: 'Discount Type'),
                                items: const [
                                  DropdownMenuItem(value: 'percentage', child: Text('Percentage (%)')),
                                  DropdownMenuItem(value: 'flat', child: Text('Flat Cash (₹)')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => discountType = val);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: discountAmountController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Discount Value*'),
                                validator: (v) => v == null || double.tryParse(v) == null ? 'Invalid discount value' : null,
                              ),
                            ),
                          ],
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: targetScope,
                          decoration: const InputDecoration(labelText: 'Target Scope'),
                          items: const [
                            DropdownMenuItem(value: 'Products', child: Text('Select Products')),
                            DropdownMenuItem(value: 'Categories', child: Text('Select Categories')),
                            DropdownMenuItem(value: 'Variants', child: Text('Select Variants')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => targetScope = val);
                            }
                          },
                        ),
                        TextFormField(
                          controller: targetDetailsController,
                          decoration: const InputDecoration(
                            labelText: 'Target Detail IDs/Names*',
                            hintText: 'comma separated list e.g. milk, eggs',
                          ),
                          validator: (v) => v == null || v.isEmpty ? 'Flash targets required' : null,
                        ),
                        const Divider(height: 24),
                        const Text('Scheduling', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => pickDateTime(true),
                                child: Text('Start: ${DateFormat('dd MMM hh:mm a').format(startDateTime)}', style: const TextStyle(fontSize: 11)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => pickDateTime(false),
                                child: Text('End: ${DateFormat('dd MMM hh:mm a').format(endDateTime)}', style: const TextStyle(fontSize: 11)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('Enable Flash Sale'),
                          value: isActive,
                          activeThumbColor: AppColors.primary,
                          onChanged: (val) => setDialogState(() => isActive = val),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() ?? false) {
                      final discountAmt = double.parse(discountAmountController.text);
                      final detailsList = targetDetailsController.text.split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();

                      final newSale = FlashSaleModel(
                        id: sale?.id ?? '',
                        title: titleController.text.trim(),
                        discountType: discountType,
                        discountValue: discountAmt,
                        targetType: targetScope,
                        targetIds: detailsList,
                        startDateTime: startDateTime,
                        endDateTime: endDateTime,
                        isActive: isActive,
                      );

                      if (sale == null) {
                        await widget.firestoreService.addFlashSale(newSale);
                      } else {
                        await widget.firestoreService.updateFlashSale(newSale);
                      }
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteFlashSale(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Flash Sale'),
        content: const Text('Are you sure you want to delete this flash sale?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await widget.firestoreService.deleteFlashSale(id);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. COUPON MANAGER VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _CouponManagerView extends StatefulWidget {
  final FirestoreService firestoreService;
  const _CouponManagerView({required this.firestoreService});

  @override
  State<_CouponManagerView> createState() => _CouponManagerViewState();
}

class _CouponManagerViewState extends State<_CouponManagerView> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CouponModel>>(
      stream: widget.firestoreService.couponsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final coupons = snapshot.data ?? [];
        if (coupons.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('No coupon promo codes created yet.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showAddEditCouponDialog(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add First Coupon'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                )
              ],
            ),
          );
        }

        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddEditCouponDialog(null),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add),
          ),
          body: ListView.builder(
            itemCount: coupons.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final coupon = coupons[index];
              final isActive = coupon.isActive && coupon.isCurrentlyActive;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  title: Text(coupon.code, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  subtitle: Text(
                    'Value: ${coupon.discountValue}${coupon.discountType == 'percentage' ? '%' : '₹'} Off\n'
                    'Min Order: ₹${coupon.minOrderValue.toStringAsFixed(0)} | Max Discount: ₹${coupon.maxDiscount.toStringAsFixed(0)}\n'
                    'Expiry: ${DateFormat('dd MMM yyyy').format(coupon.endDateTime)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isActive ? 'Active' : 'Inactive/Expired',
                          style: TextStyle(color: isActive ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showAddEditCouponDialog(coupon),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDeleteCoupon(coupon.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showAddEditCouponDialog(CouponModel? coupon) {
    final formKey = GlobalKey<FormState>();
    final codeController = TextEditingController(text: coupon?.code ?? '');
    final discountAmountController = TextEditingController(text: coupon?.discountValue.toString() ?? '50');
    String discountType = coupon?.discountType ?? 'flat';
    final minOrderController = TextEditingController(text: coupon?.minOrderValue.toString() ?? '299');
    final maxDiscountController = TextEditingController(text: coupon?.maxDiscount.toString() ?? '');
    
    DateTime expiryDate = coupon?.endDateTime ?? DateTime.now().add(const Duration(days: 30));
    bool isActive = coupon?.isActive ?? true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickExpiryDate() async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: expiryDate,
                firstDate: DateTime.now(),
                lastDate: DateTime(2030),
              );
              if (pickedDate != null) {
                setDialogState(() {
                  expiryDate = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, 23, 59, 59);
                });
              }
            }

            return AlertDialog(
              title: Text(coupon == null ? 'Create Coupon' : 'Edit Coupon'),
              content: SizedBox(
                width: 450,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: codeController,
                          decoration: const InputDecoration(labelText: 'Coupon Code* (e.g. SAVE100)'),
                          validator: (v) => v == null || v.isEmpty ? 'Code required' : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: discountType,
                                decoration: const InputDecoration(labelText: 'Discount Type'),
                                items: const [
                                  DropdownMenuItem(value: 'percentage', child: Text('Percentage (%)')),
                                  DropdownMenuItem(value: 'flat', child: Text('Flat Cash (₹)')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => discountType = val);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: discountAmountController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Discount Value*'),
                                validator: (v) => v == null || double.tryParse(v) == null ? 'Invalid discount value' : null,
                              ),
                            ),
                          ],
                        ),
                        TextFormField(
                          controller: minOrderController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Min Order Value Required (₹)*'),
                          validator: (v) => v == null || double.tryParse(v) == null ? 'Invalid minimum value' : null,
                        ),
                        TextFormField(
                          controller: maxDiscountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Max Discount Amount Cap (₹, Optional)'),
                        ),
                        const Divider(height: 24),
                        const Text('Scheduling', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: pickExpiryDate,
                          icon: const Icon(Icons.calendar_today, size: 14),
                          label: Text('Expiry Date: ${DateFormat('dd MMM yyyy').format(expiryDate)}'),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('Enable Coupon'),
                          value: isActive,
                          activeThumbColor: AppColors.primary,
                          onChanged: (val) => setDialogState(() => isActive = val),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() ?? false) {
                      final discountAmt = double.parse(discountAmountController.text);
                      final minOrder = double.parse(minOrderController.text);
                      final maxDiscount = double.tryParse(maxDiscountController.text);

                      final newCoupon = CouponModel(
                        id: coupon?.id ?? '',
                        code: codeController.text.trim().toUpperCase(),
                        title: codeController.text.trim().toUpperCase(),
                        discountType: discountType,
                        discountValue: discountAmt,
                        minOrderValue: minOrder,
                        maxDiscount: maxDiscount ?? 9999.0,
                        startDateTime: coupon?.startDateTime ?? DateTime.now(),
                        endDateTime: expiryDate,
                        isActive: isActive,
                      );

                      if (coupon == null) {
                        await widget.firestoreService.addCoupon(newCoupon);
                      } else {
                        await widget.firestoreService.updateCoupon(newCoupon);
                      }
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteCoupon(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Coupon'),
        content: const Text('Are you sure you want to delete this promo coupon?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await widget.firestoreService.deleteCoupon(id);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. BANNER ANALYTICS VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _BannerAnalyticsView extends StatelessWidget {
  final FirestoreService firestoreService;
  const _BannerAnalyticsView({required this.firestoreService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: firestoreService.allBannerAnalyticsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return const Center(
            child: Text('No marketing analytics tracked yet.', style: TextStyle(color: Colors.grey)),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Card(
                color: Colors.blueAccent,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Marketing Conversion Tracker',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Track Banner impressions, clicks, conversions, total store sales, and customer savings dynamically.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                  columns: const [
                    DataColumn(label: Text('Banner Name', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Views', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Clicks', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('CTR', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Sales Count', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Revenue (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Saved (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: list.map((item) {
                    final title = item['title'] as String? ?? item['id'] as String? ?? 'Untitled Banner';
                    final views = item['views'] as int? ?? 0;
                    final clicks = item['clicks'] as int? ?? 0;
                    final conversions = item['conversions'] as int? ?? 0;
                    final revenue = (item['revenue'] as num?)?.toDouble() ?? 0.0;
                    final discountGiven = (item['discountGiven'] as num?)?.toDouble() ?? 0.0;

                    final ctr = views > 0 ? (clicks / views) * 100 : 0.0;

                    return DataRow(cells: [
                      DataCell(Text(title, style: const TextStyle(fontWeight: FontWeight.w500))),
                      DataCell(Text('$views')),
                      DataCell(Text('$clicks')),
                      DataCell(Text('${ctr.toStringAsFixed(1)}%')),
                      DataCell(Text('$conversions')),
                      DataCell(Text('₹${revenue.toStringAsFixed(0)}')),
                      DataCell(Text('₹${discountGiven.toStringAsFixed(0)}')),
                    ]);
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
