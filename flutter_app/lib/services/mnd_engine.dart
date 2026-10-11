import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'rpa_store_engine.dart' show StoreWinRecord;
import '../models/lotto_winning_number.dart';

const kMndModelVersion = '1.0';

// ══════════════════════════════════════════════════════════════
// 모델 클래스
// ══════════════════════════════════════════════════════════════

class MndStoreAnomaly {
  final String code;
  final String storeName;
  final String sido;
  final String sigungu;
  final int totalWins;
  final double expectedWins;
  final double poissonZScore;
  final double bayesianRate;
  final double bayesianLower;
  final double bayesianUpper;
  final bool volumeAdjusted;
  final String anomalyStatus;
  final int? lastWinRound;

  const MndStoreAnomaly({
    required this.code,
    required this.storeName,
    required this.sido,
    required this.sigungu,
    required this.totalWins,
    required this.expectedWins,
    required this.poissonZScore,
    required this.bayesianRate,
    required this.bayesianLower,
    required this.bayesianUpper,
    required this.volumeAdjusted,
    required this.anomalyStatus,
    this.lastWinRound,
  });

  factory MndStoreAnomaly.fromJson(Map<String, dynamic> j) => MndStoreAnomaly(
        code: j['dhlottery_code'] as String? ?? '',
        storeName: j['store_name'] as String? ?? '',
        sido: j['sido'] as String? ?? '',
        sigungu: j['sigungu'] as String? ?? '',
        totalWins: (j['total_wins'] as num?)?.toInt() ?? 0,
        expectedWins: (j['expected_wins'] as num?)?.toDouble() ?? 0,
        poissonZScore: (j['poisson_z_score'] as num?)?.toDouble() ?? 0,
        bayesianRate: (j['bayesian_rate'] as num?)?.toDouble() ?? 0,
        bayesianLower: (j['bayesian_lower'] as num?)?.toDouble() ?? 0,
        bayesianUpper: (j['bayesian_upper'] as num?)?.toDouble() ?? 0,
        volumeAdjusted: j['volume_adjusted'] as bool? ?? false,
        anomalyStatus: j['anomaly_status'] as String? ?? 'normal',
        lastWinRound: (j['last_win_round'] as num?)?.toInt(),
      );
}

class MndTransition {
  final String fromSido;
  final String toSido;
  final int horizon;
  final int observedCount;
  final int totalFrom;
  final double observedRate;
  final double baselineRate;
  final double lift;
  final double pValue;

  const MndTransition({
    required this.fromSido,
    required this.toSido,
    required this.horizon,
    required this.observedCount,
    required this.totalFrom,
    required this.observedRate,
    required this.baselineRate,
    required this.lift,
    required this.pValue,
  });

  factory MndTransition.fromJson(Map<String, dynamic> j) => MndTransition(
        fromSido: j['from_sido'] as String? ?? '',
        toSido: j['to_sido'] as String? ?? '',
        horizon: (j['horizon'] as num?)?.toInt() ?? 1,
        observedCount: (j['observed_count'] as num?)?.toInt() ?? 0,
        totalFrom: (j['total_from'] as num?)?.toInt() ?? 0,
        observedRate: (j['observed_rate'] as num?)?.toDouble() ?? 0,
        baselineRate: (j['baseline_rate'] as num?)?.toDouble() ?? (1 / 17),
        lift: (j['lift'] as num?)?.toDouble() ?? 0,
        pValue: (j['p_value'] as num?)?.toDouble() ?? 1,
      );
}

class MndChangePoint {
  final String subjectType;
  final String subjectId;
  final int changePointRound;
  final String direction;
  final double preRate;
  final double postRate;
  final double cusumValue;
  final String interpretation;

  const MndChangePoint({
    required this.subjectType,
    required this.subjectId,
    required this.changePointRound,
    required this.direction,
    required this.preRate,
    required this.postRate,
    required this.cusumValue,
    required this.interpretation,
  });

  factory MndChangePoint.fromJson(Map<String, dynamic> j) => MndChangePoint(
        subjectType: j['subject_type'] as String? ?? 'store',
        subjectId: j['subject_id'] as String? ?? '',
        changePointRound: (j['change_point_round'] as num?)?.toInt() ?? 0,
        direction: j['direction'] as String? ?? 'increase',
        preRate: (j['pre_rate'] as num?)?.toDouble() ?? 0,
        postRate: (j['post_rate'] as num?)?.toDouble() ?? 0,
        cusumValue: (j['cusum_value'] as num?)?.toDouble() ?? 0,
        interpretation: j['interpretation'] as String? ?? 'emerging_hotspot',
      );
}

class MndSpatialResult {
  final double moransI;
  final double moransZ;
  final double moransP;
  final List<String> hotspotSidos;
  final List<String> coldspotSidos;

  const MndSpatialResult({
    required this.moransI,
    required this.moransZ,
    required this.moransP,
    required this.hotspotSidos,
    required this.coldspotSidos,
  });

  factory MndSpatialResult.fromJson(Map<String, dynamic> j) => MndSpatialResult(
        moransI: (j['morans_i'] as num?)?.toDouble() ?? 0,
        moransZ: (j['morans_z'] as num?)?.toDouble() ?? 0,
        moransP: (j['morans_p'] as num?)?.toDouble() ?? 1,
        hotspotSidos: List<String>.from(j['hotspot_sidos'] as List? ?? []),
        coldspotSidos: List<String>.from(j['coldspot_sidos'] as List? ?? []),
      );
}

class MndHypothesis {
  final String hypothesisId;
  final String hypothesisType;
  final List<String> theorySources;
  final String subjectType;
  final String subjectId;
  final String subjectName;
  final Map<String, dynamic> conditionJson;
  final int? horizon;
  final Map<String, dynamic> evidenceJson;
  final int sampleSize;
  final double effectSize;
  final double pValue;
  final double uncertaintyLower;
  final double uncertaintyUpper;
  String status;
  final int wfRounds;
  final int wfSuccesses;
  final double? wfSuccessRate;
  final double? wfBaselineRate;
  final double? wfImprovement;
  final String gateStatus;
  final String? gateReason;
  final bool livePredictionActive;
  final int trainingEndRound;
  final int? discoveredRound; // 발견 회차 — 이 회차 이후만 out-of-sample 검증

  MndHypothesis({
    required this.hypothesisId,
    required this.hypothesisType,
    required this.theorySources,
    required this.subjectType,
    required this.subjectId,
    required this.subjectName,
    required this.conditionJson,
    this.horizon,
    required this.evidenceJson,
    required this.sampleSize,
    required this.effectSize,
    required this.pValue,
    required this.uncertaintyLower,
    required this.uncertaintyUpper,
    required this.status,
    required this.wfRounds,
    required this.wfSuccesses,
    this.wfSuccessRate,
    this.wfBaselineRate,
    this.wfImprovement,
    required this.gateStatus,
    this.gateReason,
    required this.livePredictionActive,
    required this.trainingEndRound,
    this.discoveredRound,
  });

  factory MndHypothesis.fromJson(Map<String, dynamic> j) => MndHypothesis(
        hypothesisId: j['hypothesis_id'] as String? ?? '',
        hypothesisType: j['hypothesis_type'] as String? ?? '',
        theorySources: List<String>.from(j['theory_sources'] as List? ?? []),
        subjectType: j['subject_type'] as String? ?? '',
        subjectId: j['subject_id'] as String? ?? '',
        subjectName: j['subject_name'] as String? ?? '',
        conditionJson: Map<String, dynamic>.from(j['condition_json'] as Map? ?? {}),
        horizon: (j['horizon'] as num?)?.toInt(),
        evidenceJson: Map<String, dynamic>.from(j['evidence_json'] as Map? ?? {}),
        sampleSize: (j['sample_size'] as num?)?.toInt() ?? 0,
        effectSize: (j['effect_size'] as num?)?.toDouble() ?? 0,
        pValue: (j['p_value'] as num?)?.toDouble() ?? 1,
        uncertaintyLower: (j['uncertainty_lower'] as num?)?.toDouble() ?? 0,
        uncertaintyUpper: (j['uncertainty_upper'] as num?)?.toDouble() ?? 0,
        status: j['status'] as String? ?? 'observing',
        wfRounds: (j['wf_rounds'] as num?)?.toInt() ?? 0,
        wfSuccesses: (j['wf_successes'] as num?)?.toInt() ?? 0,
        wfSuccessRate: (j['wf_success_rate'] as num?)?.toDouble(),
        wfBaselineRate: (j['wf_baseline_rate'] as num?)?.toDouble(),
        wfImprovement: (j['wf_improvement'] as num?)?.toDouble(),
        gateStatus: j['gate_status'] as String? ?? 'not_evaluated',
        gateReason: j['gate_reason'] as String?,
        livePredictionActive: j['live_prediction_active'] as bool? ?? false,
        trainingEndRound: (j['training_end_round'] as num?)?.toInt() ?? 0,
        discoveredRound: (j['discovered_round'] as num?)?.toInt(),
      );

  Map<String, dynamic> toUpsertMap() => {
        'hypothesis_id': hypothesisId,
        'hypothesis_type': hypothesisType,
        'theory_sources': theorySources,
        'subject_type': subjectType,
        'subject_id': subjectId,
        'subject_name': subjectName,
        'condition_json': conditionJson,
        'horizon': horizon,
        'evidence_json': evidenceJson,
        'sample_size': sampleSize,
        'effect_size': effectSize,
        'p_value': pValue,
        'uncertainty_lower': uncertaintyLower,
        'uncertainty_upper': uncertaintyUpper,
        'status': status,
        'wf_rounds': wfRounds,
        'wf_successes': wfSuccesses,
        'wf_success_rate': wfSuccessRate,
        'wf_baseline_rate': wfBaselineRate,
        'wf_improvement': wfImprovement,
        'gate_status': gateStatus,
        'gate_reason': gateReason,
        'live_prediction_active': livePredictionActive,
        'training_end_round': trainingEndRound,
        'model_version': kMndModelVersion,
      };
}

class MndBriefing {
  final int round;
  final String briefingText;
  final List<Map<String, dynamic>> highlights;
  final List<String> hypothesisIds;

  const MndBriefing({
    required this.round,
    required this.briefingText,
    required this.highlights,
    required this.hypothesisIds,
  });

  factory MndBriefing.fromJson(Map<String, dynamic> j) => MndBriefing(
        round: (j['round'] as num?)?.toInt() ?? 0,
        briefingText: j['briefing_text'] as String? ?? '',
        highlights: List<Map<String, dynamic>>.from(
            (j['highlights'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map))),
        hypothesisIds: List<String>.from(j['hypothesis_ids'] as List? ?? []),
      );
}

class MndState {
  final int lastAnalyzedRound;
  final int totalHypotheses;
  final int observingCount;
  final int validatingCount;
  final int acceptedCount;
  final int liveCount;
  final bool volumeDataAvailable;
  final MndBriefing? latestBriefing;
  final List<MndHypothesis> hypotheses;
  final List<MndStoreAnomaly> topAnomalies;
  final MndSpatialResult? spatialResult;
  final List<MndTransition> topTransitions;
  final List<MndChangePoint> recentChangePoints;

  const MndState({
    required this.lastAnalyzedRound,
    required this.totalHypotheses,
    required this.observingCount,
    required this.validatingCount,
    required this.acceptedCount,
    required this.liveCount,
    required this.volumeDataAvailable,
    this.latestBriefing,
    required this.hypotheses,
    required this.topAnomalies,
    this.spatialResult,
    required this.topTransitions,
    required this.recentChangePoints,
  });

  static MndState empty() => const MndState(
        lastAnalyzedRound: 0,
        totalHypotheses: 0,
        observingCount: 0,
        validatingCount: 0,
        acceptedCount: 0,
        liveCount: 0,
        volumeDataAvailable: false,
        hypotheses: [],
        topAnomalies: [],
        topTransitions: [],
        recentChangePoints: [],
      );
}

// ══════════════════════════════════════════════════════════════
// 수학 유틸
// ══════════════════════════════════════════════════════════════

double _gammaCdfApprox(double x, double alpha) {
  if (x <= 0) return 0;
  // Wilson-Hilferty 근사: Gamma(alpha,1) → Normal
  final z = (pow(x / alpha, 1 / 3) - (1 - 1 / (9 * alpha))) /
      sqrt(1 / (9 * alpha));
  return _normalCdf(z);
}

double _normalCdf(double z) {
  const a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741;
  const a4 = -1.453152027, a5 = 1.061405429, p = 0.3275911;
  final sign = z < 0 ? -1 : 1;
  final x = z.abs() / sqrt(2);
  final t = 1 / (1 + p * x);
  final y = 1 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-x * x);
  return 0.5 * (1 + sign * y);
}

double _gammaQuantile(double p, double alpha) {
  // Newton–Raphson 반복
  double x = alpha;
  for (int i = 0; i < 50; i++) {
    final fx = _gammaCdfApprox(x, alpha) - p;
    final dfx = exp((alpha - 1) * log(max(x, 1e-10)) - x - _logGamma(alpha));
    final dx = fx / max(dfx, 1e-15);
    x = max(x - dx, 1e-10);
    if (dx.abs() < 1e-8) break;
  }
  return x;
}

double _logGamma(double z) {
  const c = [
    76.18009172947146, -86.50532032941677, 24.01409824083091,
    -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5
  ];
  var x = z, y = z;
  var tmp = x + 5.5;
  tmp -= (x + 0.5) * log(tmp);
  var ser = 1.000000000190015;
  for (final ci in c) {
    y += 1;
    ser += ci / y;
  }
  return -tmp + log(2.5066282746310005 * ser / x);
}

double _binomialPValue(int k, int n, double p) {
  // 이항 검정 단측 (k >= observed), 정규 근사
  if (n == 0) return 1;
  final mean = n * p;
  final std = sqrt(n * p * (1 - p));
  if (std == 0) return k > mean ? 0 : 1;
  final z = (k - 0.5 - mean) / std;
  return 1 - _normalCdf(z);
}

// ══════════════════════════════════════════════════════════════
// 한국 시도 인접 행렬
// ══════════════════════════════════════════════════════════════


// 시도 표준화 (별칭 → 대표명)
String _normalizeSido(String sido) {
  // lottery_stores.region 은 약칭('서울','경기'…)을 쓰고 인접행렬은 정식명을 쓴다.
  // 약칭을 정식명으로 통일하지 않으면 인접 쌍이 하나도 매칭되지 않아 Moran's I 가 항상 null 이 된다.
  const map = {
    '강원도': '강원특별자치도', '강원': '강원특별자치도',
    '전라북도': '전북특별자치도', '전북': '전북특별자치도',
    '서울': '서울특별시', '경기': '경기도', '인천': '인천광역시', '부산': '부산광역시',
    '대구': '대구광역시', '광주': '광주광역시', '전남광주': '광주광역시', '대전': '대전광역시',
    '울산': '울산광역시', '세종': '세종특별자치시', '충북': '충청북도', '충남': '충청남도',
    '전남': '전라남도', '경북': '경상북도', '경남': '경상남도', '제주': '제주특별자치도',
  };
  return map[sido.trim()] ?? sido.trim();
}

const _kAdjPairs = [
  ['서울특별시', '경기도'],
  ['서울특별시', '인천광역시'],
  ['경기도', '인천광역시'],
  ['경기도', '강원특별자치도'],
  ['경기도', '충청북도'],
  ['경기도', '충청남도'],
  ['인천광역시', '충청남도'],
  ['강원특별자치도', '충청북도'],
  ['강원특별자치도', '경상북도'],
  ['충청북도', '충청남도'],
  ['충청북도', '전북특별자치도'],
  ['충청북도', '경상북도'],
  ['충청남도', '전북특별자치도'],
  ['충청남도', '대전광역시'],
  ['충청남도', '세종특별자치시'],
  ['대전광역시', '세종특별자치시'],
  ['대전광역시', '충청북도'],
  ['세종특별자치시', '충청북도'],
  ['전북특별자치도', '전라남도'],
  ['전북특별자치도', '경상남도'],
  ['전북특별자치도', '광주광역시'],
  ['전라남도', '광주광역시'],
  ['전라남도', '경상남도'],
  ['전라남도', '경상북도'],
  ['경상북도', '대구광역시'],
  ['경상북도', '경상남도'],
  ['경상북도', '울산광역시'],
  ['경상남도', '대구광역시'],
  ['경상남도', '부산광역시'],
  ['경상남도', '울산광역시'],
  ['부산광역시', '울산광역시'],
];

Map<String, Set<String>> _buildAdjMap() {
  final map = <String, Set<String>>{};
  for (final pair in _kAdjPairs) {
    map.putIfAbsent(pair[0], () => {}).add(pair[1]);
    map.putIfAbsent(pair[1], () => {}).add(pair[0]);
  }
  return map;
}

// ══════════════════════════════════════════════════════════════
// MndEngine
// ══════════════════════════════════════════════════════════════

class MndEngine {
  static final MndEngine instance = MndEngine._();
  MndEngine._();

  SupabaseClient get _db => Supabase.instance.client;

  // ── 전체 분석 실행 ─────────────────────────────────────────
  Future<MndState> runAnalysis(
    List<StoreWinRecord> history,
    int trainingEndRound, {
    void Function(String)? onStatus,
  }) async {
    final filtered = history.where((r) => r.round <= trainingEndRound).toList();
    onStatus?.call('Theory A: 판매점 이상 감지');
    final anomalies = await _runTheoryA(filtered, trainingEndRound);

    onStatus?.call('Theory B: 공간 자기상관');
    final spatial = await _runTheoryB(filtered, trainingEndRound);

    onStatus?.call('Theory C: 마르코프 전이');
    final transitions = await _runTheoryC(filtered, trainingEndRound);

    onStatus?.call('Theory F: 변화점 감지');
    final changePoints = await _runTheoryF(filtered, trainingEndRound);

    onStatus?.call('가설 생성');
    await _generateHypotheses(anomalies, spatial, transitions, changePoints, trainingEndRound);

    onStatus?.call('Walk-Forward 검증');
    await _runIncrementalWf(filtered, trainingEndRound, trainingEndRound - 50);

    final state = await loadState(trainingEndRound);

    // 연구소장 브리핑 자동 생성
    onStatus?.call('연구소장 브리핑 생성');
    try {
      await generateBriefing(trainingEndRound, state);
    } catch (e) {
      debugPrint('[MND] 브리핑 생성 오류: $e');
    }

    return state;
  }

  // ── 증분 Walk-Forward ──────────────────────────────────────
  Future<void> runIncrementalWalkForward(
    List<StoreWinRecord> history,
    int trainingEndRound,
    int incrementalRounds,
  ) async {
    final filtered = history.where((r) => r.round <= trainingEndRound).toList();
    final startRound = trainingEndRound - incrementalRounds;
    await _runIncrementalWf(filtered, trainingEndRound, startRound);
  }

  // ── 상태 로드 (UI용) ───────────────────────────────────────
  Future<MndState> loadState(int trainingEndRound) async {
    try {
      final anomalyRows = await _db
          .from('mnd_store_anomalies')
          .select()
          .eq('training_end_round', trainingEndRound)
          .eq('model_version', kMndModelVersion)
          .order('poisson_z_score', ascending: false)
          .limit(20);

      final hypRows = await _db
          .from('mnd_hypotheses')
          .select()
          .eq('model_version', kMndModelVersion);

      final spatialRows = await _db
          .from('mnd_spatial_autocorr')
          .select()
          .eq('training_end_round', trainingEndRound)
          .eq('model_version', kMndModelVersion)
          .limit(1);

      final transRows = await _db
          .from('mnd_regional_transitions')
          .select()
          .eq('training_end_round', trainingEndRound)
          .eq('model_version', kMndModelVersion)
          .gte('lift', 2.0)
          .order('lift', ascending: false)
          .limit(20);

      final cpRows = await _db
          .from('mnd_change_points')
          .select()
          .eq('training_end_round', trainingEndRound)
          .eq('model_version', kMndModelVersion);

      final briefRows = await _db
          .from('mnd_briefings')
          .select()
          .order('round', ascending: false)
          .limit(1);

      final anomalies = (anomalyRows as List)
          .map((r) => MndStoreAnomaly.fromJson(r as Map<String, dynamic>))
          .toList();

      final hypotheses = (hypRows as List)
          .map((r) => MndHypothesis.fromJson(r as Map<String, dynamic>))
          .toList();

      final spatial = (spatialRows as List).isNotEmpty
          ? MndSpatialResult.fromJson((spatialRows as List).first as Map<String, dynamic>)
          : null;

      final transitions = (transRows as List)
          .map((r) => MndTransition.fromJson(r as Map<String, dynamic>))
          .toList();

      final cps = (cpRows as List)
          .map((r) => MndChangePoint.fromJson(r as Map<String, dynamic>))
          .toList();

      final briefing = (briefRows as List).isNotEmpty
          ? MndBriefing.fromJson((briefRows as List).first as Map<String, dynamic>)
          : null;

      final observing = hypotheses.where((h) => h.status == 'observing').length;
      final validating = hypotheses.where((h) => h.status == 'validating').length;
      final accepted = hypotheses.where((h) => h.status == 'accepted').length;
      final live = hypotheses.where((h) => h.livePredictionActive).length;

      return MndState(
        lastAnalyzedRound: trainingEndRound,
        totalHypotheses: hypotheses.length,
        observingCount: observing,
        validatingCount: validating,
        acceptedCount: accepted,
        liveCount: live,
        volumeDataAvailable: false,
        latestBriefing: briefing,
        hypotheses: hypotheses,
        topAnomalies: anomalies,
        spatialResult: spatial,
        topTransitions: transitions,
        recentChangePoints: cps,
      );
    } catch (e) {
      debugPrint('MndEngine.loadState error: $e');
      return MndState.empty();
    }
  }

  // ── 연구소장 브리핑 생성 ───────────────────────────────────
  Future<MndBriefing> generateBriefing(int round, MndState state) async {
    final sb = StringBuffer();
    final highlights = <Map<String, dynamic>>[];
    final hIds = <String>[];

    final passedHyps = state.hypotheses.where((h) => h.gateStatus == 'pass').toList();
    final acceptedHyps = state.hypotheses.where((h) => h.status == 'accepted').toList();

    sb.write('마스터, $round회차 기준 명당 가설 연구소 브리핑입니다.\n\n');
    sb.write('⚠️ 주의: 현재 판매량 데이터가 없어 모든 분석은 판매량 미보정 상태입니다. '
        '이상 현상이 실제 명당인지, 단순히 판매량이 많은 곳인지는 추가 검증이 필요합니다.\n\n');

    if (passedHyps.isNotEmpty) {
      sb.write('▶ 검증 통과 가설 (실전 반영 가능)\n');
      for (final h in passedHyps.take(3)) {
        hIds.add(h.hypothesisId);
        final desc = _hypothesisDesc(h);
        sb.write('  • $desc\n');
        highlights.add({'type': 'pass', 'id': h.hypothesisId, 'desc': desc});
      }
      sb.write('\n');
    } else if (acceptedHyps.isNotEmpty) {
      sb.write('▶ 연구 수락 가설 (관찰 중, 실전 미반영)\n');
      for (final h in acceptedHyps.take(3)) {
        hIds.add(h.hypothesisId);
        final desc = _hypothesisDesc(h);
        sb.write('  • $desc\n');
        highlights.add({'type': 'accepted', 'id': h.hypothesisId, 'desc': desc});
      }
      sb.write('\n');
    }

    if (state.topAnomalies.isNotEmpty) {
      final top = state.topAnomalies.first;
      sb.write('▶ 가장 눈에 띄는 판매점: ${top.storeName} (${top.sido} ${top.sigungu})\n');
      sb.write('  통계적 이상 점수 ${top.poissonZScore.toStringAsFixed(1)} - '
          '${top.totalWins}회 당첨으로 예상(${top.expectedWins.toStringAsFixed(1)}회) 대비 '
          '${(top.totalWins / max(top.expectedWins, 0.001)).toStringAsFixed(1)}배 높습니다.\n\n');
    }

    if (state.spatialResult != null && state.spatialResult!.moransI > 0.3) {
      sb.write('▶ 공간 집중 현상: 전국적으로 당첨 판매점이 특정 지역에 집중되는 경향이 관찰됩니다 '
          '(Moran\'s I = ${state.spatialResult!.moransI.toStringAsFixed(2)}).\n');
      if (state.spatialResult!.hotspotSidos.isNotEmpty) {
        sb.write('  핫스팟 지역: ${state.spatialResult!.hotspotSidos.join(', ')}\n');
      }
      sb.write('\n');
    }

    if (state.topTransitions.isNotEmpty) {
      final top = state.topTransitions.first;
      sb.write('▶ 지역 연속성: ${top.fromSido} 당첨 후 ${top.horizon}회차 뒤 '
          '${top.toSido}에서 당첨될 확률이 기준(${(top.baselineRate * 100).toStringAsFixed(1)}%)보다 '
          '${top.lift.toStringAsFixed(1)}배 높게 관찰됩니다.\n\n');
    }

    if (state.recentChangePoints.isNotEmpty) {
      final emerging = state.recentChangePoints
          .where((cp) => cp.interpretation == 'emerging_hotspot')
          .toList();
      if (emerging.isNotEmpty) {
        sb.write('▶ 신흥 명당 후보: ${emerging.length}개 판매점에서 최근 당첨 빈도가 '
            '급증하는 변화가 감지됩니다.\n\n');
      }
    }

    sb.write('총 ${state.totalHypotheses}개 가설 추적 중 '
        '(관찰: ${state.observingCount}, 검증: ${state.validatingCount}, '
        '수락: ${state.acceptedCount}, 실전: ${state.liveCount})');

    final briefing = MndBriefing(
      round: round,
      briefingText: sb.toString(),
      highlights: highlights,
      hypothesisIds: hIds,
    );

    try {
      await _db.from('mnd_briefings').upsert({
        'round': round,
        'briefing_text': briefing.briefingText,
        'highlights': briefing.highlights,
        'hypothesis_ids': briefing.hypothesisIds,
        'model_version': kMndModelVersion,
      }, onConflict: 'round,model_version');
    } catch (e) {
      debugPrint('MndEngine.generateBriefing upsert error: $e');
    }

    return briefing;
  }

  String _hypothesisDesc(MndHypothesis h) {
    switch (h.hypothesisType) {
      case 'persistence':
        return '${h.subjectName} 판매점이 통계적으로 당첨이 집중됩니다 (효과크기: ${h.effectSize.toStringAsFixed(1)}배)';
      case 'transition':
        final from = h.conditionJson['from_sido'] ?? '';
        final to = h.conditionJson['to_sido'] ?? '';
        return '$from 당첨 후 ${h.horizon}회차 뒤 $to에서 당첨 경향';
      case 'spatial_cluster':
        return '전국 당첨 판매점의 공간적 집중 현상 관찰';
      case 'emerging':
        return '${h.subjectName} 판매점에서 최근 당첨 급증 패턴 감지';
      default:
        return h.subjectName;
    }
  }

  // ── 추천판매점 연동: MND 점수 ──────────────────────────────
  Future<double?> getStoreMndScore(String dhlotteryCode, int trainingEndRound) async {
    try {
      final rows = await _db
          .from('mnd_store_anomalies')
          .select('poisson_z_score, anomaly_status')
          .eq('dhlottery_code', dhlotteryCode)
          .eq('training_end_round', trainingEndRound)
          .eq('model_version', kMndModelVersion)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      final z = (rows.first['poisson_z_score'] as num?)?.toDouble() ?? 0;
      // z-score를 0~1 범위로 정규화 (z=5 → 1.0)
      return (z / 5.0).clamp(0.0, 1.0);
    } catch (e) {
      return null;
    }
  }

  // ── 추천판매점 연동: 시도 전이 점수 ───────────────────────
  Future<double?> getSidoTransitionScore(
      String fromSido, String targetSido, int horizon, int trainingEndRound) async {
    try {
      final rows = await _db
          .from('mnd_regional_transitions')
          .select('lift')
          .eq('from_sido', fromSido)
          .eq('to_sido', targetSido)
          .eq('horizon', horizon)
          .eq('training_end_round', trainingEndRound)
          .eq('model_version', kMndModelVersion)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      final lift = (rows.first['lift'] as num?)?.toDouble() ?? 0;
      return (lift / 5.0).clamp(0.0, 1.0);
    } catch (e) {
      return null;
    }
  }

  // ── 초기 연구 완료 여부 확인 ──────────────────────────────
  Future<bool> isInitialResearchDone(int latestRound) async {
    try {
      // 1. 세션 테이블에 completed 기록이 있으면 완료
      final sessRows = await _db
          .from('mnd_research_sessions')
          .select('id')
          .eq('session_type', 'initial_historical')
          .eq('model_version', kMndModelVersion)
          .eq('status', 'completed')
          .limit(1);
      if ((sessRows as List).isNotEmpty) return true;
      // 2. 분석 결과가 있으면 완료 (테이블 없을 수도 있으므로 fallback)
      final rows = await _db
          .from('mnd_store_anomalies')
          .select('id')
          .eq('training_end_round', latestRound)
          .eq('model_version', kMndModelVersion)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── 진행 중인 세션 조회 ────────────────────────────────────
  Future<Map<String, dynamic>?> getActiveSession() async {
    try {
      // 고착 복구: 60분 넘게 running 이면 failed 로 전환 (앱 종료·예외로 완료 기록이 누락된 세션)
      try {
        final stale = DateTime.now().toUtc().subtract(const Duration(minutes: 60)).toIso8601String();
        await _db.from('mnd_research_sessions').update({
          'status': 'failed', 'error_message': '60분 초과 running 고착 → 자동 실패 처리',
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('status', 'running').lt('started_at', stale);
      } catch (_) {}
      final rows = await _db
          .from('mnd_research_sessions')
          .select()
          .eq('model_version', kMndModelVersion)
          .eq('status', 'running')
          .order('started_at', ascending: false)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      return Map<String, dynamic>.from(rows.first as Map);
    } catch (_) {
      return null;
    }
  }

  // ── 공간 밀집(B)·신흥 명당(F) 회차별 백필 (from~최신, 누락 회차만) ──
  /// 각 회차 r 에 대해 r 이하 이력만으로 Theory B/F 를 실행해 저장한다. 기존 행은 건드리지 않는다.
  Future<Map<String, int>> runSpatialEmergingBackfill(
    List<StoreWinRecord> history, {
    int from = 1200,
    void Function(String)? onStatus,
  }) async {
    final maxRound = history.map((r) => r.round).fold<int>(0, (a, b) => a > b ? a : b);
    if (maxRound < from) return {'spatial': 0, 'change_points': 0, 'rounds': 0};
    await getActiveSession(); // 고착 세션 자가 복구
    const markerType = 'mnd_backfill_v2'; // v1 마커는 저장 실패(onConflict 불일치)를 완료로 기록했으므로 폐기
    Set<int> haveSpatial = {}, haveCp = {};
    try {
      final s = await _db.from('mnd_spatial_autocorr').select('training_end_round')
          .eq('model_version', kMndModelVersion).gte('training_end_round', from);
      haveSpatial = (s as List).map((r) => (r['training_end_round'] as num).toInt()).toSet();
      final c = await _db.from('research_results').select('payload')
          .eq('research_type', markerType).eq('model_version', kMndModelVersion).limit(1);
      final l = c as List;
      if (l.isNotEmpty) {
        haveCp = Set<int>.from(((l.first['payload'] as Map)['cp_rounds_done'] as List? ?? []).map((e) => (e as num).toInt()));
      }
    } catch (_) {}
    int spatialDone = 0, cpDone = 0, rounds = 0, spatialNull = 0;
    for (int r = from; r <= maxRound; r++) {
      final needS = !haveSpatial.contains(r), needC = !haveCp.contains(r);
      if (!needS && !needC) continue;
      final filtered = history.where((x) => x.round <= r).toList();
      onStatus?.call('명당연구소 백필 $r/$maxRound회 (공간 밀집·신흥 명당)');
      if (needS) { final res = await _runTheoryB(filtered, r); if (res != null) spatialDone++; else spatialNull++; }
      if (needC) {
        await _runTheoryF(filtered, r);
        if (_lastCpPersistOk) { cpDone++; haveCp.add(r); } // 저장 성공한 회차만 완료로 기록
      }
      rounds++;
      if (rounds % 5 == 0 || r == maxRound) {
        try {
          await _db.from('research_results').upsert({
            'research_type': markerType, 'model_version': kMndModelVersion,
            'training_end_round': maxRound, 'target_round': 0,
            'payload': {'from': from, 'to': maxRound, 'cp_rounds_done': haveCp.toList()..sort(),
                'spatial_null_rounds': spatialNull, 'updated_at': DateTime.now().toUtc().toIso8601String()},
          }, onConflict: 'research_type,model_version,training_end_round,target_round');
        } catch (_) {}
      }
    }
    return {'spatial': spatialDone, 'spatial_null': spatialNull, 'change_points': cpDone, 'rounds': rounds};
  }

  // ── 최근 세션 조회 (completed/failed 포함) ─────────────────
  Future<Map<String, dynamic>?> getLatestSession() async {
    try {
      final rows = await _db
          .from('mnd_research_sessions')
          .select()
          .eq('model_version', kMndModelVersion)
          .order('started_at', ascending: false)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      return Map<String, dynamic>.from(rows.first as Map);
    } catch (_) {
      return null;
    }
  }

  // ── 초기 자동 연구 (필요할 때만 실행) ─────────────────────
  // autoStartIfNeeded: 앱 시작 or _init() 후 호출. 백그라운드에서 실행됨.
  Future<void> autoStartIfNeeded(int latestRound) async {
    try {
      // 1. 이미 완료됐으면 skip
      final done = await isInitialResearchDone(latestRound);
      if (done) return;

      // 2. 이미 실행 중이면 skip
      final active = await getActiveSession();
      if (active != null) return;

      // 3. 세션 시작 기록
      String sessionId = '';
      try {
        final res = await _db.from('mnd_research_sessions').insert({
          'session_type': 'initial_historical',
          'status': 'running',
          'model_version': kMndModelVersion,
          'end_round': latestRound,
          'current_stage': '판매점 당첨 이력 로드 중',
        }).select('id').single();
        sessionId = (res as Map)['id'] as String? ?? '';
      } catch (_) {}

      Future<void> updateStage(String stage, {int? currentRound, int? total}) async {
        if (sessionId.isEmpty) return;
        try {
          await _db.from('mnd_research_sessions').update({
            'current_stage': stage,
            if (currentRound != null) 'current_round': currentRound,
            if (total != null) 'total_rounds': total,
          }).eq('id', sessionId);
        } catch (_) {}
      }

      // 4. 판매점 이력 로드
      await updateStage('판매점 당첨 이력 로드 중');
      List<StoreWinRecord> history = [];
      try {
        // StoreModelEngine을 직접 import하면 circular import 가능성 → 동일 패키지
        final rows = await _db
            .from('winning_history')
            .select('dhlottery_code, round, lat, lng, region, purchase_method, lottery_stores(name, sido, sigungu)')
            .order('round', ascending: true);
        final List<dynamic> list = rows as List;
        history = list.map((r) {
          final m = r as Map<String, dynamic>;
          final store = m['lottery_stores'] as Map<String, dynamic>? ?? {};
          // region = "시도 시군구 ..." 형식으로 조합
          final sido = store['sido'] as String? ?? '';
          final sigungu = store['sigungu'] as String? ?? '';
          final region = [sido, sigungu].where((s) => s.isNotEmpty).join(' ');
          return StoreWinRecord(
            code: m['dhlottery_code'] as String? ?? '',
            round: (m['round'] as num?)?.toInt() ?? 0,
            lat: (m['lat'] as num?)?.toDouble() ?? 0,
            lng: (m['lng'] as num?)?.toDouble() ?? 0,
            region: region.isEmpty ? m['region'] as String? ?? '' : region,
            purchaseMethod: m['purchase_method'] as String? ?? '',
          );
        }).where((r) => r.code.isNotEmpty && r.round > 0).toList();
      } catch (e) {
        if (sessionId.isNotEmpty) {
          await _db.from('mnd_research_sessions').update({
            'status': 'failed',
            'error_message': '이력 로드 실패: $e',
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', sessionId);
        }
        return;
      }

      // 5. 분석 실행
      try {
        await updateStage('Theory A: 판매점 이상 감지', total: history.length);
        await runAnalysis(
          history,
          latestRound,
          onStatus: (msg) => updateStage(msg).ignore(),
        );
        // 6. 완료 기록
        if (sessionId.isNotEmpty) {
          await _db.from('mnd_research_sessions').update({
            'status': 'completed',
            'current_stage': '초기 연구 완료',
            'end_round': latestRound,
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', sessionId);
        }
      } catch (e) {
        if (sessionId.isNotEmpty) {
          await _db.from('mnd_research_sessions').update({
            'status': 'failed',
            'error_message': '분석 실패: $e',
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', sessionId);
        }
      }
    } catch (e) {
      debugPrint('[MND] autoStartIfNeeded 오류: $e');
    }
  }

  // ── 새 회차 증분 분석 (Round Gate 파이프라인에서 호출) ──────
  Future<void> runIncrementalForRound({
    required LottoWinningNumber newRound,
    required List<StoreWinRecord> storeHistory,
  }) async {
    final round = newRound.round;
    try {
      // 중복 방지: 이미 이 training_end_round로 분석됐으면 skip
      final existing = await _db
          .from('mnd_store_anomalies')
          .select('id')
          .eq('training_end_round', round)
          .eq('model_version', kMndModelVersion)
          .limit(1);
      if ((existing as List).isNotEmpty) return;

      // 이 회차까지의 이력만 사용 (미래 데이터 누수 방지)
      final filtered = storeHistory.where((r) => r.round <= round).toList();
      if (filtered.length < 30) return; // 최소 데이터 요건

      // 세션 기록
      String sessionId = '';
      try {
        final res = await _db.from('mnd_research_sessions').insert({
          'session_type': 'incremental',
          'status': 'running',
          'model_version': kMndModelVersion,
          'start_round': round,
          'end_round': round,
          'current_stage': '${round}회차 증분 분석',
        }).select('id').single();
        sessionId = (res as Map)['id'] as String? ?? '';
      } catch (_) {}

      await runAnalysis(filtered, round);

      if (sessionId.isNotEmpty) {
        await _db.from('mnd_research_sessions').update({
          'status': 'completed',
          'current_stage': '완료',
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', sessionId);
      }
    } catch (e) {
      debugPrint('[MND] incremental[$round] 오류: $e');
    }
  }

  // ══════════════════════════════════════════════════════════
  // Theory A: Poisson + Bayesian
  // ══════════════════════════════════════════════════════════
  Future<List<MndStoreAnomaly>> _runTheoryA(
      List<StoreWinRecord> history, int trainingEndRound) async {
    final rounds = history.map((r) => r.round).toSet();
    final nRounds = rounds.length;
    if (nRounds == 0) return [];

    final winsByStore = <String, int>{};
    final lastWinByStore = <String, int>{};
    final storeInfo = <String, StoreWinRecord>{};

    for (final r in history) {
      winsByStore[r.code] = (winsByStore[r.code] ?? 0) + 1;
      if (lastWinByStore[r.code] == null || r.round > lastWinByStore[r.code]!) {
        lastWinByStore[r.code] = r.round;
      }
      storeInfo.putIfAbsent(r.code, () => r);
    }

    final nStores = winsByStore.length;
    final totalWins = winsByStore.values.fold(0, (a, b) => a + b);
    final globalRate = totalWins / (nStores * nRounds);

    // sido별 Bayesian prior
    final sidoWins = <String, int>{};
    final sidoStores = <String, Set<String>>{};
    for (final r in history) {
      final s = _normalizeSido(r.sido);
      sidoWins[s] = (sidoWins[s] ?? 0) + 1;
      sidoStores.putIfAbsent(s, () => {}).add(r.code);
    }

    final anomalies = <MndStoreAnomaly>[];

    for (final entry in winsByStore.entries) {
      final code = entry.key;
      final k = entry.value;
      final info = storeInfo[code]!;
      final sido = _normalizeSido(info.sido);

      final expected = nRounds * globalRate;
      final zScore = (k - expected) / sqrt(max(expected, 0.001));

      // Bayesian: sido-level prior
      final sw = sidoWins[sido] ?? 0;
      final ss = (sidoStores[sido]?.length ?? 1);
      final sidoRate = sw / (ss * nRounds);
      final alpha0 = sidoRate * 10;
      final beta0 = 10.0;
      final postRate = (alpha0 + k) / (beta0 + nRounds);
      final posteriorAlpha = alpha0 + k;
      final posteriorBeta = beta0 + nRounds;
      final lower = _gammaQuantile(0.025, posteriorAlpha) / posteriorBeta;
      final upper = _gammaQuantile(0.975, posteriorAlpha) / posteriorBeta;

      String anomalyStatus;
      if (zScore > 3) {
        anomalyStatus = 'anomalous';
      } else if (zScore > 1.5) {
        anomalyStatus = 'research';
      } else {
        anomalyStatus = 'normal';
      }

      anomalies.add(MndStoreAnomaly(
        code: code,
        storeName: '',
        sido: sido,
        sigungu: info.sigungu,
        totalWins: k,
        expectedWins: expected,
        poissonZScore: zScore,
        bayesianRate: postRate,
        bayesianLower: lower,
        bayesianUpper: upper,
        volumeAdjusted: false,
        anomalyStatus: anomalyStatus,
        lastWinRound: lastWinByStore[code],
      ));
    }

    // DB upsert 배치
    final rows = anomalies
        .map((a) => {
              'dhlottery_code': a.code,
              'store_name': a.storeName,
              'sido': a.sido,
              'sigungu': a.sigungu,
              'total_wins': a.totalWins,
              'expected_wins': a.expectedWins,
              'poisson_z_score': a.poissonZScore,
              'bayesian_rate': a.bayesianRate,
              'bayesian_lower': a.bayesianLower,
              'bayesian_upper': a.bayesianUpper,
              'volume_adjusted': false,
              'anomaly_status': a.anomalyStatus,
              'last_win_round': a.lastWinRound,
              'training_end_round': trainingEndRound,
              'model_version': kMndModelVersion,
            })
        .toList();

    try {
      const chunkSize = 200;
      for (int i = 0; i < rows.length; i += chunkSize) {
        await _db.from('mnd_store_anomalies').upsert(
              rows.sublist(i, min(i + chunkSize, rows.length)),
              onConflict: 'dhlottery_code,model_version,training_end_round',
            );
      }
    } catch (e) {
      debugPrint('Theory A upsert error: $e');
    }

    return anomalies;
  }

  // ══════════════════════════════════════════════════════════
  // Theory B: Moran's I
  // ══════════════════════════════════════════════════════════
  Future<MndSpatialResult?> _runTheoryB(
      List<StoreWinRecord> history, int trainingEndRound) async {
    final sidoWins = <String, int>{};
    for (final r in history) {
      final s = _normalizeSido(r.sido);
      if (s.isNotEmpty) sidoWins[s] = (sidoWins[s] ?? 0) + 1;
    }

    final totalWins = sidoWins.values.fold(0, (a, b) => a + b);
    if (totalWins == 0) return null;

    final sidos = sidoWins.keys.toList();
    final n = sidos.length;
    if (n < 3) return null;

    final adjMap = _buildAdjMap();
    final densities = {
      for (final s in sidos) s: (sidoWins[s] ?? 0) / totalWins
    };

    final yBar = densities.values.fold(0.0, (a, b) => a + b) / n;
    double numerator = 0, denominator = 0, w = 0;

    for (int i = 0; i < sidos.length; i++) {
      final si = sidos[i];
      final yi = densities[si]! - yBar;
      denominator += yi * yi;
      final neighbors = adjMap[si] ?? {};
      for (final sj in sidos) {
        if (neighbors.contains(sj)) {
          numerator += yi * (densities[sj]! - yBar);
          w += 1;
        }
      }
    }

    if (denominator == 0 || w == 0) return null;

    final moransI = (n / w) * numerator / denominator;
    final eI = -1.0 / (n - 1);
    final varI = (n * n * (n * n - 3 * n + 3) + 3 * w * w - n * w * w) /
        ((n - 1) * (n - 1) * (n + 1) * w * w);
    final moransZ = (moransI - eI) / sqrt(max(varI.abs(), 1e-10));
    final moransP = 1 - _normalCdf(moransZ.abs());

    // Hot/cold spot (단순화: 평균 초과 여부)
    final hotspots = sidos
        .where((s) => (densities[s]! - yBar) > yBar * 0.5)
        .take(5)
        .toList();
    final coldspots = sidos
        .where((s) => (densities[s]! - yBar) < -yBar * 0.3)
        .take(5)
        .toList();

    final result = MndSpatialResult(
      moransI: moransI,
      moransZ: moransZ,
      moransP: moransP,
      hotspotSidos: hotspots,
      coldspotSidos: coldspots,
    );

    try {
      // UNIQUE 제약은 (scope, model_version, training_end_round) — onConflict 가 제약과 정확히 일치해야 저장됨
      await _db.from('mnd_spatial_autocorr').upsert({
        'scope': 'national',
        'morans_i': moransI,
        'morans_z': moransZ,
        'morans_p': moransP,
        'hotspot_sidos': hotspots,
        'coldspot_sidos': coldspots,
        'cluster_json': {'n_sidos': n, 'w_links': w, 'expected_i': eI, 'var_i': varI},
        'training_end_round': trainingEndRound,
        'model_version': kMndModelVersion,
      }, onConflict: 'scope,model_version,training_end_round');
    } catch (e) {
      debugPrint('Theory B upsert error: $e');
    }

    return result;
  }

  // ══════════════════════════════════════════════════════════
  // Theory C: Markov Transition
  // ══════════════════════════════════════════════════════════
  Future<List<MndTransition>> _runTheoryC(
      List<StoreWinRecord> history, int trainingEndRound) async {
    final byRound = <int, List<String>>{};
    for (final r in history) {
      byRound.putIfAbsent(r.round, () => []).add(_normalizeSido(r.sido));
    }

    final rounds = byRound.keys.toList()..sort();
    final transitions = <MndTransition>[];
    // 기준선 = 목적 시도가 임의 회차에 등장할 주변 확률 (균등 1/17 이 아님 —
    // 서울·경기는 회차의 절반 가까이 등장하므로 균등 기준선은 허위 lift 를 만든다)
    final toMarginal = <String, double>{};
    for (final r in rounds) {
      for (final s in byRound[r]!.toSet()) { toMarginal[s] = (toMarginal[s] ?? 0) + 1; }
    }
    toMarginal.updateAll((k, v) => v / rounds.length);

    for (int h = 1; h <= 6; h++) {
      final pairCounts = <String, int>{};
      final fromCounts = <String, int>{};

      for (int i = 0; i < rounds.length; i++) {
        final r = rounds[i];
        final targetRound = r + h;
        if (!byRound.containsKey(targetRound)) continue;

        final fromSidos = byRound[r]!.toSet();
        final toSidos = byRound[targetRound]!.toSet();

        for (final from in fromSidos) {
          fromCounts[from] = (fromCounts[from] ?? 0) + 1;
          for (final to in toSidos) {
            final key = '$from|$to';
            pairCounts[key] = (pairCounts[key] ?? 0) + 1;
          }
        }
      }

      for (final entry in pairCounts.entries) {
        if (entry.value < 3) continue;
        final parts = entry.key.split('|');
        final from = parts[0], to = parts[1];
        final totalFrom = fromCounts[from] ?? 1;
        final observedRate = entry.value / totalFrom;
        final baseline = (toMarginal[to] ?? (1 / 17.0)).clamp(1e-6, 1 - 1e-6);
        final lift = observedRate / baseline;
        final pVal = _binomialPValue(entry.value, totalFrom, baseline);

        transitions.add(MndTransition(
          fromSido: from,
          toSido: to,
          horizon: h,
          observedCount: entry.value,
          totalFrom: totalFrom,
          observedRate: observedRate,
          baselineRate: baseline,
          lift: lift,
          pValue: pVal,
        ));
      }
    }

    final rows = transitions
        .map((t) => {
              'from_sido': t.fromSido,
              'to_sido': t.toSido,
              'horizon': t.horizon,
              'observed_count': t.observedCount,
              'total_from': t.totalFrom,
              'observed_rate': t.observedRate,
              'baseline_rate': t.baselineRate,
              'lift': t.lift,
              'p_value': t.pValue,
              'training_end_round': trainingEndRound,
              'model_version': kMndModelVersion,
            })
        .toList();

    try {
      const chunkSize = 200;
      for (int i = 0; i < rows.length; i += chunkSize) {
        await _db.from('mnd_regional_transitions').upsert(
              rows.sublist(i, min(i + chunkSize, rows.length)),
              onConflict: 'from_sido,to_sido,horizon,model_version,training_end_round',
            );
      }
    } catch (e) {
      debugPrint('Theory C upsert error: $e');
    }

    return transitions;
  }

  // ══════════════════════════════════════════════════════════
  // Theory F: CUSUM 변화점
  // ══════════════════════════════════════════════════════════
  Future<List<MndChangePoint>> _runTheoryF(
      List<StoreWinRecord> history, int trainingEndRound) async {
    final rounds = history.map((r) => r.round).toSet().toList()..sort();
    if (rounds.isEmpty) return [];

    final nRounds = rounds.length;
    final winsByStore = <String, int>{};
    for (final r in history) {
      winsByStore[r.code] = (winsByStore[r.code] ?? 0) + 1;
    }
    final nStores = winsByStore.length;
    final totalWins = winsByStore.values.fold(0, (a, b) => a + b);
    final globalRate = totalWins / (nStores * nRounds);
    final k = globalRate * 0.8;
    const threshold = 3.0;

    final winsByStoreRound = <String, Set<int>>{};
    for (final r in history) {
      winsByStoreRound.putIfAbsent(r.code, () => {}).add(r.round);
    }

    final changePoints = <MndChangePoint>[];
    final storeInfo = <String, StoreWinRecord>{};
    for (final r in history) {
      storeInfo.putIfAbsent(r.code, () => r);
    }

    for (final code in winsByStoreRound.keys) {
      final winRounds = winsByStoreRound[code]!;
      double s = 0;
      int? cpRound;
      double maxS = 0;

      for (final round in rounds) {
        final indicator = winRounds.contains(round) ? 1.0 : 0.0;
        s = max(0, s + indicator - k);
        if (s > maxS) {
          maxS = s;
          if (s > threshold) cpRound ??= round;
        }
      }

      if (cpRound == null || cpRound < 1100) continue;

      final roundIdx = rounds.indexOf(cpRound);
      const window = 50;

      final preRounds = rounds
          .sublist(max(0, roundIdx - window), roundIdx)
          .where((r) => winRounds.contains(r))
          .length;
      final preTotal = min(window, roundIdx);
      final preRate = preTotal > 0 ? preRounds / preTotal : 0.0;

      final postRounds = rounds
          .sublist(roundIdx, min(rounds.length, roundIdx + window))
          .where((r) => winRounds.contains(r))
          .length;
      final postTotal = min(window, rounds.length - roundIdx);
      final postRate = postTotal > 0 ? postRounds / postTotal : 0.0;

      if (postRate <= preRate * 1.5) continue;

      changePoints.add(MndChangePoint(
        subjectType: 'store',
        subjectId: code,
        changePointRound: cpRound,
        direction: 'increase',
        preRate: preRate,
        postRate: postRate,
        cusumValue: maxS,
        interpretation: 'emerging_hotspot',
      ));
    }

    final rows = changePoints
        .map((cp) => {
              'subject_type': cp.subjectType,
              'subject_id': cp.subjectId,
              'change_point_round': cp.changePointRound,
              'direction': cp.direction,
              'pre_rate': cp.preRate,
              'post_rate': cp.postRate,
              'cusum_value': cp.cusumValue,
              'interpretation': cp.interpretation,
              'training_end_round': trainingEndRound,
              'model_version': kMndModelVersion,
            })
        .toList();

    _lastCpPersistOk = true;
    try {
      const chunkSize = 200;
      for (int i = 0; i < rows.length; i += chunkSize) {
        // UNIQUE 제약 (subject_type, subject_id, change_point_round, model_version, training_end_round) 와 일치시킴
        await _db.from('mnd_change_points').upsert(
              rows.sublist(i, min(i + chunkSize, rows.length)),
              onConflict: 'subject_type,subject_id,change_point_round,model_version,training_end_round',
            );
      }
    } catch (e) {
      _lastCpPersistOk = false;
      debugPrint('Theory F upsert error: $e');
    }

    return changePoints;
  }

  bool _lastCpPersistOk = true;

  // ══════════════════════════════════════════════════════════
  // 가설 자동 생성
  // ══════════════════════════════════════════════════════════
  Future<void> _generateHypotheses(
    List<MndStoreAnomaly> anomalies,
    MndSpatialResult? spatial,
    List<MndTransition> transitions,
    List<MndChangePoint> changePoints,
    int trainingEndRound,
  ) async {
    final rows = <Map<String, dynamic>>[];

    // A형: persistence 가설
    for (final a in anomalies.where((a) => a.poissonZScore > 2.5)) {
      final lift = a.expectedWins > 0 ? a.totalWins / a.expectedWins : 1.0;
      rows.add({
        'hypothesis_id': 'mnd_A_${a.code}',
        'hypothesis_type': 'persistence',
        'theory_sources': ['A'],
        'subject_type': 'store',
        'subject_id': a.code,
        'subject_name': a.storeName.isNotEmpty ? a.storeName : a.code,
        'condition_json': {
          'min_z_score': a.poissonZScore,
          'sido': a.sido,
          'wins': a.totalWins,
        },
        'horizon': null,
        'evidence_json': {
          'z_score': a.poissonZScore,
          'expected': a.expectedWins,
          'actual': a.totalWins,
          'volume_adjusted': false,
        },
        'sample_size': a.totalWins,
        'effect_size': lift,
        'p_value': 1 - _normalCdf(a.poissonZScore),
        'uncertainty_lower': a.bayesianLower,
        'uncertainty_upper': a.bayesianUpper,
        'status': 'observing',
        'wf_rounds': 0,
        'wf_successes': 0,
        'wf_success_rate': null,
        'wf_baseline_rate': null,
        'wf_improvement': null,
        'gate_status': 'not_evaluated',
        'gate_reason': '판매량 미보정',
        'live_prediction_active': false,
        'training_end_round': trainingEndRound,
        'discovered_round': trainingEndRound,
        'model_version': kMndModelVersion,
      });
    }

    // B형: spatial_cluster 가설
    if (spatial != null && spatial.moransI > 0.3 && spatial.moransZ > 2) {
      rows.add({
        'hypothesis_id': 'mnd_B_national',
        'hypothesis_type': 'spatial_cluster',
        'theory_sources': ['B'],
        'subject_type': 'national',
        'subject_id': 'national',
        'subject_name': '전국',
        'condition_json': {
          'min_morans_i': 0.3,
          'min_morans_z': 2.0,
        },
        'horizon': null,
        'evidence_json': {
          'morans_i': spatial.moransI,
          'morans_z': spatial.moransZ,
          'morans_p': spatial.moransP,
          'hotspots': spatial.hotspotSidos,
        },
        'sample_size': 17,
        'effect_size': spatial.moransI,
        'p_value': spatial.moransP,
        'uncertainty_lower': 0,
        'uncertainty_upper': 1,
        'status': 'observing',
        'wf_rounds': 0,
        'wf_successes': 0,
        'wf_success_rate': null,
        'wf_baseline_rate': null,
        'wf_improvement': null,
        'gate_status': 'not_evaluated',
        'gate_reason': null,
        'live_prediction_active': false,
        'training_end_round': trainingEndRound,
        'discovered_round': trainingEndRound,
        'model_version': kMndModelVersion,
      });
    }

    // C형: transition 가설
    for (final t in transitions.where((t) => t.lift > 2.0 && t.observedCount >= 3)) {
      final hid = 'mnd_C_${t.fromSido}_${t.toSido}_h${t.horizon}';
      rows.add({
        'hypothesis_id': hid,
        'hypothesis_type': 'transition',
        'theory_sources': ['C'],
        'subject_type': 'sido',
        'subject_id': '${t.fromSido}→${t.toSido}',
        'subject_name': '${t.fromSido} → ${t.toSido}',
        'condition_json': {
          'from_sido': t.fromSido,
          'to_sido': t.toSido,
          'horizon': t.horizon,
          'min_lift': 2.0,
        },
        'horizon': t.horizon,
        'evidence_json': {
          'observed_count': t.observedCount,
          'total_from': t.totalFrom,
          'lift': t.lift,
          'p_value': t.pValue,
        },
        'sample_size': t.totalFrom,
        'effect_size': t.lift,
        'p_value': t.pValue,
        'uncertainty_lower': 0,
        'uncertainty_upper': 1,
        'status': 'observing',
        'wf_rounds': 0,
        'wf_successes': 0,
        'wf_success_rate': null,
        'wf_baseline_rate': null,
        'wf_improvement': null,
        'gate_status': 'not_evaluated',
        'gate_reason': null,
        'live_prediction_active': false,
        'training_end_round': trainingEndRound,
        'discovered_round': trainingEndRound,
        'model_version': kMndModelVersion,
      });
    }

    // D형: emerging 가설
    for (final cp in changePoints.where((cp) => cp.interpretation == 'emerging_hotspot')) {
      rows.add({
        'hypothesis_id': 'mnd_D_${cp.subjectId}',
        'hypothesis_type': 'emerging',
        'theory_sources': ['F'],
        'subject_type': 'store',
        'subject_id': cp.subjectId,
        'subject_name': cp.subjectId,
        'condition_json': {
          'change_point_round': cp.changePointRound,
          'direction': cp.direction,
          'pre_rate': cp.preRate,
          'post_rate': cp.postRate,
        },
        'horizon': null,
        'evidence_json': {
          'cusum_value': cp.cusumValue,
          'change_point_round': cp.changePointRound,
          'pre_rate': cp.preRate,
          'post_rate': cp.postRate,
          'rate_increase': cp.preRate > 0 ? cp.postRate / cp.preRate : 0,
        },
        'sample_size': 50,
        'effect_size': cp.preRate > 0 ? cp.postRate / cp.preRate : 1.0,
        'p_value': 0.05,
        'uncertainty_lower': 0,
        'uncertainty_upper': 1,
        'status': 'observing',
        'wf_rounds': 0,
        'wf_successes': 0,
        'wf_success_rate': null,
        'wf_baseline_rate': null,
        'wf_improvement': null,
        'gate_status': 'not_evaluated',
        'gate_reason': '판매량 미보정',
        'live_prediction_active': false,
        'training_end_round': trainingEndRound,
        'discovered_round': trainingEndRound,
        'model_version': kMndModelVersion,
      });
    }

    if (rows.isEmpty) return;
    try {
      // 기존 가설 ID 로드 (WF/lifecycle 데이터 보존 대상)
      final existingRows = await _db
          .from('mnd_hypotheses')
          .select('hypothesis_id')
          .eq('model_version', kMndModelVersion);
      final existingIds = (existingRows as List)
          .map((r) => r['hypothesis_id'] as String)
          .toSet();

      final newRows = rows.where((r) => !existingIds.contains(r['hypothesis_id'])).toList();
      final updateRows = rows.where((r) => existingIds.contains(r['hypothesis_id'])).toList();

      // 신규 가설: 전체 삽입 (wf_rounds=0)
      if (newRows.isNotEmpty) {
        const chunkSize = 100;
        for (int i = 0; i < newRows.length; i += chunkSize) {
          await _db.from('mnd_hypotheses')
              .insert(newRows.sublist(i, min(i + chunkSize, newRows.length)));
        }
      }

      // 기존 가설: 통계 증거만 업데이트 (WF/lifecycle 필드는 건드리지 않음)
      for (final r in updateRows) {
        try {
          await _db.from('mnd_hypotheses').update({
            'evidence_json': r['evidence_json'],
            'effect_size': r['effect_size'],
            'p_value': r['p_value'],
            'sample_size': r['sample_size'],
            'condition_json': r['condition_json'],
            'training_end_round': r['training_end_round'],
            'subject_name': r['subject_name'],
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('hypothesis_id', r['hypothesis_id']).eq('model_version', kMndModelVersion);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('_generateHypotheses error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════
  // Walk-Forward 검증
  // ══════════════════════════════════════════════════════════
  Future<void> _runIncrementalWf(
    List<StoreWinRecord> history,
    int trainingEndRound,
    int startRound,
  ) async {
    // WF는 startRound 이후 데이터만 사용 (가설은 startRound 이전 데이터로 생성됨)
    // 실제로 동일 데이터로 가설 생성+WF 테스트하면 in-sample 검증이 되므로
    // holdout period = startRound ~ trainingEndRound (마지막 50 회차)
    List<MndHypothesis> hypotheses;
    try {
      final rows = await _db
          .from('mnd_hypotheses')
          .select()
          .eq('model_version', kMndModelVersion);
      hypotheses = (rows as List)
          .map((r) => MndHypothesis.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('WF load hypotheses error: $e');
      return;
    }
    if (hypotheses.isEmpty) return;

    // 이미 WF 결과가 있는 (hypothesis_id, target_round) 조합 로드 (중복 방지)
    // + 발견 회차 미기록(구버전) 가설의 out-of-sample 재집계용 성공 여부 맵
    Set<String> existingWfKeys = {};
    final existingWf = <String, Map<int, bool>>{};
    try {
      int offset = 0;
      while (true) {
        final page = await _db
            .from('mnd_wf_results')
            .select('hypothesis_id,target_round,success')
            .eq('model_version', kMndModelVersion)
            .gte('target_round', startRound)
            .range(offset, offset + 999);
        final list = page as List;
        for (final r in list) {
          final id = '${r['hypothesis_id']}';
          final tr = (r['target_round'] as num).toInt();
          existingWfKeys.add('$id:$tr');
          existingWf.putIfAbsent(id, () => {})[tr] = r['success'] == true;
        }
        if (list.length < 1000) break;
        offset += 1000;
      }
    } catch (_) {}

    final rounds = history
        .map((r) => r.round)
        .where((r) => r >= startRound && r <= trainingEndRound)
        .toSet()
        .toList()
      ..sort();

    // 시도별 글로벌 당첨 빈도 (persistence baseline용)
    final totalRounds = history.map((r) => r.round).toSet().length;
    final totalWins = history.length;
    final globalWinRate = totalRounds > 0 ? totalWins / (history.map((r) => r.code).toSet().length * totalRounds) : 0.001;

    final winsByRound = <int, Set<String>>{};
    final sidoByRound = <int, Set<String>>{};
    for (final r in history) {
      winsByRound.putIfAbsent(r.round, () => {}).add(r.code);
      sidoByRound.putIfAbsent(r.round, () => {}).add(_normalizeSido(r.sido));
    }
    // 전이 가설 기준선: 목적 시도의 주변 등장 확률 (균등 1/17 아님)
    final allRoundKeys = sidoByRound.keys.toList();
    final sidoMarginal = <String, double>{};
    for (final s in sidoByRound.values) { for (final x in s) { sidoMarginal[x] = (sidoMarginal[x] ?? 0) + 1; } }
    sidoMarginal.updateAll((k, v) => allRoundKeys.isEmpty ? 0 : v / allRoundKeys.length);

    final wfResults = <Map<String, dynamic>>[];
    final hypUpdates = <Map<String, dynamic>>[];

    for (final hyp in hypotheses) {
      int newRounds = 0;
      int newSuccesses = 0;
      // out-of-sample: 발견 회차 이후만 검증. 구버전(발견 회차 미기록)은 training_end_round 를 발견 회차로 간주
      final disc = hyp.discoveredRound ?? hyp.trainingEndRound;

      if (hyp.hypothesisType == 'persistence') {
        for (final round in rounds) {
          if (round <= disc) continue;
          final key = '${hyp.hypothesisId}:$round';
          if (existingWfKeys.contains(key)) continue; // 중복 방지
          final didWin = winsByRound[round]?.contains(hyp.subjectId) ?? false;
          newRounds++;
          if (didWin) newSuccesses++;
          wfResults.add({
            'hypothesis_id': hyp.hypothesisId,
            'target_round': round,                          // 수정: test_round → target_round
            'prediction_json': {'predicted': true, 'type': 'persistence'},
            'actual_json': {'win': didWin, 'code': hyp.subjectId},
            'success': didWin,
            'score': didWin ? 1.0 : 0.0,
            'model_version': kMndModelVersion,
          });
        }
      } else if (hyp.hypothesisType == 'transition') {
        final from = hyp.conditionJson['from_sido'] as String? ?? '';
        final to = hyp.conditionJson['to_sido'] as String? ?? '';
        final h = hyp.horizon ?? 1;

        for (final round in rounds) {
          if (round <= disc) continue;
          final key = '${hyp.hypothesisId}:$round';
          if (existingWfKeys.contains(key)) continue;
          final fromWon = sidoByRound[round]?.contains(from) ?? false;
          if (!fromWon) continue;
          final targetRound = round + h;
          final toWon = sidoByRound[targetRound]?.contains(to) ?? false;
          newRounds++;
          if (toWon) newSuccesses++;
          wfResults.add({
            'hypothesis_id': hyp.hypothesisId,
            'target_round': round,
            'prediction_json': {'from': from, 'to': to, 'horizon': h},
            'actual_json': {'win': toWon, 'target_round': targetRound},
            'success': toWon,
            'score': toWon ? 1.0 : 0.0,
            'model_version': kMndModelVersion,
          });
        }
      } else if (hyp.hypothesisType == 'emerging') {
        final cpRound = hyp.conditionJson['change_point_round'] as int? ?? 0;
        for (final round in rounds) {
          if (round <= cpRound || round <= disc) continue;
          final key = '${hyp.hypothesisId}:$round';
          if (existingWfKeys.contains(key)) continue;
          final didWin = winsByRound[round]?.contains(hyp.subjectId) ?? false;
          newRounds++;
          if (didWin) newSuccesses++;
          wfResults.add({
            'hypothesis_id': hyp.hypothesisId,
            'target_round': round,
            'prediction_json': {'predicted': true, 'type': 'emerging'},
            'actual_json': {'win': didWin, 'code': hyp.subjectId},
            'success': didWin,
            'score': didWin ? 1.0 : 0.0,
            'model_version': kMndModelVersion,
          });
        }
      }

      // 기존 누적치: 발견 회차가 기록된 가설은 저장된 누적치를 신뢰하고,
      // 미기록(구버전·in-sample 오염) 가설은 발견 회차 이후의 저장된 WF 행만으로 재집계한다.
      int baseRounds = hyp.wfRounds, baseSuccesses = hyp.wfSuccesses;
      final needsReset = hyp.discoveredRound == null;
      if (needsReset) {
        baseRounds = 0; baseSuccesses = 0;
        final m = existingWf[hyp.hypothesisId] ?? const <int, bool>{};
        m.forEach((tr, ok) { if (tr > disc) { baseRounds++; if (ok) baseSuccesses++; } });
      }
      if (newRounds == 0 && !needsReset) continue; // 새 검증 없고 재집계도 불필요

      final totalWfRounds = baseRounds + newRounds;
      final totalWfSuccesses = baseSuccesses + newSuccesses;
      final successRate = totalWfRounds > 0 ? totalWfSuccesses / totalWfRounds : null;

      // 유형별 기준선
      double? baselineRate;
      if (hyp.hypothesisType == 'transition') {
        final to = hyp.conditionJson['to_sido'] as String? ?? '';
        baselineRate = sidoMarginal[_normalizeSido(to)] ?? sidoMarginal[to] ?? (1 / 17.0);
      } else if (hyp.hypothesisType == 'persistence' || hyp.hypothesisType == 'emerging') {
        baselineRate = globalWinRate; // 판매점 글로벌 평균 (판매량 미보정 → 참고용)
      }
      final improvement = (successRate != null && baselineRate != null) ? successRate - baselineRate : null;

      // Gate 판정 — 사전 고정 규칙:
      //  · 판매량 미보정 유형(persistence/emerging)은 검증 불가 → 연구용(not_evaluated), 절대 pass 없음
      //  · transition: out-of-sample n ≥ 30, 개선 > 0.03, 이항검정 p < 0.05 모두 충족 시 pass
      String gateStatus = 'not_evaluated';
      String? gateReason;
      final volumeFree = hyp.hypothesisType == 'transition';
      if (!volumeFree) {
        gateReason = '판매량 미보정 — 당첨확률 우위 검증 불가(연구용)';
      } else if (totalWfRounds < 30) {
        gateReason = 'out-of-sample $totalWfRounds회 (최소 30회)';
      } else if (improvement != null && improvement > 0.03 &&
          _binomialPValue(totalWfSuccesses, totalWfRounds, baselineRate!) < 0.05) {
        gateStatus = 'pass';
        gateReason = null;
      } else {
        gateStatus = 'fail';
        gateReason = '개선 ${improvement == null ? '-' : (improvement * 100).toStringAsFixed(1)}pp · 유의하지 않음';
      }
      final livePrediction = gateStatus == 'pass' && volumeFree;

      hypUpdates.add({
        'hypothesis_id': hyp.hypothesisId,
        'model_version': kMndModelVersion,
        'wf_rounds': totalWfRounds,
        'wf_successes': totalWfSuccesses,
        'wf_success_rate': successRate,
        'wf_baseline_rate': baselineRate,
        'wf_improvement': improvement,
        'gate_status': gateStatus,
        'gate_reason': gateReason,
        'live_prediction_active': livePrediction,
        'discovered_round': disc,
        'status': gateStatus == 'pass' ? 'accepted'
            : gateStatus == 'fail' ? 'weakened'
            : totalWfRounds >= 10 ? 'validating'
            : 'observing',
      });
    }

    // WF 결과 저장 (upsert으로 중복 방지)
    try {
      const chunkSize = 200;
      for (int i = 0; i < wfResults.length; i += chunkSize) {
        await _db
            .from('mnd_wf_results')
            .upsert(
              wfResults.sublist(i, min(i + chunkSize, wfResults.length)),
              onConflict: 'hypothesis_id,target_round,model_version',
              ignoreDuplicates: true,
            );
      }
    } catch (e) {
      debugPrint('WF results upsert error: $e');
    }

    // 가설 WF 통계 업데이트 (lifecycle/WF 필드만, 증거 필드 덮어쓰지 않음)
    try {
      for (final upd in hypUpdates) {
        await _db.from('mnd_hypotheses').update({
          'wf_rounds': upd['wf_rounds'],
          'wf_successes': upd['wf_successes'],
          'wf_success_rate': upd['wf_success_rate'],
          'wf_baseline_rate': upd['wf_baseline_rate'],
          'wf_improvement': upd['wf_improvement'],
          'gate_status': upd['gate_status'],
          'gate_reason': upd['gate_reason'],
          'live_prediction_active': upd['live_prediction_active'],
          'discovered_round': upd['discovered_round'],
          'status': upd['status'],
          'last_updated_round': trainingEndRound,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('hypothesis_id', upd['hypothesis_id']).eq('model_version', kMndModelVersion);
      }
    } catch (e) {
      debugPrint('WF hypothesis update error: $e');
    }
  }
}
