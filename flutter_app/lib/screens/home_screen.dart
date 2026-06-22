import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import '../services/ad_service.dart';
import '../services/badge_service.dart';
import '../widgets/store_detail_popup.dart';
import 'nearby_screen.dart';
import 'region_screen.dart';
import 'recommend_screen.dart';
import 'favorites_tab_screen.dart';
import 'admin_screen.dart';
import '../services/favorites_notifier.dart';
import '../services/donation_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedBottomTab = 0;
  String _userId = '';
  bool _isAdmin = false;
  final GlobalKey<RecommendScreenState> _recommendKey = GlobalKey<RecommendScreenState>();
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
      _isAdmin = prefs.getBool('isAdmin') ?? false;
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
        isLoggedIn: _userId.isNotEmpty,
        isAdmin: _isAdmin,
        onAdminTap: _isAdmin ? () {
          Navigator.pop(dialogContext);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen()));
        } : null,
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
                  onPressed: () async {
                    if (adminController.text == ADMIN_PASSWORD) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('isAdmin', true);
                      setState(() => _isAdmin = true);
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
      RecommendScreen(key: _recommendKey),
      const FavoritesTabScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/app_icon_internal.png',
                width: 70,
                height: 70,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text('복권명당 찾기'),
            if (_isAdmin) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.admin_panel_settings, size: 14, color: Colors.purple.shade700),
                    const SizedBox(width: 4),
                    Text(
                      '관리자',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.purple.shade700),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('isAdmin', false);
                        setState(() => _isAdmin = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('관리자 로그아웃 되었습니다')),
                          );
                        }
                      },
                      child: Icon(Icons.close, color: Colors.purple.shade400, size: 14),
                    ),
                  ],
                ),
              ),
            ],
            if (_userId.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFBBDEFB)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _userId,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1565C0)),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('userId');
                        setState(() => _userId = '');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('로그아웃 되었습니다')),
                          );
                        }
                      },
                      child: const Icon(Icons.close, color: Color(0xFF1565C0), size: 14),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.settings_outlined, color: Color(0xFF666666), size: 20),
            ),
            onPressed: _showSettingsMenu,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _selectedBottomTab, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: _selectedBottomTab,
              onTap: (index) {
                if (index == 3 && _selectedBottomTab == 3) {
                  _recommendKey.currentState?.resetToMain();
                }
                setState(() => _selectedBottomTab = index);
              },
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: '홈'),
                BottomNavigationBarItem(icon: Icon(Icons.near_me_rounded), label: '주변'),
                BottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: '지역'),
                BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_rounded), label: '추천'),
                BottomNavigationBarItem(icon: Icon(Icons.star_rounded), label: '즐겨찾기'),
              ],
            ),
          ),
          if (!AdService.adsRemoved && _isBannerLoaded && _bannerAd != null)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
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

class _HomeRankingContentState extends State<_HomeRankingContent> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _rankedStores = [];
  List<Map<String, dynamic>> _internetStores = []; // 인터넷구매 지점 (별도 표시)
  Map<String, Map<String, dynamic>> _pensionInfo = {};
  int _latestLottoRound = 0;
  int _latestPensionRound = 0;
  bool _isLoading = true;
  String? _error;
  bool _badgeLoadFailed = false;
  // 크롤링 안내문
  List<Map<String, dynamic>> _recentCrawlLogs = [];

  // 확장된 카드 관리
  final Set<String> _expandedCards = {};
  // 당첨 이력 캐시
  final Map<String, List<Map<String, dynamic>>> _historyCache = {};
  // 즐겨찾기
  Set<String> _favorites = {};
  // 순위 변동 (dhlotteryCode -> 변동값, 양수=상승, 음수=하락, 0=유지)
  Map<String, int> _rankChanges = {};

  // 1~3위 카드 빛나기 애니메이션
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _loadFavorites();
    _loadRanking();
    favoritesNotifier.addListener(_loadFavorites);
  }

  @override
  void dispose() {
    _glowController.dispose();
    favoritesNotifier.removeListener(_loadFavorites);
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favorites = (prefs.getStringList('favorite_stores') ?? []).toSet();
    });
  }

  Future<void> _toggleFavorite(String dhlotteryCode) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favorites.contains(dhlotteryCode)) {
        _favorites.remove(dhlotteryCode);
      } else {
        _favorites.add(dhlotteryCode);
      }
    });
    await prefs.setStringList('favorite_stores', _favorites.toList());
    notifyFavoritesChanged();
  }

  Future<void> _loadRanking() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 1. 최신 회차 + 로또 1등 기준 TOP 30 조회
      final latestRound = await SupabaseService.getLatestRound('lotto');
      final latestPension = await SupabaseService.getLatestRound('pension');
      final allStores = await SupabaseService.getTopRankedStores(limit: 40);

      if (allStores.isEmpty) {
        setState(() {
          _rankedStores = [];
          _internetStores = [];
          _isLoading = false;
        });
        return;
      }

      // 인터넷구매 지점 분리 (store_name이 '인터넷'으로 시작하는 지점)
      final internetStores = allStores.where((s) {
        final name = (s['store_name'] ?? '') as String;
        return name.startsWith('인터넷');
      }).toList();
      final stores = allStores.where((s) {
        final name = (s['store_name'] ?? '') as String;
        return !name.startsWith('인터넷');
      }).take(30).toList();

      // 2. 순위 변동 계산
      final prefs = await SharedPreferences.getInstance();
      final prevRankList = prefs.getStringList('prev_ranking') ?? [];
      // 이전 순위 맵: dhlotteryCode -> 이전순위(1부터)
      final Map<String, int> prevRankMap = {};
      for (int i = 0; i < prevRankList.length; i++) {
        prevRankMap[prevRankList[i]] = i + 1;
      }

      // 현재 순위 리스트
      final codes = stores.map((s) => s['dhlottery_code'] as String).toList();
      // 인터넷구매 지점 코드도 배지/연금 로드에 포함
      final allCodes = [...codes, ...internetStores.map((s) => s['dhlottery_code'] as String)];

      // 변동 계산
      final Map<String, int> changes = {};
      for (int i = 0; i < codes.length; i++) {
        final code = codes[i];
        final currentRank = i + 1;
        if (prevRankMap.containsKey(code)) {
          changes[code] = prevRankMap[code]! - currentRank; // 양수=상승
        } else if (prevRankList.isNotEmpty) {
          changes[code] = 99; // 신규 진입
        }
      }

      // 현재 순위 저장 (다음 비교용)
      await prefs.setStringList('prev_ranking', codes);
      await prefs.setInt('prev_ranking_round', latestRound ?? 0);

      // 3. 배지 로드 (인터넷구매 포함)
      await BadgeService.loadBadges(allCodes);

      // 4. 연금복권 당첨 정보 조회 (배지 표시용)
      final pensionData = await SupabaseService.getPensionInfoForStores(allCodes);

      // 5. 최근 24시간 크롤링 성공 로그 조회
      List<Map<String, dynamic>> crawlLogs = [];
      try {
        crawlLogs = await SupabaseService.getRecentSuccessLogs(hours: 24);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _rankedStores = stores;
        _internetStores = internetStores;
        _pensionInfo = pensionData;
        _latestLottoRound = latestRound ?? 0;
        _latestPensionRound = latestPension ?? 0;
        _rankChanges = changes;
        _badgeLoadFailed = BadgeService.loadFailed;
        _recentCrawlLogs = crawlLogs;
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
                    // 배지 로딩 실패 안내
                    if (_badgeLoadFailed)
                      SliverToBoxAdapter(child: _buildBadgeFailBanner()),
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
                    // 인터넷구매 지점 (별도 섹션)
                    if (_internetStores.isNotEmpty) ...[
                      SliverToBoxAdapter(child: _buildInternetSection()),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index >= _internetStores.length) return null;
                              return _buildInternetCard(_internetStores[index]);
                            },
                            childCount: _internetStores.length,
                          ),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ],
                ),
    );
  }

  Widget _buildBadgeFailBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '배지 정보를 불러오지 못했습니다. 아래로 당겨 새로고침 해주세요.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ),
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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '복권명당 TOP 30',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '로또 1등 누적 당첨 횟수 기준',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_latestLottoRound > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '로또 $_latestLottoRound회',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '연금 $_latestPensionRound회',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('적용', style: TextStyle(fontSize: 12, color: Colors.white60)),
              ],
            ),
          ],
          // 크롤링 안내문 (예약/완료)
          ..._buildCrawlNotices(),
        ],
      ),
    );
  }

  /// 크롤링 안내문 목록 생성
  List<Widget> _buildCrawlNotices() {
    final notices = <Widget>[];
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 오늘 완료된 크롤링 로그 확인
    final todayLogs = _recentCrawlLogs.where((log) {
      final completedAt = log['completed_at'] as String?;
      if (completedAt == null) return false;
      return completedAt.startsWith(todayStr);
    }).toList();

    // 완료된 로그가 있으면 표시
    if (todayLogs.isNotEmpty) {
      final typeLabels = <String>[];
      for (var log in todayLogs) {
        final type = log['lottery_type'] as String? ?? '';
        final rounds = log['rounds_processed'] as String? ?? '';
        String label;
        switch (type) {
          case 'lotto':
            label = '로또';
            break;
          case 'pension':
            label = '연금';
            break;
          case 'speeto':
            label = '스피또';
            break;
          default:
            label = type;
        }
        if (rounds.isNotEmpty && rounds != 'latest') {
          label += ' $rounds회차';
        }
        typeLabels.add(label);
      }

      notices.add(const SizedBox(height: 10));
      notices.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.lightGreenAccent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${typeLabels.join(', ')} 업데이트 완료',
                  style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // 완료 로그가 없으면 오늘 예약 정보 표시
      // 스케줄: 목요일 19:30 연금, 토요일 06:00 스피또, 토요일 21:30 로또
      String? scheduleMsg;
      if (now.weekday == DateTime.thursday) {
        scheduleMsg = '오늘 19:30 연금복권 업데이트 예정';
      } else if (now.weekday == DateTime.saturday) {
        if (now.hour < 10) {
          scheduleMsg = '오늘 06:00 스피또 / 21:30 로또 업데이트 예정';
        } else if (now.hour < 22) {
          scheduleMsg = '오늘 21:30 로또 업데이트 예정';
        }
      } else if (now.weekday == DateTime.friday) {
        // 금요일 UTC 21:00 = 토요일 KST 06:00이므로 금요일에도 안내
        scheduleMsg = '내일 06:00 스피또 업데이트 예정';
      }

      if (scheduleMsg != null) {
        notices.add(const SizedBox(height: 10));
        notices.add(
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, color: Colors.amberAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scheduleMsg,
                    style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return notices;
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

  Widget _buildRankChange(int change) {
    if (change == 0) {
      return Text('─', style: TextStyle(fontSize: 11, color: Colors.grey.shade400));
    } else if (change == 99) {
      // 신규 진입
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'NEW',
          style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.bold),
        ),
      );
    } else if (change > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_drop_up, color: Colors.red.shade600, size: 18),
          Text(
            '$change',
            style: TextStyle(fontSize: 11, color: Colors.red.shade600, fontWeight: FontWeight.bold),
          ),
        ],
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_drop_down, color: Colors.blue.shade600, size: 18),
          Text(
            '${change.abs()}',
            style: TextStyle(fontSize: 11, color: Colors.blue.shade600, fontWeight: FontWeight.bold),
          ),
        ],
      );
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
    IconData? medalIcon;
    if (rank == 1) {
      rankColor = Colors.white;
      rankBgColor = const Color(0xFFFFD700);
      medalIcon = Icons.emoji_events_rounded;
    } else if (rank == 2) {
      rankColor = Colors.white;
      rankBgColor = const Color(0xFFA8A8A8);
      medalIcon = Icons.emoji_events_rounded;
    } else if (rank == 3) {
      rankColor = Colors.white;
      rankBgColor = const Color(0xFFCD7F32);
      medalIcon = Icons.emoji_events_rounded;
    } else {
      rankColor = Colors.grey.shade700;
      rankBgColor = Colors.grey.shade200;
      medalIcon = null;
    }

    // 1~3위: 순차 빛나기 (각 1초씩 오프셋)
    final bool isTop3 = rank <= 3;
    final double glowOffset = rank == 1 ? 0.0 : (rank == 2 ? 0.33 : 0.66);

    // 연속당첨 배지 분리 (지점명 옆에 표시할 것)
    final streakBadges = badges.where((b) => b.type == StoreBadgeType.streak).toList();
    final otherBadges = badges.where((b) => b.type != StoreBadgeType.streak).toList();

    // 금/은/동 카드 그라데이션
    List<Color>? cardGradient;
    if (rank == 1) {
      cardGradient = [const Color(0xFFFFFDF0), const Color(0xFFFFF8E1), const Color(0xFFFFF0C0)];
    } else if (rank == 2) {
      cardGradient = [const Color(0xFFFAFAFA), const Color(0xFFF0F0F0), const Color(0xFFE8E8E8)];
    } else if (rank == 3) {
      cardGradient = [const Color(0xFFFDF8F4), const Color(0xFFF5EDE6), const Color(0xFFEDE0D4)];
    }

    Widget cardWidget = GestureDetector(
      onTap: () => _toggleCard(dhlotteryCode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: isTop3
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: cardGradient!,
                )
              : null,
          color: isTop3 ? null : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isTop3
              ? Border.all(color: rankBgColor.withValues(alpha: 0.5), width: 2)
              : Border.all(color: isExpanded ? Colors.blue.shade200 : Colors.grey.shade200, width: 1),
          boxShadow: isTop3
              ? [
                  BoxShadow(
                    color: rankBgColor.withValues(alpha: 0.25),
                    blurRadius: 14,
                    spreadRadius: 1,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
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
                // 순위 메달
                Container(
                  width: isTop3 ? 42 : 36,
                  height: isTop3 ? 42 : 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: isTop3
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              rankBgColor,
                              rankBgColor.withValues(alpha: 0.7),
                              rankBgColor,
                            ],
                          )
                        : null,
                    color: isTop3 ? null : rankBgColor,
                    shape: BoxShape.circle,
                    border: isTop3 ? Border.all(color: rankBgColor.withValues(alpha: 0.8), width: 2) : null,
                    boxShadow: isTop3
                        ? [BoxShadow(color: rankBgColor.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1)]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isTop3) Icon(medalIcon, size: 16, color: Colors.white),
                      Text(
                        '$rank',
                        style: TextStyle(
                          color: rankColor,
                          fontWeight: FontWeight.w900,
                          fontSize: isTop3 ? 11 : 11,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 지점 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              storeName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (streakBadges.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            ...streakBadges.map((b) => _buildStreakBadgeGlow(b)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (_latestLottoRound > 0)
                            Text(
                              '$_latestLottoRound회 당첨적용',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          if (_latestLottoRound > 0) const SizedBox(width: 8),
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
                      // store_badges 배지 (연속당첨은 지점명 옆에 이미 표시)
                      if (otherBadges.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: otherBadges.map((b) => _buildBadgeChip(b)).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                // 즐겨찾기 + 순위변동 + 확장 아이콘
                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _toggleFavorite(dhlotteryCode),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          _favorites.contains(dhlotteryCode) ? Icons.star : Icons.star_border,
                          color: _favorites.contains(dhlotteryCode) ? Colors.amber : Colors.grey.shade400,
                          size: 28,
                        ),
                      ),
                    ),
                    if (_rankChanges.containsKey(dhlotteryCode))
                      _buildRankChange(_rankChanges[dhlotteryCode]!),
                    const SizedBox(height: 2),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
            // ── 확장 영역 ──
            if (isExpanded) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.grey.shade200),
              const SizedBox(height: 12),
              // 판매점 평가
              _InlineReviewSection(dhlotteryCode: dhlotteryCode),
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

    // 1~3위: 순차적 빛나기 효과 (shimmer border)
    if (isTop3) {
      return AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          // 순차 오프셋: 1위→2위→3위 순서로 빛남
          final t = (_glowController.value + glowOffset) % 1.0;
          // 0.0~0.3 구간에서 빛나고 나머지는 안 빛남
          final glowIntensity = t < 0.3 ? (0.5 + 0.5 * (1 - (t / 0.3 - 0.5).abs() * 2)).clamp(0.0, 1.0) : 0.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              boxShadow: glowIntensity > 0.05
                  ? [
                      BoxShadow(
                        color: rankBgColor.withValues(alpha: 0.3 * glowIntensity),
                        blurRadius: 16 * glowIntensity,
                        spreadRadius: 2 * glowIntensity,
                      ),
                    ]
                  : null,
            ),
            child: child,
          );
        },
        child: cardWidget,
      );
    }

    return cardWidget;
  }

  Widget _buildInternetSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.computer, color: Colors.indigo.shade400, size: 20),
              const SizedBox(width: 8),
              Text(
                '인터넷 구매',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '별도 집계',
                  style: TextStyle(fontSize: 10, color: Colors.indigo.shade400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '동행복권 온라인 구매 당첨 현황',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildInternetCard(Map<String, dynamic> store) {
    final storeName = store['store_name'] ?? '';
    final firstCount = store['first_count'] ?? 0;
    final secondCount = store['second_count'] ?? 0;
    final dhlotteryCode = store['dhlottery_code'] as String;
    final badges = BadgeService.getBadges(dhlotteryCode);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade200, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.indigo.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.language, color: Colors.indigo.shade600, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  storeName,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo.shade800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
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
        ],
      ),
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

  /// 연속당첨 배지 - 빛나는 특별 효과
  Widget _buildStreakBadgeGlow(StoreBadge badge) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final t = (_glowController.value * 2) % 1.0;
        final glow = (0.4 + 0.6 * (0.5 + 0.5 * (t < 0.5 ? t * 2 : 2 - t * 2))).clamp(0.0, 1.0);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFFF6D00).withValues(alpha: 0.15 + 0.1 * glow),
                const Color(0xFFFFAB00).withValues(alpha: 0.15 + 0.1 * glow),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Color.lerp(const Color(0xFFFF8F00), const Color(0xFFFFD600), glow)!.withValues(alpha: 0.8),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFAB00).withValues(alpha: 0.3 * glow),
                blurRadius: 6 * glow,
                spreadRadius: 1 * glow,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department, size: 12, color: Color.lerp(const Color(0xFFFF6D00), const Color(0xFFFFD600), glow)),
              const SizedBox(width: 2),
              Text(
                badge.label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE65100),
                ),
              ),
            ],
          ),
        );
      },
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

// ============================================================
// 설정 다이얼로그
// ============================================================
class _SettingsDialog extends StatefulWidget {
  final TextEditingController inputController;
  final TextEditingController couponController;
  final bool adsRemoved;
  final bool isLoggedIn;
  final bool isAdmin;
  final VoidCallback? onAdminTap;
  final void Function(String) onSaveProfile;
  final Future<Map<String, dynamic>> Function(String) onRedeemCoupon;

  const _SettingsDialog({
    required this.inputController,
    required this.couponController,
    required this.adsRemoved,
    required this.isLoggedIn,
    this.isAdmin = false,
    this.onAdminTap,
    required this.onSaveProfile,
    required this.onRedeemCoupon,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
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

class _SettingsDialogState extends State<_SettingsDialog> {
  bool _isRedeeming = false;
  String? _couponMessage;
  bool? _couponSuccess;
  late bool _adsRemoved;
  bool _isDonating = false;
  String? _donationMessage;
  bool? _donationSuccess;

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

  Future<void> _handleDonation() async {
    setState(() {
      _isDonating = true;
      _donationMessage = null;
    });

    final donation = DonationService();
    donation.onPurchaseResult = (success, message) {
      if (!mounted) return;
      setState(() {
        _isDonating = false;
        _donationSuccess = success;
        _donationMessage = message;
      });
    };

    if (!donation.isAvailable) {
      // 스토어 미연결 시 초기화 시도
      await donation.initialize();
    }

    if (!donation.isAvailable) {
      if (!mounted) return;
      setState(() {
        _isDonating = false;
        _donationSuccess = false;
        _donationMessage = '스토어에 연결할 수 없습니다. 나중에 다시 시도해 주세요.';
      });
      return;
    }

    final started = await donation.buyCoffee();
    if (!started && mounted) {
      setState(() {
        _isDonating = false;
      });
    }
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

              // 쿠폰 입력 섹션 (로그인 시에만 표시)
              if (widget.isLoggedIn) Container(
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
                                hintText: '쿠폰 코드',
                                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
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

              const SizedBox(height: 16),

              // 커피 후원 섹션
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD54F)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('☕', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '개발자에게 커피 후원하기',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '앱 개발에 큰 힘이 됩니다!',
                                style: TextStyle(fontSize: 12, color: Color(0xFF8D6E63)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isDonating ? null : _handleDonation,
                        icon: _isDonating
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('☕', style: TextStyle(fontSize: 16)),
                        label: Text(
                          _isDonating ? '처리 중...' : '커피 한 잔 후원하기',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6D4C41),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 2,
                        ),
                      ),
                    ),
                    if (_donationMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _donationMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _donationSuccess == true ? Colors.green.shade700 : Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
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
              // 관리자 바로가기
              if (widget.isAdmin && widget.onAdminTap != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onAdminTap,
                    icon: Icon(Icons.admin_panel_settings, size: 18, color: Colors.purple.shade700),
                    label: Text('관리자 페이지', style: TextStyle(color: Colors.purple.shade700, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.purple.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
