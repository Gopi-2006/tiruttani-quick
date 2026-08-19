import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../products/presentation/product_listing_screen.dart';
import '../../../config/admob_config.dart';
import '../../../widgets/banner_ad_widget.dart';
import '../../../services/startup_provider.dart';

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
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounceTimer;

  String _query = '';
  bool _isSearching = false;
  String? _searchError;
  List<SearchResultItem> _searchResults = [];

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
  void initState() {
    super.initState();
    // Auto-focus search input when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _searchDebounceTimer?.cancel();
    
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _query = '';
        _isSearching = false;
        _searchError = null;
        _searchResults = [];
      });
      return;
    }

    // Set search query immediately without blocking UI, start debounce
    setState(() {
      _query = trimmed;
      _isSearching = true;
      _searchError = null;
    });

    _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      _performSearch(trimmed);
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResults = [];
        });
      }
      return;
    }

    try {
      final startup = context.read<StartupProvider>();
      final firestore = context.read<FirestoreService>();

      List<ProductModel> allProducts = startup.products;
      List<CategoryModel> categories = startup.categories;

      // Fallback: If startup cache hasn't populated products yet, fetch directly once
      if (allProducts.isEmpty) {
        allProducts = await firestore.fetchProducts();
      }
      if (categories.isEmpty) {
        final catStream = firestore.categoriesStream();
        categories = await catStream.first.timeout(
          const Duration(seconds: 3),
          onTimeout: () => [],
        );
      }

      // Filter products using ProductSearchEngine
      final filteredProducts = ProductSearchEngine.filterProducts(
        products: allProducts,
        rawQuery: cleanQuery,
        categories: categories,
      );

      // Flatten variants
      final List<SearchResultItem> rawItems = [];
      for (final p in filteredProducts) {
        if (p.variantsEnabled && p.variants.isNotEmpty) {
          for (final v in p.variants) {
            rawItems.add(SearchResultItem(product: p, variant: v));
          }
        } else {
          rawItems.add(SearchResultItem(product: p));
        }
      }

      if (!mounted) return;
      // Stale query guard: ignore results if the user has changed the query
      if (_query != cleanQuery) return;

      setState(() {
        _isSearching = false;
        _searchError = null;
        _searchResults = rawItems;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = 'An error occurred while searching. Please try again.';
      });
    }
  }

  void _selectTag(String tag) {
    _searchController.text = tag;
    _onQueryChanged(tag);
  }

  void _clearSearch() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _isSearching = false;
      _searchError = null;
      _searchResults = [];
      _selectedWeight = null;
      _selectedVolume = null;
      _selectedPackSize = null;
      _inStockOnly = false;
    });
    _searchFocusNode.requestFocus();
  }

  Future<void> _handleRefresh() async {
    if (_query.isNotEmpty) {
      await _performSearch(_query);
    } else {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() {});
    }
  }

  List<SearchResultItem> _applyFilterChips(List<SearchResultItem> items) {
    return items.where((item) {
      // Availability filter
      if (_inStockOnly) {
        final isOut = item.variant != null
            ? item.variant!.isOutOfStock
            : item.product.isOutOfStock;
        if (isOut) return false;
      }

      // Weight filter
      if (_selectedWeight != null) {
        final name = item.variant != null
            ? item.variant!.name.toLowerCase()
            : item.product.unit.toLowerCase();
        if (!name.contains(_selectedWeight!.toLowerCase())) return false;
      }

      // Volume filter
      if (_selectedVolume != null) {
        final name = item.variant != null
            ? item.variant!.name.toLowerCase()
            : item.product.unit.toLowerCase();
        if (!name.contains(_selectedVolume!.toLowerCase())) return false;
      }

      // Pack size filter
      if (_selectedPackSize != null) {
        final name = item.variant != null
            ? item.variant!.name.toLowerCase()
            : item.product.unit.toLowerCase();
        final isPack = name.contains('pack') ||
            name.contains('carton') ||
            name.contains('box') ||
            name.contains('bundle');
        if (!isPack) return false;

        if (_selectedPackSize == 'Single Pack' &&
            !(name.contains('single') ||
                name.contains('1 pack') ||
                name.contains('1piece') ||
                name.contains('1 piece'))) {
          return false;
        }
        if (_selectedPackSize == 'Pack of 2' && !name.contains('2')) return false;
        if (_selectedPackSize == 'Pack of 3' && !name.contains('3')) return false;
        if (_selectedPackSize == 'Pack of 5' && !name.contains('5')) return false;
        if (_selectedPackSize == 'Pack of 10' && !name.contains('10')) return false;
      }

      return true;
    }).toList();
  }

  void _showWeightMenu(BuildContext context) {
    final weights = ['50 g', '100 g', '200 g', '250 g', '500 g', '750 g', '1 kg', '2 kg', '5 kg', '10 kg'];
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final position = renderBox != null
        ? renderBox.localToGlobal(Offset.zero)
        : Offset.zero;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx + 60,
        position.dy + 120,
        position.dx + 200,
        position.dy + 400,
      ),
      items: [
        const PopupMenuItem<String>(value: null, child: Text('All Weights')),
        ...weights.map((w) => PopupMenuItem<String>(value: w, child: Text(w))),
      ],
    ).then((val) {
      if (mounted) {
        setState(() {
          _selectedWeight = val;
        });
      }
    });
  }

  void _showVolumeMenu(BuildContext context) {
    final volumes = ['100 ml', '200 ml', '500 ml', '750 ml', '1 L', '2 L', '5 L'];
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final position = renderBox != null
        ? renderBox.localToGlobal(Offset.zero)
        : Offset.zero;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx + 120,
        position.dy + 120,
        position.dx + 260,
        position.dy + 400,
      ),
      items: [
        const PopupMenuItem<String>(value: null, child: Text('All Volumes')),
        ...volumes.map((v) => PopupMenuItem<String>(value: v, child: Text(v))),
      ],
    ).then((val) {
      if (mounted) {
        setState(() {
          _selectedVolume = val;
        });
      }
    });
  }

  void _showPackSizeMenu(BuildContext context) {
    final packs = ['Single Pack', 'Pack of 2', 'Pack of 3', 'Pack of 5', 'Pack of 10'];
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    final position = renderBox != null
        ? renderBox.localToGlobal(Offset.zero)
        : Offset.zero;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx + 180,
        position.dy + 120,
        position.dx + 300,
        position.dy + 400,
      ),
      items: [
        const PopupMenuItem<String>(value: null, child: Text('All Pack Sizes')),
        ...packs.map((p) => PopupMenuItem<String>(value: p, child: Text(p))),
      ],
    ).then((val) {
      if (mounted) {
        setState(() {
          _selectedPackSize = val;
        });
      }
    });
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMedium,
        vertical: 4,
      ),
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
            selectedColor: AppColors.amberLight,
            checkmarkColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
              side: BorderSide(
                color: _inStockOnly ? AppColors.primary : AppColors.border,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ActionChip(
            label: Text(_selectedWeight ?? 'Weight'),
            backgroundColor: _selectedWeight != null
                ? AppColors.amberLight
                : AppColors.surface,
            onPressed: () => _showWeightMenu(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
              side: BorderSide(
                color: _selectedWeight != null
                    ? AppColors.primary
                    : AppColors.border,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ActionChip(
            label: Text(_selectedVolume ?? 'Volume'),
            backgroundColor: _selectedVolume != null
                ? AppColors.amberLight
                : AppColors.surface,
            onPressed: () => _showVolumeMenu(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
              side: BorderSide(
                color: _selectedVolume != null
                    ? AppColors.primary
                    : AppColors.border,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ActionChip(
            label: Text(_selectedPackSize ?? 'Pack Size'),
            backgroundColor: _selectedPackSize != null
                ? AppColors.amberLight
                : AppColors.surface,
            onPressed: () => _showPackSizeMenu(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
              side: BorderSide(
                color: _selectedPackSize != null
                    ? AppColors.primary
                    : AppColors.border,
              ),
            ),
          ),
          if (_inStockOnly ||
              _selectedWeight != null ||
              _selectedVolume != null ||
              _selectedPackSize != null) ...[
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
              child: const Text(
                'Clear All',
                style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.read<FirestoreService>();
    final filteredDisplayItems = _applyFilterChips(_searchResults);

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
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface, // #F7F7F7
                  borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: _onQueryChanged,
                  onSubmitted: (val) {
                    _searchDebounceTimer?.cancel();
                    _performSearch(val);
                  },
                  decoration: InputDecoration(
                    hintText: 'Search for milk, bread, banana...',
                    hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: AppColors.textSecondary, size: 18),
                            onPressed: _clearSearch,
                          )
                        : null,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),
            if (_isSearching)
              const LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.paddingMedium,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _quickTags.map((tag) {
                    return ActionChip(
                      label: Text(tag),
                      onPressed: () => _selectTag(tag),
                      backgroundColor: AppColors.surface,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
                        side: const BorderSide(color: AppColors.border),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppDimensions.spacingMedium),
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppDimensions.paddingMedium,
                ),
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
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimensions.paddingMedium,
                        ),
                        itemCount: 5,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppDimensions.spacingNormal),
                        itemBuilder: (context, index) =>
                            const CategorySkeletonCard(),
                      );
                    }

                    final categories = snapshot.data ?? [];
                    if (categories.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                child: _buildSearchResultsSection(filteredDisplayItems),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar:
          BannerAdWidget(adUnitId: AdMobConfig.searchBannerId),
    );
  }

  Widget _buildSearchResultsSection(List<SearchResultItem> items) {
    if (_searchError != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                const SizedBox(height: AppDimensions.spacingMedium),
                Text(
                  _searchError!,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimensions.spacingMedium),
                ElevatedButton(
                  onPressed: () => _performSearch(_query),
                  child: const Text('Retry Search'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_isSearching && items.isEmpty) {
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

    if (items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.search_off, size: 64, color: AppColors.muted),
                const SizedBox(height: AppDimensions.spacingMedium),
                const Text(
                  'No products found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingSmall),
                const Text(
                  'Try adjusting your search or filters',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: AppDimensions.spacingMedium),
                OutlinedButton(
                  onPressed: _clearSearch,
                  child: const Text('Clear Search'),
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
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ProductCard(product: item.product, variant: item.variant);
      },
    );
  }
}
