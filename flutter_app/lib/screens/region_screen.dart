import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import '../models/lottery_store.dart';
import '../services/supabase_service.dart';
import '../services/badge_service.dart';
import '../widgets/store_detail_popup.dart';

class RegionScreen extends StatefulWidget {
  const RegionScreen({super.key});

  @override
  State<RegionScreen> createState() => _RegionScreenState();
}

class _RegionScreenState extends State<RegionScreen> {
  List<LotteryStore> _allStores = [];
  bool _isLoading = true;
  String? _error;

  // 즐겨찾기
  Set<String> _favorites = {};

  // 게임 타입
  String _selectedGame = 'all';

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadStores();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favJson = prefs.getString('favorite_stores') ?? '[]';
    final favList = (jsonDecode(favJson) as List).cast<String>();
    setState(() {
      _favorites = favList.toSet();
    });
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('favorite_stores', jsonEncode(_favorites.toList()));
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
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('지역 데이터 로딩중...'),
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
            ElevatedButton(onPressed: _loadStores, child: const Text('다시 시도')),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 게임 타입 선택
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildGameChip('all', '종합'),
                const SizedBox(width: 8),
                _buildGameChip('lotto', '로또'),
                const SizedBox(width: 8),
                _buildGameChip('pension', '연금복권'),
              ],
            ),
          ),
        ),
        // 즐겨찾기 섹션
        _buildFavoritesSection(),
        // 메인 콘텐츠 (박스 안에 박스)
        Expanded(child: _buildExpandableContent()),
      ],
    );
  }

  Widget _buildGameChip(String value, String label) {
    final isSelected = _selectedGame == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(
        fontSize: 12,
        color: isSelected ? Colors.white : Colors.black87,
      )),
      selected: isSelected,
      selectedColor: Colors.blue,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedGame = value;
          });
          _loadStores();
        }
      },
    );
  }

  Widget _buildFavoritesSection() {
    if (_favorites.isEmpty) return const SizedBox.shrink();

    final favStores = _allStores
        .where((s) => _favorites.contains(s.dhlotteryCode))
        .toList();

    if (favStores.isEmpty) return const SizedBox.shrink();

    // 중복 제거 (같은 dhlotteryCode)
    final seen = <String>{};
    final uniqueFavStores = favStores.where((s) {
      if (seen.contains(s.dhlotteryCode)) return false;
      seen.add(s.dhlotteryCode);
      return true;
    }).toList();

    uniqueFavStores.sort((a, b) => (b.totalCount ?? 0).compareTo(a.totalCount ?? 0));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: Colors.amber.shade700, size: 20),
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
          const SizedBox(height: 8),
          ...uniqueFavStores.take(5).map((store) => _buildStoreRow(store, showRegion: true)),
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

  // 박스 안에 박스 구조 (도 > 시/구 > 판매점)
  Widget _buildExpandableContent() {
    final regionMap = <String, List<LotteryStore>>{};
    for (final store in _allStores) {
      final r = store.region.isEmpty ? '기타' : store.region;
      if (r == '동행복권(dhlottery.co.kr)') continue;
      regionMap.putIfAbsent(r, () => []).add(store);
    }

    // total_count 합계로 정렬
    final sorted = regionMap.entries.toList()
      ..sort((a, b) {
        final sumA = a.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
        final sumB = b.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
        return sumB.compareTo(sumA);
      });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final entry = sorted[index];
        final totalWins = entry.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
        final storeCount = entry.value.toSet().length;

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          clipBehavior: Clip.antiAlias,
          color: Colors.blue.shade50,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            iconColor: Colors.blue.shade700,
            collapsedIconColor: Colors.blue.shade400,
            title: Text(
              entry.key,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue.shade900),
            ),
            subtitle: Text(
              '판매점 $storeCount개 · 총 당첨 $totalWins회',
              style: TextStyle(fontSize: 12, color: Colors.blue.shade400),
            ),
            children: [_buildSiGuExpansion(entry.value, entry.key)],
          ),
        );
      },
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
      color: Colors.grey.shade100,
      child: Column(
        children: sorted.map((entry) {
          final totalWins = entry.value.fold<int>(0, (sum, s) => sum + (s.totalCount ?? 0));
          final storeCount = entry.value.length;
          final siGuKey = '$doName/${entry.key}';

          return Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5)),
            ),
            child: ExpansionTile(
              backgroundColor: Colors.grey.shade50,
              tilePadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(
                entry.key,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.grey.shade800),
              ),
              subtitle: Text(
                '판매점 $storeCount개 · 당첨 $totalWins회',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            onExpansionChanged: (expanded) {
              if (expanded) {
                _loadBadgesForSiGu(siGuKey, entry.value);
              }
            },
            children: [_buildDongExpansion(entry.value, siGuKey)],
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

          return ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 36),
            title: Text(
              entry.key,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            subtitle: Text(
              '$storeCount개 · $totalWins회',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            children: [_buildStoreListInBox(entry.value, siGuKey: dongKey)],
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
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _siGuShowCount[siGuKey] = showCount + 20;
                  });
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40),
                ),
                child: Text('더보기 ($remaining개 남음)'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStoreRow(LotteryStore store, {bool showRegion = false}) {
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
                if (showRegion)
                  Text(
                    store.region,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          Text(
            '${store.totalCount ?? 0}회',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _toggleFavorite(store.dhlotteryCode),
            child: Icon(
              _favorites.contains(store.dhlotteryCode) ? Icons.star : Icons.star_border,
              color: _favorites.contains(store.dhlotteryCode)
                  ? Colors.amber
                  : Colors.grey.shade400,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isFav ? Colors.amber.shade50 : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          showStoreDetailPopup(
            context: context,
            store: store,
            favorites: _favorites,
            onToggleFavorite: _toggleFavorite,
          ).then((_) {
            // 팝업 닫힌 후 즐겨찾기 상태 갱신
            _loadFavorites();
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
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
              Icon(
                isFav ? Icons.star : Icons.star_border,
                color: isFav ? Colors.amber : Colors.grey.shade400,
                size: 24,
              ),
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
