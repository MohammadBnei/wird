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
        // what should be handed to a phone. An ndk.abiFilters here is a real
        // alternative and would win over the plugin's own, which is set in
        // apply() before this block is read (FlutterPlugin.configureAbis ->
        // configureAbiWithoutSplits). It is not additive to the split, though:
        // AGP fails with "in ndk abiFilters cannot be present when splits abi
        // filters are set". And a single APK listing arm64-v8a and
        // armeabi-v7a keeps a 32-bit phone buildable while still putting the
        // 32-bit libonnxruntime.so on every 64-bit phone, i.e. most of the
        // weight above; listing arm64-v8a alone drops that but leaves a
        // 32-bit phone unbuildable without editing this file. The split is
        // the option that gives each phone its own ABI only and keeps both.
        //
        // The split also decides the version code, which is not obvious and
        // costs a walk when it bites. Flutter's own Gradle plugin mints
        // `abi * 1000 + pubspec build number` for each split APK — arm64 is 2,
        // so 1.0.0+1 installs as 2001 (FlutterPluginConstants.ABI_VERSION,
        // FlutterPlugin.kt's applicationVariants.all block). A debug build
        // keeps the plain 1, so `flutter run` over a release APK fails with
        // INSTALL_FAILED_VERSION_DOWNGRADE and answers by uninstalling, which
        // takes the app's data and 72.7 MB of recogniser weights with it. A
        // walk build therefore passes `-P force-version-code-ignoring-abi=true`
        // (FlutterPluginUtils.shouldForceVersionCodeIgnoringAbi): the ABI
        // offset is skipped, the split stays, and release and debug are both
        // versionCode 1, so each installs over the other.
        //
        // ponytail: a flag at the command line, not a block in this file. The
        // plugin's override runs in afterEvaluate through the legacy
        // applicationVariants API, i.e. after androidComponents.onVariants, so
        // an override written here would be clobbered on exactly the
        // --split-per-abi build this comment recommends.
        // Ceiling: the flag is for development only. Play requires a distinct
        // version code per split APK — the reason the offsets exist at all —
        // so shipping there means dropping the flag and bumping the pubspec
        // build number above the last release's offset code, or `adb install -d`.
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
