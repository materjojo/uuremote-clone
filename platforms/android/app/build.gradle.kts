plugins {
    id("com.android.application")
    id("com.google.protobuf") version "0.9.4"
}

dependencies {
    implementation("com.google.protobuf:protobuf-javalite:3.25.3")
}

protobuf {
    protoc {
        artifact = "com.google.protobuf:protoc:3.25.3"
    }
    generateProtoTasks {
        all().forEach { task ->
            task.builtins {
                create("java") {
                    option("lite")
                }
            }
        }
    }
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

    sourceSets["main"].proto.srcDir("../../proto/gv_pb")
}
