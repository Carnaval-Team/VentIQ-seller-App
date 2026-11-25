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
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

// Los plugins fijan AGP 8.0.2 / 8.2.0 en su buildscript. Si esa resolución falla,
// el plugin de Android no se aplica y Flutter lo reporta como un fallo de AGP 9.
gradle.beforeProject {
    buildscript.configurations.configureEach {
        if (name != "classpath") return@configureEach
        resolutionStrategy.eachDependency {
            if (requested.group == "com.android.tools.build" && requested.name == "gradle") {
                useVersion("8.9.1")
                because("Align plugin AGP with the app; older pins are not resolvable")
            }
        }
    }
}

include(":app")
