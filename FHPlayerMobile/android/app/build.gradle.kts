plugins {
    id("com.android.application")
    kotlin("android")
}

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

providers.gradleProperty("fhplayerBuildDir").orNull?.takeIf { it.isNotBlank() }?.let { buildDirOverride ->
    layout.buildDirectory.set(file(buildDirOverride))
}

android {
    namespace = "com.fhplayer.mobile"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.fhplayer.mobile"
        minSdk = 26
        targetSdk = 36
        versionCode = appVersionCode
        versionName = appVersion
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
        }
        getByName("release") {
            isMinifyEnabled = false
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

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main") {
            assets.srcDir(layout.buildDirectory.dir("generated/fhplayer-assets"))
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
    implementation(kotlin("stdlib"))
}
