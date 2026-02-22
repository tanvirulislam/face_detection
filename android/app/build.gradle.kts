plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.face_detection"
    compileSdk = 36
    // flutter.ndkVersion resolves to 28.2.13676358 in Flutter 3.27 which
    // fails to auto-download. Pin to 27.0.12077973 — a stable LTS release
    // that ships bundled with most Android Studio versions.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

  defaultConfig {
        applicationId = "com.example.face_detection"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("com.google.mlkit:face-detection:16.1.6")
    implementation("androidx.multidex:multidex:2.0.1")
}

flutter {
    source = "../.."
}
