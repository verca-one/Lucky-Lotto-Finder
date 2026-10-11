// 연구 코어 수치 검증 (dart run tool/verify_research_core.dart)
// ignore_for_file: avoid_print
import 'dart:math';

import '../lib/services/research/research_core.dart';

void check(String name, bool ok, [String detail = '']) {
  print('${ok ? 'PASS' : 'FAIL'}  $name ${detail.isEmpty ? '' : '— $detail'}');
}

void main() {
  // 1. 조합론 상수
  final sumP = kMatchProb.values.reduce((a, b) => a + b);
  check('kMatchProb 합=1', (sumP - 1).abs() < 1e-9, sumP.toStringAsFixed(9));
  double mean = 0;
  kMatchProb.forEach((k, p) => mean += k * p);
  check('기대 일치 0.8', (mean - 0.8).abs() < 1e-9, mean.toStringAsFixed(6));
  check('binom(45,6)=8145060', binom(45, 6) == kLottoTotalCombos, '${binom(45, 6)}');

  // 2. 정규/카이제곱
  check('normalCdf(1.96)≈0.975', (normalCdf(1.96) - 0.975).abs() < 1e-3, normalCdf(1.96).toStringAsFixed(5));
  check('chiSquareSf(44,44)≈0.47', (chiSquareSf(44, 44) - 0.4713).abs() < 0.01, chiSquareSf(44, 44).toStringAsFixed(4));
  check('chiSquareSf(70,44)≈0.0074', (chiSquareSf(70, 44) - 0.0074).abs() < 0.002, chiSquareSf(70, 44).toStringAsFixed(4));

  // 3. Holm
  final adj = holmAdjust([0.01, 0.04, 0.03]);
  check('holm [0.01,0.04,0.03] → [0.03,0.04,0.06→0.06]', adj[0] == 0.03 && (adj[2] - 0.06).abs() < 1e-9 && adj[1] >= adj[2], '$adj');

  // 4. 채점
  check('scoreSet 6개=1등', scoreSet([1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 6], 7)[2] == 1);
  check('scoreSet 5+보너스=2등', scoreSet([1, 2, 3, 4, 5, 7], [1, 2, 3, 4, 5, 6], 7)[2] == 2);
  check('scoreSet 5=3등', scoreSet([1, 2, 3, 4, 5, 9], [1, 2, 3, 4, 5, 6], 7)[2] == 3);
  check('scoreSet 3=5등', scoreSet([1, 2, 3, 40, 41, 42], [1, 2, 3, 4, 5, 6], 7)[2] == 5);

  // 5. 특징
  final f = ComboFeatures.of([1, 2, 3, 4, 5, 6]);
  check('1-6 연속 run=6, arith', f.maxRun == 6 && f.arithmetic && f.consecPairs == 5);
  final g = ComboFeatures.of([5, 10, 15, 20, 25, 30]);
  check('5의 배수 allMult5', g.allMult5 && g.arithmetic);
  final h = ComboFeatures.of([3, 13, 23, 33, 43, 7]);
  check('끝자리 3 반복 쌍=10', h.sameLastPairs == 10, '${h.sameLastPairs}');

  // 6. 로지스틱 회귀: 합성 데이터 (β=[-0.5, +0.8, -0.6]) 복원
  final rng = SeededRandom(42);
  final X = <List<double>>[], y = <int>[];
  for (int i = 0; i < 6000; i++) {
    final x1 = rng.nextDouble() * 2 - 1, x2 = rng.nextDouble() * 2 - 1;
    final p = 1 / (1 + exp(-(-0.5 + 0.8 * x1 - 0.6 * x2)));
    X.add([x1, x2]); y.add(rng.nextDouble() < p ? 1 : 0);
  }
  final fit = fitLogistic(X, y);
  check('logistic 수렴', fit.converged);
  check('β0≈-0.5', (fit.coef[0] + 0.5).abs() < 0.12, fit.coef[0].toStringAsFixed(3));
  check('β1≈+0.8', (fit.coef[1] - 0.8).abs() < 0.15, '${fit.coef[1].toStringAsFixed(3)} ± ${fit.se[1].toStringAsFixed(3)}');
  check('β2≈-0.6', (fit.coef[2] + 0.6).abs() < 0.15, '${fit.coef[2].toStringAsFixed(3)} ± ${fit.se[2].toStringAsFixed(3)}');
  // 무신호 데이터: 기준 대비 개선 ≈ 0 (과적합 작아야 함)
  final X0 = <List<double>>[], y0 = <int>[];
  for (int i = 0; i < 4000; i++) { X0.add([rng.nextDouble(), rng.nextDouble()]); y0.add(rng.nextDouble() < 0.3 ? 1 : 0); }
  final f0 = fitLogistic(X0.sublist(0, 3000), y0.sublist(0, 3000));
  final tl = logLoss(f0, X0.sublist(3000), y0.sublist(3000));
  final bl = baselineLogLoss(y0.sublist(0, 3000).reduce((a, b) => a + b) / 3000, y0.sublist(3000));
  check('무신호: 개선≈0', (bl - tl).abs() < 0.01, (bl - tl).toStringAsFixed(4));

  // 7. 결정적 난수
  final a = SeededRandom(1245 * 7919 + 101).combo(), b = SeededRandom(1245 * 7919 + 101).combo();
  check('SeededRandom 결정적', a.join(',') == b.join(','), '$a');
  check('combo 유효', a.length == 6 && a.toSet().length == 6 && a.every((n) => n >= 1 && n <= 45));

  // 8. Wilson / t
  final ci = wilsonCi(5, 100);
  check('wilson(5/100) ≈ [0.022,0.112]', (ci[0] - 0.0216).abs() < 0.005 && (ci[1] - 0.1118).abs() < 0.005, '$ci');
  final t = oneSampleT(List<double>.generate(50, (i) => 0.8 + (i % 2 == 0 ? 0.1 : -0.1)), 0.8);
  check('t-test 평균 0.8 → t≈0', t[2].abs() < 1e-9, 't=${t[2]}');
}
