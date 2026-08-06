import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class AuthExceptionHandler {
  /// Converts any exception caught during authentication into a clear, user-friendly message.
  static String parseException(dynamic e) {
    if (e == null) return 'An unknown error occurred. Please try again.';

    if (e is FirebaseAuthException) {
      switch (e.code.toLowerCase()) {
        case 'user-not-found':
          return 'No user found with this email address. Please sign up first.';
        case 'wrong-password':
          return 'Incorrect password. Please verify and try again.';
        case 'invalid-credential':
          return 'Invalid credentials provided. Please check your details.';
        case 'email-already-in-use':
          return 'An account with this email already exists. Please sign in instead.';
        case 'user-disabled':
          return 'This user account has been disabled. Please contact support.';
        case 'too-many-requests':
          return 'Too many login attempts. Please wait a few minutes before trying again.';
        case 'operation-not-allowed':
          return 'Email/Password sign-in is not enabled in Firebase Console.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection and try again.';
        case 'account-exists-with-different-credential':
          return 'An account already exists with the same email but different sign-in credentials.';
        case 'invalid-email':
          return 'The email address format is invalid.';
        case 'weak-password':
          return 'The password is too weak. Please use at least 6 characters.';
        case 'requires-recent-login':
          return 'This operation is sensitive and requires recent authentication. Please log in again.';
        default:
          if (e.message != null && e.message!.isNotEmpty) {
            return e.message!;
          }
          return 'Authentication failed (${e.code}). Please try again.';
      }
    }

    if (e is PlatformException) {
      final code = e.code.toLowerCase();
      if (code == 'sign_in_canceled' || code == 'canceled') {
        return 'Google Sign-In was cancelled.';
      } else if (code == 'network_error') {
        return 'Network error during sign-in. Please check your connection.';
      } else if (code == 'sign_in_failed') {
        return 'Google Sign-In failed. Please check Google Play Services on your device.';
      } else if (code.contains('10')) {
        return 'Google Sign-In Error (ApiException 10): SHA-1 fingerprint missing in Firebase Console.';
      } else if (code.contains('12500')) {
        return 'Google Sign-In Error (ApiException 12500): Check google-services.json & OAuth setup.';
      }
      return e.message ?? 'Platform authentication error (${e.code}).';
    }

    final msg = e.toString();
    if (msg.contains('Google sign in was cancelled')) {
      return 'Google Sign-In was cancelled.';
    } else if (msg.contains('ApiException 10') || msg.contains('10:')) {
      return 'Google Sign-In Error (ApiException 10): SHA-1/SHA-256 fingerprint missing in Firebase Console.';
    } else if (msg.contains('ApiException 12500') || msg.contains('12500:')) {
      return 'Google Sign-In Error (ApiException 12500): Check google-services.json & OAuth setup.';
    } else if (msg.contains('SocketException') || msg.contains('ClientException')) {
      return 'Internet connection error. Please check your network and try again.';
    }

    // Strip generic Exception prefix if present
    if (msg.startsWith('Exception: ')) {
      return msg.substring(11);
    }

    return msg;
  }
}
