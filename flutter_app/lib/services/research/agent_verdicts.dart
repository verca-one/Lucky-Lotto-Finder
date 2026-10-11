// 지방장 가설 판정(verdict) · 판매점 우위 문구 · 브리핑 요약 줄 — 순수 함수 모음 (단위 테스트 대상)
//
// * 판정은 research_replay_hypotheses.evidence.verdict 를 우선 쓰고, 없으면 status 로 대체한다
//   (passed/combined → 검증 통과, weakened/rejected → 검증 실패, 그 외 → 검증 중).
// * '검증하지 않음'(판매점 가설 없음)과 '검증했으나 우위 미확인'(가설은 있으나 통과 0)을 구분한다.
// * 값이 없으면 '데이터 없음' / '-' 로 표시하고 추정값을 만들지 않는다.
// * 점수는 복권 한 장당 당첨확률이 아니다.

import 'agent_research_repository.dart';

const String kNotPerTicketProbability = '점수는 복권 한 장당 당첨확률이 아닙니다.';

/// 가설 판정 집계 (판매점 하나 또는 목록 전체)
class AgentVerdictCounts {
  /// 관련 가설 전체 판정 수
  final Map<String, int> all;

  /// 판매점 단위 유형(kAgentStoreLevelKinds)만의 판정 수
  final Map<String, int> storeLevel;
  const AgentVerdictCounts({this.all = const {}, this.storeLevel = const {}});

  static AgentVerdictCounts of(Iterable<AgentHypothesis> hyps) {
    final all = <String, int>{};
    final st = <String, int>{};
    for (final h in hyps) {
      final v = h.verdict;
      all[v] = (all[v] ?? 0) + 1;
      if (h.isStoreLevel) st[v] = (st[v] ?? 0) + 1;
    }
    return AgentVerdictCounts(all: all, storeLevel: st);
  }

  int get total => all.values.fold(0, (a, b) => a + b);
  int get storeLevelTotal => storeLevel.values.fold(0, (a, b) => a + b);
  int storeLevelOf(String verdict) => storeLevel[verdict] ?? 0;
  int get storeLevelPassed => storeLevelOf(kVerdictPassed);
}

/// 판매점 우위 판정 종류
enum StoreEdgeKind {
  /// 판매점 단위 검증 통과 가설 있음
  passed,

  /// 판매점 단위 가설은 있으나 통과 0 (검증했으나 우위 미확인)
  testedNoEdge,

  /// 판매점 단위 가설 없음 (검증하지 않음)
  notTested,

  /// 가설 조회 불가 (데이터 없음)
  unknown,
}

extension StoreEdgeKindLabel on StoreEdgeKind {
  String get label => switch (this) {
        StoreEdgeKind.passed => '검증 통과 가설 있음',
        StoreEdgeKind.testedNoEdge => '검증했으나 우위 미확인',
        StoreEdgeKind.notTested => '검증하지 않음',
        StoreEdgeKind.unknown => '데이터 없음',
      };
}

class StoreEdgeWording {
  final StoreEdgeKind kind;
  final String text;
  const StoreEdgeWording(this.kind, this.text);
}

/// 판매점 우위 문구 (순수 함수).
///   [counts] null = 가설 조회 불가. [verifiedRounds] = 순방향 검증 회차 수 (없으면 회차 수 생략).
///   * 통과 n>0  → '검증 통과 가설 n건'
///   * 판매점 단위 가설 있음, 통과 0 → '판매점 우위: 246회 순방향 검증에서 확인 안 됨 (검증 실패 a · 표본 부족 b · 관측 누적 c)'
///   * 판매점 단위 가설 없음 → '판매점 가설 없음 (당첨 이력 부족 — 데이터 부족)'
StoreEdgeWording storeEdgeWording(AgentVerdictCounts? counts, {int? verifiedRounds}) {
  if (counts == null) {
    return const StoreEdgeWording(StoreEdgeKind.unknown, '판매점 가설 조회 불가 (데이터 없음)');
  }
  final passed = counts.storeLevelPassed;
  if (passed > 0) {
    return StoreEdgeWording(StoreEdgeKind.passed, '검증 통과 가설 $passed건');
  }
  if (counts.storeLevelTotal == 0) {
    return const StoreEdgeWording(StoreEdgeKind.notTested, '판매점 가설 없음 (당첨 이력 부족 — 데이터 부족)');
  }
  final parts = <String>[
    '검증 실패 ${counts.storeLevelOf(kVerdictFailed)}',
    '표본 부족 ${counts.storeLevelOf(kVerdictLowSample)}',
    '관측 누적 ${counts.storeLevelOf(kVerdictAccumulating)}',
  ];
  final pending = counts.storeLevelOf(kVerdictPending);
  if (pending > 0) parts.add('검증 중(세부 판정 없음) $pending');
  // 알 수 없는 판정 문자열
  final known = {...kVerdictOrder};
  final other = counts.storeLevel.entries.where((e) => !known.contains(e.key)).fold(0, (a, e) => a + e.value);
  if (other > 0) parts.add('기타 판정 $other');
  final rounds = verifiedRounds == null ? '' : '$verifiedRounds회 ';
  return StoreEdgeWording(
      StoreEdgeKind.testedNoEdge, '판매점 우위: $rounds순방향 검증에서 확인 안 됨 (${parts.join(' · ')})');
}

/// 여러 판매점 판정 → 요약 칩 문구 (순수 함수). 빈 목록이면 '판매점 가설 판정: 데이터 없음'.
String storeEdgeSummaryChip(List<StoreEdgeKind> kinds) {
  if (kinds.isEmpty || kinds.every((k) => k == StoreEdgeKind.unknown)) return '판매점 가설 판정: 데이터 없음';
  final passed = kinds.where((k) => k == StoreEdgeKind.passed).length;
  if (passed > 0) return '검증 통과 가설 보유 $passed곳';
  final tested = kinds.where((k) => k == StoreEdgeKind.testedNoEdge).length;
  return tested > 0 ? '판매점 우위: 검증했으나 확인 안 됨' : '판매점 우위: 검증하지 않음 (가설 없음)';
}

/// 여러 판매점 판정 분포 한 줄
String storeEdgeSummaryLine(List<StoreEdgeKind> kinds) {
  int n(StoreEdgeKind k) => kinds.where((x) => x == k).length;
  return '판매점 가설 판정: 검증 통과 ${n(StoreEdgeKind.passed)}곳 · 검증했으나 우위 미확인 ${n(StoreEdgeKind.testedNoEdge)}곳'
      ' · 검증하지 않음 ${n(StoreEdgeKind.notTested)}곳${n(StoreEdgeKind.unknown) > 0 ? ' · 데이터 없음 ${n(StoreEdgeKind.unknown)}곳' : ''}';
}

/// 판정 → 짧은 칩 문구
String verdictShort(String v) => kVerdictShort[v] ?? v;

/// 판정 필터 일치 (null = 전체)
bool verdictMatches(AgentHypothesis h, String? filter) => filter == null || h.verdict == filter;

// ═══════════════════════════════════════════════════════════════════════
// 점수 설명 (RegionStoreRanker)
// ═══════════════════════════════════════════════════════════════════════

const String kRegionScoreLabel = '목록 내 상대 연구 점수 (0~1, 확률 아님)';

const Map<String, String> kScoreComponentShort = {
  'history': '이력',
  'agent': '지방장',
  'cycle': '주기',
  'transition': '전이',
  'quality': '품질',
};

String fmtWeight(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('0') ? v.toStringAsFixed(1) : s;
}

/// '총점 = 0.3×이력 + 0.2×지방장 + 0.15×주기 + 0.15×전이 + 0.2×품질'
String scoreFormula(Map<String, double> weights) =>
    '총점 = ${weights.entries.map((e) => '${fmtWeight(e.value)}×${kScoreComponentShort[e.key] ?? e.key}').join(' + ')}';

/// '이력 0.30×0.82=0.25 · 지방장 0.20×1.00=0.20 …' (판매점 하나)
String scoreBreakdown(Map<String, double> weights, Map<String, double> components) => weights.entries
    .map((e) {
      final c = components[e.key] ?? 0;
      return '${kScoreComponentShort[e.key] ?? e.key} ${fmtWeight(e.value)}×${c.toStringAsFixed(2)}=${(c * e.value).toStringAsFixed(2)}';
    })
    .join(' · ');

/// 가장 크게 기여한 항목 (기여 0 초과, 큰 순)
List<String> topContributors(Map<String, double> weights, Map<String, double> components, {int take = 2}) {
  final l = weights.entries
      .map((e) => MapEntry(e.key, e.value * (components[e.key] ?? 0)))
      .where((e) => e.value > 1e-9)
      .toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return l.take(take).map((e) => kScoreComponentShort[e.key] ?? e.key).toList();
}

/// 최종 추천 이유 한 줄 (순수 함수)
///   [agentRank]/[agentSize] 지방장 내 순위, [liveApplied] 검증 가설 반영 여부, [edge] 판매점 우위 판정.
String finalRecommendReason({
  required Map<String, double> weights,
  required Map<String, double> components,
  int? first,
  int? second,
  int? agentRank,
  int? agentSize,
  bool liveApplied = false,
  StoreEdgeWording? edge,
}) {
  final parts = <String>[];
  final top = topContributors(weights, components);
  if (top.isEmpty) {
    parts.add('뚜렷한 기여 항목 없음');
  } else {
    parts.add('${top.join('·')} 기여가 가장 큼');
  }
  if (first != null || second != null) parts.add('1등 ${first ?? '-'}·2등 ${second ?? '-'}');
  if (agentRank != null && agentRank > 0) {
    parts.add('지방장 내 $agentRank${agentSize == null ? '' : '/$agentSize'}위');
  }
  parts.add(liveApplied ? '검증 통과 가설 점수 반영' : '반영된 검증 가설 없음 → 이력 기반 후보');
  if (edge != null) parts.add(edge.kind.label);
  return parts.join(' · ');
}

// ═══════════════════════════════════════════════════════════════════════
// 브리핑 payload 요약 (agent_performance · hypothesis_verdicts)
// ═══════════════════════════════════════════════════════════════════════

double? _d(dynamic v) => v is num ? v.toDouble() : (v == null ? null : double.tryParse('$v'));
int? _i(dynamic v) => v is num ? v.toInt() : (v == null ? null : int.tryParse('$v'));
Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String fmtN(dynamic v, [int d = 2]) {
  if (v == null) return '-';
  if (v is int) return '$v';
  final x = _d(v);
  return x == null ? '$v' : x.toStringAsFixed(d);
}

/// 0~1 이면 백분율로, 1 초과면 이미 백분율로 본다.
String fmtShare(dynamic v) {
  final x = _d(v);
  if (x == null) return '-';
  return '${(x <= 1 ? x * 100 : x).toStringAsFixed(0)}%';
}

String _ratio(dynamic hits, dynamic expected) {
  final h = _d(hits), e = _d(expected);
  if (h == null || e == null || e <= 0) return '';
  return ' (×${(h / e).toStringAsFixed(2)})';
}

/// agent_performance.totals → '1순위 적중 3건 / 무작위 기대 2.10 (×1.43)' 등 (값 없으면 그 줄 생략)
List<String> agentPerformanceTotalsLines(Map<String, dynamic> ap) {
  final t = _m(ap['totals']);
  final out = <String>[];
  for (final n in const [1, 3, 5]) {
    final h = t['top${n}_hits'], e = t['top${n}_expected'];
    if (h == null && e == null) continue;
    out.add('상위 $n위 적중 ${fmtN(h)}건 / 무작위 기대 ${fmtN(e)}건${_ratio(h, e)}');
  }
  final hh = _i(t['history_hits']), eh = _i(t['explore_hits']);
  if (hh != null || eh != null) {
    final diff = hh == null || eh == null ? '' : ' → 미검증 신호 반영 시 적중 변화 ${eh - hh >= 0 ? '+' : ''}${eh - hh}건';
    out.add('이력만 쓴 목록 ${fmtN(hh)}건 vs 미검증 신호까지 반영한 탐색 목록 ${fmtN(eh)}건$diff');
  }
  return out;
}

/// agent_performance 분포 줄 (지방장 수 · skill · lift · 표본 부족)
String? agentPerformanceDistributionLine(Map<String, dynamic> ap) {
  if (ap['agents'] == null && ap['skill_median'] == null && ap['lift_median'] == null) return null;
  return '평가 지방장 ${fmtN(ap['agents'])}명 · log-loss skill 양수 ${fmtN(ap['skill_positive'])}명'
      ' · skill 중앙값 ${fmtN(ap['skill_median'], 4)} · lift 중앙값 ${ap['lift_median'] == null ? '-' : '×${fmtN(ap['lift_median'])}'}'
      ' · 표본 부족 ${fmtN(ap['low_sample'])}명';
}

/// best/worst 항목 한 줄 + 표본 경고 여부
(String, bool) agentPerformanceEntryLine(Map<String, dynamic> e) {
  final t1 = _m(e['top1']), t5 = _m(e['top5']);
  final rounds = _i(e['rounds']);
  final e5 = _d(t5['expected_uniform']);
  final e1 = _d(t1['expected_uniform']);
  final low = (rounds != null && rounds < 30) || (e5 ?? e1) == null || (e5 ?? e1)! < 5;
  final id = (e['agent_id'] ?? '-').toString();
  final line = '${agentLabel(id)} · skill ${fmtN(e['ll_skill'], 4)} · lift ${e['lift'] == null ? '-' : '×${fmtN(e['lift'])}'}'
      ' · 1위 ${fmtN(t1['hits'])}/${fmtN(t1['expected_uniform'])}'
      ' · 5위 안 ${fmtN(t5['hits'])}/${fmtN(t5['expected_uniform'])}'
      ' · ${rounds == null ? '-' : '$rounds'}회';
  return (line, low);
}

/// hypothesis_verdicts.store_level → 설명 줄 (값 없으면 생략)
List<String> storeLevelVerdictLines(Map<String, dynamic> hv) {
  final s = _m(hv['store_level']);
  final out = <String>[];
  if (s.isEmpty) return out;
  final by = _m(s['by_verdict']);
  final total = s['store_level_total'];
  out.add('판매점 단위 가설 ${fmtN(total)}건: '
      '${kVerdictOrder.where((v) => by[v] != null).map((v) => '$v ${fmtN(by[v])}').join(' · ')}'
      '${by.keys.where((k) => !kVerdictOrder.contains(k)).map((k) => ' · $k ${fmtN(by[k])}').join()}');
  if (s['median_expected_events'] != null || s['share_expected_below_3'] != null) {
    out.add('가설 하나당 검증 구간 기대 사건 수 중앙값 ${fmtN(s['median_expected_events'])}건 · '
        '기대 3건 미만 가설 ${fmtShare(s['share_expected_below_3'])}');
  }
  if (s['min_detectable_ratio_at_median'] != null) {
    out.add('중앙값 표본에서 판정하려면 실제가 기대의 ×${fmtN(s['min_detectable_ratio_at_median'], 1)}배 이상이어야 함');
  }
  if (s['decided'] != null) {
    out.add('판정 완료(통과·실패) ${fmtN(s['decided'])}건 · 판정 가설의 실제/기대 비 중앙값 '
        '${s['decided_ratio_median'] == null ? '-' : '×${fmtN(s['decided_ratio_median'])}'}'
        ' · 실제가 기대보다 많았던 비율 ${fmtShare(s['decided_ratio_gt1_share'])}');
  }
  final passed = _i(by[kVerdictPassed]);
  final mdr = _d(s['min_detectable_ratio_at_median']);
  final med = _d(s['median_expected_events']);
  if (passed == 0 && (mdr != null || med != null)) {
    out.add('→ 판매점 하나의 1·2등 기대 사건이 매우 적어(중앙값 ${fmtN(med)}건) '
        '${mdr == null ? '큰' : '×${fmtN(mdr, 1)}배 이상의'} 차이가 아니면 통계적으로 판정할 수 없습니다. '
        '그래서 판매점 단위 검증 통과가 0건입니다 (판매점 우위가 없다는 증명도 아님).');
  }
  return out;
}

/// hypothesis_verdicts.by_kind → '유형: 판정 n · …' 줄
List<String> verdictByKindLines(Map<String, dynamic> hv) {
  final bk = _m(hv['by_kind']);
  final keys = bk.keys.toList()..sort();
  return [
    for (final k in keys)
      '${kAgentHypKindLabel[k] ?? k}: '
          '${_m(bk[k]).entries.map((e) => '${verdictShort(e.key)} ${fmtN(e.value)}').join(' · ')}',
  ];
}
