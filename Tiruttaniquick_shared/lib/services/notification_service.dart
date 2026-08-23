import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

  String? get userId => _userId;
  String? get userRole => _userRole;

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
        await requestPermission();

        await _fcm.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // Listen for foreground FCM messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint('[FCM] Foreground message received: ${message.notification?.title}');
          _handleForegroundMessage(message);
        });

        // Listen for notification taps when the app was in the background
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          debugPrint('[FCM] Notification tapped (App in background): ${message.data}');
          _handleNotificationData(message.data);
        });

        // Check if the app was opened from a terminated state via notification tap
        final initialMessage = await _fcm.getInitialMessage();
        if (initialMessage != null) {
          debugPrint('[FCM] Notification tapped (App terminated): ${initialMessage.data}');
          _handleNotificationData(initialMessage.data);
        }

        // Listen for FCM token refreshes
        _fcm.onTokenRefresh.listen((newToken) {
          debugPrint('[FCM] Token refreshed: ${newToken.substring(0, newToken.length > 8 ? 8 : newToken.length)}...');
          if (_userId != null) {
            _saveTokenToFirestore(_userId!, newToken);
          }
        });

        _isInitialized = true;
      } catch (e, stack) {
        debugPrint('[FCM] Setup non-fatal error: $e\n$stack');
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

    if (_onTapCallback != null) {
      _onTapCallback!(data);
    } else {
      _pendingPayload = data;
    }
  }

  /// Setup user identification and sync active FCM token to Firestore
  Future<void> setupUser(String uid, String role) async {
    _userId = uid;
    _userRole = role;

    try {
      final token = await getFCMToken();
      if (token != null && token.isNotEmpty) {
        await _saveTokenToFirestore(uid, token);
      }
    } catch (e) {
      debugPrint('[FCM] Error setting up user token: $e');
    }
  }

  /// Request notifications permission (Android 13+ / iOS)
  Future<bool> requestPermission() async {
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

      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('[FCM] Error requesting permission: $e');
      return false;
    }
  }

  /// Fetch the active FCM registration token
  Future<String?> getFCMToken() async {
    try {
      return await _fcm.getToken();
    } catch (e) {
      debugPrint('[NotificationService] Error getting FCM token: $e');
      return null;
    }
  }

  /// Legacy token getter alias
  Future<String?> getToken() async {
    return getFCMToken();
  }

  /// Save FCM registration token inside Firestore
  Future<void> _saveTokenToFirestore(String uid, String token) async {
    try {
      // 1. Primary user document token
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. Multi-device subcollection support
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

      if (kDebugMode) {
        final truncated = token.length > 12
            ? '${token.substring(0, 6)}...${token.substring(token.length - 6)}'
            : token;
        debugPrint('FCM token registered: $truncated');
      }

      debugPrint('[NotificationService] FCM Token synced to Firestore for user: $uid');
    } catch (e) {
      debugPrint('[NotificationService] Failed to save FCM token to Firestore: $e');
    }
  }

  /// Logout customer: Clear FCM token and Firestore registration
  Future<void> clearToken(String uid) async {
    final currentToken = await getFCMToken();

    _userId = null;
    _userRole = null;

    try {
      // Remove token from primary user document
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': FieldValue.delete(),
      });

      // Remove device subcollection entry if available
      if (currentToken != null && currentToken.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('fcmTokens')
            .doc(currentToken)
            .delete();
      }

      // Delete the active token on the device instance
      await _fcm.deleteToken();
      debugPrint('[NotificationService] FCM token deleted on logout for user: $uid');
    } catch (e) {
      debugPrint('[NotificationService] Error clearing FCM token on logout: $e');
    }
  }

  /// Configure Android Notification Channels
  Future<void> _createNotificationChannels() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      const ordersChannel = AndroidNotificationChannel(
        'orders_channel',
        'Orders',
        description: 'Notifications regarding your order status updates.',
        importance: Importance.max,
        playSound: true,
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

      // Dedicated loud high-priority channel for Admin New Orders with bundled alert sound (v2 for clean migration)
      const adminNewOrdersChannelV2 = AndroidNotificationChannel(
        'admin_new_orders_v2',
        'New Orders',
        description: 'High-priority audio alerts when a new order is received by the store.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('new_order_alert'),
        enableVibration: true,
      );

      const adminNewOrdersChannelLegacy = AndroidNotificationChannel(
        'admin_new_orders',
        'New Orders Legacy',
        description: 'Legacy channel for new orders.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('new_order_alert'),
        enableVibration: true,
      );

      await androidPlugin.createNotificationChannel(ordersChannel);
      await androidPlugin.createNotificationChannel(promotionsChannel);
      await androidPlugin.createNotificationChannel(adminChannel);
      await androidPlugin.createNotificationChannel(adminNewOrdersChannelLegacy);
      await androidPlugin.createNotificationChannel(adminNewOrdersChannelV2);
    }
  }

  /// Local foreground message alerting handler
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString() ?? 'Tiruttani Quick';
    final body = notification?.body ?? message.data['body']?.toString() ?? '';

    // If new order alert received in foreground, trigger NewOrderAlertManager repeating alert
    if (message.data['type'] == 'new_order') {
      final orderId = message.data['orderId']?.toString() ?? '';
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
    final type = payload['type']?.toString() ?? 'promotion';
    String channelId = 'promotions_channel';
    String channelName = 'Promotions';
    AndroidNotificationSound? soundResource;

    if (type == 'new_order') {
      channelId = 'admin_new_orders_v2';
      channelName = 'New Orders';
      soundResource = const RawResourceAndroidNotificationSound('new_order_alert');
    } else if (type == 'order' || type == 'order_status') {
      channelId = 'orders_channel';
      channelName = 'Orders';
    } else if (type == 'admin') {
      channelId = 'admin_channel';
      channelName = 'Admin Alerts';
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
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
      sound: 'new_order_alert.wav',
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    try {
      final payloadStr = json.encode(payload);
      await _localNotifications.show(
        DateTime.now().millisecond,
        title,
        body,
        details,
        payload: payloadStr,
      );
    } catch (e) {
      debugPrint('[NotificationService] Error showing local notification: $e');
    }
  }
}
