import 'dart:convert';
import 'package:dispenserapp/features/ble_provisioning/sync_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dispenserapp/widgets/circular_selector.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/database_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<CircularSelectorState> _circularSelectorKey = GlobalKey<CircularSelectorState>();
  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();
  
  String? _userUid;
  List<Map<String, dynamic>> _sections = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeUserAndLoadData();
  }

  Future<void> _initializeUserAndLoadData() async {
    final uid = await _authService.getOrCreateUser();
    if (uid != null) {
      setState(() {
        _userUid = uid;
        _isLoading = false;
      });
      _loadSections();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSections() async {
    if (_userUid == null) return;

    final prefs = await SharedPreferences.getInstance();
    final String? sectionsString = prefs.getString('sections_$_userUid'); // User-specific key

    if (sectionsString != null) {
      final List<dynamic> decoded = json.decode(sectionsString);
      if (decoded.isNotEmpty && decoded.length == 6) {
        setState(() {
          _sections = decoded.map((item) {
            return {
              'name': item['name'],
              'time': TimeOfDay(hour: item['hour'], minute: item['minute']),
              'isActive': item['isActive'] ?? false,
            };
          }).toList();
        });
        return;
      }
    }

    setState(() {
      _sections = List.generate(6, (index) {
        return {
          'name': 'Bölme ${index + 1}',
          'time': TimeOfDay(hour: (8 + 2 * index) % 24, minute: 0),
          'isActive': true,
        };
      });
    });
    _saveSections();
  }

  Future<void> _saveSections() async {
    if (_userUid == null) return;

    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> serializableList = _sections.map((section) {
      final time = section['time'] as TimeOfDay;
      return {
        'name': section['name'],
        'hour': time.hour,
        'minute': time.minute,
        'isActive': section['isActive'] ?? false,
      };
    }).toList();
    
    await prefs.setString('sections_$_userUid', json.encode(serializableList));
    await _databaseService.saveSections(_userUid!, serializableList);
  }

  void _updateSection(int index, Map<String, dynamic> data) {
    setState(() {
      _sections[index].addAll(data);
    });
    _saveSections();
  }

  void _deleteSection(int index) {
    setState(() {
      _sections[index] = {
        'name': 'Bölme ${index + 1}',
        'time': TimeOfDay(hour: (8 + 2 * index) % 24, minute: 0),
        'isActive': false,
      };
    });
    _saveSections();
  }

  Future<void> _showDeleteConfirmationDialog(int index) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('İlaç Bölmesini Boşalt'),
          content: const Text('Bu ilaç bölmesini boşaltmak istediğinizden emin misiniz?'),
          actions: <Widget>[
            TextButton(
              child: const Text('İptal'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              onPressed: () {
                _deleteSection(index);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Boşalt'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
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
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 7),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          leading: CircleAvatar(
                            backgroundColor: colorScheme.primary.withOpacity(0.1),
                            child: Icon(Icons.medication_liquid_rounded, color: colorScheme.primary, size: 28),
                          ),
                          title: Text(
                            section['name'],
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 19),
                          ),
                          subtitle: Text(
                            'Saat: ${time.format(context)}',
                            style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: section['isActive'] ?? false,
                                onChanged: (bool value) {
                                  setState(() {
                                    _sections[index]['isActive'] = value;
                                  });
                                  _saveSections();
                                },
                                activeColor: colorScheme.primary,
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _circularSelectorKey.currentState?.showEditDialog(index);
                                  } else if (value == 'delete') {
                                    _showDeleteConfirmationDialog(index);
                                  }
                                },
                                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                  const PopupMenuItem<String>(
                                    value: 'edit',
                                    child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Düzenle')),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'delete',
                                    child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Bölmeyi Boşalt')),
                                  ),
                                ],
                                icon: const Icon(Icons.more_vert_rounded),
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
