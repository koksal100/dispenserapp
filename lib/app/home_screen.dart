import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dispenserapp/features/ble_provisioning/sync_screen.dart';
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

  List<Map<String, dynamic>> _sections = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  Future<void> _loadSections() async {
    setState(() {
      _isLoading = true;
    });

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
        _sections = List.generate(4, (index) {
          return {
            'name': 'Bölme ${index + 1}',
            'time': TimeOfDay(hour: (8 + 2 * index) % 24, minute: 0),
            'isActive': true,
          };
        });
        await _saveSectionConfig();
      }
    } catch (e) {
      print("Error loading sections: $e");
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
    // Schedule notifications on initial load
    _notificationService.scheduleMedicationNotifications(_sections);
  }

  Future<void> _saveSectionConfig() async {
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
    // Reschedule notifications after saving
    await _notificationService.scheduleMedicationNotifications(_sections);
  }

  void _updateSection(int index, Map<String, dynamic> data) {
    setState(() {
      _sections[index].addAll(data);
      _sections[index]['isActive'] = true;
    });
    _saveSectionConfig(); // This will also trigger rescheduling notifications
  }
  
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
                        : null, // Disable if notifications are off
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
                    await _notificationService.saveNotificationSettings(
                      enabled: notificationsEnabled,
                      offset: offset,
                    );
                    // Reschedule notifications with new settings
                    await _notificationService.scheduleMedicationNotifications(_sections);
                    Navigator.of(context).pop();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihaz Ayarları'),
        actions: [
          IconButton(
            icon: const Icon(Icons.alarm_add_rounded),
            tooltip: 'Alarm Ayarları',
            onPressed: _showNotificationSettingsDialog,
          ),
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
                    Card(
                      color: colorScheme.primaryContainer.withOpacity(0.6),
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
                    const SizedBox(height: 30),
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
                        child: CircularSelector(
                          key: _circularSelectorKey,
                          sections: _sections,
                          onUpdate: _updateSection,
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
                            backgroundColor: colorScheme.primary.withOpacity(0.1),
                            child: Icon(Icons.medication_liquid_rounded, color: colorScheme.primary, size: 28),
                          ),
                          title: Text(
                            section['name'],
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 19),
                          ),
                          subtitle: Text(
                            isActive ? 'Saat: ${time.format(context)}' : 'Pasif',
                            style: theme.textTheme.bodyMedium?.copyWith(color: isActive ? colorScheme.onSurfaceVariant : Colors.grey),
                          ),
                          trailing: Row(
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
                          onTap: () {
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
