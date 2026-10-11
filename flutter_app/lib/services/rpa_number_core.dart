// ══════════════════════════════════════════════════════════
// RPA Number Engine 핵심 계산 (순수 Dart — Flutter/DB 의존 없음)
//
// rpa_engine.dart(앱 실행)와 tool/verify_unified_prediction.dart(검증 스크립트)가
// 동일한 코드로 Number Base를 계산하도록 분리한 모듈입니다.
// 이 파일의 계산 로직을 바꾸면 반드시 kRpaActiveModelVersion을 올려야 합니다.
// ══════════════════════════════════════════════════════════

import 'dart:math';

import '../models/lotto_winning_number.dart';

const rpaPrimes45 = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43};

// 6개 이진 지표 ID
// oe33: 홀 3개인가    baseline=33.48%
// lh33: 저번호 3개    baseline=33.48%
// cons: 연속 1쌍+     baseline=52.87%
// sp:   합 짝수       baseline=50%
// rhi:  범위폭>32.86  baseline≈50%
// phi:  소수 개수>1.87 baseline≈50%
const rpaIndicatorIds = ['oe33', 'lh33', 'cons', 'sp', 'rhi', 'phi'];

const rpaIndicatorBaselines = {
  'oe33': 0.3348,
  'lh33': 0.3348,
  'cons': 0.5287,
  'sp': 0.5000,
  'rhi': 0.5000,
  'phi': 0.5000,
};

const rpaIndicatorLabels = {
  'oe33': '홀짝3:3',
  'lh33': '저고3:3',
  'cons': '연속번호',
  'sp': '합 짝수',
  'rhi': '범위 넓음',
  'phi': '소수 2+',
};

/// 회차 번호의 6개 지표 실제값 (0/1)
Map<String, double> rpaActualIndicatorValues(List<int> numbers) {
  final nums = List.of(numbers)..sort();
  final odds = nums.where((x) => x % 2 == 1).length;
  bool hasC = false;
  for (int i = 0; i < nums.length - 1; i++) {
    if (nums[i + 1] - nums[i] == 1) { hasC = true; break; }
  }
  final s = nums.reduce((a, b) => a + b);
  final rw = nums.last - nums.first;
  final pc = nums.where(rpaPrimes45.contains).length;
  return {
    'oe33': odds == 3 ? 1.0 : 0.0,
    'lh33': nums.where((x) => x <= 22).length == 3 ? 1.0 : 0.0,
    'cons': hasC ? 1.0 : 0.0,
    'sp': s % 2 == 0 ? 1.0 : 0.0,
    'rhi': rw > 32.86 ? 1.0 : 0.0,
    'phi': pc > 1.87 ? 1.0 : 0.0,
  };
}

/// 조합 단위 지표 이진값 (추천 조합 필터용)
int rpaIndicatorBinary(List<int> nums, String id) {
  final s = List.of(nums)..sort();
  switch (id) {
    case 'oe33': return s.where((x) => x % 2 == 1).length == 3 ? 1 : 0;
    case 'lh33': return s.where((x) => x <= 22).length == 3 ? 1 : 0;
    case 'cons': {
      for (int i = 0; i < s.length - 1; i++) {
        if (s[i + 1] - s[i] == 1) return 1;
      }
      return 0;
    }
    case 'sp':  return s.reduce((a, b) => a + b) % 2 == 0 ? 1 : 0;
    case 'rhi': return (s.last - s.first) > 32 ? 1 : 0;
    case 'phi': return s.where(rpaPrimes45.contains).length >= 2 ? 1 : 0;
    default: return 0;
  }
}

/// 조합이 지표 방향 조건을 모두 만족하는지
bool rpaMatchesDirs(List<int> nums, Map<String, String> dirs) {
  for (final e in dirs.entries) {
    if (e.value == 'neutral') continue;
    final v = rpaIndicatorBinary(nums, e.key);
    if (e.value == 'above' && v == 0) return false;
    if (e.value == 'below' && v == 1) return false;
  }
  return true;
}

/// 방향 예측 채점 (지표별 1/0/0.5)
Map<String, double> rpaScoreDirections(
  Map<String, String> finalDirs,
  List<int> actualNumbers,
) {
  final actualVals = rpaActualIndicatorValues(actualNumbers);
  final scores = <String, double>{};
  for (final id in rpaIndicatorIds) {
    final predicted = finalDirs[id] ?? 'neutral';
    final av = actualVals[id] ?? 0.5;
    final actualAbove = av > (rpaIndicatorBaselines[id] ?? 0.5);
    if (predicted == 'neutral') {
      scores[id] = 0.5;
    } else if (predicted == 'above') {
      scores[id] = actualAbove ? 1.0 : 0.0;
    } else {
      scores[id] = actualAbove ? 0.0 : 1.0;
    }
  }
  return scores;
}

double rpaMeanScore(Map<String, double> scores) {
  if (scores.isEmpty) return 0.5;
  return scores.values.reduce((a, b) => a + b) / scores.length;
}

// ══════════════════════════════════════════════════════════
// Rolling State (순차 계산용)
// ══════════════════════════════════════════════════════════

class RpaRollingState {
  int n = 0;
  int _oe33 = 0, _lh33 = 0, _cons = 0, _sp = 0, _rhi = 0, _phi = 0;

  final List<Map<String, double>> _window = [];
  static const _windowSize = 20;

  final Map<String, List<bool>> _recentAccuracy = {
    for (final id in rpaIndicatorIds) id: [],
  };
  static const _accuracyWindow = 10;

  final Map<String, bool> activeFlips = {
    for (final id in rpaIndicatorIds) id: false,
  };

  void addRound(LottoWinningNumber w) {
    final rv = rpaActualIndicatorValues(w.numbers);
    n++;
    if (rv['oe33'] == 1.0) _oe33++;
    if (rv['lh33'] == 1.0) _lh33++;
    if (rv['cons'] == 1.0) _cons++;
    if (rv['sp'] == 1.0) _sp++;
    if (rv['rhi'] == 1.0) _rhi++;
    if (rv['phi'] == 1.0) _phi++;
    _window.add(rv);
    if (_window.length > _windowSize) _window.removeAt(0);
  }

  Map<String, double> cumulativeRates() {
    if (n == 0) return {for (final id in rpaIndicatorIds) id: 0.5};
    return {
      'oe33': _oe33 / n,
      'lh33': _lh33 / n,
      'cons': _cons / n,
      'sp': _sp / n,
      'rhi': _rhi / n,
      'phi': _phi / n,
    };
  }

  double _slope(String id) {
    if (_window.length < 5) return 0;
    final vals = _window.map((w) => w[id] ?? 0.0).toList();
    final n_ = vals.length.toDouble();
    final sumX = n_ * (n_ - 1) / 2;
    final sumX2 = n_ * (n_ - 1) * (2 * n_ - 1) / 6;
    final sumY = vals.reduce((a, b) => a + b);
    final sumXY = List.generate(vals.length, (i) => i * vals[i])
        .reduce((a, b) => a + b);
    final denom = n_ * sumX2 - sumX * sumX;
    if (denom == 0) return 0;
    return (n_ * sumXY - sumX * sumY) / denom;
  }

  Map<String, String> theoryDirections() {
    const threshold = 0.012;
    final rates = cumulativeRates();
    final dirs = <String, String>{};
    for (final id in rpaIndicatorIds) {
      final slope = _slope(id);
      final rate = rates[id] ?? 0.5;
      final b = rpaIndicatorBaselines[id] ?? 0.5;
      final deviation = rate - b;
      if (slope > threshold || deviation > 0.05) {
        dirs[id] = 'above';
      } else if (slope < -threshold || deviation < -0.05) {
        dirs[id] = 'below';
      } else {
        dirs[id] = 'neutral';
      }
    }
    return dirs;
  }

  Map<String, String> finalDirections(Map<String, String> theory) {
    final result = Map<String, String>.from(theory);
    for (final id in rpaIndicatorIds) {
      if (activeFlips[id] == true) {
        final t = theory[id];
        if (t == 'above') {
          result[id] = 'below';
        } else if (t == 'below') {
          result[id] = 'above';
        }
      }
    }
    return result;
  }

  void recordResult(
    Map<String, String> finalDirs,
    Map<String, double> actualValues,
  ) {
    for (final id in rpaIndicatorIds) {
      final predicted = finalDirs[id] ?? 'neutral';
      final actual = actualValues[id];
      if (actual == null) continue;
      final actualAbove = actual > (rpaIndicatorBaselines[id] ?? 0.5);
      final correct = predicted == 'neutral'
          ? true
          : (predicted == 'above' ? actualAbove : !actualAbove);
      final hist = _recentAccuracy[id]!;
      hist.add(correct);
      if (hist.length > _accuracyWindow) hist.removeAt(0);
    }
    _updateFlips();
  }

  void _updateFlips() {
    for (final id in rpaIndicatorIds) {
      final hist = _recentAccuracy[id]!;
      if (hist.length < _accuracyWindow) continue;
      final acc = hist.where((x) => x).length / hist.length;
      if (acc < 0.35) {
        activeFlips[id] = !(activeFlips[id] ?? false);
      } else if (acc > 0.65) {
        activeFlips[id] = false;
      }
    }
  }
}

// ══════════════════════════════════════════════════════════
// Number Base: 1~45 전체 번호 평가
// ══════════════════════════════════════════════════════════

/// 지표 조건 일치 회차의 번호 빈도로 1~45를 평가합니다.
/// hypothesisBoost: Gate PASS 가설에서만 계산된 보정값 (0~0.3).
/// boostHypothesisIds: 보정에 기여한 가설 ID (근거 추적용)
List<Map<String, dynamic>> rpaComputeNumberEvaluations(
  List<LottoWinningNumber> trainingData,
  Map<String, String> finalDirs, {
  double hypothesisBoost = 0.0,
  int activeHypCount = 0,
  List<String> boostHypothesisIds = const [],
}) {
  final matching =
      trainingData.where((r) => rpaMatchesDirs(r.numbers, finalDirs)).toList();
  final totalMatchRounds = matching.length;
  final recentCutoff = totalMatchRounds * 2 ~/ 3;

  final Map<int, double> freq = {for (int i = 1; i <= 45; i++) i: 0.0};
  final Map<int, int> matchCount = {for (int i = 1; i <= 45; i++) i: 0};
  final Map<int, int> recentMatchCount = {for (int i = 1; i <= 45; i++) i: 0};

  for (int i = 0; i < matching.length; i++) {
    final isRecent = i >= recentCutoff;
    final weight = isRecent ? 2.0 : 1.0;
    for (final num in matching[i].numbers) {
      freq[num] = (freq[num] ?? 0.0) + weight;
      matchCount[num] = (matchCount[num] ?? 0) + 1;
      if (isRecent) recentMatchCount[num] = (recentMatchCount[num] ?? 0) + 1;
    }
  }

  final maxFreq = freq.values.fold(0.0, (a, b) => a > b ? a : b);
  // v2.1: 동점은 번호 오름차순 (v2.0은 불안정 정렬이라 실행 환경마다 동점 순서가 달랐음)
  final entries = freq.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });

  return entries.asMap().entries.map((entry) {
    final rank = entry.key + 1;
    final num = entry.value.key;
    final rawScore = maxFreq > 0
        ? double.parse((entry.value.value / maxFreq).toStringAsFixed(3))
        : 0.0;

    double finalScore;
    if (rank <= 18) {
      finalScore = rawScore * (1.0 + hypothesisBoost * (1.0 - rank / 45.0));
    } else if (rank > 30) {
      finalScore = rawScore * (1.0 - hypothesisBoost * (rank / 45.0));
    } else {
      finalScore = rawScore;
    }
    finalScore = double.parse(finalScore.clamp(0.0, 1.0).toStringAsFixed(3));

    final hypDelta = double.parse((finalScore - rawScore).toStringAsFixed(3));

    return {
      'n': num,
      'raw_score': rawScore,
      'final_score': finalScore,
      'rank': rank,
      'classification': rpaClassifyRank(rank),
      'evidence': {
        'match_rounds': matchCount[num] ?? 0,
        'total_match_rounds': totalMatchRounds,
        'recent_match_rounds': recentMatchCount[num] ?? 0,
        'recent_window_rounds': totalMatchRounds - recentCutoff,
        'total_training_rounds': trainingData.length,
        'raw_score': rawScore,
        'hyp_boost': hypDelta,
        'active_hyp_count': activeHypCount,
        'boost_hypothesis_ids': boostHypothesisIds,
      },
    };
  }).toList();
}

String rpaClassifyRank(int rank) {
  if (rank <= 5) return 'CORE';
  if (rank <= 10) return 'STRONG';
  if (rank <= 18) return 'SUPPORT';
  if (rank <= 30) return 'NEUTRAL';
  if (rank <= 40) return 'WEAK';
  return 'EXCLUDE_CANDIDATE';
}

/// 기본 추천 조합 (v2.0과 동일 알고리즘 — 시드 고정 셔플)
/// 입력 후보 순서가 같으면 항상 같은 결과를 냅니다.
List<List<int>> rpaGenerateRecommendedSets(
  List<Map<String, dynamic>> candidates,
  Map<String, String> dirs,
  int count,
) {
  if (candidates.length < 6) return [];
  final topNums = candidates.take(18).map((c) => c['n'] as int).toList();
  final sets = <List<int>>[];
  final rng = Random(42);

  for (int attempt = 0; attempt < 600 && sets.length < count; attempt++) {
    final shuffled = List.of(topNums)..shuffle(rng);
    final combo = shuffled.take(6).toList()..sort();
    final key = combo.join(',');
    if (sets.any((s) => s.join(',') == key)) continue;
    if (rpaMatchesDirs(combo, dirs)) sets.add(combo);
  }
  for (int attempt = 0; attempt < 200 && sets.length < count; attempt++) {
    final shuffled = List.of(topNums)..shuffle(rng);
    final combo = shuffled.take(6).toList()..sort();
    final key = combo.join(',');
    if (!sets.any((s) => s.join(',') == key)) sets.add(combo);
  }
  return sets;
}

// ── v2.1 결정적 조합 생성 (난수 없음) ──────────────────────

class RpaScoredSet {
  final List<int> numbers;
  final double score;
  final bool matchesDirs;
  const RpaScoredSet(this.numbers, this.score, this.matchesDirs);
  String get key => numbers.join(',');
  Map<String, dynamic> toJson() =>
      {'numbers': numbers, 'set_score': double.parse(score.toStringAsFixed(3)), 'matches_dirs': matchesDirs};
}

/// 상위 후보 C(k,6) 전체를 점수합으로 정렬 (난수 없음)
List<RpaScoredSet> rpaRankAllCombos(
  List<Map<String, dynamic>> candidates,
  Map<String, String> dirs,
) {
  final c = candidates.take(18).toList();
  final nums = c.map((e) => e['n'] as int).toList();
  final scores = c.map((e) => (e['final_score'] ?? e['s'] as num).toDouble()).toList();
  final out = <RpaScoredSet>[];
  final k = nums.length;
  if (k < 6) return out;
  for (int a = 0; a < k - 5; a++) {
    for (int b = a + 1; b < k - 4; b++) {
      for (int c2 = b + 1; c2 < k - 3; c2++) {
        for (int d = c2 + 1; d < k - 2; d++) {
          for (int e = d + 1; e < k - 1; e++) {
            for (int f = e + 1; f < k; f++) {
              final idx = [a, b, c2, d, e, f];
              final combo = idx.map((i) => nums[i]).toList()..sort();
              final s = idx.fold(0.0, (acc, i) => acc + scores[i]);
              out.add(RpaScoredSet(combo, s, rpaMatchesDirs(combo, dirs)));
            }
          }
        }
      }
    }
  }
  out.sort((x, y) {
    final cmp = y.score.compareTo(x.score);
    return cmp != 0 ? cmp : x.key.compareTo(y.key);
  });
  return out;
}

int rpaSetOverlap(List<int> a, List<int> b) => a.where(b.contains).length;

/// 정렬된 조합에서 기존 선택과 최대 [maxOverlap]개까지만 겹치는 조합을 순서대로 선택
List<RpaScoredSet> rpaPickDiverse(
  List<RpaScoredSet> ranked, {
  required int count,
  required int maxOverlap,
  List<List<int>> existing = const [],
  bool requireDirs = true,
}) {
  final picked = <RpaScoredSet>[];
  for (final s in ranked) {
    if (picked.length >= count) break;
    if (requireDirs && !s.matchesDirs) continue;
    final all = [...existing, ...picked.map((p) => p.numbers)];
    if (all.any((e) => e.join(',') == s.key)) continue;
    if (all.any((e) => rpaSetOverlap(e, s.numbers) > maxOverlap)) continue;
    picked.add(s);
  }
  return picked;
}

/// Number Base 기본 조합 (v2.1): 지표 방향을 만족하는 점수합 상위 조합,
/// 서로 3개 이하만 겹치도록 3세트.
List<RpaScoredSet> rpaBaseSets(List<RpaScoredSet> ranked) {
  final picked = rpaPickDiverse(ranked, count: 3, maxOverlap: 3);
  if (picked.length < 3) {
    picked.addAll(rpaPickDiverse(ranked,
        count: 3 - picked.length, maxOverlap: 4,
        existing: picked.map((p) => p.numbers).toList(), requireDirs: false));
  }
  return picked;
}

/// Number Base 한 회차 계산 결과
class RpaNumberBase {
  final int trainingEndRound;
  final Map<String, String> theoryDirections;
  final Map<String, String> finalDirections;
  final Map<String, double> rates;
  final Map<String, bool> flips;
  final List<Map<String, dynamic>> numberEvaluations;
  final List<Map<String, dynamic>> candidates;
  final List<List<int>> recommendedSets;

  const RpaNumberBase({
    required this.trainingEndRound,
    required this.theoryDirections,
    required this.finalDirections,
    required this.rates,
    required this.flips,
    required this.numberEvaluations,
    required this.candidates,
    required this.recommendedSets,
  });
}

/// generatePrediction과 동일한 순서로 Number Base를 계산합니다.
/// activeFlips: rpa_model_state.active_flips (순차 학습된 보정 상태)
RpaNumberBase rpaComputeNumberBase(
  List<LottoWinningNumber> trainingData, {
  required Map<String, bool> activeFlips,
  double hypothesisBoost = 0.0,
  int activeHypCount = 0,
  List<String> boostHypothesisIds = const [],
}) {
  final sorted = List.of(trainingData)..sort((a, b) => a.round.compareTo(b.round));
  final rolling = RpaRollingState();
  for (final id in rpaIndicatorIds) {
    rolling.activeFlips[id] = activeFlips[id] ?? false;
  }
  for (final w in sorted) {
    rolling.addRound(w);
  }
  final theory = rolling.theoryDirections();
  final flips = Map<String, bool>.from(rolling.activeFlips);
  final finalDirs = rolling.finalDirections(theory);
  final rates = rolling.cumulativeRates();

  final evals = rpaComputeNumberEvaluations(
    sorted, finalDirs,
    hypothesisBoost: hypothesisBoost,
    activeHypCount: activeHypCount,
    boostHypothesisIds: boostHypothesisIds,
  );
  final candidates = evals.take(18).map((e) => {
    'n': e['n'] as int,
    's': e['final_score'] as double,
  }).toList();
  // v2.1: 점수합 기반 결정적 조합 (v2.0의 시드 셔플은 동점 순서에 민감)
  final recSets = rpaBaseSets(rpaRankAllCombos(evals.take(18).toList(), finalDirs))
      .map((s) => s.numbers)
      .toList();

  return RpaNumberBase(
    trainingEndRound: sorted.isEmpty ? 0 : sorted.last.round,
    theoryDirections: theory,
    finalDirections: finalDirs,
    rates: rates,
    flips: flips,
    numberEvaluations: evals,
    candidates: candidates,
    recommendedSets: recSets,
  );
}
