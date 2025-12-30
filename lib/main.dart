import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:dispenserapp/app/alarm_ring_screen.dart';
import 'package:dispenserapp/app/login_screen.dart';
import 'package:dispenserapp/app/main_hub.dart';
import 'package:dispenserapp/app/welcome_screen.dart';
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/notification_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

// --- GLOBAL DURUM YÖNETİCİLERİ ---
final ValueNotifier<AlarmSettings?> globalAlarmState = ValueNotifier<AlarmSettings?>(null);
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await EasyLocalization.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

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
  static const platform = MethodChannel('com.example.dispenserapp/lock_control');
  StreamSubscription<AlarmSettings>? _alarmSubscription;

  @override
  void initState() {
    super.initState();
    _alarmSubscription = Alarm.ringStream.stream.listen((alarmSettings) async {
      try {
        await platform.invokeMethod('showOnLockScreen');
      } catch (_) {}
      globalAlarmState.value = alarmSettings;
    });
  }

  @override
  void dispose() {
    _alarmSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'MedTrack',
      theme: appTheme,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return ValueListenableBuilder<AlarmSettings?>(
          valueListenable: globalAlarmState,
          builder: (context, alarmSettings, _) {
            return Stack(
              children: [
                if (child != null) child,
                if (alarmSettings != null)
                  Positioned.fill(
                    child: AlarmRingScreen(alarmSettings: alarmSettings),
                  ),
              ],
            );
          },
        );
      },
      home: const RootGate(),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _isInitDone = false;
  bool _onboardingComplete = false;

  @override
  void initState() {
    super.initState();
    _appBootstrap();
  }

  Future<void> _appBootstrap() async {
    try {
      // Notification + lock screen kanal init
      await NotificationService.initializeNotifications();
      const platform = MethodChannel('com.example.dispenserapp/lock_control');
      try {
        await platform.invokeMethod('hideFromLockScreen');
      } catch (_) {}

      // SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _onboardingComplete = prefs.getBool('onboarding_complete') ?? false;

      // ✅ KRİTİK: Session restore (Silent Sign-In)
      // Daha önce login olduysa (user_uid var) ama Firebase currentUser null ise,
      // Login ekranına düşmeden önce sessizce restore etmeyi dene.
      final hasCachedUid = prefs.getString('user_uid') != null;
      if (hasCachedUid && FirebaseAuth.instance.currentUser == null) {
        await AuthService().signInSilently();
      }

      // Cold start alarm kontrolü
      final alarms = await Alarm.getAlarms();
      for (var alarm in alarms) {
        if (alarm.dateTime.isBefore(DateTime.now()) &&
            alarm.dateTime.add(const Duration(minutes: 10)).isAfter(DateTime.now())) {
          if (await Alarm.isRinging(alarm.id)) {
            globalAlarmState.value = alarm;
          }
        }
      }
    } catch (e) {
      debugPrint("Bootstrap Hatası: $e");
    } finally {
      if (mounted) setState(() => _isInitDone = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitDone) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.skyBlue)),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Firebase hala state yayınlıyor olabilir
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Cache doluysa göz kırpma engelle
          if (FirebaseAuth.instance.currentUser != null) {
            return const MainHub();
          }
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator(color: AppColors.skyBlue)),
          );
        }

        // Kullanıcı var
        if (snapshot.hasData) {
          return const MainHub();
        }

        // Kullanıcı yok
        if (_onboardingComplete) {
          return const LoginScreen();
        }

        return const WelcomeScreen();
      },
    );
  }
}
