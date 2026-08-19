import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/presentation/admin_dashboard_screen.dart';
import 'services/current_user_provider.dart';
import 'firebase_options.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() async {
  final appStartupStopwatch = AuthPerformanceLogger.start('Admin App Startup');
  WidgetsFlutterBinding.ensureInitialized();

  // Global Flutter framework error handler — prevents white screen of death in release
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };

  // Global isolate/async error handler — catches errors outside the widget tree
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PlatformError] $error\n$stack');
    return true;
  };

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
                'Admin UI Exception',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
              ),
              SizedBox(height: 4),
              Text(
                'An unhandled rendering error occurred.',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  };

  await AuthPerformanceLogger.trace(
    'Firebase Core Initialization',
    () => Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ),
  );

  AuthPerformanceLogger.stopAndLog(appStartupStopwatch, 'Admin App Startup');

  // Start background services asynchronously to enable instant UI rendering
  _initializeBackgroundServices();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const GroceryApp());
}


void _initializeBackgroundServices() async {
  try {
    // Initialize Firebase App Check
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
    );

    // Initialize our NotificationService
    await NotificationService.instance.initialize(
      onNotificationTap: (payload) {
        debugPrint('[Admin Main] Notification Tapped: $payload');
        final orderId = payload['orderId']?.toString() ?? '';
        router.go(AppRoutes.admin);
        if (orderId.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showOrderDetailsDialog(orderId);
          });
        }
      },
    );
  } catch (e) {
    debugPrint('Background services initialization error: $e');
  }
}

void showOrderDetailsDialog(String orderId) async {
  final navContext = router.routerDelegate.navigatorKey.currentContext;
  if (navContext == null) return;

  final db = FirebaseFirestore.instance;
  final firestore = navContext.read<FirestoreService>();

  showDialog(
    context: navContext,
    builder: (context) {
        return FutureBuilder<DocumentSnapshot>(
          future: db.collection('orders').doc(orderId).get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Dialog(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Loading order details...'),
                    ],
                  ),
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
              return AlertDialog(
                title: const Text('Error'),
                content: const Text('Could not load order details.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final order = OrderModel.fromFirestore(orderId, data);

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: OrderDetailsCard(
                    order: order,
                    firestore: firestore,
                    initiallyExpanded: true,
                    onChangeStatus: (status) async {
                      if (status == null) return;
                      final customerId = data['customerId'] as String?;
                      if (customerId != null && customerId.isNotEmpty) {
                        await firestore.createNotification(
                          userId: customerId,
                          title: 'Order Status Updated',
                          body: 'Order #${order.orderNumber} is now $status',
                          orderId: order.id,
                        );

                        // Dispatch Push Notification via Cloudflare Worker (FCM HTTP v1)
                        NotificationSenderService.instance.sendOrderStatusNotification(
                          orderId: order.id,
                          orderNumber: order.orderNumber,
                          customerId: customerId,
                          status: status,
                        );
                      }

                      final Map<String, dynamic> extra = {};
                      if (status == OrderStatuses.delivered) {
                        extra['deliveredAt'] = FieldValue.serverTimestamp();
                      } else if (status == OrderStatuses.confirmed) {
                        extra['confirmedAt'] = FieldValue.serverTimestamp();
                      } else if (status == OrderStatuses.packed) {
                        extra['packedAt'] = FieldValue.serverTimestamp();
                      } else if (status == OrderStatuses.outForDelivery) {
                        extra['outForDeliveryAt'] = FieldValue.serverTimestamp();
                      }

                      await firestore.updateOrderStatus(
                        orderId: order.id,
                        status: status,
                        extra: extra,
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

class GroceryApp extends StatelessWidget {
  const GroceryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: currentUserProvider..init()),
        Provider(create: (_) => FirestoreService()),
      ],
      child: MaterialApp.router(
        title: 'Thiruttani Quick Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) {
          return Consumer<CurrentUserProvider>(
            builder: (context, userProvider, _) {
              return ConnectivityWrapper(
                child: InAppNotificationListener(
                  currentUserId: userProvider.firebaseUser?.uid,
                  onTapNotification: (orderId) {
                    if (orderId != null && orderId.isNotEmpty) {
                      showOrderDetailsDialog(orderId);
                    }
                  },
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
