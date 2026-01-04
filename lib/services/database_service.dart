import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;

// Roller için enum tanımı
enum DeviceRole { owner, secondary, readOnly, none }

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Realtime Database (ESP32 ile haberleşme için)
  final rtdb.FirebaseDatabase _rtdb = rtdb.FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://smartmedicinedispenser-default-rtdb.europe-west1.firebasedatabase.app',
  );

  // --- YARDIMCI METOTLAR ---
  String _sanitize(String email) => email.trim().toLowerCase();

  // ===========================================================================
  // --- BÖLÜM 1: CİHAZ LİSTELEME VE SENKRONİZASYON ---
  // ===========================================================================

  Future<List<Map<String, String>>> getAllUserDevices(String uid, String rawEmail) async {
    List<Map<String, String>> devices = [];
    String email = _sanitize(rawEmail);

    try {
      var results = await Future.wait([
        _firestore.collection('dispenser').where('owner_mail', isEqualTo: email).get(),
        _firestore.collection('dispenser').where('secondary_mails', arrayContains: email).get(),
        _firestore.collection('dispenser').where('read_only_mails', arrayContains: email).get(),
      ]);

      Set<String> addedMacs = {};

      for (var snapshot in results) {
        for (var doc in snapshot.docs) {
          if (!addedMacs.contains(doc.id)) {
            addedMacs.add(doc.id);
            String name = 'Bilinmeyen Cihaz';
            if (doc.data().containsKey('device_name')) {
              name = doc.get('device_name');
            }
            devices.add({
              'mac': doc.id,
              'name': name,
            });
          }
        }
      }
    } catch (e) {
      print("Cihaz listesi çekme hatası: $e");
    }
    return devices;
  }

  Future<void> updateUserDeviceList(String uid, String rawEmail) async {
    if (uid.isEmpty || rawEmail.isEmpty) return;
    final String email = _sanitize(rawEmail);

    try {
      final ownerQuery = await _firestore.collection('dispenser').where('owner_mail', isEqualTo: email).get();
      final secondaryQuery = await _firestore.collection('dispenser').where('secondary_mails', arrayContains: email).get();
      final readOnlyQuery = await _firestore.collection('dispenser').where('read_only_mails', arrayContains: email).get();

      final Set<String> ownedIds = ownerQuery.docs.map((d) => d.id).toSet();
      final Set<String> secondaryIds = secondaryQuery.docs.map((d) => d.id).toSet();
      final Set<String> readOnlyIds = readOnlyQuery.docs.map((d) => d.id).toSet();

      secondaryIds.removeAll(ownedIds);
      readOnlyIds.removeAll(ownedIds);
      readOnlyIds.removeAll(secondaryIds);

      await _firestore.collection('users').doc(uid).update({
        'owned_dispensers': ownedIds.toList(),
        'secondary_dispensers': secondaryIds.toList(),
        'read_only_dispensers': readOnlyIds.toList(),
      });
    } catch (e) {
      print('Update list error: $e');
    }
  }

  // ===========================================================================
  // --- BÖLÜM 2: SAYAÇ, LOG VE RAPORLAMA ---
  // ===========================================================================
  // --- RTDB İADE İŞLEMİ (DÜZELTİLDİ: Transaction yerine Get-Set) ---
  Future<void> incrementPillCount(String macAddress, int sectionIndex) async {
    if (macAddress.isEmpty) return;
    try {
      rtdb.DatabaseReference ref = _rtdb.ref("dispensers/$macAddress/config/section_$sectionIndex/pillCount");

      // Önce mevcut değeri oku
      final snapshot = await ref.get();
      if (snapshot.exists) {
        int current = 0;
        if (snapshot.value is int) {
          current = snapshot.value as int;
        } else {
          current = int.tryParse(snapshot.value.toString()) ?? 0;
        }

        // Sonra 1 fazlasını yaz
        await ref.set(current + 1);
        print(">>> RTDB BAŞARIYLA ARTTIRILDI: $current -> ${current + 1} (Bölme $sectionIndex)");
      } else {
        // Değer hiç yoksa 1 yap
        await ref.set(1);
        print(">>> RTDB YOKTU, 1 OLARAK AYARLANDI.");
      }
    } catch (e) {
      print('!!! SAYAC ARTIRMA HATASI: $e');
    }
  }

  // --- GÜVENLİ İADE MANTIĞI ---
  Future<void> safeRefundPill(String macAddress, int sectionIndex, String currentUserId) async {
    try {
      final now = DateTime.now();
      // Son 5 dakika kuralı
      final fiveMinutesAgo = now.subtract(const Duration(minutes: 1));

      print("Güvenli İade Kontrolü Başlıyor... (Cihaz: $macAddress, Bölme: $sectionIndex)");

      // 1. KONTROL: Sistem zaten iade yapmış mı?
      final refundCheck = await _firestore.collection('dispenser').doc(macAddress).collection('logs')
          .where('type', isEqualTo: 'system_refund')
          .where('section', isEqualTo: sectionIndex)
          .where('timestamp', isGreaterThan: fiveMinutesAgo)
          .get();

      if (refundCheck.docs.isNotEmpty) {
        print("!!! GÜVENLİK KİLİDİ DEVREDE !!!");
        print("Son 5 dakika içinde zaten bir iade yapılmış. İşlem mükerrer olmaması için iptal ediliyor.");
        return; // BURADA ÇIKIYORSA ARTMAZ
      }

      // 2. İŞLEM: RTDB Stok Artır
      await incrementPillCount(macAddress, sectionIndex);

      // 3. İŞLEM: "İade Yapıldı" Logu At (Kilidi Aktif Et)
      await _firestore.collection('dispenser').doc(macAddress).collection('logs').add({
        'type': 'system_refund',
        'section': sectionIndex,
        'triggered_by': currentUserId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      print("Güvenli iade ve loglama tamamlandı.");

    } catch (e) {
      print("Safe refund error: $e");
    }
  }

  // --- YENİ EKLENEN: Sadece Stok Sayısını Güncelle (Home Screen Kullanıyor) ---
  Future<void> updatePillCountOnly(String macAddress, int sectionIndex, int newCount) async {
    if (macAddress.isEmpty) return;
    try {
      DocumentReference docRef = _firestore.collection('dispenser').doc(macAddress);

      await _firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;

        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
        List<dynamic> config = List.from(data['section_config'] ?? []);

        if (sectionIndex < config.length) {
          config[sectionIndex]['pillCount'] = newCount;
          transaction.update(docRef, {'section_config': config});
        }
      });
      print("Firestore Sync OK: Bölme $sectionIndex -> $newCount");
    } catch (e) {
      print('Stok güncelleme hatası: $e');
    }
  }

  Future<void> logDispenseStatus({
    required String macAddress,
    required int sectionIndex,
    required bool successful,
    required String userResponse,
    required String userId,
  }) async {
    try {
      await _firestore.collection('dispenser').doc(macAddress).collection('logs').add({
        'type': 'user_feedback',
        'section': sectionIndex,
        'success': successful,
        'response': userResponse,
        'userId': userId,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Log error: $e');
    }
  }

  Future<Map<String, dynamic>> getDispenseStats(String macAddress, String targetUserId) async {
    try {
      final now = DateTime.now();
      final startOfWeek = now.subtract(const Duration(days: 7));

      final query = await _firestore.collection('dispenser').doc(macAddress).collection('logs')
          .where('userId', isEqualTo: targetUserId)
          .where('timestamp', isGreaterThan: startOfWeek)
          .orderBy('timestamp', descending: true)
          .get();

      int total = 0; int success = 0; int failed = 0;
      Map<int, int> weeklySuccessMap = {1:0, 2:0, 3:0, 4:0, 5:0, 6:0, 7:0};
      Map<String, Map<String, int>> sectionStats = {};

      for (var doc in query.docs) {
        final data = doc.data();
        if (data['type'] == 'user_feedback') {
          total++;

          String sectionKey = (data['section'] ?? 0).toString();
          if (!sectionStats.containsKey(sectionKey)) {
            sectionStats[sectionKey] = {'success': 0, 'failed': 0};
          }

          if (data['success'] == true) {
            success++;
            sectionStats[sectionKey]!['success'] = (sectionStats[sectionKey]!['success']!) + 1;

            if (data['timestamp'] != null) {
              DateTime ts = (data['timestamp'] as Timestamp).toDate();
              weeklySuccessMap[ts.weekday] = (weeklySuccessMap[ts.weekday] ?? 0) + 1;
            }
          } else {
            failed++;
            sectionStats[sectionKey]!['failed'] = (sectionStats[sectionKey]!['failed']!) + 1;
          }
        }
      }
      return {
        'total': total,
        'success': success,
        'failed': failed,
        'weeklyData': weeklySuccessMap,
        'sectionStats': sectionStats
      };
    } catch (e) {
      print("Stats Error: $e");
      return {'total': 0, 'success': 0, 'failed': 0, 'weeklyData': {}, 'sectionStats': {}};
    }
  }

  // ===========================================================================
  // --- BÖLÜM 3: CİHAZ TERCİHLERİ VE YARDIMCI METOTLAR ---
  // ===========================================================================

  Future<void> saveDevicePreference(String uid, String macAddress, bool feedbackEnabled) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'device_preferences': {
          macAddress: {'feedback_enabled': feedbackEnabled}
        }
      }, SetOptions(merge: true));
    } catch (e) { print("Pref save error: $e"); }
  }

  Future<bool> getDeviceFeedbackPreference(String uid, String macAddress) async {
    try {
      var doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data()!.containsKey('device_preferences')) {
        var prefs = doc.data()!['device_preferences'] as Map<String, dynamic>;
        if (prefs.containsKey(macAddress)) {
          return prefs[macAddress]['feedback_enabled'] ?? false;
        }
      }
    } catch (e) { print("Pref read error: $e"); }
    return false;
  }

  Future<String?> getUserIdByEmail(String email) async {
    try {
      var query = await _firestore.collection('users').where('email', isEqualTo: email).limit(1).get();
      if(query.docs.isNotEmpty) return query.docs.first.id;
    } catch(e) { print("User ID fetch error: $e"); }
    return null;
  }

  // ===========================================================================
  // --- BÖLÜM 4: TEMEL CİHAZ FONKSİYONLARI ---
  // ===========================================================================

  Future<void> saveSectionConfig(String macAddress, List<Map<String, dynamic>> sections) async {
    if (macAddress.isEmpty) return;
    try {
      await _firestore.collection('dispenser').doc(macAddress).set({'section_config': sections}, SetOptions(merge: true));
      Map<String, dynamic> rtdbData = {};
      for (int i = 0; i < sections.length; i++) {
        rtdbData['section_$i'] = {
          'name': sections[i]['name'],
          'isActive': sections[i]['isActive'] ?? false,
          'pillCount': sections[i]['pillCount'] ?? 0,
          'schedule': sections[i]['schedule'] ?? [],
        };
      }
      rtdb.DatabaseReference ref = _rtdb.ref("dispensers/$macAddress/config");
      await ref.update(rtdbData);
    } catch (e) { print('Error saving config: $e'); }
  }

  Future<void> toggleBuzzer(String macAddress, bool makeItRing) async {
    if (macAddress.isEmpty) return;
    try {
      await _firestore.collection('dispenser').doc(macAddress).set({'alarm': makeItRing}, SetOptions(merge: true));
      rtdb.DatabaseReference ref = _rtdb.ref("dispensers/$macAddress/buzzer");
      await ref.set(makeItRing);
    } catch (e) { print('Error toggling buzzer: $e'); }
  }

  Future<void> updateDeviceName(String macAddress, String newName) async {
    if (macAddress.isEmpty || newName.isEmpty) return;
    try { await _firestore.collection('dispenser').doc(macAddress).update({'device_name': newName}); } catch (e) { print('Error updating name: $e'); }
  }

  // ===========================================================================
  // --- BÖLÜM 5: KULLANICI YÖNETİMİ ---
  // ===========================================================================

  Future<DeviceRole> getUserRole(String macAddress, String? rawEmail) async {
    if (rawEmail == null || macAddress.isEmpty) return DeviceRole.none;
    final String email = _sanitize(rawEmail);
    try {
      final doc = await _firestore.collection('dispenser').doc(macAddress).get();
      if (!doc.exists) return DeviceRole.none;
      final data = doc.data()!;
      if ((data['owner_mail'] as String?)?.toLowerCase() == email) return DeviceRole.owner;
      final secondary = List<String>.from(data['secondary_mails'] ?? []).map((e) => _sanitize(e)).toList();
      if (secondary.contains(email)) return DeviceRole.secondary;
      final readOnly = List<String>.from(data['read_only_mails'] ?? []).map((e) => _sanitize(e)).toList();
      if (readOnly.contains(email)) return DeviceRole.readOnly;
      return DeviceRole.none;
    } catch (e) { return DeviceRole.none; }
  }

  Future<void> addReadOnlyUser(String macAddress, String rawEmail) async {
    final String email = _sanitize(rawEmail);
    if (macAddress.isEmpty || email.isEmpty) return;
    try { await _firestore.collection('dispenser').doc(macAddress).update({'read_only_mails': FieldValue.arrayUnion([email])}); } catch (e) {}
  }

  Future<void> promoteToSecondary(String macAddress, String targetRawEmail) async {
    final String targetEmail = _sanitize(targetRawEmail);
    try {
      final deviceRef = _firestore.collection('dispenser').doc(macAddress);
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(deviceRef);
        if (!snapshot.exists) return;
        final data = snapshot.data() as Map<String, dynamic>;
        List<String> readOnly = List<String>.from(data['read_only_mails'] ?? []);
        List<String> secondary = List<String>.from(data['secondary_mails'] ?? []);
        readOnly.removeWhere((e) => _sanitize(e) == targetEmail);
        if (!secondary.any((e) => _sanitize(e) == targetEmail)) secondary.add(targetEmail);
        transaction.update(deviceRef, {'read_only_mails': readOnly, 'secondary_mails': secondary});
      });
    } catch (e) { print('Terfi hatası: $e'); }
  }

  Future<void> demoteToReadOnly(String macAddress, String targetRawEmail) async {
    final String targetEmail = _sanitize(targetRawEmail);
    try {
      final deviceRef = _firestore.collection('dispenser').doc(macAddress);
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(deviceRef);
        if (!snapshot.exists) return;
        final data = snapshot.data() as Map<String, dynamic>;
        List<String> readOnly = List<String>.from(data['read_only_mails'] ?? []);
        List<String> secondary = List<String>.from(data['secondary_mails'] ?? []);
        secondary.removeWhere((e) => _sanitize(e) == targetEmail);
        if (!readOnly.any((e) => _sanitize(e) == targetEmail)) readOnly.add(targetEmail);
        transaction.update(deviceRef, {'read_only_mails': readOnly, 'secondary_mails': secondary});
      });
    } catch (e) { print('Rütbe düşürme hatası: $e'); }
  }

  Future<void> removeUser(String macAddress, String rawEmail) async {
    final String email = _sanitize(rawEmail);
    try { await _firestore.collection('dispenser').doc(macAddress).update({'read_only_mails': FieldValue.arrayRemove([email]), 'secondary_mails': FieldValue.arrayRemove([email])}); } catch (e) { print('Error removing user: $e'); }
  }

  // ===========================================================================
  // --- BÖLÜM 6: CİHAZ EKLEME (MANUEL) ---
  // ===========================================================================

  Future<String> addDeviceManually(String uid, String rawEmail, String macAddress) async {
    if (uid.isEmpty || macAddress.isEmpty || rawEmail.isEmpty) return 'Geçersiz bilgi.';
    final String userEmail = _sanitize(rawEmail);
    try {
      final deviceRef = _firestore.collection('dispenser').doc(macAddress);
      final userRef = _firestore.collection('users').doc(uid);
      return await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userRef);
        List<dynamic> unvisibleList = [];
        if (userDoc.exists) unvisibleList = userDoc.data()?['unvisible_devices'] ?? [];
        if (unvisibleList.contains(macAddress)) {
          transaction.update(userRef, {'unvisible_devices': FieldValue.arrayRemove([macAddress]), 'visible_devices': FieldValue.arrayUnion([macAddress])});
          return 'Cihaz tekrar görünür yapıldı.';
        }
        final deviceDoc = await transaction.get(deviceRef);
        if (!deviceDoc.exists) {
          transaction.set(deviceRef, {'owner_mail': userEmail, 'secondary_mails': [], 'read_only_mails': [], 'device_name': 'MedTrack $macAddress'});
          transaction.update(userRef, {'owned_dispensers': FieldValue.arrayUnion([macAddress])});
          return 'success';
        }
        final deviceData = deviceDoc.data() as Map<String, dynamic>;
        final currentOwner = (deviceData['owner_mail'] as String?)?.toLowerCase();
        List<String> secondaryMails = List<String>.from(deviceData['secondary_mails'] ?? []);
        List<String> readOnlyMails = List<String>.from(deviceData['read_only_mails'] ?? []);
        secondaryMails.removeWhere((e) => _sanitize(e) == userEmail);
        readOnlyMails.removeWhere((e) => _sanitize(e) == userEmail);
        if (currentOwner == null || currentOwner.isEmpty) {
          transaction.update(deviceRef, {'owner_mail': userEmail, 'secondary_mails': secondaryMails, 'read_only_mails': readOnlyMails});
          transaction.update(userRef, {'owned_dispensers': FieldValue.arrayUnion([macAddress]), 'secondary_dispensers': FieldValue.arrayRemove([macAddress]), 'read_only_dispensers': FieldValue.arrayRemove([macAddress])});
        } else if (currentOwner != userEmail) {
          secondaryMails.add(userEmail);
          transaction.update(deviceRef, {'secondary_mails': secondaryMails, 'read_only_mails': readOnlyMails});
          transaction.update(userRef, {'secondary_dispensers': FieldValue.arrayUnion([macAddress]), 'owned_dispensers': FieldValue.arrayRemove([macAddress]), 'read_only_dispensers': FieldValue.arrayRemove([macAddress])});
        }
        return 'success';
      });
    } catch (e) { return 'Hata: $e'; }
  }

  // ===========================================================================
  // --- BÖLÜM 7: GRUPLAMA SİSTEMİ ---
  // ===========================================================================

  Future<void> createGroup(String uid, String groupName) async {
    try {
      final userDoc = _firestore.collection('users').doc(uid);
      final snapshot = await userDoc.get();
      List<dynamic> groups = snapshot.data()?['device_groups'] ?? [];
      String groupId = DateTime.now().millisecondsSinceEpoch.toString();
      groups.add({'id': groupId, 'name': groupName, 'devices': []});
      await userDoc.update({'device_groups': groups});
    } catch (e) { print('Error creating group: $e'); }
  }

  Future<void> deleteGroup(String uid, String groupId) async {
    try {
      final userDoc = _firestore.collection('users').doc(uid);
      final snapshot = await userDoc.get();
      List<dynamic> groups = List.from(snapshot.data()?['device_groups'] ?? []);
      groups.removeWhere((g) => g['id'] == groupId);
      await userDoc.update({'device_groups': groups});
    } catch (e) { print('Error deleting group: $e'); }
  }

  Future<void> renameGroup(String uid, String groupId, String newName) async {
    try {
      final userDoc = _firestore.collection('users').doc(uid);
      final snapshot = await userDoc.get();
      List<dynamic> groups = List.from(snapshot.data()?['device_groups'] ?? []);
      var group = groups.firstWhere((g) => g['id'] == groupId, orElse: () => null);
      if (group != null) {
        group['name'] = newName;
        await userDoc.update({'device_groups': groups});
      }
    } catch (e) { print('Error renaming group: $e'); }
  }

  Future<void> moveDeviceToGroup(String uid, String macAddress, String targetGroupId) async {
    try {
      final userDoc = _firestore.collection('users').doc(uid);
      final snapshot = await userDoc.get();
      List<dynamic> groups = List.from(snapshot.data()?['device_groups'] ?? []);
      for (var group in groups) {
        List<dynamic> devices = List.from(group['devices'] ?? []);
        devices.remove(macAddress);
        group['devices'] = devices;
      }
      if (targetGroupId.isNotEmpty) {
        var targetGroup = groups.firstWhere((g) => g['id'] == targetGroupId, orElse: () => null);
        if (targetGroup != null) {
          List<dynamic> devices = List.from(targetGroup['devices'] ?? []);
          if (!devices.contains(macAddress)) devices.add(macAddress);
          targetGroup['devices'] = devices;
        }
      }
      await userDoc.update({'device_groups': groups});
    } catch (e) { print('Error moving device: $e'); }
  }

  // ===========================================================================
  // --- BÖLÜM 8: AKRABA & GÖRÜNÜRLÜK ---
  // ===========================================================================

  Future<void> hideDevice(String uid, String macAddress) async {
    if (uid.isEmpty || macAddress.isEmpty) return;
    try {
      final userRef = _firestore.collection('users').doc(uid);
      await userRef.update({
        'unvisible_devices': FieldValue.arrayUnion([macAddress]),
        'visible_devices': FieldValue.arrayRemove([macAddress]),
      });
    } catch (e) { print('Gizleme hatası: $e'); }
  }

  Future<List<Map<String, dynamic>>> getRelativesInfo(String uid, String currentUserEmail) async {
    Set<String> relativeEmails = {};
    String myEmail = _sanitize(currentUserEmail);
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) return [];
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      List<dynamic> allDeviceIds = [];
      allDeviceIds.addAll(userData['owned_dispensers'] ?? []);
      allDeviceIds.addAll(userData['secondary_dispensers'] ?? []);
      allDeviceIds.addAll(userData['read_only_dispensers'] ?? []);
      if (allDeviceIds.isEmpty) return [];

      for (var deviceId in allDeviceIds) {
        try {
          DocumentSnapshot deviceDoc = await _firestore.collection('dispenser').doc(deviceId).get();
          if (deviceDoc.exists) {
            Map<String, dynamic> data = deviceDoc.data() as Map<String, dynamic>;
            if (data['owner_mail'] != null) relativeEmails.add(_sanitize(data['owner_mail'].toString()));
            if (data['secondary_mails'] != null) { for (var m in data['secondary_mails']) relativeEmails.add(_sanitize(m.toString())); }
            if (data['read_only_mails'] != null) { for (var m in data['read_only_mails']) relativeEmails.add(_sanitize(m.toString())); }
          }
        } catch (e) { print("Cihaz ($deviceId) okunurken hata: $e"); }
      }
      relativeEmails.remove(myEmail);
      if (relativeEmails.isEmpty) return [];

      List<Map<String, dynamic>> relativesProfiles = [];
      for (var email in relativeEmails) {
        String displayName = '';
        String photoURL = '';
        bool isRegistered = false;
        try {
          QuerySnapshot query = await _firestore.collection('users').where('email', isEqualTo: email).limit(1).get();
          if (query.docs.isNotEmpty) {
            var profile = query.docs.first.data() as Map<String, dynamic>;
            displayName = profile['displayName'] ?? '';
            photoURL = profile['photoURL'] ?? '';
            isRegistered = true;
          }
        } catch (e) { print("Profil detayı çekilemedi ($email): $e"); }
        relativesProfiles.add({
          'email': email,
          'displayName': displayName,
          'photoURL': photoURL,
          'isRegistered': isRegistered,
        });
      }
      return relativesProfiles;
    } catch (e) { print("Genel getRelativesInfo hatası: $e"); return []; }
  }

  Future<void> updateRelativeNickname(String uid, String relativeEmail, String nickname) async {
    try {
      String safeKey = relativeEmail.replaceAll('.', '_dot_');
      await _firestore.collection('users').doc(uid).set({
        'relatives_nicknames': { safeKey: nickname }
      }, SetOptions(merge: true));
    } catch (e) { print("Nickname update error: $e"); }
  }

  Future<bool> hasAnyAssociatedDevice(String uid) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) return false;
      Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
      List owned = data['owned_dispensers'] ?? [];
      List secondary = data['secondary_dispensers'] ?? [];
      List readOnly = data['read_only_dispensers'] ?? [];
      return owned.isNotEmpty || secondary.isNotEmpty || readOnly.isNotEmpty;
    } catch (e) { print("Cihaz kontrol hatası: $e"); return false; }
  }
}