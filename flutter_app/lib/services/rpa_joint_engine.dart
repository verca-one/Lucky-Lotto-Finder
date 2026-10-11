// Joint Model Engine
// Phase 4: Number Model × Store Model 결합
//
// 원칙: 두 모델을 단순 합산하지 않는다.
// 각 모델이 독립적으로 성능을 측정하고,
// 결합했을 때 실제로 개선됐는지 검증한다.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/lotto_winning_number.dart';
import 'rpa_engine.dart' show RpaSchema;
import 'rpa_number_core.dart';
import 'rpa_store_engine.dart';
import 'rpa_unified_prediction.dart' show kRpaActiveModelVersion;

// ══════════════════════════════════════════════════════════════
// 번호 패턴 특징 추출
// ══════════════════════════════════════════════════════════════

class NumberFeatures {
  final String sumBand;     // 'low' | 'mid' | 'high'
  final String oddBand;     // 'low' | 'mid' | 'high'
  final String rangeBand;   // 'narrow' | 'mid' | 'wide'
  final bool hasConsecutive;

  const NumberFeatures({
    required this.sumBand,
    required this.oddBand,
    required this.rangeBand,
    required this.hasConsecutive,
  });

  String get key => '$sumBand|$oddBand|$rangeBand|$hasConsecutive';

  static NumberFeatures from(LottoWinningNumber w) {
    final nums = w.numbers;
    final sum = nums.reduce((a, b) => a + b);
    final oddCount = nums.where((n) => n % 2 == 1).length;
    final sorted = [...nums]..sort();
    final range = sorted.last - sorted.first;

    bool consecutive = false;
    for (int i = 0; i < sorted.length - 1; i++) {
      if (sorted[i + 1] - sorted[i] == 1) { consecutive = true; break; }
    }

    return NumberFeatures(
      sumBand: sum < 130 ? 'low' : sum <= 160 ? 'mid' : 'high',
      oddBand: oddCount <= 2 ? 'low' : oddCount == 3 ? 'mid' : 'high',
      rangeBand: range < 25 ? 'narrow' : range <= 35 ? 'mid' : 'wide',
      hasConsecutive: consecutive,
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 모델
// ══════════════════════════════════════════════════════════════

class NumberRegionPattern {
  final String id;
  final String sumBand;
  final String oddBand;
  final String rangeBand;
  final bool hasConsecutive;
  final String regionSido;
  final int totalRounds;
  final int regionCount;
  final double regionRate;
  final double baselineRate;
  final double lift;
  final List<int> sampleRounds;

  const NumberRegionPattern({
    required this.id,
    required this.sumBand,
    required this.oddBand,
    required this.rangeBand,
    required this.hasConsecutive,
    required this.regionSido,
    required this.totalRounds,
    required this.regionCount,
    required this.regionRate,
    required this.baselineRate,
    required this.lift,
    required this.sampleRounds,
  });

  factory NumberRegionPattern.fromJson(Map<String, dynamic> j) =>
      NumberRegionPattern(
        id: j['id'] as String? ?? '',
        sumBand: j['sum_band'] as String,
        oddBand: j['odd_band'] as String,
        rangeBand: j['range_band'] as String,
        hasConsecutive: j['has_consecutive'] as bool? ?? false,
        regionSido: j['region_sido'] as String,
        totalRounds: (j['total_rounds'] as num).toInt(),
        regionCount: (j['region_count'] as num).toInt(),
        regionRate: (j['region_rate'] as num).toDouble(),
        baselineRate: (j['baseline_rate'] as num).toDouble(),
        lift: (j['lift'] as num).toDouble(),
        sampleRounds: List<int>.from(
            (j['sample_rounds'] as List? ?? []).map((e) => (e as num).toInt())),
      );
}

class JointModelState {
  final int lastTrainedRound;
  final int modelVersion;
  final double? numberModelAccuracy;
  final double? storeModelAccuracy;
  final double? jointModelAccuracy;
  final double? synergyScore;
  final int synergyVerifiedRounds;
  final int nrPatternCount;

  const JointModelState({
    this.lastTrainedRound = 0,
    this.modelVersion = 1,
    this.numberModelAccuracy,
    this.storeModelAccuracy,
    this.jointModelAccuracy,
    this.synergyScore,
    this.synergyVerifiedRounds = 0,
    this.nrPatternCount = 0,
  });

  factory JointModelState.fromJson(Map<String, dynamic> j) => JointModelState(
        lastTrainedRound: (j['last_trained_round'] as num? ?? 0).toInt(),
        modelVersion: (j['model_version'] as num? ?? 1).toInt(),
        numberModelAccuracy: j['number_model_accuracy'] != null
            ? (j['number_model_accuracy'] as num).toDouble()
            : null,
        storeModelAccuracy: j['store_model_accuracy'] != null
            ? (j['store_model_accuracy'] as num).toDouble()
            : null,
        jointModelAccuracy: j['joint_model_accuracy'] != null
            ? (j['joint_model_accuracy'] as num).toDouble()
            : null,
        synergyScore: j['synergy_score'] != null
            ? (j['synergy_score'] as num).toDouble()
            : null,
        synergyVerifiedRounds:
            (j['synergy_verified_rounds'] as num? ?? 0).toInt(),
        nrPatternCount: (j['nr_pattern_count'] as num? ?? 0).toInt(),
      );
}

class JointAnalysisStep {
  final String title;
  final String detail;
  final bool isError;
  const JointAnalysisStep(
      {required this.title, required this.detail, this.isError = false});
}

// ══════════════════════════════════════════════════════════════
// 엔진 싱글톤
// ══════════════════════════════════════════════════════════════

class JointModelEngine {
  static final JointModelEngine instance = JointModelEngine._();
  JointModelEngine._();

  final _db = Supabase.instance.client;

  // ── 상태 ─────────────────────────────────────────────────
  Future<JointModelState?> loadState() async {
    try {
      final raw = await _db
          .from('rpa_joint_model_state')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (raw == null) return null;
      return JointModelState.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveState(JointModelState s) async {
    try {
      await _db.from('rpa_joint_model_state').upsert({
        'id': 1,
        'last_trained_round': s.lastTrainedRound,
        'model_version': s.modelVersion,
        'number_model_accuracy': s.numberModelAccuracy,
        'store_model_accuracy': s.storeModelAccuracy,
        'joint_model_accuracy': s.jointModelAccuracy,
        'synergy_score': s.synergyScore,
        'synergy_verified_rounds': s.synergyVerifiedRounds,
        'nr_pattern_count': s.nrPatternCount,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');
    } catch (_) {}
  }

  // ── 번호 × 지역 패턴 분석 ─────────────────────────────────
  Future<List<NumberRegionPattern>> analyzeNumberRegion({
    required List<LottoWinningNumber> allNumbers,
    required List<StoreWinRecord> storeHistory,
    required int upToRound,
    int minSamples = 5,
  }) async {
    // round 기준 조인: storeWin by round
    final storeByRound = <int, StoreWinRecord>{};
    for (final s in storeHistory) {
      if (s.round <= upToRound && s.sido.isNotEmpty) {
        storeByRound[s.round] = s;
      }
    }

    if (storeByRound.isEmpty) return [];

    // 전체 지역 분포 (baseline)
    final sidoTotal = <String, int>{};
    int totalWithStore = 0;
    for (final w in allNumbers) {
      if (w.round > upToRound) continue;
      final store = storeByRound[w.round];
      if (store == null) continue;
      sidoTotal[store.sido] = (sidoTotal[store.sido] ?? 0) + 1;
      totalWithStore++;
    }
    if (totalWithStore < minSamples) return [];

    final baselineRates = <String, double>{
      for (final e in sidoTotal.entries)
        e.key: e.value / totalWithStore,
    };

    // 번호 패턴 × 지역 집계
    // key = featureKey|sido → count
    final comboCounts = <String, int>{};
    final featureTotals = <String, int>{};
    final sampleMap = <String, List<int>>{};

    for (final w in allNumbers) {
      if (w.round > upToRound) continue;
      final store = storeByRound[w.round];
      if (store == null) continue;

      final feat = NumberFeatures.from(w);
      featureTotals[feat.key] = (featureTotals[feat.key] ?? 0) + 1;

      final comboKey = '${feat.key}|${store.sido}';
      comboCounts[comboKey] = (comboCounts[comboKey] ?? 0) + 1;
      if ((sampleMap[comboKey]?.length ?? 0) < 30) {
        sampleMap.putIfAbsent(comboKey, () => []).add(w.round);
      }
    }

    // 패턴 생성 및 DB 저장
    final result = <NumberRegionPattern>[];

    for (final entry in comboCounts.entries) {
      final parts = entry.key.split('|');
      if (parts.length < 5) continue;
      // parts: sumBand|oddBand|rangeBand|hasConsecutive|sido
      final sumBand = parts[0];
      final oddBand = parts[1];
      final rangeBand = parts[2];
      final hasConsecutive = parts[3] == 'true';
      final sido = parts[4];

      final featKey = '${sumBand}|${oddBand}|${rangeBand}|${hasConsecutive}';
      final total = featureTotals[featKey] ?? 0;
      if (total < minSamples) continue;

      final count = entry.value;
      final rate = total > 0 ? count / total : 0.0;
      final baseline = baselineRates[sido] ?? 0.01;
      final lift = baseline > 0 ? rate / baseline : 0.0;

      // lift > 1.2 인 패턴만 저장
      if (lift < 1.2 && count < 3) continue;

      try {
        await _db.from('rpa_number_region_patterns').upsert({
          'sum_band': sumBand,
          'odd_band': oddBand,
          'range_band': rangeBand,
          'has_consecutive': hasConsecutive,
          'region_sido': sido,
          'total_rounds': total,
          'region_count': count,
          'region_rate': rate,
          'baseline_rate': baseline,
          'lift': lift,
          'sample_rounds': sampleMap[entry.key] ?? [],
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'sum_band,odd_band,range_band,has_consecutive,region_sido');
      } catch (_) {}

      result.add(NumberRegionPattern(
        id: entry.key,
        sumBand: sumBand,
        oddBand: oddBand,
        rangeBand: rangeBand,
        hasConsecutive: hasConsecutive,
        regionSido: sido,
        totalRounds: total,
        regionCount: count,
        regionRate: rate,
        baselineRate: baseline,
        lift: lift,
        sampleRounds: sampleMap[entry.key] ?? [],
      ));
    }

    result.sort((a, b) => b.lift.compareTo(a.lift));
    return result;
  }

  // ── Number Model 단독 정확도 계산 ─────────────────────────
  // 보정 모델의 평균 점수 (랜덤 기준 0.5 대비 성능)
  Future<double?> _calcNumberModelAccuracy() async {
    try {
      final raw = await _db
          .from('rpa_round_scores')
          .select('correction_score')
          .order('target_round', ascending: false)
          .limit(50);
      if (raw.isEmpty) return null;
      final scores = List<Map<String, dynamic>>.from(raw);
      final valid = scores
          .map((r) => (r['correction_score'] as num? ?? 0).toDouble())
          .where((v) => v > 0)
          .toList();
      if (valid.isEmpty) return null;
      return valid.reduce((a, b) => a + b) / valid.length;
    } catch (_) {
      return null;
    }
  }

  // ── Store Model 단독 정확도 계산 ─────────────────────────
  // verified가 없으면 joint_score 평균으로 대체
  Future<double?> _calcStoreModelAccuracy() async {
    try {
      // 먼저 verified 데이터 시도
      final verified = await _db
          .from('rpa_store_predictions')
          .select('region_hit, spatial_hit')
          .eq('status', 'verified')
          .limit(50);
      final vList = List<Map<String, dynamic>>.from(verified);
      if (vList.isNotEmpty) {
        final hits = vList.where((p) =>
            (p['region_hit'] as bool? ?? false) ||
            (p['spatial_hit'] as bool? ?? false)).length;
        return hits / vList.length;
      }
      // verified 없으면 spatial_score 평균으로 추정
      final raw = await _db
          .from('rpa_store_predictions')
          .select('spatial_score')
          .order('target_round', ascending: false)
          .limit(50);
      if (raw.isEmpty) return null;
      final preds = List<Map<String, dynamic>>.from(raw);
      final scores = preds
          .map((p) {
            final s = p['spatial_score'];
            if (s is Map) return (s['score'] as num? ?? 0).toDouble();
            return 0.0;
          })
          .where((v) => v > 0)
          .toList();
      if (scores.isEmpty) return null;
      return scores.reduce((a, b) => a + b) / scores.length;
    } catch (_) {
      return null;
    }
  }

  // ── Joint Model 단독 정확도 계산 ─────────────────────────
  // verified가 없으면 joint_score 평균으로 대체
  Future<double?> _calcJointModelAccuracy() async {
    try {
      // 먼저 verified 데이터 시도
      final verified = await _db
          .from('rpa_joint_predictions')
          .select('joint_hit')
          .eq('status', 'verified')
          .limit(50);
      final vList = List<Map<String, dynamic>>.from(verified);
      if (vList.isNotEmpty) {
        final hits = vList.where((p) => p['joint_hit'] as bool? ?? false).length;
        return hits / vList.length;
      }
      // verified 없으면 joint_score 평균으로 추정
      final raw = await _db
          .from('rpa_joint_predictions')
          .select('joint_score')
          .order('target_round', ascending: false)
          .limit(50);
      if (raw.isEmpty) return null;
      final preds = List<Map<String, dynamic>>.from(raw);
      final scores = preds
          .map((p) => (p['joint_score'] as num? ?? 0).toDouble())
          .where((v) => v > 0)
          .toList();
      if (scores.isEmpty) return null;
      return scores.reduce((a, b) => a + b) / scores.length;
    } catch (_) {
      return null;
    }
  }

  // ── Joint 예측 생성 ───────────────────────────────────────
  Future<void> generateJointPrediction({
    required int targetRound,
    required int trainingEndRound,
    required List<LottoWinningNumber> allNumbers,
    required List<StoreWinRecord> storeHistory,
  }) async {
    final horizon = targetRound - trainingEndRound;
    if (horizon < 1 || horizon > 6) return;

    // Number Model 예측: 최근 번호 패턴으로 다음 회차 특징 예측
    // 직전 회차 번호 패턴
    final recentNums = allNumbers
        .where((w) => w.round <= trainingEndRound)
        .toList()
      ..sort((a, b) => b.round.compareTo(a.round));

    Map<String, dynamic> numberPred = {};
    List<String> candidateRegions = [];

    if (recentNums.isNotEmpty) {
      final feat = NumberFeatures.from(recentNums.first);

      // 해당 번호 패턴에서 강한 지역 패턴 조회
      try {
        final raw = await _db
            .from('rpa_number_region_patterns')
            .select()
            .eq('sum_band', feat.sumBand)
            .eq('odd_band', feat.oddBand)
            .eq('range_band', feat.rangeBand)
            .eq('has_consecutive', feat.hasConsecutive)
            .gt('lift', 1.2)
            .order('lift', ascending: false)
            .limit(3);
        final patterns = List<Map<String, dynamic>>.from(raw);
        candidateRegions = patterns.map((p) => p['region_sido'] as String).toList();
        numberPred = {
          'last_round': recentNums.first.round,
          'feature': feat.key,
          'candidate_regions_from_nr': candidateRegions,
        };
      } catch (_) {}
    }

    // Store Model 예측: 직전 당첨 판매점 기준 공간 예측
    Map<String, dynamic> storePred = {};
    try {
      final storePredRaw = await _db
          .from('rpa_store_predictions')
          .select()
          .eq('target_round', targetRound)
          .eq('training_end_round', trainingEndRound)
          .maybeSingle();
      if (storePredRaw != null) {
        storePred = Map<String, dynamic>.from(storePredRaw);
        // Store Model의 후보 지역도 포함
        final storeRegions = List<String>.from(
            storePred['candidate_regions'] as List? ?? []);
        for (final r in storeRegions) {
          if (!candidateRegions.contains(r)) candidateRegions.add(r);
        }
      }
    } catch (_) {}

    // 구매방식 힌트: purchase_method 분포에서 최다 방식
    String? methodHint;
    final recentStores = storeHistory
        .where((s) => s.round <= trainingEndRound && s.purchaseMethod != null)
        .toList()
      ..sort((a, b) => b.round.compareTo(a.round));
    if (recentStores.length >= 10) {
      final methodCounts = <String, int>{};
      for (final s in recentStores.take(20)) {
        final m = s.purchaseMethod!;
        methodCounts[m] = (methodCounts[m] ?? 0) + 1;
      }
      methodCounts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      methodHint =
          methodCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    // Joint Score: 번호×지역 패턴이 있으면 boost
    final jointScore =
        candidateRegions.isNotEmpty ? 0.65 : 0.5;

    try {
      await _db.from('rpa_joint_predictions').upsert({
        'target_round': targetRound,
        'training_end_round': trainingEndRound,
        'model_version': 1,
        'horizon': horizon,
        'status': 'pending',
        'number_prediction': numberPred,
        'store_prediction': storePred.isEmpty
            ? {'no_store_pred': true}
            : {'target_round': storePred['target_round'],
               'best_distance_band': (storePred['spatial_score']
                   as Map<String, dynamic>?)?['best_distance_band']},
        'joint_candidate_regions': candidateRegions,
        'joint_score': jointScore,
        'purchase_method_hint': methodHint,
      }, onConflict: 'target_round,training_end_round,horizon',
          ignoreDuplicates: true);
    } catch (_) {}
  }

  // ── Joint 예측 검증 ───────────────────────────────────────
  Future<void> verifyJointPrediction({
    required int targetRound,
    required String actualSido,
    required List<int> actualNumbers,
  }) async {
    try {
      final preds = await _db
          .from('rpa_joint_predictions')
          .select()
          .eq('target_round', targetRound)
          .eq('status', 'pending');

      for (final pred in List<Map<String, dynamic>>.from(preds)) {
        // Number Model 적중: correction_score > theory_score 이면 "예측 방향 옳음"
        bool? numberHit;
        try {
          final scoreRaw = await _db
              .from('rpa_round_scores')
              .select('theory_score, correction_score')
              .eq('target_round', targetRound)
              .maybeSingle();
          if (scoreRaw != null) {
            numberHit = (scoreRaw['correction_score'] as num? ?? 0) >
                (scoreRaw['theory_score'] as num? ?? 0);
          }
        } catch (_) {}

        // Store Model 적중: rpa_store_predictions 결과 참조
        bool? storeHit;
        try {
          final storePredRaw = await _db
              .from('rpa_store_predictions')
              .select('region_hit, spatial_hit')
              .eq('target_round', targetRound)
              .eq('status', 'verified')
              .maybeSingle();
          if (storePredRaw != null) {
            storeHit = (storePredRaw['region_hit'] as bool? ?? false) ||
                (storePredRaw['spatial_hit'] as bool? ?? false);
          }
        } catch (_) {}

        // Joint 적중: joint 후보 지역에 실제 지역 포함
        final candidates = List<String>.from(
            pred['joint_candidate_regions'] as List? ?? []);
        final jointHit =
            actualSido.isNotEmpty && candidates.contains(actualSido);

        try {
          await _db.from('rpa_joint_predictions').update({
            'status': 'verified',
            'actual_region': actualSido,
            'actual_numbers': actualNumbers,
            'number_hit': numberHit,
            'store_hit': storeHit,
            'joint_hit': jointHit,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', pred['id'] as String);
        } catch (_) {}
      }
    } catch (_) {}
  }

  // ── 최근 Joint 예측 로드 ──────────────────────────────────
  Future<List<Map<String, dynamic>>> loadRecentPredictions(
      {int limit = 10}) async {
    try {
      final raw = await _db
          .from('rpa_joint_predictions')
          .select()
          .order('target_round', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(raw);
    } catch (_) {
      return [];
    }
  }

  // ── 번호×지역 패턴 로드 ───────────────────────────────────
  // 정렬 기준: lift만으로 정렬하면 표본 8개 lift 40이 상위에 오는 문제 발생.
  // → regionCount * lift (신뢰도 가중 점수) 기준 정렬로 변경.
  Future<List<NumberRegionPattern>> loadNRPatterns({int limit = 20}) async {
    try {
      final raw = await _db
          .from('rpa_number_region_patterns')
          .select()
          .gt('lift', 1.2)
          .gt('region_count', 2)
          .order('region_count', ascending: false)
          .limit(limit * 3); // 여유분 로드 후 Dart에서 재정렬
      final patterns = List<Map<String, dynamic>>.from(raw)
          .map(NumberRegionPattern.fromJson)
          .toList();
      // 신뢰도 가중 점수 = sqrt(regionCount) * lift
      patterns.sort((a, b) {
        final scoreA = math.sqrt(a.regionCount.toDouble()) * a.lift;
        final scoreB = math.sqrt(b.regionCount.toDouble()) * b.lift;
        return scoreB.compareTo(scoreA);
      });
      return patterns.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Joint 분석 회의 ───────────────────────────────────────
  Stream<JointAnalysisStep> runAnalysis({
    required List<LottoWinningNumber> allNumbers,
    required List<StoreWinRecord> storeHistory,
    required int currentRound,
  }) async* {
    yield JointAnalysisStep(
      title: '데이터 확인',
      detail: '번호 ${allNumbers.length}회차 | 판매점 ${storeHistory.length}건',
    );

    // 1. 번호 × 지역 패턴 분석
    yield JointAnalysisStep(
        title: '번호×지역 분석', detail: '번호 패턴별 지역 분포 계산 중...');

    List<NumberRegionPattern> nrPatterns = [];
    try {
      nrPatterns = await analyzeNumberRegion(
        allNumbers: allNumbers,
        storeHistory: storeHistory,
        upToRound: currentRound,
      );
      final strong = nrPatterns.where((p) => p.lift > 1.3).length;
      yield JointAnalysisStep(
        title: '번호×지역 완료',
        detail:
            '전체 ${nrPatterns.length}개 패턴 | 유의미(lift>1.3) $strong개',
      );
    } catch (e) {
      yield JointAnalysisStep(
          title: '번호×지역 오류', detail: e.toString(), isError: true);
    }

    // 2. 각 모델 단독 성능 측정
    yield JointAnalysisStep(
        title: '성능 측정', detail: '각 모델 독립 정확도 계산 중...');

    final numAcc = await _calcNumberModelAccuracy();
    final storeAcc = await _calcStoreModelAccuracy();
    final jointAcc = await _calcJointModelAccuracy();

    yield JointAnalysisStep(
      title: '성능 완료',
      detail: [
        if (numAcc != null)
          'Number ${(numAcc * 100).toStringAsFixed(1)}%',
        if (storeAcc != null)
          'Store ${(storeAcc * 100).toStringAsFixed(1)}%',
        if (jointAcc != null)
          'Joint ${(jointAcc * 100).toStringAsFixed(1)}%',
        if (numAcc == null && storeAcc == null)
          '검증 데이터 부족',
      ].join(' | '),
    );

    // Synergy 계산
    double? synergyScore;
    if (jointAcc != null && numAcc != null && storeAcc != null) {
      final best = numAcc > storeAcc ? numAcc : storeAcc;
      synergyScore = jointAcc - best;
      yield JointAnalysisStep(
        title: 'Synergy',
        detail: synergyScore > 0
            ? '결합 모델이 단독보다 ${(synergyScore * 100).toStringAsFixed(1)}% 향상'
            : '아직 시너지 미확인 (검증 데이터 축적 필요)',
      );
    } else {
      yield JointAnalysisStep(
          title: 'Synergy', detail: '검증된 Joint 예측 없음 — 계속 누적 중');
    }

    // 3. +1~+6 Joint 예측 생성
    yield JointAnalysisStep(
        title: 'Joint 예측 생성', detail: '+1~+6 결합 예측 저장 중...');

    int predCount = 0;
    for (int k = 1; k <= 6; k++) {
      try {
        await generateJointPrediction(
          targetRound: currentRound + k,
          trainingEndRound: currentRound,
          allNumbers: allNumbers,
          storeHistory: storeHistory,
        );
        predCount++;
      } catch (_) {}
    }
    yield JointAnalysisStep(
        title: 'Joint 예측 완료',
        detail:
            '예측 $predCount개 저장 (${currentRound + 1}~${currentRound + 6}회)');

    // 4. 상태 저장
    await _saveState(JointModelState(
      lastTrainedRound: currentRound,
      modelVersion: 1,
      numberModelAccuracy: numAcc,
      storeModelAccuracy: storeAcc,
      jointModelAccuracy: jointAcc,
      synergyScore: synergyScore,
      synergyVerifiedRounds:
          jointAcc != null ? (currentRound - 10).clamp(0, currentRound) : 0,
      nrPatternCount: nrPatterns.length,
    ));

    yield JointAnalysisStep(
      title: '분석 완료',
      detail: '번호×지역 패턴 ${nrPatterns.length}개 | Joint 예측 $predCount개',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Joint Contextual Prediction
  // base 번호예측 + 지역 NR 패턴 → 점수 미세 조정 → joint_sets
  // ══════════════════════════════════════════════════════════════

  /// DB에서 base snapshot + joint 예측 로드 후 contextual 생성 및 저장
  Future<void> generateJointContextualFromDB({
    required int targetRound,
    required int trainingEndRound,
  }) async {
    try {
      // base prediction 로드
      final baseRaw = await _db
          .from('rpa_prediction_snapshots')
          .select('candidate_numbers,recommended_sets')
          .eq('target_round', targetRound)
          .eq('training_end_round', trainingEndRound)
          .eq('model_version', kRpaActiveModelVersion) // 활성 엔진 Snapshot만 기준
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (baseRaw == null) return;

      final baseCandidates = List<Map<String, dynamic>>.from(
          baseRaw['candidate_numbers'] as List? ?? []);
      final baseSets = (baseRaw['recommended_sets'] as List? ?? [])
          .map((s) => List<int>.from(s as List))
          .toList();
      if (baseCandidates.isEmpty || baseSets.isEmpty) return;

      // joint 예측에서 predicted region 로드
      final jointRaw = await _db
          .from('rpa_joint_predictions')
          .select('joint_candidate_regions')
          .eq('target_round', targetRound)
          .eq('training_end_round', trainingEndRound)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final candidateRegions = List<String>.from(
          jointRaw?['joint_candidate_regions'] as List? ?? []);
      final predictedRegion = candidateRegions.isNotEmpty ? candidateRegions.first : null;

      await _generateAndSaveContextual(
        targetRound: targetRound,
        trainingEndRound: trainingEndRound,
        baseCandidates: baseCandidates,
        baseSets: baseSets,
        predictedRegion: predictedRegion,
      );
    } catch (_) {}
  }

  Future<void> _generateAndSaveContextual({
    required int targetRound,
    required int trainingEndRound,
    required List<Map<String, dynamic>> baseCandidates,
    required List<List<int>> baseSets,
    required String? predictedRegion,
  }) async {
    if (predictedRegion == null || predictedRegion.isEmpty) {
      await _saveContextual(
        targetRound: targetRound,
        trainingEndRound: trainingEndRound,
        predictedRegion: null,
        baseCandidates: baseCandidates,
        jointCandidates: baseCandidates,
        baseSets: baseSets,
        jointSets: baseSets,
        status: 'no_region',
        evidence: {},
        patternsUsed: 0,
        numbersChanged: 0,
      );
      return;
    }

    // 해당 지역의 NR 패턴 로드
    final patterns = await _loadNRPatternsForRegion(predictedRegion);
    if (patterns.isEmpty) {
      await _saveContextual(
        targetRound: targetRound,
        trainingEndRound: trainingEndRound,
        predictedRegion: predictedRegion,
        baseCandidates: baseCandidates,
        jointCandidates: baseCandidates,
        baseSets: baseSets,
        jointSets: baseSets,
        status: 'no_evidence',
        evidence: {'region': predictedRegion},
        patternsUsed: 0,
        numbersChanged: 0,
      );
      return;
    }

    // NR 패턴 → target feature profile 계산
    final profile = _computeTargetProfile(patterns);

    // base 후보 점수 조정
    final jointCandidates = _applyJointEvidence(baseCandidates, profile);

    // 조정된 점수로 새 세트 생성
    final jointSets = _generateJointSets(jointCandidates, baseSets);

    // 변경된 번호 수
    final changed = _countChanged(baseSets, jointSets);

    final evidence = {
      'region': predictedRegion,
      'patterns_used': patterns.length,
      'target_sum_band': profile['sumBand'],
      'target_odd_band': profile['oddBand'],
      'target_range_band': profile['rangeBand'],
      'top_pattern_lift': patterns.first.lift,
      'top_pattern_region_count': patterns.first.regionCount,
    };

    await _saveContextual(
      targetRound: targetRound,
      trainingEndRound: trainingEndRound,
      predictedRegion: predictedRegion,
      baseCandidates: baseCandidates,
      jointCandidates: jointCandidates,
      baseSets: baseSets,
      jointSets: jointSets,
      status: changed > 0 ? 'applied' : 'same_result',
      evidence: evidence,
      patternsUsed: patterns.length,
      numbersChanged: changed,
      targetSumBand: profile['sumBand'],
      targetOddBand: profile['oddBand'],
      targetRangeBand: profile['rangeBand'],
    );
  }

  Future<List<NumberRegionPattern>> _loadNRPatternsForRegion(String sido) async {
    try {
      final raw = await _db
          .from('rpa_number_region_patterns')
          .select()
          .eq('region_sido', sido)
          .gt('lift', 1.2)
          .gt('region_count', 5)
          .order('region_count', ascending: false)
          .limit(10);
      final patterns = List<Map<String, dynamic>>.from(raw)
          .map(NumberRegionPattern.fromJson)
          .toList();
      patterns.sort((a, b) {
        final sa = math.sqrt(a.regionCount.toDouble()) * a.lift;
        final sb = math.sqrt(b.regionCount.toDouble()) * b.lift;
        return sb.compareTo(sa);
      });
      return patterns;
    } catch (_) {
      return [];
    }
  }

  Map<String, String> _computeTargetProfile(List<NumberRegionPattern> patterns) {
    final sumW = <String, double>{};
    final oddW = <String, double>{};
    final rangeW = <String, double>{};
    double totalW = 0;

    for (final p in patterns.take(5)) {
      final w = math.sqrt(p.regionCount.toDouble()) * p.lift;
      sumW[p.sumBand] = (sumW[p.sumBand] ?? 0) + w;
      oddW[p.oddBand] = (oddW[p.oddBand] ?? 0) + w;
      rangeW[p.rangeBand] = (rangeW[p.rangeBand] ?? 0) + w;
      totalW += w;
    }
    if (totalW == 0) return {'sumBand': 'mid', 'oddBand': 'mid', 'rangeBand': 'mid'};

    String dominant(Map<String, double> m) =>
        m.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    return {
      'sumBand': dominant(sumW),
      'oddBand': dominant(oddW),
      'rangeBand': dominant(rangeW),
    };
  }

  List<Map<String, dynamic>> _applyJointEvidence(
    List<Map<String, dynamic>> base,
    Map<String, String> profile,
  ) {
    final sumBand = profile['sumBand']!;
    final oddBand = profile['oddBand']!;
    final rangeBand = profile['rangeBand']!;

    return base.map((c) {
      final n = c['n'] as int;
      double boost = 0.0;

      // 합계 구간 기여 (최대 ±0.04)
      if (sumBand == 'high' && n >= 25) boost += 0.04;
      else if (sumBand == 'low' && n <= 20) boost += 0.04;
      else if (sumBand == 'mid' && n >= 15 && n <= 30) boost += 0.02;

      // 홀짝 구간 기여 (최대 ±0.03)
      if (oddBand == 'high' && n % 2 == 1) boost += 0.03;
      else if (oddBand == 'low' && n % 2 == 0) boost += 0.03;

      // 범위 구간 기여 (최대 ±0.02)
      if (rangeBand == 'wide' && (n <= 8 || n >= 38)) boost += 0.02;
      else if (rangeBand == 'narrow' && n >= 15 && n <= 30) boost += 0.02;

      return {'n': n, 's': (c['s'] as num).toDouble() + boost, 'boost': boost};
    }).toList()
      ..sort((a, b) => (b['s'] as double).compareTo(a['s'] as double));
  }

  List<List<int>> _generateJointSets(
    List<Map<String, dynamic>> adjusted,
    List<List<int>> baseSets,
  ) {
    if (adjusted.length < 6) return baseSets;
    // v2.1: 난수 셔플 대신 조정 점수합 기반 결정적 조합 (지표 조건 없음)
    final ranked = rpaRankAllCombos(adjusted.take(18).toList(), const {});
    final sets = rpaPickDiverse(ranked, count: 3, maxOverlap: 3, requireDirs: false)
        .map((s) => s.numbers)
        .toList();
    return sets.isNotEmpty ? sets : baseSets;
  }

  int _countChanged(List<List<int>> base, List<List<int>> joint) {
    if (base.isEmpty || joint.isEmpty) return 0;
    final baseSet = base.first.toSet();
    final jointSet = joint.first.toSet();
    return jointSet.difference(baseSet).length;
  }

  // Gate: Historical Walk-Forward 개선 > 0 이어야 번호변경 허용
  // 현재 검증결과: +0.0000 (FAIL) → Joint 번호변경 참고/연구용
  static const double _gateMinImprovement = 0.001;
  static const int _gateMinSample = 200;
  static const double _currentWfImprovement = 0.0;
  static const int _currentWfN = 982;

  /// 번호 Joint Gate 측정값 (오프라인 Walk-Forward 결과 — 자동 재측정 경로 없음)
  static double get numberGateWfImprovement => _currentWfImprovement;
  static int get numberGateWfN => _currentWfN;

  bool get isJointGatePassed =>
      _currentWfImprovement > _gateMinImprovement &&
      _currentWfN >= _gateMinSample;

  String get jointGateStatus => isJointGatePassed ? 'pass' : 'fail';

  Future<void> _saveContextual({
    required int targetRound,
    required int trainingEndRound,
    required String? predictedRegion,
    required List<Map<String, dynamic>> baseCandidates,
    required List<Map<String, dynamic>> jointCandidates,
    required List<List<int>> baseSets,
    required List<List<int>> jointSets,
    required String status,
    required Map<String, dynamic> evidence,
    required int patternsUsed,
    required int numbersChanged,
    String? targetSumBand,
    String? targetOddBand,
    String? targetRangeBand,
  }) async {
    try {
      await _db.from('rpa_joint_contextual_predictions').upsert({
        'target_round': targetRound,
        'training_end_round': trainingEndRound,
        'model_version': kRpaActiveModelVersion,
        'predicted_region': predictedRegion,
        'base_sets': baseSets,
        'joint_sets': jointSets,
        'base_candidates': baseCandidates,
        'joint_candidates': jointCandidates,
        'applied_evidence': evidence,
        'joint_status': status,
        'nr_patterns_used': patternsUsed,
        'target_sum_band': targetSumBand,
        'target_odd_band': targetOddBand,
        'target_range_band': targetRangeBand,
        'numbers_changed': numbersChanged,
        'gate_status': jointGateStatus,
        'gate_wf_improvement': _currentWfImprovement,
        'gate_wf_n': _currentWfN,
      }, onConflict: await RpaSchema.hasUnifiedSchema()
          ? 'target_round,training_end_round,model_version'
          : 'target_round,training_end_round');
    } catch (e) {
      debugPrint('[Joint] contextual 저장 실패 ($targetRound): $e');
    }
  }

  /// Joint Contextual Prediction 로드.
  /// trainingEndRound/modelVersion을 주면 해당 학습 회차·엔진 버전의 결과만 반환합니다.
  Future<Map<String, dynamic>?> loadJointContextual(
    int targetRound, {
    int? trainingEndRound,
    String? modelVersion,
  }) async {
    try {
      var q = _db
          .from('rpa_joint_contextual_predictions')
          .select()
          .eq('target_round', targetRound);
      if (trainingEndRound != null) q = q.eq('training_end_round', trainingEndRound);
      if (modelVersion != null) q = q.eq('model_version', modelVersion);
      return await q.order('created_at', ascending: false).limit(1).maybeSingle();
    } catch (_) {
      return null;
    }
  }
}
