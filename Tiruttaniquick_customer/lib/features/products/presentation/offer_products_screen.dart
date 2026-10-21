import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../services/startup_provider.dart';

class OfferProductsScreen extends StatefulWidget {
  final String offerId;
  final String title;

  const OfferProductsScreen({
    super.key,
    required this.offerId,
    required this.title,
  });

  @override
  State<OfferProductsScreen> createState() => _OfferProductsScreenState();
}

class _OfferProductsScreenState extends State<OfferProductsScreen> {
  List<ProductModel> _products = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final cached = ProductRepository.instance.getCachedProducts();
    if (cached.isNotEmpty) {
      _products = cached;
    } else {
      _loadProducts();
    }
  }

  Future<void> _loadProducts() async {
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

  Future<void> _refreshProducts() async {
    try {
      final refreshed = await ProductRepository.instance.refreshProducts();
      if (mounted) {
        setState(() => _products = refreshed);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[PRODUCT] widget rebuild: OfferProductsScreen (${widget.title})');

    final startupProvider = context.read<StartupProvider>();
    final decoratedProducts = startupProvider.applyOffers(_products);
    final offerProducts = decoratedProducts
        .where((product) =>
            product.appliedOfferId == widget.offerId ||
            product.variants.any((v) => v.appliedOfferId == widget.offerId))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshProducts,
        child: _buildBody(offerProducts),
      ),
    );
  }

  Widget _buildBody(List<ProductModel> offerProducts) {
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

    if (offerProducts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(
            child: Text(
              'No products available for this offer right now.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.58,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: offerProducts.length,
      itemBuilder: (context, index) {
        return ProductCard(product: offerProducts[index]);
      },
    );
  }
}
