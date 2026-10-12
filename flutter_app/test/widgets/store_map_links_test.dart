// 판매점 지도 링크 (StoreMapLinks.of) 단위 테스트 — 실제 지도 앱·웹은 열지 않는다
import 'package:flutter_app/services/store_map_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const withCoord = StoreMapTarget(storeId: 's1', name: '행운복권', address: '서울 노원구 상계동 1-2', lat: 37.65, lng: 127.06);
  const noCoord = StoreMapTarget(storeId: 's2', name: '행운 복권방', address: '서울 노원구 상계동 1-2');

  group('좌표 있음', () {
    test('네이버 — 앱은 좌표 place, 웹은 이름+주소 검색', () {
      final l = StoreMapLinks.of(StoreMapService.naver, withCoord);
      expect(l.app.scheme, 'nmap');
      expect(l.app.host, 'place');
      expect(l.app.queryParameters['lat'], '37.65');
      expect(l.app.queryParameters['lng'], '127.06');
      expect(l.app.queryParameters['name'], '행운복권');
      expect(l.app.queryParameters['appname'], kAppPackage);
      expect(l.web.host, 'map.naver.com');
      expect(l.web.pathSegments.last, '행운복권 서울 노원구 상계동 1-2');
    });

    test('카카오 — 앱은 look 좌표, 웹은 이름 마커 + 좌표', () {
      final l = StoreMapLinks.of(StoreMapService.kakao, withCoord);
      expect(l.app.toString(), 'kakaomap://look?p=37.65,127.06');
      expect(l.web.host, 'map.kakao.com');
      expect(l.web.path, startsWith('/link/map/'));
      expect(l.web.pathSegments.last, '행운복권,37.65,127.06');
    });
  });

  group('좌표 없음', () {
    test('네이버 — 앱·웹 모두 이름+주소 검색', () {
      final l = StoreMapLinks.of(StoreMapService.naver, noCoord);
      expect(l.app.scheme, 'nmap');
      expect(l.app.host, 'search');
      expect(l.app.queryParameters['query'], '행운 복권방 서울 노원구 상계동 1-2');
      expect(l.web.pathSegments.last, '행운 복권방 서울 노원구 상계동 1-2');
    });

    test('카카오 — 앱·웹 모두 검색', () {
      final l = StoreMapLinks.of(StoreMapService.kakao, noCoord);
      expect(l.app.scheme, 'kakaomap');
      expect(l.app.host, 'search');
      expect(l.app.queryParameters['q'], '행운 복권방 서울 노원구 상계동 1-2');
      expect(l.web.path, startsWith('/link/search/'));
      expect(l.web.pathSegments.last, '행운 복권방 서울 노원구 상계동 1-2');
    });
  });

  test('한글·공백은 퍼센트 인코딩 (원문 공백·한글이 URL 에 그대로 남지 않음)', () {
    for (final s in StoreMapService.values) {
      final l = StoreMapLinks.of(s, noCoord);
      for (final u in [l.app.toString(), l.web.toString()]) {
        expect(u, isNot(contains(' ')), reason: u);
        expect(RegExp(r'[가-힣]').hasMatch(u), isFalse, reason: u);
      }
    }
    final web = StoreMapLinks.of(StoreMapService.naver, noCoord).web.toString();
    expect(web, contains('%ED%96%89')); // '행'
    expect(web, contains('%20'));
  });

  test('이름의 쉼표는 인코딩되어 카카오 좌표와 섞이지 않음', () {
    const t = StoreMapTarget(storeId: 's3', name: '복권,명당', address: '부산', lat: 35.1, lng: 129.0);
    final web = StoreMapLinks.of(StoreMapService.kakao, t).web.toString();
    expect(web, contains('%2C'));
    expect(web, endsWith(',35.1,129.0'));
  });

  test('국내 범위를 벗어난 좌표는 없는 것으로 보고 검색 링크', () {
    const cases = [
      StoreMapTarget(storeId: 'a', name: 'A', address: '서울', lat: 0, lng: 0),
      StoreMapTarget(storeId: 'b', name: 'B', address: '서울', lat: 40.1, lng: 127.0),
      StoreMapTarget(storeId: 'c', name: 'C', address: '서울', lat: 37.5, lng: 133.0),
      StoreMapTarget(storeId: 'd', name: 'D', address: '서울', lat: 37.5),
    ];
    for (final t in cases) {
      expect(t.hasCoord, isFalse, reason: t.storeId);
      expect(StoreMapLinks.of(StoreMapService.naver, t).app.host, 'search', reason: t.storeId);
      expect(StoreMapLinks.of(StoreMapService.kakao, t).app.host, 'search', reason: t.storeId);
    }
  });

  test('판매점마다 자기 이름·주소로만 링크를 만든다', () {
    const other = StoreMapTarget(storeId: 's9', name: '다른점', address: '대구 중구');
    final a = StoreMapLinks.of(StoreMapService.naver, noCoord).web.toString();
    final b = StoreMapLinks.of(StoreMapService.naver, other).web.toString();
    expect(a, isNot(b));
    expect(Uri.parse(b).pathSegments.last, '다른점 대구 중구');
  });
}
