import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // TextInputFormatter için gerekli

import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'home_screen.dart';

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  late Future<AppUser?> _initAndPrecacheFuture;
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _isInitialized = true;
      _initAndPrecacheFuture = _initialize();
    }
  }

  Future<AppUser?> _initialize() async {
    final results = await Future.wait([
      _authService.getOrCreateUser(),
      precacheImage(const AssetImage('assets/dispenser_icon.png'), context),
    ]);
    return results[0] as AppUser?;
  }

  void _retryLogin() {
    setState(() {
      _initAndPrecacheFuture = _initialize();
    });
  }

  // Manuel ekleme diyalogunu açan fonksiyon
  void _showAddDeviceDialog(String uid, String userEmail) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manuel Cihaz Ekle'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.visiblePassword,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-fA-F0-9]')),
            MacAddressInputFormatter(),
            LengthLimitingTextInputFormatter(17),
          ],
          decoration: const InputDecoration(
            labelText: 'MAC Adresi',
            hintText: 'AA:BB:CC:11:22:33',
            border: OutlineInputBorder(),
            counterText: "",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final mac = controller.text.trim();
              if (mac.length == 17) {
                // 1. Manuel Ekleme İşlemi (DatabaseService içinde hem Cihaz hem User güncelleniyor)
                final result = await _dbService.addDeviceManually(uid, userEmail, mac);

                if (!mounted) return;
                Navigator.pop(context);

                if (result == 'success') {
                  // 2. ÇİFTE GÜVENLİK: Listeleri hemen bir daha senkronize et
                  await _dbService.updateUserDeviceList(uid, userEmail);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cihaz başarıyla eklendi!')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result), backgroundColor: Colors.red),
                  );
                }
              } else {
                // ... hata mesajı ...
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  // İsim düzenleme diyaloğu
  void _showEditNameDialog(String macAddress, String currentName) {
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Cihaz Adını Düzenle"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: "Yeni cihaz adı"),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("İptal"),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  _dbService.updateDeviceName(macAddress, newName);
                }
                Navigator.of(context).pop();
              },
              child: const Text("Kaydet"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: _initAndPrecacheFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Giriş başarısız oldu."),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _retryLogin,
                  child: const Text("Tekrar Dene"),
                ),
              ],
            ),
          );
        }

        final userData = snapshot.data!;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: _buildDeviceList(userData.uid),
          floatingActionButton: FloatingActionButton(
            // Email bilgisini buradan gönderiyoruz
            onPressed: () => _showAddDeviceDialog(userData.uid, userData.email),
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Icon(Icons.add, color: Colors.white),
            tooltip: 'Manuel Cihaz Ekle',
          ),
        );
      },
    );
  }

  Widget _buildDeviceList(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
          return const CircularProgressIndicator();
        }

        final userData = userSnapshot.data!.data() as Map<String, dynamic>;

        // --- 1. TÜM LİSTELERİ ÇEKİYORUZ ---
        final List<dynamic> owned = userData['owned_dispensers'] ?? [];
        final List<dynamic> secondary = userData['secondary_dispensers'] ?? [];
        final List<dynamic> readOnly = userData['read_only_dispensers'] ?? [];

        // --- 2. LİSTELERİ BİRLEŞTİRİYORUZ (Rol bilgisi ekleyerek) ---
        final List<Map<String, dynamic>> allDevices = [];

        for (var mac in owned) {
          allDevices.add({'mac': mac, 'role': 'owner'});
        }
        for (var mac in secondary) {
          // Çakışma önlemek için kontrol eklenebilir ama set zaten DatabaseService'de yapılıyor
          if (!allDevices.any((d) => d['mac'] == mac)) {
            allDevices.add({'mac': mac, 'role': 'secondary'});
          }
        }
        for (var mac in readOnly) {
          if (!allDevices.any((d) => d['mac'] == mac)) {
            allDevices.add({'mac': mac, 'role': 'readOnly'});
          }
        }

        if (allDevices.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                "Henüz bir cihazınız yok.",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 20.0, bottom: 80),
          itemCount: allDevices.length,
          itemBuilder: (context, index) {
            final deviceItem = allDevices[index];
            final macAddress = deviceItem['mac'] as String;
            final role = deviceItem['role'] as String;

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('dispenser')
                  .doc(macAddress)
                  .snapshots(),
              builder: (context, deviceSnapshot) {
                if (!deviceSnapshot.hasData || !deviceSnapshot.data!.exists) {
                  // Cihaz verisi henüz gelmediyse veya silinmişse boş döndür (veya loading)
                  return const SizedBox();
                }

                final deviceData = deviceSnapshot.data!.data() as Map<String, dynamic>;
                final deviceName = deviceData['device_name'] as String? ?? "Akıllı İlaç Kutusu";

                // --- 3. ROL ROZETİ RENGİ VE İKONU ---
                Color roleColor;
                String roleText;
                IconData roleIcon;

                if (role == 'owner') {
                  roleColor = Colors.green;
                  roleText = "SAHİP";
                  roleIcon = Icons.verified_user;
                } else if (role == 'secondary') {
                  roleColor = Colors.blue;
                  roleText = "YÖNETİCİ";
                  roleIcon = Icons.security;
                } else {
                  roleColor = Colors.orange;
                  roleText = "İZLEYİCİ";
                  roleIcon = Icons.visibility;
                }

                return SizedBox(
                  height: 195,
                  width: double.infinity,
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    elevation: 6,
                    shadowColor: Colors.black26,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: const BorderSide(color: Colors.black, width: 1.0),
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                          colors: [
                            Color(0xFFFFD9D9),
                            Color(0xFFFFFFFF),
                          ],
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(22)),
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => HomeScreen(macAddress: macAddress),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Cihaz İkonu
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12.0),
                                    child: Image.asset(
                                      'assets/dispenser_icon.png',
                                      width: 90,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // Bilgiler ve Rozet
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // ROL ROZETİ WIDGET'I
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          margin: const EdgeInsets.only(bottom: 8),
                                          decoration: BoxDecoration(
                                            color: roleColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: roleColor.withOpacity(0.5)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(roleIcon, size: 12, color: roleColor),
                                              const SizedBox(width: 4),
                                              Text(
                                                roleText,
                                                style: TextStyle(
                                                  color: roleColor,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Cihaz İsmi
                                        Text(
                                          deviceName.toUpperCase(),
                                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        // MAC Adresi
                                        Text(
                                          'MAC: $macAddress',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.grey.shade700,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Düzenle Butonu (Sadece İzleyici değilse göster)
                                  if (role != 'readOnly')
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, color: Colors.black87),
                                      tooltip: 'Cihaz adını düzenle',
                                      onPressed: () => _showEditNameDialog(macAddress, deviceName),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// MAC Adresi için Özel Formatlayıcı
class MacAddressInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    var text = newValue.text;
    text = text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 2 == 0 && nonZeroIndex != text.length) {
        buffer.write(':');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}