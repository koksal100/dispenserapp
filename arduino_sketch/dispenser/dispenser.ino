#include <Arduino.h>
#include <WiFi.h>
#include <AccelStepper.h>
#include <Firebase_ESP_Client.h>
#include "time.h"
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <Preferences.h> // KALICI HAFIZA İÇİN

// ==========================================
// --- AYARLAR ---
// ==========================================
#define DEVICE_NAME "MEDTRACK_PROTOTYPE"
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define API_KEY "AIzaSyCiHSuyWiHG_6BvRKtJmwBu3SBLaIsKmfk"
// DİKKAT: Flutter tarafındaki databaseURL ile burası AYNI olmalı
#define DATABASE_URL "https://smartmedicinedispenser-default-rtdb.europe-west1.firebasedatabase.app"

// --- VERİ KONTROL SIKLIKLARI (MULTITASKING İÇİN) ---
#define CONFIG_CHECK_INTERVAL 15000 // 15 Saniye (İlaç saatleri ve stok)
#define BUZZER_CHECK_INTERVAL 2000  // 2 Saniye (Ses çalma emri)

// --- NOTA FREKANSLARI ---
#define NOTE_C5  523
#define NOTE_D5  587
#define NOTE_E5  659
#define NOTE_F5  698
#define NOTE_G5  784
#define NOTE_A5  880
#define NOTE_B5  988
#define NOTE_C6  1047

// --- PINLER ---
#define M1_IN1 26
#define M1_IN2 25
#define M1_IN3 17
#define M1_IN4 16
#define M2_IN1 27
#define M2_IN2 14
#define M2_IN3 4
#define M2_IN4 13
#define M3_IN1 5
#define M3_IN2 23
#define M3_IN3 19
#define M3_IN4 18
#define SPEAKER_PIN 2
#define BUTTON_PIN 0 // BOOT Butonu (IO0)

// --- MOTOR ---
#define MOTOR_INTERFACE_TYPE AccelStepper::HALF4WIRE
#define ADIM_90_DERECE 1024
#define MAX_HIZ 1000.0
#define IVME 800.0

AccelStepper stepper1(MOTOR_INTERFACE_TYPE, M1_IN1, M1_IN3, M1_IN2, M1_IN4);
AccelStepper stepper2(MOTOR_INTERFACE_TYPE, M2_IN1, M2_IN3, M2_IN2, M2_IN4);
AccelStepper stepper3(MOTOR_INTERFACE_TYPE, M3_IN1, M3_IN3, M3_IN2, M3_IN4);

// --- FIREBASE & SİSTEM ---
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;
String DEVICE_ID;
Preferences preferences; // Kalıcı hafıza nesnesi

const char* ntpServer = "pool.ntp.org";
const long  gmtOffset_sec = 10800;
const int   daylightOffset_sec = 0;

#define MAX_ALARM 10
struct AlarmZamani { int saat = -1; int dakika = -1; bool verildi = false; };
// YENİ: pillCount (ilaç sayacı) eklendi
struct Bolme { bool aktif = false; int alarmSayisi = 0; int pillCount = 0; AlarmZamani alarmlar[MAX_ALARM]; };
Bolme bolmeler[3];

// --- ZAMANLAYICILAR ---
unsigned long lastConfigCheck = 0;
unsigned long lastBuzzerCheck = 0;

bool bleMode = false;

// --- BAĞLANTI KONTROLÜ ---
unsigned long wifiKopmaZamani = 0;
unsigned long wifiBaglanmaZamani = 0;
bool internetVarMi = false;

// --- BLE ---
BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;
String receivedSSID = "";
String receivedPassword = "";
bool credentialsReceived = false;

// --- SES EFEKTİ ---
unsigned long lastBleBeepTime = 0;
bool bleConnectEvent = false;

// --- BUTON KONTROL ---
volatile int pressCount = 0;
volatile unsigned long lastPressTime = 0;
volatile bool resetTriggered = false;

// --- PROTOTİPLER ---
void ayarlaMotor(AccelStepper &stepper);
void verileriGetir(); // Config verileri (15 sn)
void buzzerKontrol(); // Ses verisi (2 sn)
void hafizadanYukle(); 
void hafizayaKaydet(int bolmeIndex); 
bool veriDegistiMi(int i, bool yeniAktif, int yeniCount, int yeniAlarmSayisi, int yeniSaatler[], int yeniDakikalar[]); // YENİ: Gereksiz yazmayı önler
void saatKontrolu();
void ilacVer(int motorNo);
void sesCikar(int sureMs);
void baslatBLE();
void durdurBLE();
void wifiBaglan(String ssid, String pass);
void firebaseBaslat();
void fabrikaAyarlarinaDon();
void playMelody(); 
void playTone(int frequency, int duration);

// ==========================================
// --- INTERRUPT (BUTON) ---
// ==========================================
void IRAM_ATTR buttonISR() {
  unsigned long now = millis();
  if (now - lastPressTime > 100) {
    if (now - lastPressTime > 1000) pressCount = 0;
    pressCount++;
    lastPressTime = now;
    if (pressCount >= 3) {
      resetTriggered = true;
      pressCount = 0;
    }
  }
}

// --- BLE CALLBACKS ---
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      bleConnectEvent = true;
    };
    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      if (bleMode) { delay(500); pServer->getAdvertising()->start(); }
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value = pCharacteristic->getValue().c_str();
      if (value.length() > 0) {
        FirebaseJson json; FirebaseJsonData d_ssid, d_pass;
        json.setJsonData(value);
        json.get(d_ssid, "s"); json.get(d_pass, "p");
        if (d_ssid.success && d_pass.success) {
           receivedSSID = d_ssid.stringValue; receivedPassword = d_pass.stringValue;
           credentialsReceived = true;
        }
      }
    }
};

void setup() {
  Serial.begin(115200);
  pinMode(SPEAKER_PIN, OUTPUT);
  digitalWrite(SPEAKER_PIN, LOW);
  
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(BUTTON_PIN), buttonISR, FALLING);

  ayarlaMotor(stepper1); ayarlaMotor(stepper2); ayarlaMotor(stepper3);

  // --- HAFIZA BAŞLATMA ---
  preferences.begin("meddata", false); // "meddata" namespace'i altında çalış
  hafizadanYukle(); // Önce hafızadaki eski ayarları yükle (Offline çalışabilmek için)

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.persistent(true); 
  
  delay(100);
  
  Serial.print("MAC Adresi Okunuyor");
  String geciciMAC = WiFi.macAddress();
  int deneme = 0;
  while ((geciciMAC == "00:00:00:00:00:00" || geciciMAC == "") && deneme < 5) {
      delay(500); Serial.print(".");
      WiFi.mode(WIFI_STA); geciciMAC = WiFi.macAddress();
      deneme++;
  }
  DEVICE_ID = geciciMAC;
  Serial.println("\nDevice ID: " + DEVICE_ID);

  WiFi.begin();
  Serial.println("WiFi baslatildi (Kayitli ag deneniyor)...");
  
  int waitTime = 0;
  while(WiFi.status() != WL_CONNECTED && waitTime < 10) {
    delay(500); Serial.print("."); waitTime++;
  }

  if (WiFi.status() == WL_CONNECTED) {
     Serial.println("\nBaslangic Baglantisi OK! (Online)");
     internetVarMi = true;
     sesCikar(1000);
     firebaseBaslat();
     verileriGetir(); // İnternet varsa hemen güncel veriyi çek
  } else {
    Serial.println("\nBaslangicta WiFi yok. Offline Mod (Hafiza) veya BLE ile devam ediliyor.");
    baslatBLE();
  }
}

void loop() {
  if (resetTriggered) {
    resetTriggered = false;
    fabrikaAyarlarinaDon();
  }

  if (bleConnectEvent) {
      Serial.println("Cihaz Baglandi! (Ses Caliniyor)");
      sesCikar(100); delay(50); sesCikar(100); delay(50); sesCikar(100);
      bleConnectEvent = false;
  }

  if (bleMode && !deviceConnected) {
      if (millis() - lastBleBeepTime > 2000) {
          sesCikar(50);
          lastBleBeepTime = millis();
      }
  }

  bool suankiDurum = (WiFi.status() == WL_CONNECTED);

  if (suankiDurum) {
      wifiKopmaZamani = 0;
      if (!internetVarMi) {
          if (wifiBaglanmaZamani == 0) wifiBaglanmaZamani = millis();
          if (millis() - wifiBaglanmaZamani > 3000) {
              Serial.println(">>> Internet Kararli Sekilde Geri Geldi!");
              internetVarMi = true;
              sesCikar(1000);
              
              if (bleMode) {
                  Serial.println("BLE Kapatiliyor...");
                  durdurBLE();
                  delay(500);
                  firebaseBaslat();
                  verileriGetir(); // Bağlantı gelir gelmez güncelle
              }
          }
      }
  }
  else {
      wifiBaglanmaZamani = 0;
      if (internetVarMi) {
          if (wifiKopmaZamani == 0) wifiKopmaZamani = millis();
          if (millis() - wifiKopmaZamani > 5000) {
              Serial.println("!!! Internet Koptu (Offline Mod Devrede) !!!");
              internetVarMi = false;
              if (!bleMode) { baslatBLE(); }
          }
      } else {
         if (!bleMode && (millis() - wifiKopmaZamani > 5000)) { baslatBLE(); }
      }
  }

  // --- MULTITASKING (Eş Zamanlı Görevler) ---
  if (internetVarMi && Firebase.ready()) {
      unsigned long currentMillis = millis();

      // Görev 1: Config Verilerini Çek (15 Saniye)
      if (currentMillis - lastConfigCheck > CONFIG_CHECK_INTERVAL) {
        verileriGetir();
        lastConfigCheck = currentMillis;
      }

      // Görev 2: Buzzer Kontrolü (2 Saniye)
      if (currentMillis - lastBuzzerCheck > BUZZER_CHECK_INTERVAL) {
        buzzerKontrol();
        lastBuzzerCheck = currentMillis;
      }
  }

  // Saat kontrolü internet olsun olmasın çalışır (RTC/Internal Clock)
  saatKontrolu();
  
  // BLE şifre kontrolü
  if (!internetVarMi && credentialsReceived) {
      Serial.println("BLE'den yeni sifre geldi...");
      wifiBaglan(receivedSSID, receivedPassword);
      credentialsReceived = false;
  }
}

// ==========================================================
// --- YENİ: HAFIZA YÖNETİMİ ---
// ==========================================================

void hafizayaKaydet(int i) {
  // Namespace: meddata
  String p = "b" + String(i);
  
  preferences.putBool((p + "_akt").c_str(), bolmeler[i].aktif);
  preferences.putInt((p + "_cnt").c_str(), bolmeler[i].pillCount);
  preferences.putInt((p + "_len").c_str(), bolmeler[i].alarmSayisi);
  
  for(int k=0; k < bolmeler[i].alarmSayisi; k++) {
    String a = p + "_a" + String(k);
    preferences.putInt((a + "_h").c_str(), bolmeler[i].alarmlar[k].saat);
    preferences.putInt((a + "_m").c_str(), bolmeler[i].alarmlar[k].dakika);
  }
}

void hafizadanYukle() {
  Serial.println("Hafizadan veri okunuyor...");
  for(int i=0; i<3; i++) {
    String p = "b" + String(i);
    // Varsayılan değerler ikinci parametredir
    bolmeler[i].aktif = preferences.getBool((p + "_akt").c_str(), false);
    bolmeler[i].pillCount = preferences.getInt((p + "_cnt").c_str(), 0);
    bolmeler[i].alarmSayisi = preferences.getInt((p + "_len").c_str(), 0);
    
    if(bolmeler[i].alarmSayisi > MAX_ALARM) bolmeler[i].alarmSayisi = MAX_ALARM;
    
    for(int k=0; k < bolmeler[i].alarmSayisi; k++) {
      String a = p + "_a" + String(k);
      bolmeler[i].alarmlar[k].saat = preferences.getInt((a + "_h").c_str(), -1);
      bolmeler[i].alarmlar[k].dakika = preferences.getInt((a + "_m").c_str(), -1);
      bolmeler[i].alarmlar[k].verildi = false; 
    }
  }
}

// ==========================================================
// --- FONKSİYONLAR ---
// ==========================================================

void baslatBLE() {
  if (bleMode) return;
  bleMode = true;
  BLEDevice::init(DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_WRITE  |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );

  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setCallbacks(new MyCallbacks());
  pService->start();
  
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("BLE Yayini Basladi");
}

void wifiBaglan(String ssid, String pass) {
  Serial.print("Yeni Ag Deneniyor: "); Serial.println(ssid);
  
  if (deviceConnected && pCharacteristic != NULL) {
      pCharacteristic->setValue("TRYING");
      pCharacteristic->notify();
  }

  WiFi.disconnect(true);
  delay(1000);
  WiFi.mode(WIFI_OFF);
  delay(100);
  WiFi.mode(WIFI_STA);
  delay(500);

  WiFi.begin(ssid.c_str(), pass.c_str());

  int count = 0;
  while (WiFi.status() != WL_CONNECTED && count < 40) {
    delay(500); Serial.print("."); count++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nBaglandi!");
    sesCikar(1000);
    wifiBaglanmaZamani = millis();

    if (deviceConnected && pCharacteristic != NULL) {
       Serial.println("Telefona SUCCESS gonderiliyor...");
       pCharacteristic->setValue("SUCCESS");
       pCharacteristic->notify();
       delay(2000); 
    }
    
  } else {
    Serial.println("\nBaglanamadi.");
    if (deviceConnected && pCharacteristic != NULL) {
       Serial.println("Telefona FAIL gonderiliyor...");
       pCharacteristic->setValue("FAIL");
       pCharacteristic->notify();
    }
  }
}

void firebaseBaslat() {
     Serial.println("Firebase Baslatiliyor...");
     configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
     
     config.api_key = API_KEY;
     config.database_url = DATABASE_URL;

     fbdo.setBSSLBufferSize(4096, 1024);

     config.timeout.wifiReconnect = 10000;
     config.timeout.socketConnection = 10000;
     config.timeout.sslHandshake = 20000;
     config.timeout.serverResponse = 10000;

     if (!Firebase.ready()) {
        Firebase.signUp(&config, &auth, "", "");
        Firebase.begin(&config, &auth);
        Firebase.reconnectWiFi(true);
     }
}

void durdurBLE() {
  if (!bleMode) return;
  BLEDevice::deinit(true);
  bleMode = false;
  Serial.println("BLE Durduruldu.");
}

void fabrikaAyarlarinaDon() {
    Serial.println("\n!!! RESET ISLEMI BASLATILDI !!!");
    sesCikar(100); delay(100); sesCikar(100); delay(100); sesCikar(100);
    
    Serial.println("Hafiza ve WiFi Siliniyor...");
    preferences.clear(); // Kalıcı hafızayı temizle
    WiFi.disconnect(true, true); 
    
    delay(1000);
    
    Serial.println("Cihaz Yeniden Baslatiliyor...");
    sesCikar(1000);
    ESP.restart();
}

// --- BUZZER KONTROLÜ (2 Saniyede Bir Çalışır) ---
void buzzerKontrol() {
  String path = "/dispensers/" + DEVICE_ID + "/buzzer";
  // getBool veriyi daha hızlı çeker ve daha az veri harcar
  if (Firebase.RTDB.getBool(&fbdo, path)) {
    if (fbdo.boolData()) {
        Serial.println("\n>>> 🔔 MELODİ: Buzzer Tetiklendi! <<<");
        playMelody(); 
        // Sesi çaldıktan sonra Firebase'deki değeri false yapıyoruz ki sürekli çalmasın
        Firebase.RTDB.setBool(&fbdo, path, false);
    }
  }
}

// --- CONFİG VERİLERİ (15 Saniyede Bir Çalışır) ---
void verileriGetir() {
  String path = "/dispensers/" + DEVICE_ID + "/config";
  
  if (Firebase.RTDB.getJSON(&fbdo, path)) {
    FirebaseJson *json = fbdo.jsonObjectPtr();
    FirebaseJsonData result;
    for (int i = 0; i < 3; i++) {
      String sectionKey = "section_" + String(i);
      json->get(result, sectionKey);
      if (result.success) {
        FirebaseJson sectionJson; result.getJSON(sectionJson);
        
        // Geçici Değişkenler (Kıyaslama için)
        bool yeniAktif = false;
        int yeniCount = 0;
        int yeniAlarmSayisi = 0;
        int yeniSaatler[MAX_ALARM];
        int yeniDakikalar[MAX_ALARM];

        // Verileri Oku
        FirebaseJsonData d_aktif; sectionJson.get(d_aktif, "isActive");
        if(d_aktif.success) yeniAktif = d_aktif.boolValue;

        FirebaseJsonData d_count; sectionJson.get(d_count, "pillCount");
        if(d_count.success) yeniCount = d_count.intValue;

        FirebaseJsonData d_schedule; sectionJson.get(d_schedule, "schedule");
        if (d_schedule.success && d_schedule.type == "array") {
          FirebaseJsonArray myArr; myArr.setJsonArrayData(d_schedule.to<String>());
          yeniAlarmSayisi = myArr.size();
          if(yeniAlarmSayisi > MAX_ALARM) yeniAlarmSayisi = MAX_ALARM;
          for (size_t k = 0; k < yeniAlarmSayisi; k++) {
            FirebaseJsonData timeData; myArr.get(timeData, k);
            FirebaseJson timeObj; timeData.getJSON(timeObj);
            FirebaseJsonData h, m; timeObj.get(h, "h"); timeObj.get(m, "m");
            yeniSaatler[k] = h.intValue;
            yeniDakikalar[k] = m.intValue;
          }
        } else { yeniAlarmSayisi = 0; }

        // --- ÖNEMLİ: DEĞİŞİKLİK KONTROLÜ ---
        // Sadece veri gerçekten değiştiyse hafızaya yaz (ESP32 ömrünü korur)
        if (veriDegistiMi(i, yeniAktif, yeniCount, yeniAlarmSayisi, yeniSaatler, yeniDakikalar)) {
           Serial.printf("\n[GUNCELLEME] Bolme %d degisti. Hafizaya yaziliyor...\n", i+1);
           
           bolmeler[i].aktif = yeniAktif;
           bolmeler[i].pillCount = yeniCount;
           bolmeler[i].alarmSayisi = yeniAlarmSayisi;
           
           for(int k=0; k < yeniAlarmSayisi; k++) {
              // Saat değiştiyse "verildi" bilgisini sıfırla
              if(bolmeler[i].alarmlar[k].saat != yeniSaatler[k] || bolmeler[i].alarmlar[k].dakika != yeniDakikalar[k]) {
                 bolmeler[i].alarmlar[k].verildi = false;
              }
              bolmeler[i].alarmlar[k].saat = yeniSaatler[k];
              bolmeler[i].alarmlar[k].dakika = yeniDakikalar[k];
           }
           hafizayaKaydet(i);
        }
      }
    }
    Serial.println("Veriler senkronize edildi.");
  } else {
      if (String(fbdo.errorReason()).indexOf("timed out") == -1) {
          Serial.print("Hata: ");
          Serial.println(fbdo.errorReason());
      }
  }
}

// Yardımcı Fonksiyon: Veri değişti mi?
bool veriDegistiMi(int i, bool yeniAktif, int yeniCount, int yeniAlarmSayisi, int yeniSaatler[], int yeniDakikalar[]) {
    if (bolmeler[i].aktif != yeniAktif) return true;
    if (bolmeler[i].pillCount != yeniCount) return true;
    if (bolmeler[i].alarmSayisi != yeniAlarmSayisi) return true;
    
    for(int k=0; k < yeniAlarmSayisi; k++) {
        if (bolmeler[i].alarmlar[k].saat != yeniSaatler[k]) return true;
        if (bolmeler[i].alarmlar[k].dakika != yeniDakikalar[k]) return true;
    }
    return false;
}

void saatKontrolu() {
  struct tm timeinfo;
  // Offline modda eğer cihaz kapanıp açıldıysa saat yanlış olabilir.
  // Ancak cihaz çalışır durumdayken internet koparsa internal clock (millis tabanlı) devam eder.
  if (!getLocalTime(&timeinfo)) return;
  int sa = timeinfo.tm_hour; int dk = timeinfo.tm_min; int sn = timeinfo.tm_sec;

  static int sonYazilanDakika = -1;
  if (dk != sonYazilanDakika) {
      Serial.printf("[Sistem Calisiyor] Saat: %02d:%02d\n", sa, dk);
      sonYazilanDakika = dk;
  }

  if (sa == 0 && dk == 0 && sn < 5) {
    for(int i=0; i<3; i++) for(int k=0; k < MAX_ALARM; k++) bolmeler[i].alarmlar[k].verildi = false;
  }
  
  for (int i = 0; i < 3; i++) {
    if (bolmeler[i].aktif) {
      for (int k = 0; k < bolmeler[i].alarmSayisi; k++) {
        if (!bolmeler[i].alarmlar[k].verildi) {
          if (bolmeler[i].alarmlar[k].saat == sa && bolmeler[i].alarmlar[k].dakika == dk && sn < 5) {
            Serial.println("\n***********************************");
            Serial.printf(">>> 💊 İLAÇ VAKTİ! BOLME %d MOTORU DONUYOR... <<<\n", i+1);
            Serial.println("***********************************\n");
            ilacVer(i + 1);
            bolmeler[i].alarmlar[k].verildi = true;
          }
        }
      }
    }
  }
}

void ilacVer(int motorNo) {
  int idx = motorNo - 1;

  // 1. Motoru Hareket Ettir
  AccelStepper *motor;
  if (motorNo == 1) motor = &stepper1; else if (motorNo == 2) motor = &stepper2; else motor = &stepper3;
  motor->enableOutputs(); sesCikar(500);
  motor->move(ADIM_90_DERECE);
  while (motor->distanceToGo() != 0) motor->run();
  motor->disableOutputs(); sesCikar(1000);

  // 2. İlaç Sayacını Düşür
  if (bolmeler[idx].pillCount > 0) {
    bolmeler[idx].pillCount--;
    Serial.printf("Bolme %d kalan ilac: %d\n", motorNo, bolmeler[idx].pillCount);
  } else {
    Serial.printf("Bolme %d sayaci zaten 0!\n", motorNo);
  }

  // 3. Güncel Durumu Hafızaya Kaydet (Offline için kritik)
  hafizayaKaydet(idx);

  // 4. İnternet varsa Firebase'i Güncelle ve Logla
  if (internetVarMi && Firebase.ready()) {
    // Sayacı güncelle
    String path = "/dispensers/" + DEVICE_ID + "/config/section_" + String(idx) + "/pillCount";
    Firebase.RTDB.setInt(&fbdo, path, bolmeler[idx].pillCount);
    
    // Log at
    String logPath = "/dispensers/" + DEVICE_ID + "/logs";
    FirebaseJson logJson;
    logJson.set("type", "auto_dispense");
    logJson.set("section", idx);
    logJson.set("timestamp", (int)time(NULL)); // UNIX timestamp
    Firebase.RTDB.pushJSON(&fbdo, logPath, &logJson);
  }
}

void playTone(int frequency, int durationMs) {
  long period = 1000000 / frequency;
  long cycles = (durationMs * 1000) / period;
  for (long i = 0; i < cycles; i++) {
    digitalWrite(SPEAKER_PIN, HIGH); delayMicroseconds(period / 2);
    digitalWrite(SPEAKER_PIN, LOW); delayMicroseconds(period / 2);
  }
}

void playMelody() {
  int notes[] = {NOTE_C5, NOTE_E5, NOTE_G5, NOTE_C6, NOTE_G5, NOTE_C6};
  int durations[] = {150, 150, 150, 300, 150, 600};
  for (int i = 0; i < 6; i++) {
    playTone(notes[i], durations[i]);
    delay(50);
  }
}

void sesCikar(int sureMs) {
  unsigned long start = millis();
  while(millis() - start < sureMs) {
    digitalWrite(SPEAKER_PIN, HIGH); delayMicroseconds(500);
    digitalWrite(SPEAKER_PIN, LOW); delayMicroseconds(500);
  }
}

void ayarlaMotor(AccelStepper &stepper) { stepper.setMaxSpeed(MAX_HIZ); stepper.setAcceleration(IVME); }