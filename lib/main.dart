import 'package:dispenserapp/services/notification_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'app/main_hub.dart';

// --- MEDTRACK RENK PALETİ ---
class AppColors {
  static const Color turquoise = Color(0xFF36C0A6); // Nane Yeşili / Turkuaz
  static const Color skyBlue = Color(0xFF1D8AD6);   // Gök Mavisi (Ana Renk)
  static const Color deepSea = Color(0xFF0F5191);   // Derin Deniz Mavisi (Başlıklar)
  static const Color background = Color(0xFFF8FAFC); // Soğuk Beyaz/Gri Zemin
  static const Color surface = Colors.white;         // Kart Zeminleri
}

ThemeData get appTheme {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.skyBlue, // Ana tohum rengi
    primary: AppColors.skyBlue,
    secondary: AppColors.turquoise,
    surface: AppColors.background,
    onSurface: AppColors.deepSea, // Metinler siyah değil, koyu mavi olacak
    brightness: Brightness.light,
  );

  final baseTheme = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,

    // --- MODERN FONT AYARLARI (Inter) ---
    textTheme: GoogleFonts.interTextTheme().copyWith(
      // Başlıklar Derin Deniz Mavisi ile çok şık durur
      displayLarge: GoogleFonts.inter(fontWeight: FontWeight.w800, color: AppColors.deepSea),
      titleLarge: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 20, color: AppColors.deepSea),
      titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.deepSea),
      bodyLarge: GoogleFonts.inter(fontSize: 16, color: const Color(0xFF334155)), // Okunabilir koyu gri
      bodyMedium: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF475569)),
    ),

    // --- APPBAR ---
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      scrolledUnderElevation: 0,
      iconTheme: const IconThemeData(color: AppColors.deepSea), // İkonlar Koyu Mavi
      titleTextStyle: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.deepSea,
        letterSpacing: -0.5,
      ),
    ),

    // --- KART TASARIMI ---
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0, // Gölge yok (Flat Design)
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blueGrey.shade50, width: 1), // Çok ince mavimsi gri çizgi
      ),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    ),

    // --- BUTONLAR ---
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.skyBlue, // Butonlar Gök Mavisi
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
    ),

    // --- FLOATING ACTION BUTTON (FAB) ---
    // Sağ alttaki + butonu Turkuaz olursa çok güzel patlar
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.turquoise,
      foregroundColor: Colors.white,
      elevation: 2,
    ),

    // --- ALT MENÜ ---
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.skyBlue,
      unselectedItemColor: Colors.blueGrey.shade300,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
    ),

    // --- INPUT ALANLARI ---
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

  return baseTheme;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Status Bar Ayarları (İkonlar koyu mavi görünsün diye dark yapıyoruz)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  await EasyLocalization.ensureInitialized();
  await NotificationService.initializeNotifications();
  await NotificationService.requestPermission();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
      path: 'assets/languages',
      fallbackLocale: const Locale('tr', 'TR'),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedTrack',
      theme: appTheme,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: const MainHub(),
      debugShowCheckedModeBanner: false,
    );
  }
}