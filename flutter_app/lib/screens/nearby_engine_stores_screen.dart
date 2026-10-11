// 내 위치 엔진 추천 명당 — 마스터 브리핑 ③ "내 위치" 버튼
// 현재 위치를 새로 측정(캐시 위치 미사용) → 반경 내 주변 판매점 전체로 가설별 점수 계산 → 상위 추천.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/research/agent_store_evidence.dart';
import '../services/research/agent_verdicts.dart';
import '../services/research/nearby_engine_recommender.dart';
import '../services/route/external_nav.dart';
import '../services/route/region_research_repository.dart';
import '../widgets/admin_region_store_widgets.dart';
import '../widgets/agent_store_evidence_widgets.dart';

const _orange = Color(0xFFE65100);

class NearbyEngineStoresScreen extends StatefulWidget {
  final int targetRound;
  final List<String> storeEngineSidos;
  const NearbyEngineStoresScreen({super.key, required this.targetRound, this.storeEngineSidos = const []});

  @override
  State<NearbyEngineStoresScreen> createState() => _NearbyEngineStoresScreenState();
}

class _NearbyEngineStoresScreenState extends State<NearbyEngineStoresScreen> {
  final _recommender = NearbyEngineRecommender();
  Position? _pos;
  double _radiusKm = 3;
  bool _busy = false;
  String _progress = '';
  String? _error;
  NearbyRecommendation? _result;
  String? _selectedCode;
  bool _showAll = false;

  // 판매점별 지방장 근거 (표시 상위 60곳 일괄 조회)
  AgentEvidenceBundle? _bundle;
  bool _bundleLoading = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  LatLng? get _me => _pos == null ? null : LatLng(_pos!.latitude, _pos!.longitude);
  NavPoint? get _origin => _me == null ? null : NavPoint(_me!, '현재 위치');

  Future<void> _locate() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = '현재 위치 측정 중…';
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw '위치 서비스가 꺼져 있습니다. 설정에서 위치를 켜 주세요.';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw '위치 권한이 거부되었습니다.';
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      if (!mounted) return;
      _pos = pos;
      await _compute();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compute() async {
    final me = _me;
    if (me == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _showAll = false;
      _bundle = null;
    });
    try {
      final r = await _recommender.recommend(
        me: me, radiusKm: _radiusKm, targetRound: widget.targetRound,
        storeEngineSidos: widget.storeEngineSidos,
        onProgress: (s) { if (mounted) setState(() => _progress = s); },
      );
      if (mounted) setState(() => _result = r);
      _loadBundle(r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() { _busy = false; _progress = ''; });
    }
  }

  Future<void> _loadBundle(NearbyRecommendation r) async {
    setState(() => _bundleLoading = true);
    try {
      final b = await loadEvidenceForRanked(r.picks.take(60).map((p) => p.ranked).toList());
      if (mounted && identical(_result, r)) setState(() => _bundle = b);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _bundleLoading = false);
    }
  }

  AgentStoreEvidence? _ev(RankedRegionStore item) => _bundle?.of(item.store.code,
      agentId: agentIdOfStore(regionId: item.store.regionId, region: item.store.region, address: item.store.address));

  void _openDetail(RankedRegionStore item) {
    setState(() => _selectedCode = item.store.code);
    showRegionStoreDetailSheet(context, item, origin: _origin, evidence: _ev(item));
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final top = r == null ? const <NearbyStorePick>[] : r.picks.take(5).toList();
    final rest = r == null ? const <NearbyStorePick>[] : r.picks.skip(5).take(_showAll ? 50 : 10).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('내 위치 엔진 추천 명당 · ${widget.targetRound}회'),
        backgroundColor: _orange, foregroundColor: Colors.white,
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        _controls(),
        if (_busy)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const CircularProgressIndicator(color: _orange),
              const SizedBox(height: 10),
              Text(_progress, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        if (_error != null) _errorBox(_error!),
        if (r != null) ...[
          _contextCard(r),
          RegionStoresMap(
            items: r.picks.take(30).map((p) => p.ranked).toList(),
            selectedCode: _selectedCode, me: _me, radiusKm: _radiusKm, onTapStore: _openDetail,
          ),
          _sectionTitle('마스터, 현 위치 엔진 추천 명당 TOP ${top.length}입니다'),
          for (final p in top) _pickCard(p),
          if (rest.isNotEmpty) ...[
            _sectionTitle('그 밖의 주변 판매점 (종합 점수순)'),
            for (final p in rest) _compactRow(p),
            if (!_showAll && r.picks.length > 15)
              Center(child: TextButton(onPressed: () => setState(() => _showAll = true),
                  child: Text('더 보기 (전체 ${r.picks.length}곳)'))),
          ],
          _methodCard(),
        ],
      ]),
    );
  }

  Widget _controls() {
    final pos = _pos;
    return Container(
      color: Colors.deepOrange.shade50,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _orange),
            onPressed: _busy ? null : _locate,
            icon: const Icon(Icons.my_location),
            label: Text(pos == null ? '내 위치로 엔진 추천 명당 찾기' : '내 위치 다시 측정해서 추천'),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          pos == null
              ? '위치는 매번 새로 측정합니다 (캐시 위치 미사용).'
              : '정확도 ±${pos.accuracy.toStringAsFixed(0)}m · (${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})',
          style: TextStyle(fontSize: 11, color: pos == null ? Colors.black54 : Colors.green.shade800),
        ),
        const SizedBox(height: 4),
        Row(children: [
          const Text('반경  ', style: TextStyle(fontSize: 12)),
          for (final v in const [1.0, 3.0, 5.0, 10.0])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${v.toStringAsFixed(0)}km', style: const TextStyle(fontSize: 12)),
                selected: _radiusKm == v,
                visualDensity: VisualDensity.compact,
                onSelected: _busy
                    ? null
                    : (_) {
                        setState(() => _radiusKm = v);
                        if (_me != null) _compute();
                      },
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _contextCard(NearbyRecommendation r) {
    final c = r.context;
    final regionLines = c.regionIds.take(4).map((id) {
      final s = c.regionStats[id];
      if (s == null) return '• ${RegionIds.display(id)}: 지역 연구 통계 없음';
      final ratio = (s.shrunkRate != null && s.baselineRate != null && s.baselineRate! > 0)
          ? (s.shrunkRate! / s.baselineRate!).toStringAsFixed(2) : '-';
      return '• ${RegionIds.display(id)}: 1등 ${s.firstWins}건 · 기준 대비 ×$ratio · 추세 z ${s.trendZ?.toStringAsFixed(2) ?? '-'} · 공백 ${s.dormantRounds ?? '-'}회';
    }).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('주변 상권 (반경 ${r.radiusKm.toStringAsFixed(0)}km)',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('판매점 ${c.storeCount}곳 (당첨 이력 보유 ${c.storesWithWins}곳) · 누적 1등 ${c.totalFirst}건 · 2등 ${c.totalSecond}건'
            ' · 유명 명당 ${c.famousCount}곳 · 신흥 명당 ${c.emergingCount}곳',
            style: const TextStyle(fontSize: 11.5)),
        Text('Store 엔진 ${r.targetRound}회 지역 후보: ${widget.storeEngineSidos.isEmpty ? '없음' : widget.storeEngineSidos.join(', ')}'
            ' · 데이터 ${c.latestRound ?? '-'}회까지',
            style: const TextStyle(fontSize: 11.5)),
        if (regionLines.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...regionLines.map((l) => Text(l, style: const TextStyle(fontSize: 11))),
        ],
        const SizedBox(height: 4),
        Text(
          r.verifiedSignalStores == 0
              ? '검증 통과 가설(주기·전이·MND)을 가진 주변 판매점 없음 — 이력·주변 비교·최근 활동 중심 추천 (판매점별 지방장 가설 판정은 카드에 표시)'
              : '검증 통과 가설 보유 판매점 ${r.verifiedSignalStores}곳 — 그래도 당첨확률 보장 아님',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.brown.shade700),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _orange)),
      );

  Color _statusColor(HypothesisStatus s) => switch (s) {
        HypothesisStatus.verified => Colors.teal.shade700,
        HypothesisStatus.researching => Colors.indigo.shade400,
        HypothesisStatus.descriptive => Colors.blueGrey.shade500,
        HypothesisStatus.none => Colors.grey.shade400,
      };

  Widget _pickCard(NearbyStorePick p) {
    final s = p.ranked.store;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s.code == _selectedCode ? _orange : _orange.withValues(alpha: 0.25),
            width: s.code == _selectedCode ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 13, backgroundColor: _orange,
                child: Text('${p.rank}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900))),
            const SizedBox(width: 8),
            Expanded(child: Text(s.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
            Text('종합 ${(p.score * 100).toStringAsFixed(0)}점',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _orange)),
          ]),
          const SizedBox(height: 3),
          Text('${s.address} · ${fmtKm(p.ranked.distanceM)}',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text('선정 이유: ${p.headline}',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _orange)),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 3, children: [
            if (_ev(p.ranked) != null)
              storeEdgeTag(_ev(p.ranked)!.edge)
            else
              regionTag(_bundleLoading ? '판매점 가설 확인 중' : '판매점 가설 데이터 없음', Colors.grey),
            regionTag('엔진 연구 점수 ${p.ranked.total.toStringAsFixed(2)} (목록 내 상대, 확률 아님)', Colors.blueGrey),
          ]),
          const SizedBox(height: 4),
          Text('엔진 연구 점수 구성: ${scoreBreakdown(p.ranked.weights, p.ranked.components)}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          AgentEvidenceCompact(evidence: _ev(p.ranked), loading: _bundleLoading, item: p.ranked),
          const SizedBox(height: 6),
          _partsBar(p),
          const SizedBox(height: 8),
          ...p.evidence.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(e.supports ? Icons.check_circle : Icons.remove_circle_outline, size: 14,
                      color: e.supports ? Colors.green.shade600 : Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Expanded(child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${e.code} ${e.title}  ',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    TextSpan(text: e.detail, style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
                  ]))),
                  const SizedBox(width: 4),
                  Text(e.status.label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: _statusColor(e.status))),
                ]),
              )),
          const SizedBox(height: 4),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => _openDetail(p.ranked),
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text('상세', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            if (s.point != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _orange),
                onPressed: () => showStoreNavSheet(context, name: s.name, point: s.point!, origin: _origin),
                icon: const Icon(Icons.directions, size: 16),
                label: const Text('길찾기 (무료도로)', style: TextStyle(fontSize: 12)),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _partsBar(NearbyStorePick p) {
    const colors = {
      'engine': Color(0xFFE65100), 'agent': Color(0xFF00695C), 'local': Color(0xFF6A1B9A), 'recent': Color(0xFF1565C0),
      'storeEngine': Color(0xFF00897B), 'region': Color(0xFF5D4037), 'access': Color(0xFF9E9E9E),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 8,
          child: Row(children: [
            for (final k in kNearbyWeights.keys)
              if (kNearbyWeights[k]! * p.parts[k]! > 0)
                Expanded(
                  flex: (kNearbyWeights[k]! * p.parts[k]! * 1000).round().clamp(1, 1000),
                  child: Container(color: colors[k]),
                ),
            if (p.score < 1)
              Expanded(flex: ((1 - p.score) * 1000).round().clamp(1, 1000), child: Container(color: Colors.grey.shade200)),
          ]),
        ),
      ),
      const SizedBox(height: 3),
      Wrap(spacing: 8, children: [
        for (final k in kNearbyWeights.keys)
          Text('${kNearbyWeightLabels[k]} ${(p.parts[k]! * 100).toStringAsFixed(0)}',
              style: TextStyle(fontSize: 9.5, color: colors[k], fontWeight: FontWeight.w700)),
      ]),
    ]);
  }

  Widget _compactRow(NearbyStorePick p) {
    final s = p.ranked.store;
    return ListTile(
      dense: true,
      leading: Text('${p.rank}', style: const TextStyle(fontWeight: FontWeight.w800, color: _orange)),
      title: Text(s.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      subtitle: Text('${fmtKm(p.ranked.distanceM)} · 1등 ${p.ranked.history.first > 0 ? p.ranked.history.first : s.firstCount}'
          ' · 2등 ${p.ranked.history.second > 0 ? p.ranked.history.second : s.secondCount} · ${p.headline}',
          style: const TextStyle(fontSize: 10.5), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text('${(p.score * 100).toStringAsFixed(0)}점', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      onTap: () => _openDetail(p.ranked),
    );
  }

  Widget _methodCard() => Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('계산 방법 (사전 고정)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            '종합 = ${kNearbyWeights.entries.map((e) => '${e.value.toStringAsFixed(2)}×${kNearbyWeightLabels[e.key]}').join(' + ')}\n'
            '· 엔진 종합: 지역 추천 엔진 — 지방장 점수가 있으면 0.3 이력 + 0.2 지방장 + 0.15 주기 + 0.15 전이 + 0.2 품질, '
            '없으면 0.4 이력 + 0.2 주기 + 0.2 전이 + 0.2 품질. 주기·전이는 검증 통과 가설만 가점\n'
            '· 지방장 연구: 1 − (지방장 내 순위−1)/(지방장 판매점 수−1), research_agent_score_sets(압축) → 없으면 research_agent_store_scores, 최신 목표 회차. '
            '지방장 점수 = 회차당 1·2등 기대 빈도(판매량 미보정), 없으면 0 (데이터 없음). live_factor ≠ 1 일 때만 검증 통과 표시\n'
            '· 주변 우위: 반경 내 판매점의 1·2등 합계를 주변 평균 쪽으로 절반 축소한 배수의 백분위\n'
            '· 최근 활동: 최근 $kRecentWindow회 1·2등 건수의 주변 백분위 (z는 본인 과거 속도 대비)\n'
            '· Store 엔진 후보: 이번 회차 Store 엔진 지역 후보 시도에 속하면 1\n'
            '· 지역 연구: 시·군·구 1등 비율(축소 추정)/기준의 주변 백분위\n'
            '· 접근성: 1 − 거리/반경\n'
            '상태 표시: 검증 통과 = 순방향 검증 게이트 통과 가설, 연구 중 = 검증 미통과, 서술 지표 = 검증 대상이 아닌 관측값.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800, height: 1.45),
          ),
          const SizedBox(height: 6),
          Text('마스터, 판매점별 판매량 자료가 없어 많이 팔리는 곳이 당첨도 많이 나옵니다. '
              '이 점수는 복권 한 장당 당첨확률이 아니며, 검증 통과 여부는 항목별 상태 표시(검증 통과 = 순방향 검증 게이트 통과)를 따릅니다. '
              '영업시간 데이터가 없으니 방문 전 확인하세요.',
              style: TextStyle(fontSize: 10.5, color: Colors.brown.shade700, height: 1.45)),
        ]),
      );

  Widget _errorBox(String msg) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text(msg, style: TextStyle(fontSize: 12, color: Colors.red.shade900)),
      );
}
