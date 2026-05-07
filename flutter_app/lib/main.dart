import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'screens/home_screen.dart';
import 'services/local_data_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase 초기화
  await Supabase.initialize(
    url: 'https://unmkjwdfthanhatyudwg.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVubWtqd2RmdGhhbmhhdHl1ZHdnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxNDc0MTMsImV4cCI6MjA5MjcyMzQxM30.gxHFHqS98fcUemZ5NshLjEy-WTkAeN_PNwVIwGvub-I',
  );

  // Google Mobile Ads 초기화
  MobileAds.instance.initialize();

  runApp(const LuckyLottoApp());
}

class LuckyLottoApp extends StatelessWidget {
  const LuckyLottoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => LocalDataService()),
      ],
      child: MaterialApp(
        title: 'Lucky Lotto Finder',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
