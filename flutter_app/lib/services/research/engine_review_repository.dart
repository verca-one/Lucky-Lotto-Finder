// 엔진 복기 연구소 — 저장된 복기 결과 조회 (research_v10_review.sql, 관리자 전용 · 읽기 전용)
// 복기·보정 계산은 서버(GitHub Actions)가 회차마다 자동 실행한다. 앱은 계산하지 않는다.
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin_gate.dart';

const String kReviewVersion = 'rv-1.0';
const String kReviewReplayRun = 'ag-1.1-r1';

const Map<String, String> kReviewGroupLabel = {
  'cycle': '주기',
  'lead': '선행·후행',
  'cowin': '동시 당첨',
  'spatial': '공간전이(인접 확산)',
  'trend': '지역 추세',
  'composite': '복합 조건',
  'other': '기타',
};

String reviewModeLabel(String? mode) => switch (mode) {
      'live' => '실전 사전 예측',
      'sequential_replay' => '과거 순차 재현',
      _ => '예측 방식 미확인',
    };

String reviewRankLabel(int? rank) => switch (rank) {
      1 => '1등',
      2 => '2등',
      3 => '3등',
      4 => '4등',
      5 => '5등',
      _ => '낙첨',
    };

/// 지방장 1명의 회차 복기 (compact 저장 형식 해석)
class AgentRoundEntry {
  final int nStores, regionFirst, regionEvents, second;
  final List<int> hits; // TOP1/3/5 1등 적중
  final List<double> expected; // TOP1/3/5 지역 내 무작위 기대
  final int any5, history5, routine, newHyp;
  final List<AgentWinner> winners;
  final Map<String, List<num>> groups; // 묶음 → [발화, 적중, 기대, 실전 적용 발화]
  final List<AgentChange> changes;
  const AgentRoundEntry({
    required this.nStores,
    required this.regionFirst,
    required this.regionEvents,
    required this.second,
    required this.hits,
    required this.expected,
    required this.any5,
    required this.history5,
    required this.winners,
    required this.groups,
    required this.changes,
    this.routine = 0,
    this.newHyp = 0,
  });

  bool get noWinner => regionFirst == 0;

  factory AgentRoundEntry.fromJson(Map j) {
    List<int> ints(dynamic v, int n) => v is List ? [for (final x in v) (x as num).toInt()] : List.filled(n, 0);
    return AgentRoundEntry(
      nStores: (j['n'] as num?)?.toInt() ?? 0,
      regionFirst: (j['rf'] as num?)?.toInt() ?? 0,
      regionEvents: (j['re'] as num?)?.toInt() ?? 0,
      second: (j['r2'] as num?)?.toInt() ?? 0,
      hits: ints(j['h'], 3),
      expected: j['x'] is List ? [for (final x in j['x'] as List) (x as num).toDouble()] : const [0, 0, 0],
      any5: (j['a5'] as num?)?.toInt() ?? 0,
      history5: (j['hh'] as num?)?.toInt() ?? 0,
      routine: (j['cc'] as num?)?.toInt() ?? 0,
      newHyp: (j['nw'] as num?)?.toInt() ?? 0,
      winners: [for (final w in (j['w'] as List? ?? const [])) AgentWinner.fromList(w as List)],
      groups: {
        for (final e in ((j['g'] as Map?) ?? const {}).entries)
          '${e.key}': [for (final x in e.value as List) x as num],
      },
      changes: [for (final c in (j['c'] as List? ?? const [])) AgentChange.fromList(c as List)],
    );
  }
}

class AgentWinner {
  final String code;
  final int? priorRank; // 추첨 전 점수 기준 지역 내 순위
  final int? hitRank; // 추천 TOP5 안이면 그 순위
  final bool normalized; // 같은 이름·주소의 다른 코드로 맞힌 경우
  const AgentWinner(this.code, this.priorRank, this.hitRank, this.normalized);
  factory AgentWinner.fromList(List l) => AgentWinner('${l[0]}', (l[1] as num?)?.toInt(), (l[2] as num?)?.toInt(),
      l.length > 3 && (l[3] as num?) == 1);
}

class AgentChange {
  final String hypothesisId, kind, from, to;
  final bool liveBefore, liveAfter;
  final double factorBefore, factorAfter;
  final int n, k;
  final double expected, p;
  const AgentChange(this.hypothesisId, this.kind, this.from, this.to, this.liveBefore, this.liveAfter, this.factorBefore,
      this.factorAfter, this.n, this.k, this.expected, this.p);
  bool get applied => liveBefore != liveAfter;
  factory AgentChange.fromList(List l) => AgentChange('${l[0]}', '${l[1]}', '${l[2]}', '${l[3]}', l[4] == 1, l[5] == 1,
      (l[6] as num).toDouble(), (l[7] as num).toDouble(), (l[8] as num).toInt(), (l[9] as num).toInt(),
      (l[10] as num).toDouble(), (l[11] as num).toDouble());
}

class EngineReviewRepository {
  EngineReviewRepository._();

  static SupabaseClient get _db => Supabase.instance.client;

  static Future<void> _adminOnly() async {
    if (!await AdminGate.isAdmin()) throw StateError('관리자 전용 화면입니다');
  }

  /// 복기된 회차 목록 (최신 먼저) — 요약·공간전이·보정 개수 포함
  static Future<List<Map<String, dynamic>>> rounds() async {
    await _adminOnly();
    final r = await _db
        .from('research_review_rounds')
        .select('target_round,status,prediction_mode,spatial,corr_count:corrections->count,'
            'corr_applied:corrections->applied,agents_summary:agents->summary')
        .eq('review_version', kReviewVersion)
        .order('target_round', ascending: false);
    return List<Map<String, dynamic>>.from(r as List);
  }

  static Future<Map<String, dynamic>?> round(int t) async {
    await _adminOnly();
    final r = await _db.from('research_review_rounds').select().eq('review_version', kReviewVersion).eq('target_round', t).limit(1);
    final l = r as List;
    return l.isEmpty ? null : Map<String, dynamic>.from(l.first as Map);
  }

  static Future<Map<String, dynamic>?> agentRound(int t) async {
    await _adminOnly();
    final r = await _db
        .from('research_review_agent_rounds')
        .select('target_round,prediction_mode,round_valid,agent_ids,entries,spatial,summary,integrity')
        .eq('review_version', kReviewVersion)
        .eq('target_round', t)
        .limit(1);
    final l = r as List;
    return l.isEmpty ? null : Map<String, dynamic>.from(l.first as Map);
  }

  static Future<List<Map<String, dynamic>>> cards() async {
    await _adminOnly();
    final r = await _db
        .from('research_review_agent_cards')
        .select()
        .eq('review_version', kReviewVersion)
        .order('agent_index');
    return List<Map<String, dynamic>>.from(r as List);
  }

  /// 지방장 1명의 최근 회차 복기 (배열 위치로 조회)
  static Future<List<(int, String?, AgentRoundEntry)>> agentHistory(int index, {int limit = 30}) async {
    await _adminOnly();
    final r = await _db
        .from('research_review_agent_rounds')
        .select('target_round,prediction_mode,e:entries->$index')
        .eq('review_version', kReviewVersion)
        .order('target_round', ascending: false)
        .limit(limit);
    return [
      for (final m in r as List)
        if (m['e'] is Map) ((m['target_round'] as num).toInt(), m['prediction_mode'] as String?, AgentRoundEntry.fromJson(m['e'] as Map)),
    ];
  }

  /// 회차 t 지방장 동결 TOP5 (원본 사전 예측)
  static Future<(List<String>, List<double>)?> frozenTop5(int t, String agentId) async {
    await _adminOnly();
    final r = await _db
        .from('research_replay_agent_predictions')
        .select('store_ids,scores')
        .eq('prediction_snapshot_id', '$kReviewReplayRun:$t')
        .eq('agent_id', agentId)
        .limit(1);
    final l = r as List;
    if (l.isEmpty) return null;
    return (
      [for (final c in l.first['store_ids'] as List) '$c'],
      [for (final s in (l.first['scores'] as List? ?? const [])) (s as num).toDouble()],
    );
  }

  static Future<Map<String, String>> storeNames(Iterable<String> codes) async {
    final list = codes.toSet().toList();
    if (list.isEmpty) return {};
    final out = <String, String>{};
    for (var i = 0; i < list.length; i += 150) {
      final r = await _db
          .from('lottery_stores')
          .select('dhlottery_code,store_name')
          .eq('lottery_type', 'lotto')
          .inFilter('dhlottery_code', list.sublist(i, i + 150 > list.length ? list.length : i + 150));
      for (final m in r as List) {
        out.putIfAbsent('${m['dhlottery_code']}', () => '${m['store_name']}');
      }
    }
    return out;
  }

  /// 엔진 브리핑용: 최신 확정 회차 복기 브리핑 (없으면 null)
  static Future<Map<String, dynamic>?> latestBriefing() async {
    await _adminOnly();
    final r = await _db
        .from('research_review_rounds')
        .select('target_round,status,prediction_mode,briefing,updated_at')
        .eq('review_version', kReviewVersion)
        .order('target_round', ascending: false)
        .limit(1);
    final l = r as List;
    return l.isEmpty ? null : Map<String, dynamic>.from(l.first as Map);
  }
}
