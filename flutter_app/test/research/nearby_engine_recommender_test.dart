import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_app/services/research/agent_research_repository.dart';
import 'package:flutter_app/services/research/nearby_engine_recommender.dart';
import 'package:flutter_app/services/route/region_research_repository.dart';

void main() {
  const me = LatLng(37.5, 127.0);
  RegionStore st(String code, double dLat, String rid) => RegionStore(
      code: code, name: code, address: '서울 강남구', region: '서울', regionId: rid, point: LatLng(37.5 + dLat, 127.0));

  test('가중치 합 = 1.0, 지방장 항목 포함', () {
    final sum = kNearbyWeights.values.fold(0.0, (a, b) => a + b);
    expect(sum, closeTo(1.0, 1e-12));
    expect(kNearbyWeights['agent'], 0.20);
    expect(kNearbyWeights['engine'], 0.30);
    expect(kNearbyWeightLabels.keys.toSet(), kNearbyWeights.keys.toSet());
  });

  test('주변 우위·최근 활동이 큰 판매점이 상위, 가설 10종 생성 (지방장 데이터 없음)', () {
    final stores = [st('A', 0.005, '서울|강남구'), st('B', 0.002, '서울|강남구'), st('C', 0.02, '서울|서초구')];
    final inputs = RegionEngineInputs(
      historyLoaded: true,
      latestRound: 1245,
      history: {
        'A': const StoreWinHistory(firstRounds: [1240, 1100], secondRounds: [1230, 1200, 1180, 900]),
        'B': const StoreWinHistory(secondRounds: [500]),
        'C': const StoreWinHistory(firstRounds: [700], secondRounds: [600]),
      },
      cycles: {'A': const StoreCycle(storeCode: 'A', trainingEndRound: 1245, cls: 'emerging', gapMean: 70, roundsSinceLast: 5)},
    );
    final ranked = RegionStoreRanker.rank(stores: stores, inputs: inputs, origin: me);
    final r = NearbyEngineRecommender.compute(
      me: me, radiusKm: 3, targetRound: 1246, ranked: ranked, inputs: inputs,
      stats: const {}, storeEngineSidos: const ['서울'],
    );
    expect(r.picks.first.ranked.store.code, 'A');
    expect(r.picks.first.rank, 1);
    expect(r.picks.first.evidence.length, 10);
    expect(r.picks.first.parts['storeEngine'], 1.0);
    expect(r.picks.first.parts['agent'], 0.0);
    final h10 = r.picks.first.evidence.last;
    expect(h10.code, 'H10');
    expect(h10.detail, contains('데이터 없음'));
    expect(h10.status, HypothesisStatus.none);
    expect(r.context.storeCount, 3);
    expect(r.context.totalFirst, 3);
    expect(r.context.emergingCount, 1);
    // 검증 통과 가설이 없으므로 검증 신호 판매점 0
    expect(r.verifiedSignalStores, 0);
    // 지방장 점수 없으면 기존 가중치
    expect(ranked.first.weights, RegionStoreRanker.weights);
    for (final p in r.picks) {
      expect(p.score, inInclusiveRange(0, 1));
    }
  });

  test('지방장 점수가 있으면 지방장 가중치 적용 · 정규화 순위 반영', () {
    final stores = [st('A', 0.005, '서울|강남구'), st('B', 0.002, '서울|강남구')];
    final inputs = RegionEngineInputs(
      historyLoaded: true,
      latestRound: 1245,
      history: {
        'A': const StoreWinHistory(firstRounds: [1100]),
        'B': const StoreWinHistory(firstRounds: [1000]),
      },
      agentScores: const {
        'A': AgentStoreScore(
            targetRound: 1246, storeCode: 'A', agentId: '서울|강남구', agentRank: 5, agentSize: 5, score: 0.001),
        'B': AgentStoreScore(
            targetRound: 1246, storeCode: 'B', agentId: '서울|강남구', agentRank: 1, agentSize: 5, score: 0.02,
            liveFactor: 1.3, hypCount: 2),
      },
    );
    final ranked = RegionStoreRanker.rank(stores: stores, inputs: inputs, origin: me);
    expect(ranked.first.store.code, 'B');
    expect(ranked.first.weights, RegionStoreRanker.weightsWithAgent);
    expect(ranked.first.components['agent'], 1.0);
    expect(ranked.last.components['agent'], 0.0);
    expect(ranked.first.reasons.any((x) => x.contains('지방장 서울|강남구 1/5위')), isTrue);
    expect(RegionStoreRanker.buildResult(ranked, inputs).weights, RegionStoreRanker.weightsWithAgent);

    final r = NearbyEngineRecommender.compute(
      me: me, radiusKm: 3, targetRound: 1246, ranked: ranked, inputs: inputs,
      stats: const {}, storeEngineSidos: const [],
    );
    final b = r.picks.firstWhere((p) => p.ranked.store.code == 'B');
    expect(b.parts['agent'], 1.0);
    final h10 = b.evidence.firstWhere((e) => e.code == 'H10');
    expect(h10.status, HypothesisStatus.verified); // live_factor != 1
    expect(h10.supports, isTrue);
    final a = r.picks.firstWhere((p) => p.ranked.store.code == 'A');
    expect(a.evidence.firstWhere((e) => e.code == 'H10').status, HypothesisStatus.descriptive);
  });

  test('AgentStoreScore 정규화 · 1곳 지역 · 평가 합산', () {
    const one = AgentStoreScore(targetRound: 1, storeCode: 'x', agentId: 'a', agentRank: 1, agentSize: 1, score: 0);
    expect(one.normalized, 1.0);
    const mid = AgentStoreScore(targetRound: 1, storeCode: 'x', agentId: 'a', agentRank: 3, agentSize: 5, score: 0);
    expect(mid.normalized, closeTo(0.5, 1e-12));
    final s = AgentRoundEvalSummary.fromRows('a', [
      {'mode': 'live', 'target_round': 1246, 'hits_any': 1, 'expected_uniform': 0.2},
      {'mode': 'backtest', 'target_round': 1000, 'hits_any': 2, 'hits_first': 1, 'expected_uniform': 0.5},
      {'mode': 'backtest', 'target_round': 1001, 'hits_any': 0, 'expected_uniform': 0.5},
    ]);
    expect(s.live!.hitsAny, 1);
    expect(s.backtest!.rounds, 2);
    expect(s.backtest!.hitsAny, 2);
    expect(s.backtest!.expectedUniform, closeTo(1.0, 1e-12));
    expect(s.backtest!.firstRound, 1000);
    // 브리핑 payload 는 모든 필드 선택적
    const b = AgentBriefing(payload: {});
    expect(b.focusRegions, isEmpty);
    expect(b.statusCounts, isEmpty);
    final h = AgentHypothesis.fromMap({'hypothesis_id': 'h', 'status': 'researching', 'summary': '요약'});
    expect(h.verified, isFalse);
    expect(h.summary, '요약');
    expect(AgentHypothesis.fromMap({'status': 'combined'}).verified, isTrue);
  });
}
