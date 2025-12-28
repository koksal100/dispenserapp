import 'dart:async';
import 'package:alarm/alarm.dart';
import 'package:dispenserapp/app/alarm_ring_screen.dart';
import 'package:dispenserapp/app/welcome_screen.dart'; // EKLENDİ: Karşılama Ekranı
import 'package:dispenserapp/services/notification_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart'; // EKLENDİ: Oturum kontrolü için
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'app/main_hub.dart';

// --- MEDTRACK RENK PALETİ ---
class AppColors {
  static const Color turquoise = Color(0xFF36C0A6);
  static const Color skyBlue = Color(0xFF1D8AD6);
  static const Color deepSea = Color(0xFF0F5191);
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
}

// --- TEMA AYARLARI ---
ThemeData get appTheme {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.skyBlue,
    primary: AppColors.skyBlue,
    secondary: AppColors.turquoise,
    surface: AppColors.background,
    onSurface: AppColors.deepSea,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: GoogleFonts.interTextTheme().copyWith(
      displayLarge: GoogleFonts.inter(fontWeight: FontWeight.w800, color: AppColors.deepSea),
      titleLarge: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 20, color: AppColors.deepSea),
      titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.deepSea),
      bodyLarge: GoogleFonts.inter(fontSize: 16, color: const Color(0xFF334155)),
      bodyMedium: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      scrolledUnderElevation: 0,
      iconTheme: const IconThemeData(color: AppColors.deepSea),
      titleTextStyle: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.deepSea,
        letterSpacing: -0.5,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blueGrey.shade50, width: 1),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.skyBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.turquoise,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.skyBlue,
      unselectedItemColor: Colors.blueGrey.shade300,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blueGrey.shade100),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.skyBlue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}

// GLOBAL NAVIGATOR KEY
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  await EasyLocalization.ensureInitialized();

  // Bildirim servisini başlatıyoruz ancak izin istemeyi BURADAN KALDIRDIK.
  // İzinler artık WelcomeScreen içerisinde isteniyor.
  await NotificationService.initializeNotifications();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
      path: 'assets/languages',
      fallbackLocale: const Locale('tr', 'TR'),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late StreamSubscription<AlarmSettings> subscription;
  // Kanal isminin MainActivity.kt ile AYNI olduğundan emin olun
  static const platform = MethodChannel('com.example.dispenserapp/lock_check');

  @override
  void initState() {
    super.initState();
    // ALARM DİNLEYİCİSİ
    subscription = Alarm.ringStream.stream.listen((alarmSettings) {
      debugPrint("Alarm tetiklendi! Ekran açılıyor...");

      // 1. Önce Native tarafa "Uygulamayı öne getir" komutu gönder
      _bringAppToFront();

      // 2. Sonra Flutter içinde sayfayı aç
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (context) => AlarmRingScreen(alarmSettings: alarmSettings),
          ),
        );
      }
    });
  }

  Future<void> _bringAppToFront() async {
    try {
      // Android ise native kodu tetikle
      if (Theme.of(context).platform == TargetPlatform.android) {
        await platform.invokeMethod('bringToFront');
      }
    } catch (e) {
      print("Öne getirme hatası: $e");
    }
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // BU KEY ÖNEMLİ
      title: 'MedTrack',
      theme: appTheme,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      // GÜNCELLEME BURADA:
      // Kullanıcı oturum açmışsa direkt ana sayfaya, açmamışsa karşılama ekranına.
      home: FirebaseAuth.instance.currentUser == null
          ? const WelcomeScreen()
          : const MainHub(),
      debugShowCheckedModeBanner: false,
    );
  }
}