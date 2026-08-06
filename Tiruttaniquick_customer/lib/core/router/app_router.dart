import 'package:flutter/material.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/checkout/presentation/checkout_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/orders/presentation/order_tracking_screen.dart';
import '../../features/products/presentation/product_listing_screen.dart';
import '../../features/products/presentation/product_details_screen.dart';
import '../../features/products/presentation/offer_products_screen.dart';
import '../../features/service_area/location_check_screen.dart';
import '../../features/service_area/service_unavailable_screen.dart';
import '../../services/current_user_provider.dart';
import '../../services/service_area_provider.dart';
import '../../services/startup_provider.dart';
import '../../features/profile/presentation/settings_screen.dart';
import '../../features/profile/presentation/account_deletion_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';

CustomTransitionPage<T> buildPageWithTransition<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOut,
        ),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 0.05), // subtle slide up for modern feel
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutQuad,
          )),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 250),
  );
}

final router = GoRouter(
  initialLocation: '/splash',
  refreshListenable: Listenable.merge([currentUserProvider, serviceAreaProvider, startupProvider]),
  redirect: (context, state) {
    final location = state.matchedLocation;

    // Gate: Stay on splash until high-priority startup initialization completes
    if (!startupProvider.isInitialized) {
      if (location != '/splash') {
        return '/splash';
      }
      return null;
    }

    if (location == '/splash') return null;


    // 2. Authentication Gate
    final currentUser = currentUserProvider;
    if (currentUser.loading) return null;

    final targetRedirect = () {
      if (!currentUser.isAuthenticated) {
        if (state.matchedLocation == AppRoutes.home ||
            state.matchedLocation == '/search' ||
            state.matchedLocation.startsWith('/products/') ||
            state.matchedLocation.startsWith('/product/') ||
            state.matchedLocation == AppRoutes.login ||
            state.matchedLocation == AppRoutes.signUp ||
            state.matchedLocation == AppRoutes.otp) {
          return null;
        }
        return AppRoutes.login;
      }

      // Authenticated users
      if (location == AppRoutes.login ||
          location == AppRoutes.signUp ||
          location == AppRoutes.otp) {
        return AppRoutes.home;
      }

      return null;
    }();

    if (targetRedirect != null) {
      AuthPerformanceLogger.stopAndLog(
        AuthPerformanceLogger.start('Route Redirect ($location -> $targetRedirect)'),
        'Route Redirect',
      );
    }
    return targetRedirect;
  },

  routes: [
    GoRoute(
      path: '/splash',
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const SplashScreen(),
      ),
    ),
    GoRoute(
      path: '/location-check',
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const LocationCheckScreen(),
      ),
    ),
    GoRoute(
      path: '/service-unavailable',
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const ServiceUnavailableScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.login,
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const LoginScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.signUp,
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const SignUpScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.otp,
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const OtpScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.home,
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const HomeScreen(initialTab: 0),
      ),
    ),
    GoRoute(
      path: '/search',
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const HomeScreen(initialTab: 1),
      ),
    ),
    GoRoute(
      path: '/products/:categoryId',
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: ProductListingScreen(
          categoryId: state.pathParameters['categoryId']!,
          categoryName: state.uri.queryParameters['name'] ?? 'Products',
        ),
      ),
    ),
    GoRoute(
      path: '/offer/:offerId',
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: OfferProductsScreen(
          offerId: state.pathParameters['offerId']!,
          title: state.uri.queryParameters['title'] ?? 'Special Offer',
        ),
      ),
    ),
    GoRoute(
      path: '/product/:productId',
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: ProductDetailsScreen(
          productId: state.pathParameters['productId']!,
          selectedBarcode: state.uri.queryParameters['barcode'],
          selectedVariantId: state.uri.queryParameters['variantId'],
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.cart,
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const HomeScreen(initialTab: 2),
      ),
    ),
    GoRoute(
      path: AppRoutes.checkout,
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const CheckoutScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.myOrders,
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const HomeScreen(initialTab: 3),
      ),
    ),
    GoRoute(
      path: '${AppRoutes.myOrders}/:orderId',
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: OrderTrackingScreen(orderId: state.pathParameters['orderId']!),
      ),
    ),
    GoRoute(
      path: AppRoutes.profile,
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const HomeScreen(initialTab: 4),
      ),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const SettingsScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.deleteAccount,
      pageBuilder: (context, state) => buildPageWithTransition(
        context: context,
        state: state,
        child: const AccountDeletionScreen(),
      ),
    ),
  ],
);
