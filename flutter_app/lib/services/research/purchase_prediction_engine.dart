// ══════════════════════════════════════════════════════════════
// 구매예측 엔진 (Purchase Prediction) — 기존 Number Engine과 독립
//
// 목적: 다른 구매자들이 선택할 가능성이 높은 번호 조합의 특징을 추정하고,
//       상대적으로 덜 선택될 가능성이 있는 조합을 제시한다.
// 원칙: 모든 조합의 1등 당첨 확률은 동일(1/8,145,060). 당첨 확률 향상을 주장하지 않는다.
//
// 데이터 현황:
//  - 실제 구매 조합별 선택 빈도: 미확보
//  - 회차별 판매액·등수별 당첨자 수: 미확보
//  - 1등 당첨자 자동/수동/반자동 구분: 보유 (winning_history, 265~1244회차, 읽기 전용)
//
// 모델:
//  (1) 휴리스틱 모델 — 일반 지식 기반 가정 가중치. 검증되지 않았음을 명시.
//  (2) 수동비율 실증 모델 — 자동 선택은 균등분포이므로 "당첨 조합 특징 → 1등 당첨자 중
//      수동 비율"의 로지스틱 회귀는 판매량 없이도 인간 선호 방향을 추정할 수 있다.
//      시간 순서 분할(앞 80% 학습 / 뒤 20% 검증), 기준 모델 대비 개선, 부트스트랩 CI로
//      사전 고정된 게이트를 통과할 때만 '부분 실증'으로 승격한다.
// ══════════════════════════════════════════════════════════════

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/lotto_winning_number.dart';
import '../rpa_store_engine.dart' show StoreWinRecord;
import 'prize_stats_service.dart';
import 'research_core.dart';

// pp-0.3: 4등 당첨자 수 기반 번호 인기도 모델(조합 특징 10 + 번호별 효과 45, 릿지)로 순위 결정.
//         시간 순 80/20 분할 검증(H1·H2) 통과 시에만 번호 제공, 실패 시 휴리스틱으로 대체하지 않고 미제공.
const String kPurchaseModelVersion = 'pp-0.3';

/// 휴리스틱 가중치 (로그 인기도 단위). 출처: 복권 번호 선택 편향에 대한 일반 지식
/// (생일·행운 숫자 선호, 극단 조합 회피, 규칙 배열 선호). 실측값이 아닌 가정이다.
const Map<String, double> kHeuristicWeights = {
  'le31': 0.25, 'le12': 0.15, 'lucky': 0.15, 'consec': -0.08, 'same_last': 0.08,
  'odd_imbalance': -0.12, 'sum_dev': -0.10, 'ge40': -0.20, 'decade_conc': 0.10,
  'regular_pattern': 1.20,
};

// 실증 모델 게이트 (평가 시작 전 고정)
const int kGateMinTrain = 2000;
const int kGateMinTest = 500;
const int kBootstrapReps = 200;

class FeatureCoef {
  final String key, name;
  final double coef, se, z, p, pHolm;
  const FeatureCoef(this.key, this.name, this.coef, this.se, this.z, this.p, this.pHolm);
  Map<String, dynamic> toJson() => {'key': key, 'name': name, 'coef': jsonNum(coef), 'se': jsonNum(se),
        'z': jsonNum(z), 'p': jsonNum(p), 'p_holm': jsonNum(pHolm)};
}

class EmpiricalModelReport {
  final bool available;
  final int nTrain, nTest, trainRoundFrom, trainRoundTo, testRoundFrom, testRoundTo;
  final double manualShareTrain, manualShareTest;
  final List<FeatureCoef> coefs;
  final double trainLogLoss, testLogLoss, baselineLogLoss, improvement;
  final List<double> improvementCi; // 부트스트랩 95%
  final bool gatePass;
  final String gateReason;
  final LogisticFit? fit;
  /// 검증 구간 단독 재적합 계수 (특징별 재현 검증용)
  final List<FeatureCoef> testCoefs;
  /// 학습·검증 구간 모두 같은 부호이고 |z|>1.96 인 특징 키
  final List<String> replicatedKeys;
  const EmpiricalModelReport({
    required this.available, this.nTrain = 0, this.nTest = 0,
    this.trainRoundFrom = 0, this.trainRoundTo = 0, this.testRoundFrom = 0, this.testRoundTo = 0,
    this.manualShareTrain = 0, this.manualShareTest = 0, this.coefs = const [],
    this.trainLogLoss = double.nan, this.testLogLoss = double.nan, this.baselineLogLoss = double.nan,
    this.improvement = double.nan, this.improvementCi = const [double.nan, double.nan],
    this.gatePass = false, this.gateReason = '', this.fit,
    this.testCoefs = const [], this.replicatedKeys = const [],
  });
  Map<String, dynamic> toJson() => {
        'available': available, 'n_train': nTrain, 'n_test': nTest,
        'train_rounds': [trainRoundFrom, trainRoundTo], 'test_rounds': [testRoundFrom, testRoundTo],
        'manual_share_train': manualShareTrain, 'manual_share_test': manualShareTest,
        'coefs': coefs.map((c) => c.toJson()).toList(),
        'train_log_loss': jsonNum(trainLogLoss), 'test_log_loss': jsonNum(testLogLoss),
        'baseline_log_loss': jsonNum(baselineLogLoss),
        'improvement': jsonNum(improvement), 'improvement_ci': improvementCi.map(jsonNum).toList(),
        'gate_pass': gatePass, 'gate_reason': gateReason,
        'test_coefs': testCoefs.map((c) => c.toJson()).toList(), 'replicated_keys': replicatedKeys,
      };
}

class PurchaseRecommendation {
  final List<int> numbers;
  final double heuristicScore;      // 로그 인기도 (0 = 평균적 조합)
  final double heuristicIndex;      // exp(score): 1.0 = 평균, <1 덜 선택 추정
  final double? empiricalManualOdds; // 실증 모델 수동 오즈비 (평균 대비), 없으면 null
  final double? volumeRatio;         // 판매량 보정 모델: 균등 대비 상대 인기도 (1.0 = 균등), 없으면 null
  final double? expectedCoWinners;   // 최근 판매량 기준 "같은 번호로 1등 맞힐 다른 사람" 기대 수
  final double? popularityIndex;     // 검증된 번호 인기도 모델: 평균 조합 대비 판매 비율 (1.0 = 평균)
  final bool extrapolated;           // 검증 구간 예측 범위를 벗어난 외삽 여부
  final List<String> reasons;
  final ComboFeatures features;
  const PurchaseRecommendation({
    required this.numbers, required this.heuristicScore, required this.heuristicIndex,
    required this.empiricalManualOdds, this.volumeRatio, this.expectedCoWinners,
    this.popularityIndex, this.extrapolated = false,
    required this.reasons, required this.features,
  });
  Map<String, dynamic> toJson() => {
        'numbers': numbers, 'heuristic_score': heuristicScore, 'heuristic_index': heuristicIndex,
        'empirical_manual_odds': empiricalManualOdds, 'volume_ratio': jsonNum(volumeRatio ?? double.nan),
        'expected_co_winners': jsonNum(expectedCoWinners ?? double.nan),
        'popularity_index': jsonNum(popularityIndex ?? double.nan), 'extrapolated': extrapolated,
        'reasons': reasons, 'features': features.toJson(),
      };
}

/// 판매량 보정 포아송 모델 보고 (y = 1등 당첨자 수, offset = log(판매 게임수/C))
class VolumeModelReport {
  final bool available;
  final int nTrain, nTest, trainRoundFrom, trainRoundTo, testRoundFrom, testRoundTo;
  final List<FeatureCoef> coefs;
  final List<FeatureCoef> testCoefs;
  final List<String> replicatedKeys;
  final double testDeviance, baselineDeviance, improvement; // 검증 이탈도 감소 (양수 = 설명력)
  final List<double> improvementCi;
  final double meanRatio;      // 학습 구간 평균 (관측/기대) — 전체 인기도 수준(≈1)
  final bool gatePass;
  final String gateReason;
  final PoissonFit? fit;
  const VolumeModelReport({
    required this.available, this.nTrain = 0, this.nTest = 0,
    this.trainRoundFrom = 0, this.trainRoundTo = 0, this.testRoundFrom = 0, this.testRoundTo = 0,
    this.coefs = const [], this.testCoefs = const [], this.replicatedKeys = const [],
    this.testDeviance = double.nan, this.baselineDeviance = double.nan, this.improvement = double.nan,
    this.improvementCi = const [double.nan, double.nan], this.meanRatio = double.nan,
    this.gatePass = false, this.gateReason = '', this.fit,
  });
  Map<String, dynamic> toJson() => {
        'available': available, 'n_train': nTrain, 'n_test': nTest,
        'train_rounds': [trainRoundFrom, trainRoundTo], 'test_rounds': [testRoundFrom, testRoundTo],
        'coefs': coefs.map((c) => c.toJson()).toList(), 'test_coefs': testCoefs.map((c) => c.toJson()).toList(),
        'replicated_keys': replicatedKeys, 'test_deviance': jsonNum(testDeviance),
        'baseline_deviance': jsonNum(baselineDeviance), 'improvement': jsonNum(improvement),
        'improvement_ci': improvementCi.map(jsonNum).toList(), 'mean_ratio': jsonNum(meanRatio),
        'gate_pass': gatePass, 'gate_reason': gateReason,
      };
}

class PurchaseModelReport {
  final int trainingEnd;
  final int targetRound;
  final EmpiricalModelReport empirical;
  final VolumeModelReport volume;
  final PopularityModelReport popularity;
  final String validationStatus; // '휴리스틱·미검증' | '부분 실증(수동비율 모델)' | '실증(판매량 보정 모델)'
  final String rankingSource;    // 'heuristic' | 'empirical' | 'volume'
  final List<Map<String, dynamic>> featureInsights; // {name, direction, source, strength}
  final List<PurchaseRecommendation> recommendations;
  final List<String> dataGaps;
  final double candidateMedianScore; // 무작위 후보 휴리스틱 점수 중앙값 (상대 지표 기준)
  final int prizeStatsRounds;        // 사용한 판매액 데이터 회차 수
  bool get validated => popularity.gatePass && recommendations.isNotEmpty;

  const PurchaseModelReport({
    required this.trainingEnd, required this.targetRound, required this.empirical, required this.volume,
    required this.popularity,
    required this.validationStatus, required this.rankingSource, required this.featureInsights,
    required this.recommendations, required this.dataGaps, required this.candidateMedianScore,
    required this.prizeStatsRounds,
  });
  Map<String, dynamic> toJson() => {
        'training_end': trainingEnd, 'target_round': targetRound, 'empirical': empirical.toJson(),
        'volume': volume.toJson(), 'popularity': popularity.toJson(), 'prize_stats_rounds': prizeStatsRounds,
        'validation_status': validationStatus, 'ranking_source': rankingSource,
        'feature_insights': featureInsights,
        'recommendations': recommendations.map((r) => r.toJson()).toList(),
        'data_gaps': dataGaps, 'candidate_median_score': candidateMedianScore,
      };
}

// 판매량 보정 모델 게이트 (평가 시작 전 고정)
const int kVolumeGateMinTrainRounds = 600;
const int kVolumeGateMinTestRounds = 150;

// 번호 인기도 모델 게이트 (평가 시작 전 고정, 2026-10-11)
//  H1: 검증 구간에서 예측 log(4등 비율) 과 실제의 상관 > 0 이고 p < 0.01
//  H2: 검증 구간 1등 당첨자 수 포아송 GLM(offset = log 기대 1등)의 인기도 계수 > 0 이고 p < 0.05
const int kPopGateMinTrainRounds = 400;
const int kPopGateMinTestRounds = 100;
const double kPopRidgeLambda = 5.0;

/// 번호 인기도 모델 (y = log(4등 관측/기대), x = 조합 특징 10 + 번호 1~45 지시변수)
class PopularityModelReport {
  final bool available;
  final bool gatePass;
  final String gateReason;
  final int nTrain, nTest, trainFrom, trainTo, testFrom, testTo;
  final double h1Corr, h1P, h1R2;
  final double h2Coef, h2P;
  final double lowCoWinRatio, highCoWinRatio; // 검증 구간 인기도 하위·상위 40% 회차의 1등 관측/기대
  final double testPredMin, testPredMax;       // 검증된 예측값 범위 (외삽 판단용)
  final List<double>? coef;                    // 전체 데이터 재적합 계수 (실전 점수용)
  final List<int> leastPopularNumbers, mostPopularNumbers;
  const PopularityModelReport({
    required this.available, this.gatePass = false, this.gateReason = '',
    this.nTrain = 0, this.nTest = 0, this.trainFrom = 0, this.trainTo = 0, this.testFrom = 0, this.testTo = 0,
    this.h1Corr = double.nan, this.h1P = double.nan, this.h1R2 = double.nan, this.h2Coef = double.nan, this.h2P = double.nan,
    this.lowCoWinRatio = double.nan, this.highCoWinRatio = double.nan,
    this.testPredMin = double.nan, this.testPredMax = double.nan, this.coef,
    this.leastPopularNumbers = const [], this.mostPopularNumbers = const [],
  });
  Map<String, dynamic> toJson() => {
        'available': available, 'gate_pass': gatePass, 'gate_reason': gateReason,
        'n_train': nTrain, 'n_test': nTest, 'train_rounds': [trainFrom, trainTo], 'test_rounds': [testFrom, testTo],
        'h1_corr': jsonNum(h1Corr), 'h1_p': jsonNum(h1P), 'h1_r2': jsonNum(h1R2), 'h2_coef': jsonNum(h2Coef), 'h2_p': jsonNum(h2P),
        'low_cowin_ratio': jsonNum(lowCoWinRatio), 'high_cowin_ratio': jsonNum(highCoWinRatio),
        'test_pred_range': [jsonNum(testPredMin), jsonNum(testPredMax)],
        'least_popular_numbers': leastPopularNumbers, 'most_popular_numbers': mostPopularNumbers,
      };
}

List<double> popularityVector(List<int> numbers) {
  final v = ComboFeatures.of(numbers).toVector();
  final d = List<double>.filled(45, 0);
  for (final n in numbers) { d[n - 1] = 1; }
  return [...v, ...d];
}

class PurchasePredictionEngine {
  PurchasePredictionEngine._();
  static final instance = PurchasePredictionEngine._();
  final _db = Supabase.instance.client;

  final Map<int, PurchaseModelReport> _cache = {};

  static List<String> dataGapsFor(int prizeRounds) => [
    '실제 구매 조합별 선택 빈도: 미확보 → 개별 조합의 절대 인기도는 직접 관측 불가(당첨 조합만 관측)',
    prizeRounds > 0
        ? '회차별 판매액·등수별 당첨자 수: 보유 ${prizeRounds}회차 (research_prize_stats) → 판매량 보정 모델 사용'
        : '회차별 판매액·등수별 당첨자 수: 미확보 → 판매량 보정 불가 (research_v3_prize_stats.sql 적용·수집 필요)',
    '1등 당첨자 자동/수동 구분: 보유(265~1244회차) → 선호 "방향" 추정',
  ];

  // ── 판매량 보정 실증 모델: 1등 당첨자 수 포아송 회귀 ─────────────
  /// y = 회차 1등 당첨자 수, offset = log(판매 게임수 / 8,145,060). 균등 선택이면 β=0.
  /// 특징 계수 β>0 → 그 특징을 가진 조합이 더 많이 선택됨(당첨 시 분배↑).
  VolumeModelReport fitVolume(List<LottoWinningNumber> allData, Map<int, PrizeStats> stats, int trainingEnd) {
    final X = <List<double>>[], y = <double>[], off = <double>[];
    final rounds = <int>[];
    final sorted = allData.where((d) => d.round <= trainingEnd).toList()..sort((a, b) => a.round.compareTo(b.round));
    for (final d in sorted) {
      final s = stats[d.round];
      if (s == null || s.rank1Winners == null || s.expectedRank1 == null || s.expectedRank1! <= 0) continue;
      X.add(ComboFeatures.of(d.numbers).toVector()..add(d.round / 1000.0 - 0.75));
      y.add(s.rank1Winners!.toDouble());
      off.add(log(s.expectedRank1!));
      rounds.add(d.round);
    }
    if (rounds.length < kVolumeGateMinTrainRounds + kVolumeGateMinTestRounds) {
      return VolumeModelReport(available: rounds.isNotEmpty, nTrain: rounds.length,
          gateReason: rounds.isEmpty ? '판매액 데이터 없음' : '표본 부족 (${rounds.length}회차, 최소 ${kVolumeGateMinTrainRounds + kVolumeGateMinTestRounds})');
    }
    final split = rounds[(rounds.length * 0.8).floor()];
    final trX = <List<double>>[], teX = <List<double>>[];
    final trY = <double>[], teY = <double>[], trO = <double>[], teO = <double>[];
    for (int i = 0; i < rounds.length; i++) {
      if (rounds[i] < split) { trX.add(X[i]); trY.add(y[i]); trO.add(off[i]); }
      else { teX.add(X[i]); teY.add(y[i]); teO.add(off[i]); }
    }
    final fit = fitPoisson(trX, trY, trO);
    double sy = 0, so = 0;
    for (int i = 0; i < trY.length; i++) { sy += trY[i]; so += exp(trO[i]); }
    final ratio = so > 0 ? sy / so : double.nan;
    final testDev = poissonDeviance(fit, teX, teY, teO);
    final baseDev = poissonBaselineDeviance(ratio, teY, teO);
    final improvement = baseDev - testDev;
    // 부트스트랩: 검증 회차 재표집
    final rng = SeededRandom(20261010);
    final boots = <double>[];
    for (int b = 0; b < kBootstrapReps; b++) {
      final bx = <List<double>>[], by = <double>[], bo = <double>[];
      for (int k = 0; k < teX.length; k++) {
        final i = rng.nextInt(teX.length); bx.add(teX[i]); by.add(teY[i]); bo.add(teO[i]);
      }
      boots.add(poissonBaselineDeviance(ratio, by, bo) - poissonDeviance(fit, bx, by, bo));
    }
    boots.sort();
    final ci = [boots[(boots.length * 0.025).floor()], boots[(boots.length * 0.975).floor() - 1]];

    final names = [...kFeatureNames, '시대 추세(회차/1000)'];
    final keys = [...kFeatureKeys, 'era'];
    List<FeatureCoef> coefsOf(PoissonFit f) {
      final ps = <double>[];
      for (int j = 0; j < keys.length; j++) {
        final z = f.se[j + 1] > 0 ? f.coef[j + 1] / f.se[j + 1] : 0.0;
        ps.add(twoSidedP(z));
      }
      final adj = holmAdjust(ps);
      return List.generate(keys.length, (j) {
        final z = f.se[j + 1] > 0 ? f.coef[j + 1] / f.se[j + 1] : 0.0;
        return FeatureCoef(keys[j], names[j], f.coef[j + 1], f.se[j + 1], z, ps[j], adj[j]);
      });
    }
    final coefs = coefsOf(fit);
    final testFit = fitPoisson(teX, teY, teO);
    final testCoefs = coefsOf(testFit);
    final replicated = <String>[];
    for (int j = 0; j < keys.length; j++) {
      if (keys[j] == 'era') continue;
      if (coefs[j].coef.sign == testCoefs[j].coef.sign && coefs[j].z.abs() > 1.96 && testCoefs[j].z.abs() > 1.96) replicated.add(keys[j]);
    }
    final gate = trX.length >= kVolumeGateMinTrainRounds && teX.length >= kVolumeGateMinTestRounds && improvement > 0 && ci[0] > 0;
    final reason = gate
        ? '학습 ${trX.length}회차·검증 ${teX.length}회차, 검증 이탈도 감소 ${improvement.toStringAsFixed(1)} (95% CI ${ci[0].toStringAsFixed(1)}~${ci[1].toStringAsFixed(1)}) > 0'
        : '게이트 미통과: 이탈도 감소 ${improvement.toStringAsFixed(1)}, CI 하한 ${ci[0].toStringAsFixed(1)} (조건: 학습≥$kVolumeGateMinTrainRounds, 검증≥$kVolumeGateMinTestRounds, 감소>0, CI 하한>0)';
    return VolumeModelReport(
      available: true, nTrain: trX.length, nTest: teX.length,
      trainRoundFrom: rounds.first, trainRoundTo: split - 1, testRoundFrom: split, testRoundTo: rounds.last,
      coefs: coefs, testCoefs: testCoefs, replicatedKeys: replicated,
      testDeviance: testDev, baselineDeviance: baseDev, improvement: improvement, improvementCi: ci,
      meanRatio: ratio, gatePass: gate, gateReason: reason, fit: fit,
    );
  }

  // ── 검증된 번호 인기도 모델 (4등 당첨자 수 기반) ─────────────────
  /// 4등(4개 일치) 당첨자는 회당 약 18만 명이라 "당첨번호를 사람들이 얼마나 샀는가"를 잡음 거의 없이 보여준다.
  /// 시간 순 80/20 분할로 H1(4등 인기도 예측)·H2(1등 공동 당첨자 예측)를 검증하고, 통과하면 전체로 재적합.
  PopularityModelReport fitPopularity(List<LottoWinningNumber> allData, Map<int, PrizeStats> stats, int trainingEnd) {
    final rows = <({int round, List<double> x, double y4, double w1, double e1})>[];
    final sorted = allData.where((d) => d.round <= trainingEnd).toList()..sort((a, b) => a.round.compareTo(b.round));
    for (final d in sorted) {
      final s = stats[d.round];
      final r4 = s?.rankWinners[4];
      final games = s?.gamesSold;
      final r1 = s?.rank1Winners;
      if (s == null || r4 == null || r4 <= 0 || games == null || games <= 0 || r1 == null) continue;
      final e4 = games * 11115 / kLottoTotalCombos;
      rows.add((round: d.round, x: popularityVector(d.numbers), y4: log(r4 / e4), w1: r1.toDouble(), e1: games / kLottoTotalCombos));
    }
    if (rows.length < kPopGateMinTrainRounds + kPopGateMinTestRounds) {
      return PopularityModelReport(available: rows.isNotEmpty,
          gateReason: rows.isEmpty ? '판매액·등수별 당첨자 수 데이터 없음' : '표본 부족 (${rows.length}회차)');
    }
    final split = (rows.length * 0.8).floor();
    final tr = rows.sublist(0, split), te = rows.sublist(split);
    final coefTr = ridgeSolve(tr.map((r) => r.x).toList(), tr.map((r) => r.y4).toList(), kPopRidgeLambda);
    if (coefTr == null) return const PopularityModelReport(available: true, gateReason: '모델 적합 실패');
    final predTe = te.map((r) => ridgePredict(coefTr, r.x)).toList();
    final yTe = te.map((r) => r.y4).toList();
    final h1 = pearsonWithP(predTe, yTe);
    final meanTr = tr.map((r) => r.y4).reduce((a, b) => a + b) / tr.length;
    double ss = 0, st = 0;
    for (int i = 0; i < te.length; i++) { ss += pow(yTe[i] - predTe[i], 2); st += pow(yTe[i] - meanTr, 2); }
    final h2 = poissonSlope(te.map((r) => r.w1).toList(), predTe, te.map((r) => log(r.e1)).toList());
    final sortedPred = [...predTe]..sort();
    final qLo = sortedPred[(sortedPred.length * 0.4).floor()], qHi = sortedPred[(sortedPred.length * 0.6).floor()];
    double lw = 0, le = 0, hw = 0, he = 0;
    for (int i = 0; i < te.length; i++) {
      if (predTe[i] <= qLo) { lw += te[i].w1; le += te[i].e1; }
      if (predTe[i] >= qHi) { hw += te[i].w1; he += te[i].e1; }
    }
    final pass = h1[0] > 0 && h1[1] < 0.01 && h2[0] > 0 && h2[2] < 0.05;
    final reason = '검증 ${te.first.round}~${te.last.round}회(${te.length}회차): 4등 인기도 예측 상관 ${h1[0].toStringAsFixed(2)} (p=${h1[1] < 1e-4 ? '<0.0001' : h1[1].toStringAsFixed(4)}), '
        '1등 공동당첨 계수 ${h2[0].toStringAsFixed(2)} (p=${h2[2].toStringAsFixed(4)})'
        '${pass ? ' → 통과' : ' → 미통과 (기준: 상관 p<0.01, 1등 계수>0·p<0.05)'}';
    // 실전 점수용: 전체 데이터로 재적합
    final coefAll = pass ? ridgeSolve(rows.map((r) => r.x).toList(), rows.map((r) => r.y4).toList(), kPopRidgeLambda) : null;
    final numEff = coefAll == null ? <MapEntry<int, double>>[] :
        [for (int n = 1; n <= 45; n++) MapEntry(n, coefAll[1 + kFeatureKeys.length + n - 1])];
    numEff.sort((a, b) => a.value.compareTo(b.value));
    return PopularityModelReport(
      available: true, gatePass: pass, gateReason: reason,
      nTrain: tr.length, nTest: te.length, trainFrom: tr.first.round, trainTo: tr.last.round, testFrom: te.first.round, testTo: te.last.round,
      h1Corr: h1[0], h1P: h1[1], h1R2: st > 0 ? 1 - ss / st : double.nan, h2Coef: h2[0], h2P: h2[2],
      lowCoWinRatio: le > 0 ? lw / le : double.nan, highCoWinRatio: he > 0 ? hw / he : double.nan,
      testPredMin: sortedPred.first, testPredMax: sortedPred.last, coef: coefAll,
      leastPopularNumbers: numEff.take(8).map((e) => e.key).toList(),
      mostPopularNumbers: numEff.reversed.take(8).map((e) => e.key).toList(),
    );
  }

  double _volumeScore(PoissonFit fit, ComboFeatures f) {
    final x = f.toVector()..add(0.0);
    double z = 0;
    for (int j = 0; j < x.length; j++) { z += fit.coef[j + 1] * x[j]; }
    return z; // log 상대 인기도 (절편·시대 제외)
  }

  // ── 휴리스틱 점수 ────────────────────────────────────────────
  static double heuristicScore(ComboFeatures f) {
    final v = f.toVector();
    double s = 0;
    for (int i = 0; i < kFeatureKeys.length; i++) {
      s += (kHeuristicWeights[kFeatureKeys[i]] ?? 0) * v[i];
    }
    return s;
  }

  // ── 실증 모델: 수동 비율 로지스틱 회귀 ───────────────────────
  EmpiricalModelReport fitEmpirical(List<LottoWinningNumber> allData, List<StoreWinRecord> history, int trainingEnd) {
    final numbersByRound = {for (final d in allData) d.round: d};
    final rows = <MapEntry<int, List<double>>>[]; // (y, x)
    final rounds = <int>[];
    for (final h in history) {
      if (h.round > trainingEnd) continue;
      final d = numbersByRound[h.round];
      final m = (h.purchaseMethod ?? '').trim();
      if (d == null || m.isEmpty) continue;
      final y = m == '자동' ? 0 : 1; // 수동·반자동 = 사람이 고른 번호
      final x = ComboFeatures.of(d.numbers).toVector()..add(h.round / 1000.0 - 0.75); // 시대 추세 공변량
      rows.add(MapEntry(y, x));
      rounds.add(h.round);
    }
    if (rows.length < kGateMinTrain + kGateMinTest) {
      return EmpiricalModelReport(available: rows.isNotEmpty, nTrain: rows.length,
          gateReason: '표본 부족 (${rows.length}건, 최소 ${kGateMinTrain + kGateMinTest}건)');
    }
    final distinct = rounds.toSet().toList()..sort();
    final splitRound = distinct[(distinct.length * 0.8).floor()];
    final trainX = <List<double>>[], testX = <List<double>>[];
    final trainY = <int>[], testY = <int>[];
    final testRounds = <int>[];
    for (int i = 0; i < rows.length; i++) {
      if (rounds[i] < splitRound) { trainX.add(rows[i].value); trainY.add(rows[i].key); }
      else { testX.add(rows[i].value); testY.add(rows[i].key); testRounds.add(rounds[i]); }
    }
    final fit = fitLogistic(trainX, trainY);
    final trainMean = trainY.reduce((a, b) => a + b) / trainY.length;
    final testLoss = logLoss(fit, testX, testY);
    final baseLoss = baselineLogLoss(trainMean, testY);
    final improvement = baseLoss - testLoss;

    // 부트스트랩: 검증 회차 단위 재표집
    final byRoundIdx = <int, List<int>>{};
    for (int i = 0; i < testRounds.length; i++) { byRoundIdx.putIfAbsent(testRounds[i], () => []).add(i); }
    final rKeys = byRoundIdx.keys.toList();
    final rng = SeededRandom(20261009);
    final boots = <double>[];
    for (int b = 0; b < kBootstrapReps; b++) {
      final bx = <List<double>>[]; final by = <int>[];
      for (int k = 0; k < rKeys.length; k++) {
        for (final i in byRoundIdx[rKeys[rng.nextInt(rKeys.length)]]!) { bx.add(testX[i]); by.add(testY[i]); }
      }
      boots.add(baselineLogLoss(trainMean, by) - logLoss(fit, bx, by));
    }
    boots.sort();
    final ci = [boots[(boots.length * 0.025).floor()], boots[(boots.length * 0.975).floor() - 1]];

    final names = [...kFeatureNames, '시대 추세(회차/1000)'];
    final keys = [...kFeatureKeys, 'era'];
    final ps = <double>[];
    for (int j = 0; j < keys.length; j++) {
      final z = fit.se[j + 1] > 0 ? fit.coef[j + 1] / fit.se[j + 1] : 0.0;
      ps.add(twoSidedP(z));
    }
    final adj = holmAdjust(ps);
    final coefs = List.generate(keys.length, (j) {
      final z = fit.se[j + 1] > 0 ? fit.coef[j + 1] / fit.se[j + 1] : 0.0;
      return FeatureCoef(keys[j], names[j], fit.coef[j + 1], fit.se[j + 1], z, ps[j], adj[j]);
    });

    // 특징별 재현 검증: 검증 구간만으로 재적합 → 학습 계수와 부호 일치 & 양쪽 |z|>1.96
    final testFit = fitLogistic(testX, testY);
    final testPs = <double>[];
    for (int j = 0; j < keys.length; j++) {
      final z = testFit.se[j + 1] > 0 ? testFit.coef[j + 1] / testFit.se[j + 1] : 0.0;
      testPs.add(twoSidedP(z));
    }
    final testAdj = holmAdjust(testPs);
    final testCoefs = List.generate(keys.length, (j) {
      final z = testFit.se[j + 1] > 0 ? testFit.coef[j + 1] / testFit.se[j + 1] : 0.0;
      return FeatureCoef(keys[j], names[j], testFit.coef[j + 1], testFit.se[j + 1], z, testPs[j], testAdj[j]);
    });
    final replicated = <String>[];
    for (int j = 0; j < keys.length; j++) {
      if (keys[j] == 'era') continue;
      final a = coefs[j], b = testCoefs[j];
      if (a.coef.sign == b.coef.sign && a.z.abs() > 1.96 && b.z.abs() > 1.96) replicated.add(keys[j]);
    }

    final gate = trainX.length >= kGateMinTrain && testX.length >= kGateMinTest && improvement > 0 && ci[0] > 0;
    final reason = gate
        ? '학습 ${trainX.length}건·검증 ${testX.length}건, 검증 로그손실 개선 ${improvement.toStringAsFixed(4)} (95% CI ${ci[0].toStringAsFixed(4)}~${ci[1].toStringAsFixed(4)}) > 0'
        : '게이트 미통과: 개선 ${improvement.toStringAsFixed(4)}, CI 하한 ${ci[0].toStringAsFixed(4)} (조건: 학습≥$kGateMinTrain, 검증≥$kGateMinTest, 개선>0, CI 하한>0)';
    return EmpiricalModelReport(
      available: true, nTrain: trainX.length, nTest: testX.length,
      trainRoundFrom: distinct.first, trainRoundTo: splitRound - 1, testRoundFrom: splitRound, testRoundTo: distinct.last,
      manualShareTrain: trainMean, manualShareTest: testY.reduce((a, b) => a + b) / testY.length,
      coefs: coefs, trainLogLoss: fit.trainLogLoss, testLogLoss: testLoss, baselineLogLoss: baseLoss,
      improvement: improvement, improvementCi: ci, gatePass: gate, gateReason: reason, fit: fit,
      testCoefs: testCoefs, replicatedKeys: replicated,
    );
  }

  // ── 추천 생성 (결정적: 같은 회차·같은 데이터 → 같은 결과) ──────
  PurchaseModelReport buildReport({
    required List<LottoWinningNumber> allData,
    required List<StoreWinRecord> history,
    required int targetRound,
    int? trainingEnd,
    Map<int, PrizeStats> prizeStats = const {},
  }) {
    final te = trainingEnd ?? allData.map((d) => d.round).fold<int>(0, (a, b) => a > b ? a : b);
    final cached = _cache[targetRound];
    if (cached != null && cached.trainingEnd == te && cached.prizeStatsRounds == prizeStats.length) return cached;

    final emp = fitEmpirical(allData, history, te);
    final useEmp = emp.gatePass && emp.fit != null;
    final vol = fitVolume(allData, prizeStats, te);
    final useVol = vol.gatePass && vol.fit != null;
    final pop = fitPopularity(allData, prizeStats, te);
    final usePop = pop.gatePass && pop.coef != null;
    // 최근 판매 게임 수 (기대 동일번호 당첨자 계산용)
    final recentStats = prizeStats.values.where((s) => s.round <= te && s.gamesSold != null).toList()
      ..sort((a, b) => b.round.compareTo(a.round));
    final recentGames = recentStats.isNotEmpty ? recentStats.first.gamesSold! : null;

    // 후보 생성
    final rng = SeededRandom(targetRound * 7919 + 101);
    const candN = 20000;
    final cands = <MapEntry<List<int>, double>>[];
    final scores = <double>[];
    final volScores = <double>[];
    final popScores = <double>[];
    for (int i = 0; i < candN; i++) {
      final c = rng.combo();
      final f = ComboFeatures.of(c);
      if (f.arithmetic || f.allMult5 || f.maxRun >= 4) continue; // 규칙 배열은 제외
      final h = heuristicScore(f);
      scores.add(h);
      final v = useVol ? _volumeScore(vol.fit!, f) : 0.0;
      if (useVol) volScores.add(v);
      final pz = usePop ? ridgePredict(pop.coef!, popularityVector(c)) : 0.0;
      if (usePop) popScores.add(pz);
      // 순위는 검증 통과한 번호 인기도 모델만 사용. 미통과면 추천 번호를 만들지 않는다(휴리스틱 대체 금지).
      cands.add(MapEntry(c, pz));
    }
    scores.sort();
    volScores.sort();
    popScores.sort();
    final median = scores.isEmpty ? 0.0 : scores[scores.length ~/ 2];
    final volMedian = volScores.isEmpty ? 0.0 : volScores[volScores.length ~/ 2];
    final popMedian = popScores.isEmpty ? 0.0 : popScores[popScores.length ~/ 2];
    cands.sort((a, b) {
      final c = a.value.compareTo(b.value);
      if (c != 0) return c;
      for (int i = 0; i < 6; i++) { final d = a.key[i].compareTo(b.key[i]); if (d != 0) return d; }
      return 0;
    });

    final picked = <List<int>>[];
    if (usePop) {
      for (final c in cands) {
        if (picked.length >= 5) break;
        final s = c.key.toSet();
        if (picked.every((p) => p.where(s.contains).length <= 2)) picked.add(c.key);
      }
    }
    final recs = picked.map((c) {
      final f = ComboFeatures.of(c);
      final h = heuristicScore(f);
      final volRatio = useVol ? exp(_volumeScore(vol.fit!, f) - volMedian) * (vol.meanRatio.isNaN ? 1 : vol.meanRatio) : null;
      final pz = ridgePredict(pop.coef!, popularityVector(c));
      final popIdx = exp(pz - popMedian);
      return PurchaseRecommendation(
        numbers: c, heuristicScore: h, heuristicIndex: exp(h - median),
        empiricalManualOdds: useEmp ? exp(_empiricalScore(emp.fit!, f)) : null,
        volumeRatio: volRatio,
        expectedCoWinners: recentGames != null ? recentGames / kLottoTotalCombos * popIdx : null,
        popularityIndex: popIdx,
        extrapolated: pz < pop.testPredMin,
        reasons: _popReasons(c, pop), features: f,
      );
    }).toList();

    final insights = <Map<String, dynamic>>[];
    for (int i = 0; i < kFeatureKeys.length; i++) {
      final w = kHeuristicWeights[kFeatureKeys[i]] ?? 0;
      insights.add({'name': kFeatureNames[i], 'direction': w > 0 ? '인기↑ 추정' : '인기↓ 추정',
        'source': '휴리스틱(가정)', 'strength': w.abs()});
    }
    if (emp.available) {
      for (final c in emp.coefs.where((c) => c.key != 'era')) {
        final rep = emp.replicatedKeys.contains(c.key);
        insights.add({'name': c.name, 'direction': c.coef > 0 ? '수동 선택↑' : '수동 선택↓',
          'source': rep ? '실증·검증구간 재현' : c.pHolm < 0.05 ? '실증(Holm p<0.05, 재현 미확인)' : '실증(유의하지 않음)',
          'strength': c.coef.abs(), 'coef': c.coef, 'se': c.se, 'p_holm': c.pHolm, 'replicated': rep});
      }
    }

    if (vol.available) {
      for (final c in vol.coefs.where((c) => c.key != 'era')) {
        final rep = vol.replicatedKeys.contains(c.key);
        insights.add({'name': c.name, 'direction': c.coef > 0 ? '선택↑(1등 당첨자↑)' : '선택↓(1등 당첨자↓)',
          'source': rep ? '판매량 보정·검증구간 재현' : c.pHolm < 0.05 ? '판매량 보정(Holm p<0.05, 재현 미확인)' : '판매량 보정(유의하지 않음)',
          'strength': c.coef.abs(), 'coef': c.coef, 'se': c.se, 'p_holm': c.pHolm, 'replicated': rep});
      }
    }

    final report = PurchaseModelReport(
      trainingEnd: te, targetRound: targetRound, empirical: emp, volume: vol, popularity: pop,
      validationStatus: usePop
          ? '검증 통과 — 번호 인기도 모델 (${pop.testFrom}~${pop.testTo}회 순방향 검증)'
          : '검증 실패 — 구매예측 번호 미제공 (${pop.gateReason})',
      rankingSource: usePop ? 'popularity' : 'none',
      featureInsights: insights, recommendations: recs, dataGaps: dataGapsFor(prizeStats.length),
      candidateMedianScore: median, prizeStatsRounds: prizeStats.length,
    );
    _cache[targetRound] = report;
    _persist(report);
    return report;
  }

  /// 실증 점수: 시대 공변량은 0(기준 시점)으로 고정해 조합 특징만 반영
  double _empiricalScore(LogisticFit fit, ComboFeatures f) {
    final x = f.toVector()..add(0.0);
    double z = 0;
    for (int j = 0; j < x.length; j++) { z += fit.coef[j + 1] * x[j]; }
    return z;
  }

  List<String> _popReasons(List<int> c, PopularityModelReport pop) {
    final least = pop.leastPopularNumbers.toSet(), most = pop.mostPopularNumbers.toSet();
    final r = <String>[];
    final lp = c.where(least.contains).toList();
    final mp = c.where(most.contains).toList();
    if (lp.isNotEmpty) r.add('실제로 적게 팔리는 번호 ${lp.join(', ')} 포함');
    if (mp.isEmpty) r.add('많이 팔리는 번호(${pop.mostPopularNumbers.take(6).join('·')} 등) 없음');
    final f = ComboFeatures.of(c);
    if (f.cntLe31 <= 2) r.add('생일 범위(1~31) 번호 ${f.cntLe31}개');
    if (f.cntGe40 >= 2) r.add('40 이상 번호 ${f.cntGe40}개');
    return r;
  }

  Future<void> _persist(PurchaseModelReport r) async {
    try {
      await _db.from('research_results').upsert({
        'research_type': 'purchase_model', 'model_version': kPurchaseModelVersion,
        'training_end_round': r.trainingEnd, 'target_round': r.targetRound, 'payload': r.toJson(),
      }, onConflict: 'research_type,model_version,training_end_round,target_round');
    } catch (e) {
      debugPrint('[Purchase] persist skipped: $e');
    }
  }

  /// DB에 저장된 같은 회차 결과가 있으면 그 추천 세트를 반환 (기기 간 일관성)
  Future<List<List<int>>?> loadStoredSets(int targetRound) async {
    try {
      final r = await _db.from('research_results')
          .select('payload,training_end_round')
          .eq('research_type', 'purchase_model').eq('model_version', kPurchaseModelVersion)
          .eq('target_round', targetRound).order('training_end_round', ascending: false).limit(1);
      final list = List<Map<String, dynamic>>.from(r as List);
      if (list.isEmpty) return null;
      final recs = (list.first['payload'] as Map)['recommendations'] as List? ?? [];
      return recs.map<List<int>>((x) => ((x as Map)['numbers'] as List).map<int>((n) => (n as num).toInt()).toList()).toList();
    } catch (_) {
      return null;
    }
  }
}
