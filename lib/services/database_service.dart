import 'package:cloud_firestore/cloud_firestore.dart';

enum DeviceRole { owner, secondary, readOnly, none }

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Yardımcı Fonksiyon: Email'i standartlaştırır
  String _sanitize(String email) => email.trim().toLowerCase();

  // 1. İlaç saatlerini kaydetme
  Future<void> saveSectionConfig(String macAddress, List<Map<String, dynamic>> sections) async {
    if (macAddress.isEmpty) return;
    try {
      await _firestore.collection('dispenser').doc(macAddress).set({
        'section_config': sections,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving section_config: $e');
    }
  }

  // 2. Cihaz adını güncelleme
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

  // 3. Manuel Cihaz Ekleme (Sağlamlaştırılmış Mantık)
  Future<String> addDeviceManually(String uid, String rawEmail, String macAddress) async {
    if (uid.isEmpty || macAddress.isEmpty || rawEmail.isEmpty) return 'Geçersiz bilgi.';

    final String userEmail = _sanitize(rawEmail);

    try {
      final deviceRef = _firestore.collection('dispenser').doc(macAddress);
      final userRef = _firestore.collection('users').doc(uid);

      return await _firestore.runTransaction((transaction) async {
        final deviceDoc = await transaction.get(deviceRef);

        if (!deviceDoc.exists) {
          return 'Bu MAC adresine sahip bir cihaz bulunamadı.';
        }

        final deviceData = deviceDoc.data() as Map<String, dynamic>;
        final currentOwner = (deviceData['owner_mail'] as String?)?.toLowerCase();

        // Mevcut listeleri al ve temizle (Büyük/Küçük harf farketmeksizin siler)
        List<String> secondaryMails = List<String>.from(deviceData['secondary_mails'] ?? []);
        List<String> readOnlyMails = List<String>.from(deviceData['read_only_mails'] ?? []);

        // Listeden bu kullanıcıyı tamamen çıkar (Temizlik)
        secondaryMails.removeWhere((e) => _sanitize(e) == userEmail);
        readOnlyMails.removeWhere((e) => _sanitize(e) == userEmail);

        if (currentOwner == null || currentOwner.isEmpty) {
          // DURUM A: Sahipsiz -> Owner Ol
          transaction.update(deviceRef, {
            'owner_mail': userEmail,
            'secondary_mails': secondaryMails, // Temizlenmiş liste
            'read_only_mails': readOnlyMails, // Temizlenmiş liste
          });

          transaction.update(userRef, {
            'owned_dispensers': FieldValue.arrayUnion([macAddress]),
            'secondary_dispensers': FieldValue.arrayRemove([macAddress]),
            'read_only_dispensers': FieldValue.arrayRemove([macAddress]),
          });

        } else if (currentOwner != userEmail) {
          // DURUM B: Sahipli -> İzleyici Ol (Varsayılan)
          readOnlyMails.add(userEmail); // Listeye ekle

          transaction.update(deviceRef, {
            'read_only_mails': readOnlyMails,
            'secondary_mails': secondaryMails, // Temizlenmiş halini yaz (varsa silinmiş olur)
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

  // 4. Kullanıcıyı Terfi Ettirme (Read-Only -> Secondary)
  Future<void> promoteToSecondary(String macAddress, String targetRawEmail) async {
    final String targetEmail = _sanitize(targetRawEmail);
    try {
      final deviceRef = _firestore.collection('dispenser').doc(macAddress);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(deviceRef);
        if (!snapshot.exists) return;

        final data = snapshot.data() as Map<String, dynamic>;

        // Listeleri al ve manuel düzenle (Case-safe)
        List<String> readOnly = List<String>.from(data['read_only_mails'] ?? []);
        List<String> secondary = List<String>.from(data['secondary_mails'] ?? []);

        // Read-only'den sil
        readOnly.removeWhere((e) => _sanitize(e) == targetEmail);

        // Secondary'e ekle (eğer yoksa)
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

  // 5. Rol Kontrolü
  Future<DeviceRole> getUserRole(String macAddress, String rawEmail) async {
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
      return DeviceRole.none;
    }
  }

  // 6. Senkronizasyon (Hiyerarşik ve Case-Insensitive)
  Future<void> updateUserDeviceList(String uid, String rawEmail) async {
    if (uid.isEmpty || rawEmail.isEmpty) return;
    final String email = _sanitize(rawEmail);

    try {
      // Veritabanındaki tüm cihazları çekip manuel filtreleyeceğiz
      // (Firestore'da 'where arrayContains' case-sensitive olduğu için %100 güvenli değil)
      // Ancak performans için şimdilik 'where' kullanıyoruz, AuthService'de email'i düzelttik.

      final ownerQuery = await _firestore.collection('dispenser').where('owner_mail', isEqualTo: email).get();
      final secondaryQuery = await _firestore.collection('dispenser').where('secondary_mails', arrayContains: email).get();
      final readOnlyQuery = await _firestore.collection('dispenser').where('read_only_mails', arrayContains: email).get();

      final Set<String> ownedIds = ownerQuery.docs.map((d) => d.id).toSet();
      final Set<String> secondaryIds = secondaryQuery.docs.map((d) => d.id).toSet();
      final Set<String> readOnlyIds = readOnlyQuery.docs.map((d) => d.id).toSet();

      // HİYERARŞİ TEMİZLİĞİ
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
}