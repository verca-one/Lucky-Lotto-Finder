import 'package:flutter/foundation.dart';

/// 즐겨찾기 변경을 전역으로 알리는 노티파이어
/// 값이 변경되면 리스너들이 즐겨찾기를 다시 로드합니다.
final ValueNotifier<int> favoritesNotifier = ValueNotifier<int>(0);

void notifyFavoritesChanged() {
  favoritesNotifier.value++;
}

/// 프로필 로그인 · 로그아웃을 전역으로 알림 — 값 = userId (빈 문자열 = 로그아웃)
///   홈 · 지역 · 주변 판매점 카드의 카메라(사진 올리기)가 앱을 다시 켜지 않아도 바로 나타나고 사라지게
final ValueNotifier<String> loginNotifier = ValueNotifier<String>('');

/// 관리자 모드 켜기 · 끄기 알림 — 관리자도 판매점 카드 카메라(사진 올리기)가 보이게
final ValueNotifier<bool> adminNotifier = ValueNotifier<bool>(false);
