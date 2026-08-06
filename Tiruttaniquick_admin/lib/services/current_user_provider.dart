import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

class CurrentUserProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? _firebaseUser;
  UserProfileModel? _profile;
  bool _loading = true;
  StreamSubscription<User?>? _subscription;
  bool privacyPolicyAccepted = false;

  User? get firebaseUser => _firebaseUser;
  UserProfileModel? get profile => _profile;
  bool get loading => _loading;
  bool get isAuthenticated => _firebaseUser != null;
  String get role => _profile?.role ?? '';

  void init() {
    _subscription ??= _auth.authStateChanges().listen((user) async {
      _firebaseUser = user;
      if (user == null) {
        _profile = null;
        _loading = false;
        privacyPolicyAccepted = false;
        notifyListeners();
        return;
      }

      // Keep router gated while profile document is loaded and validated
      _loading = true;
      notifyListeners();

      try {
        final stopwatch = AuthPerformanceLogger.start('Load Admin Profile (${user.uid})');
        final snapshot = await _db.collection('users').doc(user.uid).get();
        AuthPerformanceLogger.stopAndLog(stopwatch, 'Load Admin Profile');

        final profile = snapshot.exists
            ? UserProfileModel.fromFirestore(snapshot.id, snapshot.data()!)
            : null;

        // Allow only role == admin
        if (profile != null && profile.role.toLowerCase() != 'admin') {
          debugPrint('[CurrentUserProvider Admin] Non-admin role detected: "${profile.role}". Signing out.');
          _profile = null;
          _firebaseUser = null;
          _loading = false;
          notifyListeners();
          await _auth.signOut();
          return;
        }

        _profile = profile;
        NotificationService.instance.setupUser(user.uid, profile?.role ?? 'admin');
      } catch (e) {
        debugPrint('[CurrentUserProvider Admin] Error loading user profile: $e');
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
