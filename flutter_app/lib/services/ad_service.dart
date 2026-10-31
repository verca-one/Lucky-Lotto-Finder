import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdService {
  // ── Ad IDs ──────────────────────────────────────────────────
  static String get _bannerUnitId => kDebugMode
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-8658921182810502/7117902298';

  static String get _settingsBannerUnitId => kDebugMode
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-8658921182810502/6773924343';

  static String get _interstitialUnitId => kDebugMode
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-8658921182810502/3728545913';

  // ── Banner (홈 하단) ─────────────────────────────────────────
  static BannerAd? _bannerAd;
  static bool _bannerLoaded = false;

  // ── Settings Banner (설정 다이얼로그) ──────────────────────────
  static BannerAd? _settingsBannerAd;
  static bool _settingsBannerLoaded = false;
  static BannerAd? get settingsBannerAd =>
      _settingsBannerLoaded ? _settingsBannerAd : null;

  // ── Interstitial ─────────────────────────────────────────────
  static InterstitialAd? _interstitialAd;
  static bool _interstitialLoaded = false;

  // ── Policy counters ──────────────────────────────────────────
  static int _menuCount = 0;
  static DateTime? _lastShownAt;

  // ── State ────────────────────────────────────────────────────
  static bool _adsRemoved = false;
  static bool get adsRemoved => _adsRemoved;
  static bool get isBannerLoaded => _bannerLoaded;
  static BannerAd? get bannerAd => _bannerLoaded ? _bannerAd : null;

  // 앱 최초 홈 데이터 로딩 완료 전에는 전면광고 표시 안 함
  static bool _initialLoadComplete = false;
  static void markInitialLoadComplete() => _initialLoadComplete = true;

  // ════════════════════════════════════════════════════════════
  // Init / State
  // ════════════════════════════════════════════════════════════
  static Future<void> loadAdsRemovedState() async {
    final prefs = await SharedPreferences.getInstance();
    // 관리자 폰은 배너도 받지 않음 — 개발자가 자기 앱 실광고를 반복 노출하면 무효 트래픽으로 광고 게재가 제한됨
    _adsRemoved = (prefs.getBool('ads_removed') ?? false) || (prefs.getBool('isAdmin') ?? false);
  }

  static Future<void> setAdsRemoved(bool removed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ads_removed', removed);
    _adsRemoved = removed;
    if (removed) {
      _bannerAd?.dispose();
      _bannerAd = null;
      _bannerLoaded = false;
      _settingsBannerAd?.dispose();
      _settingsBannerAd = null;
      _settingsBannerLoaded = false;
      _interstitialAd?.dispose();
      _interstitialAd = null;
      _interstitialLoaded = false;
    }
  }

  // ════════════════════════════════════════════════════════════
  // 전면광고 제외 대상 확인 (우선순위 순서대로)
  // ════════════════════════════════════════════════════════════
  static Future<bool> _isInterstitialExempt() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. 관리자 계정
    if (prefs.getBool('isAdmin') ?? false) return true;

    // 2. 관리자 모드 (isAdmin과 동일 키 사용)
    //    별도 플래그가 생기면 여기에 추가

    // 3. 영구 광고 제거 쿠폰
    if (prefs.getBool('ads_removed') ?? false) return true;

    // 3-b. 기간제 광고 제거 쿠폰 (ad_free_until)
    final adFreeUntilStr = prefs.getString('ad_free_until');
    if (adFreeUntilStr != null) {
      final until = DateTime.tryParse(adFreeUntilStr);
      if (until != null && DateTime.now().isBefore(until)) return true;
    }

    return false;
  }

  // ════════════════════════════════════════════════════════════
  // Banner
  // ════════════════════════════════════════════════════════════
  static Future<bool> loadBannerAd() async {
    if (_adsRemoved) return false;
    if (_bannerLoaded && _bannerAd != null) return true;

    for (int attempt = 0; attempt < 2; attempt++) {
      final ok = await _tryLoadBanner();
      if (ok) return true;
      if (attempt == 0) await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  static Future<bool> _tryLoadBanner() async {
    final completer = Completer<bool>();
    _bannerAd?.dispose();
    _bannerAd = null;
    _bannerLoaded = false;

    _bannerAd = BannerAd(
      adUnitId: _bannerUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _bannerLoaded = true;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
          _bannerLoaded = false;
          debugPrint('[Ad] Banner failed: ${error.code} ${error.message}');
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    await _bannerAd?.load();
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => _bannerLoaded,
    );
  }

  // ════════════════════════════════════════════════════════════
  // Settings Banner
  // ════════════════════════════════════════════════════════════

  /// 설정 다이얼로그용 배너. [onLoaded]는 로드 성공 시 setState를 트리거하는 콜백.
  static Future<void> loadSettingsBannerAd(VoidCallback onLoaded) async {
    if (_adsRemoved) return;
    _settingsBannerAd?.dispose();
    _settingsBannerAd = null;
    _settingsBannerLoaded = false;

    _settingsBannerAd = BannerAd(
      adUnitId: _settingsBannerUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _settingsBannerLoaded = true;
          onLoaded();
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _settingsBannerAd = null;
          _settingsBannerLoaded = false;
          debugPrint('[Ad] SettingsBanner failed: ${error.code} ${error.message}');
        },
      ),
    );
    await _settingsBannerAd?.load();
  }

  static void disposeSettingsBanner() {
    _settingsBannerAd?.dispose();
    _settingsBannerAd = null;
    _settingsBannerLoaded = false;
  }

  // ════════════════════════════════════════════════════════════
  // Interstitial – preload
  // ════════════════════════════════════════════════════════════
  static void preloadInterstitial() {
    if (_adsRemoved) return;
    if (_interstitialLoaded) return;
    _loadInterstitial();
  }

  static void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: _interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialLoaded = true;
          debugPrint('[Ad] Interstitial loaded');
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          _interstitialLoaded = false;
          debugPrint('[Ad] Interstitial failed: ${error.code} ${error.message}');
          // 실패 시 광고 없이 정상 동작 (재시도 없음 — 다음 onMenuUsed 호출 때 preload)
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // Interstitial – show policy
  // ════════════════════════════════════════════════════════════

  /// 메뉴 이동 시 호출. 정책 조건 + 제외 대상 확인 후 전면광고 표시.
  /// 광고 미로드·제외 대상이면 [onAfter] 즉시 실행 (기능이 막히지 않음).
  static Future<void> onMenuUsed(BuildContext context,
      {required VoidCallback onAfter}) async {

    // ── 제외 대상 확인 (우선순위 순) ──────────────────────────
    // 1. 관리자 계정 / 2. 관리자 모드 / 3. 광고 제거 쿠폰
    if (await _isInterstitialExempt()) {
      onAfter();
      return;
    }

    // ── 초기 홈 로딩 완료 전에는 전면광고 미표시 ──────────────
    if (!_initialLoadComplete) {
      onAfter();
      return;
    }

    // ── 메뉴 카운트 증가 ──────────────────────────────────────
    _menuCount++;

    // ── 4~5: 정책 조건 확인 ───────────────────────────────────
    if (!_shouldShow) {
      onAfter();
      return;
    }

    // ── 6: 광고 표시 ──────────────────────────────────────────
    if (!_interstitialLoaded || _interstitialAd == null) {
      // 광고 미로드 → 기능 막지 않고 즉시 이동 후 재로드
      onAfter();
      preloadInterstitial();
      return;
    }

    final ad = _interstitialAd!;
    _interstitialAd = null;
    _interstitialLoaded = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _menuCount = 0;
        _lastShownAt = DateTime.now();
        onAfter();
        preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        debugPrint('[Ad] Interstitial show failed: $error');
        onAfter();
        preloadInterstitial();
      },
    );

    await ad.show();
  }

  /// 전면광고 표시 조건
  static bool get _shouldShow {
    if (_lastShownAt == null) {
      // 첫 전면광고: 10회 이용 후
      return _menuCount >= 10;
    }
    // 이후: 8회 이상 AND 5분 경과
    return _menuCount >= 8 &&
        DateTime.now().difference(_lastShownAt!).inMinutes >= 5;
  }

  // ════════════════════════════════════════════════════════════
  // Dispose
  // ════════════════════════════════════════════════════════════
  static void dispose() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _bannerLoaded = false;
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _interstitialLoaded = false;
  }
}
