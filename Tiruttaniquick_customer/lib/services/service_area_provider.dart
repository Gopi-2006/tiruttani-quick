import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'location_service.dart';
import 'service_area_service.dart';

enum ServiceAreaStatus {
  notChecked,
  checking,
  allowed,
  disallowed,
  error,
}

class ServiceAreaProvider extends ChangeNotifier {
  final ServiceAreaService _service = ServiceAreaService();
  final LocationService _locationService = LocationService();

  ServiceAreaStatus _status = ServiceAreaStatus.notChecked;
  String? _detectedPincode;
  String? _detectedCity;
  String? _detectedState;
  List<String> _allowedPincodes = [];
  String? _errorMessage;

  ServiceAreaStatus get status => _status;
  String? get detectedPincode => _detectedPincode;
  String? get detectedCity => _detectedCity;
  String? get detectedState => _detectedState;
  List<String> get allowedPincodes => _allowedPincodes;
  String? get errorMessage => _errorMessage;

  bool get isAllowed => _status == ServiceAreaStatus.allowed;
  bool get isDisallowed => _status == ServiceAreaStatus.disallowed;
  bool get isChecking => _status == ServiceAreaStatus.checking;
  bool get isError => _status == ServiceAreaStatus.error;

  // Initialize and load allowed pincodes, then check GPS
  Future<void> initServiceArea() async {
    if (_status == ServiceAreaStatus.checking) return;
    _status = ServiceAreaStatus.checking;
    notifyListeners();

    try {
      final config = await _service.getAllowedPincodes();
      _allowedPincodes = config.allowedPincodes;
    } catch (e) {
      _allowedPincodes = ['631209', '631211']; // Fallback
    }

    await checkGPSLocation();
  }

  // Force checking GPS location
  Future<void> checkGPSLocation() async {
    _status = ServiceAreaStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_allowedPincodes.isEmpty) {
        final config = await _service.getAllowedPincodes();
        _allowedPincodes = config.allowedPincodes;
      }

      final position = await _locationService.getCurrentLocation();
      if (position == null) {
        _status = ServiceAreaStatus.error;
        _errorMessage = 'GPS permission denied or location services disabled.';
        notifyListeners();
        return;
      }

      final placemark = await _locationService.getPlacemarkFromPosition(position);
      if (placemark == null || placemark.postalCode == null || placemark.postalCode!.isEmpty) {
        _status = ServiceAreaStatus.error;
        _errorMessage = 'Could not retrieve address details. Enter pincode manually.';
        notifyListeners();
        return;
      }

      _detectedPincode = placemark.postalCode!.trim();
      _detectedCity = placemark.locality ?? '';
      _detectedState = placemark.administrativeArea ?? '';

      // Allow access to the app under any detected pincode
      _status = ServiceAreaStatus.allowed;
    } catch (e) {
      _status = ServiceAreaStatus.error;
      _errorMessage = 'An error occurred while fetching location: $e';
    }

    notifyListeners();
  }

  // Check manual pincode
  Future<void> checkManualPincode(String pincode) async {
    final cleanPincode = pincode.trim();
    if (cleanPincode.isEmpty) {
      _status = ServiceAreaStatus.error;
      _errorMessage = 'Pincode cannot be empty.';
      notifyListeners();
      return;
    }

    _status = ServiceAreaStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_allowedPincodes.isEmpty) {
        final config = await _service.getAllowedPincodes();
        _allowedPincodes = config.allowedPincodes;
      }

      _detectedPincode = cleanPincode;
      _detectedCity = 'Manual Entry';
      _detectedState = '';

      // Allow access to the app under any manual pincode
      _status = ServiceAreaStatus.allowed;
    } catch (e) {
      _status = ServiceAreaStatus.error;
      _errorMessage = 'An error occurred during verification.';
    }

    notifyListeners();
  }

  Future<bool> isPincodeAllowed(String pincode) async {
    final cleanPincode = pincode.trim();
    if (_allowedPincodes.isEmpty) {
      try {
        final config = await _service.getAllowedPincodes();
        _allowedPincodes = config.allowedPincodes;
      } catch (_) {
        _allowedPincodes = ['631209', '631211'];
      }
    }
    // Only accept allowed pincodes or explicitly 631209/631211 for address/delivery
    return _allowedPincodes.contains(cleanPincode) || cleanPincode == '631209' || cleanPincode == '631211';
  }

  // Submit availability request
  Future<void> submitNotificationRequest({
    required String name,
    required String phone,
  }) async {
    if (_detectedPincode == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    await _service.requestAvailability(
      uid: uid,
      name: name,
      phone: phone,
      pincode: _detectedPincode!,
    );
  }

  void reset() {
    _status = ServiceAreaStatus.notChecked;
    _detectedPincode = null;
    _detectedCity = null;
    _detectedState = null;
    _errorMessage = null;
    notifyListeners();
  }
}

final serviceAreaProvider = ServiceAreaProvider();
