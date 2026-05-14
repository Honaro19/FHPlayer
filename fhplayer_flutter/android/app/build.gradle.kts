plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
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

val releaseSigningMode =
    providers.gradleProperty("fhplayerReleaseSigningMode")
        .orElse(providers.environmentVariable("FHPLAYER_ANDROID_SIGNING_MODE"))
        .orElse("auto")
        .get()
        .trim()
        .lowercase()

val releaseSigningPropertiesPath =
    providers.gradleProperty("fhplayerReleaseSigningProperties")
        .orElse(providers.environmentVariable("FHPLAYER_ANDROID_SIGNING_PROPERTIES_PATH"))
        .orElse("release-signing.properties")
        .get()
        .trim()

val releaseSigningPropertiesFile =
    if (releaseSigningPropertiesPath.isBlank()) {
        layout.projectDirectory.file("release-signing.properties").asFile
    } else {
        file(releaseSigningPropertiesPath)
    }

val releaseSigningProperties =
    Properties().apply {
        if (releaseSigningPropertiesFile.exists()) {
            releaseSigningPropertiesFile.inputStream().use(::load)
        }
    }

fun resolveReleaseSigningValue(gradleKey: String, envKey: String): String? =
    providers.gradleProperty(gradleKey).orNull?.trim()?.takeIf { it.isNotBlank() }
        ?: providers.environmentVariable(envKey).orNull?.trim()?.takeIf { it.isNotBlank() }
        ?: releaseSigningProperties.getProperty(gradleKey)?.trim()?.takeIf { it.isNotBlank() }

val releaseStoreFilePath =
    resolveReleaseSigningValue("fhplayerReleaseStoreFile", "FHPLAYER_ANDROID_KEYSTORE_PATH")
val releaseStorePassword =
    resolveReleaseSigningValue("fhplayerReleaseStorePassword", "FHPLAYER_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias =
    resolveReleaseSigningValue("fhplayerReleaseKeyAlias", "FHPLAYER_ANDROID_KEY_ALIAS")
val releaseKeyPassword =
    resolveReleaseSigningValue("fhplayerReleaseKeyPassword", "FHPLAYER_ANDROID_KEY_PASSWORD")

val hasReleaseSigning =
    !releaseStoreFilePath.isNullOrBlank() &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

if (releaseSigningMode !in setOf("auto", "require", "skip")) {
    throw GradleException("Unsupported fhplayerReleaseSigningMode: $releaseSigningMode")
}

if (releaseSigningMode == "require" && !hasReleaseSigning) {
    throw GradleException(
        "Android release signing is required. Provide fhplayerReleaseStoreFile, " +
            "fhplayerReleaseStorePassword, fhplayerReleaseKeyAlias, and fhplayerReleaseKeyPassword " +
            "via Gradle properties, environment variables, or release-signing.properties.",
    )
}

android {
    namespace = "com.fhplayer.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

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

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.fhplayer.mobile"
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = appVersionCode
        versionName = appVersion
    }

    buildTypes {
        release {
            signingConfig = when {
                releaseSigningMode == "skip" -> signingConfigs.getByName("debug")
                hasReleaseSigning -> signingConfigs.getByName("fhplayerRelease")
                else -> signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
