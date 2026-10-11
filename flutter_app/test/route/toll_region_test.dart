// 무료도로(통행료 회피) · 지역/현 위치 추천 단위 테스트 (네트워크 미사용)
//
// 실행: flutter test test/route

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:flutter_app/services/route/external_nav.dart';
import 'package:flutter_app/services/route/region_research_repository.dart';
import 'package:flutter_app/services/route/route_store_recommender.dart';
import 'package:flutter_app/services/route/routing_service.dart';
import 'package:flutter_app/widgets/admin_region_store_widgets.dart';

/// 테스트용 polyline 인코더 (Google 알고리즘, precision 가변)
String encodePolyline(List<LatLng> pts, {int precision = 6}) {
  final factor = precision == 6 ? 1e6 : 1e5;
  final sb = StringBuffer();
  var pLat = 0, pLng = 0;
  void enc(int v) {
    var x = v < 0 ? ~(v << 1) : (v << 1);
    while (x >= 0x20) {
      sb.writeCharCode((0x20 | (x & 0x1f)) + 63);
      x >>= 5;
    }
    sb.writeCharCode(x + 63);
  }

  for (final p in pts) {
    final lat = (p.latitude * factor).round();
    final lng = (p.longitude * factor).round();
    enc(lat - pLat);
    enc(lng - pLng);
    pLat = lat;
    pLng = lng;
  }
  return sb.toString();
}

String valhallaJson({
  required double lengthKm,
  required double timeS,
  bool? hasToll,
  List<bool?> legTolls = const [false],
  List<List<LatLng>>? legShapes,
  int status = 0,
}) {
  final shapes = legShapes ??
      [
        for (var i = 0; i < legTolls.length; i++)
          [LatLng(37.0 + i * 0.1, 127.0), LatLng(37.1 + i * 0.1, 127.0)]
      ];
  return jsonEncode({
    'trip': {
      'status': status,
      'summary': {
        'length': lengthKm,
        'time': timeS,
        'has_toll': ?hasToll,
        'has_highway': false,
        'has_ferry': false,
      },
      'legs': [
        for (var i = 0; i < legTolls.length; i++)
          {
            'summary': {'has_toll': ?legTolls[i]},
            'shape': encodePolyline(shapes[i]),
            'maneuvers': const [],
          }
      ],
    }
  });
}

/// Valhalla 형태의 결과를 내는 모의 제공자. 경유지 키 → has_toll
class TollMockProvider implements RouteProvider {
  final Map<String, bool> tollFor;
  final Map<String, (double, double)> detours;
  final Set<String> failFor;
  final String provider;
  final bool baseHasToll;
  TollMockProvider({
    this.tollFor = const {},
    this.detours = const {},
    this.failFor = const {},
    this.provider = ValhallaRouteProvider.providerName,
    this.baseHasToll = false,
  });

  static String key(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';

  @override
  Future<RouteResult?> route(List<LatLng> w) async {
    if (w.length == 2) {
      return RouteResult(
        distanceM: 10000,
        durationS: 600,
        polyline: w,
        provider: provider,
        hasToll: baseHasToll,
        tollAvoidRequested: true,
        tollVerified: true,
        legHasToll: [baseHasToll],
      );
    }
    final k = key(w[1]);
    if (failFor.contains(k)) return null;
    final (dL, dT) = detours[k] ?? (1000.0, 120.0);
    final t = tollFor[k] ?? false;
    return RouteResult(
      distanceM: 10000 + dL,
      durationS: 600 + dT,
      polyline: w,
      provider: provider,
      hasToll: t,
      tollAvoidRequested: true,
      tollVerified: true,
      legHasToll: [false, t],
    );
  }
}

class _AlwaysNull implements RouteProvider {
  @override
  Future<RouteResult?> route(List<LatLng> waypoints) async => null;
}

RouteStoreCandidate cand(String code, double lat, double lng) => RouteStoreCandidate(
      code: code,
      name: '판매점$code',
      address: '',
      region: '',
      point: LatLng(lat, lng),
    );

void main() {
  // ═════════════════════════════════════════════════════════════════════
  group('polyline6 디코더', () {
    test('Google 공식 예제(precision 5) 디코딩', () {
      final pts = decodePolyline6('_p~iF~ps|U_ulLnnqC_mqNvxq`@', precision: 5);
      expect(pts.length, 3);
      expect(pts[0].latitude, closeTo(38.5, 1e-9));
      expect(pts[0].longitude, closeTo(-120.2, 1e-9));
      expect(pts[1].latitude, closeTo(40.7, 1e-9));
      expect(pts[1].longitude, closeTo(-120.95, 1e-9));
      expect(pts[2].latitude, closeTo(43.252, 1e-9));
      expect(pts[2].longitude, closeTo(-126.453, 1e-9));
    });

    test('precision 6 왕복 (천안시청 → 대전시청), 1e-6 정밀도', () {
      const src = [
        LatLng(36.815100, 127.113900),
        LatLng(36.600001, 127.250002),
        LatLng(36.350400, 127.384800),
      ];
      final dec = decodePolyline6(encodePolyline(src));
      expect(dec.length, 3);
      for (var i = 0; i < 3; i++) {
        expect(dec[i].latitude, closeTo(src[i].latitude, 1e-6));
        expect(dec[i].longitude, closeTo(src[i].longitude, 1e-6));
      }
    });

    test('precision 6 문자열을 precision 5 로 읽으면 10배 어긋남 (정밀도 구분 확인)', () {
      final s = encodePolyline(const [LatLng(36.8151, 127.1139)]);
      final wrong = decodePolyline6(s, precision: 5);
      expect(wrong.first.latitude, closeTo(368.151, 1e-6));
    });

    test('빈 문자열·손상 문자열은 예외 없이 처리', () {
      expect(decodePolyline6(''), isEmpty);
      final s = encodePolyline(const [LatLng(37.0, 127.0), LatLng(37.1, 127.1)]);
      expect(() => decodePolyline6(s.substring(0, s.length - 1)), returnsNormally);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('Valhalla 응답 파싱', () {
    test('summary/legs has_toll · km→m · 구간 경계 중복점 제거', () {
      final body = valhallaJson(
        lengthKm: 75.673,
        timeS: 4968,
        hasToll: false,
        legTolls: [false, false],
        legShapes: const [
          [LatLng(36.8151, 127.1139), LatLng(36.6, 127.25)],
          [LatLng(36.6, 127.25), LatLng(36.3504, 127.3848)],
        ],
      );
      final r = ValhallaRouteProvider.parseResponse(body, avoidTolls: true)!;
      expect(r.distanceM, closeTo(75673, 1e-6));
      expect(r.durationS, 4968);
      expect(r.provider, ValhallaRouteProvider.providerName);
      expect(r.hasToll, isFalse);
      expect(r.tollVerified, isTrue);
      expect(r.tollAvoidRequested, isTrue);
      expect(r.legHasToll, [false, false]);
      expect(r.polyline.length, 3); // 경계점 1개 제거
      expect(r.tollCheck, TollCheck.verifiedFree);
      expect(r.confirmedTollFree, isTrue);
    });

    test('has_toll=true 구간 → tollIncluded, 무료도로 확정 아님', () {
      final body = valhallaJson(
          lengthKm: 82.6, timeS: 4392, hasToll: true, legTolls: [false, true]);
      final r = ValhallaRouteProvider.parseResponse(body, avoidTolls: true)!;
      expect(r.hasToll, isTrue);
      expect(r.legHasToll, [false, true]);
      expect(r.tollCheck, TollCheck.tollIncluded);
      expect(r.confirmedTollFree, isFalse);
      expect(r.tollCheck.label(), '유료구간 포함(회피 불가)');
    });

    test('summary 와 legs 모두 has_toll 없음 → 검증 불가', () {
      final body = valhallaJson(lengthKm: 10, timeS: 600, legTolls: [null]);
      final r = ValhallaRouteProvider.parseResponse(body, avoidTolls: true)!;
      expect(r.tollVerified, isFalse);
      expect(r.hasToll, isNull);
      expect(r.tollCheck, TollCheck.unverifiable);
      expect(r.confirmedTollFree, isFalse);
    });

    test('summary 에 없고 legs 에만 있으면 legs 로 검증', () {
      final body = valhallaJson(lengthKm: 10, timeS: 600, legTolls: [false, true]);
      final r = ValhallaRouteProvider.parseResponse(body, avoidTolls: true)!;
      expect(r.tollVerified, isTrue);
      expect(r.hasToll, isTrue);
    });

    test('status != 0 · 오류 JSON · 비 JSON → null', () {
      expect(
          ValhallaRouteProvider.parseResponse(
              valhallaJson(lengthKm: 1, timeS: 1, hasToll: false, status: 442),
              avoidTolls: true),
          isNull);
      expect(
          ValhallaRouteProvider.parseResponse(
              '{"error_code":442,"error":"No path could be found"}',
              avoidTolls: true),
          isNull);
      expect(ValhallaRouteProvider.parseResponse('<html>', avoidTolls: true), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('Valhalla 요청 body', () {
    const s = LatLng(36.8151, 127.1139), d = LatLng(36.3504, 127.3848);

    test('avoidTolls=true → exclude_tolls:true, use_tolls 0, use_ferry 0', () {
      final b = ValhallaRouteProvider.buildRequestBody([s, d], avoidTolls: true);
      final auto = (b['costing_options'] as Map)['auto'] as Map;
      expect(auto['exclude_tolls'], isTrue);
      expect(auto['use_tolls'], 0.0);
      expect(auto['use_ferry'], 0.0);
      expect(b['costing'], 'auto');
      expect((b['locations'] as List).first, {'lat': 36.8151, 'lon': 127.1139});
      expect(jsonEncode(b), contains('"exclude_tolls":true'));
    });

    test('avoidTolls=false → use_tolls 1, exclude_tolls 없음', () {
      final b = ValhallaRouteProvider.buildRequestBody([s, d], avoidTolls: false);
      final auto = (b['costing_options'] as Map)['auto'] as Map;
      expect(auto['use_tolls'], 1.0);
      expect(auto.containsKey('exclude_tolls'), isFalse);
    });

    test('실제 전송 body(MockClient)에 exclude_tolls:true · User-Agent · 캐시 키에 옵션 포함',
        () async {
      final bodies = <String>[];
      final client = MockClient((req) async {
        bodies.add(req.body);
        expect(req.method, 'POST');
        expect(req.url.toString(), ValhallaRouteProvider.routeUrl);
        expect(req.headers['User-Agent'], ValhallaRouteProvider.userAgent);
        return http.Response.bytes(
            utf8.encode(valhallaJson(lengthKm: 75.7, timeS: 4968, hasToll: false)), 200,
            headers: {'content-type': 'application/json'});
      });
      final free = ValhallaRouteProvider(avoidTolls: true, client: client);
      final r1 = await free.route([s, d]);
      final r2 = await free.route([s, d]); // 캐시
      expect(r1, isNotNull);
      expect(identical(r1, r2), isTrue);
      expect(bodies.length, 1);
      expect(bodies.first, contains('"exclude_tolls":true'));
      expect(ValhallaRouteProvider.cacheKey([s, d], true),
          isNot(ValhallaRouteProvider.cacheKey([s, d], false)));
    });

    test('HTTP 400 → null', () async {
      final client = MockClient((req) async => http.Response('{"error":"x"}', 400));
      final p = ValhallaRouteProvider(client: client);
      expect(await p.route([s, d]), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('도로 옵션 설정', () {
    test('저장값 없음/알 수 없음 → free_only, all 은 명시적일 때만', () {
      expect(RoadOptionInfo.fromStorage(null), RoadOption.freeOnly);
      expect(RoadOptionInfo.fromStorage(''), RoadOption.freeOnly);
      expect(RoadOptionInfo.fromStorage('ALL'), RoadOption.freeOnly);
      expect(RoadOptionInfo.fromStorage('free_only'), RoadOption.freeOnly);
      expect(RoadOptionInfo.fromStorage('all'), RoadOption.all);
      expect(RoadOption.freeOnly.storageValue, 'free_only');
      expect(RoadOption.all.storageValue, 'all');
      expect(RoadOptionInfo.prefsKey, 'route_road_option');
    });

    test('SharedPreferences 비어 있으면 loadRoadOption() == free_only (자동 변경 없음)',
        () async {
      SharedPreferences.setMockInitialValues({});
      expect(await loadRoadOption(), RoadOption.freeOnly);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(RoadOptionInfo.prefsKey), isNull); // 읽기만, 쓰지 않음
      SharedPreferences.setMockInitialValues({'route_road_option': 'all'});
      expect(await loadRoadOption(), RoadOption.all);
    });

    test('RouteRecommendOptions 기본 도로 옵션 = free_only', () {
      final o = RouteRecommendOptions(
          radiusKm: 3,
          maxDetourMin: 10,
          mode: RouteRecommendMode.minDetour,
          departureTime: DateTime(2026, 10, 12));
      expect(o.roadOption, RoadOption.freeOnly);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('OSRM 대체', () {
    test('Valhalla 실패 → OSRM 결과, tollVerified=false · fallbackUsed · 무료 확정 아님',
        () async {
      final osrm = MockClient((req) async => http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 70000.0,
                'duration': 3600.0,
                'geometry': {
                  'coordinates': [
                    [127.1139, 36.8151],
                    [127.3848, 36.3504]
                  ]
                }
              }
            ]
          }),
          200));
      final p = FallbackRouteProvider(
        primary: _AlwaysNull(),
        fallback: OsrmRouteProvider(client: osrm),
        tollAvoidRequested: true,
      );
      final r = (await p.route(const [LatLng(36.8151, 127.1139), LatLng(36.3504, 127.3848)]))!;
      expect(r.provider, OsrmRouteProvider.providerName);
      expect(r.fallbackUsed, isTrue);
      expect(r.tollVerified, isFalse);
      expect(r.hasToll, isNull);
      expect(r.tollAvoidRequested, isTrue);
      expect(r.confirmedTollFree, isFalse);
      expect(r.tollCheck.label(fallback: r.fallbackUsed), '검증 불가(OSRM 대체)');
    });

    test('OSRM 파싱 결과 자체도 tollVerified=false (기본값 호환)', () {
      final r = OsrmRouteProvider.parseResponse(jsonEncode({
        'code': 'Ok',
        'routes': [
          {'distance': 1.0, 'duration': 1.0, 'geometry': {'coordinates': []}}
        ]
      }))!;
      expect(r.tollVerified, isFalse);
      expect(r.legHasToll, isEmpty);
      expect(r.tollAvoidRequested, isFalse);
    });

    test('기본 경로 OSRM 대체 → 결과 경고 "통행료 회피 미보장(OSRM 대체)"', () async {
      final base = const RouteResult(
              distanceM: 10000, durationS: 600, polyline: [], provider: 'osrm-demo')
          .asFallback(tollAvoidRequested: true);
      final res = RouteRecommendResult(
        baseRoute: base,
        options: RouteRecommendOptions(
            radiusKm: 3,
            maxDetourMin: 10,
            mode: RouteRecommendMode.minDetour,
            departureTime: DateTime(2026, 10, 12)),
        items: const [],
        candidatesInRadius: 0,
        candidatesEvaluated: 0,
        verifiedEngineStores: 0,
        headerNote: '',
      );
      expect(res.baseRouteTollWarning, kTollFallbackNote);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('무료도로 모드 정렬', () {
    const origin = LatLng(37.0, 127.0), dest = LatLng(37.1, 127.0);
    final stores = [cand('A', 37.02, 127.001), cand('B', 37.05, 127.001), cand('C', 37.08, 127.001)];
    final kA = TollMockProvider.key(stores[0].point);
    final kB = TollMockProvider.key(stores[1].point);
    final kC = TollMockProvider.key(stores[2].point);

    Future<RouteRecommendResult> run(RoadOption opt, TollMockProvider p) async {
      final base = (await p.route([origin, dest]))!;
      return RouteStoreRecommender(p, perRequestDelay: Duration.zero).recommend(
        origin: origin,
        destination: dest,
        baseRoute: base,
        stores: stores,
        insights: const {},
        options: RouteRecommendOptions(
          radiusKm: 5,
          maxDetourMin: 10,
          mode: RouteRecommendMode.minDetour,
          departureTime: DateTime(2026, 10, 12, 10),
          roadOption: opt,
        ),
      );
    }

    test('has_toll=true 후보는 우회가 가장 짧아도 후순위', () async {
      final p = TollMockProvider(
        tollFor: {kA: true},
        detours: {kA: (100.0, 30.0), kB: (500.0, 120.0), kC: (800.0, 200.0)},
      );
      final res = await run(RoadOption.freeOnly, p);
      expect(res.items.map((i) => i.store.code).toList(), ['B', 'C', 'A']);
      final a = res.items.last;
      expect(a.tollDemoted, isTrue);
      expect(a.tollCheckLabel, contains('유료구간 포함(회피 불가)'));
      expect(a.reasons.any((r) => r.contains(kTollNotConfirmedWarning)), isTrue);
      expect(res.items.first.tollAvoidApplied, isTrue);
      expect(res.items.first.tollCheckLabel, contains('has_toll=false 확인'));
      expect(res.tollDemotedCount, 1);
    });

    test('전체 도로 모드에서는 has_toll 로 후순위하지 않음', () async {
      final p = TollMockProvider(
        tollFor: {kA: true},
        detours: {kA: (100.0, 30.0), kB: (500.0, 120.0), kC: (800.0, 200.0)},
      );
      final res = await run(RoadOption.all, p);
      expect(res.items.first.store.code, 'A');
      expect(res.items.first.tollDemoted, isFalse);
    });

    test('유료 후보도 우회 미확인(API 실패) 후보보다는 앞', () async {
      final p = TollMockProvider(
        tollFor: {kA: true},
        failFor: {kB},
        detours: {kA: (100.0, 30.0), kC: (800.0, 200.0)},
      );
      final res = await run(RoadOption.freeOnly, p);
      expect(res.items.map((i) => i.store.code).toList(), ['C', 'A', 'B']);
    });

    test('기본 경로 has_toll=true → "무료도로 확정 아님" 경고', () async {
      final p = TollMockProvider(baseHasToll: true);
      final res = await run(RoadOption.freeOnly, p);
      expect(res.baseRouteTollWarning, kTollNotConfirmedWarning);
    });

    test('기본(Valhalla)과 경유(OSRM) 제공자가 다르면 ΔT 미확인', () async {
      final viaP = TollMockProvider(provider: 'osrm-demo');
      final base = const RouteResult(
          distanceM: 10000,
          durationS: 600,
          polyline: [origin, dest],
          provider: ValhallaRouteProvider.providerName,
          hasToll: false,
          tollVerified: true,
          tollAvoidRequested: true);
      final res = await RouteStoreRecommender(viaP, perRequestDelay: Duration.zero).recommend(
        origin: origin,
        destination: dest,
        baseRoute: base,
        stores: stores,
        insights: const {},
        options: RouteRecommendOptions(
            radiusKm: 5,
            maxDetourMin: 10,
            mode: RouteRecommendMode.minDetour,
            departureTime: DateTime(2026, 10, 12)),
      );
      expect(res.items.every((i) => !i.detourVerified), isTrue);
      expect(res.items.first.reasons.first, contains('제공자 불일치'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('외부 내비 통행료 안내', () {
    test('세 앱 모두 딥링크 통행료 파라미터 공식 지원 아님 → 안내 문구 필수', () {
      for (final a in NavApp.values) {
        expect(a.tollAvoidParamOfficial, isFalse);
        expect(a.tollNote, contains('무료도로'));
      }
      expect(kNavFreeRoadNotice, contains("'무료도로' 옵션을 직접 선택"));
    });

    test('판매점 목적지 호출: 출발지 생략 시 slat/sp 없음, 통행료 파라미터 추가 안 함', () {
      const dest = NavPoint(LatLng(36.8151, 127.1139), '판매점');
      final n = ExternalNav.naverRouteUri(destination: dest);
      expect(n.queryParameters.containsKey('slat'), isFalse);
      expect(n.queryParameters['dlat'], '36.815100');
      final k = ExternalNav.kakaoRouteUri(destination: dest);
      expect(k.queryParameters.containsKey('sp'), isFalse);
      expect(k.queryParameters['ep'], '36.815100,127.113900');
      for (final u in [n, k, ExternalNav.tmapRouteUri(destination: dest)]) {
        expect(u.query.toLowerCase(), isNot(contains('toll')));
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('region_id 규칙', () {
    test('광역시 구/군, 도 시/군, 세종, 인터넷 제외', () {
      expect(RegionIds.fromStore(region: '서울', address: '서울 노원구 상계로 1'), '서울|노원구');
      expect(RegionIds.fromStore(region: '인천', address: '인천 강화군 강화읍 1'), '인천|강화군');
      expect(RegionIds.fromStore(region: '경기', address: '경기 수원시 장안구 정자동 1'), '경기|수원시');
      expect(RegionIds.fromStore(region: '충남', address: '충남 천안시 동남구 1'), '충남|천안시');
      expect(RegionIds.fromStore(region: '세종', address: '세종  한누리대로 321 103호'), '세종|세종시');
      expect(RegionIds.fromStore(region: '경북', address: '경북 의성군 의성읍 1'), '경북|의성군');
      expect(
          RegionIds.fromStore(
              region: '동행복권(dhlottery.co.kr)', address: '동행복권(dhlottery.co.kr)'),
          isNull);
      expect(RegionIds.fromStore(region: '서울', address: '서울특별시 강남구 테헤란로'), '서울|강남구');
      expect(RegionIds.fromStore(region: '서울', address: '서울 테헤란로 1'), isNull);
    });

    test('지역 단위 검색: 천안 / 서울 노원구', () {
      const units = [
        RegionUnit(regionId: '충남|천안시', sido: '충남', unitName: '천안시', subUnits: ['동남구', '서북구']),
        RegionUnit(regionId: '서울|노원구', sido: '서울', unitName: '노원구'),
        RegionUnit(regionId: '서울|도봉구', sido: '서울', unitName: '도봉구'),
      ];
      expect(units.where((u) => u.matches('천안')).map((u) => u.regionId), ['충남|천안시']);
      expect(units.where((u) => u.matches('서울 노원구')).map((u) => u.regionId), ['서울|노원구']);
      expect(units.where((u) => u.matches('서울')).length, 2);
      expect(units.where((u) => u.matches('서북구')).map((u) => u.regionId), ['충남|천안시']);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  group('지역 판매점 순위', () {
    RegionStore st(String code, {int f = 0, int s = 0, LatLng? p, String rid = '충남|천안시'}) =>
        RegionStore(
            code: code,
            name: code,
            address: '',
            region: '충남',
            regionId: rid,
            point: p,
            firstCount: f,
            secondCount: s);

    test('검증 신호 없음 → 이력 중심 헤더, 동점은 코드순 (결정적)', () {
      final stores = [
        st('300', f: 1, p: const LatLng(36.8, 127.1)),
        st('100', f: 1, p: const LatLng(36.8, 127.1)),
        st('200', f: 3, s: 2, p: const LatLng(36.8, 127.1)),
        st('400'),
      ];
      const inputs = RegionEngineInputs();
      final a = RegionStoreRanker.rank(stores: stores, inputs: inputs);
      final b = RegionStoreRanker.rank(stores: stores.reversed.toList(), inputs: inputs);
      expect(a.map((e) => e.store.code).toList(), ['200', '100', '300', '400']);
      expect(b.map((e) => e.store.code).toList(), a.map((e) => e.store.code).toList());
      final res = RegionStoreRanker.buildResult(a, inputs);
      expect(res.header, kRegionNoVerifiedHeader);
      expect(a.first.components['history'], closeTo(1.0, 1e-12));
      expect(a.first.total, closeTo(0.4 + 0.2, 1e-12)); // 이력 1.0 + 품질(좌표+이력) 1.0
      expect(a.last.verification, '데이터 없음');
      expect(res.disclaimer, contains('한 장당'));
    });

    test('famous 이어도 검증 통과 가설 없으면 주기 가점 0, 있으면 0.2', () {
      final stores = [st('A', f: 2), st('B', f: 2)];
      final inputs = RegionEngineInputs(
        historyLoaded: false,
        cycles: const {
          'A': StoreCycle(storeCode: 'A', trainingEndRound: 1190, cls: 'famous'),
          'B': StoreCycle(storeCode: 'B', trainingEndRound: 1190, cls: 'famous'),
        },
        storeHypotheses: const {
          'B': [
            RegionHypothesis(
                hypothesisId: 'h1', kind: 'store_cycle', storeCode: 'B', status: 'passed')
          ],
        },
      );
      final r = RegionStoreRanker.rank(stores: stores, inputs: inputs);
      expect(r.first.store.code, 'B');
      expect(r.first.components['cycle'], 1.0);
      expect(r.first.verification, '검증 통과');
      expect(r.last.components['cycle'], 0.0);
      expect(r.last.verification, '연구 중');
      expect(r.first.total - r.last.total, closeTo(0.2, 1e-12));
    });

    test('전이 가설: passed + 발화 중일 때만 가점 (researching·창 밖은 0)', () {
      const passedFiring = RegionHypothesis(
          hypothesisId: 't1',
          kind: 'transition_up',
          fromRegion: '충남|아산시',
          toRegion: '충남|천안시',
          horizon: 3,
          status: 'passed');
      const researching = RegionHypothesis(
          hypothesisId: 't2',
          kind: 'transition_up',
          fromRegion: '충남|아산시',
          toRegion: '경기|평택시',
          horizon: 3,
          status: 'researching');
      // 아산시 마지막 1등 1198회, 최신 1200회 → 1200-1198=2 < 3 발화
      expect(RegionStoreRanker.isFiring(passedFiring, {'충남|아산시': 1198}, 1200), isTrue);
      expect(RegionStoreRanker.isFiring(passedFiring, {'충남|아산시': 1197}, 1200), isFalse);
      expect(RegionStoreRanker.isFiring(passedFiring, const {}, 1200), isFalse);
      expect(RegionStoreRanker.isFiring(passedFiring, {'충남|아산시': 1198}, null), isFalse);

      final stores = [
        st('X', f: 1, rid: '충남|천안시'),
        st('Y', f: 1, rid: '경기|평택시'),
      ];
      final inputs = RegionEngineInputs(
        transitions: const [passedFiring, researching],
        lastFirstRoundByRegion: const {'충남|아산시': 1198},
        latestRound: 1200,
        historyLoaded: false,
      );
      final r = RegionStoreRanker.rank(stores: stores, inputs: inputs);
      expect(r.first.store.code, 'X');
      expect(r.first.components['transition'], 1.0);
      expect(r.first.firingTransitions.single.hypothesisId, 't1');
      expect(r.last.components['transition'], 0.0);
      expect(RegionStoreRanker.buildResult(r, inputs).header,
          isNot(kRegionNoVerifiedHeader));
    });

    test('transition_down 은 passed 여도 가점 없음', () {
      const down = RegionHypothesis(
          hypothesisId: 'd',
          kind: 'transition_down',
          fromRegion: 'a',
          toRegion: '충남|천안시',
          horizon: 5,
          status: 'passed');
      final f = RegionStoreRanker.firingByRegion(const [down], const {'a': 1200}, 1200);
      expect(f, isEmpty);
    });

    test('거리순 정렬: 동일 거리면 점수, 그다음 코드', () {
      const me = LatLng(36.8151, 127.1139);
      final stores = [
        st('B', f: 1, p: const LatLng(36.8251, 127.1139)),
        st('A', f: 0, p: const LatLng(36.8251, 127.1139)),
        st('C', f: 5, p: const LatLng(36.8551, 127.1139)),
      ];
      final r = RegionStoreRanker.rank(
          stores: stores, inputs: const RegionEngineInputs(), origin: me, sort: RegionSort.distance);
      expect(r.map((e) => e.store.code).toList(), ['B', 'A', 'C']);
      expect(r.first.distanceM, closeTo(1112, 5));
      final e = RegionStoreRanker.rank(
          stores: stores, inputs: const RegionEngineInputs(), origin: me);
      expect(e.first.store.code, 'C');
    });

    test('테이블 없음 판정: PGRST205 / 42P01 → 연구 미실행, 그 외 오류는 아님', () {
      expect(
          RegionResearchRepository.isMissingTable(const PostgrestException(
              message: "Could not find the table 'public.research_region_stats' in the schema cache",
              code: 'PGRST205')),
          isTrue);
      expect(
          RegionResearchRepository.isMissingTable(const PostgrestException(
              message: 'relation "research_store_cycles" does not exist', code: '42P01')),
          isTrue);
      expect(
          RegionResearchRepository.isMissingTable(
              const PostgrestException(message: 'JWT expired', code: 'PGRST301')),
          isFalse);
      expect(ResearchAvailability.notApplied.label, kResearchNotApplied);
      expect(ResearchAvailability.noData.label, kResearchNoData);
    });

    test('가설 목록 정렬: passed → researching → … , p 오름차순, id', () {
      final l = RegionResearchRepository.sortHypotheses([
        const RegionHypothesis(hypothesisId: 'z', kind: 'k', status: 'rejected'),
        const RegionHypothesis(hypothesisId: 'b', kind: 'k', status: 'passed', testP: 0.04),
        const RegionHypothesis(hypothesisId: 'a', kind: 'k', status: 'passed', testP: 0.04),
        const RegionHypothesis(hypothesisId: 'c', kind: 'k', status: 'researching', testP: 0.001),
        const RegionHypothesis(hypothesisId: 'd', kind: 'k', status: 'passed', testP: 0.01),
      ]);
      expect(l.map((h) => h.hypothesisId).toList(), ['d', 'a', 'b', 'c', 'z']);
    });
  });
}
