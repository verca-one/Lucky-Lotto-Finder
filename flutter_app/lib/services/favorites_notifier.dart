import 'package:flutter/foundation.dart';

/// 즐겨찾기 변경을 전역으로 알리는 노티파이어
/// 값이 변경되면 리스너들이 즐겨찾기를 다시 로드합니다.
final ValueNotifier<int> favoritesNotifier = ValueNotifier<int>(0);

void notifyFavoritesChanged() {
  favoritesNotifier.value++;
}
