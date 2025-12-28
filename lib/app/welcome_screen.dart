import 'dart:ui' as ui;
import 'package:dispenserapp/app/permissions_screen.dart';
import 'package:dispenserapp/main.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  late Animation<double> _logoFadeAnimation;
  late Animation<Offset> _logoSlideAnimation;

  late Animation<double> _textFadeAnimation;
  late Animation<Offset> _textSlideAnimation;

  late Animation<double> _buttonFadeAnimation;
  late Animation<Offset> _buttonSlideAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setAppLanguage();
    });

    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Animasyon eğrileri optimize edildi
    const curve = Curves.easeOutCubic; // Daha doğal ve hesaplaması kolay

    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: curve)),
    );
    _logoSlideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: curve)),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.3, 0.8, curve: curve)),
    );
    _textSlideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.3, 0.8, curve: curve)),
    );

    _buttonFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.6, 1.0, curve: curve)),
    );
    _buttonSlideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.6, 1.0, curve: curve)),
    );

    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // RESMİ ÖNCEDEN YÜKLE (Gecikmeyi önler)
    precacheImage(const AssetImage('assets/icon.png'), context);
  }

  void _setAppLanguage() {
    final ui.Locale systemLocale = ui.PlatformDispatcher.instance.locale;
    if (systemLocale.languageCode == 'tr') {
      context.setLocale(const Locale('tr', 'TR'));
    } else {
      context.setLocale(const Locale('en', 'US'));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleGetStarted() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const PermissionsScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600), // Sayfa geçiş hızı
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // --- 1. PERFORMANCE KATMANI: BACKGROUND ---
          // RepaintBoundary: Bu arka planı bir resim gibi cache'ler,
          // üzerindeki animasyonlar oynarken arka plan tekrar tekrar çizilmez.
          const RepaintBoundary(
            child: _BackgroundDecoration(),
          ),

          SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(flex: 3),
                    FadeTransition(
                      opacity: _logoFadeAnimation,
                      child: SlideTransition(
                        position: _logoSlideAnimation,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: screenWidth * 0.5),
                          child: Image.asset(
                            'assets/icon.png',
                            width: 140,
                            height: 140,
                            fit: BoxFit.contain,
                            // gaplessPlayback: Titremeyi önler
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.local_hospital_rounded, size: 100, color: AppColors.skyBlue),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    FadeTransition(
                      opacity: _textFadeAnimation,
                      child: SlideTransition(
                        position: _textSlideAnimation,
                        child: Column(
                          children: [
                            Text(
                              "welcome_prefix".tr(),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.w300,
                                color: AppColors.deepSea,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "MedTrack",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                color: AppColors.skyBlue,
                                letterSpacing: -1.5,
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(flex: 4),
                    FadeTransition(
                      opacity: _buttonFadeAnimation,
                      child: SlideTransition(
                        position: _buttonSlideAnimation,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 60.0),
                          child: _StartButton(onTap: _handleGetStarted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- OPTİMİZE EDİLMİŞ WIDGETLAR (Rebuild'i engellemek için ayrıldı) ---

class _BackgroundDecoration extends StatelessWidget {
  const _BackgroundDecoration();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -150,
          right: -100,
          child: Container(
            width: 400,
            height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.skyBlue.withOpacity(0.15),
                  AppColors.skyBlue.withOpacity(0.0),
                ],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StartButton extends StatelessWidget {
  final VoidCallback onTap;
  const _StartButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [AppColors.skyBlue, AppColors.deepSea],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepSea.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          splashColor: Colors.white.withOpacity(0.2),
          highlightColor: Colors.white.withOpacity(0.1),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "login_start_btn".tr(),
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}