import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

class CurrentUserProvider extends ChangeNotifier {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? _firebaseUser;
  UserProfileModel? _profile;
  bool _loading = true;
  StreamSubscription<User?>? _subscription;

  User? get firebaseUser => _firebaseUser;
  UserProfileModel? get profile => _profile;
  bool get loading => _loading;
  bool get isAuthenticated => _firebaseUser != null;
  String get role => _profile?.role ?? '';

  CurrentUserProvider() {
    _firebaseUser = _auth.currentUser;
    if (_firebaseUser != null) {
      NotificationService.instance.setupUser(_firebaseUser!.uid, 'customer');
    }
  }

  void init() {
    _subscription ??= _auth.authStateChanges().listen((user) async {
      _firebaseUser = user;
      if (user == null) {
        _profile = null;
        _loading = false;
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
        final snapshot = await _db.collection('users').doc(user.uid).get();
        AuthPerformanceLogger.stopAndLog(stopwatch, 'Load Customer Profile');

        final profile = snapshot.exists
            ? UserProfileModel.fromFirestore(snapshot.id, snapshot.data()!)
            : null;

        // Allow only role == customer (or if the user document is not created yet, e.g. during sign up)
        if (profile != null && profile.role.toLowerCase() != 'customer') {
          debugPrint('[CurrentUserProvider] Invalid role detected: "${profile.role}". Signing out.');
          _profile = null;
          _firebaseUser = null;
          _loading = false;
          notifyListeners();
          await _auth.signOut();
          return;
        }

        _profile = profile;
      } catch (e) {
        debugPrint('[CurrentUserProvider] Error loading user profile: $e');
        _profile = null;
      }

      _loading = false;
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
