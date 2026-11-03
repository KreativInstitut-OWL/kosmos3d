import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing from android/key.properties (local, git-ignored) or the
// KOSMOS_KEYSTORE_* environment variables set by the release workflow.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
fun signingValue(property: String, env: String): String? =
    keyProperties.getProperty(property) ?: System.getenv(env)
val releaseStore = signingValue("storeFile", "KOSMOS_KEYSTORE_FILE")

android {
    namespace = "com.kosmos3d.kosmos3d"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.kosmos3d.kosmos3d"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStore != null) {
            create("release") {
                storeFile = file(releaseStore)
                storePassword = signingValue("storePassword", "KOSMOS_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "KOSMOS_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "KOSMOS_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Without a release key (local test builds) fall back to the debug key.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
        }
    }
}


flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.media3:media3-exoplayer:1.9.4")
    implementation("androidx.media3:media3-ui:1.9.4")
}
