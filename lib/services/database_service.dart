import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart'; // EKLENDİ (Firebase.app() için gerekli)
import 'package:firebase_database/firebase_database.dart';

// Roller için enum tanımı
enum DeviceRole { owner, secondary, readOnly, none }

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- DÜZELTME BURADA YAPILDI ---
  // Varsayılan instance yerine, Europe-West1 URL'ini belirten instance kullanıyoruz.
  final FirebaseDatabase _rtdb = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://smartmedicinedispenser-default-rtdb.europe-west1.firebasedatabase.app',
  );

  // --- YARDIMCI METOTLAR ---
  String _sanitize(String email) => email.trim().toLowerCase();

  // --- TEMEL CİHAZ FONKSİYONLARI ---

  // 1. İlaç saatlerini kaydetme
  Future<void> saveSectionConfig(String macAddress, List<Map<String, dynamic>> sections) async {
    if (macAddress.isEmpty) return;
    try {
      // A. Firestore'a kaydet
      await _firestore.collection('dispenser').doc(macAddress).set({
        'section_config': sections,
      }, SetOptions(merge: true));

      // B. Realtime Database'e kaydet (ESP32 için)
      Map<String, dynamic> rtdbData = {};

      for (int i = 0; i < sections.length; i++) {
        List<dynamic> scheduleList = sections[i]['schedule'] ?? [];

        rtdbData['section_$i'] = {
          'name': sections[i]['name'],
          'isActive': sections[i]['isActive'] ?? false,
          'schedule': scheduleList,
        };
      }

      DatabaseReference ref = _rtdb.ref("dispensers/$macAddress/config");
      await ref.set(rtdbData);

      print("Veriler (RTDB - Europe) başarıyla kaydedildi.");

    } catch (e) {
      print('Error saving section_config: $e');
    }
  }

  // 2. Buzzer / Alarm Tetikleme
  Future<void> toggleBuzzer(String macAddress, bool makeItRing) async {
    if (macAddress.isEmpty) return;
    try {
      // A. Firestore
      await _firestore.collection('dispenser').doc(macAddress).set({
        'alarm': makeItRing,
      }, SetOptions(merge: true));

      // B. Realtime Database (ESP32 için KRİTİK)
      DatabaseReference ref = _rtdb.ref("dispensers/$macAddress/buzzer");
      await ref.set(makeItRing);

      print("Buzzer komutu gönderildi (Europe): $makeItRing");

    } catch (e) {
      print('Error toggling buzzer: $e');
    }
  }

  // 3. Cihaz adını güncelleme
  Future<void> updateDeviceName(String macAddress, String newName) async {
    if (macAddress.isEmpty || newName.isEmpty) return;
    try {
      await _firestore.collection('dispenser').doc(macAddress).update({
        'device_name': newName,
      });
    } catch (e) {
      print('Error updating device name: $e');
    }
  }

  // --- KULLANICI YÖNETİMİ (HOME SCREEN İÇİN) ---

  // 4. Rol Kontrolü
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
    } catch (e) {
      print('Rol alma hatası: $e');
      return DeviceRole.none;
    }
  }

  // 5. Yeni bir izleyici (read-only) ekler
  Future<void> addReadOnlyUser(String macAddress, String rawEmail) async {
    final String email = _sanitize(rawEmail);
    if (macAddress.isEmpty || email.isEmpty) return;

    try {
      await _firestore.collection('dispenser').doc(macAddress).update({
        'read_only_mails': FieldValue.arrayUnion([email]),
      });
    } catch (e) {
      print('Error adding read-only user: $e');
    }
  }

  // 6. İzleyiciyi yöneticiye terfi ettirir
  Future<void> promoteToSecondary(String macAddress, String targetRawEmail) async {
    final String targetEmail = _sanitize(targetRawEmail);
    if (macAddress.isEmpty || targetEmail.isEmpty) return;

    try {
      final deviceRef = _firestore.collection('dispenser').doc(macAddress);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(deviceRef);
        if (!snapshot.exists) return;
        final data = snapshot.data() as Map<String, dynamic>;

        List<String> readOnly = List<String>.from(data['read_only_mails'] ?? []);
        List<String> secondary = List<String>.from(data['secondary_mails'] ?? []);

        readOnly.removeWhere((e) => _sanitize(e) == targetEmail);
        if (!secondary.any((e) => _sanitize(e) == targetEmail)) {
          secondary.add(targetEmail);
        }

        transaction.update(deviceRef, {
          'read_only_mails': readOnly,
          'secondary_mails': secondary
        });
      });
    } catch (e) {
      print('Terfi hatası: $e');
    }
  }

  // 7. Yöneticiyi izleyiciye düşürür
  Future<void> demoteToReadOnly(String macAddress, String targetRawEmail) async {
    final String targetEmail = _sanitize(targetRawEmail);
    if (macAddress.isEmpty || targetEmail.isEmpty) return;

    try {
      final deviceRef = _firestore.collection('dispenser').doc(macAddress);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(deviceRef);
        if (!snapshot.exists) return;
        final data = snapshot.data() as Map<String, dynamic>;

        List<String> readOnly = List<String>.from(data['read_only_mails'] ?? []);
        List<String> secondary = List<String>.from(data['secondary_mails'] ?? []);

        secondary.removeWhere((e) => _sanitize(e) == targetEmail);

        if (!readOnly.any((e) => _sanitize(e) == targetEmail)) {
          readOnly.add(targetEmail);
        }

        transaction.update(deviceRef, {
          'read_only_mails': readOnly,
          'secondary_mails': secondary
        });
      });
    } catch (e) {
      print('Rütbe düşürme hatası: $e');
    }
  }

  // 8. Kullanıcıyı tamamen siler
  Future<void> removeUser(String macAddress, String rawEmail) async {
    final String email = _sanitize(rawEmail);
    if (macAddress.isEmpty || email.isEmpty) return;

    try {
      await _firestore.collection('dispenser').doc(macAddress).update({
        'read_only_mails': FieldValue.arrayRemove([email]),
        'secondary_mails': FieldValue.arrayRemove([email]),
      });
    } catch (e) {
      print('Error removing user: $e');
    }
  }

  // --- CİHAZ EKLEME VE SENKRONİZASYON ---

  // 9. Manuel Cihaz Ekleme
  Future<String> addDeviceManually(String uid, String rawEmail, String macAddress) async {
    if (uid.isEmpty || macAddress.isEmpty || rawEmail.isEmpty) return 'Geçersiz bilgi.';

    final String userEmail = _sanitize(rawEmail);

    try {
      final deviceRef = _firestore.collection('dispenser').doc(macAddress);
      final userRef = _firestore.collection('users').doc(uid);

      return await _firestore.runTransaction((transaction) async {
        // Kullanıcıda gizli mi kontrolü
        final userDoc = await transaction.get(userRef);
        List<dynamic> unvisibleList = [];
        if (userDoc.exists) {
          unvisibleList = userDoc.data()?['unvisible_devices'] ?? [];
        }

        if (unvisibleList.contains(macAddress)) {
          transaction.update(userRef, {
            'unvisible_devices': FieldValue.arrayRemove([macAddress]),
            'visible_devices': FieldValue.arrayUnion([macAddress]),
          });
          return 'Cihaz tekrar görünür yapıldı.';
        }

        final deviceDoc = await transaction.get(deviceRef);

        if (!deviceDoc.exists) {
          // Cihaz hiç yoksa oluştur ve sahip yap
          transaction.set(deviceRef, {
            'owner_mail': userEmail,
            'secondary_mails': [],
            'read_only_mails': [],
            'device_name': 'MedTrack $macAddress'
          });
          transaction.update(userRef, {
            'owned_dispensers': FieldValue.arrayUnion([macAddress]),
          });
          return 'success';
        }

        final deviceData = deviceDoc.data() as Map<String, dynamic>;
        final currentOwner = (deviceData['owner_mail'] as String?)?.toLowerCase();

        List<String> secondaryMails = List<String>.from(deviceData['secondary_mails'] ?? []);
        List<String> readOnlyMails = List<String>.from(deviceData['read_only_mails'] ?? []);

        secondaryMails.removeWhere((e) => _sanitize(e) == userEmail);
        readOnlyMails.removeWhere((e) => _sanitize(e) == userEmail);

        if (currentOwner == null || currentOwner.isEmpty) {
          transaction.update(deviceRef, {
            'owner_mail': userEmail,
            'secondary_mails': secondaryMails,
            'read_only_mails': readOnlyMails,
          });
          transaction.update(userRef, {
            'owned_dispensers': FieldValue.arrayUnion([macAddress]),
            'secondary_dispensers': FieldValue.arrayRemove([macAddress]),
            'read_only_dispensers': FieldValue.arrayRemove([macAddress]),
          });
        } else if (currentOwner != userEmail) {
          // Sahibi varsa, ikincil kullanıcı (yönetici) yap
          secondaryMails.add(userEmail);
          transaction.update(deviceRef, {
            'secondary_mails': secondaryMails,
            'read_only_mails': readOnlyMails
          });
          transaction.update(userRef, {
            'secondary_dispensers': FieldValue.arrayUnion([macAddress]),
            'owned_dispensers': FieldValue.arrayRemove([macAddress]),
            'read_only_dispensers': FieldValue.arrayRemove([macAddress]),
          });
        }
        return 'success';
      });
    } catch (e) {
      print('Manuel ekleme hatası: $e');
      return 'Bir hata oluştu: $e';
    }
  }

  // 10. Liste Senkronizasyonu
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

  // --- GRUPLAMA SİSTEMİ ---

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
    } catch (e) {
      print("Genel getRelativesInfo hatası: $e");
      return [];
    }
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
    } catch (e) {
      print("Cihaz kontrol hatası: $e");
      return false;
    }
  }
}