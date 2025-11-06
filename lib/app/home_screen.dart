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
      });
      await _loadSections();
    } 
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadSections() async {
    if (_userUid == null) return;

    final prefs = await SharedPreferences.getInstance();
    final String? sectionsString = prefs.getString('sections_$_userUid');

    if (sectionsString != null) {
      final List<dynamic> decoded = json.decode(sectionsString);
      if (decoded.isNotEmpty && decoded.length == 6) {
        _sections = decoded.asMap().entries.map((entry) {
            final int index = entry.key;
            final Map<String, dynamic> item = entry.value;
            final bool isActive = item['hour'] != -1;
            
            final TimeOfDay time = isActive
                ? TimeOfDay(hour: item['hour'], minute: item['minute'])
                : TimeOfDay(hour: (8 + 2 * index) % 24, minute: 0); // Default time for inactive

            return {
              'name': item['name'],
              'time': time,
              'isActive': isActive,
            };
        }).toList();
        return;
      }
    }

    _sections = List.generate(6, (index) {
      return {
        'name': 'Bölme ${index + 1}',
        'time': TimeOfDay(hour: (8 + 2 * index) % 24, minute: 0),
        'isActive': false, 
      };
    });
    await _saveSections();
  }

  Future<void> _saveSections() async {
    if (_userUid == null) return;

    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> serializableList = _sections.map((section) {
      final time = section['time'] as TimeOfDay;
      final bool isActive = section['isActive'] ?? false;
      
      return {
        'name': section['name'],
        'hour': isActive ? time.hour : -1,
        'minute': isActive ? time.minute : 0,
      };
    }).toList();
    
    await prefs.setString('sections_$_userUid', json.encode(serializableList));
    await _databaseService.saveSections(_userUid!, serializableList);
  }

  void _updateSection(int index, Map<String, dynamic> data) {
    setState(() {
      _sections[index].addAll(data);
      _sections[index]['isActive'] = true;
    });
    _saveSections();
  }

  void _deactivateSection(int index) {
    setState(() {
      _sections[index]['isActive'] = false;
    });
    _saveSections();
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
                                  _saveSections();
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
