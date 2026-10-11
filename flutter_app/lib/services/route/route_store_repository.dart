// 경로 기반 추천 — 기존 DB 읽기 전용 조회 (관리자 전용 연구 기능)
//
// 기존 크롤링 테이블(lottery_stores, winning_history) 및 연구 테이블(mnd_*, rpa_*) 을
// SELECT 만 수행한다. 어떤 테이블에도 쓰지 않으며 새 테이블을 만들지 않는다.
// 판매점 수만큼 쿼리하지 않고 inFilter 로 묶어서 조회한다.

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'route_store_recommender.dart';

class RouteStoreRepository {
  final SupabaseClient _db;
  RouteStoreRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  static const int _pageSize = 1000;

  /// bounding box 내 로또 판매점 (좌표 유효). 서버측 1차 필터 + 클라이언트 재검증.
  Future<List<RouteStoreCandidate>> loadLottoStoresInBox(GeoBox box) async {
    final out = <RouteStoreCandidate>[];
    var offset = 0;
    while (true) {
      final rows = await _db
          .from('lottery_stores')
          .select('dhlottery_code, store_name, address, region, first_count, '
              'second_count, latitude, longitude, latest_first_win, latest_second_win')
          .eq('lottery_type', 'lotto')
          .gte('latitude', box.minLat)
          .lte('latitude', box.maxLat)
          .gte('longitude', box.minLng)
          .lte('longitude', box.maxLng)
          .order('dhlottery_code', ascending: true)
          .range(offset, offset + _pageSize - 1);
      final list = List<Map<String, dynamic>>.from(rows);
      for (final r in list) {
        final lat = _d(r['latitude']);
        final lng = _d(r['longitude']);
        if (!RouteGeo.isValidKoreaCoord(lat, lng)) continue;
        final code = (r['dhlottery_code'] ?? '').toString();
        if (code.isEmpty) continue;
        out.add(RouteStoreCandidate(
          code: code,
          name: (r['store_name'] ?? '').toString(),
          address: (r['address'] ?? '').toString(),
          region: (r['region'] ?? '').toString(),
          point: LatLng(lat!, lng!),
          firstCount: _i(r['first_count']),
          secondCount: _i(r['second_count']),
          latestFirstWin: _iN(r['latest_first_win']),
          latestSecondWin: _iN(r['latest_second_win']),
        ));
      }
      if (list.length < _pageSize) break;
      offset += _pageSize;
    }
    // 코드 중복 제거 (첫 행 유지)
    final seen = <String>{};
    return out.where((s) => seen.add(s.code)).toList();
  }

  /// 판매점 코드 묶음에 대한 엔진/이력 근거를 한 번의 inFilter 쿼리씩으로 조회.
  Future<Map<String, StoreEngineInsight>> loadInsights(List<String> codes) async {
    if (codes.isEmpty) return {};
    final hFirst = <String, int>{};
    final hSecond = <String, int>{};
    final methods = <String, Map<String, int>>{};
    final anomalies = <String, StoreAnomalyLite>{};
    final hyps = <String, List<StoreHypothesisLite>>{};
    final cps = <String, List<StoreChangePointLite>>{};
    final rpaTarget = <String, int>{};

    // winning_history (크롤러 테이블, 읽기 전용)
    try {
      final rows = await _db
          .from('winning_history')
          .select('dhlottery_code, prize_tier, purchase_method')
          .eq('lottery_type', 'lotto')
          .inFilter('dhlottery_code', codes)
          .range(0, 4999);
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final c = (r['dhlottery_code'] ?? '').toString();
        final tier = (r['prize_tier'] ?? '').toString();
        if (tier == 'first') hFirst[c] = (hFirst[c] ?? 0) + 1;
        if (tier == 'second') hSecond[c] = (hSecond[c] ?? 0) + 1;
        final m = (r['purchase_method'] ?? '').toString().trim();
        final key = m.isEmpty ? '미상' : m;
        methods.putIfAbsent(c, () => {});
        methods[c]![key] = (methods[c]![key] ?? 0) + 1;
      }
    } catch (_) {
      // 이력 조회 실패 → 0 으로 표시 (추정값 저장 안 함)
    }

    // mnd_store_anomalies: 코드별 최신 training_end_round 행
    try {
      final rows = await _db
          .from('mnd_store_anomalies')
          .select('dhlottery_code, total_wins, expected_wins, poisson_z_score, '
              'bayesian_rate, bayesian_lower, bayesian_upper, anomaly_status, '
              'training_end_round, model_version')
          .inFilter('dhlottery_code', codes)
          .order('training_end_round', ascending: false);
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final c = (r['dhlottery_code'] ?? '').toString();
        if (anomalies.containsKey(c)) continue; // 최신만
        anomalies[c] = StoreAnomalyLite(
          totalWins: _i(r['total_wins']),
          expectedWins: _d(r['expected_wins']) ?? 0,
          poissonZ: _d(r['poisson_z_score']) ?? 0,
          bayesianRate: _d(r['bayesian_rate']) ?? 0,
          bayesianLower: _d(r['bayesian_lower']) ?? 0,
          bayesianUpper: _d(r['bayesian_upper']) ?? 0,
          anomalyStatus: (r['anomaly_status'] ?? 'normal').toString(),
          trainingEndRound: _i(r['training_end_round']),
          modelVersion: (r['model_version'] ?? '1.0').toString(),
        );
      }
    } catch (_) {}

    // mnd_hypotheses: subject_id = 판매점 코드 행만
    try {
      final rows = await _db
          .from('mnd_hypotheses')
          .select('hypothesis_id, hypothesis_type, subject_type, subject_id, status, '
              'gate_status, wf_rounds, wf_success_rate, wf_baseline_rate, '
              'wf_improvement, live_prediction_active, training_end_round')
          .inFilter('subject_id', codes)
          .order('training_end_round', ascending: false);
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final c = (r['subject_id'] ?? '').toString();
        hyps.putIfAbsent(c, () => []).add(StoreHypothesisLite(
          hypothesisId: (r['hypothesis_id'] ?? '').toString(),
          hypothesisType: (r['hypothesis_type'] ?? '').toString(),
          status: (r['status'] ?? 'observing').toString(),
          gateStatus: (r['gate_status'] ?? 'not_evaluated').toString(),
          wfRounds: _i(r['wf_rounds']),
          wfSuccessRate: _d(r['wf_success_rate']),
          wfBaselineRate: _d(r['wf_baseline_rate']),
          wfImprovement: _d(r['wf_improvement']),
          livePredictionActive: r['live_prediction_active'] == true,
          trainingEndRound: _i(r['training_end_round']),
        ));
      }
    } catch (_) {}

    // mnd_change_points
    try {
      final rows = await _db
          .from('mnd_change_points')
          .select('subject_id, change_point_round, pre_rate, post_rate, training_end_round')
          .inFilter('subject_id', codes)
          .order('training_end_round', ascending: false);
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final c = (r['subject_id'] ?? '').toString();
        cps.putIfAbsent(c, () => []).add(StoreChangePointLite(
          changePointRound: _i(r['change_point_round']),
          preRate: _d(r['pre_rate']) ?? 0,
          postRate: _d(r['post_rate']) ?? 0,
          trainingEndRound: _i(r['training_end_round']),
        ));
      }
    } catch (_) {}

    // rpa_store_predictions (있으면): 최근 예측의 candidate_store_codes 포함 여부
    try {
      final rows = await _db
          .from('rpa_store_predictions')
          .select('target_round, candidate_store_codes')
          .order('target_round', ascending: false)
          .limit(10);
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final cands = r['candidate_store_codes'];
        if (cands is! List) continue;
        final tr = _i(r['target_round']);
        for (final c in codes) {
          if (cands.contains(c) && !rpaTarget.containsKey(c)) rpaTarget[c] = tr;
        }
      }
    } catch (_) {
      // 테이블 없음/권한 없음 → 생략
    }

    final out = <String, StoreEngineInsight>{};
    for (final c in codes) {
      out[c] = StoreEngineInsight(
        historyFirst: hFirst[c] ?? 0,
        historySecond: hSecond[c] ?? 0,
        purchaseMethods: methods[c] ?? const {},
        anomaly: anomalies[c],
        hypotheses: hyps[c] ?? const [],
        changePoints: cps[c] ?? const [],
        rpaCandidateTargetRound: rpaTarget[c],
      );
    }
    return out;
  }

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _i(dynamic v) => _iN(v) ?? 0;
  static int? _iN(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
