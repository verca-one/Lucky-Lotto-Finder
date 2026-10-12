// 랜덤확률분석엔진 (RPA) v4 — 순차패턴 + 가설 생애주기 + Store Model
// Supabase 설정: rpa_supabase_setup.sql → rpa_v2 → rpa_v3 → rpa_v4_supabase_setup.sql
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/lotto_winning_number.dart';
import '../services/rpa_engine.dart';
import '../services/rpa_hypothesis_engine.dart';
import '../services/rpa_store_engine.dart';
import '../services/rpa_joint_engine.dart';
import '../services/rpa_joint_historical_engine.dart';
import '../services/rpa_monte_carlo_engine.dart';
import '../services/rpa_unified_prediction.dart' show kRpaActiveModelVersion;
import '../services/supabase_service.dart';
import 'admin_comprehensive_prediction_screen.dart';
import 'admin_mnd_screen.dart';
import '../services/research/hypothesis_replay_engine.dart';
import '../services/research/research_runtime.dart';

// ══════════════════════════════════════════════════════════
// Models
// ══════════════════════════════════════════════════════════

/// 데이터 연구·순차 재현 시작 회차 (500회 가설 → 501회 보정 → … → 최신)
const int kRpaReplayStartRound = 500;

class _ConvPoint {
  final int round;
  final double value;
  const _ConvPoint(this.round, this.value);
}

class _IndicatorResult {
  final String id;
  final String name;
  final String unit;
  final double observed;
  final double baseline;
  final double convergenceScore; // 0.0 ~ 1.0
  final List<_ConvPoint> history;
  final List<(String, double, double)> breakdown;
  double? zScore;
  bool get isSignal => zScore != null && zScore!.abs() >= 2.0;
  double get devPp => (observed - baseline) * 100;

  _IndicatorResult({
    required this.id,
    required this.name,
    required this.unit,
    required this.observed,
    required this.baseline,
    required this.convergenceScore,
    required this.history,
    this.breakdown = const [],
    this.zScore,
  });
}

class _Hypothesis {
  final String id;
  final int createdRound;
  final int targetStartRound;
  final int targetEndRound;
  final String type;
  final Map<String, dynamic> conditions;
  final List<int> representativeNumbers;
  final String evidence;
  final double? observedProbability;
  final double? randomBaseline;
  final double? zScore;
  String status; // pending, observing, verified, discarded
  final DateTime createdAt;
  List<_VerifResult> verifications;

  _Hypothesis({
    required this.id,
    required this.createdRound,
    required this.targetStartRound,
    required this.targetEndRound,
    required this.type,
    required this.conditions,
    required this.representativeNumbers,
    required this.evidence,
    this.observedProbability,
    this.randomBaseline,
    this.zScore,
    required this.status,
    required this.createdAt,
    this.verifications = const [],
  });

  factory _Hypothesis.fromJson(Map<String, dynamic> j) => _Hypothesis(
        id: j['id'] as String,
        createdRound: j['created_round'] as int,
        targetStartRound: j['target_start_round'] as int,
        targetEndRound: j['target_end_round'] as int,
        type: j['hypothesis_type'] as String? ?? 'pattern',
        conditions: (j['conditions'] as Map<String, dynamic>?) ?? {},
        representativeNumbers: (j['representative_numbers'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            [],
        evidence: j['evidence'] as String? ?? '',
        observedProbability: (j['observed_probability'] as num?)?.toDouble(),
        randomBaseline: (j['random_baseline'] as num?)?.toDouble(),
        zScore: (j['z_score'] as num?)?.toDouble(),
        status: j['status'] as String? ?? 'pending',
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'] as String)
            : DateTime.now(),
      );
}

class _VerifResult {
  final String id;
  final String hypothesisId;
  final int verifiedRound;
  final List<int> actualNumbers;
  final int numberMatches;
  final String overallResult;
  final DateTime verifiedAt;

  _VerifResult({
    required this.id,
    required this.hypothesisId,
    required this.verifiedRound,
    required this.actualNumbers,
    required this.numberMatches,
    required this.overallResult,
    required this.verifiedAt,
  });

  factory _VerifResult.fromJson(Map<String, dynamic> j) => _VerifResult(
        id: j['id'] as String,
        hypothesisId: j['hypothesis_id'] as String,
        verifiedRound: j['verified_round'] as int,
        actualNumbers: (j['actual_numbers'] as List<dynamic>)
            .map((e) => e as int)
            .toList(),
        numberMatches: j['number_matches'] as int? ?? 0,
        overallResult: j['overall_result'] as String? ?? 'miss',
        verifiedAt: j['verified_at'] != null
            ? DateTime.parse(j['verified_at'] as String)
            : DateTime.now(),
      );
}

// ══════════════════════════════════════════════════════════
// Primes in 1-45
// ══════════════════════════════════════════════════════════
const _primes45 = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43};

// Theoretical baselines for 6/45 lotto
class _Baselines {
  static const double oddEven33 = 0.33483; // P(3홀:3짝)
  static const double lowHigh33 = 0.33483; // P(1-22 중 3개)
  static const double consecutiveAny = 0.52866; // P(연속번호 1쌍 이상)
  static const double sumMean = 138.0; // E[합계]
  static const double primeMean = 1.8667; // E[소수 개수] = 6*14/45
  static const double rangeMean = 32.857; // E[최대-최소] = 46*5/7
  static const double sumEven = 0.5; // P(합계가 짝수)
  static const double freqExpected = 6.0 / 45.0; // 번호당 기대 출현율
}

// ══════════════════════════════════════════════════════════
// Analyzer
// ══════════════════════════════════════════════════════════
class _Analyzer {
  final List<LottoWinningNumber> data;
  // sorted ascending by round
  late final List<LottoWinningNumber> sorted;

  _Analyzer(this.data) {
    sorted = List.of(data)..sort((a, b) => a.round.compareTo(b.round));
  }

  int get n => sorted.length;

  // 최근 100회차 — Z-score 신호 감지용 (최신 트렌드 반영)
  List<LottoWinningNumber> get _recent =>
      sorted.length > 100 ? sorted.sublist(sorted.length - 100) : sorted;
  int get _rn => _recent.length;

  List<int> _nums(LottoWinningNumber w) => List.of(w.numbers)..sort();

  // convergence history: compute metric at milestones
  List<_ConvPoint> _history(double Function(List<LottoWinningNumber>) fn) {
    final milestones = [50, 100, 200, 300, 500, 700, 1000, 1500, n];
    final out = <_ConvPoint>[];
    for (final m in milestones) {
      if (m > n) break;
      final slice = sorted.sublist(0, m);
      final v = fn(slice);
      out.add(_ConvPoint(slice.last.round, v));
    }
    return out;
  }

  // convergence score: stability of recent values around baseline
  double _convScore(List<_ConvPoint> hist, double baseline) {
    if (hist.length < 3) return 0.5;
    final recent = hist.sublist(hist.length - 3).map((p) => p.value).toList();
    if (baseline == 0) return 0.5;
    final mean = recent.reduce((a, b) => a + b) / recent.length;
    final deviation = (mean - baseline).abs() / baseline;
    return (1.0 - deviation * 5.0).clamp(0.0, 1.0);
  }

  // ── 1. 홀짝 3:3 비율 ──────────────────────────────────
  _IndicatorResult oddEven33() {
    double fn(List<LottoWinningNumber> d) {
      final cnt = d.where((w) => _nums(w).where((n) => n % 2 == 1).length == 3).length;
      return cnt / d.length;
    }

    final obs = fn(sorted);
    final hist = _history(fn);
    // 최근 100회 기준 Z-score
    final recentObs = fn(_recent);
    final p = _Baselines.oddEven33;
    final zS = (recentObs - p) / sqrt(p * (1 - p) / _rn);
    // breakdown: 0:6 1:5 2:4 3:3 4:2 5:1 6:0
    final counts = List.filled(7, 0);
    for (final w in sorted) {
      counts[_nums(w).where((n) => n % 2 == 1).length]++;
    }
    // Theoretical probabilities from combinatorics (23 odd, 22 even)
    const theo = [0.0092, 0.0744, 0.2272, 0.3348, 0.2511, 0.0909, 0.0124];
    final bd = List.generate(
        7, (i) => ('$i홀${6 - i}짝', counts[i] / n, theo[i]));

    final r = _IndicatorResult(
      id: 'odd_even_33',
      name: '홀짝 3:3 비율',
      unit: '%',
      observed: obs,
      baseline: _Baselines.oddEven33,
      convergenceScore: _convScore(hist, _Baselines.oddEven33),
      history: hist,
      breakdown: bd,
    );
    r.zScore = zS;
    return r;
  }

  // ── 2. 저고 3:3 비율 (저=1-22) ───────────────────────
  _IndicatorResult lowHigh33() {
    double fn(List<LottoWinningNumber> d) {
      final cnt = d.where((w) => _nums(w).where((n) => n <= 22).length == 3).length;
      return cnt / d.length;
    }

    final obs = fn(sorted);
    final hist = _history(fn);
    // 최근 100회 기준 Z-score
    final recentObs = fn(_recent);
    final p2 = _Baselines.lowHigh33;
    final zS2 = (recentObs - p2) / sqrt(p2 * (1 - p2) / _rn);
    final counts = List.filled(7, 0);
    for (final w in sorted) {
      counts[_nums(w).where((n) => n <= 22).length]++;
    }
    const theo = [0.0044, 0.0572, 0.2205, 0.3348, 0.2649, 0.1032, 0.0150];
    final bd = List.generate(
        7, (i) => ('저$i고${6 - i}', counts[i] / n, theo[i]));

    final r2 = _IndicatorResult(
      id: 'low_high_33',
      name: '저고 3:3 비율',
      unit: '%',
      observed: obs,
      baseline: _Baselines.lowHigh33,
      convergenceScore: _convScore(hist, _Baselines.lowHigh33),
      history: hist,
      breakdown: bd,
    );
    r2.zScore = zS2;
    return r2;
  }

  // ── 3. 합계 평균 ──────────────────────────────────────
  _IndicatorResult sumMean() {
    double fn(List<LottoWinningNumber> d) {
      final total = d.fold<int>(0, (s, w) => s + w.numbers.reduce((a, b) => a + b));
      return total / d.length;
    }

    final obs = fn(sorted);
    final hist = _history(fn);
    // normalize to fraction of 138 for convergence
    final histNorm = hist
        .map((p) => _ConvPoint(p.round, p.value / _Baselines.sumMean))
        .toList();
    final convS = _convScore(histNorm, 1.0);
    // Z-score — 최근 100회차 기준 (σ_sum ≈ 33.5)
    final recentSum = fn(_recent);
    final zS = (recentSum - _Baselines.sumMean) / (33.5 / sqrt(_rn));

    // sum distribution in buckets
    final buckets = <String, int>{};
    for (final w in sorted) {
      final s = w.numbers.reduce((a, b) => a + b);
      final key = s < 110
          ? '<110'
          : s < 130
              ? '110-129'
              : s < 150
                  ? '130-149'
                  : s < 170
                      ? '150-169'
                      : '≥170';
      buckets[key] = (buckets[key] ?? 0) + 1;
    }
    const theoSumBuckets = {
      '<110': 0.085,
      '110-129': 0.222,
      '130-149': 0.386,
      '150-169': 0.232,
      '≥170': 0.075,
    };
    final bd = buckets.entries
        .map((e) => (e.key, e.value / n, theoSumBuckets[e.key] ?? 0.0))
        .toList();

    final r = _IndicatorResult(
      id: 'sum_mean',
      name: '합계 평균',
      unit: '점',
      observed: obs,
      baseline: _Baselines.sumMean,
      convergenceScore: convS,
      history: hist,
      breakdown: bd,
    );
    r.zScore = zS;
    return r;
  }

  // ── 4. 번호 빈도 균등도 (chi-square) ─────────────────
  _IndicatorResult freqUniformity() {
    // Returns chi-square statistic (lower = more uniform)
    // Under H0: chi2 ~ χ²(44), E[chi2]=44
    double fn(List<LottoWinningNumber> d) {
      final freq = List.filled(46, 0);
      for (final w in d) {
        for (final num in w.numbers) freq[num]++;
      }
      final exp = d.length * 6.0 / 45.0;
      double chi2 = 0;
      for (int i = 1; i <= 45; i++) {
        chi2 += (freq[i] - exp) * (freq[i] - exp) / exp;
      }
      return chi2;
    }

    final obs = fn(sorted);
    final baseline = 44.0; // E[chi2] under H0
    final hist = _history(fn);
    // 최근 100회차 기준 Z-score
    final recentChi = fn(_recent);
    final zS = (recentChi - baseline) / sqrt(2 * baseline);

    // Top 10 most deviant numbers
    final freq = List.filled(46, 0);
    for (final w in sorted) {
      for (final num in w.numbers) freq[num]++;
    }
    final exp = n * 6.0 / 45.0;
    final numList = List.generate(45, (i) => i + 1)
      ..sort((a, b) => (freq[b] - exp).abs().compareTo((freq[a] - exp).abs()));
    final bd = numList
        .take(10)
        .map((num) => ('$num번', freq[num] / n, 6.0 / 45.0))
        .toList();

    final r = _IndicatorResult(
      id: 'freq_uniformity',
      name: '번호 빈도 균등도',
      unit: 'χ²',
      observed: obs,
      baseline: baseline,
      convergenceScore: _convScore(
          hist.map((p) => _ConvPoint(p.round, p.value / baseline)).toList(),
          1.0),
      history: hist,
      breakdown: bd,
    );
    r.zScore = zS;
    return r;
  }

  // ── 5. 연속번호 출현율 ────────────────────────────────
  _IndicatorResult consecutive() {
    bool hasConsec(LottoWinningNumber w) {
      final s = _nums(w);
      for (int i = 0; i < s.length - 1; i++) {
        if (s[i + 1] - s[i] == 1) return true;
      }
      return false;
    }

    double fn(List<LottoWinningNumber> d) =>
        d.where(hasConsec).length / d.length;

    final obs = fn(sorted);
    final hist = _history(fn);
    // 최근 100회차 기준 Z-score
    final recentCons = fn(_recent);
    final zS = (recentCons - _Baselines.consecutiveAny) /
        sqrt(_Baselines.consecutiveAny * (1 - _Baselines.consecutiveAny) / _rn);

    // breakdown: 1쌍, 2쌍, 3쌍+
    int c1 = 0, c2 = 0, c3 = 0, c0 = 0;
    for (final w in sorted) {
      final s = _nums(w);
      int pairs = 0;
      for (int i = 0; i < s.length - 1; i++) {
        if (s[i + 1] - s[i] == 1) pairs++;
      }
      if (pairs == 0) c0++;
      else if (pairs == 1) c1++;
      else if (pairs == 2) c2++;
      else c3++;
    }
    final bd = [
      ('없음', c0 / n, 1 - _Baselines.consecutiveAny),
      ('1쌍', c1 / n, 0.39),
      ('2쌍', c2 / n, 0.12),
      ('3쌍+', c3 / n, 0.019),
    ];

    final r = _IndicatorResult(
      id: 'consecutive',
      name: '연속번호 출현율',
      unit: '%',
      observed: obs,
      baseline: _Baselines.consecutiveAny,
      convergenceScore: _convScore(hist, _Baselines.consecutiveAny),
      history: hist,
      breakdown: bd,
    );
    r.zScore = zS;
    return r;
  }

  // ── 6. 구간 분포 균등도 (5개 구간: 1-9, 10-18, 19-27, 28-36, 37-45) ──
  _IndicatorResult zoneBalance() {
    int _zone(int n) => (n - 1) ~/ 9; // 0~4
    // entropy: max entropy = log(5), closer to 1 is better
    double fn(List<LottoWinningNumber> d) {
      final cnt = List.filled(5, 0);
      for (final w in d) {
        for (final num in w.numbers) cnt[_zone(num)]++;
      }
      final total = cnt.reduce((a, b) => a + b).toDouble();
      double entropy = 0;
      for (final c in cnt) {
        if (c == 0) continue;
        final p = c / total;
        entropy -= p * log(p);
      }
      return entropy / log(5); // normalize 0~1
    }

    final obs = fn(sorted);
    const baseline = 0.98; // ideal uniform ≈ 1.0 but random draws slightly sub-1
    final hist = _history(fn);
    // 최근 100회차 구간 chi-square Z-score (df=4)
    final rcnt = List.filled(5, 0);
    for (final w in _recent) {
      for (final num in w.numbers) rcnt[_zone(num)]++;
    }
    final rExp = _rn * 6.0 / 5.0;
    double rChi2 = 0;
    for (final c in rcnt) rChi2 += (c - rExp) * (c - rExp) / rExp;
    final zSzone = (rChi2 - 4.0) / sqrt(2 * 4.0);

    final zoneCnts = List.filled(5, 0);
    for (final w in sorted) {
      for (final num in w.numbers) zoneCnts[_zone(num)]++;
    }
    final zTotal = zoneCnts.reduce((a, b) => a + b).toDouble();
    final zoneNames = ['1-9', '10-18', '19-27', '28-36', '37-45'];
    final bd =
        List.generate(5, (i) => (zoneNames[i], zoneCnts[i] / zTotal, 1.0 / 5));

    final rz = _IndicatorResult(
      id: 'zone_balance',
      name: '구간 분포 균등도',
      unit: '엔트로피',
      observed: obs,
      baseline: baseline,
      convergenceScore: _convScore(hist, baseline),
      history: hist,
      breakdown: bd,
    );
    rz.zScore = zSzone;
    return rz;
  }

  // ── 7. 끝수 분포 균등도 ──────────────────────────────
  _IndicatorResult endingDigit() {
    double fn(List<LottoWinningNumber> d) {
      final cnt = List.filled(10, 0);
      for (final w in d) {
        for (final num in w.numbers) cnt[num % 10]++;
      }
      final total = cnt.reduce((a, b) => a + b).toDouble();
      double entropy = 0;
      for (final c in cnt) {
        if (c == 0) continue;
        final p = c / total;
        entropy -= p * log(p);
      }
      return entropy / log(10);
    }

    final obs = fn(sorted);
    const baseline = 0.996;
    final hist = _history(fn);
    // 최근 100회차 끝수 chi-square Z-score (df=9)
    final endCnt = List.filled(10, 0);
    for (final w in _recent) {
      for (final num in w.numbers) endCnt[num % 10]++;
    }
    final endTheoFrac = [5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 4.0, 4.0, 4.0, 4.0]
        .map((x) => x / 45.0)
        .toList();
    final endTotal = _rn * 6.0;
    double endChi2 = 0;
    for (int i = 0; i < 10; i++) {
      final exp = endTotal * endTheoFrac[i];
      endChi2 += (endCnt[i] - exp) * (endCnt[i] - exp) / exp;
    }
    final zSend = (endChi2 - 9.0) / sqrt(2 * 9.0);

    final cnt = List.filled(10, 0);
    for (final w in sorted) {
      for (final num in w.numbers) cnt[num % 10]++;
    }
    final total = cnt.reduce((a, b) => a + b).toDouble();
    // Expected: ends 0-5: 5/45, ends 6-9: 4/45
    final theoEnd = [5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 4.0, 4.0, 4.0, 4.0]
        .map((x) => x / 45.0)
        .toList();
    final bd = List.generate(10, (i) => ('끝자리 $i', cnt[i] / total, theoEnd[i]));

    final re = _IndicatorResult(
      id: 'ending_digit',
      name: '끝수 분포 균등도',
      unit: '엔트로피',
      observed: obs,
      baseline: baseline,
      convergenceScore: _convScore(hist, baseline),
      history: hist,
      breakdown: bd,
    );
    re.zScore = zSend;
    return re;
  }

  // ── 8. 소수 포함 평균 ────────────────────────────────
  _IndicatorResult primeCount() {
    double fn(List<LottoWinningNumber> d) {
      final total = d.fold<int>(
          0, (s, w) => s + w.numbers.where(_primes45.contains).length);
      return total / d.length;
    }

    final obs = fn(sorted);
    final hist = _history(fn);
    // 최근 100회차 기준 Z-score
    final recentPrime = fn(_recent);
    final zS = (recentPrime - _Baselines.primeMean) / (1.12 / sqrt(_rn));

    final cnts = List.filled(7, 0);
    for (final w in sorted) cnts[w.numbers.where(_primes45.contains).length]++;
    // theoretical: binomial(6, 14/45)
    const theoP = [0.0864, 0.2802, 0.3472, 0.2087, 0.0643, 0.0124, 0.0008];
    final bd =
        List.generate(7, (i) => ('$i개', cnts[i] / n, theoP[i]));

    final r = _IndicatorResult(
      id: 'prime_count',
      name: '소수 포함 평균',
      unit: '개',
      observed: obs,
      baseline: _Baselines.primeMean,
      convergenceScore: _convScore(
          hist.map((p) => _ConvPoint(p.round, p.value / _Baselines.primeMean)).toList(),
          1.0),
      history: hist,
      breakdown: bd,
    );
    r.zScore = zS;
    return r;
  }

  // ── 9. 범위폭 평균 (max - min) ───────────────────────
  _IndicatorResult rangeWidth() {
    double fn(List<LottoWinningNumber> d) {
      final total = d.fold<int>(0, (s, w) {
        final nums = _nums(w);
        return s + nums.last - nums.first;
      });
      return total / d.length;
    }

    final obs = fn(sorted);
    final hist = _history(fn);
    // 최근 100회차 기준 Z-score
    final recentRange = fn(_recent);
    final zS = (recentRange - _Baselines.rangeMean) / (9.5 / sqrt(_rn));

    // distribution by range bucket
    final buckets = <String, int>{};
    for (final w in sorted) {
      final nums = _nums(w);
      final r = nums.last - nums.first;
      final key = r < 20
          ? '<20'
          : r < 30
              ? '20-29'
              : r < 35
                  ? '30-34'
                  : r < 40
                      ? '35-39'
                      : '≥40';
      buckets[key] = (buckets[key] ?? 0) + 1;
    }
    const theoRange = {
      '<20': 0.061,
      '20-29': 0.183,
      '30-34': 0.212,
      '35-39': 0.269,
      '≥40': 0.275,
    };
    final bd = buckets.entries
        .map((e) => (e.key, e.value / n, theoRange[e.key] ?? 0.0))
        .toList();

    final res = _IndicatorResult(
      id: 'range_width',
      name: '범위폭 평균',
      unit: '점',
      observed: obs,
      baseline: _Baselines.rangeMean,
      convergenceScore: _convScore(
          hist.map((p) => _ConvPoint(p.round, p.value / _Baselines.rangeMean)).toList(),
          1.0),
      history: hist,
      breakdown: bd,
    );
    res.zScore = zS;
    return res;
  }

  // ── 10. 합계 홀/짝 비율 ──────────────────────────────
  _IndicatorResult sumParity() {
    double fn(List<LottoWinningNumber> d) {
      final even = d.where((w) => w.numbers.reduce((a, b) => a + b) % 2 == 0).length;
      return even / d.length;
    }

    final obs = fn(sorted);
    final hist = _history(fn);
    // 최근 100회차 기준 Z-score
    final recentParity = fn(_recent);
    final zS = (recentParity - 0.5) / sqrt(0.25 / _rn);

    final even = sorted.where((w) => w.numbers.reduce((a, b) => a + b) % 2 == 0).length;
    final bd = [
      ('짝수합', even / n, 0.5),
      ('홀수합', (n - even) / n, 0.5),
    ];

    final r = _IndicatorResult(
      id: 'sum_parity',
      name: '합계 홀/짝 비율',
      unit: '%',
      observed: obs,
      baseline: 0.5,
      convergenceScore: _convScore(hist, 0.5),
      history: hist,
      breakdown: bd,
    );
    r.zScore = zS;
    return r;
  }

  List<_IndicatorResult> allIndicators() => [
        oddEven33(),
        lowHigh33(),
        sumMean(),
        freqUniformity(),
        consecutive(),
        zoneBalance(),
        endingDigit(),
        primeCount(),
        rangeWidth(),
        sumParity(),
      ];
}

// ══════════════════════════════════════════════════════════
// Simulation (top-level for compute())
// ══════════════════════════════════════════════════════════

Map<String, double> _runSimulation(int iterations) {
  final rng = Random();
  final pool = List.generate(45, (i) => i + 1);

  // Accumulators
  int cOE33 = 0, cLH33 = 0, cCons = 0, cSumEven = 0;
  double sumTotal = 0, primeTotal = 0, rangeTotal = 0;

  for (int i = 0; i < iterations; i++) {
    pool.shuffle(rng);
    final drawn = pool.sublist(0, 6)..sort();

    final odds = drawn.where((n) => n % 2 == 1).length;
    final lows = drawn.where((n) => n <= 22).length;
    final s = drawn.reduce((a, b) => a + b);
    final primes = drawn.where(_primes45.contains).length;
    final range = drawn.last - drawn.first;
    bool hasConsec = false;
    for (int j = 0; j < drawn.length - 1; j++) {
      if (drawn[j + 1] - drawn[j] == 1) { hasConsec = true; break; }
    }

    if (odds == 3) cOE33++;
    if (lows == 3) cLH33++;
    if (hasConsec) cCons++;
    if (s % 2 == 0) cSumEven++;
    sumTotal += s;
    primeTotal += primes;
    rangeTotal += range;
  }

  final n = iterations.toDouble();
  return {
    'odd_even_33': cOE33 / n,
    'low_high_33': cLH33 / n,
    'consecutive': cCons / n,
    'sum_parity': cSumEven / n,
    'sum_mean': sumTotal / n,
    'prime_mean': primeTotal / n,
    'range_mean': rangeTotal / n,
  };
}

// ══════════════════════════════════════════════════════════
// Hypothesis Service
// ══════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════
// 가설 연구소 자동 유지 — 서버 파이프라인(tool/server/research_pipeline_test.dart)이 호출.
// 화면에 있던 규칙(자동 검증 · 신호 가능성 등록 · 만료 폐기)을 그대로 옮겼다. 앱은 실행하지 않는다.
// 신호(z)는 이 실행에서 계산한 시뮬레이션 기준값으로 판단한다 (기기별 캐시 대신).
// ══════════════════════════════════════════════════════════════
Future<Map<String, int>> runRpaHypothesisLabMaintenance(List<LottoWinningNumber> data) async {
  if (!ResearchRuntime.serverWriter || data.isEmpty) return const {};
  final svc = _RpaService();
  final hypotheses = await svc.loadHypotheses();
  final verified = await _autoVerifyHypotheses(svc, hypotheses, data);
  final indicators = _Analyzer(data).allIndicators();
  final sim = await compute(_runSimulation, 50000);
  _applySimulationZ(indicators, sim, data.length);
  final latest = data.map((d) => d.round).reduce(max);
  final (created, discarded) = await _registerSignalHypotheses(svc, indicators, hypotheses, latest);
  return {'verifications': verified, 'created': created, 'discarded': discarded};
}

void _applySimulationZ(List<_IndicatorResult> indicators, Map<String, double> base, int count) {
  final n = count.toDouble();
  for (final ind in indicators) {
    double? z;
    if (ind.id == 'odd_even_33') z = (ind.observed - (base['odd_even_33'] ?? _Baselines.oddEven33)) / sqrt((base['odd_even_33'] ?? _Baselines.oddEven33) * (1 - (base['odd_even_33'] ?? _Baselines.oddEven33)) / n);
    if (ind.id == 'low_high_33') z = (ind.observed - (base['low_high_33'] ?? _Baselines.lowHigh33)) / sqrt((base['low_high_33'] ?? _Baselines.lowHigh33) * (1 - (base['low_high_33'] ?? _Baselines.lowHigh33)) / n);
    if (ind.id == 'consecutive') z = (ind.observed - (base['consecutive'] ?? _Baselines.consecutiveAny)) / sqrt((base['consecutive'] ?? _Baselines.consecutiveAny) * (1 - (base['consecutive'] ?? _Baselines.consecutiveAny)) / n);
    if (ind.id == 'sum_parity') z = (ind.observed - (base['sum_parity'] ?? 0.5)) / sqrt(0.25 / n);
    if (z != null) ind.zScore = z;
  }
}

/// 관찰 중 가설의 목표 구간 회차를 실제 당첨번호로 검증·저장. 반환 = 새 검증 수.
Future<int> _autoVerifyHypotheses(_RpaService svc, List<_Hypothesis> hypotheses, List<LottoWinningNumber> data) async {
  if (data.isEmpty) return 0;
  final latest = data.map((d) => d.round).reduce(max);
  final byRound = {for (final d in data) d.round: d};
  int saved = 0;

  for (final h in hypotheses) {
    if (h.status != 'observing') continue;
    if (latest < h.targetStartRound) continue;

    // Get all rounds in target window
    for (int r = h.targetStartRound; r <= min(h.targetEndRound, latest); r++) {
      final draw = byRound[r];
      if (draw == null) continue;
      final already = h.verifications.any((v) => v.verifiedRound == r);
      if (already) continue;

      // Check condition
      final reps = h.representativeNumbers;
      final matches = reps.isEmpty ? 0 : draw.numbers.where(reps.contains).length;
      final result = reps.isEmpty
          ? 'partial'
          : matches >= 3
              ? 'hit'
              : matches >= 1
                  ? 'partial'
                  : 'miss';

      try {
        await svc.saveVerification(
          hypothesisId: h.id,
          round: r,
          numbers: draw.numbers,
          bonus: draw.bonusNumber,
          matches: matches,
          result: result,
        );
        saved++;
      } catch (_) {}
    }

    if (latest >= h.targetEndRound) h.status = 'verified';
  }
  // Update observing → observing for active ones
  for (final h in hypotheses) {
    if (h.status == 'pending' && latest >= h.targetStartRound) {
      h.status = 'observing';
      try { await svc.updateStatus(h.id, 'observing'); } catch (_) {}
    }
  }
  return saved;
}

/// 신호(|z|≥2) 지표를 새 가능성으로 등록하고, 목표 구간이 지난 관찰 가설을 폐기. 반환 = (등록 수, 폐기 수).
Future<(int, int)> _registerSignalHypotheses(
    _RpaService svc, List<_IndicatorResult> indicators, List<_Hypothesis> hypotheses, int latestRound) async {
  if (indicators.isEmpty) return (0, 0);
  final signals = indicators.where((i) => i.isSignal).toList();
  int created = 0, discarded = 0;

  for (final sig in signals) {
    // 이미 같은 지표로 등록된 active 가능성이 있으면 스킵
    final alreadyActive = hypotheses.any((h) =>
        h.type == 'auto_signal' &&
        h.conditions['indicator_id'] == sig.id &&
        (h.status == 'pending' || h.status == 'observing'));
    if (alreadyActive) continue;

    // 새 가능성 자동 등록
    try {
      await svc.createHypothesis(
        createdRound: latestRound,
        targetStartRound: latestRound + 1,
        targetEndRound: latestRound + 10,
        type: 'auto_signal',
        conditions: {'indicator_id': sig.id, 'indicator_name': sig.name},
        representativeNumbers: const [],
        evidence: '신호 자동 감지: ${sig.name} Z=${sig.zScore?.toStringAsFixed(2)}σ (최근 100회 편차)',
        zScore: sig.zScore,
      );
      created++;
    } catch (_) {}
  }

  // 오래된 미검증 가능성 자동 폐기 (targetEndRound 지나고 observing 상태인 것)
  for (final h in hypotheses) {
    if (h.status == 'observing' && h.targetEndRound < latestRound - 5) {
      try {
        await svc.updateStatus(h.id, 'discarded');
        h.status = 'discarded';
        discarded++;
      } catch (_) {}
    }
  }
  return (created, discarded);
}

class _RpaService {
  final _db = Supabase.instance.client;

  Future<List<_Hypothesis>> loadHypotheses() async {
    try {
      final raw = await _db
          .from('rpa_hypotheses')
          .select('*, rpa_verification_results(*)')
          .neq('status', 'discarded')
          .order('created_at', ascending: false);
      return (raw as List<dynamic>).map((j) {
        final h = _Hypothesis.fromJson(j as Map<String, dynamic>);
        final verifs = (j['rpa_verification_results'] as List<dynamic>?)
                ?.map((v) => _VerifResult.fromJson(v as Map<String, dynamic>))
                .toList() ??
            [];
        h.verifications = verifs;
        return h;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> createHypothesis({
    required int createdRound,
    required int targetStartRound,
    required int targetEndRound,
    required String type,
    required Map<String, dynamic> conditions,
    required List<int> representativeNumbers,
    required String evidence,
    double? observedProb,
    double? randomBaseline,
    double? zScore,
  }) async {
    await _db.from('rpa_hypotheses').insert({
      'created_round': createdRound,
      'target_start_round': targetStartRound,
      'target_end_round': targetEndRound,
      'hypothesis_type': type,
      'conditions': conditions,
      'representative_numbers': representativeNumbers,
      'evidence': evidence,
      'observed_probability': observedProb,
      'random_baseline': randomBaseline,
      'z_score': zScore,
      'status': 'pending',
    });
  }

  Future<void> updateStatus(String id, String status) async {
    await _db
        .from('rpa_hypotheses')
        .update({'status': status}).eq('id', id);
  }

  Future<void> saveVerification({
    required String hypothesisId,
    required int round,
    required List<int> numbers,
    required int bonus,
    required int matches,
    required String result,
  }) async {
    await _db.from('rpa_verification_results').insert({
      'hypothesis_id': hypothesisId,
      'verified_round': round,
      'actual_numbers': numbers,
      'actual_bonus': bonus,
      'number_matches': matches,
      'overall_result': result,
    });
    await _db.from('rpa_hypotheses').update({'status': 'verified'}).eq('id', hypothesisId);
  }
}

// ══════════════════════════════════════════════════════════
// Main Screen
// ══════════════════════════════════════════════════════════

class AdminRpaScreen extends StatefulWidget {
  const AdminRpaScreen({super.key});

  @override
  State<AdminRpaScreen> createState() => _AdminRpaScreenState();
}

class _AdminRpaScreenState extends State<AdminRpaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _svc = _RpaService();

  bool _loading = true;
  String? _error;

  List<LottoWinningNumber> _data = [];
  List<_IndicatorResult> _indicators = [];
  List<_Hypothesis> _hypotheses = [];
  Map<String, double>? _simResult;
  bool _simRunning = false;
  DateTime? _simAt;

  // v2: model state + replay
  RpaModelState _modelState = RpaModelState();
  List<RpaRoundScore> _recentScores = [];
  bool _replayRunning = false;
  String _replayStatus = '';
  double _replayProgress = 0.0; // 0.0~1.0
  DateTime? _replayCompletedAt;
  int _lastReplayToRound = 0;
  int _lastReplaySaved = 0;
  Map<int, String> _recentStoreNames = {}; // round → 1등 판매점명
  int _modelId = 0; // 1~10 랜덤 모델 번호

  // v3: 가설 연구소
  List<RpaHypV3> _hypothesesV3 = [];

  // v4: Store Model
  StoreModelState? _storeModelState;

  // v5: Joint Model
  JointModelState? _jointModelState;

  // v6: 명당 가설 연구소
  int _mndTrainingEnd = 0;

  static const _simPrefKey = 'rpa_sim_v1';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 7, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final results = await Future.wait([
        SupabaseService.getAllWinningNumbers(),
        RpaEngine.instance.loadState(),
        RpaEngine.instance.loadRecentScores(100),
        _svc.loadHypotheses(),
        RpaModelId.get(),
      ]);
      final data = results[0] as List<LottoWinningNumber>;
      final modelState = results[1] as RpaModelState;
      final recentScores = results[2] as List<RpaRoundScore>;
      final hypotheses = results[3] as List<_Hypothesis>;
      final modelId = results[4] as int;

      final analyzer = _Analyzer(data);
      final indicators = analyzer.allIndicators();
      await _applySimCache(indicators);
      await _autoVerify(hypotheses, data);

      // 시뮬레이션 자동 실행: 앱 시작마다 조용히 백그라운드 실행
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runSimSilent();
      });

      // 최신 20회차 1등 판매점명 배치 로드
      final recentRounds = data.isNotEmpty
          ? (List.of(data)..sort((a, b) => b.round.compareTo(a.round)))
              .take(20).map((d) => d.round).toList()
          : <int>[];
      Map<int, String> storeNames = {};
      try {
        storeNames = await SupabaseService.getFirstPlaceStoreNamesByRounds(recentRounds);
      } catch (_) {}

      // v3 가설 로드 (테이블 없어도 에러 무시)
      List<RpaHypV3> hypothesesV3 = [];
      try {
        hypothesesV3 = await HypothesisEngine.instance.loadHypotheses();
      } catch (_) {}

      // v4 Store Model 상태 로드
      StoreModelState? storeModelState;
      try {
        storeModelState = await StoreModelEngine.instance.loadState();
      } catch (_) {}

      // v5 Joint Model 상태 로드
      JointModelState? jointModelState;
      try {
        jointModelState = await JointModelEngine.instance.loadState();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _data = data;
          _indicators = indicators;
          _hypotheses = hypotheses;
          _hypothesesV3 = hypothesesV3;
          _storeModelState = storeModelState;
          _jointModelState = jointModelState;
          _mndTrainingEnd = data.isNotEmpty
              ? data.map((d) => d.round).reduce((a, b) => a > b ? a : b)
              : 0;
          _modelState = modelState;
          _recentScores = recentScores;
          _recentStoreNames = storeNames;
          _modelId = modelId;
          _loading = false;
        });
      }

      // 엔진 처리(Round Gate·증분 업데이트·활성 버전 결과·MND·예측 연구·Monte Carlo)는
      // 서버 파이프라인(GitHub Actions)이 자동 실행한다. 화면을 연다고 계산·저장하지 않는다.
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // _RoundFlowPanel 콜백: ready 게이트 처리는 서버 파이프라인이 한다 → 화면은 다시 읽기만
  Future<void> _onReadyGateDetected() async {}

  Future<void> _applySimCache(List<_IndicatorResult> indicators) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_simPrefKey);
      if (str == null) return;
      final json = jsonDecode(str) as Map<String, dynamic>;
      _simResult = (json['result'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
      _simAt = DateTime.parse(json['computed_at'] as String);
      _applySimToIndicators(indicators);
    } catch (_) {}
  }

  void _applySimToIndicators(List<_IndicatorResult> indicators) {
    if (_simResult == null) return;
    _applySimulationZ(indicators, _simResult!, _data.length);
  }

  /// 가설 자동 검증 — 서버 파이프라인만 저장한다 (앱에서는 표시만)
  Future<void> _autoVerify(List<_Hypothesis> hypotheses, List<LottoWinningNumber> data) async {
    if (!ResearchRuntime.serverWriter) return;
    await _autoVerifyHypotheses(_svc, hypotheses, data);
  }

  // 1~5 회차 차이 → 증분 업데이트 (전체 리플레이 없이 새 회차만 처리)
  Future<void> _runIncrementalUpdate({required int from, required int to}) async {
    if (_replayRunning) return;
    setState(() {
      _replayRunning = true;
      _replayStatus = '증분 업데이트 중... (${from}~${to}회차)';
    });
    try {
      final newRounds = _data.where((d) => d.round >= from && d.round <= to).toList()
        ..sort((a, b) => a.round.compareTo(b.round));
      for (final r in newRounds) {
        await RpaEngine.instance.processNewRound(newRound: r, allData: _data);
      }
      final state = await RpaEngine.instance.loadState();
      final scores = await RpaEngine.instance.loadRecentScores(100);
      if (mounted) setState(() {
        _modelState = state;
        _recentScores = scores;
        _replayCompletedAt = DateTime.now();
        _lastReplayToRound = to;
        _lastReplaySaved = newRounds.length;
        _replayProgress = 1.0;
      });
      await _autoRegisterSignals();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('증분 업데이트 오류: $e')));
      }
    }
    if (mounted) setState(() { _replayRunning = false; _replayStatus = ''; });
  }

  Future<void> _runReplay() async {
    if (_replayRunning || _data.isEmpty) return;
    final latestRound = _data.isNotEmpty ? _data.map((d) => d.round).reduce((a, b) => a > b ? a : b) : 0;
    setState(() {
      _replayRunning = true;
      _replayProgress = 0.0;
      _replayStatus = '시작 중... ($kRpaReplayStartRound회차~${latestRound}회차)';
    });
    int? savedCount;
    try {
      // 주의: startRound=1 이면 _replayIsolate가 startIdx<=0 으로 빈 결과를 반환(no-op)했던 버그.
      // 데이터 연구 시작 회차(500)부터 순차 재현한다.
      savedCount = await RpaEngine.instance.runHistoricalReplay(
        allData: _data,
        startRound: kRpaReplayStartRound,
        onStatus: (s) {
          if (!mounted) return;
          // Parse progress from "저장 중... N/TOTAL (PCT%)" format
          double progress = _replayProgress;
          final pctMatch = RegExp(r'\((\d+)%\)').firstMatch(s);
          if (pctMatch != null) {
            progress = int.parse(pctMatch.group(1)!) / 100.0;
          } else if (s.startsWith('완료')) {
            progress = 1.0;
          } else if (s.contains('시뮬레이션')) {
            progress = 0.05;
          }
          setState(() { _replayStatus = s; _replayProgress = progress; });
        },
      );
      final state = await RpaEngine.instance.loadState();
      final scores = await RpaEngine.instance.loadRecentScores(100);
      // 판매점명 재로드
      final recentRounds = _data.isNotEmpty
          ? (List.of(_data)..sort((a, b) => b.round.compareTo(a.round)))
              .take(20).map((d) => d.round).toList()
          : <int>[];
      Map<int, String> storeNames = _recentStoreNames;
      try {
        storeNames = await SupabaseService.getFirstPlaceStoreNamesByRounds(recentRounds);
      } catch (_) {}
      // 엔진 재학습 완료 → 새 모델 번호 발급 (전 화면 동기화)
      final newModelId = await RpaModelId.regenerate();
      if (mounted) setState(() {
        _modelState = state;
        _recentScores = scores;
        _recentStoreNames = storeNames;
        _replayCompletedAt = DateTime.now();
        _lastReplayToRound = latestRound;
        _lastReplaySaved = savedCount ?? 0;
        _replayProgress = 1.0;
        _modelId = newModelId;
      });
      // 신호 기반 가능성 자동 등록
      await _autoRegisterSignals();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('리플레이 오류: $e')));
      }
    }
    if (mounted) setState(() { _replayRunning = false; _replayStatus = ''; });
  }

  // 신호 감지 → 가능성 자동 생성/검증/폐기
  /// 신호 가능성 등록·만료 폐기 — 서버 파이프라인만 저장한다
  Future<void> _autoRegisterSignals() async {
    if (!ResearchRuntime.serverWriter) return;
    final (created, discarded) = await _registerSignalHypotheses(_svc, _indicators, _hypotheses, _latestRound);
    if (created + discarded > 0) {
      final updated = await _svc.loadHypotheses();
      if (mounted) setState(() => _hypotheses = updated);
    }
  }

  // 백그라운드 자동 실행 — UI 인디케이터 없음, 오류 무시
  Future<void> _runSimSilent() async {
    if (_simRunning) return;
    try {
      final result = await compute(_runSimulation, 50000);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_simPrefKey, jsonEncode({
        'computed_at': DateTime.now().toIso8601String(),
        'result': result,
      }));
      if (mounted) {
        setState(() { _simResult = result; _simAt = DateTime.now(); });
        _applySimToIndicators(_indicators);
        await _proposeTheoriesFromSim(result);
      }
    } catch (_) {}
  }

  Future<void> _runSim() async {
    if (_simRunning) return;
    setState(() => _simRunning = true);
    try {
      final result = await compute(_runSimulation, 50000);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_simPrefKey, jsonEncode({
        'computed_at': DateTime.now().toIso8601String(),
        'result': result,
      }));
      _simResult = result;
      _simAt = DateTime.now();
      _applySimToIndicators(_indicators);
      // 시뮬레이션 결과 → 이론 자동 제안 (가설연구소에 추가)
      await _proposeTheoriesFromSim(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('시뮬레이션 오류: $e')));
      }
    }
    if (mounted) setState(() => _simRunning = false);
  }

  // 시뮬레이션 결과에서 의미 있는 편차 → 가설연구소에 이론 자동 제안
  Future<void> _proposeTheoriesFromSim(Map<String, double> simResult) async {
    if (_data.isEmpty) return;
    try {
      final analyzer = _Analyzer(_data);
      final indicators = analyzer.allIndicators();
      final n = _data.length.toDouble();

      // 각 지표의 관측값 vs 시뮬 기준값 비교
      final proposals = <Map<String, dynamic>>[];
      for (final ind in indicators) {
        final base = simResult[ind.id];
        if (base == null || base <= 0) continue;
        final se = sqrt(base * (1 - base) / n);
        if (se <= 0) continue;
        final z = (ind.observed - base) / se;
        if (z.abs() < 2.0) continue; // Z < 2.0 은 노이즈

        final direction = z > 0 ? '과다' : '부족';
        final name = '${ind.name} $direction 패턴 (Z=${z.toStringAsFixed(1)}σ)';
        final evidence = '몬테카를로 기준 ${(base * 100).toStringAsFixed(1)}% vs '
            '실제 ${(ind.observed * 100).toStringAsFixed(1)}%';
        proposals.add({
          'name': name,
          'evidence': evidence,
          'z_score': z,
          'indicator_id': ind.id,
          'base': base,
          'observed': ind.observed,
        });
      }

      if (proposals.isEmpty) return;
      proposals.sort((a, b) =>
          (b['z_score'] as double).abs().compareTo((a['z_score'] as double).abs()));

      // 상위 3개만 신규 가설로 제안 (중복 방지: 같은 indicator 이미 있으면 스킵)
      final existingEvidence = _hypothesesV3.map((h) => h.evidence).toSet();
      int added = 0;
      for (final p in proposals.take(3)) {
        final pEvidence = p['evidence'] as String;
        if (existingEvidence.any((e) => e.contains(p['indicator_id'] as String))) continue;
        try {
          await _svc.createHypothesis(
            createdRound: _latestRound,
            targetStartRound: _latestRound + 1,
            targetEndRound: _latestRound + 10,
            type: 'monte_carlo',
            conditions: {
              'indicator': p['indicator_id'],
              'base': p['base'],
              'observed': p['observed'],
            },
            representativeNumbers: [],
            evidence: p['evidence'] as String,
            observedProb: (p['observed'] as double),
            randomBaseline: (p['base'] as double),
            zScore: p['z_score'] as double,
          );
          added++;
        } catch (_) {}
      }

      if (added > 0) {
        final updated = await _svc.loadHypotheses();
        if (mounted) setState(() => _hypotheses = updated);
      }
    } catch (_) {}
  }

  int get _latestRound => _data.isEmpty ? 0 : _data.map((d) => d.round).reduce(max);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepPurple.shade700,
        title: Row(
          children: [
            const Text(
              '랜덤보정엔진',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber.shade600,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'v$kRpaActiveModelVersion',
                style: TextStyle(
                  fontSize: 12, color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Colors.amber,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: '대시보드'),
            Tab(icon: Icon(Icons.bar_chart), text: '분석'),
            Tab(icon: Icon(Icons.biotech_outlined), text: '가설연구소'),
            Tab(icon: Icon(Icons.science_outlined), text: '시뮬레이션'),
            Tab(icon: Icon(Icons.store_outlined), text: 'Store Model'),
            Tab(icon: Icon(Icons.hub_outlined), text: 'Joint'),
            Tab(icon: Icon(Icons.location_searching_rounded), text: '명당연구소'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('오류: $_error'))
              : TabBarView(
                  controller: _tab,
                  children: [
                    _DashboardTab(
                      indicators: _indicators,
                      dataCount: _data.length,
                      latestRound: _latestRound,
                      simAt: _simAt,
                      onDetail: _showDetail,
                      modelState: _modelState,
                      recentScores: _recentScores,
                      allWinningData: _data,
                      recentStoreNames: _recentStoreNames,
                      replayRunning: _replayRunning,
                      replayStatus: _replayStatus,
                      replayProgress: _replayProgress,
                      onRunReplay: _runReplay,
                      replayCompletedAt: _replayCompletedAt,
                      lastReplayToRound: _lastReplayToRound,
                      lastReplaySaved: _lastReplaySaved,
                      onReadyGateDetected: _onReadyGateDetected,
                    ),
                    _AnalysisTab(
                      indicators: _indicators,
                      onDetail: _showDetail,
                    ),
                    _HypothesisLabTab(
                      hypothesesV3: _hypothesesV3,
                      allData: _data,
                      latestRound: _latestRound,
                      onRefresh: _refreshHypothesesV3,
                    ),
                    const _SimulationTab(),
                    _StoreModelTab(
                      storeModelState: _storeModelState,
                      latestRound: _latestRound,
                      onRefresh: () async {
                        final s = await StoreModelEngine.instance.loadState();
                        if (mounted) setState(() => _storeModelState = s);
                      },
                    ),
                    _JointModelTab(
                      jointModelState: _jointModelState,
                      latestRound: _latestRound,
                      allData: _data,
                      onRefresh: () async {
                        final s = await JointModelEngine.instance.loadState();
                        if (mounted) setState(() => _jointModelState = s);
                      },
                    ),
                    AdminMndScreen(trainingEndRound: _mndTrainingEnd),
                  ],
                ),
    );
  }

  void _showDetail(_IndicatorResult ind) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _IndicatorDetailSheet(indicator: ind),
    );
  }

  Future<void> _refreshHypotheses() async {
    final h = await _svc.loadHypotheses();
    await _autoVerify(h, _data);
    if (mounted) setState(() => _hypotheses = h);
  }

  Future<void> _refreshHypothesesV3() async {
    try {
      final h = await HypothesisEngine.instance.loadHypotheses();
      if (mounted) setState(() => _hypothesesV3 = h);
    } catch (_) {}
  }
}

// ══════════════════════════════════════════════════════════
// Dashboard Tab
// ══════════════════════════════════════════════════════════

class _DashboardTab extends StatelessWidget {
  final List<_IndicatorResult> indicators;
  final int dataCount;
  final int latestRound;
  final DateTime? simAt;
  final void Function(_IndicatorResult) onDetail;
  final RpaModelState modelState;
  final List<RpaRoundScore> recentScores;
  final bool replayRunning;
  final String replayStatus;
  final double replayProgress;
  final VoidCallback onRunReplay;
  final DateTime? replayCompletedAt;
  final int lastReplayToRound;
  final int lastReplaySaved;
  final List<LottoWinningNumber> allWinningData;
  final Map<int, String> recentStoreNames;
  final VoidCallback? onReadyGateDetected;

  const _DashboardTab({
    required this.indicators,
    required this.dataCount,
    required this.latestRound,
    required this.simAt,
    required this.onDetail,
    required this.modelState,
    required this.recentScores,
    required this.allWinningData,
    required this.recentStoreNames,
    required this.replayRunning,
    required this.replayStatus,
    required this.replayProgress,
    required this.onRunReplay,
    this.replayCompletedAt,
    this.lastReplayToRound = 0,
    this.lastReplaySaved = 0,
    this.onReadyGateDetected,
  });

  @override
  Widget build(BuildContext context) {
    final signals = indicators.where((i) => i.isSignal).toList();

    final ms = modelState;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Summary header
        Card(
          color: Colors.deepPurple.shade50,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  Expanded(child: _statBox('분석 회차', '$latestRound회차')),
                  Expanded(child: _statBox('데이터', '$dataCount건')),
                  Expanded(
                    child: _statBox('신호 감지', '${signals.length}개',
                        color: signals.isNotEmpty ? Colors.red : Colors.green),
                  ),
                  Expanded(
                    child: _statBox(
                      '시뮬레이션',
                      simAt != null ? '${simAt!.month}/${simAt!.day}' : '미실행',
                      color: simAt == null ? Colors.orange : null,
                    ),
                  ),
                ],
              ),
              if (latestRound > 0) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: Builder(builder: (ctx) => OutlinedButton.icon(
                    onPressed: () => Navigator.push(ctx,
                        MaterialPageRoute(builder: (_) =>
                            AdminComprehensivePredictionScreen(
                                targetRound: latestRound + 1))),
                    icon: const Icon(Icons.auto_graph_rounded, size: 16),
                    label: Text('${latestRound + 1}회 이번 회차 종합예측',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF5E35B1),
                      side: const BorderSide(color: Color(0xFF5E35B1)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  )),
                ),
              ],
            ]),
          ),
        ),

        // ── 모델 상태 패널 ──────────────────────────────
        const SizedBox(height: 10),
        Card(
          color: ms.replayCompleted
              ? Colors.green.shade50
              : Colors.orange.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: ms.replayCompleted
                  ? Colors.green.shade200
                  : Colors.orange.shade200,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      ms.replayCompleted ? Icons.check_circle : Icons.pending,
                      color: ms.replayCompleted ? Colors.green : Colors.orange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '현재 모델',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: ms.replayCompleted
                            ? Colors.green.shade800
                            : Colors.orange.shade800,
                      ),
                    ),
                    const Spacer(),
                    if (!ms.replayCompleted)
                      Text('Historical Replay 필요',
                          style: TextStyle(
                              fontSize: 11, color: Colors.orange.shade700)),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _mStatBox('마지막 학습', '${ms.lastTrainedRound}회차'),
                    _mStatBox('다음 예측', '${ms.nextPredictionRound}회차'),
                    _mStatBox('누적 예측', '${ms.totalPredictions}회'),
                    _mStatBox('누적 검증', '${ms.totalVerified}회'),
                  ],
                ),
                const SizedBox(height: 10),
                // Performance comparison
                _performanceRow('이론 모델', ms.theoryAvgScore, Colors.blue),
                const SizedBox(height: 4),
                _performanceRow(
                    '보정 모델', ms.correctionAvgScore, Colors.deepPurple),
                const SizedBox(height: 4),
                _performanceRow('랜덤 기준', 0.5, Colors.grey),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _effectChip('보정 vs 이론',
                        ms.correctionVsTheory, showSign: true),
                    const SizedBox(width: 8),
                    _effectChip('보정 vs 랜덤',
                        ms.correctionVsRandom, showSign: true),
                  ],
                ),
                // Recent 20 performance
                if (ms.totalVerified > 0) ...[
                  const SizedBox(height: 8),
                  Text('최근 20회차 성능',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _effectChip('이론', ms.recent20Theory - 0.5,
                          customLabel: '${(ms.recent20Theory * 100).toStringAsFixed(1)}%'),
                      const SizedBox(width: 8),
                      _effectChip('보정', ms.recent20Correction - 0.5,
                          customLabel: '${(ms.recent20Correction * 100).toStringAsFixed(1)}%'),
                    ],
                  ),
                ],
                // ── 고급 관리 ──────────────────────────────────
                const SizedBox(height: 12),
                const Divider(height: 1),
                ExpansionTile(
                  title: const Text('고급 관리', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                  subtitle: const Text('초기 구축 / 전체 재학습 — 정상 운영 시 불필요', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: replayRunning ? null : onRunReplay,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: replayRunning
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.history_edu_rounded, size: 18),
                        label: Text(
                          replayRunning ? '엔진 적용 중...' : '전체데이터 Historical Replay',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    if (replayRunning) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            replayStatus.isNotEmpty ? replayStatus : '1회차부터 적용하는 중...',
                            style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                          ),
                          if (replayProgress > 0) ...[
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: replayProgress,
                              backgroundColor: Colors.orange.shade100,
                              color: Colors.orange.shade600,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${(replayProgress * 100).toStringAsFixed(0)}% 완료',
                              style: TextStyle(fontSize: 10, color: Colors.orange.shade700),
                            ),
                          ],
                        ]),
                      ),
                    ],
                  ],
                ),
                if (replayCompletedAt != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.shade300),
                    ),
                    child: Row(children: [
                      Icon(Icons.check_circle, size: 16, color: Colors.teal.shade700),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        '1회~${lastReplayToRound}회차  ${lastReplayToRound}건 적용 완료  '
                        '(${replayCompletedAt!.hour.toString().padLeft(2,'0')}:${replayCompletedAt!.minute.toString().padLeft(2,'0')})',
                        style: TextStyle(fontSize: 11, color: Colors.teal.shade800, fontWeight: FontWeight.w700),
                      )),
                    ]),
                  ),
                ] else if (ms.replayCompleted) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(children: [
                      Icon(Icons.check_circle_outline, size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        '1회~${ms.lastTrainedRound}회차  ${ms.lastTrainedRound}건 적용됨',
                        style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.w700),
                      )),
                    ]),
                  ),
                ] else if (!replayRunning) ...[
                  Text(
                    '전체 데이터 $dataCount건 (1회차~${latestRound}회차)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
        ),

        // ── 학습 곡선 ────────────────────────────────────
        if (recentScores.length >= 5) ...[
          const SizedBox(height: 12),
          const Text('학습 곡선 (최근 회차별 성능)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.all(8),
            child: CustomPaint(
              painter: _LearningCurvePainter(
                  recentScores.reversed.toList()),
              size: const Size(double.infinity, 104),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                _legendDot(Colors.blue, '이론'),
                const SizedBox(width: 12),
                _legendDot(Colors.deepPurple, '보정'),
                const SizedBox(width: 12),
                _legendDot(Colors.grey, '랜덤(0.5)'),
              ],
            ),
          ),
        ],

        if (signals.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SignalBanner(signals: signals, onTap: onDetail),
        ],

        // ── 회차 데이터 흐름 ─────────────────────────────────
        const SizedBox(height: 16),
        _RoundFlowPanel(onReadyGateDetected: onReadyGateDetected),
        const SizedBox(height: 12),

        // ── 회차 데이터 준비 게이트 ───────────────────────────
        const _RoundGateSection(),

        // ── 최신 회차 반영 현황 ──────────────────────────────
        const SizedBox(height: 16),
        _RoundStatusSection(
          allWinningData: allWinningData,
          recentScores: recentScores,
          recentStoreNames: recentStoreNames,
        ),

        const SizedBox(height: 12),
        const Text('수렴 확률 지도', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.45,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: indicators.length,
          itemBuilder: (_, i) => _IndicatorCard(
            indicator: indicators[i],
            onTap: () => onDetail(indicators[i]),
          ),
        ),
      ],
    );
  }

  Widget _statBox(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _mStatBox(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _performanceRow(String label, double score, Color color) {
    return Row(
      children: [
        SizedBox(
            width: 70,
            child:
                Text(label, style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: score.clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade200,
              color: color,
              minHeight: 10,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('${(score * 100).toStringAsFixed(1)}%',
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _effectChip(String label, double delta,
      {bool showSign = false, String? customLabel}) {
    final isPos = delta > 0.005;
    final isNeg = delta < -0.005;
    final color = isPos ? Colors.green : isNeg ? Colors.red : Colors.grey;
    final str = customLabel ??
        '${showSign && delta >= 0 ? '+' : ''}${(delta * 100).toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label $str',
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════
// Learning Curve Painter
// ══════════════════════════════════════════════════════════

class _LearningCurvePainter extends CustomPainter {
  final List<RpaRoundScore> scores; // ascending by round

  _LearningCurvePainter(this.scores);

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.length < 2) return;
    const pad = 8.0;
    const yMin = 0.3;
    const yMax = 0.8;

    double toX(int i) =>
        pad + i / (scores.length - 1) * (size.width - 2 * pad);
    double toY(double v) =>
        size.height - pad -
        ((v.clamp(yMin, yMax) - yMin) / (yMax - yMin) * (size.height - 2 * pad));

    // Random baseline (0.5)
    final baseY = toY(0.5);
    final dashPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;
    for (double x = pad; x < size.width - pad; x += 8) {
      canvas.drawLine(Offset(x, baseY), Offset(x + 4, baseY), dashPaint);
    }

    // Theory line (blue) — 선행: 작은 대칭 윈도우로 빠르게 반응
    _drawLine(canvas, scores, toX, toY,
        (s) => s.theoryScore, Colors.blue.shade400,
        window: 3, trailingOnly: false, strokeWidth: 2.0);

    // Correction line (deepPurple) — 후행: 큰 trailing 윈도우로 안정적 추종
    _drawLine(canvas, scores, toX, toY,
        (s) => s.correctionScore, Colors.deepPurple.shade400,
        window: 9, trailingOnly: true, strokeWidth: 1.5);
  }

  void _drawLine(
    Canvas canvas,
    List<RpaRoundScore> data,
    double Function(int) toX,
    double Function(double) toY,
    double Function(RpaRoundScore) getValue,
    Color color, {
    int window = 5,
    bool trailingOnly = false,
    double strokeWidth = 1.5,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    bool moved = false;
    for (int i = 0; i < data.length; i++) {
      final rawVal = getValue(data[i]);
      if (rawVal <= 0) {
        moved = false;
        continue;
      }
      // trailing: 이전 window개만 참조 (후행 효과), symmetric: 앞뒤 절반씩
      final start = trailingOnly
          ? max(0, i - window + 1)
          : max(0, i - window ~/ 2);
      final end = trailingOnly
          ? i
          : min(data.length - 1, i + window ~/ 2);
      final slice = data.sublist(start, end + 1).map(getValue).where((v) => v > 0).toList();
      if (slice.isEmpty) continue;
      final avg = slice.reduce((a, b) => a + b) / slice.length;
      final x = toX(i);
      final y = toY(avg);
      if (!moved) {
        path.moveTo(x, y);
        moved = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ══════════════════════════════════════════════════════════
// 최신 회차 반영 현황 섹션
// ══════════════════════════════════════════════════════════

class _RoundStatusSection extends StatelessWidget {
  final List<LottoWinningNumber> allWinningData;
  final List<RpaRoundScore> recentScores;
  final Map<int, String> recentStoreNames;

  const _RoundStatusSection({
    required this.allWinningData,
    required this.recentScores,
    required this.recentStoreNames,
  });

  @override
  Widget build(BuildContext context) {
    if (allWinningData.isEmpty) return const SizedBox.shrink();

    // 최신 20회차
    final sorted = List.of(allWinningData)
      ..sort((a, b) => b.round.compareTo(a.round));
    final recent = sorted.take(20).toList();

    // 엔진에 적용된 회차 Set
    final appliedRounds = recentScores.map((s) => s.targetRound).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('최신 회차 반영 현황',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.deepPurple.shade200),
            ),
            child: Text('최근 ${recent.length}회차',
                style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade700)),
          ),
        ]),
        const SizedBox(height: 8),
        ...recent.map((draw) {
          final score = recentScores.where((s) => s.targetRound == draw.round).firstOrNull;
          final applied = appliedRounds.contains(draw.round);
          final storeName = recentStoreNames[draw.round] ?? '';
          return _RoundStatusRow(
            draw: draw,
            score: score,
            applied: applied,
            storeName: storeName,
          );
        }),
      ],
    );
  }
}

class _RoundStatusRow extends StatelessWidget {
  final LottoWinningNumber draw;
  final RpaRoundScore? score;
  final bool applied;
  final String storeName;

  const _RoundStatusRow({
    required this.draw,
    required this.score,
    required this.applied,
    required this.storeName,
  });

  @override
  Widget build(BuildContext context) {
    final nums = List.of(draw.numbers)..sort();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: applied ? Colors.white : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: applied ? Colors.grey.shade200 : Colors.orange.shade300,
          width: applied ? 1 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // 회차
            Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade700,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text('${draw.round}회',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            // 날짜
            Text(draw.drawDate.length >= 10 ? draw.drawDate.substring(0, 10) : draw.drawDate,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const Spacer(),
            // 적용 여부 뱃지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: applied ? Colors.teal.shade50 : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: applied ? Colors.teal.shade300 : Colors.orange.shade400),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(applied ? Icons.check_circle : Icons.hourglass_empty,
                    size: 11,
                    color: applied ? Colors.teal.shade700 : Colors.orange.shade800),
                const SizedBox(width: 3),
                Text(applied ? '적용됨' : '미적용',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: applied ? Colors.teal.shade800 : Colors.orange.shade900,
                    )),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          // 번호 행
          Row(children: [
            ...nums.map((n) => _numBall(n, isBonus: false)),
            const SizedBox(width: 4),
            Text('+', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            _numBall(draw.bonusNumber, isBonus: true),
          ]),
          // 1등 판매점
          if (storeName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.storefront, size: 12, color: Colors.indigo.shade400),
              const SizedBox(width: 4),
              Text('1등: $storeName',
                  style: TextStyle(fontSize: 11, color: Colors.indigo.shade700, fontWeight: FontWeight.w600)),
            ]),
          ],
          // 엔진 점수
          if (applied && score != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              _scoreChip('이론', score!.theoryScore, Colors.blue),
              const SizedBox(width: 6),
              _scoreChip('보정', score!.correctionScore, Colors.deepPurple),
              const SizedBox(width: 6),
              _corrEffectChip(score!.correctionEffect),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _numBall(int n, {required bool isBonus}) {
    Color bg;
    if (isBonus) {
      bg = Colors.grey.shade600;
    } else if (n <= 10) {
      bg = Colors.yellow.shade700;
    } else if (n <= 20) {
      bg = Colors.blue.shade600;
    } else if (n <= 30) {
      bg = Colors.red.shade600;
    } else if (n <= 40) {
      bg = Colors.grey.shade600;
    } else {
      bg = Colors.green.shade700;
    }
    return Container(
      width: 24, height: 24,
      margin: const EdgeInsets.only(right: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _scoreChip(String label, double score, Color color) {
    final pct = (score * 100).toStringAsFixed(1);
    final positive = score > 0.5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text('$label $pct%',
          style: TextStyle(fontSize: 10, color: positive ? color : Colors.grey.shade600, fontWeight: FontWeight.w600)),
    );
  }

  Widget _corrEffectChip(double effect) {
    final isPos = effect >= 0;
    final sign = isPos ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPos ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isPos ? Colors.green.shade300 : Colors.red.shade300),
      ),
      child: Text('보정효과 $sign${(effect * 100).toStringAsFixed(1)}pp',
          style: TextStyle(fontSize: 10,
              color: isPos ? Colors.green.shade800 : Colors.red.shade800,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _SignalBanner extends StatelessWidget {
  final List<_IndicatorResult> signals;
  final void Function(_IndicatorResult) onTap;

  const _SignalBanner({required this.signals, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
              const SizedBox(width: 6),
              Text(
                '⚠️ 유의미한 편차 감지 (|Z| ≥ 2.0)',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...signals.map((s) => GestureDetector(
                onTap: () => onTap(s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.chevron_right, size: 14, color: Colors.red),
                      Text(
                        '${s.name}  Z=${s.zScore!.toStringAsFixed(2)}σ  편차 ${s.devPp >= 0 ? '+' : ''}${s.devPp.toStringAsFixed(1)}${s.unit == '%' ? 'pp' : s.unit}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class _IndicatorCard extends StatelessWidget {
  final _IndicatorResult indicator;
  final VoidCallback onTap;

  const _IndicatorCard({required this.indicator, required this.onTap});

  Color get _cardColor {
    final z = indicator.zScore;
    if (z != null && z.abs() >= 2.5) return Colors.red.shade50;
    if (z != null && z.abs() >= 2.0) return Colors.orange.shade50;
    if (indicator.convergenceScore >= 0.8) return Colors.green.shade50;
    return Colors.grey.shade50;
  }

  Color get _borderColor {
    final z = indicator.zScore;
    if (z != null && z.abs() >= 2.5) return Colors.red.shade300;
    if (z != null && z.abs() >= 2.0) return Colors.orange.shade300;
    if (indicator.convergenceScore >= 0.8) return Colors.green.shade300;
    return Colors.grey.shade300;
  }

  String get _statusIcon {
    if (indicator.isSignal) return '⚠️';
    if (indicator.convergenceScore >= 0.9) return '✅';
    if (indicator.convergenceScore >= 0.7) return '🔄';
    return '📊';
  }

  @override
  Widget build(BuildContext context) {
    final dev = indicator.devPp;
    final devStr = (dev >= 0 ? '+' : '') + dev.toStringAsFixed(1);
    final zStr = indicator.zScore != null
        ? '${indicator.zScore! >= 0 ? '+' : ''}${indicator.zScore!.toStringAsFixed(2)}σ'
        : '--';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _cardColor,
          border: Border.all(color: _borderColor),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_statusIcon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    indicator.name,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Mini convergence bar
            LinearProgressIndicator(
              value: indicator.convergenceScore,
              backgroundColor: Colors.grey.shade300,
              color: indicator.convergenceScore >= 0.8
                  ? Colors.green
                  : indicator.convergenceScore >= 0.6
                      ? Colors.orange
                      : Colors.red,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(height: 4),
            Text(
              '수렴도 ${(indicator.convergenceScore * 100).round()}%',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '편차 $devStr${indicator.unit == '%' ? 'pp' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: dev.abs() > 2 ? Colors.red.shade700 : Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Z $zStr',
                  style: TextStyle(
                    fontSize: 11,
                    color: indicator.isSignal ? Colors.red : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Analysis Tab
// ══════════════════════════════════════════════════════════

class _AnalysisTab extends StatelessWidget {
  final List<_IndicatorResult> indicators;
  final void Function(_IndicatorResult) onDetail;

  const _AnalysisTab({required this.indicators, required this.onDetail});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: indicators.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _AnalysisRow(indicator: indicators[i], onDetail: onDetail),
    );
  }
}

class _AnalysisRow extends StatelessWidget {
  final _IndicatorResult indicator;
  final void Function(_IndicatorResult) onDetail;

  const _AnalysisRow({required this.indicator, required this.onDetail});

  @override
  Widget build(BuildContext context) {
    final ind = indicator;
    final dev = ind.devPp;
    final devStr = (dev >= 0 ? '+' : '') + dev.toStringAsFixed(2);
    final obsStr = ind.unit == '%'
        ? '${(ind.observed * 100).toStringAsFixed(2)}%'
        : ind.unit == '점' || ind.unit == '개'
            ? ind.observed.toStringAsFixed(2)
            : ind.observed.toStringAsFixed(4);
    final baseStr = ind.unit == '%'
        ? '${(ind.baseline * 100).toStringAsFixed(2)}%'
        : ind.unit == '점' || ind.unit == '개'
            ? ind.baseline.toStringAsFixed(2)
            : ind.baseline.toStringAsFixed(4);

    return Card(
      child: InkWell(
        onTap: () => onDetail(ind),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ind.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  if (ind.isSignal)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('신호', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _chip('관측', obsStr, Colors.blue.shade700),
                  const SizedBox(width: 6),
                  _chip('랜덤 기준', baseStr, Colors.grey.shade700),
                  const SizedBox(width: 6),
                  _chip(
                    '편차 ${devStr}${ind.unit == '%' ? 'pp' : ''}',
                    '',
                    dev.abs() > 2 ? Colors.red.shade700 : Colors.green.shade700,
                    showLabel: false,
                  ),
                  const Spacer(),
                  if (ind.zScore != null)
                    Text(
                      'Z=${ind.zScore!.toStringAsFixed(2)}σ',
                      style: TextStyle(
                        fontSize: 12,
                        color: ind.isSignal ? Colors.red : Colors.grey,
                        fontWeight: ind.isSignal ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('수렴도', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: ind.convergenceScore,
                      backgroundColor: Colors.grey.shade200,
                      color: ind.convergenceScore >= 0.8 ? Colors.green : Colors.orange,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(ind.convergenceScore * 100).round()}%',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
              // Mini convergence line
              if (ind.history.length > 2) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 50,
                  child: _MiniConvergenceChart(indicator: ind),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String value, Color color,
      {bool showLabel = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        showLabel ? '$label: $value' : label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Convergence Chart (CustomPainter)
// ══════════════════════════════════════════════════════════

class _MiniConvergenceChart extends StatelessWidget {
  final _IndicatorResult indicator;
  const _MiniConvergenceChart({required this.indicator});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ConvChartPainter(indicator),
      size: const Size(double.infinity, 50),
    );
  }
}

class _ConvChartPainter extends CustomPainter {
  final _IndicatorResult ind;
  _ConvChartPainter(this.ind);

  @override
  void paint(Canvas canvas, Size size) {
    if (ind.history.length < 2) return;
    final history = ind.history;

    // Normalize values to [0,1] for chart
    final raw = history.map((p) => p.value).toList();
    final base = ind.baseline;
    final allVals = [...raw, base];
    final minV = allVals.reduce(min) * 0.95;
    final maxV = allVals.reduce(max) * 1.05;
    final range = maxV - minV;
    if (range == 0) return;

    double toY(double v) => size.height - ((v - minV) / range * size.height * 0.85 + size.height * 0.05);
    double toX(int i) => i / (history.length - 1) * (size.width - 20) + 10;

    // Baseline dashed line
    final basePaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final dashPath = Path();
    final by = toY(base);
    for (double x = 0; x < size.width; x += 8) {
      dashPath.moveTo(x, by);
      dashPath.lineTo(x + 4, by);
    }
    canvas.drawPath(dashPath, basePaint);

    // Actual line
    final actualPaint = Paint()
      ..color = Colors.blue.shade600
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final actualPath = Path();
    for (int i = 0; i < history.length; i++) {
      final x = toX(i);
      final y = toY(history[i].value);
      if (i == 0) actualPath.moveTo(x, y);
      else actualPath.lineTo(x, y);
    }
    canvas.drawPath(actualPath, actualPaint);

    // Points
    final ptPaint = Paint()
      ..color = Colors.blue.shade800
      ..style = PaintingStyle.fill;
    for (int i = 0; i < history.length; i++) {
      canvas.drawCircle(Offset(toX(i), toY(history[i].value)), 2.5, ptPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ══════════════════════════════════════════════════════════
// Indicator Detail Sheet
// ══════════════════════════════════════════════════════════

class _IndicatorDetailSheet extends StatelessWidget {
  final _IndicatorResult indicator;
  const _IndicatorDetailSheet({required this.indicator});

  @override
  Widget build(BuildContext context) {
    final ind = indicator;
    final dev = ind.devPp;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(ind.name, style: const TextStyle(fontSize: 16)),
          backgroundColor: Colors.deepPurple.shade700,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            )
          ],
        ),
        body: ListView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          children: [
            // Summary row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _numBox('관측값',
                    ind.unit == '%'
                        ? '${(ind.observed * 100).toStringAsFixed(2)}%'
                        : ind.observed.toStringAsFixed(3),
                    Colors.blue),
                _numBox('랜덤 기준',
                    ind.unit == '%'
                        ? '${(ind.baseline * 100).toStringAsFixed(2)}%'
                        : ind.baseline.toStringAsFixed(3),
                    Colors.grey),
                _numBox('편차',
                    '${dev >= 0 ? '+' : ''}${dev.toStringAsFixed(2)}${ind.unit == '%' ? 'pp' : ''}',
                    dev.abs() > 2 ? Colors.red : Colors.green),
                if (ind.zScore != null)
                  _numBox('Z-score', '${ind.zScore!.toStringAsFixed(2)}σ',
                      ind.isSignal ? Colors.red : Colors.blueGrey),
              ],
            ),
            const SizedBox(height: 16),
            // Convergence chart
            if (ind.history.length > 2) ...[
              const Text('수렴 이력', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: const EdgeInsets.all(8),
                child: CustomPaint(
                  painter: _DetailChartPainter(ind),
                  size: const Size(double.infinity, 144),
                ),
              ),
              // X axis labels
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: ind.history
                      .map((p) => Text('${p.round}',
                          style: const TextStyle(fontSize: 9, color: Colors.grey)))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Breakdown table
            if (ind.breakdown.isNotEmpty) ...[
              const Text('상세 분포', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...ind.breakdown.map((b) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                            width: 70,
                            child: Text(b.$1,
                                style: const TextStyle(fontSize: 12))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Stack(
                            children: [
                              // Baseline bar (gray)
                              FractionallySizedBox(
                                widthFactor: b.$3.clamp(0.0, 1.0),
                                child: Container(
                                    height: 16,
                                    color: Colors.grey.shade200),
                              ),
                              // Actual bar (blue)
                              FractionallySizedBox(
                                widthFactor: b.$2.clamp(0.0, 1.0),
                                child: Container(
                                    height: 16,
                                    color: Colors.blue.shade200.withOpacity(0.7)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 90,
                          child: Text(
                            '${(b.$2 * 100).toStringAsFixed(1)}% / ${(b.$3 * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 4),
              const Text('  실제 % / 기준 %', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _numBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class _DetailChartPainter extends CustomPainter {
  final _IndicatorResult ind;
  _DetailChartPainter(this.ind);

  @override
  void paint(Canvas canvas, Size size) {
    if (ind.history.length < 2) return;
    final history = ind.history;
    final raw = history.map((p) => p.value).toList();
    final base = ind.baseline;
    final allVals = [...raw, base];
    final minV = allVals.reduce(min) * 0.97;
    final maxV = allVals.reduce(max) * 1.03;
    final range = maxV - minV;
    if (range == 0) return;

    final pad = 8.0;
    double toY(double v) => size.height - pad - ((v - minV) / range * (size.height - 2 * pad));
    double toX(int i) => pad + i / (history.length - 1) * (size.width - 2 * pad);

    // Axis
    final axisPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;
    canvas.drawLine(Offset(pad, toY(base)), Offset(size.width - pad, toY(base)), axisPaint);

    // Baseline label
    final tp = TextPainter(
      text: TextSpan(
        text: '기준 ${ind.unit == '%' ? (base * 100).toStringAsFixed(1) + '%' : base.toStringAsFixed(2)}',
        style: const TextStyle(fontSize: 9, color: Color(0xFF888888)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - pad - tp.width, toY(base) - 12));

    // Shade area
    final shadePath = Path();
    shadePath.moveTo(toX(0), toY(history.first.value));
    for (int i = 1; i < history.length; i++) {
      shadePath.lineTo(toX(i), toY(history[i].value));
    }
    shadePath.lineTo(toX(history.length - 1), toY(base));
    shadePath.lineTo(toX(0), toY(base));
    shadePath.close();
    canvas.drawPath(
      shadePath,
      Paint()..color = Colors.blue.shade100.withOpacity(0.4),
    );

    // Actual line
    final linePaint = Paint()
      ..color = Colors.blue.shade600
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final linePath = Path();
    for (int i = 0; i < history.length; i++) {
      final x = toX(i);
      final y = toY(history[i].value);
      if (i == 0) linePath.moveTo(x, y);
      else linePath.lineTo(x, y);
    }
    canvas.drawPath(linePath, linePaint);

    // Points + values
    for (int i = 0; i < history.length; i++) {
      final x = toX(i);
      final y = toY(history[i].value);
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = Colors.blue.shade800);
      // Value label for last point
      if (i == history.length - 1) {
        final valStr = ind.unit == '%'
            ? '${(history.last.value * 100).toStringAsFixed(1)}%'
            : history.last.value.toStringAsFixed(2);
        final vt = TextPainter(
          text: TextSpan(
            text: valStr,
            style: const TextStyle(fontSize: 9, color: Color(0xFF1565C0), fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        vt.paint(canvas, Offset(x - vt.width / 2, y - 14));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ══════════════════════════════════════════════════════════
// Hypothesis Tab
// ══════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════
// Monte Carlo 연구 현황 탭 (수동 버튼 없음 — 엔진 자동 관리)
// ══════════════════════════════════════════════════════════

class _SimulationTab extends StatefulWidget {
  const _SimulationTab();

  @override
  State<_SimulationTab> createState() => _SimulationTabState();
}

class _SimulationTabState extends State<_SimulationTab> {
  McJobStats? _stats;
  List<McJob> _recentJobs = [];
  bool _loading = true;
  bool _baselineRefreshing = false;
  bool _schedulingAll = false;
  // 세션당 1회: 기준값 생성 + 미검증 가설 Random Control 자동 실행
  static bool _autoRanThisSession = false;
  bool _autoRunning = false;
  Map<String, dynamic>? _replay; // 500→최신 순차 연구 요약 (research_results)

  @override
  void initState() {
    super.initState();
    _load();
    HypothesisReplayEngine.instance.loadLatest().then((r) { if (mounted) setState(() => _replay = r); });
  }

  Widget _buildSequentialResearchCard() {
    final r = _replay;
    if (r == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
        child: const Text('순차 연구(500→최신) 결과가 아직 저장되지 않았습니다. 앱 실행 시 자동으로 수행됩니다.',
            style: TextStyle(fontSize: 12, color: Color(0xFF777777))),
      );
    }
    final post = Map<String, dynamic>.from(r['post_accept'] as Map? ?? {});
    final ho = Map<String, dynamic>.from(r['holdout'] as Map? ?? {});
    final eng = Map<String, dynamic>.from(r['engine_style'] as Map? ?? {});
    String pct(dynamic v) => v == null ? '-' : '${((v as num) * 100).toStringAsFixed(1)}%';
    String pv(dynamic v) => v == null ? '-' : (v as num) < 0.0001 ? '<0.0001' : (v as num).toStringAsFixed(4);
    final z = (post['z'] as num?)?.toDouble();
    Widget row(String k, String v, {Color? c}) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 118, child: Text(k, style: const TextStyle(fontSize: 11, color: Color(0xFF777777)))),
            Expanded(child: Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c ?? const Color(0xFF333333)))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.timeline_rounded, size: 16, color: Color(0xFF283593)),
          const SizedBox(width: 6),
          Expanded(child: Text('순차 연구 ${r['start_round']}→${r['end_round']}회 (가설 생성→다음 회차 보정 반복)',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF283593)))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
            child: const Text('완료', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        row('처리 회차', '${r['rounds_replayed']}회차 · 회차별 로그 ${r['round_logs_count'] ?? '-'}건 (DB 저장 ${r['round_logs_persisted'] ?? 0}건 신규 / ${r['round_logs_existing'] ?? 0}건 기존)'),
        row('가설', '발견 ${r['hypotheses_total']} · 채택 경험 ${r['ever_accepted']} · 상태 ${r['status_counts']}'),
        row('검증 표본 (채택 후)', '${post['n']}회 · 적중 ${pct(post['rate'])} vs 무작위 ${pct(post['baseline'])}'),
        row('유의성', 'z=${z == null ? '-' : z.toStringAsFixed(2)} · p=${pv(post['p'])} · Holm 유의 가설 ${r['significant_holm']}개',
            c: z != null && z > 1.96 ? Colors.teal.shade800 : Colors.red.shade700),
        row('홀드아웃 ${ho['from_round'] ?? ''}회~', '${ho['n'] ?? 0}회 · 적중 ${pct(ho['rate'])} vs ${pct(ho['baseline'])} · p=${pv(ho['p'])}'),
        row('엔진 방식(매 회차)', '${eng['n']}회 · ${pct(eng['rate'])} vs ${pct(eng['baseline'])} (참고)'),
        const SizedBox(height: 6),
        Text('${r['note']}', style: const TextStyle(fontSize: 10, color: Color(0xFF555555), height: 1.4)),
        const Text('Monte Carlo(아래)는 가설 검증 보조수단이며 번호 예측의 주력 가중치로 쓰지 않습니다.',
            style: TextStyle(fontSize: 10, color: Color(0xFF555555), height: 1.4)),
      ]),
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    if (!_autoRanThisSession) {
      _autoRanThisSession = true;
      if (mounted) setState(() { _autoRunning = true; _loading = false; });
      try {
        await MonteCarloEngine.instance.scheduleUnverifiedHypotheses();
        await MonteCarloEngine.instance.processQueueBatch(maxJobs: 30);
      } catch (_) {}
      if (mounted) setState(() { _autoRunning = false; _loading = true; });
    }
    try {
      final results = await Future.wait<dynamic>([
        MonteCarloEngine.instance.getStats(),
        MonteCarloEngine.instance.getRecentJobs(limit: 30),
      ]);
      if (mounted) setState(() {
        _stats = results[0] as McJobStats;
        _recentJobs = results[1] as List<McJob>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forceBaselineRefresh() async {
    if (_baselineRefreshing) return;
    setState(() => _baselineRefreshing = true);
    try {
      await MonteCarloEngine.instance.refreshBaseline();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Random Baseline 재생성 완료')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')));
      }
    }
    if (mounted) setState(() => _baselineRefreshing = false);
  }

  Future<void> _scheduleAllUnverified() async {
    if (_schedulingAll) return;
    setState(() => _schedulingAll = true);
    try {
      await MonteCarloEngine.instance.scheduleUnverifiedHypotheses();
      await MonteCarloEngine.instance.processQueueBatch(maxJobs: 10);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('미검증 가설 Random Control 예약 완료')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    }
    if (mounted) setState(() => _schedulingAll = false);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildRoleCard(),
          const SizedBox(height: 12),
          _buildSequentialResearchCard(),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            _buildBaselineCard(),
            const SizedBox(height: 12),
            _buildJobQueueCard(),
            const SizedBox(height: 12),
            _buildHypVerifiedCard(),
            const SizedBox(height: 12),
            _buildRecentJobsList(),
            const SizedBox(height: 16),
            _buildAdvancedSection(),
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }

  Widget _buildRoleCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.deepPurple.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.deepPurple.shade100),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Monte Carlo 연구 현황',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15,
              color: Color(0xFF4527A0))),
      const SizedBox(height: 6),
      const Text(
        'Monte Carlo는 예측의 주인공이 아닌 엔진의 보조 검증 도구입니다.\n'
        '• Random Control: 발견된 가설이 랜덤에서도 흔한 현상인지 검증\n'
        '• Auxiliary Signal: 현재 가설 기반 보조 시뮬레이션 참고자료 생성\n'
        '엔진이 자동으로 실행합니다. 정상 운영에서 수동 실행은 불필요합니다.',
        style: TextStyle(fontSize: 12, color: Color(0xFF555555), height: 1.5),
      ),
    ]),
  );

  Widget _buildBaselineCard() {
    final b = _stats?.baseline;
    final isStale = b == null || b.isEmpty || b.isStale;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isStale ? Colors.orange.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isStale ? Colors.orange.shade200 : Colors.green.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            isStale ? Icons.warning_rounded : Icons.check_circle_rounded,
            size: 16,
            color: isStale ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 6),
          const Text('Random Baseline',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const Spacer(),
          if (b != null && !b.isEmpty)
            Text(
              '${b.simulationCount ~/ 1000}만회 시뮬',
              style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
            ),
        ]),
        const SizedBox(height: 8),
        if (b == null || b.isEmpty)
          const Text('기준값 없음 — 아직 생성되지 않았습니다.',
              style: TextStyle(fontSize: 12, color: Colors.orange))
        else if (b.isStale)
          Text(
            '마지막 생성: ${_fmtDate(b.computedAt)} (30일 이상 경과)',
            style: const TextStyle(fontSize: 12, color: Colors.orange),
          )
        else ...[
          Text(
            '마지막 생성: ${_fmtDate(b.computedAt)}',
            style: const TextStyle(fontSize: 12, color: Colors.green),
          ),
          const SizedBox(height: 6),
          Row(children: [
            _baselineChip('홀짝3:3', '${(b.oddEven33 * 100).toStringAsFixed(2)}%'),
            const SizedBox(width: 6),
            _baselineChip('저고3:3', '${(b.lowHigh33 * 100).toStringAsFixed(2)}%'),
            const SizedBox(width: 6),
            _baselineChip('연속', '${(b.consecutive * 100).toStringAsFixed(2)}%'),
          ]),
        ],
      ]),
    );
  }

  Widget _baselineChip(String label, String val) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.green.shade300),
    ),
    child: Text('$label $val',
        style: const TextStyle(fontSize: 10, color: Color(0xFF2E7D32),
            fontWeight: FontWeight.w600)),
  );

  Widget _buildJobQueueCard() {
    final s = _stats;
    if (s == null) return const SizedBox.shrink();
    final isIdle = s.isIdle;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Job 큐 상태',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const Spacer(),
          if (!isIdle)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('실행 중',
                  style: TextStyle(fontSize: 10, color: Colors.blue,
                      fontWeight: FontWeight.w700)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('대기 없음 ✓',
                  style: TextStyle(fontSize: 10, color: Colors.green,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _jobCountChip('대기', s.queued, Colors.orange),
          const SizedBox(width: 8),
          _jobCountChip('실행중', s.running, Colors.blue),
          const SizedBox(width: 8),
          _jobCountChip('실패', s.failed, Colors.red),
        ]),
        if (s.lastCompletedAt != null) ...[
          const SizedBox(height: 8),
          Text('마지막 완료: ${_fmtDate(s.lastCompletedAt!)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF888888))),
        ],
        if (_autoRunning) ...[
          const SizedBox(height: 8),
          Row(children: const [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 6),
            Text('연구중 · 기준값 생성 및 미검증 가설 Random Control 실행 중',
                style: TextStyle(fontSize: 12, color: Color(0xFFE65100), fontWeight: FontWeight.w700)),
          ]),
        ] else if (isIdle && s.queued == 0) ...[
          const SizedBox(height: 8),
          const Text('완료 · 현재 실행 중인 검증 없음. 화면 진입·새 회차 완료 시 자동 실행됩니다.',
              style: TextStyle(fontSize: 12, color: Color(0xFF777777))),
        ],
      ]),
    );
  }

  Widget _jobCountChip(String label, int count, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
            color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: color,
            fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  Widget _buildHypVerifiedCard() {
    final verified = _stats?.totalHypothesesVerified ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('가설 Random Control 결과',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.science_rounded, size: 18, color: Color(0xFF7B2FF7)),
          const SizedBox(width: 8),
          Text('검증 완료 가설 $verified건',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        const Text(
          '각 가설이 순수 랜덤보다 실제로 유의미한지 이항분포 검정으로 확인합니다.\n'
          '결과는 가설 상세 카드의 "MC 검증" 항목에서 확인할 수 있습니다.',
          style: TextStyle(fontSize: 12, color: Color(0xFF777777), height: 1.4),
        ),
      ]),
    );
  }

  Widget _buildRecentJobsList() {
    if (_recentJobs.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('최근 Job 목록',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 10),
        ..._recentJobs.take(15).map(_buildJobRow),
      ]),
    );
  }

  Widget _buildJobRow(McJob job) {
    final statusColor = switch (job.status) {
      McJobStatus.completed => Colors.green,
      McJobStatus.running => Colors.blue,
      McJobStatus.failed => Colors.red,
      McJobStatus.queued => Colors.orange,
      _ => Colors.grey,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            job.hypothesisId != null
                ? '가설 ${job.hypothesisId!.substring(0, 8)}... Random Control'
                : job.typeLabel,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(job.statusLabel,
            style: TextStyle(fontSize: 11, color: statusColor,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Text(_fmtDate(job.createdAt),
            style: const TextStyle(fontSize: 10, color: Color(0xFF999999))),
      ]),
    );
  }

  Widget _buildAdvancedSection() => ExpansionTile(
    title: const Text('고급 관리',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
            color: Color(0xFF888888))),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(children: [
          const Text(
            '정상 운영에서는 아래 버튼을 누를 필요가 없습니다.\n'
            '앱 재설치 등으로 Baseline이 소실된 경우에만 사용하세요.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _baselineRefreshing ? null : _forceBaselineRefresh,
              icon: _baselineRefreshing
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 16),
              label: Text(_baselineRefreshing
                  ? 'Random Baseline 재생성 중...'
                  : 'Random Baseline 강제 재생성 (50,000회)'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _schedulingAll ? null : _scheduleAllUnverified,
              icon: _schedulingAll
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.science_outlined, size: 16),
              label: Text(_schedulingAll
                  ? '가설 검증 예약 중...'
                  : '미검증 가설 전체 Random Control 예약'),
            ),
          ),
        ]),
      ),
    ],
  );

  String _fmtDate(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ══════════════════════════════════════════════════════════
// Phase 2: 가설 연구소 탭
// ══════════════════════════════════════════════════════════

class _HypothesisLabTab extends StatefulWidget {
  final List<RpaHypV3> hypothesesV3;
  final List<LottoWinningNumber> allData;
  final int latestRound;
  final VoidCallback onRefresh;

  const _HypothesisLabTab({
    required this.hypothesesV3,
    required this.allData,
    required this.latestRound,
    required this.onRefresh,
  });

  @override
  State<_HypothesisLabTab> createState() => _HypothesisLabTabState();
}

class _HypothesisLabTabState extends State<_HypothesisLabTab> {
  bool _meetingRunning = false;
  bool _meetingDone = false;
  final List<MeetingStep> _log = [];
  final _scrollCtrl = ScrollController();
  String? _statusFilter;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _startMeeting() async {
    if (_meetingRunning) return;
    setState(() {
      _meetingRunning = true;
      _meetingDone = false;
      _log.clear();
    });

    try {
      await for (final step in HypothesisEngine.instance.runMeeting(
        widget.allData,
        widget.latestRound,
      )) {
        if (!mounted) break;
        setState(() => _log.add(step));
        // 자동 스크롤 없음 — 읽는 위치를 유지하고 사용자가 직접 스크롤한다
        // 로그가 길어지지 않게 약간의 지연
        await Future.delayed(const Duration(milliseconds: 80));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _log.add(MeetingStep(type: 'error', message: '오류: $e')));
      }
    }

    if (mounted) {
      setState(() {
        _meetingRunning = false;
        _meetingDone = true;
      });
      widget.onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final allHyps = widget.hypothesesV3;
    final filtered = _statusFilter == null
        ? allHyps
        : allHyps.where((h) => h.status == _statusFilter).toList();

    final active = filtered
        .where((h) => ['discovered', 'observing', 'validating', 'developing'].contains(h.status))
        .toList();
    final strong = filtered
        .where((h) => ['accepted'].contains(h.status))
        .toList();
    final weak = filtered
        .where((h) => ['weakened'].contains(h.status))
        .toList();
    final combined = filtered
        .where((h) => h.status == 'combined')
        .toList();
    final rejected = filtered
        .where((h) => h.status == 'rejected')
        .toList();

    final filterStatuses = <String?>[null, 'accepted', 'discovered', 'observing',
        'validating', 'developing', 'weakened', 'combined', 'rejected'];
    final filterLabels = <String?>[
      '전체', '수용됨', '발견됨', '관찰중', '검증중', '발전중', '약화됨', '결합됨', '폐기됨'
    ];

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ── 회의실 ──────────────────────────────────────
          _LabMeetingSection(
            running: _meetingRunning,
            done: _meetingDone,
            log: _log,
            latestRound: widget.latestRound,
            dataCount: widget.allData.length,
            scrollCtrl: _scrollCtrl,
            onStart: _startMeeting,
          ),
          const SizedBox(height: 16),

          // 통계 요약
          _LabStatRow(hypothesesV3: widget.hypothesesV3),
          const SizedBox(height: 12),

          // 상태 필터
          SizedBox(
            height: 32,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: filterStatuses.length,
              itemBuilder: (_, i) {
                final s = filterStatuses[i];
                final lbl = filterLabels[i]!;
                final selected = _statusFilter == s;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _statusFilter = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: selected ? Colors.deepPurple : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? Colors.deepPurple : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(lbl,
                          style: TextStyle(
                              fontSize: 11,
                              color: selected ? Colors.white : Colors.grey.shade700,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          if (active.isEmpty && strong.isEmpty && weak.isEmpty &&
              combined.isEmpty && rejected.isEmpty)
            _emptyHint()
          else ...[
            if (strong.isNotEmpty) ...[
              _labSectionHeader('✅ 검증됨 / 수용됨', strong.length, Colors.green),
              ...strong.map((h) => _HypV3Card(h: h)),
              const SizedBox(height: 16),
            ],
            if (active.isNotEmpty) ...[
              _labSectionHeader('🔬 연구 중', active.length, Colors.deepPurple),
              ...active.map((h) => _HypV3Card(h: h)),
              const SizedBox(height: 16),
            ],
            if (weak.isNotEmpty) ...[
              _labSectionHeader('⚠️ 약화됨', weak.length, Colors.orange),
              ...weak.map((h) => _HypV3Card(h: h)),
              const SizedBox(height: 16),
            ],
            if (combined.isNotEmpty) ...[
              _labSectionHeader('🔗 결합됨', combined.length, Colors.indigo),
              ...combined.map((h) => _HypV3Card(h: h)),
              const SizedBox(height: 16),
            ],
            if (rejected.isNotEmpty) ...[
              _labSectionHeader('🗑 폐기됨', rejected.length, Colors.red.shade400),
              ...rejected.map((h) => _HypV3Card(h: h)),
              const SizedBox(height: 16),
            ],
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _emptyHint() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.science_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            '회차 데이터가 들어오면 자동으로 가설 탐색이 진행됩니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _labSectionHeader(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$count', style: TextStyle(color: color, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

// ── 자동 분석 상태 표시 카드 ───────────────────────────────
class _AutoStatusCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int lastRound;
  final int patternCount;
  final int predCount;

  const _AutoStatusCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.lastRound,
    required this.patternCount,
    required this.predCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(
            lastRound > 0
                ? '$lastRound회 기준 자동 분석 완료 · 패턴 $patternCount개 · 예측 $predCount건'
                : '엔진 자동 실행 대기 중',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ])),
        Icon(Icons.check_circle_rounded,
            size: 16,
            color: patternCount > 0 ? Colors.green.shade400 : Colors.grey.shade300),
      ]),
    );
  }
}

// ── 회의실 위젯 ────────────────────────────────────────────
class _LabMeetingSection extends StatelessWidget {
  final bool running;
  final bool done;
  final List<MeetingStep> log;
  final int latestRound;
  final int dataCount;
  final ScrollController scrollCtrl;
  final VoidCallback onStart;

  const _LabMeetingSection({
    required this.running,
    required this.done,
    required this.log,
    required this.latestRound,
    required this.dataCount,
    required this.scrollCtrl,
    required this.onStart,
  });

  Color _stepColor(MeetingStep s) {
    switch (s.type) {
      case 'ts_result': return s.data is RpaTsResult && (s.data as RpaTsResult).isSignificant
          ? Colors.orange.shade700 : Colors.grey.shade600;
      case 'pattern_found': return Colors.deepPurple.shade700;
      case 'hyp_created': return Colors.green.shade700;
      case 'hyp_updated': return Colors.blue.shade600;
      case 'hyp_discarded': return Colors.red.shade500;
      case 'hyp_exists': return Colors.grey.shade500;
      case 'complete': return Colors.green.shade800;
      case 'error': return Colors.red.shade800;
      case 'no_patterns': return Colors.grey.shade400;
      default: return Colors.deepPurple.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: running ? Colors.deepPurple.shade400 : Colors.deepPurple.shade200,
          width: running ? 2 : 1,
        ),
        color: Colors.deepPurple.shade50.withValues(alpha: 0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.groups_outlined, color: Colors.deepPurple.shade500, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('가설 연구 회의',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.deepPurple.shade700)),
                      Text(
                        '$latestRound회차 기준 · 시계열 분석 → 패턴 탐색 → 가설 생성/진화',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (running)
                  const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: onStart,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      side: BorderSide(color: Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('강제 재실행', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),

          // 로그
          if (log.isNotEmpty) ...[
            const Divider(height: 1),
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SingleChildScrollView(
                controller: scrollCtrl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: log.map((s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      s.message,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _stepColor(s),
                        fontWeight: s.type == 'complete' || s.type == 'info' && s.message.startsWith('[')
                            ? FontWeight.bold : FontWeight.normal,
                        fontFamily: 'monospace',
                      ),
                    ),
                  )).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 통계 요약 바 ────────────────────────────────────────────
class _LabStatRow extends StatelessWidget {
  final List<RpaHypV3> hypothesesV3;
  const _LabStatRow({required this.hypothesesV3});

  @override
  Widget build(BuildContext context) {
    final total = hypothesesV3.length;
    final accepted = hypothesesV3.where((h) => h.status == 'accepted').length;
    final observing = hypothesesV3.where((h) => ['discovered','observing','validating'].contains(h.status)).length;
    final weakened = hypothesesV3.where((h) => h.status == 'weakened').length;

    return Row(
      children: [
        _stat('전체', '$total', Colors.grey),
        const SizedBox(width: 8),
        _stat('수용', '$accepted', Colors.green),
        const SizedBox(width: 8),
        _stat('연구중', '$observing', Colors.deepPurple),
        const SizedBox(width: 8),
        _stat('약화', '$weakened', Colors.orange),
      ],
    );
  }

  Widget _stat(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(val, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }
}

// ── 개별 가설 카드 (V3) ────────────────────────────────────
class _HypV3Card extends StatefulWidget {
  final RpaHypV3 h;
  const _HypV3Card({required this.h});

  @override
  State<_HypV3Card> createState() => _HypV3CardState();
}

class _HypV3CardState extends State<_HypV3Card> {
  bool _expanded = false;

  static Color _statusColor(String s) {
    switch (s) {
      case 'accepted': return Colors.green;
      case 'validating': return Colors.teal;
      case 'observing': return Colors.blue;
      case 'discovered': return Colors.deepPurple;
      case 'weakened': return Colors.orange;
      case 'developing': return Colors.cyan;
      case 'combined': return Colors.indigo;
      case 'rejected': return Colors.red;
      default: return Colors.grey;
    }
  }

  static String _statusLabel(String s) {
    const m = {
      'discovered': '발견됨',
      'observing': '관찰중',
      'validating': '검증중',
      'developing': '발전중',
      'accepted': '수용됨',
      'weakened': '약화됨',
      'combined': '결합됨',
      'rejected': '폐기됨',
    };
    return m[s] ?? s;
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.h;
    final sc = _statusColor(h.status);
    final phenom = h.expectedPhenomenon;
    final phenInd = phenom['indicator'] as String? ?? '';
    final phenDir = phenom['direction'] as String? ?? 'above';
    const indNames = {
      'oe33': '홀짝3:3', 'lh33': '저고3:3', 'cons': '연속번호',
      'sp': '합짝수', 'rhi': '범위폭↑', 'phi': '소수개수↑',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: sc.withValues(alpha: 0.4), width: 1.5),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 헤더 행 ──
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: sc.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_statusLabel(h.status),
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold, color: sc)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${indNames[phenInd] ?? phenInd}(${phenDir == 'above' ? '↑' : '↓'}) @+${h.horizon}회',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 6),

              // ── 생애주기 진행 표시 ──
              _LifecycleStrip(status: h.status),
              const SizedBox(height: 8),

              // ── 핵심 수치 ──
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _chip('발견 ${h.createdRound}회', Colors.grey),
                  _chip('과거 ${h.historicalSampleCount}건', Colors.grey),
                  _chip('성공률 ${(h.historicalSuccessRate * 100).toStringAsFixed(1)}%',
                      h.historicalSuccessRate >= 0.65 ? Colors.green : Colors.orange),
                  if (h.futureVerificationCount > 0)
                    _chip('미래검증 ${h.futureSuccessCount}/${h.futureVerificationCount}',
                        h.futureSuccessRate >= 0.6 ? Colors.green : Colors.orange),
                  _chip('가중치 ${h.currentWeight.toStringAsFixed(2)}', Colors.deepPurple),
                  if (h.monteCarloRandomRate != null)
                    _chip('MC기준 ${(h.monteCarloRandomRate! * 100).toStringAsFixed(1)}%', Colors.blueGrey),
                ],
              ),

              // ── 펼쳐진 상세 ──
              if (_expanded) ...[
                const Divider(height: 16),

                // 조건
                if (h.triggerConditions.isNotEmpty) ...[
                  Text('발동 조건',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: h.triggerConditions.entries.map((e) {
                      final dir = e.value;
                      final color = dir == 'above' ? Colors.blue : dir == 'below' ? Colors.orange : Colors.grey;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '${indNames[e.key] ?? e.key}: ${dir == 'above' ? '↑' : dir == 'below' ? '↓' : '→'}',
                          style: TextStyle(fontSize: 11, color: color),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                ],

                // 근거
                if (h.evidence.isNotEmpty) ...[
                  Text('근거', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(h.evidence, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800)),
                  const SizedBox(height: 8),
                ],

                // 이벤트 이력
                if (h.events.isNotEmpty) ...[
                  Text('회의 기록',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ...h.events.reversed.take(6).map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${e.round}회: ',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontFamily: 'monospace')),
                        Expanded(
                          child: Text(e.summary,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: e.eventType == 'verification' && e.summary.contains('적중')
                                      ? Colors.green.shade700
                                      : e.eventType == 'verification'
                                          ? Colors.red.shade400
                                          : Colors.grey.shade700)),
                        ),
                      ],
                    ),
                  )).toList(),
                  if (h.events.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('... 외 ${h.events.length - 6}건',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }
}

// ── 생애주기 진행 표시 위젯 ───────────────────────────────
class _LifecycleStrip extends StatelessWidget {
  final String status;
  const _LifecycleStrip({required this.status});

  static const _mainStages = ['discovered', 'observing', 'validating', 'developing', 'accepted'];
  static const _mainLabels = ['발견', '관찰', '검증', '발전', '채택'];
  static const _altEndStages = ['weakened', 'combined', 'rejected'];
  static const _altEndLabels = ['약화', '결합', '폐기'];
  static const _altEndColors = [Colors.orange, Colors.indigo, Colors.red];

  @override
  Widget build(BuildContext context) {
    final isAltEnd = _altEndStages.contains(status);
    final mainIdx = _mainStages.indexOf(status);

    return Row(
      children: [
        for (int i = 0; i < _mainStages.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(height: 1.5,
                  color: i <= (isAltEnd ? _mainStages.length : mainIdx)
                      ? Colors.deepPurple.shade200
                      : Colors.grey.shade200),
            ),
          _StageNode(
            label: _mainLabels[i],
            active: isAltEnd ? true : i <= mainIdx,
            current: !isAltEnd && i == mainIdx,
            color: Colors.deepPurple,
          ),
        ],
        if (isAltEnd) ...[
          const SizedBox(width: 4),
          const Text('→', style: TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(width: 2),
          () {
            final idx = _altEndStages.indexOf(status);
            return _StageNode(
              label: _altEndLabels[idx],
              active: true,
              current: true,
              color: _altEndColors[idx] as Color,
            );
          }(),
        ],
      ],
    );
  }
}

class _StageNode extends StatelessWidget {
  final String label;
  final bool active;
  final bool current;
  final Color color;
  const _StageNode({required this.label, required this.active,
      required this.current, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: current
            ? color.withValues(alpha: 0.2)
            : active
                ? color.withValues(alpha: 0.08)
                : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: current ? color : active ? color.withValues(alpha: 0.3) : Colors.grey.shade200,
          width: current ? 1.5 : 1,
        ),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9,
              color: current ? color : active ? color.withValues(alpha: 0.7) : Colors.grey.shade400,
              fontWeight: current ? FontWeight.bold : FontWeight.normal)),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Store Model Tab (Phase 3)
// ══════════════════════════════════════════════════════════

class _StoreModelTab extends StatefulWidget {
  final StoreModelState? storeModelState;
  final int latestRound;
  final VoidCallback onRefresh;

  const _StoreModelTab({
    required this.storeModelState,
    required this.latestRound,
    required this.onRefresh,
  });

  @override
  State<_StoreModelTab> createState() => _StoreModelTabState();
}

class _StoreModelTabState extends State<_StoreModelTab> {
  bool _analysisRunning = false;
  bool _analysisDone = false;
  final List<StoreAnalysisStep> _log = [];
  List<Map<String, dynamic>> _recentPreds = [];
  List<StoreSpatialPattern> _patterns = [];
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final preds = await StoreModelEngine.instance.loadRecentPredictions();
      final patterns = await StoreModelEngine.instance.loadPatterns();
      if (mounted) {
        setState(() {
          _recentPreds = preds;
          _patterns = patterns;
        });
      }
    } catch (_) {}
  }

  Future<void> _runAnalysis() async {
    if (_analysisRunning) return;
    setState(() {
      _analysisRunning = true;
      _analysisDone = false;
      _log.clear();
    });

    try {
      final history = await StoreModelEngine.instance.loadWinHistory();
      await for (final step
          in StoreModelEngine.instance.runAnalysis(history, widget.latestRound)) {
        if (!mounted) break;
        setState(() => _log.add(step));
        await Future.delayed(const Duration(milliseconds: 100));
        // 자동 스크롤 없음 — 읽는 위치 유지
      }
    } catch (e) {
      if (mounted) {
        setState(() => _log.add(StoreAnalysisStep(
            title: '오류', detail: e.toString(), isError: true)));
      }
    }

    if (mounted) {
      setState(() { _analysisRunning = false; _analysisDone = true; });
      await _loadData();
      widget.onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.storeModelState;

    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      children: [
        // 상태 카드
        _StoreStateCard(state: state),
        const SizedBox(height: 16),

        // 자동 분석 상태 표시
        _AutoStatusCard(
          icon: Icons.map_outlined,
          color: Colors.teal,
          label: '공간 전이 분석',
          lastRound: widget.latestRound,
          patternCount: _patterns.length,
          predCount: _recentPreds.length,
        ),
        const SizedBox(height: 8),
        // 고급 관리 — 강제 재분석
        ExpansionTile(
          title: const Text('고급 관리 — 강제 재분석', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
          subtitle: const Text('정상 운영 시 불필요. 데이터 이상 시에만 사용.', style: TextStyle(fontSize: 11, color: Colors.grey)),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _analysisRunning ? null : _runAnalysis,
                icon: _analysisRunning
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh_rounded),
                label: Text(_analysisRunning ? '공간 분석 실행 중...' : '강제 재분석'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),

        // 분석 로그
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('분석 로그',
                    style: TextStyle(
                        color: Colors.teal.shade300,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ..._log.map((step) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            step.isError
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            size: 14,
                            color: step.isError
                                ? Colors.red.shade400
                                : Colors.teal.shade400,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: RichText(
                              text: TextSpan(children: [
                                TextSpan(
                                    text: '${step.title}  ',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600)),
                                TextSpan(
                                    text: step.detail,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade400)),
                              ]),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],

        // 패턴 목록
        if (_patterns.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('공간 전이 패턴 (horizon별 최강)',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._buildPatternRows(),
        ],

        // 최근 예측
        if (_recentPreds.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('최근 Store 예측',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._recentPreds.take(8).map((p) => _PredRow(pred: p)),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  List<Widget> _buildPatternRows() {
    // horizon별 가장 높은 lift 패턴 하나씩
    final best = <int, StoreSpatialPattern>{};
    for (final p in _patterns) {
      if (!best.containsKey(p.horizon) ||
          p.lift > best[p.horizon]!.lift) {
        best[p.horizon] = p;
      }
    }
    return [1, 2, 3, 4, 5, 6].map((k) {
      final p = best[k];
      if (p == null) {
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('+$k회  —  데이터 없음',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        );
      }
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.lift > 1.5
              ? Colors.teal.shade50
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: p.lift > 1.5
                  ? Colors.teal.shade200
                  : Colors.grey.shade200),
        ),
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.teal.shade700,
              shape: BoxShape.circle,
            ),
            child: Text('+$k',
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.distanceBand,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(
                      '출현율 ${(p.successRate * 100).toStringAsFixed(1)}%'
                      ' | 기준 ${(p.mcRandomRate * 100).toStringAsFixed(1)}%'
                      ' | ${p.totalOccurrences}회차',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: p.lift > 1.5
                  ? Colors.teal.shade100
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('lift ${p.lift.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 11,
                    color: p.lift > 1.5
                        ? Colors.teal.shade800
                        : Colors.grey.shade700,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }).toList();
  }
}

class _StoreStateCard extends StatelessWidget {
  final StoreModelState? state;
  const _StoreStateCard({this.state});

  @override
  Widget build(BuildContext context) {
    if (state == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, color: Colors.orange.shade700),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '아직 Store 분석 결과가 없습니다.\n새 회차의 당첨번호·판매점 수집이 끝나면 엔진이 자동으로 분석합니다.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ]),
      );
    }

    final regionAcc = state!.replayRegionAccuracy;
    final spatialAcc = state!.replaySpatialAccuracy;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade700, Colors.teal.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.store_outlined, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Text('Store Model v4',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('학습 ${state!.lastTrainedRound}회차',
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _statBox('패턴', '${state!.patternCount}개'),
          const SizedBox(width: 8),
          _statBox('활성 가설', '${state!.activeHypothesisCount}개'),
          const SizedBox(width: 8),
          _statBox('테스트', '${state!.totalTestRounds}회차'),
        ]),
        if (regionAcc != null || spatialAcc != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            if (regionAcc != null)
              _statBox('지역 정확도',
                  '${(regionAcc * 100).toStringAsFixed(1)}%'),
            if (regionAcc != null) const SizedBox(width: 8),
            if (spatialAcc != null)
              _statBox('공간 정확도',
                  '${(spatialAcc * 100).toStringAsFixed(1)}%'),
          ]),
        ],
      ]),
    );
  }

  Widget _statBox(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 10)),
          ]),
        ),
      );
}

class _PredRow extends StatelessWidget {
  final Map<String, dynamic> pred;
  const _PredRow({required this.pred});

  @override
  Widget build(BuildContext context) {
    final target = pred['target_round'] as int? ?? 0;
    final horizon = pred['horizon'] as int? ?? 0;
    final status = pred['status'] as String? ?? 'pending';
    final regionHit = pred['region_hit'] as bool?;
    final spatialHit = pred['spatial_hit'] as bool?;
    final score = pred['spatial_score'] as Map<String, dynamic>? ?? {};
    final bestBand = score['best_distance_band'] as String? ?? '-';
    final candidates = List<String>.from(
        pred['candidate_regions'] as List? ?? []);

    Color statusColor;
    String statusLabel;
    if (status == 'pending') {
      statusColor = Colors.orange.shade600;
      statusLabel = '대기';
    } else {
      final hit = (regionHit ?? false) || (spatialHit ?? false);
      statusColor = hit ? Colors.green.shade600 : Colors.grey.shade500;
      statusLabel = hit ? '적중' : '미적중';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$target회차 (+$horizon)',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          Text(
              '예측 구간: $bestBand'
              '${candidates.isNotEmpty ? " | ${candidates.first}" : ""}',
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade600)),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          ),
          child: Text(statusLabel,
              style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Joint Model Tab (Phase 4)
// ══════════════════════════════════════════════════════════

class _JointModelTab extends StatefulWidget {
  final JointModelState? jointModelState;
  final int latestRound;
  final List<LottoWinningNumber> allData;
  final VoidCallback onRefresh;

  const _JointModelTab({
    required this.jointModelState,
    required this.latestRound,
    required this.allData,
    required this.onRefresh,
  });

  @override
  State<_JointModelTab> createState() => _JointModelTabState();
}

class _JointModelTabState extends State<_JointModelTab> {
  bool _running = false;
  final List<JointAnalysisStep> _log = [];
  List<NumberRegionPattern> _nrPatterns = [];
  List<Map<String, dynamic>> _recentPreds = [];
  final _scrollCtrl = ScrollController();

  // Walk-Forward Historical Validation
  WalkForwardSummary? _wfSummary;
  bool _wfRunning = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadWalkForwardSummary();
    // Walk-Forward 자동 초기화 (미완료 시 백그라운드 실행)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.allData.isNotEmpty) {
        _autoInitWalkForward();
      }
    });
    // 저장된 정확도가 없으면 자동 재분석
    final s = widget.jointModelState;
    if (s != null &&
        widget.allData.isNotEmpty &&
        (s.storeModelAccuracy == null || s.jointModelAccuracy == null ||
            (s.numberModelAccuracy != null && s.numberModelAccuracy! < 0.01))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runAnalysis();
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final patterns = await JointModelEngine.instance.loadNRPatterns();
      final preds = await JointModelEngine.instance.loadRecentPredictions();
      if (mounted) setState(() { _nrPatterns = patterns; _recentPreds = preds; });
    } catch (_) {}
  }

  Future<void> _loadWalkForwardSummary() async {
    final summary = await JointHistoricalEngine.instance.loadSummary();
    if (mounted) setState(() => _wfSummary = summary);
  }

  Future<void> _autoInitWalkForward() async {
    final summary = await JointHistoricalEngine.instance.loadSummary();
    // 이미 완료됐거나 실행 중이면 스킵
    if (summary != null && (summary.isCompleted || summary.isRunning)) {
      if (mounted) setState(() => _wfSummary = summary);
      return;
    }
    // 모델 버전 변경 감지
    final outdated = await JointHistoricalEngine.instance.isModelVersionOutdated();
    if (summary != null && !summary.needsRun && !outdated) {
      if (mounted) setState(() => _wfSummary = summary);
      return;
    }
    // 백그라운드에서 전체 Historical Replay 실행
    if (mounted) setState(() { _wfRunning = true; _wfSummary = const WalkForwardSummary(status: 'running'); });
    try {
      final storeHistory = await StoreModelEngine.instance.loadWinHistory();
      final result = await JointHistoricalEngine.instance.runHistoricalReplay(
        allNums: widget.allData,
        storeHistory: storeHistory,
        onProgress: (done, total) {
          if (mounted && total > 0) {
            setState(() => _wfSummary = WalkForwardSummary(
              status: 'running',
              totalRounds: total,
              processedRounds: done,
            ));
          }
        },
      );
      if (mounted) setState(() { _wfSummary = result; _wfRunning = false; });
    } catch (e) {
      if (mounted) setState(() {
        _wfSummary = WalkForwardSummary(status: 'failed', error: e.toString());
        _wfRunning = false;
      });
    }
  }

  // 패턴 상태: (레이블, 색상)
  // regionCount + lift 기반으로 신뢰도 단계 분류
  (String, Color) _patternState(NumberRegionPattern p) {
    if (p.regionCount >= 50 && p.lift >= 1.4) return ('LIVE', Colors.green.shade600);
    if (p.regionCount >= 30 && p.lift >= 1.3) return ('검증완료', Colors.blue.shade600);
    if (p.regionCount >= 15) return ('검증중', Colors.orange.shade600);
    if (p.regionCount >= 8) return ('관찰', Colors.amber.shade700);
    return ('발견', Colors.grey.shade600);
  }

  Future<void> _runWalkForward() async {
    if (_wfRunning || widget.allData.isEmpty) return;
    setState(() { _wfRunning = true; _wfSummary = const WalkForwardSummary(status: 'running'); });
    try {
      final storeHistory = await StoreModelEngine.instance.loadWinHistory();
      final summary = await JointHistoricalEngine.instance.runHistoricalReplay(
        allNums: widget.allData,
        storeHistory: storeHistory,
        onProgress: (done, total) {
          if (mounted && total > 0) {
            setState(() => _wfSummary = WalkForwardSummary(
              status: 'running',
              totalRounds: total,
              processedRounds: done,
            ));
          }
        },
      );
      if (mounted) setState(() { _wfSummary = summary; _wfRunning = false; });
    } catch (e) {
      if (mounted) setState(() {
        _wfSummary = WalkForwardSummary(status: 'failed', error: e.toString());
        _wfRunning = false;
      });
    }
  }

  Future<void> _runAnalysis() async {
    if (_running) return;
    setState(() { _running = true; _log.clear(); });

    try {
      final storeHistory = await StoreModelEngine.instance.loadWinHistory();
      await for (final step in JointModelEngine.instance.runAnalysis(
        allNumbers: widget.allData,
        storeHistory: storeHistory,
        currentRound: widget.latestRound,
      )) {
        if (!mounted) break;
        setState(() => _log.add(step));
        await Future.delayed(const Duration(milliseconds: 80));
        // 자동 스크롤 없음 — 읽는 위치 유지
      }
    } catch (e) {
      if (mounted) setState(() => _log.add(
        JointAnalysisStep(title: '오류', detail: e.toString(), isError: true)));
    }

    if (mounted) {
      setState(() => _running = false);
      await _loadData();
      widget.onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.jointModelState;
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      children: [
        // Synergy 상태 카드
        _JointStateCard(state: state),
        const SizedBox(height: 16),

        // Walk-Forward Historical Validation 카드
        _WalkForwardCard(
          summary: _wfSummary,
          running: _wfRunning,
          onRun: widget.allData.isEmpty ? null : _runWalkForward,
        ),
        const SizedBox(height: 16),

        // 자동 분석 상태 표시
        _AutoStatusCard(
          icon: Icons.merge_type_rounded,
          color: Colors.deepPurple,
          label: 'Joint 번호×지역 분석',
          lastRound: widget.latestRound,
          patternCount: _nrPatterns.length,
          predCount: _recentPreds.length,
        ),
        const SizedBox(height: 8),
        // 고급 관리 — 강제 재분석
        ExpansionTile(
          title: const Text('고급 관리 — 강제 재분석', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
          subtitle: const Text('정상 운영 시 불필요. 데이터 이상 시에만 사용.', style: TextStyle(fontSize: 11, color: Colors.grey)),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _running ? null : _runAnalysis,
                icon: _running
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh_rounded),
                label: Text(_running ? 'Joint 분석 실행 중...' : '강제 재분석'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),

        // 로그
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('분석 로그', style: TextStyle(
                    color: Colors.deepPurple.shade200, fontSize: 12,
                    fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ..._log.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(s.isError ? Icons.error_outline : Icons.check_circle_outline,
                        size: 14,
                        color: s.isError ? Colors.red.shade400 : Colors.deepPurple.shade300),
                    const SizedBox(width: 6),
                    Expanded(child: RichText(text: TextSpan(children: [
                      TextSpan(text: '${s.title}  ',
                          style: const TextStyle(fontSize: 12, color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      TextSpan(text: s.detail,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                    ]))),
                  ]),
                )),
              ],
            ),
          ),
        ],

        // 번호×지역 패턴 상위 10개
        if (_nrPatterns.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('번호×지역 패턴 (신뢰도 가중 정렬)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._nrPatterns.take(10).map((p) {
            final state = _patternState(p);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: state.$2.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: state.$2.withOpacity(0.3)),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: state.$2.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(state.$1,
                          style: TextStyle(fontSize: 9,
                              color: state.$2, fontWeight: FontWeight.w700)),
                    ),
                    Flexible(child: Text(
                      '합${p.sumBand} 홀${p.oddBand} 범위${p.rangeBand}'
                      '${p.hasConsecutive ? " 연속" : ""}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    )),
                  ]),
                  const SizedBox(height: 3),
                  Text('→ ${p.regionSido}  |  ${p.totalRounds}회차 중 ${p.regionCount}회',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: state.$2.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('lift ${p.lift.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 11,
                          color: state.$2, fontWeight: FontWeight.w700)),
                ),
              ]),
            );
          }),
        ],

        // 최근 Joint 예측
        if (_recentPreds.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('최근 Joint 예측',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ..._recentPreds.take(8).map((p) => _JointPredRow(pred: p)),
        ],

        const SizedBox(height: 40),
      ],
    );
  }
}

class _JointStateCard extends StatelessWidget {
  final JointModelState? state;
  const _JointStateCard({this.state});

  @override
  Widget build(BuildContext context) {
    if (state == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.deepPurple.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.deepPurple.shade100),
        ),
        child: Row(children: [
          Icon(Icons.hub_outlined, color: Colors.deepPurple.shade400),
          const SizedBox(width: 10),
          const Expanded(child: Text(
            'Joint 분석을 아직 실행하지 않았습니다.\n분석을 실행하면 번호×지역 패턴과 Synergy 점수를 계산합니다.',
            style: TextStyle(fontSize: 12),
          )),
        ]),
      );
    }

    final s = state!;
    final synergyColor = s.synergyScore == null
        ? Colors.grey
        : s.synergyScore! > 0 ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.hub_outlined, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Text('Joint Model v5', style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.white24,
                borderRadius: BorderRadius.circular(20)),
            child: Text('학습 ${s.lastTrainedRound}회차',
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 12),
        // 3개 모델 비교
        Row(children: [
          _acc('Number', s.numberModelAccuracy),
          const SizedBox(width: 8),
          _acc('Store', s.storeModelAccuracy),
          const SizedBox(width: 8),
          _acc('Joint', s.jointModelAccuracy),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: synergyColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(children: [
              Text(
                s.synergyScore == null
                    ? (s.storeModelAccuracy == null || s.jointModelAccuracy == null
                        ? 'Store/Joint\n검증 대기'
                        : '계산 대기')
                    : '${s.synergyScore! >= 0 ? "+" : ""}${(s.synergyScore! * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const Text('Synergy', style: TextStyle(color: Colors.white70, fontSize: 10)),
            ]),
          )),
          const SizedBox(width: 8),
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: Colors.white12,
                borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              Text('${s.nrPatternCount}개',
                  style: const TextStyle(color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const Text('번호×지역 패턴', style: TextStyle(color: Colors.white70, fontSize: 10)),
            ]),
          )),
        ]),
      ]),
    );
  }

  Widget _acc(String label, double? val) {
    String display;
    Color textColor;
    if (val == null) {
      display = '검증 대기';
      textColor = Colors.white38;
    } else if (val < 0.01) {
      display = '표본 부족';
      textColor = Colors.orange.shade300;
    } else {
      display = '${(val * 100).toStringAsFixed(1)}%';
      textColor = Colors.white;
    }
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: Colors.white12,
          borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        Text(display,
            style: TextStyle(color: textColor, fontSize: 13,
                fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ]),
    ));
  }
}

class _JointPredRow extends StatelessWidget {
  final Map<String, dynamic> pred;
  const _JointPredRow({required this.pred});

  @override
  Widget build(BuildContext context) {
    final target = pred['target_round'] as int? ?? 0;
    final horizon = pred['horizon'] as int? ?? 0;
    final status = pred['status'] as String? ?? 'pending';
    final jointHit = pred['joint_hit'] as bool?;
    final candidates = List<String>.from(
        pred['joint_candidate_regions'] as List? ?? []);
    final methodHint = pred['purchase_method_hint'] as String?;
    final score = ((pred['joint_score'] as num?) ?? 0.5).toDouble();

    Color statusColor;
    String statusLabel;
    if (status == 'pending') {
      statusColor = Colors.orange.shade600;
      statusLabel = '대기';
    } else {
      statusColor = (jointHit ?? false) ? Colors.green.shade600 : Colors.grey.shade500;
      statusLabel = (jointHit ?? false) ? '적중' : '미적중';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$target회차 (+$horizon)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          Text(
            [
              if (candidates.isNotEmpty) candidates.take(2).join(', '),
              if (methodHint != null) methodHint,
              'score ${(score * 100).toStringAsFixed(0)}%',
            ].join(' | '),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          ),
          child: Text(statusLabel, style: TextStyle(
              fontSize: 11, color: statusColor, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// _RoundFlowPanel — 회차 데이터 흐름 시각화
// ══════════════════════════════════════════════════════════

class _RoundFlowPanel extends StatefulWidget {
  final VoidCallback? onReadyGateDetected;
  const _RoundFlowPanel({this.onReadyGateDetected});

  @override
  State<_RoundFlowPanel> createState() => _RoundFlowPanelState();
}

class _RoundFlowPanelState extends State<_RoundFlowPanel> {
  List<RpaRoundGate> _gates = [];
  bool _loading = true;
  Map<int, bool> _predExists = {};
  bool _repairing = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // ready/processing 게이트가 있는 동안 8초마다 자동 새로고침
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      if (_gates.any((g) =>
          g.engineStatus == 'ready' || g.engineStatus == 'processing')) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = Supabase.instance.client;
      final rows = await db
          .from('rpa_round_gate')
          .select()
          .order('round', ascending: false)
          .limit(3);

      final gates = (rows as List)
          .map((r) => RpaRoundGate.fromJson(r as Map<String, dynamic>))
          .toList();

      // 각 회차의 실제 Prediction 존재 여부 확인 (gate.round+1 Number Pred)
      final Map<int, bool> predMap = {};
      for (final g in gates) {
        try {
          final predRows = await db
              .from('rpa_prediction_snapshots')
              .select('id')
              .eq('training_end_round', g.round)
              .eq('target_round', g.round + 1)
              .eq('model_version', kRpaActiveModelVersion)
              .limit(1);
          predMap[g.round] = (predRows as List).isNotEmpty;
        } catch (_) {
          predMap[g.round] = false;
        }
      }

      if (!mounted) return;
      setState(() {
        _gates = gates;
        _predExists = predMap;
        _loading = false;
      });

      // ready 게이트 발견 시 엔진 자동 트리거
      final hasUnprocessedReady = gates.any(
        (g) => g.engineStatus == 'ready' && predMap[g.round] == false,
      );
      if (hasUnprocessedReady) widget.onReadyGateDetected?.call();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _repair(RpaRoundGate gate) async {
    if (_repairing) return;
    setState(() => _repairing = true);
    try {
      final allData = await SupabaseService.getAllWinningNumbers();
      final roundData = allData.where((d) => d.round == gate.round).firstOrNull;
      if (roundData != null) {
        await RpaEngine.instance.repairRound(
          targetRound: roundData,
          allData: allData,
        );
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _repairing = false);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }
    if (_gates.isEmpty) return const SizedBox.shrink();

    final displayGates = _gates.take(2).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 15,
                    color: Colors.deepPurple.shade400),
                const SizedBox(width: 5),
                Text('회차 데이터 흐름',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                        color: Colors.deepPurple.shade600)),
                const Spacer(),
                if (_repairing)
                  const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  GestureDetector(
                    onTap: _load,
                    child: Icon(Icons.refresh, size: 15, color: Colors.grey.shade400),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...displayGates.map((g) => _RoundFlowRow(
            gate: g,
            hasPrediction: _predExists[g.round],
            onRepair: _repairing ? null : () => _repair(g),
          )),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _RoundFlowRow extends StatelessWidget {
  final RpaRoundGate gate;
  final bool? hasPrediction; // null = 로딩 중, true/false = 실제 값
  final VoidCallback? onRepair;
  const _RoundFlowRow({
    required this.gate,
    this.hasPrediction,
    this.onRepair,
  });

  Color _statusColor(String s) {
    switch (s) {
      case 'completed': return Colors.green.shade600;
      case 'processing': return Colors.blue.shade600;
      case 'ready': return Colors.teal.shade600;
      case 'waiting_store': return Colors.orange.shade600;
      case 'failed': return Colors.red.shade600;
      default: return Colors.orange.shade600; // waiting_number
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'completed': return '학습 완료';
      case 'processing': return '처리 중';
      case 'ready': return '실행 대기';
      case 'waiting_store': return '판매점 대기';
      case 'failed': return '오류';
      default: return '번호 대기';
    }
  }

  String _statusEmoji(String s) {
    switch (s) {
      case 'completed': return '✨';
      case 'processing': return '⚙️';
      case 'ready': return '▶️';
      case 'waiting_store': return '🔒';
      case 'failed': return '❌';
      default: return '⏳';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sc = _statusColor(gate.engineStatus);
    final sl = _statusLabel(gate.engineStatus);
    final em = _statusEmoji(gate.engineStatus);
    final nextRound = gate.round + 1; // 항상 이 회차의 +1 예측 대상
    final isCompleted = gate.engineStatus == 'completed';
    final isProcessing = gate.engineStatus == 'processing';
    final isWaitingStore = gate.engineStatus == 'waiting_store';
    final isWaitingNumber = gate.engineStatus == 'waiting_number';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: sc.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: sc.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더: 회차 + 상태
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${gate.round}회',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            const SizedBox(width: 8),
            Text('$em $sl',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: sc)),
            if (isProcessing) ...[
              const SizedBox(width: 6),
              const SizedBox(width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5)),
            ],
          ]),
          const SizedBox(height: 8),

          // 흐름 단계들
          _flowStep('🎱', '당첨번호', gate.hasWinningNumbers,
              waiting: isWaitingNumber && !gate.hasWinningNumbers),
          _flowStep('🏪', '당첨판매점', gate.hasStoreData,
              waitingLabel: '크롤링 대기',
              waiting: isWaitingStore && !gate.hasStoreData),
          _flowStep('⚡', '데이터 준비',
              gate.hasWinningNumbers && gate.hasStoreData,
              waiting: isWaitingStore || isWaitingNumber),
          _flowStep('🧠', '엔진 분석',
              isCompleted || isProcessing,
              inProgress: isProcessing,
              waiting: gate.engineStatus == 'ready'),

          if (isCompleted) ...[
            const SizedBox(height: 4),
            if (hasPrediction == true)
              Row(children: [
                const Text('  🔮 ', style: TextStyle(fontSize: 12)),
                Text('$nextRound회 예측 완료 ✓',
                    style: TextStyle(fontSize: 11, color: Colors.green.shade700,
                        fontWeight: FontWeight.w700)),
              ])
            else if (hasPrediction == false) ...[
              Row(children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                const SizedBox(width: 4),
                Text('$nextRound회 예측 미생성',
                    style: const TextStyle(fontSize: 11, color: Colors.orange,
                        fontWeight: FontWeight.w700)),
                if (onRepair != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onRepair,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: const Text('복구 실행',
                          style: TextStyle(fontSize: 10, color: Colors.deepOrange,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ]),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Text('completed이지만 실제 Prediction 없음 (v6 백필 오류)',
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
              ),
            ] else
              Row(children: [
                const Text('  🔮 ', style: TextStyle(fontSize: 12)),
                Text('$nextRound회 예측 확인 중...',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
          ] else if (isProcessing) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Text('  🔮 ', style: TextStyle(fontSize: 12)),
              Text('$nextRound회 예측 생성 중...',
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade600,
                      fontWeight: FontWeight.w600)),
            ]),
          ],

          if (isWaitingStore) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text('당첨번호와 1등 판매점이 모두 준비되면 자동 실행합니다',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _flowStep(String icon, String label, bool done, {
    bool inProgress = false,
    bool waiting = false,
    String? waitingLabel,
  }) {
    final Color color;
    final String suffix;
    if (done) {
      color = Colors.green.shade600;
      suffix = ' ✓';
    } else if (inProgress) {
      color = Colors.blue.shade600;
      suffix = ' ⚙️';
    } else if (waiting) {
      color = Colors.orange.shade600;
      suffix = ' ⏳ ${waitingLabel ?? '대기'}';
    } else {
      color = Colors.grey.shade400;
      suffix = '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(children: [
        Text('  $icon ', style: const TextStyle(fontSize: 12)),
        Text(label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        Text(suffix, style: TextStyle(fontSize: 10, color: color)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// _RoundGateSection — 회차 데이터 준비 게이트 상태 표시
// ══════════════════════════════════════════════════════════

class _RoundGateSection extends StatefulWidget {
  const _RoundGateSection();

  @override
  State<_RoundGateSection> createState() => _RoundGateSectionState();
}

class _RoundGateSectionState extends State<_RoundGateSection> {
  List<RpaRoundGate> _gates = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // ready/processing 게이트가 있는 동안 10초마다 자동 갱신
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      if (_gates.any((g) =>
          g.engineStatus == 'ready' || g.engineStatus == 'processing')) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final db = Supabase.instance.client;
      final rows = await db
          .from('rpa_round_gate')
          .select()
          .order('round', ascending: false)
          .limit(10);
      if (!mounted) return;
      setState(() {
        _gates = (rows as List)
            .map((r) => RpaRoundGate.fromJson(r as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_gates.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.lock_clock_outlined, size: 15, color: Color(0xFF5E35B1)),
        const SizedBox(width: 5),
        const Text('회차 데이터 준비 현황',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                color: Color(0xFF5E35B1))),
        const Spacer(),
        GestureDetector(
          onTap: () { setState(() => _loading = true); _load(); },
          child: const Icon(Icons.refresh, size: 16, color: Colors.grey),
        ),
      ]),
      const SizedBox(height: 6),
      ...(_gates.map((g) => _GateRow(gate: g))),
    ]);
  }
}

class _GateRow extends StatelessWidget {
  final RpaRoundGate gate;
  const _GateRow({required this.gate});

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    final String statusLabel;
    switch (gate.engineStatus) {
      case 'completed':
        statusColor = Colors.green.shade600; statusLabel = '학습 완료'; break;
      case 'processing':
        statusColor = Colors.blue.shade600; statusLabel = '처리 중'; break;
      case 'ready':
        statusColor = Colors.teal.shade600; statusLabel = '실행 대기'; break;
      case 'waiting_store':
        statusColor = Colors.orange.shade600; statusLabel = '판매점 대기'; break;
      case 'failed':
        statusColor = Colors.red.shade600; statusLabel = '오류'; break;
      default:
        statusColor = Colors.grey.shade500; statusLabel = '번호 대기';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Text('${gate.round}회', style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 10),
        _dot(gate.hasWinningNumbers, '당첨번호'),
        const SizedBox(width: 8),
        _dot(gate.hasStoreData, '판매점'),
        const SizedBox(width: 8),
        Text(gate.crawlStatus == 'success' ? '크롤링 ✓' : '크롤링 ${gate.crawlStatus}',
            style: TextStyle(fontSize: 10,
                color: gate.crawlStatus == 'success' ? Colors.green.shade700 : Colors.orange.shade700)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          ),
          child: Text(statusLabel, style: TextStyle(
              fontSize: 11, color: statusColor, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _dot(bool ok, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
        size: 13, color: ok ? Colors.green.shade600 : Colors.grey.shade400),
    const SizedBox(width: 3),
    Text(label, style: TextStyle(fontSize: 10,
        color: ok ? Colors.green.shade700 : Colors.grey.shade500)),
  ]);
}

// ══════════════════════════════════════════════════════════════
// Walk-Forward Historical Validation 카드
// ══════════════════════════════════════════════════════════════

class _WalkForwardCard extends StatelessWidget {
  final WalkForwardSummary? summary;
  final bool running;
  final VoidCallback? onRun;

  const _WalkForwardCard({this.summary, required this.running, this.onRun});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final isCompleted = s?.isCompleted == true;
    final isRunning = running || s?.isRunning == true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCompleted
              ? [Colors.indigo.shade900, Colors.deepPurple.shade900]
              : [Colors.grey.shade900, Colors.grey.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted ? Colors.indigo.shade700 : Colors.grey.shade700,
          width: 1.2,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 헤더
        Row(children: [
          Icon(Icons.history_rounded,
              color: isCompleted ? Colors.indigo.shade300 : Colors.grey.shade500,
              size: 18),
          const SizedBox(width: 8),
          const Text('Walk-Forward 과거 검증',
              style: TextStyle(color: Colors.white,
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (isRunning)
            const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white54))
          else if (!isCompleted)
            _badge('미실행', Colors.orange.shade700),
          if (isCompleted)
            _badge('완료 ${s!.totalRounds}회', Colors.indigo.shade700),
        ]),

        // 설명
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          child: Text(
            isCompleted
                ? '1244회차 중 실제 당첨 지역 데이터가 있는 ${s!.totalRounds}회차를 '
                  '과거 데이터만으로 예측하고 정확도를 측정했습니다.\n'
                  'Number/Store/Joint 모두 out-of-sample Walk-Forward 결과입니다.'
                : '각 회차를 과거 데이터만으로 예측해 실제와 비교합니다.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ),

        if (isCompleted && s != null) ...[
          // 정확도 3개 + Synergy
          Row(children: [
            _accBox('Number', s.nrAccuracy, Colors.blue),
            const SizedBox(width: 8),
            _accBox('Store', s.storeAccuracy, Colors.teal),
            const SizedBox(width: 8),
            _accBox('Joint', s.jointAccuracy, Colors.deepPurple),
            const SizedBox(width: 8),
            _synergyBox(s.synergy),
          ]),
          const SizedBox(height: 10),
          // 적중 수
          Text(
            'Number ${s.nrHits}/${s.totalRounds}  '
            '| Store ${s.storeHits}/${s.totalRounds}  '
            '| Joint ${s.jointHits}/${s.totalRounds}',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ] else if (isRunning && s != null && s.totalRounds > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: s.totalRounds > 0
                  ? (s.processedRounds / s.totalRounds).clamp(0.0, 1.0)
                  : null,
              backgroundColor: Colors.grey.shade800,
              color: Colors.indigo.shade400,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text('${s.processedRounds} / ${s.totalRounds} 회차 처리 중...',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        ] else if (s?.hasFailed == true) ...[
          Text('오류: ${s!.error ?? "알 수 없음"}',
              style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
        ],

        // 실행 버튼 (완료가 아니거나 재실행 원할 때)
        if (!isRunning && !isCompleted) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRun,
              icon: const Icon(Icons.play_arrow_rounded, size: 16),
              label: const Text('Walk-Forward 검증 실행'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],

        if (isCompleted) ...[
          const SizedBox(height: 10),
          ExpansionTile(
            title: const Text('재실행',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 4),
            expandedAlignment: Alignment.centerLeft,
            children: [
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onRun,
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text('Walk-Forward 재실행'),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ]),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(20)),
    child: Text(label,
        style: const TextStyle(
            fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
  );

  Widget _accBox(String label, double? acc, MaterialColor color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.shade800),
      ),
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 9, color: color.shade400)),
        const SizedBox(height: 3),
        Text(
          acc == null
              ? '-'
              : acc < 0.01
                  ? '표본 부족'
                  : '${(acc * 100).toStringAsFixed(1)}%',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: acc == null || acc < 0.01
                  ? Colors.white38
                  : acc >= 0.45
                      ? color.shade300
                      : Colors.white70),
        ),
      ]),
    ),
  );

  Widget _synergyBox(double? synergy) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: synergy == null
              ? Colors.grey.shade800
              : synergy > 0
                  ? Colors.green.shade900
                  : Colors.red.shade900,
        ),
      ),
      child: Column(children: [
        Text('Synergy',
            style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
        const SizedBox(height: 3),
        Text(
          synergy == null
              ? '-'
              : '${synergy >= 0 ? "+" : ""}${(synergy * 100).toStringAsFixed(1)}%',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: synergy == null
                  ? Colors.white38
                  : synergy > 0
                      ? Colors.greenAccent
                      : Colors.redAccent),
        ),
      ]),
    ),
  );
}
