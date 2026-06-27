import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {

  @override
  void initState() {
    super.initState();
    // 네이티브 스플래시 즉시 제거 → Flutter 스플래시가 끊김 없이 이어받음
    FlutterNativeSplash.remove();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/splash.png', fit: BoxFit.cover),
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
