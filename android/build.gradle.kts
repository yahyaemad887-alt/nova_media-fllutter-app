import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

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
    project.evaluationDependsOn(":app")
}

// تعديل وتوحيد كل إعدادات المكتبات الفرعية (Java 17 + Kotlin 17 + Namespace + CompileSdk 36)
subprojects {
    fun applyFixes() {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            // 1. إجبار compileSdkVersion على 36 لكل المكتبات
            try {
                val setCompileSdkVersion = androidExt.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                setCompileSdkVersion.invoke(androidExt, 36)
            } catch (_: Exception) {}

            // 2. معالجة الـ namespace للمكتبات القديمة
            try {
                val getNamespace = androidExt.javaClass.getMethod("getNamespace")
                if (getNamespace.invoke(androidExt) == null) {
                    val setNamespace = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespace.invoke(androidExt, "com.example.${name.replace("-", "_")}")
                }
            } catch (_: Exception) {}

            // 3. إجبار JavaCompile في Android Extension على JavaVersion 17
            try {
                val getCompileOptions = androidExt.javaClass.getMethod("getCompileOptions")
                val compileOptions = getCompileOptions.invoke(androidExt)
                if (compileOptions != null) {
                    val setSource = compileOptions.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java)
                    val setTarget = compileOptions.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java)
                    setSource.invoke(compileOptions, JavaVersion.VERSION_17)
                    setTarget.invoke(compileOptions, JavaVersion.VERSION_17)
                }
            } catch (_: Exception) {}
        }

        // 4. إجبار مهام ترجمة Java على الإصدار 17
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = "17"
            targetCompatibility = "17"
        }
    }

    if (state.executed) {
        applyFixes()
    } else {
        afterEvaluate {
            applyFixes()
        }
    }

    // 5. إجبار مهام ترجمة Kotlin على JVM 17
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}