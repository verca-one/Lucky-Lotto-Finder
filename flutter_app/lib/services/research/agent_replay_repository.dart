// 전국 지방장 에이전트 ag-1.1 — '실전형 순차 재현' 기록 조회 전용 저장소 (관리자 연구 기능)
//
// ── 데이터 원칙 ───────────────────────────────────────────────────────────
//   * research_v6_replay.sql 의 research_replay_* 테이블을 SELECT 만 한다 (anon = 읽기 전용).
//     생산자는 서버 Worker(research_agent_replay.py)이며 앱은 기록하지 않는다.
//   * 테이블 없음(PGRST205/42P01/404) = '실전형 재현 미실행(SQL 미적용)', 행 없음 = '데이터 없음'.
//     값이 없으면 '-' 로 두고 추정값을 만들지 않는다.
//   * replay_mode 'sequential_replay' = 해당 회차 이전 데이터만으로 추첨 이후에 계산한 사후 재현,
//     'live' = 추첨 전에 동결된 실제 예측. 둘을 화면에서 항상 구분한다.
//   * 점수는 연구 기반 후보 점수(회차당 1·2등 기대 빈도, 판매량 미보정)이며 한 장당 당첨확률이 아니다.

import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../route/region_research_repository.dart'
    show ResearchAvailability, ResearchLoad, RegionResearchRepository, kResearchNoData;
import 'agent_research_repository.dart'
    show
        AgentCentralStore,
        AgentFocusRegion,
        AgentHypothesis,
        AgentInfo,
        AgentResearchRepository,
        agentModelForRun,
        kAgentReplayRunId,
        kAgentReplayRunPriority,
        kAgentStoreLevelKinds,
        pickDefaultReplayRun;

const String kReplayNotApplied = '실전형 재현 미실행(SQL 미적용)';
const String kReplayNoData = '실전형 재현 기록 없음';
const String kReplayModeLiveLabel = '실전: 추첨 전 동결';
const String kReplayModeReplayLabel = '사후 재현: 해당 회차 이전 데이터만 사용해 추첨 이후 계산한 기록';
const String kReplaySalesCaution = '과거 당첨 빈도는 판매량 영향이며 한 장당 당첨확률이 아닙니다.';
const String kReplayFrozenLabel = '당시 동결된 추천';

bool isReplayLiveMode(String? mode) => mode == 'live';
String replayModeShort(String? mode) => isReplayLiveMode(mode) ? '실전(live)' : '사후 재현';
String replayModeLong(String? mode) => isReplayLiveMode(mode) ? kReplayModeLiveLabel : kReplayModeReplayLabel;

// ═══════════════════════════════════════════════════════════════════════
// 파싱 유틸 (모든 필드 nullable 취급)
// ═══════════════════════════════════════════════════════════════════════

double? _d(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _iN(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String? _s(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : <Map<String, dynamic>>[];

List<String> _strs(dynamic v) =>
    v is List ? v.where((e) => e != null).map((e) => e.toString()).toList() : <String>[];

List<double?> _dbls(dynamic v) => v is List ? v.map(_d).toList() : <double?>[];

List<int?> _ints(dynamic v) => v is List ? v.map(_iN).toList() : <int?>[];

Map<String, int> _intMap(dynamic v) {
  final out = <String, int>{};
  if (v is Map) {
    v.forEach((k, val) {
      final n = _iN(val);
      if (n != null) out[k.toString()] = n;
    });
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════════════
// 모델
// ═══════════════════════════════════════════════════════════════════════

/// research_replay_predictions 한 행 (목록용은 가벼운 컬럼만, 상세는 동결 결과 포함)
class ReplayPrediction {
  final String snapshotId;
  final int targetRound;
  final int? availableThrough;
  final String replayMode;
  final String? createdAt;
  final int? activeHypotheses;
  final int? exploreFired;
  final List<String> liveHypothesesApplied;
  final List<AgentFocusRegion> focusRegions;
  final List<AgentFocusRegion> regions;
  final List<AgentCentralStore> storeTop;
  final Map<String, dynamic> dataProvenance;

  const ReplayPrediction({
    required this.snapshotId,
    required this.targetRound,
    this.availableThrough,
    this.replayMode = 'sequential_replay',
    this.createdAt,
    this.activeHypotheses,
    this.exploreFired,
    this.liveHypothesesApplied = const [],
    this.focusRegions = const [],
    this.regions = const [],
    this.storeTop = const [],
    this.dataProvenance = const {},
  });

  factory ReplayPrediction.fromRow(Map<String, dynamic> r) => ReplayPrediction(
        snapshotId: (r['prediction_snapshot_id'] ?? '').toString(),
        targetRound: _iN(r['target_round']) ?? 0,
        availableThrough: _iN(r['available_data_through_round']),
        replayMode: (r['replay_mode'] ?? 'sequential_replay').toString(),
        createdAt: _s(r['prediction_created_at']),
        activeHypotheses: _iN(r['active_hypotheses']),
        exploreFired: _iN(r['explore_hypotheses_fired']),
        liveHypothesesApplied: _strs(r['live_hypotheses_applied']),
        focusRegions: _maps(r['focus_regions']).map(AgentFocusRegion.fromMap).toList(),
        regions: _maps(r['regions']).map(AgentFocusRegion.fromMap).toList(),
        storeTop: _maps(r['store_top']).map(AgentCentralStore.fromMap).toList(),
        dataProvenance: _map(r['data_provenance']),
      );

  bool get isLive => isReplayLiveMode(replayMode);

  /// 주목 지역 + 전체 지역에서 [regionId] 찾기
  AgentFocusRegion? regionOf(String regionId) {
    for (final f in [...focusRegions, ...regions]) {
      if (f.regionId == regionId) return f;
    }
    return null;
  }
}

/// research_replay_results (실제 결과, 예측과 분리)
class ReplayResult {
  final String snapshotId;
  final int targetRound;
  final String? verifiedAt;
  final List<String> firstStoreIds;
  final List<String> firstRegions;
  final int? eventStoreCount;
  final int? unmatchedFirst;
  final int? unmatchedSecond;
  const ReplayResult({
    required this.snapshotId,
    required this.targetRound,
    this.verifiedAt,
    this.firstStoreIds = const [],
    this.firstRegions = const [],
    this.eventStoreCount,
    this.unmatchedFirst,
    this.unmatchedSecond,
  });
  factory ReplayResult.fromRow(Map<String, dynamic> r) => ReplayResult(
        snapshotId: (r['prediction_snapshot_id'] ?? '').toString(),
        targetRound: _iN(r['target_round']) ?? 0,
        verifiedAt: _s(r['result_verified_at']),
        firstStoreIds: _strs(r['first_store_ids']),
        firstRegions: _strs(r['first_regions']),
        eventStoreCount: _iN(r['event_store_count']),
        unmatchedFirst: _iN(r['unmatched_first']),
        unmatchedSecond: _iN(r['unmatched_second']),
      );
}

/// research_replay_central_evals.evaluation_metrics
class ReplayCentralEval {
  final int targetRound;
  final Map<String, dynamic> metrics;
  final String? verifiedAt;
  const ReplayCentralEval({required this.targetRound, this.metrics = const {}, this.verifiedAt});
  factory ReplayCentralEval.fromRow(Map<String, dynamic> r) => ReplayCentralEval(
        targetRound: _iN(r['target_round']) ?? 0,
        metrics: _map(r['evaluation_metrics']),
        verifiedAt: _s(r['result_verified_at']),
      );

  double? get loglossModel => _d(metrics['logloss_model']);
  double? get loglossM0 => _d(metrics['logloss_m0']);
  double? get loglossM1 => _d(metrics['logloss_m1']);
  int? get focusHits => _iN(metrics['focus_hits']);
  int? get focusHitsM0 => _iN(metrics['focus_hits_m0']);
  double? get focusExpected => _d(metrics['focus_expected']);
  int? get regionsWithFirst => _iN(metrics['regions_with_first']);
  int? get storeHitsAny => _iN(metrics['store_hits_any']);
  int? get storeHitsFirst => _iN(metrics['store_hits_first']);
  int? get storeHitsHistory => _iN(metrics['store_hits_history']);
  double? get storeExpectedUniform => _d(metrics['store_expected_uniform']);
  int? get events => _iN(metrics['events']);
}

/// research_replay_briefings 한 건 (pre / post). payload 모든 필드 nullable.
class ReplayBriefing {
  final String snapshotId;
  final String kind;
  final int targetRound;
  final Map<String, dynamic> payload;
  final String? createdAt;
  const ReplayBriefing({
    required this.snapshotId,
    required this.kind,
    required this.targetRound,
    this.payload = const {},
    this.createdAt,
  });
  factory ReplayBriefing.fromRow(Map<String, dynamic> r) => ReplayBriefing(
        snapshotId: (r['prediction_snapshot_id'] ?? '').toString(),
        kind: (r['kind'] ?? '').toString(),
        targetRound: _iN(r['target_round']) ?? _iN(_map(r['payload'])['target_round']) ?? 0,
        payload: _map(r['payload']),
        createdAt: _s(r['created_at']),
      );

  bool get isPre => kind == 'pre';
  List<String> get lines => _strs(payload['lines']);

  // ── pre ──
  int? get availableThrough => _iN(payload['available_data_through_round']);
  String? get replayMode => _s(payload['replay_mode']);
  List<AgentFocusRegion> get focusRegions => _maps(payload['focus_regions']).map(AgentFocusRegion.fromMap).toList();
  List<AgentCentralStore> get topStores => _maps(payload['top_stores']).map(AgentCentralStore.fromMap).toList();
  int? get activeHypotheses => _iN(payload['active_hypotheses']);
  List<AgentHypothesis> get liveApplied => _maps(payload['live_applied']).map(AgentHypothesis.fromMap).toList();
  int? get exploreFired => _iN(payload['explore_fired']);
  int? get newHypothesesCount => _iN(_map(payload['new_hypotheses'])['count']);
  Map<String, int> get newHypothesesByKind => _intMap(_map(payload['new_hypotheses'])['by_kind']);
  Map<String, int> get statusCounts => _intMap(payload['status_counts']);

  // ── post ──
  Map<String, dynamic> get actual => _map(payload['actual']);
  List<String> get actualFirstRegions => _strs(actual['first_regions']);
  List<Map<String, dynamic>> get actualFirstStores => _maps(actual['first_stores']);
  List<String> get focusHitRegions => _strs(actual['focus_hit_regions']);
  Map<String, dynamic> get agents => _map(payload['agents']);
  List<Map<String, dynamic>> get rank1Hits => _maps(agents['rank1_hits']);
  Map<String, dynamic> get central => _map(payload['central']);
  Map<String, int> get hypothesisChangeCounts => _intMap(_map(payload['hypothesis_changes'])['counts']);
  List<Map<String, dynamic>> get hypothesisChangeExamples =>
      _maps(_map(payload['hypothesis_changes'])['examples']);
  Map<String, dynamic> get trend => _map(payload['trend']);
}

class ReplayRoundDetail {
  final ReplayPrediction prediction;
  final ReplayResult? result;
  final ReplayCentralEval? centralEval;
  final ReplayBriefing? pre;
  final ReplayBriefing? post;
  const ReplayRoundDetail({required this.prediction, this.result, this.centralEval, this.pre, this.post});

  /// 사후 검증까지 끝났는지 (결과 행 존재)
  bool get verified => result != null;
}

/// research_replay_agent_evals (지방장별 사후 검증)
class ReplayAgentEval {
  final int targetRound;
  final int? hitsAny;
  final int? hitsFirst;
  final double? expectedUniform;
  final Map<String, dynamic> metrics;
  const ReplayAgentEval({
    required this.targetRound,
    this.hitsAny,
    this.hitsFirst,
    this.expectedUniform,
    this.metrics = const {},
  });
  factory ReplayAgentEval.fromRow(Map<String, dynamic> r) {
    final m = _map(r['evaluation_metrics']);
    return ReplayAgentEval(
      targetRound: _iN(r['target_round']) ?? 0,
      hitsAny: _iN(r['hits_any']) ?? _iN(m['hits_any']),
      hitsFirst: _iN(r['hits_first']) ?? _iN(m['hits_first']),
      expectedUniform: _d(r['expected_uniform']) ?? _d(m['expected_uniform']),
      metrics: m,
    );
  }

  List<int?> get byRank => _ints(metrics['by_rank']);
  int? get historyHits => _iN(metrics['history_hits']);
  int? get exploreHits => _iN(metrics['explore_hits']);
  int? get regionEvents => _iN(metrics['region_events']);
  int? get regionFirst => _iN(metrics['region_first']);
  double? get expectedModel => _d(metrics['expected_model']);
  double? get llModel => _d(metrics['ll_model']);
  double? get llBase => _d(metrics['ll_base']);
  int? get nStores => _iN(metrics['n_stores']);
  bool? get evaluatedStoredSnapshot {
    final v = metrics['evaluated_stored_snapshot'];
    return v is bool ? v : null;
  }

  /// [rank](1부터)의 적중 수 (by_rank 없으면 null)
  int? hitAtRank(int rank) {
    final l = byRank;
    if (rank < 1 || rank > l.length) return null;
    return l[rank - 1];
  }
}

/// research_replay_agent_predictions (+ 검증) — 지방장 한 명의 한 회차 동결 납품
class ReplayAgentRound {
  final String snapshotId;
  final String agentId;
  final int targetRound;
  final int? availableThrough;
  final String regionId;
  final List<String> storeIds;
  final List<double?> scores;
  final List<double?> pFirst;
  final List<double?> liveFactors;
  final dynamic appliedHypothesisIds;
  final int? nStores;
  final String? createdAt;
  final String replayMode;
  final ReplayAgentEval? eval;

  const ReplayAgentRound({
    required this.snapshotId,
    required this.agentId,
    required this.targetRound,
    this.availableThrough,
    this.regionId = '',
    this.storeIds = const [],
    this.scores = const [],
    this.pFirst = const [],
    this.liveFactors = const [],
    this.appliedHypothesisIds,
    this.nStores,
    this.createdAt,
    this.replayMode = 'sequential_replay',
    this.eval,
  });

  factory ReplayAgentRound.fromRow(Map<String, dynamic> r, {ReplayAgentEval? eval}) => ReplayAgentRound(
        snapshotId: (r['prediction_snapshot_id'] ?? '').toString(),
        agentId: (r['agent_id'] ?? '').toString(),
        targetRound: _iN(r['target_round']) ?? 0,
        availableThrough: _iN(r['available_data_through_round']),
        regionId: (r['region_id'] ?? '').toString(),
        storeIds: _strs(r['store_ids']),
        scores: _dbls(r['scores']),
        pFirst: _dbls(r['p_first']),
        liveFactors: _dbls(r['live_factors']),
        appliedHypothesisIds: r['applied_hypothesis_ids'],
        nStores: _iN(r['n_stores']),
        createdAt: _s(r['prediction_created_at']),
        replayMode: (r['replay_mode'] ?? 'sequential_replay').toString(),
        eval: eval,
      );

  bool get isLive => isReplayLiveMode(replayMode);

  double? scoreAt(int i) => i < scores.length ? scores[i] : null;
  double? pFirstAt(int i) => i < pFirst.length ? pFirst[i] : null;
  double? liveFactorAt(int i) => i < liveFactors.length ? liveFactors[i] : null;

  /// i 번째 판매점의 실전 반영 가설 id 목록 (applied_hypothesis_ids 형식: [[..],[..]] 또는 {code:[..]})
  List<String> appliedAt(int i) {
    final a = appliedHypothesisIds;
    if (a is List && i < a.length) return _strs(a[i]);
    if (a is Map && i < storeIds.length) return _strs(a[storeIds[i]]);
    return const [];
  }

  /// 페이지 조합: 예측 행 + 같은 prediction_snapshot_id 의 검증 행 (순수 함수, 단위 테스트 대상)
  static List<ReplayAgentRound> join(List<Map<String, dynamic>> predRows, List<Map<String, dynamic>> evalRows) {
    final evals = <String, ReplayAgentEval>{};
    for (final e in evalRows) {
      final key = '${e['prediction_snapshot_id'] ?? ''}|${e['agent_id'] ?? ''}';
      evals[key] = ReplayAgentEval.fromRow(e);
    }
    final out = predRows
        .map((r) => ReplayAgentRound.fromRow(r,
            eval: evals['${r['prediction_snapshot_id'] ?? ''}|${r['agent_id'] ?? ''}']))
        .toList()
      ..sort((a, b) => b.targetRound.compareTo(a.targetRound));
    return out;
  }
}

class ReplayHypothesisEvent {
  final String hypothesisId;
  final int round;
  final String? statusFrom;
  final String statusTo;
  final int? testN, testK;
  final double? testExpected, testP, relativeRatio;
  final String? createdAt;
  const ReplayHypothesisEvent({
    required this.hypothesisId,
    required this.round,
    this.statusFrom,
    required this.statusTo,
    this.testN,
    this.testK,
    this.testExpected,
    this.testP,
    this.relativeRatio,
    this.createdAt,
  });
  factory ReplayHypothesisEvent.fromRow(Map<String, dynamic> r) => ReplayHypothesisEvent(
        hypothesisId: (r['hypothesis_id'] ?? '').toString(),
        round: _iN(r['round']) ?? 0,
        statusFrom: _s(r['status_from']),
        statusTo: (r['status_to'] ?? '').toString(),
        testN: _iN(r['test_n']),
        testK: _iN(r['test_k']),
        testExpected: _d(r['test_expected']),
        testP: _d(r['test_p']),
        relativeRatio: _d(r['relative_ratio']),
        createdAt: _s(r['created_at']),
      );
}

/// research_replay_runs 한 행
class ReplayRun {
  final String runId;
  final String? modelVersion;
  final String? replayMode;
  final String status;
  final int? startRound;
  final int? lastCompletedRound;
  final int? lastPredictionRound;
  final String? error;
  final String? updatedAt;
  final Map<String, dynamic> stats;

  /// research_replay_runs.data_provenance (컬럼 없으면 stats.data_provenance, 둘 다 없으면 빈 맵)
  final Map<String, dynamic> dataProvenance;

  /// 행 컬럼 또는 data_provenance 의 superseded_by / status_note
  final String? supersededBy;
  final String? statusNote;
  const ReplayRun({
    required this.runId,
    this.modelVersion,
    this.replayMode,
    this.status = '',
    this.startRound,
    this.lastCompletedRound,
    this.lastPredictionRound,
    this.error,
    this.updatedAt,
    this.stats = const {},
    this.dataProvenance = const {},
    this.supersededBy,
    this.statusNote,
  });
  factory ReplayRun.fromRow(Map<String, dynamic> r) {
    final stats = _map(r['stats']);
    final dp = r['data_provenance'] is Map ? _map(r['data_provenance']) : _map(stats['data_provenance']);
    return ReplayRun(
      runId: (r['replay_run_id'] ?? '').toString(),
      modelVersion: _s(r['model_version']),
      replayMode: _s(r['replay_mode']),
      status: (r['status'] ?? '').toString(),
      startRound: _iN(r['start_round']),
      lastCompletedRound: _iN(r['last_completed_round']),
      lastPredictionRound: _iN(r['last_prediction_round']),
      error: _s(r['error']),
      updatedAt: _s(r['updated_at']),
      stats: stats,
      dataProvenance: dp,
      supersededBy: _s(r['superseded_by']) ?? _s(dp['superseded_by']),
      statusNote: _s(r['status_note']) ?? _s(dp['status_note']),
    );
  }

  /// data_provenance.defect (문자열) — 있을 때만 결함 배지 표시
  String? get defect {
    final d = dataProvenance['defect'];
    if (d == null || d == false) return null;
    final s = d is String ? d : '$d';
    return s.trim().isEmpty ? null : s.trim();
  }

  bool get hasDefect => defect != null;

  /// data_provenance.integrity_check (date, method, result). 없으면 null.
  Map<String, dynamic>? get integrityCheck {
    final m = dataProvenance['integrity_check'];
    return m is Map ? Map<String, dynamic>.from(m) : null;
  }

  /// '무결성 검증: 2026-10-12 · 재계산 해시 비교 · 247건 일치' (없으면 null)
  String? get integrityLine => replayIntegrityLine(integrityCheck);

  /// 검증 회차 범위 ('1000~1245회') — 시작·완료 회차가 없으면 null
  String? get roundRange =>
      startRound == null || lastCompletedRound == null ? null : '$startRound~$lastCompletedRound회';

  /// 검증 회차 수 (시작~완료). 없으면 null.
  int? get verifiedRounds =>
      startRound == null || lastCompletedRound == null || lastCompletedRound! < startRound!
          ? null
          : lastCompletedRound! - startRound! + 1;
}

/// integrity_check 맵 → 한 줄 (순수 함수). 맵이 없거나 세 필드 모두 비면 null.
String? replayIntegrityLine(Map<String, dynamic>? m) {
  if (m == null) return null;
  final parts = [
    for (final k in const ['date', 'method', 'result'])
      if (m[k] != null && '${m[k]}'.trim().isNotEmpty) '${m[k]}'.trim(),
  ];
  return parts.isEmpty ? null : '무결성 검증: ${parts.join(' · ')}';
}

/// 재현 실행 배지 문구 (결함 표시가 있을 때만). 결함이 없으면 null.
String? replayRunDefectBadge(ReplayRun r) => r.hasDefect ? '데이터 결함 표시 — 기록 보존' : null;

/// Supabase 무료 한도 표시 기본값 (free_tier_bytes 가 없을 때 표시용, 500 MB)
const int kDbFreeTierBytesDefault = 500000000; // Supabase 무료 플랜 500MB (10^6 기준)

/// research_replay_runs.stats.usage — Worker 가 측정해 기록한 DB 사용량 (모든 필드 nullable)
/// {"latest":{"at","database_bytes","research_bytes","free_tier_bytes","pct"},
///  "history":[{"at","database_bytes","latest_round"}], "weekly_growth_bytes","weeks_to_limit",
///  "alert":{"level":"ok|warn|critical","message"}}
class DbUsage {
  final Map<String, dynamic> raw;
  const DbUsage(this.raw);

  /// stats 맵에서 usage 를 꺼낸다. 없거나 맵이 아니면 null (= 측정 전).
  static DbUsage? fromStats(Map<String, dynamic>? stats) {
    final u = stats?['usage'];
    return u is Map ? DbUsage(Map<String, dynamic>.from(u)) : null;
  }

  Map<String, dynamic> get latest => _map(raw['latest']);
  String? get at => _s(latest['at']);
  int? get databaseBytes => _iN(latest['database_bytes']);
  int? get researchBytes => _iN(latest['research_bytes']);
  int? get freeTierBytes => _iN(latest['free_tier_bytes']);

  /// 한도 (free_tier_bytes 없으면 500 MB 표기)
  int get limitBytes => (freeTierBytes ?? 0) > 0 ? freeTierBytes! : kDbFreeTierBytesDefault;

  /// 사용률 % — Worker 의 pct 우선, 없으면 측정값 database_bytes / 한도 로 계산. 측정값 없으면 null.
  double? get pct {
    final p = _d(latest['pct']);
    if (p != null) return p;
    final b = databaseBytes;
    return b == null ? null : b * 100 / limitBytes;
  }

  List<Map<String, dynamic>> get history => _maps(raw['history']);
  int? get latestRound {
    final h = history;
    for (var i = h.length - 1; i >= 0; i--) {
      final r = _iN(h[i]['latest_round']);
      if (r != null) return r;
    }
    return null;
  }

  double? get weeklyGrowthBytes => _d(raw['weekly_growth_bytes']);
  double? get weeksToLimit => _d(raw['weeks_to_limit']);
  Map<String, dynamic> get alert => _map(raw['alert']);

  /// 'ok' | 'warn' | 'critical' | null
  String? get alertLevel => _s(alert['level']);
  String? get alertMessage => _s(alert['message']);

  /// 측정값이 하나라도 있는지
  bool get measured => databaseBytes != null || history.isNotEmpty;
}

String fmtMb(num? bytes, [int d = 1]) => bytes == null ? '-' : (bytes / 1000000).toStringAsFixed(d);

/// performance.top["1"|"3"|"5"] — 상위 N 위 안 1·2등 적중 vs 무작위 기대
class ReplayTopPerf {
  final int? hits;
  final double? expectedUniform;
  final double? liftRaw;
  const ReplayTopPerf({this.hits, this.expectedUniform, this.liftRaw});
  factory ReplayTopPerf.fromMap(Map<String, dynamic> m) => ReplayTopPerf(
        hits: _iN(m['hits']),
        expectedUniform: _d(m['expected_uniform']),
        liftRaw: _d(m['lift']),
      );

  /// Worker 의 lift, 없으면 hits / expected_uniform (기대 0·없음이면 null)
  double? get lift => liftRaw ??
      (hits == null || expectedUniform == null || expectedUniform! <= 0 ? null : hits! / expectedUniform!);

  bool get isEmpty => hits == null && expectedUniform == null && liftRaw == null;
}

/// {"1": {...}, "3": {...}, "5": {...}} → N 오름차순 맵
Map<String, ReplayTopPerf> parseReplayTop(dynamic v) {
  final m = _map(v);
  final keys = m.keys.toList()..sort((a, b) => (_iN(a) ?? 0).compareTo(_iN(b) ?? 0));
  return {for (final k in keys) if (m[k] is Map) k: ReplayTopPerf.fromMap(_map(m[k]))};
}

/// research_agents.performance (ag-1.1) 의 최근 구간 성능
class ReplayRecentPerf {
  final int? rounds;
  final int? hitsAny;
  final double? expectedUniform;
  final int? historyHits;
  final double? llSkill;
  final Map<String, ReplayTopPerf> top;
  const ReplayRecentPerf(
      {this.rounds, this.hitsAny, this.expectedUniform, this.historyHits, this.llSkill, this.top = const {}});
  factory ReplayRecentPerf.fromMap(Map<String, dynamic> m) => ReplayRecentPerf(
        rounds: _iN(m['rounds']),
        hitsAny: _iN(m['hits_any']),
        expectedUniform: _d(m['expected_uniform']),
        historyHits: _iN(m['history_hits']),
        llSkill: _d(m['ll_skill']),
        top: parseReplayTop(m['top']),
      );

  /// 적중 / 무작위 기대 (기대 0·없음이면 null)
  double? get lift => hitsAny == null || expectedUniform == null || expectedUniform! <= 0
      ? null
      : hitsAny! / expectedUniform!;
}

/// research_agents.performance (ag-1.1) 파서 — 모든 필드 nullable
class ReplayPerformance {
  final Map<String, dynamic> raw;
  const ReplayPerformance(this.raw);

  /// ag-1.1 형식(recent / ll_skill / hits_vs_model / lift_vs_uniform 등)인지
  static bool isReplayShape(Map<String, dynamic> m) =>
      m['recent'] is Map ||
      m['top'] is Map ||
      m.containsKey('ll_skill') ||
      m.containsKey('hits_vs_model') ||
      m['data_quality'] is Map ||
      (m['rounds'] is num && m.containsKey('delivered'));

  int? get rounds => _iN(raw['rounds']);
  int? get delivered => _iN(raw['delivered']);
  int? get hitsAny => _iN(raw['hits_any']);
  int? get hitsFirst => _iN(raw['hits_first']);
  int? get historyHits => _iN(raw['history_hits']);
  int? get exploreHits => _iN(raw['explore_hits']);
  double? get expectedUniform => _d(raw['expected_uniform']);
  double? get expectedModel => _d(raw['expected_model']);
  double? get liftVsUniform => _d(raw['lift_vs_uniform']);
  double? get hitsVsModel => _d(raw['hits_vs_model']);
  double? get llSkill => _d(raw['ll_skill']);

  /// '10','30','50','100' → 구간 성능 (구간 오름차순)
  Map<String, ReplayRecentPerf> get recent {
    final m = _map(raw['recent']);
    final keys = m.keys.toList()..sort((a, b) => (_iN(a) ?? 0).compareTo(_iN(b) ?? 0));
    return {for (final k in keys) k: ReplayRecentPerf.fromMap(_map(m[k]))};
  }

  /// 상위 1·3·5 위 적중 vs 무작위 기대 ("1","3","5")
  Map<String, ReplayTopPerf> get top => parseReplayTop(raw['top']);
  ReplayTopPerf? topAt(int n) => top['$n'];

  /// 적중 기여: 검증 가설 반영 적중 / 미검증 신호 적중 / 설명
  Map<String, dynamic> get contribution => _map(raw['contribution']);
  int? get verifiedHypothesesHits => _iN(contribution['verified_hypotheses_hits']);
  int? get unverifiedSignalsHits => _iN(contribution['unverified_signals_hits']);
  String? get contributionNote => _s(contribution['note']);

  /// 비교 기준 (random_in_region, store_count, sales_volume, history_only). 값은 숫자·맵·문자열 가능.
  Map<String, dynamic> get baselines => _map(raw['baselines']);

  Map<String, int> get hypotheses => _intMap(raw['hypotheses']);
  int? get sharedOut => _iN(raw['shared_out']);
  Map<String, dynamic> get sharedIn => _map(raw['shared_in']);
  int? get sharedInCount => _iN(sharedIn['count']);
  Map<String, int> get sharedInByStatus => _intMap(sharedIn['by_status']);
  double? get sharedInMeanRatio => _d(sharedIn['mean_ratio']);
  Map<String, dynamic> get dataQuality => _map(raw['data_quality']);
  int? get regionEvents => _iN(dataQuality['region_events']);
  int? get stores => _iN(dataQuality['stores']);
  dynamic get sampleFlag => dataQuality['sample_flag'];

  /// 표본 경고 문구 (없으면 null). sample_flag 가 참/문자열이거나 무작위 기대 적중 5건 미만이면 경고.
  String? get sampleWarning {
    final f = sampleFlag;
    final reasons = <String>[];
    if (f == true) {
      reasons.add('표본 부족 표시(sample_flag)');
    } else if (f is String && f.isNotEmpty && f != 'ok' && f != 'false') {
      reasons.add('표본 표시: $f');
    }
    final e = expectedUniform;
    if (e != null && e < 5) reasons.add('무작위 기대 적중 ${e.toStringAsFixed(2)}건 (5건 미만)');
    final r = rounds;
    if (r != null && r < 30) reasons.add('평가 $r회차 (30회 미만)');
    return reasons.isEmpty ? null : '표본 경고 — ${reasons.join(' · ')}. 적중 수·배수를 성능으로 단정하지 마세요.';
  }
}

/// 누적 성능 한 점 (목표 회차 오름차순)
class ReplayCumulativePoint {
  final int targetRound;

  /// 누적 평균 log-loss (모델 / m0). 값이 없는 회차는 직전 값 유지, 처음부터 없으면 null.
  final double? meanLlModel;
  final double? meanLlM0;
  final int llRounds;

  /// 지방장 납품 합계 누적 (사후 브리핑 agents 기준, 없으면 중앙 통합 추천 store_* 기준)
  final int cumHits;
  final int cumHistoryHits;
  final double cumExpectedUniform;
  final int hitRounds;

  const ReplayCumulativePoint({
    required this.targetRound,
    this.meanLlModel,
    this.meanLlM0,
    this.llRounds = 0,
    this.cumHits = 0,
    this.cumHistoryHits = 0,
    this.cumExpectedUniform = 0,
    this.hitRounds = 0,
  });
}

/// 누적 성능 요약
class ReplayCumulative {
  final List<ReplayCumulativePoint> points;

  /// 'agents' = 사후 브리핑 지방장 합계, 'central_store' = 중앙 통합 추천(store_*) 지표, 'none'
  final String hitsSource;
  final int rounds;
  final int focusHits;
  final int focusHitsM0;
  final double focusExpected;
  final int focusRounds;
  final int liveRounds;
  final int replayRounds;

  const ReplayCumulative({
    this.points = const [],
    this.hitsSource = 'none',
    this.rounds = 0,
    this.focusHits = 0,
    this.focusHitsM0 = 0,
    this.focusExpected = 0,
    this.focusRounds = 0,
    this.liveRounds = 0,
    this.replayRounds = 0,
  });

  ReplayCumulativePoint? get last => points.isEmpty ? null : points.last;

  /// log-loss 기술 점수 = 1 − 모델/m0 (양수면 m0 보다 나음, 자료 없으면 null)
  double? get llSkill {
    final l = last;
    if (l == null || l.meanLlModel == null || l.meanLlM0 == null || l.meanLlM0 == 0) return null;
    return 1 - l.meanLlModel! / l.meanLlM0!;
  }

  /// 중앙 평가 행 + 회차별 사후 브리핑 agents 합계로 누적 시계열 생성 (순수 함수, 단위 테스트 대상).
  /// [centralRows]: {target_round, evaluation_metrics}. [postAgents]: target_round → payload.agents.
  /// [modes]: target_round → replay_mode (실전/사후 재현 회차 수 집계용, 선택).
  static ReplayCumulative build(
    List<Map<String, dynamic>> centralRows, {
    Map<int, Map<String, dynamic>> postAgents = const {},
    Map<int, String> modes = const {},
  }) {
    final byRound = <int, Map<String, dynamic>>{};
    for (final r in centralRows) {
      final t = _iN(r['target_round']);
      if (t == null) continue;
      byRound[t] = _map(r['evaluation_metrics']);
    }
    final rounds = {...byRound.keys, ...postAgents.keys}.toList()..sort();
    final useAgents = postAgents.values.any((a) => _iN(a['hits_any']) != null);
    final useCentralStore = !useAgents && byRound.values.any((m) => _iN(m['store_hits_any']) != null);

    double sumM = 0, sumM0 = 0;
    var llN = 0;
    var hits = 0, hist = 0, hitN = 0;
    double unif = 0;
    var fh = 0, fh0 = 0, fN = 0;
    double fe = 0;
    final pts = <ReplayCumulativePoint>[];
    for (final t in rounds) {
      final m = byRound[t] ?? const <String, dynamic>{};
      final lm = _d(m['logloss_model']);
      final l0 = _d(m['logloss_m0']);
      if (lm != null && l0 != null) {
        sumM += lm;
        sumM0 += l0;
        llN++;
      }
      if (useAgents) {
        final a = postAgents[t];
        final h = a == null ? null : _iN(a['hits_any']);
        if (h != null) {
          hits += h;
          hist += _iN(a!['history_hits']) ?? 0;
          unif += _d(a['expected_uniform']) ?? 0;
          hitN++;
        }
      } else if (useCentralStore) {
        final h = _iN(m['store_hits_any']);
        if (h != null) {
          hits += h;
          hist += _iN(m['store_hits_history']) ?? 0;
          unif += _d(m['store_expected_uniform']) ?? 0;
          hitN++;
        }
      }
      final f = _iN(m['focus_hits']);
      if (f != null) {
        fh += f;
        fh0 += _iN(m['focus_hits_m0']) ?? 0;
        fe += _d(m['focus_expected']) ?? 0;
        fN++;
      }
      pts.add(ReplayCumulativePoint(
        targetRound: t,
        meanLlModel: llN == 0 ? null : sumM / llN,
        meanLlM0: llN == 0 ? null : sumM0 / llN,
        llRounds: llN,
        cumHits: hits,
        cumHistoryHits: hist,
        cumExpectedUniform: unif,
        hitRounds: hitN,
      ));
    }
    var live = 0, rep = 0;
    for (final t in rounds) {
      final md = modes[t];
      if (md == null) continue;
      if (isReplayLiveMode(md)) {
        live++;
      } else {
        rep++;
      }
    }
    return ReplayCumulative(
      points: pts,
      hitsSource: useAgents ? 'agents' : (useCentralStore ? 'central_store' : 'none'),
      rounds: rounds.length,
      focusHits: fh,
      focusHitsM0: fh0,
      focusExpected: fe,
      focusRounds: fN,
      liveRounds: live,
      replayRounds: rep,
    );
  }
}

/// 가설 목록에 판매점 단위 검증 통과 가설이 있는지 (순수 함수)
bool hasPassedStoreLevelHypothesis(Iterable<AgentHypothesis> l) =>
    l.any((h) => h.verdictPassed && kAgentStoreLevelKinds.contains(h.kind));

// ═══════════════════════════════════════════════════════════════════════
// 저장소 (읽기 전용)
// ═══════════════════════════════════════════════════════════════════════

class AgentReplayRepository {
  final SupabaseClient _db;
  final String runId;

  /// [runId] 미지정 시 현재 실행 ([currentRunId], 기본 'ag-1.1-r1')
  AgentReplayRepository({SupabaseClient? client, String? runId})
      : _db = client ?? Supabase.instance.client,
        runId = runId ?? _currentRunId;

  /// 이 실행의 모델 ('ag-1.1-r1' → 'ag-1.1')
  String get model => agentModelForRun(runId);

  /// 마지막으로 확인된 현재(기본) 실행 — [resolveCurrentRunId] 가 갱신
  static String _currentRunId = kAgentReplayRunId;
  static String get currentRunId => _currentRunId;

  /// research_replay_runs 전체 + 예측 행 존재 여부로 기본 실행을 정한다 ([pickDefaultReplayRun]). 5분 캐시.
  /// 실패해도 'ag-1.1-r1' 을 돌려준다.
  static Future<String> resolveCurrentRunId({SupabaseClient? client, bool force = false}) async {
    const key = 'currentRun';
    if (!force) {
      final c = _cached<String>(key);
      if (c != null) return c;
    }
    try {
      final repo = AgentReplayRepository(client: client, runId: kAgentReplayRunId);
      final runs = await repo.loadRuns(force: force);
      final withRows = <String>{};
      final ids = {...kAgentReplayRunPriority, ...runs.data.map((r) => r.runId)}.where((s) => s.isNotEmpty);
      for (final id in ids) {
        if (await repo.runHasRows(id)) withRows.add(id);
      }
      final defective = runs.data.where((r) => r.hasDefect).map((r) => r.runId).toSet();
      _currentRunId = pickDefaultReplayRun(withRows, defective: defective);
      AgentResearchRepository.preferredRunId = _currentRunId;
    } catch (_) {
      _currentRunId = kAgentReplayRunId;
    }
    _put(key, _currentRunId);
    return _currentRunId;
  }

  static const Duration _ttl = Duration(minutes: 5);
  static final Map<String, (DateTime, dynamic)> _cache = {};
  static final Map<String, String> _storeNames = {};

  static T? _cached<T>(String key) {
    final e = _cache[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.$1) > _ttl) {
      _cache.remove(key);
      return null;
    }
    final v = e.$2;
    return v is T ? v : null;
  }

  static void _put(String key, Object v) => _cache[key] = (DateTime.now(), v);

  static void clearCache() => _cache.clear();

  static ResearchLoad<T> _fail<T>(Object e, T empty) {
    final missing = RegionResearchRepository.isMissingTable(e);
    return ResearchLoad<T>(
      missing ? ResearchAvailability.notApplied : ResearchAvailability.error,
      empty,
      message: missing ? kReplayNotApplied : '$e',
    );
  }

  static ResearchLoad<T> _ok<T>(T data, bool empty) =>
      ResearchLoad<T>(empty ? ResearchAvailability.noData : ResearchAvailability.available, data,
          message: empty ? kReplayNoData : null);

  // ── 실행 · 회차 목록 ────────────────────────────────────────────────────

  /// research_replay_runs 전체 (replay_run_id 오름차순). 5분 캐시.
  Future<ResearchLoad<List<ReplayRun>>> loadRuns({bool force = false}) async {
    const key = 'runs';
    if (!force) {
      final c = _cached<ResearchLoad<List<ReplayRun>>>(key);
      if (c != null) return c;
    }
    try {
      final rows = List<Map<String, dynamic>>.from(
          await _db.from('research_replay_runs').select().order('replay_run_id', ascending: true).limit(50));
      final l = rows.map(ReplayRun.fromRow).where((r) => r.runId.isNotEmpty).toList();
      final res = _ok(l, l.isEmpty);
      _put(key, res);
      return res;
    } catch (e) {
      final res = _fail(e, const <ReplayRun>[]);
      if (res.state == ResearchAvailability.notApplied) _put(key, res);
      return res;
    }
  }

  /// [id] 실행에 동결 예측 행이 있는지 (오류 → false)
  Future<bool> runHasRows(String id) async {
    try {
      final rows = await _db
          .from('research_replay_predictions')
          .select('prediction_snapshot_id')
          .eq('replay_run_id', id)
          .limit(1);
      return List<Map<String, dynamic>>.from(rows).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<ResearchLoad<ReplayRun?>> loadRun() async {
    try {
      final rows = await _db.from('research_replay_runs').select().eq('replay_run_id', runId).limit(1);
      final l = List<Map<String, dynamic>>.from(rows);
      return _ok<ReplayRun?>(l.isEmpty ? null : ReplayRun.fromRow(l.first), l.isEmpty);
    } catch (e) {
      return _fail<ReplayRun?>(e, null);
    }
  }

  /// DB 사용량 (research_replay_runs.stats.usage 만 조회). data null = 측정 전. 5분 캐시.
  Future<ResearchLoad<DbUsage?>> loadDbUsage({bool force = false}) async {
    final key = 'dbUsage_$runId';
    if (!force) {
      final c = _cached<ResearchLoad<DbUsage?>>(key);
      if (c != null) return c;
    }
    try {
      final rows = List<Map<String, dynamic>>.from(await _db
          .from('research_replay_runs')
          .select('usage:stats->usage')
          .eq('replay_run_id', runId)
          .limit(1));
      final u = rows.isEmpty ? null : DbUsage.fromStats({'usage': rows.first['usage']});
      final res = _ok<DbUsage?>(u, u == null);
      _put(key, res);
      return res;
    } catch (e) {
      final res = _fail<DbUsage?>(e, null);
      if (res.state == ResearchAvailability.notApplied) _put(key, res);
      return res;
    }
  }

  /// 회차 목록 (target_round 오름차순, 가벼운 컬럼만). 5분 캐시.
  Future<ResearchLoad<List<ReplayPrediction>>> loadRounds({bool force = false}) async {
    final key = 'rounds_$runId';
    if (!force) {
      final c = _cached<ResearchLoad<List<ReplayPrediction>>>(key);
      if (c != null) return c;
    }
    try {
      final out = <ReplayPrediction>[];
      var off = 0;
      while (true) {
        final page = List<Map<String, dynamic>>.from(await _db
            .from('research_replay_predictions')
            .select('prediction_snapshot_id, target_round, available_data_through_round, replay_mode, '
                'prediction_created_at, active_hypotheses, explore_hypotheses_fired')
            .eq('replay_run_id', runId)
            .order('target_round', ascending: true)
            .range(off, off + 999));
        out.addAll(page.map(ReplayPrediction.fromRow));
        if (page.length < 1000) break;
        off += 1000;
      }
      final res = _ok(out, out.isEmpty);
      _put(key, res);
      return res;
    } catch (e) {
      final res = _fail(e, const <ReplayPrediction>[]);
      if (res.state == ResearchAvailability.notApplied) _put(key, res);
      return res;
    }
  }

  // ── 회차 상세 ──────────────────────────────────────────────────────────

  /// 예측(동결) + 실제 결과 + 중앙 검증 + 사전·사후 브리핑
  Future<ResearchLoad<ReplayRoundDetail?>> loadRoundDetail(int target) async {
    try {
      final pr = List<Map<String, dynamic>>.from(await _db
          .from('research_replay_predictions')
          .select('prediction_snapshot_id, target_round, available_data_through_round, replay_mode, '
              'prediction_created_at, focus_regions, store_top, active_hypotheses, live_hypotheses_applied, '
              'explore_hypotheses_fired, data_provenance')
          .eq('replay_run_id', runId)
          .eq('target_round', target)
          .limit(1));
      if (pr.isEmpty) return _ok<ReplayRoundDetail?>(null, true);
      final p = ReplayPrediction.fromRow(pr.first);
      final sid = p.snapshotId;
      final rs = List<Map<String, dynamic>>.from(
          await _db.from('research_replay_results').select().eq('prediction_snapshot_id', sid).limit(1));
      final ce = List<Map<String, dynamic>>.from(
          await _db.from('research_replay_central_evals').select().eq('prediction_snapshot_id', sid).limit(1));
      final br = List<Map<String, dynamic>>.from(
          await _db.from('research_replay_briefings').select().eq('prediction_snapshot_id', sid));
      ReplayBriefing? pre, post;
      for (final b in br.map(ReplayBriefing.fromRow)) {
        if (b.kind == 'pre') pre = b;
        if (b.kind == 'post') post = b;
      }
      return _ok<ReplayRoundDetail?>(
          ReplayRoundDetail(
            prediction: p,
            result: rs.isEmpty ? null : ReplayResult.fromRow(rs.first),
            centralEval: ce.isEmpty ? null : ReplayCentralEval.fromRow(ce.first),
            pre: pre,
            post: post,
          ),
          false);
    } catch (e) {
      return _fail<ReplayRoundDetail?>(e, null);
    }
  }

  /// 최신 사후 브리핑 (target_round 내림차순 1건). 5분 캐시.
  Future<ResearchLoad<ReplayBriefing?>> loadLatestPostBriefing({bool force = false}) async {
    final key = 'latestPost_$runId';
    if (!force) {
      final c = _cached<ResearchLoad<ReplayBriefing?>>(key);
      if (c != null) return c;
    }
    try {
      final rows = List<Map<String, dynamic>>.from(await _db
          .from('research_replay_briefings')
          .select()
          .eq('replay_run_id', runId)
          .eq('kind', 'post')
          .order('target_round', ascending: false)
          .limit(1));
      final res = _ok<ReplayBriefing?>(rows.isEmpty ? null : ReplayBriefing.fromRow(rows.first), rows.isEmpty);
      _put(key, res);
      return res;
    } catch (e) {
      final res = _fail<ReplayBriefing?>(e, null);
      if (res.state == ResearchAvailability.notApplied) _put(key, res);
      return res;
    }
  }

  // ── 지방장 이력 ────────────────────────────────────────────────────────

  /// 이 실행 모델의 지방장 목록 (research_agents.performance 포함). 없으면 빈 목록.
  Future<ResearchLoad<List<AgentInfo>>> loadAgents() => AgentResearchRepository(client: _db).loadAgents(model: model);

  /// 한 지방장의 회차별 동결 납품 + 검증 (최신순, [page] 0부터, [pageSize] 건씩)
  Future<ResearchLoad<List<ReplayAgentRound>>> loadAgentHistory(String agentId,
      {int page = 0, int pageSize = 20}) async {
    try {
      final from = page * pageSize;
      final preds = List<Map<String, dynamic>>.from(await _db
          .from('research_replay_agent_predictions')
          .select()
          .eq('replay_run_id', runId)
          .eq('agent_id', agentId)
          .order('target_round', ascending: false)
          .range(from, from + pageSize - 1));
      if (preds.isEmpty) return _ok(const <ReplayAgentRound>[], true);
      final ids = preds.map((r) => (r['prediction_snapshot_id'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
      final evals = ids.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(await _db
              .from('research_replay_agent_evals')
              .select()
              .eq('agent_id', agentId)
              .inFilter('prediction_snapshot_id', ids));
      final list = ReplayAgentRound.join(preds, evals);
      return _ok(list, list.isEmpty);
    } catch (e) {
      return _fail(e, const <ReplayAgentRound>[]);
    }
  }

  /// (지방장/지역, 목표 회차) 의 동결 추천 + 검증(있으면)
  Future<ResearchLoad<ReplayAgentRound?>> loadFrozen(String agentId, int target) async {
    try {
      final preds = List<Map<String, dynamic>>.from(await _db
          .from('research_replay_agent_predictions')
          .select()
          .eq('replay_run_id', runId)
          .eq('agent_id', agentId)
          .eq('target_round', target)
          .limit(1));
      if (preds.isEmpty) return _ok<ReplayAgentRound?>(null, true);
      final sid = (preds.first['prediction_snapshot_id'] ?? '').toString();
      final evals = List<Map<String, dynamic>>.from(await _db
          .from('research_replay_agent_evals')
          .select()
          .eq('prediction_snapshot_id', sid)
          .eq('agent_id', agentId)
          .limit(1));
      final l = ReplayAgentRound.join(preds, evals);
      return _ok<ReplayAgentRound?>(l.first, false);
    } catch (e) {
      return _fail<ReplayAgentRound?>(e, null);
    }
  }

  /// 목표 회차의 중앙 예측 (지역 순위 포함, 지역 추천 화면의 '당시 동결' 평가용)
  Future<ResearchLoad<ReplayPrediction?>> loadPredictionWithRegions(int target) async {
    final key = 'predRegions_${runId}_$target';
    final c = _cached<ResearchLoad<ReplayPrediction?>>(key);
    if (c != null) return c;
    try {
      final rows = List<Map<String, dynamic>>.from(await _db
          .from('research_replay_predictions')
          .select('prediction_snapshot_id, target_round, available_data_through_round, replay_mode, '
              'prediction_created_at, focus_regions, regions')
          .eq('replay_run_id', runId)
          .eq('target_round', target)
          .limit(1));
      final res = _ok<ReplayPrediction?>(rows.isEmpty ? null : ReplayPrediction.fromRow(rows.first), rows.isEmpty);
      _put(key, res);
      return res;
    } catch (e) {
      return _fail<ReplayPrediction?>(e, null);
    }
  }

  /// 목표 회차의 실제 결과 (research_replay_results). 없으면 null (= 추첨 결과 반영 전). 5분 캐시.
  Future<ResearchLoad<ReplayResult?>> loadResult(int target) async {
    final key = 'result_${runId}_$target';
    final c = _cached<ResearchLoad<ReplayResult?>>(key);
    if (c != null) return c;
    try {
      final rows = List<Map<String, dynamic>>.from(await _db
          .from('research_replay_results')
          .select()
          .eq('replay_run_id', runId)
          .eq('target_round', target)
          .limit(1));
      final res = _ok<ReplayResult?>(rows.isEmpty ? null : ReplayResult.fromRow(rows.first), rows.isEmpty);
      _put(key, res);
      return res;
    } catch (e) {
      return _fail<ReplayResult?>(e, null);
    }
  }

  /// 판매점 코드 → 이름 (lottery_stores 읽기 전용, 150개씩). 실패 시 빈 맵.
  Future<Map<String, String>> storeNames(Iterable<String> codes) async {
    final need = codes.where((c) => c.isNotEmpty && !_storeNames.containsKey(c)).toSet().toList()..sort();
    for (var i = 0; i < need.length; i += 150) {
      final ch = need.sublist(i, math.min(need.length, i + 150));
      try {
        final rows = await _db
            .from('lottery_stores')
            .select('dhlottery_code, store_name')
            .eq('lottery_type', 'lotto')
            .inFilter('dhlottery_code', ch);
        for (final r in List<Map<String, dynamic>>.from(rows)) {
          final c = (r['dhlottery_code'] ?? '').toString();
          final n = _s(r['store_name']);
          if (c.isNotEmpty && n != null) _storeNames[c] = n;
        }
      } catch (_) {
        break;
      }
    }
    return {for (final c in codes) if (_storeNames[c] != null) c: _storeNames[c]!};
  }

  // ── 가설 ───────────────────────────────────────────────────────────────

  /// research_replay_hypotheses 목록 (필터: status, kind, 공유만, 실전 반영만). 최대 [limit].
  Future<ResearchLoad<List<AgentHypothesis>>> loadHypotheses({
    String? status,
    String? kind,
    bool sharedOnly = false,
    bool appliedLiveOnly = false,
    int limit = 300,
  }) async {
    try {
      var q = _db.from('research_replay_hypotheses').select().eq('replay_run_id', runId);
      if (status != null) q = q.eq('status', status);
      if (kind != null) q = q.eq('kind', kind);
      if (sharedOnly) q = q.not('shared_from', 'is', null);
      if (appliedLiveOnly) q = q.gt('applied_live_count', 0);
      final rows = await q.order('updated_at', ascending: false).range(0, limit - 1);
      final list = AgentResearchRepository.sortHypotheses(
          List<Map<String, dynamic>>.from(rows).map(AgentHypothesis.fromMap).toList());
      return _ok(list, list.isEmpty);
    } catch (e) {
      return _fail(e, const <AgentHypothesis>[]);
    }
  }

  /// 판매점 단위 유형 중 검증 통과(passed/combined) 가설 수 (최대 50까지 셈). 5분 캐시.
  Future<ResearchLoad<int>> countPassedStoreLevel() async {
    final key = 'passedStore_$runId';
    final c = _cached<ResearchLoad<int>>(key);
    if (c != null) return c;
    try {
      final rows = await _db
          .from('research_replay_hypotheses')
          .select('hypothesis_id')
          .eq('replay_run_id', runId)
          .inFilter('status', const ['passed', 'combined'])
          .inFilter('kind', kAgentStoreLevelKinds.toList())
          .limit(50);
      final n = List<Map<String, dynamic>>.from(rows).length;
      final res = ResearchLoad<int>(ResearchAvailability.available, n);
      _put(key, res);
      return res;
    } catch (e) {
      return _fail(e, 0);
    }
  }

  /// 가설 상태 변화 이력 (round 오름차순)
  Future<ResearchLoad<List<ReplayHypothesisEvent>>> loadHypothesisEvents(String hypothesisId) async {
    try {
      final rows = await _db
          .from('research_replay_hypothesis_events')
          .select()
          .eq('replay_run_id', runId)
          .eq('hypothesis_id', hypothesisId)
          .order('round', ascending: true)
          .range(0, 999);
      final list = List<Map<String, dynamic>>.from(rows).map(ReplayHypothesisEvent.fromRow).toList();
      return _ok(list, list.isEmpty);
    } catch (e) {
      return _fail(e, const <ReplayHypothesisEvent>[]);
    }
  }

  // ── 누적 성능 ──────────────────────────────────────────────────────────

  /// 전 회차 중앙 검증 지표 + 사후 브리핑 지방장 합계 → 누적 시계열. 5분 캐시.
  Future<ResearchLoad<ReplayCumulative>> loadCumulative({bool force = false}) async {
    final key = 'cumulative_$runId';
    if (!force) {
      final c = _cached<ResearchLoad<ReplayCumulative>>(key);
      if (c != null) return c;
    }
    try {
      final central = <Map<String, dynamic>>[];
      var off = 0;
      while (true) {
        final page = List<Map<String, dynamic>>.from(await _db
            .from('research_replay_central_evals')
            .select('target_round, evaluation_metrics')
            .eq('replay_run_id', runId)
            .order('target_round', ascending: true)
            .range(off, off + 999));
        central.addAll(page);
        if (page.length < 1000) break;
        off += 1000;
      }
      // 사후 브리핑의 agents 합계만 (payload 전체를 받지 않는다). 실패해도 중앙 지표로 계속.
      final post = <int, Map<String, dynamic>>{};
      try {
        var o2 = 0;
        while (true) {
          final page = List<Map<String, dynamic>>.from(await _db
              .from('research_replay_briefings')
              .select('target_round, agents:payload->agents')
              .eq('replay_run_id', runId)
              .eq('kind', 'post')
              .order('target_round', ascending: true)
              .range(o2, o2 + 999));
          for (final r in page) {
            final t = _iN(r['target_round']);
            if (t != null && r['agents'] is Map) post[t] = _map(r['agents']);
          }
          if (page.length < 1000) break;
          o2 += 1000;
        }
      } catch (_) {}
      final modes = <int, String>{};
      final rounds = await loadRounds(force: force);
      for (final p in rounds.data) {
        modes[p.targetRound] = p.replayMode;
      }
      final cum = ReplayCumulative.build(central, postAgents: post, modes: modes);
      final res = _ok(cum, cum.points.isEmpty);
      _put(key, res);
      return res;
    } catch (e) {
      final res = _fail(e, const ReplayCumulative());
      if (res.state == ResearchAvailability.notApplied) _put(key, res);
      return res;
    }
  }
}

/// 상태 → 문구 (재현 전용)
String replayStateLabel(ResearchAvailability s, {String? message}) => switch (s) {
      ResearchAvailability.notApplied => kReplayNotApplied,
      ResearchAvailability.noData => '$kReplayNoData ($kResearchNoData)',
      ResearchAvailability.available => '기록 있음',
      ResearchAvailability.error => '조회 오류${message == null ? '' : ': $message'}',
    };
