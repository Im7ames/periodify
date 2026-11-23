plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.im7ames.periodify"
    compileSdk = 36
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
dependencies { implementation("com.google.android.gms:play-services-wearable:20.0.1") }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
