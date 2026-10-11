// 내 위치 기반 엔진 추천 명당 — 마스터 브리핑 ③ "내 위치" 버튼
//
// 현재 위치 반경 내 판매점 전체(주변 상권)를 불러와 판매점마다 여러 가설을 계산하고,
// 사전 고정 가중치로 합산해 순위를 매긴다. 모든 DB 접근은 읽기 전용.
//
// 가설(판매점별):
//   H1 누적 이력        — winning_history 1·2등 횟수 (엔진 종합에 포함)
//   H2 주변 상권 우위    — 반경 내 판매점 대비 1·2등 합계 (경험적 베이즈 축소 배수, 주변 백분위)
//   H3 최근 활동        — 최근 100회 1·2등 수 vs 본인 과거 속도 (포아송 z)
//   H4 주기·신흥        — research_store_cycles (class, 평균 간격, 마지막 1등 후 회차)
//   H5 지역 전이        — 검증 통과 + 발화 중 전이 가설 (research_region_hypotheses)
//   H6 명당연구소(MND)  — mnd_hypotheses gate pass
//   H7 Store 엔진 후보  — rpa_store_predictions 이번 회차 지역 후보 시도
//   H8 시·군·구 연구    — research_region_stats 축소 추정/기준, 추세 z, 1등 공백
//   H9 접근성           — 현재 위치 직선거리
//   H10 지방장 연구     — research_agent_score_sets(압축) → 없으면 research_agent_store_scores (지방장 내 순위, live_factor/explore_factor)
//
// 종합 점수(사전 고정, 화면에 그대로 표시):
//   0.30×엔진 종합(H1·H4·H5·H6, RegionStoreRanker) + 0.20×지방장 연구 + 0.15×주변 우위
//   + 0.10×최근 활동 + 0.10×Store 엔진 후보 + 0.05×지역 연구 + 0.10×접근성
//   지방장 연구 = 1 − (지방장 내 순위−1)/(지방장 판매점 수−1), 점수 없으면 0 (데이터 없음).
// 판매점별 판매량 자료가 없으므로 어떤 가설도 "한 장당 당첨확률 우위"를 입증하지 않는다.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../route/region_research_repository.dart';

/// 판매점 데이터 시작 회차 (동행복권 판매점 당첨 정보 공개 시작)
const int kStoreDataStartRound = 262;
const int kRecentWindow = 100;

const Map<String, double> kNearbyWeights = {
  'engine': 0.30,
  'agent': 0.20,
  'local': 0.15,
  'recent': 0.10,
  'storeEngine': 0.10,
  'region': 0.05,
  'access': 0.10,
};

const Map<String, String> kNearbyWeightLabels = {
  'engine': '엔진 종합',
  'agent': '지방장 연구',
  'local': '주변 우위',
  'recent': '최근 활동',
  'storeEngine': 'Store 엔진 후보',
  'region': '지역 연구',
  'access': '접근성',
};

enum HypothesisStatus { verified, researching, descriptive, none }

extension HypothesisStatusLabel on HypothesisStatus {
  String get label => switch (this) {
        HypothesisStatus.verified => '검증 통과',
        HypothesisStatus.researching => '연구 중',
        HypothesisStatus.descriptive => '서술 지표',
        HypothesisStatus.none => '해당 없음',
      };
}

class StoreHypothesisEvidence {
  final String code;   // H1..H10
  final String title;
  final String detail;
  final HypothesisStatus status;
  final bool supports; // 이 판매점을 지지하는 방향인가
  const StoreHypothesisEvidence(this.code, this.title, this.detail, this.status, this.supports);
}

class NearbyStorePick {
  final RankedRegionStore ranked;
  final int rank;
  final double score;
  final Map<String, double> parts; // 0~1
  final List<StoreHypothesisEvidence> evidence;
  final String headline;
  const NearbyStorePick({
    required this.ranked, required this.rank, required this.score,
    required this.parts, required this.evidence, required this.headline,
  });
  int get supportCount => evidence.where((e) => e.supports).length;
  int get verifiedSupportCount =>
      evidence.where((e) => e.supports && e.status == HypothesisStatus.verified).length;
}

class NearbyContext {
  final int storeCount;
  final int storesWithWins;
  final int totalFirst;
  final int totalSecond;
  final int famousCount;
  final int emergingCount;
  final List<String> regionIds;
  final Map<String, RegionStats> regionStats;
  final int? latestRound;
  const NearbyContext({
    required this.storeCount, required this.storesWithWins, required this.totalFirst,
    required this.totalSecond, required this.famousCount, required this.emergingCount,
    required this.regionIds, required this.regionStats, required this.latestRound,
  });
}

class NearbyRecommendation {
  final LatLng me;
  final double radiusKm;
  final int targetRound;
  final NearbyContext context;
  final List<NearbyStorePick> picks; // 종합 점수 내림차순 (전체)
  final int verifiedSignalStores;
  const NearbyRecommendation({
    required this.me, required this.radiusKm, required this.targetRound,
    required this.context, required this.picks, required this.verifiedSignalStores,
  });
}

class NearbyEngineRecommender {
  NearbyEngineRecommender({RegionResearchRepository? repo}) : _repo = repo ?? RegionResearchRepository();
  final RegionResearchRepository _repo;

  Future<NearbyRecommendation> recommend({
    required LatLng me,
    required double radiusKm,
    required int targetRound,
    List<String> storeEngineSidos = const [],
    void Function(String)? onProgress,
  }) async {
    onProgress?.call('반경 ${radiusKm.toStringAsFixed(0)}km 판매점 조회 중…');
    final stores = await _repo.loadStoresNear(me, radiusKm);
    if (stores.isEmpty) {
      throw '반경 ${radiusKm.toStringAsFixed(0)}km 안에 좌표가 확인된 로또 판매점이 없습니다. 반경을 늘려 주세요.';
    }
    onProgress?.call('주변 ${stores.length}곳의 당첨 이력·주기·가설 조회 중…');
    final regionIds = stores.map((s) => s.regionId).whereType<String>().toSet();
    final inputs = await _repo.loadEngineInputs(stores, regionIds);
    onProgress?.call('시·군·구 지역 연구 통계 조회 중…');
    final statsLoad = await _repo.loadLatestStats(regionIds.toList()..sort());
    final stats = statsLoad.data;

    onProgress?.call('가설별 점수 계산 중…');
    final ranked = RegionStoreRanker.rank(stores: stores, inputs: inputs, origin: me);
    return compute(
      me: me, radiusKm: radiusKm, targetRound: targetRound, ranked: ranked,
      inputs: inputs, stats: stats, storeEngineSidos: storeEngineSidos,
    );
  }

  /// 순수 계산 (단위 테스트 대상)
  static NearbyRecommendation compute({
    required LatLng me,
    required double radiusKm,
    required int targetRound,
    required List<RankedRegionStore> ranked,
    required RegionEngineInputs inputs,
    required Map<String, RegionStats> stats,
    required List<String> storeEngineSidos,
  }) {
    final latest = inputs.latestRound ?? (targetRound - 1);
    final n = ranked.length;

    int firstOf(RankedRegionStore r) =>
        inputs.historyLoaded ? r.history.first : r.store.firstCount;
    int secondOf(RankedRegionStore r) =>
        inputs.historyLoaded ? r.history.second : r.store.secondCount;

    // ── H2 주변 상권: 1·2등 합계의 경험적 베이즈 축소 배수 ─────────────────
    final wins = [for (final r in ranked) firstOf(r) + secondOf(r)];
    final meanWins = n == 0 ? 0.0 : wins.reduce((a, b) => a + b) / n;
    final localRatio = <double>[
      for (final w in wins) meanWins > 0 ? (w + meanWins) / (2 * meanWins) : 1.0,
    ];
    final localPct = _percentiles(localRatio);

    // ── H3 최근 활동: 최근 100회 vs 본인 과거 속도 (포아송 z) ───────────────
    final recentStart = latest - kRecentWindow + 1;
    final pastSpan = math.max(1, recentStart - kStoreDataStartRound);
    final recentK = <int>[];
    final recentZ = <double?>[];
    for (final r in ranked) {
      int k;
      int past;
      if (inputs.historyLoaded) {
        k = r.history.firstRounds.where((x) => x >= recentStart).length +
            r.history.secondRounds.where((x) => x >= recentStart).length;
        past = r.history.first + r.history.second - k;
      } else {
        k = 0;
        past = r.store.firstCount + r.store.secondCount;
      }
      recentK.add(k);
      // 과거 속도 기반 기대치 (사전 0.5건 가산으로 이력 없는 판매점 과대평가 방지)
      final expected = (past + 0.5) / pastSpan * kRecentWindow;
      recentZ.add(inputs.historyLoaded ? (k - expected) / math.sqrt(expected) : null);
    }
    final recentScore = <double>[
      for (var i = 0; i < n; i++) recentK[i] == 0 ? 0.0 : (recentK[i] + 0.0),
    ];
    final recentPct = _percentiles(recentScore, zeroStaysZero: true);

    // ── H8 지역 연구: 축소 추정 / 기준 비율 ─────────────────────────────────
    double? regionRatio(String? rid) {
      final s = rid == null ? null : stats[rid];
      if (s == null || s.shrunkRate == null || s.baselineRate == null || s.baselineRate! <= 0) return null;
      return s.shrunkRate! / s.baselineRate!;
    }

    final regionVals = <double>[for (final r in ranked) regionRatio(r.store.regionId) ?? 0];
    final regionPct = _percentiles(regionVals, zeroStaysZero: true);

    final picks = <NearbyStorePick>[];
    for (var i = 0; i < n; i++) {
      final r = ranked[i];
      final f = firstOf(r), s2 = secondOf(r);
      final sido = r.store.regionId == null ? null : RegionIds.sidoOf(r.store.regionId!);
      final inStoreEngine = sido != null && storeEngineSidos.contains(sido);
      final d = r.distanceM;
      final access = d == null ? 0.0 : (1 - d / (radiusKm * 1000)).clamp(0.0, 1.0);

      final parts = <String, double>{
        'engine': r.total.clamp(0.0, 1.0),
        'agent': (r.components['agent'] ?? 0.0).clamp(0.0, 1.0),
        'local': localPct[i],
        'recent': recentPct[i],
        'storeEngine': inStoreEngine ? 1.0 : 0.0,
        'region': regionPct[i],
        'access': access,
      };
      var score = 0.0;
      kNearbyWeights.forEach((k, w) => score += w * parts[k]!);

      final ev = <StoreHypothesisEvidence>[];
      // H1
      ev.add(StoreHypothesisEvidence('H1', '누적 당첨 이력',
          '1등 $f회 · 2등 $s2회${r.history.firstRounds.isEmpty ? '' : ' · 최근 1등 ${r.history.firstRounds.take(3).join(', ')}회'}',
          HypothesisStatus.descriptive, f + s2 > 0));
      // H2
      final localRank = localRatio.where((x) => x > localRatio[i]).length + 1;
      ev.add(StoreHypothesisEvidence('H2', '주변 상권 우위',
          '반경 내 $n곳 평균(1·2등 ${meanWins.toStringAsFixed(1)}건) 대비 ×${localRatio[i].toStringAsFixed(2)} '
          '(축소 추정) · 주변 $localRank위',
          HypothesisStatus.descriptive, localRatio[i] > 1.05));
      // H3
      final z = recentZ[i];
      ev.add(StoreHypothesisEvidence('H3', '최근 $kRecentWindow회 활동',
          inputs.historyLoaded
              ? '최근 $recentStart~$latest회 1·2등 ${recentK[i]}건'
                '${z == null ? '' : ' · 본인 과거 속도 대비 z ${z >= 0 ? '+' : ''}${z.toStringAsFixed(2)}'}'
              : '당첨 회차 이력 조회 실패 → 계산 불가',
          HypothesisStatus.descriptive, recentK[i] > 0 && (z ?? 0) > 0));
      // H4
      final c = r.cycle;
      if (c == null) {
        ev.add(const StoreHypothesisEvidence('H4', '주기·신흥 명당', '주기 연구 대상 아님 (1등 이력 부족)',
            HypothesisStatus.none, false));
      } else {
        final clsName = {'famous': '유명 명당', 'emerging': '신흥 명당', 'regular': '일반', 'sparse': '희소'}[c.cls] ?? (c.cls ?? '-');
        final due = c.gapMean != null && c.roundsSinceLast != null && c.roundsSinceLast! >= c.gapMean!;
        final verified = (r.components['cycle'] ?? 0) > 0;
        ev.add(StoreHypothesisEvidence('H4', '주기·신흥 명당',
            '$clsName'
            '${c.gapMean == null ? '' : ' · 평균 간격 ${c.gapMean!.toStringAsFixed(0)}회'}'
            '${c.roundsSinceLast == null ? '' : ' · 마지막 1등 후 ${c.roundsSinceLast}회${due ? ' (평균 간격 도달)' : ''}'}'
            '${c.emergingP == null || c.cls != 'emerging' ? '' : ' · 급증 p=${c.emergingP!.toStringAsFixed(3)}'}'
            '${verified ? '' : ' · 판매점 주기 가설 검증 통과 없음 → 엔진 가점 0'}',
            verified ? HypothesisStatus.verified : HypothesisStatus.researching,
            c.famousOrEmerging || due));
      }
      // H5
      if (r.firingTransitions.isNotEmpty) {
        ev.add(StoreHypothesisEvidence('H5', '지역 전이 발화',
            r.firingTransitions.take(2).map((h) => h.summary).join(' / '),
            HypothesisStatus.verified, true));
      } else {
        ev.add(StoreHypothesisEvidence('H5', '지역 전이 발화',
            r.store.regionId == null
                ? '지역 미상'
                : '${RegionIds.display(r.store.regionId!)}로 향하는 검증 통과·발화 중 전이 가설 없음',
            HypothesisStatus.none, false));
      }
      // H6
      ev.add(StoreHypothesisEvidence('H6', '명당연구소(MND)',
          r.mndVerified
              ? 'gate pass 가설 보유'
              : (r.mndHypothesisCount > 0 ? '가설 ${r.mndHypothesisCount}건 연구 중 (gate 미통과)' : 'MND 가설 없음'),
          r.mndVerified
              ? HypothesisStatus.verified
              : (r.mndHypothesisCount > 0 ? HypothesisStatus.researching : HypothesisStatus.none),
          r.mndVerified));
      // H7
      ev.add(StoreHypothesisEvidence('H7', 'Store 엔진 $targetRound회 지역 후보',
          storeEngineSidos.isEmpty
              ? 'Store 엔진 이번 회차 후보 없음'
              : (inStoreEngine
                  ? '$sido — 이번 회차 후보(${storeEngineSidos.join(', ')})에 포함'
                  : '${sido ?? '지역 미상'} — 이번 회차 후보(${storeEngineSidos.join(', ')}) 밖'),
          HypothesisStatus.researching, inStoreEngine));
      // H8
      final st = r.store.regionId == null ? null : stats[r.store.regionId!];
      final rr = regionRatio(r.store.regionId);
      ev.add(StoreHypothesisEvidence('H8', '시·군·구 지역 연구',
          st == null
              ? '지역 연구 통계 없음'
              : '${RegionIds.display(st.regionId)}: 1등 비율 기준 대비 ×${rr?.toStringAsFixed(2) ?? '-'}'
                ' · 추세 z ${st.trendZ?.toStringAsFixed(2) ?? '-'} · 1등 공백 ${st.dormantRounds ?? '-'}회'
                ' (${st.trainingEndRound}회 기준)',
          st == null ? HypothesisStatus.none : HypothesisStatus.descriptive,
          (rr ?? 0) > 1.0 || (st?.trendZ ?? 0) > 1.0));
      // H9
      ev.add(StoreHypothesisEvidence('H9', '접근성', d == null ? '거리 미상' : '현재 위치에서 직선 ${_km(d)}',
          HypothesisStatus.descriptive, access >= 0.5));
      // H10
      final ag = inputs.agentScores[r.store.code];
      if (ag == null) {
        ev.add(const StoreHypothesisEvidence('H10', '지방장 연구', '데이터 없음 (지방장 연구 미실행)',
            HypothesisStatus.none, false));
      } else {
        ev.add(StoreHypothesisEvidence('H10', '지방장 연구',
            '${ag.agentId} ${ag.agentRank}/${ag.agentSize}위 · 점수 ${ag.score.toStringAsFixed(4)}'
            ' (회차당 1·2등 기대 빈도, 판매량 미보정) · live ×${ag.liveFactor.toStringAsFixed(2)}'
            ' · 탐색 ×${ag.exploreFactor.toStringAsFixed(2)} · 관련 가설 ${ag.hypCount}건 · ${ag.targetRound}회 목표',
            ag.liveApplied ? HypothesisStatus.verified : HypothesisStatus.descriptive,
            ag.normalized >= 0.8));
      }

      picks.add(NearbyStorePick(
        ranked: r, rank: 0, score: score, parts: parts, evidence: ev,
        headline: _headline(parts, ev),
      ));
    }

    picks.sort((a, b) {
      var c = b.score.compareTo(a.score);
      if (c == 0) c = (a.ranked.distanceM ?? double.infinity).compareTo(b.ranked.distanceM ?? double.infinity);
      return c != 0 ? c : a.ranked.store.code.compareTo(b.ranked.store.code);
    });
    final ordered = [
      for (var i = 0; i < picks.length; i++)
        NearbyStorePick(
          ranked: picks[i].ranked, rank: i + 1, score: picks[i].score, parts: picks[i].parts,
          evidence: picks[i].evidence, headline: picks[i].headline,
        ),
    ];

    final ctx = NearbyContext(
      storeCount: n,
      storesWithWins: wins.where((w) => w > 0).length,
      totalFirst: ranked.fold(0, (a, r) => a + firstOf(r)),
      totalSecond: ranked.fold(0, (a, r) => a + secondOf(r)),
      famousCount: ranked.where((r) => r.cycle?.cls == 'famous').length,
      emergingCount: ranked.where((r) => r.cycle?.cls == 'emerging').length,
      regionIds: (ranked.map((r) => r.store.regionId).whereType<String>().toSet().toList()..sort()),
      regionStats: stats,
      latestRound: inputs.latestRound,
    );
    return NearbyRecommendation(
      me: me, radiusKm: radiusKm, targetRound: targetRound, context: ctx, picks: ordered,
      verifiedSignalStores: ordered.where((p) => p.verifiedSupportCount > 0).length,
    );
  }

  /// 가장 크게 기여한 항목 2~3개로 선정 이유 한 줄
  static String _headline(Map<String, double> parts, List<StoreHypothesisEvidence> ev) {
    final contrib = kNearbyWeights.entries
        .map((e) => MapEntry(e.key, e.value * parts[e.key]!))
        .where((e) => e.value > 0.02)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final names = contrib.take(3).map((e) => kNearbyWeightLabels[e.key]!).toList();
    final support = ev.where((e) => e.supports).length;
    if (names.isEmpty) return '지지 가설 없음 — 거리·데이터 품질만 반영';
    return '${names.join(' · ')} 기여가 큼 · 지지 가설 $support/${ev.length}';
  }

  /// 값의 백분위(0~1). 동률은 같은 값. [zeroStaysZero] 이면 0 값은 0.
  static List<double> _percentiles(List<double> v, {bool zeroStaysZero = false}) {
    final n = v.length;
    if (n <= 1) return [for (final x in v) (zeroStaysZero && x == 0) ? 0.0 : (n == 1 ? 1.0 : 0.0)];
    final sorted = [...v]..sort();
    return [
      for (final x in v)
        (zeroStaysZero && x == 0)
            ? 0.0
            : sorted.where((y) => y < x).length / (n - 1),
    ];
  }

  static String _km(double m) => m < 1000 ? '${m.toStringAsFixed(0)}m' : '${(m / 1000).toStringAsFixed(2)}km';
}
