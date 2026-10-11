// 경로 기반 추천 — 라우팅 서비스 (관리자 전용 연구 기능)
//
// ── 사용 API: OSRM 공개 데모 서버 ───────────────────────────────────────
//   https://router.project-osrm.org/route/v1/driving/{lng,lat;lng,lat;...}
//     ?overview=full&geometries=geojson
//
// ── 이용 정책 (반드시 준수) ───────────────────────────────────────────────
//   * 데모 서버는 "fair-use" 공개 서비스로, 상업적/대량 호출을 위한 SLA가 없다.
//     (https://github.com/Project-OSRM/osrm-backend/wiki/Demo-server)
//   * 비용 0원, API 키 불필요. 대신 과도한 요청 금지 → 동일 좌표열 결과는 10분 메모리 캐시.
//   * 교통 상황 미반영(trafficAware = false). 모든 소요시간은 "교통 미반영 추정값".
//   * 좌표 순서: OSRM 은 `lng,lat` / flutter_map(latlong2) 은 `lat,lng` 이므로
//     [coordinateString] · [parseResponse] 에서 변환한다.
//   * 실패(타임아웃 12s, 비정상 코드, 파싱 오류)는 예외 대신 null 반환.
//
// ── 무료도로(통행료 회피): Valhalla 공개 인스턴스 (FOSSGIS) ─────────────────
//   POST https://valhalla1.openstreetmap.de/route  (키 없음, 무료, fair-use)
//   * OSRM 데모 서버는 exclude=toll 에 HTTP 400 → 통행료 회피·검증 불가. 그래서 무료도로
//     모드의 1차 제공자는 Valhalla, 실패 시에만 OSRM 대체(통행료 회피 미보장 명시).
//   * 응답 trip.summary.has_toll / trip.legs[i].summary.has_toll 로 실제 검증.
//   * shape = encoded polyline precision 6 ([decodePolyline6]).
//   * 요청 간 최소 1초 간격(스로틀), 10분 메모리 캐시(키에 avoidTolls 포함), 타임아웃 20s.
//
// 기존 크롤링 시스템과 무관한 독립 모듈이며 DB에 쓰지 않는다.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// 경로 조회 결과.
class RouteResult {
  /// 총 거리 (미터)
  final double distanceM;

  /// 총 소요시간 (초) — 교통 미반영 추정값
  final double durationS;

  /// 지도 표시용 경로 (lat,lng 순서의 latlong2 LatLng)
  final List<LatLng> polyline;

  /// 제공자 식별자 (예: 'osrm-demo', 'valhalla-fossgis', 'mock')
  final String provider;

  /// 교통 반영 여부. OSRM 데모·Valhalla 공개 서버 모두 false.
  final bool trafficAware;

  /// 응답이 보고한 유료구간 포함 여부 (Valhalla trip.summary.has_toll). 모르면 null.
  final bool? hasToll;

  /// 통행료 회피를 요청했는지 (무료도로 모드). OSRM 대체 결과에서도 "요청" 여부는 유지한다.
  final bool tollAvoidRequested;

  /// 응답에 has_toll 필드가 실제로 존재해 통행료 포함 여부를 검증할 수 있었는지.
  final bool tollVerified;

  /// 구간(leg)별 has_toll. S→P→D 이면 [S→P, P→D].
  final List<bool?> legHasToll;

  /// 1차 제공자 실패로 OSRM 대체 결과인지 (통행료 회피 미보장).
  final bool fallbackUsed;

  const RouteResult({
    required this.distanceM,
    required this.durationS,
    required this.polyline,
    required this.provider,
    this.trafficAware = false,
    this.hasToll,
    this.tollAvoidRequested = false,
    this.tollVerified = false,
    this.legHasToll = const [],
    this.fallbackUsed = false,
  });

  double get distanceKm => distanceM / 1000.0;
  double get durationMin => durationS / 60.0;

  /// 통행료 검증 상태 (화면 문구·정렬에 사용)
  TollCheck get tollCheck {
    if (!tollVerified || hasToll == null) return TollCheck.unverifiable;
    return hasToll! ? TollCheck.tollIncluded : TollCheck.verifiedFree;
  }

  /// "무료도로 확정" — 회피를 요청했고, 응답으로 has_toll=false 가 검증된 경우에만 true.
  bool get confirmedTollFree =>
      tollAvoidRequested && !fallbackUsed && tollCheck == TollCheck.verifiedFree;

  /// OSRM 대체 표시용 복사본: 통행료 검증 불가로 강등한다.
  RouteResult asFallback({required bool tollAvoidRequested}) => RouteResult(
        distanceM: distanceM,
        durationS: durationS,
        polyline: polyline,
        provider: provider,
        trafficAware: trafficAware,
        hasToll: null,
        tollAvoidRequested: tollAvoidRequested,
        tollVerified: false,
        legHasToll: const [],
        fallbackUsed: true,
      );

  @override
  String toString() =>
      'RouteResult($provider, ${distanceM.toStringAsFixed(0)}m, '
      '${durationS.toStringAsFixed(0)}s, ${polyline.length}pts, toll=$hasToll'
      '${fallbackUsed ? ', fallback' : ''})';
}

/// 통행료 검증 상태
enum TollCheck {
  /// 응답 has_toll=false 확인
  verifiedFree,

  /// 응답 has_toll=true (유료구간 포함)
  tollIncluded,

  /// 응답에 has_toll 없음 (OSRM 등) → 검증 불가
  unverifiable,
}

extension TollCheckLabel on TollCheck {
  /// [fallback] 이면 OSRM 대체 문구로 표시
  String label({bool fallback = false, bool avoidRequested = true}) => switch (this) {
        TollCheck.verifiedFree => 'has_toll=false 확인',
        TollCheck.tollIncluded =>
          avoidRequested ? '유료구간 포함(회피 불가)' : '유료구간 포함',
        TollCheck.unverifiable =>
          fallback ? '검증 불가(OSRM 대체)' : '검증 불가(응답에 has_toll 없음)',
      };
}

/// 도로 옵션 (SharedPreferences 'route_road_option' = free_only | all)
enum RoadOption { freeOnly, all }

extension RoadOptionInfo on RoadOption {
  static const String prefsKey = 'route_road_option';

  String get storageValue => switch (this) {
        RoadOption.freeOnly => 'free_only',
        RoadOption.all => 'all',
      };

  String get label => switch (this) {
        RoadOption.freeOnly => '무료도로만 이용',
        RoadOption.all => '전체 도로 이용',
      };

  bool get avoidTolls => this == RoadOption.freeOnly;

  /// 저장값 파싱. 값이 없거나 알 수 없으면 항상 free_only (자동으로 all 로 바꾸지 않는다).
  static RoadOption fromStorage(String? v) =>
      v == 'all' ? RoadOption.all : RoadOption.freeOnly;
}

/// OSM 통행료 판정 한계 문구
const String kTollDataDisclaimer =
    '통행료 판정은 OpenStreetMap toll 태그 기준이며 실제 통행료 정책과 다를 수 있음'
    '(무료 고속도로·유료 교량/터널 포함)';
const String kTollFallbackNote = '통행료 회피 미보장(OSRM 대체)';
const String kTollNotConfirmedWarning =
    '무료도로 확정 아님 — 이 구간은 유료도로 회피 경로가 없음';

/// 라우팅 제공자 추상화. 테스트에서는 모의 구현을 주입한다.
abstract class RouteProvider {
  /// [waypoints] 순서대로 경유하는 경로. 실패 시 null.
  Future<RouteResult?> route(List<LatLng> waypoints);
}

class _CacheEntry {
  final RouteResult result;
  final DateTime storedAt;
  _CacheEntry(this.result, this.storedAt);
}

/// OSRM 공개 데모 서버 기반 구현.
class OsrmRouteProvider implements RouteProvider {
  static const String baseUrl =
      'https://router.project-osrm.org/route/v1/driving/';
  static const String userAgent =
      'LuckyLottoFinder/1.0 (admin route research)';
  static const Duration cacheTtl = Duration(minutes: 10);
  static const String providerName = 'osrm-demo';

  final http.Client _client;
  final Duration timeout;
  final Map<String, _CacheEntry> _cache = {};

  /// [client] 는 테스트 주입용. 생략 시 기본 http.Client 사용.
  OsrmRouteProvider({http.Client? client, this.timeout = const Duration(seconds: 12)})
      : _client = client ?? http.Client();

  /// OSRM 좌표열: `lng,lat;lng,lat` (경도 먼저!). 캐시 키로도 사용.
  static String coordinateString(List<LatLng> waypoints) => waypoints
      .map((p) =>
          '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
      .join(';');

  static Uri buildUri(List<LatLng> waypoints) => Uri.parse(
      '$baseUrl${coordinateString(waypoints)}?overview=full&geometries=geojson');

  /// OSRM JSON 응답 파싱. geometry.coordinates 는 [lng, lat] 이므로 LatLng(lat, lng)로 뒤집는다.
  static RouteResult? parseResponse(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map<String, dynamic>) return null;
      if (j['code'] != 'Ok') return null;
      final routes = j['routes'];
      if (routes is! List || routes.isEmpty) return null;
      final r = routes.first;
      if (r is! Map<String, dynamic>) return null;
      final distance = (r['distance'] as num?)?.toDouble();
      final duration = (r['duration'] as num?)?.toDouble();
      if (distance == null || duration == null) return null;
      final geometry = r['geometry'];
      final coords = (geometry is Map) ? geometry['coordinates'] : null;
      final pts = <LatLng>[];
      if (coords is List) {
        for (final c in coords) {
          if (c is List && c.length >= 2) {
            final lng = (c[0] as num).toDouble();
            final lat = (c[1] as num).toDouble();
            pts.add(LatLng(lat, lng));
          }
        }
      }
      return RouteResult(
        distanceM: distance,
        durationS: duration,
        polyline: pts,
        provider: providerName,
        trafficAware: false,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<RouteResult?> route(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return null;
    final key = coordinateString(waypoints);
    final now = DateTime.now();
    final cached = _cache[key];
    if (cached != null && now.difference(cached.storedAt) < cacheTtl) {
      return cached.result;
    }
    try {
      final res = await _client
          .get(buildUri(waypoints), headers: {'User-Agent': userAgent})
          .timeout(timeout);
      if (res.statusCode != 200) return null;
      final parsed = parseResponse(utf8.decode(res.bodyBytes));
      if (parsed != null) _cache[key] = _CacheEntry(parsed, now);
      return parsed;
    } catch (_) {
      // 타임아웃·네트워크 오류·파싱 오류 → null (호출측이 "API 실패"로 표시)
      return null;
    }
  }

  void clearCache() => _cache.clear();
}

// ═══════════════════════════════════════════════════════════════════════
// Valhalla (FOSSGIS 공개 인스턴스) — 통행료 회피 + has_toll 검증
// ═══════════════════════════════════════════════════════════════════════

/// Google encoded polyline 디코더 (기본 precision 6 = 1e6, Valhalla shape 형식).
/// [precision] 5 를 넘기면 일반 Google polyline(1e5) 도 디코딩한다.
List<LatLng> decodePolyline6(String encoded, {int precision = 6}) {
  final factor = math.pow(10, precision).toDouble();
  final out = <LatLng>[];
  var index = 0, lat = 0, lng = 0;
  final len = encoded.length;
  int? next() {
    var result = 0, shift = 0, b = 0;
    do {
      if (index >= len) return null;
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < len) {
    final dLat = next();
    final dLng = next();
    if (dLat == null || dLng == null) break; // 손상된 문자열 → 디코딩된 점까지만
    lat += dLat;
    lng += dLng;
    out.add(LatLng(lat / factor, lng / factor));
  }
  return out;
}

/// Valhalla 공개 인스턴스 기반 구현.
class ValhallaRouteProvider implements RouteProvider {
  static const String routeUrl = 'https://valhalla1.openstreetmap.de/route';
  static const String userAgent = 'LuckyLottoFinder/1.0 (admin route research)';
  static const Duration cacheTtl = Duration(minutes: 10);
  static const Duration minInterval = Duration(seconds: 1);
  static const String providerName = 'valhalla-fossgis';

  /// true(기본): exclude_tolls + use_tolls=0 + use_ferry=0 / false: use_tolls=1 (전체 도로)
  final bool avoidTolls;
  final http.Client _client;
  final Duration timeout;
  final Map<String, _CacheEntry> _cache = {};

  /// 인스턴스 공통 스로틀 (공개 서버 fair-use: 앱 전체에서 1초 1요청)
  static DateTime? _lastRequestAt;
  static Future<void> _gate = Future.value();

  ValhallaRouteProvider({
    this.avoidTolls = true,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  /// 요청 body (순수 함수, 테스트 가능)
  static Map<String, dynamic> buildRequestBody(List<LatLng> waypoints,
      {required bool avoidTolls}) {
    final auto = avoidTolls
        ? <String, dynamic>{'use_tolls': 0.0, 'exclude_tolls': true, 'use_ferry': 0.0}
        : <String, dynamic>{'use_tolls': 1.0};
    return {
      'locations': [
        for (final p in waypoints)
          {
            'lat': double.parse(p.latitude.toStringAsFixed(6)),
            'lon': double.parse(p.longitude.toStringAsFixed(6)),
          }
      ],
      'costing': 'auto',
      'costing_options': {'auto': auto},
      'directions_options': {'units': 'kilometers'},
    };
  }

  static String cacheKey(List<LatLng> waypoints, bool avoidTolls) =>
      '${avoidTolls ? 'free' : 'all'}|${OsrmRouteProvider.coordinateString(waypoints)}';

  /// Valhalla /route JSON 파싱. length(km)→m, time(s). 실패 시 null.
  static RouteResult? parseResponse(String body, {required bool avoidTolls}) {
    try {
      final j = jsonDecode(body);
      if (j is! Map<String, dynamic>) return null;
      final trip = j['trip'];
      if (trip is! Map<String, dynamic>) return null;
      final status = trip['status'];
      if (status is num && status != 0) return null;
      final summary = trip['summary'];
      if (summary is! Map<String, dynamic>) return null;
      final lengthKm = (summary['length'] as num?)?.toDouble();
      final timeS = (summary['time'] as num?)?.toDouble();
      if (lengthKm == null || timeS == null) return null;
      final hasTollField = summary['has_toll'] is bool;
      bool? hasToll = hasTollField ? summary['has_toll'] as bool : null;

      final legs = trip['legs'];
      final pts = <LatLng>[];
      final legToll = <bool?>[];
      if (legs is List) {
        for (final leg in legs) {
          if (leg is! Map) continue;
          final ls = leg['summary'];
          bool? lt = (ls is Map && ls['has_toll'] is bool) ? ls['has_toll'] as bool : null;
          // 구간 요약에 has_toll 이 없으면 maneuvers[].toll 로 보조 판정
          if (lt == null) {
            final man = leg['maneuvers'];
            if (man is List && man.isNotEmpty) {
              lt = man.any((m) => m is Map && m['toll'] == true);
            }
          }
          legToll.add(lt);
          final shape = leg['shape'];
          if (shape is String && shape.isNotEmpty) {
            final dec = decodePolyline6(shape);
            // 구간 경계 중복점 제거
            if (pts.isNotEmpty && dec.isNotEmpty && pts.last == dec.first) {
              pts.addAll(dec.skip(1));
            } else {
              pts.addAll(dec);
            }
          }
        }
      }
      // 요약에 has_toll 이 없으면 모든 구간이 판정된 경우에만 구간값으로 검증
      var verified = hasTollField;
      if (!hasTollField && legToll.isNotEmpty && legToll.every((t) => t != null)) {
        hasToll = legToll.any((t) => t == true);
        verified = true;
      }
      return RouteResult(
        distanceM: lengthKm * 1000.0,
        durationS: timeS,
        polyline: pts,
        provider: providerName,
        trafficAware: false,
        hasToll: hasToll,
        tollAvoidRequested: avoidTolls,
        tollVerified: verified,
        legHasToll: legToll,
      );
    } catch (_) {
      return null;
    }
  }

  /// 직렬 스로틀: 직전 요청 이후 최소 [minInterval] 대기
  Future<void> _throttle() {
    final prev = _gate;
    final c = Completer<void>();
    _gate = c.future;
    return prev.then((_) async {
      final last = _lastRequestAt;
      if (last != null) {
        final wait = minInterval - DateTime.now().difference(last);
        if (wait > Duration.zero) await Future.delayed(wait);
      }
      _lastRequestAt = DateTime.now();
      c.complete();
    });
  }

  @override
  Future<RouteResult?> route(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return null;
    final key = cacheKey(waypoints, avoidTolls);
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.storedAt) < cacheTtl) {
      return cached.result;
    }
    try {
      await _throttle();
      final res = await _client
          .post(
            Uri.parse(routeUrl),
            headers: {
              'User-Agent': userAgent,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(buildRequestBody(waypoints, avoidTolls: avoidTolls)),
          )
          .timeout(timeout);
      if (res.statusCode != 200) return null;
      final parsed = parseResponse(utf8.decode(res.bodyBytes), avoidTolls: avoidTolls);
      if (parsed != null) _cache[key] = _CacheEntry(parsed, DateTime.now());
      return parsed;
    } catch (_) {
      // 타임아웃·네트워크·파싱 오류 → null (FallbackRouteProvider 가 OSRM 대체)
      return null;
    }
  }

  void clearCache() => _cache.clear();
}

/// 1차 제공자(Valhalla) 실패 시 OSRM 으로 대체하는 래퍼.
/// 대체 결과는 [RouteResult.fallbackUsed]=true, tollVerified=false 로 강등되어
/// 절대 "무료도로 확정"으로 표시되지 않는다.
class FallbackRouteProvider implements RouteProvider {
  final RouteProvider primary;
  final RouteProvider fallback;

  /// 대체 결과에 기록할 "통행료 회피 요청" 여부 (무료도로 모드면 true)
  final bool tollAvoidRequested;

  const FallbackRouteProvider({
    required this.primary,
    required this.fallback,
    required this.tollAvoidRequested,
  });

  @override
  Future<RouteResult?> route(List<LatLng> waypoints) async {
    final r = await primary.route(waypoints);
    if (r != null) return r;
    final f = await fallback.route(waypoints);
    return f?.asFallback(tollAvoidRequested: tollAvoidRequested);
  }
}
