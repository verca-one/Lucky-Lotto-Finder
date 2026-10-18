// 전국 지방장 에이전트 — 공용 위젯 (관리자 전용 연구 기능)
// 최신 실전 = ag-1.1(실전형 재현 계보) → 없으면 ag-1.0. 모델 표기는 실제 조회된 행 기준.
// 가설 판정은 evidence.verdict(없으면 status 대체)로 표시한다.
//
// * showAgentStoreSheet / AgentStoreSection : 판매점 하나의 지방장 연구 근거
// * AgentCentralView                        : 중앙 엔진 주목 지역 + 전국 상위 후보
// * AgentRegionDeliverySection              : 지역(지방장) 납품 목록 + 중앙 엔진 평가
// * agentHypTile                            : 가설 한 건 표시
//
// 모든 데이터는 research_agent* 테이블 읽기 전용 조회 결과이며, 없으면 '데이터 없음'·'연구 미실행'으로 표시한다.
// 점수는 연구 기반 후보 점수(회차당 1·2등 기대 빈도, 판매량 미보정)이며 한 장당 당첨확률이 아니다.

import 'package:flutter/material.dart';

import '../screens/admin_region_research_screen.dart';
import '../services/research/agent_replay_repository.dart';
import '../services/research/agent_research_repository.dart';
import '../services/research/agent_verdicts.dart';
import '../services/route/region_research_repository.dart';
import 'admin_region_store_widgets.dart' show regionTag, hypothesisStatusColor;
import 'agent_replay_widgets.dart' show AgentFrozenRecommendation;

const Color kAgentColor = Color(0xFF00695C);

/// 중앙 엔진 '주목 지역'으로 보는 상위 순위 (live 중앙 결과는 전체 지역 순위를 담는다)
const int kAgentFocusTop = 20;

// ═══════════════════════════════════════════════════════════════════════
// 공용 표시 함수
// ═══════════════════════════════════════════════════════════════════════

/// 연구 테이블 상태 문구 (지방장 연구 전용)
String agentStateLabel(ResearchAvailability s, {String? message}) => switch (s) {
      ResearchAvailability.notApplied => kAgentNotApplied,
      ResearchAvailability.noData => kAgentNoData,
      ResearchAvailability.available => '연구 결과 있음',
      ResearchAvailability.error => '조회 오류${message == null ? '' : ': $message'}',
    };

Widget agentStateNote(ResearchAvailability s, {String? message}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: s == ResearchAvailability.error ? Colors.red.shade50 : Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        s == ResearchAvailability.notApplied
            ? '$kAgentNotApplied — research_v5_agents.sql 적용 및 서버 Worker 실행 후 표시됩니다.'
            : agentStateLabel(s, message: message),
        style: TextStyle(
            fontSize: 11.5,
            color: s == ResearchAvailability.error ? Colors.red.shade800 : Colors.blueGrey.shade800),
      ),
    );

String fmtScore(double? v) => v == null ? '-' : v.toStringAsFixed(4);
String fmtNum(dynamic v, [int d = 2]) =>
    v == null ? '-' : (v is num ? (v is int ? '$v' : v.toStringAsFixed(d)) : '$v');

/// 판정 색
MaterialColor agentVerdictColor(String v) => switch (v) {
      kVerdictPassed => Colors.green,
      kVerdictFailed => Colors.red,
      kVerdictAccumulating => Colors.teal,
      kVerdictLowSample => Colors.brown,
      _ => Colors.blueGrey,
    };

/// 판정 배지 (evidence.verdict 가 없으면 '(상태 기준)' 표시)
Widget agentVerdictTag(AgentHypothesis h) =>
    regionTag(h.verdictFromEvidence ? h.verdict : '${h.verdict} (상태 기준)', agentVerdictColor(h.verdict));

/// 판정 세부 줄들 (verdict_detail · 최소 판정 배수 · 기대 사건 수). 없으면 빈 목록.
List<String> agentVerdictDetailLines(AgentHypothesis h) {
  final out = <String>[];
  if (h.verdictDetail != null) out.add(h.verdictDetail!);
  final mdl = h.minDetectableLine;
  if (mdl != null) {
    final e = h.powerExpected;
    final k = h.powerMinK;
    final extra = e == null ? '' : ' (기대 ${e.toStringAsFixed(2)}건${k == null ? '' : ' · p<0.05 판정에 $k건 필요'})';
    out.add('$mdl$extra');
  }
  return out;
}

/// 판정 필터 칩 (null = 전체). [counts] 가 있으면 건수 표시.
Widget agentVerdictFilterChips(String? selected, ValueChanged<String?> onSelected, {Map<String, int>? counts}) =>
    SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        for (final v in <String?>[null, ...kVerdictOrder])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(v == null ? '전체 판정' : '${verdictShort(v)}${counts == null ? '' : ' ${counts[v] ?? 0}'}',
                  style: const TextStyle(fontSize: 11)),
              selected: selected == v,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onSelected(v),
            ),
          ),
      ]),
    );

/// 가설 한 건 (판정·상태·공유·발견/검증 통계·실전 반영)
Widget agentHypTile(AgentHypothesis h, {bool showOwner = true}) {
  final c = hypothesisStatusColor(h.status);
  final details = agentVerdictDetailLines(h);
  return Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(h.summary,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        const SizedBox(width: 6),
        agentVerdictTag(h),
      ]),
      const SizedBox(height: 3),
      Wrap(spacing: 4, runSpacing: 3, children: [
        regionTag('상태 ${h.statusLabel}', c),
        regionTag(h.kindLabel, Colors.blueGrey),
        if (showOwner && h.agentId.isNotEmpty) regionTag('발견 ${agentLabel(h.agentId)}', Colors.indigo),
        regionTag(h.predictive ? '예측형(다음 회차)' : '동시 연관 · 다음 회차 예측 불가',
            h.predictive ? Colors.indigo : Colors.brown),
        if (h.isShared)
          regionTag('공유받음 ← ${agentLabel(h.sharedByAgent)}', Colors.deepPurple),
        if (h.sharedToCount > 0) regionTag('공유 ${h.sharedToCount}곳', Colors.deepPurple),
        regionTag(h.discoverySignificant ? 'FDR 유의(q<0.10)' : '탐색 후보(FDR 미통과)',
            h.discoverySignificant ? Colors.teal : Colors.grey),
        if (h.liveEligible) regionTag('실전 반영 가능', Colors.green),
        if (h.isReplay && h.appliedLive) regionTag('실전 반영 ${h.appliedLiveCount}회', Colors.green),
        if (h.discoveredRound != null) regionTag('발견 ${h.discoveredRound}회 기준', Colors.blueGrey),
        if (h.isReplay) regionTag('재현 가설 ${h.replayRunId}', Colors.blueGrey),
      ]),
      const SizedBox(height: 3),
      Text('${h.trainLine}  ·  ${h.testLine}',
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800)),
      if (h.appliedLine != null)
        Text(
            '${h.appliedLine}'
            '${h.relativeRatio == null ? '' : ' · 상대비 ×${h.relativeRatio!.toStringAsFixed(2)}'}'
            '${h.kOff == null && h.eOff == null ? '' : ' · 미반영 구간 ${h.kOff ?? '-'}건 (기대 ${h.eOff == null ? '-' : h.eOff!.toStringAsFixed(2)})'}',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800)),
      for (final l in details)
        Text(l, style: TextStyle(fontSize: 10.5, color: agentVerdictColor(h.verdict).shade800)),
      if (h.isShared)
        Text('원 가설 ${h.sharedFrom}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      if (!h.verdictPassed)
        Text('검증 미통과 — 연구용 참고 정보', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 판매점 지방장 근거 (바텀시트 + 재사용 섹션)
// ═══════════════════════════════════════════════════════════════════════

Future<void> showAgentStoreSheet(BuildContext context, String storeCode, {String? name}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(name ?? '판매점 $storeCode',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text('코드 $storeCode', style: const TextStyle(fontSize: 11, color: Colors.black45)),
          AgentStoreSection(storeCode: storeCode),
          const SizedBox(height: 8),
          Text(kRegionSalesDisclaimer, style: TextStyle(fontSize: 10.5, color: Colors.red.shade700)),
        ],
      ),
    ),
  );
}

class _AgentStoreData {
  final ResearchLoad<AgentLiveRef?> target;
  final AgentStoreScore? score;
  final ResearchLoad<List<AgentDelivery>>? deliveries;
  final ResearchLoad<List<AgentDelivery>>? agentTop;
  final ResearchLoad<List<AgentHypothesis>> hyps;
  final ResearchLoad<List<AgentRelation>> relations;
  const _AgentStoreData({
    required this.target,
    required this.score,
    required this.deliveries,
    required this.agentTop,
    required this.hyps,
    required this.relations,
  });
}

/// 판매점 하나의 지방장 연구 근거 (다른 상세 시트에 끼워 넣을 수 있는 섹션)
class AgentStoreSection extends StatefulWidget {
  final String storeCode;
  const AgentStoreSection({super.key, required this.storeCode});

  @override
  State<AgentStoreSection> createState() => _AgentStoreSectionState();
}

class _AgentStoreSectionState extends State<AgentStoreSection> {
  late Future<_AgentStoreData> _future;
  final _repo = AgentResearchRepository();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(AgentStoreSection old) {
    super.didUpdateWidget(old);
    if (old.storeCode != widget.storeCode) _future = _load();
  }

  Future<_AgentStoreData> _load() async {
    final code = widget.storeCode;
    final target = await _repo.latestLive();
    AgentStoreScore? score;
    ResearchLoad<List<AgentDelivery>>? deliveries;
    ResearchLoad<List<AgentDelivery>>? agentTop;
    final ref = target.data;
    if (ref != null) {
      deliveries = await _repo.loadDeliveriesForStore(code, target: ref.target, model: ref.model);
      // 납품 행으로 지방장을 알면 그 지방장 점수 행만, 모르면 회차 전체(10분 캐시)에서 찾는다.
      final known = deliveries.data.isEmpty ? null : deliveries.data.first.agentId;
      final s = await _repo.loadStoreScores([code], ref.target,
          model: ref.model, agentIds: known == null || known.isEmpty ? null : {known});
      score = s.data[code];
      final agentId = score?.agentId ?? known;
      if (agentId != null) {
        agentTop = await _repo.loadDeliveries(agentId: agentId, target: ref.target, model: ref.model);
      }
    }
    final hyps = target.state == ResearchAvailability.notApplied
        ? ResearchLoad<List<AgentHypothesis>>(target.state, const [], message: target.message)
        : await _repo.loadHypothesesForStore(code);
    final rel = target.state == ResearchAvailability.notApplied
        ? ResearchLoad<List<AgentRelation>>(target.state, const [], message: target.message)
        : await _repo.loadRelationsForStore(code);
    return _AgentStoreData(
        target: target, score: score, deliveries: deliveries, agentTop: agentTop, hyps: hyps, relations: rel);
  }

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kAgentColor)),
      );

  Widget _l(String t, {Color? color, FontWeight? weight}) => Padding(
        padding: const EdgeInsets.only(left: 4, top: 2),
        child: Text(t, style: TextStyle(fontSize: 11.5, color: color, fontWeight: weight)),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AgentStoreData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _h('지방장 연구 (전국 지방장 에이전트)'),
            const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
          ]);
        }
        if (snap.hasError || snap.data == null) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _h('지방장 연구 (전국 지방장 에이전트)'),
            agentStateNote(ResearchAvailability.error, message: '${snap.error}'),
          ]);
        }
        return _body(snap.data!);
      },
    );
  }

  Widget _body(_AgentStoreData d) {
    final code = widget.storeCode;
    final ref = d.target.data;
    final children = <Widget>[_h(ref == null ? '지방장 연구 (전국 지방장 에이전트)' : '지방장 연구 (전국 지방장 에이전트 ${ref.model})')];
    if (ref?.fallbackNote != null) {
      children.add(_l(ref!.fallbackNote!, color: Colors.brown.shade700));
    }
    if (d.target.data == null) {
      children.add(agentStateNote(d.target.state, message: d.target.message));
      if (d.target.state == ResearchAvailability.notApplied) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
      }
    }
    final s = d.score;
    final dl = d.deliveries?.data ?? const <AgentDelivery>[];
    final delivery = dl.isEmpty ? null : dl.first;
    final agentId = s?.agentId ?? delivery?.agentId;
    final target = d.target.data?.target;
    final hyps = d.hyps.data;

    // 담당 지방장
    children.add(_h('담당 지방장'));
    children.add(_l(agentId == null ? '$kResearchNoData (점수·납품 행 없음)' : agentLabel(agentId),
        weight: FontWeight.w700));

    // 이번 회차 후보 순위 · 점수
    children.add(_h('이번 회차 후보 순위 · 점수${target == null ? '' : ' (목표 $target회)'}'));
    if (s == null) {
      children.add(_l('지방장 점수 없음 — $kResearchNoData'));
    } else {
      children.add(_l('지방장 내 ${s.agentRank}/${s.agentSize}위', weight: FontWeight.w700));
    }
    final top = d.agentTop?.data ?? const <AgentDelivery>[];
    if (delivery != null) {
      children.add(_l('지방장 납품 목록 포함 (납품 순위 ${delivery.rank}위 / ${top.isEmpty ? '-' : top.length}곳)',
          color: Colors.green.shade800));
    } else if (target != null) {
      children.add(_l('지방장 납품 목록에 없음${top.isEmpty ? '' : ' (납품 ${top.length}곳)'}'));
    }
    if (s != null || delivery != null) {
      children.add(_l('점수 ${fmtScore(s?.score ?? delivery?.score)} — $kAgentScoreLabel'));
      children.add(_l('p_first ${fmtScore(s?.pFirst ?? delivery?.pFirst)} — $kAgentPFirstLabel'));
      if (s != null) {
        children.add(_l('검증 가설 반영 계수 live_factor ${s.liveFactor.toStringAsFixed(3)}'
            '${s.liveApplied ? ' (검증 통과 가설 반영)' : ' (반영 가설 없음 = 1)'}'
            ' · 탐색 계수 explore_factor ${s.exploreFactor.toStringAsFixed(3)} (실전 미반영)'
            ' · 관련 가설 ${s.hypCount}건'));
      }
      if (delivery != null && delivery.components.isNotEmpty) {
        children.add(_l('구성: ${delivery.components.entries.map((e) => '${e.key} ${fmtNum(e.value, 4)}').join(' · ')}',
            color: Colors.black54));
      }
    }

    // 당첨 이력
    children.add(_h('당첨 이력 (지방장 납품 기록)'));
    final hist = delivery?.history ?? const <String, dynamic>{};
    if (hist.isEmpty) {
      children.add(_l('납품 이력 정보 없음 (납품 목록 밖이거나 $kResearchNoData)'));
    } else {
      children.add(_l('1등 ${hist['first'] ?? '-'}회 · 2등 ${hist['second'] ?? '-'}회'
          ' · 마지막 1·2등 ${hist['last_event_round'] ?? '-'}회'));
      final fr = hist['first_rounds'];
      if (fr is List && fr.isNotEmpty) {
        children.add(_l('최근 1등 회차: ${fr.take(10).join(', ')}'));
      }
    }

    // 당첨 주기 (납품 이력 간격 통계 + 반복 간격 가설 params)
    final cycles = hyps.where((h) => h.isCycle).toList();
    children.add(_h('당첨 주기'));
    final hasHistGap = hist['gap_mean'] != null || hist['gap_median'] != null || hist['rounds_since_last'] != null;
    if (hasHistGap) {
      children.add(_l('납품 이력 기준: 1·2등 간격 평균 ${fmtNum(hist['gap_mean'], 1)}회 · 중앙값 ${fmtNum(hist['gap_median'], 0)}회'
          ' · 마지막 당첨 후 ${hist['rounds_since_last'] ?? '-'}회'));
    }
    final gaps = hist['gaps'];
    final hasGaps = gaps is List && gaps.isNotEmpty;
    if (gaps is List && gaps.isNotEmpty) {
      children.add(_l('당첨 간격: ${gaps.take(15).join(', ')}회'));
    }
    if (!hasHistGap && !hasGaps) {
      children.add(_l('납품 이력 간격 통계 없음', color: Colors.black54));
    }
    if (cycles.isEmpty) {
      children.add(_l('반복 간격 가설: ${_noHyp(d)}'));
    } else {
      for (final h in cycles.take(4)) {
        final p = h.params;
        children.add(_l('[${h.verdict}] ${h.summary}', color: agentVerdictColor(h.verdict)));
        final gapLine = (p['gap_mean'] != null || p['gap_lo'] != null || p['gap_hi'] != null)
            ? '주기 평균 ${fmtNum(p['gap_mean'], 1)}회 · 범위 ${fmtNum(p['gap_lo'], 0)}~${fmtNum(p['gap_hi'], 0)}회'
            : '가설에 주기 값(gap_mean/gap_lo/gap_hi) 없음';
        children.add(_l(gapLine, weight: FontWeight.w700));
        final kv = <String, dynamic>{...p, ...h.evidence}
          ..removeWhere((k, v) =>
              k == 'gap_mean' || k == 'gap_lo' || k == 'gap_hi' || v is Map || (v is List && v.length > 12));
        if (kv.isNotEmpty) {
          children.add(_l(
              kv.entries
                  .take(8)
                  .map((e) => '${e.key} ${e.value is List ? (e.value as List).join(',') : fmtNum(e.value)}')
                  .join(' · '),
              color: Colors.black54));
        }
        children.add(_l(h.testLine, color: Colors.black54));
        for (final l in agentVerdictDetailLines(h)) {
          children.add(_l(l, color: Colors.black54));
        }
      }
    }

    // 타 지역 연관 판매점
    children.add(_h('타 지역 연관 판매점 (관계 그래프)'));
    final rels = d.relations.data;
    if (rels.isEmpty) {
      children.add(_l(d.relations.state == ResearchAvailability.available
          ? '연관 관계 없음'
          : agentStateLabel(d.relations.state, message: d.relations.message)));
    } else {
      children.add(_l('기준 ${rels.first.trainingEndRound}회 · 유의성과 무관하게 기록된 상위 관계 (p 오름차순)',
          color: Colors.black45));
      for (final r in rels) {
        final other = r.otherId(code);
        final otherRegion = r.otherRegion(code);
        final cross = agentId != null && otherRegion != null && otherRegion != agentId;
        final dir = r.kind.endsWith('lead') ? (r.isSource(code) ? '→ 후행' : '← 선행') : '⇄ 동시';
        children.add(_l(
            '${cross ? '[타 지역] ' : ''}${kAgentHypKindLabel[r.kind] ?? r.kind} $dir $other'
            '${otherRegion == null ? '' : ' (${agentLabel(otherRegion)})'}'
            '${r.lag == 0 ? '' : ' +${r.lag}회'} · ${r.k ?? '-'}/${r.n ?? '-'}'
            ' 기대 ${fmtNum(r.expected)} · ×${fmtNum(r.ratio)} · p=${fmtP(r.p)}',
            color: cross ? Colors.indigo.shade700 : null));
      }
    }

    // 가설 묶음 (없으면 '해당 가설 없음'을 명시)
    void hypGroup(String title, List<AgentHypothesis> l) {
      children.add(_h(title));
      if (l.isEmpty) {
        children.add(_l(_noHyp(d)));
      } else {
        children.addAll(l.take(6).map((h) => agentHypTile(h)));
        if (l.length > 6) children.add(_l('외 ${l.length - 6}건', color: Colors.black54));
      }
    }

    final cowin = hyps.where(isAgentCowinHyp).toList();
    final leadLag = hyps.where(isAgentLeadLagHyp).toList();
    final shared = hyps.where((h) => h.isShared).toList();
    hypGroup('동시 당첨 가설', cowin);
    hypGroup('선행·후행 가설 (선행·후행·확산)', leadLag);
    hypGroup('공유 가설 (다른 지방장에게서 공유받음)', shared);
    final other = hyps
        .where((h) => !h.isCycle && !isAgentCowinHyp(h) && !isAgentLeadLagHyp(h) && !h.isShared)
        .toList();
    if (other.isNotEmpty) hypGroup('기타 가설', other);

    // 검증 판정 (가설별)
    children.add(_h('검증 판정 (가설별)'));
    final counts = AgentVerdictCounts.of(hyps);
    final hypsOk = d.hyps.state == ResearchAvailability.available || d.hyps.state == ResearchAvailability.noData;
    final edge = storeEdgeWording(hypsOk ? counts : null);
    children.add(_l('${edge.kind.label} — ${edge.text}',
        color: edge.kind == StoreEdgeKind.passed ? Colors.green.shade800 : Colors.brown.shade700,
        weight: FontWeight.w700));
    if (hyps.isEmpty) {
      children.add(_l(_noHyp(d)));
    } else {
      final verdictKeys = [...kVerdictOrder, ...counts.all.keys.where((k) => !kVerdictOrder.contains(k))];
      children.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 4, runSpacing: 3, children: [
          for (final v in verdictKeys)
            if (counts.all[v] != null) regionTag('$v ${counts.all[v]}', agentVerdictColor(v)),
        ]),
      ));
      for (final h in hyps.take(20)) {
        children.add(_l(
            '[${h.verdict}] ${h.kindLabel} · ${h.summary} — ${h.testLine}'
            '${h.isReplay && h.appliedLive ? ' · 실전 반영 ${h.appliedLiveCount}회' : ''}'
            '${h.minDetectableLine == null ? '' : ' · ${h.minDetectableLine}'}',
            color: agentVerdictColor(h.verdict)));
      }
      if (hyps.length > 20) children.add(_l('외 ${hyps.length - 20}건', color: Colors.black54));
    }
    if (delivery != null && delivery.verification.isNotEmpty) {
      children.add(_l('납품 검증 표시: ${delivery.verification}'));
    }

    // 기준 회차·출처
    children.add(_h('기준 회차 · 데이터 출처'));
    final ter = s?.trainingEndRound ?? delivery?.trainingEndRound;
    children.add(_l('학습 기준 ${ter == null ? '-' : '$ter회'}까지 데이터 · 목표 ${target ?? '-'}회 · 모델 ${agentModelLabel(ref?.model)}'));
    final replayHyps = hyps.any((h) => h.isReplay);
    final scoreSrc = s == null
        ? '점수 행 없음 (research_agent_score_sets · research_agent_store_scores 조회)'
        : (s.fromScoreSet ? 'research_agent_score_sets (압축 저장)' : 'research_agent_store_scores');
    final runIds = hyps.map((h) => h.replayRunId).whereType<String>().toSet();
    final hypSrc = replayHyps
        ? 'research_replay_hypotheses (${runIds.join(', ')})'
        : (hyps.isEmpty
            ? 'research_replay_hypotheses → 없으면 research_agent_hypotheses'
            : 'research_agent_hypotheses ($kAgentModelLegacy)');
    children.add(_l(
        '출처: 점수 $scoreSrc · research_agent_deliveries · 가설 $hypSrc'
        ' · 관계 research_agent_relations ($kAgentModelLegacy) (읽기 전용)',
        color: Colors.black45));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  /// 가설이 없을 때 문구 (조회 상태가 정상이 아니면 상태도 함께)
  String _noHyp(_AgentStoreData d) =>
      d.hyps.state == ResearchAvailability.available || d.hyps.state == ResearchAvailability.noData
          ? '해당 가설 없음'
          : '해당 가설 없음 (${agentStateLabel(d.hyps.state, message: d.hyps.message)})';
}

/// 판매점 동시 당첨 가설 (store_cowin, region_cowin)
bool isAgentCowinHyp(AgentHypothesis h) => h.isCowin;

/// 선행·후행·확산 가설 (store_lead, region_store_lead, region_lead, store_spill, neighbor_spill)
bool isAgentLeadLagHyp(AgentHypothesis h) =>
    h.isLeadLag || h.kind == 'store_spill' || h.kind == 'neighbor_spill';

// ═══════════════════════════════════════════════════════════════════════
// 중앙 엔진 (주목 지역 + 전국 상위 후보)
// ═══════════════════════════════════════════════════════════════════════

void openRegionResearch(BuildContext context, String regionId) {
  Navigator.push(
    context,
    MaterialPageRoute(
        builder: (_) => AdminRegionResearchScreen(initialTab: 1, initialRegion: regionId)),
  );
}

Widget agentFocusRegionRow(BuildContext context, AgentFocusRegion f) => InkWell(
      onTap: f.regionId.isEmpty || f.regionId == 'internet' ? null : () => openRegionResearch(context, f.regionId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(
              width: 26,
              child: Text('${f.rank ?? '-'}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kAgentColor))),
          Expanded(
              child: Text(agentLabel(f.regionId),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
          Text('p ${fmtNum(f.p, 3)} · 기준 ${fmtNum(f.base, 3)} · ×${fmtNum(f.ratio)}'
              '${f.factor == null || (f.factor! - 1).abs() < 1e-9 ? '' : ' · 가설 ×${fmtNum(f.factor)}'}',
              style: const TextStyle(fontSize: 11)),
          const Icon(Icons.chevron_right, size: 16, color: Colors.black38),
        ]),
      ),
    );

Widget agentCentralStoreRow(BuildContext context, AgentCentralStore s, int index) => InkWell(
      onTap: s.storeCode.isEmpty ? null : () => showAgentStoreSheet(context, s.storeCode, name: s.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 26,
              child: Text('$index',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kAgentColor))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.display, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              Text(
                  '${agentLabel(s.agentId)}${s.agentRank == null ? '' : ' ${s.agentRank}위'}'
                  ' · 점수 ${fmtScore(s.score)} · p_first ${fmtScore(s.pFirst)}',
                  style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
              if (s.reason != null)
                Text(s.reason!, style: const TextStyle(fontSize: 10.5, color: Colors.black87)),
            ]),
          ),
          if (s.verification != null) ...[
            const SizedBox(width: 4),
            regionTag(s.verification!,
                s.verification!.contains('검증 가설 반영') ? Colors.green : Colors.grey),
          ],
        ]),
      ),
    );

/// research_agent_central (최신 live 목표 회차) — 주목 지역 + 전국 상위 후보
class AgentCentralView extends StatefulWidget {
  final int maxStores;
  final bool scrollable;

  /// null = 최신 실전 자동 (ag-1.1 → 없으면 ag-1.0)
  final String? model;
  const AgentCentralView({super.key, this.maxStores = 30, this.scrollable = true, this.model});

  @override
  State<AgentCentralView> createState() => _AgentCentralViewState();
}

class _AgentCentralViewState extends State<AgentCentralView> {
  final _repo = AgentResearchRepository();
  late Future<ResearchLoad<AgentCentral?>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.loadLatestCentral(model: widget.model);
  }

  void _refresh() => setState(() { _future = _repo.loadLatestCentral(force: true, model: widget.model); });

  Widget _card(String title, List<Widget> body, {Widget? trailing}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kAgentColor.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kAgentColor))),
            ?trailing,
          ]),
          const SizedBox(height: 6),
          ...body,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ResearchLoad<AgentCentral?>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        final load = snap.data;
        final c = load?.data;
        final children = <Widget>[];
        if (c == null) {
          children.add(_card('중앙 엔진', [
            agentStateNote(load?.state ?? ResearchAvailability.error,
                message: load?.message ?? '${snap.error}'),
          ], trailing: IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh, size: 18))));
        } else {
          children.add(_card('중앙 엔진 · 목표 ${c.targetRound}회 (${c.mode})', [
            Text('모델 ${agentModelLabel(c.modelVersion)}'
                '${widget.model == null && c.modelVersion == kAgentModelLegacy ? ' — 상위 모델 실전 납품이 없어 대체 표시' : ''}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
            Text('학습 기준 ${c.trainingEndRound ?? '-'}회까지 · 납품 지방장 ${c.agentsDelivered}명'
                ' · 실전 반영 검증 가설 ${c.liveHypotheses}건',
                style: const TextStyle(fontSize: 11.5)),
            const SizedBox(height: 2),
            Text(
                c.liveHypotheses == 0
                    ? '검증 통과 가설이 실전 반영되지 않았습니다 — 이력 기반 후보입니다.'
                    : '검증 통과 가설 ${c.liveHypotheses}건이 실전 반영됐습니다 — 그래도 당첨 보장 아님.',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c.liveHypotheses == 0 ? Colors.brown.shade700 : Colors.green.shade800)),
          ], trailing: IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh, size: 18))));
          children.add(_card('주목 지역 (지역 후보 평가)', [
            if (c.focusRegions.isEmpty) const Text(kResearchNoData, style: TextStyle(fontSize: 12)),
            for (final f in c.focusRegions.take(20)) agentFocusRegionRow(context, f),
            if (c.focusRegions.length > 20)
              Text('상위 20곳 표시 (평가 지역 ${c.focusRegions.length}곳)',
                  style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
            const SizedBox(height: 4),
            const Text('p = 지역 단위 회차당 1등 발생 추정, 기준 = 판매점 수 비례 기준, × = p/기준. 판매량 미보정. 탭하면 지역 연구로 이동합니다.',
                style: TextStyle(fontSize: 10, color: Colors.black45)),
          ]));
          children.add(_card('전국 상위 후보 판매점 (판매점 후보 평가)', [
            if (c.storeTop.isEmpty) const Text(kResearchNoData, style: TextStyle(fontSize: 12)),
            for (var i = 0; i < c.storeTop.length && i < widget.maxStores; i++)
              agentCentralStoreRow(context, c.storeTop[i], i + 1),
            const SizedBox(height: 4),
            const Text('점수 = $kAgentScoreLabel. 한 장당 당첨확률이 아닙니다. 탭하면 지방장 근거를 봅니다.',
                style: TextStyle(fontSize: 10, color: Colors.black45)),
          ]));
        }
        if (!widget.scrollable) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
        }
        return ListView(padding: const EdgeInsets.all(12), children: children);
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 지역(지방장) 납품 + 중앙 평가
// ═══════════════════════════════════════════════════════════════════════

class AgentRegionDeliverySection extends StatefulWidget {
  final String regionId;
  const AgentRegionDeliverySection({super.key, required this.regionId});

  @override
  State<AgentRegionDeliverySection> createState() => _AgentRegionDeliverySectionState();
}

class _AgentRegionDeliverySectionState extends State<AgentRegionDeliverySection> {
  final _repo = AgentResearchRepository();
  final _replay = AgentReplayRepository();
  late Future<(ResearchLoad<AgentLiveRef?>, ResearchLoad<List<AgentDelivery>>?, AgentCentral?)> _future;
  late Future<ResearchLoad<List<ReplayPrediction>>> _rounds;

  /// null = 최신 실전, 값 = 과거 목표 회차 (당시 동결된 추천)
  int? _round;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _rounds = _replay.loadRounds();
  }

  @override
  void didUpdateWidget(AgentRegionDeliverySection old) {
    super.didUpdateWidget(old);
    if (old.regionId != widget.regionId) {
      _future = _load();
      _round = null;
    }
  }

  Future<(ResearchLoad<AgentLiveRef?>, ResearchLoad<List<AgentDelivery>>?, AgentCentral?)> _load() async {
    final t = await _repo.latestLive();
    final ref = t.data;
    if (ref == null) return (t, null, null);
    final d = await _repo.loadDeliveries(agentId: widget.regionId, target: ref.target, model: ref.model);
    final c = await _repo.loadCentral(ref.target, model: ref.model);
    return (t, d, c.data);
  }

  Widget _selector() => FutureBuilder<ResearchLoad<List<ReplayPrediction>>>(
        future: _rounds,
        builder: (context, snap) {
          final rounds = (snap.data?.data ?? const <ReplayPrediction>[]).reversed.toList();
          final state = snap.data?.state;
          return Row(children: [
            const Text('기준 회차  ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
            Expanded(
              child: DropdownButton<int?>(
                isExpanded: true,
                isDense: true,
                value: rounds.any((p) => p.targetRound == _round) ? _round : null,
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('최신 실전 (추천 기본값)', style: TextStyle(fontSize: 12))),
                  for (final p in rounds)
                    DropdownMenuItem<int?>(
                      value: p.targetRound,
                      child: Text(
                          '${p.targetRound}회 · ${replayModeShort(p.replayMode)}'
                          ' · ${p.availableThrough ?? '-'}회까지 데이터',
                          style: const TextStyle(fontSize: 12)),
                    ),
                ],
                onChanged: (v) => setState(() => _round = v),
              ),
            ),
            if (snap.connectionState != ConnectionState.done)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else if (rounds.isEmpty)
              Tooltip(
                message: state == null ? kReplayNoData : replayStateLabel(state, message: snap.data?.message),
                child: const Icon(Icons.info_outline, size: 16, color: Colors.black38),
              ),
          ]);
        },
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.teal.shade50.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kAgentColor.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _selector(),
        const SizedBox(height: 6),
        if (_round != null)
          AgentFrozenRecommendation(
              key: ValueKey('frozen_${widget.regionId}_$_round'), regionId: widget.regionId, targetRound: _round!)
        else
          _live(),
      ]),
    );
  }

  Widget _live() => FutureBuilder<(ResearchLoad<AgentLiveRef?>, ResearchLoad<List<AgentDelivery>>?, AgentCentral?)>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('지방장 납품', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kAgentColor)),
              Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
            ]);
          }
          if (snap.hasError || snap.data == null) {
            return agentStateNote(ResearchAvailability.error, message: '${snap.error}');
          }
          final (t, d, c) = snap.data!;
          final ref = t.data;
          final children = <Widget>[
            Text(
                '지방장 납품${ref == null ? '' : ' (최신 실전 · 목표 ${ref.target}회 · ${ref.model})'} — ${RegionIds.display(widget.regionId)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kAgentColor)),
            const SizedBox(height: 4),
          ];
          if (ref == null) {
            children.add(agentStateNote(t.state, message: t.message));
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
          }
          if (ref.fallbackNote != null) {
            children.add(Text(ref.fallbackNote!, style: TextStyle(fontSize: 11, color: Colors.brown.shade700)));
          }
          // 중앙 엔진 평가
          final f = c?.focusOf(widget.regionId);
          final top = f != null && (f.rank ?? 999) <= kAgentFocusTop;
          final evalText = f == null
              ? ''
              : '${f.rank ?? '-'}위 / ${c!.focusRegions.length}곳 · p ${fmtNum(f.p, 3)} · 기준 ${fmtNum(f.base, 3)} · ×${fmtNum(f.ratio)}';
          children.add(Text(
              c == null
                  ? '중앙 엔진 결과 없음 ($kResearchNoData)'
                  : (f == null
                      ? '중앙 엔진 상위 지역 아님 (평가 목록 ${c.focusRegions.length}곳에 없음)'
                      : (top ? '중앙 엔진 주목 지역 $evalText' : '중앙 엔진 상위 지역 아님 ($evalText)')),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: top ? Colors.green.shade800 : Colors.brown.shade700)));
          final list = d?.data ?? const <AgentDelivery>[];
          if (list.isEmpty) {
            children.add(agentStateNote(d?.state ?? ResearchAvailability.noData, message: d?.message));
          } else {
            for (final x in list.take(15)) {
              children.add(InkWell(
                onTap: () => showAgentStoreSheet(context, x.storeCode, name: x.storeName),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                        width: 24,
                        child: Text('${x.rank}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kAgentColor))),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        Text('점수 ${fmtScore(x.score)} · p_first ${fmtScore(x.pFirst)}'
                            ' · 실전 적용 가설 ${x.appliedHypothesisCount}건 · 발화 ${x.firingHypothesisCount}건 / 관련 ${x.hypotheses.length}건',
                            style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
                      ]),
                    ),
                    regionTag(x.verification.isEmpty ? '-' : x.verification,
                        x.verification.contains('검증 가설 반영') ? Colors.green : Colors.grey),
                  ]),
                ),
              ));
            }
            if (list.length > 15) {
              children.add(Text('외 ${list.length - 15}곳', style: const TextStyle(fontSize: 11)));
            }
          }
          children.add(const SizedBox(height: 4));
          children.add(const Text('점수 = $kAgentScoreLabel. 한 장당 당첨확률이 아닙니다.',
              style: TextStyle(fontSize: 10, color: Colors.black45)));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
        },
      );
}


// ═══════════════════════════════════════════════════════════════════════
// 성능 요약 (브리핑 payload.performance / research_agents.performance)
// ═══════════════════════════════════════════════════════════════════════

const Map<String, String> kAgentPerfLabels = {
  'agent_hits_live': '지방장 실전 목록 1·2등 적중 (검증 가설만 반영)',
  'agent_hits_first': '지방장 실전 목록 1등 적중',
  'agent_hits_history': '지방장 이력 기준 목록 적중',
  'agent_hits_explore': '지방장 탐색 목록 적중 (연구 중 가설 포함)',
  'expected_uniform': '무작위 같은 수 선택 시 기대 적중',
  'total_events': '실제 1·2등 판매점 수',
  'n_rounds': 'backtest 회차 수',
  'central_store_hits': '중앙 상위 판매점 1·2등 적중',
  'central_store_hits_first': '중앙 상위 판매점 1등 적중',
  'central_store_hits_history': '중앙 이력 기준 판매점 적중',
  'central_store_expected_uniform': '중앙 판매점 무작위 기대 적중',
  'central_region_hits': '중앙 주목 지역 적중',
  'central_region_hits_m0': '중앙 주목 지역 적중 (판매점 수 기준 m0)',
  'central_region_expected': '중앙 주목 지역 기대 적중',
  'live_rounds_evaluated': '실전(live) 평가 회차 수',
  'backtest_rounds': 'backtest 평가 회차',
  'hits_any': '실전 목록 1·2등 적중',
  'hits_first': '실전 목록 1등 적중',
  'explore_hits_any': '탐색 목록 적중',
  'history_hits_any': '이력 기준 목록 적중',
  'region_events': '지역 실제 1·2등 판매점 수',
  'region_first': '지역 실제 1등 판매점 수',
  'lift_vs_uniform': '무작위 기대 대비 배수',
  'multi_condition': '다중 조건 검증',
  'rounds': 'backtest 평가 회차',
};

/// 성능 맵을 사람이 읽는 줄로 (알 수 없는 키는 그대로 표시). ag-1.1 형식이면 [replayPerformanceLines].
List<String> agentPerformanceLines(Map<String, dynamic> perf) {
  if (ReplayPerformance.isReplayShape(perf)) return replayPerformanceLines(ReplayPerformance(perf));
  final out = <String>[];
  final rounds = perf['rounds'];
  final live = perf['live_rounds_evaluated'];
  if (rounds is List && rounds.isNotEmpty) {
    out.add('backtest(사후 순차 재현) ${rounds.first}~${rounds.last}회'
        '${perf['n_rounds'] == null ? '' : ' (${perf['n_rounds']}회차)'} — 아래 적중 수치는 backtest 기준');
  }
  out.add(live == null
      ? '실전(live, 추첨 전 저장 납품) 평가 기록 없음'
      : '실전(live, 추첨 전 저장 납품) 평가 $live회차${live == 0 ? ' — 아직 실전 검증 없음' : ''}');
  for (final e in perf.entries) {
    if (e.key == 'rounds' || e.key == 'live_rounds_evaluated' || e.key == 'n_rounds') continue;
    if (e.value == null) continue;
    if (e.key == 'central_logloss' && e.value is Map) {
      final m = Map<String, dynamic>.from(e.value as Map);
      out.add('중앙 지역 log-loss: 모델 ${fmtNum(m['model'], 4)} · m0(판매점 수 비례) ${fmtNum(m['m0'], 4)}'
          ' · m1(지역 빈도) ${fmtNum(m['m1'], 4)} (낮을수록 좋음)');
      continue;
    }
    if (e.key == 'multi_condition' && e.value is Map) {
      const names = {'ge2': '조건 2개 이상', 'one': '조건 1개', 'none': '조건 없음'};
      final m = Map<String, dynamic>.from(e.value as Map);
      final parts = <String>[];
      m.forEach((k, v) {
        if (v is Map) {
          parts.add('${names[k] ?? k} ${v['k'] ?? '-'}/${v['n'] ?? '-'} (기대 ${fmtNum(v['expected'])})');
        }
      });
      out.add('다중 조건 검증: ${parts.join(' · ')}');
      continue;
    }
    if (e.value is Map || e.value is List) {
      final txt = '${e.value}';
      out.add('${kAgentPerfLabels[e.key] ?? e.key}: ${txt.length > 160 ? '${txt.substring(0, 160)}…' : txt}');
      continue;
    }
    out.add('${kAgentPerfLabels[e.key] ?? e.key}: ${fmtNum(e.value)}');
  }
  return out;
}

String _n(num? v, [int d = 2]) => v == null ? '-' : (v is int ? '$v' : v.toStringAsFixed(d));

const Map<String, String> kReplayBaselineLabels = {
  'random_in_region': '지역 내 무작위',
  'store_count': '판매점 수 비례',
  'sales_volume': '판매량 비례',
  'history_only': '이력만',
};

/// 기준선 값 표시: 숫자 / 문자열(예: '데이터 미확보 …') / {hits, expected_uniform, lift} 맵
String replayBaselineValue(dynamic v) {
  if (v == null) return '-';
  if (v is num) return _n(v);
  if (v is String) return v;
  if (v is Map) {
    final m = Map<String, dynamic>.from(v);
    final h = m['hits'], e = m['expected'] ?? m['expected_uniform'], l = m['lift'];
    if (h != null || e != null || l != null) {
      return '${h ?? '-'}/${e is num ? _n(e) : (e ?? '-')}${l is num ? ' ×${_n(l)}' : ''}';
    }
    return m.entries.map((x) => '${x.key} ${x.value is num ? _n(x.value as num) : x.value}').join(', ');
  }
  return '$v';
}

/// ag-1.1 research_agents.performance → 표시 줄 (값 없으면 '-', 추정값 없음)
List<String> replayPerformanceLines(ReplayPerformance p) {
  final out = <String>[];
  out.add('실전형 재현 평가 ${_n(p.rounds)}회차 · 납품 ${_n(p.delivered)}건 (사후 재현 + 실전 회차 합산)');
  out.add('1·2등 적중 ${_n(p.hitsAny)}건 (1등 ${_n(p.hitsFirst)}) · 무작위 기대 ${_n(p.expectedUniform)}건'
      ' · 모델 기대 ${_n(p.expectedModel)}건');
  out.add('무작위 대비 배수(lift) ${p.liftVsUniform == null ? '-' : '×${_n(p.liftVsUniform)}'}'
      ' · 모델 기대 대비 ${p.hitsVsModel == null ? '-' : '×${_n(p.hitsVsModel)}'}'
      ' · log-loss 기술 점수 ${_n(p.llSkill, 4)} (0 초과면 기준 모델보다 나음)');
  out.add('비교 기준: 이력 기준 목록 적중 ${_n(p.historyHits)}건 · 탐색 목록 적중 ${_n(p.exploreHits)}건');
  final top = p.top;
  if (top.isNotEmpty) {
    final parts = top.entries.map((e) => '${e.key}위 안 ${_n(e.value.hits)}/${_n(e.value.expectedUniform)}'
        '${e.value.lift == null ? '' : ' ×${_n(e.value.lift)}'}');
    out.add('상위 N위 적중 (적중/무작위 기대): ${parts.join(' · ')}');
  }
  if (p.contribution.isNotEmpty) {
    out.add('적중 기여: 검증 가설 반영 ${_n(p.verifiedHypothesesHits)}건 · 미검증 신호 ${_n(p.unverifiedSignalsHits)}건'
        '${p.contributionNote == null ? '' : ' — ${p.contributionNote}'}');
  }
  final bl = p.baselines;
  if (bl.isNotEmpty) {
    final parts = bl.entries.map((e) => '${kReplayBaselineLabels[e.key] ?? e.key} ${replayBaselineValue(e.value)}');
    out.add('비교 기준선: ${parts.join(' · ')}');
  }
  final rec = p.recent;
  if (rec.isNotEmpty) {
    out.add('최근 구간: ${rec.entries.map((e) => '${e.key}회 ${_n(e.value.hitsAny)}/${_n(e.value.expectedUniform)}'
        '${e.value.lift == null ? '' : ' ×${_n(e.value.lift)}'} skill ${_n(e.value.llSkill, 3)}').join(' · ')}');
  }
  final h = p.hypotheses;
  if (h.isNotEmpty) {
    out.add('가설: ${h.entries.map((e) => '${kAgentHypStatusLabel[e.key] ?? e.key} ${e.value}').join(' · ')}');
  }
  if (p.sharedOut != null || p.sharedInCount != null) {
    out.add('공유: 내보냄 ${_n(p.sharedOut)} · 받음 ${_n(p.sharedInCount)}'
        '${p.sharedInMeanRatio == null ? '' : ' (평균 상대비 ×${_n(p.sharedInMeanRatio)})'}'
        '${p.sharedInByStatus.isEmpty ? '' : ' · ${p.sharedInByStatus.entries.map((e) => '${kAgentHypStatusLabel[e.key] ?? e.key} ${e.value}').join(', ')}'}');
  }
  if (p.dataQuality.isNotEmpty) {
    out.add('데이터: 지역 1·2등 ${_n(p.regionEvents)}건 · 판매점 ${_n(p.stores)}곳'
        '${p.sampleFlag == null ? '' : ' · sample_flag ${p.sampleFlag}'}');
  }
  final w = p.sampleWarning;
  if (w != null) out.add(w);
  return out;
}

class AgentPerformanceView extends StatelessWidget {
  final Map<String, dynamic> performance;
  const AgentPerformanceView({super.key, required this.performance});

  @override
  Widget build(BuildContext context) {
    if (performance.isEmpty) {
      return const Text('성능 기록 없음 ($kResearchNoData)', style: TextStyle(fontSize: 11.5));
    }
    final lines = agentPerformanceLines(performance);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final l in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text('• $l', style: const TextStyle(fontSize: 11.5)),
        ),
      const SizedBox(height: 4),
      Text(
          ReplayPerformance.isReplayShape(performance)
              ? '실전형 재현 수치는 대부분 사후 재현(해당 회차 이전 데이터만 사용, 추첨 이후 계산) 회차입니다. '
                  '적중 건수만으로 지방장을 비교하지 말고 무작위 기대·lift·skill 과 표본 경고를 함께 보세요. $kReplaySalesCaution'
              : kAgentBacktestCaution,
          style: TextStyle(fontSize: 10.5, color: Colors.brown.shade700)),
    ]);
  }
}
