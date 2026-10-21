import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/constants/order_status.dart';
import 'new_order_alert_manager.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  FirebaseMessaging get _fcm => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  String? _userId;
  String? _userRole;
  Function(Map<String, dynamic> payload)? _onTapCallback;
  Map<String, dynamic>? _pendingPayload;
  bool _isInitialized = false;

  final Map<String, DateTime> _recentlyHandledEvents = {};

  String? get userId => _userId;
  String? get userRole => _userRole;

  @visibleForTesting
  void resetRecentEventsForTesting() => _recentlyHandledEvents.clear();

  @visibleForTesting
  bool isEventRecentlyHandled(String eventId) => _recentlyHandledEvents.containsKey(eventId);

  /// Initialize notifications setup: Firebase Cloud Messaging, Local Notifications, and Channels
  Future<void> initialize({
    required Function(Map<String, dynamic> payload) onNotificationTap,
  }) async {
    _onTapCallback = onNotificationTap;

    // 1. Local notifications initialization settings for foreground alerts and fallback
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payloadStr = response.payload;
        if (payloadStr != null && payloadStr.isNotEmpty) {
          try {
            final Map<String, dynamic> payload = json.decode(payloadStr) as Map<String, dynamic>;
            _handleNotificationData(payload);
            return;
          } catch (e) {
            debugPrint('[NotificationService] Error parsing notification response payload: $e');
          }
        }
        _handleNotificationData({});
      },
    );

    // 2. Create the required notification channels for Android
    await _createNotificationChannels();

    // 3. Firebase Messaging Setup
    if (!_isInitialized) {
      try {
        debugPrint('[FCM DIAGNOSTICS] FCM initialization started');
        final hasPermission = await requestPermission();
        debugPrint('[FCM DIAGNOSTICS] Notification permission granted: $hasPermission');

        await _fcm.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // Listen for foreground FCM messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint('[FCM DIAGNOSTICS] CUSTOMER FCM onMessage RECEIVED: title=${message.notification?.title}, data=${message.data}');
          _handleForegroundMessage(message);
        });

        // Listen for notification taps when the app was in the background
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          debugPrint('[FCM DIAGNOSTICS] Notification tapped (App in background): ${message.data}');
          _handleNotificationData(message.data);
        });

        // Check if the app was opened from a terminated state via notification tap
        final initialMessage = await _fcm.getInitialMessage();
        if (initialMessage != null) {
          debugPrint('[FCM DIAGNOSTICS] Notification tapped (App terminated): ${initialMessage.data}');
          _handleNotificationData(initialMessage.data);
        }

        // Enable auto-init for Firebase Messaging
        await _fcm.setAutoInitEnabled(true);

        // Listen for FCM token refreshes
        _fcm.onTokenRefresh.listen((newToken) {
          final truncated = newToken.length > 8 ? '...${newToken.substring(newToken.length - 8)}' : newToken;
          debugPrint('[FCM DIAGNOSTICS] onTokenRefresh fired with new token: $truncated');
          final activeUid = _userId ?? FirebaseAuth.instance.currentUser?.uid;
          if (activeUid != null) {
            _saveTokenToFirestore(activeUid, newToken);
          }
        });

        _isInitialized = true;
        debugPrint('[FCM DIAGNOSTICS] FCM initialization completed successfully');

        // Check if an authenticated user is already present on cold start
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          debugPrint('[FCM DIAGNOSTICS] Authenticated user found on startup: ${currentUser.uid}, running setupUser');
          setupUser(currentUser.uid, _userRole ?? 'customer');
        }
      } catch (e, stack) {
        debugPrint('[FCM DIAGNOSTICS] Setup non-fatal error: $e\n$stack');
      }
    }

    // Flush any pending notification tapped before UI was mounted
    if (_pendingPayload != null && _onTapCallback != null) {
      final payload = _pendingPayload!;
      _pendingPayload = null;
      _onTapCallback!(payload);
    }
  }

  /// Centralized notification payload dispatcher
  void _handleNotificationData(Map<String, dynamic> data) {
    final orderId = data['orderId']?.toString();
    if (orderId != null && orderId.isNotEmpty) {
      // Immediately acknowledge and silence repeating alert for this order
      NewOrderAlertManager.instance.acknowledgeOrder(orderId);
    } else {
      // Immediately silence all active alerts on generic notification tap
      NewOrderAlertManager.instance.acknowledgeAll();
    }

    // Cancel all local notification tray items immediately upon tap
    _localNotifications.cancelAll().catchError((e) {
      debugPrint('[NotificationService] Error cancelling notifications: $e');
    });

    if (_onTapCallback != null) {
      _onTapCallback!(data);
    } else {
      _pendingPayload = data;
    }
  }

  /// Setup user identification and sync active FCM token to Firestore with retry resilience
  Future<void> setupUser(String uid, String role) async {
    _userId = uid;
    _userRole = role;
    debugPrint('[FCM DIAGNOSTICS] setupUser started for uid: $uid (role: $role)');

    // Ensure FCM permission is requested (idempotent — safe to call multiple times)
    if (!_isInitialized) {
      try {
        await requestPermission();
      } catch (_) {}
    }

    // Subscribe to customer topic channels for broadcasts and user-level pushes
    try {
      if (role == 'customer' || role == 'Customer') {
        await _fcm.subscribeToTopic('all_customers');
        await _fcm.subscribeToTopic('user_$uid');
      }
    } catch (e) {
      debugPrint('[FCM DIAGNOSTICS] Topic subscription notice: $e');
    }

    try {
      String? token = await getFCMToken();

      // Retry up to 3 times with increasing delay — handles cold-start race with Play Services
      if (token == null || token.isEmpty) {
        debugPrint('[FCM DIAGNOSTICS] Token null on first attempt, retrying...');
        await Future.delayed(const Duration(milliseconds: 1500));
        token = await getFCMToken();
      }
      if (token == null || token.isEmpty) {
        debugPrint('[FCM DIAGNOSTICS] Token null on second attempt, retrying after 3 seconds...');
        await Future.delayed(const Duration(seconds: 3));
        token = await getFCMToken();
      }

      if (token != null && token.isNotEmpty) {
        await _saveTokenToFirestore(uid, token);
      } else {
        debugPrint('[FCM DIAGNOSTICS] Warning: FCM token could not be obtained for uid: $uid after 3 attempts');
      }
    } catch (e) {
      debugPrint('[FCM DIAGNOSTICS] Error setting up user token: $e');
    }
  }

  /// Request notifications permission (Android 13+ / iOS)
  Future<bool> requestPermission() async {
    debugPrint('[FCM DIAGNOSTICS] Requesting notification permission...');
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      // On Android 13+ (API 33+), also explicitly request the runtime permission via flutter_local_notifications plugin
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
          if (androidPlugin != null) {
            final granted = await androidPlugin.requestNotificationsPermission();
            debugPrint('[FCM DIAGNOSTICS] AndroidLocalNotifications permission granted: $granted');
          }
        } catch (e) {
          debugPrint('[FCM DIAGNOSTICS] Android permission request notice: $e');
        }
      }

      final statusStr = settings.authorizationStatus.toString();
      final isAuthorized = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      debugPrint('[FCM DIAGNOSTICS] FCM permission status: $statusStr (isAuthorized: $isAuthorized)');

      return isAuthorized;
    } catch (e) {
      debugPrint('[FCM DIAGNOSTICS] Error requesting permission: $e');
      return false;
    }
  }

  /// Fetch the active FCM registration token
  Future<String?> getFCMToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        final truncated = token.length > 8 ? '...${token.substring(token.length - 8)}' : token;
        debugPrint('[FCM DIAGNOSTICS] FCM Token retrieved successfully: $truncated');
      } else {
        debugPrint('[FCM DIAGNOSTICS] FCM getToken returned null or empty');
      }
      return token;
    } catch (e) {
      debugPrint('[FCM DIAGNOSTICS] Error getting FCM token: $e');
      return null;
    }
  }

  /// Legacy token getter alias
  Future<String?> getToken() async {
    return getFCMToken();
  }

  /// Save FCM registration token inside Firestore
  Future<void> _saveTokenToFirestore(String uid, String token) async {
    final truncated = token.length > 8 ? '...${token.substring(token.length - 8)}' : token;
    debugPrint('[FCM DIAGNOSTICS] Saving token ($truncated) to Firestore for user: $uid');

    const maxAttempts = 3;
    int attempt = 0;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        // 1. Multi-device subcollection support first (always safe under user's own uid)
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('fcmTokens')
              .doc(token)
              .set({
            'token': token,
            'platform': defaultTargetPlatform.name,
            'lastSeen': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (subErr) {
          debugPrint('[FCM DIAGNOSTICS] Subcollection token save notice: $subErr');
        }

        // 2. Primary user document token fields
        final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);

        try {
          await userDocRef.update({
            'fcmToken': token,
            'fcmTokens': FieldValue.arrayUnion([token]),
            'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          });
          debugPrint('[FCM DIAGNOSTICS] Token updated via update() for user: $uid (attempt $attempt)');
        } on FirebaseException catch (updateErr) {
          debugPrint('[FCM DIAGNOSTICS] User doc update notice: ${updateErr.code}, trying set with merge for uid: $uid');
          final resolvedRole = (_userRole == 'Admin' || _userRole == 'admin') ? 'Admin' : 'Customer';
          await userDocRef.set({
            'uid': uid,
            'role': resolvedRole,
            'fcmToken': token,
            'fcmTokens': FieldValue.arrayUnion([token]),
            'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          debugPrint('[FCM DIAGNOSTICS] Token saved via set(merge) for user: $uid');
        }

        debugPrint('[FCM DIAGNOSTICS] Token registration SUCCESS in Firestore for user: $uid');
        return; // Success — exit retry loop
      } catch (e) {
        debugPrint('[FCM DIAGNOSTICS] Token registration FAILURE (attempt $attempt/$maxAttempts): $e');
        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
    debugPrint('[FCM DIAGNOSTICS] Token registration FAILED after $maxAttempts attempts for user: $uid');
  }

  /// Logout customer: Clear FCM token and Firestore registration
  Future<void> clearToken(String uid) async {
    debugPrint('[FCM DIAGNOSTICS] clearToken called for uid: $uid');
    final currentToken = await getFCMToken();

    _userId = null;
    _userRole = null;

    try {
      final updates = <String, dynamic>{
        'fcmToken': FieldValue.delete(),
      };
      if (currentToken != null && currentToken.isNotEmpty) {
        updates['fcmTokens'] = FieldValue.arrayRemove([currentToken]);
      }

      // Remove token from primary user document
      await FirebaseFirestore.instance.collection('users').doc(uid).update(updates);

      // Remove device subcollection entry if available
      if (currentToken != null && currentToken.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('fcmTokens')
            .doc(currentToken)
            .delete();
      }

      // Unsubscribe from topics
      try {
        await _fcm.unsubscribeFromTopic('all_customers');
        await _fcm.unsubscribeFromTopic('user_$uid');
      } catch (_) {}

      // Delete the active token on the device instance
      await _fcm.deleteToken();
      debugPrint('[FCM DIAGNOSTICS] FCM token deleted on logout for user: $uid');
    } catch (e) {
      debugPrint('[FCM DIAGNOSTICS] Error clearing FCM token on logout: $e');
    }
  }

  /// Configure Android Notification Channels
  Future<void> _createNotificationChannels() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // 1. Customer Order Status Channel (v4)
      const orderStatusChannelV4 = AndroidNotificationChannel(
        'tq_order_status_v4',
        'Order Status Updates',
        description: 'High-priority notifications regarding your order status updates.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      // 2. Admin Loud New Orders Channel (v4)
      const adminNewOrdersChannelV4 = AndroidNotificationChannel(
        'tq_new_orders_v4',
        'New Orders Alert',
        description: 'High-priority audio alerts when a new order is received by the store.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('order_received'),
        enableVibration: true,
      );

      const promotionsChannel = AndroidNotificationChannel(
        'promotions_channel',
        'Promotions',
        description: 'Special offers, campaigns, and discounts.',
        importance: Importance.defaultImportance,
        playSound: true,
      );

      const adminChannel = AndroidNotificationChannel(
        'admin_channel',
        'Admin Alerts',
        description: 'Alerts for general notifications, registrations, and low stock.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await androidPlugin.createNotificationChannel(orderStatusChannelV4);
      await androidPlugin.createNotificationChannel(adminNewOrdersChannelV4);
      await androidPlugin.createNotificationChannel(promotionsChannel);
      await androidPlugin.createNotificationChannel(adminChannel);
    }
  }

  /// Public method to display a notification from a RemoteMessage
  Future<void> showFromRemoteMessage(RemoteMessage message) async {
    _handleForegroundMessage(message);
  }

  /// Deduplicate rapid duplicate FCM triggers for the same event
  bool checkAndRecordEventDeduplication(String? eventId) {
    if (eventId == null || eventId.isEmpty) return false;
    final now = DateTime.now();
    _recentlyHandledEvents.removeWhere((_, time) => now.difference(time).inSeconds > 300);

    if (_recentlyHandledEvents.containsKey(eventId)) {
      debugPrint('[FCM DIAGNOSTICS] Duplicate foreground notification suppressed for eventId: $eventId');
      return true;
    }
    _recentlyHandledEvents[eventId] = now;
    return false;
  }

  /// Calculates deterministic notification ID per order to ensure single card in tray
  static int calculateNotificationId(String? orderId) {
    if (orderId != null && orderId.isNotEmpty) {
      return (orderId.hashCode.abs() % 100000);
    }
    return DateTime.now().millisecond;
  }

  /// Calculates collapse tag per order for Android notification manager
  static String? calculateCollapseTag(String? orderId) {
    if (orderId != null && orderId.isNotEmpty) {
      return 'order_$orderId';
    }
    return null;
  }

  /// Local foreground message alerting handler
  void _handleForegroundMessage(RemoteMessage message) {
    final orderId = message.data['orderId']?.toString() ?? '';
    final status = message.data['status']?.toString() ?? '';
    final messageId = message.messageId;
    final eventId = message.data['eventId']?.toString() ??
        (orderId.isNotEmpty && status.isNotEmpty ? '${orderId}_$status' : messageId);

    // Deduplicate rapid duplicate FCM triggers for the same event in foreground
    if (checkAndRecordEventDeduplication(eventId)) {
      return;
    }

    // On iOS, if message.notification != null, the OS already presents the banner
    // due to setForegroundNotificationPresentationOptions(alert: true).
    // Avoid double presentation on iOS.
    if (defaultTargetPlatform == TargetPlatform.iOS && message.notification != null) {
      debugPrint('[FCM DIAGNOSTICS] iOS foreground alert already presented by system; skipping duplicate local display.');
      return;
    }

    final notification = message.notification;
    var title = notification?.title ?? message.data['title']?.toString() ?? '';
    var body = notification?.body ?? message.data['body']?.toString() ?? '';

    // If body is empty, synthesize based on event type/status to prevent empty notification cards (Bug 2 fix)
    if (body.trim().isEmpty) {
      final type = message.data['type']?.toString();
      final orderNumber = message.data['orderNumber']?.toString() ?? (orderId.isNotEmpty ? orderId : '');
      final partnerName = message.data['deliveryPersonName']?.toString().trim();

      if (type == 'delivery_partner_assigned' || status == 'delivery_partner_assigned') {
        title = 'Delivery Partner Assigned';
        final idPart = orderNumber.isNotEmpty ? ' #$orderNumber' : '';
        body = (partnerName != null && partnerName.isNotEmpty)
            ? '$partnerName has been assigned to deliver your order$idPart.'
            : 'A delivery partner has been assigned to your order$idPart.';
      } else if (type == 'order_status' && status.isNotEmpty) {
        final displayStatus = OrderStatuses.display(status);
        if (title.isEmpty || title == 'Tiruttani Quick') {
          title = 'Order $displayStatus';
        }
        final idPart = orderNumber.isNotEmpty ? ' #$orderNumber' : '';
        body = 'Your Tiruttani Quick order$idPart is $displayStatus.';
      } else if (type == 'new_order') {
        if (title.isEmpty || title == 'Tiruttani Quick') {
          title = 'New Order Received! 🛒';
        }
        final idPart = orderNumber.isNotEmpty ? ' #$orderNumber' : '';
        body = 'New order$idPart received.';
      }
    }

    if (title.trim().isEmpty) {
      title = 'Tiruttani Quick';
    }

    // If body is STILL completely empty after synthesis attempt, suppress displaying empty card
    if (body.trim().isEmpty) {
      debugPrint('[FCM DIAGNOSTICS] Dropping empty foreground notification for orderId: $orderId');
      return;
    }

    // If new order alert received in foreground, trigger NewOrderAlertManager repeating alert
    if (message.data['type'] == 'new_order') {
      if (orderId.isNotEmpty) {
        NewOrderAlertManager.instance.handleNewOrderReceived(
          orderId: orderId,
          orderNumber: message.data['orderNumber']?.toString(),
          totalAmount: double.tryParse(message.data['totalAmount']?.toString() ?? '0'),
          customerName: message.data['customerName']?.toString(),
          customerId: message.data['customerId']?.toString(),
          rawPayload: message.data,
        );
      }
    }

    showLocalNotification(
      title: title,
      body: body,
      payload: message.data,
    );
  }

  /// Display a local banner notification
  Future<void> showLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    final cleanBody = body.trim();
    if (cleanBody.isEmpty) {
      debugPrint('[NotificationService] Suppressing local notification with empty body');
      return;
    }
    final cleanTitle = title.trim().isNotEmpty ? title.trim() : 'Tiruttani Quick';

    final type = payload['type']?.toString() ?? 'promotion';
    final orderId = payload['orderId']?.toString() ?? '';
    String channelId = 'promotions_channel';
    String channelName = 'Promotions';
    AndroidNotificationSound? soundResource;

    if (type == 'new_order') {
      channelId = 'tq_new_orders_v4';
      channelName = 'New Orders Alert';
      soundResource = const RawResourceAndroidNotificationSound('order_received');
    } else if (type == 'order' || type == 'order_status' || type == 'test') {
      channelId = 'tq_order_status_v4';
      channelName = 'Order Status Updates';
    } else if (type == 'admin') {
      channelId = 'admin_channel';
      channelName = 'Admin Alerts';
    }

    // Deterministic notification ID and collapse tag per order to ensure Android OS
    // updates/replaces rather than stacking duplicate notification shade cards
    final int notificationId = calculateNotificationId(orderId);
    final String? collapseTag = calculateCollapseTag(orderId);

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      tag: collapseTag,
      playSound: true,
      sound: soundResource,
      enableVibration: true,
      ongoing: false,
      autoCancel: true,
      audioAttributesUsage: AudioAttributesUsage.notification,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'order_received.mp3',
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    try {
      final payloadStr = json.encode(payload);
      await _localNotifications.show(
        notificationId,
        cleanTitle,
        cleanBody,
        details,
        payload: payloadStr,
      );
      debugPrint('[FCM DIAGNOSTICS] LOCAL NOTIFICATION SHOWN: id=$notificationId tag=$collapseTag');
    } catch (e) {
      debugPrint('[FCM DIAGNOSTICS] Error showing local notification: $e');
    }
  }
}
