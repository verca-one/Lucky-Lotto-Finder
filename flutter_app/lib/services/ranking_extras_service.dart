// 홈 랭킹 카드 부가 정보 (읽기 전용 일괄 조회)
//
// 화면에 보이는 랭킹 목록 전체에 대해 한 번에 조회한다 (카드별 요청 없음).
//   * 평균 간격 · 마지막 1등 이후 — research_store_cycles (model_version 'rg-1.0', 최신 training_end_round)
//
// 관련 가설 수 · 지방장 연구 점수는 관리자 메뉴 전용 연구 정보이므로 홈 랭킹에서는 조회하지 않는다
// (hypothesisCount · agentScore 는 항상 null).
//
// 조회에 실패하면 해당 값만 비운다(null → 화면에서 '-' 또는 숨김).
// 값을 추정하거나 만들어내지 않는다. 연구 점수는 복권 한 장당 당첨확률이 아니다.
import 'package:supabase_flutter/supabase_flutter.dart';

import 'research/agent_research_repository.dart' show AgentStoreScore;

/// research_store_cycles 모델 버전 (지역·판매점 주기 연구)
const String kRankingCycleModel = 'rg-1.0';

/// 판매점 하나의 부가 정보. 각 필드는 데이터가 없거나 조회에 실패하면 null.
class RankingStoreExtras {
  /// 1등 평균 간격(회) — research_store_cycles.gap_mean
  final double? gapMean;

  /// 마지막 1등 이후 회차 수 (training_end_round 기준) — research_store_cycles.rounds_since_last
  final int? cycleRoundsSinceLast;

  /// 주기 연구 기준 회차 — research_store_cycles.training_end_round
  final int? cycleTrainingEnd;

  /// 이 판매점이 related_stores 에 포함된 가설 수 (조회 실패 = null, 조회 성공·없음 = 0)
  final int? hypothesisCount;

  /// 지방장 연구 점수 (없으면 null → 연구 점수 칸 숨김)
  final AgentStoreScore? agentScore;

  const RankingStoreExtras({
    this.gapMean,
    this.cycleRoundsSinceLast,
    this.cycleTrainingEnd,
    this.hypothesisCount,
    this.agentScore,
  });

  static const RankingStoreExtras empty = RankingStoreExtras();
}

class RankingExtrasService {
  RankingExtrasService._();

  static const Duration _ttl = Duration(minutes: 10);
  static final Map<String, (DateTime, RankingStoreExtras)> _cache = {};

  /// 캐시된 값 (없거나 만료 → null)
  static RankingStoreExtras? cached(String code) {
    final e = _cache[code];
    if (e == null) return null;
    if (DateTime.now().difference(e.$1) > _ttl) {
      _cache.remove(code);
      return null;
    }
    return e.$2;
  }

  static void clearCache() => _cache.clear();

  /// [stores] = lottery_stores 행 (dhlottery_code, region, address). 보이는 목록 전체를 한 번에 조회한다.
  /// [force] 이면 캐시를 무시하고 다시 조회한다 (당겨서 새로고침).
  static Future<Map<String, RankingStoreExtras>> load(
    List<Map<String, dynamic>> stores, {
    bool force = false,
    SupabaseClient? client,
  }) async {
    final codes = <String>[];
    for (final s in stores) {
      final code = (s['dhlottery_code'] ?? '').toString();
      if (code.isEmpty || codes.contains(code)) continue;
      codes.add(code);
    }

    final out = <String, RankingStoreExtras>{};
    final missing = <String>[];
    for (final c in codes) {
      final hit = force ? null : cached(c);
      if (hit != null) {
        out[c] = hit;
      } else {
        missing.add(c);
      }
    }
    if (missing.isEmpty) return out;

    SupabaseClient db;
    try {
      db = client ?? Supabase.instance.client;
    } catch (_) {
      return out; // Supabase 미초기화 (테스트 등) → 부가 정보 없음
    }

    final cycles = await _loadCycles(db, missing);

    final now = DateTime.now();
    for (final c in missing) {
      final cy = cycles?[c];
      final e = RankingStoreExtras(
        gapMean: _d(cy?['gap_mean']),
        cycleRoundsSinceLast: _i(cy?['rounds_since_last']),
        cycleTrainingEnd: _i(cy?['training_end_round']),
      );
      out[c] = e;
      // 실패했으면 캐시하지 않는다 (다음 진입 때 다시 시도)
      if (cycles != null) _cache[c] = (now, e);
    }
    return out;
  }

  /// store_code → 최신 training_end_round 행. 실패 = null.
  static Future<Map<String, Map<String, dynamic>>?> _loadCycles(SupabaseClient db, List<String> codes) async {
    try {
      final rows = await db
          .from('research_store_cycles')
          .select('store_code, training_end_round, gap_mean, rounds_since_last')
          .eq('model_version', kRankingCycleModel)
          .inFilter('store_code', codes)
          .order('training_end_round', ascending: false)
          .range(0, 1999);
      final out = <String, Map<String, dynamic>>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final c = (r['store_code'] ?? '').toString();
        if (c.isEmpty || out.containsKey(c)) continue; // 최신 회차만
        out[c] = r;
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// 가설 행(hypothesis_id, related_stores) → store_code 별 고유 가설 수 (순수 함수, 단위 테스트 대상).
  static Map<String, int> countHypothesesByStore(List<Map<String, dynamic>> rows, Iterable<String> codes) {
    final want = codes.toSet();
    final ids = <String, Set<String>>{};
    for (final r in rows) {
      final id = (r['hypothesis_id'] ?? '').toString();
      final rel = r['related_stores'];
      if (id.isEmpty || rel is! List) continue;
      for (final s in rel) {
        final c = s?.toString() ?? '';
        if (want.contains(c)) (ids[c] ??= <String>{}).add(id);
      }
    }
    return {for (final c in want) c: ids[c]?.length ?? 0};
  }

  static double? _d(dynamic v) => v is num ? v.toDouble() : (v == null ? null : double.tryParse('$v'));
  static int? _i(dynamic v) => v is num ? v.toInt() : (v == null ? null : int.tryParse('$v'));
}
