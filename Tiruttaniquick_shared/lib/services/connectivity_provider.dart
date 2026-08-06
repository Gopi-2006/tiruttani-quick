import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum NetworkType {
  wifi,
  mobile,
  none,
}

class ConnectivityProvider extends ChangeNotifier {
  static final ConnectivityProvider instance = ConnectivityProvider._internal();
  
  ConnectivityProvider._internal() {
    _startMonitoring();
  }

  bool _isOnline = true;
  bool _isFirstCheck = true;
  NetworkType _networkType = NetworkType.wifi;
  Timer? _timer;
  bool _checking = false;

  bool get isOnline => _isOnline;
  NetworkType get networkType => _networkType;

  final StreamController<bool> _statusController = StreamController<bool>.broadcast();
  Stream<bool> get onConnectivityChanged => _statusController.stream;

  void _startMonitoring() {
    _checkConnection();
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => _checkConnection());
  }

  Future<void> _checkConnection() async {
    if (kIsWeb) {
      _updateStatus(true, NetworkType.wifi);
      return;
    }
    if (_checking) return;
    _checking = true;

    try {
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      final online = result.isNotEmpty && result[0].rawAddress.isNotEmpty;

      if (online) {
        final netType = await _detectNetworkType();
        _updateStatus(true, netType);
      } else {
        _updateStatus(false, NetworkType.none);
      }
    } catch (_) {
      _updateStatus(false, NetworkType.none);
    } finally {
      _checking = false;
    }
  }

  Future<NetworkType> _detectNetworkType() async {
    try {
      final interfaces = await NetworkInterface.list();
      if (interfaces.isEmpty) return NetworkType.none;
      
      bool hasWifi = false;
      bool hasMobile = false;

      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.contains('wlan') || name.contains('wifi') || name.contains('eth') || name.contains('en')) {
          hasWifi = true;
        } else if (name.contains('rmnet') || name.contains('pdp') || name.contains('cellular') || name.contains('mobile') || name.contains('lte') || name.contains('ccmni')) {
          hasMobile = true;
        }
      }

      if (hasWifi) return NetworkType.wifi;
      if (hasMobile) return NetworkType.mobile;
      return NetworkType.wifi; // Default to wifi if online but interface matches aren't clean
    } catch (_) {
      return NetworkType.wifi;
    }
  }

  void _updateStatus(bool online, NetworkType netType) {
    if (_isFirstCheck) {
      _isOnline = online;
      _networkType = netType;
      _isFirstCheck = false;
      
      // Seed Firestore network configuration on startup
      if (!_isOnline) {
        try {
          FirebaseFirestore.instance.disableNetwork();
        } catch (_) {}
        _statusController.add(_isOnline);
        notifyListeners();
      }
      return;
    }

    if (online != _isOnline || netType != _networkType) {
      _isOnline = online;
      _networkType = netType;

      try {
        if (_isOnline) {
          FirebaseFirestore.instance.enableNetwork();
        } else {
          FirebaseFirestore.instance.disableNetwork();
        }
      } catch (_) {}

      _statusController.add(_isOnline);
      notifyListeners();
    }
  }

  Future<bool> forceCheck() async {
    await _checkConnection();
    return _isOnline;
  }

  void disposeProvider() {
    _timer?.cancel();
    _statusController.close();
  }
}
