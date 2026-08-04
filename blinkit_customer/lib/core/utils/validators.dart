import 'package:blinkit_shared/blinkit_shared.dart';

class Validators {
  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationMessages.enterPhone;
    }
    if (value.trim().length < 10) {
      return ValidationMessages.enterValidPhone;
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationMessages.enterPassword;
    }
    if (value.trim().length < 6) {
      return ValidationMessages.passwordLength;
    }
    return null;
  }

  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationMessages.enterName;
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    if (!value.contains('@')) {
      return ValidationMessages.enterValidEmail;
    }
    return null;
  }

  static String? validateRequired(String? value, {String? message}) {
    if (value == null || value.trim().isEmpty) {
      return message ?? ValidationMessages.fieldRequired;
    }
    return null;
  }
}
