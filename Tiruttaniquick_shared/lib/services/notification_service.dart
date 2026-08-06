import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  String? _userId;
  String? _userRole;
  Function(Map<String, dynamic> payload)? _onTapCallback;

  String? get userId => _userId;
  String? get userRole => _userRole;

  // Initialize notifications setup
  Future<void> initialize({
    required Function(Map<String, dynamic> payload) onNotificationTap,
  }) async {
    _onTapCallback = onNotificationTap;

    // Local notifications initialization settings
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
        if (payloadStr != null && _onTapCallback != null) {
          try {
            final Map<String, dynamic> payload = json.decode(payloadStr) as Map<String, dynamic>;
            _onTapCallback!(payload);
          } catch (e) {
            debugPrint('Error parsing notification response payload: $e');
          }
        }
      },
    );

    // Create the required notification channels for Android
    await _createNotificationChannels();

    // Set foreground notification options (disable default banners to prevent duplicates with local notifications)
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: true,
    );

    // Handle messages when app is in the foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground message received: ${message.notification?.title}');
      _handleForegroundMessage(message);
    });

    // Handle notification clicks when the app is in the background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification clicked (App in background): ${message.data}');
      if (_onTapCallback != null) {
        _onTapCallback!(message.data);
      }
    });

    // Check if the app was opened from a terminated state via a notification click
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('Notification clicked (App terminated): ${initialMessage.data}');
      if (_onTapCallback != null) {
        _onTapCallback!(initialMessage.data);
      }
    }

    // Auto update user's FCM token when it is refreshed by Firebase
    _fcm.onTokenRefresh.listen((token) async {
      debugPrint('FCM Token refreshed: $token');
      if (_userId != null) {
        await _saveTokenToFirestore(_userId!, token);
      }
    });

    // Request permissions during initialization
    await requestPermission();
  }

  // Set up user profile mapping to auto refresh tokens
  Future<void> setupUser(String uid, String role) async {
    _userId = uid;
    _userRole = role;

    final hasPermission = await requestPermission();
    if (hasPermission) {
      final token = await getFCMToken();
      if (token != null) {
        await _saveTokenToFirestore(uid, token);
      }
    }
  }

  // Request notifications permissions
  Future<bool> requestPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  // Fetch the active FCM token using correct name
  Future<String?> getFCMToken() async {
    try {
      return await _fcm.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  // Legacy/Alternative token getter for backward compatibility
  Future<String?> getToken() async {
    return getFCMToken();
  }

  // Save fcmToken inside firestore
  Future<void> _saveTokenToFirestore(String uid, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': token,
      });
      debugPrint('FCM Token updated successfully for user: $uid');
    } catch (e) {
      // Fallback: If update fails (e.g. document does not exist yet), set with merge
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'uid': uid,
          'fcmToken': token,
        }, SetOptions(merge: true));
        debugPrint('FCM Token saved successfully (set merge) for user: $uid');
      } catch (innerError) {
        debugPrint('Failed to save FCM token to Firestore: $innerError');
      }
    }
  }

  // Delete FCM token from user's record on logout
  Future<void> clearToken(String uid) async {
    _userId = null;
    _userRole = null;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': FieldValue.delete(),
      });
      debugPrint('FCM Token removed from Firestore for user: $uid');
    } catch (e) {
      debugPrint('Failed to remove FCM token from Firestore: $e');
    }
  }

  // Configure Android Notification Channels
  Future<void> _createNotificationChannels() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // 1. Orders Channel
      const ordersChannel = AndroidNotificationChannel(
        'orders_channel',
        'Orders',
        description: 'Notifications regarding your order status updates.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      // 2. Promotions Channel
      const promotionsChannel = AndroidNotificationChannel(
        'promotions_channel',
        'Promotions',
        description: 'Special offers, campaigns, and discounts.',
        importance: Importance.defaultImportance,
        playSound: true,
      );

      // 3. Admin Channel
      const adminChannel = AndroidNotificationChannel(
        'admin_channel',
        'Admin Alerts',
        description: 'Alerts for new orders, registrations, and low stock.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await androidPlugin.createNotificationChannel(ordersChannel);
      await androidPlugin.createNotificationChannel(promotionsChannel);
      await androidPlugin.createNotificationChannel(adminChannel);
    }
  }

  // Local foreground message alerting handler
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      showLocalNotification(
        title: notification.title ?? 'Blinkit Alert',
        body: notification.body ?? '',
        payload: message.data,
      );
    }
  }

  // Display a local banner notification
  Future<void> showLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
  }) async {
    final type = payload['type'] ?? 'promotion';
    String channelId = 'promotions_channel';
    String channelName = 'Promotions';

    if (type == 'order') {
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
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
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
      debugPrint('Error showing local notification: $e');
    }
  }
}
