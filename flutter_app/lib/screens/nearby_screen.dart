import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import '../models/lottery_store.dart';
import '../services/supabase_service.dart';
import '../services/badge_service.dart';
import '../services/admin_gate.dart';
import '../services/ranking_extras_service.dart';
import '../widgets/ranking_store_card.dart';
import '../widgets/store_detail_popup.dart';
import '../services/favorites_notifier.dart';
import '../services/rpa_joint_engine.dart';
import '../services/rpa_store_engine.dart';
import 'admin_comprehensive_prediction_screen.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  Position? _currentPosition;
  List<LotteryStore>? _nearbyStores;
  bool _isLoading = false;
  bool _isSearching = false; // 이 지역 검색 로딩
  String? _error;
  final String _selectedGame = 'lotto';
  double _searchRadiusKm = 1.3;
  MapController? _mapController;
  Set<String> _favorites = {};
  Map<String, int> _top30Ranks = {}; // dhlotteryCode -> 순위
  String _userId = '';

  // GPS 정밀도 관련
  bool _isRefiningGps = false;     // 정밀 측정 진행 중
  double? _gpsAccuracy;            // 현재 채택된 위치의 accuracy (m)
  bool _isApproxLocation = false;  // 대략적 위치 권한 사용 중

  static const double _goodAccuracyM  = 30.0;   // 이 이하면 즉시 채택
  static const double _usableAccuracyM = 150.0;  // 이 이하면 사용 가능
  static const Duration _refineTimeout = Duration(seconds: 20);

  // 랜덤확률분석엔진 연동
  int _latestRound = 0;
  List<String> _engineCandidateRegions = []; // Joint Model 유력 지역
  bool _isAnalyzingList = false;
  Map<String, bool> _engineEndorsed = {}; // dhlotteryCode → 엔진 추천 여부
  Map<String, RegionTemporalInfo> _regionTemporal = {}; // sido → 지역 temporal 신호

  bool _mapReady = false; // flutter_map 컨트롤러 attach 완료 여부

  /// 엔진 관련 표시(회차 분석·목록 분석·유력 지역·엔진추천)는 관리자 모드에서만
  bool _isAdmin = false;

  /// 카드 하단 통계(평균 간격 등) — 목록 단위 일괄 조회
  Map<String, RankingStoreExtras> _extras = {};

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadFavorites();
    _loadTop30Ranks();
    _loadUserId();
    _getCurrentLocation();
    _loadLatestRound();
    AdminGate.isAdmin().then((v) { if (mounted) setState(() => _isAdmin = v); });
    favoritesNotifier.addListener(_onFavoritesChanged);
  }

  Future<void> _loadExtras(List<LotteryStore> stores) async {
    try {
      final x = await RankingExtrasService.load(
          stores.map((s) => <String, dynamic>{'dhlottery_code': s.dhlotteryCode}).toList());
      if (mounted) setState(() => _extras = x);
    } catch (_) {}
  }

  void _safeMapMove(double lat, double lng, double zoom) {
    if (!_mapReady) return; // 컨트롤러가 아직 attach되지 않았으면 무시
    try {
      _mapController?.move(LatLng(lat, lng), zoom);
    } catch (_) {} // LateInitializationError 방어
  }

  // ── 랜덤확률분석엔진 연동 ──────────────────────────────────────────

  Future<void> _loadLatestRound() async {
    try {
      final round = await SupabaseService.getLatestRound('lotto');
      if (mounted && round != null) setState(() => _latestRound = round);
    } catch (_) {}
  }

  // 5-9: 현재 목록 판매점을 Joint Model 후보 지역과 대조하여 엔진 추천 표시
  Future<void> _analyzeCurrentList() async {
    if (_nearbyStores == null || _nearbyStores!.isEmpty) return;
    setState(() => _isAnalyzingList = true);
    try {
      final round = _latestRound > 0 ? _latestRound + 1 : null;
      if (round == null) { setState(() => _isAnalyzingList = false); return; }

      // Joint Model 예측에서 유력 지역 로드
      final preds = await JointModelEngine.instance.loadRecentPredictions(limit: 6);
      // 해당 회차 예측만 사용 (다른 회차 예측으로 대체하지 않음)
      final targetPred = preds.where((p) => p['target_round'] == round).firstOrNull;

      List<String> candidates = [];
      if (targetPred != null) {
        candidates = List<String>.from(
            targetPred['joint_candidate_regions'] as List? ?? []);
      }

      // 각 판매점의 지역(sido)이 후보에 포함되는지 확인
      final endorsed = <String, bool>{};
      for (final store in _nearbyStores!) {
        final sido = _getSido(store.region ?? '');
        endorsed[store.dhlotteryCode] = candidates.contains(sido);
      }

      // 지역 temporal 신호: 최근 당첨 현황 로드
      Map<String, RegionTemporalInfo> temporal = {};
      try {
        final storeHistory = await StoreModelEngine.instance.loadWinHistory();
        temporal = computeRegionTemporalSignals(storeHistory, round - 1);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _engineCandidateRegions = candidates;
          _engineEndorsed = endorsed;
          _regionTemporal = temporal;
          _isAnalyzingList = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isAnalyzingList = false);
    }
  }

  String _getSido(String region) {
    if (region.isEmpty) return '';
    final parts = region.split(' ');
    return parts.first;
  }

  // ── GPS 정밀 측정 ────────────────────────────────────────────────

  /// 초기 위치 확보 + 백그라운드에서 정밀도 개선
  Future<void> _getCurrentLocation() async {
    try {
      setState(() { _isLoading = true; _error = null; });

      // 권한 확인
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('위치 권한이 거부되었습니다');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('위치 권한이 영구적으로 거부되었습니다. 설정에서 권한을 변경해주세요.');
      }

      // 빠른 첫 위치: lastKnown (임시 표시용만, 검색에는 쓰지 않음)
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() {
          _currentPosition = lastKnown;
          _gpsAccuracy = lastKnown.accuracy;
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _safeMapMove(lastKnown.latitude, lastKnown.longitude, 14.0);
        });
      }

      // 정밀 측정 시작 (스트림 기반)
      await _refineLocation(triggerSearch: true);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  /// GPS 스트림으로 정밀도 개선.
  /// triggerSearch=true 이면 충분한 정밀도 확보 시 주변판매점 검색.
  Future<void> _refineLocation({bool triggerSearch = false}) async {
    if (_isRefiningGps) return;
    if (mounted) setState(() { _isRefiningGps = true; _isApproxLocation = false; });

    try {
      final deadline = DateTime.now().add(_refineTimeout);
      Position? best = _currentPosition;

      await for (final pos in Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      ).timeout(_refineTimeout, onTimeout: (sink) => sink.close())) {

        if (!mounted) break;

        // 더 정확한 위치만 채택
        if (best == null || pos.accuracy < best.accuracy) {
          best = pos;
          setState(() {
            _currentPosition = pos;
            _gpsAccuracy = pos.accuracy;
            _isLoading = false;
          });
          _safeMapMove(pos.latitude, pos.longitude, 14.0);
        }

        // 충분히 정밀하면 즉시 중단
        if (pos.accuracy <= _goodAccuracyM) break;
        // 타임아웃 체크
        if (DateTime.now().isAfter(deadline)) break;
      }

      if (!mounted) return;
      setState(() => _isRefiningGps = false);

      final finalAcc = best?.accuracy ?? 9999;
      if (finalAcc > _usableAccuracyM) {
        setState(() => _isApproxLocation = true);
      }

      // 검색 트리거: 위치가 확보됐고 아직 검색을 안 했거나 재측정인 경우
      if (triggerSearch && best != null && mounted) {
        await _searchNearbyStores();
      }
    } catch (e) {
      if (mounted) setState(() { _isRefiningGps = false; _isLoading = false; });
    }
  }

  /// 사용자가 [다시 측정] 버튼 누를 때
  Future<void> _remeasureLocation() async {
    if (_isRefiningGps) return;
    setState(() {
      _gpsAccuracy = null;
      _isApproxLocation = false;
    });
    await _refineLocation(triggerSearch: true);
  }

  void _onFavoritesChanged() {
    _loadFavorites();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _userId = prefs.getString('userId') ?? '');
  }

  Future<void> _searchAtMapCenterExtended() async {
    if (_mapController == null) return;
    setState(() => _isSearching = true);
    try {
      final center = _mapController!.camera.center;
      final stores = await SupabaseService.getNearbyStores(
        latitude: center.latitude,
        longitude: center.longitude,
        radiusKm: 5.0,
        lotteryType: _selectedGame,
      );
      BadgeService.clearCache();
      final codes = stores.map((s) => s.dhlotteryCode).toSet().toList();
      await BadgeService.loadBadges(codes);
      _loadExtras(stores);
      setState(() {
        _nearbyStores = stores;
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('반경 5km로 확장 검색 완료!')),
        );
      }
    } catch (e) {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _favorites = (prefs.getStringList('favorite_stores') ?? []).toSet());
  }

  Future<void> _loadTop30Ranks() async {
    final prefs = await SharedPreferences.getInstance();
    final rankList = prefs.getStringList('prev_ranking') ?? [];
    final Map<String, int> ranks = {};
    for (int i = 0; i < rankList.length; i++) {
      ranks[rankList[i]] = i + 1;
    }
    setState(() => _top30Ranks = ranks);
  }

  Future<void> _toggleFavorite(String code) async {
    setState(() {
      if (_favorites.contains(code)) {
        _favorites.remove(code);
      } else {
        _favorites.add(code);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_stores', _favorites.toList());
    notifyFavoritesChanged();
  }

  @override
  void dispose() {
    favoritesNotifier.removeListener(_onFavoritesChanged);
    _mapController?.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _searchNearbyStores() async {
    if (_currentPosition == null) return;

    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Supabase에서 좌표가 있는 판매점만 조회
      final stores = await SupabaseService.getNearbyStores(
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        radiusKm: _searchRadiusKm,
        lotteryType: _selectedGame,
      );

      // 좌표 없는 판매점이 하나도 없을 때 안내
      if (stores.isEmpty) {
        // 좌표 데이터가 아예 없는 건지 확인
        final allStores = await SupabaseService.getAllStores(lotteryType: _selectedGame);
        final hasCoords = allStores.any((s) => s.latitude != null && s.longitude != null);

        if (!hasCoords) {
          setState(() {
            _nearbyStores = [];
            _isLoading = false;
            _error = '판매점 좌표 데이터가 아직 준비되지 않았습니다.\n지오코딩 스크립트를 먼저 실행해주세요.';
          });
          return;
        }
      }

      // store_badges에서 배지 읽기 (종합 - 로또+연금 모두)
      BadgeService.clearCache();
      final codes = stores.map((s) => s.dhlotteryCode).toSet().toList();
      await BadgeService.loadBadges(codes);
      _loadExtras(stores);

      setState(() {
        _nearbyStores = stores;
        _isLoading = false;
      });
      // 판매점이 있을 때만 시트 절반으로 올리기
      if (stores.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sheetController.isAttached) {
            _sheetController.animateTo(
              0.5,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40, height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: const Color(0xFF1565C0),
              ),
            ),
            const SizedBox(height: 16),
            Text('위치를 찾는 중...', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_off_rounded, size: 48, color: Color(0xFF1565C0)),
              ),
              const SizedBox(height: 20),
              Text('위치를 확인할 수 없습니다', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              Text(
                '$_error',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _getCurrentLocation,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentPosition == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.location_searching_rounded, size: 48, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 20),
              Text('위치를 가져올 수 없습니다', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _getCurrentLocation,
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: const Text('위치 다시 가져오기'),
              ),
            ],
          ),
        ),
      );
    }

    // 지도는 항상 표시
    final storeCount = _nearbyStores?.length ?? 0;
    final screenHeight = MediaQuery.of(context).size.height;

    return Stack(
      children: [
        // 전체 화면 지도
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
              ),
              initialZoom: 14.0,
              onTap: (_, __) => setState(() => _selectedMarkerIndex = null),
              onMapReady: () => setState(() => _mapReady = true),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.luckylotto.finder',
              ),
              MarkerLayer(markers: _buildMapMarkers()),
            ],
          ),
        ),

        // 이 주변 검색 버튼 (상단 중앙)
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _isSearching ? null : _searchAtMapCenter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isSearching
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1565C0)),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF1565C0)),
                    const SizedBox(width: 6),
                    const Text(
                      '이 주변 검색',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1565C0)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),


        // 내 위치 버튼 (지도 오른쪽, 시트 위)
        Positioned(
          right: 12,
          bottom: screenHeight * 0.5 + 12,
          child: GestureDetector(
            onTap: _moveToCurrentLocation,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.my_location_rounded, size: 20, color: Color(0xFF1565C0)),
              ),
            ),
          ),
        ),

        // 드래그 가능한 근처 당첨지점 시트
        DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: 0.09,
          minChildSize: 0.09,
          maxChildSize: 0.92,
          snap: true,
          snapSizes: const [0.09, 0.5, 0.92],
          builder: (context, scrollController) {
            _listScrollController = scrollController;
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 12,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 손잡이 바 (드래그 + 탭)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (!_sheetController.isAttached) return;
                      final current = _sheetController.size;
                      double target;
                      if (current < 0.3) {
                        target = 0.5;
                      } else if (current < 0.7) {
                        target = 0.92;
                      } else {
                        target = 0.09;
                      }
                      _sheetController.animateTo(
                        target,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    },
                    onVerticalDragUpdate: (details) {
                      if (!_sheetController.isAttached) return;
                      final screenH = MediaQuery.of(context).size.height;
                      final delta = -details.delta.dy / screenH;
                      final next = (_sheetController.size + delta).clamp(0.09, 0.92);
                      _sheetController.jumpTo(next);
                    },
                    onVerticalDragEnd: (details) {
                      if (!_sheetController.isAttached) return;
                      final current = _sheetController.size;
                      // 속도 기반으로 목표 결정
                      final velocity = details.primaryVelocity ?? 0;
                      double target;
                      if (velocity < -300) {
                        // 빠르게 위로 → 최대
                        target = current < 0.7 ? 0.5 : 0.92;
                      } else if (velocity > 300) {
                        // 빠르게 아래로 → 최소
                        target = current > 0.3 ? 0.5 : 0.09;
                      } else {
                        // 느린 드래그 → 가장 가까운 스냅 포인트
                        if (current < 0.3) target = 0.09;
                        else if (current < 0.7) target = 0.5;
                        else target = 0.92;
                      }
                      _sheetController.animateTo(
                        target,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    },
                    child: SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 헤더
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Row(
                      children: [
                        const Icon(Icons.store_rounded, size: 18, color: Color(0xFF1565C0)),
                        const SizedBox(width: 6),
                        const Text(
                          '근처 당첨지점',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1A1A1A)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F2FD),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$storeCount개',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1565C0)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // GPS 정확도 상태 바
                  _buildGpsStatusBar(),
                  // ── 이번 회차 분석 버튼 (5-8, 5-9) — 관리자 모드 전용 ──────────────
                  if (_isAdmin && _latestRound > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      child: Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) =>
                                    AdminComprehensivePredictionScreen(
                                        targetRound: _latestRound + 1))),
                            icon: const Icon(Icons.auto_graph_rounded, size: 13),
                            label: Text('${_latestRound + 1}회 분석',
                                style: const TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF5E35B1),
                              side: const BorderSide(color: Color(0xFF5E35B1), width: 1),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isAnalyzingList ? null : _analyzeCurrentList,
                            icon: _isAnalyzingList
                                ? const SizedBox(width: 13, height: 13,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.checklist_rounded, size: 13),
                            label: Text(
                              _engineEndorsed.isEmpty ? '현재 목록 분석' : '재분석',
                              style: const TextStyle(fontSize: 11),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.teal.shade700,
                              side: BorderSide(color: Colors.teal.shade700, width: 1),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  // 엔진 추천 지역 배지 — 관리자 모드 전용
                  if (_isAdmin && _engineCandidateRegions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                      child: Wrap(spacing: 4, runSpacing: 2, children: [
                        const Text('유력 지역:',
                            style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ..._engineCandidateRegions.map((r) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8EAF6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF5E35B1), width: 0.5),
                          ),
                          child: Text(r, style: const TextStyle(fontSize: 10,
                              color: Color(0xFF5E35B1), fontWeight: FontWeight.w600)),
                        )),
                      ]),
                    ),
                  // 리스트
                  Expanded(
                    child: storeCount == 0
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF5F5F5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  '이 주변에 당첨지점이 없습니다',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '지도를 이동한 뒤 "이 주변 검색"을 눌러보세요',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            itemCount: storeCount,
                            itemBuilder: (context, index) {
                              return _buildStoreCard(_nearbyStores![index], index);
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  final Set<int> _expandedStoreIndices = {};
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  ScrollController? _listScrollController;

  // 선택된 마커 인덱스 (말풍선 표시용)
  int? _selectedMarkerIndex;

  /// 지도 마커 탭 → 지도 중앙 이동 + 시트 열기 + 리스트 스크롤 + 카드 펼침
  void _onMarkerTap(LotteryStore store, int index) {
    // 마커를 지도 보이는 영역 상단으로 이동
    if (store.latitude != null && store.longitude != null && _mapReady && _mapController != null) {
      try {
        final sheetSize = _sheetController.isAttached ? _sheetController.size : 0.5;
        final screenHeight = MediaQuery.of(context).size.height;
        final visibleMapHeight = screenHeight * (1 - sheetSize);
        final zoom = _mapController!.camera.zoom;
        final metersPerPx = 156543.03392 / (1 << zoom.round()) * math.cos(store.latitude! * math.pi / 180);
        final latOffset = (visibleMapHeight / 2.2) * metersPerPx / 111320;
        _mapController!.move(LatLng(store.latitude! - latOffset, store.longitude!), zoom);
      } catch (_) {}
    }
    setState(() {
      _selectedMarkerIndex = index;
      _expandedStoreIndices.clear();
      _expandedStoreIndices.add(index);
    });
    // 시트가 너무 접혀 있으면 절반으로 펼치기
    if (_sheetController.isAttached && _sheetController.size < 0.35) {
      _sheetController.animateTo(
        0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    // 리스트를 해당 아이템으로 스크롤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollListToIndex(index);
    });
  }

  void _scrollListToIndex(int index) {
    if (_listScrollController == null || !_listScrollController!.hasClients) return;
    const estimatedItemHeight = 180.0;
    final maxExtent = _listScrollController!.position.maxScrollExtent;
    final offset = (index * estimatedItemHeight).clamp(0.0, maxExtent);
    _listScrollController!.animateTo(
      offset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  /// 리스트 카드 탭 → 지도 마커를 시트 위 보이는 영역 중앙으로 이동 + 카드 인라인 토글 펼침
  void _onCardTap(LotteryStore store, int index) {
    if (store.latitude != null && store.longitude != null && _mapReady && _mapController != null) {
      try {
        final sheetSize = _sheetController.isAttached ? _sheetController.size : 0.5;
        final screenHeight = MediaQuery.of(context).size.height;
        final visibleMapHeight = screenHeight * (1 - sheetSize);
        final zoom = _mapController!.camera.zoom;
        final metersPerPx = 156543.03392 / (1 << zoom.round()) * math.cos(store.latitude! * math.pi / 180);
        final latOffset = (visibleMapHeight / 2.2) * metersPerPx / 111320;
        _mapController!.move(
          LatLng(store.latitude! - latOffset, store.longitude!),
          zoom,
        );
      } catch (_) {}
    }
    setState(() {
      _selectedMarkerIndex = index;
      if (_expandedStoreIndices.contains(index)) {
        _expandedStoreIndices.remove(index);
      } else {
        _expandedStoreIndices.clear();
        _expandedStoreIndices.add(index);
      }
    });
    // 리스트에서 해당 카드가 보이도록 스크롤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollListToIndex(index);
    });
  }

  Future<void> _openExternalMap(String mapType, LotteryStore store) async {
    String url;
    if (store.latitude != null && store.longitude != null) {
      // 좌표가 있으면 좌표로 직접 열기
      final name = Uri.encodeComponent(store.storeName);
      if (mapType == 'naver') {
        url = 'nmap://map?lat=${store.latitude}&lng=${store.longitude}&label=$name&appname=com.luckylotto.finder';
      } else {
        url = 'https://map.kakao.com/link/map/$name,${store.latitude},${store.longitude}';
      }
    } else {
      // 좌표 없으면 주소로 검색
      final query = Uri.encodeComponent(store.address);
      if (mapType == 'naver') {
        url = 'https://map.naver.com/v5/search/$query';
      } else {
        url = 'https://map.kakao.com/link/search/$query';
      }
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // nmap 스킴 실패 시 웹 URL로 폴백
      final fallbackQuery = Uri.encodeComponent(store.address);
      final fallbackUrl = mapType == 'naver'
          ? 'https://map.naver.com/v5/search/$fallbackQuery'
          : 'https://map.kakao.com/link/search/$fallbackQuery';
      await launchUrl(Uri.parse(fallbackUrl), mode: LaunchMode.externalApplication);
    }
  }

  // ── GPS 정확도 상태 바 ───────────────────────────────────────────
  Widget _buildGpsStatusBar() {
    // 측정 중
    if (_isRefiningGps) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            const SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF1565C0)),
            ),
            const SizedBox(width: 6),
            Text(
              'GPS 정밀 측정 중...',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    if (_gpsAccuracy == null) return const SizedBox(height: 4);

    final acc = _gpsAccuracy!;
    final Color accColor;
    final String accLabel;
    if (acc <= _goodAccuracyM) {
      accColor = const Color(0xFF2E7D32);
      accLabel = '약 ${acc.toStringAsFixed(0)}m (양호)';
    } else if (acc <= _usableAccuracyM) {
      accColor = const Color(0xFFE65100);
      accLabel = '약 ${acc.toStringAsFixed(0)}m (보통)';
    } else {
      accColor = Colors.red.shade600;
      accLabel = '약 ${acc.toStringAsFixed(0)}m (저정밀)';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(Icons.gps_fixed_rounded, size: 12, color: accColor),
          const SizedBox(width: 4),
          Text(
            'GPS 정확도: $accLabel',
            style: TextStyle(fontSize: 11, color: accColor, fontWeight: FontWeight.w500),
          ),
          if (_isApproxLocation || acc > _usableAccuracyM) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _remeasureLocation,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF90CAF9)),
                ),
                child: const Text(
                  '다시 측정',
                  style: TextStyle(fontSize: 11, color: Color(0xFF1565C0), fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStoreCard(LotteryStore store, int index) {
    final distance = _calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      store.latitude ?? 0,
      store.longitude ?? 0,
    );
    final isFav = _favorites.contains(store.dhlotteryCode);
    final isExpanded = _expandedStoreIndices.contains(index);
    final (highlight, others) = splitStoreBadges(BadgeService.getBadges(store.dhlotteryCode));
    final endorsed = _isAdmin && _engineEndorsed[store.dhlotteryCode] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RankingStoreCard(
        key: ValueKey('nearby_card_${store.dhlotteryCode}'),
        data: RankingCardData.fromLotteryStore(store),
        extras: _extras[store.dhlotteryCode],
        badges: others,
        highlightBadges: highlight,
        isFavorite: isFav,
        isExpanded: isExpanded,
        latestRound: _latestRound,
        showResearch: false,
        showMedal: false,
        selected: _selectedMarkerIndex == index,
        trailing: DistanceTag(km: distance),
        extraChips: [
          if (_top30Ranks.containsKey(store.dhlotteryCode)) _buildTop30Badge(_top30Ranks[store.dhlotteryCode]!),
          if (endorsed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE7F6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF7E57C2), width: 0.5),
              ),
              child: const Text('엔진추천',
                  style: TextStyle(fontSize: 10, color: Color(0xFF5E35B1), fontWeight: FontWeight.w700)),
            ),
        ],
        // 엔진추천 판매점 → 추천 구매시점 (관리자 모드 전용)
        extraBody: endorsed ? _buildTemporalCard(store) : null,
        onTap: () => _onCardTap(store, index),
        onFavoriteTap: () => _toggleFavorite(store.dhlotteryCode),
        expandedChild: isExpanded
            ? Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openExternalMap('naver', store),
                      icon: const Icon(Icons.map_outlined, size: 15),
                      label: const Text('네이버지도', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        side: BorderSide(color: Colors.grey.shade300),
                        foregroundColor: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openExternalMap('kakao', store),
                      icon: const Icon(Icons.place_outlined, size: 15),
                      label: const Text('카카오지도', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        side: BorderSide(color: Colors.grey.shade300),
                        foregroundColor: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildTemporalCard(LotteryStore store) {
    final sido = _getSido(store.region ?? '');
    final temporal = _regionTemporal[sido];
    final nextRound = _latestRound > 0 ? _latestRound + 1 : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCE93D8), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(children: [
            const Icon(Icons.access_time_outlined, size: 13, color: Color(0xFF7B1FA2)),
            const SizedBox(width: 4),
            const Text('추천 구매시점', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7B1FA2))),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF7B1FA2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('랜덤확률분석엔진 반영',
                  style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 6),
          // 다음 추첨일 정보
          if (nextRound != null) ...[
            Row(children: [
              const Icon(Icons.event_rounded, size: 11, color: Color(0xFF9C27B0)),
              const SizedBox(width: 4),
              Text('${nextRound}회 추첨: ${RegionTemporalInfo.drawDateLabel(nextRound)}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6A1B9A), fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              () {
                final days = RegionTemporalInfo.daysUntilNextDraw(nextRound);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: days <= 2 ? const Color(0xFFE91E63) : const Color(0xFF9C27B0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    days == 0 ? 'D-Day' : 'D-$days',
                    style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                );
              }(),
            ]),
            const SizedBox(height: 4),
          ],
          // 지역 당첨 현황
          if (temporal != null) ...[
            _buildTemporalRow(
              Icons.history_rounded,
              '최근 당첨',
              temporal.lastWinRound != null
                  ? '${temporal.roundsAgoLastWin}회차 전 (${temporal.lastWinRound}회)'
                  : '기록 없음',
              _temporalStatusColor(temporal.recencyStatus),
            ),
            const SizedBox(height: 2),
            _buildTemporalRow(
              Icons.bar_chart_rounded,
              '최근 30회',
              '${temporal.winsLast30Rounds}회 당첨',
              temporal.winsLast30Rounds >= 3 ? const Color(0xFF388E3C)
                  : temporal.winsLast30Rounds >= 1 ? const Color(0xFF1976D2)
                  : Colors.grey.shade600,
            ),
            const SizedBox(height: 4),
            // 상태 배지
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _temporalStatusColor(temporal.recencyStatus).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _temporalStatusColor(temporal.recencyStatus).withOpacity(0.4)),
                ),
                child: Text(temporal.recencyStatus,
                    style: TextStyle(fontSize: 9, color: _temporalStatusColor(temporal.recencyStatus),
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Text('(실제 구매 시각 데이터 없음 — 회차 이력 기반)',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
            ]),
          ] else ...[
            Text('지역 당첨 이력 분석 중',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ],
      ),
    );
  }

  Widget _buildTemporalRow(IconData icon, String label, String value, Color valueColor) {
    return Row(children: [
      Icon(icon, size: 11, color: Colors.grey.shade500),
      const SizedBox(width: 4),
      Text('$label  ', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      Text(value, style: TextStyle(fontSize: 10, color: valueColor, fontWeight: FontWeight.w600)),
    ]);
  }

  Color _temporalStatusColor(String status) {
    switch (status) {
      case '최근활성': return const Color(0xFF388E3C);
      case '활성': return const Color(0xFF1976D2);
      case '보통': return const Color(0xFF7B1FA2);
      default: return Colors.grey.shade500;
    }
  }

  Widget _buildMapButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF666666)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF555555), fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildTop30Badge(int rank) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300, width: 1),
      ),
      child: Text(
        '복권명당 TOP30:$rank위',
        style: TextStyle(
          fontSize: 10,
          color: Colors.amber.shade800,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<Marker> _buildMapMarkers() {
    List<Marker> markers = [];

    if (_currentPosition == null) return markers;

    // 현재 위치 마커
    markers.add(
      Marker(
        point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        width: 44,
        height: 44,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.my_location_rounded, color: Colors.white, size: 20),
          ),
        ),
      ),
    );

    // 근처 판매점 마커 (빨간 핀)
    if (_nearbyStores != null) {
      for (int i = 0; i < _nearbyStores!.length; i++) {
        final store = _nearbyStores![i];
        final index = i;
        if (store.latitude != null && store.longitude != null) {
          final isSelected = _selectedMarkerIndex == index;

          markers.add(
            Marker(
              point: LatLng(store.latitude!, store.longitude!),
              width: isSelected ? 44 : 36,
              height: isSelected ? 44 : 36,
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onTap: () => _onMarkerTap(store, index),
                child: Icon(
                  Icons.place,
                  color: isSelected ? Colors.white : const Color(0xFFE53935),
                  size: isSelected ? 44 : 36,
                  shadows: const [
                    Shadow(
                      color: Color(0x55000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      }

      // 말풍선 마커 (선택된 지점만, 마커 바로 위에 꼬리 달린 말풍선)
      if (_selectedMarkerIndex != null && _selectedMarkerIndex! < _nearbyStores!.length) {
        final store = _nearbyStores![_selectedMarkerIndex!];
        if (store.latitude != null && store.longitude != null) {
          final top30Rank = _top30Ranks[store.dhlotteryCode];
          final bubbleHeight = top30Rank != null ? 78.0 : 52.0;
          markers.add(
            Marker(
              point: LatLng(store.latitude!, store.longitude!),
              width: 200,
              height: bubbleHeight + 10,
              alignment: const Alignment(0.0, -1.2), // 마커 바로 위 중앙
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 말풍선 본체
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.storeName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (top30Rank != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade300, width: 0.5),
                            ),
                            child: Text(
                              '복권명당 TOP30:$top30Rank위',
                              style: TextStyle(fontSize: 10, color: Colors.amber.shade800, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 꼬리 (삼각형)
                  CustomPaint(
                    size: const Size(14, 8),
                    painter: _BubbleTailPainter(),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }

    return markers;
  }

  /// 이 주변 검색 (지도 중심 기준)
  Future<void> _searchAtMapCenter() async {
    if (_mapController == null) return;

    setState(() => _isSearching = true);

    try {
      final center = _mapController!.camera.center;
      final zoom = _mapController!.camera.zoom;

      // 줌 레벨에 따라 검색 반경 자동 조절
      if (zoom >= 16) {
        _searchRadiusKm = 0.5;
      } else if (zoom >= 14) {
        _searchRadiusKm = 1.5;
      } else if (zoom >= 12) {
        _searchRadiusKm = 5.0;
      } else if (zoom >= 10) {
        _searchRadiusKm = 15.0;
      } else {
        _searchRadiusKm = 30.0;
      }

      final stores = await SupabaseService.getNearbyStores(
        latitude: center.latitude,
        longitude: center.longitude,
        radiusKm: _searchRadiusKm,
        lotteryType: _selectedGame,
      );

      // 배지 로드
      BadgeService.clearCache();
      final codes = stores.map((s) => s.dhlotteryCode).toSet().toList();
      await BadgeService.loadBadges(codes);
      _loadExtras(stores);

      setState(() {
        _nearbyStores = stores;
        _isSearching = false;
      });
      if (stores.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_sheetController.isAttached && _sheetController.size < 0.35) {
            _sheetController.animateTo(
              0.5,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('검색 오류: $e')),
        );
      }
    }
  }

  /// 내 위치 버튼 — 지도를 현재 위치로 이동만 (정밀 측정 중이면 현재 best 위치 사용)
  void _moveToCurrentLocation() {
    if (_currentPosition != null) {
      _mapController?.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        14.0,
      );
    } else {
      // 위치가 없으면 재측정 트리거
      _remeasureLocation();
    }
  }

  /// 두 좌표 간 거리 계산 (km)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degree) {
    return degree * math.pi / 180;
  }
}

/// 말풍선 꼬리 (아래쪽 삼각형, 그림자 포함)
class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 그림자
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final shadowPath = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height + 1)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(shadowPath, shadowPaint);

    // 흰색 꼬리
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 카드 내 인라인 판매점 평가 + 신고 위젯
class _InlineReviewSection extends StatefulWidget {
  final String dhlotteryCode;
  const _InlineReviewSection({required this.dhlotteryCode});

  @override
  State<_InlineReviewSection> createState() => _InlineReviewSectionState();
}

class _InlineReviewSectionState extends State<_InlineReviewSection> {
  Map<String, Map<String, int>> _summary = {};
  bool _isLoading = true;
  bool _isLoggedIn = false;
  String _deviceId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}_${UniqueKey().hashCode}';
      await prefs.setString('device_id', deviceId);
    }
    _deviceId = deviceId;
    final userId = prefs.getString('userId') ?? '';

    final summary = await SupabaseService.getReviewSummary(widget.dhlotteryCode);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _isLoggedIn = userId.isNotEmpty;
      _isLoading = false;
    });
  }

  Future<void> _showReviewDialog() async {
    final myVotes = await SupabaseService.getMyVotes(
      dhlotteryCode: widget.dhlotteryCode,
      deviceId: _deviceId,
    );

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ReviewDialog(
        dhlotteryCode: widget.dhlotteryCode,
        deviceId: _deviceId,
        initialVotes: myVotes,
      ),
    );

    if (result == true && mounted) {
      final summary = await SupabaseService.getReviewSummary(widget.dhlotteryCode);
      if (mounted) setState(() => _summary = summary);
    }
  }

  Future<void> _showReportDialog() async {
    String? selectedReason;
    final detailController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('판매점 신고', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('신고 사유를 선택하세요', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 12),
                ...reportReasons.map((reason) => RadioListTile<String>(
                  title: Text(reason, style: const TextStyle(fontSize: 14)),
                  value: reason,
                  groupValue: selectedReason,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setDialogState(() => selectedReason = v),
                )),
                const SizedBox(height: 8),
                TextField(
                  controller: detailController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: '추가 설명 (선택)',
                    hintStyle: const TextStyle(fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            ElevatedButton(
              onPressed: selectedReason == null ? null : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('신고', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedReason != null && mounted) {
      final resp = await SupabaseService.createReport(
        dhlotteryCode: widget.dhlotteryCode,
        deviceId: _deviceId,
        reason: selectedReason!,
        detail: detailController.text.trim().isEmpty ? null : detailController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resp['message'] ?? '')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 로그인 안내 or 신고+평가 버튼
        if (!_isLoggedIn)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text('로그인해야 지점평가가 가능합니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
              ],
            ),
          )
        else Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            GestureDetector(
              onTap: _showReportDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag_outlined, size: 14, color: Colors.red.shade400),
                    const SizedBox(width: 4),
                    Text('신고', style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _showReviewDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.rate_review_outlined, size: 14, color: Colors.blue.shade400),
                    const SizedBox(width: 4),
                    Text('평가', style: TextStyle(fontSize: 11, color: Colors.blue.shade400, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 승인된 평가 수치 표시
        const Text('판매점 평가', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        ...reviewItems.map((item) {
          final counts = _summary[item.key] ?? {'up': 0, 'down': 0};
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(item.icon, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(child: Text(item.label, style: const TextStyle(fontSize: 13))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.thumb_up, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text('${counts['up']}', style: const TextStyle(fontSize: 11, color: Colors.blue)),
                  ]),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.thumb_down, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Text('${counts['down']}', style: const TextStyle(fontSize: 11, color: Colors.red)),
                  ]),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// 평가 다이얼로그 (새 창)
class _ReviewDialog extends StatefulWidget {
  final String dhlotteryCode;
  final String deviceId;
  final Map<String, String> initialVotes;

  const _ReviewDialog({
    required this.dhlotteryCode,
    required this.deviceId,
    required this.initialVotes,
  });

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late Map<String, String> _votes;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _votes = Map.from(widget.initialVotes);
  }

  void _toggleVote(String reviewKey, String voteType) {
    setState(() {
      if (_votes[reviewKey] == voteType) {
        _votes.remove(reviewKey);
      } else {
        _votes[reviewKey] = voteType;
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    for (final entry in _votes.entries) {
      await SupabaseService.vote(
        dhlotteryCode: widget.dhlotteryCode,
        reviewKey: entry.key,
        deviceId: widget.deviceId,
        voteType: entry.value,
      );
    }

    if (mounted) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('평가가 제출되었습니다. 승인 후 반영됩니다.')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVotes = _votes.isNotEmpty;

    return AlertDialog(
      title: const Text('판매점 평가', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('이 판매점에 대해 평가해주세요', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text('승인 후 반영됩니다', style: TextStyle(fontSize: 11, color: Colors.orange.shade600)),
            const SizedBox(height: 16),
            ...reviewItems.map((item) {
              final myVote = _votes[item.key];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(item.icon, size: 18, color: Colors.grey.shade700),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item.label, style: const TextStyle(fontSize: 14))),
                    GestureDetector(
                      onTap: () => _toggleVote(item.key, 'up'),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: myVote == 'up' ? Colors.blue.shade100 : Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.thumb_up, size: 18, color: myVote == 'up' ? Colors.blue : Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _toggleVote(item.key, 'down'),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: myVote == 'down' ? Colors.red.shade100 : Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.thumb_down, size: 18, color: myVote == 'down' ? Colors.red : Colors.grey),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('닫기'),
        ),
        ElevatedButton(
          onPressed: (!hasVotes || _isSubmitting) ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('제출', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

