plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")

    // Flutter Gradle plugin हमेशा Android और Kotlin plugins के बाद होना चाहिए।
    id("dev.flutter.flutter-gradle-plugin")

    // यह तभी चाहिए जब android/app/google-services.json file मौजूद है।
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.onyxtube"

    // Flutter SDK की values use होंगी।
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.onyxtube"

        // Flutter template default minSdk use करता है।
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            // अभी release build debug key से sign होगा।
            // Play Store upload से पहले proper upload keystore add करना होगा।
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}