import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dispenserapp/app/home_screen.dart';
import 'package:dispenserapp/features/ble_provisioning/sync_screen.dart';
import 'package:dispenserapp/app/relatives_screen.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/database_service.dart';
import 'package:flutter/material.dart';

import 'device_list_screen.dart';

class MainHub extends StatefulWidget {
  const MainHub({super.key});

  @override
  State<MainHub> createState() => _MainHubState();
}

class _MainHubState extends State<MainHub> {
  final AuthService _authService = AuthService();
  int _selectedIndex = 0;
  Key _deviceListScreenKey = UniqueKey();
  String? _userName;

  late final List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _authService.getOrCreateUser().then((user) {
      if (user != null) {
        setState(() {
          _userName = user.displayName;
        });
      }
    });
    _widgetOptions = <Widget>[
      DeviceListScreen(key: _deviceListScreenKey),
      const SyncScreen(),
      const RelativesScreen(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _signOut() async {
    final bool? shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emin misiniz?'),
        content: const Text('Çıkış yapmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hayır'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Evet'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      await _authService.signOut();
      final newUser = await _authService.getOrCreateUser();
      if (newUser != null) {
        setState(() {
          _userName = newUser.displayName;
          _deviceListScreenKey = UniqueKey();
          _widgetOptions[0] = DeviceListScreen(key: _deviceListScreenKey);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const double navigationBarHeight = 65; // BottomNavigationBar'ın yüksekliğini ayarlamak için

    return Scaffold(
      appBar: AppBar(
        // AppBar'ın yükseltisini kaldırarak daha modern bir görünüm (isteğe bağlı)
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor, // Arkaplan rengini kullan
        foregroundColor: colorScheme.onSurface, // İkon ve yazı rengi

        // Kullanıcı Adı: CircleAvatar ile daha şık bir profil görünümü
        leading: _userName != null
            ? Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: GestureDetector(
              onTap: () {
                // Tek tıklandığında SnackBar'ı göster
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    // Bilgi kutucuğunda gözükecek tam isim
                    content: Center(
                      child: Text(
                        'Google kullanıcı adı: $_userName',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimary, // Metin rengi
                        ),
                      ),
                    ),
                    // SnackBar'ın stilini ayarlıyoruz
                    backgroundColor: colorScheme.primary, // Arkaplan rengi
                    duration: const Duration(milliseconds: 1500), // 1.5 saniye sonra kaybol
                    behavior: SnackBarBehavior.floating, // Floating stil
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              },
              child: CircleAvatar(
                backgroundColor: colorScheme.primary.withOpacity(0.1),
                child: Text(
                  // Kullanıcı adının ilk harfi
                  _userName![0].toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ),
        )
            : null,

        // Başlık
        title: Text(
          'Cihazlarım',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.7
          ),
        ),

        // Aksiyonlar
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış Yap',
            onPressed: _signOut,
            color: colorScheme.error, // Çıkış ikonuna dikkat çekici bir renk
          ),
          const SizedBox(width: 8), // Sağ kenardan boşluk
        ],
      ),

      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),

      // BottomNavigationBar İyileştirmeleri
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Colors.grey.shade300, // Hafif bir üst çizgi
              width: 0.5,
            ),
          ),
        ),
        height: navigationBarHeight,
        child: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.devices_other_rounded, size: 26), // İkon büyüklüğü
              label: 'Cihazlarım',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.sync_rounded, size: 26),
              label: 'Senkronizasyon',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_alt_rounded, size: 26),
              label: 'Yakınlarım',
            ),
          ],
          currentIndex: _selectedIndex,

          // Renkler
          selectedItemColor: colorScheme.primary, // Temel renk
          unselectedItemColor: Colors.grey.shade600, // Daha koyu gri
          backgroundColor: theme.scaffoldBackgroundColor, // Arkaplan rengi

          // Tipografi
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold, // Seçili etiketi kalın yap
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 12,
          ),

          onTap: _onItemTapped,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed, // Daha iyi kontrol için
        ),
      ),
    );
  }
}
