import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import org.gradle.api.tasks.compile.JavaCompile

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
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

// Ensure all subprojects (including plugins) compile with Java 11 and Kotlin jvmTarget 11
subprojects {
    // Configure Java compile tasks if present
    tasks.withType(org.gradle.api.tasks.compile.JavaCompile::class.java).configureEach {
        sourceCompatibility = "11"
        targetCompatibility = "11"
        // Rely on `sourceCompatibility` and `targetCompatibility` instead of `--release`.
        // Android Gradle Plugin manages the bootclasspath; do not set `options.release` here.
        // Suppress the specific warning about obsolete -source/-target options
        options.compilerArgs.add("-Xlint:-options")
    }

    // Configure Kotlin compile tasks if present
    tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
        kotlinOptions.jvmTarget = "11"
    }
}
