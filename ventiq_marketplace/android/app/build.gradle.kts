 import java.io.FileInputStream
 import java.util.Properties
 import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

 val keystoreProperties = Properties()
 val keystorePropertiesFile = rootProject.file("key.properties")
 val hasKeystoreProperties = keystorePropertiesFile.exists()

 if (hasKeystoreProperties) {
     keystoreProperties.load(FileInputStream(keystorePropertiesFile))
 }

 val keystoreStoreFile = keystoreProperties.getProperty("storeFile")
 val keystoreStorePassword = keystoreProperties.getProperty("storePassword")
 val keystoreKeyAlias = keystoreProperties.getProperty("keyAlias")
 val keystoreKeyPassword = keystoreProperties.getProperty("keyPassword")

 val hasValidReleaseSigningConfig = hasKeystoreProperties &&
         !keystoreStoreFile.isNullOrBlank() &&
         !keystoreStorePassword.isNullOrBlank() &&
         !keystoreKeyAlias.isNullOrBlank() &&
         !keystoreKeyPassword.isNullOrBlank()

 val isReleaseBuild = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

android {
    namespace = "com.inventtia.marketplace"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
      // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
      applicationId = "com.inventtia.marketplace"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasValidReleaseSigningConfig) {
                storeFile = file(keystoreStoreFile!!)
                storePassword = keystoreStorePassword!!
                keyAlias = keystoreKeyAlias!!
                keyPassword = keystoreKeyPassword!!
            }
        }
    }

    buildTypes {
        release {
            if (isReleaseBuild && !hasValidReleaseSigningConfig) {
                throw GradleException(
                    "Missing android/key.properties (or it is incomplete). " +
                        "Create it to enable release signing."
                )
            }

            signingConfig = if (hasValidReleaseSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}
