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
import '../widgets/store_detail_popup.dart';
import '../services/favorites_notifier.dart';

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

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadFavorites();
    _loadTop30Ranks();
    _loadUserId();
    _getCurrentLocation();
    favoritesNotifier.addListener(_onFavoritesChanged);
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

  Future<void> _getCurrentLocation() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // 위치 권한 확인
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

      // 현재 위치 가져오기 (실시간 GPS)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      setState(() {
        _currentPosition = position;
      });

      // 근처 판매점 검색
      if (mounted) {
        await _searchNearbyStores();
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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

  /// 지도 마커 탭 → 말풍선 + 시트 절반으로 열기 + 리스트 스크롤 + 상세 팝업
  void _onMarkerTap(LotteryStore store, int index) {
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
    // 상세 팝업 열기
    _showStoreDetailSheet(store, index);
  }

  void _scrollListToIndex(int index) {
    if (_listScrollController == null || !_listScrollController!.hasClients) return;
    const estimatedItemHeight = 140.0;
    final maxExtent = _listScrollController!.position.maxScrollExtent;
    final offset = (index * estimatedItemHeight).clamp(0.0, maxExtent);
    _listScrollController!.animateTo(
      offset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  /// 리스트 카드 탭 → 상세 팝업 (아래서 올라오는 작은 시트)
  Future<void> _showStoreDetailSheet(LotteryStore store, int index) async {
    final distance = _calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      store.latitude ?? 0,
      store.longitude ?? 0,
    );

    // 지도를 해당 판매점으로 이동
    if (store.latitude != null && store.longitude != null && _mapController != null) {
      _mapController!.move(LatLng(store.latitude!, store.longitude!), 15);
    }

    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('userId') ?? '';

    showStoreDetailPopup(
      context: context,
      store: store,
      favorites: _favorites,
      onToggleFavorite: _toggleFavorite,
      distanceKm: distance,
      isLoggedIn: currentUserId.isNotEmpty,
    ).then((_) {
      _loadFavorites();
    });
  }

  /// 아래 리스트 카드 탭 → 지도 이동 + 상세 팝업
  void _scrollToAndExpand(int index, LotteryStore store) {
    if (store.latitude != null && store.longitude != null && _mapController != null) {
      _mapController!.move(LatLng(store.latitude!, store.longitude!), 15);
    }
    _showStoreDetailSheet(store, index);
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

  Widget _buildStoreCard(LotteryStore store, int index) {
    final distance = _calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      store.latitude ?? 0,
      store.longitude ?? 0,
    );
    final isFav = _favorites.contains(store.dhlotteryCode);

    return GestureDetector(
      onTap: () {
        // 지도를 해당 판매점으로 이동
        if (store.latitude != null && store.longitude != null && _mapController != null) {
          _mapController!.move(LatLng(store.latitude!, store.longitude!), 15);
        }
        setState(() {
          _selectedMarkerIndex = index;
          _expandedStoreIndices.clear();
          _expandedStoreIndices.add(index);
        });
        // 상세 팝업 열기
        _showStoreDetailSheet(store, index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _selectedMarkerIndex == index ? const Color(0xFFF0F7FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _selectedMarkerIndex == index ? const Color(0xFF90CAF9) : const Color(0xFFEEEEEE),
            width: _selectedMarkerIndex == index ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더: 이름 + 거리 + 즐겨찾기
            Row(
              children: [
                Expanded(
                  child: Text(
                    store.storeName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1A1A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.near_me_rounded, size: 11, color: const Color(0xFF2E7D32)),
                      const SizedBox(width: 3),
                      Text(
                        '${distance.toStringAsFixed(2)}km',
                        style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleFavorite(store.dhlotteryCode),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      isFav ? Icons.star_rounded : Icons.star_border_rounded,
                      color: isFav ? Colors.amber : Colors.grey.shade300,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    store.address,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 배지
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (_top30Ranks.containsKey(store.dhlotteryCode))
                  _buildTop30Badge(_top30Ranks[store.dhlotteryCode]!),
                ...BadgeService.getBadges(store.dhlotteryCode).map((badge) {
                  return _buildBadgeChip(badge);
                }),
              ],
            ),
            // 탭 안내 아이콘
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: Icon(Icons.keyboard_arrow_right_rounded, color: Colors.grey.shade300, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildBadgeChip(StoreBadge badge) {
    Color color;
    switch (badge.type) {
      case StoreBadgeType.hot:
        color = Colors.red;
        break;
      case StoreBadgeType.myeongdang:
        color = Colors.amber.shade800;
        break;
      case StoreBadgeType.matjip:
        color = Colors.deepOrange;
        break;
      case StoreBadgeType.first:
        color = Colors.red.shade700;
        break;
      case StoreBadgeType.second:
        color = Colors.orange;
        break;
      case StoreBadgeType.regional:
        color = Colors.purple;
        break;
      case StoreBadgeType.streak:
        color = Colors.blue;
        break;
      case StoreBadgeType.rank:
        color = Colors.teal;
        break;
      case StoreBadgeType.pattern:
        color = Colors.grey.shade700;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badge.type == StoreBadgeType.hot
            ? color.withValues(alpha: 0.15)
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: badge.type == StoreBadgeType.hot
            ? Border.all(color: color.withValues(alpha: 0.5), width: 1)
            : null,
      ),
      child: Text(
        badge.label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: badge.type == StoreBadgeType.hot ? FontWeight.bold : FontWeight.w600,
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
                  color: isSelected ? const Color(0xFFFFD600) : const Color(0xFFE53935),
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

  /// 내 위치로 이동 (GPS 재조회)
  Future<void> _moveToCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: true,
      ).timeout(const Duration(seconds: 10));
      setState(() => _currentPosition = position);
      _mapController?.move(
        LatLng(position.latitude, position.longitude),
        14.0,
      );
    } catch (e) {
      // 타임아웃 시 마지막 알려진 위치 시도
      try {
        final lastPosition = await Geolocator.getLastKnownPosition();
        if (lastPosition != null && mounted) {
          setState(() => _currentPosition = lastPosition);
          _mapController?.move(
            LatLng(lastPosition.latitude, lastPosition.longitude),
            14.0,
          );
          return;
        }
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('위치 갱신 실패: $e')),
        );
      }
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

    final summary = await SupabaseService.getReviewSummary(widget.dhlotteryCode);
    if (!mounted) return;
    setState(() {
      _summary = summary;
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
        // 신고 + 평가 버튼 행
        Row(
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

