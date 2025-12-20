import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/notification_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:dispenserapp/widgets/circular_selector.dart';
import 'package:dispenserapp/services/database_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  // ARTIK YAPIMIZ: 'times': List<TimeOfDay>
  List<Map<String, dynamic>> _sections = [];
  bool _isLoading = true;
  bool _isRinging = false;

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
      _currentUserEmail = user.email;
      _currentRole = await _databaseService.getUserRole(widget.macAddress, user.email);
    }
    await _loadSections();
    if (mounted) setState(() => _isLoading = false);
  }

  // --- ÇOKLU SAAT DESTEKLİ YÜKLEME ---
  Future<void> _loadSections() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('dispenser').doc(widget.macAddress).get();
      if (!mounted) return;

      bool dataIsValid = false;

      if (doc.exists && doc.data()!.containsKey('section_config')) {
        final List<dynamic> configData = doc.data()!['section_config'];

        if (configData.length == 3) {
          dataIsValid = true;
          _sections = configData.map((item) {
            final Map<String, dynamic> section = item as Map<String, dynamic>;
            final bool isActive = section['isActive'] ?? false;

            // YENİ FORMAT: 'schedule' listesi var mı?
            List<TimeOfDay> times = [];
            if (section.containsKey('schedule')) {
              // Yeni format: [{h:8, m:0}, {h:12, m:0}]
              times = (section['schedule'] as List).map((t) {
                return TimeOfDay(hour: t['h'], minute: t['m']);
              }).toList();
            } else {
              // Eski format (Tekil saat): {hour: 8, minute: 0}
              // Geriye dönük uyumluluk için
              if (isActive) {
                times.add(TimeOfDay(hour: section['hour'] ?? 8, minute: section['minute'] ?? 0));
              }
            }

            // Eğer hiç saat yoksa varsayılan bir saat ekle (Aktifse)
            if (times.isEmpty && isActive) {
              times.add(const TimeOfDay(hour: 8, minute: 0));
            }

            return {
              'name': section['name'],
              'times': times, // ARTIK LİSTE
              'isActive': isActive,
            };
          }).toList();
        }
      }

      // Veri yoksa veya hatalıysa (4 bölme vb.) sıfırla
      if (!dataIsValid) {
        _sections = List.generate(3, (index) {
          return {
            'name': 'medicine_default_name'.tr(args: [(index + 1).toString()]),
            'times': [TimeOfDay(hour: (8 + 5 * index) % 24, minute: 0)], // Varsayılan tek saat
            'isActive': true,
          };
        });

        if (_canEdit()) {
          await _saveSectionConfig();
        }
      }

      _notificationService.scheduleMedicationNotifications(_sections);

    } catch (e) {
      print("Error loading sections: $e");
    }
  }

  // --- ÇOKLU SAAT DESTEKLİ KAYIT ---
  Future<void> _saveSectionConfig() async {
    if (!_canEdit()) return;

    final List<Map<String, dynamic>> serializableList = _sections.map((section) {
      final List<TimeOfDay> times = section['times'] as List<TimeOfDay>;

      // Saatleri her zaman sıralı kaydedelim (Sabah -> Akşam)
      times.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

      return {
        'name': section['name'],
        'isActive': section['isActive'] ?? false,
        // SADECE SCHEDULE LİSTESİ OLUŞTURUYORUZ
        'schedule': times.map((t) => {'h': t.hour, 'm': t.minute}).toList(),
      };
    }).toList();

    await _databaseService.saveSectionConfig(widget.macAddress, serializableList);
    // await _notificationService.scheduleMedicationNotifications(_sections);
  }

  void _updateSection(int index, Map<String, dynamic> data) {
    if (!_canEdit()) {
      _showReadOnlyWarning();
      return;
    }

    setState(() {
      _sections[index].addAll(data);
      _sections[index]['isActive'] = true; // Düzenleyince aktif olsun
    });
    _saveSectionConfig();
  }

  Future<void> _handleBuzzer() async {
    setState(() => _isRinging = !_isRinging);
    await _databaseService.toggleBuzzer(widget.macAddress, _isRinging);
    if (_isRinging) {
      Future.delayed(const Duration(seconds: 3), () async {
        if (mounted && _isRinging) {
          setState(() => _isRinging = false);
          await _databaseService.toggleBuzzer(widget.macAddress, false);
        }
      });
    }
  }

  bool _canEdit() => _currentRole == DeviceRole.owner || _currentRole == DeviceRole.secondary;

  void _showReadOnlyWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("read_only_warning".tr()), backgroundColor: Colors.orange, duration: const Duration(seconds: 2)),
    );
  }

  // --- KULLANICI YÖNETİMİ DİYALOGU ---
  void _showUserManagementDialog() {
    final TextEditingController emailController = TextEditingController();

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
              title: Text("access_management_title".tr()),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: emailController,
                            decoration: InputDecoration(
                              hintText: "user_email_hint".tr(),
                              labelText: "grant_access".tr(),
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          style: IconButton.styleFrom(backgroundColor: Colors.green.shade50),
                          icon: const Icon(Icons.person_add, color: Colors.green),
                          tooltip: "add".tr(),
                          onPressed: () {
                            final mail = emailController.text.trim();
                            if (mail.isNotEmpty) {
                              _databaseService.addReadOnlyUser(widget.macAddress, mail);
                              emailController.clear();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text("user_list_title".tr(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (readOnlyUsers.isEmpty && secondaryUsers.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text("no_users_yet".tr(), style: const TextStyle(fontStyle: FontStyle.italic)),
                            ),
                          ...readOnlyUsers.map((email) => Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              leading: const Icon(Icons.remove_red_eye, color: Colors.grey),
                              title: Text(email, style: const TextStyle(fontSize: 13)),
                              subtitle: Text("viewer".tr()),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_upward_rounded, color: Colors.green),
                                    tooltip: "promote_admin".tr(),
                                    onPressed: () async {
                                      await _databaseService.promoteToSecondary(widget.macAddress, email);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    tooltip: "delete".tr(),
                                    onPressed: () async {
                                      await _databaseService.removeUser(widget.macAddress, email);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          )),
                          ...secondaryUsers.map((email) => Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: Colors.blue.shade50,
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              leading: const Icon(Icons.verified_user, color: Colors.blue),
                              title: Text(email, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              subtitle: Text("admin".tr()),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_downward_rounded, color: Colors.orange),
                                    tooltip: "demote_viewer".tr(),
                                    onPressed: () async {
                                      await _databaseService.demoteToReadOnly(widget.macAddress, email);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    tooltip: "delete".tr(),
                                    onPressed: () async {
                                      await _databaseService.removeUser(widget.macAddress, email);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text("close".tr()),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- ALARM AYARLARI ---
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
              title: Text("alarm_settings_title".tr()),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_canEdit())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        "alarm_settings_note".tr(),
                        style: const TextStyle(fontSize: 12, color: Colors.orange, fontStyle: FontStyle.italic),
                      ),
                    ),
                  SwitchListTile(
                    title: Text("enable_alarms".tr()),
                    value: notificationsEnabled,
                    onChanged: (value) {
                      setStateInDialog(() {
                        notificationsEnabled = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Text("alarm_offset_label".tr()),
                  DropdownButton<int>(
                    value: offset,
                    items: [0, 5, 10, 15, 30].map<DropdownMenuItem<int>>((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text(value == 0 ? "exact_time".tr() : "minutes_before".tr(args: [value.toString()])),
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
                  child: Text("cancel".tr()),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _notificationService.saveNotificationSettings(
                      enabled: notificationsEnabled,
                      offset: offset,
                    );
                    await _notificationService.scheduleMedicationNotifications(_sections);
                    if (mounted) Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("alarm_settings_saved".tr())),
                    );
                  },
                  child: Text("save".tr()),
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
        title: Text("device_settings_title".tr()),
        actions: [
          if (_currentRole == DeviceRole.owner)
            IconButton(
              icon: const Icon(Icons.manage_accounts_rounded),
              tooltip: "access_management_title".tr(),
              onPressed: _showUserManagementDialog,
            ),
          IconButton(
            icon: const Icon(Icons.alarm_add_rounded, size: 30),
            tooltip: "alarm_settings_title".tr(),
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
              if (isReadOnly)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
                  child: Row(children: [const Icon(Icons.lock_outline, color: Colors.orange), const SizedBox(width: 12), Expanded(child: Text("read_only_banner".tr(), style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange.shade900, fontWeight: FontWeight.w600)))]),
                )
              else
                Card(
                  color: colorScheme.primaryContainer.withOpacity(0.6),
                  margin: const EdgeInsets.only(bottom: 30),
                  child: Padding(padding: const EdgeInsets.all(20.0), child: Row(children: [Icon(Icons.tips_and_updates_outlined, color: colorScheme.onPrimaryContainer, size: 28), const SizedBox(width: 15), Expanded(child: Text("home_hint_text".tr(), style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w500)))])),
                ),

              Center(
                child: Container(
                  height: MediaQuery.of(context).size.width * 0.85,
                  width: MediaQuery.of(context).size.width * 0.85,
                  decoration: BoxDecoration(color: colorScheme.surface, shape: BoxShape.circle, boxShadow: [BoxShadow(color: colorScheme.primary.withOpacity(0.15), spreadRadius: 5, blurRadius: 20)]),
                  child: AbsorbPointer(
                    absorbing: isReadOnly,
                    child: CircularSelector(key: _circularSelectorKey, sections: _sections, onUpdate: _updateSection),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              if (!isReadOnly)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Center(
                    child: SizedBox(
                      width: 220, height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _handleBuzzer,
                        style: ElevatedButton.styleFrom(backgroundColor: _isRinging ? Colors.red : colorScheme.primary, foregroundColor: Colors.white, elevation: 4),
                        icon: Icon(_isRinging ? Icons.stop_circle_outlined : Icons.wifi_tethering),
                        label: Text(_isRinging ? "stop_sound".tr() : "find_device".tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text("scheduled_meds_title".tr(), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 15),

              // --- PLANLANMIŞ İLAÇLAR LİSTESİ (ÇOKLU SAAT GÖRÜNÜMÜ) ---
              ..._sections.asMap().entries.map((entry) {
                int index = entry.key;
                Map<String, dynamic> section = entry.value;
                List<TimeOfDay> times = section['times'] as List<TimeOfDay>;
                bool isActive = section['isActive'] ?? false;

                // Saatleri sırala
                times.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 7),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: isReadOnly ? Colors.grey.shade200 : colorScheme.primary.withOpacity(0.1),
                              child: Icon(Icons.medication_liquid_rounded, color: isReadOnly ? Colors.grey : colorScheme.primary, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                section['name'],
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 19),
                              ),
                            ),

                            // --- SAĞ TARAFTAKİ BUTONLAR ---
                            if (!isReadOnly) ...[
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: "edit".tr(),
                                onPressed: () {
                                  _circularSelectorKey.currentState?.showEditDialog(index);
                                },
                              ),
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
                            ] else
                              Tooltip(
                                message: "no_permission".tr(),
                                child: const Icon(Icons.lock, color: Colors.grey),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // SAATLERİ GÖSTEREN KISIM (CHIP LIST)
                        if (!isActive)
                          Padding(
                            padding: const EdgeInsets.only(left: 56.0),
                            child: Text("passive".tr(), style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                          )
                        else if (times.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 56.0),
                            child: Text("no_times_added".tr(), style: TextStyle(color: Colors.orange.shade300)),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(left: 56.0),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: times.map((t) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.access_time, size: 14, color: colorScheme.primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        t.format(context),
                                        style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          )
                      ],
                    ),
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