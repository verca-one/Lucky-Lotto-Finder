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

class _FavoritesScreenState extends State<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  Set<String> _favorites = {};
  List<LotteryStore> _allStores = [];
  List<LotteryStore> _winnerStores = [];
  Map<String, String> _winnerTiers = {}; // code -> 'first' | 'second'
  int _latestRound = 0;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _selfTriggered = false;
  DateTime? _lastRefreshTime;
  final Set<String> _expandedCards = {};

  late AnimationController _blinkController;
  late Animation<double> _blinkAnim;

  // 토~월요일만 당첨 배너 표시 (화요일 00:00부터 숨김)
  bool get _showWinnerBanner {
    final weekday = DateTime.now().weekday;
    return weekday == DateTime.saturday ||
        weekday == DateTime.sunday ||
        weekday == DateTime.monday;
  }

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _blinkAnim = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
    _loadData();
    favoritesNotifier.addListener(_onFavoritesChanged);
  }

  @override
  void dispose() {
    _blinkController.dispose();
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
    if (_lastRefreshTime != null &&
        DateTime.now().difference(_lastRefreshTime!).inSeconds < 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('10초 후에 다시 시도해주세요'),
              duration: Duration(seconds: 1)),
        );
      }
      return;
    }
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    _lastRefreshTime = DateTime.now();
    await _loadData(forceRefresh: true);
    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (!forceRefresh) setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    _favorites = (prefs.getStringList('favorite_stores') ?? []).toSet();

    if (_favorites.isEmpty) {
      if (!mounted) return;
      setState(() {
        _allStores = [];
        _winnerStores = [];
        _winnerTiers = {};
        _isLoading = false;
      });
      return;
    }

    List<LotteryStore> favStores;
    if (forceRefresh) {
      favStores = await SupabaseService.getStoresByCodes(_favorites.toList());
      _saveToCache(prefs, favStores);
    } else {
      favStores = _loadFromCache(prefs);
      favStores = favStores.where((s) => _favorites.contains(s.dhlotteryCode)).toList();
      final cachedCodes = favStores.map((s) => s.dhlotteryCode).toSet();
      final missingCodes = _favorites.difference(cachedCodes);
      if (missingCodes.isNotEmpty) {
        favStores = await SupabaseService.getStoresByCodes(_favorites.toList());
        _saveToCache(prefs, favStores);
      }
    }

    final seen = <String>{};
    final uniqueStores = favStores.where((s) {
      if (seen.contains(s.dhlotteryCode)) return false;
      seen.add(s.dhlotteryCode);
      return true;
    }).toList();

    if (uniqueStores.isNotEmpty) {
      await BadgeService.loadBadges(
        uniqueStores.map((s) => s.dhlotteryCode).toList(),
      );
    }

    uniqueStores.sort((a, b) => (b.totalCount ?? 0).compareTo(a.totalCount ?? 0));

    // 이번 회차 당첨 판매점 확인 (토~월요일만)
    List<LotteryStore> winnerStores = [];
    Map<String, String> winnerTiers = {};
    int latestRound = 0;

    if (_showWinnerBanner && uniqueStores.isNotEmpty) {
      final round = await SupabaseService.getLatestRound('lotto');
      if (round != null && round > 0) {
        latestRound = round;
        final codes = uniqueStores.map((s) => s.dhlotteryCode).toList();
        winnerTiers = await SupabaseService.getWinnersInRound(round, codes);
        winnerStores = uniqueStores
            .where((s) => winnerTiers.containsKey(s.dhlotteryCode))
            .toList();
      }
    }

    if (!mounted) return;
    setState(() {
      _allStores = uniqueStores;
      _winnerStores = winnerStores;
      _winnerTiers = winnerTiers;
      _latestRound = latestRound;
      _isLoading = false;
    });
  }

  Future<void> _removeFavorite(String dhlotteryCode) async {
    setState(() {
      _favorites.remove(dhlotteryCode);
      _allStores.removeWhere((s) => s.dhlotteryCode == dhlotteryCode);
      _winnerStores.removeWhere((s) => s.dhlotteryCode == dhlotteryCode);
      _winnerTiers.remove(dhlotteryCode);
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
            Text('즐겨찾기한 판매점이 없습니다',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Text('지역 메뉴에서 판매점을 즐겨찾기 해보세요',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
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
            Text('즐겨찾기 판매점 정보를 불러올 수 없습니다',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    final showBanner = _showWinnerBanner && _winnerStores.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // 당첨 배너 (토~월요일, 당첨 판매점 있을 때만)
          if (showBanner) ...[
            // vito.png
            Image.asset(
              'assets/vito.png',
              width: double.infinity,
              height: 300,
              fit: BoxFit.cover,
            ),
            // 골드 당첨 섹션
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFD54F), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD54F).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 섹션 헤더
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: [
                        const Text('🎉', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text(
                          '$_latestRound회 당첨 판매점',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB8860B),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD54F),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_winnerStores.length}곳',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5D4037),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFFFE082)),
                  // 당첨 판매점 카드들
                  ...(_winnerStores.map((store) => _buildWinnerCard(store))),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],

          // 일반 즐겨찾기 목록
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.star, color: Colors.amber.shade700, size: 22),
                const SizedBox(width: 8),
                Text(
                  '즐겨찾기 (${_allStores.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _refresh,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isRefreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF1565C0),
                            ),
                          )
                        : const Icon(Icons.refresh_rounded,
                            color: Color(0xFF666666), size: 20),
                  ),
                ),
              ],
            ),
          ),
          ...(_allStores.map((store) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildStoreCard(store),
              ))),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildWinnerCard(LotteryStore store) {
    final tier = _winnerTiers[store.dhlotteryCode] ?? 'first';
    final isFirst = tier == 'first';
    final isExpanded = _expandedCards.contains(store.dhlotteryCode);

    return InkWell(
      onTap: () => setState(() {
        if (isExpanded) {
          _expandedCards.remove(store.dhlotteryCode);
        } else {
          _expandedCards.add(store.dhlotteryCode);
        }
      }),
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFirst ? const Color(0xFFFFD700) : const Color(0xFFFFC107),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              store.storeName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 깜빡이는 당첨 네온 텍스트
                          AnimatedBuilder(
                            animation: _blinkAnim,
                            builder: (_, __) => Opacity(
                              opacity: _blinkAnim.value,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isFirst
                                      ? const Color(0xFFFF6F00)
                                      : const Color(0xFF1565C0),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isFirst
                                              ? const Color(0xFFFF6F00)
                                              : const Color(0xFF1565C0))
                                          .withValues(alpha: _blinkAnim.value * 0.8),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  isFirst ? '🏆 1등 당첨' : '🥈 2등 당첨',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        store.address,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: BadgeService.getBadges(store.dhlotteryCode)
                            .map((b) => _buildBadgeChip(b))
                            .toList(),
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
    );
  }

  Widget _buildStoreCard(LotteryStore store) {
    final isExpanded = _expandedCards.contains(store.dhlotteryCode);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
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
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          store.address,
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: BadgeService.getBadges(store.dhlotteryCode)
                              .map((badge) => _buildBadgeChip(badge))
                              .toList(),
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
              fontWeight: badge.type == StoreBadgeType.hot
                  ? FontWeight.bold
                  : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
