// 마스터 주요 브리핑 — 다음 회차 엔진 추천번호 · 구매예측 번호 · 이번 주 엔진 추천 명당
//
// 모두 DB 저장 결과와 기존 엔진 계산을 그대로 사용한다(새 계산 규칙 없음).
// ① 엔진 추천번호 = 공식 최종 예측(OfficialPredictionService, 패턴 분석·추천번호 화면과 같은 스냅샷).
//   Number 엔진 기본 조합(RpaLiveNumbers)은 연구용으로만 함께 담는다.
// 관리자 전용: 비관리자는 조회하지 않는다(AdminGate — 앱 내부 확인, DB 수준 강제는 Supabase Auth 필요).
// 명당 선정 규칙(사전 고정) — 지방장 파이프라인 우선:
//   1) 최신 live 중앙 엔진(research_agent_central)의 주목 지역 상위 5곳 각각의 지방장 납품 1위
//      (현재 모델 research_agent_deliveries, rank = 1)
//   2) 부족하면 중앙 엔진 전국 상위 후보(store_top) 순서로 채움 — 최대 5곳, 중복 제외
//   지방장 자료(중앙 결과·납품)가 없으면 이전 규칙으로 대체:
//     Store 엔진 지역 후보 상위 2 · 신흥 명당 2 · 유명 명당 1 (엔진 종합 = RegionStoreRanker)
//   Store 엔진 이번 회차 지역 후보(rpa_store_predictions.candidate_regions)는 별도 참고 신호로 함께 표시한다.
// 판매점별 가설 판정(검증 통과 / 검증했으나 우위 미확인 / 검증하지 않음)을 함께 담는다.
// 어떤 점수도 복권 한 장당 당첨확률이 아니다.

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin_gate.dart';
import '../route/region_research_repository.dart';
import '../rpa_live_numbers.dart';
import '../supabase_service.dart';
import 'agent_research_repository.dart';
import 'agent_store_evidence.dart';
import 'final_recommendation_engine.dart';
import 'number_popularity.dart';
import 'recommend_release.dart';
import 'purchase_prediction_engine.dart';
import 'research_scheduler.dart';
import 'store_hit_ranking.dart';

/// 명당 선정 경로
enum MasterPickSource { agentFocus, agentStoreTop, legacy }

class MasterStorePick {
  final RankedRegionStore ranked;
  final String why; // 선정 이유 (사람이 읽는 문장)
  final String? regionId;
  final MasterPickSource source;
  final AgentFocusRegion? focus;
  final AgentDelivery? delivery;
  final AgentCentralStore? central;

  /// 지방장 1등 추정 확률 · 검증 가설 배수 · 반영 확률 (hs-apply). 자료 없으면 null / 1.
  final double? pFirst;
  final double factor;
  final List<StoreHitHypothesis> hypotheses;
  const MasterStorePick(this.ranked, this.why, this.regionId,
      {this.source = MasterPickSource.legacy, this.focus, this.delivery, this.central,
      this.pFirst, this.factor = 1, this.hypotheses = const []});

  double? get pAdj => pFirst == null ? null : pFirst! * factor;
}

/// 지방장 파이프라인 후보 (순수 선택 결과)
class AgentPickCandidate {
  final String code;
  final String? regionId;
  final String why;
  final MasterPickSource source;
  final AgentFocusRegion? focus;
  final AgentDelivery? delivery;
  final AgentCentralStore? central;
  const AgentPickCandidate({
    required this.code,
    required this.why,
    required this.source,
    this.regionId,
    this.focus,
    this.delivery,
    this.central,
  });
}

String _f(double? v, [int d = 2]) => v == null ? '-' : v.toStringAsFixed(d);

/// 지방장별 납품 중 '1등 추정 확률(p_first, 없으면 점수) × 검증 가설 배수'가 가장 높은 1곳 (같으면 납품 순위, 순수 함수)
Map<String, AgentDelivery> pickByHit(List<AgentDelivery> deliveries, double Function(String code) factorOf) {
  final out = <String, AgentDelivery>{};
  double v(AgentDelivery x) => (x.pFirst ?? x.score ?? 0) * factorOf(x.storeCode);
  for (final x in [...deliveries]..sort((a, b) => a.rank.compareTo(b.rank))) {
    final cur = out[x.agentId];
    if (cur == null || v(x) > v(cur)) out[x.agentId] = x;
  }
  return out;
}

/// 선정 이유에 검증 가설 반영 내용을 붙인다
String _withHit(AgentPickCandidate c, StoreHitRanking? hit) {
  if (hit == null) return c.why;
  final f = hit.factorOf(c.code);
  final moved = c.delivery != null && c.delivery!.rank > 1;
  if (f <= 1 && !moved) return c.why;
  return '${c.why.replaceFirst('지방장 납품 1위', moved ? '지방장 납품 ${c.delivery!.rank}위' : '지방장 납품 1위')}'
      '${f > 1 ? ' · 검증 가설 ×${f.toStringAsFixed(2)} 반영' : ''}${moved ? ' → 가설 반영 후 지역 1위' : ''}';
}

/// 주목 지역 상위 [topRegions]곳의 지방장 1위 납품 → 부족하면 전국 상위 후보로 채움 (최대 [max]곳, 순수 함수)
List<AgentPickCandidate> selectAgentPicks({
  required List<AgentFocusRegion> focus,
  required Map<String, AgentDelivery> rank1ByAgent,
  required List<AgentCentralStore> storeTop,
  int topRegions = 5,
  int max = 5,
}) {
  final sorted = [...focus.where((f) => f.regionId.isNotEmpty)]
    ..sort((a, b) => (a.rank ?? 1 << 30).compareTo(b.rank ?? 1 << 30));
  final out = <AgentPickCandidate>[];
  final used = <String>{};
  for (final f in sorted.take(topRegions)) {
    if (out.length >= max) break;
    final d = rank1ByAgent[f.regionId];
    if (d == null || d.storeCode.isEmpty || !used.add(d.storeCode)) continue;
    out.add(AgentPickCandidate(
      code: d.storeCode,
      regionId: f.regionId,
      source: MasterPickSource.agentFocus,
      focus: f,
      delivery: d,
      why: '중앙 엔진 주목 지역 ${f.rank ?? '-'}위 ${agentLabel(f.regionId)} (p ${_f(f.p, 3)} · 기준 대비 ×${_f(f.ratio)})'
          ' · 그 지역 지방장 납품 1위 (점수 ${_f(d.score, 4)})',
    ));
  }
  for (var i = 0; i < storeTop.length && out.length < max; i++) {
    final s = storeTop[i];
    if (s.storeCode.isEmpty || !used.add(s.storeCode)) continue;
    out.add(AgentPickCandidate(
      code: s.storeCode,
      regionId: s.agentId,
      source: MasterPickSource.agentStoreTop,
      central: s,
      why: '중앙 엔진 전국 상위 후보 ${i + 1}위'
          '${s.agentId == null ? '' : ' · ${agentLabel(s.agentId)}${s.agentRank == null ? '' : ' 지방장 내 ${s.agentRank}위'}'}'
          ' (점수 ${_f(s.score, 4)})',
    ));
  }
  return out;
}

class MasterBriefing {
  final int targetRound;
  final int latestRound;

  /// ① 공식 최종 예측 (조회 실패 시 null → [officialError])
  final OfficialPrediction? official;
  final String? officialError;

  /// 연구용 · Number 엔진 기본 조합 (최종 추천 아님)
  final RpaLiveNumbers? engine;
  final PurchaseModelReport? purchase;

  /// 번호 인기도 (pop-1.0 · 서버 저장본) — 공식 세트 인기도 · 비인기 추천 5세트
  final NumberPopularity? popularity;

  /// 이번 회차 추천번호 공개 상태 (월요일 0시 KST 또는 수동 추천). null = 확인 실패(공개로 취급)
  final ReleaseState? release;

  /// 사전 등록 장부(research_predictions)의 이번 회차 세트 — 알고리즘별 최신 버전 (④ Number 엔진 · ⑤ 무작위 대조군 표시용)
  final Map<String, List<List<int>>> ledger;
  bool get numbersReleased => release?.released ?? true;
  final List<MasterStorePick> stores;
  final List<String> storeEngineRegions;   // Store 엔진 이번 회차 지역 후보
  final int? storeEngineTrainingEnd;
  final String? storeError;

  /// 명당 선정 기준 (지방장 파이프라인이면 최신 live 기준, 이전 규칙이면 null)
  final AgentLiveRef? agentRef;

  /// 지방장 파이프라인을 쓰지 못해 이전 규칙으로 대체한 이유 (대체하지 않았으면 null)
  final String? fallbackReason;

  /// 명당별 지방장 근거 (조회 실패 시 null)
  final AgentEvidenceBundle? evidence;

  /// 전국 판매점 적중 예측 순위 (지방장 확률 × 검증 가설 배수, hs-apply). 서버 결과 없으면 null.
  final StoreHitRanking? hitRanking;

  /// 비관리자 요청 → 조회하지 않음 ('관리자 전용')
  final String? deniedMessage;
  const MasterBriefing({
    required this.targetRound, required this.latestRound, this.official, this.officialError, this.engine, this.purchase, this.popularity, this.release, this.ledger = const {},
    this.stores = const [], this.storeEngineRegions = const [], this.storeEngineTrainingEnd, this.storeError,
    this.agentRef, this.fallbackReason, this.evidence, this.deniedMessage, this.hitRanking,
  });

  bool get agentPipeline => agentRef != null && stores.any((s) => s.source != MasterPickSource.legacy);

  static const String storeDisclaimer =
      '엔진 추천 명당은 지방장 연구(중앙 엔진 주목 지역 · 지방장 납품 1위 · 전국 상위 후보)로 고른 것입니다. '
      '판매점별 판매량 자료가 없어 점수는 복권 한 장당 당첨확률이 아니며, 판매점 우위 여부는 카드의 가설 판정을 따릅니다.';
  static const String legacyDisclaimer =
      '이전 규칙(누적 당첨 이력·최근 활동·Store 엔진 지역 후보)으로 고른 명당입니다. '
      '판매점별 판매량 자료가 없어 점수는 복권 한 장당 당첨확률이 아닙니다.';
}

class MasterBriefingService {
  MasterBriefingService._();
  static final instance = MasterBriefingService._();
  final _db = Supabase.instance.client;

  MasterBriefing? _cache;
  DateTime? _cachedAt;

  void clearCache() => _cache = null;

  Future<MasterBriefing> load({bool force = false}) async {
    // 관리자 전용 (캐시보다 먼저 확인)
    if (!await AdminGate.isAdmin()) {
      return const MasterBriefing(targetRound: 0, latestRound: 0, deniedMessage: kAdminOnlyMessage);
    }
    if (!force && _cache != null && _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < const Duration(minutes: 10)) {
      return _cache!;
    }
    final recent = await SupabaseService.getRecentWinningNumbers(1);
    final latest = recent.isEmpty ? 0 : recent.first.round;
    final target = latest + 1;

    OfficialPrediction? official;
    String? officialError;
    try {
      official = await OfficialPredictionService.instance.load(target, force: force);
    } catch (e) {
      officialError = '$e';
      debugPrint('[Master] official: $e');
    }
    RpaLiveNumbers? engine;
    try { engine = await RpaLiveNumbers.load(target); } catch (e) { debugPrint('[Master] engine: $e'); }
    PurchaseModelReport? purchase;
    try { purchase = await ResearchScheduler.instance.purchaseReport(targetRound: target); } catch (e) { debugPrint('[Master] purchase: $e'); }
    NumberPopularity? popularity;
    try { popularity = await NumberPopularity.load(target); } catch (e) { debugPrint('[Master] popularity: $e'); }
    ReleaseState? release;
    try {
      release = await RecommendRelease.state(target, prevDrawDate: recent.isEmpty ? null : recent.first.drawDate);
    } catch (e) { debugPrint('[Master] release: $e'); }
    final ledger = <String, List<List<int>>>{};
    try {
      final rows = await _db.from('research_predictions').select('algorithm,version,sets')
          .eq('target_round', target).order('version', ascending: true);
      for (final r in List<Map<String, dynamic>>.from(rows as List)) {
        ledger['${r['algorithm']}'] = (r['sets'] as List)
            .map((s) => (s as List).map((n) => (n as num).toInt()).toList()..sort())
            .toList(); // 버전 오름차순이라 마지막(최신 버전)이 남는다
      }
    } catch (e) { debugPrint('[Master] ledger: $e'); }

    var regions = <String>[];
    int? storeTe;
    var picks = <MasterStorePick>[];
    String? storeErr;
    AgentLiveRef? agentRef;
    String? fallbackReason;
    AgentEvidenceBundle? evidence;
    StoreHitRanking? hit;
    try {
      hit = await StoreHitRanking.load(target);
    } catch (e) {
      debugPrint('[Master] hit ranking: $e');
    }
    // Store 엔진 이번 회차 지역 후보 (참고 신호로 함께 표시)
    try {
      final sp = await _db.from('rpa_store_predictions').select('training_end_round,candidate_regions')
          .eq('target_round', target).order('training_end_round', ascending: false).limit(1);
      if ((sp as List).isNotEmpty) {
        storeTe = (sp.first['training_end_round'] as num?)?.toInt();
        regions = List<String>.from((sp.first['candidate_regions'] as List? ?? []).map((e) => RegionIds.normalizeSido('$e')));
      }
    } catch (e) {
      debugPrint('[Master] store engine regions: $e');
    }
    // 1) 지방장 파이프라인
    try {
      final r = await _pickAgentStores(hit);
      agentRef = r.$1;
      picks = r.$2;
      fallbackReason = r.$3;
    } catch (e) {
      fallbackReason = '지방장 자료 조회 오류: $e';
      debugPrint('[Master] agent stores: $e');
    }
    // 2) 대체: 이전 규칙
    if (picks.isEmpty) {
      agentRef = null;
      try {
        picks = await _pickStores(regions);
      } catch (e) {
        storeErr = '$e';
        debugPrint('[Master] stores: $e');
      }
    }
    if (picks.isNotEmpty) {
      try {
        evidence = await loadEvidenceForRanked(picks.map((p) => p.ranked).toList());
      } catch (e) {
        debugPrint('[Master] evidence: $e');
      }
    }

    _cache = MasterBriefing(
      targetRound: target, latestRound: latest, official: official, officialError: officialError,
      engine: engine, purchase: purchase, popularity: popularity, release: release, ledger: ledger,
      stores: picks, storeEngineRegions: regions, storeEngineTrainingEnd: storeTe, storeError: storeErr,
      agentRef: agentRef, fallbackReason: fallbackReason, evidence: evidence, hitRanking: hit,
    );
    _cachedAt = DateTime.now();
    return _cache!;
  }

  /// 지방장 파이프라인 선정. (기준, 명당, 대체 사유). 자료가 없으면 명당 빈 목록 + 사유.
  Future<(AgentLiveRef?, List<MasterStorePick>, String?)> _pickAgentStores(StoreHitRanking? hit) async {
    final repo = AgentResearchRepository();
    final live = await repo.latestLive();
    final ref = live.data;
    if (ref == null) return (null, <MasterStorePick>[], '지방장 실전 기준 없음 (${live.message ?? kResearchNoData})');
    final central = (await repo.loadCentral(ref.target, model: ref.model)).data;
    if (central == null) return (ref, <MasterStorePick>[], '${ref.target}회 중앙 엔진 결과 없음');
    final sortedFocus = [...central.focusRegions]
      ..sort((a, b) => (a.rank ?? 1 << 30).compareTo(b.rank ?? 1 << 30));
    final topIds = sortedFocus.take(5).map((f) => f.regionId).where((s) => s.isNotEmpty).toList();
    // 지방장 납품 TOP5 중 '1등 추정 확률 × 검증 가설 배수'가 가장 높은 곳 (가설 결과 없으면 납품 1위)
    final d = await repo.loadDeliveriesForAgents(topIds, target: ref.target, model: ref.model);
    final hitOk = hit != null && hit.targetRound == ref.target;
    final rank1 = pickByHit(d.data, hitOk ? hit.factorOf : (_) => 1.0);
    final cands = selectAgentPicks(focus: central.focusRegions, rank1ByAgent: rank1, storeTop: central.storeTop);
    if (cands.isEmpty) return (ref, <MasterStorePick>[], '주목 지역 납품·전국 상위 후보 없음');

    // 판매점 기본 정보 (lottery_stores, 읽기 전용) → 엔진 연구 점수 (선정 명당 목록 내 상대)
    final codes = cands.map((c) => c.code).toList();
    final rows = await _db.from('lottery_stores')
        .select('dhlottery_code,store_name,address,region,latitude,longitude,first_count,second_count')
        .eq('lottery_type', 'lotto').inFilter('dhlottery_code', codes);
    final stores = <RegionStore>[];
    for (final r in List<Map<String, dynamic>>.from(rows as List)) {
      final lat = (r['latitude'] as num?)?.toDouble(), lng = (r['longitude'] as num?)?.toDouble();
      final ok = lat != null && lng != null && lat >= 33 && lat <= 39 && lng >= 124 && lng <= 132;
      final code = r['dhlottery_code'] as String;
      final region = (r['region'] as String?) ?? '';
      final address = (r['address'] as String?) ?? '';
      stores.add(RegionStore(
        code: code, name: (r['store_name'] as String?) ?? code, address: address, region: region,
        regionId: RegionIds.fromStore(region: region, address: address),
        point: ok ? LatLng(lat, lng) : null,
        firstCount: (r['first_count'] as num?)?.toInt() ?? 0, secondCount: (r['second_count'] as num?)?.toInt() ?? 0,
      ));
    }
    if (stores.isEmpty) return (ref, <MasterStorePick>[], '선정 판매점 정보(lottery_stores) 없음');
    final regionIds = stores.map((s) => s.regionId).whereType<String>().toSet();
    var inputs = await RegionResearchRepository().loadEngineInputs(stores, regionIds);
    if (hitOk) {
      inputs = inputs.withFactoryVerified({
        for (final c in codes)
          if (hit.factorOf(c) > 1) c: [for (final h in hit.hypothesesOf(c)) h.label],
      });
    }
    final ranked = {for (final r in RegionStoreRanker.rank(stores: stores, inputs: inputs)) r.store.code: r};
    final picks = <MasterStorePick>[
      for (final c in cands)
        if (ranked[c.code] != null)
          MasterStorePick(ranked[c.code]!, _withHit(c, hitOk ? hit : null), c.regionId ?? ranked[c.code]!.store.regionId,
              source: c.source, focus: c.focus, delivery: c.delivery, central: c.central,
              pFirst: c.delivery?.pFirst ?? c.central?.pFirst,
              factor: hitOk ? hit.factorOf(c.code) : 1.0,
              hypotheses: hitOk ? hit.hypothesesOf(c.code) : const []),
    ]..sort((a, b) => (b.pAdj ?? -1).compareTo(a.pAdj ?? -1)); // 적중 예측 높은 순
    return (ref, picks, picks.isEmpty ? '선정 판매점 정보 없음' : null);
  }

  Future<List<MasterStorePick>> _pickStores(List<String> engineSidos) async {
    // 최신 판매점 주기 연구 회차
    final lr = await _db.from('research_store_cycles').select('training_end_round')
        .order('training_end_round', ascending: false).limit(1);
    if ((lr as List).isEmpty) return [];
    final te = (lr.first['training_end_round'] as num).toInt();

    Future<List<Map<String, dynamic>>> cycles(dynamic Function(dynamic q) f, int limit) async {
      final q = _db.from('research_store_cycles')
          .select('store_code,region_id,class,first_count,second_count,recent100_first,emerging_p')
          .eq('training_end_round', te);
      return List<Map<String, dynamic>>.from(await (f(q) as dynamic).limit(limit) as List);
    }

    final regionRows = <Map<String, dynamic>>[];
    for (final sd in engineSidos) {
      regionRows.addAll(await cycles((q) => q.like('region_id', '$sd|%').order('first_count', ascending: false), 40));
    }
    final emergingRows = await cycles((q) => q.eq('class', 'emerging').order('emerging_p'), 30);
    final famousRows = await cycles((q) => q.eq('class', 'famous').order('first_count', ascending: false), 30);

    final rowsByCode = <String, Map<String, dynamic>>{};
    for (final r in [...regionRows, ...emergingRows, ...famousRows]) {
      rowsByCode[r['store_code'] as String] = r;
    }
    if (rowsByCode.isEmpty) return [];

    // 판매점 기본 정보 (lottery_stores, 읽기 전용)
    final codes = rowsByCode.keys.toList()..sort();
    final stores = <RegionStore>[];
    for (var i = 0; i < codes.length; i += 150) {
      final chunk = codes.sublist(i, i + 150 > codes.length ? codes.length : i + 150);
      final rows = await _db.from('lottery_stores')
          .select('dhlottery_code,store_name,address,region,latitude,longitude,first_count,second_count')
          .eq('lottery_type', 'lotto').inFilter('dhlottery_code', chunk);
      for (final r in List<Map<String, dynamic>>.from(rows as List)) {
        final lat = (r['latitude'] as num?)?.toDouble(), lng = (r['longitude'] as num?)?.toDouble();
        final ok = lat != null && lng != null && lat >= 33 && lat <= 39 && lng >= 124 && lng <= 132;
        final code = r['dhlottery_code'] as String;
        stores.add(RegionStore(
          code: code, name: (r['store_name'] as String?) ?? code, address: (r['address'] as String?) ?? '',
          region: (r['region'] as String?) ?? '', regionId: rowsByCode[code]?['region_id'] as String?,
          point: ok ? LatLng(lat, lng) : null,
          firstCount: (r['first_count'] as num?)?.toInt() ?? 0, secondCount: (r['second_count'] as num?)?.toInt() ?? 0,
        ));
      }
    }
    final regionIds = stores.map((s) => s.regionId).whereType<String>().toSet();
    final inputs = await RegionResearchRepository().loadEngineInputs(stores, regionIds);
    final ranked = RegionStoreRanker.rank(stores: stores, inputs: inputs);

    final used = <String>{};
    final picks = <MasterStorePick>[];
    void take(bool Function(RankedRegionStore r) pred, int n, String why) {
      for (final r in ranked) {
        if (picks.length >= 5 || n <= 0) return;
        if (used.contains(r.store.code) || !pred(r)) continue;
        used.add(r.store.code);
        picks.add(MasterStorePick(r, why, r.store.regionId));
        n--;
      }
    }
    final emergingCodes = emergingRows.map((r) => r['store_code']).toSet();
    final famousCodes = famousRows.map((r) => r['store_code']).toSet();
    take((r) => engineSidos.any((sd) => (r.store.regionId ?? '').startsWith('$sd|')), 2,
        'Store 엔진 이번 회차 지역 후보(${engineSidos.join(', ')}) 내 엔진 종합 상위');
    take((r) => emergingCodes.contains(r.store.code), 2, '신흥 명당 — 최근 100회 1등 급증');
    take((r) => famousCodes.contains(r.store.code), 1, '유명 명당 — 누적 1등 최상위');
    take((r) => true, 5 - picks.length, '엔진 종합 상위');
    return picks;
  }
}
