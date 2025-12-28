import 'dart:async';
import 'dart:io';
import 'package:dispenserapp/app/main_hub.dart';
import 'package:dispenserapp/features/ble_provisioning/wifi_credentials_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';

// Çeviri yardımcısı
String getTranslated(BuildContext context, String key) {
  return key.tr();
}

class SyncScreen extends StatefulWidget {
  // true  -> İlk açılış (Geniş boşluklar, "Daha Sonra Ekle" var)
  // false -> Uygulama içi (Kompakt görünüm, Geri butonu YOK)
  final bool isOnboarding;

  const SyncScreen({super.key, required this.isOnboarding});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> with SingleTickerProviderStateMixin {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;

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
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint("Scan Error: $e");
    }

    FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          results.sort((a, b) {
            bool aIsMed = a.device.platformName.toUpperCase().startsWith("MEDTRACK");
            bool bIsMed = b.device.platformName.toUpperCase().startsWith("MEDTRACK");
            if (aIsMed && !bIsMed) return -1;
            if (!aIsMed && bIsMed) return 1;
            return b.rssi.compareTo(a.rssi);
          });
          _scanResults = results;
        });
      }
    });

    FlutterBluePlus.isScanning.listen((isScanning) {
      if (mounted) setState(() => _isScanning = isScanning);
    });
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _stopScan();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      await device.connect();

      if (!mounted) return;
      Navigator.pop(context);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WifiCredentialsScreen(device: device),
        ),
      );

      await device.disconnect();

    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${getTranslated(context, 'conn_error')} $e')),
        );
      }
    }
  }

  void _skipSetup() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MainHub()),
    );
  }

  IconData _getSignalIcon(int rssi) {
    if (rssi > -50) return Icons.wifi;
    if (rssi > -70) return Icons.wifi;
    if (rssi > -80) return Icons.network_wifi;
    return Icons.wifi_off;
  }

  Widget _getDeviceIcon(BluetoothDevice device, bool isMedtrack) {
    if (isMedtrack) {
      return Image.asset(
        'assets/dispenser_icon.png',
        width: 40,
        height: 60,
        fit: BoxFit.contain,
        errorBuilder: (c, o, s) => const Icon(Icons.medication, size: 40, color: Colors.blue),
      );
    } else {
      String name = device.platformName.toUpperCase();
      IconData icon = Icons.bluetooth;

      if (name.contains("WATCH") || name.contains("BAND")) icon = Icons.watch;
      else if (name.contains("TV")) icon = Icons.tv;
      else if (name.contains("PHONE") || name.contains("IPHONE")) icon = Icons.smartphone;
      else if (name.contains("PC") || name.contains("LAPTOP")) icon = Icons.computer;
      else if (name.contains("BUDS") || name.contains("HEADSET")) icon = Icons.headphones;

      return Icon(icon, size: 30, color: Colors.grey.shade400);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.blue.shade800;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,

      // Onboarding değilse AppBar göster (Geri butonu kapalı, sadece boşluk yönetimi için)
      // Title olmadığı için otomatik olarak toolbarHeight kadar yer kaplar.
      appBar: !widget.isOnboarding
          ? AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 0, // AppBar'ın yüksekliğini sıfırlayarak boşluğu yok ediyoruz
        automaticallyImplyLeading: false,
      )
          : null,

      body: SafeArea(
        // Onboarding ise üstten boşluk bırak, değilse bırakma (AppBar 0 height olsa bile SafeArea korur)
        child: Padding(
          padding: EdgeInsets.only(top: widget.isOnboarding ? 20 : 10),
          child: Column(
            children: [
              // --- 1. BAŞLIK ALANI ---
              Padding(
                // Onboarding değilse (App içi) padding'i minimumda tutuyoruz
                padding: EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: widget.isOnboarding ? 24.0 : 0.0
                ),
                child: Column(
                  children: [
                    Text(
                      widget.isOnboarding
                          ? getTranslated(context, 'onboarding_device_not_found')
                          : getTranslated(context, 'onboarding_searching'),
                      style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: primaryColor
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isOnboarding
                          ? getTranslated(context, 'onboarding_no_device_desc')
                          : getTranslated(context, 'onboarding_search_desc'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          height: 1.4
                      ),
                    ),
                  ],
                ),
              ),

              // Onboarding değilse araya biraz daha mesafe koy (Başlık ile Radar arası)
              SizedBox(height: widget.isOnboarding ? 0 : 20),

              // --- 2. RADAR ANİMASYONU ---
              SizedBox(
                height: widget.isOnboarding ? 180 : 130,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isScanning)
                      FadeTransition(
                        opacity: Tween(begin: 0.5, end: 0.0).animate(_animationController),
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            width: widget.isOnboarding ? 120 : 100,
                            height: widget.isOnboarding ? 120 : 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.blue.withOpacity(0.3), width: 8),
                            ),
                          ),
                        ),
                      ),
                    Container(
                      width: widget.isOnboarding ? 90 : 80,
                      height: widget.isOnboarding ? 90 : 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.blue.withOpacity(0.1), blurRadius: 20, spreadRadius: 5)
                        ],
                      ),
                      child: Icon(
                        _isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                        size: widget.isOnboarding ? 40 : 32,
                        color: _isScanning ? Colors.blue.shade700 : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              // --- YENİ BOŞLUK ---
              // Radar ile Liste arasında istenen boşluk
              const SizedBox(height: 40),

              // --- 3. CİHAZ LİSTESİ ---
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))
                    ],
                  ),
                  child: Column(
                    children: [
                      // Liste Başlığı
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            24,
                            24, // Buradaki üst boşluğu sabitledik
                            24,
                            10
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "${getTranslated(context, 'found_devices')} (${_scanResults.length})",
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.black87
                              ),
                            ),
                            if (_isScanning)
                              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            else
                              GestureDetector(
                                onTap: _startScan,
                                child: const Icon(Icons.refresh, color: Colors.blue),
                              )
                          ],
                        ),
                      ),

                      // Liste İçeriği
                      Expanded(
                        child: _scanResults.isEmpty
                            ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.device_unknown, size: 50, color: Colors.grey.shade300),
                              const SizedBox(height: 10),
                              Text(
                                _isScanning
                                    ? getTranslated(context, 'please_wait')
                                    : getTranslated(context, 'device_not_found_tip'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                            ],
                          ),
                        )
                            : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _scanResults.length,
                          separatorBuilder: (c, i) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final result = _scanResults[index];
                            final isMedtrack = result.device.platformName.toUpperCase().startsWith("MEDTRACK");
                            final deviceName = result.device.platformName.isEmpty
                                ? getTranslated(context, 'unknown_device')
                                : result.device.platformName;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                              leading: _getDeviceIcon(result.device, isMedtrack),
                              title: Text(
                                deviceName,
                                style: TextStyle(
                                  fontWeight: isMedtrack ? FontWeight.bold : FontWeight.normal,
                                  color: isMedtrack ? Colors.black87 : Colors.grey.shade500,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Row(
                                children: [
                                  Icon(_getSignalIcon(result.rssi), size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text("${result.rssi} dBm", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                              trailing: ElevatedButton(
                                onPressed: isMedtrack ? () => _connectToDevice(result.device) : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isMedtrack ? primaryColor : Colors.grey.shade100,
                                  foregroundColor: isMedtrack ? Colors.white : Colors.grey.shade400,
                                  elevation: isMedtrack ? 2 : 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text(getTranslated(context, 'setup_btn')),
                              ),
                            );
                          },
                        ),
                      ),

                      // --- DAHA SONRA EKLE BUTONU (Sadece Onboarding) ---
                      if (widget.isOnboarding)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24.0),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border(top: BorderSide(color: Colors.grey.shade100))
                          ),
                          child: ElevatedButton(
                            onPressed: _skipSetup,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                elevation: 4,
                                shadowColor: primaryColor.withOpacity(0.4),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)
                                )
                            ),
                            child: Text(
                              getTranslated(context, 'add_later_btn'),
                              style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold
                              ),
                            ),
                          ),
                        ),

                      if (!widget.isOnboarding)
                        const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}