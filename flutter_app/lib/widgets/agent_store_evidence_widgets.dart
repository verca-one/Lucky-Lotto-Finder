// 추천 판매점별 지방장 근거 표시 (관리자 전용 연구 기능)
//
// * storeEdgeTag            : 판매점 우위 판정 칩 (검증 통과 n건 / 검증했으나 우위 미확인 / 검증하지 않음)
// * AgentEvidenceCompact    : 카드용 요약 (담당 지방장 검증 기록 · 판정 · 반영 가설 · 지역 평가 · 미검증 신호 · 추천 이유)
// * AgentEvidenceFull       : 상세 시트용 전체 (근거가 없으면 판매점 하나만 직접 조회)
//
// 모든 값은 읽기 전용 조회 결과이며, 없으면 '데이터 없음'으로 표시한다. 점수는 복권 한 장당 당첨확률이 아니다.
import 'package:flutter/material.dart';

import '../services/research/agent_replay_repository.dart';
import '../services/research/agent_research_repository.dart';
import '../services/research/agent_store_evidence.dart';
import '../services/research/agent_verdicts.dart';
import '../services/route/region_research_repository.dart';
import 'admin_region_store_widgets.dart' show regionTag;
import 'agent_store_widgets.dart' show agentVerdictColor, kAgentColor;

MaterialColor storeEdgeColor(StoreEdgeKind k) => switch (k) {
      StoreEdgeKind.passed => Colors.green,
      StoreEdgeKind.testedNoEdge => Colors.brown,
      StoreEdgeKind.notTested => Colors.blueGrey,
      StoreEdgeKind.unknown => Colors.grey,
    };

Widget storeEdgeTag(StoreEdgeWording w) => regionTag(w.kind.label, storeEdgeColor(w.kind));

String _f(num? v, [int d = 2]) => v == null ? '-' : (v is int ? '$v' : v.toStringAsFixed(d));

String _topText(ReplayTopPerf? t, String label) {
  if (t == null || t.isEmpty) return '$label 데이터 없음';
  return '$label ${_f(t.hits)}/${_f(t.expectedUniform)}${t.lift == null ? '' : ' ×${_f(t.lift)}'}';
}

/// 담당 지방장 + 실전형 재현 검증 기록 한 줄
String agentRecordLine(AgentStoreEvidence e) {
  if (e.agentId == null) return '담당 지방장: 판정 불가 (데이터 없음)';
  final name = agentLabel(e.agentId);
  final p = e.performance;
  if (p == null) return '담당 지방장 $name · 검증 기록 없음 (데이터 없음)';
  final range = e.bundle.run?.roundRange;
  final parts = <String>[
    '담당 지방장 $name',
    '검증 ${range ?? '구간 -'} · ${_f(p.rounds)}회',
    _topText(p.topAt(1), '1위'),
    _topText(p.topAt(5), '5위 안'),
    'skill ${_f(p.llSkill, 3)}',
  ];
  final flag = p.sampleFlag;
  if (flag != null) parts.add('sample_flag $flag');
  return parts.join(' · ');
}

/// 중앙 엔진의 지역 평가 한 줄
String centralRegionLine(AgentStoreEvidence e) {
  final c = e.bundle.central;
  if (c == null) return '중앙 엔진 지역 평가: 데이터 없음';
  final f = e.focus;
  if (f == null) {
    return '중앙 엔진 지역 평가: ${e.agentId == null ? '지역 미상' : '${agentLabel(e.agentId)} — 평가 목록 ${c.focusRegions.length}곳에 없음'}';
  }
  return '중앙 엔진 지역 평가: ${agentLabel(f.regionId)} ${f.rank ?? '-'}위/${c.focusRegions.length}곳'
      ' · p ${_f(f.p, 3)} · 기준 ${_f(f.base, 3)} · ×${_f(f.ratio)}';
}

/// 미검증 연구 신호 한 줄
String unverifiedSignalLine(AgentStoreEvidence e) {
  final s = e.score;
  final fc = e.firingCount;
  if (s == null && fc == null) return '$kUnverifiedSignalLabel: 데이터 없음';
  return '$kUnverifiedSignalLabel: 탐색 계수 ×${s == null ? '-' : s.exploreFactor.toStringAsFixed(3)}'
      ' · 발화 가설 ${fc == null ? '- (납품 목록 밖)' : '$fc건'}';
}

/// 점수에 반영된 검증 가설 한 줄
String appliedHypLine(AgentStoreEvidence e) {
  final s = e.score;
  if (s == null) return '점수 반영 가설: 지방장 점수 없음 (데이터 없음)';
  final l = e.appliedHypotheses;
  if (l.isEmpty) return '점수 반영 가설: 반영된 검증 가설 없음 (live_factor 1)';
  return '점수 반영 가설 (live ×${s.liveFactor.toStringAsFixed(3)}): ${l.take(3).join(' / ')}'
      '${l.length > 3 ? ' 외 ${l.length - 3}건' : ''}';
}

/// 판매점 연구 점수 한 줄 (지방장 점수)
String agentScoreLine(AgentStoreEvidence e) {
  final s = e.score;
  if (s == null) return '지방장 연구 점수: 데이터 없음';
  return '지방장 연구 점수 ${s.score.toStringAsFixed(4)} · 지방장 내 ${s.agentRank}/${s.agentSize}위'
      ' (${s.targetRound}회 목표 · 회차당 1·2등 기대 빈도, 판매량 미보정)';
}

/// 최종 추천 이유 (RegionStoreRanker 항목이 있을 때)
String finalReasonFor(AgentStoreEvidence? e, RankedRegionStore item) => finalRecommendReason(
      weights: item.weights,
      components: item.components,
      first: item.history.first == 0 && item.store.firstCount > 0 ? item.store.firstCount : item.history.first,
      second: item.history.second == 0 && item.store.secondCount > 0 ? item.store.secondCount : item.history.second,
      agentRank: (e?.score ?? item.agentScore)?.agentRank,
      agentSize: (e?.score ?? item.agentScore)?.agentSize,
      liveApplied: (e?.score ?? item.agentScore)?.liveApplied ?? false,
      edge: e?.edge,
    );

/// 카드용 요약
class AgentEvidenceCompact extends StatelessWidget {
  final AgentStoreEvidence? evidence;
  final bool loading;
  final RankedRegionStore? item;
  const AgentEvidenceCompact({super.key, this.evidence, this.loading = false, this.item});

  Widget _l(String t, {Color? color, FontWeight? weight}) => Padding(
        padding: const EdgeInsets.only(left: 2, top: 1),
        child: Text(t, style: TextStyle(fontSize: 10.5, color: color ?? Colors.black87, fontWeight: weight)),
      );

  @override
  Widget build(BuildContext context) {
    final e = evidence;
    if (e == null) {
      return _l(loading ? '지방장 근거 조회 중…' : '지방장 근거: 데이터 없음', color: Colors.black45);
    }
    final edge = e.edge;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _l(agentRecordLine(e), weight: FontWeight.w600),
      _l(edge.text, color: storeEdgeColor(edge.kind).shade800, weight: FontWeight.w700),
      _l(appliedHypLine(e)),
      _l(centralRegionLine(e)),
      _l(unverifiedSignalLine(e), color: Colors.black54),
      if (item != null) _l('최종 추천 이유: ${finalReasonFor(e, item!)}', color: kAgentColor, weight: FontWeight.w700),
    ]);
  }
}

/// 상세 시트용 전체. [evidence] 가 없으면 판매점 하나만 조회한다.
class AgentEvidenceFull extends StatefulWidget {
  final String storeCode;
  final String? agentId;
  final AgentStoreScore? score;
  final AgentStoreEvidence? evidence;
  final RankedRegionStore? item;
  const AgentEvidenceFull({super.key, required this.storeCode, this.agentId, this.score, this.evidence, this.item});

  @override
  State<AgentEvidenceFull> createState() => _AgentEvidenceFullState();
}

class _AgentEvidenceFullState extends State<AgentEvidenceFull> {
  Future<AgentStoreEvidence>? _future;

  @override
  void initState() {
    super.initState();
    if (widget.evidence == null) {
      _future = AgentEvidenceBundle.load([(widget.storeCode, widget.agentId)],
              scores: widget.score == null ? const {} : {widget.storeCode: widget.score!})
          .then((b) => b.of(widget.storeCode, agentId: widget.agentId));
    }
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
    if (widget.evidence != null) return _body(widget.evidence!);
    return FutureBuilder<AgentStoreEvidence>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _h('추천 근거 (지방장 검증 기록 · 가설 판정)'),
            const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
          ]);
        }
        if (snap.data == null) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _h('추천 근거 (지방장 검증 기록 · 가설 판정)'),
            _l('조회 오류: ${snap.error ?? kResearchNoData}', color: Colors.red.shade700),
          ]);
        }
        return _body(snap.data!);
      },
    );
  }

  Widget _body(AgentStoreEvidence e) {
    final ref = e.bundle.ref;
    final c = <Widget>[_h('추천 근거 (지방장 검증 기록 · 가설 판정)')];
    if (ref == null) {
      c.add(_l('지방장 연구 기준 회차 없음 — ${e.bundle.live.message ?? kResearchNoData}', color: Colors.brown.shade700));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: c);
    }
    c.add(_l('기준: ${agentModelLabel(ref.model)} · 목표 ${ref.target}회'
        '${e.bundle.runId == null ? '' : ' · 재현 실행 ${e.bundle.runId}'}'
        '${e.bundle.run?.roundRange == null ? '' : ' (${e.bundle.run!.roundRange} 순방향 검증)'}',
        color: Colors.black54));
    if (ref.fallbackNote != null) c.add(_l(ref.fallbackNote!, color: Colors.brown.shade700));
    final integ = e.bundle.run?.integrityLine;
    if (integ != null) c.add(_l(integ, color: Colors.black54));

    // 1) 담당 지방장 검증 기록
    c.add(_h('담당 지방장의 실전형 재현 검증 기록'));
    c.add(_l(agentRecordLine(e), weight: FontWeight.w700));
    final p = e.performance;
    if (p != null) {
      final top = p.top;
      if (top.isNotEmpty) {
        c.add(_l(top.entries
            .map((t) => '${t.key}위 안 ${_f(t.value.hits)}건 / 무작위 기대 ${_f(t.value.expectedUniform)}건'
                '${t.value.lift == null ? '' : ' (×${_f(t.value.lift)})'}')
            .join(' · ')));
      }
      c.add(_l('log-loss 기술 점수 ${_f(p.llSkill, 4)} (0 초과면 판매점 수 비례 기준보다 나음)'));
      if (p.contribution.isNotEmpty) {
        c.add(_l('적중 기여: 검증 가설 반영 ${_f(p.verifiedHypothesesHits)}건 · 미검증 신호 ${_f(p.unverifiedSignalsHits)}건'
            '${p.contributionNote == null ? '' : ' — ${p.contributionNote}'}'));
      }
      final w = p.sampleWarning;
      if (w != null) c.add(_l(w, color: Colors.orange.shade900));
    }

    // 2) 판매점 연구 점수 · 반영 가설
    c.add(_h('판매점 연구 점수 · 점수에 반영된 가설'));
    c.add(_l(agentScoreLine(e)));
    c.add(_l(appliedHypLine(e), color: e.liveApplied ? Colors.green.shade800 : Colors.brown.shade700));

    // 3) 판매점 가설 판정
    c.add(_h('판매점 가설 판정 (${e.bundle.runId ?? '재현 실행'} · 관련 가설)'));
    final edge = e.edge;
    c.add(Padding(
      padding: const EdgeInsets.only(left: 4, top: 2),
      child: Wrap(spacing: 4, runSpacing: 3, children: [
        storeEdgeTag(edge),
        if (e.counts != null)
          for (final v in kVerdictOrder)
            if ((e.counts!.storeLevel[v] ?? 0) > 0) regionTag('판매점 단위 $v ${e.counts!.storeLevel[v]}', agentVerdictColor(v)),
      ]),
    ));
    c.add(_l(edge.text, color: storeEdgeColor(edge.kind).shade800, weight: FontWeight.w700));
    if (edge.kind == StoreEdgeKind.testedNoEdge) {
      c.add(_l('= 검증은 했으나 판매점 우위가 확인되지 않음 (우위가 없다는 증명도 아님)', color: Colors.black54));
    } else if (edge.kind == StoreEdgeKind.notTested) {
      c.add(_l('= 이 판매점에 대한 판매점 단위 가설이 없어 검증하지 않음', color: Colors.black54));
    }
    if (e.counts != null && e.counts!.total > e.counts!.storeLevelTotal) {
      c.add(_l('그 외 관련 가설(지역 단위 등) ${e.counts!.total - e.counts!.storeLevelTotal}건', color: Colors.black54));
    }

    // 4) 중앙 엔진 지역 평가
    c.add(_h('중앙 엔진의 지역 평가'));
    c.add(_l(centralRegionLine(e)));
    c.add(_l(kCentralFocusIndependence, color: Colors.black54));

    // 5) 미검증 신호
    c.add(_h('미검증 연구 신호'));
    c.add(_l(unverifiedSignalLine(e)));
    c.add(_l('탐색 계수·발화 가설은 검증을 통과하지 않아 추천 순위·점수에 반영하지 않습니다.', color: Colors.black54));

    // 6) 최종 추천 이유
    final item = widget.item;
    if (item != null) {
      c.add(_h('최종 추천 이유'));
      c.add(_l(finalReasonFor(e, item), weight: FontWeight.w700, color: kAgentColor));
    }
    c.add(_l(kNotPerTicketProbability, color: Colors.red.shade700));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: c);
  }
}
