plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.uuremote"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.uuremote"
        minSdk = 26
        targetSdk = 34
        versionCode = 633
        versionName = "4.48.1"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
