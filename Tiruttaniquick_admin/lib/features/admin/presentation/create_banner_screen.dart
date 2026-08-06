import 'dart:async';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CreateBannerScreen extends StatefulWidget {
  final BannerModel? banner;

  const CreateBannerScreen({super.key, this.banner});

  @override
  State<CreateBannerScreen> createState() => _CreateBannerScreenState();
}

class _CreateBannerScreenState extends State<CreateBannerScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();

  // Basic Details
  late TextEditingController _titleController;
  late TextEditingController _subtitleController;
  late TextEditingController _descriptionController;
  late String _bannerType;

  // Image Settings
  late TextEditingController _imageUrlController;

  // Action Settings
  late String _actionType;
  late TextEditingController _actionTargetController;
  String _selectedItemName = ''; // Friendly name for selected product/category

  // Offer Settings
  late String _offerType;
  late TextEditingController _discountValueController;
  late String _targetScope;
  late TextEditingController _targetDetailsController;

  // Scheduling
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;
  late bool _countdownEnabled;
  late bool _repeatOffer;
  late bool _isEnabled;

  // Preview Ticking Simulated Countdown
  Duration _simulatedCountdown = const Duration(days: 3, hours: 4, minutes: 12, seconds: 30);
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    final b = widget.banner;

    // Load initial values
    _titleController = TextEditingController(text: b?.title ?? '');
    _subtitleController = TextEditingController(text: b?.subtitle ?? '');
    _descriptionController = TextEditingController(text: b?.description ?? '');
    _bannerType = b?.bannerType ?? 'Promo Banner';

    _imageUrlController = TextEditingController(text: b?.imageUrl ?? '');

    _actionType = b?.actionType ?? 'Open Offer Page';
    _actionTargetController = TextEditingController(text: b?.actionTarget ?? '');
    _selectedItemName = b?.actionTarget.isNotEmpty == true ? 'Loaded: ${b?.actionTarget}' : '';

    _offerType = b?.offerType ?? 'Percentage Discount';
    _discountValueController = TextEditingController(text: b?.discountValue.toString() ?? '0');
    _targetScope = b?.targetType ?? 'Entire Store';
    _targetDetailsController = TextEditingController(text: b?.targetIds.join(', ') ?? '');

    _startDate = b?.startDateTime ?? DateTime.now();
    _startTime = TimeOfDay.fromDateTime(b?.startDateTime ?? DateTime.now());
    _endDate = b?.endDateTime ?? DateTime.now().add(const Duration(days: 7));
    _endTime = TimeOfDay.fromDateTime(b?.endDateTime ?? DateTime.now().add(const Duration(days: 7)));

    _countdownEnabled = b?.countdownEnabled ?? true;
    _repeatOffer = false;
    _isEnabled = b?.isActive ?? true;

    // Start simulation countdown ticking
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_simulatedCountdown.inSeconds > 0) {
            _simulatedCountdown = _simulatedCountdown - const Duration(seconds: 1);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _titleController.dispose();
    _subtitleController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    _actionTargetController.dispose();
    _discountValueController.dispose();
    _targetDetailsController.dispose();
    super.dispose();
  }

  DateTime get _startDateTime {
    return DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime.hour,
      _startTime.minute,
    );
  }

  DateTime get _endDateTime {
    return DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      _endTime.hour,
      _endTime.minute,
    );
  }

  // Pick Date
  Future<void> _pickDate(bool isStart) async {
    final initialDate = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            onSurface: AppColors.text,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  // Pick Time
  Future<void> _pickTime(bool isStart) async {
    final initialTime = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            onSurface: AppColors.text,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  // Search and Select Target Item Sheet
  void _openSearchPicker() {
    String collection = 'products';
    if (_actionType == 'Open Category' || _targetScope == 'Categories') {
      collection = 'categories';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            'Select ${collection == 'products' ? 'Product' : 'Category'}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          )
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        onChanged: (v) {
                          setSheetState(() => query = v.trim().toLowerCase());
                        },
                        decoration: InputDecoration(
                          hintText: 'Search items by name...',
                          prefixIcon: const Icon(Icons.search),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection(collection).snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final docs = snapshot.data?.docs ?? [];
                          final filtered = docs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final name = (data['productName'] ?? data['name'] ?? '').toString().toLowerCase();
                            return name.contains(query);
                          }).toList();

                          if (filtered.isEmpty) {
                            return const Center(
                              child: Text('No matching items found', style: TextStyle(color: Colors.grey)),
                            );
                          }

                          return ListView.builder(
                            controller: scrollController,
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final doc = filtered[index];
                              final data = doc.data() as Map<String, dynamic>;
                              final name = (data['productName'] ?? data['name'] ?? 'Unnamed').toString();
                              final sub = data['brand']?.toString() ?? data['description']?.toString() ?? '';

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                  child: const Icon(Icons.shopping_bag_outlined, color: AppColors.primary, size: 20),
                                ),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: sub.isNotEmpty ? Text(sub, style: const TextStyle(fontSize: 11)) : null,
                                trailing: const Icon(Icons.chevron_right, size: 18),
                                onTap: () {
                                  setState(() {
                                    _actionTargetController.text = doc.id;
                                    _selectedItemName = name;
                                  });
                                  Navigator.pop(context);
                                },
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
      },
    );
  }

  // Simulated upload source dialog
  void _simulateUpload(String source) {
    setState(() {
      // Inject dummy mock image URL depending on banner theme
      _imageUrlController.text = source == 'Camera' 
          ? 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=1080&q=80'
          : 'https://images.unsplash.com/photo-1578916171728-46686eac8d58?w=1080&q=80';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Simulated upload completed via $source!')),
    );
  }

  // Publish / Save function
  Future<void> _publishBanner() async {
    if (_formKey.currentState?.validate() ?? false) {
      final discountAmt = double.tryParse(_discountValueController.text) ?? 0.0;
      final detailsList = _targetDetailsController.text.split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final newBanner = BannerModel(
        id: widget.banner?.id ?? '',
        title: _titleController.text.trim(),
        subtitle: _subtitleController.text.trim(),
        imageUrl: _imageUrlController.text.trim(),
        bannerType: _bannerType,
        offerType: discountAmt > 0
            ? (_offerType)
            : 'None',
        discountType: discountAmt > 0 ? (_offerType == 'Flat Discount' ? 'flat' : 'percentage') : 'percentage',
        discountValue: discountAmt,
        targetType: _targetScope,
        targetIds: detailsList,
        actionType: _actionType,
        actionTarget: _actionTargetController.text.trim(),
        displayOrder: widget.banner?.displayOrder ?? 0,
        isActive: _isEnabled,
        countdownEnabled: _countdownEnabled,
        startDateTime: _startDateTime,
        endDateTime: _endDateTime,
      );

      try {
        if (widget.banner == null) {
          await _firestoreService.addBanner(newBanner);
        } else {
          await _firestoreService.updateBanner(newBanner);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Banner saved successfully!')),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save banner: $e')),
          );
        }
      }
    }
  }

  // Simulated Customer App preview layout
  Widget _buildSimulationPreview() {
    final title = _titleController.text.isEmpty ? 'Simulated Banner Title' : _titleController.text;
    final subtitle = _subtitleController.text;
    final url = _imageUrlController.text;
    final discountVal = double.tryParse(_discountValueController.text) ?? 0.0;
    
    // Format ticker countdown
    final hours = _simulatedCountdown.inHours.toString().padLeft(2, '0');
    final mins = (_simulatedCountdown.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (_simulatedCountdown.inSeconds % 60).toString().padLeft(2, '0');

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 1080 / 450, // standard banner aspect ratio
        child: Stack(
          children: [
            // Image
            url.isNotEmpty
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (context, _, __) => Container(
                      color: Colors.grey.shade100,
                      child: const Center(child: Icon(Icons.broken_image, size: 40, color: Colors.grey)),
                    ),
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal, Colors.tealAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
            // Glass overlay / dark gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black.withValues(alpha: 0.65), Colors.black.withValues(alpha: 0.1)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
            // Text overlays
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _bannerType.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                  if (discountVal > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      _offerType == 'Percentage Discount' 
                          ? '${discountVal.toStringAsFixed(0)}% OFF'
                          : '₹${discountVal.toStringAsFixed(0)} CASHBACK',
                      style: const TextStyle(color: Colors.yellow, fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                  ],
                ],
              ),
            ),
            // Ticking countdown timer simulation overlay (Bottom Right)
            if (_countdownEnabled)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.yellow.withValues(alpha: 0.5), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, color: Colors.yellow, size: 10),
                      const SizedBox(width: 4),
                      Text(
                        'Ends in $hours:$mins:$secs',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ),
            // Carousel Dots Indicator simulation (Bottom Left)
            Positioned(
              bottom: 8,
              left: 16,
              child: Row(
                children: List.generate(4, (index) {
                  return Container(
                    width: index == 0 ? 14 : 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: index == 0 ? Colors.white : Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Cancel',
        ),
        title: Text(
          widget.banner == null ? 'Create Banner' : 'Edit Banner',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: _publishBanner,
            child: const Text('Save Draft', style: TextStyle(color: Colors.grey)),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'reset') {
                _formKey.currentState?.reset();
                setState(() {
                  _titleController.clear();
                  _subtitleController.clear();
                  _imageUrlController.clear();
                  _actionTargetController.clear();
                  _discountValueController.clear();
                  _targetDetailsController.clear();
                });
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'reset', child: Text('Reset Fields')),
            ],
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Section 1: Banner Details
                    _buildSectionHeader(title: '1. Banner Details', icon: Icons.description_outlined),
                    _buildSectionCard(
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _titleController,
                            decoration: const InputDecoration(labelText: 'Banner Title*'),
                            validator: (v) => v == null || v.isEmpty ? 'Title required' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _subtitleController,
                            decoration: const InputDecoration(labelText: 'Subtitle (e.g. Fresh dairy items)'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _descriptionController,
                            maxLines: 2,
                            decoration: const InputDecoration(labelText: 'Extended Campaign Description'),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _bannerType,
                            decoration: const InputDecoration(labelText: 'Banner Category Type'),
                            items: const [
                              DropdownMenuItem(value: 'Promo Banner', child: Text('Promo / Offer Banner')),
                              DropdownMenuItem(value: 'Flash Sale', child: Text('Flash Sale Banner')),
                              DropdownMenuItem(value: 'Festival Offer', child: Text('Festival Offer')),
                              DropdownMenuItem(value: 'General Announcement', child: Text('General Info/Announcement')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _bannerType = val);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Section 2: Banner Image
                    _buildSectionHeader(title: '2. Banner Graphic Image', icon: Icons.image_outlined),
                    _buildSectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _imageUrlController,
                            decoration: const InputDecoration(labelText: 'Image Web URL*'),
                            validator: (v) => v == null || v.isEmpty ? 'Image URL required' : null,
                            onChanged: (v) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          // Picker Box
                          Container(
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildSimulatedPickerButton(
                                  label: 'Gallery',
                                  icon: Icons.photo_library_outlined,
                                  onTap: () => _simulateUpload('Gallery'),
                                ),
                                Container(width: 1, height: 60, color: Colors.grey.shade200),
                                _buildSimulatedPickerButton(
                                  label: 'Camera',
                                  icon: Icons.camera_alt_outlined,
                                  onTap: () => _simulateUpload('Camera'),
                                ),
                                Container(width: 1, height: 60, color: Colors.grey.shade200),
                                _buildSimulatedPickerButton(
                                  label: 'Crop Image',
                                  icon: Icons.crop_outlined,
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Simulated crop/adjust completed!')),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Row(
                            children: [
                              Icon(Icons.info_outline, size: 14, color: Colors.blue),
                              SizedBox(width: 6),
                              Text('Recommended Size: 1080 × 450 px (Aspect 12:5)', style: TextStyle(color: Colors.grey, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Section 3: Banner Action Settings
                    _buildSectionHeader(title: '3. Tap Action Target', icon: Icons.touch_app_outlined),
                    _buildSectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _actionType,
                            decoration: const InputDecoration(labelText: 'Click Action Destination'),
                            items: const [
                              DropdownMenuItem(value: 'Open Product', child: Text('Open Product Details')),
                              DropdownMenuItem(value: 'Open Category', child: Text('Open Category Products')),
                              DropdownMenuItem(value: 'Open Brand', child: Text('Filter by Brand Search')),
                              DropdownMenuItem(value: 'Open Offer Page', child: Text('Open Banner Promo Products')),
                              DropdownMenuItem(value: 'External URL', child: Text('Open External Web Link')),
                              DropdownMenuItem(value: 'No Action', child: Text('Static Graphic (No Action)')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _actionType = val;
                                  _actionTargetController.clear();
                                  _selectedItemName = '';
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          // Searchable Picker Button for Products / Categories
                          if (_actionType == 'Open Product' || _actionType == 'Open Category') ...[
                            ElevatedButton.icon(
                              onPressed: _openSearchPicker,
                              icon: const Icon(Icons.search, size: 16),
                              label: Text(
                                _selectedItemName.isNotEmpty 
                                    ? 'Change: $_selectedItemName'
                                    : 'Search & Select ${_actionType == 'Open Product' ? 'Product' : 'Category'}',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                foregroundColor: AppColors.primary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          TextFormField(
                            controller: _actionTargetController,
                            decoration: InputDecoration(
                              labelText: 'Target Payload Value*',
                              hintText: _actionType == 'External URL' ? 'https://google.com' : 'Auto-filled ID or keyword',
                            ),
                            validator: (v) => _actionType != 'No Action' && (v == null || v.isEmpty)
                                ? 'Target payload required'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Section 4: Offer Settings
                    _buildSectionHeader(title: '4. Target Offer & Discounts', icon: Icons.local_offer_outlined),
                    _buildSectionCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                 child: DropdownButtonFormField<String>(
                                  initialValue: _offerType,
                                  decoration: const InputDecoration(labelText: 'Discount System'),
                                  items: const [
                                    DropdownMenuItem(value: 'Percentage Discount', child: Text('Percentage (%)')),
                                    DropdownMenuItem(value: 'Flat Discount', child: Text('Flat Cash (₹)')),
                                    DropdownMenuItem(value: 'Buy 1 Get 1', child: Text('BOGO (Buy 1 Get 1)')),
                                    DropdownMenuItem(value: 'Flash Sale Special', child: Text('Flash Sale')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _offerType = val);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _discountValueController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'Discount Value'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _targetScope,
                            decoration: const InputDecoration(labelText: 'Applies to Target'),
                            items: const [
                              DropdownMenuItem(value: 'Entire Store', child: Text('Entire Store Catalog')),
                              DropdownMenuItem(value: 'Products', child: Text('Selected Products')),
                              DropdownMenuItem(value: 'Categories', child: Text('Selected Categories')),
                              DropdownMenuItem(value: 'Brands', child: Text('Selected Brands')),
                              DropdownMenuItem(value: 'Variants', child: Text('Selected Variants')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _targetScope = val;
                                });
                              }
                            },
                          ),
                          if (_targetScope != 'Entire Store') ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _targetDetailsController,
                              decoration: const InputDecoration(
                                labelText: 'Applied Target IDs*',
                                hintText: 'comma separated list e.g. milk, eggs',
                              ),
                              validator: (v) => _targetScope != 'Entire Store' && (v == null || v.isEmpty)
                                  ? 'Target scoping details required'
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Section 5: Scheduling
                    _buildSectionHeader(title: '5. Date Schedule', icon: Icons.date_range_outlined),
                    _buildSectionCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: () => _pickDate(true),
                                  icon: const Icon(Icons.calendar_month, size: 16),
                                  label: Text('Start: ${DateFormat('dd MMM').format(_startDate)}'),
                                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                                ),
                              ),
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: () => _pickTime(true),
                                  icon: const Icon(Icons.access_time, size: 16),
                                  label: Text(_startTime.format(context)),
                                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: () => _pickDate(false),
                                  icon: const Icon(Icons.calendar_month, size: 16),
                                  label: Text('End: ${DateFormat('dd MMM').format(_endDate)}'),
                                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                                ),
                              ),
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: () => _pickTime(false),
                                  icon: const Icon(Icons.access_time, size: 16),
                                  label: Text(_endTime.format(context)),
                                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Show Live Countdown Alert', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: const Text('Ticks down on customer app banner', style: TextStyle(fontSize: 11)),
                            value: _countdownEnabled,
                            activeThumbColor: AppColors.primary,
                            onChanged: (val) => setState(() => _countdownEnabled = val),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Repeat Offer Weekly', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            value: _repeatOffer,
                            activeThumbColor: AppColors.primary,
                            onChanged: (val) => setState(() => _repeatOffer = val),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Publish Immediately', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            value: _isEnabled,
                            activeThumbColor: AppColors.primary,
                            onChanged: (val) => setState(() => _isEnabled = val),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Section 6: Real-time Simulation Preview
                    _buildSectionHeader(title: '6. Customer App Banner Preview', icon: Icons.preview_outlined),
                    _buildSimulationPreview(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            // Bottom Sticky Navigation Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.grey.shade200, blurRadius: 4, offset: const Offset(0, -2)),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _publishBanner,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Publish Banner'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({required String title, required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required Widget child}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: child,
      ),
    );
  }

  Widget _buildSimulatedPickerButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        width: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: AppColors.primary),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
