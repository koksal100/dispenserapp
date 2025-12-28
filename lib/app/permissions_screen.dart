import 'dart:io';
import 'package:dispenserapp/app/login_screen.dart';
import 'package:dispenserapp/main.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);

    // Küçük bir bekleme ekleyip thread'i kilitlemeyi önlüyoruz
    await Future.delayed(const Duration(milliseconds: 100));

    if (Platform.isAndroid) {
      await [
        Permission.notification,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }
      if (await Permission.systemAlertWindow.isDenied) {
        await Permission.systemAlertWindow.request();
      }
    } else if (Platform.isIOS) {
      await [Permission.notification, Permission.bluetooth].request();
    }

    if (mounted) {
      // Sayfa geçiş animasyonu (Fade)
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
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

              // Animasyonlu Alan
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      // İkon Alanı - Statik olduğu için const
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.skyBlue.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.security_update_good_rounded, size: 60, color: AppColors.skyBlue),
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

              // Buton Alanı
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 40.0),
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator(color: AppColors.skyBlue))
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

// Butonu ayırarak rebuild maliyetini düşürüyoruz
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