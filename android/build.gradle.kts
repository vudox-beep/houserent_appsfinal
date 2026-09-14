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

// Avoid evaluationDependsOn(":app") — it deadlocks Gradle caches under AGP 9.
// Force compileSdk on Flutter plugins that omit it (e.g. shared_preferences_android).
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        try {
            val getCompileSdk = androidExt.javaClass.methods.firstOrNull {
                it.name == "getCompileSdk" && it.parameterCount == 0
            }
            val current = getCompileSdk?.invoke(androidExt) as? Int
            if (current == null || current < 36) {
                androidExt.javaClass.methods.firstOrNull {
                    it.name == "setCompileSdk" && it.parameterCount == 1
                }?.invoke(androidExt, 36)
            }
        } catch (_: Throwable) {
            // Plugin may use a different extension shape; ignore.
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
