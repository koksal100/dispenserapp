import 'package:dispenserapp/app/main_hub.dart';
import 'package:dispenserapp/main.dart'; // AppColors
import 'package:dispenserapp/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dispenserapp/services/database_service.dart';
import 'package:dispenserapp/features/ble_provisioning/sync_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Animasyon eğrileri
    const curve = Curves.easeOutCubic;

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: curve)),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 1.0, curve: curve)),
    );

    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 120HZ İÇİN KRİTİK: Resimleri önbelleğe alıyoruz.
    // Böylece animasyon oynarken resim yüklemeye çalışıp takılma yapmaz.

    // Uygulama ikonu
    precacheImage(const AssetImage('assets/icon.png'), context);

    // Google Logosu (Lütfen assets klasörüne 'google_logo.png' ekleyin)
    // Eğer dosyanız yoksa bu satırı yorum satırı yapın.
    try {
      precacheImage(const AssetImage('assets/google_logo.png'), context);
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);

    try {
      final user = await _authService.getOrCreateUser();

      if (user != null && mounted) {
        // 1. Önce listeleri güncelle (Davetiyeler vs. için)
        final dbService = DatabaseService();
        await dbService.updateUserDeviceList(user.uid, user.email!);

        // 2. Hiç cihazı var mı kontrol et?
        bool hasDevice = await dbService.hasAnyAssociatedDevice(user.uid);

        if (mounted) {
          if (hasDevice) {
            // Cihazı var -> Ana Ekrana
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const MainHub()),
            );
          } else {
            // Cihazı yok -> Kurulum Ekranına (ONBOARDING MODUNDA)
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const SyncScreen(isOnboarding: true)),
            );
          }
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("error_occurred".tr(args: [e.toString()]))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // --- GPU DOSTU ARKA PLAN ---
          // RepaintBoundary ile arka planı "donduruyoruz", GPU tekrar tekrar çizmiyor.
          const RepaintBoundary(child: _LoginBackground()),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),

                  // --- LOGO ve BAŞLIK ---
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Column(
                        children: [
                          Container(
                            // Logoyu sınırla ki çok büyük görünmesin
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.skyBlue.withOpacity(0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/icon.png',
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              errorBuilder: (c,o,s) => const Icon(Icons.health_and_safety, size: 80, color: AppColors.skyBlue),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            "login_title".tr(),
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppColors.deepSea,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "login_subtitle".tr(),
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

                  const SizedBox(height: 48),

                  // --- GOOGLE BUTONU ---
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator(color: AppColors.skyBlue))
                          : _GoogleButton(onTap: _handleGoogleSignIn),
                    ),
                  ),

                  const Spacer(),

                  // --- ALT BİLGİ ---
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20.0),
                      child: Text(
                        "MedTrack Security",
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.blueGrey.shade300,
                            fontWeight: FontWeight.w500
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- ARKA PLAN WIDGET ---
class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -100,
          left: -50,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Blur yerine Gradient kullanımı (Performans artışı)
              gradient: RadialGradient(
                colors: [
                  AppColors.turquoise.withOpacity(0.15),
                  AppColors.turquoise.withOpacity(0.0),
                ],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -50,
          right: -50,
          child: Container(
            width: 250,
            height: 250,
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

// --- GOOGLE BUTONU (Asset Kullanımlı) ---
class _GoogleButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GoogleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. Assets klasörüne 'google_logo.png' attığınızdan emin olun.
              // 2. Eğer dosya yoksa, geçici olarak aşağıdaki Icon'u açabilirsiniz.
              Image.asset(
                'assets/google_logo.png', // Buraya kendi dosyanızı koyun
                height: 24,
                width: 24,
                errorBuilder: (context, error, stackTrace) {
                  // Dosya bulunamazsa yedek ikon göster
                  return const Icon(Icons.g_mobiledata, size: 36, color: Colors.red);
                },
              ),

              const SizedBox(width: 12),

              Text(
                "google_sign_in".tr(),
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}