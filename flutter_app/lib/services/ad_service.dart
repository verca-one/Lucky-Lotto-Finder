import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdService {
  static const String appId = 'ca-app-pub-8658921158210502~3234497602';

  static String get bannerAdUnitId => kDebugMode
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-8658921158210502/7117902298';
  static String get rewardedAdUnitId => kDebugMode
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-8658921158210502/3178657282';

  static BannerAd? _bannerAd;
  static bool _isLoaded = false;
  static bool _adsRemoved = false;
  static RewardedAd? _rewardedAd;
  static bool _isRewardedLoaded = false;

  static bool get adsRemoved => _adsRemoved;

  static Future<void> loadAdsRemovedState() async {
    final prefs = await SharedPreferences.getInstance();
    _adsRemoved = prefs.getBool('ads_removed') ?? false;
  }

  static Future<void> setAdsRemoved(bool removed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ads_removed', removed);
    _adsRemoved = removed;
    if (removed) {
      _bannerAd?.dispose();
      _bannerAd = null;
      _isLoaded = false;
    }
  }

  // 배너 광고 로드 (실패 시 1회 재시도)
  static Future<bool> loadBannerAd() async {
    if (_adsRemoved) return false;
    if (_isLoaded && _bannerAd != null) return true;

    for (int attempt = 0; attempt < 2; attempt++) {
      final result = await _tryLoadBanner();
      if (result) return true;
      if (attempt == 0) await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  static Future<bool> _tryLoadBanner() async {
    final completer = Completer<bool>();

    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;

    _bannerAd = BannerAd(
      adUnitId: bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _isLoaded = true;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
          _isLoaded = false;
          debugPrint('배너 광고 로드 실패: ${error.message} (code: ${error.code})');
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    await _bannerAd?.load();

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => _isLoaded,
    );
  }

  static BannerAd? getBannerAd() => _isLoaded ? _bannerAd : null;
  static bool get isLoaded => _isLoaded;

  // 보상형 광고 로드
  static Future<bool> loadRewardedAd() async {
    final completer = Completer<bool>();
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedLoaded = true;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          _isRewardedLoaded = false;
          debugPrint('보상형 광고 로드 실패: ${error.message}');
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => false,
    );
  }

  static Future<bool> showRewardedAd({required VoidCallback onRewarded}) async {
    if (!_isRewardedLoaded || _rewardedAd == null) return false;
    final ad = _rewardedAd!;
    _rewardedAd = null;
    _isRewardedLoaded = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) => ad.dispose(),
      onAdFailedToShowFullScreenContent: (ad, error) => ad.dispose(),
    );
    ad.show(onUserEarnedReward: (_, __) => onRewarded());
    return true;
  }

  static bool get isRewardedLoaded => _isRewardedLoaded;

  static void dispose() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isRewardedLoaded = false;
  }
}
