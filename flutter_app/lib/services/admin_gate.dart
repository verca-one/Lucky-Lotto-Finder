// 관리자 모드 확인 — 연구 데이터 조회 전 앱 내부 접근 제한
//
// 홈 화면에서 관리자 모드를 켜면 SharedPreferences 'isAdmin' = true 가 저장된다.
// 연구 로더(엔진 브리핑 · 지방장 연구 · 실전형 재현)는 이 값이 false 이면 조회하지 않고
// '관리자 전용' 상태를 돌려준다.
//
// 주의: 이것은 앱 내부 확인일 뿐이다. DB 수준 강제는 Supabase Auth(로그인 사용자·역할)를 도입한 뒤
// RLS 정책으로만 가능하며, 현재 anon 키의 RLS 는 연구 테이블 읽기를 허용한다.
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 관리자 모드 키
const String kAdminPrefKey = 'isAdmin';

/// 비관리자에게 돌려주는 안내 문구
const String kAdminOnlyMessage = '관리자 전용';

class AdminGate {
  AdminGate._();

  /// 관리자 모드 여부 (읽기 실패 = false)
  static Future<bool> isAdmin() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(kAdminPrefKey) ?? false;
    } catch (_) {
      return false;
    }
  }
}
