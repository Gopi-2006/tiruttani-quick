import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blinkit_shared/blinkit_shared.dart';
import 'package:blinkit_customer/services/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Hardcore Concurrency & Reentrancy Tests', () {
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final Map<String, String> secureStorageMock = {};

    setUp(() {
      secureStorageMock.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'write':
            // Add a small artificial delay to simulate real secure storage latency
            await Future.delayed(const Duration(milliseconds: 10));
            secureStorageMock[methodCall.arguments['key']] = methodCall.arguments['value'];
            return null;
          case 'read':
            await Future.delayed(const Duration(milliseconds: 5));
            return secureStorageMock[methodCall.arguments['key']];
          case 'delete':
            secureStorageMock.remove(methodCall.arguments['key']);
            return null;
          case 'containsKey':
            return secureStorageMock.containsKey(methodCall.arguments['key']);
          case 'deleteAll':
            secureStorageMock.clear();
            return null;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('Stress test concurrent SettingsProvider settings changes', () async {
      final provider = SettingsProvider();
      await provider.init();

      // Launch multiple concurrent operations on SettingsProvider
      final futures = <Future<void>>[];
      for (int i = 0; i < 50; i++) {
        final lang = i % 2 == 0 ? 'ta' : 'en';
        final theme = i % 2 == 0 ? ThemeMode.dark : ThemeMode.light;
        futures.add(provider.setLanguageCode(lang));
        futures.add(provider.setThemeMode(theme));
      }

      await Future.wait(futures);

      // Verify final states correspond to last writes and no deadlocks or errors occurred
      expect(provider.languageCode, isNotNull);
      expect(provider.themeMode, isNotNull);
      expect(secureStorageMock['language_code'], provider.languageCode);
      expect(secureStorageMock['theme_mode'], provider.themeMode == ThemeMode.dark ? 'dark' : 'light');
    });
  });

  group('Hardcore Robustness & Fault Tolerance Tests', () {
    test('ProductModel handling of extreme/bad mathematical values', () {
      final dataNaN = {
        'sellingPrice': double.nan,
        'mrp': double.infinity,
        'stockQuantity': -9999, // negative stock
        'lowStockThreshold': 999999, // massive threshold
      };

      final product = ProductModel.fromFirestore('prod_extreme', dataNaN);

      expect(product.price.isNaN, isTrue);
      expect(product.mrp, double.infinity);
      expect(product.stockQuantity, -9999);
      expect(product.isOutOfStock, true); // stock <= 0
      expect(product.isLowStock, false); // should not trigger low stock if out of stock
    });

    test('OrderModel robust decoding of corrupted database datatypes', () {
      final corruptData = {
        'orderNumber': 12345, // Int instead of String
        'subtotal': '25.50', // String instead of num/double
        'deliveryFee': 'abc', // Corrupt string representation
        'totalPrice': null,
        'placedAt': '2026-06-28T14:30:00Z', // String instead of Timestamp
        'status': 42, // Int instead of status String
      };

      // Ensure this does not crash the app, but falls back safely
      final order = OrderModel.fromFirestore('order_corrupt', corruptData);

      expect(order.id, 'order_corrupt');
      expect(order.orderNumber, '12345'); // parsed int to string successfully
      expect(order.subtotal, 25.5); // parsed string to double successfully
      expect(order.deliveryFee, 0.0); // fails parsing, falls back to 0.0
      expect(order.totalPrice, 0.0);
      expect(order.status, '42'); // parsed int to string successfully
      expect(order.placedAt, isNull); // String date is rejected, falls back to null instead of crashing
      expect(order.formattedPlacedAt, '');
    });
  });

  group('Hardcore Resource Disposal / Leak Detection Tests', () {
    testWidgets('NotificationPopupCard disposes cleanly and cancels timers on dismiss', (WidgetTester tester) async {
      bool dismissedCalled = false;
      bool showCard = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                if (!showCard) return const SizedBox();
                return Stack(
                  children: [
                    NotificationPopupCard(
                      title: 'Disposal Test',
                      body: 'Testing clean disposal of resources.',
                      onTap: () {},
                      onDismissed: () {
                        dismissedCalled = true;
                        setState(() {
                          showCard = false;
                        });
                      },
                      duration: const Duration(seconds: 10),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Wait for slide-in animation to complete
      await tester.pumpAndSettle();

      // Tap on close button to dismiss immediately
      await tester.tap(find.byIcon(Icons.close_rounded));
      // Wait for slide-out animation to complete and widget state update to resolve
      await tester.pumpAndSettle();

      // Ensure the widget is no longer in the tree
      expect(find.byType(NotificationPopupCard), findsNothing);
      expect(dismissedCalled, isTrue);

      // Verify no remaining active timers or transient frames
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
