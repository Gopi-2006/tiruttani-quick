# ProGuard/R8 Rules for Thiruttani Quick (tiruttaniquick_customer)

# ==========================================
# 0. Suppress warnings for missing libraries
# ==========================================
# Suppress Play Core warnings (since deferred components are not used)
-dontwarn com.google.android.play.core.**

# ==========================================
# 1. Flutter Rules
# ==========================================
# Keep all Flutter engine and wrapper classes to prevent reflection issues
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.editing.** { *; }
-keep class io.flutter.plugin.platform.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep MainActivity
-keep class com.thiruttaniquick.customer.MainActivity { *; }

# ==========================================
# 2. Firebase Rules
# ==========================================
# Firebase Common & Authentication
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.internal.firebase_auth.** { *; }
-dontwarn com.google.firebase.**

# Firebase Messaging (Push Notifications)
-keep class com.google.firebase.messaging.** { *; }
-dontwarn com.google.firebase.messaging.**

# ==========================================
# 3. Google Sign-In, Credential Manager & Play Services
# ==========================================
# Google Sign-In needs these classes preserved to avoid ApiException: 10
-keep class com.google.android.gms.auth.api.signin.** { *; }
-keep class com.google.android.gms.auth.api.signin.internal.** { *; }
-keep class com.google.android.gms.common.api.** { *; }
-keep class androidx.credentials.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }
-keep class com.google.firebase.appcheck.** { *; }
-dontwarn com.google.android.gms.**
-dontwarn androidx.credentials.**
-dontwarn com.google.android.libraries.identity.googleid.**


# ==========================================
# 4. Gson
# ==========================================
# Prevent obfuscation of serialized names and signature structures
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ==========================================
# 5. Retrofit & OkHttp
# ==========================================
# Keep Retrofit and OkHttp classes in case they are used by underlying plugins
-dontwarn retrofit2.**
-keep class retrofit2.** { *; }
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepclassmembers,allowshrinking,allowobfuscation class * {
    @retrofit2.http.* <methods>;
}

-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# ==========================================
# 6. Glide
# ==========================================
# Image caching library rules
-keep class com.bumptech.glide.** { *; }
-dontwarn com.bumptech.glide.**
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep public class * extends com.bumptech.glide.module.AppGlideModule {
    <init>(...);
}
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
    **[] $VALUES;
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ==========================================
# 7. Camera & Image Picker
# ==========================================
-keep class androidx.core.content.FileProvider { *; }

# ==========================================
# 8. SharedPreferences
# ==========================================
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# ==========================================
# 9. SQLite / Sqflite
# ==========================================
-keep class com.tekartik.sqflite.** { *; }
-keep class org.sqlite.** { *; }
-dontwarn org.sqlite.**

# ==========================================
# 10. WebView
# ==========================================
-keep class io.flutter.plugins.webviewflutter.** { *; }
-keep class android.webkit.** { *; }

# ==========================================
# 11. Google Mobile Ads (AdMob)
# ==========================================
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# ==========================================
# 12. SendOTP SDK
# ==========================================
-keep class com.msg91.sendotp.sendotp_flutter_sdk.** { *; }

# ==========================================
# 13. Other plugins & standard keepers
# ==========================================
# Geolocator / Geocoding / Local Notifications
-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.geocoding.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Flutter Secure Storage (Crypto & KeyStore)
-keep class com.it_delights.flutter_secure_storage.** { *; }
-keep class androidx.security.crypto.** { *; }
-dontwarn com.it_delights.flutter_secure_storage.**
-dontwarn androidx.security.crypto.**

# Firebase App Check & Play Integrity & GMS Tasks
-keep class com.google.firebase.appcheck.** { *; }
-keep class com.google.android.play.core.integrity.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
-dontwarn com.google.firebase.appcheck.**
-dontwarn com.google.android.play.core.integrity.**
-dontwarn com.google.android.gms.tasks.**

# Flutter Ringtone Player
-keep class io.inway.ringtoneplayer.** { *; }
-keep class com.io.flutter_ringtone_player.** { *; }
-dontwarn io.inway.ringtoneplayer.**

# Flutter Dotenv
-keep class com.example.flutter_dotenv.** { *; }
-dontwarn com.example.flutter_dotenv.**

# URL Launcher
-keep class io.flutter.plugins.urllauncher.** { *; }
-dontwarn io.flutter.plugins.urllauncher.**

# Application Packages & Data Models
-keep class com.thiruttaniquick.** { *; }
-keep class tiruttaniquick_shared.** { *; }

# ==========================================
# 14. Kotlin Keep Rules
# ==========================================
-keepclassmembers class * {
    metadata.jvm.internal.DefaultConstructorMarker *;
}
-keepattributes AnnotationDefault, EnclosingMethod, InnerClasses, Signature, SourceFile, LineNumberTable, *Annotation*, EnclosingMethod
# Preserve Kotlin Metadata
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.jvm.internal.**

# ==========================================
# 15. AndroidX Keep Rules
# ==========================================
-keep class androidx.annotation.** { *; }
-dontwarn androidx.**
-keep class androidx.lifecycle.** { *; }
