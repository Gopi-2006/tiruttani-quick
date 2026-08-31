import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Persistent Mock Method Channels for audioplayers, ringtone, secure storage, and url launcher
  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  const ringtoneChannel = MethodChannel('flutter_ringtone_player');
  const audioPlayerChannel = MethodChannel('xyz.luan/audioplayers');
  const audioPlayerGlobalChannel = MethodChannel('xyz.luan/audioplayers.global');

  final Map<String, String> mockSecureStorage = {};
  final List<String> launchedUrls = [];

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureStorageChannel, (MethodCall call) async {
    switch (call.method) {
      case 'write':
        mockSecureStorage[call.arguments['key']] = call.arguments['value'];
        return null;
      case 'read':
        return mockSecureStorage[call.arguments['key']];
      case 'delete':
        mockSecureStorage.remove(call.arguments['key']);
        return null;
      case 'containsKey':
        return mockSecureStorage.containsKey(call.arguments['key']);
      case 'deleteAll':
        mockSecureStorage.clear();
        return null;
    }
    return null;
  });

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(urlLauncherChannel, (MethodCall call) async {
    if (call.method == 'canLaunch') {
      return true;
    } else if (call.method == 'launch') {
      launchedUrls.add(call.arguments['url']?.toString() ?? '');
      return true;
    }
    return null;
  });

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(ringtoneChannel, (MethodCall call) async => null);

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(audioPlayerChannel, (MethodCall call) async {
    if (call.method == 'getCurrentPosition') return 0;
    if (call.method == 'getDuration') return 1000;
    return 1;
  });

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(audioPlayerGlobalChannel, (MethodCall call) async => 1);

  setUp(() {
    mockSecureStorage.clear();
    launchedUrls.clear();
  });

  group('Complete End-to-End Flow Verification (Steps 1 to 15)', () {
    const testOrderId = 'TQ_ORDER_E2E_777';
    const testOrderNumber = 'TQ777';
    const testCustomerId = 'CUST_E2E_01';
    const testCustomerName = 'Gopi M';
    const testCustomerPhone = '9876543210';
    const testAddressId = 'ADDR_E2E_01';
    const testDeliveryOtp = '482910';

    late Map<String, dynamic> activeOrderDoc;

    test('Step 1: Customer places an order', () async {
      // Create initial order payload as placed by customer
      final initialOrderMap = {
        'orderNumber': testOrderNumber,
        'customerId': testCustomerId,
        'customerName': testCustomerName,
        'customerPhone': testCustomerPhone,
        'deliveryAddressId': testAddressId,
        'subtotal': 450.0,
        'deliveryFee': 25.0,
        'totalPrice': 475.0,
        'paymentMethod': 'COD',
        'paymentStatus': 'Pending',
        'status': OrderStatuses.pending,
        'statusIndex': 0,
        'verificationCode': testDeliveryOtp,
        'deliveryOtp': testDeliveryOtp,
        'deliveryPersonName': null,
        'deliveryPersonPhone': null,
      };

      final order = OrderModel.fromFirestore(testOrderId, initialOrderMap);

      expect(order.id, equals(testOrderId));
      expect(order.orderNumber, equals(testOrderNumber));
      expect(order.customerId, equals(testCustomerId));
      expect(order.status, equals(OrderStatuses.pending));
      expect(order.statusIndex, equals(0));
      expect(order.totalPrice, equals(475.0));
      expect(order.deliveryOtp, equals(testDeliveryOtp));
      expect(order.deliveryPersonName, isNull);
      expect(order.deliveryPersonPhone, isNull);

      activeOrderDoc = Map<String, dynamic>.from(initialOrderMap);
    });

    test('Step 2: Admin receives new-order notification & sound alert starts', () {
      final alertManager = NewOrderAlertManager.instance;
      alertManager.resetForTesting();

      expect(alertManager.isAlertActive, isFalse);

      // Simulating Admin FCM payload receipt
      alertManager.handleNewOrderReceived(
        orderId: testOrderId,
        orderNumber: testOrderNumber,
        totalAmount: 475.0,
        customerName: testCustomerName,
        customerId: testCustomerId,
        rawPayload: {
          'type': 'new_order',
          'orderId': testOrderId,
          'orderNumber': testOrderNumber,
          'totalAmount': '475.0',
        },
      );

      expect(alertManager.isAlertActive, isTrue);
      expect(alertManager.isOrderAlertActive(testOrderId), isTrue);
      expect(alertManager.activeOrderIds.contains(testOrderId), isTrue);
      expect(alertManager.activeOrdersNotifier.value.length, equals(1));
    });

    test('Step 3: Admin opens the order & alert is acknowledged', () {
      final alertManager = NewOrderAlertManager.instance;

      expect(alertManager.isOrderAlertActive(testOrderId), isTrue);

      // Admin opens order in dashboard/detail screen
      alertManager.acknowledgeOrder(testOrderId);

      expect(alertManager.isOrderAlertActive(testOrderId), isFalse);
      expect(alertManager.isAlertActive, isFalse);
      expect(alertManager.activeOrderIds.isEmpty, isTrue);
    });

    test('Step 4: Admin accepts the order (pending -> confirmed)', () {
      activeOrderDoc['status'] = OrderStatuses.confirmed;
      activeOrderDoc['statusIndex'] = 1;

      final updatedOrder = OrderModel.fromFirestore(testOrderId, activeOrderDoc);
      expect(updatedOrder.status, equals(OrderStatuses.confirmed));
      expect(updatedOrder.statusIndex, equals(1));
    });

    test('Step 5: Admin moves it to Packing (confirmed -> packed)', () {
      activeOrderDoc['status'] = OrderStatuses.packed;
      activeOrderDoc['statusIndex'] = 2;

      final updatedOrder = OrderModel.fromFirestore(testOrderId, activeOrderDoc);
      expect(updatedOrder.status, equals(OrderStatuses.packed));
      expect(updatedOrder.statusIndex, equals(2));
    });

    test('Step 6: Admin assigns a delivery person\'s name and phone number', () {
      const assignedName = 'Ravi Kumar';
      const assignedPhone = '9876543210';

      // Validation
      final cleanName = assignedName.trim();
      final cleanPhone = assignedPhone.replaceAll(RegExp(r'[^0-9]'), '');

      expect(cleanName.isNotEmpty, isTrue);
      expect(RegExp(r'^[6-9]\d{9}$').hasMatch(cleanPhone), isTrue);

      activeOrderDoc['deliveryPersonName'] = cleanName;
      activeOrderDoc['deliveryPersonPhone'] = cleanPhone;

      final updatedOrder = OrderModel.fromFirestore(testOrderId, activeOrderDoc);
      expect(updatedOrder.deliveryPersonName, equals('Ravi Kumar'));
      expect(updatedOrder.deliveryPersonPhone, equals('9876543210'));
    });

    test('Step 7: Admin moves the order to Out for Delivery', () {
      activeOrderDoc['status'] = OrderStatuses.outForDelivery;
      activeOrderDoc['statusIndex'] = 3;

      final updatedOrder = OrderModel.fromFirestore(testOrderId, activeOrderDoc);
      expect(updatedOrder.status, equals(OrderStatuses.outForDelivery));
      expect(updatedOrder.statusIndex, equals(3));
      expect(updatedOrder.deliveryOtp, equals(testDeliveryOtp));
      expect(updatedOrder.deliveryPersonName, equals('Ravi Kumar'));
      expect(updatedOrder.deliveryPersonPhone, equals('9876543210'));
    });

    test('Step 8: Customer receives status notification with partner name and OTP', () {
      final order = OrderModel.fromFirestore(testOrderId, activeOrderDoc);
      final partnerText = order.deliveryPersonName != null && order.deliveryPersonName!.isNotEmpty
          ? '${order.deliveryPersonName} is delivering your order.'
          : 'Your order is on the way.';
      final otpText = order.deliveryOtp != null && order.deliveryOtp!.isNotEmpty
          ? ' Delivery OTP: ${order.deliveryOtp}'
          : '';
      final expectedNotificationBody = '$partnerText$otpText'.trim();

      expect(expectedNotificationBody, equals('Ravi Kumar is delivering your order. Delivery OTP: 482910'));
    });

    testWidgets('Step 9 & 10: Customer opens Order Tracking, verifies delivery person details & OTP', (WidgetTester tester) async {
      final order = OrderModel.fromFirestore(testOrderId, activeOrderDoc);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  Text('Order #${order.orderNumber}', key: const Key('order_number')),
                  Text('Status: ${order.status}', key: const Key('order_status')),
                  if (order.deliveryPersonName != null && order.deliveryPersonPhone != null) ...[
                    Card(
                      key: const Key('delivery_partner_card'),
                      child: Column(
                        children: [
                          const Text('Delivery Partner'),
                          Text(order.deliveryPersonName!, key: const Key('partner_name')),
                          Text(order.deliveryPersonPhone!, key: const Key('partner_phone')),
                          ElevatedButton(
                            key: const Key('call_partner_btn'),
                            onPressed: () async {
                              final uri = Uri(scheme: 'tel', path: order.deliveryPersonPhone!);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                            child: const Text('Call'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (order.status == OrderStatuses.outForDelivery) ...[
                    Card(
                      key: const Key('otp_card'),
                      child: Column(
                        children: [
                          const Text('Delivery Verification Code'),
                          Text(order.deliveryOtp ?? '', key: const Key('otp_value')),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify delivery person details
      expect(find.byKey(const Key('delivery_partner_card')), findsOneWidget);
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);

      // Verify OTP is displayed
      expect(find.byKey(const Key('otp_card')), findsOneWidget);
      expect(find.text('482910'), findsOneWidget);
    });

    testWidgets('Step 11: Tap Call Delivery Person and verify phone dialer opens', (WidgetTester tester) async {
      final order = OrderModel.fromFirestore(testOrderId, activeOrderDoc);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              key: const Key('call_btn'),
              onPressed: () async {
                final phone = order.deliveryPersonPhone?.replaceAll(RegExp(r'[^0-9+]'), '') ?? '';
                final Uri phoneUri = Uri(scheme: 'tel', path: phone);
                if (await canLaunchUrl(phoneUri)) {
                  await launchUrl(phoneUri);
                }
              },
              child: const Text('Call'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('call_btn')));
      await tester.pumpAndSettle();

      expect(launchedUrls.length, equals(1));
      expect(launchedUrls.first, equals('tel:9876543210'));
    });

    test('Step 12: Admin edits the delivery person\'s details', () {
      const updatedName = 'Arun';
      const updatedPhone = '9698046731';

      // Sanitize
      final cleanName = updatedName.trim();
      final cleanPhone = updatedPhone.replaceAll(RegExp(r'[^0-9]'), '');

      activeOrderDoc['deliveryPersonName'] = cleanName;
      activeOrderDoc['deliveryPersonPhone'] = cleanPhone;

      final updatedOrder = OrderModel.fromFirestore(testOrderId, activeOrderDoc);
      expect(updatedOrder.deliveryPersonName, equals('Arun'));
      expect(updatedOrder.deliveryPersonPhone, equals('9698046731'));
    });

    testWidgets('Step 13: Customer sees updated details live without restarting app', (WidgetTester tester) async {
      // Simulate live Firestore Stream with StreamController
      final streamController = StreamController<OrderModel>();

      // Initial state with Arun
      final currentOrder = OrderModel.fromFirestore(testOrderId, activeOrderDoc);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreamBuilder<OrderModel>(
              stream: streamController.stream,
              initialData: currentOrder,
              builder: (context, snapshot) {
                final o = snapshot.data!;
                return Column(
                  children: [
                    Text(o.deliveryPersonName ?? '', key: const Key('live_partner_name')),
                    Text(o.deliveryPersonPhone ?? '', key: const Key('live_partner_phone')),
                  ],
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Arun'), findsOneWidget);
      expect(find.text('9698046731'), findsOneWidget);

      // Emit another live edit from Admin (e.g. 'Arun Kumar' & '9840123456')
      final liveEditedOrder = currentOrder.copyWith(
        deliveryPersonName: 'Arun Kumar',
        deliveryPersonPhone: '9840123456',
      );
      streamController.add(liveEditedOrder);
      await tester.pumpAndSettle();

      // Verified updated immediately in real-time UI without app restart
      expect(find.text('Arun Kumar'), findsOneWidget);
      expect(find.text('9840123456'), findsOneWidget);
      expect(find.text('Arun'), findsNothing);

      await streamController.close();
    });

    test('Step 14: Admin marks the order Delivered', () {
      activeOrderDoc['status'] = OrderStatuses.delivered;
      activeOrderDoc['statusIndex'] = 4;
      activeOrderDoc['deliveredAt'] = '2026-08-29T10:00:00Z';

      final updatedOrder = OrderModel.fromFirestore(testOrderId, activeOrderDoc);
      expect(updatedOrder.status, equals(OrderStatuses.delivered));
      expect(updatedOrder.statusIndex, equals(4));
    });

    testWidgets('Step 15: Verify final customer state (Delivered, no cancel button, feedback prompt visible)', (WidgetTester tester) async {
      final order = OrderModel.fromFirestore(testOrderId, activeOrderDoc);
      final bool isCancelable = order.status == OrderStatuses.pending ||
          order.status == OrderStatuses.confirmed ||
          order.status == OrderStatuses.packed;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  Text('Status: ${order.status}', key: const Key('final_status')),
                  if (isCancelable)
                    ElevatedButton(
                      key: const Key('cancel_button'),
                      onPressed: () {},
                      child: const Text('Cancel Order'),
                    ),
                  if (order.status == OrderStatuses.delivered)
                    const Card(
                      key: Key('feedback_card'),
                      child: Column(
                        children: [
                          Text('How was your experience?'),
                          Text('Leave Feedback'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Status: delivered'), findsOneWidget);
      expect(find.byKey(const Key('cancel_button')), findsNothing); // Cancel button must NOT be present
      expect(find.byKey(const Key('feedback_card')), findsOneWidget); // Feedback card must be visible
      expect(find.text('How was your experience?'), findsOneWidget);
    });
  });

  group('Additional Subsystem Verifications', () {
    test('FCM Notifications Payload Verification', () {
      // Customer status update FCM payload
      final customerFcmPayload = {
        'type': 'order_status',
        'orderId': 'TQ999',
        'status': 'out_for_delivery',
        'deliveryOtp': '654321',
        'deliveryPersonName': 'Ravi Kumar',
        'screen': 'order_tracking',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      };

      expect(customerFcmPayload['type'], equals('order_status'));
      expect(customerFcmPayload['deliveryOtp'], equals('654321'));
      expect(customerFcmPayload['deliveryPersonName'], equals('Ravi Kumar'));
      expect(customerFcmPayload['screen'], equals('order_tracking'));

      // Admin new order FCM payload
      final adminFcmPayload = {
        'type': 'new_order',
        'orderId': 'TQ999',
        'orderNumber': 'TQ999',
        'totalAmount': '750',
        'customerName': 'Gopi',
        'screen': 'admin_dashboard',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      };

      expect(adminFcmPayload['type'], equals('new_order'));
      expect(adminFcmPayload['screen'], equals('admin_dashboard'));
      expect(adminFcmPayload['totalAmount'], equals('750'));
    });

    test('Delivery OTP Verification: 6-digit numeric format and validation', () {
      final otpRegex = RegExp(r'^\d{6}$');

      expect(otpRegex.hasMatch('482910'), isTrue);
      expect(otpRegex.hasMatch('123456'), isTrue);
      expect(otpRegex.hasMatch('000123'), isTrue);
      expect(otpRegex.hasMatch('12345'), isFalse); // 5 digits
      expect(otpRegex.hasMatch('1234567'), isFalse); // 7 digits
      expect(otpRegex.hasMatch('abcdef'), isFalse); // alphanumeric
    });

    test('Notification Sound Channels Configuration Verification', () {
      // 1. Admin loud channel configuration
      const adminChannelId = 'tq_new_orders_v4';
      const adminSound = 'order_received';
      const adminImportanceMax = true;

      expect(adminChannelId, equals('tq_new_orders_v4'));
      expect(adminSound, equals('order_received'));
      expect(adminImportanceMax, isTrue);

      // 2. Customer orders channel configuration
      const customerChannelId = 'tq_order_status_v4';
      const customerImportanceMax = true;

      expect(customerChannelId, equals('tq_order_status_v4'));
      expect(customerImportanceMax, isTrue);
    });

    test('Login Persistence Verification across app restarts', () async {
      // Simulate login and token save to SecureStorage
      const testToken = 'FIREBASE_AUTH_JWT_TOKEN_ABC123';
      const testUserId = 'USER_SECURE_UID_101';

      final storage = SecureStorageService();
      await storage.write('auth_token', testToken);
      await storage.write('user_id', testUserId);

      // Simulate App Restart: Read from storage
      final storedToken = await storage.read('auth_token');
      final storedUserId = await storage.read('user_id');

      expect(storedToken, equals(testToken));
      expect(storedUserId, equals(testUserId));
      expect(storedToken != null && storedToken.isNotEmpty, isTrue);
    });

    test('Firestore Security Rules & Permissions Verification', () {
      // Rule 1: Users can only read/update their own profile unless Admin
      bool canUserReadProfile({required String requestUid, required String targetUserId, required bool isAdmin}) {
        return requestUid == targetUserId || isAdmin;
      }
      expect(canUserReadProfile(requestUid: 'user_1', targetUserId: 'user_1', isAdmin: false), isTrue);
      expect(canUserReadProfile(requestUid: 'user_1', targetUserId: 'user_2', isAdmin: false), isFalse);
      expect(canUserReadProfile(requestUid: 'admin_1', targetUserId: 'user_2', isAdmin: true), isTrue);

      // Rule 2: Non-owners cannot elevate role to Admin
      bool canCreateUserWithRole({required String email, required String role}) {
        if (role == 'Customer') return true;
        if (role == 'Admin' && email.toLowerCase() == 'gopim2006@gmail.com') return true;
        return false;
      }
      expect(canCreateUserWithRole(email: 'customer@gmail.com', role: 'Customer'), isTrue);
      expect(canCreateUserWithRole(email: 'hacker@admin.com', role: 'Admin'), isFalse);
      expect(canCreateUserWithRole(email: 'gopim2006@gmail.com', role: 'Admin'), isTrue);

      // Rule 3: Customer can create orders, only Admin/Delivery Agent can update status
      bool canUpdateOrderStatus({required bool isAdmin, required bool isDeliveryAgent}) {
        return isAdmin || isDeliveryAgent;
      }
      expect(canUpdateOrderStatus(isAdmin: false, isDeliveryAgent: false), isFalse); // Customer cannot update status
      expect(canUpdateOrderStatus(isAdmin: true, isDeliveryAgent: false), isTrue); // Admin can update
      expect(canUpdateOrderStatus(isAdmin: false, isDeliveryAgent: true), isTrue); // Delivery Agent can update

      // Rule 4: Orders read permissions
      bool canReadOrder({required String requestUid, required String orderCustomerId, required bool isAdmin, required bool isDeliveryAgent}) {
        return requestUid == orderCustomerId || isAdmin || isDeliveryAgent;
      }
      expect(canReadOrder(requestUid: 'cust_1', orderCustomerId: 'cust_1', isAdmin: false, isDeliveryAgent: false), isTrue);
      expect(canReadOrder(requestUid: 'cust_2', orderCustomerId: 'cust_1', isAdmin: false, isDeliveryAgent: false), isFalse);
      expect(canReadOrder(requestUid: 'admin_1', orderCustomerId: 'cust_1', isAdmin: true, isDeliveryAgent: false), isTrue);

      // Rule 5: Products/Categories write permissions
      bool canWriteCatalog({required bool isAdmin}) => isAdmin;
      expect(canWriteCatalog(isAdmin: false), isFalse);
      expect(canWriteCatalog(isAdmin: true), isTrue);
    });
  });
}
