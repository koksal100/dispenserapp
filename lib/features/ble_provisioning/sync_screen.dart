import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'wifi_credentials_screen.dart'; // Dosya yolunun doğru olduğundan emin ol
import 'package:easy_localization/easy_localization.dart';

// --- ÇEVİRİ KÖPRÜSÜ ---
String getTranslated(BuildContext context, String key) {
  return key.tr();
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> with SingleTickerProviderStateMixin {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  BluetoothDevice? _connectedDevice;

  // Animasyon Kontrolcüleri
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // Radar animasyonu
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _requestPermissionsAndScan();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _stopScan();
    super.dispose();
  }

  Future<void> _requestPermissionsAndScan() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      if (statuses[Permission.bluetoothScan]!.isGranted &&
          statuses[Permission.bluetoothConnect]!.isGranted) {
        _startScan();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(getTranslated(context, 'bluetooth_perm_required'))),
          );
        }
      }
    } else {
      _startScan();
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _scanResults = [];
      _isScanning = true;
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      debugPrint("Scan Error: $e");
    }

    // Sonuçları dinle
    FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          // Sıralama: MEDTRACK cihazları en üstte
          results.sort((a, b) {
            bool aIsMed = a.device.platformName.toUpperCase().startsWith("MEDTRACK");
            bool bIsMed = b.device.platformName.toUpperCase().startsWith("MEDTRACK");
            if (aIsMed && !bIsMed) return -1;
            if (!aIsMed && bIsMed) return 1;
            return 0;
          });

          _scanResults = results;
        });
      }
    });

    // Tarama durumunu dinle
    FlutterBluePlus.isScanning.listen((isScanning) {
      if (mounted) {
        setState(() {
          _isScanning = isScanning;
        });
      }
    });
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _stopScan();

    // Yükleniyor dialogu
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      await device.connect();

      if (!mounted) return;
      Navigator.pop(context); // Dialogu kapat

      setState(() {
        _connectedDevice = device;
      });

      // Diğer sayfaya git
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WifiCredentialsScreen(device: device),
        ),
      );

      // Dönünce bağlantıyı kes
      await device.disconnect();
      setState(() {
        _connectedDevice = null;
      });

    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Hata olursa dialogu kapat
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${getTranslated(context, 'conn_error')} $e')),
        );
      }
    }
  }

  // Sinyal İkonları
  IconData _getSignalIcon(int rssi) {
    if (rssi > -50) return Icons.wifi;
    if (rssi > -70) return Icons.wifi;
    if (rssi > -80) return Icons.network_wifi;
    return Icons.wifi_off;
  }

  // --- AKILLI CİHAZ İKONU SEÇİCİ ---
  Widget _getDeviceIcon(BluetoothDevice device, bool isMedtrack) {
    // 1. MEDTRACK CİHAZI (Özel Resim)
    if (isMedtrack) {
      return Image.asset(
        'assets/dispenser_icon.png',
        width: 40,
        height: 60,
        fit: BoxFit.contain,
      );
    }

    // 2. DİĞER CİHAZLAR (İsme Göre Tahmin)
    else {
      String name = device.platformName.toUpperCase();
      IconData icon;

      // Anahtar kelime taraması
      if (name.contains("WATCH") || name.contains("BAND") || name.contains("GT") || name.contains("MI")) {
        icon = Icons.watch;
      } else if (name.contains("TV") || name.contains("BOX") || name.contains("TELEVISION")) {
        icon = Icons.tv;
      } else if (name.contains("TAB") || name.contains("PAD")) {
        icon = Icons.tablet_android; // Tablet
      } else if (name.contains("PHONE") || name.contains("IPHONE") || name.contains("SAMSUNG") || name.contains("REDMI")) {
        icon = Icons.smartphone;
      } else if (name.contains("PC") || name.contains("LAPTOP") || name.contains("BOOK") || name.contains("MAC")) {
        icon = Icons.computer;
      } else if (name.contains("BUDS") || name.contains("PODS") || name.contains("AIR") || name.contains("HEAD") || name.contains("AUDIO")) {
        icon = Icons.headphones;
      } else if (name.contains("CAR") || name.contains("AUTO")) {
        icon = Icons.directions_car;
      } else {
        icon = Icons.bluetooth; // Hiçbiri değilse standart ikon
      }

      return Icon(
          icon,
          size: 30,
          color: Colors.grey.shade400 // Soluk gri
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.blue.shade800;
    final backgroundColor = Colors.grey.shade100;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          getTranslated(context, 'device_setup_title'),
          style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 24),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // --- RADAR BÖLÜMÜ ---
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(color: backgroundColor),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isScanning)
                      FadeTransition(
                        opacity: Tween(begin: 0.5, end: 0.0).animate(_animationController),
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.blue.withOpacity(0.5), width: 4),
                            ),
                          ),
                        ),
                      ),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _isScanning ? Colors.blue.shade100 : Colors.grey.shade300,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)
                        ],
                      ),
                      child: Icon(
                        _isScanning ? Icons.bluetooth_searching : Icons.bluetooth,
                        size: 40,
                        color: _isScanning ? primaryColor : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _isScanning
                      ? getTranslated(context, 'searching_devices')
                      : getTranslated(context, 'scan_stopped'),
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
                ),
              ],
            ),
          ),

          // --- LİSTE BÖLÜMÜ ---
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 25, 0, 15),
                    child: Text(
                      "${getTranslated(context, 'found_devices')} (${_scanResults.length})",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                    ),
                  ),
                  Expanded(
                    child: _scanResults.isEmpty
                        ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.device_unknown, size: 60, color: Colors.grey.shade300),
                          const SizedBox(height: 10),
                          Text(
                            _isScanning
                                ? getTranslated(context, 'please_wait')
                                : getTranslated(context, 'device_not_found_tip'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    )
                        : ListView.builder(
                      itemCount: _scanResults.length,
                      itemBuilder: (context, index) {
                        final result = _scanResults[index];
                        final rssi = result.rssi;

                        // Bu cihaz bizim mi?
                        final isMedtrack = result.device.platformName.toUpperCase().startsWith("MEDTRACK");

                        final deviceName = result.device.platformName.isEmpty
                            ? getTranslated(context, 'unknown_device')
                            : result.device.platformName;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 15),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              // Eğer Medtrack ise belirgin kenar, değilse silik
                                color: isMedtrack ? Colors.blue.shade100 : Colors.grey.shade200
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),

                            // DÜZELTME: Akıllı İkon Seçici Kullanıldı
                            leading: _getDeviceIcon(result.device, isMedtrack),

                            title: Text(
                              deviceName,
                              style: TextStyle(
                                fontWeight: isMedtrack ? FontWeight.bold : FontWeight.normal,
                                fontSize: 16,
                                // Medtrack ise siyah, değilse gri yazı
                                color: isMedtrack ? Colors.black87 : Colors.grey.shade500,
                              ),
                            ),

                            subtitle: Row(
                              children: [
                                // Sinyal ikonu hep gri
                                Icon(_getSignalIcon(rssi), size: 16, color: Colors.grey.shade400),
                                const SizedBox(width: 4),
                                Text(
                                    "$rssi dBm",
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12)
                                ),
                                const SizedBox(width: 10),
                                Text(
                                    result.device.remoteId.str.substring(0,8),
                                    style: TextStyle(color: Colors.grey.shade300, fontSize: 10)
                                ),
                              ],
                            ),

                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                // Pasif ise gri, aktif ise ana renk
                                backgroundColor: isMedtrack ? primaryColor : Colors.grey.shade200,
                                // Pasif ise yazı rengi de gri olsun
                                foregroundColor: isMedtrack ? Colors.white : Colors.grey.shade400,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: isMedtrack ? 2 : 0,
                              ),
                              // Medtrack değilse null vererek butonu disable et
                              onPressed: isMedtrack ? () => _connectToDevice(result.device) : null,
                              child: Text(getTranslated(context, 'setup_btn')),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: SizedBox(
        height: 65,
        width: 65,
        child: FloatingActionButton(
          onPressed: _isScanning ? _stopScan : _startScan,
          backgroundColor: _isScanning ? Colors.red.shade400 : primaryColor,
          elevation: 4,
          child: Icon(_isScanning ? Icons.stop : Icons.search, size: 30, color: Colors.white),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}