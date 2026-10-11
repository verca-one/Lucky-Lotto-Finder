// 경로 기반 추천 — 핵심 수학/정렬 단위 테스트 (네트워크 미사용)
//
// 실행: flutter test test/route

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_app/services/route/external_nav.dart';
import 'package:flutter_app/services/route/geocoding_service.dart';
import 'package:flutter_app/services/route/route_store_recommender.dart';
import 'package:flutter_app/services/route/routing_service.dart';

/// 모의 RouteProvider: 경유지 수에 따라 고정 duration/distance 를 반환하거나,
/// 특정 좌표 경유 시 실패(null)를 흉내 낸다.
class MockRouteProvider implements RouteProvider {
  final double baseDistanceM;
  final double baseDurationS;

  /// 경유지(P) 좌표 → (추가거리 m, 추가시간 s). 없으면 기본 추가값.
  final Map<String, (double, double)> detours;
  final Set<String> failFor;
  final List<List<LatLng>> calls = [];

  MockRouteProvider({
    this.baseDistanceM = 10000,
    this.baseDurationS = 600,
    this.detours = const {},
    this.failFor = const {},
  });

  static String key(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';

  @override
  Future<RouteResult?> route(List<LatLng> waypoints) async {
    calls.add(waypoints);
    if (waypoints.length == 2) {
      return RouteResult(
        distanceM: baseDistanceM,
        durationS: baseDurationS,
        polyline: waypoints,
        provider: 'mock',
      );
    }
    final k = key(waypoints[1]);
    if (failFor.contains(k)) return null;
    final (dL, dT) = detours[k] ?? (1000.0, 120.0);
    return RouteResult(
      distanceM: baseDistanceM + dL,
      durationS: baseDurationS + dT,
      polyline: waypoints,
      provider: 'mock',
    );
  }
}

void main() {
  // 서울시청 → 수원역 방향의 단순 2점 직선 경로
  const origin = LatLng(37.5663, 126.9779);
  const dest = LatLng(37.2659, 127.0003);
  final polyline = [origin, const LatLng(37.45, 126.99), dest];

  group('RouteGeo 기하', () {
    test('Haversine: 서울시청-수원역 약 33.4km', () {
      final d = RouteGeo.haversineM(origin, dest);
      expect(d, closeTo(33400, 400));
    });

    test('선분-점 거리: 선분 중점에서 동쪽 1km 떨어진 점', () {
      const a = LatLng(37.0, 127.0);
      const b = LatLng(37.0, 127.1);
      // 위도 37도에서 경도 1도 ≈ 88.9km → 1km ≈ 0.01125도 (중점 127.05 에서 남쪽으로 0.009도=1km)
      const p = LatLng(36.991, 127.05);
      final d = RouteGeo.pointToSegmentDistanceM(p, a, b);
      expect(d, closeTo(1000, 30));
    });

    test('선분-점 거리: 선분 밖(연장선)의 점은 끝점까지 거리', () {
      const a = LatLng(37.0, 127.0);
      const b = LatLng(37.0, 127.1);
      const p = LatLng(37.0, 127.2); // b 에서 동쪽으로 더 감
      final d = RouteGeo.pointToSegmentDistanceM(p, a, b);
      expect(d, closeTo(RouteGeo.haversineM(p, b), 1));
    });

    test('길이 0 선분은 점 거리', () {
      const a = LatLng(37.0, 127.0);
      const p = LatLng(37.01, 127.0);
      expect(RouteGeo.pointToSegmentDistanceM(p, a, a),
          closeTo(RouteGeo.haversineM(p, a), 0.01));
    });

    test('polyline 최소거리는 각 선분 최소값', () {
      const p = LatLng(37.45, 127.02); // 중간점 근처 동쪽 ~2.65km
      final d = RouteGeo.minDistanceToPolylineM(p, polyline);
      expect(d, lessThan(3000));
      expect(d, greaterThan(2000));
    });

    test('bounding box 여유 반경 포함', () {
      final box = RouteGeo.boundingBox(polyline, 3);
      expect(box.minLat, lessThan(37.2659));
      expect(box.maxLat, greaterThan(37.5663));
      expect(box.contains(const LatLng(37.4, 127.0)), isTrue);
      // 경로에서 약 3km 안쪽(경도 0.025도 ≈ 2.2km) 포함
      expect(box.contains(const LatLng(37.4, 127.025)), isTrue);
      // 10km 밖 제외
      expect(box.contains(const LatLng(37.4, 127.2)), isFalse);
    });

    test('한국 좌표 범위 검사: null/0/범위 밖 제외', () {
      expect(RouteGeo.isValidKoreaCoord(37.5, 127.0), isTrue);
      expect(RouteGeo.isValidKoreaCoord(null, 127.0), isFalse);
      expect(RouteGeo.isValidKoreaCoord(0, 0), isFalse);
      expect(RouteGeo.isValidKoreaCoord(40.0, 127.0), isFalse);
      expect(RouteGeo.isValidKoreaCoord(37.0, 120.0), isFalse);
    });
  });

  group('필터링', () {
    RouteStoreCandidate mk(String code, double lat, double lng,
            {int first = 0, int second = 0}) =>
        RouteStoreCandidate(
          code: code,
          name: 'S$code',
          address: '',
          region: '',
          point: LatLng(lat, lng),
          firstCount: first,
          secondCount: second,
        );

    test('bounding box + 반경 필터, 거리순 정렬', () {
      final stores = [
        mk('C', 37.45, 127.02), // ~2.6km
        mk('A', 37.45, 126.995), // ~0.4km
        mk('B', 37.45, 127.10), // ~9.7km (bbox 안이지만 반경 밖)
        mk('Z', 38.5, 127.0), // bbox 밖
        mk('N', 0, 0), // 좌표 무효
      ];
      final r = RouteStoreRecommender.filterByRoute(stores, polyline, 3);
      expect(r.map((s) => s.code).toList(), ['A', 'C']);
      expect(r.first.distToRouteM, lessThan(600));
      expect(r.first.distToRouteM, greaterThan(300));
    });

    test('상위 후보: 거리 절반 + 이력 절반 혼합, 결정적', () {
      final stores = <RouteStoreCandidate>[];
      for (var i = 0; i < 20; i++) {
        // 코드 00..19, 거리는 코드순 증가(선분에서 동쪽으로), 이력은 역순
        stores.add(mk(i.toString().padLeft(2, '0'), 37.45,
            126.99 + 0.0005 * (i + 1),
            first: 20 - i));
      }
      final inR = RouteStoreRecommender.filterByRoute(stores, polyline, 5);
      final top1 = RouteStoreRecommender.selectTopCandidates(inR, max: 6);
      final top2 = RouteStoreRecommender.selectTopCandidates(inR, max: 6);
      expect(top1.length, 6);
      expect(top1.map((s) => s.code), top2.map((s) => s.code));
      // 거리 상위 3 (00,01,02) 포함. 이력 상위는 00,01,02 (겹침) → 거리순으로 채움
      expect(top1.map((s) => s.code).toList(),
          ['00', '01', '02', '03', '04', '05']);
    });
  });

  group('추천기 ΔT/ΔL · 정렬', () {
    final p1 = const LatLng(37.45, 126.995); // 가까움
    final p2 = const LatLng(37.40, 126.99);
    final p3 = const LatLng(37.35, 127.00);
    final stores = [
      RouteStoreCandidate(code: '002', name: 'B', address: '', region: '', point: p2, firstCount: 10),
      RouteStoreCandidate(code: '001', name: 'A', address: '', region: '', point: p1, firstCount: 1),
      RouteStoreCandidate(code: '003', name: 'C', address: '', region: '', point: p3, firstCount: 5),
    ];
    final base = RouteResult(
        distanceM: 10000, durationS: 600, polyline: polyline, provider: 'mock');

    RouteRecommendOptions opts(RouteRecommendMode m, {int maxDetour = 10}) =>
        RouteRecommendOptions(
          radiusKm: 5,
          maxDetourMin: maxDetour,
          mode: m,
          departureTime: DateTime(2026, 10, 10, 19, 0), // 토요일 19:00
        );

    test('ΔT/ΔL 은 모의 Provider 의 S→P→D 값 − 기본값 (직선거리 아님)', () async {
      final prov = MockRouteProvider(detours: {
        MockRouteProvider.key(p1): (500.0, 60.0),
        MockRouteProvider.key(p2): (3000.0, 400.0),
        MockRouteProvider.key(p3): (1500.0, 200.0),
      });
      final rec = RouteStoreRecommender(prov, perRequestDelay: Duration.zero);
      final res = await rec.recommend(
        origin: origin,
        destination: dest,
        baseRoute: base,
        stores: stores,
        insights: const {},
        options: opts(RouteRecommendMode.minDetour),
      );
      expect(res.items.length, 3);
      final byCode = {for (final i in res.items) i.store.code: i};
      expect(byCode['001']!.deltaTimeS, 60);
      expect(byCode['001']!.deltaDistM, 500);
      expect(byCode['002']!.deltaTimeS, 400);
      expect(byCode['003']!.deltaDistM, 1500);
      // 모든 경유 호출은 [S, P, D] 3점
      expect(prov.calls.every((c) => c.length == 3), isTrue);
      expect(prov.calls.map((c) => c.first), everyElement(origin));
      expect(prov.calls.map((c) => c.last), everyElement(dest));
      // minDetour: ΔT 오름차순 001(60) < 003(200) < 002(400)
      expect(res.items.map((i) => i.store.code).toList(), ['001', '003', '002']);
      expect(res.items.map((i) => i.rank).toList(), [1, 2, 3]);
    });

    test('ETA = 출발 + 경유 duration, 토요일 20:00 이후 경고', () async {
      final prov = MockRouteProvider();
      final rec = RouteStoreRecommender(prov, perRequestDelay: Duration.zero);
      final res = await rec.recommend(
        origin: origin,
        destination: dest,
        baseRoute: base,
        stores: stores.take(1).toList(),
        insights: const {},
        options: RouteRecommendOptions(
          radiusKm: 5,
          maxDetourMin: 10,
          mode: RouteRecommendMode.minDetour,
          departureTime: DateTime(2026, 10, 10, 19, 50), // 토
        ),
      );
      final it = res.items.single;
      // 600 + 120 = 720s → 20:02
      expect(it.eta, DateTime(2026, 10, 10, 20, 2));
      expect(it.etaAfterSalesClose, isTrue);
      expect(it.openStatus, kOpenStatusUnknown);
    });

    test('API 실패 후보는 "우회시간 미확인" 으로 맨 뒤', () async {
      final prov = MockRouteProvider(
        detours: {
          MockRouteProvider.key(p2): (100.0, 10.0), // 가장 빠름이지만 실패 대상 아님
          MockRouteProvider.key(p3): (900.0, 90.0),
        },
        failFor: {MockRouteProvider.key(p1)},
      );
      final rec = RouteStoreRecommender(prov, perRequestDelay: Duration.zero);
      final res = await rec.recommend(
        origin: origin,
        destination: dest,
        baseRoute: base,
        stores: stores,
        insights: const {},
        options: opts(RouteRecommendMode.minDetour),
      );
      expect(res.items.last.store.code, '001');
      expect(res.items.last.detourVerified, isFalse);
      expect(res.items.last.reasons, contains(kDetourUnverified));
      expect(res.items.first.store.code, '002');
    });

    test('history 모드: log1p 가중, 최대 우회 초과는 뒤 그룹, 재현성', () async {
      final prov = MockRouteProvider(detours: {
        MockRouteProvider.key(p1): (500.0, 60.0),
        MockRouteProvider.key(p2): (3000.0, 900.0), // 15분 > 10분 초과
        MockRouteProvider.key(p3): (1500.0, 200.0),
      });
      final ins = {
        '001': const StoreEngineInsight(historyFirst: 1),
        '002': const StoreEngineInsight(historyFirst: 10),
        '003': const StoreEngineInsight(historyFirst: 5, historySecond: 2, hypotheses: [
          StoreHypothesisLite(hypothesisId: 'h', hypothesisType: 'persistence', status: 'observing', gateStatus: 'not_evaluated'),
        ]),
      };
      final rec = RouteStoreRecommender(prov, perRequestDelay: Duration.zero);
      final r1 = await rec.recommend(
          origin: origin, destination: dest, baseRoute: base, stores: stores,
          insights: ins, options: opts(RouteRecommendMode.history));
      final r2 = await rec.recommend(
          origin: origin, destination: dest, baseRoute: base, stores: stores,
          insights: ins, options: opts(RouteRecommendMode.history));
      expect(r1.items.map((i) => i.store.code).toList(),
          r2.items.map((i) => i.store.code).toList());
      // 003 (log1p(5)+0.3*log1p(2)+0.2 ≈ 2.32) > 001 (0.69) 이고 002 는 초과그룹으로 뒤
      expect(r1.items.map((i) => i.store.code).toList(), ['003', '001', '002']);
      expect(r1.items[2].detourGroup, DetourGroup.overLimit);
      expect(r1.headerNote, contains(kHistoryModeNote));
      expect(r1.items.first.score.components['quality'], 0.2);
      expect(r1.items.first.score.weights['log1p_second'], 0.3);
    });

    test('engine 모드: 검증 통과 0곳이면 헤더 문구, 가중 0', () async {
      final prov = MockRouteProvider(detours: {
        MockRouteProvider.key(p1): (500.0, 60.0),
        MockRouteProvider.key(p2): (3000.0, 300.0),
        MockRouteProvider.key(p3): (1500.0, 200.0),
      });
      final ins = {
        '002': const StoreEngineInsight(historyFirst: 10, hypotheses: [
          StoreHypothesisLite(hypothesisId: 'h', hypothesisType: 'persistence', status: 'observing', gateStatus: 'fail'),
        ]),
      };
      final rec = RouteStoreRecommender(prov, perRequestDelay: Duration.zero);
      final res = await rec.recommend(
          origin: origin, destination: dest, baseRoute: base, stores: stores,
          insights: ins, options: opts(RouteRecommendMode.engine));
      expect(res.verifiedEngineStores, 0);
      expect(res.headerNote, contains(kNoVerifiedEngineHeader));
      expect(res.disclaimer, kScoreDisclaimer);
      for (final it in res.items) {
        expect(it.score.components['engine_bonus'], 0.0);
        expect(it.score.weights['access'], 0.5);
        expect(it.score.weights['history'], 0.3);
        expect(it.score.weights['quality'], 0.2);
      }
      // 001: access 1-60/600=0.9 → 0.45 ; 002: access 0.5→0.25 + hist 0.3 + quality 0.3*0.2=0.06 → 0.61
      final byCode = {for (final i in res.items) i.store.code: i};
      expect(byCode['001']!.score.total, closeTo(0.45, 1e-9));
      expect(byCode['002']!.score.total, closeTo(0.61, 1e-9));
      expect(res.items.first.store.code, '002');
    });

    test('engine 모드: gate pass 가설은 +1.0/개, 최대 +2.0', () async {
      final prov = MockRouteProvider();
      const h = StoreHypothesisLite(
          hypothesisId: 'h', hypothesisType: 'emerging', status: 'validated', gateStatus: 'pass');
      final ins = {
        '001': const StoreEngineInsight(hypotheses: [h, h, h]),
        '002': const StoreEngineInsight(hypotheses: [h]),
      };
      final rec = RouteStoreRecommender(prov, perRequestDelay: Duration.zero);
      final res = await rec.recommend(
          origin: origin, destination: dest, baseRoute: base, stores: stores,
          insights: ins, options: opts(RouteRecommendMode.engine));
      final byCode = {for (final i in res.items) i.store.code: i};
      expect(byCode['001']!.score.components['engine_bonus'], 2.0);
      expect(byCode['002']!.score.components['engine_bonus'], 1.0);
      expect(byCode['003']!.score.components['engine_bonus'], 0.0);
      expect(res.verifiedEngineStores, 2);
      expect(res.headerNote, isNot(contains(kNoVerifiedEngineHeader)));
      expect(res.items.first.store.code, '001');
    });

    test('동률 tie-break 는 판매점 코드순', () async {
      final prov = MockRouteProvider(); // 모두 동일 ΔT
      final rec = RouteStoreRecommender(prov, perRequestDelay: Duration.zero);
      final res = await rec.recommend(
          origin: origin, destination: dest, baseRoute: base, stores: stores,
          insights: const {}, options: opts(RouteRecommendMode.minDetour));
      expect(res.items.map((i) => i.store.code).toList(), ['001', '002', '003']);
    });
  });

  group('좌표 순서 (OSRM lng,lat ↔ flutter_map lat,lng)', () {
    test('OSRM URL 은 lng,lat 순서', () {
      final uri = OsrmRouteProvider.buildUri([origin, dest]);
      expect(uri.path, contains('126.977900,37.566300;127.000300,37.265900'));
      expect(uri.queryParameters['overview'], 'full');
      expect(uri.queryParameters['geometries'], 'geojson');
    });

    test('OSRM 응답 [lng,lat] → LatLng(lat,lng)', () {
      final body = jsonEncode({
        'code': 'Ok',
        'routes': [
          {
            'distance': 38839.4,
            'duration': 2258.5,
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [126.977229, 37.566301],
                [127.000928, 37.266142],
              ],
            },
          }
        ],
      });
      final r = OsrmRouteProvider.parseResponse(body)!;
      expect(r.distanceM, 38839.4);
      expect(r.durationS, 2258.5);
      expect(r.trafficAware, isFalse);
      expect(r.polyline.first.latitude, 37.566301);
      expect(r.polyline.first.longitude, 126.977229);
      expect(OsrmRouteProvider.parseResponse('{"code":"NoRoute"}'), isNull);
      expect(OsrmRouteProvider.parseResponse('not json'), isNull);
    });

    test('Nominatim 파싱 lat/lon 문자열 → LatLng', () {
      final list = NominatimGeocodingService.parseResponse(jsonEncode([
        {'lat': '37.5663', 'lon': '126.9779', 'name': '서울특별시청', 'display_name': '서울특별시청, 세종대로, 중구'}
      ]));
      expect(list.single.point.latitude, 37.5663);
      expect(list.single.point.longitude, 126.9779);
      expect(list.single.name, '서울특별시청');
      final uri = NominatimGeocodingService.buildUri('서울시청');
      expect(uri.queryParameters['countrycodes'], 'kr');
      expect(uri.queryParameters['limit'], '5');
    });

    test('내비 딥링크: 네이버 lat/lng, TMAP X=lng Y=lat, 카카오 "lat,lng"', () {
      const o = NavPoint(LatLng(37.5663, 126.9779), '출발');
      const v = NavPoint(LatLng(37.45, 126.995), '판매점');
      const d = NavPoint(LatLng(37.2659, 127.0003), '도착');
      final n = ExternalNav.naverRouteUri(origin: o, waypoint: v, destination: d);
      expect(n.scheme, 'nmap');
      expect(n.host, 'route');
      expect(n.path, '/car');
      expect(n.queryParameters['slat'], '37.566300');
      expect(n.queryParameters['slng'], '126.977900');
      expect(n.queryParameters['v1lat'], '37.450000');
      expect(n.queryParameters['v1lng'], '126.995000');
      expect(n.queryParameters['dlat'], '37.265900');
      expect(n.queryParameters['appname'], 'com.luckylotto.finder');

      final t = ExternalNav.tmapRouteUri(destination: v);
      expect(t.scheme, 'tmap');
      expect(t.queryParameters['rGoX'], '126.995000'); // 경도
      expect(t.queryParameters['rGoY'], '37.450000'); // 위도
      expect(t.queryParameters.containsKey('rV1X'), isFalse);
      final t2 = ExternalNav.tmapRouteUri(
          origin: o, waypoint: v, destination: d, includeUnofficialParams: true);
      expect(t2.queryParameters['rV1X'], '126.995000');

      final k = ExternalNav.kakaoRouteUri(origin: o, waypoint: v, destination: d);
      expect(k.scheme, 'kakaomap');
      expect(k.queryParameters['sp'], '37.566300,126.977900');
      expect(k.queryParameters['ep'], '37.265900,127.000300');
      expect(k.queryParameters['vp'], '37.450000,126.995000');
      expect(k.queryParameters['by'], 'car');
    });
  });
}
