// 엔진 브리핑 — 전국 지방장 연구 보고 (research_agent_briefings.payload, Worker 가 DB 결과로 생성)
//
// payload 의 모든 필드는 선택적이다. 값이 없으면 '데이터 없음'으로 표시하고 추정값을 만들지 않는다.
// 점수 = 연구 기반 후보 점수(회차당 1·2등 기대 빈도, 판매량 미보정). 한 장당 당첨확률이 아니다.
import 'package:flutter/material.dart';

import '../screens/admin_agent_research_screen.dart';
import '../services/research/agent_research_repository.dart';
import '../services/route/region_research_repository.dart';
import 'admin_region_store_widgets.dart' show regionTag;
import 'agent_hidden_stores_card.dart';
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
      // 사후 브리핑은 브리핑 맨 위 '지방장 적중'(지역별로 맞춘 판매점)으로 대신한다
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

  // ── 본문 ────────────────────────────────────────────────────────────────

  Widget _content(AgentBriefing b) {
    final ag = b.agents;
    final focus = b.focusRegions;
    final status = b.statusCounts;
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

      _h('2', '지방에서 가볼 만한 연구 추천 명당'),
      const HiddenStoresCard(),
      _t('③ 유명 명당 반복 · ④ 지역 간 동시 당첨 · ⑤ 선행·후행 공간전이 · ⑥ 새로 공유된 가설은 브리핑 맨 위 요약으로, '
          '근거 자료와 검증 현황은 전국 지방장 연구소(↗)에서 봅니다.', color: Colors.black45, size: 10),
    ]);
  }
}
