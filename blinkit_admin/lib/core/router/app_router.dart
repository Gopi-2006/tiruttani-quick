import 'package:blinkit_shared/blinkit_shared.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/admin/presentation/product_import_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../services/current_user_provider.dart';
import '../../features/splash/presentation/splash_screen.dart';

final router = GoRouter(
  initialLocation: '/splash',
  refreshListenable: currentUserProvider,
  redirect: (context, state) {
    final location = state.matchedLocation;
    if (location == '/splash') return null;

    final currentUser = currentUserProvider;
    if (currentUser.loading) return null;

    if (!currentUser.isAuthenticated) {
      return AppRoutes.login;
    }

    // Authenticated users

    if (location == AppRoutes.login) {
      return AppRoutes.admin;
    }

    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginScreen()),
    GoRoute(path: AppRoutes.admin, builder: (context, state) => const AdminDashboardScreen()),
    GoRoute(path: AppRoutes.adminImportProducts, builder: (context, state) => const ProductImportScreen()),
  ],
);
