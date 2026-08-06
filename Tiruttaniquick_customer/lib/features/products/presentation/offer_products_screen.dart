import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../services/startup_provider.dart';

class OfferProductsScreen extends StatelessWidget {
  final String offerId;
  final String title;

  const OfferProductsScreen({
    super.key,
    required this.offerId,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final firestore = context.read<FirestoreService>();
    final startupProvider = context.watch<StartupProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<ProductModel>>(
        stream: firestore.productsStream(includeInactive: false),
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

          final allProducts = snapshot.data ?? [];
          // Apply active offers to see which ones get this offerId applied
          final decoratedProducts = startupProvider.applyOffers(allProducts);
          final offerProducts = decoratedProducts
              .where((product) =>
                  product.appliedOfferId == offerId ||
                  product.variants.any((v) => v.appliedOfferId == offerId))
              .toList();

          if (offerProducts.isEmpty) {
            return const Center(
              child: Text(
                'No products available for this offer right now.',
                style: TextStyle(color: AppColors.muted),
              ),
            );
          }

          return GridView.builder(
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
        },
      ),
    );
  }
}
