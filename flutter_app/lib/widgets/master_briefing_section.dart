// 엔진 브리핑 — 마스터 주요 브리핑 3종 (엔진 추천번호 · 구매예측 번호 · 이번 주 엔진 추천 명당)
import 'package:flutter/material.dart';

import '../screens/nearby_engine_stores_screen.dart';
import '../services/research/agent_research_repository.dart' show agentModelLabel;
import '../services/research/agent_verdicts.dart';
import '../services/research/master_briefing_service.dart';
import 'agent_store_evidence_widgets.dart';
import 'purchase_recommend_card.dart' show lottoBall, statusChip, popularityValidationLine;

const _purple = Color(0xFF4527A0);

/// 상세 화면용 전체 섹션
class MasterBriefingSection extends StatefulWidget {
  const MasterBriefingSection({super.key});
  @override
  State<MasterBriefingSection> createState() => _MasterBriefingSectionState();
}

class _MasterBriefingSectionState extends State<MasterBriefingSection> {
  late Future<MasterBriefing> _future;

  @override
  void initState() {
    super.initState();
    _future = MasterBriefingService.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MasterBriefing>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _box(const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Column(children: [
              CircularProgressIndicator(),
              SizedBox(height: 10),
              Text('마스터, 이번 회차 주요 브리핑을 준비하고 있습니다…', style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
            ])),
          ));
        }
        if (snap.hasError || snap.data == null) {
          return _box(Padding(padding: const EdgeInsets.all(14),
              child: Text('주요 브리핑을 불러오지 못했습니다: ${snap.error}', style: const TextStyle(fontSize: 12))));
        }
        final b = snap.data!;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('주요 브리핑', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _purple)),
            const SizedBox(width: 6),
            statusChip('${b.targetRound}회 대상 · ${b.latestRound}회까지 반영', _purple),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact, iconSize: 18, tooltip: '새로고침',
              icon: const Icon(Icons.refresh, color: _purple),
              onPressed: () => setState(() => _future = MasterBriefingService.instance.load(force: true)),
            ),
          ]),
          const SizedBox(height: 6),
          _engineCard(b),
          const SizedBox(height: 10),
          _purchaseCard(b),
          const SizedBox(height: 10),
          _storeCard(b),
        ]);
      },
    );
  }

  Widget _box(Widget child, {Color border = const Color(0xFFEDE7F6)}) => Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
        child: child,
      );

  Widget _header(String no, String title, Color color, {Widget? chip}) => Row(children: [
        Container(
          width: 22, height: 22, alignment: Alignment.center,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
          child: Text(no, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color))),
        if (chip != null) chip,
      ]);

  Widget _balls(List<int> nums, {double size = 28}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: nums.map((n) => lottoBall(n, size: size)).toList(),
      );

  Widget _setRow(int i, List<int> nums, Color color, {String? trailing}) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          SizedBox(width: 18, child: Text('$i', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color))),
          Expanded(child: _balls(nums)),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Text(trailing, style: const TextStyle(fontSize: 9.5, color: Color(0xFF888888))),
          ],
        ]),
      );

  // ① 엔진 추천번호
  Widget _engineCard(MasterBriefing b) {
    final e = b.engine;
    const color = Color(0xFF1565C0);
    return _box(Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header('1', '${b.targetRound}회 엔진 추천번호', color,
            chip: e == null ? null : statusChip(e.baseLive ? 'Number 엔진 · 실전' : '실전 아님', e.baseLive ? color : Colors.grey)),
        const SizedBox(height: 4),
        Text(e?.note ?? '엔진 예측을 불러오지 못했습니다.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        if (e == null || e.baseSets.isEmpty)
          Text('${b.targetRound}회 엔진 추천번호가 아직 없습니다. 새 회차 처리 후 자동 생성됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900))
        else
          ...e.baseSets.asMap().entries.map((s) => _setRow(s.key + 1, s.value, color)),
        Text('마스터, 엔진 번호는 과거 지표 방향으로 고른 조합입니다. 순방향 검증에서 무작위보다 나은 적중은 확인되지 않았습니다.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
      ]),
    ));
  }

  // ② 구매예측 번호 — 검증 통과 시에만 표시 (미통과면 카드 자체를 생략)
  Widget _purchaseCard(MasterBriefing b) {
    final p = b.purchase;
    if (p == null || !p.validated) return const SizedBox.shrink();
    const color = Color(0xFF00897B);
    return _box(Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header('2', '${b.targetRound}회 구매예측 번호', color, chip: statusChip('검증 통과', color)),
        const SizedBox(height: 4),
        Text('실제 판매 데이터로 검증한 "덜 팔리는 조합" — 당첨 시 상금을 나눌 사람이 적은 번호',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(popularityValidationLine(p.popularity), style: TextStyle(fontSize: 10.5, color: Colors.teal.shade800, height: 1.4)),
        const SizedBox(height: 8),
        ...p.recommendations.asMap().entries.map((r) => _setRow(r.key + 1, r.value.numbers, color,
            trailing: '인기도 ×${(r.value.popularityIndex ?? 1).toStringAsFixed(2)}')),
        Text('마스터, 모든 조합의 1등 확률은 같습니다(1/8,145,060). 구매예측은 확률이 아니라 "당첨 시 나눠 가질 위험"을 줄이는 선택이며, '
            '인기도 ×0.xx 는 평균 조합 대비 판매 비율 추정입니다.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
      ]),
    ));
  }

  // ③ 이번 주 엔진 추천 명당
  Widget _storeCard(MasterBriefing b) {
    const color = Color(0xFFE65100);
    final ev = b.evidence;
    final kinds = [
      for (final p in b.stores)
        if (ev != null) ev.of(p.ranked.store.code, agentId: p.regionId).edge.kind,
    ];
    final chipText = storeEdgeSummaryChip(kinds);
    return _box(Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header('3', '이번 주 엔진 추천 명당', color,
            chip: statusChip(chipText, chipText.startsWith('검증 통과') ? Colors.green.shade700 : Colors.grey.shade700)),
        const SizedBox(height: 4),
        Text(
            b.agentPipeline
                ? '선정: 지방장 연구 — ${agentModelLabel(b.agentRef?.model)} · 목표 ${b.agentRef?.target ?? '-'}회 '
                    '(중앙 엔진 주목 지역 상위 5곳의 지방장 납품 1위 → 전국 상위 후보로 채움)'
                : '선정: 이전 규칙 (Store 엔진 지역 후보·신흥·유명 명당)${b.fallbackReason == null ? '' : ' — 지방장 자료 대체 사유: ${b.fallbackReason}'}',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
        if (kinds.isNotEmpty)
          Text(storeEdgeSummaryLine(kinds), style: TextStyle(fontSize: 10.5, color: Colors.brown.shade700)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: color, visualDensity: VisualDensity.compact),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => NearbyEngineStoresScreen(
                  targetRound: b.targetRound, storeEngineSidos: b.storeEngineRegions),
            )),
            icon: const Icon(Icons.my_location, size: 18),
            label: const Text('내 위치 — 주변 엔진 추천 명당 보기', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 6),
        Text(b.storeEngineRegions.isEmpty
                ? '참고 신호 — Store 엔진 이번 회차 지역 후보 없음'
                : '참고 신호 — Store 엔진 ${b.targetRound}회 지역 후보: ${b.storeEngineRegions.join(', ')} (${b.storeEngineTrainingEnd ?? '-'}회까지 학습)',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        if (b.stores.isEmpty)
          Text(b.storeError != null ? '명당 연구 결과를 불러오지 못했습니다: ${b.storeError}' : '추천할 명당 연구 결과가 없습니다 (지역 연구 미실행).',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900))
        else
          ...b.stores.asMap().entries.map((e) {
            final r = e.value.ranked;
            final se = ev?.of(r.store.code, agentId: e.value.regionId);
            final h = r.history;
            final first = h.first > 0 ? h.first : r.store.firstCount;
            final second = h.second > 0 ? h.second : r.store.secondCount;
            return Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('${e.key + 1}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r.store.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                  Text('1등 $first · 2등 $second', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 2),
                Text(r.store.address, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('선정: ${e.value.why}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
                if (se != null) ...[
                  const SizedBox(height: 3),
                  storeEdgeTag(se.edge),
                ],
                if (r.cycle != null)
                  Text('주기 연구: ${{'famous': '유명', 'emerging': '신흥', 'regular': '일반', 'sparse': '희소'}[r.cycle!.cls] ?? r.cycle!.cls}'
                      '${r.cycle!.gapMean == null ? '' : ' · 평균 간격 ${r.cycle!.gapMean!.toStringAsFixed(0)}회'}'
                      '${r.cycle!.roundsSinceLast == null ? '' : ' · 마지막 1등 후 ${r.cycle!.roundsSinceLast}회'}',
                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                Text('엔진 연구 점수 ${r.total.toStringAsFixed(2)} — 선정 명당 목록 내 상대 연구 점수 (0~1, 확률 아님)',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                Text('${scoreFormula(r.weights)} · ${scoreBreakdown(r.weights, r.components)}',
                    style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600)),
                const SizedBox(height: 3),
                AgentEvidenceCompact(evidence: se, item: r),
              ]),
            );
          }),
        Text('마스터, ${b.agentPipeline ? MasterBriefing.storeDisclaimer : MasterBriefing.legacyDisclaimer}',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
      ]),
    ));
  }
}

/// 관리자 패널 브리핑 카드용 한 줄 요약
class MasterBriefingCompact extends StatelessWidget {
  const MasterBriefingCompact({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MasterBriefing>(
      future: MasterBriefingService.instance.load(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Text('마스터, 이번 회차 주요 브리핑을 준비하고 있습니다…',
              style: TextStyle(fontSize: 12, color: Color(0xFF888888)));
        }
        final b = snap.data;
        if (b == null) return const SizedBox.shrink();
        final eng = b.engine?.baseSets.isNotEmpty == true ? b.engine!.baseSets.first : null;
        final pur = b.purchase?.validated == true ? b.purchase!.recommendations.first.numbers : null;
        Widget line(String label, List<int>? nums, Color c) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                SizedBox(width: 62, child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c))),
                if (nums == null) const Text('-', style: TextStyle(fontSize: 11))
                else ...nums.map((n) => Padding(padding: const EdgeInsets.only(right: 3), child: lottoBall(n, size: 20))),
              ]),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('마스터, ${b.targetRound}회 주요 브리핑입니다.',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF333333))),
          const SizedBox(height: 6),
          line('엔진 번호', eng, const Color(0xFF1565C0)),
          if (pur != null) line('구매예측', pur, const Color(0xFF00897B)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(width: 62, child: Text('추천 명당', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFE65100)))),
            Expanded(child: Text(
              b.stores.isEmpty ? '-' : b.stores.take(3).map((s) => s.ranked.store.name).join(' · '),
              style: const TextStyle(fontSize: 11, color: Color(0xFF333333)), maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
        ]);
      },
    );
  }
}
