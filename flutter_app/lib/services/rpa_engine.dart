// 랜덤확률분석엔진 v3 — 순차예측 / 보정학습 / 가설연구 / 자동운영
//
// 시간 원칙: target_round 예측 시 training_end_round 까지의 데이터만 사용.
// 예측 스냅샷은 생성 후 절대 수정하지 않는다.
// 보정은 별도 규칙으로 관리하고 이론값을 덮어쓰지 않는다.

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/lotto_winning_number.dart';
import 'rpa_hypothesis_engine.dart';
import 'rpa_store_engine.dart';
import 'rpa_joint_engine.dart';
import 'rpa_monte_carlo_engine.dart';
import 'rpa_joint_historical_engine.dart';
import 'rpa_number_core.dart';
import 'rpa_unified_prediction.dart';
import 'mnd_engine.dart';

// ── 모델 ID 유틸 ──────────────────────────────────────────────────
// 앱 설치 후 한 번 생성(1~10 랜덤)하여 SharedPreferences에 영구 저장.
// 패턴분석·추천판매점 화면에서 동일 번호를 읽어 "랜덤확률보정기 N번" 표시.
class RpaModelId {
  static const _key = 'rpa_model_id';
  static int? _cached;

  static Future<int> get() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    int? stored = prefs.getInt(_key);
    if (stored == null) {
      stored = Random().nextInt(10) + 1; // 1~10
      await prefs.setInt(_key, stored);
    }
    _cached = stored;
    return stored;
  }

  // 엔진 재학습 완료 시 새 모델 번호 발급 (1~10 재추첨)
  static Future<int> regenerate() async {
    final prefs = await SharedPreferences.getInstance();
    int newId = Random().nextInt(10) + 1;
    // 같은 번호 연속 방지
    if (_cached != null && newId == _cached) {
      newId = (newId % 10) + 1;
    }
    await prefs.setInt(_key, newId);
    _cached = newId;
    return newId;
  }

  // 캐시만 초기화 (다음 get() 호출 시 SharedPreferences에서 다시 읽음)
  static void clearCache() => _cached = null;
}

// ── 통합 예측 스키마 확인 ─────────────────────────────────────────
// rpa_v11_unified_prediction.sql 적용 여부를 확인합니다.
// 미적용이면 새 버전 Snapshot을 만들 수 없으므로 화면에 그 사실을 그대로 표시합니다.
class RpaSchema {
  static bool? _ready;
  static DateTime? _checkedAt;

  static const migrationMessage =
      'DB 마이그레이션 미적용: rpa_v11_unified_prediction.sql을 Supabase SQL Editor에서 실행해야 '
      '활성 엔진(v$kRpaActiveModelVersion) Snapshot을 저장할 수 있습니다.';

  static Future<bool> hasUnifiedSchema({bool force = false}) async {
    final fresh = _checkedAt != null &&
        DateTime.now().difference(_checkedAt!) < const Duration(minutes: 2);
    if (_ready == true || (!force && fresh && _ready != null)) return _ready!;
    final db = Supabase.instance.client;
    try {
      await db.from('rpa_prediction_snapshots').select('number_evaluations,gate_status').limit(1);
      await db.from('rpa_prediction_results').select('id').limit(1);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    _checkedAt = DateTime.now();
    return _ready!;
  }
}

class RpaPipelineError implements Exception {
  final String message;
  RpaPipelineError(this.message);
  @override
  String toString() => message;
}

enum RpaEnsureStatus { upToDate, generated, migrationRequired, noData, failed }

class RpaEnsureResult {
  final RpaEnsureStatus status;
  final String message;
  final int? trainingEndRound;
  const RpaEnsureResult(this.status, this.message, {this.trainingEndRound});
  bool get ok => status == RpaEnsureStatus.upToDate || status == RpaEnsureStatus.generated;
}

/// 화면 공통 데이터: 같은 학습 회차의 활성 버전 Snapshot + 통합 결과
class RpaActiveView {
  final int trainingEndRound;
  bool schemaReady = false;
  final Map<int, RpaPredSnapshot> activeSnapshots = {};   // horizon → 활성 버전
  final Map<int, RpaPredSnapshot> legacySnapshots = {};   // horizon → 이전 버전 (보존)
  final Map<int, Map<String, RpaPredictionResult>> results = {}; // horizon → type → result

  RpaActiveView({required this.trainingEndRound});

  RpaPredictionResult? result(int horizon, String type) => results[horizon]?[type];
}

RpaWalkForwardReport _walkForwardIsolate(Map<String, dynamic> p) => rpaWalkForward(
      List<LottoWinningNumber>.from(p['data'] as List),
      trainingEndRound: p['end'] as int,
    );

// ══════════════════════════════════════════════════════════
// Constants
// ══════════════════════════════════════════════════════════


// 6개 이진 지표 ID — 순수 랜덤 시 each = 50%가 되도록 정의
// oe33: 홀 3개인가    baseline=33.48% → 1이면 '홀짝3:3이 나왔다'
// lh33: 저번호 3개    baseline=33.48%
// cons: 연속 1쌍+     baseline=52.87%
// sp:   합 짝수       baseline=50%
// rhi:  범위폭>32.86  baseline≈50%
// phi:  소수 개수>1.87 baseline≈50%
const _indicatorIds = rpaIndicatorIds;

// ══════════════════════════════════════════════════════════
// Models
// ══════════════════════════════════════════════════════════

class RpaModelState {
  final int lastTrainedRound;
  final int nextPredictionRound;
  final bool replayCompleted;
  final int replayStartRound;
  final int totalPredictions;
  final int totalVerified;
  final double theoryAvgScore;
  final double correctionAvgScore;
  final double correctionVsTheory;
  final double correctionVsRandom;
  final double recent20Theory;
  final double recent20Correction;
  final DateTime updatedAt;
  // 현재 활성 flip 상태 (correction_rules 버그 우회: rolling state 최종값 직접 저장)
  final Map<String, bool> activeFlips;

  RpaModelState({
    this.lastTrainedRound = 0,
    this.nextPredictionRound = 0,
    this.replayCompleted = false,
    this.replayStartRound = 500,
    this.totalPredictions = 0,
    this.totalVerified = 0,
    this.theoryAvgScore = 0.5,
    this.correctionAvgScore = 0.5,
    this.correctionVsTheory = 0,
    this.correctionVsRandom = 0,
    this.recent20Theory = 0.5,
    this.recent20Correction = 0.5,
    DateTime? updatedAt,
    Map<String, bool>? activeFlips,
  })  : updatedAt = updatedAt ?? DateTime(2000),
        activeFlips = activeFlips ?? {for (final id in _indicatorIds) id: false};

  factory RpaModelState.fromJson(Map<String, dynamic> j) {
    Map<String, bool> flips = {for (final id in _indicatorIds) id: false};
    final raw = j['active_flips'];
    if (raw is Map) {
      for (final id in _indicatorIds) {
        flips[id] = (raw[id] as bool?) ?? false;
      }
    }
    return RpaModelState(
      lastTrainedRound: j['last_trained_round'] as int? ?? 0,
      nextPredictionRound: j['next_prediction_round'] as int? ?? 0,
      replayCompleted: j['replay_completed'] as bool? ?? false,
      replayStartRound: j['replay_start_round'] as int? ?? 500,
      totalPredictions: j['total_predictions'] as int? ?? 0,
      totalVerified: j['total_verified'] as int? ?? 0,
      theoryAvgScore: (j['theory_avg_score'] as num?)?.toDouble() ?? 0.5,
      correctionAvgScore:
          (j['correction_avg_score'] as num?)?.toDouble() ?? 0.5,
      correctionVsTheory:
          (j['correction_vs_theory'] as num?)?.toDouble() ?? 0,
      correctionVsRandom:
          (j['correction_vs_random'] as num?)?.toDouble() ?? 0,
      recent20Theory: (j['recent_20_theory'] as num?)?.toDouble() ?? 0.5,
      recent20Correction:
          (j['recent_20_correction'] as num?)?.toDouble() ?? 0.5,
      updatedAt: j['updated_at'] != null
          ? DateTime.parse(j['updated_at'] as String)
          : DateTime.now(),
      activeFlips: flips,
    );
  }
}

class RpaPredSnapshot {
  final String id;
  final int targetRound;
  final int trainingEndRound;
  final Map<String, String> theoryDirections;
  final Map<String, String> finalDirections;
  final Map<String, dynamic> correctionSnapshot;
  final String status;
  final DateTime createdAt;
  // 출처 추적
  final String? runId;
  final int? horizon;
  // 지표 필터 기반 후보
  final List<Map<String, dynamic>> candidateNumbers;   // [{n, s}, ...] top-18
  final List<List<int>> recommendedSets;               // [[6개 번호], ...]
  // 1~45 전체 번호 평가 (엔진 통합 판단)
  final List<Map<String, dynamic>> numberEvaluations;  // [{n, raw_score, final_score, rank, classification}, ...]
  // 통합 예측 계약 (v2.1+)
  final String modelVersion;
  final String? gateStatus;
  final String? validationStatus;
  final Map<String, dynamic> evidence;
  final DateTime? generatedAt;

  const RpaPredSnapshot({
    required this.id,
    required this.targetRound,
    required this.trainingEndRound,
    required this.theoryDirections,
    required this.finalDirections,
    this.correctionSnapshot = const {},
    required this.status,
    required this.createdAt,
    this.runId,
    this.horizon,
    this.candidateNumbers = const [],
    this.recommendedSets = const [],
    this.numberEvaluations = const [],
    this.modelVersion = '2.0',
    this.gateStatus,
    this.validationStatus,
    this.evidence = const {},
    this.generatedAt,
  });

  factory RpaPredSnapshot.fromJson(Map<String, dynamic> j) {
    Map<String, String> _dirs(dynamic raw) {
      if (raw == null) return {};
      return (raw as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String));
    }

    List<Map<String, dynamic>> _candidates(dynamic raw) {
      if (raw == null) return [];
      return (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    List<List<int>> _sets(dynamic raw) {
      if (raw == null) return [];
      return (raw as List).map((s) => List<int>.from((s as List).map((n) => n as int))).toList();
    }

    return RpaPredSnapshot(
      id: j['id'] as String,
      targetRound: j['target_round'] as int,
      trainingEndRound: j['training_end_round'] as int,
      theoryDirections:
          _dirs((j['theory_snapshot'] as Map<String, dynamic>?)?['directions']),
      finalDirections:
          _dirs((j['final_prediction'] as Map<String, dynamic>?)?['directions']),
      correctionSnapshot:
          (j['correction_snapshot'] as Map<String, dynamic>?) ?? {},
      status: j['status'] as String? ?? 'pending',
      createdAt: j['created_at'] != null
          ? DateTime.parse(j['created_at'] as String)
          : DateTime.now(),
      runId: j['run_id'] as String?,
      horizon: j['horizon'] as int?,
      candidateNumbers: _candidates(j['candidate_numbers']),
      recommendedSets: _sets(j['recommended_sets']),
      numberEvaluations: _candidates(j['number_evaluations']),
      modelVersion: '${j['model_version'] ?? '2.0'}',
      gateStatus: j['gate_status'] as String?,
      validationStatus: j['validation_status'] as String?,
      evidence: Map<String, dynamic>.from(j['evidence'] as Map? ?? {}),
      generatedAt: j['generated_at'] != null ? DateTime.tryParse('${j['generated_at']}') : null,
    );
  }
}

class RpaRoundScore {
  final int targetRound;
  final double theoryScore;
  final double correctionScore;
  final double correctionEffect;
  final Map<String, double> indicatorScores;

  const RpaRoundScore({
    required this.targetRound,
    required this.theoryScore,
    required this.correctionScore,
    required this.correctionEffect,
    required this.indicatorScores,
  });

  factory RpaRoundScore.fromJson(Map<String, dynamic> j) => RpaRoundScore(
        targetRound: j['target_round'] as int,
        theoryScore: (j['theory_score'] as num?)?.toDouble() ?? 0.5,
        correctionScore: (j['correction_score'] as num?)?.toDouble() ?? 0.5,
        correctionEffect: (j['correction_effect'] as num?)?.toDouble() ?? 0,
        indicatorScores: (j['indicator_scores'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
            {},
      );
}

class RpaCorrectionRule {
  final String id;
  final String indicatorId;
  final int useCount;
  final int improveCount;
  final int worsenCount;
  final double avgImprovement;
  final double weight;
  String status;

  RpaCorrectionRule({
    required this.id,
    required this.indicatorId,
    required this.useCount,
    required this.improveCount,
    required this.worsenCount,
    required this.avgImprovement,
    required this.weight,
    required this.status,
  });

  factory RpaCorrectionRule.fromJson(Map<String, dynamic> j) =>
      RpaCorrectionRule(
        id: j['id'] as String,
        indicatorId: j['indicator_id'] as String,
        useCount: j['use_count'] as int? ?? 0,
        improveCount: j['improve_count'] as int? ?? 0,
        worsenCount: j['worsen_count'] as int? ?? 0,
        avgImprovement: (j['avg_improvement'] as num?)?.toDouble() ?? 0,
        weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
        status: j['status'] as String? ?? 'active',
      );

  double get accuracy =>
      useCount == 0 ? 0 : improveCount / useCount;
  bool get isEffective => useCount >= 5 && accuracy > 0.55;
  bool get isHarmful => useCount >= 5 && accuracy < 0.35;
}

class RpaProcessResult {
  final bool success;
  final bool waitingForStore; // 판매점 크롤링 대기 중 (엔진 실행 보류)
  final int verifiedRound;
  final double theoryScore;
  final double correctionScore;
  final int predictionsSaved;
  final String? error;

  const RpaProcessResult({
    required this.success,
    this.waitingForStore = false,
    required this.verifiedRound,
    required this.theoryScore,
    required this.correctionScore,
    required this.predictionsSaved,
    this.error,
  });
}

// ── 회차 데이터 준비 게이트 ───────────────────────────────────────
class RpaRoundGate {
  final int round;
  final bool hasWinningNumbers;
  final bool hasStoreData;
  final String crawlStatus; // pending | running | success | failed
  final String engineStatus; // waiting_number | waiting_store | ready | processing | completed | failed

  const RpaRoundGate({
    required this.round,
    required this.hasWinningNumbers,
    required this.hasStoreData,
    required this.crawlStatus,
    required this.engineStatus,
  });

  bool get isReady =>
      hasWinningNumbers && hasStoreData && crawlStatus == 'success' &&
      (engineStatus == 'ready' || engineStatus == 'waiting_store' || engineStatus == 'waiting_number');

  bool get isCompleted => engineStatus == 'completed';

  factory RpaRoundGate.fromJson(Map<String, dynamic> j) => RpaRoundGate(
    round: j['round'] as int,
    hasWinningNumbers: j['has_winning_numbers'] as bool? ?? false,
    hasStoreData: j['has_store_data'] as bool? ?? false,
    crawlStatus: j['crawl_status'] as String? ?? 'pending',
    engineStatus: j['engine_status'] as String? ?? 'waiting_number',
  );
}

// ══════════════════════════════════════════════════════════
// Rolling State / 채점 — rpa_number_core.dart 단일 구현 사용
// ══════════════════════════════════════════════════════════

typedef _RollingState = RpaRollingState;

Map<String, double> _scoreDirections(
  Map<String, String> finalDirs,
  LottoWinningNumber actual,
) => rpaScoreDirections(finalDirs, actual.numbers);

double _meanScore(Map<String, double> scores) => rpaMeanScore(scores);

// ══════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════
// Historical Replay (top-level for compute())
// Returns list of result maps to save to Supabase
// ══════════════════════════════════════════════════════════

// isolate 반환: results 리스트 + 마지막 항목으로 final_flips 맵 포함
List<Map<String, dynamic>> _replayIsolate(Map<String, dynamic> params) {
  final rawData = params['data'] as List<dynamic>;
  final startRound = params['start_round'] as int;

  final data = rawData
      .map((e) => e as Map<String, dynamic>)
      .toList()
    ..sort((a, b) => (a['round'] as int).compareTo(b['round'] as int));

  final byRound = <int, Map<String, dynamic>>{
    for (final d in data) d['round'] as int: d,
  };

  final allRounds = data.map((d) => d['round'] as int).toList();
  final startIdx = allRounds.indexWhere((r) => r >= startRound);
  if (startIdx <= 0) return [];

  final rolling = _RollingState();

  // Pre-populate up to startRound
  for (int i = 0; i < startIdx; i++) {
    rolling.addRound(_toWinning(data[i]));
  }

  final results = <Map<String, dynamic>>[];

  for (int i = startIdx; i < allRounds.length; i++) {
    final targetRound = allRounds[i];
    final trainingEnd = allRounds[i - 1];

    final theory = rolling.theoryDirections();
    final rates = rolling.cumulativeRates();
    final flips = Map<String, bool>.from(rolling.activeFlips);
    final finalDirs = rolling.finalDirections(theory);

    // Verify immediately (historical)
    final actualRaw = byRound[targetRound];
    if (actualRaw == null) continue;
    final actual = _toWinning(actualRaw);
    final iScores = _scoreDirections(finalDirs, actual);
    final ts = _meanScore(_scoreDirections(theory, actual));
    final cs = _meanScore(iScores);

    results.add({
      'target_round': targetRound,
      'training_end_round': trainingEnd,
      'theory_snapshot': {'directions': theory, 'rates': rates},
      'correction_snapshot': {
        'flips': flips,
      },
      'final_prediction': {'directions': finalDirs},
      'theory_score': ts,
      'correction_score': cs,
      'correction_effect': cs - ts,
      'indicator_scores': iScores,
      'actual_numbers': actual.numbers,
      'actual_bonus': actual.bonusNumber,
    });

    // Record result in rolling state for next round's correction
    final actualVals = rpaActualIndicatorValues(actual.numbers);
    rolling.recordResult(finalDirs, actualVals);
    rolling.addRound(actual);
  }

  // 마지막에 final_flips 센티널 항목 추가 (target_round=-1 로 식별)
  results.add({
    'target_round': -1,
    'final_flips': Map<String, bool>.from(rolling.activeFlips),
  });

  return results;
}

LottoWinningNumber _toWinning(Map<String, dynamic> d) => LottoWinningNumber(
      round: d['round'] as int,
      numbers: (d['numbers'] as List<dynamic>).cast<int>(),
      bonusNumber: d['bonus'] as int? ?? 0,
      drawDate: d['draw_date'] as String? ?? '',
    );

// ══════════════════════════════════════════════════════════
// RpaEngine — Main Service
// ══════════════════════════════════════════════════════════

class RpaEngine {
  static final RpaEngine instance = RpaEngine._();
  RpaEngine._();

  final _db = Supabase.instance.client;

  // ── Load / Save model state ───────────────────────────

  Future<RpaModelState> loadState() async {
    try {
      final raw = await _db
          .from('rpa_model_state')
          .select()
          .eq('state_key', 'current')
          .maybeSingle();
      if (raw == null) return RpaModelState();
      return RpaModelState.fromJson(raw);
    } catch (_) {
      return RpaModelState();
    }
  }

  Future<void> _saveState(Map<String, dynamic> updates) async {
    try {
      await _db.from('rpa_model_state').upsert({
        'state_key': 'current',
        'updated_at': DateTime.now().toIso8601String(),
        ...updates,
      });
    } catch (_) {}
  }

  // ── Load recent scores ────────────────────────────────

  Future<List<RpaRoundScore>> loadRecentScores(int n) async {
    try {
      final raw = await _db
          .from('rpa_round_scores')
          .select()
          .order('target_round', ascending: false)
          .limit(n);
      return (raw as List<dynamic>)
          .map((j) => RpaRoundScore.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Load correction rules ─────────────────────────────

  Future<List<RpaCorrectionRule>> loadCorrectionRules() async {
    try {
      final raw = await _db
          .from('rpa_correction_rules')
          .select()
          .neq('status', 'retired')
          .order('indicator_id');
      return (raw as List<dynamic>)
          .map((j) => RpaCorrectionRule.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Load pending snapshots ────────────────────────────

  Future<List<RpaPredSnapshot>> loadPendingSnapshots() async {
    try {
      final raw = await _db
          .from('rpa_prediction_snapshots')
          .select()
          .eq('status', 'pending')
          .order('target_round');
      return (raw as List<dynamic>)
          .map((j) => RpaPredSnapshot.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Run Historical Replay ─────────────────────────────
  //   returns number of rounds processed

  Future<int> runHistoricalReplay({
    required List<LottoWinningNumber> allData,
    required int startRound,
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('리플레이 데이터 준비 중...');

    final serialized = allData
        .map((w) => {
              'round': w.round,
              'numbers': w.numbers,
              'bonus': w.bonusNumber,
              'draw_date': w.drawDate,
            })
        .toList();

    onStatus?.call('순차 예측 시뮬레이션 실행 중 (백그라운드)...');

    final rawResults = await compute(_replayIsolate, {
      'data': serialized,
      'start_round': startRound,
    });
    final results = List<Map<String, dynamic>>.from(rawResults);

    if (results.isEmpty) return 0;

    // 센티널(final_flips) 분리
    Map<String, bool> finalFlips = {for (final id in _indicatorIds) id: false};
    if (results.last['target_round'] == -1) {
      final sentinel = results.removeLast();
      final rawFlips = sentinel['final_flips'] as Map<String, dynamic>?;
      if (rawFlips != null) {
        for (final id in _indicatorIds) {
          finalFlips[id] = (rawFlips[id] as bool?) ?? false;
        }
      }
    }

    onStatus?.call('결과 저장 중... (0/${results.length})');

    // Batch save to Supabase in chunks
    const chunkSize = 50;
    int saved = 0;
    int chunksDone = 0;
    final totalChunks = (results.length / chunkSize).ceil();
    for (int i = 0; i < results.length; i += chunkSize) {
      final chunk = results.sublist(
          i, min(i + chunkSize, results.length));

      // 1. Upsert prediction snapshots (batch)
      final snapshots = chunk.map((r) => {
            'target_round': r['target_round'],
            'training_end_round': r['training_end_round'],
            'theory_snapshot': r['theory_snapshot'],
            'correction_snapshot': r['correction_snapshot'],
            'final_prediction': r['final_prediction'],
            'status': 'verified',
            'model_version': kRpaActiveModelVersion,
          }).toList();
      try {
        await _db.from('rpa_prediction_snapshots').upsert(
          snapshots,
          onConflict: await RpaSchema.hasUnifiedSchema()
              ? 'target_round,training_end_round,model_version'
              : 'target_round,training_end_round',
          ignoreDuplicates: true,
        );
      } catch (e) {
        debugPrint('[RPA] replay snapshot 저장 실패: $e');
      }

      // 2. Batch SELECT snapshot IDs for this chunk (1 query instead of N)
      final targetRounds = chunk.map((r) => r['target_round'] as int).toList();
      Map<int, String> snapIdMap = {};
      try {
        final snapRows = await _db
            .from('rpa_prediction_snapshots')
            .select('id, target_round, training_end_round')
            .inFilter('target_round', targetRounds)
            .eq('status', 'verified');
        final trainingByTarget = {
          for (final r in chunk) r['target_round'] as int: r['training_end_round'] as int,
        };
        for (final row in snapRows as List) {
          final t = row['target_round'] as int;
          if (row['training_end_round'] != trainingByTarget[t]) continue;
          snapIdMap[t] = row['id'] as String;
        }
      } catch (_) {}

      // 3. Batch upsert round scores using fetched IDs
      final scoreRows = <Map<String, dynamic>>[];
      for (final r in chunk) {
        final snapId = snapIdMap[r['target_round'] as int];
        if (snapId == null) continue;
        scoreRows.add({
          'snapshot_id': snapId,
          'target_round': r['target_round'],
          'training_end_round': r['training_end_round'],
          'actual_numbers': r['actual_numbers'],
          'actual_bonus': r['actual_bonus'],
          'theory_score': r['theory_score'],
          'correction_score': r['correction_score'],
          'correction_effect': r['correction_effect'],
          'indicator_scores': r['indicator_scores'],
        });
      }
      if (scoreRows.isNotEmpty) {
        try {
          await _db.from('rpa_round_scores').upsert(
            scoreRows,
            onConflict: 'target_round',
            ignoreDuplicates: false,
          );
          saved += scoreRows.length;
        } catch (_) {}
      }

      chunksDone++;
      final pct = (chunksDone * 100 ~/ totalChunks);
      onStatus?.call('저장 중... $saved/${results.length} (${pct}%)  [$chunksDone/$totalChunks 청크]');
    }

    // Compute aggregate scores
    final allScores = results
        .map((r) => (
              theory: (r['theory_score'] as num).toDouble(),
              correction: (r['correction_score'] as num).toDouble(),
            ))
        .toList();

    final theoryAvg = allScores.isEmpty
        ? 0.5
        : allScores.map((s) => s.theory).reduce((a, b) => a + b) /
            allScores.length;
    final corrAvg = allScores.isEmpty
        ? 0.5
        : allScores.map((s) => s.correction).reduce((a, b) => a + b) /
            allScores.length;

    final recent = allScores.length > 20
        ? allScores.sublist(allScores.length - 20)
        : allScores;
    final recent20T = recent.isEmpty
        ? 0.5
        : recent.map((s) => s.theory).reduce((a, b) => a + b) / recent.length;
    final recent20C = recent.isEmpty
        ? 0.5
        : recent.map((s) => s.correction).reduce((a, b) => a + b) /
            recent.length;

    final latestRound =
        results.isNotEmpty ? results.last['target_round'] as int : startRound;

    await _saveState({
      'last_trained_round': latestRound,
      'next_prediction_round': latestRound + 1,
      'replay_completed': true,
      'replay_start_round': startRound,
      'total_predictions': results.length,
      'total_verified': results.length,
      'theory_avg_score': theoryAvg,
      'correction_avg_score': corrAvg,
      'correction_vs_theory': corrAvg - theoryAvg,
      'correction_vs_random': corrAvg - 0.5,
      'recent_20_theory': recent20T,
      'recent_20_correction': recent20C,
      'active_flips': finalFlips,
    });

    onStatus?.call('완료: $saved/${results.length}회차 저장 완료 ✅');
    return saved;
  }

  // ── Generate prediction for a future round ────────────
  // 활성 model_version의 Number Base Snapshot을 생성합니다.
  // 반환: 저장된(또는 기존) snapshot id. 실패 시 RpaPipelineError.
  Future<String> generatePrediction({
    required int targetRound,
    required List<LottoWinningNumber> trainingData,
    String? runId,
    List<RpaHypothesisInput>? hypotheses,
  }) async {
    final sorted = List.of(trainingData)
      ..sort((a, b) => a.round.compareTo(b.round));
    final trainingEnd = sorted.isEmpty ? 0 : sorted.last.round;
    if (trainingEnd >= targetRound) {
      throw RpaPipelineError('미래정보 사용 금지: 학습 $trainingEnd회 ≥ 대상 $targetRound회');
    }
    if (!await RpaSchema.hasUnifiedSchema()) {
      throw RpaPipelineError(RpaSchema.migrationMessage);
    }

    final existing = await _db
        .from('rpa_prediction_snapshots')
        .select('id')
        .eq('target_round', targetRound)
        .eq('training_end_round', trainingEnd)
        .eq('model_version', kRpaActiveModelVersion)
        .maybeSingle();
    if (existing != null) return existing['id'] as String;

    final modelState = await loadState();
    final hyps = hypotheses ?? await loadHypothesisInputs();
    // Gate를 통과한 가설만 Number 점수 보정에 사용 (생명주기 상태만으로는 반영하지 않음)
    final live = hyps.map(rpaEvaluateHypothesis).where((v) => v.live).toList();
    final boost = live.isEmpty
        ? 0.0
        : (live.map((v) => v.h.currentWeight ?? 0).reduce((a, b) => a + b) /
                live.length * 0.3)
            .clamp(0.0, 0.3);

    final base = rpaComputeNumberBase(
      sorted,
      activeFlips: modelState.activeFlips,
      hypothesisBoost: boost,
      activeHypCount: live.length,
      boostHypothesisIds: live.map((v) => v.h.id).toList(),
    );

    final row = await _db.from('rpa_prediction_snapshots').upsert({
      'target_round': targetRound,
      'training_end_round': trainingEnd,
      'theory_snapshot': {'directions': base.theoryDirections, 'rates': base.rates},
      'correction_snapshot': {'flips': base.flips},
      'final_prediction': {'directions': base.finalDirections},
      'status': 'pending',
      'model_version': kRpaActiveModelVersion,
      'run_id': runId,
      'horizon': targetRound - trainingEnd,
      'candidate_numbers': base.candidates,
      'recommended_sets': base.recommendedSets,
      'number_evaluations': base.numberEvaluations,
      'prediction_type': RpaPredictionType.numberBase,
      'gate_status': base.numberEvaluations.length == 45 ? RpaGate.pass : RpaGate.fail,
      'validation_status': RpaValidation.integrityOnly,
      'score_definition': {
        'final_score': kScoreDefinitions['final_score'],
        'set_score': kScoreDefinitions['set_score'],
      },
      'evidence': {
        'training_rounds': sorted.length,
        'live_hypothesis_ids': live.map((v) => v.h.id).toList(),
        'hypothesis_boost': boost,
        'set_rule': '지표 방향 만족 + 점수합 내림차순 + 세트 간 중복 3개 이하 (난수 없음)',
      },
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'target_round,training_end_round,model_version', ignoreDuplicates: true)
        .select('id');
    if ((row as List).isNotEmpty) return row.first['id'] as String;
    // 동시 실행으로 이미 생성된 경우
    final again = await _db
        .from('rpa_prediction_snapshots')
        .select('id')
        .eq('target_round', targetRound)
        .eq('training_end_round', trainingEnd)
        .eq('model_version', kRpaActiveModelVersion)
        .single();
    return again['id'] as String;
  }

  Future<List<RpaHypothesisInput>> loadHypothesisInputs() async {
    final rows = await _db
        .from('rpa_hypotheses_v3')
        .select()
        .order('created_at', ascending: false)
        .limit(300);
    return (rows as List)
        .map((r) => RpaHypothesisInput.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // ── 통합 Prediction Result 생성 (+1~+6) ────────────────
  // 같은 학습 회차·활성 버전의 Number Snapshot에서 가설/제외/자리별/대안/Joint 결과를 파생해 저장합니다.
  Future<int> generateUnifiedResults({
    required int trainingEndRound,
    required List<LottoWinningNumber> allData,
    String? runId,
    void Function(String)? onStatus,
  }) async {
    if (!await RpaSchema.hasUnifiedSchema()) {
      throw RpaPipelineError(RpaSchema.migrationMessage);
    }
    final training = allData.where((d) => d.round <= trainingEndRound).toList()
      ..sort((a, b) => a.round.compareTo(b.round));
    onStatus?.call('Historical Walk-Forward 검증 중 (미래정보 없음)...');
    final wf = await compute(_walkForwardIsolate, {'data': training, 'end': trainingEndRound});
    final hyps = await loadHypothesisInputs();
    final jointGate = await _loadJointGate();

    int saved = 0;
    for (final h in [1, 2, 3, 4, 5, 6]) {
      final target = trainingEndRound + h;
      final snapRaw = await _db
          .from('rpa_prediction_snapshots')
          .select()
          .eq('target_round', target)
          .eq('training_end_round', trainingEndRound)
          .eq('model_version', kRpaActiveModelVersion)
          .maybeSingle();
      if (snapRaw == null) continue;
      final snap = RpaPredSnapshot.fromJson(snapRaw);
      final jc = await JointModelEngine.instance.loadJointContextual(
        target,
        trainingEndRound: trainingEndRound,
        modelVersion: kRpaActiveModelVersion,
      );
      final bundle = rpaBuildUnifiedBundle(RpaUnifiedInputs(
        targetRound: target,
        trainingEndRound: trainingEndRound,
        runId: runId ?? snap.runId,
        sourceSnapshotId: snap.id,
        numberEvaluations: snap.numberEvaluations,
        finalDirections: snap.finalDirections,
        hypotheses: hyps,
        trainingData: training,
        walkForward: wf,
        jointContextual: jc,
        jointGate: jointGate,
      ));
      final rows = bundle.results.map((r) {
        final row = r.toRow();
        if (r.predictionType == RpaPredictionType.numberBase) {
          row['evidence'] = {...r.evidence, 'conflicts': bundle.conflicts};
        }
        return row;
      }).toList();
      await _db.from('rpa_prediction_results').upsert(
        rows,
        onConflict: 'target_round,training_end_round,model_version,prediction_type',
      );
      saved += rows.length;
    }
    return saved;
  }

  Future<Map<String, dynamic>> _loadJointGate() async {
    Map<String, dynamic>? job;
    List<Map<String, dynamic>> storeRows = [];
    try {
      job = await _db.from('rpa_joint_historical_job').select().eq('id', 1).maybeSingle();
    } catch (_) {}
    try {
      final rows = await _db
          .from('rpa_store_predictions')
          .select('candidate_regions,region_hit,spatial_hit,actual_region')
          .not('region_hit', 'is', null)
          .limit(2000);
      storeRows = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {}
    final counts = <String, int>{};
    for (final r in storeRows) {
      final g = r['actual_region'] as String?;
      if (g != null) counts[g] = (counts[g] ?? 0) + 1;
    }
    final total = counts.values.fold(0, (a, b) => a + b);
    return rpaJointGate(
      numberWfImprovement: JointModelEngine.numberGateWfImprovement,
      numberWfN: JointModelEngine.numberGateWfN,
      regionJob: job,
      storeRows: storeRows,
      regionBaseRates: counts.map((k, v) => MapEntry(k, total == 0 ? 0.0 : v / total)),
    );
  }

  // ── 활성 버전 결과 보장 (자동 실행 진입점) ─────────────
  // 최신 학습 완료 회차에 대해 활성 model_version Snapshot/결과가 없으면 생성합니다.
  // 화면 진입·엔진 처리 후 호출되며, 중복 실행은 잠금 + DB 유니크 제약으로 방지합니다.
  Future<RpaEnsureResult> ensureActiveVersionPredictions(
    List<LottoWinningNumber> allData, {
    void Function(String)? onStatus,
  }) async {
    final running = _ensureRunning;
    if (running != null) return running;
    final c = _ensureImpl(allData, onStatus: onStatus);
    _ensureRunning = c;
    try {
      return await c;
    } catch (e) {
      return RpaEnsureResult(RpaEnsureStatus.failed, '$e');
    } finally {
      _ensureRunning = null;
    }
  }

  Future<RpaEnsureResult>? _ensureRunning;

  Future<RpaEnsureResult> _ensureImpl(
    List<LottoWinningNumber> allData, {
    void Function(String)? onStatus,
  }) async {
    if (allData.isEmpty) return const RpaEnsureResult(RpaEnsureStatus.noData, '당첨번호 없음');
    if (!await RpaSchema.hasUnifiedSchema(force: true)) {
      return const RpaEnsureResult(RpaEnsureStatus.migrationRequired, RpaSchema.migrationMessage);
    }
    final trainingEnd = await resolveTrainingEndRound(allData);
    if (trainingEnd <= 0) {
      return const RpaEnsureResult(RpaEnsureStatus.noData, '학습 완료 회차 없음');
    }

    final snaps = await _db
        .from('rpa_prediction_snapshots')
        .select('target_round')
        .eq('training_end_round', trainingEnd)
        .eq('model_version', kRpaActiveModelVersion);
    final results = await _db
        .from('rpa_prediction_results')
        .select('target_round')
        .eq('training_end_round', trainingEnd)
        .eq('model_version', kRpaActiveModelVersion);
    final snapCount = (snaps as List).length;
    final resultCount = (results as List).length;
    if (snapCount >= 6 && resultCount >= 6 * RpaPredictionType.all.length) {
      return RpaEnsureResult(RpaEnsureStatus.upToDate,
          '$trainingEnd회 기준 v$kRpaActiveModelVersion 결과 준비됨',
          trainingEndRound: trainingEnd);
    }

    final runId = '${trainingEnd}_v${kRpaActiveModelVersion}_${DateTime.now().millisecondsSinceEpoch}';
    final training = allData.where((d) => d.round <= trainingEnd).toList();
    final hyps = await loadHypothesisInputs();
    onStatus?.call('v$kRpaActiveModelVersion Number Snapshot 생성 중...');
    for (final h in [1, 2, 3, 4, 5, 6]) {
      await generatePrediction(
        targetRound: trainingEnd + h,
        trainingData: training,
        runId: runId,
        hypotheses: hyps,
      );
    }
    onStatus?.call('Joint Contextual 생성 중...');
    for (final h in [1, 2, 3, 4, 5, 6]) {
      await JointModelEngine.instance.generateJointContextualFromDB(
        targetRound: trainingEnd + h,
        trainingEndRound: trainingEnd,
      );
    }
    final saved = await generateUnifiedResults(
      trainingEndRound: trainingEnd,
      allData: allData,
      runId: runId,
      onStatus: onStatus,
    );
    return RpaEnsureResult(RpaEnsureStatus.generated,
        '$trainingEnd회 기준 v$kRpaActiveModelVersion Snapshot/결과 $saved건 생성',
        trainingEndRound: trainingEnd);
  }

  /// 예측 기준 학습 회차: 엔진 처리가 끝난 최신 실제 회차
  /// (판매점 크롤링 대기 중인 회차는 학습 기준으로 쓰지 않음)
  Future<int> resolveTrainingEndRound(List<LottoWinningNumber> allData) async {
    if (allData.isEmpty) return 0;
    final latest = allData.map((d) => d.round).reduce(max);
    final gate = await _loadRoundGate(latest);
    if (gate?.isCompleted == true) return latest;
    final state = await loadState();
    return min(latest, state.lastTrainedRound);
  }

  /// 화면용: 활성 버전 Snapshot(+horizon)과 통합 결과 로드
  Future<RpaActiveView> loadActiveView(int trainingEndRound) async {
    final view = RpaActiveView(trainingEndRound: trainingEndRound);
    view.schemaReady = await RpaSchema.hasUnifiedSchema(force: true);
    final snapRows = await _db
        .from('rpa_prediction_snapshots')
        .select()
        .eq('training_end_round', trainingEndRound)
        .gte('target_round', trainingEndRound + 1)
        .lte('target_round', trainingEndRound + 6)
        .order('created_at', ascending: false);
    for (final raw in snapRows as List) {
      final snap = RpaPredSnapshot.fromJson(Map<String, dynamic>.from(raw as Map));
      final h = snap.targetRound - trainingEndRound;
      if (snap.modelVersion == kRpaActiveModelVersion) {
        view.activeSnapshots.putIfAbsent(h, () => snap);
      } else {
        view.legacySnapshots.putIfAbsent(h, () => snap);
      }
    }
    if (view.schemaReady) {
      final resRows = await _db
          .from('rpa_prediction_results')
          .select()
          .eq('training_end_round', trainingEndRound)
          .eq('model_version', kRpaActiveModelVersion);
      for (final raw in resRows as List) {
        final r = RpaPredictionResult.fromRow(Map<String, dynamic>.from(raw as Map));
        view.results
            .putIfAbsent(r.targetRound - trainingEndRound, () => {})[r.predictionType] = r;
      }
    }
    return view;
  }

  // ── Round gate helpers ────────────────────────────────
  Future<void> _upsertRoundGate(int round, Map<String, dynamic> fields) async {
    try {
      await _db.from('rpa_round_gate').upsert(
        {'round': round, ...fields, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        onConflict: 'round',
      );
    } catch (_) {}
  }

  Future<RpaRoundGate?> _loadRoundGate(int round) async {
    try {
      final raw = await _db.from('rpa_round_gate').select().eq('round', round).maybeSingle();
      if (raw == null) return null;
      return RpaRoundGate.fromJson(raw as Map<String, dynamic>);
    } catch (_) { return null; }
  }

  // 해당 sourceRound를 기준으로 +1 Number Prediction이 실제 존재하는지 확인
  Future<bool> _hasActualPredictions(int sourceRound) async {
    try {
      final rows = await _db
          .from('rpa_prediction_snapshots')
          .select('id')
          .eq('training_end_round', sourceRound)
          .eq('target_round', sourceRound + 1)
          .eq('model_version', kRpaActiveModelVersion)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) { return false; }
  }

  // completed인데 실제 산출물이 없는 회차 감지 및 재처리 (INCOMPLETE 복구)
  Future<int> checkAndRepairIncompleteRounds(List<LottoWinningNumber> allData) async {
    int repaired = 0;
    try {
      // completed 상태 게이트 중 최신 N개 검사
      final rows = await _db
          .from('rpa_round_gate')
          .select()
          .eq('engine_status', 'completed')
          .eq('has_winning_numbers', true)
          .eq('has_store_data', true)
          .order('round', ascending: false)
          .limit(5);
      final gates = (rows as List)
          .map((r) => RpaRoundGate.fromJson(r as Map<String, dynamic>))
          .toList();
      for (final gate in gates) {
        final hasOutput = await _hasActualPredictions(gate.round);
        if (!hasOutput) {
          // INCOMPLETE: reset → 재처리
          await _upsertRoundGate(gate.round, {'engine_status': 'ready'});
          final roundData = allData.where((d) => d.round == gate.round).firstOrNull;
          if (roundData == null) continue;
          final result = await _executeEngine(roundData, allData);
          if (result.success) {
            await _upsertRoundGate(gate.round, {
              'engine_status': 'completed',
              'processed_at': DateTime.now().toUtc().toIso8601String(),
              'error_msg': null,
            });
            repaired++;
          }
        }
      }
    } catch (_) {}
    return repaired;
  }

  // 특정 회차를 강제 재처리 (관리자 수동 복구용)
  Future<RpaProcessResult> repairRound({
    required LottoWinningNumber targetRound,
    required List<LottoWinningNumber> allData,
  }) async {
    await _upsertRoundGate(targetRound.round, {
      'engine_status': 'ready',
      'has_winning_numbers': true,
      'has_store_data': true,
      'crawl_status': 'success',
    });
    final result = await _executeEngine(targetRound, allData);
    if (result.success) {
      await _upsertRoundGate(targetRound.round, {
        'engine_status': 'completed',
        'processed_at': DateTime.now().toUtc().toIso8601String(),
        'error_msg': null,
      });
    } else {
      await _upsertRoundGate(targetRound.round, {
        'engine_status': 'failed',
        'error_msg': result.error,
      });
    }
    return result;
  }

  // 최근 N회차 중 당첨번호+판매점이 존재하지만 gate row가 없는 회차를 자동 생성
  // 최근 N회차 중 gate row가 누락된 실제 완료 회차를 자동 생성
  // allData = lotto_winning_numbers 테이블 (실제 추첨 완료 회차만 포함)
  // → 미래 예측 대상 회차는 lotto_winning_numbers에 없으므로 절대 gate 생성 안 됨
  Future<void> syncMissingGates(List<LottoWinningNumber> allData) async {
    if (allData.isEmpty) return;
    try {
      // 최신 10회차만 체크 (모두 실제 추첨 완료된 회차)
      final sorted = List.of(allData)..sort((a, b) => b.round.compareTo(a.round));
      final recentRounds = sorted.take(10).map((d) => d.round).toList();

      // 기존 gate row 목록
      final existingRows = await _db
          .from('rpa_round_gate')
          .select('round, engine_status')
          .inFilter('round', recentRounds);
      final existingMap = {
        for (final r in existingRows as List)
          r['round'] as int: r['engine_status'] as String
      };

      for (final round in recentRounds) {
        // gate 가 있어도 판매점 대기 상태면 다시 확인한다 — 크롤링 전에 생성된 gate 가
        // 크롤링 완료 후에도 waiting_store 로 고착되던 문제 (판매점은 수집됐는데 엔진이 못 읽음)
        final st = existingMap[round];
        if (st != null && st != 'waiting_store' && st != 'waiting_number') continue;
        // 이 round는 lotto_winning_numbers에서 온 실제 추첨 완료 회차
        // 예측 데이터(rpa_prediction_snapshots)와 무관
        try {
          final storeCheck = await _db
              .from('winning_history')
              .select('id')
              .eq('round', round)
              .eq('lottery_type', 'lotto')
              .eq('prize_tier', 'first')
              .limit(1);
          if ((storeCheck as List).isNotEmpty) {
            // 실제 당첨번호 + 실제 판매점 모두 존재 → 학습 가능 → ready
            await _upsertRoundGate(round, {
              'has_winning_numbers': true,
              'has_store_data': true,
              'crawl_status': 'success',
              'engine_status': 'ready',
            });
          } else {
            // 실제 당첨번호는 있지만 판매점 미수집 → waiting_store
            await _upsertRoundGate(round, {
              'has_winning_numbers': true,
              'has_store_data': false,
              'crawl_status': 'pending',
              'engine_status': 'waiting_store',
            });
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  // 판매점 크롤링이 완료된 회차 중 아직 엔진 미처리인 것들 확인 후 처리
  // round ASC 순서로 처리하여 오래된 회차부터 catch-up
  Future<void> checkAndProcessReadyRounds(List<LottoWinningNumber> allData) async {
    // processing 고착 복구: 30분 넘게 processing인 게이트는 ready로 되돌려 재처리
    try {
      final staleBefore = DateTime.now().toUtc().subtract(const Duration(minutes: 30)).toIso8601String();
      await _db.from('rpa_round_gate')
          .update({'engine_status': 'ready', 'error_msg': 'processing 고착 자동 복구 → 재처리'})
          .eq('engine_status', 'processing')
          .lt('updated_at', staleBefore);
    } catch (_) {}
    try {
      final rows = await _db
          .from('rpa_round_gate')
          .select()
          .inFilter('engine_status', ['waiting_store', 'ready'])
          .eq('has_winning_numbers', true)
          .eq('has_store_data', true)
          .eq('crawl_status', 'success')
          .order('round', ascending: true); // catch-up: 오래된 회차부터 순서대로
      final gates = (rows as List)
          .map((r) => RpaRoundGate.fromJson(r as Map<String, dynamic>))
          .toList();
      for (final gate in gates) {
        final roundData = allData.where((d) => d.round == gate.round).firstOrNull;
        if (roundData == null) continue;
        // processing 상태로 변경 후 실행
        await _upsertRoundGate(gate.round, {'engine_status': 'processing'});
        RpaProcessResult? result;
        try {
          result = await _executeEngine(roundData, allData);
        } catch (e) {
          // 예외 발생 시 'processing' 고착 방지 — 반드시 'failed' 로 업데이트
          await _upsertRoundGate(gate.round, {
            'engine_status': 'failed',
            'error_msg': 'Exception: $e',
          });
          continue;
        }
        // 완료/실패 상태 기록
        if (result.success) {
          await _upsertRoundGate(gate.round, {
            'engine_status': 'completed',
            'processed_at': DateTime.now().toUtc().toIso8601String(),
            'error_msg': null,
          });
        } else {
          await _upsertRoundGate(gate.round, {
            'engine_status': 'failed',
            'error_msg': result.error,
          });
        }
      }
    } catch (_) {}
  }

  // ── Process new round (auto-trigger from admin) ───────

  Future<RpaProcessResult> processNewRound({
    required LottoWinningNumber newRound,
    required List<LottoWinningNumber> allData,
  }) async {
    // ── 게이트 체크 ───────────────────────────────────────
    // 당첨번호 등록 완료 기록
    await _upsertRoundGate(newRound.round, {'has_winning_numbers': true});

    // 판매점 데이터 확인: rpa_round_gate에 crawl_status='success' 이거나
    // winning_history에 해당 회차 1등 당첨판매점 데이터가 있는지 확인
    final gate = await _loadRoundGate(newRound.round);
    bool storeReady = gate?.crawlStatus == 'success' && gate?.hasStoreData == true;

    // 게이트에 크롤 정보가 없으면 winning_history에서 직접 확인
    if (!storeReady) {
      try {
        final storeCheck = await _db
            .from('winning_history')
            .select('id')
            .eq('round', newRound.round)
            .eq('lottery_type', 'lotto')
            .eq('prize_tier', 'first')
            .limit(1);
        if ((storeCheck as List).isNotEmpty) {
          storeReady = true;
          await _upsertRoundGate(newRound.round, {
            'has_store_data': true,
            'crawl_status': 'success',
          });
        }
      } catch (_) {}
    }

    if (!storeReady) {
      // 판매점 크롤링 대기 상태로 표시 후 조기 반환
      await _upsertRoundGate(newRound.round, {'engine_status': 'waiting_store'});
      return RpaProcessResult(
        success: false,
        waitingForStore: true,
        verifiedRound: newRound.round,
        theoryScore: 0.5,
        correctionScore: 0.5,
        predictionsSaved: 0,
      );
    }

    // 이미 완료된 회차 재실행 방지 — 단, 실제 Prediction이 없으면 INCOMPLETE로 판단
    if (gate?.isCompleted == true) {
      final hasOutput = await _hasActualPredictions(newRound.round);
      if (hasOutput) {
        // 실제 완료 — 재실행 불필요
        return RpaProcessResult(
          success: true,
          verifiedRound: newRound.round,
          theoryScore: 0.5,
          correctionScore: 0.5,
          predictionsSaved: 0,
        );
      }
      // INCOMPLETE: completed 표시지만 실제 산출물 없음 (v6 백필 등) → 재처리
      await _upsertRoundGate(newRound.round, {'engine_status': 'ready'});
    }

    // processing 상태로 변경
    await _upsertRoundGate(newRound.round, {'engine_status': 'processing'});

    final result = await _executeEngine(newRound, allData);

    // 완료/실패 상태 기록
    if (result.success) {
      await _upsertRoundGate(newRound.round, {
        'engine_status': 'completed',
        'processed_at': DateTime.now().toUtc().toIso8601String(),
        'error_msg': null,
      });
    } else {
      await _upsertRoundGate(newRound.round, {
        'engine_status': 'failed',
        'error_msg': result.error,
      });
    }
    return result;
  }

  // ── 실제 엔진 실행 (게이트 통과 후) ────────────────────
  Future<RpaProcessResult> _executeEngine(
    LottoWinningNumber newRound,
    List<LottoWinningNumber> allData,
  ) async {
    int predSaved = 0;
    double theoryScore = 0.5;
    double corrScore = 0.5;
    final runId = '${newRound.round}_${DateTime.now().millisecondsSinceEpoch}';

    // 1. 이 회차를 대상으로 한 모든 pending Snapshot 채점
    //    (+1~+6 예측과 버전별 Snapshot이 공존하므로 여러 행이 정상)
    try {
      final snapRows = await _db
          .from('rpa_prediction_snapshots')
          .select()
          .eq('target_round', newRound.round)
          .eq('status', 'pending')
          .order('training_end_round', ascending: false);
      final snaps = (snapRows as List)
          .map((r) => RpaPredSnapshot.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      // 대표 채점: 가장 최근 학습(=+1) + 활성 버전 우선
      snaps.sort((a, b) {
        final t = b.trainingEndRound.compareTo(a.trainingEndRound);
        if (t != 0) return t;
        final av = a.modelVersion == kRpaActiveModelVersion ? 0 : 1;
        final bv = b.modelVersion == kRpaActiveModelVersion ? 0 : 1;
        return av.compareTo(bv);
      });

      for (int i = 0; i < snaps.length; i++) {
        final snap = snaps[i];
        final iScores = _scoreDirections(snap.finalDirections, newRound);
        final tScore = _meanScore(_scoreDirections(snap.theoryDirections, newRound));
        final cScore = _meanScore(iScores);
        final effect = cScore - tScore;
        final actual = newRound.numbers.toSet();
        final setHits = snap.recommendedSets
            .map((s) => s.where(actual.contains).length)
            .toList();

        if (i == 0) {
          theoryScore = tScore;
          corrScore = cScore;
          try {
            await _db.from('rpa_round_scores').upsert({
              'snapshot_id': snap.id,
              'target_round': newRound.round,
              'training_end_round': snap.trainingEndRound,
              'actual_numbers': newRound.numbers,
              'actual_bonus': newRound.bonusNumber,
              'theory_score': tScore,
              'correction_score': cScore,
              'correction_effect': effect,
              'indicator_scores': iScores,
            }, onConflict: 'target_round', ignoreDuplicates: true);
          } catch (e) {
            debugPrint('[RPA] round score 저장 실패: $e');
          }
          // 보정 규칙은 대표 Snapshot 기준으로 한 번만 갱신
          await _updateCorrectionRules(snap, effect, newRound.round);
        }

        await _db
            .from('rpa_prediction_snapshots')
            .update({'status': 'verified'})
            .eq('id', snap.id);

        // 통합 결과에 실제 적중 기록 (엔진 점수와 분리된 '실제 당첨 적중')
        if (await RpaSchema.hasUnifiedSchema()) {
          try {
            await _db
                .from('rpa_prediction_results')
                .update({
                  'verification': {
                    'actual_numbers': newRound.numbers,
                    'base_set_hits': setHits,
                    'direction_score': cScore,
                    'verified_at': DateTime.now().toUtc().toIso8601String(),
                  },
                })
                .eq('target_round', newRound.round)
                .eq('training_end_round', snap.trainingEndRound)
                .eq('model_version', snap.modelVersion);
          } catch (e) {
            debugPrint('[RPA] result verification 저장 실패: $e');
          }
        }
      }
    } catch (e) {
      return RpaProcessResult(
        success: false,
        verifiedRound: newRound.round,
        theoryScore: theoryScore,
        correctionScore: corrScore,
        predictionsSaved: 0,
        error: '이전 예측 채점 실패: $e',
      );
    }

    // 5. Full Store Model training (spatial analysis)
    List<StoreWinRecord> storeHistory = [];
    try {
      storeHistory = await StoreModelEngine.instance.loadWinHistory();
      await StoreModelEngine.instance
          .runAnalysis(storeHistory, newRound.round)
          .drain<void>();
    } catch (_) {}

    // 6. Full Joint Model training (number × region analysis)
    try {
      await JointModelEngine.instance.runAnalysis(
        allNumbers: allData,
        storeHistory: storeHistory,
        currentRound: newRound.round,
      ).drain<void>();
    } catch (_) {}

    // 7. Full Hypothesis Meeting (pattern discovery + lifecycle)
    // allData를 newRound.round 이전으로 필터링 → 미래 데이터 누수 방지
    final trainingOnly = allData.where((d) => d.round <= newRound.round).toList();
    try {
      await HypothesisEngine.instance
          .runMeeting(trainingOnly, newRound.round)
          .drain<void>();
    } catch (_) {}

    // 7b. Prediction Error → 추가 연구 트리거
    // corrScore < 0.35 이면 큰 예측 실패 → 추가 회의 1회 더 실행
    if (corrScore < 0.35 && trainingOnly.length >= 50) {
      try {
        await HypothesisEngine.instance
            .runMeeting(trainingOnly, newRound.round)
            .drain<void>();
      } catch (_) {}
    }

    // 8. Verify active hypotheses against new round result
    try {
      final hyps = await HypothesisEngine.instance.loadHypotheses();
      await HypothesisEngine.instance.verifyAgainstNewRound(newRound, hyps);
    } catch (_) {}

    // 9. Verify store prediction + generate new store predictions +1~+6
    try {
      final actualStore = storeHistory
          .where((r) => r.round == newRound.round)
          .firstOrNull;
      if (actualStore != null) {
        await StoreModelEngine.instance.verifyStorePrediction(actualStore);
      }
      for (final offset in [1, 2, 3, 4, 5, 6]) {
        await StoreModelEngine.instance.generateStorePrediction(
          targetRound: newRound.round + offset,
          history: storeHistory,
          trainingEndRound: newRound.round,
        );
      }
    } catch (_) {}

    // 10. Verify joint prediction + generate new joint predictions +1~+6
    try {
      final actualStore = storeHistory
          .where((r) => r.round == newRound.round)
          .firstOrNull;
      await JointModelEngine.instance.verifyJointPrediction(
        targetRound: newRound.round,
        actualSido: actualStore?.sido ?? '',
        actualNumbers: newRound.numbers,
      );
      for (final offset in [1, 2, 3, 4, 5, 6]) {
        await JointModelEngine.instance.generateJointPrediction(
          targetRound: newRound.round + offset,
          trainingEndRound: newRound.round,
          allNumbers: allData,
          storeHistory: storeHistory,
        );
      }
    } catch (_) {}

    // 10b. Walk-Forward 증분 검증 (fire-and-forget)
    JointHistoricalEngine.instance.runIncremental(
      newRound: newRound.round,
      allNums: allData,
      storeHistory: storeHistory,
    ).ignore();

    // 11. 활성 버전 Number Snapshot +1~+6 → Joint Contextual → 통합 결과 (순서 보장)
    String? pipelineError;
    final trainingData = allData.where((d) => d.round <= newRound.round).toList();
    try {
      final hyps = await loadHypothesisInputs();
      for (final offset in [1, 2, 3, 4, 5, 6]) {
        await generatePrediction(
          targetRound: newRound.round + offset,
          trainingData: trainingData,
          runId: runId,
          hypotheses: hyps,
        );
        predSaved++;
      }
      for (final offset in [1, 2, 3, 4, 5, 6]) {
        await JointModelEngine.instance.generateJointContextualFromDB(
          targetRound: newRound.round + offset,
          trainingEndRound: newRound.round,
        );
      }
      await generateUnifiedResults(
        trainingEndRound: newRound.round,
        allData: allData,
        runId: runId,
      );
    } catch (e) {
      pipelineError = 'Snapshot/통합 결과 생성 실패: $e';
      debugPrint('[RPA] $pipelineError');
    }

    // 12. MND 명당 연구소 증분 분석 (Round Gate 완료 후 자동 실행)
    try {
      await MndEngine.instance.runIncrementalForRound(
        newRound: newRound,
        storeHistory: storeHistory,
      );
    } catch (e) {
      debugPrint('[MND] 증분 분석 오류: $e');
    }

    // 13. Refresh model state
    await _refreshModelState(newRound.round);

    // 13. MC 큐 처리 (새 가설 Random Control 검증 등) — 비차단
    MonteCarloEngine.instance.processQueueBatch(maxJobs: 5).ignore();

    // 산출물 없이 completed 처리하지 않음 → 다음 실행에서 자동 재처리
    return RpaProcessResult(
      success: pipelineError == null && predSaved == 6,
      verifiedRound: newRound.round,
      theoryScore: theoryScore,
      correctionScore: corrScore,
      predictionsSaved: predSaved,
      error: pipelineError,
    );
  }

  Future<void> _updateCorrectionRules(
    RpaPredSnapshot snap,
    double correctionEffect,
    int verifiedRound,
  ) async {
    final flips =
        (snap.correctionSnapshot['flips'] as Map<String, dynamic>?) ?? {};

    for (final id in _indicatorIds) {
      final wasFlipped = flips[id] as bool? ?? false;
      if (!wasFlipped) continue;

      final improved = correctionEffect > 0.02;
      final worsened = correctionEffect < -0.02;

      try {
        // Upsert correction rule for this indicator
        final existing = await _db
            .from('rpa_correction_rules')
            .select()
            .eq('indicator_id', id)
            .eq('rule_type', 'direction_flip')
            .maybeSingle();

        if (existing == null) {
          await _db.from('rpa_correction_rules').insert({
            'indicator_id': id,
            'rule_type': 'direction_flip',
            'trigger_condition': 'low_accuracy',
            'direction_override': 'flip',
            'use_count': 1,
            'improve_count': improved ? 1 : 0,
            'worsen_count': worsened ? 1 : 0,
            'avg_improvement': correctionEffect,
            'weight': 1.0,
            'status': 'active',
            'last_applied_round': verifiedRound,
          });
        } else {
          final useCount = (existing['use_count'] as int? ?? 0) + 1;
          final impCnt = (existing['improve_count'] as int? ?? 0) +
              (improved ? 1 : 0);
          final worCnt = (existing['worsen_count'] as int? ?? 0) +
              (worsened ? 1 : 0);
          final prevAvg =
              (existing['avg_improvement'] as num?)?.toDouble() ?? 0;
          final newAvg =
              (prevAvg * (useCount - 1) + correctionEffect) / useCount;
          final accuracy = impCnt / useCount;

          // Retire harmful rules
          String status = 'active';
          if (useCount >= 10 && accuracy < 0.3) status = 'deprecated';
          if (useCount >= 20 && accuracy < 0.25) status = 'retired';

          await _db
              .from('rpa_correction_rules')
              .update({
                'use_count': useCount,
                'improve_count': impCnt,
                'worsen_count': worCnt,
                'avg_improvement': newAvg,
                'weight': accuracy >= 0.5 ? 1.0 : (accuracy - 0.25) * 4,
                'status': status,
                'last_applied_round': verifiedRound,
              })
              .eq('id', existing['id']);
        }
      } catch (_) {}
    }
  }

  Future<void> _refreshModelState(int latestRound) async {
    try {
      final scores = await loadRecentScores(100);
      if (scores.isEmpty) return;

      final theoryAvg =
          scores.map((s) => s.theoryScore).reduce((a, b) => a + b) /
              scores.length;
      final corrAvg =
          scores.map((s) => s.correctionScore).reduce((a, b) => a + b) /
              scores.length;

      final recent = scores.take(20).toList();
      final r20T = recent.isEmpty
          ? 0.5
          : recent.map((s) => s.theoryScore).reduce((a, b) => a + b) /
              recent.length;
      final r20C = recent.isEmpty
          ? 0.5
          : recent.map((s) => s.correctionScore).reduce((a, b) => a + b) /
              recent.length;

      await _saveState({
        'last_trained_round': latestRound,
        'next_prediction_round': latestRound + 1,
        'total_verified': scores.length,
        'theory_avg_score': theoryAvg,
        'correction_avg_score': corrAvg,
        'correction_vs_theory': corrAvg - theoryAvg,
        'correction_vs_random': corrAvg - 0.5,
        'recent_20_theory': r20T,
        'recent_20_correction': r20C,
      });
    } catch (_) {}
  }
}
