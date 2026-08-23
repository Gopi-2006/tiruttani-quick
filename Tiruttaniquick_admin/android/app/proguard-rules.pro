# ProGuard / R8 Rules for Thiruttani Quick Admin (tiruttaniquick_admin)
# Optimized for maximum R8 shrinking, obfuscation, and Google Play performance.

# ==========================================
# 1. Flutter Engine & Application Entry Points
# ==========================================
-keep class com.thiruttaniquick.admin.MainActivity { *; }
-keep class io.flutter.app.FlutterApplication { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class io.flutter.plugin.common.MethodChannel$* { *; }
-keep class io.flutter.plugin.common.BasicMessageChannel$* { *; }
-keep class io.flutter.plugin.common.EventChannel$* { *; }

# Preserve necessary annotations and line numbers for crash reporting / de-obfuscation
-keepattributes *Annotation*, SourceFile, LineNumberTable, InnerClasses, EnclosingMethod, Signature

# ==========================================
# 2. Gson / Serialization
# ==========================================
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
    @com.google.gson.annotations.Expose <fields>;
}
-dontwarn com.google.gson.**

# ==========================================
# 3. AndroidX / WorkManager / Room / SQLite
# ==========================================
# AndroidX components bundle consumer rules. We preserve reflectively instantiated worker and DB constructors.
-keep public class * extends androidx.work.Worker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep public class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep public class * extends androidx.room.RoomDatabase {
    public <init>();
}
-dontwarn androidx.work.**
-dontwarn androidx.room.**
-dontwarn androidx.startup.**
-dontwarn androidx.sqlite.**
-dontwarn androidx.**

# ==========================================
# 4. Firebase & Google Play Services
# ==========================================
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-dontwarn androidx.credentials.**
-dontwarn com.google.android.libraries.identity.googleid.**

# ==========================================
# 5. Glide & Image Handling
# ==========================================
-dontwarn com.bumptech.glide.**
-keep public class ** implements com.bumptech.glide.module.GlideModule
-keep public class ** extends com.bumptech.glide.module.AppGlideModule {
    <init>(...);
}
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
    **[] $VALUES;
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ==========================================
# 6. Local Notifications & Plugins
# ==========================================
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**
-keep class com.msg91.sendotp.sendotp_flutter_sdk.** { *; }
-dontwarn com.msg91.sendotp.sendotp_flutter_sdk.**
-dontwarn com.baseflow.geolocator.**
-dontwarn com.baseflow.geocoding.**
-dontwarn org.sqlite.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn retrofit2.**
-dontwarn com.google.android.play.core.**

# ==========================================
# 7. Kotlin Metadata
# ==========================================
-dontwarn kotlin.jvm.internal.**
