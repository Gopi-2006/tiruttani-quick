import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class AddEditProductScreen extends StatefulWidget {
  final ProductModel? product;
  final FirestoreService firestore;

  const AddEditProductScreen({
    super.key,
    this.product,
    required this.firestore,
  });

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isEdit = false;
  String? _editingProductId;

  // Form controllers & values
  final _nameController = TextEditingController();
  final _tamilNameController = TextEditingController();
  final _brandController = TextEditingController();
  final _categoryController = TextEditingController();
  final _categoryNameController = TextEditingController();
  final _subCategoryController = TextEditingController();
  
  // Section 2: Images
  final _imageUrlController = TextEditingController();
  List<String> _additionalImages = [];
  bool _isUploadingMain = false;
  bool _isUploadingAdditional = false;
  double _uploadProgress = 0.0;

  // Section 3: Pricing (Single product)
  final _purchasePriceController = TextEditingController();
  final _mrpController = TextEditingController();
  final _sellingPriceController = TextEditingController();

  // Section 4: Inventory (Single product)
  final _stockController = TextEditingController();
  final _minStockController = TextEditingController();
  final _maxStockController = TextEditingController();

  // Section 5: Variants
  bool _variantsEnabled = false;
  List<Map<String, dynamic>> _variants = [];

  // Section 6: Descriptions
  final _descriptionController = TextEditingController();
  final _longDescriptionController = TextEditingController();
  final _ingredientsController = TextEditingController();
  final _storageInstructionsController = TextEditingController();

  // Section 7: SEO
  final _keywordsController = TextEditingController();
  final _tagsController = TextEditingController();
  final _metaTitleController = TextEditingController();
  final _metaDescriptionController = TextEditingController();
  final _slugController = TextEditingController();

  // Section 8: Visibility & Badges
  bool _isActive = true;
  bool _isFeatured = false;
  bool _isTodayDeal = false;
  bool _isTrending = false;
  bool _isRecommended = false;
  bool _isBestSeller = false;
  bool _isNewArrival = false;
  bool _enableReviews = true;
  bool _enableWishlist = true;

  // Section 9: Offers
  final _couponCodeController = TextEditingController();
  bool _buyOneGetOne = false;
  bool _isFlashSale = false;
  bool _isComboOffer = false;
  bool _isLimitedTimeOffer = false;

  // Additional Dropdown values
  String _selectedUnit = 'g';
  String _selectedSupplier = 'Main Supplier A';
  String _selectedWarehouse = 'Main Central Warehouse';

  // Expansion panel states
  final List<bool> _isOpen = List.generate(9, (index) => index == 0); // Open first by default

  // Auto-save timer
  Timer? _autoSaveTimer;

  // Checklist Validation Statuses
  bool get _isBasicValid => _nameController.text.isNotEmpty && _categoryController.text.isNotEmpty;
  bool get _isPricingValid => _variantsEnabled 
      ? _variants.isNotEmpty && _variants.every((v) => (v['price'] ?? 0.0) > 0.0)
      : (_sellingPriceController.text.isNotEmpty && (double.tryParse(_sellingPriceController.text) ?? 0.0) > 0.0);
  bool get _isInventoryValid => _variantsEnabled 
      ? _variants.isNotEmpty && _variants.every((v) => (v['stockQuantity'] ?? 0) >= 0)
      : _stockController.text.isNotEmpty;
  bool get _isVariantsValid => !_variantsEnabled || (_variants.isNotEmpty && _variants.every((v) => v['name'] != null && v['name'].toString().isNotEmpty));
  bool get _isImagesValid => _imageUrlController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.product != null;
    
    // Setup listeners for live calculations
    _mrpController.addListener(_calculatePricingStats);
    _sellingPriceController.addListener(_calculatePricingStats);
    _purchasePriceController.addListener(_calculatePricingStats);

    // Auto slugify
    _nameController.addListener(() {
      if (!_isEdit && _slugController.text.isEmpty) {
        _slugController.text = _nameController.text
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
            .replaceAll(RegExp(r'\s+'), '-');
      }
    });

    if (_isEdit) {
      _loadProductData(widget.product!);
    } else {
      _loadDraftIfExists();
    }

    // Start 30-second Auto-save draft timer
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _autoSaveDraft();
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _nameController.dispose();
    _tamilNameController.dispose();
    _brandController.dispose();
    _categoryController.dispose();
    _categoryNameController.dispose();
    _subCategoryController.dispose();
    _imageUrlController.dispose();
    _purchasePriceController.dispose();
    _mrpController.dispose();
    _sellingPriceController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
    _maxStockController.dispose();
    _descriptionController.dispose();
    _longDescriptionController.dispose();
    _ingredientsController.dispose();
    _storageInstructionsController.dispose();
    _keywordsController.dispose();
    _tagsController.dispose();
    _metaTitleController.dispose();
    _metaDescriptionController.dispose();
    _slugController.dispose();
    _couponCodeController.dispose();
    super.dispose();
  }

  // Calculate Profit, Margin %, Discount amount & percentage in real time
  double _profit = 0.0;
  double _marginPercent = 0.0;
  double _discountAmount = 0.0;
  double _discountPercent = 0.0;

  void _calculatePricingStats() {
    final mrp = double.tryParse(_mrpController.text) ?? 0.0;
    final selling = double.tryParse(_sellingPriceController.text) ?? 0.0;
    final purchase = double.tryParse(_purchasePriceController.text) ?? 0.0;

    setState(() {
      _discountAmount = (mrp > selling) ? mrp - selling : 0.0;
      _discountPercent = (mrp > 0 && mrp > selling) ? (_discountAmount / mrp) * 100 : 0.0;
      _profit = (selling > purchase) ? selling - purchase : 0.0;
      _marginPercent = (selling > 0) ? (_profit / selling) * 100 : 0.0;
    });
  }

  void _loadProductData(ProductModel p) {
    _editingProductId = p.id;
    _nameController.text = p.name;
    _tamilNameController.text = p.nameTamil;
    _imageUrlController.text = p.imageUrl;
    _categoryController.text = p.categoryId;
    _brandController.text = p.brand;
    _subCategoryController.text = p.subCategoryId;
    
    _sellingPriceController.text = p.price.toString();
    _mrpController.text = p.mrp.toString();
    // Default mock purchase price to 75% of price if zero
    _purchasePriceController.text = (p.price * 0.75).toStringAsFixed(1);
    
    _stockController.text = p.stockQuantity.toString();
    _minStockController.text = p.lowStockThreshold.toString();
    _maxStockController.text = p.maxStock.toString();

    _variantsEnabled = p.variantsEnabled;
    _variants = p.variants.map((v) => v.toMap()).toList();

    _descriptionController.text = p.description;
    _longDescriptionController.text = p.longDescription;
    _ingredientsController.text = p.ingredients;
    _storageInstructionsController.text = p.storageInstructions;

    _keywordsController.text = p.searchKeywords.join(', ');
    _tagsController.text = p.tags.join(', ');
    _metaTitleController.text = p.metaTitle;
    _metaDescriptionController.text = p.metaDescription;
    _slugController.text = p.slug;

    _isActive = p.isActive;
    _isFeatured = p.isFeatured;
    _isTodayDeal = p.isTodayDeal;
    _isTrending = p.isTrending;
    _isRecommended = p.isRecommended;
    _isBestSeller = p.isBestSeller;
    _isNewArrival = p.isNewArrival;
    _enableReviews = p.enableReviews;
    _enableWishlist = p.enableWishlist;

    _couponCodeController.text = p.couponCode;
    _buyOneGetOne = p.buyOneGetOne;
    _isFlashSale = p.isFlashSale;
    _isComboOffer = p.isComboOffer;
    _isLimitedTimeOffer = p.isLimitedTimeOffer;

    _selectedUnit = p.unit.isNotEmpty ? p.unit : 'g';
    _additionalImages = List<String>.from(p.productImages);

    _calculatePricingStats();
  }

  // Draft Auto-Save Helpers
  Future<void> _autoSaveDraft() async {
    if (_isEdit) return; // Don't auto-save draft when editing a real product
    try {
      final draft = _buildProductModel(id: 'draft');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/product_draft.json');
      await file.writeAsString(jsonEncode(draft.toMap()));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Draft auto-saved at ${_formatTime(DateTime.now())}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.grey.shade800,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving draft: $e');
    }
  }

  Future<void> _loadDraftIfExists() async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/product_draft.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        final draftProduct = ProductModel.fromFirestore('draft', data);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Loaded previously saved draft!'),
              action: SnackBarAction(
                label: 'Clear',
                onPressed: () async {
                  if (await file.exists()) await file.delete();
                },
              ),
            ),
          );
          setState(() {
            _loadProductData(draftProduct);
            _editingProductId = null; // Still in create mode
            _isEdit = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading draft: $e');
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  // Image Selection and Mock Compression/Upload
  Future<void> _pickAndUploadImage({bool isMain = true}) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        setState(() {
          if (isMain) {
            _isUploadingMain = true;
          } else {
            _isUploadingAdditional = true;
          }
          _uploadProgress = 0.1;
        });

        // Step 1: Compress simulation
        await Future.delayed(const Duration(milliseconds: 600));
        setState(() {
          _uploadProgress = 0.4;
        });

        // Step 2: Upload simulation
        await Future.delayed(const Duration(milliseconds: 800));
        setState(() {
          _uploadProgress = 0.8;
        });

        await Future.delayed(const Duration(milliseconds: 600));
        
        // Mock successful URL based on category or random picsum images
        final mockUrl = 'https://picsum.photos/id/${(10 + (DateTime.now().millisecond % 90))}/600/600';

        setState(() {
          _uploadProgress = 1.0;
          if (isMain) {
            _imageUrlController.text = mockUrl;
            _isUploadingMain = false;
          } else {
            if (_additionalImages.length < 10) {
              _additionalImages.add(mockUrl);
            }
            _isUploadingAdditional = false;
          }
        });
      }
    } catch (e) {
      setState(() {
        _isUploadingMain = false;
        _isUploadingAdditional = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  // Build model helper
  ProductModel _buildProductModel({required String id}) {
    final List<ProductVariantModel> finalVariants = _variantsEnabled
        ? _variants.map((v) {
            final mrp = (v['mrp'] as num?)?.toDouble() ?? 0.0;
            final price = (v['price'] as num?)?.toDouble() ?? 0.0;
            double discount = (v['discount'] as num?)?.toDouble() ?? 0.0;
            if (discount == 0.0 && mrp > price && mrp > 0) {
              discount = (((mrp - price) / mrp) * 100).roundToDouble();
            }
            return ProductVariantModel(
              id: v['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
              name: v['name'] as String? ?? '',
              size: v['size']?.toString() ?? '',
              unitType: v['unitType'] as String? ?? 'g',
              mrp: mrp,
              price: price,
              purchasePrice: (v['purchasePrice'] as num?)?.toDouble() ?? 0.0,
              discount: discount,
              stockQuantity: (v['stockQuantity'] as num?)?.toInt() ?? 0,
              lowStockThreshold: (v['lowStockThreshold'] as num?)?.toInt() ?? 5,
              status: v['status'] as String? ?? 'Available',
              barcode: v['barcode'] as String? ?? '',
              sku: v['sku'] as String? ?? '',
              imageUrl: v['imageUrl'] as String? ?? '',
            );
          }).toList()
        : [];

    final keywords = _keywordsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final tags = _tagsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return ProductModel(
      id: id,
      name: _nameController.text,
      nameTamil: _tamilNameController.text,
      imageUrl: _imageUrlController.text,
      price: double.tryParse(_sellingPriceController.text) ?? 0.0,
      categoryId: _categoryController.text,
      unit: _variantsEnabled ? '' : _selectedUnit,
      stockQuantity: _variantsEnabled
          ? finalVariants.fold(0, (acc, v) => acc + v.stockQuantity)
          : int.tryParse(_stockController.text) ?? 0,
      lowStockThreshold: _variantsEnabled
          ? 5
          : int.tryParse(_minStockController.text) ?? 5,
      maxStock: int.tryParse(_maxStockController.text) ?? 9999,
      isActive: _isActive,
      sortOrder: 0,
      brand: _brandController.text,
      description: _descriptionController.text,
      longDescription: _longDescriptionController.text,
      ingredients: _ingredientsController.text,
      storageInstructions: _storageInstructionsController.text,
      mrp: double.tryParse(_mrpController.text) ?? 0.0,
      variantsEnabled: _variantsEnabled,
      variants: finalVariants,
      subCategoryId: _subCategoryController.text,
      productImages: _additionalImages,
      tags: tags,
      searchKeywords: keywords,
      metaTitle: _metaTitleController.text,
      metaDescription: _metaDescriptionController.text,
      slug: _slugController.text,
      isFeatured: _isFeatured,
      isTodayDeal: _isTodayDeal,
      isTrending: _isTrending,
      isRecommended: _isRecommended,
      isBestSeller: _isBestSeller,
      isNewArrival: _isNewArrival,
      enableReviews: _enableReviews,
      enableWishlist: _enableWishlist,
      couponCode: _couponCodeController.text,
      buyOneGetOne: _buyOneGetOne,
      isFlashSale: _isFlashSale,
      isComboOffer: _isComboOffer,
      isLimitedTimeOffer: _isLimitedTimeOffer,
    );
  }

  // Save product logic
  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please correct errors in the form before saving.')),
      );
      return;
    }

    try {
      final product = _buildProductModel(id: _editingProductId ?? '');
      if (_editingProductId == null) {
        await widget.firestore.addProduct(product);
      } else {
        await widget.firestore.updateProduct(product);
      }

      // If draft exists, delete it
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/product_draft.json');
      if (await file.exists()) {
        await file.delete();
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving product: $e')),
        );
      }
    }
  }

  // Searchable dropdown bottom sheet builder
  void _showSearchableDropdown({
    required String title,
    required List<String> items,
    required Function(String) onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = items
                .where((item) => item.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onChanged: (val) {
                      setSheetState(() {
                        searchQuery = val;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(filtered[index]),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () {
                            onSelect(filtered[index]);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Search Category helper (streams live categories from Firestore)
  void _showCategoryDropdown() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String searchQuery = '';
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(16.0),
          child: StreamBuilder<List<CategoryModel>>(
            stream: widget.firestore.categoriesStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final categories = snapshot.data ?? [];
              return StatefulBuilder(
                builder: (context, setSheetState) {
                  final filtered = categories
                      .where((c) => c.name.toLowerCase().contains(searchQuery.toLowerCase()))
                      .toList();

                  return Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                      ),
                      const Text('Select Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Search categories...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onChanged: (val) {
                          setSheetState(() => searchQuery = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(child: Text('No categories match search query.'))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final cat = filtered[index];
                                  return ListTile(
                                    title: Text(cat.name),
                                    onTap: () {
                                      setState(() {
                                        _categoryController.text = cat.id;
                                        _categoryNameController.text = cat.name;
                                      });
                                      Navigator.pop(context);
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
          ),
        );
      },
    );
  }

  // Discard changes dialog
  void _confirmDiscard() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text('Are you sure you want to discard your unsaved changes? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Pop screen
            },
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Preview Drawer
  void _showPreviewDrawer() {
    final previewProduct = _buildProductModel(id: 'preview');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Product Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (previewProduct.imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            previewProduct.imageUrl,
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              height: 200,
                              color: Colors.grey.shade100,
                              child: const Icon(Icons.broken_image, size: 60, color: Colors.grey),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        previewProduct.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                      ),
                      if (previewProduct.nameTamil.isNotEmpty)
                        Text(
                          previewProduct.nameTamil,
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Brand: ${previewProduct.brand.isNotEmpty ? previewProduct.brand : 'Generic'}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Selling Price: ₹${previewProduct.price}',
                              style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (previewProduct.mrp > previewProduct.price)
                            Text(
                              'MRP: ₹${previewProduct.mrp}',
                              style: TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: Colors.grey.shade50,
                              ),
                            ),
                        ],
                      ),
                      const Divider(height: 24),
                      const Text('Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(
                        previewProduct.description.isNotEmpty ? previewProduct.description : 'No description provided.',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      if (previewProduct.ingredients.isNotEmpty) ...[
                        const Text('Ingredients', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 6),
                        Text(previewProduct.ingredients, style: const TextStyle(fontSize: 14)),
                        const SizedBox(height: 12),
                      ],
                      if (previewProduct.variantsEnabled) ...[
                        const Text('Variants Configured', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        ...previewProduct.variants.map((v) => Card(
                              child: ListTile(
                                title: Text('${v.name} (${v.size} ${v.unitType})'),
                                subtitle: Text('Price: ₹${v.price} | Stock: ${v.stockQuantity}'),
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: _confirmDiscard,
        ),
        title: Text(
          _isEdit ? 'Edit Product' : 'Add Product',
          style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isEdit ? null : _autoSaveDraft,
            child: Text(
              'Save Draft',
              style: TextStyle(color: _isEdit ? Colors.grey : const Color(0xFF16A34A), fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.visibility_outlined, color: Color(0xFF64748B)),
            tooltip: 'Preview Product',
            onPressed: _showPreviewDrawer,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
            onSelected: (value) {
              if (value == 'reset') {
                _formKey.currentState?.reset();
              } else if (value == 'discard') {
                _confirmDiscard();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'reset', child: Text('Reset Form')),
              const PopupMenuItem(value: 'discard', child: Text('Discard Changes')),
            ],
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Dynamic Top Progress Tracker
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildProgressItem('Basic', _isBasicValid),
                  _buildProgressItem('Pricing', _isPricingValid),
                  _buildProgressItem('Inventory', _isInventoryValid),
                  _buildProgressItem('Variants', _isVariantsValid),
                  _buildProgressItem('Images', _isImagesValid),
                ],
              ),
            ),
            
            // Image Upload Progress overlay if uploading
            if (_isUploadingMain || _isUploadingAdditional)
              LinearProgressIndicator(
                value: _uploadProgress,
                backgroundColor: Colors.green.shade100,
                color: const Color(0xFF16A34A),
              ),

            // Form Fields
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Section 1: Basic Information
                    _buildSectionHeader(0, '1. Basic Information', _isBasicValid),
                    if (_isOpen[0])
                      _buildSectionCard(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTextField(
                              controller: _nameController,
                              label: 'Product Name (English)*',
                              validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _tamilNameController,
                              label: 'Product Name (Tamil)',
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () {
                                _showSearchableDropdown(
                                  title: 'Select Brand',
                                  items: const ['Aashirvaad', 'Tata', 'Amul', 'Nestle', 'Cadbury', 'Britannia', 'Haldiram\'s', 'Surf Excel', 'Horlicks', 'Colgate', 'Dettol', 'Organic India', 'Fortune', 'Maggi'],
                                  onSelect: (val) => setState(() => _brandController.text = val),
                                );
                              },
                              child: AbsorbPointer(
                                child: _buildTextField(
                                  controller: _brandController,
                                  label: 'Brand',
                                  suffixIcon: const Icon(Icons.arrow_drop_down),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: _showCategoryDropdown,
                              child: AbsorbPointer(
                                child: _buildTextField(
                                  controller: _categoryNameController,
                                  label: 'Category*',
                                  validator: (v) => _categoryController.text.isEmpty ? 'Required' : null,
                                  suffixIcon: const Icon(Icons.arrow_drop_down),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () {
                                _showSearchableDropdown(
                                  title: 'Select Sub Category',
                                  items: const ['Atta & Flours', 'Rice & Rice Products', 'Dals & Pulses', 'Organic Ghee', 'Fresh Milk', 'Paneer & Curd', 'Chocolates & Bars', 'Biscuits & Cookies', 'Chips & Crisps', 'Soaps & Bodywash', 'Oral Care', 'Detergent Liquids'],
                                  onSelect: (val) => setState(() => _subCategoryController.text = val),
                                );
                              },
                              child: AbsorbPointer(
                                child: _buildTextField(
                                  controller: _subCategoryController,
                                  label: 'Sub Category',
                                  suffixIcon: const Icon(Icons.arrow_drop_down),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 12),

                    // Section 2: Images
                    _buildSectionHeader(1, '2. Product Images', _isImagesValid),
                    if (_isOpen[1])
                      _buildSectionCard(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Main Image', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _imageUrlController,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Main Image URL (Paste URL or Upload below)*',
                                hintText: 'https://images.unsplash.com/...',
                                prefixIcon: const Icon(Icons.link_rounded),
                                suffixIcon: _imageUrlController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () => setState(() => _imageUrlController.clear()),
                                      )
                                    : null,
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: Colors.grey.shade200),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: Colors.grey.shade100),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _imageUrlController.text.isNotEmpty
                                ? Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.network(
                                          _imageUrlController.text,
                                          height: 150,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            height: 120,
                                            width: double.infinity,
                                            color: Colors.grey.shade100,
                                            child: const Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.broken_image_outlined, size: 36, color: Colors.orange),
                                                SizedBox(height: 4),
                                                Text('Invalid or Unreachable Image URL', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: 8,
                                        top: 8,
                                        child: CircleAvatar(
                                          backgroundColor: Colors.white.withValues(alpha: 0.8),
                                          radius: 16,
                                          child: IconButton(
                                            icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                            onPressed: () => setState(() => _imageUrlController.clear()),
                                          ),
                                        ),
                                      )
                                    ],
                                  )
                                : Container(
                                    width: double.infinity,
                                    height: 100,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.grey.shade200, width: 1.5),
                                    ),
                                    child: InkWell(
                                      onTap: () => _pickAndUploadImage(isMain: true),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add_photo_alternate_outlined, size: 36, color: Colors.grey.shade400),
                                          const SizedBox(height: 4),
                                          Text('Or Upload Main Image File', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                  ),
                            const SizedBox(height: 16),
                            const Text('Additional Images (Max 10)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 80,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _additionalImages.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == _additionalImages.length) {
                                    return Container(
                                      width: 80,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      child: InkWell(
                                        onTap: () {
                                          if (_additionalImages.length >= 10) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Maximum 10 additional images allowed.')),
                                            );
                                            return;
                                          }
                                          _pickAndUploadImage(isMain: false);
                                        },
                                        child: const Icon(Icons.add_a_photo_outlined, color: Colors.grey),
                                      ),
                                    );
                                  }

                                  return Stack(
                                    children: [
                                      Container(
                                        width: 80,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          image: DecorationImage(
                                            image: NetworkImage(_additionalImages[index]),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: 12,
                                        top: 4,
                                        child: GestureDetector(
                                          onTap: () => setState(() => _additionalImages.removeAt(index)),
                                          child: Container(
                                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                            padding: const EdgeInsets.all(2),
                                            child: const Icon(Icons.close, size: 12, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Section 3: Pricing
                    _buildSectionHeader(2, '3. Pricing & Margins', _isPricingValid),
                    if (_isOpen[2])
                      _buildSectionCard(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_variantsEnabled)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8.0),
                                child: Text(
                                  'Variants are enabled. Adjust individual prices in Section 5 below.',
                                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              )
                            else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _purchasePriceController,
                                      label: 'Purchase Price (₹)',
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _mrpController,
                                      label: 'MRP (₹)*',
                                      keyboardType: TextInputType.number,
                                      validator: (v) => !_variantsEnabled && (v?.isEmpty ?? true) ? 'Required' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _sellingPriceController,
                                      label: 'Selling Price (₹)*',
                                      keyboardType: TextInputType.number,
                                      validator: (v) => !_variantsEnabled && (v?.isEmpty ?? true) ? 'Required' : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Calculations Card
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Calculated Discount', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                                        Text(
                                          '₹${_discountAmount.toStringAsFixed(2)} (${_discountPercent.toStringAsFixed(1)}% OFF)',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Expected Profit', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                                        Text(
                                          '₹${_profit.toStringAsFixed(2)}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF22C55E)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Profit Margin %', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                                        Text(
                                          '${_marginPercent.toStringAsFixed(1)}%',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: _marginPercent >= 20 ? const Color(0xFF16A34A) : Colors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Section 4: Inventory
                    _buildSectionHeader(3, '4. Inventory Parameters', _isInventoryValid),
                    if (_isOpen[3])
                      _buildSectionCard(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_variantsEnabled)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8.0),
                                child: Text(
                                  'Variants are enabled. Adjust individual stock quantities in Section 5 below.',
                                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              )
                            else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _stockController,
                                      label: 'Stock Quantity*',
                                      keyboardType: TextInputType.number,
                                      validator: (v) => !_variantsEnabled && (v?.isEmpty ?? true) ? 'Required' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _minStockController,
                                      label: 'Min Stock Alert',
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildTextField(
                                      controller: _maxStockController,
                                      label: 'Max Stock',
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Stock Status Widget
                              Row(
                                children: [
                                  const Text('Computed Stock Status: ', style: TextStyle(fontSize: 13)),
                                  const SizedBox(width: 8),
                                  _buildStockBadge(),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      _showSearchableDropdown(
                                        title: 'Select Supplier',
                                        items: const ['Main Supplier A', 'Green Groceries Wholesaler', 'Dairy Fresh Distributor', 'Snack & Beverage Corp', 'Direct Farm Sourcing'],
                                        onSelect: (val) => setState(() => _selectedSupplier = val),
                                      );
                                    },
                                    child: AbsorbPointer(
                                      child: _buildTextField(
                                        controller: TextEditingController(text: _selectedSupplier),
                                        label: 'Supplier',
                                        suffixIcon: const Icon(Icons.arrow_drop_down),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      _showSearchableDropdown(
                                        title: 'Select Warehouse',
                                        items: const ['Main Central Warehouse', 'Cold Storage Facility North', 'South City Hub', 'Express Delivery Depot'],
                                        onSelect: (val) => setState(() => _selectedWarehouse = val),
                                      );
                                    },
                                    child: AbsorbPointer(
                                      child: _buildTextField(
                                        controller: TextEditingController(text: _selectedWarehouse),
                                        label: 'Warehouse Location',
                                        suffixIcon: const Icon(Icons.arrow_drop_down),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Section 5: Advanced Product Variants
                    _buildSectionHeader(4, '5. Product Variants (Flipkart Style)', _isVariantsValid),
                    if (_isOpen[4])
                      _buildSectionCard(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Enable Product Variants', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: const Text('Multi-size, weight, volume, or pack configurations'),
                              value: _variantsEnabled,
                              onChanged: (val) {
                                setState(() {
                                  _variantsEnabled = val;
                                  if (val && _variants.isEmpty) {
                                    _variants.add({
                                      'id': '${DateTime.now().millisecondsSinceEpoch}_0',
                                      'name': '',
                                      'size': '',
                                      'unitType': 'g',
                                      'mrp': 0.0,
                                      'price': 0.0,
                                      'purchasePrice': 0.0,
                                      'discount': 0.0,
                                      'stockQuantity': 0,
                                      'lowStockThreshold': 5,
                                      'status': 'Available',
                                      'barcode': '',
                                      'sku': '',
                                      'imageUrl': '',
                                    });
                                  }
                                });
                              },
                            ),
                            if (_variantsEnabled) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Variants Checklist (${_variants.length})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ReorderableListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _variants.length,
                                onReorderItem: (oldIndex, newIndex) {
                                  setState(() {
                                    final item = _variants.removeAt(oldIndex);
                                    _variants.insert(newIndex, item);
                                  });
                                },
                                itemBuilder: (context, index) {
                                  final variant = _variants[index];
                                  final String varId = variant['id']?.toString() ?? index.toString();
                                  final bool isExpanded = variant['isExpanded'] as bool? ?? true;
                                  final bool isValid = _isVariantValid(variant);
                                  
                                  return Card(
                                    key: ValueKey(varId),
                                    margin: const EdgeInsets.symmetric(vertical: 8),
                                    color: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(
                                        color: isExpanded 
                                            ? const Color(0xFF16A34A) 
                                            : (isValid ? Colors.grey.shade200 : Colors.red.shade300),
                                        width: isExpanded ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        // Summary header
                                        InkWell(
                                          onTap: () {
                                            setState(() {
                                              variant['isExpanded'] = !isExpanded;
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(16),
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Row(
                                              children: [
                                                ReorderableDragStartListener(
                                                  index: index,
                                                  child: Icon(Icons.drag_indicator, color: Colors.grey.shade400),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        variant['name']?.toString().isNotEmpty == true 
                                                            ? variant['name'].toString() 
                                                            : 'New Variant #${index + 1}',
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Wrap(
                                                        spacing: 12,
                                                        runSpacing: 4,
                                                        children: [
                                                          Text(
                                                            'Price: ₹${variant['price'] ?? 0.0}',
                                                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                                          ),
                                                          Text(
                                                            'Stock: ${variant['stockQuantity'] ?? 0}',
                                                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                                          ),
                                                          _buildMiniStatusBadge(variant['status']?.toString() ?? 'Available'),
                                                        ],
                                                      ),
                                                      if (!isValid && !isExpanded) ...[
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          '⚠ Incomplete fields',
                                                          style: TextStyle(color: Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                                                        ),
                                                      ]
                                                    ],
                                                  ),
                                                ),
                                                Icon(
                                                  isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (isExpanded) ...[
                                          const Divider(height: 1),
                                          Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                _buildVariantTextField(
                                                  labelText: 'Variant Name* (e.g. 500 g, Pack of 2)',
                                                  initialValue: variant['name']?.toString(),
                                                  onChanged: (v) => setState(() => variant['name'] = v),
                                                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                                                ),
                                                const SizedBox(height: 12),
                                                _buildVariantTextField(
                                                  labelText: 'Weight / Size Value* (e.g. 500, 2)',
                                                  initialValue: variant['size']?.toString(),
                                                  onChanged: (v) => setState(() => variant['size'] = v),
                                                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                                                ),
                                                const SizedBox(height: 12),
                                                DropdownButtonFormField<String>(
                                                  initialValue: ['g', 'kg', 'ml', 'L', 'Pieces', 'Packets', 'Custom'].contains(variant['unitType']) ? variant['unitType'] : 'g',
                                                  decoration: _variantInputDecoration('Unit Type*'),
                                                  items: const [
                                                    DropdownMenuItem(value: 'g', child: Text('Weight (g)')),
                                                    DropdownMenuItem(value: 'kg', child: Text('Weight (kg)')),
                                                    DropdownMenuItem(value: 'ml', child: Text('Volume (ml)')),
                                                    DropdownMenuItem(value: 'L', child: Text('Volume (L)')),
                                                    DropdownMenuItem(value: 'Pieces', child: Text('Pieces')),
                                                    DropdownMenuItem(value: 'Packets', child: Text('Packets')),
                                                    DropdownMenuItem(value: 'Custom', child: Text('Custom')),
                                                  ],
                                                  onChanged: (v) => setState(() => variant['unitType'] = v),
                                                ),
                                                const SizedBox(height: 12),
                                                DropdownButtonFormField<String>(
                                                  initialValue: ['Available', 'Out of Stock', 'Disabled'].contains(variant['status']) ? variant['status'] : 'Available',
                                                  decoration: _variantInputDecoration('Status*'),
                                                  items: const [
                                                    DropdownMenuItem(value: 'Available', child: Text('Available')),
                                                    DropdownMenuItem(value: 'Out of Stock', child: Text('Out of Stock')),
                                                    DropdownMenuItem(value: 'Disabled', child: Text('Disabled')),
                                                  ],
                                                  onChanged: (v) => setState(() => variant['status'] = v),
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: _buildVariantTextField(
                                                        labelText: 'MRP (₹)*',
                                                        initialValue: variant['mrp']?.toString() ?? '0.0',
                                                        keyboardType: TextInputType.number,
                                                        onChanged: (v) => setState(() => variant['mrp'] = double.tryParse(v) ?? 0.0),
                                                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: _buildVariantTextField(
                                                        labelText: 'Selling Price (₹)*',
                                                        initialValue: variant['price']?.toString() ?? '0.0',
                                                        keyboardType: TextInputType.number,
                                                        onChanged: (v) => setState(() => variant['price'] = double.tryParse(v) ?? 0.0),
                                                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: _buildVariantTextField(
                                                        labelText: 'Purchase Price (₹)',
                                                        initialValue: variant['purchasePrice']?.toString() ?? '0.0',
                                                        keyboardType: TextInputType.number,
                                                        onChanged: (v) => setState(() => variant['purchasePrice'] = double.tryParse(v) ?? 0.0),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: _buildVariantTextField(
                                                        labelText: 'Stock Qty*',
                                                        initialValue: variant['stockQuantity']?.toString() ?? '0',
                                                        keyboardType: TextInputType.number,
                                                        onChanged: (v) => setState(() => variant['stockQuantity'] = int.tryParse(v) ?? 0),
                                                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                _buildVariantTextField(
                                                  labelText: 'Barcode',
                                                  initialValue: variant['barcode']?.toString(),
                                                  onChanged: (v) => setState(() => variant['barcode'] = v),
                                                ),
                                                const SizedBox(height: 12),
                                                _buildVariantTextField(
                                                  labelText: 'SKU',
                                                  initialValue: variant['sku']?.toString(),
                                                  onChanged: (v) => setState(() => variant['sku'] = v),
                                                ),
                                                const SizedBox(height: 16),
                                                const Text('Variant Image', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                                const SizedBox(height: 8),
                                                _buildVariantImageSelector(variant),
                                                const SizedBox(height: 16),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.end,
                                                  children: [
                                                    TextButton.icon(
                                                      onPressed: () {
                                                        setState(() {
                                                          final clone = Map<String, dynamic>.from(variant);
                                                          clone['id'] = '${DateTime.now().millisecondsSinceEpoch}_copy_$index';
                                                          clone['barcode'] = '';
                                                          clone['isExpanded'] = true;
                                                          _variants.insert(index + 1, clone);
                                                        });
                                                      },
                                                      icon: const Icon(Icons.copy, size: 16, color: Colors.blue),
                                                      label: const Text('Duplicate', style: TextStyle(color: Colors.blue)),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    TextButton.icon(
                                                      onPressed: () {
                                                        setState(() {
                                                          _variants.removeAt(index);
                                                        });
                                                      },
                                                      icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _variants.add({
                                        'id': '${DateTime.now().millisecondsSinceEpoch}_${_variants.length}',
                                        'name': '',
                                        'size': '',
                                        'unitType': 'g',
                                        'mrp': 0.0,
                                        'price': 0.0,
                                        'purchasePrice': 0.0,
                                        'discount': 0.0,
                                        'stockQuantity': 0,
                                        'lowStockThreshold': 5,
                                        'status': 'Available',
                                        'barcode': '',
                                        'sku': '',
                                        'imageUrl': '',
                                        'isExpanded': true,
                                      });
                                    });
                                  },
                                  icon: const Icon(Icons.add, color: Colors.white),
                                  label: const Text('Add Variant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF16A34A),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],                    ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Section 6: Descriptions & Ingredients
                    _buildSectionHeader(5, '6. Descriptions & Logistics', true),
                    if (_isOpen[5])
                      _buildSectionCard(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTextField(
                              controller: _descriptionController,
                              label: 'Short Description',
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _longDescriptionController,
                              label: 'Long Description / Details',
                              maxLines: 4,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _ingredientsController,
                              label: 'Ingredients (If edible or chemical products)',
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _storageInstructionsController,
                              label: 'Storage Instructions (e.g. Keep in cool place)',
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Section 7: SEO
                    _buildSectionHeader(6, '7. SEO Configuration', true),
                    if (_isOpen[6])
                      _buildSectionCard(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTextField(
                              controller: _keywordsController,
                              label: 'Search Keywords (Comma-separated)',
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _tagsController,
                              label: 'Tags (Comma-separated)',
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _metaTitleController,
                              label: 'Meta Title',
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _metaDescriptionController,
                              label: 'Meta Description',
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _slugController,
                              label: 'URL Slug',
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Section 8: Visibility
                    _buildSectionHeader(7, '8. Visibility & Featured Flags', true),
                    if (_isOpen[7])
                      _buildSectionCard(
                        Column(
                          children: [
                            SwitchListTile(
                              title: const Text('Visible to Customers'),
                              subtitle: const Text('Publish this product in the catalog immediately'),
                              value: _isActive,
                              onChanged: (v) => setState(() => _isActive = v),
                            ),
                            const Divider(),
                            CheckboxListTile(
                              title: const Text('Featured Product'),
                              value: _isFeatured,
                              onChanged: (v) => setState(() => _isFeatured = v ?? false),
                            ),
                            CheckboxListTile(
                              title: const Text('Today\'s Deal'),
                              value: _isTodayDeal,
                              onChanged: (v) => setState(() => _isTodayDeal = v ?? false),
                            ),
                            CheckboxListTile(
                              title: const Text('Trending Product'),
                              value: _isTrending,
                              onChanged: (v) => setState(() => _isTrending = v ?? false),
                            ),
                            CheckboxListTile(
                              title: const Text('Recommended Product'),
                              value: _isRecommended,
                              onChanged: (v) => setState(() => _isRecommended = v ?? false),
                            ),
                            CheckboxListTile(
                              title: const Text('Best Seller'),
                              value: _isBestSeller,
                              onChanged: (v) => setState(() => _isBestSeller = v ?? false),
                            ),
                            CheckboxListTile(
                              title: const Text('New Arrival'),
                              value: _isNewArrival,
                              onChanged: (v) => setState(() => _isNewArrival = v ?? false),
                            ),
                            const Divider(),
                            SwitchListTile(
                              title: const Text('Enable Reviews'),
                              value: _enableReviews,
                              onChanged: (v) => setState(() => _enableReviews = v),
                            ),
                            SwitchListTile(
                              title: const Text('Enable Wishlist'),
                              value: _enableWishlist,
                              onChanged: (v) => setState(() => _enableWishlist = v),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Section 9: Offers
                    _buildSectionHeader(8, '9. Offers & Promos', true),
                    if (_isOpen[8])
                      _buildSectionCard(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTextField(
                              controller: _couponCodeController,
                              label: 'Coupon Code',
                            ),
                            const SizedBox(height: 12),
                            CheckboxListTile(
                              title: const Text('Buy One Get One (BOGO)'),
                              value: _buyOneGetOne,
                              onChanged: (v) => setState(() => _buyOneGetOne = v ?? false),
                            ),
                            CheckboxListTile(
                              title: const Text('Flash Sale active'),
                              value: _isFlashSale,
                              onChanged: (v) => setState(() => _isFlashSale = v ?? false),
                            ),
                            CheckboxListTile(
                              title: const Text('Combo Offer eligible'),
                              value: _isComboOffer,
                              onChanged: (v) => setState(() => _isComboOffer = v ?? false),
                            ),
                            CheckboxListTile(
                              title: const Text('Limited Time Offer'),
                              value: _isLimitedTimeOffer,
                              onChanged: (v) => setState(() => _isLimitedTimeOffer = v ?? false),
                            ),
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Sticky Bottom Save Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        side: const BorderSide(color: Color(0xFF64748B)),
                      ),
                      onPressed: _confirmDiscard,
                      child: const Text('Cancel', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.visibility),
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _showPreviewDrawer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: _saveProduct,
                      child: Text(
                        _isEdit ? 'Update Product' : 'Save Product',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
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

  // Row progress checklists helper
  Widget _buildProgressItem(String title, bool isValid) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isValid ? Icons.check_circle : Icons.circle_outlined,
          color: isValid ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
          size: 14,
        ),
        const SizedBox(width: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isValid ? FontWeight.bold : FontWeight.normal,
            color: isValid ? const Color(0xFF1E293B) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // Header click triggers collapse/expansion
  Widget _buildSectionHeader(int index, String title, bool isComplete) {
    final active = _isOpen[index];
    return GestureDetector(
      onTap: () {
        setState(() {
          _isOpen[index] = !_isOpen[index];
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? const Color(0xFF16A34A) : Colors.grey.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: active ? const Color(0xFF16A34A) : const Color(0xFF1E293B),
                  ),
                ),
                if (isComplete) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 16),
                ]
              ],
            ),
            Icon(active ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(Widget child) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    int? maxLines = 1,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        floatingLabelStyle: const TextStyle(color: Color(0xFF16A34A)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade100),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildStockBadge() {
    final stock = int.tryParse(_stockController.text) ?? 0;
    final minAlert = int.tryParse(_minStockController.text) ?? 5;

    if (stock <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
        child: const Text('Out of Stock', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
      );
    } else if (stock <= minAlert) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6)),
        child: Text('Low Stock: $stock left', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
      child: Text('In Stock: $stock', style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  bool _isVariantValid(Map<String, dynamic> v) {
    final name = v['name']?.toString() ?? '';
    final size = v['size']?.toString() ?? '';
    final mrp = (v['mrp'] as num?)?.toDouble() ?? 0.0;
    final price = (v['price'] as num?)?.toDouble() ?? 0.0;
    final stock = (v['stockQuantity'] as num?)?.toInt() ?? 0;
    return name.isNotEmpty && size.isNotEmpty && mrp > 0.0 && price > 0.0 && stock >= 0;
  }

  Widget _buildMiniStatusBadge(String status) {
    Color bg = Colors.green.shade50;
    Color fg = const Color(0xFF16A34A);
    if (status == 'Out of Stock') {
      bg = Colors.red.shade50;
      fg = Colors.red;
    } else if (status == 'Disabled') {
      bg = Colors.grey.shade100;
      fg = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(status, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildVariantTextField({
    required String labelText,
    required String? initialValue,
    required Function(String) onChanged,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      initialValue: initialValue,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      decoration: _variantInputDecoration(labelText),
    );
  }

  InputDecoration _variantInputDecoration(String labelText) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
      floatingLabelStyle: const TextStyle(color: Color(0xFF16A34A)),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade100),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildVariantImageSelector(Map<String, dynamic> variant) {
    final String currentUrl = variant['imageUrl']?.toString() ?? '';
    final bool isUploading = variant['isUploadingImage'] as bool? ?? false;
    
    if (currentUrl.isNotEmpty) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              currentUrl,
              height: 120,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: CircleAvatar(
              backgroundColor: Colors.white.withValues(alpha: 0.8),
              radius: 16,
              child: IconButton(
                icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                onPressed: () => setState(() => variant['imageUrl'] = ''),
              ),
            ),
          )
        ],
      );
    }

    if (isUploading) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 1.5),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Compressing and uploading image...', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: InkWell(
        onTap: () async {
          try {
            final result = await FilePicker.platform.pickFiles(type: FileType.image);
            if (result != null && result.files.single.path != null) {
              setState(() {
                variant['isUploadingImage'] = true;
              });
              
              await Future.delayed(const Duration(milliseconds: 1200));
              final mockUrl = 'https://picsum.photos/id/${(100 + (DateTime.now().millisecond % 50))}/500/500';
              
              setState(() {
                variant['isUploadingImage'] = false;
                variant['imageUrl'] = mockUrl;
              });
            }
          } catch (e) {
            setState(() {
              variant['isUploadingImage'] = false;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error picking variant image: $e')),
              );
            }
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, size: 30, color: Colors.grey.shade400),
            const SizedBox(height: 4),
            Text('Upload Variant Image', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
