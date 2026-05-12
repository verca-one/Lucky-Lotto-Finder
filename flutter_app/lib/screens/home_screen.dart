import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import '../services/ad_service.dart';
import '../services/badge_service.dart';
import 'nearby_screen.dart';
import 'region_screen.dart';
import 'favorites_screen.dart';
import 'admin_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedBottomTab = 0;
  String _userId = '';
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _initAdsAndBanner();
  }

  Future<void> _initAdsAndBanner() async {
    await AdService.loadAdsRemovedState();
    if (AdService.adsRemoved) return;
    final loaded = await AdService.loadBannerAd();
    if (!mounted) return;
    setState(() {
      _isBannerLoaded = loaded;
      _bannerAd = AdService.getBannerAd();
    });
  }

  @override
  void dispose() {
    AdService.dispose();
    super.dispose();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getString('userId') ?? '';
    });
  }

  Future<void> _saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);
    setState(() {
      _userId = userId;
    });
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}_${UniqueKey().hashCode}';
      await prefs.setString('device_id', deviceId);
    }
    return deviceId;
  }

  void _showSettingsMenu() {
    final rootContext = context;
    TextEditingController inputController = TextEditingController();
    TextEditingController couponController = TextEditingController();

    showDialog(
      context: rootContext,
      builder: (dialogContext) => _SettingsDialog(
        inputController: inputController,
        couponController: couponController,
        adsRemoved: AdService.adsRemoved,
        onSaveProfile: (text) {
          if (text.isEmpty) return;
          if (text == '공룡로또') {
            Navigator.pop(dialogContext);
            _showAdminPasswordDialog();
          } else {
            _saveUserId(text);
            Navigator.pop(dialogContext);
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(content: Text('프로필이 저장되었습니다: $text')),
            );
          }
        },
        onRedeemCoupon: (code) async {
          final deviceId = await _getDeviceId();
          final result = await SupabaseService.redeemCoupon(
            couponCode: code,
            deviceId: deviceId,
          );
          if (!mounted) return result;

          if (result['success'] == true && result['type'] == 'ad_removal') {
            await AdService.setAdsRemoved(true);
            setState(() {
              _isBannerLoaded = false;
              _bannerAd = null;
            });
          }
          return result;
        },
      ),
    );
  }

  void _showAdminPasswordDialog() {
    TextEditingController adminController = TextEditingController();
    const String ADMIN_PASSWORD = 'admin@2018!';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '관리자 인증',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '관리자 비밀번호를 입력하세요',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: adminController,
                decoration: InputDecoration(
                  hintText: '비밀번호',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    if (adminController.text == ADMIN_PASSWORD) {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminScreen()),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('관리자 인증 성공')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('비밀번호가 일치하지 않습니다')),
                      );
                    }
                  },
                  child: const Text(
                    '인증',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _HomeRankingContent(),
      const NearbyScreen(),
      const RegionScreen(),
      const FavoritesScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Row(
          children: [
            const Text(
              '복권명당',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            if (_userId.isNotEmpty) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _userId,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _showSettingsMenu,
          ),
        ],
      ),
      body: IndexedStack(index: _selectedBottomTab, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!AdService.adsRemoved && _isBannerLoaded && _bannerAd != null)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          BottomNavigationBar(
            backgroundColor: Colors.white,
            selectedItemColor: Colors.blue,
            unselectedItemColor: Colors.grey,
            currentIndex: _selectedBottomTab,
            onTap: (index) {
              setState(() => _selectedBottomTab = index);
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
              BottomNavigationBarItem(
                icon: Icon(Icons.location_on),
                label: '주변판매점',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.location_city),
                label: '지역',
              ),
              BottomNavigationBarItem(icon: Icon(Icons.star), label: '즐겨찾기'),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 홈 랭킹 콘텐츠 (당첨지점 TOP 30)
// ============================================================
class _HomeRankingContent extends StatefulWidget {
  const _HomeRankingContent();

  @override
  State<_HomeRankingContent> createState() => _HomeRankingContentState();
}

class _HomeRankingContentState extends State<_HomeRankingContent> {
  List<Map<String, dynamic>> _rankedStores = [];
  Map<String, Map<String, dynamic>> _pensionInfo = {};
  bool _isLoading = true;
  String? _error;

  // 확장된 카드 관리
  final Set<String> _expandedCards = {};
  // 당첨 이력 캐시
  final Map<String, List<Map<String, dynamic>>> _historyCache = {};

  @override
  void initState() {
    super.initState();
    _loadRanking();
  }

  Future<void> _loadRanking() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 1. 로또 1등 기준 TOP 30 조회
      final stores = await SupabaseService.getTopRankedStores(limit: 30);

      if (stores.isEmpty) {
        setState(() {
          _rankedStores = [];
          _isLoading = false;
        });
        return;
      }

      // 2. 배지 로드
      final codes = stores.map((s) => s['dhlottery_code'] as String).toList();
      await BadgeService.loadBadges(codes, lotteryType: 'lotto');

      // 3. 연금복권 당첨 정보 조회 (배지 표시용)
      final pensionData = await SupabaseService.getPensionInfoForStores(codes);

      if (!mounted) return;
      setState(() {
        _rankedStores = stores;
        _pensionInfo = pensionData;
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

  /// 토요일 21:00~21:30 업데이트 안내 표시 여부
  bool get _isUpdateTime {
    final now = DateTime.now();
    // 토요일(6) 21:00 ~ 21:30
    if (now.weekday == DateTime.saturday) {
      final hour = now.hour;
      final minute = now.minute;
      if (hour == 21 && minute < 30) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadRanking,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('오류: $_error'))
              : CustomScrollView(
                  slivers: [
                    // 업데이트 안내 배너
                    if (_isUpdateTime)
                      SliverToBoxAdapter(child: _buildUpdateBanner()),
                    // 헤더
                    SliverToBoxAdapter(child: _buildHeader()),
                    // 랭킹 리스트
                    _rankedStores.isEmpty
                        ? const SliverFillRemaining(
                            child: Center(child: Text('당첨지점 데이터가 없습니다')),
                          )
                        : SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (index >= _rankedStores.length) return null;
                                  return _buildRankCard(index, _rankedStores[index]);
                                },
                                childCount: _rankedStores.length,
                              ),
                            ),
                          ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ],
                ),
    );
  }

  Widget _buildUpdateBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade600, Colors.orange.shade600],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '이번 주 당첨지점 발표를 적용 중입니다...\n잠시 후 새로고침 해주세요.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.emoji_events, color: Colors.amber.shade700, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '복권명당 TOP 30',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '로또 1등 누적 당첨 횟수 기준',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: Colors.grey.shade300),
        ],
      ),
    );
  }

  void _toggleCard(String code) async {
    setState(() {
      if (_expandedCards.contains(code)) {
        _expandedCards.remove(code);
      } else {
        _expandedCards.add(code);
      }
    });
    // 당첨 이력 로드 (캐시 없을 때만)
    if (_expandedCards.contains(code) && !_historyCache.containsKey(code)) {
      final history = await SupabaseService.getWinningHistoryForStore(code);
      if (mounted) {
        setState(() {
          _historyCache[code] = history;
        });
      }
    }
  }

  Future<void> _openMap({required String mapType, required String storeName, required String address}) async {
    final query = Uri.encodeComponent(address);
    String url;
    if (mapType == 'naver') {
      url = 'https://map.naver.com/v5/search/$query';
    } else {
      url = 'https://map.kakao.com/link/search/$query';
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildRankCard(int index, Map<String, dynamic> store) {
    final rank = index + 1;
    final storeName = store['store_name'] ?? '';
    final address = store['address'] ?? '';
    final region = store['region'] ?? '';
    final firstCount = store['first_count'] ?? 0;
    final secondCount = store['second_count'] ?? 0;
    final latestFirstWin = store['latest_first_win'];
    final dhlotteryCode = store['dhlottery_code'] as String;
    final isExpanded = _expandedCards.contains(dhlotteryCode);

    // 배지 가져오기
    final badges = BadgeService.getBadges(dhlotteryCode);

    // 연금복권 정보
    final pension = _pensionInfo[dhlotteryCode];
    final pensionFirstCount = pension?['first_count'] ?? 0;
    final pensionSecondCount = pension?['second_count'] ?? 0;

    // 순위별 색상
    Color rankColor;
    Color rankBgColor;
    if (rank == 1) {
      rankColor = Colors.white;
      rankBgColor = const Color(0xFFFFD700);
    } else if (rank == 2) {
      rankColor = Colors.white;
      rankBgColor = const Color(0xFFC0C0C0);
    } else if (rank == 3) {
      rankColor = Colors.white;
      rankBgColor = const Color(0xFFCD7F32);
    } else {
      rankColor = Colors.grey.shade700;
      rankBgColor = Colors.grey.shade200;
    }

    return GestureDetector(
      onTap: () => _toggleCard(dhlotteryCode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: rank <= 3
              ? Border.all(color: rankBgColor.withValues(alpha: 0.6), width: 1.5)
              : Border.all(color: isExpanded ? Colors.blue.shade200 : Colors.grey.shade200, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 순위 원
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rankBgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank위',
                    style: TextStyle(
                      color: rankColor,
                      fontWeight: FontWeight.bold,
                      fontSize: rank <= 3 ? 13 : 11,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 지점 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        storeName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (latestFirstWin != null)
                            Text(
                              '${latestFirstWin}회 당첨적용',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          if (latestFirstWin != null) const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(region, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        address,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // 당첨 정보 행
                      Row(
                        children: [
                          _buildInfoChip('1등 ${firstCount}회', Colors.red.shade700, Colors.red.shade50),
                          const SizedBox(width: 6),
                          if (secondCount > 0)
                            _buildInfoChip('2등 ${secondCount}회', Colors.orange.shade700, Colors.orange.shade50),
                          if (secondCount > 0) const SizedBox(width: 6),
                        ],
                      ),
                      // 연금복권 배지
                      if (pensionFirstCount > 0 || pensionSecondCount > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.monetization_on, size: 14, color: Colors.green.shade600),
                            const SizedBox(width: 4),
                            Text('연금복권', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 6),
                            if (pensionFirstCount > 0)
                              _buildInfoChip('1등 ${pensionFirstCount}회', Colors.green.shade700, Colors.green.shade50),
                            if (pensionFirstCount > 0 && pensionSecondCount > 0)
                              const SizedBox(width: 4),
                            if (pensionSecondCount > 0)
                              _buildInfoChip('2등 ${pensionSecondCount}회', Colors.teal.shade700, Colors.teal.shade50),
                          ],
                        ),
                      ],
                      // store_badges 배지
                      if (badges.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: badges.map((b) => _buildBadgeChip(b)).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                // 확장 아이콘
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
            // ── 확장 영역 ──
            if (isExpanded) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.grey.shade200),
              const SizedBox(height: 12),
              // 판매점 평가 (가로 2개씩)
              _buildStoreRating(dhlotteryCode),
              const SizedBox(height: 12),
              // 지도 버튼
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openMap(mapType: 'naver', storeName: storeName, address: address),
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: const Text('네이버지도', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openMap(mapType: 'kakao', storeName: storeName, address: address),
                      icon: const Icon(Icons.place_outlined, size: 16),
                      label: const Text('카카오지도', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 당첨 회차 목록
              _buildWinningHistory(dhlotteryCode),
            ],
          ],
        ),
      ),
    );
  }

  /// 판매점 평가 (가로 2개씩)
  Widget _buildStoreRating(String dhlotteryCode) {
    final items = [
      {'icon': Icons.thumb_up, 'label': '당첨 기운', 'color': Colors.red},
      {'icon': Icons.store, 'label': '매장 청결', 'color': Colors.blue},
      {'icon': Icons.people, 'label': '친절도', 'color': Colors.orange},
      {'icon': Icons.access_time, 'label': '대기 시간', 'color': Colors.green},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('판매점 평가', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (int i = 0; i < 2; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: (items[i]['color'] as Color).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: (items[i]['color'] as Color).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(items[i]['icon'] as IconData, size: 16, color: items[i]['color'] as Color),
                      const SizedBox(width: 6),
                      Text(items[i]['label'] as String, style: TextStyle(fontSize: 12, color: items[i]['color'] as Color, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (int i = 2; i < 4; i++) ...[
              if (i > 2) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: (items[i]['color'] as Color).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: (items[i]['color'] as Color).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(items[i]['icon'] as IconData, size: 16, color: items[i]['color'] as Color),
                      const SizedBox(width: 6),
                      Text(items[i]['label'] as String, style: TextStyle(fontSize: 12, color: items[i]['color'] as Color, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 당첨 회차 목록 (로또/연금 구분, 1등 노랑, 2등 은색)
  Widget _buildWinningHistory(String dhlotteryCode) {
    final history = _historyCache[dhlotteryCode];
    if (history == null) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }
    if (history.isEmpty) {
      return Text('당첨 이력이 없습니다', style: TextStyle(fontSize: 12, color: Colors.grey.shade500));
    }

    // 로또/연금 분리
    final lottoHistory = history.where((h) => h['lottery_type'] == 'lotto').toList();
    final pensionHistory = history.where((h) => h['lottery_type'] == 'pension').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('당첨 이력', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        if (lottoHistory.isNotEmpty) ...[
          Text('로또', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: lottoHistory.map((h) => _buildRoundChip(h)).toList(),
          ),
        ],
        if (lottoHistory.isNotEmpty && pensionHistory.isNotEmpty)
          const SizedBox(height: 10),
        if (pensionHistory.isNotEmpty) ...[
          Text('연금복권', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: pensionHistory.map((h) => _buildRoundChip(h)).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildRoundChip(Map<String, dynamic> history) {
    final round = history['round'] ?? 0;
    final tier = history['prize_tier'] ?? 'first';
    final isFirst = tier == 'first';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isFirst ? const Color(0xFFFFF8E1) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFirst ? const Color(0xFFFFD700) : const Color(0xFFC0C0C0),
          width: 1.5,
        ),
      ),
      child: Text(
        '${round}회 ${isFirst ? "1등" : "2등"}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isFirst ? const Color(0xFFB8860B) : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildInfoChip(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor),
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

// ============================================================
// 설정 다이얼로그
// ============================================================
class _SettingsDialog extends StatefulWidget {
  final TextEditingController inputController;
  final TextEditingController couponController;
  final bool adsRemoved;
  final void Function(String) onSaveProfile;
  final Future<Map<String, dynamic>> Function(String) onRedeemCoupon;

  const _SettingsDialog({
    required this.inputController,
    required this.couponController,
    required this.adsRemoved,
    required this.onSaveProfile,
    required this.onRedeemCoupon,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  bool _isRedeeming = false;
  String? _couponMessage;
  bool? _couponSuccess;
  late bool _adsRemoved;

  @override
  void initState() {
    super.initState();
    _adsRemoved = widget.adsRemoved;
  }

  Future<void> _handleRedeem() async {
    final code = widget.couponController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _couponMessage = '쿠폰 코드를 입력하세요';
        _couponSuccess = false;
      });
      return;
    }

    setState(() {
      _isRedeeming = true;
      _couponMessage = null;
    });

    final result = await widget.onRedeemCoupon(code);

    if (!mounted) return;
    setState(() {
      _isRedeeming = false;
      _couponSuccess = result['success'] == true;
      _couponMessage = result['message'] ?? '';
      if (_couponSuccess == true) {
        _adsRemoved = true;
        widget.couponController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '설정',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              // 쿠폰 입력 섹션
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.card_giftcard, color: Colors.orange.shade700, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          '쿠폰 입력',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_adsRemoved) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '광고제거 쿠폰이 적용되어 있습니다',
                                style: TextStyle(fontSize: 13, color: Colors.green),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: widget.couponController,
                              decoration: InputDecoration(
                                hintText: 'XXXX-XXXX-XXXX',
                                hintStyle: const TextStyle(fontSize: 13),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10,
                                ),
                                isDense: true,
                              ),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 42,
                            child: ElevatedButton(
                              onPressed: _isRedeeming ? null : _handleRedeem,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _isRedeeming
                                  ? const SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      '적용',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      if (_couponMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _couponMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _couponSuccess == true ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),

              // 프로필 섹션
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '프로필 이름을 입력하세요',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.inputController,
                decoration: InputDecoration(
                  hintText: '예: 행운이',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => widget.onSaveProfile(widget.inputController.text),
                  child: const Text(
                    '저장',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
