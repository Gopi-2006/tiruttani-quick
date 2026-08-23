import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing config from key.properties — REQUIRED for release builds.
// Copy key.properties.template to key.properties in android/ and fill in your credentials.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.thiruttaniquick.customer"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            if (!keystorePropertiesFile.exists()) {
                            throw GradleException(
                    "\n\n========================================\n" +
                    "RELEASE SIGNING ERROR\n" +
                    "========================================\n" +
                    "'key.properties' not found at:\n  ${keystorePropertiesFile.absolutePath}\n\n" +
                    "Copy 'key.properties.template' to 'key.properties' in android/ and fill in your\n" +
                    "storePassword, keyPassword, keyAlias, and storeFile values.\n" +
                    "NEVER commit key.properties to version control.\n" +
                    "========================================"
                )
            }
            keyAlias = keystoreProperties["keyAlias"] as? String
                ?: throw GradleException("Release signing error: 'keyAlias' is missing from key.properties")
            keyPassword = keystoreProperties["keyPassword"] as? String
                ?: throw GradleException("Release signing error: 'keyPassword' is missing from key.properties")
            val storeFileVal = keystoreProperties["storeFile"] as? String
                ?: throw GradleException("Release signing error: 'storeFile' is missing from key.properties")
            storePassword = keystoreProperties["storePassword"] as? String
                ?: throw GradleException("Release signing error: 'storePassword' is missing from key.properties")
            val storeFileObj = file(storeFileVal)
            if (!storeFileObj.exists()) {
                throw GradleException(
                    "Release signing error: Keystore not found at:\n  ${storeFileObj.absolutePath}\n" +
                    "Check the 'storeFile' path in your key.properties."
                )
            }
            storeFile = storeFileObj
        }
    }

    defaultConfig {
        applicationId = "com.thiruttaniquick.customer"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release builds ALWAYS use the release signing config.
            // NO debug fallback exists. Missing/invalid key.properties causes a
            // clear build error in signingConfigs.release above.
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Exclude SafetyNet — deprecated and flagged by Play Console.
// firebase_app_check Flutter plugin pulls firebase-appcheck-safetynet as a transitive
// dependency even when only AndroidProvider.playIntegrity is activated at runtime.
// These exclusions remove the SafetyNet JAR from the release classpath entirely.
// firebase-appcheck-playintegrity:18.0.0 remains in the classpath and is used at runtime.
configurations.all {
    exclude(group = "com.google.firebase", module = "firebase-appcheck-safetynet")
    exclude(group = "com.google.android.gms", module = "play-services-safetynet")
}
