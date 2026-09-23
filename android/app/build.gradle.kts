import java.util.Properties

plugins {
    id("com.android.application")
    // Needed while android.builtInKotlin=false, see gradle.properties.
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "org.infai.optimise.mobile_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        // Off by default since AGP 9; the app label per build type is a resValue.
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.infai.optimise.mobile_app"
        resValue("string", "label", "\"OPTIMISE\"")
        minSdk = 28
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
        }
        getByName("debug") {
            applicationIdSuffix = ".debug"
            resValue("string", "label", "\"OPTI D\"")
        }
        getByName("profile") {
            resValue("string", "label", "\"OPTI P\"")
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
    implementation("org.reactivestreams:reactive-streams:1.0.4")
    implementation("io.reactivex.rxjava2:rxjava:2.2.21")
    implementation("com.google.code.gson:gson:2.14.0")
}
