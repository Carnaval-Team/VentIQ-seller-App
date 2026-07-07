allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    // Fuerza compileSdk >= 34 en todos los plugins para evitar conflictos de AAR metadata.
    // Debe registrarse ANTES de evaluationDependsOn, que dispara la evaluación de los subproyectos.
    afterEvaluate {
        extensions.findByType(com.android.build.api.dsl.LibraryExtension::class)?.let {
            it.compileSdk = 36
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
