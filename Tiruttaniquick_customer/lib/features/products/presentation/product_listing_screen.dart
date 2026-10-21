import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/startup_provider.dart';

import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../widgets/banner_ad_widget.dart';
import '../../../config/admob_config.dart';
import '../../../core/widgets/native_ad_card.dart';

class ProductListingScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const ProductListingScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<ProductListingScreen> createState() => _ProductListingScreenState();
}

class _ProductListingScreenState extends State<ProductListingScreen> {
  List<ProductModel> _products = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final cached = ProductRepository.instance.getCachedProducts(categoryId: widget.categoryId);
    if (cached.isNotEmpty) {
      // Apply offers immediately using the startup provider after the first frame
      // so that context is available.
      _products = cached;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final startup = context.read<StartupProvider>();
          setState(() {
            _products = startup.applyOffers(cached);
          });
        }
      });
      debugPrint('[PRODUCT] initial load SUCCESS (from cache, count: ${_products.length})');
    } else {
      _loadProducts();
    }
  }

  Future<void> _loadProducts() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final startup = context.read<StartupProvider>();
      final items = await ProductRepository.instance.loadInitialProducts(categoryId: widget.categoryId);
      if (mounted) {
        setState(() {
          _products = startup.applyOffers(items);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Unable to load products. Please check your internet connection and try again.';
        });
      }
    }
  }

  Future<void> _refreshListing() async {
    try {
      final startup = context.read<StartupProvider>();
      final refreshed = await ProductRepository.instance.refreshProducts(categoryId: widget.categoryId);
      if (mounted) {
        setState(() {
          _products = startup.applyOffers(refreshed);
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't refresh products. Please try again."),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName)),
      body: RefreshIndicator(
        onRefresh: _refreshListing,
        child: _buildBody(context),
      ),
      bottomNavigationBar: BannerAdWidget(adUnitId: AdMobConfig.categoryBannerId),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading && _products.isEmpty) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.58,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 4,
        itemBuilder: (context, index) => const ProductSkeletonCard(),
      );
    }

    if (_errorMessage != null && _products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadProducts,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_products.isEmpty) {
      return const Center(child: Text(Messages.noProductsInCategory));
    }

    final List<Widget> slivers = [];
    const int productsPerChunk = 20;

    for (int i = 0; i < _products.length; i += productsPerChunk) {
      final int end = (i + productsPerChunk < _products.length)
          ? i + productsPerChunk
          : _products.length;
      final chunk = _products.sublist(i, end);

      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.58,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return ProductCard(product: chunk[index]);
              },
              childCount: chunk.length,
            ),
          ),
        ),
      );

      // Show Native Ad after every chunk of 20 products
      if (end % productsPerChunk == 0) {
        slivers.add(
          SliverToBoxAdapter(
            child: NativeAdCard(key: ValueKey('category_native_ad_$end')),
          ),
        );
      }
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(), // Ensures pull-to-refresh works
      slivers: slivers,
    );
  }
}
