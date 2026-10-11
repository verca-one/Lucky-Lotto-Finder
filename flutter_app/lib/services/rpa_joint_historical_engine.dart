// Joint Model Historical Walk-Forward Validation Engine
//
// 원칙: 500회를 예측할 때는 1~499 데이터만 사용한다.
// 현재 학습된 가설/패턴을 과거 회차 예측에 사용하지 않는다.
//
// 알고리즘:
// - minTrain(100)회 이후부터 마지막 회차까지 순서대로 순회
// - 회차 T 예측 시 rounds 1..T-1 데이터만 사용
// - NR 패턴은 retrainFreq(100)마다 재계산 (메모리 내, DB 저장 안 함)
// - 결과를 rpa_joint_historical_results에 upsert

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/lotto_winning_number.dart';
import 'rpa_store_engine.dart';

// ══════════════════════════════════════════════════════════════
// Walk-Forward 요약 모델
// ══════════════════════════════════════════════════════════════

class WalkForwardSummary {
  final String status; // idle / running / completed / failed
  final int totalRounds;
  final int processedRounds;
  final int nrHits;
  final int storeHits;
  final int jointHits;
  final double? nrAccuracy;
  final double? storeAccuracy;
  final double? jointAccuracy;
  final double? synergy;
  final DateTime? completedAt;
  final String? error;

  const WalkForwardSummary({
    required this.status,
    this.totalRounds = 0,
    this.processedRounds = 0,
    this.nrHits = 0,
    this.storeHits = 0,
    this.jointHits = 0,
    this.nrAccuracy,
    this.storeAccuracy,
    this.jointAccuracy,
    this.synergy,
    this.completedAt,
    this.error,
  });

  factory WalkForwardSummary.fromJson(Map<String, dynamic> j) =>
      WalkForwardSummary(
        status: j['status'] as String? ?? 'idle',
        totalRounds: (j['total_rounds'] as num? ?? 0).toInt(),
        processedRounds: (j['processed_rounds'] as num? ?? 0).toInt(),
        nrHits: (j['nr_hits'] as num? ?? 0).toInt(),
        storeHits: (j['store_hits'] as num? ?? 0).toInt(),
        jointHits: (j['joint_hits'] as num? ?? 0).toInt(),
        nrAccuracy: j['nr_accuracy'] != null
            ? (j['nr_accuracy'] as num).toDouble()
            : null,
        storeAccuracy: j['store_accuracy'] != null
            ? (j['store_accuracy'] as num).toDouble()
            : null,
        jointAccuracy: j['joint_accuracy'] != null
            ? (j['joint_accuracy'] as num).toDouble()
            : null,
        synergy: j['synergy'] != null
            ? (j['synergy'] as num).toDouble()
            : null,
        completedAt: j['completed_at'] != null
            ? DateTime.tryParse(j['completed_at'] as String)
            : null,
        error: j['error_message'] as String?,
      );

  bool get isCompleted => status == 'completed';
  bool get isRunning => status == 'running';
  bool get hasFailed => status == 'failed';
  bool get needsRun => status == 'idle' || status == 'failed';
}

// ══════════════════════════════════════════════════════════════
// Isolate 최상위 함수들 (순수 계산, DB 접근 없음)
// ══════════════════════════════════════════════════════════════

// 번호 특징 키 계산 (NumberFeatures.key 와 동일 로직)
String _computeFeatureKey(Map<String, dynamic> numMap) {
  final raw = numMap['numbers'];
  if (raw == null) return 'low|mid|mid|false';
  final numbers =
      (raw as List<dynamic>).map((e) => (e as num).toInt()).toList();
  if (numbers.isEmpty) return 'low|mid|mid|false';

  final sum = numbers.reduce((a, b) => a + b);
  final oddCount = numbers.where((n) => n % 2 == 1).length;
  final sorted = [...numbers]..sort();
  final range = sorted.last - sorted.first;

  bool consecutive = false;
  for (int i = 0; i < sorted.length - 1; i++) {
    if (sorted[i + 1] - sorted[i] == 1) {
      consecutive = true;
      break;
    }
  }

  final sumBand = sum < 130 ? 'low' : sum <= 160 ? 'mid' : 'high';
  final oddBand = oddCount <= 2 ? 'low' : oddCount == 3 ? 'mid' : 'high';
  final rangeBand = range < 25 ? 'narrow' : range <= 35 ? 'mid' : 'wide';

  return '$sumBand|$oddBand|$rangeBand|$consecutive';
}

// 메모리 내 NR 패턴 계산 (DB 저장 없음)
// Returns: featureKey → [{sido, lift, count}] sorted by lift desc
Map<String, List<Map<String, dynamic>>> _computePatternsInMemory(
  List<Map<String, dynamic>> trainNums,
  Map<int, String> storeByRound,
) {
  final comboCounts = <String, int>{};
  final featureTotals = <String, int>{};
  final sidoTotal = <String, int>{};
  int total = 0;

  for (final numMap in trainNums) {
    final round = (numMap['round'] as num).toInt();
    final sido = storeByRound[round];
    if (sido == null || sido.isEmpty) continue;

    final feat = _computeFeatureKey(numMap);
    featureTotals[feat] = (featureTotals[feat] ?? 0) + 1;
    sidoTotal[sido] = (sidoTotal[sido] ?? 0) + 1;
    comboCounts['$feat|$sido'] = (comboCounts['$feat|$sido'] ?? 0) + 1;
    total++;
  }

  if (total == 0) return {};

  const minSamples = 5;
  final result = <String, List<Map<String, dynamic>>>{};

  for (final entry in comboCounts.entries) {
    // comboKey = sumBand|oddBand|rangeBand|hasConsecutive|sido
    // feat = parts[0..3], sido = parts[4..] (Korean names never contain |)
    final parts = entry.key.split('|');
    if (parts.length < 5) continue;
    final feat = '${parts[0]}|${parts[1]}|${parts[2]}|${parts[3]}';
    final sido = parts.sublist(4).join('|');
    if (sido.isEmpty) continue;

    final featTotal = featureTotals[feat] ?? 0;
    if (featTotal < minSamples) continue;

    final count = entry.value;
    final rate = count / featTotal;
    final baseline = (sidoTotal[sido] ?? 0) / total;
    if (baseline <= 0) continue;
    final lift = rate / baseline;
    if (lift < 1.2) continue;

    result.putIfAbsent(feat, () => []).add({
      'sido': sido,
      'lift': lift,
      'count': count,
    });
  }

  for (final list in result.values) {
    list.sort(
        (a, b) => (b['lift'] as double).compareTo(a['lift'] as double));
  }
  return result;
}

// Walk-Forward 메인 계산 (Isolate에서 실행)
Map<String, dynamic> _runWalkForwardIsolate(Map<String, dynamic> params) {
  final numMaps = List<Map<String, dynamic>>.from(
      (params['nums'] as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)));
  final storeMaps = params['stores'] as List<dynamic>;
  final minTrain = params['minTrain'] as int;
  final retrainFreq = params['retrainFreq'] as int;

  // Round 순으로 정렬
  numMaps.sort((a, b) =>
      (a['round'] as int).compareTo(b['round'] as int));

  // storeByRound 맵 구축 (round → sido 시/도)
  final storeByRound = <int, String>{};
  for (final s in storeMaps) {
    final sm = s as Map;
    final round = (sm['round'] as num).toInt();
    final region = (sm['region'] as String? ?? '').trim();
    if (region.isNotEmpty) {
      storeByRound[round] = region.split(' ').first;
    }
  }

  final results = <Map<String, dynamic>>[];
  Map<String, List<Map<String, dynamic>>>? patterns;

  for (int i = minTrain; i < numMaps.length; i++) {
    final targetNum = numMaps[i];
    final targetRound = (targetNum['round'] as num).toInt();

    // retrainFreq마다 (또는 최초) NR 패턴 재계산
    if (patterns == null || i % retrainFreq == 0) {
      patterns = _computePatternsInMemory(
          numMaps.sublist(0, i), storeByRound);
    }

    // 직전 회차 번호로 특징 계산 → 이번 회차 지역 예측
    final prevNum = numMaps[i - 1];
    final feat = _computeFeatureKey(prevNum);

    // NR 후보 지역: lift > 1.2 패턴 상위 3개
    final matchingPats = patterns[feat] ?? [];
    final nrCandidates = matchingPats
        .take(3)
        .map((p) => p['sido'] as String)
        .toList();

    // Store 후보 지역: 직전 30회차 1등 지역 빈도 상위 3개
    final recentSidos = <String>[];
    for (int j = i - 1; j >= 0 && recentSidos.length < 30; j--) {
      final r = (numMaps[j]['round'] as num).toInt();
      final sido = storeByRound[r];
      if (sido != null && sido.isNotEmpty) recentSidos.add(sido);
    }
    final sidoCounts = <String, int>{};
    for (final s in recentSidos) {
      sidoCounts[s] = (sidoCounts[s] ?? 0) + 1;
    }
    final storeSorted = sidoCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final storeCandidates =
        storeSorted.take(3).map((e) => e.key).toList();

    // Joint: NR + Store 합집합
    final jointSet = <String>{...nrCandidates, ...storeCandidates};

    // 실제 결과
    final actualSido = storeByRound[targetRound] ?? '';
    final hasActual = actualSido.isNotEmpty;

    results.add({
      'target_round': targetRound,
      'training_end_round': targetRound - 1,
      'nr_candidate_regions': nrCandidates,
      'store_candidate_regions': storeCandidates,
      'joint_candidate_regions': jointSet.toList(),
      'actual_region': actualSido,
      'nr_hit': hasActual && nrCandidates.contains(actualSido),
      'store_hit': hasActual && storeCandidates.contains(actualSido),
      'joint_hit': hasActual && jointSet.contains(actualSido),
    });
  }

  // 실제 지역 데이터가 있는 회차만으로 정확도 계산
  final withRegion =
      results.where((r) => (r['actual_region'] as String).isNotEmpty).toList();
  final total = withRegion.length;
  final nrHits =
      withRegion.where((r) => r['nr_hit'] as bool).length;
  final storeHits =
      withRegion.where((r) => r['store_hit'] as bool).length;
  final jointHits =
      withRegion.where((r) => r['joint_hit'] as bool).length;

  final nrAcc = total > 0 ? nrHits / total : 0.0;
  final storeAcc = total > 0 ? storeHits / total : 0.0;
  final jointAcc = total > 0 ? jointHits / total : 0.0;
  final best = nrAcc > storeAcc ? nrAcc : storeAcc;
  final synergy = jointAcc - best;

  return {
    'results': results,
    'total': results.length,
    'verified_total': total,
    'nr_hits': nrHits,
    'store_hits': storeHits,
    'joint_hits': jointHits,
    'nr_accuracy': nrAcc,
    'store_accuracy': storeAcc,
    'joint_accuracy': jointAcc,
    'synergy': synergy,
  };
}

// ══════════════════════════════════════════════════════════════
// Engine Singleton
// ══════════════════════════════════════════════════════════════

class JointHistoricalEngine {
  static final JointHistoricalEngine instance = JointHistoricalEngine._();
  JointHistoricalEngine._();

  final _db = Supabase.instance.client;
  bool _isRunning = false;

  // 알고리즘 버전 — 변경 시 자동 재검증 트리거
  static const int currentModelVersion = 1;

  // ── 앱 시작 시 자동 초기화 ────────────────────────────────
  // 정상 운영: 사용자가 버튼을 누를 필요 없음
  // - 최초: 전체 Historical Replay 자동 실행
  // - 모델 버전 변경: 자동 재검증
  // - 이미 완료: 아무 것도 하지 않음 (증분은 새 회차 도착 시 runIncremental 호출)
  Future<void> autoInitialize({
    required List<LottoWinningNumber> allNums,
    required List<StoreWinRecord> storeHistory,
  }) async {
    if (_isRunning) return;
    try {
      final summary = await loadSummary();
      final needsFullRun = summary == null ||
          summary.needsRun ||
          (summary.status == 'completed' &&
              await _isModelVersionOutdated());
      if (!needsFullRun) return;
      // 백그라운드에서 실행 (await 없이 fire-and-forget)
      runHistoricalReplay(allNums: allNums, storeHistory: storeHistory)
          .ignore();
    } catch (_) {}
  }

  Future<bool> isModelVersionOutdated() => _isModelVersionOutdated();

  Future<bool> _isModelVersionOutdated() async {
    try {
      final raw = await _db
          .from('rpa_joint_historical_job')
          .select('model_version')
          .eq('id', 1)
          .maybeSingle();
      if (raw == null) return false;
      final dbVersion = (raw['model_version'] as num? ?? 1).toInt();
      return dbVersion < currentModelVersion;
    } catch (_) {
      return false;
    }
  }

  // ── 증분 처리: 새 회차 도착 시 호출 ─────────────────────
  // 1) 이전 회차의 저장된 Prediction → 실제 결과와 비교 (채점)
  // 2) 누적 통계 업데이트
  // 3) 다음 회차 Prediction 생성 (rpa_joint_predictions에 위임)
  Future<void> runIncremental({
    required int newRound,
    required List<LottoWinningNumber> allNums,
    required List<StoreWinRecord> storeHistory,
  }) async {
    if (_isRunning) return;
    try {
      final summary = await loadSummary();
      if (summary == null || !summary.isCompleted) return;

      // 마지막 검증 회차 이후부터 newRound까지 처리
      final lastRow = await _db
          .from('rpa_joint_historical_results')
          .select('target_round')
          .order('target_round', ascending: false)
          .limit(1)
          .maybeSingle();
      final lastProcessed = lastRow != null
          ? (lastRow['target_round'] as num).toInt()
          : 0;

      if (newRound <= lastProcessed) return; // 이미 처리됨

      // 신규 회차들 증분 계산
      final newNums = allNums
          .where((w) => w.round > lastProcessed && w.round <= newRound)
          .toList();
      if (newNums.isEmpty) return;

      // 마지막으로 계산된 패턴 (전체 allNums 기준) 사용
      final storeByRound = <int, String>{};
      for (final s in storeHistory) {
        if (s.sido.isNotEmpty) storeByRound[s.round] = s.sido;
      }

      final sortedAll = List<Map<String, dynamic>>.from(
          allNums.map((w) => {'round': w.round, 'numbers': w.numbers}))
        ..sort((a, b) => (a['round'] as int).compareTo(b['round'] as int));

      final patterns = _computePatternsInMemory(
          sortedAll.where((m) => (m['round'] as int) < newRound).toList(),
          storeByRound);

      final rows = <Map<String, dynamic>>[];
      for (final target in newNums) {
        final idx = sortedAll
            .indexWhere((m) => (m['round'] as int) == target.round);
        if (idx <= 0) continue;
        final prevNum = sortedAll[idx - 1];
        final feat = _computeFeatureKey(prevNum);

        final nrCands = (patterns[feat] ?? [])
            .take(3)
            .map((p) => p['sido'] as String)
            .toList();

        final recentSidos = <String>[];
        for (int j = idx - 1; j >= 0 && recentSidos.length < 30; j--) {
          final sido = storeByRound[(sortedAll[j]['round'] as int)];
          if (sido != null) recentSidos.add(sido);
        }
        final sidoCounts = <String, int>{};
        for (final s in recentSidos) {
          sidoCounts[s] = (sidoCounts[s] ?? 0) + 1;
        }
        final storeCands = (sidoCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(3)
            .map((e) => e.key)
            .toList();

        final jointSet = <String>{...nrCands, ...storeCands};
        final actualSido = storeByRound[target.round] ?? '';
        final hasActual = actualSido.isNotEmpty;

        rows.add({
          'target_round': target.round,
          'training_end_round': target.round - 1,
          'nr_candidate_regions': nrCands,
          'store_candidate_regions': storeCands,
          'joint_candidate_regions': jointSet.toList(),
          'actual_region': actualSido,
          'nr_hit': hasActual && nrCands.contains(actualSido),
          'store_hit': hasActual && storeCands.contains(actualSido),
          'joint_hit': hasActual && jointSet.contains(actualSido),
        });
      }

      if (rows.isEmpty) return;

      await _db
          .from('rpa_joint_historical_results')
          .upsert(rows, onConflict: 'target_round');

      // 누적 통계 재계산 (전체 결과 집계)
      await _recalcStats();
    } catch (_) {}
  }

  // 전체 historical_results 집계 후 job 업데이트
  Future<void> _recalcStats() async {
    try {
      final raw = await _db
          .from('rpa_joint_historical_results')
          .select('nr_hit, store_hit, joint_hit, actual_region');
      final all = List<Map<String, dynamic>>.from(raw);
      final withRegion =
          all.where((r) => (r['actual_region'] as String? ?? '').isNotEmpty).toList();
      final n = withRegion.length;
      if (n == 0) return;
      final nrH = withRegion.where((r) => r['nr_hit'] as bool? ?? false).length;
      final stH = withRegion.where((r) => r['store_hit'] as bool? ?? false).length;
      final joH = withRegion.where((r) => r['joint_hit'] as bool? ?? false).length;
      final nrA = nrH / n;
      final stA = stH / n;
      final joA = joH / n;
      final syn = joA - (nrA > stA ? nrA : stA);
      await _upsertJob({
        'id': 1,
        'status': 'completed',
        'total_rounds': n,
        'processed_rounds': all.length,
        'nr_hits': nrH,
        'store_hits': stH,
        'joint_hits': joH,
        'nr_accuracy': nrA,
        'store_accuracy': stA,
        'joint_accuracy': joA,
        'synergy': syn,
        'model_version': currentModelVersion,
        'completed_at': DateTime.now().toIso8601String(),
      });
      await _db.from('rpa_joint_model_state').upsert({
        'id': 1,
        'number_model_accuracy': nrA,
        'store_model_accuracy': stA,
        'joint_model_accuracy': joA,
        'synergy_score': syn,
        'synergy_verified_rounds': n,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');
    } catch (_) {}
  }

  // ── Job 상태 로드 ─────────────────────────────────────────
  Future<WalkForwardSummary?> loadSummary() async {
    try {
      final raw = await _db
          .from('rpa_joint_historical_job')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (raw == null) return null;
      return WalkForwardSummary.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  // ── 메인 실행 ─────────────────────────────────────────────
  Future<WalkForwardSummary> runHistoricalReplay({
    required List<LottoWinningNumber> allNums,
    required List<StoreWinRecord> storeHistory,
    void Function(int processed, int total)? onProgress,
    int minTrainingRounds = 100,
    int retrainFrequency = 100,
  }) async {
    if (_isRunning) {
      final summary = await loadSummary();
      return summary ??
          const WalkForwardSummary(status: 'running');
    }
    _isRunning = true;

    final totalRounds = (allNums.length - minTrainingRounds).clamp(0, allNums.length);
    await _upsertJob({
      'id': 1,
      'status': 'running',
      'total_rounds': totalRounds,
      'processed_rounds': 0,
      'started_at': DateTime.now().toIso8601String(),
      'completed_at': null,
      'error_message': null,
    });

    try {
      onProgress?.call(0, totalRounds);

      // 데이터를 직렬화해서 Isolate에 전달
      final numMaps = allNums
          .map((w) => <String, dynamic>{'round': w.round, 'numbers': w.numbers})
          .toList();
      final storeMaps = storeHistory
          .map((s) => <String, dynamic>{'round': s.round, 'region': s.region})
          .toList();

      final output = await compute(_runWalkForwardIsolate, {
        'nums': numMaps,
        'stores': storeMaps,
        'minTrain': minTrainingRounds,
        'retrainFreq': retrainFrequency,
      });

      final results = output['results'] as List<dynamic>;
      final verifiedTotal = output['verified_total'] as int;
      final nrHits = output['nr_hits'] as int;
      final storeHits = output['store_hits'] as int;
      final jointHits = output['joint_hits'] as int;
      final nrAcc = (output['nr_accuracy'] as num).toDouble();
      final storeAcc = (output['store_accuracy'] as num).toDouble();
      final jointAcc = (output['joint_accuracy'] as num).toDouble();
      final synergy = (output['synergy'] as num).toDouble();

      // 결과 배치 upsert
      const batchSize = 200;
      int done = 0;
      for (int i = 0; i < results.length; i += batchSize) {
        final end = (i + batchSize).clamp(0, results.length);
        final batch = results.sublist(i, end);
        final rows = batch.map((r) {
          final m = Map<String, dynamic>.from(r as Map);
          return {
            'target_round': m['target_round'],
            'training_end_round': m['training_end_round'],
            'nr_candidate_regions': m['nr_candidate_regions'],
            'store_candidate_regions': m['store_candidate_regions'],
            'joint_candidate_regions': m['joint_candidate_regions'],
            'actual_region': m['actual_region'],
            'nr_hit': m['nr_hit'],
            'store_hit': m['store_hit'],
            'joint_hit': m['joint_hit'],
          };
        }).toList();
        try {
          await _db
              .from('rpa_joint_historical_results')
              .upsert(rows, onConflict: 'target_round');
        } catch (_) {}
        done += batch.length;
        onProgress?.call(done, results.length);
      }

      await _upsertJob({
        'id': 1,
        'status': 'completed',
        'total_rounds': verifiedTotal,
        'processed_rounds': results.length,
        'nr_hits': nrHits,
        'store_hits': storeHits,
        'joint_hits': jointHits,
        'nr_accuracy': nrAcc,
        'store_accuracy': storeAcc,
        'joint_accuracy': jointAcc,
        'synergy': synergy,
        'completed_at': DateTime.now().toIso8601String(),
        'error_message': null,
      });

      // Walk-Forward 결과를 rpa_joint_model_state에 반영
      // (in-sample 추정치를 실제 검증된 out-of-sample 수치로 대체)
      try {
        await _db.from('rpa_joint_model_state').upsert({
          'id': 1,
          'number_model_accuracy': nrAcc,
          'store_model_accuracy': storeAcc,
          'joint_model_accuracy': jointAcc,
          'synergy_score': synergy,
          'synergy_verified_rounds': verifiedTotal,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      } catch (_) {}

      return WalkForwardSummary(
        status: 'completed',
        totalRounds: verifiedTotal,
        processedRounds: results.length,
        nrHits: nrHits,
        storeHits: storeHits,
        jointHits: jointHits,
        nrAccuracy: nrAcc,
        storeAccuracy: storeAcc,
        jointAccuracy: jointAcc,
        synergy: synergy,
        completedAt: DateTime.now(),
      );
    } catch (e) {
      await _upsertJob({
        'id': 1,
        'status': 'failed',
        'error_message': e.toString(),
        'completed_at': DateTime.now().toIso8601String(),
      });
      rethrow;
    } finally {
      _isRunning = false;
    }
  }

  // ── 최근 결과 로드 ────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getResults({int limit = 20}) async {
    try {
      final raw = await _db
          .from('rpa_joint_historical_results')
          .select()
          .order('target_round', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> _upsertJob(Map<String, dynamic> data) async {
    try {
      await _db
          .from('rpa_joint_historical_job')
          .upsert(data, onConflict: 'id');
    } catch (_) {}
  }

}
