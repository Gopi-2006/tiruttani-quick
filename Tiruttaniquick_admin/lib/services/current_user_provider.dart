import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

class CurrentUserProvider extends ChangeNotifier {
  static const String _privacyPolicyKey = 'admin_privacy_policy_version';
  static const String _currentPrivacyVersion = '1.0';

  FirebaseFirestore? get _db {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseAuth? get _auth {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  final SecureStorageService _storage = SecureStorageService();

  User? _firebaseUser;
  UserProfileModel? _profile;
  bool _loading = true;
  StreamSubscription<User?>? _subscription;
  bool privacyPolicyAccepted = false;
  bool _isInitStarted = false;

  /// Completer that resolves once the initial auth state has been fully resolved.
  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get initComplete => _initCompleter.future;

  User? get firebaseUser => _firebaseUser ?? _auth?.currentUser;
  UserProfileModel? get profile => _profile;
  bool get loading => _loading;
  bool get isAuthenticated => (_firebaseUser ?? _auth?.currentUser) != null;
  String get role => _profile?.role ?? 'admin';

  Future<void> init() async {
    if (_isInitStarted) return;
    _isInitStarted = true;

    // Immediately cache current user from Firebase Auth local persistence
    _firebaseUser = _auth?.currentUser;

    // 1. Preload privacy policy state from local storage
    await _loadPrivacyPolicyState();

    // 2. Centralized authStateChanges listener
    final auth = _auth;
    if (auth != null) {
      _subscription = auth.authStateChanges().listen((user) async {
        _firebaseUser = user;
        if (user == null) {
          _profile = null;
          _loading = false;
          if (!_initCompleter.isCompleted) _initCompleter.complete();
          notifyListeners();
          return;
        }

        // User exists in Firebase Auth
        try {
          final stopwatch = AuthPerformanceLogger.start('Load Admin Profile (${user.uid})');
          final db = _db;
          final snapshot = db != null
              ? await db
                  .collection('users')
                  .doc(user.uid)
                  .get()
                  .timeout(const Duration(seconds: 6))
              : null;
          AuthPerformanceLogger.stopAndLog(stopwatch, 'Load Admin Profile');

          if (snapshot != null && snapshot.exists && snapshot.data() != null) {
            _profile = UserProfileModel.fromFirestore(snapshot.id, snapshot.data()!);
          } else {
            _profile = UserProfileModel(
              id: user.uid,
              name: user.displayName ?? 'Admin',
              email: user.email ?? '',
              phone: user.phoneNumber ?? '',
              role: 'admin',
            );
          }

          NotificationService.instance.setupUser(user.uid, _profile?.role ?? 'admin');
        } catch (e) {
          debugPrint('[CurrentUserProvider Admin] Non-fatal error loading profile: $e');
          _profile ??= UserProfileModel(
            id: user.uid,
            name: user.displayName ?? 'Admin',
            email: user.email ?? '',
            phone: user.phoneNumber ?? '',
            role: 'admin',
          );
        }

        // Re-verify privacy policy persistence
        await _loadPrivacyPolicyState();

        _loading = false;
        if (!_initCompleter.isCompleted) _initCompleter.complete();
        notifyListeners();
      });
    } else {
      _loading = false;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      notifyListeners();
    }
  }

  /// Internal helper to load privacy policy acceptance from persistent stores
  Future<void> _loadPrivacyPolicyState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVersion = prefs.getString(_privacyPolicyKey);
      if (savedVersion == _currentPrivacyVersion) {
        privacyPolicyAccepted = true;
        return;
      }

      // Secondary fallback to SecureStorageService
      final secureVersion = await _storage.read(_privacyPolicyKey);
      if (secureVersion == _currentPrivacyVersion) {
        privacyPolicyAccepted = true;
        await prefs.setString(_privacyPolicyKey, _currentPrivacyVersion);
      }
    } catch (e) {
      debugPrint('[CurrentUserProvider Admin] Error reading privacy policy storage: $e');
    }
  }

  /// Sets privacy policy acceptance and persists across restarts to persistent storage.
  Future<void> setPrivacyPolicyAccepted(bool accepted) async {
    privacyPolicyAccepted = accepted;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (accepted) {
        await prefs.setString(_privacyPolicyKey, _currentPrivacyVersion);
        await _storage.write(_privacyPolicyKey, _currentPrivacyVersion);
      } else {
        await prefs.remove(_privacyPolicyKey);
        await _storage.delete(_privacyPolicyKey);
      }
    } catch (e) {
      debugPrint('[CurrentUserProvider Admin] Error saving privacy policy storage: $e');
    }
    notifyListeners();
  }

  /// Resets in-memory state on explicit user logout
  void reset() {
    _firebaseUser = null;
    _profile = null;
    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final currentUserProvider = CurrentUserProvider();

