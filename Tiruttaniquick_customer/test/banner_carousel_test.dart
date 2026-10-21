import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tiruttaniquick_customer/features/home/presentation/widgets/banner_carousel.dart';
import 'package:tiruttaniquick_customer/features/home/presentation/widgets/banner_shimmer.dart';
import 'package:tiruttaniquick_customer/services/startup_provider.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Banner Feature Tests', () {
    testWidgets('BannerShimmerWidget renders with 16:9 aspect ratio', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BannerShimmerWidget(),
          ),
        ),
      );

      expect(find.byType(BannerShimmerWidget), findsOneWidget);
      expect(find.byType(AspectRatio), findsOneWidget);

      final AspectRatio aspectRatioWidget = tester.widget(find.byType(AspectRatio));
      expect(aspectRatioWidget.aspectRatio, 16 / 9);
    });

    testWidgets('BannerCarousel displays shimmer loading state when not initialized', (tester) async {
      final startupProvider = StartupProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<StartupProvider>.value(
          value: startupProvider,
          child: const MaterialApp(
            home: Scaffold(
              body: BannerCarousel(),
            ),
          ),
        ),
      );

      // Shows shimmer skeleton when not yet initialized with banners
      expect(find.byType(BannerShimmerWidget), findsOneWidget);
    });

    test('BannerModel client-side expiry logic works correctly', () {
      final now = DateTime.now();

      final activeBanner = BannerModel.fromFirestore('active_1', {
        'title': 'Flat 20% Off Groceries',
        'subtitle': 'Shop top daily essentials',
        'imageUrl': 'https://example.com/banner.jpg',
        'actionType': 'Open Category',
        'actionTarget': 'groceries',
        'isActive': true,
        'startDateTime': now.subtract(const Duration(days: 1)),
        'endDateTime': now.add(const Duration(days: 2)),
      });

      final expiredBanner = BannerModel.fromFirestore('expired_1', {
        'title': 'Expired Sale',
        'imageUrl': 'https://example.com/expired.jpg',
        'isActive': true,
        'startDateTime': now.subtract(const Duration(days: 5)),
        'endDateTime': now.subtract(const Duration(days: 1)),
      });

      final inactiveBanner = BannerModel.fromFirestore('inactive_1', {
        'title': 'Inactive Banner',
        'imageUrl': 'https://example.com/inactive.jpg',
        'isActive': false,
      });

      expect(activeBanner.isCurrentlyActive, isTrue);
      expect(expiredBanner.isCurrentlyActive, isFalse);
      expect(inactiveBanner.isCurrentlyActive, isFalse);
    });
  });
}
