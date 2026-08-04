import 'package:blinkit_shared/blinkit_shared.dart';
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

  const ProductListingScreen({super.key, required this.categoryId, required this.categoryName});

  @override
  State<ProductListingScreen> createState() => _ProductListingScreenState();
}

class _ProductListingScreenState extends State<ProductListingScreen> {
  Future<void> _refreshListing() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.read<FirestoreService>();

    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName)),
      body: RefreshIndicator(
        onRefresh: _refreshListing,
        child: StreamBuilder<List<ProductModel>>(
          stream: firestore.productsStream(categoryId: widget.categoryId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
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
  
            final rawProducts = snapshot.data ?? [];
            final products = context.watch<StartupProvider>().applyOffers(rawProducts);
            if (products.isEmpty) {
              return const Center(child: Text(Messages.noProductsInCategory));
            }
  
            final List<Widget> slivers = [];
            const int productsPerChunk = 20;

            for (int i = 0; i < products.length; i += productsPerChunk) {
              final int end = (i + productsPerChunk < products.length)
                  ? i + productsPerChunk
                  : products.length;
              final chunk = products.sublist(i, end);

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
          },
        ),
      ),
      bottomNavigationBar: BannerAdWidget(adUnitId: AdMobConfig.categoryBannerId),
    );
  }
}

