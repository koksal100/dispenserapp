import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'circular_selector.dart'; // circular_selector.dart dosyasını çağır

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<CircularSelectorState> _circularSelectorKey = GlobalKey<CircularSelectorState>();
  List<Map<String, dynamic>> _sections = [];

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  Future<void> _loadSections() async {
    final prefs = await SharedPreferences.getInstance();
    final String? sectionsString = prefs.getString('sections');
    if (sectionsString != null) {
      final List<dynamic> decoded = json.decode(sectionsString);
      if (decoded.isNotEmpty && decoded.length == 6) { // Make sure we have 6 sections
        setState(() {
          _sections = decoded.map((item) {
            return {
              'name': item['name'],
              'time': TimeOfDay(hour: item['hour'], minute: item['minute']),
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
        };
      });
    });
    _saveSections();
  }

  Future<void> _saveSections() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> serializableList = _sections.map((section) {
      final time = section['time'] as TimeOfDay;
      return {
        'name': section['name'],
        'hour': time.hour,
        'minute': time.minute,
      };
    }).toList();
    await prefs.setString('sections', json.encode(serializableList));
  }

  void _updateSection(int index, Map<String, dynamic> data) {
    setState(() {
      _sections[index] = data;
    });
    _saveSections();
  }
  
  void _deleteSection(int index) {
    setState(() {
      _sections[index] = {
        'name': 'Bölme ${index + 1}',
        'time': TimeOfDay(hour: (8 + 2 * index) % 24, minute: 0),
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
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          '💊 İlaç Takip',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Card(
                color: Colors.teal.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, color: Colors.teal),
                      SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          'İlaç hatırlatmalarınızı ayarlayın. Saatleri daireden veya listeden düzenleyebilirsiniz.',
                          style: TextStyle(color: Colors.teal, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              Center(
                child: Container(
                  height: MediaQuery.of(context).size.width * 0.8,
                  width: MediaQuery.of(context).size.width * 0.8,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        spreadRadius: 3,
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(10),
                  child: CircularSelector(
                    key: _circularSelectorKey,
                    sections: _sections,
                    onUpdate: _updateSection,
                  ),
                ),
              ),
              const SizedBox(height: 30),

              const Text(
                'Planlanmış İlaçlar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              ..._sections.asMap().entries.map((entry) {
                int index = entry.key;
                Map<String, dynamic> section = entry.value;
                TimeOfDay time = section['time'] as TimeOfDay;

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                      child: Icon(Icons.medication, color: Theme.of(context).primaryColor),
                    ),
                    title: Text(
                      section['name'],
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                    ),
                    subtitle: Text(
                      'Saat: ${time.format(context)}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    trailing: PopupMenuButton<String>(
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
                      icon: const Icon(Icons.more_vert),
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
