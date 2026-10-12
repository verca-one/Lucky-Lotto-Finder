// 서버(헤드리스) 실행 환경 — flutter test 러너에서 기존 Dart 연구 엔진을 그대로 실행하기 위한 초기화.
// 키는 환경변수(SUPABASE_URL, SUPABASE_KEY)로만 받는다. 앱 번들에는 포함되지 않는다(tool/ 은 빌드 대상 아님).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> initServerSupabase() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 바인딩은 실제 HTTP 를 막는다 → 서버 실행에서는 해제
  HttpOverrides.global = null;
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final url = Platform.environment['SUPABASE_URL'] ?? '';
  final key = Platform.environment['SUPABASE_KEY'] ?? '';
  if (url.isEmpty || key.isEmpty) {
    throw StateError('SUPABASE_URL / SUPABASE_KEY 환경변수 필요');
  }
  await Supabase.initialize(
    url: url,
    anonKey: key,
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
      detectSessionInUri: false,
      autoRefreshToken: false,
    ),
  );
}

String envOr(String name, String fallback) => Platform.environment[name] ?? fallback;
