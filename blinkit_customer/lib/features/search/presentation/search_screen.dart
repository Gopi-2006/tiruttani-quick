import 'package:blinkit_shared/blinkit_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/skeleton_loader.dart';

import '../../products/presentation/product_listing_screen.dart';
import '../../../config/admob_config.dart';
import '../../../widgets/banner_ad_widget.dart';

class SearchResultItem {
  final ProductModel product;
  final ProductVariantModel? variant;
  SearchResultItem({required this.product, this.variant});
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  final List<String> _quickTags = [
    'Milk',
    'Bread',
    'Egg',
    'Tomato',
    'Potato',
    'Onion',
    'Apple',
    'Banana',
    'Paneer'
  ];

  // Search Filters State
  String? _selectedWeight;
  String? _selectedVolume;
  String? _selectedPackSize;
  bool _inStockOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    setState(() {
      _query = value.trim();
    });
  }

  void _selectTag(String tag) {
    _searchController.text = tag;
    setState(() {
      _query = tag;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _selectedWeight = null;
      _selectedVolume = null;
      _selectedPackSize = null;
      _inStockOnly = false;
    });
  }

  Future<void> _handleRefresh() async {
    // Simulate refresh delay
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {});
    }
  }

  void _showWeightMenu(BuildContext context) {
    final weights = ['50 g', '100 g', '200 g', '250 g', '500 g', '750 g', '1 kg', '2 kg', '5 kg', '10 kg'];
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx + 60, position.dy + 120, position.dx + 200, position.dy + 400),
      items: [
        const PopupMenuItem<String>(value: null, child: Text('All Weights')),
        ...weights.map((w) => PopupMenuItem<String>(value: w, child: Text(w))),
      ],
    ).then((val) {
      if (val != null || val == null) {
        setState(() {
          _selectedWeight = val;
        });
      }
    });
  }

  void _showVolumeMenu(BuildContext context) {
    final volumes = ['100 ml', '200 ml', '500 ml', '750 ml', '1 L', '2 L', '5 L'];
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx + 120, position.dy + 120, position.dx + 260, position.dy + 400),
      items: [
        const PopupMenuItem<String>(value: null, child: Text('All Volumes')),
        ...volumes.map((v) => PopupMenuItem<String>(value: v, child: Text(v))),
      ],
    ).then((val) {
      if (val != null || val == null) {
        setState(() {
          _selectedVolume = val;
        });
      }
    });
  }

  void _showPackSizeMenu(BuildContext context) {
    final packs = ['Single Pack', 'Pack of 2', 'Pack of 3', 'Pack of 5', 'Pack of 10'];
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx + 180, position.dy + 120, position.dx + 300, position.dy + 400),
      items: [
        const PopupMenuItem<String>(value: null, child: Text('All Pack Sizes')),
        ...packs.map((p) => PopupMenuItem<String>(value: p, child: Text(p))),
      ],
    ).then((val) {
      if (val != null || val == null) {
        setState(() {
          _selectedPackSize = val;
        });
      }
    });
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium, vertical: 4),
      child: Row(
        children: [
          FilterChip(
            label: const Text('In Stock Only'),
            selected: _inStockOnly,
            onSelected: (val) {
              setState(() {
                _inStockOnly = val;
              });
            },
            selectedColor: AppColors.accent.withValues(alpha: 0.2),
            checkmarkColor: AppColors.primary,
          ),
          const SizedBox(width: 8),
          ActionChip(
            label: Text(_selectedWeight ?? 'Weight'),
            backgroundColor: _selectedWeight != null ? AppColors.accent.withValues(alpha: 0.2) : Colors.transparent,
            onPressed: () => _showWeightMenu(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _selectedWeight != null ? AppColors.primary : AppColors.border),
            ),
          ),
          const SizedBox(width: 8),
          ActionChip(
            label: Text(_selectedVolume ?? 'Volume'),
            backgroundColor: _selectedVolume != null ? AppColors.accent.withValues(alpha: 0.2) : Colors.transparent,
            onPressed: () => _showVolumeMenu(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _selectedVolume != null ? AppColors.primary : AppColors.border),
            ),
          ),
          const SizedBox(width: 8),
          ActionChip(
            label: Text(_selectedPackSize ?? 'Pack Size'),
            backgroundColor: _selectedPackSize != null ? AppColors.accent.withValues(alpha: 0.2) : Colors.transparent,
            onPressed: () => _showPackSizeMenu(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _selectedPackSize != null ? AppColors.primary : AppColors.border),
            ),
          ),
          if (_inStockOnly || _selectedWeight != null || _selectedVolume != null || _selectedPackSize != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _inStockOnly = false;
                  _selectedWeight = null;
                  _selectedVolume = null;
                  _selectedPackSize = null;
                });
              },
              child: const Text('Clear All', style: TextStyle(color: Colors.red, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Search Products',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.paddingMedium,
                vertical: AppDimensions.paddingSmall,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearch,
                onSubmitted: _onSearch,
                decoration: InputDecoration(
                  hintText: 'Search for milk, bread, banana...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _clearSearch,
                        )
                      : null,
                ),
              ),
            ),
            if (_query.isNotEmpty) _buildFilterBar(),
            if (_query.isEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppDimensions.paddingMedium,
                  vertical: AppDimensions.paddingSmall,
                ),
                child: Text(
                  'Popular Searches',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _quickTags.map((tag) {
                    return ActionChip(
                      label: Text(tag),
                      onPressed: () => _selectTag(tag),
                      backgroundColor: AppColors.white,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppColors.border),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppDimensions.spacingMedium),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
                child: Text(
                  'Browse Categories',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: AppDimensions.spacingSmall),
              Expanded(
                child: StreamBuilder<List<CategoryModel>>(
                  stream: firestore.categoriesStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
                        itemCount: 5,
                        separatorBuilder: (_, __) => const SizedBox(width: AppDimensions.spacingNormal),
                        itemBuilder: (context, index) => const CategorySkeletonCard(),
                      );
                    }

                    final categories = snapshot.data ?? [];
                    if (categories.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: AppDimensions.spacingNormal,
                        mainAxisSpacing: AppDimensions.spacingNormal,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final cat = categories[index];
                        return CategoryCard(
                          title: cat.name,
                          categoryImage: cat.categoryImage,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ProductListingScreen(
                                  categoryId: cat.id,
                                  categoryName: cat.name,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ] else ...[
              Expanded(
                child: StreamBuilder<List<ProductModel>>(
                  stream: firestore.productsStream(searchQuery: _query),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return GridView.builder(
                        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.58,
                          crossAxisSpacing: AppDimensions.spacingNormal,
                          mainAxisSpacing: AppDimensions.spacingNormal,
                        ),
                        itemCount: 6,
                        itemBuilder: (context, index) => const ProductSkeletonCard(),
                      );
                    }

                    final rawProducts = snapshot.data ?? [];
                    
                    // Flatten variants
                    final List<SearchResultItem> resultItems = [];
                    for (final p in rawProducts) {
                      if (p.variantsEnabled && p.variants.isNotEmpty) {
                        for (final v in p.variants) {
                          resultItems.add(SearchResultItem(product: p, variant: v));
                        }
                      } else {
                        resultItems.add(SearchResultItem(product: p));
                      }
                    }

                    // Apply filters
                    final filteredItems = resultItems.where((item) {
                      // Availability filter
                      if (_inStockOnly) {
                        final isOut = item.variant != null ? item.variant!.isOutOfStock : item.product.isOutOfStock;
                        if (isOut) return false;
                      }

                      // Weight filter
                      if (_selectedWeight != null) {
                        final name = item.variant != null ? item.variant!.name.toLowerCase() : item.product.unit.toLowerCase();
                        if (!name.contains(_selectedWeight!.toLowerCase())) return false;
                      }

                      // Volume filter
                      if (_selectedVolume != null) {
                        final name = item.variant != null ? item.variant!.name.toLowerCase() : item.product.unit.toLowerCase();
                        if (!name.contains(_selectedVolume!.toLowerCase())) return false;
                      }

                      // Pack size filter
                      if (_selectedPackSize != null) {
                        final name = item.variant != null ? item.variant!.name.toLowerCase() : item.product.unit.toLowerCase();
                        final isPack = name.contains('pack') || name.contains('carton') || name.contains('box') || name.contains('bundle');
                        if (!isPack) return false;
                        
                        if (_selectedPackSize == 'Single Pack' && !(name.contains('single') || name.contains('1 pack') || name.contains('1piece') || name.contains('1 piece'))) {
                          return false;
                        }
                        if (_selectedPackSize == 'Pack of 2' && !name.contains('2')) return false;
                        if (_selectedPackSize == 'Pack of 3' && !name.contains('3')) return false;
                        if (_selectedPackSize == 'Pack of 5' && !name.contains('5')) return false;
                        if (_selectedPackSize == 'Pack of 10' && !name.contains('10')) return false;
                      }

                      return true;
                    }).toList();

                    if (filteredItems.isEmpty) {
                      return ListView(
                        children: const [
                          SizedBox(height: 100),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 64, color: AppColors.muted),
                                SizedBox(height: AppDimensions.spacingMedium),
                                Text(
                                  'No products found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.text,
                                  ),
                                ),
                                SizedBox(height: AppDimensions.spacingSmall),
                                Text(
                                  'Try adjusting your search or filters',
                                  style: TextStyle(color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.58,
                        crossAxisSpacing: AppDimensions.spacingNormal,
                        mainAxisSpacing: AppDimensions.spacingNormal,
                      ),
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return ProductCard(product: item.product, variant: item.variant);
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: BannerAdWidget(adUnitId: AdMobConfig.searchBannerId),
    );
  }
}
