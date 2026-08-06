import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';
import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';
import '../core/constants/app_roles.dart';
import '../core/utils/auth_exception_handler.dart';
import '../core/utils/auth_performance_logger.dart';
import '../models/user_profile_model.dart';
import 'connectivity_provider.dart';

class AuthRepository {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '335404099413-igkbppn88jhr9fdidhm92gfte28sr796.apps.googleusercontent.com',
  );

  late final GoogleSignIn _googleSignIn;

  static const String msg91WidgetId = String.fromEnvironment('MSG91_WIDGET_ID', defaultValue: '');
  static const String msg91AuthToken = String.fromEnvironment('MSG91_AUTH_TOKEN', defaultValue: '');
  static const String msg91AuthKey = String.fromEnvironment('MSG91_AUTH_KEY', defaultValue: '');

  AuthRepository() {
    _googleSignIn = GoogleSignIn(serverClientId: googleWebClientId);

    try {
      OTPWidget.initializeWidget(msg91WidgetId, msg91AuthToken);
    } catch (e) {
      debugPrint('[AuthRepository] Error initializing MSG91 OTPWidget: $e');
    }
  }

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// Helper to retry transient network failures gracefully with backoff
  Future<T> _retryOnNetworkFailure<T>(Future<T> Function() action, {int maxAttempts = 2}) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return await action();
      } catch (e) {
        final isNetworkError = e.toString().contains('SocketException') ||
            e.toString().contains('network-request-failed') ||
            e.toString().contains('ClientException') ||
            e.toString().contains('network_error');

        if (isNetworkError && attempt < maxAttempts) {
          debugPrint('[AuthRepository] Transient network failure detected. Retrying attempt $attempt...');
          await Future.delayed(Duration(milliseconds: 600 * attempt));
          continue;
        }
        rethrow;
      }
    }
  }

  /// Verifies connectivity prior to authentication operations
  void _verifyConnectivity() {
    if (!ConnectivityProvider.instance.isOnline) {
      throw Exception('No internet connection. Please connect to the internet and try again.');
    }
  }

  String _passwordFromPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    return 'RanukaGrocery_${cleaned}_SecureOtpPass';
  }

  String _formatPhoneForMsg91(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    if (cleaned.length == 10) {
      return '91$cleaned';
    }
    return cleaned;
  }

  Future<UserCredential> signInWithPhonePassword({
    required String phone,
    required String password,
  }) async {
    _verifyConnectivity();
    final email = _emailFromPhone(phone);
    return AuthPerformanceLogger.trace(
      'Sign-In with Phone/Password ($email)',
      () => _retryOnNetworkFailure(
        () => _auth.signInWithEmailAndPassword(email: email, password: password),
      ),
    );
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _verifyConnectivity();
    final trimmedEmail = email.trim();
    return AuthPerformanceLogger.trace(
      'Sign-In with Email ($trimmedEmail)',
      () => _retryOnNetworkFailure(
        () => _auth.signInWithEmailAndPassword(
          email: trimmedEmail,
          password: password,
        ),
      ),
    );
  }

  Future<UserCredential> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    _verifyConnectivity();
    final trimmedEmail = email.trim();
    return AuthPerformanceLogger.trace(
      'Sign-Up with Email ($trimmedEmail)',
      () async {
        final credential = await _retryOnNetworkFailure(
          () => _auth.createUserWithEmailAndPassword(
            email: trimmedEmail,
            password: password,
          ),
        );

        await _retryOnNetworkFailure(
          () => _db.collection('users').doc(credential.user!.uid).set({
            'name': name,
            'email': trimmedEmail,
            'role': AppRoles.customer,
            'createdAt': FieldValue.serverTimestamp(),
          }),
        );

        return credential;
      },
    );
  }

  Future<UserCredential> signUp({
    required String name,
    required String phone,
    required String email,
    required String password,
    bool sendVerificationOtp = true,
  }) async {
    _verifyConnectivity();
    final authEmail = _emailFromPhone(phone);
    final authPassword = _passwordFromPhone(phone);

    return AuthPerformanceLogger.trace(
      'Sign-Up Customer ($phone)',
      () async {
        final credential = await _retryOnNetworkFailure(
          () => _auth.createUserWithEmailAndPassword(
            email: authEmail,
            password: authPassword,
          ),
        );

        await _retryOnNetworkFailure(
          () => _db.collection('users').doc(credential.user!.uid).set({
            'name': name,
            'phone': phone.trim(),
            'email': email.trim(),
            'role': AppRoles.customer,
            'createdAt': FieldValue.serverTimestamp(),
          }),
        );

        if (sendVerificationOtp) {
          await sendOtp(phone);
        }
        return credential;
      },
    );
  }

  Future<UserCredential> signInWithGoogle() async {
    _verifyConnectivity();
    return AuthPerformanceLogger.trace(
      'Google Sign-In Complete Flow',
      () async {
        try {
          final googleUser = await AuthPerformanceLogger.trace(
            'Google Sign-In Native UI Picker',
            () => _googleSignIn.signIn(),
          );

          if (googleUser == null) {
            throw Exception('Google sign in was cancelled.');
          }

          final googleAuth = await AuthPerformanceLogger.trace(
            'Google Auth Tokens Fetch',
            () => googleUser.authentication,
          );

          final credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );

          final userCredential = await AuthPerformanceLogger.trace(
            'Firebase Auth Credential Exchange',
            () => _retryOnNetworkFailure(
              () => _auth.signInWithCredential(credential),
            ),
          );

          final user = userCredential.user;

          if (user != null) {
            final email = user.email ?? googleUser.email;
            final isAdmin = _isFirebaseOwner(email);
            final phone = user.phoneNumber ?? '';

            final userDoc = await AuthPerformanceLogger.trace(
              'Firestore User Document Read',
              () => _retryOnNetworkFailure(
                () => _db.collection('users').doc(user.uid).get(),
              ),
            );

            String resolvedRole = AppRoles.customer;
            if (isAdmin) {
              resolvedRole = AppRoles.admin;
            } else if (userDoc.exists) {
              resolvedRole = userDoc.data()?['role'] as String? ?? AppRoles.customer;
            }

            final Map<String, dynamic> data = {
              'name': user.displayName ?? googleUser.displayName ?? 'Customer',
              'email': email,
              'role': resolvedRole,
            };

            if (!userDoc.exists) {
              data['phone'] = phone;
              data['createdAt'] = FieldValue.serverTimestamp();
            } else {
              final existingPhone = userDoc.data()?['phone'] as String? ?? '';
              final existingPhoneDigits = existingPhone.replaceAll(RegExp(r'[^0-9]'), '');

              if (phone.isNotEmpty) {
                data['phone'] = phone;
              } else if (existingPhoneDigits.length < 10) {
                data['phone'] = '';
              }
            }

            await AuthPerformanceLogger.trace(
              'Firestore User Document Update',
              () => _retryOnNetworkFailure(
                () => _db.collection('users').doc(user.uid).set(data, SetOptions(merge: true)),
              ),
            );
          }

          return userCredential;
        } catch (e) {
          debugPrint('[AuthRepository] Google Sign-In Exception: $e');
          final parsedMessage = AuthExceptionHandler.parseException(e);
          throw Exception(parsedMessage);
        }
      },
    );
  }

  /// Grants admin role ONLY to exact whitelisted email addresses.
  /// Uses full-email matching — substring matching (e.g. contains('admin'))
  /// is a security vulnerability that would grant admin to arbitrary accounts.
  bool _isFirebaseOwner(String? email) {
    if (email == null) return false;
    // Add exact admin email addresses here. Never use substring/contains matching.
    const adminEmails = <String>{
      'gopim2006@gmail.com', // TODO: replace with your real admin Gmail address
    };
    return adminEmails.contains(email.toLowerCase().trim());
  }

  Future<bool> checkUserExists(String phone) async {
    _verifyConnectivity();
    final snapshot = await _retryOnNetworkFailure(
      () => _db.collection('users')
          .where('phone', isEqualTo: phone.trim())
          .limit(1)
          .get(),
    );
    return snapshot.docs.isNotEmpty;
  }

  Future<bool> sendOtpMsg91(String phone) async {
    final cleanedPhone = _formatPhoneForMsg91(phone);

    try {
      final data = {'identifier': cleanedPhone};
      final response = await OTPWidget.sendOTP(data);
      debugPrint('[AuthRepository] MSG91 Send OTP response: $response');

      final Map? res = response;
      if (res != null && res['type'] == 'success') {
        final reqId = res['message'] as String;
        await _db.collection('otp_codes').doc('otp_$cleanedPhone').set({
          'phone': phone,
          'reqId': reqId,
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      }

      debugPrint('[AuthRepository] MSG91 SDK returned non-success response.');
      // SECURITY: Mock OTP fallback is ONLY allowed in debug/development builds.
      // In production, a real OTP must always be delivered via MSG91.
      if (kDebugMode) {
        debugPrint('[AuthRepository] DEBUG ONLY: Falling back to mock OTP 123456.');
        await _db.collection('otp_codes').doc('otp_$cleanedPhone').set({
          'phone': phone,
          'code': '123456',
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[AuthRepository] Error calling MSG91 sendOTP SDK: $e.');
      // SECURITY: Mock OTP fallback is ONLY allowed in debug/development builds.
      if (kDebugMode) {
        debugPrint('[AuthRepository] DEBUG ONLY: Falling back to mock OTP 123456.');
        await _db.collection('otp_codes').doc('otp_$cleanedPhone').set({
          'phone': phone,
          'code': '123456',
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 5))),
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      }
      return false;
    }
  }

  Future<bool> verifyOtpMsg91(String phone, String code) async {
    final cleanedPhone = _formatPhoneForMsg91(phone);

    try {
      final snapshot = await _db.collection('otp_codes').doc('otp_$cleanedPhone').get();
      if (!snapshot.exists) return false;

      final reqId = snapshot.data()?['reqId'] as String?;
      if (reqId != null && reqId.isNotEmpty) {
        final data = {
          'reqId': reqId,
          'otp': code,
        };
        final response = await OTPWidget.verifyOTP(data);
        debugPrint('[AuthRepository] MSG91 Verify OTP response: $response');

        final Map? res = response;
        if (res != null && res['type'] == 'success') {
          return true;
        }
      }

      final savedCode = snapshot.data()?['code'] as String?;
      final expiresAt = snapshot.data()?['expiresAt'];
      final expired = expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now());
      return savedCode == code && !expired;
    } catch (e) {
      debugPrint('[AuthRepository] Error calling MSG91 verifyOTP SDK: $e. Falling back to local mock.');
      final snapshot = await _db.collection('otp_codes').doc('otp_$cleanedPhone').get();
      if (snapshot.exists) {
        final savedCode = snapshot.data()?['code'] as String?;
        final expiresAt = snapshot.data()?['expiresAt'];
        final expired = expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now());
        return savedCode == code && !expired;
      }
      return false;
    }
  }

  Future<void> sendOtp(String phone) async {
    await sendOtpMsg91(phone);
  }

  Future<bool> verifyOtp(String code, {String? phone}) async {
    String? targetPhone = phone;
    if (targetPhone == null && currentUser != null) {
      final profile = await getCurrentProfile();
      targetPhone = profile?.phone;
    }
    if (targetPhone == null || targetPhone.isEmpty) return false;
    return verifyOtpMsg91(targetPhone, code);
  }

  Future<Map<String, dynamic>?> verifyAccessToken(String accessToken) async {
    try {
      final url = Uri.parse('https://control.msg91.com/api/v5/widget/verifyAccessToken');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'authkey': msg91AuthKey,
          'access-token': accessToken,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('[AuthRepository] Error verifying access token: status ${response.statusCode}, body: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[AuthRepository] Exception in verifyAccessToken: $e');
      return null;
    }
  }

  Future<bool> retryOtpMsg91(String phone, {int retryChannel = 11}) async {
    final cleanedPhone = _formatPhoneForMsg91(phone);
    try {
      final snapshot = await _db.collection('otp_codes').doc('otp_$cleanedPhone').get();
      if (!snapshot.exists) return false;

      final reqId = snapshot.data()?['reqId'] as String?;
      if (reqId != null && reqId.isNotEmpty) {
        final data = {
          'reqId': reqId,
          'retryChannel': retryChannel,
        };
        final response = await OTPWidget.retryOTP(data);
        debugPrint('[AuthRepository] MSG91 Retry OTP response: $response');
        final Map? res = response;
        if (res != null && res['type'] == 'success') {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('[AuthRepository] Error calling MSG91 retryOTP SDK: $e');
      return false;
    }
  }

  Future<bool> retryOtp({String? phone, int retryChannel = 11}) async {
    String? targetPhone = phone;
    if (targetPhone == null && currentUser != null) {
      final profile = await getCurrentProfile();
      targetPhone = profile?.phone;
    }
    if (targetPhone == null || targetPhone.isEmpty) return false;
    return retryOtpMsg91(targetPhone, retryChannel: retryChannel);
  }

  Future<UserCredential> signInWithPhoneOtp({
    required String phone,
    required String otp,
  }) async {
    _verifyConnectivity();
    final verified = await verifyOtp(otp, phone: phone);
    if (!verified) {
      throw Exception('Invalid or expired OTP. Please try again.');
    }

    final query = await _retryOnNetworkFailure(
      () => _db.collection('users')
          .where('phone', isEqualTo: phone.trim())
          .limit(1)
          .get(),
    );

    if (query.docs.isEmpty) {
      throw Exception('This phone number is not registered. Please sign up first.');
    }

    final email = _emailFromPhone(phone);
    final password = _passwordFromPhone(phone);
    return _retryOnNetworkFailure(
      () => _auth.signInWithEmailAndPassword(email: email, password: password),
    );
  }

  Future<UserProfileModel?> getCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;

    return AuthPerformanceLogger.trace(
      'GetCurrentProfile (${user.uid})',
      () async {
        final snapshot = await _retryOnNetworkFailure(
          () => _db.collection('users').doc(user.uid).get(),
        );
        if (!snapshot.exists) return null;
        return UserProfileModel.fromFirestore(snapshot.id, snapshot.data()!);
      },
    );
  }

  Future<void> saveFcmToken(String token) async {
    final user = currentUser;
    if (user == null) return;

    await _retryOnNetworkFailure(
      () => _db.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
    );
  }

  Future<void> signOut() async {
    await AuthPerformanceLogger.trace(
      'Sign-Out',
      () async {
        try {
          await _googleSignIn.signOut();
        } catch (e) {
          debugPrint('[AuthRepository] Non-fatal error during Google Sign-Out: $e');
        }
        await _auth.signOut();
      },
    );
  }

  Future<void> updateProfilePhone(String phone) async {
    final user = currentUser;
    if (user == null) return;

    await _retryOnNetworkFailure(
      () => _db.collection('users').doc(user.uid).set({
        'phone': phone,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
    );
  }

  String _emailFromPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    return '$cleaned@thiruttaniquick.local';
  }
}
