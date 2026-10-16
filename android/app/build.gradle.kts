import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Read .env file
val envFile = rootProject.file("../.env")
val envProperties = Properties()
if (envFile.exists()) {
    envFile.inputStream().use { envProperties.load(it) }
}

android {
    namespace = "com.truenyx.naviqandroid"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    // kotlinOptions is removed in newer Kotlin versions
    // See kotlin { jvmToolchain(11) } block below

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.truenyx.naviqandroid"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Inject Google Maps API Key from .env file
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = envProperties.getProperty("GOOGLE_MAPS_API_KEY", "")
    }

    buildTypes {
        release {
            val keystoreFile = rootProject.file("key.properties")
            if (keystoreFile.exists()) {
                val props = Properties()
                keystoreFile.inputStream().use { props.load(it) }
                signingConfig = signingConfigs.create("release") {
                    storeFile = rootProject.file(props.getProperty("storeFile"))
                    storePassword = props.getProperty("storePassword")
                    keyAlias = props.getProperty("keyAlias")
                    keyPassword = props.getProperty("keyPassword")
                }
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    // Play Billing Library — required to satisfy Google Play's minimum version requirement
    // (raised from v6.0.1 to v8.0.0 as of the Aug 31, 2026 policy deadline; pinned to 9.0.0
    // here to clear that bar with margin). Without this, Play Console flags the BILLING
    // permission as using an outdated Billing Library version and rejects new app updates.
    implementation("com.android.billingclient:billing:9.0.0")
    // Native GeofencingClient + FusedLocationProviderClient — used directly from Kotlin
    // (not just via the Geolocator plugin) so geofence transitions and periodic location
    // fixes are delivered by Play Services via PendingIntent/BroadcastReceiver, independent
    // of the Flutter engine or app process being alive (survives force-kill).
    implementation("com.google.android.gms:play-services-location:21.3.0")
    // WorkManager is already on the transitive classpath via workmanager_android, but only
    // as an `implementation` dependency there, which Gradle hides from this module — declare
    // it explicitly so LocationWatchdogWorker.kt can reference androidx.work.* directly.
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // JVM unit tests for the pure native tracking rules (TrackingRecovery.decide,
    // NearFencePolicy, GeofenceRegistrationDiff, NativeLocationPayload).
    testImplementation("junit:junit:4.13.2")
}
