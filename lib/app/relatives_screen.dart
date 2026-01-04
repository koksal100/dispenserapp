import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dispenserapp/app/reports_screen.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/database_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class RelativesScreen extends StatefulWidget {
  const RelativesScreen({super.key});

  @override
  State<RelativesScreen> createState() => _RelativesScreenState();
}

class _RelativesScreenState extends State<RelativesScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();

  String? _currentUid;
  String? _currentEmail;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  Future<void> _initUser() async {
    final user = await _authService.getOrCreateUser();
    if (user != null) {
      setState(() {
        _currentUid = user.uid;
        _currentEmail = user.email;
        _isLoading = false;
      });
    }
  }

  // Takma İsim Düzenleme
  void _showEditNicknameDialog(String email, String currentNickname) {
    final controller = TextEditingController(text: currentNickname);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("edit_nickname".tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("nickname_hint".tr(), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "father_mom_etc".tr(),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("cancel".tr()),
          ),
          ElevatedButton(
            onPressed: () {
              if (_currentUid != null) {
                _dbService.updateRelativeNickname(_currentUid!, email, controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: Text("save".tr()),
          ),
        ],
      ),
    );
  }

  // Ortak cihazları bulma
  Future<List<Map<String, String>>> _getCommonDevices(String otherEmail) async {
    List<Map<String, String>> commonDevices = [];
    if(_currentUid == null || _currentEmail == null) return [];

    // Benim listemdeki cihazlar
    final myDevices = await _dbService.getAllUserDevices(_currentUid!, _currentEmail!);

    for (var device in myDevices) {
      String mac = device['mac']!;
      var doc = await FirebaseFirestore.instance.collection('dispenser').doc(mac).get();
      if (doc.exists) {
        var data = doc.data()!;
        List<String> allUsers = [];
        if (data['owner_mail'] != null) allUsers.add(data['owner_mail']);
        if (data['secondary_mails'] != null) allUsers.addAll(List<String>.from(data['secondary_mails']));
        if (data['read_only_mails'] != null) allUsers.addAll(List<String>.from(data['read_only_mails']));

        // Diğer kişi listede mi?
        if (allUsers.map((e) => e.toLowerCase()).contains(otherEmail.toLowerCase())) {
          commonDevices.add(device);
        }
      }
    }
    return commonDevices;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_currentUid == null) return const Center(child: Text("Giriş hatası"));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(_currentUid).snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());

          Map<String, dynamic> nicknamesMap = {};
          try {
            nicknamesMap = userSnapshot.data!.get('relatives_nicknames') as Map<String, dynamic>;
          } catch (e) { }

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _dbService.getRelativesInfo(_currentUid!, _currentEmail!),
            builder: (context, relativesSnapshot) {
              if (relativesSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final relatives = relativesSnapshot.data ?? [];

              if (relatives.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                        child: Icon(Icons.people_outline_rounded, size: 60, color: Colors.blue.shade200),
                      ),
                      const SizedBox(height: 16),
                      Text("no_relatives_found".tr(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700)),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text("no_relatives_desc".tr(), textAlign: TextAlign.center, style: TextStyle(color: Colors.blueGrey.shade400)),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: relatives.length,
                itemBuilder: (context, index) {
                  final person = relatives[index];
                  final String email = person['email'];
                  final String rawName = person['displayName'];
                  final String photoUrl = person['photoURL'];

                  String safeKey = email.replaceAll('.', '_dot_');
                  String? nickname = nicknamesMap[safeKey];
                  String displayName = (nickname != null && nickname.isNotEmpty)
                      ? nickname
                      : (rawName.isNotEmpty ? rawName : email.split('@')[0]);

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          radius: 26,
                          backgroundColor: const Color(0xFF1D8AD6),
                          backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                          child: (photoUrl.isEmpty)
                              ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : "?", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20))
                              : null,
                        ),
                        title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF0F5191))),
                        subtitle: Text(email, style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade300), overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _showEditNicknameDialog(email, nickname ?? ""),
                              icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF36C0A6)),
                              tooltip: "edit_nickname".tr(),
                            ),
                            const Icon(Icons.expand_more, color: Colors.grey),
                          ],
                        ),
                        children: [
                          FutureBuilder<List<Map<String, String>>>(
                            future: _getCommonDevices(email),
                            builder: (context, deviceSnap) {
                              if (deviceSnap.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator());

                              final devices = deviceSnap.data ?? [];

                              if (devices.isEmpty) return Padding(padding: const EdgeInsets.all(16.0), child: Text("Ortak cihaz yok", style: TextStyle(color: Colors.grey.shade600)));

                              return Column(
                                children: devices.map((device) {
                                  return ListTile(
                                    contentPadding: const EdgeInsets.only(left: 72, right: 16),
                                    title: Text(device['name']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F5191))),
                                    subtitle: Text(device['mac']!, style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                    trailing: const Icon(Icons.bar_chart_rounded, color: Color(0xFF36C0A6)),
                                    onTap: () async {
                                      // 1. Kullanıcı ID'sini bul
                                      String? targetUid = await _dbService.getUserIdByEmail(email);
                                      if (targetUid == null) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Kullanıcı verisine ulaşılamadı.")));
                                        return;
                                      }

                                      // 2. Feedback açık mı kontrol et
                                      bool isFeedbackOn = await _dbService.getDeviceFeedbackPreference(targetUid, device['mac']!);

                                      if (isFeedbackOn) {
                                        Navigator.push(context, MaterialPageRoute(
                                            builder: (context) => ReportsScreen(
                                              macAddress: device['mac']!,
                                              targetUserId: targetUid,
                                              titlePrefix: displayName,
                                            )
                                        ));
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Bu kullanıcı geri bildirimi kapatmış.")));
                                      }
                                    },
                                  );
                                }).toList(),
                              );
                            },
                          )
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}