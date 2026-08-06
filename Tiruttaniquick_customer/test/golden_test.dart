import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

void main() {
  group('NotificationPopupCard Golden Tests', () {
    testWidgets('NotificationPopupCard renders correctly with status info', (WidgetTester tester) async {
      // Set logical window size (400x300) to focus closely on the popup card
      tester.view.physicalSize = const Size(800, 600); // 400x300 at ratio 2.0
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.grey[200],
            body: Stack(
              children: [
                NotificationPopupCard(
                  title: 'Order Status Update',
                  body: 'Your order #98765 is out for delivery. Our partner is on their way.',
                  onTap: () {},
                  onDismissed: () {},
                  duration: const Duration(seconds: 10),
                ),
              ],
            ),
          ),
        ),
      );

      // Wait for the slide and fade transitions to finish
      await tester.pumpAndSettle();

      // Assert basic structural layout first to be robust
      expect(find.text('Order Status Update'), findsOneWidget);
      expect(find.textContaining('out for delivery'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Match visual layout
      await expectLater(
        find.byType(NotificationPopupCard),
        matchesGoldenFile('goldens/notification_popup_card.png'),
      );

      // Clean up the auto-dismiss timer to prevent "A Timer is still pending" error
      await tester.pump(const Duration(seconds: 11));
    });
  });
}
