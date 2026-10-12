import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../models/lottery_store.dart';
import '../services/supabase_service.dart';
import '../services/badge_service.dart';
import '../services/ranking_extras_service.dart';
import '../widgets/ranking_store_card.dart';
import '../widgets/store_detail_popup.dart';
import '../services/favorites_notifier.dart';

class RegionScreen extends StatefulWidget {
  const RegionScreen({super.key});

  @override
  State<RegionScreen> createState() => _RegionScreenState();
}

class _RegionScreenState extends State<RegionScreen> {
  List<LotteryStore> _allStores = [];
  bool _isLoading = true;
  String? _error;

  // 판매점 즐겨찾기
  Set<String> _favorites = {};
  String _userId = '';

  // 지역 즐겨찾기
  Set<String> _favoriteRegions = {};

  // 현재위치 기반 추천
  bool _isLocating = false;
  String? _nearestRegion;
  bool _showNearbySection = false;

  // 게임 타입
  String _selectedGame = 'all';

  // 검색
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _searchBadgesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadFavoriteRegions();
    _loadStores();
    _loadUserId();
    SupabaseService.getLatestRound('lotto').then((r) {
      if (mounted && r != null) setState(() => _latestRound = r);
    });
    _loadHomeRanks();
    favoritesNotifier.addListener(_onFavoritesChanged);
  }

  // ── 카드 하단 통계(평균 간격 등): 화면에 그려진 카드의 코드를 모아 한 번에 조회 ──
  int _latestRound = 0;

  /// 홈 랭킹(TOP 20, 인터넷 판매점 제외)과 같은 순위 — 여기에 있는 판매점만 순위를 표시한다
  Map<String, int> _homeRanks = {};

  Future<void> _loadHomeRanks() async {
    try {
      final all = await SupabaseService.getTopRankedStores(limit: 20);
      final ranked = all.where((s) => !((s['store_name'] ?? '') as String).startsWith('인터넷')).take(20).toList();
      final m = <String, int>{};
      for (var i = 0; i < ranked.length; i++) {
        final c = (ranked[i]['dhlottery_code'] ?? '').toString();
        if (c.isNotEmpty) m[c] = i + 1;
      }
      if (mounted) setState(() => _homeRanks = m);
    } catch (_) {}
  }
  final Map<String, RankingStoreExtras> _extras = {};
  final Set<String> _extrasPending = {};
  final Set<String> _extrasRequested = {};
  bool _extrasScheduled = false;

  void _requestExtras(String code) {
    if (_extras.containsKey(code) || _extrasRequested.contains(code)) return;
    _extrasPending.add(code);
    if (_extrasScheduled) return;
    _extrasScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _extrasScheduled = false;
      final codes = _extrasPending.toList();
      _extrasPending.clear();
      _extrasRequested.addAll(codes);
      try {
        final x = await RankingExtrasService.load(codes.map((c) => <String, dynamic>{'dhlottery_code': c}).toList());
        if (mounted) setState(() => _extras.addAll(x));
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    favoritesNotifier.removeListener(_onFavoritesChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onFavoritesChanged() {
    _loadFavorites();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _userId = prefs.getString('userId') ?? '');
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favorites = (prefs.getStringList('favorite_stores') ?? []).toSet();
    });
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_stores', _favorites.toList());
    notifyFavoritesChanged();
  }

  Future<void> _loadFavoriteRegions() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favoriteRegions = (prefs.getStringList('favorite_regions') ?? []).toSet();
    });
  }

  Future<void> _saveFavoriteRegions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_regions', _favoriteRegions.toList());
  }

  Future<void> _toggleFavoriteRegion(String region) async {
    setState(() {
      if (_favoriteRegions.contains(region)) {
        _favoriteRegions.remove(region);
      } else {
        _favoriteRegions.add(region);
      }
    });
    await _saveFavoriteRegions();
  }

  Future<void> _locateAndRecommend() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 서비스를 켜주세요')),
          );
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('위치 권한이 필요합니다')),
            );
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('설정에서 위치 권한을 허용해주세요')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final nearest = _findNearestRegion(pos);
      if (mounted) {
        setState(() {
          _nearestRegion = nearest;
          _showNearbySection = nearest != null;
        });
        if (nearest != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('📍 내 주변 지역: $nearest')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('위치를 가져올 수 없습니다')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  String? _findNearestRegion(Position pos) {
    LotteryStore? nearest;
    double minDist = double.infinity;
    for (final store in _allStores) {
      if (store.latitude == null || store.longitude == null) continue;
      final dlat = pos.latitude - store.latitude!;
      final dlon = pos.longitude - store.longitude!;
      final d = dlat * dlat + dlon * dlon;
      if (d < minDist) {
        minDist = d;
        nearest = store;
      }
    }
    return nearest?.region;
  }

  Future<void> _toggleFavorite(String dhlotteryCode) async {
    setState(() {
      if (_favorites.contains(dhlotteryCode)) {
        _favorites.remove(dhlotteryCode);
      } else {
        _favorites.add(dhlotteryCode);
      }
    });
    await _saveFavorites();
  }

  // 배지 로딩된 시/구 추적
  final Set<String> _badgeLoadedSiGu = {};

  Future<void> _loadStores() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      BadgeService.clearCache();
      _badgeLoadedSiGu.clear();
      _siGuShowCount.clear();

      List<LotteryStore> stores;
      if (_selectedGame == 'all') {
        // 종합: 로또 + 연금 판매점을 합치되, dhlotteryCode 기준 중복 제거 (로또 우선)
        final lottoStores = await SupabaseService.getAllStores(lotteryType: 'lotto');
        final pensionStores = await SupabaseService.getAllStores(lotteryType: 'pension');
        final codeSet = <String>{};
        final merged = <LotteryStore>[];
        for (var s in lottoStores) {
          codeSet.add(s.dhlotteryCode);
          merged.add(s);
        }
        for (var s in pensionStores) {
          if (!codeSet.contains(s.dhlotteryCode)) {
            codeSet.add(s.dhlotteryCode);
            merged.add(s);
          }
        }
        stores = merged;
      } else {
        stores = await SupabaseService.getAllStores(lotteryType: _selectedGame);
      }

      // 배지는 여기서 안 불러옴 → 시/구 펼칠 때 지연 로딩

      if (!mounted) return;
      setState(() {
        _allStores = stores;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 시/구 펼칠 때 해당 판매점들의 배지만 로드
  Future<void> _loadBadgesForSiGu(String siGuKey, List<LotteryStore> stores) async {
    if (_badgeLoadedSiGu.contains(siGuKey)) return;
    final codes = stores.map((s) => s.dhlotteryCode).toSet().toList();
    final lotteryType = _selectedGame == 'all' ? null : _selectedGame;
    await BadgeService.loadBadges(codes, lotteryType: lotteryType);
    _badgeLoadedSiGu.add(siGuKey);
    if (mounted) setState(() {});
  }

  // 주소에서 시/구/군 추출
  String _extractSiGu(String address) {
    final parts = address.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return parts[1]; // 두 번째 토큰: 강남구, 수원시, etc.
    }
    return '기타';
  }

  // 주소에서 동/읍/면 추출
  String _extractDong(String address) {
    final parts = address.trim().split(RegExp(r'\s+'));
    if (parts.length >= 3) {
      return parts[2]; // 세 번째 토큰: 도로명 또는 동
    }
    return '기타';
  }

  @override
  Widget build(BuildContext context) {
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
            Text('지역 데이터 로딩중...', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
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
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.wifi_off_rounded, size: 48, color: Colors.red.shade300),
              ),
              const SizedBox(height: 20),
              Text('데이터를 불러올 수 없습니다', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              Text('네트워크 연결을 확인해주세요', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadStores,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    // 지역별 데이터 준비
    final regionMap = <String, List<LotteryStore>>{};
    for (final store in _allStores) {
      final r = store.region.isEmpty ? '기타' : store.region;
      if (r == '동행복권(dhlottery.co.kr)') continue;
      regionMap.putIfAbsent(r, () => []).add(store);
    }
    final sortedRegions = regionMap.entries.toList()
      ..sort((a, b) {
        final sumA = a.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
        final sumB = b.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
        return sumB.compareTo(sumA);
      });

    return Container(
      color: const Color(0xFFF2F4F8),
      child: CustomScrollView(
        slivers: [
          // 헤더 (파란 그라디언트)
          SliverToBoxAdapter(child: _buildRegionHeader()),
          // 현재위치 기반 추천 섹션
          if (_showNearbySection && _nearestRegion != null)
            SliverToBoxAdapter(child: _buildNearbySection(regionMap)),
          // 지역 즐겨찾기 섹션
          if (_favoriteRegions.isNotEmpty)
            SliverToBoxAdapter(child: _buildFavoriteRegionsSection(regionMap)),
          // 판매점 즐겨찾기 섹션
          SliverToBoxAdapter(child: _buildFavoritesSection()),
          // 검색창
          SliverToBoxAdapter(child: _buildSearchBar()),
          // 검색 결과
          if (_searchQuery.trim().isNotEmpty)
            SliverToBoxAdapter(child: _buildSearchResults()),
          // 지역별 목록
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildRegionItem(sortedRegions[index]),
                childCount: sortedRegions.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E0E0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (val) async {
            final q = val.trim();
            setState(() {
              _searchQuery = q;
              _searchBadgesLoaded = false;
            });
            if (q.isNotEmpty) {
              final results = _getSearchResults(q);
              if (results.isNotEmpty) {
                final codes = results.map((s) => s.dhlotteryCode).toList();
                await BadgeService.loadBadges(codes);
                if (mounted) setState(() => _searchBadgesLoaded = true);
              }
            }
          },
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: '판매점 이름 또는 주소 검색',
            hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF1565C0), size: 22),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          ),
        ),
      ),
    );
  }

  List<LotteryStore> _getSearchResults(String query) {
    final q = query.toLowerCase();
    final seen = <String>{};
    return _allStores.where((s) {
      if (seen.contains(s.dhlotteryCode)) return false;
      if (s.storeName.toLowerCase().contains(q) || s.address.toLowerCase().contains(q)) {
        seen.add(s.dhlotteryCode);
        return true;
      }
      return false;
    }).take(30).toList();
  }

  Widget _buildSearchResults() {
    final results = _getSearchResults(_searchQuery);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3F2FD), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 16, color: Color(0xFF1565C0)),
                  const SizedBox(width: 6),
                  Text(
                    '검색 결과 (${results.length}개)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1565C0)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE3F2FD)),
            if (results.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    '"$_searchQuery" 검색 결과가 없습니다',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: results.map((s) => _buildStoreCard(s, 0)).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbySection(Map<String, List<LotteryStore>> regionMap) {
    final region = _nearestRegion!;
    final stores = regionMap[region] ?? [];
    final topStores = [...stores]
      ..sort((a, b) => (b.totalCount ?? 0).compareTo(a.totalCount ?? 0));
    final display = topStores.take(5).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF81C784), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
            child: Row(
              children: [
                const Icon(Icons.my_location_rounded, size: 18, color: Color(0xFF2E7D32)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '내 주변 명당 · $region',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32)),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    _showNearbySection = false;
                    _nearestRegion = null;
                  }),
                  child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF2E7D32)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFA5D6A7)),
          if (display.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('이 지역 판매점 데이터가 없습니다', style: TextStyle(fontSize: 13, color: Colors.grey)),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: display.map((s) => _buildStoreCard(s, 0)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFavoriteRegionsSection(Map<String, List<LotteryStore>> regionMap) {
    final favList = _favoriteRegions.toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCE93D8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(Icons.bookmark_rounded, color: Colors.purple.shade600, size: 20),
                const SizedBox(width: 6),
                Text(
                  '즐겨찾기 지역 (${favList.length})',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.purple.shade700),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFCE93D8)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: favList.map((region) {
                final stores = regionMap[region] ?? [];
                final totalWins = stores.fold<int>(0, (s, e) => s + (e.totalCount ?? 0));
                return GestureDetector(
                  onTap: () => _showRegionBottomSheet(region, stores),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.purple.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purple.withValues(alpha: 0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          region,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.purple.shade700),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '·당첨$totalWins회',
                          style: TextStyle(fontSize: 11, color: Colors.purple.shade400),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _toggleFavoriteRegion(region),
                          child: Icon(Icons.bookmark_remove_rounded, size: 16, color: Colors.purple.shade300),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showRegionBottomSheet(String region, List<LotteryStore> stores) {
    final topStores = [...stores]
      ..sort((a, b) => (b.totalCount ?? 0).compareTo(a.totalCount ?? 0));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.location_city_rounded, color: Colors.purple.shade600, size: 20),
                    const SizedBox(width: 8),
                    Text(region, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.purple.shade700)),
                    const Spacer(),
                    Text('${topStores.length}개 판매점', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: topStores.length,
                  itemBuilder: (_, i) => _buildStoreCard(topStores[i], i + 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegionItem(MapEntry<String, List<LotteryStore>> entry) {
    final totalWins = entry.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
    final seen = <String>{};
    final storeCount = entry.value.where((s) {
      if (seen.contains(s.dhlotteryCode)) return false;
      seen.add(s.dhlotteryCode);
      return true;
    }).length;
    final isFavRegion = _favoriteRegions.contains(entry.key);
    final isNearest = _showNearbySection && _nearestRegion == entry.key;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isNearest ? const Color(0xFF81C784) : const Color(0xFFE0E0E0),
          width: isNearest ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.only(left: 16, right: 8, top: 2, bottom: 2),
          childrenPadding: EdgeInsets.zero,
          iconColor: const Color(0xFF1565C0),
          collapsedIconColor: const Color(0xFF999999),
          leading: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isNearest ? const Color(0xFFE8F5E9) : const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isNearest ? Icons.my_location_rounded : Icons.location_city_rounded,
              size: 18,
              color: isNearest ? const Color(0xFF2E7D32) : const Color(0xFF1565C0),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isNearest ? const Color(0xFF2E7D32) : const Color(0xFF1A1A1A),
                  ),
                ),
              ),
              if (isNearest)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF81C784)),
                  ),
                  child: const Text('내 주변', style: TextStyle(fontSize: 10, color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
                ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _toggleFavoriteRegion(entry.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Icon(
                    isFavRegion ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    size: 22,
                    color: isFavRegion ? Colors.purple.shade400 : Colors.grey.shade300,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                _buildMiniTag('$storeCount개', const Color(0xFF1565C0)),
                const SizedBox(width: 6),
                _buildMiniTag('당첨 $totalWins회', const Color(0xFFFF8F00)),
              ],
            ),
          ),
          children: [
            Divider(height: 1, color: Colors.grey.shade200),
            _buildSiGuExpansion(entry.value, entry.key),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '지역별 명당',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white60, letterSpacing: 1.0),
                ),
                const SizedBox(height: 4),
                const Text(
                  '전국 판매점',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5, height: 1.1),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildRegionChip('all', '전체'),
                    const SizedBox(width: 8),
                    _buildRegionChip('lotto', '로또'),
                    const SizedBox(width: 8),
                    _buildRegionChip('pension', '연금'),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              // 현재위치 버튼
              GestureDetector(
                onTap: _isLocating ? null : _locateAndRecommend,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: _showNearbySection
                        ? Colors.greenAccent.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _showNearbySection
                          ? Colors.greenAccent.withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: _isLocating
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(
                          _showNearbySection ? Icons.my_location_rounded : Icons.location_searching_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '내 주변',
                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRegionChip(String value, String label) {
    final selected = _selectedGame == value;
    return GestureDetector(
      onTap: () {
        if (_selectedGame != value) {
          setState(() => _selectedGame = value);
          _loadStores();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.white : Colors.white.withValues(alpha: 0.3), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF1565C0) : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritesSection() {
    if (_favorites.isEmpty) return const SizedBox.shrink();

    final favStores = _allStores
        .where((s) => _favorites.contains(s.dhlotteryCode))
        .toList();

    if (favStores.isEmpty) return const SizedBox.shrink();

    final seen = <String>{};
    final uniqueFavStores = favStores.where((s) {
      if (seen.contains(s.dhlotteryCode)) return false;
      seen.add(s.dhlotteryCode);
      return true;
    }).toList();

    uniqueFavStores.sort((a, b) => (b.totalCount ?? 0).compareTo(a.totalCount ?? 0));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded, color: Colors.amber.shade700, size: 20),
              const SizedBox(width: 6),
              Text(
                '즐겨찾기 (${uniqueFavStores.length})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.amber.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '즐겨찾기 메뉴에서 확인해주세요',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          ...uniqueFavStores.take(5).map((store) => _buildFavStoreRow(store)),
          if (uniqueFavStores.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${uniqueFavStores.length - 5}개 더',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFavStoreRow(LotteryStore store) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store.storeName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  store.region,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Text(
            '${store.totalCount ?? 0}회',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1565C0),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _toggleFavorite(store.dhlotteryCode),
            child: Icon(
              Icons.star_rounded,
              color: Colors.amber,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // _buildStoreRow removed — replaced by _buildFavStoreRow


  Widget _buildMiniTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  // 시/구 펼침 (2단계)
  Widget _buildSiGuExpansion(List<LotteryStore> stores, String doName) {
    final siGuMap = <String, List<LotteryStore>>{};
    for (final store in stores) {
      final siGu = _extractSiGu(store.address);
      siGuMap.putIfAbsent(siGu, () => []).add(store);
    }

    final sorted = siGuMap.entries.toList()
      ..sort((a, b) {
        final sumA = a.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
        final sumB = b.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
        return sumB.compareTo(sumA);
      });

    return Container(
      color: const Color(0xFFFAFAFA),
      child: Column(
        children: sorted.map((entry) {
          final totalWins = entry.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
          final storeCount = entry.value.length;
          final siGuKey = '$doName/${entry.key}';

          return Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                backgroundColor: const Color(0xFFF5F5F5),
                tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                iconColor: const Color(0xFF1565C0),
                collapsedIconColor: const Color(0xFFBBBBBB),
                title: Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF333333)),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    '$storeCount개 · 당첨 $totalWins회',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
                onExpansionChanged: (expanded) {
                  if (expanded) {
                    _loadBadgesForSiGu(siGuKey, entry.value);
                  }
                },
                children: [_buildDongExpansion(entry.value, siGuKey)],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // 동/읍/면 펼침 (3단계)
  Widget _buildDongExpansion(List<LotteryStore> stores, String siGuKey) {
    final dongMap = <String, List<LotteryStore>>{};
    for (final store in stores) {
      final dong = _extractDong(store.address);
      dongMap.putIfAbsent(dong, () => []).add(store);
    }

    final sorted = dongMap.entries.toList()
      ..sort((a, b) {
        final sumA = a.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
        final sumB = b.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
        return sumB.compareTo(sumA);
      });

    return Container(
      color: Colors.white,
      child: Column(
        children: sorted.map((entry) {
          final totalWins = entry.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
          final storeCount = entry.value.length;
          final dongKey = '$siGuKey/${entry.key}';

          return Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 32),
              iconColor: const Color(0xFF1565C0),
              collapsedIconColor: const Color(0xFFCCCCCC),
              title: Row(
                children: [
                  Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Color(0xFF444444)),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Text(
                  '$storeCount개 · $totalWins회',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ),
              children: [_buildStoreListInBox(entry.value, siGuKey: dongKey)],
            ),
          );
        }).toList(),
      ),
    );
  }

  // 판매점 목록 (4단계 - 박스 안, 페이지네이션)
  Widget _buildStoreListInBox(List<LotteryStore> stores, {String siGuKey = ''}) {
    // 중복 제거
    final seen = <String>{};
    final uniqueStores = stores.where((s) {
      if (seen.contains(s.dhlotteryCode)) return false;
      seen.add(s.dhlotteryCode);
      return true;
    }).toList();

    // total_count 내림차순, 즐겨찾기 상단
    uniqueStores.sort((a, b) => (b.totalCount ?? 0).compareTo(a.totalCount ?? 0));
    final favStores = uniqueStores.where((s) => _favorites.contains(s.dhlotteryCode)).toList();
    final nonFavStores = uniqueStores.where((s) => !_favorites.contains(s.dhlotteryCode)).toList();
    final sortedStores = [...favStores, ...nonFavStores];

    final showCount = _siGuShowCount[siGuKey] ?? 20;
    final displayStores = sortedStores.take(showCount).toList();
    final remaining = sortedStores.length - displayStores.length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          ...displayStores.asMap().entries.map((entry) {
            return _buildStoreCard(entry.value, entry.key + 1);
          }),
          if (remaining > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _siGuShowCount[siGuKey] = showCount + 20;
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_rounded, size: 16, color: Color(0xFF1565C0)),
                      const SizedBox(width: 6),
                      Text(
                        '더보기 ($remaining개 남음)',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF1565C0), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // _buildStoreRow removed — favorites section now handled in dedicated tab

  // 시/구별 표시 개수 추적
  final Map<String, int> _siGuShowCount = {};

  // 카드 펼침 상태
  final Set<String> _expandedCards = {};

  Future<void> _openMap(String mapType, LotteryStore store) async {
    String url;
    if (store.latitude != null && store.longitude != null) {
      final name = Uri.encodeComponent(store.storeName);
      if (mapType == 'naver') {
        url = 'nmap://map?lat=${store.latitude}&lng=${store.longitude}&label=$name&appname=com.luckylotto.finder';
      } else {
        url = 'https://map.kakao.com/link/map/$name,${store.latitude},${store.longitude}';
      }
    } else {
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
      final fallbackQuery = Uri.encodeComponent(store.address);
      final fallbackUrl = mapType == 'naver'
          ? 'https://map.naver.com/v5/search/$fallbackQuery'
          : 'https://map.kakao.com/link/search/$fallbackQuery';
      await launchUrl(Uri.parse(fallbackUrl), mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildStoreCard(LotteryStore store, int rank) {
    final isFav = _favorites.contains(store.dhlotteryCode);
    final isExpanded = _expandedCards.contains(store.dhlotteryCode);
    final (highlight, others) = splitStoreBadges(BadgeService.getBadges(store.dhlotteryCode));
    _requestExtras(store.dhlotteryCode);
    // 홈 랭킹에 있는 판매점만 홈과 같은 순위로 표시, 나머지는 순위 없이 표시
    final homeRank = _homeRanks[store.dhlotteryCode];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RankingStoreCard(
        key: ValueKey('region_card_${store.dhlotteryCode}_$rank'),
        data: RankingCardData.fromLotteryStore(store, rank: homeRank ?? 0),
        extras: _extras[store.dhlotteryCode],
        badges: others,
        highlightBadges: highlight,
        isFavorite: isFav,
        isExpanded: isExpanded,
        latestRound: _latestRound,
        showResearch: false,
        showMedal: homeRank != null,
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedCards.remove(store.dhlotteryCode);
            } else {
              _expandedCards.clear();
              _expandedCards.add(store.dhlotteryCode);
            }
          });
        },
        onFavoriteTap: () => _toggleFavorite(store.dhlotteryCode),
        expandedChild: isExpanded
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMapButton('네이버지도', Icons.map_outlined, () => _openMap('naver', store)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMapButton('카카오지도', Icons.place_outlined, () => _openMap('kakao', store)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 판매점 평가
                  _InlineReviewSection(dhlotteryCode: store.dhlotteryCode),
                ],
              )
            : null,
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
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp['message'] ?? '')),
        );
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
