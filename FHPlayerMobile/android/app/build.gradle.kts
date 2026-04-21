plugins {
    id("com.android.application")
    kotlin("android")
}

import java.util.Properties

val appVersionFile = layout.projectDirectory.file("../../../VERSION").asFile
if (!appVersionFile.exists()) {
    throw GradleException("Missing VERSION file at ${appVersionFile.absolutePath}")
}

val appVersion = appVersionFile.readText().trim()
val appVersionMatch = Regex("""^(\d+)\.(\d+)\.(\d+)$""").matchEntire(appVersion)
    ?: throw GradleException("VERSION must use major.minor.patch. Found: $appVersion")
val appVersionCode = appVersionMatch.destructured.let { (major, minor, patch) ->
    major.toInt() * 10000 + minor.toInt() * 100 + patch.toInt()
}
val defaultUpdateFeedUrl = "https://drive.google.com/file/d/1yB-YWh4vKyxgVeYKXK8raaCTsKBT70JV/view?usp=sharing"
val updateFeedUrl =
    providers.gradleProperty("fhplayerUpdateFeedUrl").orNull?.trim()?.takeIf { it.isNotBlank() }
        ?: providers.environmentVariable("FHPLAYER_UPDATE_FEED_URL").orNull?.trim()?.takeIf { it.isNotBlank() }
        ?: defaultUpdateFeedUrl

providers.gradleProperty("fhplayerBuildDir").orNull?.takeIf { it.isNotBlank() }?.let { buildDirOverride ->
    layout.buildDirectory.set(file(buildDirOverride))
}

val releaseSigningPropertiesFile =
    providers.gradleProperty("fhplayerReleaseSigningProperties")
        .orNull
        ?.takeIf { it.isNotBlank() }
        ?.let { file(it) }
        ?: layout.projectDirectory.file("release-signing.properties").asFile
val releaseSigningProperties =
    Properties().apply {
        if (releaseSigningPropertiesFile.exists()) {
            releaseSigningPropertiesFile.inputStream().use(::load)
        }
    }
val releaseSigningMode = providers.gradleProperty("fhplayerReleaseSigningMode").orNull?.trim()?.lowercase() ?: "auto"

fun resolveReleaseSigningValue(gradleKey: String, envKey: String): String? =
    providers.gradleProperty(gradleKey).orNull?.trim()?.takeIf { it.isNotBlank() }
        ?: providers.environmentVariable(envKey).orNull?.trim()?.takeIf { it.isNotBlank() }
        ?: releaseSigningProperties.getProperty(gradleKey)?.trim()?.takeIf { it.isNotBlank() }

val releaseStoreFilePath = resolveReleaseSigningValue("fhplayerReleaseStoreFile", "FHPLAYER_ANDROID_KEYSTORE_PATH")
val releaseStorePassword = resolveReleaseSigningValue("fhplayerReleaseStorePassword", "FHPLAYER_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = resolveReleaseSigningValue("fhplayerReleaseKeyAlias", "FHPLAYER_ANDROID_KEY_ALIAS")
val releaseKeyPassword = resolveReleaseSigningValue("fhplayerReleaseKeyPassword", "FHPLAYER_ANDROID_KEY_PASSWORD")
val hasReleaseSigning =
    releaseSigningMode != "skip" &&
        !releaseStoreFilePath.isNullOrBlank() &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

if (releaseSigningMode == "require" && !hasReleaseSigning) {
    throw GradleException(
        "Android release signing is required. Provide fhplayerReleaseStoreFile, " +
            "fhplayerReleaseStorePassword, fhplayerReleaseKeyAlias, and fhplayerReleaseKeyPassword " +
            "via Gradle properties, environment variables, or release-signing.properties.",
    )
}

android {
    namespace = "com.fhplayer.mobile"
    compileSdk = 36

    signingConfigs {
        if (hasReleaseSigning) {
            create("fhplayerRelease") {
                storeFile = file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "com.fhplayer.mobile"
        minSdk = 26
        targetSdk = 36
        versionCode = appVersionCode
        versionName = appVersion
        buildConfigField("String", "FHPLAYER_UPDATE_FEED_URL", "\"${updateFeedUrl.replace("\\", "\\\\").replace("\"", "\\\"")}\"")
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
        }
        getByName("release") {
            isMinifyEnabled = false
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("fhplayerRelease")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main") {
            assets.srcDir(layout.buildDirectory.dir("generated/fhplayer-assets"))
        }
        getByName("test") {
            resources.srcDir(layout.projectDirectory.dir("../../../tests/fixtures"))
        }
    }
}

val syncWebAssets by tasks.registering(Copy::class) {
    from(layout.projectDirectory.dir("../../../static"))
    include("index.html", "styles.css", "playlist-app.js")
    into(layout.buildDirectory.dir("generated/fhplayer-assets/www"))
}

tasks.named("preBuild").configure {
    dependsOn(syncWebAssets)
}

dependencies {
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation(kotlin("stdlib"))
    testImplementation("org.json:json:20240303")
    testImplementation(kotlin("test"))
}
