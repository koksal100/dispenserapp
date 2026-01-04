import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:alarm/alarm.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:dispenserapp/main.dart'; // Global alarm state için
import 'package:dispenserapp/services/database_service.dart';
import 'package:dispenserapp/services/auth_service.dart';

class AlarmRingScreen extends StatefulWidget {
  final AlarmSettings alarmSettings;
  const AlarmRingScreen({super.key, required this.alarmSettings});

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen> {
  static const platform = MethodChannel('com.example.dispenserapp/lock_control');
  final DatabaseService _dbService = DatabaseService();

  // Renk Paleti
  static const Color colTurquoise = Color(0xFF36C0A6);
  static const Color colSkyBlue = Color(0xFF1D8AD6);
  static const Color colDeepSea = Color(0xFF0F5191);

  bool _feedbackEnabled = true; // Varsayılan true, ayarlardan güncellenir
  bool _showingFeedback = false;
  bool _processing = false;

  String _macAddress = "";
  List<int> _sectionIndices = [];
  List<String> _medicineNames = [];

  int _currentFeedbackIndex = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Ekranın kapanmasını engelle
    _checkSettings();
    _loadMetadata();
  }

  // Kullanıcının "Feedback" ayarını kontrol et
  Future<void> _checkSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        // Eğer ayar hiç yapılmamışsa varsayılan olarak açık gelsin (true)
        _feedbackEnabled = prefs.getBool('feedback_enabled') ?? true;
      });
    }
  }

  // Alarm kurulurken kaydedilen meta veriyi (MAC adresi, İlaç İsimleri) yükle
  Future<void> _loadMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    String? metaData = prefs.getString('alarm_meta_${widget.alarmSettings.id}');

    debugPrint("Alarm Çalıyor - Meta Veri: $metaData");

    if (metaData != null && metaData.isNotEmpty) {
      List<String> parts = metaData.split('|');
      // Format: MAC_ADRESİ | BOLME_INDEXLERI (1,2) | ILAC_ISIMLERI (Aspirin,Parol)
      if (parts.length >= 3) {
        setState(() {
          _macAddress = parts[0];
          if (parts[1].isNotEmpty) {
            _sectionIndices = parts[1].split(',').map((e) => int.parse(e)).toList();
          }
          if (parts[2].isNotEmpty) {
            _medicineNames = parts[2].split(',');
          }
        });
      }
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable(); // Wakelock kilidini kaldır
    super.dispose();
  }

  // Alarmı Sustur Butonu
  Future<void> _handleStop() async {
    await Alarm.stop(widget.alarmSettings.id);

    // Eğer feedback açıksa ve elimizde cihaz verisi varsa Feedback ekranına geç
    if (_feedbackEnabled && _macAddress.isNotEmpty && _medicineNames.isNotEmpty) {
      setState(() {
        _showingFeedback = true;
      });
    } else {
      // Veri yoksa veya feedback kapalıysa uygulamayı kapat
      _closeApp();
    }
  }

  // --- KRİTİK BÖLÜM: FEEDBACK İŞLEME VE STOK İADESİ ---
  Future<void> _processSingleFeedback(bool dropped) async {
    if (_processing) return;
    setState(() => _processing = true);

    try {
      // Şu an sorulan ilacın bölme numarası
      int currentSection = _sectionIndices[_currentFeedbackIndex];

      final user = await AuthService().getOrCreateUser();
      String uid = user?.uid ?? "unknown_user";

      // 1. ADIM: İLAÇ DÜŞMEDİYSE İADE ET (Safe Refund)
      if (!dropped) {
        // Kullanıcı "Hayır" dedi.
        // DatabaseService içindeki safeRefundPill fonksiyonunu çağırıyoruz.
        // Bu fonksiyon, son 5 dk içinde başka bir iade yapılmış mı diye kontrol edip
        // gerekirse RTDB sayacını 1 artıracak.
        await _dbService.safeRefundPill(_macAddress, currentSection, uid);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Stok durumu kontrol edildi ve düzeltildi."),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      // 2. ADIM: LOG AT
      await _dbService.logDispenseStatus(
        macAddress: _macAddress,
        sectionIndex: currentSection,
        successful: dropped,
        userResponse: dropped ? "Yes" : "No",
        userId: uid,
      );

      // 3. ADIM: SONRAKİ İLACA GEÇ VEYA KAPAT
      if (_currentFeedbackIndex < _medicineNames.length - 1) {
        // Listede başka ilaç varsa ona geç
        setState(() {
          _currentFeedbackIndex++;
          _processing = false;
        });
      } else {
        // Hepsi bitti, meta veriyi temizle ve kapat
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('alarm_meta_${widget.alarmSettings.id}');

        await Future.delayed(const Duration(milliseconds: 300));
        _closeApp();
      }

    } catch (e) {
      debugPrint("Feedback işleme hatası: $e");
      _closeApp();
    }
  }

  void _closeApp() {
    try {
      // Android kilit ekranından kaldırma (Native kanal varsa)
      platform.invokeMethod('hideFromLockScreen');
    } catch (e) {
      debugPrint("Lock screen error: $e");
    }

    // Global alarm state'i temizle (main.dart'ta tanımlı olmalı)
    globalAlarmState.value = null;

    if (Platform.isAndroid) {
      SystemNavigator.pop(); // Uygulamadan çık
    } else {
      Navigator.of(context).pop(); // iOS için pop
    }
  }

  @override
  Widget build(BuildContext context) {
    // Geri tuşunu engelle (Alarmı zorla susturmak için)
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: colDeepSea,
        body: _showingFeedback ? _buildFeedbackUI() : _buildAlarmUI(),
      ),
    );
  }

  // --- FEEDBACK ARAYÜZÜ (Evet / Hayır Ekranı) ---
  Widget _buildFeedbackUI() {
    String currentMedName = _medicineNames.isNotEmpty
        ? _medicineNames[_currentFeedbackIndex]
        : "İlaç";

    return Container(
      width: double.infinity, height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colDeepSea, Color(0xFF15202B)]
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Çoklu ilaç varsa noktalarla gösterge
            if(_medicineNames.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_medicineNames.length, (index) {
                    return Container(
                      width: 10, height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _currentFeedbackIndex ? colTurquoise : Colors.white24
                      ),
                    );
                  }),
                ),
              ),

            const Icon(Icons.help_outline_rounded, color: Colors.white, size: 80),
            const SizedBox(height: 30),

            // Soru Metni
            Text(
              "$currentMedName düştü mü?",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
            ),
            const SizedBox(height: 15),

            Text(
                "Lütfen ilacı alıp almadığınızı onaylayın.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16, decoration: TextDecoration.none)
            ),
            const SizedBox(height: 60),

            if (_processing)
              const CircularProgressIndicator(color: Colors.white)
            else
              Row(
                children: [
                  // HAYIR BUTONU
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withOpacity(0.9),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                      ),
                      onPressed: () => _processSingleFeedback(false),
                      child: const Text("Hayır", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // EVET BUTONU
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: colTurquoise,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                      ),
                      onPressed: () => _processSingleFeedback(true),
                      child: const Text("Evet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              )
          ],
        ),
      ),
    );
  }

  // --- ALARM ÇALMA ARAYÜZÜ ---
  Widget _buildAlarmUI() {
    return Stack(
      children: [
        // Arkaplan
        Container(
          width: double.infinity, height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colDeepSea, colSkyBlue, colTurquoise],
                stops: [0.2, 0.6, 1.0]
            ),
          ),
        ),
        // Dekoratif Daire
        Positioned(
            top: -100, right: -100,
            child: Container(
                width: 300, height: 300,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05))
            )
        ),

        SafeArea(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Saat ve Tarih
                StreamBuilder(
                  stream: Stream.periodic(const Duration(seconds: 1)),
                  builder: (context, snapshot) {
                    final now = DateTime.now();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}",
                            style: const TextStyle(
                                fontSize: 90, fontWeight: FontWeight.w200,
                                color: Colors.white, height: 1, fontFamily: 'Roboto',
                                decoration: TextDecoration.none,
                                shadows: [Shadow(blurRadius: 10, color: Colors.black26, offset: Offset(0, 4))]
                            ),
                            textAlign: TextAlign.center
                        ),
                        const SizedBox(height: 8),
                        Text(
                            DateFormat('EEEE, d MMMM', context.locale.toString()).format(now),
                            style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w400, letterSpacing: 1.2, decoration: TextDecoration.none),
                            textAlign: TextAlign.center
                        ),
                      ],
                    );
                  },
                ),

                // İlaç Bilgisi ve İkon
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 200, width: 200,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.1),
                          boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.15), blurRadius: 50, spreadRadius: 5)]
                      ),
                      child: Padding(
                          padding: const EdgeInsets.all(30.0),
                          child: Image.asset('assets/pill_icon.png', fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.medication_liquid_rounded, size: 100, color: Colors.white))
                      ),
                    ),
                    const SizedBox(height: 40),

                    Text(
                        widget.alarmSettings.notificationSettings.title,
                        style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5, decoration: TextDecoration.none, shadows: [Shadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2))]),
                        textAlign: TextAlign.center
                    ),
                    const SizedBox(height: 12),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40.0),
                      child: _medicineNames.isNotEmpty
                          ? Column(
                        children: _medicineNames.map((name) => Text(
                          "• $name",
                          style: TextStyle(fontSize: 22, color: Colors.white.withOpacity(0.95), height: 1.4, fontWeight: FontWeight.w600, decoration: TextDecoration.none),
                          textAlign: TextAlign.center,
                        )).toList(),
                      )
                          : Text(
                          widget.alarmSettings.notificationSettings.body,
                          style: TextStyle(fontSize: 20, color: Colors.white.withOpacity(0.95), height: 1.4, fontWeight: FontWeight.w500, decoration: TextDecoration.none),
                          textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis
                      ),
                    ),
                  ],
                ),

                // Durdur Butonu
                Padding(
                  padding: const EdgeInsets.only(bottom: 40.0),
                  child: GestureDetector(
                    onTap: _handleStop,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          width: 240, height: 80,
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))]
                          ),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.alarm_off_rounded, color: Colors.white, size: 36),
                                const SizedBox(width: 15),
                                Text("ALARMI DURDUR", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2, decoration: TextDecoration.none))
                              ]
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
    );
  }
}