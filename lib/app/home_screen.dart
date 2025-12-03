import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:dispenserapp/widgets/circular_selector.dart';
import 'package:dispenserapp/services/database_service.dart';

class HomeScreen extends StatefulWidget {
  final String macAddress;

  const HomeScreen({super.key, required this.macAddress});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<CircularSelectorState> _circularSelectorKey = GlobalKey<CircularSelectorState>();
  final DatabaseService _databaseService = DatabaseService();
  final NotificationService _notificationService = NotificationService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _sections = [];
  bool _isLoading = true;

  // Varsayılan olarak en kısıtlı rolü veriyoruz
  DeviceRole _currentRole = DeviceRole.readOnly;
  String? _currentUserEmail;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);

    final user = await _authService.getOrCreateUser();
    if (user != null) {
      _currentUserEmail = user.email; // Zaten küçük harfe çevrilmiş hali

      // --- DEBUG BAŞLANGICI ---
      print("--- ROL KONTROLÜ BAŞLIYOR ---");
      print("Giriş Yapan Mail: '$_currentUserEmail'");

      final doc = await FirebaseFirestore.instance.collection('dispenser').doc(widget.macAddress).get();
      if (doc.exists) {
        final ownerInDb = doc.data()?['owner_mail'];
        print("Veritabanındaki Owner Mail: '$ownerInDb'");

        if (ownerInDb != _currentUserEmail) {
          print("!!! UYUŞMAZLIK VAR !!! Harf hatası veya boşluk olabilir.");
        } else {
          print("Mailler Eşleşiyor. Yetki verilmeli.");
        }
      } else {
        print("Cihaz veritabanında bulunamadı.");
      }
      // --- DEBUG BİTİŞİ ---

      _currentRole = await _databaseService.getUserRole(widget.macAddress, user.email);
    }

    await _loadSections();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSections() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('dispenser').doc(widget.macAddress).get();
      if (!mounted) return;

      if (doc.exists && doc.data()!.containsKey('section_config')) {
        final List<dynamic> configData = doc.data()!['section_config'];
        _sections = configData.map((item) {
          final Map<String, dynamic> section = item as Map<String, dynamic>;
          final bool isActive = section['isActive'] ?? false;
          final TimeOfDay time = isActive
              ? TimeOfDay(hour: section['hour'], minute: section['minute'])
              : const TimeOfDay(hour: 8, minute: 0);

          return {
            'name': section['name'],
            'time': time,
            'isActive': isActive,
          };
        }).toList();
      } else {
        // Veri yoksa varsayılan oluştur
        _sections = List.generate(4, (index) {
          return {
            'name': 'Bölme ${index + 1}',
            'time': TimeOfDay(hour: (8 + 2 * index) % 24, minute: 0),
            'isActive': true,
          };
        });

        // Sadece yetkili ise varsayılan ayarları kaydet
        if (_canEdit()) {
          await _saveSectionConfig();
        }
      }

      // İzleyici bile olsa kendi telefonunda bildirimleri planlar (Local Notification)
      _notificationService.scheduleMedicationNotifications(_sections);

    } catch (e) {
      print("Error loading sections: $e");
    }
  }

  // Sadece Owner ve Secondary çağırabilir
  Future<void> _saveSectionConfig() async {
    if (!_canEdit()) return;

    final List<Map<String, dynamic>> serializableList = _sections.map((section) {
      final time = section['time'] as TimeOfDay;
      return {
        'name': section['name'],
        'hour': time.hour,
        'minute': time.minute,
        'isActive': section['isActive'] ?? false,
      };
    }).toList();

    await _databaseService.saveSectionConfig(widget.macAddress, serializableList);
    // Veritabanı değiştikten sonra bildirimleri tekrar planla
    await _notificationService.scheduleMedicationNotifications(_sections);
  }

  void _updateSection(int index, Map<String, dynamic> data) {
    if (!_canEdit()) {
      _showReadOnlyWarning();
      return;
    }

    setState(() {
      _sections[index].addAll(data);
      _sections[index]['isActive'] = true;
    });
    _saveSectionConfig();
  }

  // YETKİ KONTROLÜ
  bool _canEdit() {
    return _currentRole == DeviceRole.owner || _currentRole == DeviceRole.secondary;
  }

  void _showReadOnlyWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sadece İzleyici modundasınız. Değişiklik yapmak için cihaz sahibinden yetki isteyin.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // --- KULLANICI YÖNETİMİ DİYALOGU (Sadece Owner) ---
  void _showUserManagementDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('dispenser').doc(widget.macAddress).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final readOnlyUsers = List<String>.from(data['read_only_mails'] ?? []);
            final secondaryUsers = List<String>.from(data['secondary_mails'] ?? []);

            return AlertDialog(
              title: const Text('Kullanıcı Yönetimi'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (readOnlyUsers.isEmpty && secondaryUsers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text("Henüz başka kullanıcı yok."),
                      ),

                    // 1. İzleyiciler (Yetki Verilebilir)
                    if (readOnlyUsers.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('İzleyiciler (Yetki Bekleyenler)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ...readOnlyUsers.map((email) => ListTile(
                        dense: true,
                        title: Text(email),
                        subtitle: const Text("Salt Okunur"),
                        trailing: IconButton(
                          icon: const Icon(Icons.arrow_upward_rounded, color: Colors.green),
                          tooltip: 'Yönetici Yap',
                          onPressed: () async {
                            // DatabaseService içindeki promoteToSecondary fonksiyonunu kullanıyoruz
                            await _databaseService.promoteToSecondary(widget.macAddress, email);
                          },
                        ),
                      )),
                      const Divider(),
                    ],

                    // 2. Yöneticiler (Zaten Yetkili)
                    if (secondaryUsers.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('Yöneticiler', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      ),
                      ...secondaryUsers.map((email) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.verified_user, color: Colors.blue, size: 20),
                        title: Text(email),
                      )),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Kapat'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- ALARM AYARLARI DİYALOGU ---
  // Not: İzleyiciler de bu menüye girebilir çünkü bu ayarlar (offset vb.)
  // cihazın kendisine değil, telefondaki yerel uygulamaya (SharedPreferences) kaydedilir.
  Future<void> _showNotificationSettingsDialog() async {
    final settings = await _notificationService.getNotificationSettings();
    bool notificationsEnabled = settings['enabled'];
    int offset = settings['offset'];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateInDialog) {
            return AlertDialog(
              title: const Text('Alarm Ayarları'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_canEdit())
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        "Not: Bu ayarlar sadece sizin telefonunuzu etkiler. Cihaz saatlerini değiştiremezsiniz.",
                        style: TextStyle(fontSize: 12, color: Colors.orange, fontStyle: FontStyle.italic),
                      ),
                    ),
                  SwitchListTile(
                    title: const Text('Alarmları Aktif Et'),
                    value: notificationsEnabled,
                    onChanged: (value) {
                      setStateInDialog(() {
                        notificationsEnabled = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('İlaç saatinden ne kadar önce haber verilsin?'),
                  DropdownButton<int>(
                    value: offset,
                    items: [0, 5, 10, 15, 30].map<DropdownMenuItem<int>>((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text(value == 0 ? 'Tam zamanında' : '$value dakika önce'),
                      );
                    }).toList(),
                    onChanged: notificationsEnabled
                        ? (int? newValue) {
                      setStateInDialog(() {
                        offset = newValue!;
                      });
                    }
                        : null,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // Yerel ayarları kaydet
                    await _notificationService.saveNotificationSettings(
                      enabled: notificationsEnabled,
                      offset: offset,
                    );
                    // Bildirimleri tekrar planla (kendi telefonu için)
                    await _notificationService.scheduleMedicationNotifications(_sections);

                    if (mounted) Navigator.of(context).pop();

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Alarm ayarları kaydedildi.')),
                    );
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isReadOnly = !_canEdit();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihaz Ayarları'),
        actions: [
          // 1. KULLANICI YÖNETİMİ BUTONU (Sadece Owner Görebilir)
          if (_currentRole == DeviceRole.owner)
            IconButton(
              icon: const Icon(Icons.manage_accounts_rounded),
              tooltip: 'Kullanıcıları Yönet',
              onPressed: _showUserManagementDialog,
            ),

          // 2. ALARM AYARLARI BUTONU (Herkes Görebilir)
          IconButton(
            icon: const Icon(Icons.alarm_add_rounded, size: 30),
            tooltip: 'Alarm Ayarları',
            onPressed: _showNotificationSettingsDialog,
          ),

          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // İZLEYİCİ UYARISI
              if (isReadOnly)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline, color: Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "İzleyici Modu: İlaç saatlerini sadece cihaz sahibi değiştirebilir. Siz sadece bildirim alabilirsiniz.",
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.w600
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
              // BİLGİ KARTI (Sadece yetkililer için)
                Card(
                  color: colorScheme.primaryContainer.withOpacity(0.6),
                  margin: const EdgeInsets.only(bottom: 30),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        Icon(Icons.tips_and_updates_outlined, color: colorScheme.onPrimaryContainer, size: 28),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Text(
                            'İlaç saatlerinizi dairesel seçiciden veya listeden kolayca ayarlayın.',
                            style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              Center(
                child: Container(
                  height: MediaQuery.of(context).size.width * 0.85,
                  width: MediaQuery.of(context).size.width * 0.85,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.15),
                        spreadRadius: 5,
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  // İZLEYİCİ İSE DOKUNMAYI ENGELLE
                  child: AbsorbPointer(
                    absorbing: isReadOnly,
                    child: CircularSelector(
                      key: _circularSelectorKey,
                      sections: _sections,
                      onUpdate: _updateSection,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  'Planlanmış İlaçlar',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 15),

              ..._sections.asMap().entries.map((entry) {
                int index = entry.key;
                Map<String, dynamic> section = entry.value;
                TimeOfDay time = section['time'] as TimeOfDay;
                bool isActive = section['isActive'] ?? false;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 7),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: isReadOnly ? Colors.grey.shade200 : colorScheme.primary.withOpacity(0.1),
                      child: Icon(
                          Icons.medication_liquid_rounded,
                          color: isReadOnly ? Colors.grey : colorScheme.primary,
                          size: 28
                      ),
                    ),
                    title: Text(
                      section['name'],
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 19),
                    ),
                    subtitle: Text(
                      isActive ? 'Saat: ${time.format(context)}' : 'Pasif',
                      style: theme.textTheme.bodyMedium?.copyWith(color: isActive ? colorScheme.onSurfaceVariant : Colors.grey),
                    ),
                    // İZLEYİCİ İSE KİLİT GÖSTER, DEĞİLSE EDİT BUTONLARINI GÖSTER
                    trailing: isReadOnly
                        ? const Tooltip(
                      message: "Değiştirme yetkiniz yok",
                      child: Icon(Icons.lock, color: Colors.grey),
                    )
                        : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: isActive,
                          onChanged: (bool value) {
                            setState(() {
                              _sections[index]['isActive'] = value;
                            });
                            _saveSectionConfig();
                          },
                          activeColor: colorScheme.primary,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Düzenle',
                          onPressed: () {
                            _circularSelectorKey.currentState?.showEditDialog(index);
                          },
                        ),
                      ],
                    ),
                    onTap: isReadOnly
                        ? () => _showReadOnlyWarning()
                        : () {
                      _circularSelectorKey.currentState?.showEditDialog(index);
                    },
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }
}