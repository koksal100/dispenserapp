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

  void _showProfileMenu() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Profil Fotoğrafı
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  backgroundImage: _currentUser?.photoURL != null
                      ? NetworkImage(_currentUser!.photoURL!)
                      : null,
                  child: _currentUser?.photoURL == null
                      ? Text(
                    _currentUser?.displayName != null
                        ? _currentUser!.displayName![0].toUpperCase()
                        : "U",
                    style: const TextStyle(fontSize: 30, color: Colors.white),
                  )
                      : null,
                ),
                const SizedBox(height: 16),

                // "Oturum Açıldı" metni
                Text("logged_in_as".tr(), style: const TextStyle(fontSize: 12, color: Colors.grey)),

                Text(
                  _currentUser?.displayName ?? "Kullanıcı",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // --- AYARLAR MENÜSÜ ---
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: Text("settings_title".tr()), // "Ayarlar"
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(context); // Menüyü kapat
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    );
                  },
                ),
                const Divider(),

                // --- ÇIKIŞ BUTONU ---
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: Text("logout".tr()), // "Çıkış Yap"
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.errorContainer,
                      foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                )
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

        // --- SOL ÜST: PROFİL FOTOĞRAFI ---
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: InkWell(
            onTap: _showProfileMenu,
            borderRadius: BorderRadius.circular(50),
            child: CircleAvatar(
              backgroundColor: colorScheme.primary,
              backgroundImage: _currentUser?.photoURL != null
                  ? NetworkImage(_currentUser!.photoURL!)
                  : null,
              child: _currentUser?.photoURL == null
                  ? Text(
                _currentUser?.displayName != null
                    ? _currentUser!.displayName![0].toUpperCase()
                    : "U",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              )
                  : null,
            ),
          ),
        ),

        // --- BAŞLIK (Dinamik Çeviri) ---
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
                _isDragMode ? Icons.close : Icons.menu,
                size: 30,
                color: _isDragMode ? colorScheme.error : colorScheme.onSurface,
              ),
              tooltip: _isDragMode ? 'edit_mode'.tr() : 'edit_mode'.tr(), // Tooltip de çevrilebilir
              onPressed: () => _toggleDragMode(!_isDragMode),
            ),
          const SizedBox(width: 8),
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