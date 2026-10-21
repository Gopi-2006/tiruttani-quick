# Proguard rules for YOUPI Observer App

# Keep application components
-keep class com.youpi.observer.** { *; }

# Keep AndroidX Security Crypto
-keep class androidx.security.crypto.** { *; }

# Keep ZXing QR
-keep class com.google.zxing.** { *; }

# Keep OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
