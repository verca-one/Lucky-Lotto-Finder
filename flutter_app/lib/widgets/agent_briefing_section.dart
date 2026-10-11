// 엔진 브리핑 — 전국 지방장 연구 보고 (research_agent_briefings.payload, Worker 가 DB 결과로 생성)
//
// payload 의 모든 필드는 선택적이다. 값이 없으면 '데이터 없음'으로 표시하고 추정값을 만들지 않는다.
// 점수 = 연구 기반 후보 점수(회차당 1·2등 기대 빈도, 판매량 미보정). 한 장당 당첨확률이 아니다.
import 'package:flutter/material.dart';

import '../screens/admin_agent_research_screen.dart';
import '../services/research/agent_research_repository.dart';
import '../services/research/agent_verdicts.dart';
import '../services/route/region_research_repository.dart';
import 'admin_region_store_widgets.dart' show regionTag, hypothesisStatusColor;
import 'agent_replay_widgets.dart' show AgentReplayPostSummaryCard;
import 'agent_store_widgets.dart';

class AgentBriefingSection extends StatefulWidget {
  const AgentBriefingSection({super.key});
  @override
  State<AgentBriefingSection> createState() => _AgentBriefingSectionState();
}

class _AgentBriefingSectionState extends State<AgentBriefingSection> {
  final _repo = AgentResearchRepository();
  late Future<ResearchLoad<AgentBriefing?>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.loadBriefing();
  }

  Widget _box(Widget child) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kAgentColor.withValues(alpha: 0.25)),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _briefing(context),
      const SizedBox(height: 10),
      // 실전형 재현(ag-1.1) 최신 사후 브리핑 요약 + 회차별 사전·사후 브리핑 링크
      const AgentReplayPostSummaryCard(),
    ]);
  }

  Widget _briefing(BuildContext context) {
    return FutureBuilder<ResearchLoad<AgentBriefing?>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _box(const Padding(
            padding: EdgeInsets.all(16),
            child: Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('지방장 연구 결과를 확인하고 있습니다…', style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
            ]),
          ));
        }
        final load = snap.data;
        final b = load?.data;
        if (b == null) {
          final state = load?.state ?? ResearchAvailability.error;
          return _box(Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.groups_2_outlined, color: kAgentColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state == ResearchAvailability.notApplied
                      ? kAgentNotApplied
                      : state == ResearchAvailability.noData
                          ? '지방장 연구 브리핑 없음 (서버 Worker 실행 전)'
                          : '지방장 연구 브리핑 조회 오류: ${load?.message ?? snap.error}',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
                ),
              ),
            ]),
          ));
        }
        return _box(Padding(padding: const EdgeInsets.all(14), child: _content(b)));
      },
    );
  }

  // ── 표시 도우미 ─────────────────────────────────────────────────────────

  Widget _h(String no, String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: kAgentColor, borderRadius: BorderRadius.circular(6)),
            child: Text(no, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: kAgentColor))),
        ]),
      );

  Widget _t(String s, {Color? color, double size = 11.5, FontWeight? weight}) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(s, style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.4)),
      );

  Widget _empty() => _t(kResearchNoData, color: Colors.grey.shade600);

  static Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  Widget _counts(Map<String, dynamic> counts, {Map<String, String>? labels}) {
    final entries = counts.entries.where((e) => e.value != null).toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(spacing: 4, runSpacing: 3, children: [
        for (final e in entries)
          regionTag('${labels?[e.key] ?? kAgentHypStatusLabel[e.key] ?? kAgentHypKindLabel[e.key] ?? e.key} ${e.value}',
              kAgentHypStatusLabel.containsKey(e.key) ? hypothesisStatusColor(e.key) : Colors.blueGrey),
      ]),
    );
  }

  Widget _hypRow(AgentHypothesis h) {
    final stores = h.relatedStores;
    final regions = h.relatedRegions.where((r) => r != 'internet').toList();
    VoidCallback? onTap;
    if (stores.isNotEmpty) {
      onTap = () => showAgentStoreSheet(context, stores.first);
    } else if (regions.isNotEmpty) {
      onTap = () => openRegionResearch(context, regions.first);
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.summary, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text(
                  '${h.agentId.isEmpty ? '' : '${agentLabel(h.agentId)} · '}'
                  '검증 ${h.testK ?? '-'}건 · 기대 ${h.testExpected == null ? '-' : h.testExpected!.toStringAsFixed(2)}'
                  ' · p=${fmtP(h.testP)}'
                  '${regions.isEmpty ? '' : ' · ${regions.take(3).map(agentLabel).join(', ')}'}',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
              for (final l in agentVerdictDetailLines(h))
                Text(l, style: TextStyle(fontSize: 10, color: agentVerdictColor(h.verdict).shade800)),
            ]),
          ),
          const SizedBox(width: 6),
          agentVerdictTag(h),
        ]),
      ),
    );
  }

  List<Widget> _hyps(dynamic list, {int take = 5}) {
    final l = AgentBriefing.hyps(list);
    if (l.isEmpty) return [_empty()];
    return l.take(take).map(_hypRow).toList();
  }

  // ── 지방장별 실전 검증 성과 (payload.agent_performance) ────────────────

  List<Widget> _agentPerformance(Map<String, dynamic> ap) {
    if (ap.isEmpty) return [_t('지방장별 실전 검증 성과 데이터 없음 (브리핑에 agent_performance 없음)', color: Colors.grey.shade600)];
    final out = <Widget>[];
    final dist = agentPerformanceDistributionLine(ap);
    if (dist != null) out.add(_t(dist, weight: FontWeight.w700));
    for (final l in agentPerformanceTotalsLines(ap)) {
      out.add(_t('• $l'));
    }
    Widget entries(String title, dynamic list, Color color) {
      final l = _maps(list);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _t(title, weight: FontWeight.w800, color: color),
        if (l.isEmpty) _empty(),
        for (final e in l.take(5))
          Builder(builder: (context) {
            final (line, low) = agentPerformanceEntryLine(e);
            final id = (e['agent_id'] ?? '').toString();
            return InkWell(
              onTap: id.isEmpty || id == 'internet' ? null : () => openRegionResearch(context, id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(line, style: const TextStyle(fontSize: 11, height: 1.35))),
                  if (low) ...[const SizedBox(width: 4), regionTag('표본 경고', Colors.orange)],
                ]),
              ),
            );
          }),
      ]);
    }

    out.add(const SizedBox(height: 4));
    out.add(entries('상위 지방장 (skill 기준)', ap['best'], Colors.green.shade800));
    out.add(const SizedBox(height: 4));
    out.add(entries('하위 지방장', ap['worst'], Colors.brown.shade700));
    out.add(_t('1위/5위 안 = 적중/무작위 기대. 표본 경고 = 30회 미만이거나 무작위 기대 5건 미만 — 순위로 단정하지 마세요. '
        '미검증 신호 반영 시 적중 변화는 탐색 목록(검증 미통과 가설까지 반영)과 이력만 쓴 목록의 차이입니다.',
        color: Colors.black45, size: 10));
    return out;
  }

  // ── 가설 판정 현황 (payload.hypothesis_verdicts) ──────────────────────────

  List<Widget> _hypothesisVerdicts(Map<String, dynamic> hv) {
    if (hv.isEmpty) return [_t('가설 판정 현황 데이터 없음 (브리핑에 hypothesis_verdicts 없음)', color: Colors.grey.shade600)];
    final out = <Widget>[];
    final store = storeLevelVerdictLines(hv);
    if (store.isEmpty) {
      out.add(_t('판매점 단위 판정 요약 없음', color: Colors.grey.shade600));
    } else {
      for (var i = 0; i < store.length; i++) {
        final explain = store[i].startsWith('→');
        out.add(_t(explain ? store[i] : '• ${store[i]}',
            weight: i == 0 || explain ? FontWeight.w700 : null, color: explain ? Colors.brown.shade700 : null));
      }
    }
    final kinds = verdictByKindLines(hv);
    if (kinds.isNotEmpty) {
      out.add(_t('유형별 판정', weight: FontWeight.w800));
      for (final l in kinds) {
        out.add(_t('• $l', size: 11));
      }
    }
    out.add(_t('검증 통과 = 순방향 검증에서 실제가 기대보다 유의하게 많음. 검증 실패 = 확인 안 됨. '
        '관측 누적 중 = 아직 판정할 만큼 미래 회차가 쌓이지 않음. 표본 부족 = 기대 사건이 너무 적어 판정 불가.',
        color: Colors.black45, size: 10));
    return out;
  }

  static List<Map<String, dynamic>> _maps(dynamic v) => v is List
      ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : <Map<String, dynamic>>[];

  // ── 본문 ────────────────────────────────────────────────────────────────

  Widget _content(AgentBriefing b) {
    final ag = b.agents;
    final focus = b.focusRegions;
    final top = b.topStores;
    final famous = b.famousCycles;
    final cowin = b.cowin;
    final lead = b.leadLag;
    final shared = b.shared;
    final status = b.statusCounts;
    final changes = b.rankChanges;
    final limits = b.dataLimits;
    final verified = (status['passed'] ?? 0) + (status['combined'] ?? 0);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.groups_2, color: kAgentColor, size: 20),
        const SizedBox(width: 6),
        const Expanded(
          child: Text('마스터, 지방장 연구 결과를 보고드리겠습니다.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kAgentColor)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          tooltip: '전국 지방장 연구소',
          icon: const Icon(Icons.open_in_new, color: kAgentColor),
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAgentResearchScreen())),
        ),
      ]),
      Wrap(spacing: 4, runSpacing: 3, children: [
        regionTag('목표 ${b.targetRound ?? '-'}회', kAgentColor),
        regionTag('${b.trainingEndRound ?? '-'}회까지 반영', Colors.blueGrey),
        regionTag('모델 ${b.modelVersion ?? '-'}', Colors.blueGrey),
        if (ag.isNotEmpty)
          regionTag('지방장 ${ag['completed'] ?? '-'}/${ag['total'] ?? '-'} 완료'
              '${(ag['failed'] ?? 0) == 0 ? '' : ' · 실패 ${ag['failed']}'}', Colors.indigo),
        if (ag['stores'] != null) regionTag('판매점 ${ag['stores']}곳', Colors.indigo),
        regionTag(verified > 0 ? '검증 통과 가설 $verified건' : '검증 통과 가설 없음',
            verified > 0 ? Colors.green : Colors.brown),
      ]),
      if (b.lines.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (final l in b.lines.take(8)) _t('• $l'),
      ],

      _h('1', '중앙 엔진 주목 지역'),
      if (focus.isEmpty) _empty() else ...focus.take(10).map((f) => agentFocusRegionRow(context, f)),
      _t('p = 지역 단위 회차당 1등 발생 추정, 기준 = 판매점 수 비례. 판매량 미보정.',
          color: Colors.black45, size: 10),

      _h('2', '지방장 추천 후보'),
      if (top.isEmpty)
        _empty()
      else
        for (var i = 0; i < top.length && i < 10; i++) agentCentralStoreRow(context, top[i], i + 1),
      _t('점수 = $kAgentScoreLabel', color: Colors.black45, size: 10),

      _h('3', '유명 명당 반복 당첨 연구'),
      _t('검정 ${famous['tested'] ?? 0}건'),
      _counts(_m(famous['by_status'])),
      ..._hyps(famous['examples']),

      _h('4', '지역 간 동시 당첨'),
      _counts(_m(cowin['counts']), labels: const {
        'store_pairs': '판매점 쌍',
        'cross_region_store_pairs': '타 지역 판매점 쌍',
        'region_pairs': '지역 쌍',
      }),
      _t('판매점 쌍', weight: FontWeight.w700),
      ..._hyps(cowin['store_pairs'], take: 4),
      _t('지역 쌍', weight: FontWeight.w700),
      ..._hyps(cowin['region_pairs'], take: 4),
      _t('동시 당첨은 같은 회차 연관이라 다음 회차 예측 근거로 쓰지 않습니다.', color: Colors.black45, size: 10),

      _h('5', '선행·후행 공간전이'),
      _counts(_m(lead['counts'])),
      ..._hyps(lead['examples']),

      _h('6', '새로 공유된 가설'),
      _t('공유 템플릿 ${shared['templates'] ?? 0} · 적용 사례 ${shared['instances'] ?? 0}'
          ' · 이번 체크포인트 신규 ${shared['new_this_checkpoint'] ?? 0} · 상충 ${shared['conflicts'] ?? 0}'),
      ..._hyps(shared['examples']),

      _h('7', '검증 현황'),
      if (status.isEmpty)
        _empty()
      else
        Wrap(spacing: 4, runSpacing: 3, children: [
          for (final s in kAgentHypStatusOrder)
            if (status[s] != null) regionTag('${kAgentHypStatusLabel[s]} ${status[s]}', hypothesisStatusColor(s)),
        ]),
      _t('검증 통과 = passed/combined 만. 발견·연구 중 가설은 실전 점수에 반영하지 않습니다.',
          color: Colors.black45, size: 10),

      _h('8', '지방장 미래 검증 성능'),
      AgentPerformanceView(performance: b.performance),

      _h('9', '지방장별 실전 검증 성과'),
      ..._agentPerformance(b.agentPerformance),

      _h('10', '가설 판정 현황'),
      ..._hypothesisVerdicts(b.hypothesisVerdicts),

      _h('11', '추천 순위 변경 이유'),
      if (changes.isEmpty)
        _t('직전 납품 대비 순위 변경 기록 없음', color: Colors.grey.shade600)
      else
        for (final c in changes.take(8))
          InkWell(
            onTap: (c['store_code'] ?? '').toString().isEmpty
                ? null
                : () => showAgentStoreSheet(context, c['store_code'].toString(), name: c['name']?.toString()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    '${c['name'] ?? c['store_code'] ?? '-'} · ${agentLabel(c['agent_id']?.toString())}'
                    ' · ${c['rank_prev'] ?? '신규'} → ${c['rank_now'] ?? '-'}위',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                if (c['reason'] != null)
                  Text('${c['reason']}', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
              ]),
            ),
          ),

      _h('12', '데이터 부족·불확실성'),
      for (final l in limits) _t('• $l', color: Colors.brown.shade700),
      _t('• $kRegionSalesDisclaimer', color: Colors.red.shade700, size: 10.5),
      _t('• $kAgentBacktestCaution', color: Colors.brown.shade700, size: 10.5),
    ]);
  }
}
