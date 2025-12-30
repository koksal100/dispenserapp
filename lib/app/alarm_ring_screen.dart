import 'dart:io';
import 'dart:ui'; // ImageFilter için
import 'package:alarm/alarm.dart';
import 'package:dispenserapp/main.dart'; // globalAlarmState'e erişmek için
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; // EKRANIN AÇIK KALMASI İÇİN

class AlarmRingScreen extends StatefulWidget {
  final AlarmSettings alarmSettings;

  const AlarmRingScreen({super.key, required this.alarmSettings});

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen> {
  static const platform = MethodChannel('com.example.dispenserapp/lock_control');

  // --- RENK PALETİ ---
  static const Color colTurquoise = Color(0xFF36C0A6);
  static const Color colSkyBlue = Color(0xFF1D8AD6);
  static const Color colDeepSea = Color(0xFF0F5191);

  @override
  void initState() {
    super.initState();
    // Ekranın kapanmasını engelle
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _handleStop() async {
    // 1. Alarmı sustur
    await Alarm.stop(widget.alarmSettings.id);

    // 2. Kilit ekranı iznini kapat
    try {
      await platform.invokeMethod('hideFromLockScreen');
    } catch (e) {
      debugPrint("Error hiding from lock screen: $e");
    }

    // 3. EKRANI KAPATMA MANTIĞI (Overlay'i kaldır)
    // Global değişkeni null yapınca builder yeniden tetiklenir ve bu ekran kaybolur.
    globalAlarmState.value = null;

    // 4. Eğer Android'de kilitliysek uygulamayı tamamen alta at (veya kapat)
    // ki kullanıcı kilit ekranını görsün.
    if (Platform.isAndroid) {
      // SystemNavigator.pop() uygulamayı öldürür.
      // Eğer uygulamanın açık kalmasını istiyorsan bunu kaldırabilirsin
      // ama kilit ekranı güvenliği için önerilir.
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // MaterialApp içinde Overlay olarak çalıştığı için Scaffold şart.
    // PopScope: Geri tuşunu engelle.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          children: [
            // 1. ARKA PLAN (GRADYAN)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colDeepSea, colSkyBlue, colTurquoise],
                  stops: [0.2, 0.6, 1.0],
                ),
              ),
            ),

            // Hafif Arka Plan Deseni
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),

            // 2. İÇERİK (ORTALANMIŞ)
            SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [

                    // --- ÜST KISIM: SAAT ---
                    StreamBuilder(
                      stream: Stream.periodic(const Duration(seconds: 1)),
                      builder: (context, snapshot) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}",
                              style: const TextStyle(
                                fontSize: 90,
                                fontWeight: FontWeight.w200,
                                color: Colors.white,
                                height: 1,
                                fontFamily: 'Roboto',
                                decoration: TextDecoration.none, // Overlay'de textDecoration şart olabilir
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              DateFormat('EEEE, d MMMM', context.locale.toString()).format(DateTime.now()),
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white.withOpacity(0.8),
                                fontWeight: FontWeight.w400,
                                letterSpacing: 1.2,
                                decoration: TextDecoration.none,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        );
                      },
                    ),

                    // --- ORTA KISIM: GÖRSEL VE METİN ---
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // İlaç Görseli
                        Container(
                          height: 200,
                          width: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.15),
                                blurRadius: 50,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Image.asset(
                              'assets/pill_icon.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                    Icons.medication_liquid_rounded,
                                    size: 100,
                                    color: Colors.white
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Başlık
                        Text(
                          widget.alarmSettings.notificationSettings.title,
                          style: const TextStyle(
                            fontSize: 28,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            decoration: TextDecoration.none,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),

                        // Açıklama
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40.0),
                          child: Text(
                            widget.alarmSettings.notificationSettings.body,
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white.withOpacity(0.9),
                              height: 1.4,
                              decoration: TextDecoration.none,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    // --- ALT KISIM: DURDUR BUTONU ---
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20.0),
                      child: GestureDetector(
                        onTap: _handleStop,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(50),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              width: 220,
                              height: 75,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  )
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.alarm_off_rounded, color: Colors.white, size: 32),
                                  const SizedBox(width: 15),
                                  Text(
                                    "stop_alarm".tr().toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}