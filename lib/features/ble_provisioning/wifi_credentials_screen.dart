import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:easy_localization/easy_localization.dart';

// --- ÇEVİRİ KÖPRÜSÜ
String getTranslated(BuildContext context, String key) {

  return key.tr();
}

class WifiCredentialsScreen extends StatefulWidget {
  final BluetoothDevice device;

  const WifiCredentialsScreen({super.key, required this.device});

  @override
  State<WifiCredentialsScreen> createState() => _WifiCredentialsScreenState();
}

class _WifiCredentialsScreenState extends State<WifiCredentialsScreen> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isConnecting = false;
  bool _isPasswordVisible = false;
  String _statusMessage = "";
  IconData _statusIcon = Icons.wifi_find;

  // ESP32 UUID'leri (Sabit)
  final String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCredentials() async {
    // 1. Boş alan kontrolü
    if (_ssidController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(getTranslated(context, 'fill_all_fields')),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
          )
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = getTranslated(context, 'connecting');
      _statusIcon = Icons.bluetooth_connected;
    });

    BluetoothCharacteristic? targetChar;
    StreamSubscription? notifySubscription;

    try {
      // 2. Bağlan
      await widget.device.connect();

      setState(() {
        _statusMessage = getTranslated(context, 'discovering_services');
        _statusIcon = Icons.search;
      });

      // 3. Servis Bul
      List<BluetoothService> services = await widget.device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == SERVICE_UUID) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == CHAR_UUID) {
              targetChar = characteristic;
              break;
            }
          }
        }
      }

      if (targetChar == null) {
        throw Exception(getTranslated(context, 'service_not_found'));
      }

      // 4. Dinlemeye Başla
      setState(() {
        _statusMessage = getTranslated(context, 'opening_channel');
        _statusIcon = Icons.import_export;
      });

      await targetChar.setNotifyValue(true);

      Completer<String> responseCompleter = Completer<String>();

      notifySubscription = targetChar.lastValueStream.listen((value) {
        String response = utf8.decode(value).trim();
        debugPrint("ESP32 Response: $response");

        if (response == "SUCCESS") {
          if (!responseCompleter.isCompleted) responseCompleter.complete("SUCCESS");
        } else if (response == "FAIL") {
          if (!responseCompleter.isCompleted) responseCompleter.complete("FAIL");
        } else if (response == "TRYING") {
          setState(() {
            _statusMessage = getTranslated(context, 'negotiating');
            _statusIcon = Icons.router;
          });
        }
      });

      // 5. Veriyi Gönder
      Map<String, String> data = {
        "s": _ssidController.text.trim(),
        "p": _passwordController.text.trim()
      };
      String jsonString = jsonEncode(data);

      setState(() {
        _statusMessage = getTranslated(context, 'sending_info');
        _statusIcon = Icons.send;
      });

      await targetChar.write(utf8.encode(jsonString));

      setState(() {
        _statusMessage = getTranslated(context, 'waiting_result');
        _statusIcon = Icons.hourglass_top;
      });

      // 6. Cevap Bekle (45 Saniye)
      String finalResult = await responseCompleter.future.timeout(
          const Duration(seconds: 45),
          onTimeout: () => "TIMEOUT"
      );

      // 7. Sonuç
      if (finalResult == "SUCCESS") {
        setState(() { _statusMessage = getTranslated(context, 'success_caps'); });
        _showResultDialog(true);
      } else if (finalResult == "FAIL") {
        setState(() { _statusMessage = getTranslated(context, 'error_password'); });
        _showResultDialog(false, message: getTranslated(context, 'error_wifi_tip'));
      } else {
        setState(() { _statusMessage = getTranslated(context, 'timeout'); });
        _showResultDialog(false, message: getTranslated(context, 'no_response'));
      }

    } catch (e) {
      setState(() { _statusMessage = "${getTranslated(context, 'error_title')}: $e"; });
      _showResultDialog(false, message: "$e");
    } finally {
      // Temizlik
      notifySubscription?.cancel();
      if (mounted) setState(() { _isConnecting = false; });
      try { await widget.device.disconnect(); } catch (_) {}
    }
  }

  void _showResultDialog(bool success, {String? message}) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: success ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 10),
            Text(success
                ? getTranslated(context, 'success_title')
                : getTranslated(context, 'error_title')),
          ],
        ),
        content: Text(
          message ?? (success
              ? getTranslated(context, 'success_message')
              : getTranslated(context, 'error_generic')),
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (success) {
                Navigator.pop(context);
              }
            },
            child: Text(
                getTranslated(context, 'ok_btn'),
                style: const TextStyle(fontWeight: FontWeight.bold)
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.blue.shade800;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
            getTranslated(context, 'network_settings'),
            style: const TextStyle(color: Colors.black87)
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // İKON
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.wifi_tethering, size: 60, color: primaryColor),
                  ),
                ),
                const SizedBox(height: 20),
                // Cihaz Adı
                Text(
                  widget.device.platformName,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 8),
                Text(
                  getTranslated(context, 'enter_wifi_info'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 30),

                // FORM KARTI
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _ssidController,
                        enabled: !_isConnecting,
                        decoration: InputDecoration(
                          labelText: getTranslated(context, 'wifi_ssid'),
                          hintText: getTranslated(context, 'wifi_hint'),
                          prefixIcon: Icon(Icons.wifi, color: primaryColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        enabled: !_isConnecting,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          labelText: getTranslated(context, 'wifi_pass'),
                          prefixIcon: Icon(Icons.lock_outline, color: primaryColor),
                          suffixIcon: IconButton(
                            icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                            onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // BUTON veya DURUM ÇUBUĞU
                if (_isConnecting)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_statusIcon, color: primaryColor, size: 20),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _statusMessage,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _sendCredentials,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        shadowColor: Colors.blue.withOpacity(0.3),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.link),
                          const SizedBox(width: 10),
                          Text(getTranslated(context, 'connect_setup_btn'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}