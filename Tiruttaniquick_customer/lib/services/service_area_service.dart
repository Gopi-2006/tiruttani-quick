import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/service_area_model.dart';

class ServiceAreaService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<ServiceAreaModel> getAllowedPincodes() async {
    try {
      final docRef = _db.collection('service_config').doc('delivery_area');
      final snapshot = await docRef.get();
      if (!snapshot.exists) {
        // Seed default pincodes
        final defaultModel = ServiceAreaModel(allowedPincodes: ['631209', '631211']);
        await docRef.set(defaultModel.toMap());
        return defaultModel;
      } else {
        final data = snapshot.data();
        if (data == null || data['allowedPincodes'] == null) {
          final defaultModel = ServiceAreaModel(allowedPincodes: ['631209', '631211']);
          await docRef.set(defaultModel.toMap(), SetOptions(merge: true));
          return defaultModel;
        }
        return ServiceAreaModel.fromMap(data);
      }
    } catch (e) {
      // In case of error (e.g. offline or network issue), fallback to local default
      return ServiceAreaModel(allowedPincodes: ['631209', '631211']);
    }
  }

  Future<void> requestAvailability({
    required String uid,
    required String name,
    required String phone,
    required String pincode,
  }) async {
    await _db.collection('availability_requests').add({
      'uid': uid,
      'name': name,
      'phone': phone,
      'pincode': pincode,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
