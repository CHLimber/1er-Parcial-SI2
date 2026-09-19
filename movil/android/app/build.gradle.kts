plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "bo.fashionstore.fashionstore_movil"
    compileSdk = flutter.compileSdkVersion
    // El NDK que piden los plugins nativos (url_launcher_android, camera, mlkit). Es el que
    // Gradle usa para hacer `strip` de las .so del APK de release: conviene que sea
    // exactamente este y no uno mas nuevo "compatible". Si otra maquina no lo tiene
    // instalado, se instala desde el SDK Manager en vez de cambiar el numero de aca.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "bo.fashionstore.fashionstore_movil"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // AGP 9 activa R8 por defecto en release (AGP 8 no lo hacia). Con R8 encendido
            // el APK instalaba pero moria antes del primer frame:
            //
            //   java.lang.RuntimeException: Unable to get provider androidx.startup.InitializationProvider
            //   Caused by: Failed to create an instance of androidx.work.impl.WorkDatabase
            //
            // WorkManager entra por google_mlkit_pose_detection (CU16) y su base Room se
            // instancia por reflexion (`WorkDatabase_Impl`); R8 le cambia el nombre y la
            // clase deja de existir, asi que el ContentProvider de androidx.startup explota
            // en el arranque del proceso. Mantener R8 exigiria reglas -keep para Room,
            // WorkManager, ML Kit y Stripe, y cada plugin nuevo que use reflexion seria otra
            // bomba de tiempo que solo se nota en release. El codigo Dart (donde vive la
            // logica) ya viaja compilado en libapp.so, y el dex es una fraccion minima del
            // APK frente a las .so, asi que apagarlo no cambia el tamanio en la practica:
            // para eso se compila con --split-per-abi (ver movil/README.md).
            isMinifyEnabled = false
            isShrinkResources = false
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
