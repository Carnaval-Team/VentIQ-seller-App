pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
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
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

// another_telephony 0.4.1 requests AGP 7.1.3 (never published). Rewrite before its buildscript resolves.
gradle.beforeProject {
    if (name != "another_telephony") return@beforeProject
    buildscript.configurations.configureEach {
        if (name != "classpath") return@configureEach
        resolutionStrategy.eachDependency {
            if (requested.group == "com.android.tools.build" && requested.name == "gradle") {
                useVersion("8.11.1")
                because("Replace nonexistent AGP 7.1.3 from another_telephony")
            }
        }
    }
}
