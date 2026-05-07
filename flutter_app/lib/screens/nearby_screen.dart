import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import '../models/lottery_store.dart';
import '../services/supabase_service.dart';
import '../services/badge_service.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  Position? _currentPosition;
  List<LotteryStore>? _nearbyStores;
  bool _isLoading = false;
  String? _error;
  final String _selectedGame = 'lotto';
  final double _radiusKm = 1.3;
  MapController? _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _listScrollController.dispose();
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

      // 현재 위치 가져오기
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

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
        radiusKm: _radiusKm,
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
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('위치를 찾는 중...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('오류: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _getCurrentLocation,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_currentPosition == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('위치를 가져올 수 없습니다'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _getCurrentLocation,
              child: const Text('위치 다시 가져오기'),
            ),
          ],
        ),
      );
    }

    if (_nearbyStores == null || _nearbyStores!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '${_radiusKm}km 범위 내 ${_gameTypeToString(_selectedGame)} 당첨지점이 없습니다',
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _searchNearbyStores,
              child: const Text('다시 검색'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 300,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        ),
                        initialZoom: 13.0,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.luckylotto.finder',
                        ),
                        MarkerLayer(markers: _buildMapMarkers()),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'nearby_current_location_btn',
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue,
                    onPressed: _moveToCurrentLocation,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '근처 당첨지점 (${_nearbyStores!.length}개)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _listScrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _nearbyStores!.length,
            itemBuilder: (context, index) {
              return _buildStoreCard(_nearbyStores![index], index);
            },
          ),
        ),
      ],
    );
  }

  final Set<int> _expandedStoreIndices = {};
  final ScrollController _listScrollController = ScrollController();

  /// 지도 마커 탭 → 팝업
  void _showStorePopup(LotteryStore store, int index) {
    final distance = _calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      store.latitude ?? 0,
      store.longitude ?? 0,
    );
    final badges = BadgeService.getBadges(store.dhlotteryCode);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 핸들
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    store.storeName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${distance.toStringAsFixed(2)}km',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              store.address,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: badges.map((b) => _buildBadgeChip(b)).toList(),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openExternalMap('naver', store);
                    },
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('네이버지도'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openExternalMap('kakao', store);
                    },
                    icon: const Icon(Icons.place_outlined, size: 18),
                    label: const Text('카카오지도'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 아래 리스트 카드 탭 → 지도 이동 + 카드 펼침
  void _scrollToAndExpand(int index, LotteryStore store) {
    // 지도를 해당 판매점으로 이동
    if (store.latitude != null && store.longitude != null && _mapController != null) {
      _mapController!.move(LatLng(store.latitude!, store.longitude!), 15);
    }
    // 카드 펼침
    setState(() {
      _expandedStoreIndices.add(index);
    });
    // 리스트 스크롤 (카드 높이 약 120 기준)
    final offset = index * 120.0;
    _listScrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
    final isExpanded = _expandedStoreIndices.contains(index);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (isExpanded) {
            setState(() {
              _expandedStoreIndices.remove(index);
            });
          } else {
            _scrollToAndExpand(index, store);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      store.storeName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${distance.toStringAsFixed(2)}km',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                store.address,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: BadgeService.getBadges(store.dhlotteryCode).map((badge) {
                  return _buildBadgeChip(badge);
                }).toList(),
              ),
              if (isExpanded) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openExternalMap('naver', store),
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: const Text('네이버지도'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openExternalMap('kakao', store),
                          icon: const Icon(Icons.place_outlined, size: 18),
                          label: const Text('카카오지도'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
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

    // 현재 위치 마커 (초록색 동그란 아이콘)
    markers.add(
      Marker(
        point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        width: 50,
        height: 50,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.my_location, color: Colors.white, size: 24),
          ),
        ),
      ),
    );

    // 근처 판매점 마커 (파란 지도 마커, 탭 가능)
    if (_nearbyStores != null) {
      for (int i = 0; i < _nearbyStores!.length; i++) {
        final store = _nearbyStores![i];
        final index = i;
        if (store.latitude != null && store.longitude != null) {
          markers.add(
            Marker(
              point: LatLng(store.latitude!, store.longitude!),
              width: 45,
              height: 50,
              child: GestureDetector(
                onTap: () => _showStorePopup(store, index),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  width: 40,
                  height: 40,
                  child: const Center(
                    child: Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    return markers;
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371;
    final dLat = _toRadian(lat2 - lat1);
    final dLon = _toRadian(lon2 - lon1);
    final a =
        (1 - math.cos(dLat)) / 2 +
        math.cos(_toRadian(lat1)) *
            math.cos(_toRadian(lat2)) *
            (1 - math.cos(dLon)) /
            2;
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadian(double degree) => degree * math.pi / 180;

  void _moveToCurrentLocation() {
    if (_currentPosition == null || _mapController == null) return;
    _mapController!.move(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      13,
    );
  }

  String _gameTypeToString(String type) {
    switch (type) {
      case 'lotto':
        return '로또';
      case 'pension':
        return '연금복권';
      case 'speedlotto_2000':
        return '스피또 2000';
      case 'speedlotto_1000':
        return '스피또 1000';
      case 'speedlotto_500':
        return '스피또 500';
      default:
        return type;
    }
  }
}
