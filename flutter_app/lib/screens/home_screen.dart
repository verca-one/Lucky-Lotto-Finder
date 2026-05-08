import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/lotto_winning_number.dart';
import '../models/lottery_store.dart';
import '../models/pension_winning_number.dart';
import '../services/local_data_service.dart';
import '../services/lotto_winning_service.dart';
import '../services/supabase_service.dart';
import '../services/ad_service.dart';
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
  int _lottoRefreshToken = 0;
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
                '🤖 관리자 인증',
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
                      ).then((_) {
                        if (mounted) {
                          setState(() {
                            _lottoRefreshToken++;
                          });
                        }
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✓ 관리자 인증 성공')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✗ 비밀번호가 일치하지 않습니다')),
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
      Column(
        children: [
          TabBar(
            tabs: const [
              Tab(text: '로또'),
              Tab(text: '연금복권'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _LotteryTabContent(
                  type: 'lotto',
                  refreshToken: _lottoRefreshToken,
                ),
                _LotteryTabContent(
                  type: 'pension',
                  refreshToken: _lottoRefreshToken,
                ),
              ],
            ),
          ),
        ],
      ),
      const NearbyScreen(),
      const RegionScreen(),
      const FavoritesScreen(),
    ];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
      ),
    );
  }
}

class _BottomTabPlaceholder extends StatelessWidget {
  final String message;
  const _BottomTabPlaceholder({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message));
  }
}

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

              // ── 쿠폰 입력 섹션 ──
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

              // ── 프로필 섹션 ──
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

class _LotteryTabContent extends StatefulWidget {
  final String type;
  final int refreshToken;

  const _LotteryTabContent({required this.type, required this.refreshToken});

  @override
  State<_LotteryTabContent> createState() => _LotteryTabContentState();
}

class _LotteryTabContentState extends State<_LotteryTabContent> {
  final Set<String> _expandedStoreKeys = <String>{};
  late Future<List<LotteryStore>> _storesFuture;
  late Future<LottoWinningNumber?> _latestWinningFuture;
  late Future<List<LotteryStore>> _loadedWinningStoresFuture;
  late Future<List<LottoWinningNumber>> _allRoundsFuture;

  // 회차 이동 관련
  int? _selectedLottoRound;

  // 연금복권 관련
  late Future<List<PensionWinningNumber>> _pensionRoundsFuture;
  int? _selectedPensionRound;

  @override
  void initState() {
    super.initState();
    _storesFuture = _loadStores();
    _latestWinningFuture = _loadLatestLottoWinning();
    _loadedWinningStoresFuture = _loadLoadedWinningStores();
    _allRoundsFuture = _loadAllRounds();
    _pensionRoundsFuture = _loadPensionRounds();
  }

  @override
  void didUpdateWidget(covariant _LotteryTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type ||
        oldWidget.refreshToken != widget.refreshToken) {
      _storesFuture = _loadStores();
      _latestWinningFuture = _loadLatestLottoWinning();
      _loadedWinningStoresFuture = _loadLoadedWinningStores();
      _pensionRoundsFuture = _loadPensionRounds();
    }
  }

  Future<List<LotteryStore>> _loadStores() {
    return widget.type == 'lotto'
        ? LocalDataService().getLottoStores()
        : LocalDataService().getPensionStores();
  }

  // 최신 회차 캐시 (중복 API 호출 방지)
  int? _cachedLatestRound;

  Future<LottoWinningNumber?> _loadLatestLottoWinning() async {
    if (widget.type != 'lotto') return Future.value(null);

    // 로컬 캐시 우선 (빠름)
    final localRounds = await LottoWinningService().getAllRounds();
    if (localRounds.isNotEmpty) {
      _cachedLatestRound = localRounds.first.round;
      return localRounds.first;
    }

    // 로컬 없으면 Supabase
    final latestRound = await SupabaseService.getLatestRound('lotto');
    if (latestRound == null) return null;
    _cachedLatestRound = latestRound;

    final fromSupabase = await SupabaseService.getWinningNumbersForRound(latestRound);
    return fromSupabase;
  }

  Future<List<LotteryStore>> _loadLoadedWinningStores() async {
    if (widget.type != 'lotto') return [];

    // _loadLatestLottoWinning에서 캐시된 회차 재활용 (중복 API 호출 방지)
    // 아직 캐시 안 됐으면 대기
    int? round = _cachedLatestRound;
    if (round == null) {
      // 먼저 로컬에서 시도
      final localRounds = await LottoWinningService().getAllRounds();
      if (localRounds.isNotEmpty) {
        round = localRounds.first.round;
      } else {
        round = await SupabaseService.getLatestRound('lotto');
      }
    }
    if (round == null) return [];
    return SupabaseService.getLottoWinningStoresForRound(round);
  }

  Future<List<LotteryStore>> _loadLoadedWinningStoresForRound(int round) async {
    if (widget.type != 'lotto') return [];
    // Supabase에서 직접 당첨지점 조회 (로컬 저장소 우회)
    return SupabaseService.getLottoWinningStoresForRound(round);
  }

  Future<List<PensionWinningNumber>> _loadPensionRounds() async {
    // 관리자가 생성한 회차만 (Supabase pension_rounds 기반)
    return SupabaseService.getAdminPensionRounds();
  }

  Future<List<LotteryStore>> _loadPensionWinningStoresForRound(int round) async {
    // 관리자가 발행한 회차의 지점만 (Supabase pension_rounds.stores_published 확인)
    return SupabaseService.getPublishedPensionStores(round);
  }

  Future<List<LottoWinningNumber>> _loadAllRounds() async {
    if (widget.type != 'lotto') return [];

    // 로컬 캐시 우선 (빠름)
    final localRounds = await LottoWinningService().getAllRounds();
    if (localRounds.isNotEmpty) return localRounds;

    // 로컬 없으면 Supabase에서 최신 20개만
    final supabaseWinnings = await SupabaseService.getRecentWinningNumbers(20);
    if (supabaseWinnings.isNotEmpty) {
      // 로컬에 캐시 저장
      final service = LottoWinningService();
      for (final r in supabaseWinnings) {
        await service.saveRound(r);
      }
      return supabaseWinnings;
    }

    return [];
  }

  // 지역 정렬 순서 (서울 → 제주)
  static const List<String> _regionOrder = [
    '서울', '경기', '인천', '강원', '충북', '충남', '대전', '세종',
    '전북', '전남', '광주', '경북', '대구', '경남', '부산', '울산', '제주',
  ];

  static int _regionIndex(String region) {
    for (int i = 0; i < _regionOrder.length; i++) {
      if (region.contains(_regionOrder[i])) return i;
    }
    return _regionOrder.length;
  }

  // 당첨지점을 지역순으로 정렬
  List<LotteryStore> _sortByRegion(List<LotteryStore> stores) {
    final sorted = List<LotteryStore>.from(stores);
    sorted.sort((a, b) => _regionIndex(a.region).compareTo(_regionIndex(b.region)));
    return sorted;
  }

  /// 날짜를 "YYYY년 MM월 DD일" 형식으로 변환
  String _formatDateOnly(String dateStr) {
    if (dateStr.isEmpty || dateStr == '정보 없음') return dateStr;
    try {
      // "2024-01-06", "2024-01-06T12:00:00" 등 파싱
      final dt = DateTime.parse(dateStr.replaceAll('.', '-').split('T').first.split(' ').first);
      return '${dt.year}년 ${dt.month}월 ${dt.day}일';
    } catch (_) {
      // "2024.01.06" 같은 포맷
      final parts = dateStr.split(RegExp(r'[.\-/]'));
      if (parts.length >= 3) {
        return '${parts[0]}년 ${int.tryParse(parts[1]) ?? parts[1]}월 ${int.tryParse(parts[2].split(' ').first.split('T').first) ?? parts[2]}일';
      }
      return dateStr;
    }
  }

  String _storeKey(LotteryStore store) {
    return '${store.round}_${store.prizeTier}_${store.dhlotteryCode}_${store.storeName}';
  }

  void _toggleStoreCard(LotteryStore store) {
    final key = _storeKey(store);
    setState(() {
      if (_expandedStoreKeys.contains(key)) {
        _expandedStoreKeys.remove(key);
      } else {
        _expandedStoreKeys.add(key);
      }
    });
  }

  Future<void> _openMap({
    required String mapType,
    required LotteryStore store,
  }) async {
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
      // 네이버지도 앱 미설치 등 폴백
      final fallbackQuery = Uri.encodeComponent(store.address);
      final fallbackUrl = mapType == 'naver'
          ? 'https://map.naver.com/v5/search/$fallbackQuery'
          : 'https://map.kakao.com/link/search/$fallbackQuery';
      final launched = await launchUrl(Uri.parse(fallbackUrl), mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('지도를 열 수 없습니다')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LotteryStore>>(
      future: _storesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('오류: ${snapshot.error}'));
        }

        final stores = snapshot.data ?? [];
        if (stores.isEmpty) {
          return const Center(child: Text('데이터가 없습니다'));
        }

        final latestRound = stores.isNotEmpty
            ? stores.reduce((a, b) => a.round > b.round ? a : b).round
            : 0;
        final latestStores = stores
            .where((s) => s.round == latestRound)
            .toList();

        final firstPlace = latestStores.where((s) => s.prizeTier == 'first');
        final secondPlace = latestStores.where((s) => s.prizeTier == 'second');

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 번호 영역 (회색 배경)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                color: Colors.grey.shade100,
                child: widget.type == 'lotto'
                    ? FutureBuilder<List<LottoWinningNumber>>(
                          future: _allRoundsFuture,
                          builder: (context, allRoundsSnapshot) {
                            final allRounds = allRoundsSnapshot.data ?? [];
                            final latestRoundNum = allRounds.isNotEmpty
                                ? allRounds.first.round
                                : latestRound;

                            final displayRound = _selectedLottoRound ?? latestRoundNum;

                            // 선택한 회차의 당첨번호 찾기
                            final selectedWinning = allRounds.firstWhere(
                              (r) => r.round == displayRound,
                              orElse: () => LottoWinningNumber(
                                drawDate: '',
                                round: displayRound,
                                numbers: [],
                                bonusNumber: 0,
                              ),
                            );

                            final displayDate = selectedWinning.drawDate.isNotEmpty
                                ? selectedWinning.drawDate
                                : (latestStores.isNotEmpty
                                    ? latestStores.first.crawledAt ?? '정보 없음'
                                    : '정보 없음');

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // 회차 네비게이션 (양옆 화살표)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // 좌측 화살표 (이전 회차)
                                    IconButton(
                                      icon: const Icon(Icons.arrow_back_ios, size: 20),
                                      onPressed: displayRound > 1
                                          ? () => setState(() {
                                                _selectedLottoRound = displayRound - 1;
                                              })
                                          : null,
                                    ),
                                    // 당첨 회차
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          '로또 $displayRound회',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.headlineSmall,
                                        ),
                                      ),
                                    ),
                                    // 우측 화살표 (다음 회차) - 최신 회차면 숨김
                                    displayRound < latestRoundNum
                                        ? IconButton(
                                            icon: const Icon(Icons.arrow_forward_ios, size: 20),
                                            onPressed: () => setState(() {
                                              _selectedLottoRound = displayRound + 1;
                                            }),
                                          )
                                        : SizedBox(
                                            width: 48,
                                          ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDateOnly(displayDate),
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 8),
                                // 회차이동 버튼
                                Center(
                                  child: TextButton(
                                    onPressed: () => _showRoundPickerDialog(context, allRounds, latestRoundNum),
                                    child: Text('회차이동', style: TextStyle(color: Colors.blue.shade600, fontSize: 13)),
                                  ),
                                ),
                                if (selectedWinning.numbers.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ...selectedWinning.numbers.map(
                                        (value) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                          ),
                                          child: _buildBall(
                                            value,
                                            _ballColorForNumber(value),
                                          ),
                                        ),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: Text(
                                          '+',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      _buildBall(
                                        selectedWinning.bonusNumber,
                                        _ballColorForNumber(
                                          selectedWinning.bonusNumber,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            );
                          },
                        )
                      : FutureBuilder<List<PensionWinningNumber>>(
                          future: _pensionRoundsFuture,
                          builder: (context, pensionSnapshot) {
                            final pensionRounds = pensionSnapshot.data ?? [];
                            if (pensionRounds.isEmpty) {
                              return const Center(child: Text('연금복권 당첨번호가 아직 없습니다'));
                            }

                            final latestPensionRound = pensionRounds.first.round;
                            final displayRound = _selectedPensionRound ?? latestPensionRound;

                            final selected = pensionRounds.firstWhere(
                              (r) => r.round == displayRound,
                              orElse: () => pensionRounds.first,
                            );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // 회차 네비게이션
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.arrow_back_ios, size: 20),
                                      onPressed: displayRound > 1
                                          ? () => setState(() => _selectedPensionRound = displayRound - 1)
                                          : null,
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          '연금복권 $displayRound회',
                                          style: Theme.of(context).textTheme.headlineSmall,
                                        ),
                                      ),
                                    ),
                                    displayRound < latestPensionRound
                                        ? IconButton(
                                            icon: const Icon(Icons.arrow_forward_ios, size: 20),
                                            onPressed: () => setState(() => _selectedPensionRound = displayRound + 1),
                                          )
                                        : const SizedBox(width: 48),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(_formatDateOnly(selected.drawDate), style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                const SizedBox(height: 8),
                                // 회차이동 버튼
                                Center(
                                  child: TextButton(
                                    onPressed: () => _showPensionRoundPickerDialog(context, pensionRounds, latestPensionRound),
                                    child: Text('회차이동', style: TextStyle(color: Colors.orange.shade600, fontSize: 13)),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // 1등 번호 표시
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.orange.shade300),
                                  ),
                                  child: Column(
                                    children: [
                                      const Text('1등', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange)),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          _buildPensionGroupBall(selected.winningGroup),
                                          const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 4),
                                            child: Text('조', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                          ),
                                          ...selected.winningNumber.split('').asMap().entries.map(
                                            (e) => Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 2),
                                              child: _buildPensionBall(e.value, e.key),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      const Text('보너스', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 4),
                                            child: Text('각조', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          ),
                                          ...selected.bonusNumber.split('').asMap().entries.map(
                                            (e) => Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 2),
                                              child: _buildPensionBall(e.value, e.key),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
              ),
              // 구분선
              Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
              // 하단 당첨지점 영역
              Padding(
                padding: const EdgeInsets.all(16),
                child: _buildWinningStoresSection(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWinningStoresSection() {
    if (widget.type == 'lotto') {
      return FutureBuilder<List<LottoWinningNumber>>(
        future: _allRoundsFuture,
        builder: (context, allRoundsSnapshot) {
          final allRounds = allRoundsSnapshot.data ?? [];
          final latestRoundNum = allRounds.isNotEmpty ? allRounds.first.round : 0;
          final displayRound = _selectedLottoRound ?? latestRoundNum;

          return FutureBuilder<List<LotteryStore>>(
            future: _loadLoadedWinningStoresForRound(displayRound),
            builder: (context, loadedSnapshot) {
              final loadedStores = loadedSnapshot.data ?? [];
              if (loadedStores.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('당첨지점을 검색하는 중입니다.', style: TextStyle(color: Colors.grey.shade500)),
                  ),
                );
              }
              final firstPlace = _sortByRegion(loadedStores.where((s) => s.prizeTier == 'first').toList());
              final secondPlace = _sortByRegion(loadedStores.where((s) => s.prizeTier == 'second').toList());

              return Column(
                children: [
                  _buildPrizeSection(firstPlace, isFirst: true, accentColor: Colors.amber),
                  const SizedBox(height: 16),
                  _buildPrizeSection(secondPlace, isFirst: false, accentColor: Colors.grey),
                ],
              );
            },
          );
        },
      );
    } else {
      return FutureBuilder<List<PensionWinningNumber>>(
        future: _pensionRoundsFuture,
        builder: (context, pensionSnapshot) {
          final pensionRounds = pensionSnapshot.data ?? [];
          if (pensionRounds.isEmpty) {
            return Center(child: Text('연금복권 데이터가 없습니다', style: TextStyle(color: Colors.grey.shade500)));
          }
          final latestPensionRound = pensionRounds.first.round;
          final displayRound = _selectedPensionRound ?? latestPensionRound;

          return FutureBuilder<List<LotteryStore>>(
            future: _loadPensionWinningStoresForRound(displayRound),
            builder: (context, storeSnapshot) {
              final pensionStores = storeSnapshot.data ?? [];
              if (pensionStores.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('당첨지점을 검색하는 중입니다.', style: TextStyle(color: Colors.grey.shade500)),
                  ),
                );
              }
              final firstPlace = _sortByRegion(pensionStores.where((s) => s.prizeTier == 'first').toList());
              final secondPlace = _sortByRegion(pensionStores.where((s) => s.prizeTier == 'second').toList());

              return Column(
                children: [
                  _buildPrizeSection(firstPlace, isFirst: true, accentColor: Colors.orange),
                  const SizedBox(height: 16),
                  _buildPrizeSection(secondPlace, isFirst: false, accentColor: Colors.grey),
                ],
              );
            },
          );
        },
      );
    }
  }

  Widget _buildPrizeSection(List<LotteryStore> stores, {required bool isFirst, required MaterialColor accentColor}) {
    if (stores.isEmpty) {
      return Text(
        isFirst ? '1등 당첨지점이 없습니다' : '2등 당첨지점이 없습니다',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isFirst ? accentColor.shade100 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFirst ? accentColor.shade400 : const Color(0xFFC0C0C0),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isFirst ? '🎉 1등 (${stores.length}개)' : '🥈 2등 (${stores.length}개)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isFirst ? accentColor.shade800 : Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),
          ...stores.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _buildWinningStoreCard(entry.value, isSecondPlace: !isFirst, index: entry.key + 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWinningStoreCard(
    LotteryStore store, {
    required bool isSecondPlace,
    int index = 0,
  }) {
    final isExpanded = _expandedStoreKeys.contains(_storeKey(store));
    final borderColor = isSecondPlace
        ? const Color(0xFF8E8E93)
        : Colors.amber.shade300;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _toggleStoreCard(store),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (index > 0) ...[
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSecondPlace ? Colors.grey.shade400 : Colors.amber.shade600,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    store.storeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (!isSecondPlace && (store.purchaseMethod ?? store.method ?? '').isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.blue.shade300, width: 1),
                    ),
                    child: Text(
                      store.purchaseMethod ?? store.method ?? '',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox.shrink(),
                if (store.winningAmount != null)
                  Text(
                    '상금: ${store.winningAmount}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 12),
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
                        onPressed: () =>
                            _openMap(mapType: 'naver', store: store),
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('네이버지도'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _openMap(mapType: 'kakao', store: store),
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

  Widget _buildBall(int value, Color color) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        '$value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _ballColorForNumber(int number) {
    if (number >= 1 && number <= 10) return const Color(0xFFFBC02D); // 노랑
    if (number >= 11 && number <= 20) return const Color(0xFF1976D2); // 파랑
    if (number >= 21 && number <= 30) return const Color(0xFFD32F2F); // 빨강
    if (number >= 31 && number <= 40) return const Color(0xFF616161); // 회색
    return const Color(0xFF2E7D32); // 초록 (41~45)
  }

  // 연금복권 번호별 색상 (자릿수 기반 - 실제 연금복권 색상)
  static const List<Color> _pensionBallColors = [
    Color(0xFFFFA726), // 십만 - 주황
    Color(0xFFFFA726), // 만 - 주황
    Color(0xFFFBC02D), // 천 - 노랑
    Color(0xFF42A5F5), // 백 - 파랑
    Color(0xFFAB47BC), // 십 - 보라
    Color(0xFF9E9E9E), // 일 - 회색
  ];

  Widget _buildPensionGroupBall(int group) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade400, width: 1.5),
      ),
      child: Text(
        '$group',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
      ),
    );
  }

  Widget _buildPensionBall(String digit, int position) {
    final color = position < _pensionBallColors.length
        ? _pensionBallColors[position]
        : Colors.grey;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2.5),
      ),
      child: Text(
        digit,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color),
      ),
    );
  }

  void _showPensionRoundPickerDialog(
    BuildContext context,
    List<PensionWinningNumber> allRounds,
    int latestRoundNum,
  ) {
    final ScrollController scrollController = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final idx = allRounds.indexWhere((r) => r.round == _selectedPensionRound);
      if (idx != -1) scrollController.jumpTo(idx * 50.0);
    });

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 300,
          height: 400,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('회차 선택', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: allRounds.length,
                  itemBuilder: (context, index) {
                    final round = allRounds[index];
                    final isSelected = round.round == _selectedPensionRound;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedPensionRound = round.round);
                        Navigator.of(dialogContext).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.orange.shade100 : Colors.grey.shade50,
                          border: Border.all(
                            color: isSelected ? Colors.orange.shade400 : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${round.round}회',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.orange.shade800 : Colors.black87,
                              ),
                            ),
                            Text(
                              round.drawDate,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRoundPickerDialog(
    BuildContext context,
    List<LottoWinningNumber> allRounds,
    int latestRoundNum,
  ) {
    final ScrollController scrollController = ScrollController();

    // 초기 스크롤 위치 설정 (선택된 회차가 중앙에 오도록)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selectedRoundIndex = allRounds.indexWhere((r) => r.round == _selectedLottoRound);
      if (selectedRoundIndex != -1) {
        scrollController.jumpTo(selectedRoundIndex * 50.0);
      }
    });

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 300,
          height: 400,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                '회차 선택',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: allRounds.length,
                  itemBuilder: (context, index) {
                    final round = allRounds[index];
                    final isSelected = round.round == _selectedLottoRound;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedLottoRound = round.round;
                        });
                        Navigator.of(dialogContext).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.amber.shade100
                              : Colors.grey.shade50,
                          border: Border.all(
                            color: isSelected
                                ? Colors.amber.shade400
                                : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${round.round}회',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.amber.shade800
                                    : Colors.black87,
                              ),
                            ),
                            if (round.round == latestRoundNum)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade300,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '최신',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('닫기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoreCard(LotteryStore store) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              store.storeName,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              store.address,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '판매방식: ${store.method}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (store.winningAmount != null)
                  Text(
                    '상금: ${store.winningAmount}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedlottoTabContent extends StatelessWidget {
  const _SpeedlottoTabContent();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSpeedlottoSection(
            '스피또 2000',
            () => LocalDataService().getSpeedlotto2000Stores(),
          ),
          const SizedBox(height: 24),
          _buildSpeedlottoSection(
            '스피또 1000',
            () => LocalDataService().getSpeedlotto1000Stores(),
          ),
          const SizedBox(height: 24),
          _buildSpeedlottoSection(
            '스피또 500',
            () => LocalDataService().getSpeedlotto500Stores(),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedlottoSection(
    String title,
    Future<List<LotteryStore>> Function() getFuture,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<LotteryStore>>(
          future: getFuture(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('오류: ${snapshot.error}'));
            }

            final stores = snapshot.data ?? [];
            if (stores.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('데이터가 없습니다'),
                ),
              );
            }

            return Column(
              children: stores.map((store) => _buildStoreCard(store)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStoreCard(LotteryStore store) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              store.storeName,
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              store.address,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '판매방식: ${store.method}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (store.winningAmount != null)
                  Text(
                    '상금: ${store.winningAmount}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
