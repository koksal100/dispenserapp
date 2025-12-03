import 'package:dispenserapp/services/database_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String? displayName;
  final String email;

  AppUser({required this.uid, this.displayName, required this.email});
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseService _dbService = DatabaseService();

  Future<AppUser?> getOrCreateUser() async {
    final prefs = await SharedPreferences.getInstance();
    String? uid = prefs.getString('user_uid');
    String? email;
    String? displayName;

    if (uid == null) {
      try {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return null;

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final UserCredential userCredential = await _auth.signInWithCredential(credential);

        uid = userCredential.user?.uid;
        // KRİTİK DÜZELTME: Email'i her zaman küçük harfe çeviriyoruz
        email = userCredential.user?.email?.toLowerCase();
        displayName = userCredential.user?.displayName;

        if (uid != null && email != null) {
          await prefs.setString('user_uid', uid);

          await _firestore.collection('users').doc(uid).set({
            'createdAt': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
            'email': email, // Veritabanına da küçük harfle kaydediyoruz
            'displayName': displayName,
            'photoURL': userCredential.user?.photoURL,
          }, SetOptions(merge: true));
        }
      } catch (e) {
        print('Google giriş hatası: $e');
        return null;
      }
    } else {
      try {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        if (userDoc.exists) {
          // Veritabanından gelen veriyi de garantiye alalım
          email = (userDoc.data()!['email'] as String?)?.toLowerCase();
          displayName = userDoc.data()!['displayName'] as String?;
        }
        await _firestore.collection('users').doc(uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        print('Kullanıcı bilgisi çekme hatası: $e');
      }
    }

    if (uid != null && email != null) {
      // Listeleri senkronize et
      await _dbService.updateUserDeviceList(uid, email);
      return AppUser(uid: uid, displayName: displayName, email: email);
    }
    return null;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_uid');
  }
}