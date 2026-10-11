// 경로 기반 추천 — 외부 내비 앱 딥링크 (관리자 전용 연구 기능)
//
// ── 스킴 출처 (공식 문서 확인 결과) ──────────────────────────────────────
// [네이버지도] nmap://route/car  — 공식 (NAVER Cloud Platform Maps URL Scheme)
//   https://guide.ncloud-docs.com/docs/maps-url-scheme
//   https://guide.ncloud-docs.com/docs/en/application-maps-url-scheme-vpc
//   파라미터: slat, slng, sname(선택) / dlat, dlng(필수), dname / v1lat, v1lng, v1name
//   … v5 까지 경유지 최대 5개 (공식 표에 정의) / appname(필수, Android applicationId).
//   iOS: Info.plist LSApplicationQueriesSchemes 에 'nmap' 등록 필요.
//
// [카카오맵] kakaomap://route — 공식 (KakaoMapsSDK v2 iOS 문서 "URL Scheme")
//   https://apis.map.kakao.com/ios_v2/docs/getting-started/urlscheme/
//   파라미터: sp=lat,lng / ep=lat,lng / by=car|publictransit|foot|bicycle (소문자)
//   경유지: vp, vp2 … vp5 (최대 5개, publictransit 미지원). 앱 6.0.0+.
//   미설치 시 모바일 웹 폴백: http://m.map.kakao.com/scheme/route?...
//   ※ 과제 명세는 "경유지 미지원"으로 가정했으나 공식 문서에 vp 가 있어 경유지를 지원하고,
//     만약을 위해 "판매점만 목적지" 대안 버튼도 함께 제공한다.
//
// [TMAP] tmap://route — 공식 공개 문서 미확인 (커뮤니티/서드파티 자료만 존재)
//   목적지 rGoName / rGoX(경도) / rGoY(위도) 는 다수 사례에서 동작 보고.
//   출발지 rStName/rStX/rStY, 경유지 rV1Name/rV1X/rV1Y 는 서드파티 래퍼
//   (react-native-invoke-tmap README) 에만 등장 → 동작 불확실.
//   → 기본은 "판매점을 목적지로" 호출, 경유지 포함 호출은 '미확인' 표시 옵션으로 제공.
//   SK Open API 포럼: https://openapi.sk.com/qnaCommunity/214 (답변 없음)
//
// Android 11+ 패키지 가시성: AndroidManifest.xml <queries> 에 nmap / kakaomap / tmap 스킴 추가.
//
// ── 통행료 회피(무료도로) 파라미터 조사 (2026-10-11) ────────────────────────
// [네이버지도] 공식 "경로 탐색 공통 파라미터" 표: slat/slng/sname, dlat/dlng/dname,
//   v1~v5 lat/lng/name 뿐 → 통행료/경로 옵션 파라미터 없음.
//   https://guide.ncloud-docs.com/docs/application-maps-url-scheme-vpc
// [카카오맵] 공식 문서 파라미터: sp, ep, vp~vp5, by 뿐 → 통행료 옵션 없음.
//   https://apis.map.kakao.com/ios_v2/docs/getting-started/urlscheme/
// [TMAP] 앱 URL 스킴 공식 공개 문서 자체를 찾지 못함 → 통행료 옵션 지원 가정 금지.
//   (TMAP REST 경로 API 의 searchOption 은 앱 키 필요한 별도 서버 API 이며 앱 딥링크와 무관)
// → 세 앱 모두 딥링크로 무료도로를 강제할 수 없다. 실행 전 [kNavFreeRoadNotice] 안내 필수.

import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// 외부 내비 실행 전 안내 (딥링크 통행료 옵션 공식 미지원)
const String kNavFreeRoadNotice =
    "내비 앱에서 '무료도로' 옵션을 직접 선택하세요.\n"
    '네이버지도·카카오맵·TMAP 딥링크에는 통행료 회피 파라미터가 공식 문서에 없어, '
    '앱이 유료도로 경로를 안내할 수 있습니다.';

enum NavApp { naver, tmap, kakao }

extension NavAppInfo on NavApp {
  String get label => switch (this) {
        NavApp.naver => '네이버지도',
        NavApp.tmap => 'TMAP',
        NavApp.kakao => '카카오맵',
      };

  /// 경유지 공식 지원 여부
  bool get waypointOfficial => switch (this) {
        NavApp.naver => true,
        NavApp.kakao => true,
        NavApp.tmap => false,
      };

  String get waypointNote => switch (this) {
        NavApp.naver => '경유지 공식 지원 (v1lat/v1lng/v1name)',
        NavApp.kakao => '경유지 공식 지원 (vp, 앱 6.0.0+)',
        NavApp.tmap => '경유지 파라미터 공식 문서 미확인 → 판매점을 목적지로 권장',
      };

  /// 딥링크 통행료 회피 파라미터 공식 지원 여부 — 조사 결과 세 앱 모두 false
  bool get tollAvoidParamOfficial => false;

  String get tollNote => switch (this) {
        NavApp.naver => '통행료 옵션 파라미터 공식 문서에 없음 → 앱에서 무료도로 직접 선택',
        NavApp.kakao => '통행료 옵션 파라미터 공식 문서에 없음 → 앱에서 무료도로 직접 선택',
        NavApp.tmap => 'URL 스킴 공식 문서 미확인 → 앱에서 무료도로 직접 선택',
      };

  String get scheme => switch (this) {
        NavApp.naver => 'nmap',
        NavApp.tmap => 'tmap',
        NavApp.kakao => 'kakaomap',
      };

  /// 미설치 시 스토어 링크 (Android)
  Uri get storeUri => switch (this) {
        NavApp.naver => Uri.parse('market://details?id=com.nhn.android.nmap'),
        NavApp.tmap => Uri.parse('market://details?id=com.skt.tmap.ku'),
        NavApp.kakao => Uri.parse('market://details?id=net.daum.android.map'),
      };
}

class NavPoint {
  final LatLng point;
  final String name;
  const NavPoint(this.point, this.name);
}

class NavLaunchResult {
  final bool launched;
  final String message;
  final Uri uri;
  const NavLaunchResult(this.launched, this.message, this.uri);
}

class ExternalNav {
  ExternalNav._();

  /// 네이버지도 appname = Android applicationId
  static const String appName = 'com.luckylotto.finder';

  static String _f(double v) => v.toStringAsFixed(6);

  // ── URI 빌더 (순수 함수, 테스트 가능) ───────────────────────────────────

  /// [origin] 생략 시 출발지 파라미터 없이 호출 (앱이 현재 위치를 출발지로 사용).
  static Uri naverRouteUri({
    NavPoint? origin,
    NavPoint? waypoint,
    required NavPoint destination,
  }) {
    final q = <String, String>{
      if (origin != null) 'slat': _f(origin.point.latitude),
      if (origin != null) 'slng': _f(origin.point.longitude),
      if (origin != null) 'sname': origin.name,
      'dlat': _f(destination.point.latitude),
      'dlng': _f(destination.point.longitude),
      'dname': destination.name,
      if (waypoint != null) 'v1lat': _f(waypoint.point.latitude),
      if (waypoint != null) 'v1lng': _f(waypoint.point.longitude),
      if (waypoint != null) 'v1name': waypoint.name,
      'appname': appName,
    };
    return Uri(scheme: 'nmap', host: 'route', path: '/car', queryParameters: q);
  }

  /// 카카오맵: sp/ep/vp 는 "lat,lng" 문자열. by 는 소문자 car (공식 문서).
  static Uri kakaoRouteUri({
    NavPoint? origin,
    NavPoint? waypoint,
    required NavPoint destination,
  }) {
    final q = <String, String>{
      if (origin != null)
        'sp': '${_f(origin.point.latitude)},${_f(origin.point.longitude)}',
      'ep': '${_f(destination.point.latitude)},${_f(destination.point.longitude)}',
      'by': 'car',
      if (waypoint != null)
        'vp': '${_f(waypoint.point.latitude)},${_f(waypoint.point.longitude)}',
    };
    return Uri(scheme: 'kakaomap', host: 'route', queryParameters: q);
  }

  /// 카카오맵 미설치 시 모바일 웹 폴백 (공식 문서의 동등 스킴)
  static Uri kakaoWebRouteUri({
    NavPoint? origin,
    NavPoint? waypoint,
    required NavPoint destination,
  }) {
    final app = kakaoRouteUri(
        origin: origin, waypoint: waypoint, destination: destination);
    return Uri.http('m.map.kakao.com', '/scheme/route', app.queryParameters);
  }

  /// TMAP: rGoX = 경도(lng), rGoY = 위도(lat). 경유지/출발지 파라미터는 비공식(미확인).
  static Uri tmapRouteUri({
    NavPoint? origin,
    NavPoint? waypoint,
    required NavPoint destination,
    bool includeUnofficialParams = false,
  }) {
    final q = <String, String>{
      'rGoName': destination.name,
      'rGoX': _f(destination.point.longitude),
      'rGoY': _f(destination.point.latitude),
      if (includeUnofficialParams && origin != null) 'rStName': origin.name,
      if (includeUnofficialParams && origin != null)
        'rStX': _f(origin.point.longitude),
      if (includeUnofficialParams && origin != null)
        'rStY': _f(origin.point.latitude),
      if (includeUnofficialParams && waypoint != null) 'rV1Name': waypoint.name,
      if (includeUnofficialParams && waypoint != null)
        'rV1X': _f(waypoint.point.longitude),
      if (includeUnofficialParams && waypoint != null)
        'rV1Y': _f(waypoint.point.latitude),
    };
    return Uri(scheme: 'tmap', host: 'route', queryParameters: q);
  }

  // ── 설치 확인 · 실행 ─────────────────────────────────────────────────────

  static Future<bool> isInstalled(NavApp app) async {
    try {
      final probe = switch (app) {
        NavApp.naver => Uri.parse('nmap://route/car?dlat=37.5&dlng=127.0&appname=$appName'),
        NavApp.tmap => Uri.parse('tmap://route?rGoName=a&rGoX=127.0&rGoY=37.5'),
        NavApp.kakao => Uri.parse('kakaomap://route?sp=37.5,127.0&ep=37.5,127.0&by=car'),
      };
      return await canLaunchUrl(probe);
    } catch (_) {
      return false;
    }
  }

  /// [waypoint] 가 null 이면 S→D (또는 판매점을 목적지로 하는 호출에 사용).
  /// TMAP 은 [tmapUnofficialWaypoint] 가 true 일 때만 경유지/출발지 파라미터를 붙인다.
  static Future<NavLaunchResult> launchRoute({
    required NavApp app,
    NavPoint? origin,
    NavPoint? waypoint,
    required NavPoint destination,
    bool tmapUnofficialWaypoint = false,
  }) async {
    final Uri uri;
    switch (app) {
      case NavApp.naver:
        uri = naverRouteUri(
            origin: origin, waypoint: waypoint, destination: destination);
        break;
      case NavApp.kakao:
        uri = kakaoRouteUri(
            origin: origin, waypoint: waypoint, destination: destination);
        break;
      case NavApp.tmap:
        uri = tmapRouteUri(
          origin: origin,
          waypoint: waypoint,
          destination: destination,
          includeUnofficialParams: tmapUnofficialWaypoint,
        );
        break;
    }
    try {
      if (await canLaunchUrl(uri)) {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        return NavLaunchResult(ok, ok ? '${app.label} 실행' : '${app.label} 실행 실패', uri);
      }
      // 카카오맵은 공식 웹 폴백 존재
      if (app == NavApp.kakao) {
        final web = kakaoWebRouteUri(
            origin: origin, waypoint: waypoint, destination: destination);
        final ok = await launchUrl(web, mode: LaunchMode.externalApplication);
        return NavLaunchResult(
            ok, ok ? '카카오맵 앱 미설치 → 모바일 웹으로 실행' : '카카오맵 실행 실패', web);
      }
      return NavLaunchResult(false,
          '${app.label} 앱이 설치되어 있지 않거나 스킴 조회가 차단됨 (AndroidManifest <queries> 확인)', uri);
    } catch (e) {
      return NavLaunchResult(false, '${app.label} 실행 오류: $e', uri);
    }
  }

  static Future<bool> openStore(NavApp app) async {
    try {
      return await launchUrl(app.storeUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
