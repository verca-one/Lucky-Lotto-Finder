import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  // Google AdMob 애플리케이션 ID
  static const String appId = 'ca-app-pub-8658921158210502~3234497602';

  // 배너 광고 단위 ID
  static const String bannerAdUnitId = 'ca-app-pub-8658921158210502/7117902298';

  static BannerAd? _bannerAd;

  // 배너 광고 로드
  static Future<void> loadBannerAd() async {
    _bannerAd = BannerAd(
      adUnitId: bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) => print('배너 광고 로드됨'),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          print('배너 광고 로드 실패: ${error.message}');
        },
      ),
    );
    await _bannerAd?.load();
  }

  // 배너 광고 반환
  static BannerAd? getBannerAd() => _bannerAd;

  // 리소스 정리
  static void dispose() {
    _bannerAd?.dispose();
  }
}
