import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart'; // RTDB Paketi eklendi

// Roller için enum tanımı
enum DeviceRole { owner, secondary, readOnly, none }

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance; // RTDB örneği

  // --- YARDIMCI METOTLAR ---
  String _sanitize(String email) => email.trim().toLowerCase();

  // --- TEMEL CİHAZ FONKSİYONLARI ---

  // 1. İlaç saatlerini kaydetme (ÇOKLU SAAT DESTEKLİ - GÜNCELLENDİ)
  Future<void> saveSectionConfig(String macAddress, List<Map<String, dynamic>> sections) async {
    if (macAddress.isEmpty) return;
    try {
      // A. Firestore'a kaydet (schedule listesi olarak)
      await _firestore.collection('dispenser').doc(macAddress).set({
        'section_config': sections,
      }, SetOptions(merge: true));

      // B. Realtime Database'e kaydet (ESP32 için)
      // Yapı: /dispensers/{macAddress}/config/section_0/schedule/[ {h:8, m:0}, {h:12, m:30} ]
      Map<String, dynamic> rtdbData = {};

      for (int i = 0; i < sections.length; i++) {
        // schedule listesini alalım
        List<dynamic> scheduleList = sections[i]['schedule'] ?? [];

        rtdbData['section_$i'] = {
          'name': sections[i]['name'],
          'isActive': sections[i]['isActive'] ?? false,
          'schedule': scheduleList, // ARTIK SADECE LİSTE GÖNDERİYORUZ
          // 'hour' ve 'minute' alanları SİLİNDİ.
        };
      }

      DatabaseReference ref = _rtdb.ref("dispensers/$macAddress/config");
      await ref.set(rtdbData);

      print("Veriler (Çoklu Saat) başarıyla kaydedildi.");

    } catch (e) {
      print('Error saving section_config: $e');
    }
  }

  // 2. Buzzer / Alarm Tetikleme (HEM FIRESTORE HEM RTDB)
  Future<void> toggleBuzzer(String macAddress, bool makeItRing) async {
    if (macAddress.isEmpty) return;
    try {
      // A. Firestore (Opsiyonel, log amaçlı veya UI durumu için)
      await _firestore.collection('dispenser').doc(macAddress).set({
        'alarm': makeItRing,
      }, SetOptions(merge: true));

      // B. Realtime Database (ESP32'nin anlık tepki vermesi için KRİTİK)
      // Yol: /dispensers/{macAddress}/buzzer -> true/false
      DatabaseReference ref = _rtdb.ref("dispensers/$macAddress/buzzer");
      await ref.set(makeItRing);

      print("Buzzer komutu gönderildi: $makeItRing");

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
  // 8. Manuel Cihaz Ekleme (GÜNCELLENDİ: Gizliyse tekrar görünür yapar)
  Future<String> addDeviceManually(String uid, String rawEmail, String macAddress) async {
    if (uid.isEmpty || macAddress.isEmpty || rawEmail.isEmpty) return 'Geçersiz bilgi.';

    final String userEmail = _sanitize(rawEmail);

    try {
      final deviceRef = _firestore.collection('dispenser').doc(macAddress);
      final userRef = _firestore.collection('users').doc(uid);

      return await _firestore.runTransaction((transaction) async {
        // Önce kullanıcının gizli listesinde var mı bakalım
        final userDoc = await transaction.get(userRef);
        List<dynamic> unvisibleList = [];
        if (userDoc.exists) {
          unvisibleList = userDoc.data()?['unvisible_devices'] ?? [];
        }

        // Eğer cihaz zaten kullanıcınınsa ama gizliyse, sadece görünür yap
        // (Burada kullanıcının already owner/secondary olduğunu kontrol eden mantığınız zaten var,
        //  biz sadece görünürlük kilidini açıyoruz).
        if (unvisibleList.contains(macAddress)) {
          transaction.update(userRef, {
            'unvisible_devices': FieldValue.arrayRemove([macAddress]),
            'visible_devices': FieldValue.arrayUnion([macAddress]),
          });
          return 'Cihaz tekrar görünür yapıldı.';
        }
        final deviceDoc = await transaction.get(deviceRef);

        if (!deviceDoc.exists) {
          return 'Bu MAC adresine sahip bir cihaz bulunamadı.';
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
          readOnlyMails.add(userEmail);
          transaction.update(deviceRef, {
            'read_only_mails': readOnlyMails,
            'secondary_mails': secondaryMails,
          });
          transaction.update(userRef, {
            'read_only_dispensers': FieldValue.arrayUnion([macAddress]),
            'owned_dispensers': FieldValue.arrayRemove([macAddress]),
            'secondary_dispensers': FieldValue.arrayRemove([macAddress]),
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

  // 11. Yeni bir klasör oluştur
  Future<void> createGroup(String uid, String groupName) async {
    try {
      final userDoc = _firestore.collection('users').doc(uid);
      final snapshot = await userDoc.get();

      List<dynamic> groups = snapshot.data()?['device_groups'] ?? [];

      String groupId = DateTime.now().millisecondsSinceEpoch.toString();

      groups.add({
        'id': groupId,
        'name': groupName,
        'devices': [],
      });

      await userDoc.update({'device_groups': groups});
    } catch (e) {
      print('Error creating group: $e');
    }
  }

  // 12. Klasörü sil
  Future<void> deleteGroup(String uid, String groupId) async {
    try {
      final userDoc = _firestore.collection('users').doc(uid);
      final snapshot = await userDoc.get();

      List<dynamic> groups = List.from(snapshot.data()?['device_groups'] ?? []);
      groups.removeWhere((g) => g['id'] == groupId);

      await userDoc.update({'device_groups': groups});
    } catch (e) {
      print('Error deleting group: $e');
    }
  }

  // 13. Klasör ismini değiştir
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
    } catch (e) {
      print('Error renaming group: $e');
    }
  }

  // 14. Cihazı klasöre taşı
  Future<void> moveDeviceToGroup(String uid, String macAddress, String targetGroupId) async {
    try {
      final userDoc = _firestore.collection('users').doc(uid);
      final snapshot = await userDoc.get();

      List<dynamic> groups = List.from(snapshot.data()?['device_groups'] ?? []);

      // 1. Mevcut gruplardan çıkar
      for (var group in groups) {
        List<dynamic> devices = List.from(group['devices'] ?? []);
        devices.remove(macAddress);
        group['devices'] = devices;
      }

      // 2. Yeni gruba ekle
      if (targetGroupId.isNotEmpty) {
        var targetGroup = groups.firstWhere((g) => g['id'] == targetGroupId, orElse: () => null);
        if (targetGroup != null) {
          List<dynamic> devices = List.from(targetGroup['devices'] ?? []);
          if (!devices.contains(macAddress)) {
            devices.add(macAddress);
          }
          targetGroup['devices'] = devices;
        }
      }

      await userDoc.update({'device_groups': groups});
    } catch (e) {
      print('Error moving device: $e');
    }
  }

  // 15. Cihazı "Çöp Kutusuna" at (Sadece görünürlüğü kapatır, yetkiyi silmez)
  Future<void> hideDevice(String uid, String macAddress) async {
    if (uid.isEmpty || macAddress.isEmpty) return;

    try {
      final userRef = _firestore.collection('users').doc(uid);

      // Cihazı 'unvisible_devices' listesine ekle
      // İsteğe bağlı: 'visible_devices' varsa oradan çıkarılabilir ama blacklist mantığı daha sağlamdır.
      await userRef.update({
        'unvisible_devices': FieldValue.arrayUnion([macAddress]),
        'visible_devices': FieldValue.arrayRemove([macAddress]), // Eğer whitelist tutuyorsanız
      });

      print('Cihaz gizlendi: $macAddress');
    } catch (e) {
      print('Gizleme hatası: $e');
    }
  }

  // 16. Gizli cihazları filtreleyen yardımcı fonksiyon
  // UI tarafında StreamBuilder içinde kullanılır.
  List<String> filterVisibleDevices(List<String> allDevices, List<dynamic>? unvisibleList) {
    if (unvisibleList == null || unvisibleList.isEmpty) return allDevices;

    final unvisibleSet = unvisibleList.map((e) => e.toString()).toSet();
    return allDevices.where((device) => !unvisibleSet.contains(device)).toList();
  }
}