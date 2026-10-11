// RPA Monte Carlo Engine
// 역할: 가설 Random Control 검증 + Auxiliary Simulation Evidence 생성
// 주의: 예측의 주인공이 아닌 엔진 내부 보조 검증/참고 도구

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'rpa_hypothesis_engine.dart';

// ═══════════════════════════════════════════════════════════════
// Isolate-safe baseline computation (top-level)
// ═══════════════════════════════════════════════════════════════

const Set<int> _mcPrimes = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43};

Map<String, double> _computeBaselineIsolate(int iterations) {
  final rng = math.Random();
  int cOE33 = 0, cLH33 = 0, cCons = 0, cSumEven = 0;
  double sumTotal = 0, primeTotal = 0, rangeTotal = 0;

  for (int i = 0; i < iterations; i++) {
    final nums = <int>{};
    while (nums.length < 6) {
      nums.add(rng.nextInt(45) + 1);
    }
    final sorted = nums.toList()..sort();

    final odds = sorted.where((n) => n % 2 == 1).length;
    final lows = sorted.where((n) => n <= 22).length;
    final s = sorted.fold<int>(0, (a, b) => a + b);
    final primes = sorted.where(_mcPrimes.contains).length;
    final range = sorted.last - sorted.first;
    bool hasConsec = false;
    for (int j = 0; j < 5; j++) {
      if (sorted[j + 1] - sorted[j] == 1) {
        hasConsec = true;
        break;
      }
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

// ═══════════════════════════════════════════════════════════════
// McBaseline
// ═══════════════════════════════════════════════════════════════

class McBaseline {
  final int simulationCount;
  final double oddEven33;
  final double lowHigh33;
  final double consecutive;
  final double sumParity;
  final double sumMean;
  final double primeMean;
  final double rangeMean;
  final DateTime computedAt;
  final String engineVersion;

  const McBaseline({
    required this.simulationCount,
    required this.oddEven33,
    required this.lowHigh33,
    required this.consecutive,
    required this.sumParity,
    required this.sumMean,
    required this.primeMean,
    required this.rangeMean,
    required this.computedAt,
    this.engineVersion = '1',
  });

  factory McBaseline.fromJson(Map<String, dynamic> j) => McBaseline(
        simulationCount: (j['simulation_count'] as num?)?.toInt() ?? 50000,
        oddEven33: (j['odd_even_33'] as num?)?.toDouble() ?? 0,
        lowHigh33: (j['low_high_33'] as num?)?.toDouble() ?? 0,
        consecutive: (j['consecutive'] as num?)?.toDouble() ?? 0,
        sumParity: (j['sum_parity'] as num?)?.toDouble() ?? 0,
        sumMean: (j['sum_mean'] as num?)?.toDouble() ?? 0,
        primeMean: (j['prime_mean'] as num?)?.toDouble() ?? 0,
        rangeMean: (j['range_mean'] as num?)?.toDouble() ?? 0,
        computedAt: DateTime.tryParse(j['computed_at'] as String? ?? '') ?? DateTime(2000),
        engineVersion: j['engine_version'] as String? ?? '1',
      );

  Map<String, dynamic> toJson() => {
        'simulation_count': simulationCount,
        'odd_even_33': oddEven33,
        'low_high_33': lowHigh33,
        'consecutive': consecutive,
        'sum_parity': sumParity,
        'sum_mean': sumMean,
        'prime_mean': primeMean,
        'range_mean': rangeMean,
        'computed_at': computedAt.toIso8601String(),
        'engine_version': engineVersion,
      };

  bool get isStale => DateTime.now().difference(computedAt).inDays > 30;
  bool get isEmpty => simulationCount == 0;

  double? rateFor(String key) {
    switch (key) {
      case 'odd_even_33': return oddEven33;
      case 'low_high_33': return lowHigh33;
      case 'consecutive': return consecutive;
      case 'sum_parity': return sumParity;
      default: return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// McJob
// ═══════════════════════════════════════════════════════════════

enum McJobType {
  baseline,          // Random Baseline 재생성
  hypothesisControl, // 가설 Random Control (binomial test)
}

enum McJobStatus { queued, running, completed, failed, cached, skipped }

class McJob {
  final String id;
  final McJobType type;
  final String? hypothesisId;
  final int? sourceRound;
  final int simulationCount;
  McJobStatus status;
  int priority; // 1=높음, 5=보통, 9=낮음
  double progress;
  Map<String, dynamic>? result;
  String? errorMessage;
  final DateTime createdAt;
  DateTime? startedAt;
  DateTime? completedAt;

  McJob({
    required this.id,
    required this.type,
    this.hypothesisId,
    this.sourceRound,
    required this.simulationCount,
    required this.status,
    this.priority = 5,
    this.progress = 0.0,
    this.result,
    this.errorMessage,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  factory McJob.fromJson(Map<String, dynamic> j) => McJob(
        id: j['id'] as String,
        type: McJobType.values.firstWhere(
          (t) => t.name == (j['job_type'] as String? ?? ''),
          orElse: () => McJobType.hypothesisControl,
        ),
        hypothesisId: j['hypothesis_id'] as String?,
        sourceRound: j['source_round'] as int?,
        simulationCount: (j['simulation_count'] as num?)?.toInt() ?? 10000,
        status: McJobStatus.values.firstWhere(
          (s) => s.name == (j['status'] as String? ?? 'queued'),
          orElse: () => McJobStatus.queued,
        ),
        priority: (j['priority'] as num?)?.toInt() ?? 5,
        progress: (j['progress'] as num?)?.toDouble() ?? 0.0,
        result: j['result'] as Map<String, dynamic>?,
        errorMessage: j['error_message'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        startedAt: j['started_at'] != null ? DateTime.tryParse(j['started_at'] as String) : null,
        completedAt: j['completed_at'] != null ? DateTime.tryParse(j['completed_at'] as String) : null,
      );

  String get typeLabel {
    switch (type) {
      case McJobType.baseline: return 'Random Baseline';
      case McJobType.hypothesisControl: return '가설 Random Control';
    }
  }

  String get statusLabel {
    switch (status) {
      case McJobStatus.queued: return '대기';
      case McJobStatus.running: return '실행 중';
      case McJobStatus.completed: return '완료';
      case McJobStatus.failed: return '실패';
      case McJobStatus.cached: return '캐시 사용';
      case McJobStatus.skipped: return '건너뜀';
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// McJobStats
// ═══════════════════════════════════════════════════════════════

class McJobStats {
  final int queued;
  final int running;
  final int completedToday;
  final int failed;
  final int totalHypothesesVerified;
  final McBaseline? baseline;
  final DateTime? lastCompletedAt;

  const McJobStats({
    required this.queued,
    required this.running,
    required this.completedToday,
    required this.failed,
    required this.totalHypothesesVerified,
    this.baseline,
    this.lastCompletedAt,
  });

  bool get isIdle => queued == 0 && running == 0;
}

// ═══════════════════════════════════════════════════════════════
// Binomial test utility (main thread, no isolate needed)
// ═══════════════════════════════════════════════════════════════

final _logFactCache = <int, double>{};

double _logFactorial(int n) {
  if (n <= 1) return 0.0;
  return _logFactCache[n] ??= _logFactorial(n - 1) + math.log(n);
}

// one-tailed P(X >= observed | n, pNull) — 관측값이 랜덤보다 좋을 확률
double binomialPValue({
  required int n,
  required int observed,
  required double pNull,
}) {
  if (pNull <= 0) return observed > 0 ? 0.0 : 1.0;
  if (pNull >= 1) return 1.0;
  if (observed <= 0) return 1.0;
  if (observed > n) return 0.0;

  // 큰 n은 정규 근사
  if (n > 300) {
    final mean = n * pNull;
    final std = math.sqrt(n * pNull * (1 - pNull));
    if (std <= 0) return observed > mean ? 0.0 : 1.0;
    final z = (observed - 0.5 - mean) / std; // continuity correction
    return _normalSurvival(z);
  }

  final logP = math.log(pNull);
  final logQ = math.log(1 - pNull);
  final logFactN = _logFactorial(n);

  double pValue = 0.0;
  for (int k = observed; k <= n; k++) {
    pValue += math.exp(logFactN - _logFactorial(k) - _logFactorial(n - k) +
        k * logP + (n - k) * logQ);
  }
  return pValue.clamp(0.0, 1.0);
}

double _normalSurvival(double z) {
  if (z < -8) return 1.0;
  if (z > 8) return 0.0;
  const t0 = 0.2316419;
  const p0 = 0.319381530;
  const p1 = -0.356563782;
  const p2 = 1.781477937;
  const p3 = -1.821255978;
  const p4 = 1.330274429;
  final t = 1.0 / (1.0 + t0 * z.abs());
  final poly = t * (p0 + t * (p1 + t * (p2 + t * (p3 + t * p4))));
  final pdf = math.exp(-z * z / 2) / math.sqrt(2 * math.pi);
  final area = pdf * poly;
  return z >= 0 ? area : 1.0 - area;
}

// ═══════════════════════════════════════════════════════════════
// MonteCarloEngine
// ═══════════════════════════════════════════════════════════════

class MonteCarloEngine {
  MonteCarloEngine._();
  static final instance = MonteCarloEngine._();

  final _db = Supabase.instance.client;
  bool _isProcessing = false;
  static const _engineVersion = '2';
  static const _baselineCount = 50000;

  // ── Baseline ──────────────────────────────────────────────────────────

  Future<McBaseline?> loadBaseline() async {
    try {
      final row = await _db
          .from('rpa_mc_baseline')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return null;
      return McBaseline.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  Future<bool> needsBaselineRefresh() async {
    final b = await loadBaseline();
    if (b == null || b.isEmpty) return true;
    return b.isStale;
  }

  Future<McBaseline> refreshBaseline({int count = _baselineCount}) async {
    // 실행 중인 baseline job이 있으면 완료까지 대기하지 않고 예약
    final running = await _countJobsByStatus(McJobType.baseline, McJobStatus.running);
    if (running > 0) {
      final b = await loadBaseline();
      if (b != null) return b;
    }

    final jobId = await _createJob(
      type: McJobType.baseline,
      simulationCount: count,
      priority: 1,
    );

    final result = await compute(_computeBaselineIsolate, count);

    final baseline = McBaseline(
      simulationCount: count,
      oddEven33: result['odd_even_33']!,
      lowHigh33: result['low_high_33']!,
      consecutive: result['consecutive']!,
      sumParity: result['sum_parity']!,
      sumMean: result['sum_mean']!,
      primeMean: result['prime_mean']!,
      rangeMean: result['range_mean']!,
      computedAt: DateTime.now(),
      engineVersion: _engineVersion,
    );

    try {
      await _db.from('rpa_mc_baseline').upsert({
        'id': 1,
        ...baseline.toJson(),
        'engine_version': _engineVersion,
      });
      await _completeJob(jobId, {
        'odd_even_33': baseline.oddEven33,
        'low_high_33': baseline.lowHigh33,
      });
    } catch (_) {}

    return baseline;
  }

  // ── Hypothesis Random Control ─────────────────────────────────────────

  Future<void> onHypothesisCreated(RpaHypV3 hyp) async {
    await _scheduleHypothesisControl(hyp, priority: 3);
  }

  Future<void> _scheduleHypothesisControl(RpaHypV3 hyp, {int priority = 5}) async {
    // 이미 최근 검증된 경우 건너뜀
    final existing = await _countJobsByHypAndStatus(
      hyp.id, McJobStatus.completed,
    );
    if (existing > 0) return;

    await _createJob(
      type: McJobType.hypothesisControl,
      hypothesisId: hyp.id,
      simulationCount: 0, // binomial test는 시뮬레이션 불필요
      priority: priority,
    );
  }

  Future<void> _executeHypothesisControl(McJob job) async {
    final hypId = job.hypothesisId;
    if (hypId == null) return;

    final row = await _db
        .from('rpa_hypotheses_v3')
        .select('historical_sample_count, historical_success_rate, monte_carlo_random_rate, status')
        .eq('id', hypId)
        .maybeSingle();

    if (row == null) return;

    final n = (row['historical_sample_count'] as num?)?.toInt() ?? 0;
    final rate = (row['historical_success_rate'] as num?)?.toDouble() ?? 0.0;
    final baselineRate = (row['monte_carlo_random_rate'] as num?)?.toDouble();

    if (n < 5 || baselineRate == null || baselineRate <= 0) {
      await _completeJob(job.id, {'skipped': true, 'reason': 'insufficient_data'});
      return;
    }

    final observed = (n * rate).round();
    final pValue = binomialPValue(n: n, observed: observed, pNull: baselineRate);
    final percentile = ((1 - pValue) * 100).clamp(0.0, 100.0);

    // 효과크기
    final effectSize = rate - baselineRate;
    // evidence level
    final String evidenceLevel;
    if (pValue < 0.01 && effectSize >= 0.1) {
      evidenceLevel = 'strong';
    } else if (pValue < 0.05 && effectSize >= 0.06) {
      evidenceLevel = 'moderate';
    } else if (pValue < 0.1) {
      evidenceLevel = 'weak';
    } else {
      evidenceLevel = 'none';
    }

    final evidence = {
      'n': n,
      'observed': observed,
      'observed_rate': rate,
      'baseline_rate': baselineRate,
      'effect_size': effectSize,
      'p_value': pValue,
      'percentile': percentile,
      'evidence_level': evidenceLevel,
      'method': 'binomial_one_tailed',
    };

    // 가설에 저장
    try {
      await _db.from('rpa_hypotheses_v3').update({
        'mc_evidence': evidence,
        'mc_percentile': percentile,
        'mc_last_verified_round': job.sourceRound,
        'monte_carlo_p_value': pValue,
      }).eq('id', hypId);
    } catch (_) {}

    await _completeJob(job.id, evidence);
  }

  // ── Job Queue Management ──────────────────────────────────────────────

  Future<void> processQueueBatch({int maxJobs = 3}) async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      // Baseline이 필요하면 먼저 처리
      if (await needsBaselineRefresh()) {
        try {
          await refreshBaseline();
        } catch (_) {}
      }

      int processed = 0;
      while (processed < maxJobs) {
        final job = await _claimNextJob();
        if (job == null) break;
        try {
          await _executeJob(job);
        } catch (e) {
          await _failJob(job.id, e.toString());
        }
        processed++;
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _executeJob(McJob job) async {
    switch (job.type) {
      case McJobType.baseline:
        // baseline은 refreshBaseline()에서 직접 처리
        break;
      case McJobType.hypothesisControl:
        await _executeHypothesisControl(job);
        break;
    }
  }

  // ── Status / Stats ────────────────────────────────────────────────────

  Future<McJobStats> getStats() async {
    try {
      final results = await Future.wait<dynamic>([
        _db.from('rpa_mc_jobs').select('status').inFilter('status', ['queued', 'running']),
        _db.from('rpa_mc_jobs').select('status').eq('status', 'failed'),
        // 저장값은 McJobType.name('hypothesisControl'); 구 표기도 함께 허용
        _db.from('rpa_mc_jobs').select('id').eq('status', 'completed')
            .inFilter('job_type', ['hypothesisControl', 'hypothesis_control']),
        _db.from('rpa_mc_jobs').select('completed_at').eq('status', 'completed')
            .order('completed_at', ascending: false).limit(1).maybeSingle(),
        loadBaseline(),
      ]);

      final active = results[0] as List;
      final failed = results[1] as List;
      final verified = results[2] as List;
      final lastJob = results[3] as Map<String, dynamic>?;
      final baseline = results[4] as McBaseline?;

      int queued = 0, running = 0;
      for (final r in active) {
        if (r['status'] == 'queued') queued++;
        if (r['status'] == 'running') running++;
      }

      DateTime? lastAt;
      if (lastJob != null) {
        lastAt = DateTime.tryParse(lastJob['completed_at'] as String? ?? '');
      }

      return McJobStats(
        queued: queued,
        running: running,
        completedToday: 0,
        failed: failed.length,
        totalHypothesesVerified: verified.length,
        baseline: baseline,
        lastCompletedAt: lastAt,
      );
    } catch (_) {
      return McJobStats(
        queued: 0, running: 0, completedToday: 0, failed: 0,
        totalHypothesesVerified: 0,
      );
    }
  }

  Future<List<McJob>> getRecentJobs({int limit = 20}) async {
    try {
      final rows = await _db
          .from('rpa_mc_jobs')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((r) => McJob.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Auto-schedule all un-verified hypotheses ──────────────────────────

  Future<void> scheduleUnverifiedHypotheses() async {
    try {
      final hyps = await _db
          .from('rpa_hypotheses_v3')
          .select('id, historical_sample_count, historical_success_rate, monte_carlo_random_rate, status')
          .isFilter('mc_percentile', null)
          .inFilter('status', ['discovered', 'observing', 'validating', 'developing', 'accepted'])
          .limit(50);

      // 부분 컬럼 행을 RpaHypV3.fromJson 으로 변환하면 누락 필드 캐스트 예외로 전체가 중단됐음 → id 만 사용
      for (final row in hyps as List) {
        final id = '${(row as Map)['id']}';
        if (id.isEmpty || id == 'null') continue;
        try {
          final existing = await _countJobsByHypAndStatus(id, McJobStatus.completed);
          if (existing > 0) continue;
          final queued = await _db.from('rpa_mc_jobs').select('id')
              .eq('hypothesis_id', id).inFilter('status', ['queued', 'running']);
          if ((queued as List).isNotEmpty) continue;
          await _createJob(type: McJobType.hypothesisControl, hypothesisId: id, simulationCount: 0, priority: 7);
        } catch (_) {}
      }
    } catch (_) {}
  }

  // ── DB helpers ────────────────────────────────────────────────────────

  Future<String> _createJob({
    required McJobType type,
    String? hypothesisId,
    int? sourceRound,
    required int simulationCount,
    int priority = 5,
  }) async {
    try {
      final row = await _db.from('rpa_mc_jobs').insert({
        'job_type': type.name,
        'hypothesis_id': hypothesisId,
        'source_round': sourceRound,
        'simulation_count': simulationCount,
        'status': 'queued',
        'priority': priority,
        'progress': 0.0,
        'engine_version': _engineVersion,
      }).select('id').single();
      return (row as Map)['id'] as String;
    } catch (_) {
      return 'local_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<McJob?> _claimNextJob() async {
    try {
      final rows = await _db
          .from('rpa_mc_jobs')
          .select()
          .eq('status', 'queued')
          .order('priority')
          .order('created_at')
          .limit(1);
      if ((rows as List).isEmpty) return null;
      final job = McJob.fromJson(Map<String, dynamic>.from(rows.first as Map));
      await _db.from('rpa_mc_jobs').update({
        'status': 'running',
        'started_at': DateTime.now().toIso8601String(),
      }).eq('id', job.id);
      job.status = McJobStatus.running;
      return job;
    } catch (_) {
      return null;
    }
  }

  Future<void> _completeJob(String id, Map<String, dynamic> result) async {
    try {
      await _db.from('rpa_mc_jobs').update({
        'status': 'completed',
        'progress': 1.0,
        'result': result,
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } catch (_) {}
  }

  Future<void> _failJob(String id, String error) async {
    try {
      await _db.from('rpa_mc_jobs').update({
        'status': 'failed',
        'error_message': error,
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } catch (_) {}
  }

  Future<int> _countJobsByStatus(McJobType type, McJobStatus status) async {
    try {
      final rows = await _db
          .from('rpa_mc_jobs')
          .select('id')
          .eq('job_type', type.name)
          .eq('status', status.name);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _countJobsByHypAndStatus(String hypId, McJobStatus status) async {
    try {
      final rows = await _db
          .from('rpa_mc_jobs')
          .select('id')
          .eq('hypothesis_id', hypId)
          .eq('status', status.name);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }
}
