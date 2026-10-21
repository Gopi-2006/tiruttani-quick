import 'dart:async';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../services/settings_provider.dart';
import '../../../widgets/banner_ad_widget.dart';
import '../../../config/admob_config.dart';

import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/native_ad_card.dart';
import '../../../services/native_ad_manager.dart';

import '../../../services/current_user_provider.dart';
import '../../../services/startup_provider.dart';

import '../../cart/presentation/cart_screen.dart';
import '../../cart/presentation/cart_provider.dart';
import '../../orders/presentation/my_orders_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/voice_search_dialog.dart';
import 'widgets/banner_carousel.dart';

class HomeScreen extends StatefulWidget {
  final int initialTab;
  const HomeScreen({super.key, this.initialTab = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;
  bool _isNavVisible = true;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
    // Cart initialization is handled reactively in main.dart via
    // CartProvider.bindToUserProvider(). No manual sync needed here.
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() {
        _selectedIndex = widget.initialTab;
        _isNavVisible = true;
      });
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    return ScrollHideBottomNav.handleScrollNotification(
      notification: notification,
      isCurrentlyVisible: _isNavVisible,
      onVisibilityChanged: (newVisibility) {
        if (mounted) {
          setState(() => _isNavVisible = newVisibility);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final cartCount = cartProvider.itemCount;

    return Scaffold(
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ChangeNotifierProvider(
          create: (_) => HomeSearchProvider(),
          child: IndexedStack(
            index: _selectedIndex,
            children: const [
              _HomeBody(),
              CategoriesTabScreen(),
              TopPicksTabScreen(),
              MyOrdersScreen(),
              CartScreen(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: ScrollHideBottomNav(
        isVisible: _isNavVisible,
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
              _isNavVisible = true;
            });
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view),
              label: 'Categories',
            ),
            const NavigationDestination(
              icon: Icon(Icons.star_outline),
              selectedIcon: Icon(Icons.star),
              label: 'Top Picks',
            ),
            const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Orders',
            ),
            NavigationDestination(
              icon: cartCount > 0
                  ? Badge(
                      label: Text('$cartCount'),
                      backgroundColor: AppColors.primary,
                      textColor: Colors.white,
                      child: const Icon(Icons.shopping_cart_outlined),
                    )
                  : const Icon(Icons.shopping_cart_outlined),
              selectedIcon: cartCount > 0
                  ? Badge(
                      label: Text('$cartCount'),
                      backgroundColor: AppColors.primary,
                      textColor: Colors.white,
                      child: const Icon(Icons.shopping_cart),
                    )
                  : const Icon(Icons.shopping_cart),
              label: 'Cart',
            ),
          ],
        ),
      ),
    );
  }

}

class _HomeBody extends StatefulWidget {
  const _HomeBody();

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  Timer? _debounceTimer;
  final _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _lastSyncedQuery = '';
  // Cached stream — created once in initState so every home rebuild
  // doesn't open a new Firestore listener for shop settings.
  late final Stream<ShopSettingsModel> _shopSettingsStream;

  @override
  void initState() {
    super.initState();
    _shopSettingsStream = FirestoreService().shopSettingsStream();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NativeAdManager.instance.preloadAd();
      if (ProductRepository.instance.getCachedProducts().isEmpty) {
        ProductRepository.instance.loadInitialProducts().then((_) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final searchProvider = context.read<HomeSearchProvider>();
      if (searchProvider.query.isEmpty) {
        context.read<StartupProvider>().loadNextPageProducts();
      }
    }
  }

  void _onSearchChanged(String value, HomeSearchProvider provider) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      _lastSyncedQuery = value;
      provider.query = value;
    });
  }

  Future<void> _refreshHomeData() async {
    // Actually refresh the product catalog from Firestore (not just a fake setState).
    try {
      await ProductRepository.instance.refreshProducts();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _showFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sort & Filter',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.sort_by_alpha, color: AppColors.primary),
                title: const Text('Name: A to Z'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.trending_down, color: AppColors.primary),
                title: const Text('Price: Low to High'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.trending_up, color: AppColors.primary),
                title: const Text('Price: High to Low'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopPicksSection(bool loading, List<ProductModel> products) {
    if (loading && products.isEmpty) {
      return const SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final topPicks = products.where((product) => product.mrp > product.price).toList();
    if (topPicks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
        child: Text('No discounted picks available today.', style: TextStyle(color: AppColors.muted)),
      );
    }

    return SizedBox(
      height: 280,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
        itemCount: topPicks.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppDimensions.spacingNormal),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 155,
            child: ProductCard(product: topPicks[index]),
          );
        },
      ),
    );
  }

  Widget _buildBestSellersSection(
    bool loading,
    List<ProductModel> products, {
    bool isLoadingMore = false,
    String searchQuery = '',
  }) {
    if (loading && products.isEmpty) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.58,
          crossAxisSpacing: AppDimensions.spacingNormal,
          mainAxisSpacing: AppDimensions.spacingNormal,
        ),
        itemCount: 4,
        itemBuilder: (context, index) => const ProductSkeletonCard(),
      );
    }

    if (products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingLarge, vertical: 32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.inventory_2_outlined,
                size: 52,
                color: AppColors.muted,
              ),
              const SizedBox(height: 12),
              Text(
                searchQuery.trim().isNotEmpty
                    ? 'No products found for "${searchQuery.trim()}"'
                    : 'No products available right now.',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.text),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                searchQuery.trim().isNotEmpty
                    ? 'Try searching by a different name, category, or Tamil name.'
                    : 'Please check back soon.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final List<Widget> gridItems = [];
    const int productsPerChunk = 20;

    for (int i = 0; i < products.length; i += productsPerChunk) {
      final int end = (i + productsPerChunk < products.length)
          ? i + productsPerChunk
          : products.length;
      final chunk = products.sublist(i, end);

      gridItems.add(
        GridView.builder(
          key: PageStorageKey('best_sellers_grid_$i'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.58,
            crossAxisSpacing: AppDimensions.spacingNormal,
            mainAxisSpacing: AppDimensions.spacingNormal,
          ),
          itemCount: chunk.length,
          itemBuilder: (context, index) {
            return ProductCard(product: chunk[index]);
          },
        ),
      );
    }

    return Column(
      children: [
        ...gridItems,
        if (isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchProvider = context.watch<HomeSearchProvider>();
    final startup = context.watch<StartupProvider>();

    // Sync text controller ONLY if provider query changed externally (e.g. voice search, banner click)
    if (searchProvider.query != _lastSyncedQuery) {
      _lastSyncedQuery = searchProvider.query;
      if (_searchController.text != searchProvider.query) {
        _searchController.text = searchProvider.query;
      }
    }

    final cachedCatalog = ProductRepository.instance.getCachedProducts();
    final allProducts = cachedCatalog.isNotEmpty ? cachedCatalog : startup.products;

    final List<ProductModel> searchResults = searchProvider.query.isNotEmpty
        ? ProductSearchEngine.filterProducts(
            products: allProducts,
            rawQuery: searchProvider.query,
            categories: startup.categories,
          )
        : <ProductModel>[];

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ranuka Store',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 18),
            ),
            Text(
              'Tiruttani Quick Delivery',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          Consumer<CurrentUserProvider>(
            builder: (context, userProvider, _) {
              if (!userProvider.isAuthenticated) {
                return TextButton(
                  onPressed: () => context.go(AppRoutes.login),
                  child: const Text(ButtonTexts.login),
                );
              }

              return IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                ),
                tooltip: Labels.profile,
                icon: const Icon(AppIcons.person, color: AppColors.primary),
              );
            },
          ),
        ],
      ),
      body: (!ConnectivityProvider.instance.isOnline && startup.products.isEmpty)
          ? OfflinePlaceholderWidget(
              onRetrySuccess: _refreshHomeData,
            )
          : RefreshIndicator(
              onRefresh: _refreshHomeData,
              child: searchProvider.query.isNotEmpty
                  ? _buildHomeContent(
                      context,
                      false,
                      searchResults,
                      isSearch: true,
                      categories: startup.categories,
                    )
                  : _buildHomeContent(
                      context,
                      false,
                      startup.products,
                      isSearch: false,
                      categories: startup.categories,
                    ),
            ),
      bottomNavigationBar: BannerAdWidget(adUnitId: AdMobConfig.homeBannerId),
    );
  }

  Widget _buildHomeContent(
    BuildContext context,
    bool loading,
    List<ProductModel> products, {
    required bool isSearch,
    required List<CategoryModel> categories,
  }) {
    final searchProvider = context.read<HomeSearchProvider>();
    final startup = context.watch<StartupProvider>();

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDeliveryAvailabilityBanner(),
          // Search + Voice + Filter Header (Pill-shaped Figma style)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface, // #F7F7F7
                      borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        _onSearchChanged(value, searchProvider);
                        setState(() {});
                      },
                      onSubmitted: (value) {
                        if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
                        _lastSyncedQuery = value;
                        searchProvider.query = value;
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        hintText: context.translate('searchPlaceholder'),
                        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        prefixIcon: const Icon(AppIcons.search, color: AppColors.textSecondary, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: AppColors.textSecondary, size: 20),
                                onPressed: () {
                                  if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
                                  _searchController.clear();
                                  _lastSyncedQuery = '';
                                  searchProvider.query = '';
                                  setState(() {});
                                },
                              )
                            : IconButton(
                                icon: const Icon(Icons.mic, color: AppColors.primary, size: 20),
                                onPressed: () async {
                                  final query = await showDialog<String>(
                                    context: context,
                                    builder: (context) => const VoiceSearchDialog(),
                                  );
                                  if (query != null && query.isNotEmpty) {
                                    _searchController.text = query;
                                    _lastSyncedQuery = query;
                                    searchProvider.query = query;
                                    setState(() {});
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
                ),
                const SizedBox(width: AppDimensions.spacingSmall),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.amberLight,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.filter_list, size: 20),
                    color: AppColors.primary,
                    onPressed: () => _showFilterBottomSheet(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spacingNormal),

          if (isSearch) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Search Results (${products.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
                  ),
                  if (products.isNotEmpty)
                    const Text(
                      'Best Matches',
                      style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.spacingSmall),
            _buildBestSellersSection(
              loading,
              products,
              isLoadingMore: false,
              searchQuery: searchProvider.query,
            ),
            const SizedBox(height: AppDimensions.spacingLarge),
          ] else ...[
            // Promotional Banner Carousel (Directly below search bar, above categories)
            const BannerCarousel(),
            const SizedBox(height: AppDimensions.spacingMedium),

            // Shop by Category in the top
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
              child: Text(
                'Shop by Category',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingSmall),
            _buildCategoriesSection(categories),
            const SizedBox(height: AppDimensions.spacingMedium),

            // Top Picks Horizontal scrolling
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
              child: Text(
                'Top Picks for You',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingSmall),
            _buildTopPicksSection(loading, products),
            const SizedBox(height: AppDimensions.spacingLarge),

            // Dedicated Sponsored Ad Slot (kept separate from product picks)
            _buildSponsoredAdSlot(),
            const SizedBox(height: AppDimensions.spacingLarge),

            // Best Sellers 2-column grid
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
              child: Text(
                'Best Sellers',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingNormal),
            _buildBestSellersSection(
              loading,
              products,
              isLoadingMore: startup.isLoadingMore,
              searchQuery: '',
            ),
            const SizedBox(height: AppDimensions.spacingLarge),
          ],
        ],
      ),
    );
  }

  Widget _buildDeliveryAvailabilityBanner() {
    return StreamBuilder<ShopSettingsModel>(
      stream: _shopSettingsStream,
      builder: (context, snapshot) {
        final settings = snapshot.data ?? const ShopSettingsModel();
        if (settings.deliveryAvailable) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingMedium,
            vertical: AppDimensions.spacingSmall,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.remove_shopping_cart_rounded, color: Color(0xFFDC2626), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔴 Delivery Currently Unavailable',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF991B1B),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      settings.deliveryUnavailableMessage.isNotEmpty
                          ? settings.deliveryUnavailableMessage
                          : 'Orders are temporarily unavailable. Please try again later.',
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSponsoredAdSlot() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Sponsored',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const NativeAdCard(key: ValueKey('home_sponsored_ad_slot')),
      ],
    );
  }

  Widget _buildCategoriesSection(List<CategoryModel> categories) {
    if (categories.isEmpty) {
      return SizedBox(
        height: 148,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(width: AppDimensions.spacingLarge),
          itemBuilder: (context, index) => const CategorySkeletonCard(),
        ),
      );
    }

    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppDimensions.spacingLarge),
        itemBuilder: (context, index) {
          final category = categories[index];
          return CategoryCard(
            title: category.name,
            categoryImage: category.imageUrl,
            onTap: () {
              FocusScope.of(context).unfocus();
              context.push('/products/${category.id}?name=${Uri.encodeComponent(category.name)}');
            },
          );
        },
      ),
    );
  }
}

class CategoriesTabScreen extends StatelessWidget {
  const CategoriesTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final startup = context.watch<StartupProvider>();
    final categories = startup.categories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Categories', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: categories.isEmpty
          ? (!ConnectivityProvider.instance.isOnline
              ? const OfflinePlaceholderWidget()
              : const Center(child: CircularProgressIndicator(color: AppColors.primary)))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                childAspectRatio: 0.72,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                return CategoryCard(
                  title: category.name,
                  categoryImage: category.imageUrl,
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    context.push('/products/${category.id}?name=${Uri.encodeComponent(category.name)}');
                  },
                );
              },
            ),
    );
  }
}

class TopPicksTabScreen extends StatefulWidget {
  const TopPicksTabScreen({super.key});

  @override
  State<TopPicksTabScreen> createState() => _TopPicksTabScreenState();
}

class _TopPicksTabScreenState extends State<TopPicksTabScreen> {
  List<ProductModel> _products = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final cached = ProductRepository.instance.getCachedProducts();
    if (cached.isNotEmpty) {
      _products = cached;
    } else {
      _loadTopPicks();
    }
  }

  Future<void> _loadTopPicks() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final items = await ProductRepository.instance.loadInitialProducts();
      if (mounted) {
        setState(() {
          _products = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshTopPicks() async {
    try {
      final refreshed = await ProductRepository.instance.refreshProducts();
      if (mounted) {
        setState(() => _products = refreshed);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[PRODUCT] widget rebuild: TopPicksTabScreen');

    final topPicks = _products.where((product) => product.mrp > product.price).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Top Picks for You', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshTopPicks,
        child: _buildBody(topPicks),
      ),
    );
  }

  Widget _buildBody(List<ProductModel> topPicks) {
    if (_isLoading && _products.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (topPicks.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('No top picks available right now.')),
        ],
      );
    }

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.58,
      ),
      itemCount: topPicks.length,
      itemBuilder: (context, index) {
        return ProductCard(product: topPicks[index]);
      },
    );
  }
}

class HomeSearchProvider extends ChangeNotifier {
  String _query = '';
  String get query => _query;
  set query(String value) {
    _query = value;
    notifyListeners();
  }
}
