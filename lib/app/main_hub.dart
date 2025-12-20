import 'package:dispenserapp/app/home_screen.dart';
import 'package:dispenserapp/features/ble_provisioning/sync_screen.dart';
import 'package:dispenserapp/app/relatives_screen.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/database_service.dart';
import 'package:easy_localization/easy_localization.dart'; // Çeviri paketi
import 'package:flutter/material.dart';

import 'device_list_screen.dart';
import 'settings_screen.dart'; // Ayarlar sayfası

class MainHub extends StatefulWidget {
  const MainHub({super.key});

  @override
  State<MainHub> createState() => _MainHubState();
}

class _MainHubState extends State<MainHub> {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  int _selectedIndex = 0;

  // Sürükle Bırak Modu Aktif mi?
  bool _isDragMode = false;

  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _authService.getOrCreateUser().then((user) {
      if (user != null) {
        setState(() {
          _currentUser = user;
        });
      }
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _isDragMode = false; // Sayfa değişince modu kapat
    });
  }

  // Modu değiştiren fonksiyon
  void _toggleDragMode(bool value) {
    setState(() {
      _isDragMode = value;
    });
    if (value) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("drag_info".tr()), // Çeviri: "Düzenlemek için sürükleyin..."
            duration: const Duration(seconds: 2),
          )
      );
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    final newUser = await _authService.getOrCreateUser();
    setState(() {
      _currentUser = newUser;
    });
    // Menü açıksa kapat
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
  }

  // --- YENİ MODERN PROFİL MENÜSÜ ---
  void _showProfileMenu() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Profil Fotoğrafı (Gölge Eklendi)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE0F2FE), width: 2), // Açık Mavi Çerçeve
                  ),
                  child: CircleAvatar(
                    radius: 42,
                    backgroundColor: const Color(0xFF1D8AD6), // Gök Mavisi
                    backgroundImage: _currentUser?.photoURL != null
                        ? NetworkImage(_currentUser!.photoURL!)
                        : null,
                    child: _currentUser?.photoURL == null
                        ? Text(
                      _currentUser?.displayName != null
                          ? _currentUser!.displayName![0].toUpperCase()
                          : "U",
                      style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
                    )
                        : null,
                  ),
                ),
                const SizedBox(height: 16),

                // İsim ve Bilgi
                Text(
                  _currentUser?.displayName ?? "User",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F5191)), // Derin Mavi
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  _currentUser?.email ?? "",
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade400),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // --- 1. MODERN AYARLAR BUTONU ---
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                      ),
                      child: const Icon(Icons.settings_rounded, color: Color(0xFF0F5191), size: 22),
                    ),
                    title: Text(
                        "settings_title".tr(),
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F5191))
                    ),
                    trailing: Icon(Icons.chevron_right_rounded, color: Colors.blueGrey.shade300),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsScreen()),
                      );
                    },
                  ),
                ),

                // --- 2. MODERN ÇIKIŞ BUTONU (PASTEL KIRMIZI) ---
                InkWell(
                  onTap: _signOut,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2), // Çok açık kırmızı zemin
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFECACA)), // Açık kırmızı çerçeve
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout_rounded, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 10),
                        Text(
                            "logout".tr(),
                            style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w700,
                                fontSize: 15
                            )
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateFolderDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("create_room".tr()), // "Yeni Oda Oluştur"
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: "room_name_hint".tr()), // "Örn: 102 Nolu Oda"
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("cancel".tr()) // "İptal"
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty && _currentUser != null) {
                _dbService.createGroup(_currentUser!.uid, controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: Text("create".tr()), // "Oluştur"
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget currentScreen;
    if (_selectedIndex == 0) {
      currentScreen = DeviceListScreen(
        isDragMode: _isDragMode,
        onModeChanged: _toggleDragMode,
      );
    } else if (_selectedIndex == 1) {
      currentScreen = const SyncScreen();
    } else {
      currentScreen = const RelativesScreen();
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: colorScheme.onSurface,
        centerTitle: true,

        // ÖNEMLİ: Sol taraftaki alanı genişlettik (Standart 56'dır, 74 yaptık)
        // Böylece hem soldan boşluk bırakıp hem de resmi büyük tutabileceğiz.
        leadingWidth: 74,

        // --- SOL ÜST: PROFİL FOTOĞRAFI (BÜYÜK & ÇERÇEVELİ) ---
        leading: Container(
          // Soldan 20px boşluk bırakarak kenardan uzaklaştırdık
          margin: const EdgeInsets.only(left: 20.0),
          child: Center( // Dikeyde ortalamak için Center şart
            child: InkWell(
              onTap: _showProfileMenu,
              borderRadius: BorderRadius.circular(50),
              child: Container(
                width: 46, // Çerçevenin toplam genişliği (Resim bunun içine sığacak)
                height: 46,
                padding: const EdgeInsets.all(3), // Çerçeve ile Resim arasındaki beyaz boşluk
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent, // Arka plan şeffaf
                  border: Border.all(
                      color: const Color(0xFF1D8AD6).withOpacity(0.4), // Gök Mavisi Çerçeve
                      width: 2.5 // Çerçeve kalınlığı artırıldı
                  ),
                ),
                child: CircleAvatar(
                  backgroundColor: colorScheme.primary,
                  // Resmin kendisi (Padding yüzünden çerçeveden biraz küçük olur, şık durur)
                  backgroundImage: _currentUser?.photoURL != null
                      ? NetworkImage(_currentUser!.photoURL!)
                      : null,
                  child: _currentUser?.photoURL == null
                      ? Text(
                    _currentUser?.displayName != null
                        ? _currentUser!.displayName![0].toUpperCase()
                        : "U",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
                  )
                      : null,
                ),
              ),
            ),
          ),
        ),
        // -----------------------------------------------------------------

        title: Text(
          _selectedIndex == 0
              ? (_isDragMode ? 'edit_mode'.tr() : 'my_devices'.tr())
              : (_selectedIndex == 1 ? 'sync'.tr() : 'relatives'.tr()),
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),

        actions: [
          if (_selectedIndex == 0)
            IconButton(
              icon: Icon(
                _isDragMode ? Icons.check_circle_rounded : Icons.menu_rounded, // İkonları da modernleştirdim
                size: 30,
                color: _isDragMode ? colorScheme.primary : colorScheme.onSurface,
              ),
              tooltip: _isDragMode ? 'edit_mode'.tr() : 'edit_mode'.tr(),
              onPressed: () => _toggleDragMode(!_isDragMode),
            ),
          const SizedBox(width: 12), // Sağ taraftan da biraz boşluk
        ],
      ),

      body: currentScreen,

      floatingActionButton: (_selectedIndex == 0 && _isDragMode)
          ? FloatingActionButton.extended(
        onPressed: _showCreateFolderDialog,
        icon: const Icon(Icons.create_new_folder),
        label: Text("add_room".tr()), // "Oda Ekle"
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      )
          : null,

      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
              icon: const Icon(Icons.devices_other_rounded),
              label: 'my_devices'.tr() // "Cihazlarım"
          ),
          BottomNavigationBarItem(
              icon: const Icon(Icons.sync_rounded),
              label: 'sync'.tr() // "Senkronizasyon"
          ),
          BottomNavigationBarItem(
              icon: const Icon(Icons.people_alt_rounded),
              label: 'relatives'.tr() // "Yakınlarım"
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: colorScheme.primary,
        onTap: _onItemTapped,
      ),
    );
  }
}