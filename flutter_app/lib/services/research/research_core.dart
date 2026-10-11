// ══════════════════════════════════════════════════════════════
// 연구 모듈 공통 코어 (순수 Dart — Flutter/DB 의존 없음)
//
// 추첨예측 연구·구매예측·예측력 검증이 공유하는 조합론 상수, 조합 특징,
// 통계 검정, 로지스틱 회귀(IRLS)를 모아둔다.
// 기존 엔진(rpa_number_core 등)과 독립이며 기존 코드를 수정하지 않는다.
// ══════════════════════════════════════════════════════════════

import 'dart:math';

// ── 로또 6/45 조합론 ───────────────────────────────────────────
const int kLottoTotalCombos = 8145060; // C(45,6)

/// 6개 선택 시 당첨번호와 k개 일치할 확률 (초기하분포, 보너스 미포함)
/// P(k) = C(6,k)·C(39,6-k) / C(45,6)
const Map<int, double> kMatchProb = {
  0: 3262623 / 8145060,
  1: 3454542 / 8145060,
  2: 1233765 / 8145060,
  3: 182780 / 8145060,
  4: 11115 / 8145060,
  5: 234 / 8145060,
  6: 1 / 8145060,
};

/// 무작위 6개 선택의 기대 일치 개수 = 6·6/45 = 0.8
const double kExpectedMatches = 0.8;

/// 무작위 6개 선택의 일치 개수 분산 (초기하) ≈ 0.6145
const double kMatchVariance = 0.61454545;

/// 3개 이상 일치(5등 이상) 확률 ≈ 0.02383
const double kProbAtLeast3 = (182780 + 11115 + 234 + 1) / 8145060;

int binom(int n, int k) {
  if (k < 0 || k > n) return 0;
  k = min(k, n - k);
  int r = 1;
  for (int i = 1; i <= k; i++) {
    r = r * (n - k + i) ~/ i;
  }
  return r;
}

// ── 조합 특징 (구매자 선택 편향 연구용) ────────────────────────
/// 6개 번호 조합의 특징. 모든 값은 "관측값"이며 해석은 엔진 쪽에서 한다.
class ComboFeatures {
  final int cntLe31;       // 1~31 (생일 일 범위) 개수
  final int cntLe12;       // 1~12 (생일 월 범위) 개수
  final int cntLucky;      // 선호 숫자 {3,7,8} 개수
  final int consecPairs;   // 연속쌍 개수 (예: 12,13)
  final int maxRun;        // 최장 연속 길이
  final int sameLastPairs; // 끝자리 동일 쌍 개수
  final int oddCnt;        // 홀수 개수
  final int sum;           // 합계
  final int cntGe40;       // 40 이상 개수
  final int spread;        // 최대-최소
  final int maxDecade;     // 같은 10단위 구간 최대 개수
  final bool arithmetic;   // 등차수열 (공차 일정)
  final bool allMult5;     // 전부 5의 배수

  const ComboFeatures({
    required this.cntLe31, required this.cntLe12, required this.cntLucky,
    required this.consecPairs, required this.maxRun, required this.sameLastPairs,
    required this.oddCnt, required this.sum, required this.cntGe40,
    required this.spread, required this.maxDecade,
    required this.arithmetic, required this.allMult5,
  });

  factory ComboFeatures.of(List<int> numbers) {
    final n = List<int>.of(numbers)..sort();
    int consec = 0, run = 1, maxRun = 1;
    for (int i = 1; i < n.length; i++) {
      if (n[i] - n[i - 1] == 1) {
        consec++;
        run++;
        if (run > maxRun) maxRun = run;
      } else {
        run = 1;
      }
    }
    int sameLast = 0;
    for (int i = 0; i < n.length; i++) {
      for (int j = i + 1; j < n.length; j++) {
        if (n[i] % 10 == n[j] % 10) sameLast++;
      }
    }
    final decades = <int, int>{};
    for (final x in n) {
      final d = (x - 1) ~/ 10;
      decades[d] = (decades[d] ?? 0) + 1;
    }
    bool arith = n.length >= 3;
    if (arith) {
      final d = n[1] - n[0];
      for (int i = 2; i < n.length; i++) {
        if (n[i] - n[i - 1] != d) { arith = false; break; }
      }
    }
    return ComboFeatures(
      cntLe31: n.where((x) => x <= 31).length,
      cntLe12: n.where((x) => x <= 12).length,
      cntLucky: n.where((x) => x == 3 || x == 7 || x == 8).length,
      consecPairs: consec,
      maxRun: maxRun,
      sameLastPairs: sameLast,
      oddCnt: n.where((x) => x.isOdd).length,
      sum: n.fold(0, (a, b) => a + b),
      cntGe40: n.where((x) => x >= 40).length,
      spread: n.last - n.first,
      maxDecade: decades.values.reduce(max),
      arithmetic: arith,
      allMult5: n.every((x) => x % 5 == 0),
    );
  }

  /// 회귀용 수치 벡터 (균등분포 기대값 기준으로 중심화해 해석을 쉽게 한다)
  /// 순서는 [kFeatureNames]와 일치.
  List<double> toVector() => [
        cntLe31 - 6 * 31 / 45,          // 기대 4.133
        cntLe12 - 6 * 12 / 45,          // 기대 1.6
        cntLucky - 6 * 3 / 45,          // 기대 0.4
        consecPairs - 0.6667,           // 기대 5·(1/9)… 근사 (실측 평균 ≈0.67)
        sameLastPairs - 1.36,           // 근사 기대 (15쌍 × ~0.09)
        (oddCnt - 3).abs().toDouble(),  // 홀짝 불균형 (0=3:3)
        (sum - 138).abs() / 20.0,       // 합계 중심(138)에서의 편차
        cntGe40 - 6 * 6 / 45,           // 기대 0.8
        (maxDecade - 2).clamp(0, 6).toDouble(), // 10단위 집중
        (arithmetic || allMult5 || maxRun >= 4) ? 1.0 : 0.0, // 규칙 배열
      ];

  Map<String, dynamic> toJson() => {
        'cnt_le31': cntLe31, 'cnt_le12': cntLe12, 'cnt_lucky': cntLucky,
        'consec_pairs': consecPairs, 'max_run': maxRun, 'same_last_pairs': sameLastPairs,
        'odd_cnt': oddCnt, 'sum': sum, 'cnt_ge40': cntGe40, 'spread': spread,
        'max_decade': maxDecade, 'arithmetic': arithmetic, 'all_mult5': allMult5,
      };
}

const List<String> kFeatureNames = [
  '1~31 집중', '1~12 집중', '선호숫자(3·7·8)', '연속쌍', '끝자리 반복',
  '홀짝 불균형', '합계 편차', '40 이상', '10단위 집중', '규칙 배열',
];
const List<String> kFeatureKeys = [
  'le31', 'le12', 'lucky', 'consec', 'same_last',
  'odd_imbalance', 'sum_dev', 'ge40', 'decade_conc', 'regular_pattern',
];

// ── 결정적 난수 (같은 회차·같은 데이터 → 같은 결과) ──────────────
class SeededRandom {
  final Random _r;
  SeededRandom(int seed) : _r = Random(seed);

  /// 1~45 중 서로 다른 6개 (정렬)
  List<int> combo() {
    final pool = List<int>.generate(45, (i) => i + 1);
    for (int i = 0; i < 6; i++) {
      final j = i + _r.nextInt(45 - i);
      final t = pool[i]; pool[i] = pool[j]; pool[j] = t;
    }
    return pool.sublist(0, 6)..sort();
  }

  int nextInt(int max) => _r.nextInt(max);
  double nextDouble() => _r.nextDouble();
}

// ── 통계 유틸 ──────────────────────────────────────────────────
double normalCdf(double z) {
  // Abramowitz-Stegun 7.1.26 근사 (오차 < 1.5e-7)
  final t = 1 / (1 + 0.2316419 * z.abs());
  final d = 0.3989423 * exp(-z * z / 2);
  final p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))));
  return z >= 0 ? 1 - p : p;
}

/// 양측 p값 (정규 근사)
double twoSidedP(double z) => 2 * (1 - normalCdf(z.abs()));

/// 정규화 상부 불완전감마 Q(a, x) — 카이제곱 생존함수용
double _gammaQ(double a, double x) {
  if (x <= 0) return 1;
  if (x < a + 1) {
    // 급수 전개 P(a,x) → Q = 1 - P
    double sum = 1 / a, term = 1 / a, ap = a;
    for (int n = 0; n < 500; n++) {
      ap += 1; term *= x / ap; sum += term;
      if (term.abs() < sum.abs() * 1e-14) break;
    }
    return 1 - sum * exp(-x + a * log(x) - _lnGamma(a));
  }
  // 연분수 (Lentz)
  double b = x + 1 - a, c = 1 / 1e-300, d = 1 / b, h = d;
  for (int i = 1; i < 500; i++) {
    final an = -i * (i - a);
    b += 2;
    d = an * d + b; if (d.abs() < 1e-300) d = 1e-300;
    c = b + an / c; if (c.abs() < 1e-300) c = 1e-300;
    d = 1 / d;
    final del = d * c; h *= del;
    if ((del - 1).abs() < 1e-14) break;
  }
  return exp(-x + a * log(x) - _lnGamma(a)) * h;
}

double _lnGamma(double x) {
  const g = [76.18009172947146, -86.50532032941677, 24.01409824083091,
    -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5];
  double y = x, tmp = x + 5.5;
  tmp -= (x + 0.5) * log(tmp);
  double ser = 1.000000000190015;
  for (final c in g) { y += 1; ser += c / y; }
  return -tmp + log(2.5066282746310005 * ser / x);
}

/// 카이제곱 생존함수 P(X² ≥ stat | df)
double chiSquareSf(double stat, int df) => _gammaQ(df / 2, stat / 2);

/// Holm 보정: p값 리스트 → 보정된 p값 (같은 순서)
List<double> holmAdjust(List<double> p) {
  final idx = List<int>.generate(p.length, (i) => i)..sort((a, b) => p[a].compareTo(p[b]));
  final adj = List<double>.filled(p.length, 1);
  double running = 0;
  for (int k = 0; k < idx.length; k++) {
    final v = ((p.length - k) * p[idx[k]]).clamp(0.0, 1.0);
    running = max(running, v);
    adj[idx[k]] = running;
  }
  return adj;
}

/// Wilson 95% 신뢰구간 (비율)
List<double> wilsonCi(int successes, int n, {double z = 1.96}) {
  if (n == 0) return [0, 1];
  final p = successes / n;
  final denom = 1 + z * z / n;
  final center = (p + z * z / (2 * n)) / denom;
  final half = z * sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom;
  return [(center - half).clamp(0, 1), (center + half).clamp(0, 1)];
}

/// 1표본 t 통계량 (표본 평균 vs 기준값). 반환: [mean, se, t, p(정규근사), n]
List<double> oneSampleT(List<double> xs, double mu0) {
  final n = xs.length;
  if (n < 2) return [n == 1 ? xs[0] : double.nan, double.nan, double.nan, double.nan, n.toDouble()];
  final mean = xs.reduce((a, b) => a + b) / n;
  final varS = xs.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / (n - 1);
  final se = sqrt(varS / n);
  final t = se > 0 ? (mean - mu0) / se : double.nan;
  return [mean, se, t, t.isNaN ? double.nan : twoSidedP(t), n.toDouble()];
}

// ── 로지스틱 회귀 (IRLS + 약한 릿지) ──────────────────────────
class LogisticFit {
  final List<double> coef;   // [intercept, β1..βk]
  final List<double> se;
  final int n;
  final double trainLogLoss;
  final bool converged;
  const LogisticFit(this.coef, this.se, this.n, this.trainLogLoss, this.converged);

  double predictProb(List<double> x) {
    double z = coef[0];
    for (int j = 0; j < x.length; j++) {
      z += coef[j + 1] * x[j];
    }
    return 1 / (1 + exp(-z));
  }

  double linear(List<double> x) {
    double z = coef[0];
    for (int j = 0; j < x.length; j++) {
      z += coef[j + 1] * x[j];
    }
    return z;
  }
}

/// X: n×k (절편 없이), y: 0/1. ridge: 계수 안정화용 L2 (절편 제외).
LogisticFit fitLogistic(List<List<double>> X, List<int> y, {double ridge = 1e-3, int maxIter = 50}) {
  final n = X.length;
  final k = n == 0 ? 0 : X[0].length;
  final p = k + 1;
  var beta = List<double>.filled(p, 0);
  if (n == 0) return LogisticFit(beta, List<double>.filled(p, double.nan), 0, double.nan, false);
  // 절편 초기화: logit(평균)
  final ybar = y.reduce((a, b) => a + b) / n;
  beta[0] = log((ybar + 1e-6) / (1 - ybar + 1e-6));

  bool converged = false;
  List<List<double>> xtwx = List.generate(p, (_) => List<double>.filled(p, 0));
  for (int it = 0; it < maxIter; it++) {
    for (final row in xtwx) { row.fillRange(0, p, 0); }
    final grad = List<double>.filled(p, 0);
    for (int i = 0; i < n; i++) {
      double z = beta[0];
      for (int j = 0; j < k; j++) { z += beta[j + 1] * X[i][j]; }
      final mu = 1 / (1 + exp(-z));
      final w = mu * (1 - mu);
      final r = y[i] - mu;
      grad[0] += r;
      xtwx[0][0] += w;
      for (int a = 0; a < k; a++) {
        grad[a + 1] += r * X[i][a];
        xtwx[a + 1][0] += w * X[i][a];
        xtwx[0][a + 1] += w * X[i][a];
        for (int b = 0; b < k; b++) {
          xtwx[a + 1][b + 1] += w * X[i][a] * X[i][b];
        }
      }
    }
    for (int j = 1; j < p; j++) {
      xtwx[j][j] += ridge;
      grad[j] -= ridge * beta[j];
    }
    final step = _solve(xtwx, grad);
    if (step == null) break;
    double maxStep = 0;
    for (int j = 0; j < p; j++) {
      beta[j] += step[j];
      maxStep = max(maxStep, step[j].abs());
    }
    if (maxStep < 1e-7) { converged = true; break; }
  }
  // 표준오차: (X'WX)^-1 대각
  final inv = _invert(xtwx);
  final se = List<double>.generate(p, (j) => inv == null ? double.nan : sqrt(max(inv[j][j], 0)));
  final fit = LogisticFit(beta, se, n, 0, converged);
  double ll = 0;
  for (int i = 0; i < n; i++) {
    final mu = fit.predictProb(X[i]).clamp(1e-9, 1 - 1e-9);
    ll += -(y[i] * log(mu) + (1 - y[i]) * log(1 - mu));
  }
  return LogisticFit(beta, se, n, ll / n, converged);
}

double logLoss(LogisticFit fit, List<List<double>> X, List<int> y) {
  if (X.isEmpty) return double.nan;
  double ll = 0;
  for (int i = 0; i < X.length; i++) {
    final mu = fit.predictProb(X[i]).clamp(1e-9, 1 - 1e-9);
    ll += -(y[i] * log(mu) + (1 - y[i]) * log(1 - mu));
  }
  return ll / X.length;
}

/// 절편만 있는 기준 모델의 로그손실 (학습 평균을 그대로 예측)
double baselineLogLoss(double trainMean, List<int> yTest) {
  if (yTest.isEmpty) return double.nan;
  final mu = trainMean.clamp(1e-9, 1 - 1e-9);
  double ll = 0;
  for (final v in yTest) { ll += -(v * log(mu) + (1 - v) * log(1 - mu)); }
  return ll / yTest.length;
}

List<double>? _solve(List<List<double>> A, List<double> b) {
  final n = b.length;
  final M = List.generate(n, (i) => [...A[i], b[i]]);
  for (int c = 0; c < n; c++) {
    int piv = c;
    for (int r = c + 1; r < n; r++) {
      if (M[r][c].abs() > M[piv][c].abs()) piv = r;
    }
    if (M[piv][c].abs() < 1e-12) return null;
    final tmp = M[c]; M[c] = M[piv]; M[piv] = tmp;
    for (int r = 0; r < n; r++) {
      if (r == c) continue;
      final f = M[r][c] / M[c][c];
      if (f == 0) continue;
      for (int j = c; j <= n; j++) { M[r][j] -= f * M[c][j]; }
    }
  }
  return List<double>.generate(n, (i) => M[i][n] / M[i][i]);
}

List<List<double>>? _invert(List<List<double>> A) {
  final n = A.length;
  final M = List.generate(n, (i) => [...A[i], ...List<double>.generate(n, (j) => i == j ? 1.0 : 0.0)]);
  for (int c = 0; c < n; c++) {
    int piv = c;
    for (int r = c + 1; r < n; r++) {
      if (M[r][c].abs() > M[piv][c].abs()) piv = r;
    }
    if (M[piv][c].abs() < 1e-12) return null;
    final tmp = M[c]; M[c] = M[piv]; M[piv] = tmp;
    final d = M[c][c];
    for (int j = 0; j < 2 * n; j++) { M[c][j] /= d; }
    for (int r = 0; r < n; r++) {
      if (r == c) continue;
      final f = M[r][c];
      if (f == 0) continue;
      for (int j = 0; j < 2 * n; j++) { M[r][j] -= f * M[c][j]; }
    }
  }
  return List.generate(n, (i) => M[i].sublist(n));
}

// ── 릿지 회귀 (절편 비벌점) ────────────────────────────────────
/// 반환: [b0, b1..bk]. X 는 절편 없이 n×k.
List<double>? ridgeSolve(List<List<double>> X, List<double> y, double lam) {
  final n = X.length;
  if (n == 0) return null;
  final p = X[0].length + 1;
  final A = List.generate(p, (_) => List<double>.filled(p, 0));
  final b = List<double>.filled(p, 0);
  for (int i = 0; i < n; i++) {
    final row = [1.0, ...X[i]];
    for (int a = 0; a < p; a++) {
      b[a] += row[a] * y[i];
      for (int c = 0; c < p; c++) { A[a][c] += row[a] * row[c]; }
    }
  }
  for (int j = 1; j < p; j++) { A[j][j] += lam; }
  return _solve(A, b);
}

double ridgePredict(List<double> coef, List<double> x) {
  double z = coef[0];
  for (int j = 0; j < x.length; j++) { z += coef[j + 1] * x[j]; }
  return z;
}

/// 피어슨 상관과 양측 p (t 분포 → 정규 근사, n 충분히 클 때)
List<double> pearsonWithP(List<double> a, List<double> b) {
  final n = a.length;
  if (n < 3) return [double.nan, double.nan];
  final ma = a.reduce((x, y) => x + y) / n, mb = b.reduce((x, y) => x + y) / n;
  double sab = 0, saa = 0, sbb = 0;
  for (int i = 0; i < n; i++) {
    sab += (a[i] - ma) * (b[i] - mb); saa += (a[i] - ma) * (a[i] - ma); sbb += (b[i] - mb) * (b[i] - mb);
  }
  if (saa <= 0 || sbb <= 0) return [0, 1];
  final r = sab / sqrt(saa * sbb);
  final t = r * sqrt((n - 2) / max(1e-12, 1 - r * r));
  return [r, twoSidedP(t)];
}

/// 2-모수 포아송 GLM: y ~ Poisson(exp(offset + b0 + b1·z)). 반환 [b1, se, p]
List<double> poissonSlope(List<double> y, List<double> z, List<double> offset) {
  final fit = fitPoisson([for (final v in z) [v]], y, offset, ridge: 0);
  final b1 = fit.coef[1], se = fit.se[1];
  return [b1, se, se > 0 ? twoSidedP(b1 / se) : double.nan];
}

// ── 포아송 회귀 (IRLS, 오프셋 지원) — 판매량 보정 인기도 모델용 ─────
/// log E[y] = offset + β0 + β·x.  y: 카운트(당첨자 수), offset: log(기대 당첨자 수 under 균등)
class PoissonFit {
  final List<double> coef; // [intercept, β1..βk]
  final List<double> se;
  final int n;
  final double deviance;
  final bool converged;
  const PoissonFit(this.coef, this.se, this.n, this.deviance, this.converged);

  double linear(List<double> x) {
    double z = coef[0];
    for (int j = 0; j < x.length; j++) { z += coef[j + 1] * x[j]; }
    return z;
  }
  double predictMean(List<double> x, double offset) => exp(offset + linear(x));
}

PoissonFit fitPoisson(List<List<double>> X, List<double> y, List<double> offset, {double ridge = 1e-3, int maxIter = 60}) {
  final n = X.length;
  final k = n == 0 ? 0 : X[0].length;
  final p = k + 1;
  final beta = List<double>.filled(p, 0);
  if (n == 0) return PoissonFit(beta, List<double>.filled(p, double.nan), 0, double.nan, false);
  double sy = 0, so = 0;
  for (int i = 0; i < n; i++) { sy += y[i]; so += exp(offset[i]); }
  beta[0] = log(max(sy, 1e-9) / max(so, 1e-9));
  bool converged = false;
  final xtwx = List.generate(p, (_) => List<double>.filled(p, 0));
  for (int it = 0; it < maxIter; it++) {
    for (final row in xtwx) { row.fillRange(0, p, 0); }
    final grad = List<double>.filled(p, 0);
    for (int i = 0; i < n; i++) {
      double z = beta[0];
      for (int j = 0; j < k; j++) { z += beta[j + 1] * X[i][j]; }
      final mu = exp(offset[i] + z);
      final r = y[i] - mu;
      grad[0] += r; xtwx[0][0] += mu;
      for (int a = 0; a < k; a++) {
        grad[a + 1] += r * X[i][a];
        xtwx[a + 1][0] += mu * X[i][a]; xtwx[0][a + 1] += mu * X[i][a];
        for (int b = 0; b < k; b++) { xtwx[a + 1][b + 1] += mu * X[i][a] * X[i][b]; }
      }
    }
    for (int j = 1; j < p; j++) { xtwx[j][j] += ridge; grad[j] -= ridge * beta[j]; }
    final step = _solve(xtwx, grad);
    if (step == null) break;
    double maxStep = 0;
    for (int j = 0; j < p; j++) {
      final s = step[j].clamp(-1.0, 1.0); // 발산 방지
      beta[j] += s; maxStep = max(maxStep, s.abs());
    }
    if (maxStep < 1e-7) { converged = true; break; }
  }
  final inv = _invert(xtwx);
  final se = List<double>.generate(p, (j) => inv == null ? double.nan : sqrt(max(inv[j][j], 0)));
  final fit = PoissonFit(beta, se, n, 0, converged);
  return PoissonFit(beta, se, n, poissonDeviance(fit, X, y, offset), converged);
}

/// 포아송 이탈도 (작을수록 적합). 기준 모델(절편만) 대비 감소량이 설명력.
double poissonDeviance(PoissonFit fit, List<List<double>> X, List<double> y, List<double> offset) {
  double d = 0;
  for (int i = 0; i < X.length; i++) {
    final mu = max(fit.predictMean(X[i], offset[i]), 1e-12);
    d += 2 * ((y[i] > 0 ? y[i] * log(y[i] / mu) : 0) - (y[i] - mu));
  }
  return d;
}

/// 절편만 있는 포아송 기준 모델의 이탈도 (학습 비율을 검증에 적용)
double poissonBaselineDeviance(double trainRatio, List<double> y, List<double> offset) {
  double d = 0;
  for (int i = 0; i < y.length; i++) {
    final mu = max(exp(offset[i]) * trainRatio, 1e-12);
    d += 2 * ((y[i] > 0 ? y[i] * log(y[i] / mu) : 0) - (y[i] - mu));
  }
  return d;
}

/// JSON 직렬화용: NaN/무한대는 null (jsonEncode가 NaN에서 실패하므로)
double? jsonNum(double v) => v.isNaN || v.isInfinite ? null : v;

// ── 채점 ───────────────────────────────────────────────────────
/// 예측 세트 vs 실제 번호: [일치 개수, 보너스 일치(0/1), 등수(0=낙첨,1~5)]
List<int> scoreSet(List<int> predicted, List<int> actual, int bonus) {
  final a = actual.toSet();
  final m = predicted.where(a.contains).length;
  final b = predicted.contains(bonus) ? 1 : 0;
  int rank = 0;
  if (m == 6) {
    rank = 1;
  } else if (m == 5 && b == 1) {
    rank = 2;
  } else if (m == 5) {
    rank = 3;
  } else if (m == 4) {
    rank = 4;
  } else if (m == 3) {
    rank = 5;
  }
  return [m, b, rank];
}
