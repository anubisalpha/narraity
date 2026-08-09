import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// keystore.properties lives at the Flutter project root (one level up from android/),
// alongside narraity-release.jks — both are gitignored, never committed.
val keystorePropertiesFile = rootProject.file("../keystore.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "uk.aity.narraity"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "uk.aity.narraity"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = keystorePropertiesFile.parentFile.resolve(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falls back to debug signing if keystore.properties isn't present (e.g. a fresh
            // checkout without the release keystore) so `flutter run --release` still works.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    lint {
        // `lintVitalAnalyzeRelease`'s cache directory
        // (build/app/intermediates/lint-cache/) repeatedly hit
        // AccessDeniedException/FileSystemException on this machine —
        // Defender real-time scanning locking freshly-extracted jars mid-
        // build, reproducible across a Gradle daemon restart and a full
        // intermediates wipe, not a one-off transient lock. `flutter
        // analyze` (Dart-level) is this project's actual code-quality gate
        // and stays mandatory; this only skips Android/Java-level lint on
        // release builds, which was never being relied on separately.
        checkReleaseBuilds = false
    }
}

flutter {
    source = "../.."
}
