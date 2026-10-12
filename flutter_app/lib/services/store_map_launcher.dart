// 판매점 위치를 네이버 지도·카카오맵에서 보여 준다 (길찾기 아님).
//
// · 검증된 좌표(국내 범위)가 있으면 좌표로 해당 위치를 표시하고, 없으면 '판매점명 + 주소'로 지도 검색한다.
// · 설치된 지도 앱이 있으면 앱으로, 실행에 실패하면 웹 지도로 연다.
// · URL 은 판매점마다 그 판매점의 이름·주소·좌표로만 만든다 (다른 판매점과 섞이지 않음).
import 'package:url_launcher/url_launcher.dart';

const String kAppPackage = 'com.luckylotto.finder';

enum StoreMapService { naver, kakao }

class StoreMapTarget {
  final String storeId;
  final String name;
  final String address;
  final double? lat;
  final double? lng;
  const StoreMapTarget({required this.storeId, required this.name, required this.address, this.lat, this.lng});

  /// 국내 범위의 유효 좌표만 사용
  bool get hasCoord => lat != null && lng != null && lat! >= 33 && lat! <= 39 && lng! >= 124 && lng! <= 132;

  /// 좌표가 없을 때의 검색어: 판매점명 + 주소 (주소가 있으면 동명 판매점과 구분된다)
  String get query => [name.trim(), address.trim()].where((s) => s.isNotEmpty).join(' ');
}

/// 앱 링크(먼저 시도)와 웹 링크(대체) — 순수 함수 (단위 테스트 대상)
class StoreMapLinks {
  final Uri app;
  final Uri web;
  const StoreMapLinks(this.app, this.web);

  factory StoreMapLinks.of(StoreMapService s, StoreMapTarget t) {
    final q = Uri.encodeComponent(t.query);
    final name = Uri.encodeComponent(t.name.trim().isEmpty ? t.query : t.name.trim());
    switch (s) {
      case StoreMapService.naver:
        if (t.hasCoord) {
          return StoreMapLinks(
            Uri.parse('nmap://place?lat=${t.lat}&lng=${t.lng}&name=$name&appname=$kAppPackage'),
            Uri.parse('https://map.naver.com/p/search/$q'),
          );
        }
        return StoreMapLinks(
          Uri.parse('nmap://search?query=$q&appname=$kAppPackage'),
          Uri.parse('https://map.naver.com/p/search/$q'),
        );
      case StoreMapService.kakao:
        if (t.hasCoord) {
          return StoreMapLinks(
            Uri.parse('kakaomap://look?p=${t.lat},${t.lng}'),
            // 웹: 이름 마커와 함께 정확한 좌표 표시
            Uri.parse('https://map.kakao.com/link/map/$name,${t.lat},${t.lng}'),
          );
        }
        return StoreMapLinks(
          Uri.parse('kakaomap://search?q=$q'),
          Uri.parse('https://map.kakao.com/link/search/$q'),
        );
    }
  }
}

/// 지도 열기 결과: 'app' | 'web' | 'failed'
Future<String> openStoreOnMap(StoreMapService service, StoreMapTarget target) async {
  final links = StoreMapLinks.of(service, target);
  try {
    if (await launchUrl(links.app, mode: LaunchMode.externalApplication)) return 'app';
  } catch (_) {
    // 앱 미설치·실행 오류 → 웹으로
  }
  try {
    if (await launchUrl(links.web, mode: LaunchMode.externalApplication)) return 'web';
  } catch (_) {}
  return 'failed';
}
