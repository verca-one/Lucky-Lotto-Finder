// 경로 기반 추천 화면 (관리자 전용 연구 기능)
//
// 출발지 → 목적지 기본 경로 주변 로또 판매점을 찾아, 각 판매점을 경유했을 때의
// 실제 추가 시간/거리를 같은 라우팅 제공자로 재조회해 순위를 매긴다. 모든 데이터는 읽기 전용.
// 도로 옵션(SharedPreferences 'route_road_option'): 무료도로만(기본, Valhalla 통행료 회피 +
// has_toll 검증) / 전체 도로(사용자가 직접 선택한 경우만). Valhalla 실패 시 OSRM 대체
// (통행료 회피 미보장 명시, 무료도로 확정 표시 금지).
// 외부 API 정책: routing_service.dart / geocoding_service.dart 상단 주석 참조.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/research/agent_research_repository.dart' show AgentResearchRepository, AgentStoreScore;
import '../services/research/agent_store_evidence.dart';
import '../services/route/external_nav.dart';
import '../services/route/geocoding_service.dart';
import '../services/route/region_research_repository.dart' show RegionIds;
import '../services/route/route_store_recommender.dart';
import '../services/route/route_store_repository.dart';
import '../services/route/routing_service.dart';
import '../widgets/admin_region_store_widgets.dart' show confirmNavFreeRoadNotice;
import '../widgets/agent_store_evidence_widgets.dart';

/// Scaffold 래퍼 (단독 진입용)
class AdminRouteRecommendScreen extends StatelessWidget {
  const AdminRouteRecommendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        title: const Text('경로 기반 추천 (관리자)',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: const AdminRouteRecommendContent(),
    );
  }
}

class _RoutePoint {
  final String name;
  final LatLng point;
  const _RoutePoint(this.name, this.point);

  Map<String, dynamic> toJson() =>
      {'name': name, 'lat': point.latitude, 'lng': point.longitude};

  static _RoutePoint? fromJson(dynamic j) {
    if (j is! Map) return null;
    final lat = (j['lat'] as num?)?.toDouble();
    final lng = (j['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return _RoutePoint((j['name'] ?? '').toString(), LatLng(lat, lng));
  }
}

/// 탭 내부용 콘텐츠 (Scaffold 없음)
class AdminRouteRecommendContent extends StatefulWidget {
  const AdminRouteRecommendContent({super.key});

  @override
  State<AdminRouteRecommendContent> createState() =>
      _AdminRouteRecommendContentState();
}

class _AdminRouteRecommendContentState
    extends State<AdminRouteRecommendContent> {
  static const _recentKey = 'route_recent_destinations';
  static const _maxRecent = 5;

  final _geocoder = NominatimGeocodingService();
  final _osrm = OsrmRouteProvider();
  final _valhallaFree = ValhallaRouteProvider(avoidTolls: true);
  final _valhallaAll = ValhallaRouteProvider(avoidTolls: false);
  final _repo = RouteStoreRepository();

  /// 도로 옵션 — 저장값 없으면 free_only. 자동으로 all 로 바꾸지 않는다.
  RoadOption _roadOption = RoadOption.freeOnly;

  ValhallaRouteProvider get _valhalla =>
      _roadOption.avoidTolls ? _valhallaFree : _valhallaAll;

  /// 기본 경로용: Valhalla → 실패 시 OSRM 대체
  RouteProvider get _baseProvider => FallbackRouteProvider(
        primary: _valhalla,
        fallback: _osrm,
        tollAvoidRequested: _roadOption.avoidTolls,
      );

  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _mapCtrl = MapController();
  final _scrollCtrl = ScrollController();
  final Map<String, GlobalKey> _cardKeys = {};

  bool _adminChecked = false;
  bool _isAdmin = false;

  _RoutePoint? _origin;
  _RoutePoint? _dest;
  List<_RoutePoint> _recent = [];

  // GPS 상태
  Position? _gpsPos;
  bool _gpsLoading = false;
  String? _gpsError;

  // 필터
  double _radiusKm = 3;
  int _maxDetourMin = 10;
  RouteRecommendMode _mode = RouteRecommendMode.minDetour;
  bool _preferOpenCheck = false;

  // 결과
  bool _loading = false;
  String _progress = '';
  String? _error;
  RouteRecommendResult? _result;
  RouteStoreRecommendation? _selected;
  bool _mapReady = false;

  /// 지방장 점수 (표시 전용 배지 — 경로 추천 순위·무료도로 기본값에는 영향 없음)
  Map<String, AgentStoreScore> _agentScores = const {};

  /// 판매점별 지방장 근거 (결과 목록 일괄 조회)
  AgentEvidenceBundle? _bundle;
  bool _bundleLoading = false;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
    _loadRecent();
    _loadRoadOption();
  }

  Future<void> _loadRoadOption() async {
    final prefs = await SharedPreferences.getInstance();
    final opt = RoadOptionInfo.fromStorage(prefs.getString(RoadOptionInfo.prefsKey));
    if (mounted) setState(() => _roadOption = opt);
  }

  /// 사용자가 직접 선택한 경우에만 저장 (전체 도로 포함)
  Future<void> _setRoadOption(RoadOption opt) async {
    setState(() => _roadOption = opt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(RoadOptionInfo.prefsKey, opt.storageValue);
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    _mapCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── 관리자 판별: isAdmin 이 true 가 아니면 즉시 pop + 스낵바 ─────────────
  Future<void> _checkAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final isAdmin = prefs.getBool('isAdmin') ?? false;
    if (!mounted) return;
    setState(() {
      _isAdmin = isAdmin;
      _adminChecked = true;
    });
    if (!isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('관리자 전용 기능입니다.')));
        Navigator.of(context).maybePop();
      });
    }
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        final parsed = list.map(_RoutePoint.fromJson).whereType<_RoutePoint>().toList();
        if (mounted) setState(() => _recent = parsed);
      }
    } catch (_) {}
  }

  Future<void> _saveRecent(_RoutePoint p) async {
    final list = [p, ..._recent.where((r) => r.name != p.name)].take(_maxRecent).toList();
    setState(() => _recent = list);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recentKey, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  // ── 지오코딩 (버튼/submit 시에만 호출: Nominatim 자동완성 금지) ───────────
  Future<void> _searchPlace({required bool isOrigin}) async {
    final q = (isOrigin ? _originCtrl : _destCtrl).text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    List<GeoPlace> places;
    try {
      places = await _geocoder.search(q);
    } on GeocodingException catch (e) {
      _snack('검색 실패: ${e.message}');
      return;
    }
    if (!mounted) return;
    if (places.isEmpty) {
      _snack('검색 결과 없음: "$q"');
      return;
    }
    final picked = await showModalBottomSheet<GeoPlace>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('검색 결과 (Nominatim · OpenStreetMap)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final p in places)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(p.address, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final rp = _RoutePoint(picked.name, picked.point);
    setState(() {
      if (isOrigin) {
        _origin = rp;
        _originCtrl.text = picked.name;
      } else {
        _dest = rp;
        _destCtrl.text = picked.name;
      }
    });
  }

  // ── 현재 위치: getCurrentPosition (캐시 좌표 사용 금지) ───────────────────
  Future<void> _useCurrentLocation() async {
    setState(() {
      _gpsLoading = true;
      _gpsError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw '위치 서비스가 꺼져 있습니다. 출발지를 수동 입력하세요.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'GPS 권한 거부됨. 출발지를 수동 입력하세요.';
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      if (!mounted) return;
      final p = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _gpsPos = pos;
        _origin = _RoutePoint('현재 위치', p);
        _originCtrl.text =
            '현재 위치 (${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)})';
      });
    } catch (e) {
      if (mounted) setState(() => _gpsError = e.toString());
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  void _swap() {
    setState(() {
      final o = _origin;
      _origin = _dest;
      _dest = o;
      final t = _originCtrl.text;
      _originCtrl.text = _destCtrl.text;
      _destCtrl.text = t;
    });
  }

  // ── 경로 검색 + 추천 ───────────────────────────────────────────────────
  Future<void> _run() async {
    final o = _origin, d = _dest;
    if (o == null || d == null) {
      _snack('출발지와 목적지를 모두 선택하세요 (검색 후 결과를 선택).');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _selected = null;
      _agentScores = const {};
      _progress = '기본 경로 조회 중 (Valhalla · ${_roadOption.label})…';
    });
    try {
      final roadOption = _roadOption;
      final base = await _baseProvider.route([o.point, d.point]);
      if (base == null) {
        throw '기본 경로를 찾을 수 없습니다 (네트워크 오류 또는 경로 없음). '
            'Valhalla·OSRM 공개 서버 상태를 확인하세요.';
      }
      // 경유 경로는 기본 경로와 같은 제공자로만 계산 (ΔT/ΔL 비교 일관성).
      // 기본이 OSRM 대체였으면 경유도 OSRM(대체 표시), Valhalla 였으면 Valhalla 만.
      final RouteProvider viaProvider = base.fallbackUsed
          ? FallbackRouteProvider(
              primary: _NullRouteProvider(),
              fallback: _osrm,
              tollAvoidRequested: roadOption.avoidTolls)
          : _valhalla;
      final recommender = RouteStoreRecommender(viaProvider,
          perRequestDelay: base.fallbackUsed
              ? const Duration(milliseconds: 250)
              : Duration.zero); // Valhalla 는 provider 내부 1초 스로틀
      if (base.polyline.isEmpty) throw '경로 폴리라인이 비어 있습니다.';
      setState(() => _progress = '경로 주변 판매점 조회 중…');
      final box = RouteGeo.boundingBox(base.polyline, _radiusKm);
      final stores = await _repo.loadLottoStoresInBox(box);
      if (stores.isEmpty) {
        throw '경로 주변(bounding box)에 좌표가 유효한 로또 판매점이 없습니다.';
      }
      final inRadius =
          RouteStoreRecommender.filterByRoute(stores, base.polyline, _radiusKm);
      if (inRadius.isEmpty) {
        throw '반경 ${_radiusKm.toStringAsFixed(0)}km 내 후보 판매점이 없습니다. 반경을 늘려보세요.';
      }
      final top = RouteStoreRecommender.selectTopCandidates(inRadius);
      setState(() => _progress = '엔진 근거 조회 중 (${top.length}곳)…');
      final insights = await _repo.loadInsights(top.map((s) => s.code).toList());
      final opts = RouteRecommendOptions(
        radiusKm: _radiusKm,
        maxDetourMin: _maxDetourMin,
        mode: _mode,
        preferOpenCheck: _preferOpenCheck,
        departureTime: DateTime.now(),
        roadOption: roadOption,
      );
      final res = await recommender.recommend(
        origin: o.point,
        destination: d.point,
        baseRoute: base,
        stores: inRadius,
        insights: insights,
        options: opts,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _progress =
                '우회 경로 조회 $done/$total (${base.fallbackUsed ? 'OSRM 대체' : 'Valhalla'})…');
          }
        },
      );
      await _saveRecent(d);
      if (!mounted) return;
      setState(() => _result = res);
      _fitMap();
      _loadAgentScores(res);
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

  /// 결과 판매점의 지방장 점수 (테이블 없음/오류 → 배지 없음)
  Future<void> _loadAgentScores(RouteRecommendResult res) async {
    try {
      // 지방장 id = 주소 기준 시·군·구 region_id (인터넷 판매점은 'internet'). 판정 불가가 있으면 회차 전체 조회.
      final agentIds = AgentResearchRepository.agentIdsOf(res.items.map((i) =>
          RegionIds.isInternet(i.store.region, i.store.address)
              ? 'internet'
              : RegionIds.fromStore(region: i.store.region, address: i.store.address)));
      final l = await AgentResearchRepository()
          .loadLatestStoreScores(res.items.map((i) => i.store.code).toList(), agentIds: agentIds);
      if (mounted && identical(_result, res)) setState(() => _agentScores = l.data);
    } catch (_) {}
    if (!mounted || !identical(_result, res)) return;
    setState(() {
      _bundle = null;
      _bundleLoading = true;
    });
    try {
      final b = await AgentEvidenceBundle.load([
        for (final i in res.items)
          (
            i.store.code,
            RegionIds.isInternet(i.store.region, i.store.address)
                ? 'internet'
                : RegionIds.fromStore(region: i.store.region, address: i.store.address)
          ),
      ], scores: _agentScores);
      if (mounted && identical(_result, res)) setState(() => _bundle = b);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _bundleLoading = false);
    }
  }

  void _fitMap() {
    final r = _result;
    if (r == null || !_mapReady) return;
    try {
      final pts = <LatLng>[
        ...r.baseRoute.polyline,
        ...r.items.map((i) => i.store.point),
      ];
      if (pts.length < 2) return;
      _mapCtrl.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(36),
      ));
    } catch (_) {
      // 지도 실패 시에도 목록은 사용 가능
    }
  }

  void _select(RouteStoreRecommendation item, {bool scroll = false}) {
    setState(() => _selected = _selected?.store.code == item.store.code ? null : item);
    if (scroll && _selected != null) {
      final key = _cardKeys[item.store.code];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300), alignment: 0.1);
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── 내비 실행 시트 ────────────────────────────────────────────────────
  Future<void> _showNavSheet(RouteStoreRecommendation item) async {
    final o = _origin, d = _dest;
    if (o == null || d == null) return;
    final origin = NavPoint(o.point, o.name);
    final dest = NavPoint(d.point, d.name);
    final via = NavPoint(item.store.point, item.store.name);
    final installed = <NavApp, bool>{};
    for (final a in NavApp.values) {
      installed[a] = await ExternalNav.isInstalled(a);
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('내비 실행 — ${item.store.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text('${o.name} → ${item.store.name}(경유) → ${d.name}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                if (_roadOption == RoadOption.freeOnly)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(kNavFreeRoadNotice, style: TextStyle(fontSize: 11)),
                  ),
                const SizedBox(height: 10),
                for (final app in NavApp.values) ...[
                  Row(children: [
                    Expanded(
                      child: Text('${app.label}  ${installed[app] == true ? '(설치됨)' : '(미설치/조회 불가)'}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  Text(app.waypointNote,
                      style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  Text(app.tollNote,
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade900)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (app.waypointOfficial)
                      FilledButton.tonal(
                        onPressed: () async {
                          if (!await confirmNavFreeRoadNotice(ctx, app,
                              roadOption: _roadOption)) {
                            return;
                          }
                          final r = await ExternalNav.launchRoute(
                              app: app, origin: origin, waypoint: via, destination: dest);
                          _snack(r.message);
                        },
                        child: const Text('경유지 포함 실행'),
                      )
                    else
                      OutlinedButton(
                        onPressed: () async {
                          if (!await confirmNavFreeRoadNotice(ctx, app,
                              roadOption: _roadOption)) {
                            return;
                          }
                          final r = await ExternalNav.launchRoute(
                              app: app,
                              origin: origin,
                              waypoint: via,
                              destination: dest,
                              tmapUnofficialWaypoint: true);
                          _snack('${r.message} (경유지 파라미터 미확인)');
                        },
                        child: const Text('경유지 포함 (미확인)'),
                      ),
                    FilledButton.tonal(
                      onPressed: () async {
                        if (!await confirmNavFreeRoadNotice(ctx, app,
                            roadOption: _roadOption)) {
                          return;
                        }
                        final r = await ExternalNav.launchRoute(
                            app: app, origin: origin, destination: via);
                        _snack(r.message);
                      },
                      child: const Text('판매점을 목적지로'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        if (!await confirmNavFreeRoadNotice(ctx, app,
                            roadOption: _roadOption)) {
                          return;
                        }
                        final r = await ExternalNav.launchRoute(
                            app: app, origin: via, destination: dest);
                        _snack(r.message);
                      },
                      child: const Text('판매점 → 원래 목적지'),
                    ),
                    if (installed[app] != true)
                      TextButton(
                        onPressed: () => ExternalNav.openStore(app),
                        child: const Text('스토어 열기'),
                      ),
                  ]),
                  const Divider(height: 18),
                ],
                const Text(
                  '※ 외부 앱의 경로·소요시간·통행료는 각 앱 기준이며 본 화면의 Valhalla/OSRM 추정(교통 미반영)과 다를 수 있습니다.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_adminChecked) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_isAdmin) {
      return const Center(child: Text('관리자 전용 기능입니다.'));
    }
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _buildInputs(),
        _buildFilters(),
        if (_loading) _buildLoading(),
        if (_error != null) _buildError(),
        if (_result != null) ...[
          _buildMap(),
          _buildHeader(),
          for (final item in _result!.items) _buildCard(item),
          if (_result!.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('후보 판매점이 없습니다.'),
            ),
        ],
      ],
    );
  }

  Widget _buildInputs() {
    return Container(
      color: Colors.deepOrange.shade50,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _originCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: '출발지',
                  hintText: '주소·장소명 입력 후 검색',
                  prefixIcon: const Icon(Icons.trip_origin, size: 18),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => _searchPlace(isOrigin: true),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _searchPlace(isOrigin: true),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: '현재 위치',
              onPressed: _gpsLoading ? null : _useCurrentLocation,
              icon: _gpsLoading
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ]),
          if (_gpsPos != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                'GPS 정확도 ±${_gpsPos!.accuracy.toStringAsFixed(0)}m · 갱신 ${_fmtDateTime(_gpsPos!.timestamp)}',
                style: TextStyle(fontSize: 11, color: Colors.green.shade800),
              ),
            ),
          if (_gpsError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(_gpsError!,
                  style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
            ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _destCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: '목적지',
                  hintText: '주소·장소명 입력 후 검색',
                  prefixIcon: const Icon(Icons.flag, size: 18),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => _searchPlace(isOrigin: false),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _searchPlace(isOrigin: false),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: '출발지 ↔ 목적지 교환',
              onPressed: _swap,
              icon: const Icon(Icons.swap_vert),
            ),
          ]),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  const Center(
                      child: Text('최근: ', style: TextStyle(fontSize: 12, color: Colors.black54))),
                  for (final r in _recent)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(r.name, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() {
                          _dest = r;
                          _destCtrl.text = r.name;
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                onPressed: _loading ? null : _run,
                icon: const Icon(Icons.alt_route),
                label: const Text('경로 검색 + 경유 판매점 추천'),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            '선택: ${_origin?.name ?? '-'} → ${_dest?.name ?? '-'}',
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    Widget chips<T>(String label, List<T> values, T current, String Function(T) fmt,
        void Function(T) onSel) {
      return Row(children: [
        SizedBox(width: 56, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Wrap(
            spacing: 6,
            children: [
              for (final v in values)
                ChoiceChip(
                  label: Text(fmt(v), style: const TextStyle(fontSize: 12)),
                  selected: v == current,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onSel(v),
                ),
            ],
          ),
        ),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          chips<RoadOption>('도로', RoadOption.values, _roadOption, (v) => v.label,
              (v) => _setRoadOption(v)),
          Padding(
            padding: const EdgeInsets.only(left: 56, bottom: 4),
            child: Text(
              _roadOption == RoadOption.freeOnly
                  ? '무료도로: Valhalla(OSM) 통행료 회피 + has_toll 검증. 실패 시 OSRM 대체(회피 미보장).'
                  : '전체 도로: 유료도로 포함 최단시간 경로 (사용자 선택).',
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ),
          chips<double>('반경', const [1, 3, 5], _radiusKm, (v) => '${v.toStringAsFixed(0)}km',
              (v) => setState(() => _radiusKm = v)),
          chips<int>('최대우회', const [5, 10, 15, 30], _maxDetourMin, (v) => '$v분',
              (v) => setState(() => _maxDetourMin = v)),
          chips<RouteRecommendMode>('모드', RouteRecommendMode.values, _mode, (v) => v.label,
              (v) => setState(() => _mode = v)),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('영업 확인 우선', style: TextStyle(fontSize: 12)),
            subtitle: const Text('영업시간 데이터 없음 → 모든 판매점 "확인 필요" (출발 전 전화 확인 권장)',
                style: TextStyle(fontSize: 10)),
            value: _preferOpenCheck,
            onChanged: (v) => setState(() => _preferOpenCheck = v),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 8),
          Text(_progress, style: const TextStyle(fontSize: 12)),
        ]),
      );

  Widget _buildError() => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red.shade900))),
        ]),
      );

  Widget _buildMap() {
    final r = _result!;
    final via = _selected?.viaRoute;
    final center = r.baseRoute.polyline.isNotEmpty
        ? r.baseRoute.polyline[r.baseRoute.polyline.length ~/ 2]
        : (_origin?.point ?? const LatLng(37.5665, 126.978));
    return SizedBox(
      height: 300,
      child: FlutterMap(
        mapController: _mapCtrl,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 11,
          onMapReady: () {
            _mapReady = true;
            _fitMap();
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.luckylotto.finder',
          ),
          PolylineLayer(polylines: [
            Polyline(points: r.baseRoute.polyline, color: Colors.blue, strokeWidth: 4),
            if (via != null)
              Polyline(points: via.polyline, color: Colors.orange, strokeWidth: 4),
          ]),
          MarkerLayer(markers: [
            if (_origin != null)
              Marker(
                point: _origin!.point,
                width: 32,
                height: 32,
                child: const Icon(Icons.trip_origin, color: Colors.green, size: 28),
              ),
            if (_dest != null)
              Marker(
                point: _dest!.point,
                width: 32,
                height: 32,
                child: const Icon(Icons.flag, color: Colors.red, size: 28),
              ),
            for (final item in r.items)
              Marker(
                point: item.store.point,
                width: 30,
                height: 30,
                child: GestureDetector(
                  onTap: () => _select(item, scroll: true),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _selected?.store.code == item.store.code
                          ? Colors.orange
                          : Colors.deepOrange.shade700,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text('${item.rank}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final r = _result!;
    return Container(
      width: double.infinity,
      color: Colors.orange.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '기본 경로 ${r.baseRoute.distanceKm.toStringAsFixed(1)}km · '
            '${r.baseRoute.durationMin.toStringAsFixed(0)}분 '
            '(${r.baseRoute.provider}${r.baseRoute.fallbackUsed ? ' 대체' : ''}, 교통 미반영)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          Text(
            '${r.options.roadOption.label} · 통행료 회피 적용: '
            '${r.baseRoute.tollAvoidRequested && !r.baseRoute.fallbackUsed ? '예' : '아니오'}'
            '${r.baseRoute.fallbackUsed ? ' ($kTollFallbackNote)' : ''} · 검증: '
            '${r.baseRoute.tollCheck.label(fallback: r.baseRoute.fallbackUsed, avoidRequested: r.options.roadOption.avoidTolls)}'
            '${r.baseRoute.confirmedTollFree ? ' · 무료도로 확인' : ''}',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: r.baseRoute.confirmedTollFree
                    ? Colors.green.shade800
                    : Colors.brown.shade700),
          ),
          if (r.baseRouteTollWarning != null)
            Text('⚠ 기본 경로: ${r.baseRouteTollWarning}',
                style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
          if (r.tollDemotedCount > 0)
            Text('유료구간 포함 후보 ${r.tollDemotedCount}곳은 무료도로 모드에서 후순위',
                style: TextStyle(fontSize: 10, color: Colors.red.shade700)),
          const SizedBox(height: 2),
          Text(r.headerNote, style: TextStyle(fontSize: 11, color: Colors.orange.shade900)),
          const SizedBox(height: 2),
          Text(r.disclaimer, style: const TextStyle(fontSize: 10, color: Colors.black54)),
          const Text(kTollDataDisclaimer,
              style: TextStyle(fontSize: 10, color: Colors.black54)),
          if (_preferOpenCheck)
            const Text('영업 확인 우선: 영업시간 데이터가 없어 정렬에 반영되지 않습니다. 각 판매점 영업 여부를 직접 확인하세요.',
                style: TextStyle(fontSize: 10, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildCard(RouteStoreRecommendation item) {
    final key = _cardKeys.putIfAbsent(item.store.code, () => GlobalKey());
    final selected = _selected?.store.code == item.store.code;
    final ins = item.insight;
    final via = item.viaRoute;
    final detourText = item.detourVerified
        ? '추가 +${item.deltaTimeMin!.toStringAsFixed(1)}분 · +${item.deltaDistKm!.toStringAsFixed(1)}km '
            '(${via?.provider ?? '-'} 실제 경로값)'
        : kDetourUnverified;
    final totalText = via == null
        ? '경유 경로 총거리·시간: 미확인'
        : '경유 경로 총 ${via.distanceKm.toStringAsFixed(1)}km · ${via.durationMin.toStringAsFixed(0)}분';
    final tollColor = item.tollDemoted
        ? Colors.red.shade700
        : (via?.confirmedTollFree == true ? Colors.green.shade800 : Colors.brown.shade700);
    final etaText = item.eta == null
        ? '예상 도착: 미확인'
        : '예상 도착 ${_fmtDateTime(item.eta!)} ($kEtaNote)';

    return Card(
      key: key,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: selected ? Colors.orange : Colors.grey.shade300, width: selected ? 2 : 1),
      ),
      child: InkWell(
        onTap: () => _select(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: Colors.deepOrange,
                  child: Text('${item.rank}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.store.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(item.store.address,
                          style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _tag('1등 ${ins.historyFirst}회', Colors.red),
                _tag('2등 ${ins.historySecond}회', Colors.blue),
                _tag(item.openStatus, Colors.grey),
                if (item.etaAfterSalesClose) _tag('⚠ 토 20:00 판매 마감 이후 도착', Colors.red),
                if (item.detourGroup == DetourGroup.overLimit)
                  _tag('최대 우회 초과', Colors.orange),
                if (via?.confirmedTollFree == true) _tag('무료도로 확인', Colors.green),
                if (item.tollDemoted) _tag('유료구간 포함', Colors.red),
                if (via?.fallbackUsed == true) _tag('OSRM 대체·통행료 미검증', Colors.brown),
                if (ins.verifiedHypothesisCount > 0)
                  _tag('명당연구소 검증 통과 ${ins.verifiedHypothesisCount}', Colors.green),
                if (ins.researchingHypothesisCount > 0)
                  _tag('연구 중 ${ins.researchingHypothesisCount}', Colors.teal),
                if (!ins.hasAnyAnalysis) _tag(kNoEngineResult, Colors.grey),
                if (ins.dataRound != null) _tag('데이터 기준 ${ins.dataRound}회차', Colors.indigo),
                if (_agentScores[item.store.code] != null)
                  _tag('지방장 ${_agentScores[item.store.code]!.agentRank}/${_agentScores[item.store.code]!.agentSize}위'
                      ' (${_agentScores[item.store.code]!.targetRound}회 · 판매량 미보정)',
                      Colors.teal.shade700),
              ]),
              const SizedBox(height: 8),
              Text(detourText,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: item.detourVerified ? Colors.black87 : Colors.red.shade700)),
              Text(totalText, style: const TextStyle(fontSize: 11)),
              Text('${item.tollApplyLabel} · ${item.tollCheckLabel}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tollColor)),
              if (item.tollDemoted)
                Text('⚠ $kTollNotConfirmedWarning (후순위)',
                    style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
              Text(etaText, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              Text(
                '${item.score.mode.label} 점수 ${item.score.total.isFinite ? item.score.total.toStringAsFixed(3) : '∞'}'
                ' · ${item.score.weights.entries.map((e) => '${e.key} ${e.value}').join(', ')}',
                style: const TextStyle(fontSize: 10, color: Colors.black45),
              ),
              const SizedBox(height: 6),
              const Text('지방장 근거', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              if (_bundle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                  child: storeEdgeTag(_bundle!.of(item.store.code).edge),
                ),
              AgentEvidenceCompact(evidence: _bundle?.of(item.store.code), loading: _bundleLoading),
              const SizedBox(height: 6),
              const Text('엔진 추천 이유',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              for (final reason in item.reasons)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Text('• $reason', style: const TextStyle(fontSize: 11)),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _select(item),
                    icon: Icon(selected ? Icons.check_circle : Icons.add_location_alt_outlined,
                        size: 16),
                    label: Text(selected ? '경유지 선택됨' : '경유지로 선택',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                    onPressed: () => _showNavSheet(item),
                    icon: const Icon(Icons.navigation, size: 16),
                    label: const Text('내비 실행', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      );

  static String _fmtDateTime(DateTime? t) {
    if (t == null) return '-';
    final l = t.toLocal();
    return '${l.month}/${l.day} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

/// 항상 null 을 반환하는 제공자 (OSRM 대체 표시를 위해 FallbackRouteProvider 와 함께 사용)
class _NullRouteProvider implements RouteProvider {
  @override
  Future<RouteResult?> route(List<LatLng> waypoints) async => null;
}
