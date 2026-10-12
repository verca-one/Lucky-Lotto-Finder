import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import '../services/ad_service.dart';
import '../services/badge_service.dart';
import '../services/ranking_extras_service.dart';
import '../widgets/ranking_store_card.dart';
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
    if (!mounted) return;
    final loaded = await AdService.loadBannerAd();
    if (!mounted) return;
    setState(() {
      _isBannerLoaded = loaded;
      _bannerAd = AdService.bannerAd;
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
      backgroundColor: Colors.transparent,
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
      body: Stack(
        children: [
          // 1. dra.png 배경 (전체 opacity)
          Positioned.fill(
            child: Image.asset(
              'assets/dra.png',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
            ),
          ),
          // 2. 흰색 반투명 오버레이 (0.75 → 이미지 25% 노출, 테스트용)
          Positioned.fill(
            child: Container(
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          // 3. 기존 콘텐츠
          IndexedStack(index: _selectedBottomTab, children: pages),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: Container(
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
              elevation: 0,
              currentIndex: _selectedBottomTab,
              onTap: (index) {
                if (index == 3 && _selectedBottomTab == 3) {
                  _recommendKey.currentState?.resetToMain();
                }
                // 탭 전환은 누른 즉시 반영한다. (이전: 전면광고가 닫히거나 표시 실패 콜백이 온 뒤에
                // 탭을 바꿔, 사용자가 홈에 돌아와 있어도 몇 초~수십 초 뒤 '추천' 등으로 저절로 넘어갔다.)
                // 광고는 전환 후에 띄우며, 광고 콜백은 화면을 이동시키지 않는다. 같은 탭 재탭은 카운트 제외.
                final changed = index != _selectedBottomTab;
                setState(() => _selectedBottomTab = index);
                if (changed) AdService.onMenuUsed(context, onAfter: () {});
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
          ),
          if (!AdService.adsRemoved && _isBannerLoaded && _bannerAd != null)
            SafeArea(
              top: false,
              left: false,
              right: false,
              child: SizedBox(
                width: double.infinity,
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            )
          else
            SafeArea(top: false, left: false, right: false, child: const SizedBox.shrink()),
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

class _HomeRankingContentState extends State<_HomeRankingContent> with TickerProviderStateMixin {
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
  // 로그인 여부
  String _userId = '';
  // 랭킹 카드 부가 정보 (주기 통계 · 관련 가설 수 · 지방장 연구 점수) — 목록 단위 일괄 조회
  Map<String, RankingStoreExtras> _extras = {};

  // 1~3위 카드 빛나기 애니메이션
  late AnimationController _glowController;
  // 스켈레톤 shimmer 애니메이션
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _loadFavorites();
    _loadRanking();
    _loadUserId();
    favoritesNotifier.addListener(_loadFavorites);
  }

  @override
  void dispose() {
    _glowController.dispose();
    _shimmerController.dispose();
    favoritesNotifier.removeListener(_loadFavorites);
    super.dispose();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _userId = prefs.getString('userId') ?? '');
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

  Future<void> _loadExtras(List<Map<String, dynamic>> stores, {bool force = false}) async {
    try {
      final extras = await RankingExtrasService.load(stores, force: force);
      if (!mounted) return;
      setState(() => _extras = extras);
    } catch (_) {
      // 부가 정보는 선택 사항 — 실패해도 카드는 기본 정보로 표시
    }
  }

  Future<void> _loadRanking() async {
    // 당겨서 새로고침이면 부가 정보 캐시도 무시
    final isRefresh = _rankedStores.isNotEmpty;
    // 캐시 데이터가 있으면 먼저 표시 (로딩 스켈레톤 없이 즉시 보임)
    if (_rankedStores.isEmpty) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      // 1. home_stats(1건) + TOP 20 — 병렬 실행
      final results = await Future.wait([
        SupabaseService.getHomeStats(),
        SupabaseService.getTopRankedStores(limit: 20),
      ]);

      final homeStats = results[0] as Map<String, dynamic>?;
      final int? latestRound = homeStats != null
          ? (homeStats['lotto_latest_round'] as num?)?.toInt()
          : await SupabaseService.getLatestRound('lotto');
      final int? latestPension = homeStats != null
          ? (homeStats['pension_latest_round'] as num?)?.toInt()
          : await SupabaseService.getLatestRound('pension');
      final allStores = results[1] as List<Map<String, dynamic>>;

      if (allStores.isEmpty) {
        setState(() {
          _rankedStores = [];
          _internetStores = [];
          _isLoading = false;
        });
        return;
      }

      // 인터넷구매 지점 분리
      final internetStores = allStores.where((s) {
        final name = (s['store_name'] ?? '') as String;
        return name.startsWith('인터넷');
      }).toList();
      final stores = allStores.where((s) {
        final name = (s['store_name'] ?? '') as String;
        return !name.startsWith('인터넷');
      }).take(20).toList();

      final codes    = stores.map((s) => s['dhlottery_code'] as String).toList();
      final allCodes = [...codes, ...internetStores.map((s) => s['dhlottery_code'] as String)];

      // 2. 순위 변동은 DB의 rank_change / rank_status 값을 그대로 사용
      //    (recalculate_store_counts.py가 크롤링마다 DB에 저장) → RankingCardData.fromStore 에서 해석

      // 3. 배지 + 연금 + 크롤링 로그 — 병렬 실행
      List<Map<String, dynamic>> crawlLogs = [];
      final secondResults = await Future.wait([
        BadgeService.loadBadges(allCodes),
        SupabaseService.getPensionInfoForStores(allCodes),
        SupabaseService.getRecentSuccessLogs(hours: 168).catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final pensionData = secondResults[1] as Map<String, Map<String, dynamic>>;
      crawlLogs = secondResults[2] as List<Map<String, dynamic>>;

      if (!mounted) return;
      setState(() {
        _rankedStores = stores;
        _internetStores = internetStores;
        _pensionInfo = pensionData;
        _latestLottoRound = latestRound ?? 0;
        _latestPensionRound = latestPension ?? 0;
        _badgeLoadFailed = BadgeService.loadFailed;
        _recentCrawlLogs = crawlLogs;
        _isLoading = false;
      });
      // 초기 로딩 완료 → 이후 전면광고 허용
      AdService.markInitialLoadComplete();
      // 카드 부가 정보: 보이는 랭킹 목록 전체를 한 번에 조회 (실패 시 해당 값만 '-')
      _loadExtras(stores, force: isRefresh);
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
    if (_error != null) {
      return Center(child: Text('오류: $_error'));
    }

    return RefreshIndicator(
      onRefresh: _loadRanking,
      child: CustomScrollView(
        slivers: [
          // 헤더 (파란 배경) — 로딩 중에도 먼저 표시
          SliverToBoxAdapter(child: _buildHeader()),

          if (_isLoading) ...[
            // ── 스켈레톤 로딩 UI ──────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Row(
                  children: [
                    const Text(
                      '랭킹',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'TOP 30',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '전국 당첨지점 정보를 불러오는 중입니다...',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => i < 5 ? _buildSkeletonCard() : null,
                  childCount: 5,
                ),
              ),
            ),
          ] else ...[
            // ── 실제 데이터 ───────────────────────────────────
            if (_isUpdateTime)
              SliverToBoxAdapter(child: _buildUpdateBanner()),
            if (_badgeLoadFailed)
              SliverToBoxAdapter(child: _buildBadgeFailBanner()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  children: [
                    const Text(
                      '랭킹',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'TOP ${_rankedStores.length}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
        ],
      ),
    );
  }

  // ── 스켈레톤 카드 ────────────────────────────────────────────
  Widget _buildSkeletonCard() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, _) {
        final sweep = _shimmerController.value * 3.0 - 1.5;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBox(36, 36, sweep, isCircle: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(null, 15, sweep),
                    const SizedBox(height: 6),
                    _shimmerBox(160, 12, sweep),
                    const SizedBox(height: 4),
                    _shimmerBox(120, 12, sweep),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _shimmerBox(62, 22, sweep),
                        const SizedBox(width: 6),
                        _shimmerBox(78, 22, sweep),
                        const SizedBox(width: 6),
                        _shimmerBox(62, 22, sweep),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  _shimmerBox(28, 28, sweep, isCircle: true),
                  const SizedBox(height: 6),
                  _shimmerBox(28, 14, sweep),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _shimmerBox(double? width, double height, double sweep,
      {bool isCircle = false}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(sweep - 1, 0),
          end: Alignment(sweep + 1, 0),
          colors: const [Color(0xFFE0E0E0), Color(0xFFF5F5F5), Color(0xFFE0E0E0)],
        ),
        borderRadius: BorderRadius.circular(isCircle ? height / 2 : 4),
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
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x881565C0), Color(0x881E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '실제 당첨 이력을 분석한 통계입니다.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '당첨주기 예상은 예측이 아닌 참고 정보입니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                      ),
                      child: const Text(
                        '⚠️ 복권명당 찾기 앱은 당첨을 보장하지 않습니다.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 38),
              ),
            ],
          ),
          if (_latestLottoRound > 0) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                _buildHeaderChip('로또 $_latestLottoRound회'),
                const SizedBox(width: 8),
                _buildHeaderChip('연금 $_latestPensionRound회'),
                const SizedBox(width: 8),
                Text('기준', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
              ],
            ),
          ],
          ..._buildCrawlNotices(),
        ],
      ),
    );
  }

  Widget _buildHeaderChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
    );
  }

  /// 크롤링 안내문 목록 생성
  List<Widget> _buildCrawlNotices() {
    if (_recentCrawlLogs.isEmpty) return [];

    // 타입별 최신 로그 1건씩 추출
    final latestByType = <String, Map<String, dynamic>>{};
    for (final log in _recentCrawlLogs) {
      final type = log['lottery_type'] as String? ?? '';
      if (type.isEmpty) continue;
      if (!latestByType.containsKey(type)) latestByType[type] = log;
    }
    if (latestByType.isEmpty) return [];

    // 표시 순서: 로또 → 연금 → 스피또
    const order = ['lotto', 'pension', 'speeto'];
    final lines = <String>[];
    final now = DateTime.now();

    for (final type in order) {
      final log = latestByType[type];
      if (log == null) continue;
      final completedAtRaw = log['completed_at'] as String?;
      if (completedAtRaw == null) continue;

      // UTC → KST (+9시간)
      final utc = DateTime.tryParse(completedAtRaw);
      if (utc == null) continue;
      final kst = utc.toLocal(); // 기기 타임존 = KST 가정
      final hh = kst.hour.toString().padLeft(2, '0');
      final mm = kst.minute.toString().padLeft(2, '0');

      // 오늘이 아니면 날짜도 표시
      final isToday = kst.year == now.year && kst.month == now.month && kst.day == now.day;
      final timeStr = isToday ? '$hh:$mm' : '${kst.month}/${kst.day} $hh:$mm';

      String label;
      switch (type) {
        case 'lotto':
          label = _latestLottoRound > 0 ? '로또(${_latestLottoRound}회)' : '로또';
          break;
        case 'pension':
          label = _latestPensionRound > 0 ? '연금(${_latestPensionRound}회)' : '연금';
          break;
        case 'speeto':
          label = '스피또';
          break;
        default:
          label = type;
      }
      lines.add('$label가 ${timeStr}에 업데이트 되었습니다.');
    }

    if (lines.isEmpty) return [];

    return [
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines.map((line) => Padding(
            padding: EdgeInsets.only(bottom: line == lines.last ? 0 : 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.lightGreenAccent, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    line,
                    style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          )).toList(),
        ),
      ),
    ];
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
    final storeName = (store['store_name'] ?? '').toString();
    final address = (store['address'] ?? '').toString();
    final dhlotteryCode = store['dhlottery_code'] as String;
    final isExpanded = _expandedCards.contains(dhlotteryCode);

    // 배지 가져오기 (store_badges, BadgeService 캐시)
    final badges = BadgeService.getBadges(dhlotteryCode);

    // 연속당첨 배지 분리 (지점명 아래 강조 칩)
    // "이번 달 N회 당첨" 배지가 여러 개면 가장 높은 것만 표시
    final allStreakBadges = badges.where((b) => b.type == StoreBadgeType.streak).toList();
    final monthWinBadges = allStreakBadges.where((b) => b.label.contains('이번 달')).toList();
    final otherStreakBadges = allStreakBadges.where((b) => !b.label.contains('이번 달')).toList();
    StoreBadge? topMonthBadge;
    if (monthWinBadges.isNotEmpty) {
      topMonthBadge = monthWinBadges.reduce((a, b) {
        final aNum = RegExp(r'(\d+)회').firstMatch(a.label)?.group(1);
        final bNum = RegExp(r'(\d+)회').firstMatch(b.label)?.group(1);
        return (int.tryParse(aNum ?? '0') ?? 0) >= (int.tryParse(bNum ?? '0') ?? 0) ? a : b;
      });
    }
    final streakBadges = [?topMonthBadge, ...otherStreakBadges];
    final otherBadges = badges.where((b) => b.type != StoreBadgeType.streak).toList();

    final data = RankingCardData.fromStore(rank, store, pension: _pensionInfo[dhlotteryCode]);
    final tier = data.tier;

    final Widget cardWidget = RankingStoreCard(
      key: ValueKey('ranking_card_$dhlotteryCode'),
      data: data,
      extras: _extras[dhlotteryCode],
      badges: otherBadges,
      highlightBadges: streakBadges,
      isFavorite: _favorites.contains(dhlotteryCode),
      isExpanded: isExpanded,
      latestRound: _latestLottoRound,
      glow: _glowController,
      onTap: () => _toggleCard(dhlotteryCode),
      onFavoriteTap: () => _toggleFavorite(dhlotteryCode),
      onMapTap: address.isEmpty
          ? null
          : () => _openMap(mapType: 'naver', storeName: storeName, address: address),
      expandedChild: isExpanded ? _buildExpandedDetail(dhlotteryCode, storeName, address) : null,
      // 엔진·지방장 연구 정보는 관리자 메뉴 전용 → 홈 랭킹 카드에는 표시하지 않는다
      showResearch: false,
    );

    // 1~3위: 순차적 빛나기 효과 (각 1초씩 오프셋)
    if (tier != RankTier.plain) {
      final double glowOffset = rank == 1 ? 0.0 : (rank == 2 ? 0.33 : 0.66);
      final Color glowColor = rank == 1
          ? const Color(0xFFFFD700)
          : (rank == 2 ? const Color(0xFFA8A8A8) : const Color(0xFFCD7F32));
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            // 순차 오프셋: 1위→2위→3위 순서로 빛남, 0.0~0.3 구간에서만 빛남
            final t = (_glowController.value + glowOffset) % 1.0;
            final glowIntensity = t < 0.3 ? (0.5 + 0.5 * (1 - (t / 0.3 - 0.5).abs() * 2)).clamp(0.0, 1.0) : 0.0;
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: glowIntensity > 0.05
                    ? [
                        BoxShadow(
                          color: glowColor.withValues(alpha: 0.3 * glowIntensity),
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
        ),
      );
    }

    return Padding(padding: const EdgeInsets.only(bottom: 12), child: cardWidget);
  }

  /// 카드 확장 영역 (기존 기능: 판매점 평가 · 지도 버튼 · 당첨 이력 + 지방장 연구 근거)
  Widget _buildExpandedDetail(String dhlotteryCode, String storeName, String address) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

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
    );
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
  bool _settingsBannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _adsRemoved = widget.adsRemoved;
    _loadSettingsBanner();
  }

  @override
  void dispose() {
    AdService.disposeSettingsBanner();
    super.dispose();
  }

  void _loadSettingsBanner() {
    AdService.loadSettingsBannerAd(() {
      if (mounted) setState(() => _settingsBannerLoaded = true);
    });
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

              // 설정 배너 광고 (로드 성공 시에만 표시)
              if (!_adsRemoved &&
                  _settingsBannerLoaded &&
                  AdService.settingsBannerAd != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: AdService.settingsBannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: AdService.settingsBannerAd!),
                ),
                const SizedBox(height: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
