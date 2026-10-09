import java.io.FileInputStream
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

/** The upload key lives outside the repo (never committed, never on CI as a
 * file) — this reads it from environment variables first, since that's what
 * a CI runner has, then falls back to `android/keystore.properties` (also
 * gitignored) for local release builds. If neither is present the release
 * build must still assemble — just unsigned — rather than fail, so
 * `assembleRelease` stays usable for local testing (R8 shrink, size checks)
 * without anyone needing the real key. */
data class ReleaseSigning(
    val storeFile: File,
    val storePassword: String,
    val keyAlias: String,
    val keyPassword: String,
)

fun loadReleaseSigning(): ReleaseSigning? {
    val env = System.getenv()
    val envStore = env["CHIPTUNE_KEYSTORE"]
    val envStorePassword = env["CHIPTUNE_KEYSTORE_PASSWORD"]
    val envKeyAlias = env["CHIPTUNE_KEY_ALIAS"]
    val envKeyPassword = env["CHIPTUNE_KEY_PASSWORD"]
    if (envStore != null && envStorePassword != null && envKeyAlias != null && envKeyPassword != null) {
        return ReleaseSigning(File(envStore), envStorePassword, envKeyAlias, envKeyPassword)
    }

    val propsFile = rootProject.file("keystore.properties")
    if (propsFile.exists()) {
        val props = Properties()
        FileInputStream(propsFile).use { props.load(it) }
        val storePath = props.getProperty("CHIPTUNE_KEYSTORE")
        val storePassword = props.getProperty("CHIPTUNE_KEYSTORE_PASSWORD")
        val keyAlias = props.getProperty("CHIPTUNE_KEY_ALIAS")
        val keyPassword = props.getProperty("CHIPTUNE_KEY_PASSWORD")
        if (storePath != null && storePassword != null && keyAlias != null && keyPassword != null) {
            return ReleaseSigning(rootProject.file(storePath), storePassword, keyAlias, keyPassword)
        }
    }

    logger.warn(
        "WARNING: no release signing config found (checked CHIPTUNE_KEYSTORE* env vars and " +
            "android/keystore.properties). Building an UNSIGNED release artifact — fine for " +
            "local R8/shrink testing, but it cannot be uploaded to Play Console as-is."
    )
    return null
}

/** Same convention as `Tools/stamp-build-info.sh` on iOS: a trailing `+` on
 * the hash means the tree had uncommitted changes when this was built, so
 * the hash names the nearest commit rather than the exact code. */
fun gitCommitHash(): String {
    // providers.exec rather than Project.exec, which Gradle deprecates for
    // removal in 9.0 and which blocks the configuration cache.
    return try {
        val hash = providers.exec {
            commandLine("git", "rev-parse", "--short", "HEAD")
        }.standardOutput.asText.get().trim()
        val dirty = providers.exec {
            commandLine("git", "status", "--porcelain")
        }.standardOutput.asText.get()
        hash + if (dirty.isBlank()) "" else "+"
    } catch (e: Exception) {
        "nogit"
    }
}

android {
    namespace = "dev.individuation.chiptune"
    compileSdk = 37

    defaultConfig {
        applicationId = "dev.individuation.chiptune"
        minSdk = 26
        targetSdk = 36
        // versionName stays put at 1.0 for the whole 1.0 release; versionCode
        // comes from CI (CHIPTUNE_VERSION_CODE), defaulting to 1 for local
        // builds so a plain `assembleRelease` here never needs the env var.
        versionCode = (System.getenv("CHIPTUNE_VERSION_CODE") ?: "1").toInt()
        versionName = "1.0"

        buildConfigField("String", "GIT_COMMIT_HASH", "\"${gitCommitHash()}\"")
        // The day of the build (UTC), for the menu's "Built ..." line. A day
        // rather than an instant, so BuildConfig only changes once a day.
        buildConfigField("String", "BUILD_DATE", "\"${LocalDate.now(ZoneOffset.UTC)}\"")

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    val releaseSigning = loadReleaseSigning()

    signingConfigs {
        if (releaseSigning != null) {
            create("release") {
                storeFile = releaseSigning.storeFile
                storePassword = releaseSigning.storePassword
                keyAlias = releaseSigning.keyAlias
                keyPassword = releaseSigning.keyPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (releaseSigning != null) {
                signingConfig = signingConfigs.getByName("release")
            }
            // else: left unsigned on purpose — see loadReleaseSigning()'s warning.
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    sourceSets {
        // The .chipsong and golden-WAV fixtures are shared with the iOS suite
        // and read in place, so both platforms test against the same bytes.
        getByName("test") {
            resources.directories.add("../../Tests/Fixtures")
        }
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            // kotlinx-coroutines-debug's agent data: only read when the
            // coroutine debugger attaches, which never happens on a device.
            excludes += "DebugProbesKt.bin"
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.kotlinx.coroutines.core)
    // Compose used to pull in 1.3.1, whose installer gives up on API 35+'s
    // ART ("unsupported ART version") — a sideloaded or non-Play install on
    // a current phone then ran every screen interpreted/JIT until background
    // dexopt got round to it. 1.4 writes the profile there too. Compose now
    // brings 1.4 itself; this keeps that floor if it ever stops.
    implementation(libs.androidx.profileinstaller)
    debugImplementation(libs.androidx.ui.tooling)

    testImplementation(libs.junit)
    // The real org.json implementation, for the JVM unit-test classpath only —
    // the Android platform jar used elsewhere ships org.json as stubs that
    // throw at runtime outside an instrumented/Robolectric test.
    testImplementation(libs.org.json)
}
