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

// The distribution channel, read from the same .env the app reads at runtime.
// Only "github" builds update themselves (AppUpdater._updateSupported), so only
// they declare the permission to install packages; see src/github.
// Only this one line is parsed, the way flutter_dotenv reads it: the last
// assignment wins (the workflow appends one), an inline comment and quotes are
// dropped. java.util.Properties would keep both, and fails on other values.
val dotEnvFile = rootProject.file("../.env")
val distributor = if (!dotEnvFile.exists()) null else dotEnvFile.readLines()
    .map { it.trim() }
    .lastOrNull { it.startsWith("DISTRIBUTOR=") }
    ?.substringAfter("=")
    ?.substringBefore(" #")
    ?.trim()
    ?.trim('"', '\'')

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

androidComponents {
    onVariants { variant ->
        if (distributor == "github") {
            variant.sources.manifests.addStaticManifestFile("src/github/AndroidManifest.xml")
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
