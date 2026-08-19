import 'dart:async';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/settings_provider.dart';
import '../../../widgets/banner_ad_widget.dart';
import '../../../config/admob_config.dart';

import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/native_ad_card.dart';
import '../../../services/native_ad_manager.dart';

import '../../../services/current_user_provider.dart';
import '../../../services/startup_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../cart/presentation/cart_provider.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../orders/presentation/my_orders_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../../core/widgets/skeleton_loader.dart';

class HomeScreen extends StatefulWidget {
  final int initialTab;
  const HomeScreen({super.key, this.initialTab = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;

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
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ChangeNotifierProvider(
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Categories',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: 'Top Picks',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart),
            label: 'Cart',
          ),
        ],
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NativeAdManager.instance.preloadAd();
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
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      provider.query = value;
    });
  }

  Future<void> _refreshHomeData() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {});
    }
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

  Widget _buildBestSellersSection(bool loading, List<ProductModel> products, {bool isLoadingMore = false}) {
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
      return const Padding(
        padding: EdgeInsets.all(AppDimensions.paddingLarge),
        child: Text(Messages.noProductsHome),
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

      // Show Native Ad after every chunk of 20 products
      if (end % productsPerChunk == 0) {
        gridItems.add(NativeAdCard(key: ValueKey('home_native_ad_$end')));
      }
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

    if (_searchController.text != searchProvider.query && searchProvider.query.isEmpty) {
      _searchController.text = searchProvider.query;
    }

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
                      ProductSearchEngine.filterProducts(
                        products: startup.products,
                        rawQuery: searchProvider.query,
                        categories: startup.categories,
                      ),
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
                      onChanged: (value) => _onSearchChanged(value, searchProvider),
                      onSubmitted: (value) {
                        if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
                        searchProvider.query = value;
                      },
                      decoration: InputDecoration(
                        hintText: context.translate('searchPlaceholder'),
                        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        prefixIcon: const Icon(AppIcons.search, color: AppColors.textSecondary, size: 20),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.mic, color: AppColors.primary, size: 20),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Text('Voice Search'),
                                content: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.mic, size: 48, color: AppColors.primary),
                                    SizedBox(height: 12),
                                    Text('Listening... Say product name', style: TextStyle(color: AppColors.textSecondary)),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel', style: TextStyle(color: AppColors.primary)),
                                  ),
                                ],
                              ),
                            );
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
          const SizedBox(height: AppDimensions.spacingNormal),

          // Auto-sliding Banner Carousel
          const BannerCarousel(),
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

          // Best Sellers 2-column grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
            child: Text(
              isSearch ? 'Search Results' : 'Best Sellers',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
            ),
          ),
          const SizedBox(height: AppDimensions.spacingNormal),
          _buildBestSellersSection(
            loading,
            products,
            isLoadingMore: !isSearch && startup.isLoadingMore,
          ),
          const SizedBox(height: AppDimensions.spacingLarge),
        ],
      ),
    );
  }

  Widget _buildDeliveryAvailabilityBanner() {
    return StreamBuilder<ShopSettingsModel>(
      stream: FirestoreService().shopSettingsStream(),
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

  Widget _buildCategoriesSection(List<CategoryModel> categories) {
    if (categories.isEmpty) {
      return SizedBox(
        height: 110,
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
      height: 110,
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
            onTap: () => context.push('/products/${category.id}?name=${Uri.encodeComponent(category.name)}'),
          );
        },
      ),
    );
  }
}

class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;
  int _bannerCount = 0;
  final Set<String> _recordedBannerViews = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  void _startTimer() {
    _timer?.cancel();
    if (_bannerCount > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
        if (mounted) {
          setState(() {
            _currentPage++;
            _pageController.animateToPage(
              _currentPage,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
            );
          });
        }
      });
    }
  }

  void _recordViewIfNeeded(List<BannerModel> activeBanners, int index) {
    if (activeBanners.isEmpty) return;
    final banner = activeBanners[index % activeBanners.length];
    if (!_recordedBannerViews.contains(banner.id)) {
      _recordedBannerViews.add(banner.id);
      FirestoreService().recordBannerView(banner.id);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final startup = context.watch<StartupProvider>();
    final activeBanners = startup.banners.where((b) => b.isCurrentlyActive).toList();
    if (activeBanners.length != _bannerCount) {
      _bannerCount = activeBanners.length;
      _currentPage = _bannerCount > 1 ? _bannerCount * 500 : 0;
      _pageController.dispose();
      _pageController = PageController(initialPage: _currentPage);
      _startTimer();
      if (activeBanners.isNotEmpty) {
        _recordViewIfNeeded(activeBanners, _currentPage);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startup = context.watch<StartupProvider>();
    final activeBanners = startup.banners.where((b) => b.isCurrentlyActive).toList();

    if (activeBanners.isEmpty) {
      return const SizedBox.shrink();
    }

    final int actualCount = activeBanners.length;
    final int virtualCount = actualCount > 1 ? actualCount * 1000 : 1;

    return Column(
      children: [
        SizedBox(
          height: 145,
          child: PageView.builder(
            controller: _pageController,
            itemCount: virtualCount,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
              _recordViewIfNeeded(activeBanners, index);
            },
            itemBuilder: (context, index) {
              final banner = activeBanners[index % actualCount];
              return Hero(
                tag: 'banner_image_${banner.id}',
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _handleBannerTap(banner),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: banner.imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey.shade100,
                                child: const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(colors: [Color(0xFF15803D), Color(0xFF22C55E)]),
                                ),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      banner.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (banner.subtitle.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        banner.subtitle,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            // Gradient overlay for readability if texts exist
                            if (banner.title.isNotEmpty || banner.subtitle.isNotEmpty)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.6),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        banner.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if (banner.subtitle.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          banner.subtitle,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            // Countdown Timer (if enabled)
                            if (banner.countdownEnabled)
                              Positioned(
                                top: 12,
                                right: 12,
                                child: BannerCountdownWidget(endDateTime: banner.endDateTime),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (actualCount > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(actualCount, (idx) {
              final isSelected = (_currentPage % actualCount) == idx;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isSelected ? 12 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  void _handleBannerTap(BannerModel banner) async {
    // 1. Record analytics click
    await FirestoreService().recordBannerClick(banner.id);

    // 2. Set clicked banner in cart provider for conversion attribution
    if (mounted) {
      context.read<CartProvider>().bannerIdClicked = banner.id;
    }

    // 3. Perform click action navigation
    final destination = banner.actionType;
    final target = banner.actionTarget;

    if (!mounted) return;

    switch (destination) {
      case 'Open Product':
        context.push('/product/$target');
        break;
      case 'Open Category':
        context.push('/products/$target?name=${Uri.encodeComponent(banner.title)}');
        break;
      case 'Open Brand':
        final searchProvider = context.read<HomeSearchProvider>();
        searchProvider.query = target;
        break;
      case 'Open Offer Page':
        context.push('/offer/${banner.id}?title=${Uri.encodeComponent(banner.title)}');
        break;
      case 'Open Collection':
        final searchProvider = context.read<HomeSearchProvider>();
        searchProvider.query = target;
        break;
      case 'Open Search':
        final searchProvider = context.read<HomeSearchProvider>();
        searchProvider.query = target;
        break;
      case 'External URL':
        final uri = Uri.tryParse(target);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
      case 'No Action':
      default:
        break;
    }
  }
}

class BannerCountdownWidget extends StatefulWidget {
  final DateTime endDateTime;
  const BannerCountdownWidget({super.key, required this.endDateTime});

  @override
  State<BannerCountdownWidget> createState() => _BannerCountdownWidgetState();
}

class _BannerCountdownWidgetState extends State<BannerCountdownWidget> {
  late Timer _timer;
  late Duration _timeLeft;

  @override
  void initState() {
    super.initState();
    _calculateTimeLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _calculateTimeLeft();
        });
      }
    });
  }

  void _calculateTimeLeft() {
    _timeLeft = widget.endDateTime.difference(DateTime.now());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_timeLeft.isNegative) {
      return const SizedBox.shrink();
    }

    final hours = _timeLeft.inHours.toString().padLeft(2, '0');
    final minutes = (_timeLeft.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (_timeLeft.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: Colors.orangeAccent, size: 13),
          const SizedBox(width: 4),
          Text(
            'Ends in $hours:$minutes:$seconds',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier', // Monospace font for stable digit sizing
            ),
          ),
        ],
      ),
    );
  }
}

class CategoriesTabScreen extends StatelessWidget {
  const CategoriesTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestore = context.read<FirestoreService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Categories', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<CategoryModel>>(
        stream: firestore.categoriesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
            if (!ConnectivityProvider.instance.isOnline) {
              return const OfflinePlaceholderWidget();
            }
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          final categories = snapshot.data ?? [];
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              childAspectRatio: 0.8,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return CategoryCard(
                title: category.name,
                categoryImage: category.imageUrl,
                onTap: () => context.push('/products/${category.id}?name=${Uri.encodeComponent(category.name)}'),
              );
            },
          );
        },
      ),
    );
  }
}

class TopPicksTabScreen extends StatelessWidget {
  const TopPicksTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestore = context.read<FirestoreService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Top Picks for You', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<ProductModel>>(
        stream: firestore.productsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          // Filter products that have a discount (mrp > price)
          final topPicks = (snapshot.data ?? [])
              .where((product) => product.mrp > product.price)
              .toList();

          if (topPicks.isEmpty) {
            return const Center(child: Text('No top picks available right now.'));
          }

          return GridView.builder(
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
        },
      ),
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
