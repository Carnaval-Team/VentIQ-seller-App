allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // another_telephony 0.4.1 pins AGP 7.1.3, which was never published to Google Maven.
    buildscript {
        repositories {
            google()
            mavenCentral()
        }
        configurations.classpath {
            resolutionStrategy.eachDependency {
                if (requested.group == "com.android.tools.build" && requested.name == "gradle") {
                    useVersion("8.11.1")
                    because("Replace nonexistent AGP 7.1.3 from another_telephony")
                }
            }
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
