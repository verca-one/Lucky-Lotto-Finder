// 지역 추천 · 현 위치 추천 공용 위젯 (관리자 전용 연구 기능)
//
// 판매점 카드 / 상세 바텀시트 / 지도 / 외부 내비(판매점 목적지) + 무료도로 안내.
// 모든 데이터는 읽기 전용 조회 결과를 표시만 한다.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/route/external_nav.dart';
import '../services/route/region_research_repository.dart';
import '../services/route/route_store_recommender.dart';
import '../services/route/route_store_repository.dart';
import '../services/route/routing_service.dart';
import '../services/research/agent_store_evidence.dart';
import '../services/research/agent_verdicts.dart';
import 'agent_store_evidence_widgets.dart';
import 'agent_store_widgets.dart' show AgentStoreSection;

// ═══════════════════════════════════════════════════════════════════════
// 무료도로 안내 + 외부 내비
// ═══════════════════════════════════════════════════════════════════════

Future<RoadOption> loadRoadOption() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return RoadOptionInfo.fromStorage(prefs.getString(RoadOptionInfo.prefsKey));
  } catch (_) {
    return RoadOption.freeOnly;
  }
}

/// 외부 내비 실행 전 안내. 무료도로 모드면 확인 다이얼로그, 취소 시 false.
Future<bool> confirmNavFreeRoadNotice(BuildContext context, NavApp app,
    {RoadOption? roadOption}) async {
  final opt = roadOption ?? await loadRoadOption();
  if (opt != RoadOption.freeOnly) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('무료도로 안내'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(kNavFreeRoadNotice, style: TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Text('${app.label}: ${app.tollNote}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: const Text('확인 후 실행')),
      ],
    ),
  );
  return ok == true;
}

/// 판매점을 목적지로 외부 내비 실행 시트. [origin] 이 없으면 각 앱이 현재 위치를 출발지로 사용.
Future<void> showStoreNavSheet(BuildContext context,
    {required String name, required LatLng point, NavPoint? origin}) async {
  final installed = <NavApp, bool>{};
  for (final a in NavApp.values) {
    installed[a] = await ExternalNav.isInstalled(a);
  }
  final roadOption = await loadRoadOption();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('판매점 목적지 — $name',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              '도로 옵션: ${roadOption.label}'
              '${roadOption == RoadOption.freeOnly ? " · 내비 앱에서 '무료도로'를 직접 선택해야 합니다" : ''}',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
            ),
            const SizedBox(height: 8),
            for (final app in NavApp.values)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                    '${app.label}  ${installed[app] == true ? '(설치됨)' : '(미설치/조회 불가)'}'),
                subtitle: Text(app.tollNote, style: const TextStyle(fontSize: 10)),
                trailing: Wrap(spacing: 4, children: [
                  if (installed[app] != true && app != NavApp.kakao)
                    TextButton(
                        onPressed: () => ExternalNav.openStore(app),
                        child: const Text('스토어')),
                  FilledButton.tonal(
                    onPressed: () async {
                      if (!await confirmNavFreeRoadNotice(ctx, app,
                          roadOption: roadOption)) {
                        return;
                      }
                      final r = await ExternalNav.launchRoute(
                          app: app, origin: origin, destination: NavPoint(point, name));
                      messenger?.showSnackBar(SnackBar(content: Text(r.message)));
                    },
                    child: const Text('목적지 실행'),
                  ),
                ]),
              ),
            const Text(
              '※ 외부 앱의 경로·소요시간·통행료는 각 앱 기준입니다. 영업시간 데이터가 없어 방문 전 확인이 필요합니다.',
              style: TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ],
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 공용 태그
// ═══════════════════════════════════════════════════════════════════════

Widget regionTag(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );

Color verificationColor(String v) => switch (v) {
      '검증 통과' => Colors.green,
      '연구 중' => Colors.teal,
      _ => Colors.grey,
    };

Color hypothesisStatusColor(String s) => switch (s) {
      'passed' => Colors.green,
      'researching' => Colors.teal,
      'discovered' => Colors.blue,
      'weakened' => Colors.orange,
      'combined' => Colors.purple,
      'rejected' => Colors.red,
      _ => Colors.grey,
    };

String fmtKm(double? m) => m == null ? '-' : '${(m / 1000).toStringAsFixed(2)}km';

// ═══════════════════════════════════════════════════════════════════════
// 헤더 (점수 구성·가중치·면책)
// ═══════════════════════════════════════════════════════════════════════

class RegionRankingHeader extends StatelessWidget {
  final RegionRankingResult result;
  final String title;
  const RegionRankingHeader({super.key, required this.result, required this.title});

  @override
  Widget build(BuildContext context) {
    final w = result.weights;
    return Container(
      width: double.infinity,
      color: Colors.orange.shade50,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(result.header,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: result.verifiedSignalStores == 0
                      ? Colors.brown.shade700
                      : Colors.green.shade800)),
          const SizedBox(height: 2),
          Text('연구 점수 = $kRegionScoreLabel — 각 항목을 0~1 로 정규화해 사전 고정 가중치로 더한 값',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.black87)),
          Text('${scoreFormula(w)} (가중치 합 ${w.values.fold(0.0, (a, b) => a + b).toStringAsFixed(2)})',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.black87)),
          Text(
            '점수 구성(사전 고정): '
            '${w.entries.map((e) => '${RegionStoreRanker.componentLabels[e.key]} ${e.value}').join(' + ')}'
            '  · 이력=norm(log1p(1등)+0.3·log1p(2등)) — 이 목록 최댓값 기준 정규화, 주기·신흥=famous/emerging+검증 통과 판매점 가설, '
            '전이=status passed 전이 가설 발화 중, 품질=좌표 0.5+이력 0.5'
            '${w.containsKey('agent') ? ', 지방장=1−(지방장 내 순위−1)/(판매점 수−1) (research_agent_score_sets → 없으면 research_agent_store_scores)' : ' · 지방장 점수 없음 → 기존 가중치'}',
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
          Text(
            '연구 테이블: ${result.researchState.label}'
            '${result.latestRound == null ? '' : ' · 데이터 기준 최신 ${result.latestRound}회차'}',
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
          const Text(kCentralFocusIndependence, style: TextStyle(fontSize: 10, color: Colors.black54)),
          Text('${result.disclaimer} $kNotPerTicketProbability',
              style: TextStyle(fontSize: 10, color: Colors.red.shade700)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 판매점 카드
// ═══════════════════════════════════════════════════════════════════════

class RegionStoreCard extends StatelessWidget {
  final RankedRegionStore item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onNav;

  /// 지방장 근거 (목록 일괄 조회 결과). null + [evidenceLoading] = 조회 중.
  final AgentStoreEvidence? evidence;
  final bool evidenceLoading;
  const RegionStoreCard({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onNav,
    this.evidence,
    this.evidenceLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = item.store;
    final ev = evidence;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: selected ? Colors.orange : Colors.grey.shade300, width: selected ? 2 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: Colors.deepOrange,
                  child: Text('${item.rank}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(s.address,
                          style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    ],
                  ),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(item.total.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  const Text('연구 점수', style: TextStyle(fontSize: 9, color: Colors.black45)),
                ]),
              ]),
              const SizedBox(height: 4),
              Text('$kRegionScoreLabel: ${scoreBreakdown(item.weights, item.components)}',
                  style: const TextStyle(fontSize: 10, color: Colors.black54)),
              const SizedBox(height: 4),
              Wrap(spacing: 5, runSpacing: 4, children: [
                if (ev != null)
                  storeEdgeTag(ev.edge)
                else
                  regionTag(evidenceLoading ? '판매점 가설 확인 중' : '판매점 가설 데이터 없음', Colors.grey),
                regionTag('1등 ${item.history.first == 0 && s.firstCount > 0 ? s.firstCount : item.history.first}회',
                    Colors.red),
                regionTag('2등 ${item.history.second == 0 && s.secondCount > 0 ? s.secondCount : item.history.second}회',
                    Colors.blue),
                if (item.distanceM != null) regionTag('직선 ${fmtKm(item.distanceM)}', Colors.indigo),
                if (item.cycle?.cls != null) regionTag('주기 ${item.cycle!.cls}', Colors.purple),
                if (item.firingTransitions.isNotEmpty)
                  regionTag('전이 발화 ${item.firingTransitions.length}', Colors.green),
                if (item.agentScore != null)
                  regionTag('지방장 ${item.agentScore!.agentRank}/${item.agentScore!.agentSize}위',
                      Colors.teal.shade700),
                if (item.dataRound != null) regionTag('기준 ${item.dataRound}회차', Colors.blueGrey),
                if (s.regionId != null) regionTag(RegionIds.display(s.regionId!), Colors.brown),
              ]),
              const SizedBox(height: 6),
              for (final r in item.reasons.take(3))
                Padding(
                  padding: const EdgeInsets.only(left: 2, top: 1),
                  child: Text('• $r', style: const TextStyle(fontSize: 11)),
                ),
              const SizedBox(height: 4),
              AgentEvidenceCompact(evidence: ev, loading: evidenceLoading, item: item),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.analytics_outlined, size: 16),
                    label: const Text('상세 근거', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                    onPressed: s.point == null ? null : onNav,
                    icon: const Icon(Icons.navigation, size: 16),
                    label: const Text('판매점 목적지', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 지도
// ═══════════════════════════════════════════════════════════════════════

class RegionStoresMap extends StatefulWidget {
  final List<RankedRegionStore> items;
  final String? selectedCode;
  final LatLng? me;
  final double? radiusKm;
  final ValueChanged<RankedRegionStore> onTapStore;
  final int maxPins;
  const RegionStoresMap({
    super.key,
    required this.items,
    required this.onTapStore,
    this.selectedCode,
    this.me,
    this.radiusKm,
    this.maxPins = 60,
  });

  @override
  State<RegionStoresMap> createState() => _RegionStoresMapState();
}

class _RegionStoresMapState extends State<RegionStoresMap> {
  final _ctrl = MapController();
  bool _ready = false;

  @override
  void didUpdateWidget(covariant RegionStoresMap old) {
    super.didUpdateWidget(old);
    if (old.items != widget.items || old.me != widget.me) _fit();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<RankedRegionStore> get _pins =>
      widget.items.where((i) => i.store.point != null).take(widget.maxPins).toList();

  void _fit() {
    if (!_ready) return;
    final pts = <LatLng>[
      ..._pins.map((i) => i.store.point!),
      if (widget.me != null) widget.me!,
    ];
    try {
      if (pts.length >= 2) {
        _ctrl.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(30)));
      } else if (pts.length == 1) {
        _ctrl.move(pts.first, 14);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pins = _pins;
    final center = widget.me ??
        (pins.isNotEmpty ? pins.first.store.point! : const LatLng(36.5, 127.8));
    return SizedBox(
      height: 260,
      child: FlutterMap(
        mapController: _ctrl,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 12,
          onMapReady: () {
            _ready = true;
            _fit();
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.luckylotto.finder',
          ),
          if (widget.me != null && widget.radiusKm != null)
            CircleLayer(circles: [
              CircleMarker(
                point: widget.me!,
                radius: widget.radiusKm! * 1000,
                useRadiusInMeter: true,
                color: Colors.blue.withValues(alpha: 0.06),
                borderColor: Colors.blue.withValues(alpha: 0.5),
                borderStrokeWidth: 1.5,
              ),
            ]),
          MarkerLayer(markers: [
            if (widget.me != null)
              Marker(
                point: widget.me!,
                width: 26,
                height: 26,
                child: const Icon(Icons.my_location, color: Colors.blue, size: 24),
              ),
            for (final item in pins)
              Marker(
                point: item.store.point!,
                width: 28,
                height: 28,
                child: GestureDetector(
                  onTap: () => widget.onTapStore(item),
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.selectedCode == item.store.code
                          ? Colors.orange
                          : Colors.deepOrange.shade700,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text('${item.rank}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 상세 바텀시트
// ═══════════════════════════════════════════════════════════════════════

Future<void> showRegionStoreDetailSheet(BuildContext context, RankedRegionStore item,
    {NavPoint? origin, AgentStoreEvidence? evidence}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _RegionStoreDetail(item: item, scroll: scroll, origin: origin, evidence: evidence),
    ),
  );
}

class _RegionStoreDetail extends StatefulWidget {
  final RankedRegionStore item;
  final ScrollController scroll;
  final NavPoint? origin;
  final AgentStoreEvidence? evidence;
  const _RegionStoreDetail({required this.item, required this.scroll, this.origin, this.evidence});

  @override
  State<_RegionStoreDetail> createState() => _RegionStoreDetailState();
}

class _RegionStoreDetailState extends State<_RegionStoreDetail> {
  StoreEngineInsight? _mnd;
  bool _mndLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMnd();
  }

  Future<void> _loadMnd() async {
    try {
      final m = await RouteStoreRepository().loadInsights([widget.item.store.code]);
      if (mounted) setState(() => _mnd = m[widget.item.store.code]);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _mndLoading = false);
    }
  }

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      );

  Widget _l(String t, {Color? color}) => Padding(
        padding: const EdgeInsets.only(left: 4, top: 2),
        child: Text(t, style: TextStyle(fontSize: 11.5, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final s = item.store;
    final c = item.cycle;
    final h = item.history;
    final w = item.weights;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('${item.rank}. ${s.name}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        Text(s.address, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        Text('코드 ${s.code} · ${s.regionId == null ? '지역 판정 불가' : RegionIds.display(s.regionId!)}'
            '${item.distanceM == null ? '' : ' · 직선 ${fmtKm(item.distanceM)}'}',
            style: const TextStyle(fontSize: 11, color: Colors.black45)),
        const SizedBox(height: 6),
        Wrap(spacing: 5, runSpacing: 4, children: [
          if (widget.evidence != null) storeEdgeTag(widget.evidence!.edge),
          regionTag('지역·주기 연구 가설: ${item.verification}', verificationColor(item.verification)),
          if (item.dataRound != null) regionTag('데이터 기준 ${item.dataRound}회차', Colors.blueGrey),
          regionTag(kOpenHoursUnknown, Colors.grey),
        ]),
        _h('연구 점수 ${item.total.toStringAsFixed(3)} — $kRegionScoreLabel'),
        _l('이 목록 안에서의 상대 점수입니다. 각 항목을 0~1 로 정규화(이력은 목록 최댓값 기준)한 뒤 사전 고정 가중치로 더합니다.',
            color: Colors.black54),
        _l(scoreFormula(w)),
        for (final e in w.entries)
          _l('${RegionStoreRanker.componentLabels[e.key] ?? e.key}: '
              '${(item.components[e.key] ?? 0).toStringAsFixed(3)} × ${e.value} = '
              '${((item.components[e.key] ?? 0) * e.value).toStringAsFixed(3)}'),
        for (final r in item.reasons) _l('• $r'),
        _l('$kRegionSalesDisclaimer $kNotPerTicketProbability', color: Colors.red.shade700),
        AgentEvidenceFull(
          storeCode: s.code,
          agentId: s.regionId ?? (RegionIds.isInternet(s.region, s.address) ? 'internet' : null),
          score: item.agentScore,
          evidence: widget.evidence,
          item: item,
        ),
        _h('당첨 이력 (winning_history, 로또)'),
        _l('1등 ${h.first}회${h.firstRounds.isEmpty ? '' : ': ${h.firstRounds.take(20).join(', ')}회'}'),
        _l('2등 ${h.second}회${h.secondRounds.isEmpty ? '' : ' (최근 ${h.secondRounds.take(10).join(', ')}회)'}'),
        if (h.purchaseMethods.isNotEmpty)
          _l('구매방식: ${h.purchaseMethods.entries.map((e) => '${e.key} ${e.value}').join(', ')}'),
        if (h.isEmpty)
          _l('winning_history 행 없음 (lottery_stores 집계: 1등 ${s.firstCount} · 2등 ${s.secondCount})'),
        _h('주기 연구 (research_store_cycles)'),
        if (c == null)
          _l('$kResearchNoData 또는 $kResearchNotApplied')
        else ...[
          _l('분류 ${c.cls ?? '-'} · 기준 ${c.trainingEndRound}회차'),
          _l('평균 간격 ${c.gapMean?.toStringAsFixed(1) ?? '-'}회 · 변동계수 ${c.gapCv?.toStringAsFixed(2) ?? '-'}'),
          _l('마지막 1등 후 ${c.roundsSinceLast ?? '-'}회 · 신흥 p=${c.emergingP?.toStringAsFixed(4) ?? '-'}'),
        ],
        _h('지역 연구 가설 (research_region_hypotheses)'),
        if (item.storeHypotheses.isEmpty && item.firingTransitions.isEmpty)
          _l('판매점·전이 가설 없음'),
        for (final hy in item.storeHypotheses)
          _l('[${hy.status}] ${hy.summary}'
              '${hy.testRate == null ? '' : ' · 검증 ${(hy.testRate! * 100).toStringAsFixed(1)}%'}'
              '${hy.testBase == null ? '' : ' vs ${(hy.testBase! * 100).toStringAsFixed(1)}%'}'
              '${hy.testP == null ? '' : ' (p=${hy.testP!.toStringAsFixed(4)})'}'
              '${hy.liveEligible ? ' · 실전 반영 가능' : ''}',
              color: hypothesisStatusColor(hy.status)),
        for (final hy in item.firingTransitions)
          _l('[발화 중·passed] ${hy.summary}', color: Colors.green.shade800),
        if (item.firingTransitions.isNotEmpty)
          _l(kTransitionFiringRule, color: Colors.black45),
        _h('명당연구소(MND) 근거'),
        if (_mndLoading)
          const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          )
        else if (_mnd == null || !_mnd!.hasAnyAnalysis)
          _l('MND 분석 결과 없음(데이터 부족)')
        else ...[
          if (_mnd!.anomaly != null)
            _l('이상치 ${_mnd!.anomaly!.anomalyStatus}: 실제 ${_mnd!.anomaly!.totalWins} / '
                '기대 ${_mnd!.anomaly!.expectedWins.toStringAsFixed(2)} · z=${_mnd!.anomaly!.poissonZ.toStringAsFixed(2)} '
                '(기준 ${_mnd!.anomaly!.trainingEndRound}회차)'),
          for (final hy in _mnd!.hypotheses)
            _l('가설 ${hy.hypothesisType} [${hy.isVerified ? '검증 통과' : '연구 중'} · ${hy.status}/${hy.gateStatus}]',
                color: hy.isVerified ? Colors.green.shade800 : null),
          for (final cp in _mnd!.changePoints)
            _l('변화점 ${cp.changePointRound}회차: ${cp.preRate.toStringAsFixed(4)} → ${cp.postRate.toStringAsFixed(4)}'),
        ],
        AgentStoreSection(storeCode: s.code),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
          onPressed: s.point == null
              ? null
              : () => showStoreNavSheet(context,
                  name: s.name, point: s.point!, origin: widget.origin),
          icon: const Icon(Icons.navigation),
          label: Text(s.point == null ? '좌표 없음 — 내비 불가' : '판매점 목적지로 내비 실행'),
        ),
      ],
    );
  }
}
