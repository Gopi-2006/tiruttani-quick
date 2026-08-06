import 'package:firebase_core/firebase_core.dart';

/// Firebase configuration for the **tiruttaniquick_customer** app.
///
/// appId  → matches `mobilesdk_app_id` for `com.thiruttaniquick.customer`
///           in google-services.json
/// androidClientId → type-1 OAuth client for `com.thiruttaniquick.customer`
///                   (SHA-1 debug fingerprint: f57099e7...)
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return const FirebaseOptions(
      apiKey: 'AIzaSyC3NfrW8Ozq9gGRHEMp3jOWbTMCU5dcMck',
      appId: '1:335404099413:android:263a2b7d815db0ae6eb1dc',
      messagingSenderId: '335404099413',
      projectId: 'blinkit-grocery-c3f5d',
      storageBucket: 'blinkit-grocery-c3f5d.firebasestorage.app',
      // Required for Google Sign-In on Android: the type-1 OAuth client
      // registered for com.thiruttaniquick.customer in Firebase Console.
      androidClientId:
          '335404099413-9u05pjk9ekua0a38mup66mk0prorhn76.apps.googleusercontent.com',
    );
  }
}
