import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  // Google AdMob 애플리케이션 ID
  static const String appId = 'ca-app-pub-8658921158210502~3234497602';

  // 배너 광고 단위 ID
  static const String bannerAdUnitId = 'ca-app-pub-8658921158210502/7117902298';

  static BannerAd? _bannerAd;
  static bool _isLoaded = false;

  // 배너 광고 로드 (Completer로 로드 완료까지 대기)
  static Future<bool> loadBannerAd() async {
    final completer = Completer<bool>();

    _bannerAd = BannerAd(
      adUnitId: bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          print('배너 광고 로드됨');
          _isLoaded = true;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
          _isLoaded = false;
          print('배너 광고 로드 실패: ${error.message}');
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    await _bannerAd?.load();

    // 5초 타임아웃
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => _isLoaded,
    );
  }

  // 배너 광고 반환
  static BannerAd? getBannerAd() => _isLoaded ? _bannerAd : null;

  // 로드 여부
  static bool get isLoaded => _isLoaded;

  // 리소스 정리
  static void dispose() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;
  }
}
