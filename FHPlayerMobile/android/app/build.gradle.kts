plugins {
    id("com.android.application")
    kotlin("android")
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
        versionCode = 1
        versionName = "0.1.0"
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
