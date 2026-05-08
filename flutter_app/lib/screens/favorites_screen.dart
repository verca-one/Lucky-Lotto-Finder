import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import '../models/lottery_store.dart';
import '../services/supabase_service.dart';
import '../services/badge_service.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  Set<String> _favorites = {};
  List<LotteryStore> _allStores = [];
  bool _isLoading = true;
  final Set<String> _expandedCards = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // 즐겨찾기 목록 로드
    final prefs = await SharedPreferences.getInstance();
    final favJson = prefs.getString('favorite_stores') ?? '[]';
    final favList = (jsonDecode(favJson) as List).cast<String>();
    _favorites = favList.toSet();

    if (_favorites.isEmpty) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }

    // Supabase에서 전체 판매점 로드 (로또)
    final lottoStores = await SupabaseService.getAllStores(lotteryType: 'lotto');

    // 즐겨찾기에 해당하는 판매점만 필터
    final favStores = lottoStores
        .where((s) => _favorites.contains(s.dhlotteryCode))
        .toList();

    // 중복 제거
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
        lotteryType: 'lotto',
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
    await prefs.setString('favorite_stores', jsonEncode(_favorites.toList()));
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
      onRefresh: _loadData,
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
}
