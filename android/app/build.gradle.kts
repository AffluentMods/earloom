plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.affluentlabs.earloom"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (new episode notifications) needs
        // the newer Java time APIs on older Android versions.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The application id can never change after the first store upload.
        applicationId = "com.affluentlabs.earloom"
        // Android 8.0. Media sessions, notification channels and background
        // limits all behave the modern way from here up.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // play: Google Play and the App Store build (may later carry Google Cast).
    // foss: F-Droid and IzzyOnDroid, with no proprietary SDKs. Today both are
    // the same app; CI checks that foss never pulls a Google proprietary
    // library. Build with --flavor play or --flavor foss.
    flavorDimensions += "store"
    productFlavors {
        create("play") { dimension = "store" }
        create("foss") { dimension = "store" }
    }

    buildTypes {
        release {
            // Debug keys for now, so `flutter run --release` works. The release
            // pipeline (Phase 9) signs with the upload key from key.properties,
            // which lives outside the repo.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
