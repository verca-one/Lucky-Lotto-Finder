// 전국 지방장 에이전트 — 조회 전용 저장소 (관리자 연구 기능)
//
// ── 모델 계보 ─────────────────────────────────────────────────────────────
//   * 최신 실전(live) 선택 우선순위 = ag-1.1('ag-1.1-r1' 실전형 순차 재현 계보) → ag-1.0.
//     live 중앙 결과 행(research_agent_central)이 있는 첫 모델을 쓴다.
//   * 재현 실행은 research_replay_runs 에서 일반적으로 나열한다(이후 실행 추가 대비). 실행 행의
//     data_provenance.defect 가 있을 때만 결함 배지를, integrity_check 가 있으면 무결성 검증 줄을 표시한다.
//   * 가설은 현재 재현 실행(기본 'ag-1.1-r1')의 research_replay_hypotheses 를, 없으면
//     research_agent_hypotheses(ag-1.0)를 읽는다. 관계 그래프는 ag-1.0 만 있다.
//
// ── 데이터 원칙 ───────────────────────────────────────────────────────────
//   * research_v5_agents.sql 의 research_agent* 테이블을 SELECT 만 한다 (anon = 읽기 전용).
//     생산자는 서버 Worker(research_agent_worker.py)이며 앱은 기록하지 않는다.
//   * 테이블 없음(PGRST205/42P01/404) = '연구 미실행(SQL 미적용)', 행 없음 = '데이터 없음'.
//     데이터가 없을 때 점수·확률을 만들어내지 않는다.
//   * score / p_first 는 "연구 기반 후보 점수 (회차당 1·2등 기대 빈도, 판매량 미보정)"이며
//     복권 한 장당 당첨확률이 아니다.
//   * '검증 통과' 는 evidence.verdict(없으면 status passed / combined) 기준으로만 쓴다.
//
// 지방장(agent_id) = 시·군·구 region_id ('서울|노원구', '경기|수원시') + 'internet'.

import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin_gate.dart';
import '../route/region_research_repository.dart'
    show ResearchAvailability, ResearchLoad, RegionResearchRepository, kResearchNotApplied, kResearchNoData;

/// 이전 모델 (backtest + 1246회 실전 스냅샷)
const String kAgentModelLegacy = 'ag-1.0';

/// 실전형 순차 재현 계보 모델 (최신 live 납품 생산, 현행)
const String kAgentModelReplay = 'ag-1.1';

/// 실전형 순차 재현 실행 id (research_replay_* 테이블, 현행 기본)
const String kAgentReplayRunId = 'ag-1.1-r1';

/// 최신 실전 납품 선택 우선순위 (live 중앙 결과 행이 있는 첫 모델)
const List<String> kAgentLiveModelPriority = [kAgentModelReplay, kAgentModelLegacy];

/// 재현 실행 기본 선택 우선순위 (행이 있는 첫 실행). 목록에 없는 실행도 선택기에서 고를 수 있다.
const List<String> kAgentReplayRunPriority = [kAgentReplayRunId];

String agentModelLabel(String? m) => switch (m) {
      kAgentModelReplay => 'ag-1.1 (실전형 재현 계보)',
      kAgentModelLegacy => 'ag-1.0 (이전 모델 스냅샷)',
      null => '-',
      _ => m,
    };

/// 재현 실행 id → 모델 ('ag-1.1-r1' → 'ag-1.1'). 형식이 다르면 그대로.
String agentModelForRun(String runId) => RegExp(r'^(.+)-r\d+$').firstMatch(runId)?.group(1) ?? runId;

/// 모델 → 재현 실행 id ('ag-1.1' → 'ag-1.1-r1'). ag-1.0(재현 실행 없음)·null → null.
String? agentRunIdForModel(String? model) =>
    model == null || model == kAgentModelLegacy || model.isEmpty ? null : '$model-r1';

/// 재현 화면 기본 실행 (순수 함수, 단위 테스트 대상):
///   우선순위 목록 중 행이 있는 첫 실행 → 없으면 행이 있는 실행 중 결함 표시가 없는 것(이름순 마지막)
///   → 그래도 없으면 'ag-1.1-r1'.
String pickDefaultReplayRun(Set<String> runsWithRows, {Set<String> defective = const {}}) {
  for (final r in kAgentReplayRunPriority) {
    if (runsWithRows.contains(r) && !defective.contains(r)) return r;
  }
  final ok = runsWithRows.where((r) => !defective.contains(r)).toList()..sort();
  if (ok.isNotEmpty) return ok.last;
  for (final r in kAgentReplayRunPriority) {
    if (runsWithRows.contains(r)) return r;
  }
  return kAgentReplayRunId;
}

/// 최신 실전 납품 기준 (모델 + 목표 회차)
class AgentLiveRef {
  final String model;
  final int target;
  final String mode;

  /// ag-1.1 live 행이 없어 ag-1.0 으로 대체됐는지
  final bool fallback;
  const AgentLiveRef({required this.model, required this.target, this.mode = 'live', this.fallback = false});

  /// 이 모델의 재현 실행 id (ag-1.0 이면 null)
  String? get runId => agentRunIdForModel(model);

  /// 최우선 모델이 아닐 때 안내 문구 (최우선이면 null)
  String? get fallbackNote => fallback ? 'ag-1.1 실전 납품 없음 → ag-1.0 스냅샷 기준' : null;

  /// research_agent_central 행(model_version, target_round, mode) 목록에서 기준 선택 (순수 함수).
  /// [model] 미지정: 우선순위(ag-1.1) live 최대 목표 회차 → 없으면 ag-1.0 의 live(없으면 아무 mode) 최대 목표 회차.
  /// [model] 지정: 그 모델의 live → 없으면 아무 mode 최대 목표 회차.
  static AgentLiveRef? pick(List<Map<String, dynamic>> rows, {String? model}) {
    (int, String)? best(String m, {required bool liveOnly}) {
      (int, String)? out;
      for (final r in rows) {
        if ((r['model_version'] ?? '').toString() != m) continue;
        final t = _iN(r['target_round']);
        if (t == null) continue;
        final mode = (r['mode'] ?? '').toString();
        if (liveOnly && mode != 'live') continue;
        if (out == null || t > out.$1 || (t == out.$1 && mode == 'live')) out = (t, mode);
      }
      return out;
    }

    if (model != null) {
      final b = best(model, liveOnly: true) ?? best(model, liveOnly: false);
      return b == null ? null : AgentLiveRef(model: model, target: b.$1, mode: b.$2);
    }
    for (final m in kAgentLiveModelPriority) {
      if (m == kAgentModelLegacy) continue;
      final r = best(m, liveOnly: true);
      if (r != null) return AgentLiveRef(model: m, target: r.$1, mode: r.$2);
    }
    final l = best(kAgentModelLegacy, liveOnly: true) ?? best(kAgentModelLegacy, liveOnly: false);
    return l == null ? null : AgentLiveRef(model: kAgentModelLegacy, target: l.$1, mode: l.$2, fallback: true);
  }
}

const String kAgentNotApplied = '지방장 연구 미실행(SQL 미적용)';
const String kAgentNoData = '데이터 없음 (지방장 연구 미실행)';
const String kAgentScoreLabel = '연구 기반 후보 점수 (회차당 1·2등 기대 빈도, 판매량 미보정)';
const String kAgentPFirstLabel = '회차당 1등 기대 빈도 (판매량 미보정, 한 장당 확률 아님)';
const String kAgentBacktestCaution =
    'backtest(사후 순차 재현) 적중은 실전(live, 추첨 전 저장 납품) 성능과 다릅니다. '
    '실전 평가 회차가 쌓이기 전까지 backtest 수치를 미래 성능으로 해석하지 마세요.';
const String kAgentDataSources =
    'research_agents · research_agent_hypotheses · research_agent_relations · research_agent_deliveries · '
    'research_agent_score_sets(압축, 1247회~) · research_agent_store_scores · research_agent_round_evals · research_agent_central · research_agent_briefings';

const Map<String, String> kAgentHypStatusLabel = {
  'discovered': '발견',
  'researching': '연구 중',
  'passed': '검증 통과',
  'weakened': '약화',
  'rejected': '기각',
  'combined': '결합(검증)',
};

// ── 판정(verdict) — Worker 가 evidence.verdict 로 기록. 없으면 status 로 대체 ──────────
const String kVerdictPassed = '검증 통과';
const String kVerdictFailed = '검증 실패';
const String kVerdictAccumulating = '검증 중: 미래 관측 누적 중';
const String kVerdictLowSample = '검증 중: 표본 부족';

/// status 만 있고 세부 판정이 없는 '검증 중' (ag-1.1 이전 행)
const String kVerdictPending = '검증 중';

const List<String> kVerdictOrder = [
  kVerdictPassed, kVerdictFailed, kVerdictAccumulating, kVerdictLowSample, kVerdictPending,
];

const Map<String, String> kVerdictShort = {
  kVerdictPassed: '통과',
  kVerdictFailed: '실패',
  kVerdictAccumulating: '관측 누적 중',
  kVerdictLowSample: '표본 부족',
  kVerdictPending: '검증 중(세부 판정 없음)',
};

/// status → 판정 (evidence.verdict 가 없을 때). passed/combined → 통과, weakened/rejected → 실패, 그 외 → 검증 중.
String agentVerdictFromStatus(String? status) => switch (status) {
      'passed' || 'combined' => kVerdictPassed,
      'weakened' || 'rejected' => kVerdictFailed,
      _ => kVerdictPending,
    };

/// evidence.verdict 우선, 없으면 status 대체 (순수 함수)
String agentVerdictOf(Map<String, dynamic> evidence, String? status) {
  final v = evidence['verdict'];
  if (v is String && v.trim().isNotEmpty) return v.trim();
  return agentVerdictFromStatus(status);
}

/// '이 표본으로는 ×N배 이상 차이여야 판정 가능' (값 없으면 null)
String? agentMinDetectableLine(double? ratio) => ratio == null || !ratio.isFinite
    ? null
    : '이 표본으로는 ×${ratio.toStringAsFixed(ratio >= 10 ? 0 : 1)}배 이상 차이여야 판정 가능';

/// 판매점 단위 가설 유형 (판매점 단위 검증 통과 여부 판단용)
const Set<String> kAgentStoreLevelKinds = {
  'store_lead', 'store_cowin', 'region_store_lead', 'store_cycle', 'store_spill',
  'composite', 'cycle_pooled', 'neighbor_spill',
};

const List<String> kAgentHypStatusOrder = [
  'passed', 'combined', 'researching', 'discovered', 'weakened', 'rejected',
];

const Map<String, String> kAgentHypKindLabel = {
  'store_lead': '판매점 선행·후행',
  'store_cowin': '판매점 동시 당첨',
  'region_store_lead': '지역→판매점 선행',
  'region_lead': '지역 선행·후행',
  'region_cowin': '지역 동시 당첨',
  'self_repeat': '같은 지역 반복',
  'store_cycle': '판매점 반복 간격',
  'cycle_pooled': '반복 간격(풀링)',
  'neighbor_spill': '인접 지역 확산',
  'region_trend_up': '지역 상승 추세',
  'region_trend_down': '지역 하락 추세',
  'region_dormant': '지역 휴면 반등',
  'composite': '복합 가설',
  'multi_condition': '다중 조건',
  'store_spill': '판매점 확산',
};

const Map<String, String> kAgentStatusLabel = {
  'idle': '대기',
  'running': '연구 중',
  'completed': '완료',
  'failed': '실패',
};

String agentLabel(String? id) {
  if (id == null || id.isEmpty) return '-';
  if (id == 'internet') return '인터넷 판매';
  return id.replaceAll('|', ' ');
}

// ═══════════════════════════════════════════════════════════════════════
// 파싱 유틸
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

int _i(dynamic v) => _iN(v) ?? 0;

String? _s(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

bool _b(dynamic v) => v == true || v == 'true';

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : <Map<String, dynamic>>[];

List<String> _strs(dynamic v) =>
    v is List ? v.where((e) => e != null).map((e) => e.toString()).toList() : <String>[];

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

class AgentInfo {
  final String agentId;
  final String level;
  final String sido;
  final String unitName;
  final List<Map<String, dynamic>> subUnits;
  final int storeCount;
  final int activeStoreCount;
  final int geoStoreCount;
  final int duplicateGroups;
  final String status;
  final int? lastProcessedRound;
  final int? lastTargetRound;
  final Map<String, int> hypothesisCounts;
  final int deliveryCount;
  final Map<String, dynamic> performance;
  final String? error;
  final String? lastRunAt;
  final String? modelVersion;

  const AgentInfo({
    required this.agentId,
    this.level = 'sigungu',
    this.sido = '',
    this.unitName = '',
    this.subUnits = const [],
    this.storeCount = 0,
    this.activeStoreCount = 0,
    this.geoStoreCount = 0,
    this.duplicateGroups = 0,
    this.status = 'idle',
    this.lastProcessedRound,
    this.lastTargetRound,
    this.hypothesisCounts = const {},
    this.deliveryCount = 0,
    this.performance = const {},
    this.error,
    this.lastRunAt,
    this.modelVersion,
  });

  factory AgentInfo.fromRow(Map<String, dynamic> r) => AgentInfo(
        agentId: (r['agent_id'] ?? '').toString(),
        level: (r['level'] ?? 'sigungu').toString(),
        sido: (r['sido'] ?? '').toString(),
        unitName: (r['unit_name'] ?? '').toString(),
        subUnits: r['sub_units'] is List
            ? (r['sub_units'] as List)
                .map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{'name': '$e'})
                .toList()
            : const [],
        storeCount: _i(r['store_count']),
        activeStoreCount: _i(r['active_store_count']),
        geoStoreCount: _i(r['geo_store_count']),
        duplicateGroups: _i(r['duplicate_groups']),
        status: (r['status'] ?? 'idle').toString(),
        lastProcessedRound: _iN(r['last_processed_round']),
        lastTargetRound: _iN(r['last_target_round']),
        hypothesisCounts: _intMap(r['hypothesis_counts']),
        deliveryCount: _i(r['delivery_count']),
        performance: _map(r['performance']),
        error: _s(r['error']),
        lastRunAt: _s(r['last_run_at']),
        modelVersion: _s(r['model_version']),
      );

  String get display => agentLabel(agentId);
  int get hypothesisTotal => hypothesisCounts.values.fold(0, (a, b) => a + b);
  int get verifiedHypotheses => (hypothesisCounts['passed'] ?? 0) + (hypothesisCounts['combined'] ?? 0);

  bool matches(String query) {
    final toks = query.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (toks.isEmpty) return true;
    final hay = [agentId, sido, unitName, ...subUnits.map((m) => '${m['name'] ?? ''}')].join(' ');
    return toks.every(hay.contains);
  }
}

class AgentHypothesis {
  final String hypothesisId;
  final String agentId;
  final String kind;
  final String? scope;
  final String? canonicalKey;
  final String direction;
  final bool predictive;
  final String? sourceRegion;
  final String? targetRegion;
  final String? sourceStore;
  final String? targetStore;
  final List<String> relatedRegions;
  final List<String> relatedStores;
  final int? lag;
  final Map<String, dynamic> params;
  final String? sharedFrom;
  final String? sharedByAgent;
  final int sharedToCount;
  final int? discoveredRound;
  final bool discoverySignificant;
  final int? trainN, trainK;
  final double? trainExpected, trainP, trainQ;
  final int? testN, testK;
  final double? testExpected, testP, testQ;
  final String status;
  final bool liveEligible;
  final String? recState;
  final Map<String, dynamic> evidence;
  final int? evaluatedRound;

  /// 브리핑 payload 가 제공한 요약 문장 (없으면 필드로 생성)
  final String? summaryText;

  // ── 실전형 재현(research_replay_hypotheses) 전용 필드 (ag-1.0 행에서는 null/0) ──
  /// replay_run_id (재현 가설이면 'ag-1.1-r1', ag-1.0 가설이면 null)
  final String? replayRunId;
  final String? modelVersion;
  final int? firstAppliedLiveRound;
  final int? firstAppliedExploreRound;
  final int appliedLiveCount;
  final int appliedExploreCount;
  final int? kOff;
  final double? eOff;
  final double? relativeRatio;
  final String? updatedAt;

  const AgentHypothesis({
    required this.hypothesisId,
    required this.agentId,
    required this.kind,
    this.scope,
    this.canonicalKey,
    this.direction = 'up',
    this.predictive = true,
    this.sourceRegion,
    this.targetRegion,
    this.sourceStore,
    this.targetStore,
    this.relatedRegions = const [],
    this.relatedStores = const [],
    this.lag,
    this.params = const {},
    this.sharedFrom,
    this.sharedByAgent,
    this.sharedToCount = 0,
    this.discoveredRound,
    this.discoverySignificant = false,
    this.trainN,
    this.trainK,
    this.trainExpected,
    this.trainP,
    this.trainQ,
    this.testN,
    this.testK,
    this.testExpected,
    this.testP,
    this.testQ,
    this.status = 'discovered',
    this.liveEligible = false,
    this.recState,
    this.evidence = const {},
    this.evaluatedRound,
    this.summaryText,
    this.replayRunId,
    this.modelVersion,
    this.firstAppliedLiveRound,
    this.firstAppliedExploreRound,
    this.appliedLiveCount = 0,
    this.appliedExploreCount = 0,
    this.kOff,
    this.eOff,
    this.relativeRatio,
    this.updatedAt,
  });

  /// research_agent_hypotheses 행, research_replay_hypotheses 행 또는 브리핑 HYP 객체 (모든 필드 선택적).
  /// 재현 가설의 first_discovered_round 는 [discoveredRound] 로 매핑한다.
  factory AgentHypothesis.fromMap(Map<String, dynamic> r) {
    final ev = _map(r['evidence']);
    // 배치 조회에서 evidence 대신 verdict 만 별칭으로 받은 경우 (verdict:evidence->>verdict)
    if (!ev.containsKey('verdict') && r['verdict'] is String) ev['verdict'] = r['verdict'];
    final control = _map(ev['control']);
    return AgentHypothesis(
        hypothesisId: (r['hypothesis_id'] ?? '').toString(),
        agentId: (r['agent_id'] ?? '').toString(),
        kind: (r['kind'] ?? '').toString(),
        scope: _s(r['scope']),
        canonicalKey: _s(r['canonical_key']),
        direction: (r['direction'] ?? 'up').toString(),
        predictive: r['predictive'] == null ? true : _b(r['predictive']),
        sourceRegion: _s(r['source_region']),
        targetRegion: _s(r['target_region']),
        sourceStore: _s(r['source_store']),
        targetStore: _s(r['target_store']),
        relatedRegions: _strs(r['related_regions']),
        relatedStores: _strs(r['related_stores']),
        lag: _iN(r['lag']),
        params: _map(r['params']),
        sharedFrom: _s(r['shared_from']),
        sharedByAgent: _s(r['shared_by_agent']),
        sharedToCount: _i(r['shared_to_count']),
        discoveredRound: _iN(r['discovered_round']) ?? _iN(r['first_discovered_round']),
        discoverySignificant: _b(r['discovery_significant']),
        trainN: _iN(r['train_n']),
        trainK: _iN(r['train_k']),
        trainExpected: _d(r['train_expected']),
        trainP: _d(r['train_p']),
        trainQ: _d(r['train_q']),
        testN: _iN(r['test_n']),
        testK: _iN(r['test_k']),
        testExpected: _d(r['test_expected']),
        testP: _d(r['test_p']),
        testQ: _d(r['test_q']),
        status: (r['status'] ?? 'discovered').toString(),
        liveEligible: _b(r['live_eligible']),
        recState: _s(r['rec_state']),
        evidence: ev,
        evaluatedRound: _iN(r['evaluated_round']),
        summaryText: _s(r['summary']),
        replayRunId: _s(r['replay_run_id']),
        modelVersion: _s(r['model_version']),
        firstAppliedLiveRound: _iN(r['first_applied_live_round']),
        firstAppliedExploreRound: _iN(r['first_applied_explore_round']),
        appliedLiveCount: _i(r['applied_live_count']),
        appliedExploreCount: _i(r['applied_explore_count']),
        kOff: _iN(r['k_off']) ?? _iN(control['k_off']),
        eOff: _d(r['e_off']) ?? _d(control['e_off']),
        relativeRatio: _d(r['relative_ratio']) ?? _d(ev['relative_ratio']),
        updatedAt: _s(r['updated_at']),
      );
  }

  /// 실전형 재현 가설(research_replay_hypotheses)인지
  bool get isReplay => replayRunId != null;

  /// 판정: evidence.verdict → 없으면 status 대체
  String get verdict => agentVerdictOf(evidence, status);

  /// 판정이 Worker 의 evidence.verdict 에서 왔는지 (false = status 로 대체)
  bool get verdictFromEvidence {
    final v = evidence['verdict'];
    return v is String && v.trim().isNotEmpty;
  }

  String? get verdictDetail => _s(evidence['verdict_detail']);
  Map<String, dynamic> get power => _map(evidence['power']);

  /// 무작위 기대 사건 수 (검증 구간)
  double? get powerExpected => _d(power['expected']);

  /// p<0.05 판정에 필요한 최소 사건 수
  int? get powerMinK => _iN(power['min_k_p05']);

  /// 이 표본으로 판정 가능한 최소 배수 (실제/기대)
  double? get minDetectableRatio => _d(power['min_detectable_ratio']);

  String? get minDetectableLine => agentMinDetectableLine(minDetectableRatio);

  bool get verdictPassed => verdict == kVerdictPassed;

  /// 실전 추천에 한 번이라도 반영됐는지 (재현 가설 기준)
  bool get appliedLive => appliedLiveCount > 0 || firstAppliedLiveRound != null;

  /// 판매점 단위 가설 유형인지
  bool get isStoreLevel => kAgentStoreLevelKinds.contains(kind);

  /// 실전 반영 이력 한 줄 (재현 가설만, 없으면 null)
  String? get appliedLine {
    if (!isReplay) return null;
    final live = firstAppliedLiveRound == null ? '실전 반영 없음' : '첫 실전 반영 $firstAppliedLiveRound회 · 실전 $appliedLiveCount회';
    final exp = firstAppliedExploreRound == null
        ? '탐색 반영 없음'
        : '첫 탐색 반영 $firstAppliedExploreRound회 · 탐색 $appliedExploreCount회';
    return '$live · $exp';
  }

  /// '검증 통과' 는 passed / combined 만
  bool get verified => status == 'passed' || status == 'combined';
  bool get isShared => sharedFrom != null && sharedFrom!.isNotEmpty;
  String get statusLabel => kAgentHypStatusLabel[status] ?? status;
  String get kindLabel => kAgentHypKindLabel[kind] ?? kind;

  bool get isCowin => kind == 'store_cowin' || kind == 'region_cowin';
  bool get isLeadLag => kind == 'store_lead' || kind == 'region_lead' || kind == 'region_store_lead';
  bool get isCycle => kind == 'store_cycle' || kind == 'cycle_pooled' || kind == 'self_repeat';

  String get summary {
    if (summaryText != null) return summaryText!;
    final src = sourceStore ?? (sourceRegion == null ? null : agentLabel(sourceRegion));
    final dst = targetStore ?? (targetRegion == null ? null : agentLabel(targetRegion));
    final path = [?src, ?dst].join(isCowin ? ' ⇄ ' : ' → ');
    final lagText = lag == null || lag == 0 ? '' : ' (+$lag회)';
    final dir = direction == 'down' ? ' · 감소 방향' : '';
    return '$kindLabel${path.isEmpty ? '' : ' $path'}$lagText$dir';
  }

  String get testLine {
    if ((testN ?? 0) == 0 && testK == null) return '순방향 검증 회차 없음';
    final exp = testExpected == null ? '' : ' (기대 ${testExpected!.toStringAsFixed(2)})';
    final p = testP == null ? '' : ' p=${fmtP(testP)}';
    final n = testN == null ? '' : '/$testN회';
    return '검증 ${testK ?? '-'}건$n$exp$p';
  }

  String get trainLine {
    if (trainN == null && trainK == null) return '발견 구간 통계 없음';
    final exp = trainExpected == null ? '' : ' (기대 ${trainExpected!.toStringAsFixed(2)})';
    final p = trainP == null ? '' : ' p=${fmtP(trainP)}';
    final q = trainQ == null ? '' : ' q=${fmtP(trainQ)}';
    return '발견 ${trainK ?? '-'}건/${trainN ?? '-'}회$exp$p$q';
  }
}

String fmtP(double? v) => v == null ? '-' : (v < 0.0001 ? '<0.0001' : v.toStringAsFixed(4));

class AgentDelivery {
  final int targetRound;
  final String agentId;
  final String storeCode;
  final String mode;
  final int rank;
  final double? score;
  final double? pFirst;
  final String? storeName;
  final String? address;
  final double? lat, lng;
  final Map<String, dynamic> history;
  final Map<String, dynamic> components;
  final List<Map<String, dynamic>> hypotheses;
  final String verification;
  final Map<String, dynamic> dataQuality;
  final int? trainingEndRound;

  const AgentDelivery({
    required this.targetRound,
    required this.agentId,
    required this.storeCode,
    this.mode = 'live',
    required this.rank,
    this.score,
    this.pFirst,
    this.storeName,
    this.address,
    this.lat,
    this.lng,
    this.history = const {},
    this.components = const {},
    this.hypotheses = const [],
    this.verification = '',
    this.dataQuality = const {},
    this.trainingEndRound,
  });

  factory AgentDelivery.fromRow(Map<String, dynamic> r) => AgentDelivery(
        targetRound: _i(r['target_round']),
        agentId: (r['agent_id'] ?? '').toString(),
        storeCode: (r['store_code'] ?? '').toString(),
        mode: (r['mode'] ?? 'live').toString(),
        rank: _i(r['rank']),
        score: _d(r['score']),
        pFirst: _d(r['p_first']),
        storeName: _s(r['store_name']),
        address: _s(r['address']),
        lat: _d(r['lat']),
        lng: _d(r['lng']),
        history: _map(r['history']),
        components: _map(r['components']),
        hypotheses: _maps(r['hypotheses']),
        verification: (r['verification'] ?? '').toString(),
        dataQuality: _map(r['data_quality']),
        trainingEndRound: _iN(r['training_end_round']),
      );

  String get name => storeName ?? storeCode;
  /// 실전 점수에 반영된 가설 (applied_live, 구형 키 applied 도 허용)
  int get appliedHypothesisCount =>
      hypotheses.where((h) => h['applied_live'] == true || h['applied'] == true).length;

  /// 이번 회차 발화(조건 충족) 가설 — 검증 통과가 아니면 실전 미반영
  int get firingHypothesisCount => hypotheses.where((h) => h['firing'] == true).length;
}

class AgentStoreScore {
  final int targetRound;
  final String storeCode;
  final String agentId;
  final int agentRank;
  final int agentSize;
  final double score;
  final double? pFirst;
  final double liveFactor;
  final double exploreFactor;
  final int hypCount;
  final int? trainingEndRound;
  final String? modelVersion;

  /// research_agent_score_sets(압축 저장)에서 펼친 값인지 (false = research_agent_store_scores 행)
  final bool fromScoreSet;

  const AgentStoreScore({
    this.fromScoreSet = false,
    required this.targetRound,
    required this.storeCode,
    required this.agentId,
    required this.agentRank,
    required this.agentSize,
    required this.score,
    this.pFirst,
    this.liveFactor = 1,
    this.exploreFactor = 1,
    this.hypCount = 0,
    this.trainingEndRound,
    this.modelVersion,
  });

  factory AgentStoreScore.fromRow(Map<String, dynamic> r) => AgentStoreScore(
        targetRound: _i(r['target_round']),
        storeCode: (r['store_code'] ?? '').toString(),
        agentId: (r['agent_id'] ?? '').toString(),
        agentRank: _i(r['agent_rank']),
        agentSize: _i(r['agent_size']),
        score: _d(r['score']) ?? 0,
        pFirst: _d(r['p_first']),
        liveFactor: _d(r['live_factor']) ?? 1,
        exploreFactor: _d(r['explore_factor']) ?? 1,
        hypCount: _i(r['hyp_count']),
        trainingEndRound: _iN(r['training_end_round']),
        modelVersion: _s(r['model_version']),
      );

  /// 지방장 내 순위 정규화: 1 - (rank-1)/max(size-1,1), 0~1
  double get normalized {
    if (agentRank <= 0) return 0;
    final v = 1 - (agentRank - 1) / math.max(agentSize - 1, 1);
    return v.clamp(0.0, 1.0).toDouble();
  }

  /// 검증 통과 가설이 실전 반영됐는지 (live_factor != 1)
  bool get liveApplied => (liveFactor - 1).abs() > 1e-9;
}

/// research_agent_score_sets 한 행 — 지방장 하나의 판매점 전체 점수 (순위순 배열 압축 저장).
///   * store_codes[i] = (i+1)위 판매점, scores[i] = 그 판매점 점수
///   * live_factors / explore_factors 가 빈 배열이면 전부 1 (가설 반영 없음)
///   * hyp_counts 가 빈 배열이면 전부 0
///   * p_first = score × first_share (first_share 없으면 null)
class AgentScoreSet {
  final String modelVersion;
  final int targetRound;
  final String agentId;
  final List<String> storeCodes;
  final List<double?> scores;
  final List<double?> liveFactors;
  final List<double?> exploreFactors;
  final List<int?> hypCounts;
  final double? firstShare;
  final int? trainingEndRound;

  const AgentScoreSet({
    required this.modelVersion,
    required this.targetRound,
    required this.agentId,
    this.storeCodes = const [],
    this.scores = const [],
    this.liveFactors = const [],
    this.exploreFactors = const [],
    this.hypCounts = const [],
    this.firstShare,
    this.trainingEndRound,
  });

  factory AgentScoreSet.fromRow(Map<String, dynamic> r) => AgentScoreSet(
        modelVersion: (r['model_version'] ?? '').toString(),
        targetRound: _i(r['target_round']),
        agentId: (r['agent_id'] ?? '').toString(),
        storeCodes: _strs(r['store_codes']),
        scores: r['scores'] is List ? (r['scores'] as List).map(_d).toList() : const [],
        liveFactors: r['live_factors'] is List ? (r['live_factors'] as List).map(_d).toList() : const [],
        exploreFactors: r['explore_factors'] is List ? (r['explore_factors'] as List).map(_d).toList() : const [],
        hypCounts: r['hyp_counts'] is List ? (r['hyp_counts'] as List).map(_iN).toList() : const [],
        firstShare: _d(r['first_share']),
        trainingEndRound: _iN(r['training_end_round']),
      );

  int get size => storeCodes.length;

  /// 배열 계수: 빈 배열 = 전부 1, 값 누락(배열 길이 부족·null) = 1 (중립, 반영 없음)
  static double _factorAt(List<double?> l, int i) => l.isEmpty || i >= l.length ? 1 : (l[i] ?? 1);

  /// 판매점 하나로 펼치기. [i] 위치에 점수가 없으면 null (점수를 만들어내지 않는다).
  AgentStoreScore? expandAt(int i) {
    if (i < 0 || i >= storeCodes.length) return null;
    final code = storeCodes[i];
    final score = i < scores.length ? scores[i] : null;
    if (code.isEmpty || score == null) return null;
    return AgentStoreScore(
      targetRound: targetRound,
      storeCode: code,
      agentId: agentId,
      agentRank: i + 1,
      agentSize: storeCodes.length,
      score: score,
      pFirst: firstShare == null ? null : score * firstShare!,
      liveFactor: _factorAt(liveFactors, i),
      exploreFactor: _factorAt(exploreFactors, i),
      hypCount: hypCounts.isEmpty || i >= hypCounts.length ? 0 : (hypCounts[i] ?? 0),
      trainingEndRound: trainingEndRound,
      modelVersion: modelVersion.isEmpty ? null : modelVersion,
      fromScoreSet: true,
    );
  }

  /// 전체 펼치기 (순위순)
  List<AgentStoreScore> expand() => [
        for (var i = 0; i < storeCodes.length; i++) ?expandAt(i),
      ];

  /// 여러 행을 store_code → 점수로 펼친다 (순수 함수, 단위 테스트 대상).
  /// [codes] 지정 시 그 판매점만. 같은 코드가 여러 지방장에 있으면 처음 것을 유지한다.
  static Map<String, AgentStoreScore> expandRows(Iterable<AgentScoreSet> sets, {Iterable<String>? codes}) {
    final want = codes?.toSet();
    final out = <String, AgentStoreScore>{};
    for (final s in sets) {
      for (var i = 0; i < s.storeCodes.length; i++) {
        final code = s.storeCodes[i];
        if (want != null && !want.contains(code)) continue;
        if (out.containsKey(code)) continue;
        final e = s.expandAt(i);
        if (e != null) out[code] = e;
      }
    }
    return out;
  }
}

/// (모델, 목표 회차)별 score_sets 캐시 항목
class _ScoreSetEntry {
  final DateTime at = DateTime.now();

  /// null = 아직 모름, false = 테이블 없음/해당 회차 행 없음 (기존 테이블로 대체)
  bool? present;

  /// 해당 회차 전체 행을 받았는지
  bool complete = false;
  final Map<String, AgentScoreSet> sets = {};
  final Set<String> fetchedAgents = {};
}

class AgentFocusRegion {
  final String regionId;
  final double? p, base, ratio, factor;
  final int? rank;
  const AgentFocusRegion({required this.regionId, this.p, this.base, this.ratio, this.factor, this.rank});
  factory AgentFocusRegion.fromMap(Map<String, dynamic> m) => AgentFocusRegion(
        regionId: (m['region_id'] ?? '').toString(),
        p: _d(m['p']),
        base: _d(m['base']),
        ratio: _d(m['ratio']),
        factor: _d(m['factor']),
        rank: _iN(m['rank']),
      );
}

class AgentCentralStore {
  final String storeCode;
  final String? agentId;
  final String? name;
  final double? score;
  final double? pFirst;
  final int? agentRank;
  final String? verification;
  final String? reason;
  const AgentCentralStore({
    required this.storeCode,
    this.agentId,
    this.name,
    this.score,
    this.pFirst,
    this.agentRank,
    this.verification,
    this.reason,
  });
  factory AgentCentralStore.fromMap(Map<String, dynamic> m) => AgentCentralStore(
        storeCode: (m['store_code'] ?? '').toString(),
        agentId: _s(m['agent_id']),
        name: _s(m['name']) ?? _s(m['store_name']),
        score: _d(m['score']),
        pFirst: _d(m['p_first']),
        agentRank: _iN(m['agent_rank']),
        verification: _s(m['verification']),
        reason: _s(m['reason']),
      );
  String get display => name ?? storeCode;
}

class AgentCentral {
  final int targetRound;
  final String mode;
  final int? trainingEndRound;
  final List<AgentFocusRegion> focusRegions;
  final List<AgentCentralStore> storeTop;
  final int liveHypotheses;
  final int agentsDelivered;
  final String? createdAt;
  final String? modelVersion;
  const AgentCentral({
    required this.targetRound,
    this.mode = 'live',
    this.trainingEndRound,
    this.focusRegions = const [],
    this.storeTop = const [],
    this.liveHypotheses = 0,
    this.agentsDelivered = 0,
    this.createdAt,
    this.modelVersion,
  });
  factory AgentCentral.fromRow(Map<String, dynamic> r) => AgentCentral(
        targetRound: _i(r['target_round']),
        mode: (r['mode'] ?? 'live').toString(),
        trainingEndRound: _iN(r['training_end_round']),
        focusRegions: _maps(r['focus_regions']).map(AgentFocusRegion.fromMap).toList(),
        storeTop: _maps(r['store_top']).map(AgentCentralStore.fromMap).toList(),
        liveHypotheses: _i(r['live_hypotheses']),
        agentsDelivered: _i(r['agents_delivered']),
        createdAt: _s(r['created_at']),
        modelVersion: _s(r['model_version']),
      );

  AgentFocusRegion? focusOf(String regionId) {
    for (final f in focusRegions) {
      if (f.regionId == regionId) return f;
    }
    return null;
  }
}

/// research_agent_briefings.payload 래퍼 (모든 필드 선택적)
class AgentBriefing {
  final Map<String, dynamic> payload;
  final int? targetRound;
  final int? trainingEndRound;
  final String? createdAt;
  final String? rowModelVersion;
  const AgentBriefing(
      {required this.payload, this.targetRound, this.trainingEndRound, this.createdAt, this.rowModelVersion});

  factory AgentBriefing.fromRow(Map<String, dynamic> r) {
    final p = _map(r['payload']);
    return AgentBriefing(
      payload: p,
      targetRound: _iN(p['target_round']) ?? _iN(r['target_round']),
      trainingEndRound: _iN(p['training_end_round']) ?? _iN(r['training_end_round']),
      createdAt: _s(r['created_at']),
      rowModelVersion: _s(r['model_version']),
    );
  }

  String? get modelVersion => _s(payload['model_version']) ?? rowModelVersion;
  Map<String, dynamic> get agents => _map(payload['agents']);
  List<AgentFocusRegion> get focusRegions =>
      _maps(payload['focus_regions']).map(AgentFocusRegion.fromMap).toList();
  List<AgentCentralStore> get topStores =>
      _maps(payload['top_stores']).map(AgentCentralStore.fromMap).toList();
  Map<String, dynamic> get famousCycles => _map(payload['famous_cycles']);
  Map<String, dynamic> get cowin => _map(payload['cowin']);
  Map<String, dynamic> get leadLag => _map(payload['lead_lag']);
  Map<String, dynamic> get shared => _map(payload['shared']);
  Map<String, int> get statusCounts => _intMap(payload['status_counts']);
  Map<String, dynamic> get performance => _map(payload['performance']);
  List<Map<String, dynamic>> get rankChanges => _maps(payload['rank_changes']);
  List<String> get dataLimits => _strs(payload['data_limits']);
  List<String> get lines => _strs(payload['lines']);

  /// 지방장별 실전 검증 성과 요약 (없으면 빈 맵)
  Map<String, dynamic> get agentPerformance => _map(payload['agent_performance']);

  /// 가설 판정 현황 (없으면 빈 맵)
  Map<String, dynamic> get hypothesisVerdicts => _map(payload['hypothesis_verdicts']);

  static List<AgentHypothesis> hyps(dynamic list) =>
      _maps(list).map(AgentHypothesis.fromMap).toList();
}

class AgentModeEval {
  final String mode;
  final int rounds;
  final int hitsFirst;
  final int hitsAny;
  final int exploreHitsAny;
  final int historyHitsAny;
  final int regionEvents;
  final int regionFirst;
  final double expectedUniform;
  final int? firstRound;
  final int? lastRound;
  const AgentModeEval({
    required this.mode,
    this.rounds = 0,
    this.hitsFirst = 0,
    this.hitsAny = 0,
    this.exploreHitsAny = 0,
    this.historyHitsAny = 0,
    this.regionEvents = 0,
    this.regionFirst = 0,
    this.expectedUniform = 0,
    this.firstRound,
    this.lastRound,
  });
}

class AgentRoundEvalSummary {
  final String agentId;
  final Map<String, AgentModeEval> byMode;
  const AgentRoundEvalSummary({required this.agentId, this.byMode = const {}});
  AgentModeEval? get live => byMode['live'];
  AgentModeEval? get backtest => byMode['backtest'];
  bool get isEmpty => byMode.isEmpty;

  /// 행 목록을 mode 별로 합산 (순수 함수, 단위 테스트 대상)
  static AgentRoundEvalSummary fromRows(String agentId, List<Map<String, dynamic>> rows) {
    final acc = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      acc.putIfAbsent((r['mode'] ?? 'backtest').toString(), () => []).add(r);
    }
    final out = <String, AgentModeEval>{};
    acc.forEach((mode, l) {
      int sum(String k) => l.fold(0, (a, r) => a + _i(r[k]));
      final rounds = l.map((r) => _iN(r['target_round'])).whereType<int>().toList()..sort();
      out[mode] = AgentModeEval(
        mode: mode,
        rounds: l.length,
        hitsFirst: sum('hits_first'),
        hitsAny: sum('hits_any'),
        exploreHitsAny: sum('explore_hits_any'),
        historyHitsAny: sum('history_hits_any'),
        regionEvents: sum('region_events'),
        regionFirst: sum('region_first'),
        expectedUniform: l.fold(0.0, (a, r) => a + (_d(r['expected_uniform']) ?? 0)),
        firstRound: rounds.isEmpty ? null : rounds.first,
        lastRound: rounds.isEmpty ? null : rounds.last,
      );
    });
    return AgentRoundEvalSummary(agentId: agentId, byMode: out);
  }
}

class AgentRelation {
  final int trainingEndRound;
  final String kind;
  final String srcId;
  final String dstId;
  final int lag;
  final String? srcRegion, dstRegion;
  final int? n, k;
  final double? expected, ratio, p, q;
  const AgentRelation({
    required this.trainingEndRound,
    required this.kind,
    required this.srcId,
    required this.dstId,
    this.lag = 0,
    this.srcRegion,
    this.dstRegion,
    this.n,
    this.k,
    this.expected,
    this.ratio,
    this.p,
    this.q,
  });
  factory AgentRelation.fromRow(Map<String, dynamic> r) => AgentRelation(
        trainingEndRound: _i(r['training_end_round']),
        kind: (r['kind'] ?? '').toString(),
        srcId: (r['src_id'] ?? '').toString(),
        dstId: (r['dst_id'] ?? '').toString(),
        lag: _i(r['lag']),
        srcRegion: _s(r['src_region']),
        dstRegion: _s(r['dst_region']),
        n: _iN(r['n']),
        k: _iN(r['k']),
        expected: _d(r['expected']),
        ratio: _d(r['ratio']),
        p: _d(r['p']),
        q: _d(r['q']),
      );

  /// [code] 기준 상대편 id 와 지역
  String otherId(String code) => srcId == code ? dstId : srcId;
  String? otherRegion(String code) => srcId == code ? dstRegion : srcRegion;
  bool isSource(String code) => srcId == code;
}

// ═══════════════════════════════════════════════════════════════════════
// 저장소 (읽기 전용)
// ═══════════════════════════════════════════════════════════════════════

class AgentResearchRepository {
  final SupabaseClient _db;
  AgentResearchRepository({SupabaseClient? client}) : _db = client ?? Supabase.instance.client;

  static const int _chunk = 150;
  static const Duration _ttl = Duration(minutes: 5);
  static final Map<String, (DateTime, dynamic)> _cache = {};

  /// 마지막으로 자동 선택된 최신 실전 모델 (미확인 시 최우선 모델 ag-1.1)
  static String _liveModel = kAgentLiveModelPriority.first;
  static String get liveModel => _liveModel;

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

  static void clearCache() {
    _cache.clear();
    _scoreSetCache.clear();
  }

  static ResearchLoad<T> _fail<T>(Object e, T empty) {
    final missing = RegionResearchRepository.isMissingTable(e);
    return ResearchLoad<T>(
      missing ? ResearchAvailability.notApplied : ResearchAvailability.error,
      empty,
      message: missing ? kResearchNotApplied : '$e',
    );
  }

  static ResearchLoad<T> _ok<T>(T data, bool empty) =>
      ResearchLoad<T>(empty ? ResearchAvailability.noData : ResearchAvailability.available, data,
          message: empty ? kResearchNoData : null);

  /// 관리자 전용 — 비관리자는 조회하지 않고 '관리자 전용' 상태(빈 값)를 돌려준다. null = 통과.
  /// 앱 내부 확인일 뿐이다. DB 수준 강제는 Supabase Auth 도입 후 RLS 로만 가능하며 현재 anon RLS 는 읽기를 허용한다.
  static Future<ResearchLoad<T>?> _adminOnly<T>(T empty) async => await AdminGate.isAdmin()
      ? null
      : ResearchLoad<T>(ResearchAvailability.notApplied, empty, message: kAdminOnlyMessage);

  static List<List<String>> _chunks(List<String> l) {
    final out = <List<String>>[];
    for (var i = 0; i < l.length; i += _chunk) {
      out.add(l.sublist(i, math.min(l.length, i + _chunk)));
    }
    return out;
  }

  // ── 목표 회차 · 중앙 엔진 ─────────────────────────────────────────────

  /// 최신 실전 기준 (모델 + 목표 회차). [model] 미지정 = ag-1.1 live → 없으면 ag-1.0. 5분 캐시.
  Future<ResearchLoad<AgentLiveRef?>> latestLive({bool force = false, String? model}) async {
    final denied = await _adminOnly<AgentLiveRef?>(null);
    if (denied != null) return denied;
    final key = 'latestLive_${model ?? 'auto'}';
    if (!force) {
      final c = _cached<ResearchLoad<AgentLiveRef?>>(key);
      if (c != null) return c;
    }
    try {
      final models = model == null ? kAgentLiveModelPriority : [model];
      final rows = await _db
          .from('research_agent_central')
          .select('model_version, target_round, mode')
          .inFilter('model_version', models)
          .order('target_round', ascending: false)
          .limit(80);
      final ref = AgentLiveRef.pick(List<Map<String, dynamic>>.from(rows), model: model);
      if (model == null && ref != null) _liveModel = ref.model;
      final res = _ok<AgentLiveRef?>(ref, ref == null);
      _put(key, res);
      return res;
    } catch (e) {
      final res = _fail<AgentLiveRef?>(e, null);
      if (res.state == ResearchAvailability.notApplied) _put(key, res); // 미적용 상태도 5분 캐시 (반복 404 방지)
      return res;
    }
  }

  /// 최신 실전 목표 회차 (모델은 [liveModel] 에 기록). [model] 지정 시 그 모델 기준.
  Future<ResearchLoad<int?>> latestLiveTarget({bool force = false, String? model}) async {
    final r = await latestLive(force: force, model: model);
    return ResearchLoad<int?>(r.state, r.data?.target, message: r.message);
  }

  /// [model] 이 null 이면 최신 실전 모델로 해석
  Future<String> _resolveModel(String? model) async {
    if (model != null) return model;
    final r = await latestLive();
    return r.data?.model ?? _liveModel;
  }

  /// 목표 회차의 중앙 엔진 결과 (live 우선, 없으면 backtest). 5분 캐시.
  Future<ResearchLoad<AgentCentral?>> loadCentral(int target, {bool force = false, String? model}) async {
    final denied = await _adminOnly<AgentCentral?>(null);
    if (denied != null) return denied;
    final m = model ?? _liveModel;
    final key = 'central_${m}_$target';
    if (!force) {
      final c = _cached<ResearchLoad<AgentCentral?>>(key);
      if (c != null) return c;
    }
    try {
      final rows = await _db
          .from('research_agent_central')
          .select()
          .eq('model_version', m)
          .eq('target_round', target);
      final list = List<Map<String, dynamic>>.from(rows);
      Map<String, dynamic>? pick;
      for (final r in list) {
        if ((r['mode'] ?? '') == 'live') pick = r;
      }
      pick ??= list.isEmpty ? null : list.first;
      final res = _ok<AgentCentral?>(pick == null ? null : AgentCentral.fromRow(pick), pick == null);
      _put(key, res);
      return res;
    } catch (e) {
      final res = _fail<AgentCentral?>(e, null);
      if (res.state == ResearchAvailability.notApplied) _put(key, res); // 미적용 상태도 5분 캐시 (반복 404 방지)
      return res;
    }
  }

  /// 최신 실전 목표 회차의 중앙 엔진 결과 ([model] 지정 시 그 모델의 최신)
  Future<ResearchLoad<AgentCentral?>> loadLatestCentral({bool force = false, String? model}) async {
    final t = await latestLive(force: force, model: model);
    if (t.data == null) return ResearchLoad<AgentCentral?>(t.state, null, message: t.message);
    return loadCentral(t.data!.target, force: force, model: t.data!.model);
  }

  // ── 납품 · 판매점 점수 ────────────────────────────────────────────────

  /// 목표 회차 live 납품 (지방장 지정 시 해당 지방장만). rank 오름차순.
  Future<ResearchLoad<List<AgentDelivery>>> loadDeliveries(
      {String? agentId, required int target, String? model}) async {
    final denied = await _adminOnly<List<AgentDelivery>>(const <AgentDelivery>[]);
    if (denied != null) return denied;
    try {
      var q = _db
          .from('research_agent_deliveries')
          .select()
          .eq('model_version', model ?? _liveModel)
          .eq('target_round', target)
          .eq('mode', 'live');
      if (agentId != null) q = q.eq('agent_id', agentId);
      final rows = await q.order('rank', ascending: true).range(0, 1999);
      final list = List<Map<String, dynamic>>.from(rows).map(AgentDelivery.fromRow).toList()
        ..sort((a, b) {
          final c = a.rank.compareTo(b.rank);
          return c != 0 ? c : a.storeCode.compareTo(b.storeCode);
        });
      return _ok(list, list.isEmpty);
    } catch (e) {
      return _fail(e, const <AgentDelivery>[]);
    }
  }

  /// 판매점 코드별 납품 (목표 회차 live)
  Future<ResearchLoad<List<AgentDelivery>>> loadDeliveriesForStore(String code,
      {required int target, String? model}) async {
    final denied = await _adminOnly<List<AgentDelivery>>(const <AgentDelivery>[]);
    if (denied != null) return denied;
    try {
      final rows = await _db
          .from('research_agent_deliveries')
          .select()
          .eq('model_version', model ?? _liveModel)
          .eq('target_round', target)
          .eq('mode', 'live')
          .eq('store_code', code);
      final list = List<Map<String, dynamic>>.from(rows).map(AgentDelivery.fromRow).toList();
      return _ok(list, list.isEmpty);
    } catch (e) {
      return _fail(e, const <AgentDelivery>[]);
    }
  }

  // ── 압축 점수(research_agent_score_sets, research_v7_score_sets.sql) ──
  // 1247회부터 ag-1.1 은 이 테이블에만 쓴다. 테이블 없음·해당 회차 행 없음 → research_agent_store_scores.
  static const Duration _scoreSetTtl = Duration(minutes: 10);
  static final Map<String, _ScoreSetEntry> _scoreSetCache = {};
  static const String _scoreSetCols = 'model_version, target_round, agent_id, store_codes, scores, live_factors, '
      'explore_factors, hyp_counts, first_share, training_end_round';

  /// (모델, 목표 회차)의 score_sets 행 (agent_id → 행). null = 테이블 없음/행 없음/오류 → 기존 테이블 사용.
  /// [agentIds] 지정 시 그 지방장 행만 조회, 미지정 시 해당 회차 전체(약 238행)를 받아 10분 캐시.
  Future<Map<String, AgentScoreSet>?> _loadScoreSets(String model, int target, Set<String>? agentIds) async {
    final key = '$model|$target';
    var entry = _scoreSetCache[key];
    if (entry != null && DateTime.now().difference(entry.at) > _scoreSetTtl) {
      _scoreSetCache.remove(key);
      entry = null;
    }
    entry ??= _scoreSetCache[key] = _ScoreSetEntry();
    if (entry.present == false) return null;
    try {
      if (!entry.complete) {
        if (agentIds == null) {
          final rows = List<Map<String, dynamic>>.from(await _db
              .from('research_agent_score_sets')
              .select(_scoreSetCols)
              .eq('model_version', model)
              .eq('target_round', target)
              .range(0, 999));
          for (final r in rows) {
            final s = AgentScoreSet.fromRow(r);
            entry.sets[s.agentId] = s;
          }
          entry.complete = true;
          entry.present = entry.sets.isNotEmpty;
        } else {
          final need = agentIds.where((a) => a.isNotEmpty && !entry!.fetchedAgents.contains(a)).toList()..sort();
          for (final ch in _chunks(need)) {
            final rows = List<Map<String, dynamic>>.from(await _db
                .from('research_agent_score_sets')
                .select(_scoreSetCols)
                .eq('model_version', model)
                .eq('target_round', target)
                .inFilter('agent_id', ch));
            for (final r in rows) {
              final s = AgentScoreSet.fromRow(r);
              entry.sets[s.agentId] = s;
            }
            entry.fetchedAgents.addAll(ch);
          }
          if (entry.sets.isNotEmpty) entry.present = true;
          if (entry.present == null) {
            // 요청 지방장 행이 없음 → 해당 회차 행이 아예 없는지 확인 (없으면 기존 테이블로 대체)
            final probe = await _db
                .from('research_agent_score_sets')
                .select('agent_id')
                .eq('model_version', model)
                .eq('target_round', target)
                .limit(1);
            entry.present = List<Map<String, dynamic>>.from(probe).isNotEmpty;
          }
        }
      }
      return entry.present == true ? entry.sets : null;
    } catch (e) {
      if (RegionResearchRepository.isMissingTable(e)) {
        entry.present = false; // SQL 미적용 → 10분 동안 기존 테이블만 사용 (반복 404 방지)
      } else {
        _scoreSetCache.remove(key); // 일시 오류는 캐시하지 않음
      }
      return null;
    }
  }

  /// 판매점별 지방장 점수. research_agent_score_sets(압축) 우선 → 테이블 없음·해당 회차 행 없음이면
  /// research_agent_store_scores(150개씩 inFilter).
  /// [agentIds] = 해당 판매점들의 지방장 id(= RegionStore.regionId). 모든 판매점의 지방장을 알 때만 넘긴다.
  Future<ResearchLoad<Map<String, AgentStoreScore>>> loadStoreScores(List<String> codes, int target,
      {String? model, Set<String>? agentIds}) async {
    final denied = await _adminOnly<Map<String, AgentStoreScore>>(const <String, AgentStoreScore>{});
    if (denied != null) return denied;
    final out = <String, AgentStoreScore>{};
    if (codes.isEmpty) return _ok(out, true);
    final m = model ?? _liveModel;
    final sets = await _loadScoreSets(m, target, agentIds == null || agentIds.isEmpty ? null : agentIds);
    if (sets != null) {
      out.addAll(AgentScoreSet.expandRows(sets.values, codes: codes));
      return _ok(out, out.isEmpty);
    }
    try {
      final sorted = codes.toSet().toList()..sort();
      for (final ch in _chunks(sorted)) {
        final rows = await _db
            .from('research_agent_store_scores')
            .select()
            .eq('model_version', m)
            .eq('target_round', target)
            .inFilter('store_code', ch);
        for (final r in List<Map<String, dynamic>>.from(rows)) {
          final s = AgentStoreScore.fromRow(r);
          if (s.storeCode.isNotEmpty) out[s.storeCode] = s;
        }
      }
      return _ok(out, out.isEmpty);
    } catch (e) {
      return _fail(e, const <String, AgentStoreScore>{});
    }
  }

  /// 최신 실전 기준(ag-1.1 → 없으면 ag-1.0) 판매점 점수. [agentIds] 는 [loadStoreScores] 와 같다.
  Future<ResearchLoad<Map<String, AgentStoreScore>>> loadLatestStoreScores(List<String> codes,
      {Set<String>? agentIds}) async {
    final t = await latestLive();
    if (t.data == null) {
      return ResearchLoad(t.state, const <String, AgentStoreScore>{}, message: t.message);
    }
    return loadStoreScores(codes, t.data!.target, model: t.data!.model, agentIds: agentIds);
  }

  /// 판매점들의 지방장 id 집합. 하나라도 판정 불가(null/빈 값)면 null (= 해당 회차 전체 조회).
  static Set<String>? agentIdsOf(Iterable<String?> ids) {
    final out = <String>{};
    for (final id in ids) {
      if (id == null || id.isEmpty) return null;
      out.add(id);
    }
    return out.isEmpty ? null : out;
  }

  // ── 지방장 ─────────────────────────────────────────────────────────────

  Future<ResearchLoad<List<AgentInfo>>> loadAgents({String? model}) async {
    final denied = await _adminOnly<List<AgentInfo>>(const <AgentInfo>[]);
    if (denied != null) return denied;
    try {
      final m = await _resolveModel(model);
      final rows = await _db
          .from('research_agents')
          .select()
          .eq('model_version', m)
          .order('agent_id', ascending: true)
          .range(0, 1999);
      final list = List<Map<String, dynamic>>.from(rows).map(AgentInfo.fromRow).toList();
      return _ok(list, list.isEmpty);
    } catch (e) {
      return _fail(e, const <AgentInfo>[]);
    }
  }

  Future<ResearchLoad<AgentInfo?>> loadAgent(String id, {String? model}) async {
    final denied = await _adminOnly<AgentInfo?>(null);
    if (denied != null) return denied;
    try {
      final m = await _resolveModel(model);
      final rows = await _db
          .from('research_agents')
          .select()
          .eq('model_version', m)
          .eq('agent_id', id)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows);
      return _ok<AgentInfo?>(list.isEmpty ? null : AgentInfo.fromRow(list.first), list.isEmpty);
    } catch (e) {
      return _fail<AgentInfo?>(e, null);
    }
  }

  // ── 가설 ───────────────────────────────────────────────────────────────

  static List<AgentHypothesis> sortHypotheses(List<AgentHypothesis> l) {
    int si(String s) {
      final i = kAgentHypStatusOrder.indexOf(s);
      return i < 0 ? kAgentHypStatusOrder.length : i;
    }

    return l
      ..sort((a, b) {
        var c = si(a.status).compareTo(si(b.status));
        if (c != 0) return c;
        c = (a.testP ?? 1.0).compareTo(b.testP ?? 1.0);
        if (c != 0) return c;
        return a.hypothesisId.compareTo(b.hypothesisId);
      });
  }

  /// 현재(기본) 재현 실행 — AgentReplayRepository.resolveCurrentRunId 가 갱신 (기본 'ag-1.1-r1')
  static String preferredRunId = kAgentReplayRunId;

  /// [runId] 재현 실행에 가설 행이 있는지 (테이블 없음·오류 → false). 5분 캐시.
  Future<bool> _replayHypExists(String runId) async {
    final key = 'replayHyp_$runId';
    final c = _cached<bool>(key);
    if (c != null) return c;
    var ok = false;
    try {
      final rows = await _db
          .from('research_replay_hypotheses')
          .select('hypothesis_id')
          .eq('replay_run_id', runId)
          .limit(1);
      ok = List<Map<String, dynamic>>.from(rows).isNotEmpty;
    } catch (_) {
      ok = false;
    }
    _put(key, ok);
    return ok;
  }

  /// 가설을 읽을 재현 실행 id. null = research_agent_hypotheses(ag-1.0) 사용.
  ///   [model] 미지정 → 현재 실행 (우선순위 목록 중 가설 행이 있는 첫 실행, 기본 ag-1.1-r1)
  ///   [model] 지정 → 그 모델의 실행 (가설 없으면 null), ag-1.0 → null.
  Future<String?> hypothesisRunId({String? model}) async {
    if (model == kAgentModelLegacy) return null;
    final runs = model == null
        ? {preferredRunId, ...kAgentReplayRunPriority}.toList()
        : [?agentRunIdForModel(model)];
    for (final r in runs) {
      if (await _replayHypExists(r)) return r;
    }
    return null;
  }

  /// 재현 가설 사용 여부 (하위 호환). [hypothesisRunId] 가 null 이 아니면 true.
  Future<bool> useReplayHypotheses({String? model}) async => (await hypothesisRunId(model: model)) != null;

  PostgrestFilterBuilder<PostgrestList> _hypBase(String? runId, {String columns = '*'}) => runId != null
      ? _db.from('research_replay_hypotheses').select(columns).eq('replay_run_id', runId)
      : _db.from('research_agent_hypotheses').select(columns).eq('model_version', kAgentModelLegacy);

  /// related_stores 에 [code] 가 포함된 가설 (현재 재현 실행 우선, 없으면 ag-1.0)
  Future<ResearchLoad<List<AgentHypothesis>>> loadHypothesesForStore(String code, {String? model}) async {
    final denied = await _adminOnly<List<AgentHypothesis>>(const <AgentHypothesis>[]);
    if (denied != null) return denied;
    try {
      final run = await hypothesisRunId(model: model);
      final rows = await _hypBase(run).contains('related_stores', [code]).range(0, 499);
      final list = sortHypotheses(List<Map<String, dynamic>>.from(rows).map(AgentHypothesis.fromMap).toList());
      return _ok(list, list.isEmpty);
    } catch (e) {
      return _fail(e, const <AgentHypothesis>[]);
    }
  }

  /// 지방장 소유(agent_id) 또는 관련 지역(related_regions)에 [id] 가 포함된 가설 (중복 제거)
  Future<ResearchLoad<List<AgentHypothesis>>> loadHypothesesForAgent(String id,
      {String? status, int limit = 100, String? model}) async {
    final denied = await _adminOnly<List<AgentHypothesis>>(const <AgentHypothesis>[]);
    if (denied != null) return denied;
    try {
      final run = await hypothesisRunId(model: model);
      final byId = <String, AgentHypothesis>{};
      var q1 = _hypBase(run).eq('agent_id', id);
      if (status != null) q1 = q1.eq('status', status);
      for (final r in List<Map<String, dynamic>>.from(await q1.range(0, limit - 1))) {
        final h = AgentHypothesis.fromMap(r);
        byId[h.hypothesisId] = h;
      }
      var q2 = _hypBase(run).contains('related_regions', [id]);
      if (status != null) q2 = q2.eq('status', status);
      for (final r in List<Map<String, dynamic>>.from(await q2.range(0, limit - 1))) {
        final h = AgentHypothesis.fromMap(r);
        byId.putIfAbsent(h.hypothesisId, () => h);
      }
      final list = sortHypotheses(byId.values.toList()).take(limit).toList();
      return _ok(list, list.isEmpty);
    } catch (e) {
      return _fail(e, const <AgentHypothesis>[]);
    }
  }

  /// 가설 저장소 (kind / status 필터). 재현 가설 우선, 없으면 ag-1.0.
  Future<ResearchLoad<List<AgentHypothesis>>> loadHypotheses(
      {String? kind, String? status, int limit = 200, String? model}) async {
    final denied = await _adminOnly<List<AgentHypothesis>>(const <AgentHypothesis>[]);
    if (denied != null) return denied;
    try {
      final run = await hypothesisRunId(model: model);
      var q = _hypBase(run);
      if (kind != null) q = q.eq('kind', kind);
      if (status != null) q = q.eq('status', status);
      final rows = await q.order('updated_at', ascending: false).range(0, limit - 1);
      final list = sortHypotheses(List<Map<String, dynamic>>.from(rows).map(AgentHypothesis.fromMap).toList());
      return _ok(list, list.isEmpty);
    } catch (e) {
      return _fail(e, const <AgentHypothesis>[]);
    }
  }

  /// 여러 판매점의 관련 가설 일괄 조회 (related_stores ov {codes}, 100개씩). store_code → 가설 목록.
  /// [runId] 미지정 시 현재 재현 실행 ([hypothesisRunId]). 실행이 없으면 ag-1.0 가설.
  /// 결과 맵에는 요청한 모든 코드가 들어간다 (가설 없음 = 빈 목록).
  Future<ResearchLoad<Map<String, List<AgentHypothesis>>>> loadHypothesesForStores(List<String> codes,
      {String? runId, String? model}) async {
    final denied = await _adminOnly<Map<String, List<AgentHypothesis>>>(const <String, List<AgentHypothesis>>{});
    if (denied != null) return denied;
    final want = codes.where((c) => c.isNotEmpty).toSet().toList()..sort();
    final out = <String, List<AgentHypothesis>>{for (final c in want) c: <AgentHypothesis>[]};
    if (want.isEmpty) return _ok(out, true);
    try {
      final run = runId ?? await hypothesisRunId(model: model);
      for (var i = 0; i < want.length; i += 100) {
        final ch = want.sublist(i, math.min(want.length, i + 100));
        final rows = await _hypBase(run).overlaps('related_stores', ch).range(0, 2999);
        for (final r in List<Map<String, dynamic>>.from(rows)) {
          final h = AgentHypothesis.fromMap(r);
          // 같은 가설이 여러 묶음에서 와도 판매점마다 한 번만 연결
          for (final c in h.relatedStores) {
            final l = out[c];
            if (l != null && !l.any((x) => x.hypothesisId == h.hypothesisId)) l.add(h);
          }
        }
      }
      for (final l in out.values) {
        sortHypotheses(l);
      }
      return _ok(out, out.values.every((l) => l.isEmpty));
    } catch (e) {
      return _fail(e, const <String, List<AgentHypothesis>>{});
    }
  }

  /// 지방장 여러 명 (research_agents, [model]) — agent_id → 정보
  Future<ResearchLoad<Map<String, AgentInfo>>> loadAgentsByIds(Iterable<String> ids, {required String model}) async {
    final denied = await _adminOnly<Map<String, AgentInfo>>(const <String, AgentInfo>{});
    if (denied != null) return denied;
    final want = ids.where((c) => c.isNotEmpty).toSet().toList()..sort();
    final out = <String, AgentInfo>{};
    if (want.isEmpty) return _ok(out, true);
    try {
      for (final ch in _chunks(want)) {
        final rows = await _db.from('research_agents').select().eq('model_version', model).inFilter('agent_id', ch);
        for (final r in List<Map<String, dynamic>>.from(rows)) {
          final a = AgentInfo.fromRow(r);
          out[a.agentId] = a;
        }
      }
      return _ok(out, out.isEmpty);
    } catch (e) {
      return _fail(e, const <String, AgentInfo>{});
    }
  }

  /// 여러 지방장의 목표 회차 live 납품 (선택: [rank] 지정 시 그 순위만). rank 오름차순.
  Future<ResearchLoad<List<AgentDelivery>>> loadDeliveriesForAgents(Iterable<String> agentIds,
      {required int target, required String model, int? rank}) async {
    final denied = await _adminOnly<List<AgentDelivery>>(const <AgentDelivery>[]);
    if (denied != null) return denied;
    final want = agentIds.where((c) => c.isNotEmpty).toSet().toList()..sort();
    if (want.isEmpty) return _ok(const <AgentDelivery>[], true);
    try {
      final out = <AgentDelivery>[];
      for (final ch in _chunks(want)) {
        var q = _db
            .from('research_agent_deliveries')
            .select()
            .eq('model_version', model)
            .eq('target_round', target)
            .eq('mode', 'live')
            .inFilter('agent_id', ch);
        if (rank != null) q = q.eq('rank', rank);
        final rows = await q.order('rank', ascending: true).range(0, 2999);
        out.addAll(List<Map<String, dynamic>>.from(rows).map(AgentDelivery.fromRow));
      }
      out.sort((a, b) {
        final c = a.rank.compareTo(b.rank);
        if (c != 0) return c;
        final c2 = a.agentId.compareTo(b.agentId);
        return c2 != 0 ? c2 : a.storeCode.compareTo(b.storeCode);
      });
      return _ok(out, out.isEmpty);
    } catch (e) {
      return _fail(e, const <AgentDelivery>[]);
    }
  }

  // ── 관계 그래프 (ag-1.0 만 존재) ─────────────────────────────────────────

  /// src_id 또는 dst_id 가 [code] 인 관계 — 최신 training_end_round 만, p 오름차순 상위 [limit]
  Future<ResearchLoad<List<AgentRelation>>> loadRelationsForStore(String code, {int limit = 20}) async {
    final denied = await _adminOnly<List<AgentRelation>>(const <AgentRelation>[]);
    if (denied != null) return denied;
    try {
      final all = <AgentRelation>[];
      for (final col in const ['src_id', 'dst_id']) {
        final rows = await _db
            .from('research_agent_relations')
            .select()
            .eq('model_version', kAgentModelLegacy)
            .eq(col, code)
            .order('training_end_round', ascending: false)
            .range(0, 299);
        all.addAll(List<Map<String, dynamic>>.from(rows).map(AgentRelation.fromRow));
      }
      if (all.isEmpty) return _ok(const <AgentRelation>[], true);
      final latest = all.map((r) => r.trainingEndRound).reduce(math.max);
      final seen = <String>{};
      final list = all
          .where((r) => r.trainingEndRound == latest)
          .where((r) => seen.add('${r.kind}|${r.srcId}|${r.dstId}|${r.lag}'))
          .toList()
        ..sort((a, b) {
          final c = (a.p ?? 1.0).compareTo(b.p ?? 1.0);
          if (c != 0) return c;
          return (b.ratio ?? 0).compareTo(a.ratio ?? 0);
        });
      final out = list.take(limit).toList();
      return _ok(out, out.isEmpty);
    } catch (e) {
      return _fail(e, const <AgentRelation>[]);
    }
  }

  // ── 평가 ───────────────────────────────────────────────────────────────

  /// 지방장별 회차 평가(research_agent_round_evals)를 mode(live/backtest)별로 합산.
  /// ag-1.1 은 이 테이블에 쓰지 않으므로 기본은 ag-1.0 (ag-1.1 이력은 AgentReplayRepository).
  Future<ResearchLoad<AgentRoundEvalSummary>> loadEvalSummary(String agentId,
      {String model = kAgentModelLegacy}) async {
    final denied = await _adminOnly<AgentRoundEvalSummary>(AgentRoundEvalSummary(agentId: agentId));
    if (denied != null) return denied;
    try {
      final rows = <Map<String, dynamic>>[];
      var off = 0;
      while (true) {
        final page = List<Map<String, dynamic>>.from(await _db
            .from('research_agent_round_evals')
            .select('target_round, mode, hits_first, hits_any, explore_hits_any, history_hits_any, '
                'region_events, region_first, expected_uniform')
            .eq('model_version', model)
            .eq('agent_id', agentId)
            .order('target_round', ascending: true)
            .range(off, off + 999));
        rows.addAll(page);
        if (page.length < 1000) break;
        off += 1000;
      }
      final s = AgentRoundEvalSummary.fromRows(agentId, rows);
      return _ok(s, s.isEmpty);
    } catch (e) {
      return _fail(e, AgentRoundEvalSummary(agentId: agentId));
    }
  }

  // ── 브리핑 ─────────────────────────────────────────────────────────────

  Future<AgentBriefing?> _briefingOf(String model) async {
    final rows = await _db
        .from('research_agent_briefings')
        .select()
        .eq('model_version', model)
        .order('target_round', ascending: false)
        .order('training_end_round', ascending: false)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    return list.isEmpty ? null : AgentBriefing.fromRow(list.first);
  }

  /// 최신 브리핑 (target_round → training_end_round 내림차순). [model] 미지정 시 ag-1.1 → 없으면 ag-1.0. 5분 캐시.
  Future<ResearchLoad<AgentBriefing?>> loadBriefing({bool force = false, String? model}) async {
    final denied = await _adminOnly<AgentBriefing?>(null);
    if (denied != null) return denied;
    final key = 'briefing_${model ?? 'auto'}';
    if (!force) {
      final c = _cached<ResearchLoad<AgentBriefing?>>(key);
      if (c != null) return c;
    }
    try {
      AgentBriefing? b;
      for (final m in model == null ? kAgentLiveModelPriority : [model]) {
        b = await _briefingOf(m);
        if (b != null) break;
      }
      final res = _ok<AgentBriefing?>(b, b == null);
      _put(key, res);
      return res;
    } catch (e) {
      final res = _fail<AgentBriefing?>(e, null);
      if (res.state == ResearchAvailability.notApplied) _put(key, res); // 미적용 상태도 5분 캐시 (반복 404 방지)
      return res;
    }
  }
}
