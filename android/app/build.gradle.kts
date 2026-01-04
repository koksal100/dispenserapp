import java.util.Properties
import java.io.FileInputStream

// 1. ADIM: key.properties dosyasını yükle
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    // Debug konsolunda bu yazıyı görürsen dosya yanlış yerdedir
    println("!!! UYARI: key.properties dosyası bulunamadı! Yol: ${keystorePropertiesFile.absolutePath}")
}

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.dispenserapp"
    // compileSdk 34 veya 35 önerilir (Google Play politikası için)
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    java {
        toolchain {
            languageVersion.set(JavaLanguageVersion.of(17))
        }
    }

    defaultConfig {
        applicationId = "com.example.dispenserapp"
        minSdk = flutter.minSdkVersion // flutter.minSdkVersion bazen hata verebilir, manuel 21 iyidir
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // 'create' yerine 'getByName("release")' mevcutsa onu kullanır, yoksa hata verir.
        // Flutter projelerinde 'release' genelde tanımlı değildir, o yüzden 'create' doğru.
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            val storeFileValue = keystoreProperties["storeFile"] as String?
            if (storeFileValue != null) {
                storeFile = file(storeFileValue)
            }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        getByName("release") {
            // Yukarıda oluşturduğumuz signingConfig'i bağla
            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
