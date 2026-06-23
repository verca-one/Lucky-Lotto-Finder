import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdService {
  // Google AdMob 애플리케이션 ID
  static const String appId = 'ca-app-pub-8658921158210502~3234497602';

  // 배너 광고 단위 ID
  static const String bannerAdUnitId = 'ca-app-pub-8658921158210502/7117902298';

  // 보상형 광고 단위 ID (NearbySearchReward)
  static const String rewardedAdUnitId = 'ca-app-pub-8658921158210502/3178657282';

  static BannerAd? _bannerAd;
  static bool _isLoaded = false;
  static bool _adsRemoved = false;
  static RewardedAd? _rewardedAd;
  static bool _isRewardedLoaded = false;

  /// 광고 제거 상태 확인
  static bool get adsRemoved => _adsRemoved;

  /// SharedPreferences에서 광고제거 상태 로드
  static Future<void> loadAdsRemovedState() async {
    final prefs = await SharedPreferences.getInstance();
    _adsRemoved = prefs.getBool('ads_removed') ?? false;
  }

  /// 광고 제거 적용
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

  // 배너 광고 로드 - 화면 너비에 맞는 앵커 적응형 배너
  static Future<bool> loadBannerAd(BuildContext context) async {
    if (_adsRemoved) return false;
    final completer = Completer<bool>();

    final width = MediaQuery.of(context).size.width.truncate();
    final adSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (adSize == null) return false;

    _bannerAd = BannerAd(
      adUnitId: bannerAdUnitId,
      request: const AdRequest(),
      size: adSize,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _isLoaded = true;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
          _isLoaded = false;
          debugPrint('배너 광고 로드 실패: ${error.message}');
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    await _bannerAd?.load();

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => _isLoaded,
    );
  }

  // 배너 광고 반환
  static BannerAd? getBannerAd() => _isLoaded ? _bannerAd : null;

  // 로드 여부
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

  // 보상형 광고 표시. 완료 시 onRewarded 콜백 호출
  static Future<bool> showRewardedAd({required VoidCallback onRewarded}) async {
    if (!_isRewardedLoaded || _rewardedAd == null) return false;
    final ad = _rewardedAd!;
    _rewardedAd = null;
    _isRewardedLoaded = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) => ad.dispose(),
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        debugPrint('보상형 광고 표시 실패: ${error.message}');
      },
    );
    ad.show(onUserEarnedReward: (_, __) => onRewarded());
    return true;
  }

  static bool get isRewardedLoaded => _isRewardedLoaded;

  // 리소스 정리
  static void dispose() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isRewardedLoaded = false;
  }
}
