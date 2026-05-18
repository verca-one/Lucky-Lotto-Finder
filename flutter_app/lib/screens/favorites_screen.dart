import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/lottery_store.dart';
import '../services/supabase_service.dart';
import '../services/badge_service.dart';
import '../services/favorites_notifier.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  Set<String> _favorites = {};
  List<LotteryStore> _allStores = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _selfTriggered = false;
  DateTime? _lastRefreshTime;
  final Set<String> _expandedCards = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    favoritesNotifier.addListener(_onFavoritesChanged);
  }

  @override
  void dispose() {
    favoritesNotifier.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (_selfTriggered) {
      _selfTriggered = false;
      return;
    }
    _loadData();
  }

  List<LotteryStore> _loadFromCache(SharedPreferences prefs) {
    final cached = prefs.getString('favorite_stores_cache');
    if (cached == null) return [];
    try {
      final list = jsonDecode(cached) as List;
      return list.map((e) => LotteryStore.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  void _saveToCache(SharedPreferences prefs, List<LotteryStore> stores) {
    final json = jsonEncode(stores.map((s) => s.toJson()).toList());
    prefs.setString('favorite_stores_cache', json);
  }

  Future<void> _refresh() async {
    // 10초 쿨타임 체크
    if (_lastRefreshTime != null &&
        DateTime.now().difference(_lastRefreshTime!).inSeconds < 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('10초 후에 다시 시도해주세요'), duration: Duration(seconds: 1)),
        );
      }
      return;
    }
    // 중복 클릭 방지
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);
    _lastRefreshTime = DateTime.now();

    await _loadData(forceRefresh: true);

    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (!forceRefresh) setState(() => _isLoading = true);

    // 즐겨찾기 목록 로드 (StringList 방식)
    final prefs = await SharedPreferences.getInstance();
    _favorites = (prefs.getStringList('favorite_stores') ?? []).toSet();

    if (_favorites.isEmpty) {
      if (!mounted) return;
      setState(() {
        _allStores = [];
        _isLoading = false;
      });
      return;
    }

    List<LotteryStore> favStores;
    if (forceRefresh) {
      // Supabase 1회 묶음 조회 → 캐시 갱신
      favStores = await SupabaseService.getStoresByCodes(_favorites.toList());
      _saveToCache(prefs, favStores);
    } else {
      // 기본 진입: 로컬 캐시 먼저 표시
      favStores = _loadFromCache(prefs);
      favStores = favStores.where((s) => _favorites.contains(s.dhlotteryCode)).toList();
      final cachedCodes = favStores.map((s) => s.dhlotteryCode).toSet();
      final missingCodes = _favorites.difference(cachedCodes);
      if (missingCodes.isNotEmpty) {
        favStores = await SupabaseService.getStoresByCodes(_favorites.toList());
        _saveToCache(prefs, favStores);
      }
    }

    // ��복 제거
    final seen = <String>{};
    final uniqueStores = favStores.where((s) {
      if (seen.contains(s.dhlotteryCode)) return false;
      seen.add(s.dhlotteryCode);
      return true;
    }).toList();

    // 배지 로드
    if (uniqueStores.isNotEmpty) {
      await BadgeService.loadBadges(
        uniqueStores.map((s) => s.dhlotteryCode).toList(),
      );
    }

    // total_count 내림차순 정렬
    uniqueStores.sort((a, b) => (b.totalCount ?? 0).compareTo(a.totalCount ?? 0));

    if (!mounted) return;
    setState(() {
      _allStores = uniqueStores;
      _isLoading = false;
    });
  }

  Future<void> _removeFavorite(String dhlotteryCode) async {
    setState(() {
      _favorites.remove(dhlotteryCode);
      _allStores.removeWhere((s) => s.dhlotteryCode == dhlotteryCode);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_stores', _favorites.toList());
    _selfTriggered = true;
    notifyFavoritesChanged();
  }

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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star_border, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '즐겨찾기한 판매점이 없습니다',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              '지역 메뉴에서 판매점을 즐겨찾기 해보세요',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    if (_allStores.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star_border, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '즐겨찾기 판매점 정보를 불러올 수 없습니다',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _allStores.length + 1, // +1 for header
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.star, color: Colors.amber.shade700, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    '즐겨찾기 (${_allStores.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _refresh,
                    child: _isRefreshing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.grey.shade600,
                            ),
                          )
                        : Icon(Icons.refresh, color: Colors.grey.shade600, size: 22),
                  ),
                ],
              ),
            );
          }

          final store = _allStores[index - 1];
          return _buildStoreCard(store);
        },
      ),
    );
  }

  Widget _buildStoreCard(LotteryStore store) {
    final isExpanded = _expandedCards.contains(store.dhlotteryCode);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.amber.shade50,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedCards.remove(store.dhlotteryCode);
            } else {
              _expandedCards.add(store.dhlotteryCode);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.storeName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          store.address,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // 배지
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: BadgeService.getBadges(store.dhlotteryCode).map((badge) {
                            return _buildBadgeChip(badge);
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => _removeFavorite(store.dhlotteryCode),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.star, color: Colors.amber, size: 28),
                    ),
                  ),
                ],
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
                          onPressed: () => _openMap('naver', store),
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: const Text('네이버지도'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openMap('kakao', store),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge.type == StoreBadgeType.hot)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Icon(Icons.monetization_on, size: 13, color: color),
            ),
          Text(
            badge.label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: badge.type == StoreBadgeType.hot ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
