import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

class SettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  String _languageCode = 'en';

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> init() async {
    final storage = SecureStorageService();
    try {
      final savedTheme = await storage.read('theme_mode');
      final savedLang = await storage.read('language_code');

      if (savedTheme == 'dark') {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.light;
      }

      if (savedLang == 'ta') {
        _languageCode = 'ta';
      } else {
        _languageCode = 'en';
      }
    } catch (e) {
      debugPrint('Error loading settings from storage: $e');
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final storage = SecureStorageService();
      await storage.write('theme_mode', mode == ThemeMode.dark ? 'dark' : 'light');
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
  }

  Future<void> setLanguageCode(String code) async {
    _languageCode = code;
    notifyListeners();
    try {
      final storage = SecureStorageService();
      await storage.write('language_code', code);
    } catch (e) {
      debugPrint('Error saving language code: $e');
    }
  }

  String translate(String key) {
    return _translations[_languageCode]?[key] ?? key;
  }

  static const Map<String, Map<String, String>> _translations = {
    'en': {
      'profileTitle': 'My Profile',
      'contact': 'Contact',
      'gmail': 'Gmail',
      'phone': 'Phone',
      'addPhone': 'Add phone number',
      'savedAddresses': 'Saved Addresses',
      'noSavedAddresses': 'No saved addresses yet',
      'reviewsFeedback': 'My Reviews & Feedback',
      'reviewsSubtitle': 'Share your experience or submit feedback',
      'logout': 'Logout',
      'fcmDebug': 'FCM Debug Console',
      'fcmSubtitle': 'View token, permissions, and test push notifications',
      'settings': 'Settings',
      'themeMode': 'Theme Mode',
      'lightTheme': 'Light Theme',
      'darkTheme': 'Dark Theme',
      'language': 'Language Preference',
      'english': 'English',
      'tamil': 'Tamil',
      'editPhone': 'Edit Phone',
      'cancel': 'Cancel',
      'save': 'Save',
      'addAddress': 'Add Address',
      'editAddress': 'Edit Address',
      'pincodeWarning': 'We currently do not deliver to this pincode.',
      'label': 'Label',
      'fullAddress': 'Full Address',
      'fillManuallyNote': 'Note: Please fill the address details manually.',
      'landmark': 'Landmark',
      'pincode': 'Pincode',
      'home': 'Home',
      'popularCategories': 'Popular categories',
      'popularProducts': 'Popular products',
      'searchPlaceholder': 'Search groceries, biscuits, oil...',
      'addToCart': 'Add to cart',
      'cart': 'Cart',
      'myOrders': 'My Orders',
      'deleteAccount': 'Delete Account',
    },
    'ta': {
      'profileTitle': 'எனது சுயவிவரம்',
      'contact': 'தொடர்பு கொள்ள',
      'gmail': 'ஜிமெயில்',
      'phone': 'தொலைபேசி',
      'addPhone': 'தொலைபேசி எண்ைச் சேர்க்கவும்',
      'savedAddresses': 'சேமிக்கப்பட்ட முகவரிகள்',
      'noSavedAddresses': 'இன்னும் முகவரிகள் சேமிக்கப்படவில்லை',
      'reviewsFeedback': 'எனது மதிப்புரைகள் & கருத்து',
      'reviewsSubtitle': 'உங்கள் அனுபவத்தைப் பகிரவும் அல்லது கருத்தைச் சமர்ப்பிக்கவும்',
      'logout': 'வெளியேறு',
      'fcmDebug': 'FCM பிழைத்திருத்த முனையம்',
      'fcmSubtitle': 'டோக்கன், அனுமதிகள் மற்றும் புஷ் அறிவிப்புகளை சோதிக்கவும்',
      'settings': 'அமைப்புகள்',
      'themeMode': 'தீம் முறை',
      'lightTheme': 'ஒளி தீம்',
      'darkTheme': 'இருண்ட தீம்',
      'language': 'மொழி முன்னுரிமை',
      'english': 'ஆங்கிலம் (English)',
      'tamil': 'தமிழ் (Tamil)',
      'editPhone': 'தொலைபேசியைத் திருத்து',
      'cancel': 'ரத்துசெய்',
      'save': 'சேமி',
      'addAddress': 'முகவரியைச் சேர்',
      'editAddress': 'முகவரியைத் திருத்து',
      'pincodeWarning': 'இந்த பின்கோட்டிற்கு நாங்கள் தற்போது விநியோகம் செய்வதில்லை.',
      'label': 'பெயர் குறிச்சொல்',
      'fullAddress': 'முழு முகவரி',
      'fillManuallyNote': 'குறிப்பு: முகவரி விவரங்களை கைமுறையாக நிரப்பவும்.',
      'landmark': 'அடையாளம்',
      'pincode': 'பின்கோடு',
      'home': 'முகப்பு',
      'popularCategories': 'பிரபலமான பிரிவுகள்',
      'popularProducts': 'பிரபலமான தயாரிப்புகள்',
      'searchPlaceholder': 'மளிகை பொருட்கள், பிஸ்கட், எண்ணெய் தேடவும்...',
      'addToCart': 'வண்டியில் சேர்',
      'cart': 'வண்டி',
      'myOrders': 'எனது ஆர்டர்கள்',
      'deleteAccount': 'கணக்கை நீக்கு',
    }
  };
}

extension LocalizationExtension on BuildContext {
  String translate(String key) {
    return watch<SettingsProvider>().translate(key);
  }
}
