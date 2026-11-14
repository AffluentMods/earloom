import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key lives outside the repo: android/key.properties (git-ignored)
// names the keystore file and its passwords. Without it, release builds are
// signed with the debug key so `flutter run --release` still works.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
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
        // Impeller stays on everywhere except the CI emulator, which has no
        // GPU and crashes rendering it (.github/workflows/devices.yml passes
        // -P earloomImpeller=false). Set through the manifest because the
        // playback service's Flutter engine ignores launch flags.
        manifestPlaceholders["enableImpeller"] = (project.findProperty("earloomImpeller") ?: "true").toString()
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

    signingConfigs {
        if (keyProperties.isNotEmpty()) {
            create("upload") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (keyProperties.isNotEmpty()) signingConfigs.getByName("upload") else signingConfigs.getByName("debug")
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
