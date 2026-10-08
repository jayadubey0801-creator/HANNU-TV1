plugins {
    id("com.android.application")
    id("kotlin-android") // 🔥 Added for explicit kotlin support 🔥
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.onyxtube"
    
    compileSdk = 35 // 🔥 36 abhi experimental hai, 35 stable hai 🔥
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions { // 🔥 Replaced compilerOptions with standard kotlinOptions 🔥
        jvmTarget = "17"
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

flutter {
    source = "../.."
}