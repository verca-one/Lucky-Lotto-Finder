// 다음 회차 추천번호 엔진 실행 시점 — 추첨(토) 후 바로 예측하지 않고 수요일 0시(KST)에 서버가 자동 실행.
// 그 전에 필요하면 관리자가 [수동 추천]으로 엔진 실행을 요청한다 (research_engine_requests, 회차당 1번).
// 앱은 요청 1행만 넣고, 실행은 서버(research_request_poll.py → Research Engine)가 한다. 규칙은 research_release.py 와 같다.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReleaseState {
  final int target;

  /// 자동 실행 시각(UTC). 직전 회차 추첨일을 모르면 null (= 제한 없음)
  final DateTime? releaseAtUtc;

  /// 수동 추천 요청 시각 · 서버 처리 상태(pending | dispatched | done)
  final DateTime? manualAt;
  final String? requestStatus;

  /// 다음 회차 예측이 열렸는지 (수요일 0시가 지났거나 수동 추천 요청이 있음)
  final bool released;
  const ReleaseState(this.target, this.releaseAtUtc, this.manualAt, this.released, {this.requestStatus});

  /// '10/21(수) 0시'
  String get releaseLabel {
    final r = releaseAtUtc;
    if (r == null) return '수요일 0시';
    final k = r.add(const Duration(hours: 9));
    return '${k.month}/${k.day}(수) 0시';
  }
}

class RecommendRelease {
  /// 수동 추천 요청 등 상태가 바뀌면 증가 (브리핑 화면 새로고침용)
  static final ValueNotifier<int> changes = ValueNotifier(0);

  /// 테스트에서 바꿔 끼우는 서버 접근
  static Future<Map<String, dynamic>?> Function(int target) fetchRequest = _fetch;
  static Future<void> Function(int target) insertRequest = _insert;

  /// 목표 회차 자동 실행 시각: 직전 회차 추첨일(토) + 4일 = 수요일 0시 KST (= 화요일 15:00 UTC)
  static DateTime? releaseAtUtc(String? prevDrawDate) {
    final d = DateTime.tryParse((prevDrawDate ?? '').trim().replaceAll('.', '-'));
    if (d == null) return null;
    return DateTime.utc(d.year, d.month, d.day).add(const Duration(days: 4)).subtract(const Duration(hours: 9));
  }

  /// 예측이 열렸는지 (순수 계산 — 단위 테스트 대상)
  static bool releasedAt({required DateTime? releaseAtUtc, required DateTime? manualAt, required DateTime nowUtc}) =>
      manualAt != null || releaseAtUtc == null || !nowUtc.toUtc().isBefore(releaseAtUtc);

  static Future<ReleaseState> state(int target, {String? prevDrawDate, DateTime? nowUtc}) async {
    final at = releaseAtUtc(prevDrawDate);
    Map<String, dynamic>? req;
    try {
      req = await fetchRequest(target);
    } catch (_) {}
    final manual = req == null ? null : DateTime.tryParse('${req['requested_at']}');
    return ReleaseState(target, at, manual,
        releasedAt(releaseAtUtc: at, manualAt: manual, nowUtc: nowUtc ?? DateTime.now().toUtc()),
        requestStatus: req?['status'] as String?);
  }

  /// 수동 추천 — 수요일 자동 실행 전에 이 회차 엔진 실행을 서버에 요청 (회차당 1번)
  static Future<void> requestRun(int target) async {
    await insertRequest(target);
    changes.value++;
  }

  static Future<Map<String, dynamic>?> _fetch(int target) async {
    final rows = await Supabase.instance.client
        .from('research_engine_requests')
        .select('target_round,requested_at,status')
        .eq('target_round', target)
        .limit(1);
    final l = List<Map<String, dynamic>>.from(rows as List);
    return l.isEmpty ? null : l.first;
  }

  static Future<void> _insert(int target) async {
    await Supabase.instance.client.from('research_engine_requests').insert({'target_round': target});
  }
}
