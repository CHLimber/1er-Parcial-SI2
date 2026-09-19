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
// Varios plugins de terceros (stripe_android, google_mlkit_commons, ...) no fijan un
// JVM target propio consistente: unos quedan en Java 11/17 con javac pero Kotlin
// termina usando el JDK que detecta Gradle en la maquina (25) -- eso rompe
// compileDebugKotlin con "Inconsistent JVM Target Compatibility". Se fuerza Java 17 y
// Kotlin 17 (via afterEvaluate, porque compileOptions ya viene finalizado si se toca
// antes de que el plugin de Android evalue el subproyecto) para todos los subproyectos.
// Tiene que registrarse ANTES de evaluationDependsOn(":app") de abajo: ese ya dispara
// la evaluacion de :app, y un afterEvaluate agregado despues llega tarde.
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

// `flutter build apk --release` dispara automaticamente "lintVital*" en cada
// submodulo de libreria antes de armar el release. stripe_android arrastra una
// dependencia opcional (com.stripe:stripe-android-issuing-push-provisioning,
// solo para Google Pay push provisioning con tarjetas fisicas, que esta app no
// usa) que a su vez pide play-services-tapandpay:18.8.0 -- esa version no esta
// disponible en ningun repositorio y rompe SOLO el analisis de lint, no la app.
// Se desactivan los lintVital* en todos los subproyectos para que el release
// no dependa de un artefacto de Google Play Services que no se usa. Tiene que
// registrarse ANTES de evaluationDependsOn(":app") de abajo, mismo motivo que
// el bloque de JVM target: ese ya dispara la evaluacion de :app.
subprojects {
    afterEvaluate {
        tasks.matching { it.name.startsWith("lintVital") }.configureEach {
            enabled = false
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
