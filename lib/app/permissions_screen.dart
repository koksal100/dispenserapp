import 'dart:io';
import 'package:flutter/services.dart';
import 'package:dispenserapp/app/login_screen.dart';
import 'package:dispenserapp/main.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isLoading = false;
  static const _platform = MethodChannel('com.example.dispenserapp/permissions');
  bool _needsRecheckOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
        );

    _controller.forward();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _needsRecheckOnResume) {
      _needsRecheckOnResume = false;
      _recheckAndContinueIfOk();
    }
  }

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 100));

    // 1) Normal izinler
    await _requestStandardPermissions();

    // 2) Android özel izinler
    if (Platform.isAndroid) {
      final ok = await _ensureAndroidSpecialPermissions();
      if (!ok) {
        setState(() => _isLoading = false);
        return;
      }

      // 3) KRİTİK: Pil optimizasyonu izni
      final batteryOk = await _ensureBatteryOptimization();
      if (!batteryOk) {
        setState(() => _isLoading = false);
        return;
      }
    }

    await _completeOnboarding();
  }

  Future<void> _requestStandardPermissions() async {
    await Permission.notification.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
  }

  Future<bool> _ensureAndroidSpecialPermissions() async {
    // Exact alarm
    final canExact =
        await _platform.invokeMethod<bool>('canScheduleExactAlarms') ?? false;

    if (!canExact) {
      final go = await _showGoToSettingsDialog(
        title: 'alarm_permission_title'.tr(),
        message: 'alarm_permission_desc'.tr(),
        button: 'open_settings'.tr(),
      );
      if (go) {
        _needsRecheckOnResume = true;
        await _platform.invokeMethod('openExactAlarmSettings');
      }
      return false;
    }

    // Full-screen intent
    final canFsi =
        await _platform.invokeMethod<bool>('canUseFullScreenIntent') ?? true;

    if (!canFsi) {
      final go = await _showGoToSettingsDialog(
        title: 'fsi_permission_title'.tr(),
        message: 'fsi_permission_desc'.tr(),
        button: 'open_settings'.tr(),
      );
      if (go) {
        _needsRecheckOnResume = true;
        await _platform.invokeMethod('openFullScreenIntentSettings');
      }
      return false;
    }

    return true;
  }

  // KRİTİK YENİ FONKSİYON: Pil optimizasyonu
  Future<bool> _ensureBatteryOptimization() async {
    final isDisabled =
        await _platform.invokeMethod<bool>('isBatteryOptimizationDisabled') ?? false;

    if (!isDisabled) {
      final go = await _showGoToSettingsDialog(
        title: 'Pil Tasarrufu İzni',
        message: 'Alarmların arka planda çalışması için pil optimizasyonunu kapatmanız gerekiyor. Bu, alarmların sistem tarafından kapatılmasını engelleyecek.',
        button: 'Ayarları Aç',
      );
      if (go) {
        _needsRecheckOnResume = true;
        await _platform.invokeMethod('requestBatteryOptimization');
      }
      return false;
    }

    return true;
  }

  Future<void> _recheckAndContinueIfOk() async {
    setState(() => _isLoading = true);

    final ok1 = await _ensureAndroidSpecialPermissions();
    if (!ok1) {
      setState(() => _isLoading = false);
      return;
    }

    final ok2 = await _ensureBatteryOptimization();
    if (!ok2) {
      setState(() => _isLoading = false);
      return;
    }

    await _completeOnboarding();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
        const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  Future<bool> _showGoToSettingsDialog({
    required String title,
    required String message,
    required String button,
  }) async {
    if (!mounted) return false;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(button),
          ),
        ],
      ),
    ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.skyBlue.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.security_update_good_rounded,
                            size: 60, color: AppColors.skyBlue),
                      ),
                      const SizedBox(height: 30),
                      Text(
                        "permissions_title".tr(),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.deepSea,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "permissions_description".tr(),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: Colors.blueGrey.shade600,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 40.0),
                    child: _isLoading
                        ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.skyBlue))
                        : _PermissionButton(onTap: _requestPermissions),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionButton extends StatelessWidget {
  final VoidCallback onTap;
  const _PermissionButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [AppColors.skyBlue, AppColors.deepSea],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepSea.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Text(
              "permissions_button".tr(),
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}