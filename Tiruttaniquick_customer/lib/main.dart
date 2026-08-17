import 'dart:ui';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/cart/presentation/cart_provider.dart';
import 'firebase_options.dart';
import 'services/current_user_provider.dart';
import 'services/service_area_provider.dart';
import 'services/settings_provider.dart';
import 'services/startup_provider.dart';

Future<void> main() async {
  final appStartupStopwatch = AuthPerformanceLogger.start('App Startup');

  // Step 1: Ensure Flutter widget binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Global Flutter framework error handler — prevents white screen of death in release
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[Startup Log] [FlutterError] ${details.exceptionAsString()}\n${details.stack}');
  };

  // Global isolate/async error handler — catches errors outside the widget tree
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[Startup Log] [PlatformError] $error\n$stack');
    return true; // Returning true prevents the app from crashing
  };

  // Replace default yellow/red error screen with user-friendly error UI
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFEA580C), size: 48),
              SizedBox(height: 12),
              Text(
                'Something went wrong',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
              ),
              SizedBox(height: 4),
              Text(
                'Please refresh or try again later.',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  };

  String? initError;

  // Step 2: Load environment variables
  try {
    debugPrint('[Startup Log] Step 1: Loading .env configuration...');
    await dotenv.load(fileName: '.env');
    debugPrint('[Startup Log] Step 1 Complete: .env loaded successfully.');
  } catch (e, stack) {
    debugPrint('[Startup Log] Step 1 Warning: .env file loading failed or missing: $e\n$stack');
    // Non-fatal, app can proceed with default fallback values
  }

  // Step 3: Initialize Firebase Core BEFORE runApp() to avoid uninitialized service calls
  try {
    await AuthPerformanceLogger.trace(
      'Firebase Core Initialization',
      () => Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ),
    );
    debugPrint('[Startup Log] Step 2 Complete: Firebase App Core initialized.');
  } catch (e, stack) {
    debugPrint('[Startup Log] CRITICAL ERROR initializing Firebase: $e\n$stack');
    initError = 'Failed to initialize core services: $e';
  }

  AuthPerformanceLogger.stopAndLog(appStartupStopwatch, 'App Startup');

  if (initError != null) {
    runApp(StartupErrorApp(errorMessage: initError));
  } else {
    runApp(const GroceryApp());
  }
}


class StartupErrorApp extends StatelessWidget {
  final String errorMessage;

  const StartupErrorApp({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFDC2626),
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Initialization Error',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'The application encountered a problem during startup:\n$errorMessage',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF4B5563),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    main();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry Startup'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GroceryApp extends StatelessWidget {
  const GroceryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: startupProvider),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..init()),
        ChangeNotifierProvider.value(value: currentUserProvider),
        ChangeNotifierProvider.value(value: serviceAreaProvider),
        // CartProvider is bound to CurrentUserProvider so it self-initialises
        // the moment the auth state resolves, preventing first-login race conditions.
        ChangeNotifierProvider(
          create: (_) {
            final cart = CartProvider();
            // Reactive binding: cart listens to currentUserProvider and
            // initialises itself as soon as a user session is available.
            cart.bindToUserProvider(currentUserProvider);
            return cart;
          },
        ),
        Provider(create: (_) => FirestoreService()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp.router(
            title: AppStrings.appTitle,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: settings.themeMode,
            routerConfig: router,
            builder: (context, child) {
              return Consumer<CurrentUserProvider>(
                builder: (context, userProvider, _) {
                  return ConnectivityWrapper(
                    child: InAppNotificationListener(
                      currentUserId: userProvider.firebaseUser?.uid,
                      onPlaySound: () {
                        try {
                          FlutterRingtonePlayer().playNotification();
                        } catch (e) {
                          debugPrint('[Ringtone] Error playing ringtone: $e');
                        }
                      },
                      onTapNotification: (orderId) {
                        if (orderId != null && orderId.isNotEmpty) {
                          router.push('${AppRoutes.myOrders}/$orderId');
                        }
                      },
                      child: child ?? const SizedBox.shrink(),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
