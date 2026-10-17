// 추천번호 공개 시점 — 추첨(토) 후 바로 보이지 않고 수요일 0시(한국시간)에 공개, 그 전엔 관리자가 '수동 추천'으로 공개.
// 번호 계산·사전 등록(서버)은 그대로이며, 앱 화면에서 보여주는 시점만 정한다. 수동 공개는 이 기기에만 저장된다.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReleaseState {
  final int target;

  /// 자동 공개 시각(UTC). 직전 회차 추첨일을 모르면 null (= 바로 공개)
  final DateTime? releaseAtUtc;

  /// 수동 공개 시각 (수동 추천 버튼을 누른 경우)
  final DateTime? manualAt;
  final bool released;
  const ReleaseState(this.target, this.releaseAtUtc, this.manualAt, this.released);

  /// '10/21(수) 0시'
  String get releaseLabel {
    final r = releaseAtUtc;
    if (r == null) return '-';
    final k = r.add(const Duration(hours: 9));
    return '${k.month}/${k.day}(수) 0시';
  }
}

class RecommendRelease {
  static const _key = 'recommend_manual_release_';

  /// 추천 공개 상태가 바뀌면 증가 (브리핑 화면 새로고침용)
  static final ValueNotifier<int> changes = ValueNotifier(0);

  /// 목표 회차 자동 공개 시각: 직전 회차 추첨일(토) + 4일 = 수요일 0시 KST (= 화요일 15:00 UTC)
  static DateTime? releaseAtUtc(String? prevDrawDate) {
    final d = DateTime.tryParse((prevDrawDate ?? '').trim().replaceAll('.', '-'));
    if (d == null) return null;
    return DateTime.utc(d.year, d.month, d.day).add(const Duration(days: 4)).subtract(const Duration(hours: 9));
  }

  /// 공개 여부 (순수 계산 — 단위 테스트 대상)
  static bool releasedAt({required DateTime? releaseAtUtc, required DateTime? manualAt, required DateTime nowUtc}) =>
      manualAt != null || releaseAtUtc == null || !nowUtc.toUtc().isBefore(releaseAtUtc);

  static Future<ReleaseState> state(int target, {String? prevDrawDate, DateTime? nowUtc}) async {
    final at = releaseAtUtc(prevDrawDate);
    DateTime? manual;
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('$_key$target');
      manual = s == null ? null : DateTime.tryParse(s);
    } catch (_) {}
    return ReleaseState(target, at, manual,
        releasedAt(releaseAtUtc: at, manualAt: manual, nowUtc: nowUtc ?? DateTime.now().toUtc()));
  }

  /// 수동 추천 — 수요일 전에 이 회차 추천번호를 지금 공개 (이 기기)
  static Future<void> releaseNow(int target) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('$_key$target', DateTime.now().toUtc().toIso8601String());
    changes.value++;
  }
}
