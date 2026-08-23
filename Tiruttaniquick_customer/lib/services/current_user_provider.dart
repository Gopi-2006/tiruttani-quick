import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

class CurrentUserProvider extends ChangeNotifier {
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

  User? _firebaseUser;
  UserProfileModel? _profile;
  bool _loading = true;
  StreamSubscription<User?>? _subscription;
  bool _isInitStarted = false;

  /// Completer that resolves once the first auth state has been fully processed.
  /// Splash screen awaits this to avoid navigating before auth is resolved.
  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get initComplete => _initCompleter.future;

  User? get firebaseUser => _firebaseUser;
  UserProfileModel? get profile => _profile;
  bool get loading => _loading;
  bool get isAuthenticated => _firebaseUser != null;
  String get role => _profile?.role ?? '';

  CurrentUserProvider() {
    try {
      _firebaseUser = _auth?.currentUser;
      if (_firebaseUser != null) {
        NotificationService.instance.setupUser(_firebaseUser!.uid, 'customer');
      }
    } catch (e) {
      debugPrint('[CurrentUserProvider] Non-fatal init warning: $e');
    }
  }

  void init() {
    if (_isInitStarted) return;
    _isInitStarted = true;

    final auth = _auth;
    if (auth == null) {
      _loading = false;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      notifyListeners();
      return;
    }

    _subscription = auth.authStateChanges().listen((user) async {
      _firebaseUser = user;
      if (user == null) {
        _profile = null;
        _loading = false;
        if (!_initCompleter.isCompleted) _initCompleter.complete();
        notifyListeners();
        return;
      }

      // Always setup notifications for the authenticated customer immediately
      NotificationService.instance.setupUser(user.uid, 'customer');

      // Keep router gated while profile document is loaded and validated
      _loading = true;
      notifyListeners();

      try {
        final stopwatch = AuthPerformanceLogger.start('Load Customer Profile (${user.uid})');
        final db = _db;
        final snapshot = db != null ? await db.collection('users').doc(user.uid).get() : null;
        AuthPerformanceLogger.stopAndLog(stopwatch, 'Load Customer Profile');

        final profile = (snapshot != null && snapshot.exists && snapshot.data() != null)
            ? UserProfileModel.fromFirestore(snapshot.id, snapshot.data()!)
            : null;

        _profile = profile;
      } catch (e) {
        debugPrint('[CurrentUserProvider] Error loading user profile: $e');
        _profile = null;
      }

      _loading = false;
      if (!_initCompleter.isCompleted) _initCompleter.complete();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final currentUserProvider = CurrentUserProvider();
