# ProGuard/R8 Rules for Thiruttani Quick (tiruttaniquick_customer)
# Optimized for high R8 shrinking, obfuscation, and Google Play release.

# ==========================================
# 1. Core Android & Flutter Entry Points
# ==========================================
-keep class com.thiruttaniquick.customer.MainActivity { *; }
-keep class io.flutter.app.FlutterApplication { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

-keepattributes *Annotation*, SourceFile, LineNumberTable, InnerClasses, EnclosingMethod, Signature, RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations

# ==========================================
# 2. AndroidX Startup, WorkManager & Room
# (Fixes: Failed to create an instance of androidx.work.impl.WorkDatabase)
# ==========================================
-keep class androidx.startup.** { *; }
-keep class androidx.work.** { *; }
-keep class androidx.work.impl.** { *; }
-keep class * extends androidx.work.impl.WorkDatabase { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.room.** { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**
-dontwarn androidx.startup.**

# ==========================================
# 3. Firebase Suite (Core, Auth, Messaging, AppCheck, Firestore)
# ==========================================
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.internal.firebase_auth.** { *; }
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.appcheck.** { *; }
-dontwarn com.google.firebase.**

# ==========================================
# 4. Google Sign-In & Play Services
# ==========================================
-keep class com.google.android.gms.auth.api.signin.** { *; }
-keep class com.google.android.gms.auth.api.signin.internal.** { *; }
-keep class com.google.android.gms.common.api.** { *; }
-keep class androidx.credentials.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }
-dontwarn com.google.android.gms.**
-dontwarn androidx.credentials.**
-dontwarn com.google.android.libraries.identity.googleid.**

# ==========================================
# 5. Google Mobile Ads (AdMob) & UMP SDK
# ==========================================
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.ump.** { *; }
-dontwarn com.google.android.gms.ads.**
-dontwarn com.google.android.ump.**

# ==========================================
# 6. Local Notifications Plugin
# ==========================================
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# ==========================================
# 7. Flutter Secure Storage / EncryptedSharedPreferences
# ==========================================
-keep class com.it_delights.flutter_secure_storage.** { *; }
-keep class androidx.security.crypto.** { *; }
-dontwarn com.it_delights.flutter_secure_storage.**
-dontwarn androidx.security.crypto.**

# ==========================================
# 8. Geolocator & Geocoding
# ==========================================
-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.geocoding.** { *; }
-dontwarn com.baseflow.geolocator.**
-dontwarn com.baseflow.geocoding.**

# ==========================================
# 9. MSG91 SendOTP SDK
# ==========================================
-keep class com.msg91.sendotp.sendotp_flutter_sdk.** { *; }
-dontwarn com.msg91.sendotp.sendotp_flutter_sdk.**

# ==========================================
# 10. Serialization / Data Models (Gson)
# ==========================================
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ==========================================
# 11. Audio / Ringtone Player & URL Launcher
# ==========================================
-dontwarn io.inway.ringtoneplayer.**
-dontwarn com.io.flutter_ringtone_player.**
-dontwarn io.flutter.plugins.urllauncher.**
-dontwarn com.google.android.play.core.**

# ==========================================
# 12. Kotlin Metadata & AndroidX Lifecycle
# ==========================================
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.jvm.internal.**
-keep class androidx.annotation.** { *; }
-keep class androidx.lifecycle.** { *; }
-dontwarn androidx.**
