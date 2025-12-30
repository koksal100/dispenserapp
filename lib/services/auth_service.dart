import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dispenserapp/services/database_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppUser {
  final String uid;
  final String? displayName;
  final String? photoURL;
  final String? email;

  AppUser({
    required this.uid,
    this.displayName,
    this.photoURL,
    this.email,
  });
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseService _dbService = DatabaseService();

  /// Kullanıcı ilk kez butona basınca (interactive) çağır.
  /// Varsa mevcut Firebase oturumunu kullanır, yoksa Google Sign-In açar.
  Future<AppUser?> getOrCreateUser() async {
    final prefs = await SharedPreferences.getInstance();
    User? firebaseUser = _auth.currentUser;

    // Firebase oturumu yoksa -> interactive Google sign-in
    if (firebaseUser == null) {
      try {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return null; // kullanıcı iptal etti

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final UserCredential userCredential = await _auth.signInWithCredential(credential);
        firebaseUser = userCredential.user;
      } catch (e) {
        print('Google Sign-In Error: $e');
        return null;
      }
    }

    if (firebaseUser == null) return null;

    // Kullanıcıyı normalize et (prefs + firestore + device list)
    return _postAuthSync(firebaseUser, prefs: prefs);
  }

  /// Uygulama yeniden açıldığında session restore için çağır.
  /// Google hesabı cihazda varsa sessizce token alır ve Firebase’e tekrar oturtur.
  Future<User?> signInSilently() async {
    try {
      // Zaten kullanıcı varsa hiçbir şey yapma
      final existing = _auth.currentUser;
      if (existing != null) return existing;

      final GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      // Restore sonrası da aynı sync adımlarını uygula (firestore + prefs + device list)
      final prefs = await SharedPreferences.getInstance();
      final u = userCredential.user;
      if (u != null) {
        await _postAuthSync(u, prefs: prefs);
      }
      return u;
    } catch (e) {
      print('Silent Sign-In Error: $e');
      return null;
    }
  }

  Future<AppUser> _postAuthSync(User firebaseUser, {required SharedPreferences prefs}) async {
    final uid = firebaseUser.uid;
    final email = firebaseUser.email;
    final displayName = firebaseUser.displayName;
    final photoURL = firebaseUser.photoURL;

    // “Bu cihazda bir zamanlar login olmuştu” bilgisini sakla
    await prefs.setString('user_uid', uid);

    // Firestore’da profil bilgilerini güncelle (merge ile)
    try {
      await _firestore.collection('users').doc(uid).set({
        'email': email,
        'displayName': displayName ?? '',
        'photoURL': photoURL ?? '',
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Firestore update error: $e');
    }

    // Device list sync (email yoksa atla)
    if (email != null) {
      await _dbService.updateUserDeviceList(uid, email);
    }

    return AppUser(
      uid: uid,
      displayName: displayName,
      photoURL: photoURL,
      email: email,
    );
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_uid');
    } catch (e) {
      print("Sign out error: $e");
    }
  }
}
