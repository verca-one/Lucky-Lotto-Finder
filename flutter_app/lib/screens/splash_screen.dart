import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';
import '../services/donation_service.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleAnim = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6)),
    );

    _startUp();
  }

  Future<void> _startUp() async {
    // 무거운 초기화를 병렬로 시작
    final initFuture = _initServices();

    // 0.3초 후 네이티브 스플래시 제거 → Flutter 스플래시(sss.png)로 전환
    await Future.delayed(const Duration(milliseconds: 50));
    FlutterNativeSplash.remove();
    _ctrl.forward();

    // 초기화 완료 + 최소 800ms Flutter 스플래시 표시 중 더 긴 쪽 대기
    await Future.wait([
      initFuture,
      Future.delayed(const Duration(milliseconds: 800)),
    ]);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  Future<void> _initServices() async {
    await Supabase.initialize(
      url: 'https://unmkjwdfthanhatyudwg.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVubWtqd2RmdGhhbmhhdHl1ZHdnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxNDc0MTMsImV4cCI6MjA5MjcyMzQxM30.gxHFHqS98fcUemZ5NshLjEy-WTkAeN_PNwVIwGvub-I',
    );
    await MobileAds.instance.initialize();
    MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: []),
    );
    DonationService().initialize();
    AdService.preloadInterstitial();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 배경: sss.png 전체화면
          Image.asset('assets/sss.png', fit: BoxFit.cover),
          // 반투명 어두운 오버레이 (아이콘 가독성 향상)
          Container(color: Colors.black.withValues(alpha: 0.15)),
          // 아이콘 (글로우 포함, 팝업 애니메이션)
          Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, child) => FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(scale: _scaleAnim, child: child),
              ),
              child: Image.asset(
                'assets/mamain_splash.png',
                width: MediaQuery.of(context).size.width * 0.55,
              ),
            ),
          ),
          // 하단 저작권
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '© 2026 HiCL Studio · All Rights Reserved',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                  shadows: const [
                    Shadow(offset: Offset(-1, -1), blurRadius: 3, color: Colors.black),
                    Shadow(offset: Offset(1, -1), blurRadius: 3, color: Colors.black),
                    Shadow(offset: Offset(-1,  1), blurRadius: 3, color: Colors.black),
                    Shadow(offset: Offset(1,  1), blurRadius: 3, color: Colors.black),
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
