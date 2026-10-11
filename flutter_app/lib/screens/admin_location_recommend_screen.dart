// 현 위치 추천 (관리자 전용 연구 기능)
//
// geolocator getCurrentPosition (캐시 위치 사용 금지) → 반경 1/3/5km 내 로또 판매점
// (행정 경계 무관, Haversine) → 거리순 / 엔진 종합순.
// 현재 위치의 시·군·구(가장 가까운 판매점의 region_id 또는 research_region_units 중심 최근접)와
// 인접 생활권(neighbors) 연구를 함께 표시한다. 모든 데이터는 읽기 전용.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/research/agent_store_evidence.dart';
import '../services/route/external_nav.dart';
import '../services/route/region_research_repository.dart';
import '../services/route/route_store_recommender.dart' show RouteGeo;
import '../widgets/admin_region_store_widgets.dart';

class AdminLocationRecommendContent extends StatefulWidget {
  /// 권한 거부 등으로 지역을 수동 선택할 때 지역 추천 탭으로 이동 (regionId 는 선택 사항)
  final void Function(String? regionId)? onOpenRegion;
  const AdminLocationRecommendContent({super.key, this.onOpenRegion});

  @override
  State<AdminLocationRecommendContent> createState() =>
      _AdminLocationRecommendContentState();
}

class _AdminLocationRecommendContentState extends State<AdminLocationRecommendContent> {
  final _repo = RegionResearchRepository();

  bool _adminChecked = false;
  bool _isAdmin = false;

  Position? _pos;
  bool _gpsLoading = false;
  String? _gpsError;
  bool _permissionDenied = false;

  double _radiusKm = 3;
  RegionSort _sort = RegionSort.distance;

  bool _loading = false;
  String _progress = '';
  String? _error;
  List<RegionStore> _stores = [];
  RegionEngineInputs? _inputs;
  RegionRankingResult? _result;
  String? _selectedCode;

  // 판매점별 지방장 근거 (목록 일괄 조회)
  AgentEvidenceBundle? _bundle;
  bool _bundleLoading = false;

  // 현재 지역 · 인접 생활권
  String? _currentRegionId;
  String _currentRegionBasis = '';
  RegionUnit? _currentUnit;
  ResearchLoad<Map<String, RegionStats>>? _neighborStats;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final isAdmin = prefs.getBool('isAdmin') ?? false;
    if (!mounted) return;
    setState(() {
      _isAdmin = isAdmin;
      _adminChecked = true;
    });
  }

  LatLng? get _me => _pos == null ? null : LatLng(_pos!.latitude, _pos!.longitude);

  /// 현재 위치 새로 측정 (getCurrentPosition, getLastKnownPosition 미사용) 후 추천
  Future<void> _locateAndRecommend() async {
    setState(() {
      _gpsLoading = true;
      _gpsError = null;
      _permissionDenied = false;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _permissionDenied = true;
        throw '위치 서비스가 꺼져 있습니다. 지역을 수동으로 선택하세요.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _permissionDenied = true;
        throw '위치 권한이 거부되었습니다. 지역을 수동으로 선택하세요.';
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      if (!mounted) return;
      setState(() => _pos = pos);
      await _recommend();
    } catch (e) {
      if (mounted) setState(() => _gpsError = e.toString());
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _recommend() async {
    final me = _me;
    if (me == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _selectedCode = null;
      _bundle = null;
      _progress = '반경 ${_radiusKm.toStringAsFixed(0)}km 판매점 조회 중…';
    });
    try {
      final stores = await _repo.loadStoresNear(me, _radiusKm);
      if (!mounted) return;
      _stores = stores;
      // 현재 시·군·구: 가장 가까운 판매점의 region_id → 없으면 연구 단위 중심 최근접
      _resolveCurrentRegion(me, stores);
      final unitsLoad = await _repo.loadUnits();
      if (_currentRegionId == null) {
        _nearestUnitRegion(me, unitsLoad.data);
      }
      _currentUnit = _currentRegionId == null
          ? null
          : unitsLoad.data.where((u) => u.regionId == _currentRegionId).firstOrNull;

      if (stores.isEmpty) {
        throw '반경 ${_radiusKm.toStringAsFixed(0)}km 내 좌표가 확인된 로또 판매점이 없습니다. 반경을 늘려보세요.';
      }
      setState(() => _progress = '엔진 근거 조회 중 (${stores.length}곳)…');
      final regionIds = stores.map((s) => s.regionId).whereType<String>().toSet();
      final inputs = await _repo.loadEngineInputs(stores, regionIds);
      _inputs = inputs;
      _rerank();
      _loadBundle();

      final statIds = <String>{
        ?_currentRegionId,
        ...?_currentUnit?.neighbors.map((n) => n.regionId),
      }.toList()
        ..sort();
      final ns = await _repo.loadLatestStats(statIds);
      if (mounted) setState(() => _neighborStats = ns);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = '';
        });
      }
    }
  }

  void _resolveCurrentRegion(LatLng me, List<RegionStore> stores) {
    _currentRegionId = null;
    _currentRegionBasis = '';
    RegionStore? best;
    var bestD = double.infinity;
    for (final s in stores) {
      if (s.point == null || s.regionId == null) continue;
      final d = RouteGeo.haversineM(me, s.point!);
      if (d < bestD || (d == bestD && best != null && s.code.compareTo(best.code) < 0)) {
        bestD = d;
        best = s;
      }
    }
    if (best != null) {
      _currentRegionId = best.regionId;
      _currentRegionBasis = '가장 가까운 판매점(${best.name}, ${fmtKm(bestD)}) 주소 기준';
    }
  }

  void _nearestUnitRegion(LatLng me, List<RegionUnit> units) {
    RegionUnit? best;
    var bestD = double.infinity;
    for (final u in units) {
      if (u.center == null) continue;
      final d = RouteGeo.haversineM(me, u.center!);
      if (d < bestD) {
        bestD = d;
        best = u;
      }
    }
    if (best != null) {
      _currentRegionId = best.regionId;
      _currentRegionBasis = '지역 단위 중심 최근접 (${fmtKm(bestD)})';
    }
  }

  void _rerank() {
    final inputs = _inputs;
    if (inputs == null) return;
    final ranked =
        RegionStoreRanker.rank(stores: _stores, inputs: inputs, origin: _me, sort: _sort);
    setState(() => _result = RegionStoreRanker.buildResult(ranked, inputs));
  }

  NavPoint? get _origin => _me == null ? null : NavPoint(_me!, '현재 위치');

  Future<void> _loadBundle() async {
    final res = _result;
    if (res == null) return;
    setState(() => _bundleLoading = true);
    try {
      final b = await loadEvidenceForRanked(res.items);
      if (mounted) setState(() => _bundle = b);
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
    if (!_adminChecked) return const Center(child: CircularProgressIndicator());
    if (!_isAdmin) return const Center(child: Text('관리자 전용 기능입니다.'));
    final r = _result;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _buildControls(),
        if (_loading)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(_progress, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        if (_error != null) _errorBox(_error!),
        if (_currentRegionId != null) _buildCurrentRegion(),
        if (r != null) ...[
          RegionStoresMap(
            items: r.items,
            selectedCode: _selectedCode,
            me: _me,
            radiusKm: _radiusKm,
            onTapStore: _openDetail,
          ),
          RegionRankingHeader(
            result: r,
            title: '반경 ${_radiusKm.toStringAsFixed(0)}km 내 ${r.items.length}곳 · ${_sort.label}',
          ),
          for (final item in r.items)
            RegionStoreCard(
              item: item,
              selected: item.store.code == _selectedCode,
              onTap: () => _openDetail(item),
              onNav: () => showStoreNavSheet(context,
                  name: item.store.name, point: item.store.point!, origin: _origin),
              evidence: _ev(item),
              evidenceLoading: _bundleLoading,
            ),
        ],
      ],
    );
  }

  Widget _buildControls() {
    final pos = _pos;
    return Container(
      color: Colors.deepOrange.shade50,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                onPressed: (_gpsLoading || _loading) ? null : _locateAndRecommend,
                icon: _gpsLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(pos == null ? Icons.my_location : Icons.refresh),
                label: Text(pos == null ? '현재 위치로 추천' : '현장 도착 후 다시 추천'),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          if (pos != null)
            Text(
              '정확도 ±${pos.accuracy.toStringAsFixed(0)}m · 갱신 ${_fmt(pos.timestamp)} · '
              '(${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})',
              style: TextStyle(fontSize: 11, color: Colors.green.shade800),
            )
          else
            const Text('위치는 매번 새로 측정합니다 (캐시 위치 미사용).',
                style: TextStyle(fontSize: 11, color: Colors.black54)),
          if (_gpsError != null) ...[
            const SizedBox(height: 4),
            Text(_gpsError!, style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
          ],
          if (_permissionDenied || _gpsError != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onOpenRegion == null ? null : () => widget.onOpenRegion!(null),
                icon: const Icon(Icons.location_city, size: 16),
                label: const Text('지역 수동 선택 (지역 추천 탭으로 이동)'),
              ),
            ),
          const SizedBox(height: 4),
          Row(children: [
            const SizedBox(width: 44, child: Text('반경', style: TextStyle(fontSize: 12))),
            for (final v in const [1.0, 3.0, 5.0])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('${v.toStringAsFixed(0)}km', style: const TextStyle(fontSize: 12)),
                  selected: _radiusKm == v,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    setState(() => _radiusKm = v);
                    if (_me != null && !_loading) _recommend();
                  },
                ),
              ),
          ]),
          Row(children: [
            const SizedBox(width: 44, child: Text('정렬', style: TextStyle(fontSize: 12))),
            for (final s in RegionSort.values.reversed)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(s.label, style: const TextStyle(fontSize: 12)),
                  selected: _sort == s,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    setState(() => _sort = s);
                    _rerank();
                  },
                ),
              ),
          ]),
          const Text('반경은 행정 경계와 무관한 직선거리(Haversine)입니다. 영업시간 데이터 없음 → 방문 전 확인 필요.',
              style: TextStyle(fontSize: 10, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildCurrentRegion() {
    final id = _currentRegionId!;
    final u = _currentUnit;
    final ns = _neighborStats;
    String statLine(String rid) {
      final s = ns?.data[rid];
      if (s == null) return ns == null ? '조회 중' : ns.state.label;
      final pct = s.shrunkRate == null ? '-' : '${(s.shrunkRate! * 100).toStringAsFixed(2)}%';
      return '축소추정 $pct · 1등 공백 ${s.dormantRounds ?? '-'}회 · 추세 z ${s.trendZ?.toStringAsFixed(2) ?? '-'} (기준 ${s.trainingEndRound}회차)';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('현재 지역: ${RegionIds.display(id)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            if (widget.onOpenRegion != null)
              TextButton(
                onPressed: () => widget.onOpenRegion!(id),
                child: const Text('지역 추천 보기', style: TextStyle(fontSize: 12)),
              ),
          ]),
          Text(_currentRegionBasis, style: const TextStyle(fontSize: 10, color: Colors.black54)),
          Text('지역 연구: ${statLine(id)}', style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 4),
          const Text('인접 생활권 (research_region_units.neighbors, 중심 거리 기준)',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          if (u == null || u.derived)
            Text('인접 생활권 연구: ${u == null ? kResearchNoData : kResearchNotApplied} '
                '(research_region_units 미적용 또는 해당 지역 행 없음)',
                style: TextStyle(fontSize: 11, color: Colors.brown.shade700))
          else if (u.neighbors.isEmpty)
            const Text('인접 생활권: 데이터 없음', style: TextStyle(fontSize: 11))
          else
            for (final n in u.neighbors.take(8))
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Text(
                    '• ${RegionIds.display(n.regionId)} (${n.km.toStringAsFixed(1)}km): ${statLine(n.regionId)}',
                    style: const TextStyle(fontSize: 11)),
              ),
        ],
      ),
    );
  }

  static String _fmt(DateTime t) {
    final l = t.toLocal();
    return '${l.month}/${l.day} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}:${l.second.toString().padLeft(2, '0')}';
  }

  Widget _errorBox(String msg) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text(msg, style: TextStyle(fontSize: 12, color: Colors.red.shade900)),
      );
}
