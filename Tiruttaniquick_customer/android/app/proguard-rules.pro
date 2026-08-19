# ProGuard / R8 Rules for Thiruttani Quick (tiruttaniquick_customer)
# Optimized for maximum R8 shrinking, obfuscation, and Google Play performance.

# ==========================================
# 1. Flutter Engine & Application Entry Points
# ==========================================
-keep class com.thiruttaniquick.customer.MainActivity { *; }
-keep class io.flutter.app.FlutterApplication { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class io.flutter.plugin.common.MethodChannel$* { *; }
-keep class io.flutter.plugin.common.BasicMessageChannel$* { *; }
-keep class io.flutter.plugin.common.EventChannel$* { *; }

# Preserve necessary annotations and line numbers for crash reporting / de-obfuscation
-keepattributes *Annotation*, SourceFile, LineNumberTable, InnerClasses, EnclosingMethod, Signature

# ==========================================
# 2. Gson / Serialization (Targeted members only)
# ==========================================
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
    @com.google.gson.annotations.Expose <fields>;
}
-dontwarn com.google.gson.**

# ==========================================
# 3. AndroidX / WorkManager / Room
# ==========================================
-dontwarn androidx.work.**
-dontwarn androidx.room.**
-dontwarn androidx.startup.**
-dontwarn androidx.**

# Keep worker classes if instantiated via reflection by WorkManager
-keep public class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# ==========================================
# 4. Firebase & Google Play Services
# ==========================================
# Firebase and Play Services bundle consumer Proguard rules automatically.
# Suppress non-fatal warnings so R8 can freely optimize, strip unused methods, and obfuscate.
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-dontwarn androidx.credentials.**
-dontwarn com.google.android.libraries.identity.googleid.**

# ==========================================
# 5. Google Mobile Ads (AdMob) & UMP SDK
# ==========================================
# Google Mobile Ads bundles consumer ProGuard rules. Suppress remaining warnings.
-dontwarn com.google.android.gms.ads.**
-dontwarn com.google.android.ump.**

# ==========================================
# 6. Local Notifications & Ringtone Player
# ==========================================
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**
-dontwarn io.inway.ringtoneplayer.**
-dontwarn com.io.flutter_ringtone_player.**

# ==========================================
# 7. Plugins & Utilities (Geolocator, MSG91, URL Launcher, etc.)
# ==========================================
-keep class com.msg91.sendotp.sendotp_flutter_sdk.** { *; }
-dontwarn com.msg91.sendotp.sendotp_flutter_sdk.**
-dontwarn com.baseflow.geolocator.**
-dontwarn com.baseflow.geocoding.**
-dontwarn com.it_delights.flutter_secure_storage.**
-dontwarn androidx.security.crypto.**
-dontwarn io.flutter.plugins.urllauncher.**
-dontwarn com.google.android.play.core.**

# ==========================================
# 8. Kotlin Metadata
# ==========================================
-dontwarn kotlin.jvm.internal.**

