// ══════════════════════════════════════════════════════════
// RPA 통합 예측 체계 (Unified Prediction) — 순수 Dart
//
// 패턴분석/추천판매점의 모든 실전 추천은 이 모듈이 만든
// "활성 model_version + 학습 회차 + 대상 회차" 단위의 결과에서 파생됩니다.
//
//  - Number Base      : 엔진 번호 평가 + 결정적 기본 조합
//  - 가설 추천         : 가설 Gate 통과 여부로 실전/연구 분리, 동일 지지 조합 묶음
//  - 제외 후보         : 엔진 WEAK/EXCLUDE + Walk-Forward 제외 Gate
//  - 자리별 패턴       : Number Base 대비 Walk-Forward 비교 (보조 Evidence 자격)
//  - 대안 조합         : 활성 Number 후보 점수 기반 결정적 생성
//  - 충돌 검사         : 추천 ↔ 제외 ↔ 연구 결과 간 충돌 기록 (숨기거나 삭제하지 않음)
//
// 점수 정의(score_definition)는 각 결과에 함께 저장해
// 엔진 내부 점수 / 후보 순위 / 과거검증 성능 / 실제 적중을 섞지 않습니다.
// ══════════════════════════════════════════════════════════

import 'dart:math';

import '../models/lotto_winning_number.dart';
import 'rpa_number_core.dart';

/// 현재 활성 엔진 버전.
/// 2.1: 결정적 조합 생성(동점 번호순), 검증 Gate 기반 가설 보정,
///      통합 Prediction Result 저장. Number 점수 산식은 2.0과 동일.
const String kRpaActiveModelVersion = '2.1';

const kRpaModelVersionNotes = {
  '2.0': '시드 고정 셔플 조합 — 동점 순서에 따라 조합이 크게 바뀜',
  '2.1': '점수합 기반 결정적 조합, Gate 통과 가설만 보정, 통합 결과 저장',
};

// ── Prediction Result 계약 ─────────────────────────────────
class RpaPredictionType {
  static const numberBase = 'number_base';
  static const hypothesis = 'hypothesis';
  static const exclusion = 'exclusion';
  static const alternative = 'alternative';
  static const positional = 'positional';
  static const jointContextual = 'joint_contextual';
  static const all = [numberBase, hypothesis, exclusion, alternative, positional, jointContextual];
}

/// gate_status: 실전 반영 자격 (pass만 실전)
class RpaGate {
  static const pass = 'pass';
  static const fail = 'fail';
  static const notEvaluated = 'not_evaluated';
}

/// validation_status: 과거 검증 결과의 성격
class RpaValidation {
  static const validated = 'validated';        // 랜덤/기준 대비 유의한 개선 확인
  static const notBetter = 'not_better';       // 검증했으나 개선 없음
  static const insufficient = 'insufficient';  // 표본 부족
  static const research = 'research';          // 연구 단계 (미검증)
  static const integrityOnly = 'integrity_only'; // 데이터 무결성만 확인
}

class RpaPredictionResult {
  final int targetRound;
  final int trainingEndRound;
  final String modelVersion;
  final String? runId;
  final String predictionType;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> evidence;
  final String gateStatus;
  final String validationStatus;
  final Map<String, dynamic> scoreDefinition;
  final DateTime generatedAt;
  final String? sourceSnapshotId;

  const RpaPredictionResult({
    required this.targetRound,
    required this.trainingEndRound,
    required this.modelVersion,
    this.runId,
    required this.predictionType,
    required this.payload,
    required this.evidence,
    required this.gateStatus,
    required this.validationStatus,
    required this.scoreDefinition,
    required this.generatedAt,
    this.sourceSnapshotId,
  });

  bool get isLive => gateStatus == RpaGate.pass;

  Map<String, dynamic> toRow() => {
        'target_round': targetRound,
        'training_end_round': trainingEndRound,
        'model_version': modelVersion,
        'run_id': runId,
        'prediction_type': predictionType,
        'payload': payload,
        'evidence': evidence,
        'gate_status': gateStatus,
        'validation_status': validationStatus,
        'score_definition': scoreDefinition,
        'generated_at': generatedAt.toUtc().toIso8601String(),
        if (sourceSnapshotId != null) 'source_snapshot_id': sourceSnapshotId,
      };

  factory RpaPredictionResult.fromRow(Map<String, dynamic> r) => RpaPredictionResult(
        targetRound: r['target_round'] as int,
        trainingEndRound: r['training_end_round'] as int,
        modelVersion: '${r['model_version']}',
        runId: r['run_id'] as String?,
        predictionType: r['prediction_type'] as String,
        payload: Map<String, dynamic>.from(r['payload'] as Map? ?? {}),
        evidence: Map<String, dynamic>.from(r['evidence'] as Map? ?? {}),
        gateStatus: r['gate_status'] as String? ?? RpaGate.notEvaluated,
        validationStatus: r['validation_status'] as String? ?? RpaValidation.research,
        scoreDefinition: Map<String, dynamic>.from(r['score_definition'] as Map? ?? {}),
        generatedAt: DateTime.tryParse('${r['generated_at']}') ?? DateTime.now(),
        sourceSnapshotId: r['source_snapshot_id'] as String?,
      );
}

const kScoreDefinitions = {
  'final_score': '엔진 내부 점수: 지표 조건 일치 회차에서의 가중 출현 빈도 / 최댓값 (0~1). 확률·정확도가 아님',
  'rank': '후보 순위: final_score 내림차순, 동점은 번호 오름차순',
  'set_score': '조합 점수: 6개 번호 final_score 합 (0~6). 정렬용 내부 값',
  'wf_hits': '과거검증 성능: 미래정보 없이 t-1까지로 예측한 뒤 t회 실제 번호와 일치한 개수의 평균',
  'random_hits': '랜덤 기준: 6개 번호를 무작위로 고를 때 기대 적중 수 = 0.8개',
  'actual_hits': '실제 당첨 적중: 해당 회차 추첨 후 채점된 일치 개수',
};

// ══════════════════════════════════════════════════════════
// 통계 유틸
// ══════════════════════════════════════════════════════════

/// 비율 검정 z값 (관측 성공 k / n, 기준 확률 p0)
double rpaProportionZ(int k, int n, double p0) {
  if (n == 0 || p0 <= 0 || p0 >= 1) return 0;
  return (k / n - p0) / sqrt(p0 * (1 - p0) / n);
}

/// 대응 표본 평균차 t값
({double mean, double t, int n}) rpaPairedT(List<double> diffs) {
  final n = diffs.length;
  if (n < 2) return (mean: 0, t: 0, n: n);
  final mean = diffs.reduce((a, b) => a + b) / n;
  final varSum = diffs.fold(0.0, (s, d) => s + (d - mean) * (d - mean)) / (n - 1);
  final se = sqrt(varSum / n);
  return (mean: mean, t: se == 0 ? 0 : mean / se, n: n);
}

double _r(double v, [int d = 4]) => double.parse(v.toStringAsFixed(d));

// ══════════════════════════════════════════════════════════
// 결정적 조합 생성 (v2.1)
// ══════════════════════════════════════════════════════════

/// 1~45 평가에서 동점은 번호 오름차순으로 정렬한 후보 목록
List<Map<String, dynamic>> rpaStableCandidates(List<Map<String, dynamic>> evals, {int take = 18}) {
  final sorted = List<Map<String, dynamic>>.from(evals)
    ..sort((a, b) {
      final c = (b['final_score'] as num).compareTo(a['final_score'] as num);
      return c != 0 ? c : (a['n'] as int).compareTo(b['n'] as int);
    });
  return sorted.take(take).toList();
}

// ══════════════════════════════════════════════════════════
// 자리별 패턴 (구 PatternAnalysisEngine — 통계 참고)
// ══════════════════════════════════════════════════════════

class RpaPositionalPick {
  final int position;
  final int refNumber;
  final List<({int number, double score})> ranked; // 통합 점수 내림차순 TOP 5
  const RpaPositionalPick(this.position, this.refNumber, this.ranked);
}

/// 정렬된 당첨번호의 자리별 후속/차이/끝자리 통계 (화면의 기존 로직과 동일)
List<RpaPositionalPick> rpaPositionalAnalysis(List<LottoWinningNumber> rounds) {
  final sorted = List.of(rounds)..sort((a, b) => a.round.compareTo(b.round));
  if (sorted.length < 2) return [];
  List<int> pos(LottoWinningNumber r) => [...r.numbers]..sort();
  final latest = pos(sorted.last);
  final recentCutoff = sorted.length - 100;
  return List.generate(6, (p) {
    final ref = latest[p];
    final follow = <int, double>{};
    final delta = <int, double>{};
    final lastDigit = <int, double>{};
    for (int i = 0; i < sorted.length - 1; i++) {
      final cur = pos(sorted[i])[p];
      final next = pos(sorted[i + 1])[p];
      final w = i >= recentCutoff ? 3.0 : 1.0;
      delta[next - cur] = (delta[next - cur] ?? 0) + w;
      if (cur == ref) follow[next] = (follow[next] ?? 0) + w;
      if (next % 10 == ref % 10) lastDigit[next] = (lastDigit[next] ?? 0) + w;
    }
    List<int> rankedKeys(Map<int, double> m) {
      final e = m.entries.toList()
        ..sort((a, b) {
          final c = b.value.round().compareTo(a.value.round());
          return c != 0 ? c : a.key.compareTo(b.key);
        });
      return e.map((x) => x.key).toList();
    }
    final f = rankedKeys(follow)..remove(ref);
    final d = rankedKeys(delta.map((k, v) => MapEntry(k, v))..remove(0))
        .map((dd) => ref + dd)
        .where((n) => n >= 1 && n <= 45 && n != ref)
        .toList();
    final l = rankedKeys(lastDigit)..remove(ref);
    double norm(int i, int t) => t == 0 ? 0.0 : (1.0 - i / t).clamp(0.0, 1.0);
    final score = <int, List<double>>{};
    for (int i = 0; i < f.length; i++) { (score[f[i]] ??= [0, 0, 0])[0] = norm(i, f.length); }
    for (int i = 0; i < d.length; i++) { (score[d[i]] ??= [0, 0, 0])[1] = norm(i, d.length); }
    for (int i = 0; i < l.length; i++) { (score[l[i]] ??= [0, 0, 0])[2] = norm(i, l.length); }
    final ranked = score.entries
        .map((e) => (number: e.key, score: e.value[0] * 0.4 + e.value[1] * 0.4 + e.value[2] * 0.2))
        .toList()
      ..sort((a, b) {
        final c = b.score.compareTo(a.score);
        return c != 0 ? c : a.number.compareTo(b.number);
      });
    return RpaPositionalPick(p, ref, ranked.take(5).toList());
  });
}

List<int> rpaPositionalTopNumbers(List<RpaPositionalPick> picks) {
  final out = <int>[];
  for (final p in picks) {
    for (final r in p.ranked) {
      if (!out.contains(r.number)) { out.add(r.number); break; }
    }
  }
  return out;
}

// ══════════════════════════════════════════════════════════
// Historical Walk-Forward (미래정보 없음: t회 예측에 t-1까지만 사용)
// ══════════════════════════════════════════════════════════

class RpaWalkForwardReport {
  final int fromRound;
  final int toRound;
  final int n;
  final double baseTop6Hits;        // Number Base 상위 6개 평균 적중
  final double positionalTop6Hits;  // 자리별 1위 6개 평균 적중
  final double randomHits;          // 0.8
  final ({double mean, double t, int n}) positionalVsBase;
  final ({double mean, double t, int n}) baseVsRandom;
  final Map<String, ({int hits, int slots, double rate, double z})> classHitRates;
  final ({int correct, int total, double expected, double z}) directionRule;

  const RpaWalkForwardReport({
    required this.fromRound,
    required this.toRound,
    required this.n,
    required this.baseTop6Hits,
    required this.positionalTop6Hits,
    required this.randomHits,
    required this.positionalVsBase,
    required this.baseVsRandom,
    required this.classHitRates,
    required this.directionRule,
  });

  Map<String, dynamic> toJson() => {
        'from_round': fromRound,
        'to_round': toRound,
        'n': n,
        'base_top6_hits': _r(baseTop6Hits),
        'positional_top6_hits': _r(positionalTop6Hits),
        'random_hits': randomHits,
        'positional_vs_base': {'mean': _r(positionalVsBase.mean), 't': _r(positionalVsBase.t, 2), 'n': positionalVsBase.n},
        'base_vs_random': {'mean': _r(baseVsRandom.mean), 't': _r(baseVsRandom.t, 2), 'n': baseVsRandom.n},
        'class_hit_rates': classHitRates.map((k, v) => MapEntry(k, {
              'hits': v.hits, 'slots': v.slots, 'rate': _r(v.rate), 'z': _r(v.z, 2),
              'random_rate': _r(6 / 45),
            })),
        'direction_rule': {
          'correct': directionRule.correct, 'total': directionRule.total,
          'expected': _r(directionRule.expected, 1), 'z': _r(directionRule.z, 2),
        },
      };
}

/// 최근 [window]회차를 한 회차씩 전진하며 검증합니다.
/// Number Base 방향 보정(flip)은 리플레이와 동일하게 순차 학습합니다.
RpaWalkForwardReport rpaWalkForward(
  List<LottoWinningNumber> data, {
  required int trainingEndRound,
  int window = 300,
  int positionalStride = 1,
}) {
  final sorted = data.where((d) => d.round <= trainingEndRound).toList()
    ..sort((a, b) => a.round.compareTo(b.round));
  final startIdx = max(100, sorted.length - window);
  final rolling = RpaRollingState();
  for (int i = 0; i < startIdx; i++) {
    rolling.addRound(sorted[i]);
  }

  final baseHits = <double>[];
  final posDiffs = <double>[];
  final posHitsList = <double>[];
  final randDiffs = <double>[];
  final classHits = <String, int>{};
  final classSlots = <String, int>{};
  int dirCorrect = 0, dirTotal = 0;
  double dirExpected = 0;

  for (int i = startIdx; i < sorted.length; i++) {
    final train = sorted.sublist(0, i);
    final actual = sorted[i].numbers.toSet();
    final theory = rolling.theoryDirections();
    final finalDirs = rolling.finalDirections(theory);

    final evals = rpaComputeNumberEvaluations(train, finalDirs);
    final stable = rpaStableCandidates(evals, take: 45);
    final top6 = stable.take(6).map((e) => e['n'] as int).toList();
    final h = top6.where(actual.contains).length.toDouble();
    baseHits.add(h);
    randDiffs.add(h - 0.8);

    for (int r = 0; r < stable.length; r++) {
      final cls = rpaClassifyRank(r + 1);
      classSlots[cls] = (classSlots[cls] ?? 0) + 1;
      if (actual.contains(stable[r]['n'])) classHits[cls] = (classHits[cls] ?? 0) + 1;
    }

    // 지표 방향 규칙 검증 (neutral 제외)
    final av = rpaActualIndicatorValues(sorted[i].numbers);
    for (final id in rpaIndicatorIds) {
      final dir = finalDirs[id] ?? 'neutral';
      if (dir == 'neutral') continue;
      final base = rpaIndicatorBaselines[id] ?? 0.5;
      final above = (av[id] ?? 0) > base;
      dirTotal++;
      dirExpected += dir == 'above' ? base : 1 - base;
      if ((dir == 'above') == above) dirCorrect++;
    }

    if ((i - startIdx) % positionalStride == 0) {
      final posTop = rpaPositionalTopNumbers(rpaPositionalAnalysis(train));
      final ph = posTop.where(actual.contains).length.toDouble();
      posHitsList.add(ph);
      posDiffs.add(ph - h);
    }

    rolling.recordResult(finalDirs, av);
    rolling.addRound(sorted[i]);
  }

  double mean(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
  final classRates = <String, ({int hits, int slots, double rate, double z})>{};
  for (final cls in ['CORE', 'STRONG', 'SUPPORT', 'NEUTRAL', 'WEAK', 'EXCLUDE_CANDIDATE']) {
    final hits = classHits[cls] ?? 0;
    final slots = classSlots[cls] ?? 0;
    classRates[cls] = (
      hits: hits,
      slots: slots,
      rate: slots == 0 ? 0 : hits / slots,
      z: rpaProportionZ(hits, slots, 6 / 45),
    );
  }
  final dirSd = dirTotal == 0 ? 1.0 : sqrt(dirExpected * (1 - dirExpected / dirTotal));
  return RpaWalkForwardReport(
    fromRound: sorted[startIdx].round,
    toRound: sorted.last.round,
    n: baseHits.length,
    baseTop6Hits: mean(baseHits),
    positionalTop6Hits: mean(posHitsList),
    randomHits: 0.8,
    positionalVsBase: rpaPairedT(posDiffs),
    baseVsRandom: rpaPairedT(randDiffs),
    classHitRates: classRates,
    directionRule: (
      correct: dirCorrect,
      total: dirTotal,
      expected: dirExpected,
      z: dirSd == 0 ? 0 : (dirCorrect - dirExpected) / dirSd,
    ),
  );
}

// ══════════════════════════════════════════════════════════
// 가설 Gate
// ══════════════════════════════════════════════════════════

class RpaHypothesisInput {
  final String id;
  final String evidence;
  final String status;
  final String type;
  final int horizon;
  final String? indicator;   // expected_phenomenon.indicator
  final String? direction;   // above | below
  final int historicalSamples;
  final double historicalSuccessRate;
  final int futureVerifications;
  final int futureSuccesses;
  final double? monteCarloP;
  final double? currentWeight;

  const RpaHypothesisInput({
    required this.id,
    required this.evidence,
    required this.status,
    required this.type,
    required this.horizon,
    this.indicator,
    this.direction,
    required this.historicalSamples,
    required this.historicalSuccessRate,
    required this.futureVerifications,
    required this.futureSuccesses,
    this.monteCarloP,
    this.currentWeight,
  });

  factory RpaHypothesisInput.fromRow(Map<String, dynamic> r) {
    final exp = Map<String, dynamic>.from(r['expected_phenomenon'] as Map? ?? {});
    final trig = Map<String, dynamic>.from(r['trigger_conditions'] as Map? ?? {});
    return RpaHypothesisInput(
      id: '${r['id']}',
      evidence: r['evidence'] as String? ?? '',
      status: r['status'] as String? ?? 'discovered',
      type: (trig['type'] as String?) ?? (r['hypothesis_type'] as String? ?? 'sequential'),
      horizon: r['horizon'] as int? ?? (exp['horizon'] as int? ?? 1),
      indicator: exp['indicator'] as String?,
      direction: exp['direction'] as String?,
      historicalSamples: r['historical_sample_count'] as int? ?? 0,
      historicalSuccessRate: (r['historical_success_rate'] as num?)?.toDouble() ?? 0,
      futureVerifications: r['future_verification_count'] as int? ?? 0,
      futureSuccesses: r['future_success_count'] as int? ?? 0,
      monteCarloP: (r['monte_carlo_p_value'] as num?)?.toDouble(),
      currentWeight: (r['current_weight'] as num?)?.toDouble(),
    );
  }

  bool get isNumberHypothesis =>
      indicator != null && rpaIndicatorIds.contains(indicator) &&
      (direction == 'above' || direction == 'below');

  /// 랜덤일 때 이 방향이 맞을 확률
  double get randomBaseline {
    final b = rpaIndicatorBaselines[indicator] ?? 0.5;
    return direction == 'above' ? b : 1 - b;
  }

  String get groupKey => '$indicator:$direction';
}

class RpaHypothesisGateConfig {
  static const minFutureVerifications = 20;
  static const minFutureZ = 1.645;     // 단측 5%
  static const maxMonteCarloP = 0.05;
  static const lifecycleAllowed = {'validating', 'developing', 'accepted'};
}

class RpaHypothesisVerdict {
  final RpaHypothesisInput h;
  final bool live;
  final List<String> failedReasons;
  final double futureZ;
  final double historicalLift;
  const RpaHypothesisVerdict(this.h, this.live, this.failedReasons, this.futureZ, this.historicalLift);

  Map<String, dynamic> toJson() => {
        'id': h.id,
        'evidence': h.evidence,
        'status': h.status,
        'horizon': h.horizon,
        'indicator': h.indicator,
        'direction': h.direction,
        'live': live,
        'failed_reasons': failedReasons,
        'future': '${h.futureSuccesses}/${h.futureVerifications}',
        'future_z': _r(futureZ, 2),
        'random_baseline': _r(h.isNumberHypothesis ? h.randomBaseline : 0),
        'historical_success_rate': _r(h.historicalSuccessRate),
        'historical_lift': _r(historicalLift),
        'monte_carlo_p': h.monteCarloP,
      };
}

/// 실전 적용 자격: 생명주기 상태만으로 판단하지 않고 실제 검증 수치를 모두 통과해야 합니다.
RpaHypothesisVerdict rpaEvaluateHypothesis(RpaHypothesisInput h) {
  final reasons = <String>[];
  if (!h.isNumberHypothesis) reasons.add('번호 지표 가설 아님 (${h.type}) — 번호 추천에 적용 불가');
  if (!RpaHypothesisGateConfig.lifecycleAllowed.contains(h.status)) {
    reasons.add('생명주기 ${h.status} — 검증 단계 미도달');
  }
  if (h.futureVerifications < RpaHypothesisGateConfig.minFutureVerifications) {
    reasons.add('실제 미래 검증 ${h.futureVerifications}회 < ${RpaHypothesisGateConfig.minFutureVerifications}회');
  }
  final z = h.isNumberHypothesis
      ? rpaProportionZ(h.futureSuccesses, h.futureVerifications, h.randomBaseline)
      : 0.0;
  if (h.isNumberHypothesis && z < RpaHypothesisGateConfig.minFutureZ) {
    reasons.add('미래 적중률이 랜덤 기준(${(h.randomBaseline * 100).toStringAsFixed(1)}%) 대비 유의하지 않음 (z=${z.toStringAsFixed(2)})');
  }
  if (h.monteCarloP == null) {
    reasons.add('Monte Carlo 랜덤대조 미실행');
  } else if (h.monteCarloP! > RpaHypothesisGateConfig.maxMonteCarloP) {
    reasons.add('Monte Carlo p=${h.monteCarloP!.toStringAsFixed(3)} > ${RpaHypothesisGateConfig.maxMonteCarloP}');
  }
  final lift = h.isNumberHypothesis ? h.historicalSuccessRate - h.randomBaseline : 0.0;
  return RpaHypothesisVerdict(h, reasons.isEmpty, reasons, z, lift);
}

// ══════════════════════════════════════════════════════════
// 통합 번들 생성
// ══════════════════════════════════════════════════════════

class RpaUnifiedInputs {
  final int targetRound;
  final int trainingEndRound;
  final String? runId;
  final String? sourceSnapshotId;
  final List<Map<String, dynamic>> numberEvaluations;
  final Map<String, String> finalDirections;
  final List<RpaHypothesisInput> hypotheses;
  final List<LottoWinningNumber> trainingData;
  final RpaWalkForwardReport walkForward;
  final Map<String, dynamic>? jointContextual; // rpa_joint_contextual_predictions row
  final Map<String, dynamic> jointGate;        // rpaJointGate 결과

  const RpaUnifiedInputs({
    required this.targetRound,
    required this.trainingEndRound,
    this.runId,
    this.sourceSnapshotId,
    required this.numberEvaluations,
    required this.finalDirections,
    required this.hypotheses,
    required this.trainingData,
    required this.walkForward,
    this.jointContextual,
    required this.jointGate,
  });
}

class RpaUnifiedBundle {
  final List<RpaPredictionResult> results;
  final List<Map<String, dynamic>> conflicts;
  const RpaUnifiedBundle(this.results, this.conflicts);

  RpaPredictionResult? of(String type) {
    for (final r in results) {
      if (r.predictionType == type) return r;
    }
    return null;
  }
}

RpaUnifiedBundle rpaBuildUnifiedBundle(RpaUnifiedInputs inp, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final wf = inp.walkForward;
  final evalByN = {for (final e in inp.numberEvaluations) e['n'] as int: e};
  final stable = rpaStableCandidates(inp.numberEvaluations, take: 45);
  final rankOf = {for (int i = 0; i < stable.length; i++) stable[i]['n'] as int: i + 1};
  final classOf = {for (final e in stable) e['n'] as int: rpaClassifyRank(rankOf[e['n']]!)};

  RpaPredictionResult mk(String type, Map<String, dynamic> payload, Map<String, dynamic> evidence,
          String gate, String validation, Map<String, dynamic> scoreDef) =>
      RpaPredictionResult(
        targetRound: inp.targetRound,
        trainingEndRound: inp.trainingEndRound,
        modelVersion: kRpaActiveModelVersion,
        runId: inp.runId,
        predictionType: type,
        payload: payload,
        evidence: evidence,
        gateStatus: gate,
        validationStatus: validation,
        scoreDefinition: scoreDef,
        generatedAt: at,
        sourceSnapshotId: inp.sourceSnapshotId,
      );

  // ── 1. Number Base ────────────────────────────────────
  final ranked = rpaRankAllCombos(stable.take(18).toList(), inp.finalDirections);
  final baseSets = rpaBaseSets(ranked);
  final baseVsRandom = wf.baseVsRandom;
  final baseValidated = baseVsRandom.n >= 100 && baseVsRandom.t >= 1.96;
  final numberBase = mk(
    RpaPredictionType.numberBase,
    {
      'sets': baseSets.map((s) => s.toJson()).toList(),
      'top_numbers': stable.take(18).map((e) => {
            'n': e['n'], 'final_score': e['final_score'], 'rank': rankOf[e['n']],
            'classification': classOf[e['n']],
          }).toList(),
      'final_directions': inp.finalDirections,
    },
    {
      'walk_forward': wf.toJson(),
      'set_rule': '지표 방향 만족 + 점수합 내림차순 + 세트 간 중복 3개 이하 (난수 없음)',
      'hypothesis_boost_ids': ((stable.first['evidence'] as Map?)?['boost_hypothesis_ids']) ?? [],
    },
    // Number Base는 활성 엔진의 기준 출력: 무결성 Gate(학습 t-1, 활성 버전, 평가 45개)
    stable.length == 45 ? RpaGate.pass : RpaGate.fail,
    baseValidated ? RpaValidation.validated : RpaValidation.notBetter,
    {
      'final_score': kScoreDefinitions['final_score'],
      'set_score': kScoreDefinitions['set_score'],
      'wf_hits': kScoreDefinitions['wf_hits'],
      'random_hits': kScoreDefinitions['random_hits'],
    },
  );

  // ── 2. 가설 ───────────────────────────────────────────
  final horizon = inp.targetRound - inp.trainingEndRound;
  final verdicts = inp.hypotheses
      .where((h) => !['rejected', 'combined'].contains(h.status))
      .map(rpaEvaluateHypothesis)
      .toList();
  final groups = <String, List<RpaHypothesisVerdict>>{};
  for (final v in verdicts) {
    groups.putIfAbsent(v.h.isNumberHypothesis ? v.h.groupKey : 'non_number:${v.h.type}', () => []).add(v);
  }
  final groupPayload = groups.entries.map((g) {
    final first = g.value.first.h;
    final supported = <int>[];
    if (first.isNumberHypothesis) {
      for (int i = 0; i < baseSets.length; i++) {
        final v = rpaIndicatorBinary(baseSets[i].numbers, first.indicator!);
        final ok = first.direction == 'above' ? v == 1 : v == 0;
        if (ok) supported.add(i + 1);
      }
    }
    final atHorizon = g.value.where((v) => v.h.horizon == horizon).toList();
    return {
      'group_key': g.key,
      'label': first.isNumberHypothesis
          ? '${rpaIndicatorLabels[first.indicator] ?? first.indicator}(${first.direction == 'above' ? '↑' : '↓'})'
          : first.type,
      'hypothesis_count': g.value.length,
      'live_count': g.value.where((v) => v.live).length,
      'horizons': g.value.map((v) => v.h.horizon).toList()..sort(),
      'applies_to_target': atHorizon.isNotEmpty,
      'supported_base_sets': supported,
      'members': g.value.map((v) => v.toJson()).toList(),
    };
  }).toList();
  final liveCount = verdicts.where((v) => v.live).length;
  final hypothesis = mk(
    RpaPredictionType.hypothesis,
    {
      'live_count': liveCount,
      'research_count': verdicts.length - liveCount,
      'groups': groupPayload,
      'message': liveCount == 0 ? '현재 실전 반영 가능한 가설 없음 — 자동 연구는 계속됩니다' : null,
    },
    {
      'gate_rule': {
        'lifecycle': RpaHypothesisGateConfig.lifecycleAllowed.toList(),
        'min_future_verifications': RpaHypothesisGateConfig.minFutureVerifications,
        'min_future_z': RpaHypothesisGateConfig.minFutureZ,
        'max_monte_carlo_p': RpaHypothesisGateConfig.maxMonteCarloP,
      },
      'note': '가설은 번호를 직접 고르지 않습니다. 기본 조합이 가설 방향과 일치하는지(지지)만 표시합니다.',
    },
    liveCount > 0 ? RpaGate.pass : RpaGate.fail,
    liveCount > 0 ? RpaValidation.validated : RpaValidation.research,
    {'future_z': '실제 미래 검증 적중률의 랜덤 기준 대비 z값 (1.645 이상이면 단측 5% 유의)'},
  );

  // ── 3. 제외 ───────────────────────────────────────────
  final weak = stable.where((e) => classOf[e['n']] == 'WEAK').map((e) => e['n'] as int).toList();
  final excl = stable.where((e) => classOf[e['n']] == 'EXCLUDE_CANDIDATE').map((e) => e['n'] as int).toList();
  bool clsValidated(String cls) {
    final c = wf.classHitRates[cls];
    return c != null && wf.n >= 200 && c.z <= -1.645;
  }
  final weakLive = clsValidated('WEAK');
  final exclLive = clsValidated('EXCLUDE_CANDIDATE');
  final liveExcluded = [if (exclLive) ...excl, if (weakLive) ...weak]..sort();
  final researchExcluded = [if (!exclLive) ...excl, if (!weakLive) ...weak]..sort();
  final exclusion = mk(
    RpaPredictionType.exclusion,
    {
      'live_excluded': liveExcluded,
      'research_excluded': researchExcluded,
      'engine_weak': weak..sort(),
      'engine_exclude_candidate': excl..sort(),
      'message': liveExcluded.isEmpty ? '실전 제외번호 없음 — 엔진 약세 번호는 연구용 참고' : null,
    },
    {
      'walk_forward_class_rates': wf.toJson()['class_hit_rates'],
      'rule': 'Walk-Forward에서 해당 등급 번호의 출현율이 랜덤(13.3%)보다 유의하게 낮을 때(z≤-1.645, n≥200)만 실전 제외',
    },
    liveExcluded.isNotEmpty ? RpaGate.pass : RpaGate.fail,
    liveExcluded.isNotEmpty ? RpaValidation.validated : RpaValidation.notBetter,
    {'rate': '해당 등급 번호가 다음 회차에 실제로 나온 비율 (랜덤 6/45=13.3%)'},
  );

  // ── 4. 자리별 패턴 ────────────────────────────────────
  final picks = rpaPositionalAnalysis(inp.trainingData);
  final posTop = rpaPositionalTopNumbers(picks);
  final pvb = wf.positionalVsBase;
  final posValidated = pvb.n >= 100 && pvb.mean > 0 && pvb.t >= 1.96;
  final positional = mk(
    RpaPredictionType.positional,
    {
      'positions': picks.map((p) => {
            'position': p.position + 1,
            'ref': p.refNumber,
            'ranked': p.ranked.map((r) => {
                  'n': r.number,
                  'stat_score': _r(r.score, 3),
                  'engine_rank': rankOf[r.number],
                  'engine_class': classOf[r.number],
                }).toList(),
          }).toList(),
      'top_numbers': posTop,
    },
    {
      'walk_forward': {
        'positional_top6_hits': _r(wf.positionalTop6Hits),
        'base_top6_hits': _r(wf.baseTop6Hits),
        'diff_mean': _r(pvb.mean), 't': _r(pvb.t, 2), 'n': pvb.n,
      },
      'rule': '자리별 1위 6개의 평균 적중이 Number Base 상위 6개보다 유의하게 높을 때(t≥1.96)만 보조 Evidence',
    },
    posValidated ? RpaGate.pass : RpaGate.fail,
    posValidated ? RpaValidation.validated : RpaValidation.notBetter,
    {'stat_score': '자리별 통계 점수(후속40·차이40·끝자리20 순위 정규화). 확률 아님'},
  );

  // ── 5. 대안 조합 ──────────────────────────────────────
  final dirRule = wf.directionRule;
  final dirValidated = dirRule.total >= 300 && dirRule.z >= 1.645;
  final alts = rpaPickDiverse(ranked,
      count: 3, maxOverlap: 4,
      existing: baseSets.map((s) => s.numbers).toList(),
      requireDirs: dirValidated);
  final alternative = mk(
    RpaPredictionType.alternative,
    {
      'sets': alts.map((s) => {
            ...s.toJson(),
            'overlap_with_base': baseSets.map((b) => rpaSetOverlap(b.numbers, s.numbers)).toList(),
          }).toList(),
      'direction_rule_applied': dirValidated,
    },
    {
      'method': '활성 Number 후보 상위 18개의 C(18,6) 전체를 점수합으로 정렬 → 기본 조합과 동일한 조합 제외, '
          '기존 조합과 4개 초과 중복 제외. 난수 없음 (동점은 번호순).',
      'direction_rule_validation': wf.toJson()['direction_rule'],
    },
    // 대안 조합은 Number Base 후보에서만 파생 → Number Base와 동일 Gate
    numberBase.gateStatus,
    dirValidated ? RpaValidation.validated : RpaValidation.notBetter,
    {'set_score': kScoreDefinitions['set_score']},
  );

  // ── 6. Joint Contextual ───────────────────────────────
  final jc = inp.jointContextual;
  final jointLive = inp.jointGate['number_gate'] == RpaGate.pass;
  final joint = mk(
    RpaPredictionType.jointContextual,
    {
      'available': jc != null,
      'predicted_region': jc?['predicted_region'],
      'joint_sets': jc?['joint_sets'] ?? [],
      'source_model_version': jc?['model_version'],
      'source_base_matches_active': jc != null &&
          '${jc['base_sets']}' == '${baseSets.map((s) => s.numbers).toList()}',
      'label': jointLive ? '판매점별 실전 반영' : '연구용 · 실전 미반영',
    },
    inp.jointGate,
    jointLive ? RpaGate.pass : RpaGate.fail,
    jointLive ? RpaValidation.validated : RpaValidation.notBetter,
    {'gate_wf_improvement': 'Joint 번호 조정의 Walk-Forward 적중 개선폭'},
  );

  // ── 7. 충돌 검사 ──────────────────────────────────────
  final conflicts = <Map<String, dynamic>>[];
  final weakSet = {...weak, ...excl};
  void check(String source, String sourceStatus, Iterable<int> nums) {
    for (final n in nums) {
      if (!weakSet.contains(n)) continue;
      final e = evalByN[n];
      conflicts.add({
        'number': n,
        'source': source,
        'source_status': sourceStatus,
        'engine_class': classOf[n],
        'engine_rank': rankOf[n],
        'engine_final_score': e?['final_score'],
        'match_rounds': (e?['evidence'] as Map?)?['match_rounds'],
        'exclusion_live': liveExcluded.contains(n),
        'reason': '$n번: $source에서 추천되지만 엔진 평가는 ${classOf[n]} (${rankOf[n]}위, 점수 ${e?['final_score']}). '
            '${liveExcluded.contains(n) ? '검증된 실전 제외 대상' : '제외는 미검증(연구용)'}',
      });
    }
  }
  for (int i = 0; i < baseSets.length; i++) {
    check('엔진 기본 조합 ${i + 1}', '실전', baseSets[i].numbers);
  }
  for (int i = 0; i < alts.length; i++) {
    check('대안 조합 ${i + 1}', numberBase.isLive ? '실전' : '연구용', alts[i].numbers);
  }
  check('자리별 1위', posValidated ? '보조 Evidence' : '통계 참고', posTop);
  final js = (jc?['joint_sets'] as List?) ?? [];
  for (int i = 0; i < js.length; i++) {
    check('Joint 조합 ${i + 1}', jointLive ? '실전' : '연구용', List<int>.from(js[i] as List));
  }

  return RpaUnifiedBundle(
    [numberBase, hypothesis, exclusion, alternative, positional, joint],
    conflicts,
  );
}

// ══════════════════════════════════════════════════════════
// Joint / Store / Spatial / Temporal Gate (서로 독립)
// ══════════════════════════════════════════════════════════

/// 번호 Joint Gate: 번호 조정의 Walk-Forward 개선폭이 기준 이상이어야 판매점별 실전 번호에 반영.
/// 현재 측정값은 rpa_joint_engine의 오프라인 Walk-Forward(개선 0.00%, n=982)이며
/// 자동 재측정 경로가 없으므로 그 출처를 그대로 기록합니다.
Map<String, dynamic> rpaJointGate({
  required double numberWfImprovement,
  required int numberWfN,
  Map<String, dynamic>? regionJob,
  List<Map<String, dynamic>> storeRows = const [],
  Map<String, double> regionBaseRates = const {},
}) {
  const minImprovement = 0.001;
  const minN = 200;
  final numberPass = numberWfImprovement > minImprovement && numberWfN >= minN;

  // Store Gate: 검증된 판매점 지역 예측 적중률 vs 같은 지역을 무작위로 골랐을 때의 기대 적중률
  int hits = 0, n = 0;
  double expected = 0;
  int spatialHits = 0, spatialN = 0;
  for (final r in storeRows) {
    final hit = r['region_hit'];
    if (hit is! bool) continue;
    n++;
    if (hit) hits++;
    final regions = List<String>.from(r['candidate_regions'] as List? ?? []);
    expected += regions.fold(0.0, (s, g) => s + (regionBaseRates[g] ?? 0));
    final sh = r['spatial_hit'];
    if (sh is bool) {
      spatialN++;
      if (sh) spatialHits++;
    }
  }
  final p0 = n == 0 ? 0.0 : expected / n;
  final storeZ = rpaProportionZ(hits, n, p0.clamp(0.001, 0.999));
  final storePass = n >= 30 && storeZ >= 1.645;

  return {
    'number_gate': numberPass ? RpaGate.pass : RpaGate.fail,
    'number_wf_improvement': numberWfImprovement,
    'number_wf_n': numberWfN,
    'number_gate_source': 'rpa_joint_engine 오프라인 Walk-Forward 측정값 (자동 재측정 미구현)',
    'number_gate_rule': '개선 > ${minImprovement * 100}% 그리고 n ≥ $minN',
    'store_gate': n == 0 ? RpaGate.notEvaluated : (storePass ? RpaGate.pass : RpaGate.fail),
    'store_hits': hits,
    'store_n': n,
    'store_random_expected_rate': _r(p0),
    'store_z': _r(storeZ, 2),
    'spatial_gate': spatialN == 0 ? RpaGate.notEvaluated : RpaGate.fail,
    'spatial_hits': spatialHits,
    'spatial_n': spatialN,
    'spatial_note': spatialN == 0
        ? '검증된 공간 예측 없음'
        : '공간 적중 기준 확률 산출 근거 없음 → 랜덤 대비 검증 불가',
    'temporal_gate': RpaGate.notEvaluated,
    'temporal_note': '구매시각 원천 데이터 없음 (winning_history에는 자동/수동 구분만 존재). '
        '시간대 추천은 만들지 않습니다.',
    'region_job': regionJob == null
        ? null
        : {
            'joint_accuracy': regionJob['joint_accuracy'],
            'store_accuracy': regionJob['store_accuracy'],
            'synergy': regionJob['synergy'],
            'note': 'Joint 지역 후보는 Store 후보의 합집합이라 synergy≥0이 구조적으로 보장됨 → Gate 근거로 사용하지 않음',
          },
  };
}
