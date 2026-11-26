plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.im7ames.periodify"
    compileSdk = 36
    sourceSets.getByName("main").apply {
        java.srcDir(rootProject.file("shared/kotlin"))
        res.srcDir(rootProject.file("shared/res"))
    }
    defaultConfig {
        applicationId = "com.im7ames.periodify"
        minSdk = 30
        targetSdk = 36
        versionCode = (System.getenv("BUILD_NUMBER") ?: "1").toInt()
        versionName = System.getenv("BUILD_VERSION") ?: "0.1.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    signingConfigs {
        create("release") {
            val path = System.getenv("ANDROID_KEYSTORE_PATH")
            if (path != null) storeFile = file(path)
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
    buildTypes { release { signingConfig = signingConfigs.getByName("release") } }
}
dependencies {
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
    implementation("androidx.core:core:1.17.0")
    implementation("androidx.wear.watchface:watchface-complications-data-source-ktx:1.2.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
