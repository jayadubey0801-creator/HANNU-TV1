plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android") // 🔥 Yahan Kotlin explicitly add kiya taaki conflict na ho 🔥
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.onyxtube"
    compileSdk = 34 // 🔥 Isko 34 hi rakhna sabse stable hai 🔥
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.onyxtube"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    jvmToolchain(17) // 🔥 YAHI HAI MASTER FIX: Java 25 ki jagah strictly Java 17 force karega 🔥
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}