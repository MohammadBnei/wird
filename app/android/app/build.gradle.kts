plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.bnei.wird"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.bnei.wird"
        // `flutter build --target-platform` filters Flutter's own libraries and
        // not a plugin's. sherpa_onnx brings libonnxruntime.so for three ABIs
        // through its AAR, so an arm64 phone was carrying 25.6 MB of x86_64 and
        // 15.4 MB of armeabi-v7a it can never execute — more dead weight than
        // the whole app was before voice-follow existed. This has to sit in
        // defaultConfig: a buildTypes.release filter does not reach libraries
        // that arrive from a dependency rather than being built here.
        //
        // Build with `--split-per-abi`, which writes one APK per ABI and is
        // what should be handed to a phone. An ndk.abiFilters here would do
        // the same for a single APK, but it cannot coexist with the split and
        // the split is the one that also keeps a 32-bit phone buildable.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug keys until the release signing config exists, so `flutter run --release` works.
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
