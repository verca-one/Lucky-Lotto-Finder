// rpa_hypothesis_engine.dart
// Phase 2: 순차패턴 탐색 + 가설 생애주기 관리 + 회의 시스템
//
// 설계 원칙:
//  - 예측 스냅샷은 수정 금지 (이 파일에서는 건드리지 않음)
//  - 시간 원칙: 분석 시 target round 이전 데이터만 사용
//  - 패턴은 발견 → 관찰 → 검증 → 발전/약화/폐기 순으로 진화

import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/lotto_winning_number.dart';
import 'rpa_monte_carlo_engine.dart';

// ──────────────────────────────────────────────────────────
// 상수
// ──────────────────────────────────────────────────────────
const _hypIndIds = ['oe33', 'lh33', 'cons', 'sp', 'rhi', 'phi'];
const _hypIndNames = {
  'oe33': '홀짝3:3',
  'lh33': '저고3:3',
  'cons': '연속번호',
  'sp':   '합짝수',
  'rhi':  '범위폭↑',
  'phi':  '소수개수↑',
};
const _hypBaselines = {
  'oe33': 0.3348,
  'lh33': 0.3348,
  'cons': 0.5287,
  'sp':   0.5000,
  'rhi':  0.5000,
  'phi':  0.5000,
};
const _hypPrimes = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43};

// ──────────────────────────────────────────────────────────
// 모델
// ──────────────────────────────────────────────────────────

/// 지표 시계열 분석 결과 (1개 지표)
class RpaTsResult {
  final String id;
  final String name;
  final double currentRate;   // 전체 누적 비율
  final double recent10Rate;  // 최근 10회 비율
  final double recent50Rate;  // 최근 50회 비율
  final double baseline;
  final double shortLongDiff; // recent10 - recent50
  final double trend;         // last-20 선형 기울기
  final double volatility;    // last-20 표준편차
  final double autocorr;      // lag-1 자기상관
  final String stateDir;      // 'above' | 'below' | 'neutral'

  const RpaTsResult({
    required this.id,
    required this.name,
    required this.currentRate,
    required this.recent10Rate,
    required this.recent50Rate,
    required this.baseline,
    required this.shortLongDiff,
    required this.trend,
    required this.volatility,
    required this.autocorr,
    required this.stateDir,
  });

  bool get isSignificant => shortLongDiff.abs() > 0.07;
  String get dirSymbol => stateDir == 'above' ? '↑' : stateDir == 'below' ? '↓' : '→';
  String get label => '${name}${dirSymbol}';
}

/// 순차 패턴 (+N회 후속현상)
class RpaSeqPattern {
  final String id; // '${indicator}_h${horizon}_${dir}'
  final Map<String, String> triggerState;
  final int horizon;
  final String phenIndicator;
  final String phenDirection; // 'above' | 'below'
  final int totalOccurrences;
  final int phenCount;
  final double successRate;
  final double mcRandomRate;
  final List<int> sampleRounds;

  const RpaSeqPattern({
    required this.id,
    required this.triggerState,
    required this.horizon,
    required this.phenIndicator,
    required this.phenDirection,
    required this.totalOccurrences,
    required this.phenCount,
    required this.successRate,
    required this.mcRandomRate,
    required this.sampleRounds,
  });

  bool get isSignificant =>
      totalOccurrences >= 8 && (successRate >= 0.62 || successRate <= 0.38);
  double get effect => successRate - mcRandomRate;
  String get description =>
      '${_hypIndNames[phenIndicator]}(${phenDirection == 'above' ? '↑' : '↓'}) @+$horizon회';
}

/// 가설 V3 (전체 생애주기)
class RpaHypV3 {
  final String id;
  final int createdRound;
  final String type; // 'sequential' | 'combined' | 'manual'
  String status;
  // 'discovered' | 'observing' | 'validating' | 'developing'
  // | 'accepted' | 'weakened' | 'combined' | 'rejected'
  final Map<String, String> triggerConditions;
  final Map<String, dynamic> expectedPhenomenon;
  final int horizon;

  // Historical Replay 통계
  final int historicalSampleCount;
  final double historicalSuccessRate;

  // Monte Carlo
  final double? monteCarloP;
  final double? monteCarloRandomRate;

  // 미래 검증
  int futureVerificationCount;
  int futureSuccessCount;

  double currentWeight;
  final String evidence;
  final DateTime createdAt;
  DateTime updatedAt;
  List<RpaHypEvent> events;
  final List<String> parentHypothesisIds; // 복합가설 lineage

  RpaHypV3({
    required this.id,
    required this.createdRound,
    required this.type,
    required this.status,
    required this.triggerConditions,
    required this.expectedPhenomenon,
    required this.horizon,
    required this.historicalSampleCount,
    required this.historicalSuccessRate,
    this.monteCarloP,
    this.monteCarloRandomRate,
    required this.futureVerificationCount,
    required this.futureSuccessCount,
    required this.currentWeight,
    this.parentHypothesisIds = const [],
    required this.evidence,
    required this.createdAt,
    required this.updatedAt,
    this.events = const [],
  });

  double get futureSuccessRate =>
      futureVerificationCount == 0 ? 0 : futureSuccessCount / futureVerificationCount;

  factory RpaHypV3.fromJson(Map<String, dynamic> j) {
    Map<String, String> parseDirs(dynamic raw) {
      if (raw == null) return {};
      return (raw as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v.toString()));
    }
    return RpaHypV3(
      id: j['id'] as String,
      createdRound: j['created_round'] as int,
      type: j['hypothesis_type'] as String? ?? 'sequential',
      status: j['status'] as String? ?? 'discovered',
      triggerConditions: parseDirs(j['trigger_conditions']),
      expectedPhenomenon: (j['expected_phenomenon'] as Map<String, dynamic>?) ?? {},
      horizon: j['horizon'] as int? ?? 1,
      historicalSampleCount: j['historical_sample_count'] as int? ?? 0,
      historicalSuccessRate: (j['historical_success_rate'] as num?)?.toDouble() ?? 0.5,
      monteCarloP: (j['monte_carlo_p_value'] as num?)?.toDouble(),
      monteCarloRandomRate: (j['monte_carlo_random_rate'] as num?)?.toDouble(),
      futureVerificationCount: j['future_verification_count'] as int? ?? 0,
      futureSuccessCount: j['future_success_count'] as int? ?? 0,
      currentWeight: (j['current_weight'] as num?)?.toDouble() ?? 0.5,
      evidence: j['evidence'] as String? ?? '',
      createdAt: j['created_at'] != null
          ? DateTime.parse(j['created_at'] as String)
          : DateTime.now(),
      updatedAt: j['updated_at'] != null
          ? DateTime.parse(j['updated_at'] as String)
          : DateTime.now(),
      parentHypothesisIds: j['parent_hypothesis_ids'] != null
          ? List<String>.from(j['parent_hypothesis_ids'] as List)
          : const [],
    );
  }
}

/// 가설 이벤트 (생애주기 이력)
class RpaHypEvent {
  final String id;
  final String hypothesisId;
  final int round;
  final String eventType;
  final String? previousStatus;
  final String? newStatus;
  final double? previousWeight;
  final double? newWeight;
  final String summary;
  final DateTime createdAt;

  const RpaHypEvent({
    required this.id,
    required this.hypothesisId,
    required this.round,
    required this.eventType,
    this.previousStatus,
    this.newStatus,
    this.previousWeight,
    this.newWeight,
    required this.summary,
    required this.createdAt,
  });

  factory RpaHypEvent.fromJson(Map<String, dynamic> j) => RpaHypEvent(
        id: j['id'] as String,
        hypothesisId: j['hypothesis_id'] as String,
        round: j['round'] as int,
        eventType: j['event_type'] as String,
        previousStatus: j['previous_status'] as String?,
        newStatus: j['new_status'] as String?,
        previousWeight: (j['previous_weight'] as num?)?.toDouble(),
        newWeight: (j['new_weight'] as num?)?.toDouble(),
        summary: j['summary'] as String? ?? '',
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'] as String)
            : DateTime.now(),
      );
}

/// 회의 진행 스텝 (Stream 아이템)
class MeetingStep {
  final String type;
  // 'info' | 'ts_result' | 'pattern_found' | 'no_patterns'
  // | 'hyp_created' | 'hyp_exists' | 'hyp_updated' | 'hyp_discarded'
  // | 'complete' | 'error'
  final String message;
  final dynamic data;

  const MeetingStep({
    required this.type,
    required this.message,
    this.data,
  });
}

// ──────────────────────────────────────────────────────────
// 내부 유틸: 지표값 계산
// ──────────────────────────────────────────────────────────
Map<String, double> _indValues(LottoWinningNumber w) {
  final nums = List.of(w.numbers)..sort();
  final odds = nums.where((x) => x % 2 == 1).length;
  bool hasC = false;
  for (int i = 0; i < nums.length - 1; i++) {
    if (nums[i + 1] - nums[i] == 1) { hasC = true; break; }
  }
  final s = nums.reduce((a, b) => a + b);
  final rw = nums.last - nums.first;
  final pc = nums.where(_hypPrimes.contains).length;
  return {
    'oe33': odds == 3 ? 1.0 : 0.0,
    'lh33': nums.where((x) => x <= 22).length == 3 ? 1.0 : 0.0,
    'cons': hasC ? 1.0 : 0.0,
    'sp':   s % 2 == 0 ? 1.0 : 0.0,
    'rhi':  rw > 32.86 ? 1.0 : 0.0,
    'phi':  pc > 1.87 ? 1.0 : 0.0,
  };
}

/// 비율 vs 기준선으로 방향 결정
String _dir(double rate, double baseline, {double threshold = 0.05}) {
  if (rate > baseline + threshold) return 'above';
  if (rate < baseline - threshold) return 'below';
  return 'neutral';
}

// ──────────────────────────────────────────────────────────
// 시계열 분석기
// ──────────────────────────────────────────────────────────
class TimeSeriesAnalyzer {
  static List<RpaTsResult> analyze(List<LottoWinningNumber> allData) {
    final sorted = List.of(allData)..sort((a, b) => a.round.compareTo(b.round));
    if (sorted.isEmpty) return [];
    final allVals = sorted.map(_indValues).toList();
    final n = sorted.length;

    return _hypIndIds.map((id) {
      final vals = allVals.map((v) => v[id] ?? 0.0).toList();

      final currentRate = vals.reduce((a, b) => a + b) / n;

      final r10Start = n >= 10 ? n - 10 : 0;
      final r10 = vals.sublist(r10Start);
      final recent10Rate = r10.reduce((a, b) => a + b) / r10.length;

      final r50Start = n >= 50 ? n - 50 : 0;
      final r50 = vals.sublist(r50Start);
      final recent50Rate = r50.reduce((a, b) => a + b) / r50.length;

      final r20Start = n >= 20 ? n - 20 : 0;
      final r20 = vals.sublist(r20Start);
      final trend = _slope(r20);
      final volatility = _stdDev(r20);
      final autocorr = _autocorr(r50, 1);

      final base = _hypBaselines[id] ?? 0.5;
      final stateDir = _dir(recent10Rate, base);

      return RpaTsResult(
        id: id,
        name: _hypIndNames[id] ?? id,
        currentRate: currentRate,
        recent10Rate: recent10Rate,
        recent50Rate: recent50Rate,
        baseline: base,
        shortLongDiff: recent10Rate - recent50Rate,
        trend: trend,
        volatility: volatility,
        autocorr: autocorr,
        stateDir: stateDir,
      );
    }).toList();
  }

  static double _slope(List<double> v) {
    if (v.length < 3) return 0;
    final n = v.length.toDouble();
    final sumX = n * (n - 1) / 2;
    final sumX2 = n * (n - 1) * (2 * n - 1) / 6;
    final sumY = v.reduce((a, b) => a + b);
    final sumXY =
        List.generate(v.length, (i) => i * v[i]).reduce((a, b) => a + b);
    final denom = n * sumX2 - sumX * sumX;
    if (denom == 0) return 0;
    return (n * sumXY - sumX * sumY) / denom;
  }

  static double _stdDev(List<double> v) {
    if (v.length < 2) return 0;
    final mean = v.reduce((a, b) => a + b) / v.length;
    final variance =
        v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
            v.length;
    return sqrt(variance);
  }

  static double _autocorr(List<double> v, int lag) {
    if (v.length <= lag) return 0;
    final mean = v.reduce((a, b) => a + b) / v.length;
    double num = 0, den = 0;
    for (int i = lag; i < v.length; i++) {
      num += (v[i] - mean) * (v[i - lag] - mean);
    }
    for (final x in v) den += (x - mean) * (x - mean);
    return den == 0 ? 0 : num / den;
  }
}

// ──────────────────────────────────────────────────────────
// 순차 패턴 탐색기
// ──────────────────────────────────────────────────────────
class SequentialPatternFinder {
  /// 현재 상태와 유사한 과거 상태를 찾고 +1~+6 후속현상을 분석한다.
  ///
  /// [minSamples]: 유의한 패턴으로 간주하기 위한 최소 표본 수
  /// [sigThreshold]: 유의한 성공률 최소값 (0.5 + 편차)
  /// [matchRequired]: 6개 지표 중 몇 개 이상 일치해야 "유사" 판정
  static List<RpaSeqPattern> find(
    List<LottoWinningNumber> allData, {
    int minSamples = 8,
    double sigThreshold = 0.62,
    int matchRequired = 4,
  }) {
    final sorted = List.of(allData)..sort((a, b) => a.round.compareTo(b.round));
    if (sorted.length < 30) return [];

    final n = sorted.length;
    final allVals = sorted.map(_indValues).toList();

    // 각 위치에서 10회 롤링 비율로 상태 계산
    final stateAt = <Map<String, String>>[];
    for (int i = 0; i < n; i++) {
      final start = i >= 9 ? i - 9 : 0;
      final window = allVals.sublist(start, i + 1);
      final state = <String, String>{};
      for (final id in _hypIndIds) {
        final rate =
            window.map((v) => v[id] ?? 0.0).reduce((a, b) => a + b) /
                window.length;
        state[id] = _dir(rate, _hypBaselines[id] ?? 0.5);
      }
      stateAt.add(state);
    }

    // 현재 상태 (마지막 위치)
    final currentState = stateAt.last;

    // 유사 과거 위치 찾기 (뒤 6개는 제외 — +6 데이터가 없음)
    final similarIdxs = <int>[];
    for (int i = 0; i < n - 6; i++) {
      int matches = 0;
      for (final id in _hypIndIds) {
        if (stateAt[i][id] == currentState[id]) matches++;
      }
      if (matches >= matchRequired) similarIdxs.add(i);
    }

    if (similarIdxs.length < minSamples) return [];

    final patterns = <RpaSeqPattern>[];

    for (final id in _hypIndIds) {
      final base = _hypBaselines[id] ?? 0.5;
      for (int h = 1; h <= 6; h++) {
        final validIdxs = similarIdxs.where((idx) => idx + h < n).toList();
        if (validIdxs.length < minSamples) continue;

        int aboveCount = 0;
        for (final idx in validIdxs) {
          if ((allVals[idx + h][id] ?? 0.0) > base * 0.99) aboveCount++;
        }

        final total = validIdxs.length;
        final aboveRate = aboveCount / total;
        final belowRate = 1 - aboveRate;

        // mcRandomRate: 순수 랜덤에서의 기대값 = baseline 비율
        final mcRate = base;

        // Multiple Testing 보정: Bonferroni (72개 조합)
        // 유의수준 α=0.05 → 보정 후 α=0.05/72≈0.0007 → 성공률 임계 상향
        // 실용적 구현: sigThreshold를 기본값보다 0.03 더 높게 요구
        const mtBonus = 0.03; // ~Bonferroni 보정 효과
        final adjustedSig = sigThreshold + mtBonus;

        for (final entry in [
          ('above', aboveRate),
          ('below', belowRate),
        ]) {
          final dir = entry.$1;
          final rate = entry.$2;
          if (rate >= adjustedSig && (rate - mcRate).abs() >= 0.08 && total >= minSamples) {
            final sample = validIdxs.take(20).map((idx) => sorted[idx].round).toList();
            patterns.add(RpaSeqPattern(
              id: '${id}_h${h}_$dir',
              triggerState: Map.from(currentState),
              horizon: h,
              phenIndicator: id,
              phenDirection: dir,
              totalOccurrences: total,
              phenCount: dir == 'above' ? aboveCount : total - aboveCount,
              successRate: rate,
              mcRandomRate: mcRate,
              sampleRounds: sample,
            ));
          }
        }
      }
    }

    // 효과 크기(실제율 - MC기준) 내림차순 정렬
    patterns.sort((a, b) => b.effect.compareTo(a.effect));
    return patterns;
  }

  /// 유사 상태 개수만 반환 (UI 표시용)
  static int countSimilarStates(
    List<LottoWinningNumber> allData, {
    int matchRequired = 4,
  }) {
    final sorted = List.of(allData)..sort((a, b) => a.round.compareTo(b.round));
    if (sorted.length < 20) return 0;
    final n = sorted.length;
    final allVals = sorted.map(_indValues).toList();

    final stateAt = <Map<String, String>>[];
    for (int i = 0; i < n; i++) {
      final start = i >= 9 ? i - 9 : 0;
      final window = allVals.sublist(start, i + 1);
      final state = <String, String>{};
      for (final id in _hypIndIds) {
        final rate =
            window.map((v) => v[id] ?? 0.0).reduce((a, b) => a + b) /
                window.length;
        state[id] = _dir(rate, _hypBaselines[id] ?? 0.5);
      }
      stateAt.add(state);
    }

    final current = stateAt.last;
    int cnt = 0;
    for (int i = 0; i < n - 6; i++) {
      int m = 0;
      for (final id in _hypIndIds) {
        if (stateAt[i][id] == current[id]) m++;
      }
      if (m >= matchRequired) cnt++;
    }
    return cnt;
  }
}

// ──────────────────────────────────────────────────────────
// HypothesisEngine (싱글톤)
// ──────────────────────────────────────────────────────────
class HypothesisEngine {
  HypothesisEngine._();
  static final HypothesisEngine instance = HypothesisEngine._();

  final _db = Supabase.instance.client;

  // ── 로드 ─────────────────────────────────────────────────
  Future<List<RpaHypV3>> loadHypotheses({bool includeRejected = false}) async {
    try {
      final raw = includeRejected
          ? await _db
              .from('rpa_hypotheses_v3')
              .select()
              .order('created_at', ascending: false)
              .limit(200)
          : await _db
              .from('rpa_hypotheses_v3')
              .select()
              .neq('status', 'rejected')
              .order('created_at', ascending: false)
              .limit(200);
      final hyps = (raw as List<dynamic>)
          .map((j) => RpaHypV3.fromJson(j as Map<String, dynamic>))
          .toList();
      await _attachEvents(hyps);
      return hyps;
    } catch (_) {
      return [];
    }
  }

  Future<void> _attachEvents(List<RpaHypV3> hyps) async {
    if (hyps.isEmpty) return;
    try {
      final ids = hyps.map((h) => h.id).toList();
      final raw = await _db
          .from('rpa_hypothesis_events')
          .select()
          .inFilter('hypothesis_id', ids)
          .order('round', ascending: true);
      final evMap = <String, List<RpaHypEvent>>{};
      for (final j in raw as List<dynamic>) {
        final ev = RpaHypEvent.fromJson(j as Map<String, dynamic>);
        evMap.putIfAbsent(ev.hypothesisId, () => []).add(ev);
      }
      for (final h in hyps) {
        h.events = evMap[h.id] ?? [];
      }
    } catch (_) {}
  }

  // ── 가설 생성 ─────────────────────────────────────────────
  Future<RpaHypV3?> createFromPattern(
    RpaSeqPattern pattern,
    int currentRound,
  ) async {
    try {
      final evidence =
          '${_hypIndNames[pattern.phenIndicator]}'
          '(${pattern.phenDirection == 'above' ? '↑' : '↓'})'
          ' @+${pattern.horizon}회 — '
          '과거표본 ${pattern.totalOccurrences}회, '
          '성공률 ${(pattern.successRate * 100).toStringAsFixed(1)}%';

      final row = await _db.from('rpa_hypotheses_v3').insert({
        'created_round': currentRound,
        'hypothesis_type': 'sequential',
        'status': 'discovered',
        'trigger_conditions': pattern.triggerState,
        'expected_phenomenon': {
          'indicator': pattern.phenIndicator,
          'direction': pattern.phenDirection,
          'horizon': pattern.horizon,
        },
        'horizon': pattern.horizon,
        'historical_sample_count': pattern.totalOccurrences,
        'historical_success_rate': pattern.successRate,
        'monte_carlo_random_rate': pattern.mcRandomRate,
        'future_verification_count': 0,
        'future_success_count': 0,
        'current_weight': _initWeight(pattern.successRate),
        'evidence': evidence,
      }).select().single();

      final hyp = RpaHypV3.fromJson(row as Map<String, dynamic>);

      await _addEvent(
        hyp.id, currentRound, 'discovered',
        summary: '순차패턴 발견 — '
            '${pattern.phenDirection == 'above' ? '↑' : '↓'}'
            '${_hypIndNames[pattern.phenIndicator]}'
            ' @+${pattern.horizon}회 '
            '(표본 ${pattern.totalOccurrences}회, 성공률 ${(pattern.successRate * 100).toStringAsFixed(1)}%)',
        newStatus: 'discovered',
        newWeight: hyp.currentWeight,
      );

      // 신규 가설 → MC Random Control 자동 예약
      MonteCarloEngine.instance.onHypothesisCreated(hyp).ignore();

      return hyp;
    } catch (_) {
      return null;
    }
  }

  double _initWeight(double successRate) =>
      (0.5 + (successRate - 0.5) * 0.8).clamp(0.1, 1.0);

  // ── 상태 변경 ─────────────────────────────────────────────
  Future<void> updateStatus(
    String id,
    String newStatus, {
    double? newWeight,
    required int round,
    required String summary,
    String? previousStatus,
    double? previousWeight,
  }) async {
    try {
      await _db.from('rpa_hypotheses_v3').update({
        'status': newStatus,
        if (newWeight != null) 'current_weight': newWeight,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      await _addEvent(
        id, round, 'status_change',
        summary: summary,
        previousStatus: previousStatus,
        newStatus: newStatus,
        previousWeight: previousWeight,
        newWeight: newWeight,
      );
    } catch (_) {}
  }

  // ── 이벤트 기록 ───────────────────────────────────────────
  Future<void> _addEvent(
    String hypothesisId,
    int round,
    String eventType, {
    required String summary,
    String? previousStatus,
    String? newStatus,
    double? previousWeight,
    double? newWeight,
    Map<String, dynamic>? details,
  }) async {
    try {
      await _db.from('rpa_hypothesis_events').insert({
        'hypothesis_id': hypothesisId,
        'round': round,
        'event_type': eventType,
        if (previousStatus != null) 'previous_status': previousStatus,
        if (newStatus != null) 'new_status': newStatus,
        if (previousWeight != null) 'previous_weight': previousWeight,
        if (newWeight != null) 'new_weight': newWeight,
        'summary': summary,
        if (details != null) 'details': details,
      });
    } catch (_) {}
  }

  // ── 실제 회차 결과로 가설 검증 ───────────────────────────
  Future<void> verifyAgainstNewRound(
    LottoWinningNumber newRound,
    List<RpaHypV3> hypotheses,
  ) async {
    final vals = _indValues(newRound);

    // 이미 이 회차로 검증된 가설 (게이트 재처리 시 같은 회차 중복 집계 방지)
    Set<String> alreadyVerified = {};
    try {
      final rows = await _db.from('rpa_hypothesis_events').select('hypothesis_id')
          .eq('event_type', 'verification').eq('round', newRound.round);
      alreadyVerified = (rows as List).map((r) => '${r['hypothesis_id']}').toSet();
    } catch (_) {}

    for (final h in hypotheses) {
      if (h.status == 'rejected' || h.status == 'combined') continue;
      // 데이터 누수 방지: 가설 생성 회차 이하(자기 학습 데이터)로는 검증하지 않음
      if (newRound.round <= h.createdRound) continue;
      if (alreadyVerified.contains(h.id)) continue;
      final phenom = h.expectedPhenomenon;
      final indId = phenom['indicator'] as String?;
      if (indId == null) continue;

      final expDir = phenom['direction'] as String? ?? 'above';
      final actualVal = vals[indId] ?? 0.0;
      final base = _hypBaselines[indId] ?? 0.5;
      final actualDir = actualVal > base * 0.99 ? 'above' : 'below';
      final hit = actualDir == expDir;

      h.futureVerificationCount++;
      if (hit) h.futureSuccessCount++;

      final newW =
          hit ? (h.currentWeight + 0.05).clamp(0.1, 1.0) : (h.currentWeight - 0.05).clamp(0.1, 1.0);

      try {
        await _db.from('rpa_hypotheses_v3').update({
          'future_verification_count': h.futureVerificationCount,
          'future_success_count': h.futureSuccessCount,
          'current_weight': newW,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', h.id);

        await _addEvent(
          h.id, newRound.round, 'verification',
          summary: '${newRound.round}회 검증: '
              '${hit ? '적중 ✓' : '실패 ✗'} '
              '(${_hypIndNames[indId]}'
              '${expDir == 'above' ? '↑' : '↓'} 예상, '
              '실제 ${actualDir == 'above' ? '↑' : '↓'})',
          previousWeight: h.currentWeight,
          newWeight: newW,
        );
        h.currentWeight = newW;

        // 누적 성능으로 상태 전환
        if (h.futureVerificationCount >= 5) {
          final rate = h.futureSuccessRate;
          String? next;
          // discovered 는 검증이 쌓여도 전진 경로가 없어 고착됐음 → observing 과 동일하게 취급
          if (rate >= 0.65 && (h.status == 'observing' || h.status == 'discovered')) next = 'validating';
          if (rate >= 0.72 && h.status == 'validating') next = 'accepted';
          if (rate < 0.35 && h.status != 'weakened') next = 'weakened';

          if (next != null) {
            await updateStatus(
              h.id, next,
              newWeight: newW,
              round: newRound.round,
              summary: '누적 성능 → $next '
                  '(${h.futureVerificationCount}회 중 ${h.futureSuccessCount}회 성공)',
              previousStatus: h.status,
              previousWeight: h.currentWeight,
            );
            h.status = next;
          }
        }
      } catch (_) {}
    }
  }

  // ── 전체 회의 (Stream) ────────────────────────────────────
  Stream<MeetingStep> runMeeting(
    List<LottoWinningNumber> allData,
    int currentRound,
  ) async* {
    yield MeetingStep(type: 'info', message: '[$currentRound회차 기준] 회의 시작...');

    // 1단계: 시계열 분석
    yield MeetingStep(type: 'info', message: '① 시계열 분석 중...');
    await Future.delayed(const Duration(milliseconds: 100));
    final tsResults = TimeSeriesAnalyzer.analyze(allData);
    for (final ts in tsResults) {
      yield MeetingStep(
        type: 'ts_result',
        message: '${ts.label}: '
            '최근10회 ${(ts.recent10Rate * 100).toStringAsFixed(1)}% '
            '/ 기준 ${(ts.baseline * 100).toStringAsFixed(1)}% '
            '(Δ${ts.shortLongDiff >= 0 ? '+' : ''}'
            '${(ts.shortLongDiff * 100).toStringAsFixed(1)}pp)'
            '${ts.isSignificant ? ' ⚡유의' : ''}',
        data: ts,
      );
    }
    final sigTs = tsResults.where((t) => t.isSignificant).length;
    yield MeetingStep(
      type: 'info',
      message: '시계열: 유의 지표 $sigTs/${tsResults.length}개',
    );

    // 2단계: 순차 패턴 탐색 (유의 TS 지표에 가중치 부여)
    yield MeetingStep(type: 'info', message: '② 순차 패턴 탐색 중...');
    await Future.delayed(const Duration(milliseconds: 100));
    final sigTsIds = tsResults.where((t) => t.isSignificant).map((t) => t.id).toSet();
    final similarCount = SequentialPatternFinder.countSimilarStates(allData);
    final rawPatterns = SequentialPatternFinder.find(allData);
    // TS 유의 지표와 일치하는 패턴을 앞으로 정렬
    final patterns = [
      ...rawPatterns.where((p) => sigTsIds.contains(p.phenIndicator)),
      ...rawPatterns.where((p) => !sigTsIds.contains(p.phenIndicator)),
    ];

    yield MeetingStep(
      type: 'info',
      message: '유사 과거 상태: $similarCount회 / '
          '유의 패턴: ${patterns.length}개 발견',
    );

    if (patterns.isEmpty) {
      yield MeetingStep(
        type: 'no_patterns',
        message: '현재 상태와 유사한 과거 사례가 부족하거나 유의한 후속현상이 없음',
      );
    } else {
      for (final p in patterns.take(5)) {
        yield MeetingStep(
          type: 'pattern_found',
          message: '패턴: ${p.description} — '
              '표본 ${p.totalOccurrences}회, '
              '성공률 ${(p.successRate * 100).toStringAsFixed(1)}% '
              '(MC기준: ${(p.mcRandomRate * 100).toStringAsFixed(1)}%)',
          data: p,
        );
      }
    }

    // 3단계: 기존 가설 검토 + 신규 가설 생성
    yield MeetingStep(type: 'info', message: '③ 기존 가설 검토 및 신규 가설 생성 중...');
    await Future.delayed(const Duration(milliseconds: 100));
    // 폐기된 가설 포함 로드 → 재발견 방지
    final existingHyps = await loadHypotheses(includeRejected: true);

    int created = 0, maintained = 0, transitioned = 0, discarded = 0;

    for (final p in patterns.take(10)) {
      // rejected 포함 전체에서 존재 여부 확인 → 재발견 방지
      final exists = existingHyps.any((h) =>
          h.expectedPhenomenon['indicator'] == p.phenIndicator &&
          h.expectedPhenomenon['direction'] == p.phenDirection &&
          h.horizon == p.horizon);

      if (!exists) {
        final hyp = await createFromPattern(p, currentRound);
        if (hyp != null) {
          created++;
          yield MeetingStep(
            type: 'hyp_created',
            message: '🆕 가설 생성: ${p.description} '
                '(표본 ${p.totalOccurrences}, 성공률 ${(p.successRate * 100).toStringAsFixed(1)}%)',
            data: hyp,
          );
        }
      } else {
        maintained++;
        yield MeetingStep(
          type: 'hyp_exists',
          message: '📋 기존 가설 유지: ${p.description}',
        );
      }
    }

    // 발견 → 관찰 전환
    for (final h in existingHyps.where((h) => h.status == 'discovered')) {
      if (currentRound > h.createdRound) {
        await updateStatus(
          h.id, 'observing',
          round: currentRound,
          summary: '발견 후 다음 회차 → 관찰 시작',
          previousStatus: 'discovered',
          previousWeight: h.currentWeight,
        );
        h.status = 'observing';
        transitioned++;
        yield MeetingStep(
          type: 'hyp_updated',
          message: '👁 관찰 시작: ${h.evidence.length > 40 ? h.evidence.substring(0, 40) + '...' : h.evidence}',
        );
      }
    }

    // 지속 실패 → 폐기
    for (final h in existingHyps.where((h) => h.status == 'weakened')) {
      if (h.futureVerificationCount >= 10 && h.futureSuccessRate < 0.35) {
        await updateStatus(
          h.id, 'rejected',
          round: currentRound,
          summary: '지속 실패 → 폐기 '
              '(${h.futureVerificationCount}회 검증, 성공률 ${(h.futureSuccessRate * 100).toStringAsFixed(1)}%)',
          previousStatus: h.status,
          previousWeight: h.currentWeight,
        );
        discarded++;
        yield MeetingStep(
          type: 'hyp_discarded',
          message: '🗑 폐기: ${h.evidence.length > 40 ? h.evidence.substring(0, 40) + '...' : h.evidence}',
        );
      }
    }

    // 4단계: 복합가설 생성 (accepted 가설 쌍 결합)
    yield MeetingStep(type: 'info', message: '④ 복합가설 탐색 중...');
    int compoundCreated = 0;
    try {
      final activeHyps = existingHyps.where(
        (h) => (h.status == 'accepted' || h.status == 'validating') &&
               h.futureVerificationCount >= 5 &&
               h.futureSuccessRate >= 0.55,
      ).toList();

      for (int i = 0; i < activeHyps.length && compoundCreated < 3; i++) {
        for (int j = i + 1; j < activeHyps.length && compoundCreated < 3; j++) {
          final a = activeHyps[i];
          final b = activeHyps[j];
          // 서로 다른 지표만 결합 (같은 지표 중복 방지)
          if (a.expectedPhenomenon['indicator'] == b.expectedPhenomenon['indicator']) continue;

          final combinedId = 'comb_${a.id.substring(0, 8)}_${b.id.substring(0, 8)}';
          final alreadyExists = existingHyps.any((h) => h.id == combinedId || h.type == 'combined' &&
              h.evidence.contains(a.id.substring(0, 8)) &&
              h.evidence.contains(b.id.substring(0, 8)));
          if (alreadyExists) continue;

          final combinedWeight = ((a.currentWeight + b.currentWeight) / 2).clamp(0.0, 1.0);
          await _db.from('rpa_hypotheses_v3').insert({
            'id': combinedId,
            'created_round': currentRound,
            'hypothesis_type': 'combined',
            'status': 'discovered',
            'trigger_conditions': {...a.triggerConditions, ...b.triggerConditions},
            'expected_phenomenon': {
              'indicator': '${a.expectedPhenomenon['indicator']}+${b.expectedPhenomenon['indicator']}',
              'direction': '${a.expectedPhenomenon['direction']}+${b.expectedPhenomenon['direction']}',
            },
            'horizon': (a.horizon + b.horizon) ~/ 2,
            'historical_sample_count': (a.historicalSampleCount + b.historicalSampleCount) ~/ 2,
            'historical_success_rate': (a.historicalSuccessRate + b.historicalSuccessRate) / 2,
            'current_weight': combinedWeight,
            'evidence': '복합[${a.id.substring(0, 8)}+${b.id.substring(0, 8)}]: '
                '${a.evidence.length > 30 ? a.evidence.substring(0, 30) : a.evidence} & '
                '${b.evidence.length > 30 ? b.evidence.substring(0, 30) : b.evidence}',
            'parent_hypothesis_ids': [a.id, b.id],
          });
          compoundCreated++;
          yield MeetingStep(
            type: 'hyp_created',
            message: '🔗 복합가설 생성: ${a.expectedPhenomenon['indicator']} + ${b.expectedPhenomenon['indicator']}',
          );
        }
      }
    } catch (e) {
      yield MeetingStep(type: 'info', message: '복합가설 생성 오류(무시): $e');
    }

    // 5단계: 완료
    yield MeetingStep(
      type: 'complete',
      message: '✅ 회의 완료 — '
          '생성 $created건 / 유지 $maintained건 / '
          '전환 $transitioned건 / 폐기 $discarded건 / 복합 $compoundCreated건',
    );
  }
}
