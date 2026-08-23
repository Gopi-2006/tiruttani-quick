import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

import '../../../config/admob_config.dart';
import '../../../core/widgets/horizontal_product_card.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/voice_search_dialog.dart';
import '../../../services/startup_provider.dart';
import '../../../widgets/banner_ad_widget.dart';
import '../../products/presentation/product_listing_screen.dart';
import 'search_filter_bottom_sheet.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounceTimer;
  int _searchToken = 0;

  String _query = '';
  bool _isSearching = false;
  String? _searchError;
  List<ProductModel> _searchResults = [];

  // Filter & Sort State
  ProductFilterOptions _filterOptions = ProductFilterOptions.empty;
  ProductSortOption _sortOption = ProductSortOption.relevance;

  final List<String> _popularTags = [
    'Milk',
    'Bread',
    'Egg',
    'Atta',
    'Rice',
    'Oil',
    'Tomato',
    'Onion',
    'Biscuits',
    'Soap',
  ];

  @override
  void initState() {
    super.initState();
    // Auto-focus search input when screen opens
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
    if (trimmed.isEmpty && !_filterOptions.hasActiveFilters) {
      setState(() {
        _query = '';
        _isSearching = false;
        _searchError = null;
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _query = trimmed;
      _isSearching = true;
      _searchError = null;
    });

    // Crisp 250ms debounce for typing responsiveness without lag
    _searchDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      _executeSearch(trimmed);
    });
  }

  Future<void> _executeSearch(String query) async {
    if (!mounted) return;
    final int currentToken = ++_searchToken;

    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty && !_filterOptions.hasActiveFilters) {
      if (mounted && _searchToken == currentToken) {
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

      // Fallback: If startup cache hasn't loaded products yet, fetch directly once
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

      // Execute high-speed search and multi-field ranking via ProductSearchEngine
      final results = ProductSearchEngine.filterProducts(
        products: allProducts,
        rawQuery: cleanQuery,
        categories: categories,
        filterOptions: _filterOptions,
        sortOption: _sortOption,
      );

      if (!mounted) return;
      // Stale query protection: ignore outdated async responses
      if (_searchToken != currentToken) return;

      setState(() {
        _isSearching = false;
        _searchError = null;
        _searchResults = results;
      });
    } catch (e) {
      if (!mounted || _searchToken != currentToken) return;
      setState(() {
        _isSearching = false;
        _searchError = 'Unable to search products. Please try again.';
      });
    }
  }

  void _selectPopularTag(String tag) {
    _searchController.text = tag;
    _onQueryChanged(tag);
  }

  void _clearSearch() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _searchError = null;
    });

    if (_filterOptions.hasActiveFilters) {
      _executeSearch('');
    } else {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
    }
    _searchFocusNode.requestFocus();
  }

  void _openFilterBottomSheet() {
    final startup = context.read<StartupProvider>();
    final List<CategoryModel> categories = startup.categories;

    // Extract all unique brands dynamically
    final Set<String> brandSet = {};
    for (final p in startup.products) {
      if (p.brand.trim().isNotEmpty) {
        brandSet.add(p.brand.trim());
      }
    }
    final availableBrands = brandSet.toList()..sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SearchFilterBottomSheet(
        currentFilters: _filterOptions,
        currentSort: _sortOption,
        categories: categories,
        availableBrands: availableBrands,
        onApply: (updatedFilters, updatedSort) {
          setState(() {
            _filterOptions = updatedFilters;
            _sortOption = updatedSort;
            _isSearching = true;
          });
          _executeSearch(_query);
        },
      ),
    );
  }

  Future<void> _handleRefresh() async {
    await _executeSearch(_query);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bool hasActiveQueryOrFilter = _query.isNotEmpty || _filterOptions.hasActiveFilters;

    return Scaffold(
      backgroundColor: isDarkMode ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        backgroundColor: isDarkMode ? AppColors.darkSurface : AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        titleSpacing: 0,
        title: Container(
          height: 44,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
            border: Border.all(
              color: isDarkMode ? AppColors.darkBorder : AppColors.border,
            ),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            textInputAction: TextInputAction.search,
            onChanged: _onQueryChanged,
            onSubmitted: (val) {
              _searchDebounceTimer?.cancel();
              _executeSearch(val);
            },
            decoration: InputDecoration(
              hintText: 'Search groceries, atta, rice, milk...',
              hintStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: AppColors.textSecondary,
                size: 20,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                      onPressed: _clearSearch,
                    )
                  : IconButton(
                      icon: const Icon(
                        Icons.mic,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      onPressed: () async {
                        final query = await showDialog<String>(
                          context: context,
                          builder: (context) => const VoiceSearchDialog(),
                        );
                        if (query != null && query.isNotEmpty) {
                          _searchController.text = query;
                          _executeSearch(query);
                        }
                      },
                    ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.tune, color: AppColors.textPrimary),
                tooltip: 'Filter & Sort',
                onPressed: _openFilterBottomSheet,
              ),
              if (_filterOptions.hasActiveFilters || _sortOption != ProductSortOption.relevance)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${_filterOptions.activeFilterCount + (_sortOption != ProductSortOption.relevance ? 1 : 0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress Indicator while typing
            if (_isSearching)
              const LinearProgressIndicator(
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),

            // Quick Filter Chips Bar (Visible when searching or active filters)
            if (hasActiveQueryOrFilter) _buildQuickFilterBar(),

            // Main Content Area
            Expanded(
              child: hasActiveQueryOrFilter
                  ? _buildSearchResultsList()
                  : _buildInitialSearchDiscovery(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BannerAdWidget(adUnitId: AdMobConfig.searchBannerId),
    );
  }

  Widget _buildQuickFilterBar() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkSurface : AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: isDarkMode ? AppColors.darkBorder : AppColors.border,
            width: 0.5,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
        child: Row(
          children: [
            // Filter Button Chip
            ActionChip(
              avatar: Icon(
                Icons.tune,
                size: 16,
                color: _filterOptions.hasActiveFilters ? AppColors.primary : AppColors.textSecondary,
              ),
              label: Text(
                _filterOptions.hasActiveFilters
                    ? 'Filters (${_filterOptions.activeFilterCount})'
                    : 'Filter',
                style: TextStyle(
                  color: _filterOptions.hasActiveFilters ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: _filterOptions.hasActiveFilters ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
              backgroundColor: _filterOptions.hasActiveFilters ? AppColors.amberLight : Colors.transparent,
              onPressed: _openFilterBottomSheet,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
                side: BorderSide(
                  color: _filterOptions.hasActiveFilters ? AppColors.primary : AppColors.border,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // In Stock Only Quick Toggle
            FilterChip(
              label: const Text('In Stock'),
              selected: _filterOptions.inStockOnly,
              onSelected: (val) {
                setState(() {
                  _filterOptions = _filterOptions.copyWith(inStockOnly: val);
                  _isSearching = true;
                });
                _executeSearch(_query);
              },
              selectedColor: AppColors.amberLight,
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(
                color: _filterOptions.inStockOnly ? AppColors.primary : AppColors.textPrimary,
                fontWeight: _filterOptions.inStockOnly ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
                side: BorderSide(
                  color: _filterOptions.inStockOnly ? AppColors.primary : AppColors.border,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Sort Quick Label Chip
            ActionChip(
              avatar: const Icon(Icons.sort, size: 16, color: AppColors.textSecondary),
              label: Text(
                _sortOption.label,
                style: TextStyle(
                  color: _sortOption != ProductSortOption.relevance ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: _sortOption != ProductSortOption.relevance ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
              backgroundColor: _sortOption != ProductSortOption.relevance ? AppColors.amberLight : Colors.transparent,
              onPressed: _openFilterBottomSheet,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
                side: BorderSide(
                  color: _sortOption != ProductSortOption.relevance ? AppColors.primary : AppColors.border,
                ),
              ),
            ),

            // Clear All Filters (if active)
            if (_filterOptions.hasActiveFilters || _sortOption != ProductSortOption.relevance) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _filterOptions = ProductFilterOptions.empty;
                    _sortOption = ProductSortOption.relevance;
                    _isSearching = true;
                  });
                  _executeSearch(_query);
                },
                child: const Text(
                  'Clear Filters',
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultsList() {
    if (_searchError != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                  const SizedBox(height: AppDimensions.spacingMedium),
                  Text(
                    _searchError!,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppDimensions.spacingMedium),
                  ElevatedButton(
                    onPressed: () => _executeSearch(_query),
                    child: const Text('Retry Search'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_isSearching && _searchResults.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: 6,
        itemBuilder: (context, index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          height: 120,
          child: const ProductSkeletonCard(),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off, size: 64, color: AppColors.muted),
                  const SizedBox(height: AppDimensions.spacingMedium),
                  Text(
                    _query.isNotEmpty
                        ? 'No products found for "$_query"'
                        : 'No products match selected filters',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppDimensions.spacingSmall),
                  const Text(
                    'Try another keyword or reset filters',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppDimensions.spacingMedium),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_filterOptions.hasActiveFilters)
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _filterOptions = ProductFilterOptions.empty;
                              _sortOption = ProductSortOption.relevance;
                              _isSearching = true;
                            });
                            _executeSearch(_query);
                          },
                          child: const Text('Clear Filters'),
                        ),
                      if (_filterOptions.hasActiveFilters && _query.isNotEmpty)
                        const SizedBox(width: 12),
                      if (_query.isNotEmpty)
                        ElevatedButton(
                          onPressed: _clearSearch,
                          child: const Text('Clear Search'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      itemCount: _searchResults.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // Dynamic Result Header Row
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMedium,
              vertical: 8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_searchResults.length} ${_searchResults.length == 1 ? 'product' : 'products'} found${_query.isNotEmpty ? ' for "$_query"' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  _sortOption.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          );
        }

        final product = _searchResults[index - 1];
        return HorizontalProductCard(product: product);
      },
    );
  }

  Widget _buildInitialSearchDiscovery() {
    final firestore = context.read<FirestoreService>();

    return ListView(
      children: [
        // Popular Searches Section
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingMedium,
            vertical: AppDimensions.paddingSmall,
          ),
          child: Text(
            'Popular Searches',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _popularTags.map((tag) {
              return ActionChip(
                label: Text(tag),
                onPressed: () => _selectPopularTag(tag),
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

        // Browse Categories Grid
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
          child: Text(
            'Browse Categories',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: AppDimensions.spacingSmall),

        StreamBuilder<List<CategoryModel>>(
          stream: firestore.categoriesStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
                  itemCount: 5,
                  separatorBuilder: (_, __) => const SizedBox(width: AppDimensions.spacingNormal),
                  itemBuilder: (context, index) => const CategorySkeletonCard(),
                ),
              );
            }

            final categories = snapshot.data ?? [];
            if (categories.isEmpty) {
              return const SizedBox.shrink();
            }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
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
      ],
    );
  }
}
