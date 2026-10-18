// 엔진 브리핑 — 마스터 주요 브리핑 3종 (엔진 추천번호 · 구매예측 번호 · 이번 주 엔진 추천 명당)
import 'package:flutter/material.dart';

import '../screens/nearby_engine_stores_screen.dart';
import '../services/research/agent_research_repository.dart' show agentModelLabel;
import '../services/research/agent_verdicts.dart';
import '../services/research/final_recommendation_engine.dart';
import '../services/research/master_briefing_service.dart';
import '../services/research/number_popularity.dart';
import '../services/research/recommend_release.dart';
import '../services/store_map_launcher.dart';
import '../services/supabase_service.dart';
import 'agent_store_evidence_widgets.dart';
import 'purchase_recommend_card.dart' show lottoBall, statusChip, popularityValidationLine;
import 'store_map_buttons.dart';

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
    RecommendRelease.changes.addListener(_reload);
  }

  @override
  void dispose() {
    RecommendRelease.changes.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = MasterBriefingService.instance.load(force: true));
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
        if (b.deniedMessage != null) {
          return _box(Padding(padding: const EdgeInsets.all(14),
              child: Text('주요 브리핑: ${b.deniedMessage}', style: const TextStyle(fontSize: 12))));
        }
        // 고정 영역: ① 공식 · ② 비인기 · ③ 구매예측 · ④ Number 엔진(연구용) · ⑤ 무작위 대조군(비교 기준) · ⑥ 명당
        // 회차 검증도 같은 번호로 같은 세트를 채점한다 (뒤에서 따로 채점하는 영역 없음)
        final open = b.numbersReleased;
        final wait = '${b.targetRound}회 번호는 ${b.release?.releaseLabel ?? '수요일 0시'}에 공개됩니다 (수동 추천으로 먼저 받을 수 있음).';
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
          Text('추첨 후 회차 검증도 아래 영역(①~⑥)을 같은 번호로 채점합니다.',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          BriefingSection(
            key: const ValueKey('buy_section'),
            title: '구매할 번호 — ${b.targetRound}회',
            subtitle: '① 공식 5세트 + ② 비인기 5세트 + ③ 구매예측 5세트 = 15세트',
            icon: Icons.shopping_cart_rounded,
            color: const Color(0xFFD84315),
            children: [
              _engineCard(b),
              const SizedBox(height: 10),
              if (!open)
                _areaPlaceholder('2', '${b.targetRound}회 비인기 추천조합', kPopularityColor, wait)
              else if (b.popularity == null)
                _areaPlaceholder('2', '${b.targetRound}회 비인기 추천조합', kPopularityColor, '저장본 없음 (당첨자 수 수집 후 서버가 만듭니다)')
              else
                PopularityPicksCard(no: '2', target: b.targetRound, pop: b.popularity!),
              const SizedBox(height: 10),
              if (!open)
                _areaPlaceholder('3', '${b.targetRound}회 구매예측 번호', const Color(0xFF00897B), wait)
              else
                _purchaseCard(b, '3'),
              const SizedBox(height: 8),
              Text('모든 조합의 1등 확률은 같습니다(1/8,145,060). 15세트 중 하나라도 5등 이상일 확률 약 30%.',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
            ],
          ),
          const SizedBox(height: 12),
          BriefingSection(
            key: const ValueKey('reference_section'),
            title: '참고 — 구매 대상 아님',
            subtitle: '검증 때 ①~③과 비교하려고 함께 사전 등록한 번호',
            icon: Icons.science_outlined,
            color: Colors.blueGrey.shade600,
            children: [
          LedgerSetsCard(no: '4', title: '${b.targetRound}회 Number 엔진 기본 조합', chip: '연구용 · 최종 추천 아님',
              color: Colors.grey.shade700, sets: open ? b.ledger['number_engine'] : null,
              note: open ? 'Number 엔진이 과거 지표 방향으로 고른 기본 조합입니다. 순방향 검증에서 무작위보다 나은 적중은 확인되지 않았습니다.' : wait),
          const SizedBox(height: 10),
          LedgerSetsCard(no: '5', title: '${b.targetRound}회 무작위 대조군', chip: '비교 기준 · 엔진 추천 아님',
              color: Colors.blueGrey.shade600, sets: open ? b.ledger['random_control'] : null,
              note: open ? '①~③ 추천이 무작위로 뽑은 번호보다 나은지 비교하려고 함께 사전 등록한 세트입니다.' : wait),
            ],
          ),
          const SizedBox(height: 12),
          _storeCard(b, '6'),
        ]);
      },
    );
  }

  /// 영역은 항상 같은 번호로 자리를 지킨다 — 내용이 없거나 공개 전이면 안내만
  Widget _areaPlaceholder(String no, String title, Color color, String text) => _box(Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(no, title, color),
          const SizedBox(height: 6),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
        ]),
      ));

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

  // ① 엔진 추천번호 — 공식 최종 예측 5세트 (패턴 분석·추천번호 화면과 같은 스냅샷)
  Widget _engineCard(MasterBriefing b) {
    final o = b.official;
    final f = o != null && o.hasSets ? o.rec : null;
    const color = Color(0xFF1565C0);
    return _box(Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header('1', '${b.targetRound}회 엔진 추천번호', color,
            chip: f == null
                ? null
                : statusChip(f.verifiedEdge ? '검증 신호 반영' : '검증된 당첨확률 우위 없음',
                    f.verifiedEdge ? Colors.teal.shade700 : Colors.grey)),
        const SizedBox(height: 4),
        if (o != null && f != null)
          Text(officialProvenanceLine(o),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade700, height: 1.4)),
        if (o?.statusNote != null)
          Text(o!.statusNote!, style: TextStyle(fontSize: 11, color: Colors.orange.shade900, height: 1.4)),
        const SizedBox(height: 8),
        if (f == null)
          Text(
              b.officialError != null
                  ? '${b.targetRound}회 최종 예측을 불러오지 못했습니다: ${b.officialError}'
                  : '${b.targetRound}회 $kOfficialPreparingMessage — 다른 회차 번호를 대신 표시하지 않습니다.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900))
        else ...[
          ...f.sets.asMap().entries.map((s) {
            final ps = b.popularity?.scoreOf(s.value);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _setRow(s.key + 1, s.value, color),
              if (ps != null) Padding(padding: const EdgeInsets.fromLTRB(26, 0, 0, 6), child: PopularityTag(score: ps)),
            ]);
          }),
          if (b.popularity != null && b.popularity!.official.isNotEmpty)
            Text('인기도: 다른 사람들이 같은 조합을 고를 가능성(무작위 조합 대비). 1등 확률은 같고, 당첨 시 나눠 가질 사람 수가 달라집니다.',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.4)),
          Text('마스터, ${f.note}', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
        ],
      ]),
    ));
  }

  // ① 아래 — 연구용 Number 엔진 기본 조합 (기본 접힘. 펼쳐도 스크롤 이동 없음)
  Widget _numberBaseResearchTile(MasterBriefing b) {
    final e = b.engine;
    const color = Color(0xFF1565C0);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text('연구용 · Number 엔진 기본 조합 (최종 추천 아님)',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
        children: [
          if (e != null)
            Align(
              alignment: Alignment.centerLeft,
              child: statusChip(e.baseLive ? 'Number 엔진 · 실전' : '실전 아님', e.baseLive ? color : Colors.grey),
            ),
          const SizedBox(height: 4),
          Text(e?.note ?? '엔진 예측을 불러오지 못했습니다.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          if (!b.numbersReleased)
            Text('${b.targetRound}회 번호는 ${b.release?.releaseLabel ?? '수요일 0시'}에 공개됩니다 (수동 추천으로 먼저 받을 수 있음).',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900))
          else if (e == null || e.baseSets.isEmpty)
            Text('${b.targetRound}회 Number 엔진 기본 조합이 아직 없습니다. 새 회차 처리 후 자동 생성됩니다.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900))
          else
            ...e.baseSets.asMap().entries.map((s) => _setRow(s.key + 1, s.value, Colors.grey.shade600)),
          Text('마스터, 엔진 번호는 과거 지표 방향으로 고른 조합입니다. 순방향 검증에서 무작위보다 나은 적중은 확인되지 않았습니다.',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
        ],
      ),
    );
  }

  // ② 구매예측 번호 — 검증 통과 시에만 표시 (미통과면 카드 자체를 생략)
  Widget _purchaseCard(MasterBriefing b, String no) {
    final p = b.purchase;
    const color = Color(0xFF00897B);
    if (p == null || p.recommendations.isEmpty) {
      return _areaPlaceholder(no, '${b.targetRound}회 구매예측 번호', color, '이번 회차 구매예측 저장본 없음');
    }
    return _box(Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(no, '${b.targetRound}회 구매예측 번호', color,
            chip: statusChip(p.validated ? '검증 통과' : '검증 미통과', p.validated ? color : Colors.grey)),
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
  Widget _storeCard(MasterBriefing b, String no) {
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
        _header(no, '이번 주 엔진 추천 명당', color,
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
                const SizedBox(height: 8),
                StoreMapButtons(
                  target: StoreMapTarget(
                    storeId: r.store.code,
                    name: r.store.name,
                    address: r.store.address,
                    lat: r.store.point?.latitude,
                    lng: r.store.point?.longitude,
                  ),
                ),
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
        if (b.deniedMessage != null) {
          return Text('주요 브리핑: ${b.deniedMessage}', style: const TextStyle(fontSize: 12, color: Color(0xFF888888)));
        }
        // ① 과 같은 공식 최종 예측 1세트
        final eng = b.official?.hasSets == true ? b.official!.rec!.sets.first : null;
        final open = b.numbersReleased;
        final pur = open && b.purchase?.validated == true ? b.purchase!.recommendations.first.numbers : null;
        final pop = open && b.popularity?.picks.isNotEmpty == true ? b.popularity!.picks.first.set : null;
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
          if (pop != null) line('비인기', pop, kPopularityColor),
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

const kPopularityColor = Color(0xFF6A1B9A);

/// 공식 세트 아래 인기도 한 줄 — '인기 상위 5% · 몫 −13%'
class PopularityTag extends StatelessWidget {
  final PopularityScore score;
  const PopularityTag({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final c = [Colors.red.shade700, Colors.grey.shade700, Colors.green.shade700][score.tier];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
      child: Text('${score.label} · ${score.shareLabel}',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
    );
  }
}

/// 비인기 추천 5세트 (pop-1.0) — 1등 확률은 같고, 당첨 시 나눠 가질 사람이 적을 것으로 추정되는 조합
class PopularityPicksCard extends StatelessWidget {
  final String no;
  final int target;
  final NumberPopularity pop;
  const PopularityPicksCard({super.key, required this.no, required this.target, required this.pop});

  @override
  Widget build(BuildContext context) {
    const color = kPopularityColor;
    final status = switch (pop.picksStatus) {
      'registered' => ('사전 등록 완료', Colors.teal.shade700),
      'late' => ('마감 후 생성 · 장부 미등록', Colors.orange.shade800),
      'pending' => ('등록 대기', Colors.grey.shade700),
      _ => ('검증 미통과 · 추천 없음', Colors.grey.shade700),
    };
    return Container(
      key: const ValueKey('popularity_picks_card'),
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEDE7F6))),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 22, height: 22, alignment: Alignment.center,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
            child: Text(no, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('$target회 비인기 추천조합', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color))),
          statusChip(status.$1, status.$2),
        ]),
        const SizedBox(height: 4),
        Text('다른 사람들이 잘 고르지 않는 조합 — 당첨되면 나눠 가질 사람이 적을 것으로 추정',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(pop.validationLine, style: TextStyle(fontSize: 10.5, color: Colors.teal.shade800, height: 1.4)),
        const SizedBox(height: 8),
        if (pop.picks.isEmpty)
          Text('이번 회차 비인기 추천조합이 없습니다.', style: TextStyle(fontSize: 12, color: Colors.orange.shade900))
        else
          ...pop.picks.asMap().entries.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
                child: Column(children: [
                  Row(children: [
                    SizedBox(width: 18, child: Text('${e.key + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color))),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: e.value.set.map((n) => lottoBall(n, size: 28)).toList(),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Align(alignment: Alignment.centerRight, child: PopularityTag(score: e.value)),
                ]),
              )),
        Text('마스터, 모든 조합의 1등 확률은 같습니다(1/8,145,060). 이 조합은 확률이 아니라 "당첨 시 나눠 가질 사람 수"를 줄이려는 선택이며, '
            '몫 +N%는 ${pop.trainingEnd}회까지 당첨자 수로 학습한 모델 추정치입니다. 선정: ${pop.pickRule}',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
      ]),
    );
  }
}


/// 브리핑 맨 위 — 수동 추천 버튼: 수요일 0시 자동 실행 전에 다음 회차 추천번호 엔진을 지금 실행 요청
class ManualRecommendCard extends StatefulWidget {
  /// 테스트용: (목표 회차, 직전 회차 추첨일)
  final Future<(int, String?)> Function()? target;

  /// 테스트용: 목표 회차 공식 추천번호가 이미 만들어졌는지
  final Future<bool> Function(int target)? generated;
  final DateTime? nowUtc;
  const ManualRecommendCard({super.key, this.target, this.generated, this.nowUtc});
  @override
  State<ManualRecommendCard> createState() => _ManualRecommendCardState();
}

class _ManualRecommendCardState extends State<ManualRecommendCard> {
  ReleaseState? _s;
  bool _made = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (target, prevDraw) = await (widget.target ?? _latest)();
      final s = await RecommendRelease.state(target, prevDrawDate: prevDraw, nowUtc: widget.nowUtc);
      var made = false;
      if (s.released) {
        try {
          made = await (widget.generated ?? _generated)(target);
        } catch (_) {}
      }
      if (mounted) setState(() {
        _s = s;
        _made = made;
      });
    } catch (_) {}
  }

  static Future<(int, String?)> _latest() async {
    final recent = await SupabaseService.getRecentWinningNumbers(1);
    if (recent.isEmpty) throw StateError('no rounds');
    return (recent.first.round + 1, recent.first.drawDate);
  }

  static Future<bool> _generated(int target) async =>
      (await OfficialPredictionService.instance.load(target, force: true)).hasSets;

  Future<void> _press() async {
    final s = _s!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${s.target}회 수동 추천'),
        content: Text('${s.target}회 추천번호 엔진을 지금 실행합니다.\n'
            '평소 ${s.releaseLabel} 자동 실행을 앞당기는 것이며, 회차당 한 번만 요청할 수 있습니다.\n'
            '서버에서 실행되어 보통 10~20분 뒤 브리핑에 추천번호가 나옵니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('엔진 실행')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await RecommendRelease.requestRun(s.target);
      OfficialPredictionService.instance.clearCache();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('엔진 실행 요청 실패: $e')));
      }
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Widget _note(String key, IconData icon, Color c, Color bg, String text, {bool refresh = false}) => Container(
        key: ValueKey(key),
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c))),
          if (refresh)
            IconButton(
              visualDensity: VisualDensity.compact, iconSize: 18, tooltip: '새로고침',
              icon: Icon(Icons.refresh, color: c),
              onPressed: () {
                _load();
                RecommendRelease.changes.value++;
              },
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SizedBox.shrink();
    if (s.released) {
      final how = s.manualAt != null ? '수동 추천' : '수요일 자동 실행';
      if (_made) {
        return _note('manual_recommend_done', Icons.check_circle_rounded, const Color(0xFF2E7D32), const Color(0xFFE8F5E9),
            '${s.target}회 추천번호 생성 완료 · $how');
      }
      return _note('manual_recommend_waiting', Icons.hourglass_top_rounded, const Color(0xFFE65100), const Color(0xFFFFF3E0),
          '${s.target}회 엔진 실행 대기 · $how — 서버 실행 후 표시 (보통 10~20분)', refresh: true);
    }
    return Container(
      key: const ValueKey('manual_recommend_card'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB300), width: 1.4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.schedule_rounded, size: 18, color: Color(0xFFE65100)),
          const SizedBox(width: 6),
          Expanded(child: Text('${s.target}회 추천번호 — ${s.releaseLabel} 엔진 자동 실행',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFFE65100)))),
        ]),
        const SizedBox(height: 4),
        Text('추첨 후에는 지난 회차 검증을 먼저 하고, 추천번호 엔진은 수요일에 돌립니다. 그 전에 필요하면 수동 추천으로 지금 실행하세요.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, height: 1.4)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('manual_recommend_button'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE65100)),
            onPressed: _busy ? null : _press,
            icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
            label: Text('수동 추천 · 지금 ${s.target}회 엔진 실행', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}


/// 장부(사전 등록)에 올라간 세트를 그대로 보여주는 영역 카드 — ④ Number 엔진 · ⑤ 무작위 대조군
class LedgerSetsCard extends StatelessWidget {
  final String no, title, chip, note;
  final Color color;
  final List<List<int>>? sets;
  const LedgerSetsCard({super.key, required this.no, required this.title, required this.chip, required this.color,
      required this.sets, required this.note});

  @override
  Widget build(BuildContext context) {
    final s = sets;
    return Container(
      key: ValueKey('ledger_area_$no'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDE1E6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 22, height: 22, alignment: Alignment.center,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
            child: Text(no, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color))),
          statusChip(chip, color),
        ]),
        const SizedBox(height: 6),
        if (s == null || s.isEmpty)
          Text(s == null ? note : '이번 회차 사전 등록 세트 없음', style: TextStyle(fontSize: 12, color: Colors.orange.shade900))
        else ...[
          for (final e in s.asMap().entries)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                SizedBox(width: 18, child: Text('${e.key + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color))),
                Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: e.value.map((n) => lottoBall(n, size: 26)).toList())),
              ]),
            ),
          Text(note, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
        ],
      ]),
    );
  }
}


/// 브리핑 구역 묶음 — '구매할 번호' · '참고' 를 한눈에 구분
class BriefingSection extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final List<Widget> children;
  const BriefingSection({super.key, required this.title, required this.subtitle, required this.icon,
      required this.color, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1.4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: color))),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2, bottom: 8),
            child: Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ),
          ...children,
        ]),
      );
}
