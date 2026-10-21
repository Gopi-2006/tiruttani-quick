# Release App Bundle (.AAB), Signing & Crashlytics Guide

This step-card walkthrough details how to build production-ready, signed **Android App Bundles (.aab)** for Google Play Console, optimize download sizes, and integrate **Firebase Crashlytics** for stability monitoring.

---

## CARD 1: Building the Release App Bundle (.AAB)

Google Play Store requires an **Android App Bundle (.aab)** for all new app releases instead of raw APKs. When users download the app, Google Play dynamically generates an optimized APK containing only the resources for that user's specific device architecture and screen density (saving 30–50% in download size).

### Step 1: Verify `key.properties`
Ensure `Tiruttaniquick_customer/android/key.properties` exists with the correct paths and passwords:
```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=thiruttaniquick
storeFile=release-keystore.jks
```

### Step 2: Run the Release Build Command
Open your terminal in the customer app directory:
```bash
cd Tiruttaniquick_customer

# Build production signed App Bundle with code obfuscation and debug symbol extraction
flutter build appbundle --release --obfuscate --split-debug-info=build/app/outputs/symbols
```

### Step 3: Output Location
The signed release bundle is generated at:
```
Tiruttaniquick_customer/build/app/outputs/bundle/release/app-release.aab
```
*Upload this exact `.aab` file to Google Play Console.*

---

## CARD 2: App Size Optimization & Analysis

### 1. Analyze Bundle Breakdown
To inspect which packages, assets, or native libraries are taking up the most space:
```bash
flutter build appbundle --analyze-size --release
```
This produces a terminal tree breakdown and outputs a JSON file (e.g., `build/bundle-analysis.json`) that you can visualize at [Flutter DevTools App Size Tool](https://docs.flutter.dev/tools/devtools/app-size).

### 2. Gradle Bundle Splits Configuration
In `Tiruttaniquick_customer/android/app/build.gradle.kts`, ensure dynamic resource splitting is configured:
```kotlin
android {
    ...
    bundle {
        language {
            enableSplit = true
        }
        density {
            enableSplit = true
        }
        abi {
            enableSplit = true
        }
    }
}
```
This ensures users only download the native code (e.g. `arm64-v8a`) and screen density (e.g. `xxhdpi`) appropriate for their phone.

### 3. R8 / ProGuard Minification & Resource Shrinking
Our `build.gradle.kts` already enables R8 minification and resource shrinking for release builds:
```kotlin
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
    }
}
```
*Note: All Firebase, Flutter, and AdMob classes are already protected in `proguard-rules.pro`.*

---

## CARD 3: Firebase Crashlytics Integration

Google Play Console monitors **User-perceived crash rates** (< 1.09% threshold) and **ANR rates** (< 0.47% threshold). Setting up Firebase Crashlytics catches exceptions in production before they impact your store rating.

### Step 1: Add Crashlytics Dependency
In `Tiruttaniquick_customer/pubspec.yaml`, add under `dependencies`:
```yaml
dependencies:
  firebase_crashlytics: ^4.3.0
```
Then run:
```bash
flutter pub get
```

### Step 2: Configure Android Gradle Plugins
1. In `Tiruttaniquick_customer/android/build.gradle.kts` (Project-level), add to the plugins block:
```kotlin
plugins {
    ...
    id("com.google.firebase.crashlytics") version "3.0.2" apply false
}
```

2. In `Tiruttaniquick_customer/android/app/build.gradle.kts` (App-level), apply the plugin:
```kotlin
plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    id("dev.flutter.flutter-gradle-plugin")
}
```

### Step 3: Initialize Crashlytics in `main.dart`
In `Tiruttaniquick_customer/lib/main.dart`:
```dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // 1. Pass all uncaught Flutter framework errors to Crashlytics
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };

  // 2. Pass all uncaught asynchronous errors outside Flutter framework
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(const MyApp());
}
```

### Step 4: Verify Crash Reporting
To verify integration in debug/staging, trigger a test crash on a hidden button or in staging code:
```dart
// Test crash (DO NOT keep in production UI)
FirebaseCrashlytics.instance.crash();
```
Check the **Firebase Console &gt; Crashlytics dashboard** within 5 minutes to see the recorded crash trace.

---

## CARD 4: Google Play Closed Testing & Release Checklist

Google requires **all new personal developer accounts created after November 13, 2023** to complete closed testing before applying for production access.

### 20 Testers for 14 Days Rule:
1. **Create Closed Testing Track:**
   - Go to **Play Console &gt; Testing &gt; Closed testing**.
   - Create a track named "Closed Testing".
   - Upload your `app-release.aab`.
2. **Opt-In 20+ Testers:**
   - Create an email list of at least 20 testers (friends, family, local beta users).
   - Testers **MUST** click the web/Google Play opt-in link provided by Play Console and install the app on their Android devices.
   - Testers **must remain opted in for at least 14 consecutive days**.
3. **Inspect the Pre-Launch Report:**
   - Google automatically runs automated tests across 10+ real Android devices (Firebase Test Lab).
   - Check the **Pre-launch report** in Play Console for:
     - Crashes or ANRs on specific OS versions.
     - Screen display / layout issues across various aspect ratios.
     - Security vulnerabilities.
4. **Apply for Production Access:**
   - After the 14 days have passed and testing engagement criteria are satisfied, the **"Apply for production"** button in Play Console will unlock.
   - Answer the questionnaire about your testing feedback, bug fixes, and production readiness.

---

## CARD 5: Version Management & Release Flow

Each release to Google Play Console requires incrementing the `versionCode` in `pubspec.yaml`:

```yaml
# Format: version: versionName+versionCode
version: 1.0.13+20
```
- **`versionName` (1.0.13):** Displayed to users in the Play Store.
- **`versionCode` (20):** Must be strictly greater than the previous upload (monotonically increasing integer).

### Quick Build & Release Command Cheatsheet
```bash
# 1. Bump version in pubspec.yaml (e.g., version: 1.0.13+20)
# 2. Run tests to ensure quality
flutter test

# 3. Analyze code for zero warnings
flutter analyze lib/

# 4. Build signed App Bundle
flutter build appbundle --release --obfuscate --split-debug-info=build/app/outputs/symbols

# 5. Upload to Google Play Console
# File: Tiruttaniquick_customer/build/app/outputs/bundle/release/app-release.aab
```
