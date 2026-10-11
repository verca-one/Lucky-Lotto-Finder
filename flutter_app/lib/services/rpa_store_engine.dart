// Store Model Engine
// Phase 3: 판매점/지역 공간 전이 분석
//
// 원칙: target_round 예측 시 training_end_round 까지의 데이터만 사용.
// 스냅샷은 생성 후 수정하지 않는다.

import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

// ══════════════════════════════════════════════════════════════
// 모델
// ══════════════════════════════════════════════════════════════

class StoreWinRecord {
  final String code;
  final int round;
  final double? lat;
  final double? lng;
  final String region; // raw, e.g. "경기도 수원시 권선구"
  final String? purchaseMethod;

  const StoreWinRecord({
    required this.code,
    required this.round,
    required this.lat,
    required this.lng,
    required this.region,
    this.purchaseMethod,
  });

  // 시/도 (e.g. "경기도")
  String get sido {
    final t = region.trim();
    if (t.isEmpty) return '';
    return t.split(' ').first;
  }

  // 시/군/구 (e.g. "수원시")
  String get sigungu {
    final parts = region.trim().split(' ');
    return parts.length >= 2 ? parts[1] : '';
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static StoreWinRecord fromRaw(Map<String, dynamic> h, Map<String, dynamic> geo) =>
      StoreWinRecord(
        code: h['dhlottery_code'] as String,
        round: (h['round'] as num).toInt(),
        lat: _parseDouble(geo['latitude']),
        lng: _parseDouble(geo['longitude']),
        region: geo['region'] as String? ?? '',
        purchaseMethod: h['purchase_method'] as String?,
      );
}

// ── 지역별 시간 신호 모델 ─────────────────────────────────────────
class RegionTemporalInfo {
  final String sido;
  final int? lastWinRound;
  final int roundsAgoLastWin; // trainingEndRound - lastWinRound
  final int winsLast30Rounds;
  final String recencyStatus; // '최근활성' | '활성' | '보통' | '장기미당첨'

  const RegionTemporalInfo({
    required this.sido,
    required this.lastWinRound,
    required this.roundsAgoLastWin,
    required this.winsLast30Rounds,
    required this.recencyStatus,
  });

  // 회차 번호 → 추첨 날짜 (1회 = 2002-12-07 토요일, 매주 +7일)
  static DateTime drawDateFromRound(int round) =>
      DateTime(2002, 12, 7).add(Duration(days: (round - 1) * 7));

  // 다음 추첨까지 남은 일수 (오늘 기준)
  static int daysUntilNextDraw(int nextRound) {
    final drawDate = drawDateFromRound(nextRound);
    final today = DateTime.now();
    final diff = drawDate.difference(DateTime(today.year, today.month, today.day)).inDays;
    return diff < 0 ? 0 : diff;
  }

  // 추첨 날짜 문자열 "10월 11일 (토)"
  static String drawDateLabel(int round) {
    final d = drawDateFromRound(round);
    const weekdays = ['', '월', '화', '수', '목', '금', '토', '일'];
    return '${d.month}월 ${d.day}일 (${weekdays[d.weekday]})';
  }
}

// ── 지역 temporal 신호 계산 ───────────────────────────────────────
Map<String, RegionTemporalInfo> computeRegionTemporalSignals(
    List<StoreWinRecord> history, int trainingEndRound) {
  final sorted = history
      .where((r) => r.round <= trainingEndRound && r.sido.isNotEmpty)
      .toList()
    ..sort((a, b) => b.round.compareTo(a.round));

  final lastWinBySido = <String, int>{};
  final winsLast30 = <String, int>{};
  final cutoff30 = trainingEndRound - 30;

  for (final r in sorted) {
    lastWinBySido.putIfAbsent(r.sido, () => r.round);
    if (r.round > cutoff30) {
      winsLast30[r.sido] = (winsLast30[r.sido] ?? 0) + 1;
    }
  }

  final result = <String, RegionTemporalInfo>{};
  final allSidos = {...lastWinBySido.keys, ...winsLast30.keys};
  for (final sido in allSidos) {
    final lastRound = lastWinBySido[sido];
    final roundsAgo = lastRound != null ? trainingEndRound - lastRound : 999;
    final wins30 = winsLast30[sido] ?? 0;

    String status;
    if (roundsAgo <= 5) status = '최근활성';
    else if (roundsAgo <= 20) status = '활성';
    else if (roundsAgo <= 50) status = '보통';
    else status = '장기미당첨';

    result[sido] = RegionTemporalInfo(
      sido: sido,
      lastWinRound: lastRound,
      roundsAgoLastWin: roundsAgo,
      winsLast30Rounds: wins30,
      recencyStatus: status,
    );
  }
  return result;
}

class StoreSpatialPattern {
  final String id;
  final int horizon;
  final String distanceBand;
  final String regionFrom;
  final int totalOccurrences;
  final int phenomenonCount;
  final double successRate;
  final double mcRandomRate;
  final List<int> sampleRounds;

  const StoreSpatialPattern({
    required this.id,
    required this.horizon,
    required this.distanceBand,
    required this.regionFrom,
    required this.totalOccurrences,
    required this.phenomenonCount,
    required this.successRate,
    required this.mcRandomRate,
    required this.sampleRounds,
  });

  double get lift => mcRandomRate > 0 ? successRate / mcRandomRate : 0;

  factory StoreSpatialPattern.fromJson(Map<String, dynamic> j) => StoreSpatialPattern(
        id: j['id'] as String? ?? '',
        horizon: (j['horizon'] as num).toInt(),
        distanceBand: j['distance_band'] as String,
        regionFrom: j['region_from'] as String? ?? 'all',
        totalOccurrences: (j['total_occurrences'] as num).toInt(),
        phenomenonCount: (j['phenomenon_count'] as num).toInt(),
        successRate: (j['success_rate'] as num).toDouble(),
        mcRandomRate: (j['mc_random_rate'] as num).toDouble(),
        sampleRounds: List<int>.from(
            (j['sample_rounds'] as List? ?? []).map((e) => (e as num).toInt())),
      );
}

class StoreModelState {
  final int lastTrainedRound;
  final int modelVersion;
  final int patternCount;
  final double? replayRegionAccuracy;
  final double? replaySpatialAccuracy;
  final int activeHypothesisCount;
  final int totalTestRounds;

  const StoreModelState({
    this.lastTrainedRound = 0,
    this.modelVersion = 1,
    this.patternCount = 0,
    this.replayRegionAccuracy,
    this.replaySpatialAccuracy,
    this.activeHypothesisCount = 0,
    this.totalTestRounds = 0,
  });

  factory StoreModelState.fromJson(Map<String, dynamic> j) => StoreModelState(
        lastTrainedRound: (j['last_trained_round'] as num? ?? 0).toInt(),
        modelVersion: (j['model_version'] as num? ?? 1).toInt(),
        patternCount: (j['pattern_count'] as num? ?? 0).toInt(),
        replayRegionAccuracy: j['replay_region_accuracy'] != null
            ? (j['replay_region_accuracy'] as num).toDouble()
            : null,
        replaySpatialAccuracy: j['replay_spatial_accuracy'] != null
            ? (j['replay_spatial_accuracy'] as num).toDouble()
            : null,
        activeHypothesisCount:
            (j['active_hypothesis_count'] as num? ?? 0).toInt(),
        totalTestRounds: (j['total_test_rounds'] as num? ?? 0).toInt(),
      );
}

class StoreAnalysisStep {
  final String title;
  final String detail;
  final bool isError;
  const StoreAnalysisStep(
      {required this.title, required this.detail, this.isError = false});
}

// ══════════════════════════════════════════════════════════════
// 거리 구간
// ══════════════════════════════════════════════════════════════

const _kDistanceBands = [
  '0-1km', '1-3km', '3-5km', '5-10km', '10-20km', '20km+'
];

// 거리 구간별 면적 비율 (Monte Carlo 기준선)
// ring 면적 ∝ r2² - r1²
const _kBandAreaRatios = {
  '0-1km': 1.0,
  '1-3km': 8.0,
  '3-5km': 16.0,
  '5-10km': 75.0,
  '10-20km': 300.0,
  '20km+': 600.0,
};

// ══════════════════════════════════════════════════════════════
// 엔진 싱글톤
// ══════════════════════════════════════════════════════════════

class StoreModelEngine {
  static final StoreModelEngine instance = StoreModelEngine._();
  StoreModelEngine._();

  final _db = Supabase.instance.client;

  // ── Haversine ────────────────────────────────────────────
  static double haversine(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * asin(sqrt(a.clamp(0.0, 1.0)));
  }

  static double _rad(double deg) => deg * pi / 180;

  static String distanceBand(double km) {
    if (km < 1) return '0-1km';
    if (km < 3) return '1-3km';
    if (km < 5) return '3-5km';
    if (km < 10) return '5-10km';
    if (km < 20) return '10-20km';
    return '20km+';
  }

  // ── 1등 당첨 이력 로드 ────────────────────────────────────
  Future<List<StoreWinRecord>> loadWinHistory() async {
    // 1. winning_history 1등 전체 로드 (페이지네이션)
    final allHistory = <Map<String, dynamic>>[];
    int offset = 0;
    while (true) {
      final batch = await _db
          .from('winning_history')
          .select('dhlottery_code, round, purchase_method')
          .eq('lottery_type', 'lotto')
          .eq('prize_tier', 'first')
          .order('round', ascending: true)
          .range(offset, offset + 999);
      allHistory.addAll(List<Map<String, dynamic>>.from(batch));
      if (batch.length < 1000) break;
      offset += 1000;
    }

    if (allHistory.isEmpty) return [];

    // 2. 고유 판매점 코드 추출
    final codes =
        allHistory.map((r) => r['dhlottery_code'] as String).toSet().toList();

    // 3. 판매점 지역/좌표 로드 (청크)
    final geoMap = <String, Map<String, dynamic>>{};
    const chunkSize = 400;
    for (int i = 0; i < codes.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, codes.length);
      final rows = await _db
          .from('lottery_stores')
          .select('dhlottery_code, region, latitude, longitude')
          .inFilter('dhlottery_code', codes.sublist(i, end));
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        geoMap[r['dhlottery_code'] as String] = r;
      }
    }

    return allHistory.map((h) {
      final code = h['dhlottery_code'] as String;
      final geo = geoMap[code] ?? {};
      return StoreWinRecord.fromRaw(h, geo);
    }).toList();
  }

  // ── 상태 로드/저장 ────────────────────────────────────────
  Future<StoreModelState?> loadState() async {
    try {
      final raw = await _db
          .from('rpa_store_model_state')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (raw == null) return null;
      return StoreModelState.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveState(StoreModelState s) async {
    try {
      await _db.from('rpa_store_model_state').upsert({
        'id': 1,
        'last_trained_round': s.lastTrainedRound,
        'model_version': s.modelVersion,
        'pattern_count': s.patternCount,
        'replay_region_accuracy': s.replayRegionAccuracy,
        'replay_spatial_accuracy': s.replaySpatialAccuracy,
        'active_hypothesis_count': s.activeHypothesisCount,
        'total_test_rounds': s.totalTestRounds,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');
    } catch (_) {}
  }

  // ── 공간 전이 패턴 분석 ───────────────────────────────────
  // history: 전체 1등 이력 (round 오름차순)
  // upToRound: 이 회차까지의 데이터만 사용
  Future<List<StoreSpatialPattern>> analyzeSpatialPatterns(
    List<StoreWinRecord> history, {
    required int upToRound,
    int minSamples = 8,
  }) async {
    // 회차당 마지막 1등 (동일 회차에 복수 판매점 가능 — 대표 1개 사용)
    final byRound = <int, StoreWinRecord>{};
    for (final r in history) {
      if (r.round <= upToRound) byRound[r.round] = r;
    }

    final rounds = byRound.keys.toList()..sort();
    if (rounds.length < 2) return [];

    final totalArea =
        _kBandAreaRatios.values.reduce((a, b) => a + b);

    // horizon × band 집계
    final counts = <int, Map<String, int>>{};
    final totals = <int, int>{};
    final samples = <int, Map<String, List<int>>>{};

    for (int k = 1; k <= 6; k++) {
      counts[k] = {for (final b in _kDistanceBands) b: 0};
      totals[k] = 0;
      samples[k] = {for (final b in _kDistanceBands) b: []};
    }

    for (int i = 0; i < rounds.length; i++) {
      final rA = byRound[rounds[i]]!;
      if (rA.lat == null || rA.lng == null) continue;

      for (int k = 1; k <= 6; k++) {
        final targetRound = rounds[i] + k;
        final rB = byRound[targetRound];
        if (rB == null || rB.lat == null || rB.lng == null) continue;

        final dist =
            haversine(rA.lat!, rA.lng!, rB.lat!, rB.lng!);
        final band = distanceBand(dist);

        counts[k]![band] = (counts[k]![band] ?? 0) + 1;
        totals[k] = (totals[k] ?? 0) + 1;
        if ((samples[k]![band]?.length ?? 0) < 50) {
          samples[k]![band]!.add(rounds[i]);
        }
      }
    }

    // DB에 저장 + 결과 수집
    final result = <StoreSpatialPattern>[];

    for (int k = 1; k <= 6; k++) {
      final total = totals[k] ?? 0;
      if (total < minSamples) continue;

      for (final band in _kDistanceBands) {
        final count = counts[k]![band] ?? 0;
        final sr = total > 0 ? count / total : 0.0;
        final mcRate = (_kBandAreaRatios[band] ?? 1.0) / totalArea;

        try {
          await _db.from('rpa_store_spatial_patterns').upsert({
            'horizon': k,
            'distance_band': band,
            'region_from': 'all',
            'total_occurrences': total,
            'phenomenon_count': count,
            'success_rate': sr,
            'mc_random_rate': mcRate,
            'sample_rounds': samples[k]![band],
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'horizon,distance_band,region_from');
        } catch (_) {}

        result.add(StoreSpatialPattern(
          id: '$k-$band',
          horizon: k,
          distanceBand: band,
          regionFrom: 'all',
          totalOccurrences: total,
          phenomenonCount: count,
          successRate: sr,
          mcRandomRate: mcRate,
          sampleRounds: samples[k]![band]!,
        ));
      }
    }

    return result;
  }

  // ── 패턴 로드 (DB) ────────────────────────────────────────
  Future<List<StoreSpatialPattern>> loadPatterns({int? horizon}) async {
    try {
      var q = _db
          .from('rpa_store_spatial_patterns')
          .select()
          .eq('region_from', 'all');
      if (horizon != null) q = q.eq('horizon', horizon) as dynamic;
      final raw = await (q as dynamic).order('success_rate', ascending: false);
      return List<Map<String, dynamic>>.from(raw)
          .map(StoreSpatialPattern.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Historical Replay ─────────────────────────────────────
  // 학습 80% → 테스트 20% 슬라이딩 검증
  Future<Map<String, dynamic>> runHistoricalReplay(
      List<StoreWinRecord> history) async {
    final sorted = [...history]..sort((a, b) => a.round.compareTo(b.round));
    if (sorted.length < 20) return {'error': '데이터 부족 (최소 20건)'};

    final splitIdx = (sorted.length * 0.8).toInt();
    final trainData = sorted.sublist(0, splitIdx);
    final testData = sorted.sublist(splitIdx);

    // 학습 데이터로 horizon별 최다 발생 거리 구간 계산
    final byRoundTrain = <int, StoreWinRecord>{};
    for (final r in trainData) { byRoundTrain[r.round] = r; }

    final bandCounts = <int, Map<String, int>>{};
    final bandTotals = <int, int>{};
    for (int k = 1; k <= 6; k++) {
      bandCounts[k] = {for (final b in _kDistanceBands) b: 0};
      bandTotals[k] = 0;
    }

    final trainRounds = byRoundTrain.keys.toList()..sort();
    for (int i = 0; i < trainRounds.length; i++) {
      final rA = byRoundTrain[trainRounds[i]]!;
      if (rA.lat == null || rA.lng == null) continue;
      for (int k = 1; k <= 6; k++) {
        final rB = byRoundTrain[trainRounds[i] + k];
        if (rB == null || rB.lat == null || rB.lng == null) continue;
        final band = distanceBand(
            haversine(rA.lat!, rA.lng!, rB.lat!, rB.lng!));
        bandCounts[k]![band] = (bandCounts[k]![band] ?? 0) + 1;
        bandTotals[k] = (bandTotals[k] ?? 0) + 1;
      }
    }

    // horizon별 최다 거리 구간 (예측값)
    final bestBands = <int, String>{};
    for (int k = 1; k <= 6; k++) {
      final tot = bandTotals[k] ?? 0;
      if (tot == 0) continue;
      final best = bandCounts[k]!.entries
          .reduce((a, b) => a.value >= b.value ? a : b);
      bestBands[k] = best.key;
    }

    // 테스트 데이터 평가
    int regionHits = 0, spatialHits = 0, total = 0;

    for (final actual in testData) {
      if (actual.lat == null || actual.lng == null) continue;

      // 직전 1등
      final prevList = sorted
          .where((r) => r.round < actual.round && r.lat != null && r.lng != null)
          .toList();
      if (prevList.isEmpty) continue;
      final prev = prevList.last;

      final horizon = actual.round - prev.round;
      if (horizon < 1 || horizon > 6) continue;

      total++;

      // 지역 적중: 같은 시/도
      if (prev.sido == actual.sido && prev.sido.isNotEmpty) regionHits++;

      // 공간 적중: 예측 거리 구간 == 실제 거리 구간
      final actualBand = distanceBand(
          haversine(prev.lat!, prev.lng!, actual.lat!, actual.lng!));
      if (bestBands[horizon] == actualBand) spatialHits++;
    }

    return {
      'total_test_rounds': total,
      'region_hits': regionHits,
      'spatial_hits': spatialHits,
      'region_accuracy': total > 0 ? regionHits / total : 0.0,
      'spatial_accuracy': total > 0 ? spatialHits / total : 0.0,
    };
  }

  // ── 판매점 예측 스냅샷 저장 ───────────────────────────────
  Future<void> generateStorePrediction({
    required int targetRound,
    required List<StoreWinRecord> history,
    required int trainingEndRound,
  }) async {
    final horizon = targetRound - trainingEndRound;
    if (horizon < 1 || horizon > 6) return;

    // trainingEndRound 이하 최근 1등
    final sorted = history
        .where((r) => r.round <= trainingEndRound && r.lat != null)
        .toList()
      ..sort((a, b) => b.round.compareTo(a.round));
    if (sorted.isEmpty) return;
    final lastWin = sorted.first;

    // 해당 horizon의 최강 패턴
    final patterns = await loadPatterns(horizon: horizon);
    patterns.sort((a, b) => (b.lift).compareTo(a.lift));

    final bestBand = patterns.isNotEmpty ? patterns.first.distanceBand : null;
    final candidateRegions = lastWin.sido.isNotEmpty ? [lastWin.sido] : <String>[];

    try {
      await _db.from('rpa_store_predictions').upsert({
        'target_round': targetRound,
        'training_end_round': trainingEndRound,
        'model_version': 1,
        'horizon': horizon,
        'status': 'pending',
        'candidate_regions': candidateRegions,
        'candidate_store_codes': [],
        'spatial_score': {
          'last_win_round': lastWin.round,
          'last_win_code': lastWin.code,
          'last_win_region': lastWin.region,
          'last_win_lat': lastWin.lat,
          'last_win_lng': lastWin.lng,
          'best_distance_band': bestBand,
          'best_pattern_lift':
              patterns.isNotEmpty ? patterns.first.lift : null,
          'best_pattern_sr':
              patterns.isNotEmpty ? patterns.first.successRate : null,
        },
        'used_hypothesis_ids': [],
      }, onConflict: 'target_round,training_end_round,horizon',
          ignoreDuplicates: true);
    } catch (_) {}
  }

  // ── 예측 검증 (새 회차 실제 결과 입력 후) ─────────────────
  Future<void> verifyStorePrediction(StoreWinRecord actual) async {
    try {
      final preds = await _db
          .from('rpa_store_predictions')
          .select()
          .eq('target_round', actual.round)
          .eq('status', 'pending');

      for (final pred in List<Map<String, dynamic>>.from(preds)) {
        final candidates = List<String>.from(
            pred['candidate_regions'] as List? ?? []);
        final regionHit = actual.sido.isNotEmpty &&
            candidates.contains(actual.sido);

        bool? spatialHit;
        final score = pred['spatial_score'] as Map<String, dynamic>? ?? {};
        final prevLat =
            StoreWinRecord._parseDouble(score['last_win_lat']);
        final prevLng =
            StoreWinRecord._parseDouble(score['last_win_lng']);
        final bestBand = score['best_distance_band'] as String?;

        if (prevLat != null &&
            prevLng != null &&
            actual.lat != null &&
            actual.lng != null &&
            bestBand != null) {
          final dist = haversine(
              prevLat, prevLng, actual.lat!, actual.lng!);
          spatialHit = distanceBand(dist) == bestBand;
        }

        try {
          await _db.from('rpa_store_predictions').update({
            'status': 'verified',
            'actual_store_code': actual.code,
            'actual_region': actual.sido,
            'region_hit': regionHit,
            'spatial_hit': spatialHit,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', pred['id'] as String);
        } catch (_) {}
      }
    } catch (_) {}
  }

  // ── 최근 예측 로드 ────────────────────────────────────────
  Future<List<Map<String, dynamic>>> loadRecentPredictions({int limit = 10}) async {
    try {
      final raw = await _db
          .from('rpa_store_predictions')
          .select()
          .order('target_round', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(raw);
    } catch (_) {
      return [];
    }
  }

  // ── 공간 분석 회의 (Stream) ───────────────────────────────
  Stream<StoreAnalysisStep> runAnalysis(
    List<StoreWinRecord> history,
    int currentRound,
  ) async* {
    final geoCount =
        history.where((r) => r.lat != null && r.lng != null).length;

    yield StoreAnalysisStep(
      title: '데이터 확인',
      detail: '1등 기록 ${history.length}건 | 좌표 보유 $geoCount건',
    );

    if (geoCount < 20) {
      yield StoreAnalysisStep(
        title: '분석 불가',
        detail: '좌표 보유 판매점이 너무 적습니다 (최소 20건 필요)',
        isError: true,
      );
      return;
    }

    // 1. 공간 전이 패턴 분석
    yield StoreAnalysisStep(
      title: '공간 전이 분석',
      detail: '+1~+6 거리 구간 분포 계산 중...',
    );

    List<StoreSpatialPattern> patterns = [];
    try {
      patterns = await analyzeSpatialPatterns(
          history, upToRound: currentRound);
      final strong = patterns.where((p) => p.lift > 1.3).length;
      yield StoreAnalysisStep(
        title: '패턴 완료',
        detail:
            '전체 ${patterns.length}개 패턴 | 유의미(lift>1.3) $strong개',
      );
    } catch (e) {
      yield StoreAnalysisStep(
          title: '패턴 오류', detail: e.toString(), isError: true);
    }

    // 2. 강한 패턴 → 가설 생성
    final strong = patterns.where((p) => p.lift > 1.3).toList()
      ..sort((a, b) => b.lift.compareTo(a.lift));

    int created = 0;
    for (final p in strong.take(6)) {
      try {
        // 동일 가설 중복 방지 (trigger_conditions 기준)
        final existing = await _db
            .from('rpa_hypotheses_v3')
            .select('id')
            .eq('hypothesis_type', 'store_spatial')
            .eq('created_round', currentRound)
            .limit(1);
        if ((existing as List).isNotEmpty) break;

        await _db.from('rpa_hypotheses_v3').insert({
          'created_round': currentRound,
          'hypothesis_type': 'store_spatial',
          'status': 'discovered',
          'trigger_conditions': {
            'type': 'spatial_transition',
            'horizon': p.horizon,
            'distance_band': p.distanceBand,
          },
          'expected_phenomenon': {
            'distance_band': p.distanceBand,
            'direction': 'above',
            'horizon': p.horizon,
          },
          'horizon': p.horizon,
          'historical_sample_count': p.totalOccurrences,
          'historical_success_rate': p.successRate,
          'monte_carlo_random_rate': p.mcRandomRate,
          'current_weight': p.successRate,
          'evidence':
              '+${p.horizon}회 ${p.distanceBand} 출현율 ${(p.successRate * 100).toStringAsFixed(1)}%'
              ' (기준 ${(p.mcRandomRate * 100).toStringAsFixed(1)}%, lift ${p.lift.toStringAsFixed(2)})',
        });
        created++;
        break; // 한 번에 최강 1개만
      } catch (_) {}
    }

    if (created > 0) {
      yield StoreAnalysisStep(
          title: '가설 생성', detail: '공간 전이 가설 $created개 생성');
    }

    // 3. Historical Replay
    yield StoreAnalysisStep(
        title: 'Historical Replay', detail: '예측 성능 검증 중...');

    Map<String, dynamic> replay = {};
    try {
      replay = await runHistoricalReplay(history);
    } catch (e) {
      replay = {'error': e.toString()};
    }

    if (replay['error'] != null) {
      yield StoreAnalysisStep(
          title: 'Replay 생략',
          detail: replay['error'] as String,
          isError: true);
    } else {
      final regionAcc = replay['region_accuracy'] as double;
      final spatialAcc = replay['spatial_accuracy'] as double;
      final total = replay['total_test_rounds'] as int;
      yield StoreAnalysisStep(
        title: 'Replay 완료',
        detail: '지역 정확도 ${(regionAcc * 100).toStringAsFixed(1)}%'
            ' | 공간 정확도 ${(spatialAcc * 100).toStringAsFixed(1)}%'
            ' (테스트 $total회차)',
      );
    }

    // 4. 상태 저장
    await _saveState(StoreModelState(
      lastTrainedRound: currentRound,
      modelVersion: 1,
      patternCount: patterns.length,
      replayRegionAccuracy:
          replay['error'] == null ? replay['region_accuracy'] as double? : null,
      replaySpatialAccuracy:
          replay['error'] == null ? replay['spatial_accuracy'] as double? : null,
      activeHypothesisCount: strong.length,
      totalTestRounds:
          replay['total_test_rounds'] as int? ?? 0,
    ));

    // 5. +1~+6 예측 스냅샷 저장
    yield StoreAnalysisStep(
        title: '예측 생성', detail: '+1~+6 공간 예측 저장 중...');
    int predCount = 0;
    for (int k = 1; k <= 6; k++) {
      try {
        await generateStorePrediction(
          targetRound: currentRound + k,
          history: history,
          trainingEndRound: currentRound,
        );
        predCount++;
      } catch (_) {}
    }

    yield StoreAnalysisStep(
      title: '분석 완료',
      detail:
          '예측 $predCount개 저장 (${currentRound + 1}~${currentRound + 6}회)',
    );
  }
}
