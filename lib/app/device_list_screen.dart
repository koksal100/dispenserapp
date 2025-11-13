import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
        return _buildDeviceList(userData.uid);
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
        final List<dynamic> ownedDispensers =
            userData['owned_dispensers'] ?? [];
        if (ownedDispensers.isEmpty) {
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
          padding: const EdgeInsets.only(top: 20.0),
          // Üst boşluğu biraz artırdık
          itemCount: ownedDispensers.length,
          itemBuilder: (context, index) {
            final macAddress = ownedDispensers[index] as String;
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('dispenser')
                  .doc(macAddress)
                  .snapshots(),
              builder: (context, deviceSnapshot) {
                if (!deviceSnapshot.hasData || !deviceSnapshot.data!.exists) {
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    child: ListTile(
                      title: Text(macAddress),
                      subtitle: const Text("Cihaz bilgisi yükleniyor..."),
                    ),
                  );
                }

                final deviceData =
                    deviceSnapshot.data!.data() as Map<String, dynamic>;
                final deviceName =
                    deviceData['device_name'] as String? ??
                    "Akıllı İlaç Kutusu";

                return SizedBox(
                  height: 185,
                  width: double.infinity,
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    // Dikey boşluğu artırdık
                    elevation: 9,
                    shadowColor: Colors.black38,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: const BorderSide(
                        color: Colors.black, // Siyah kenarlık rengi
                        width:
                            1.0, // Kenarlık kalınlığı (istediğiniz gibi değiştirebilirsiniz)
                      ),
                    ),
                    // Daha yuvarlak köşeler
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                          colors: [
                            Color(0xFFFFD9D9), // Açık mavi
                            Color(0xFFFFFFFF), // Çok açık mor
                          ],
                        ),
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  HomeScreen(macAddress: macAddress),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 20,
                            horizontal: 16,
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8.0),
                                child: Image.asset(
                                  'assets/dispenser_icon.png',
                                  width: 110,
                                  height: 120,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      deviceName.toUpperCase(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 2,
                                          ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        'MAC Adresi: $macAddress',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Colors.grey.shade600,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: 30,
                                  color: Colors.black,
                                ),
                                tooltip: 'Cihaz adını düzenle',
                                onPressed: () =>
                                    _showEditNameDialog(macAddress, deviceName),
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
