pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }

            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) {
                "flutter.sdk not set in local.properties"
            }

            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // Flutter minimum requirement: Android Gradle Plugin 8.11.1
    id("com.android.application") version "8.11.1" apply false

    // Flutter minimum requirement: Kotlin 2.2.20
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false

    // Firebase / Google Sign-In support
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")