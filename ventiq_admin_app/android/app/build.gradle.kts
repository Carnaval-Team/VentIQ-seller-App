plugins {
    id("com.android.application")
    id("kotlin-android")
    // Compose compiler: requerido por los widgets de pantalla de inicio (Jetpack Glance).
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.ventiq_admin_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Enable core library desugaring for flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.ventiq_admin_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        // Jetpack Glance (Home Screen Widgets) se escribe con Compose.
        compose = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    // Core library desugaring for flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // ── Home Screen Widgets (Jetpack Glance) ──────────────────────────────────
    // Los receivers de Glance extienden clases de home_widget
    // (HomeWidgetGlanceStateDefinition, HomeWidgetGlanceWidgetReceiver...), y el
    // classpath que inyecta Flutter no las expone al módulo :app. Se declara el
    // proyecto del plugin explícitamente; `:home_widget` lo incluye
    // FlutterAppPluginLoaderPlugin en settings.gradle.kts.
    implementation(project(":home_widget"))

    // glance-appwidget ya viene del plugin; se fija la versión y se añade
    // material3 para GlanceTheme/colores dinámicos.
    implementation("androidx.glance:glance-appwidget:1.1.1")
    implementation("androidx.glance:glance-material3:1.1.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("androidx.work:work-runtime-ktx:2.11.2")
}
