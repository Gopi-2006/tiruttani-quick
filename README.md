# Tiruttani Quick — Grocery Delivery App

A production-ready Flutter grocery delivery platform for **Tiruttani Quick / Ranuka Store**.

## Apps

| App | Package ID | Description |
|-----|-----------|-------------|
| Customer | `com.thiruttaniquick.customer` | Customer-facing grocery ordering app |
| Admin | `com.thiruttaniquick.admin` | Admin panel for order & product management |

## Tech Stack

- **Flutter** / Dart (Android target: API 36)
- **Firebase Auth** — Email/Password, Google Sign-In, OTP via MSG91
- **Cloud Firestore** — Real-time database
- **Firebase Cloud Messaging** — Push notifications
- **Firebase App Check** — Play Integrity (SafetyNet-free)
- **AdMob** — Banner & Interstitial ads
- **Cloud Functions (Node 18)** — Order status notifications & security

## Project Structure

```
Tiruttaniquick_customer/   # Customer Flutter app
Tiruttaniquick_admin/      # Admin Flutter app
Tiruttaniquick_shared/     # Shared business logic (models, services, widgets)
functions/                 # Firebase Cloud Functions (v2)
firestore.rules            # Firestore security rules
```

## Build

```bash
# Customer release AAB
cd Tiruttaniquick_customer && flutter build appbundle --release

# Admin release AAB
cd Tiruttaniquick_admin && flutter build appbundle --release
```

## Resources

- [Flutter documentation](https://docs.flutter.dev/)
- [Firebase Flutter setup](https://firebase.google.com/docs/flutter/setup)
