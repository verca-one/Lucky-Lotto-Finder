// 추천 판매점별 지방장 근거 묶음 — 화면에 보이는 판매점 목록을 한 번에 조회 (읽기 전용)
//
// 판매점마다: 담당 지방장 + 그 지방장의 실전형 재현 검증 기록(research_agents.performance, 현재 모델),
// 점수에 실제 반영된 검증 가설(live_factor ≠ 1), 관련 가설 판정 수(research_replay_hypotheses
// related_stores ov {codes}, 현재 실행), 중앙 엔진의 지역 평가(live 중앙 결과 focus_regions),
// 미검증 연구 신호(explore_factor · 발화 가설 수, 순위 미반영).
//
// 조회 실패는 각 항목별로 '데이터 없음' 처리하며 값을 만들어내지 않는다.

import '../route/region_research_repository.dart' show RankedRegionStore, RegionIds, ResearchAvailability, ResearchLoad;
import 'agent_replay_repository.dart';
import 'agent_research_repository.dart';
import 'agent_verdicts.dart';

const String kCentralFocusIndependence =
    '판매점 목록 순위는 판매점 점수로 정해지며 중앙 엔진의 지역 주목 평가와 독립적입니다. '
    '그래서 주목 지역 밖 판매점도 목록에 나올 수 있습니다.';

const String kUnverifiedSignalLabel = '미검증 연구 신호 (검증 미통과 · 순위 미반영)';

/// 판매점 하나의 근거
class AgentStoreEvidence {
  final String code;
  final String? agentId;
  final AgentStoreScore? score;
  final AgentInfo? agent;
  final AgentFocusRegion? focus;
  final AgentDelivery? delivery;

  /// null = 가설 조회 불가
  final List<AgentHypothesis>? hypotheses;
  final AgentEvidenceBundle bundle;

  const AgentStoreEvidence({
    required this.code,
    required this.bundle,
    this.agentId,
    this.score,
    this.agent,
    this.focus,
    this.delivery,
    this.hypotheses,
  });

  AgentVerdictCounts? get counts => hypotheses == null ? null : AgentVerdictCounts.of(hypotheses!);

  StoreEdgeWording get edge => storeEdgeWording(counts, verifiedRounds: bundle.run?.verifiedRounds);

  ReplayPerformance? get performance => agent == null || agent!.performance.isEmpty
      ? null
      : ReplayPerformance(agent!.performance);

  bool get liveApplied => score?.liveApplied ?? false;

  /// 점수에 실제 반영된 가설 (live_factor ≠ 1 일 때만). 반영 없으면 빈 목록.
  List<String> get appliedHypotheses {
    final s = score;
    if (s == null || !s.liveApplied) return const [];
    final out = <String>[];
    final d = delivery;
    if (d != null) {
      for (final h in d.hypotheses) {
        if (h['applied_live'] == true || h['applied'] == true) {
          final f = h['factor_live'] ?? h['factor'];
          out.add('${h['summary'] ?? kAgentHypKindLabel[h['kind']] ?? h['kind'] ?? '-'}'
              '${f == null ? '' : ' ×$f'}');
        }
      }
    }
    if (out.isEmpty && hypotheses != null) {
      for (final h in hypotheses!) {
        if (h.verdictPassed && h.appliedLive) out.add('${h.summary} [${h.verdict}]');
      }
    }
    if (out.isEmpty) out.add('live_factor ×${s.liveFactor.toStringAsFixed(3)} 반영 (반영 가설 목록 데이터 없음)');
    return out;
  }

  /// 이번 회차 발화(조건 충족)했지만 검증 미통과라 실전 미반영인 가설 수 (납품 행이 있을 때만)
  int? get firingCount => delivery?.firingHypothesisCount;
}

/// 판매점의 지방장 id (region_id, 인터넷 판매점은 'internet', 판정 불가면 null)
String? agentIdOfStore({required String? regionId, required String region, required String address}) =>
    regionId ?? (RegionIds.isInternet(region, address) ? 'internet' : null);

/// RankedRegionStore 목록 → 근거 묶음 (지방장 점수는 이미 있는 값을 재사용)
Future<AgentEvidenceBundle> loadEvidenceForRanked(List<RankedRegionStore> items) => AgentEvidenceBundle.load(
      [
        for (final i in items)
          (i.store.code, agentIdOfStore(regionId: i.store.regionId, region: i.store.region, address: i.store.address)),
      ],
      scores: {
        for (final i in items)
          if (i.agentScore != null) i.store.code: i.agentScore!,
      },
    );

class AgentEvidenceBundle {
  final ResearchLoad<AgentLiveRef?> live;
  final AgentCentral? central;
  final String? runId;
  final ReplayRun? run;
  final ResearchLoad<Map<String, AgentInfo>>? agents;
  final ResearchLoad<Map<String, List<AgentHypothesis>>>? hyps;
  final Map<String, AgentDelivery> deliveries;
  final Map<String, AgentStoreScore> scores;
  final Map<String, String?> agentIds;

  const AgentEvidenceBundle({
    required this.live,
    this.central,
    this.runId,
    this.run,
    this.agents,
    this.hyps,
    this.deliveries = const {},
    this.scores = const {},
    this.agentIds = const {},
  });

  AgentLiveRef? get ref => live.data;
  bool get available => ref != null;

  AgentStoreEvidence of(String code, {String? agentId}) {
    final s = scores[code];
    final d = deliveries[code];
    final aid = s?.agentId ?? agentId ?? agentIds[code] ?? d?.agentId;
    final hypsOk = hyps != null &&
        (hyps!.state == ResearchAvailability.available || hyps!.state == ResearchAvailability.noData);
    return AgentStoreEvidence(
      code: code,
      bundle: this,
      agentId: aid,
      score: s,
      agent: aid == null ? null : agents?.data[aid],
      focus: aid == null ? null : central?.focusOf(aid),
      delivery: d,
      hypotheses: hypsOk ? (hyps!.data[code] ?? const <AgentHypothesis>[]) : null,
    );
  }

  /// [stores] = (판매점 코드, 지방장 id = region_id 또는 'internet'). [scores] 가 이미 있으면 재조회하지 않는다.
  static Future<AgentEvidenceBundle> load(
    List<(String, String?)> stores, {
    Map<String, AgentStoreScore> scores = const {},
    AgentResearchRepository? repo,
  }) async {
    final r = repo ?? AgentResearchRepository();
    final codes = stores.map((e) => e.$1).where((c) => c.isNotEmpty).toSet().toList()..sort();
    final ids = <String, String?>{for (final e in stores) e.$1: e.$2};
    final live = await r.latestLive();
    final ref = live.data;
    if (ref == null || codes.isEmpty) {
      return AgentEvidenceBundle(live: live, scores: scores, agentIds: ids);
    }
    AgentCentral? central;
    try {
      central = (await r.loadCentral(ref.target, model: ref.model)).data;
    } catch (_) {}

    // 점수 (없는 코드만)
    final sc = <String, AgentStoreScore>{...scores};
    final missing = codes.where((c) => !sc.containsKey(c)).toList();
    if (missing.isNotEmpty) {
      try {
        final l = await r.loadStoreScores(missing, ref.target,
            model: ref.model, agentIds: AgentResearchRepository.agentIdsOf(missing.map((c) => ids[c])));
        sc.addAll(l.data);
      } catch (_) {}
    }
    final agentIds = <String>{
      for (final c in codes) ?(sc[c]?.agentId ?? ids[c]),
    }..removeWhere((e) => e.isEmpty);

    // 재현 실행 (검증 회차 범위)
    final runId = await AgentReplayRepository.resolveCurrentRunId();
    ReplayRun? run;
    try {
      run = (await AgentReplayRepository(runId: runId).loadRun()).data;
    } catch (_) {}

    ResearchLoad<Map<String, AgentInfo>>? agents;
    try {
      agents = await r.loadAgentsByIds(agentIds, model: ref.model);
    } catch (_) {}

    final deliveries = <String, AgentDelivery>{};
    try {
      final d = await r.loadDeliveriesForAgents(agentIds, target: ref.target, model: ref.model);
      for (final x in d.data) {
        deliveries.putIfAbsent(x.storeCode, () => x);
      }
    } catch (_) {}

    ResearchLoad<Map<String, List<AgentHypothesis>>>? hyps;
    try {
      final hr = await r.hypothesisRunId();
      hyps = await r.loadHypothesesForStores(codes, runId: hr);
    } catch (_) {}

    return AgentEvidenceBundle(
      live: live,
      central: central,
      runId: runId,
      run: run,
      agents: agents,
      hyps: hyps,
      deliveries: deliveries,
      scores: sc,
      agentIds: ids,
    );
  }
}
