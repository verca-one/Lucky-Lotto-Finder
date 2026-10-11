// 경로 기반 추천 — 지오코딩 서비스 (관리자 전용 연구 기능)
//
// ── 사용 API: Nominatim (OpenStreetMap) ────────────────────────────────
//   https://nominatim.openstreetmap.org/search
//     ?q=...&format=json&limit=5&countrycodes=kr&accept-language=ko
//
// ── 이용 정책 (Nominatim Usage Policy, 반드시 준수) ─────────────────────
//   https://operations.osmfoundation.org/policies/nominatim/
//   * 최대 1 req/s (절대 초과 금지) → [_minInterval] 스로틀.
//   * 식별 가능한 User-Agent 필수 → 'LuckyLottoFinder/1.0 (admin route research)'.
//   * 자동완성(타이핑마다 호출) 금지 → UI는 "검색" 버튼 또는 submit 시에만 호출.
//   * 결과 캐시 권장 → 동일 질의는 메모리 캐시 재사용.
//   * 대량·벌크 지오코딩 금지. 비용 0원, API 키 불필요.
//
// 기존 크롤링 시스템과 무관한 독립 모듈이며 DB에 쓰지 않는다.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class GeoPlace {
  /// 짧은 이름 (name 필드, 없으면 display_name 앞부분)
  final String name;

  /// 전체 주소 (display_name)
  final String address;
  final LatLng point;

  const GeoPlace({required this.name, required this.address, required this.point});

  @override
  String toString() => 'GeoPlace($name, ${point.latitude}, ${point.longitude})';
}

class GeocodingException implements Exception {
  final String message;
  GeocodingException(this.message);
  @override
  String toString() => 'GeocodingException: $message';
}

abstract class GeocodingService {
  Future<List<GeoPlace>> search(String query);
}

class NominatimGeocodingService implements GeocodingService {
  static const String userAgent =
      'LuckyLottoFinder/1.0 (admin route research)';
  static const Duration _minInterval = Duration(seconds: 1);

  final http.Client _client;
  final Duration timeout;
  final Map<String, List<GeoPlace>> _cache = {};
  DateTime? _lastRequestAt;

  /// 동시 호출이 몰려도 1 req/s 를 지키기 위한 직렬화 락.
  Future<void> _chain = Future.value();

  NominatimGeocodingService(
      {http.Client? client, this.timeout = const Duration(seconds: 12)})
      : _client = client ?? http.Client();

  static Uri buildUri(String query) => Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': query,
          'format': 'json',
          'limit': '5',
          'countrycodes': 'kr',
          'accept-language': 'ko',
        },
      );

  static List<GeoPlace> parseResponse(String body) {
    final j = jsonDecode(body);
    if (j is! List) return const [];
    final out = <GeoPlace>[];
    for (final e in j) {
      if (e is! Map) continue;
      final lat = double.tryParse('${e['lat']}');
      final lon = double.tryParse('${e['lon']}');
      if (lat == null || lon == null) continue;
      final display = (e['display_name'] ?? '').toString();
      var name = (e['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        name = display.split(',').first.trim();
      }
      if (name.isEmpty) name = '$lat, $lon';
      out.add(GeoPlace(name: name, address: display, point: LatLng(lat, lon)));
    }
    return out;
  }

  @override
  Future<List<GeoPlace>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final cached = _cache[q];
    if (cached != null) return cached;

    // 직렬화 + 1 req/s 스로틀
    final completer = Completer<List<GeoPlace>>();
    _chain = _chain.then((_) async {
      try {
        final last = _lastRequestAt;
        if (last != null) {
          final wait = _minInterval - DateTime.now().difference(last);
          if (wait > Duration.zero) await Future.delayed(wait);
        }
        _lastRequestAt = DateTime.now();
        final res = await _client
            .get(buildUri(q), headers: {'User-Agent': userAgent})
            .timeout(timeout);
        if (res.statusCode != 200) {
          throw GeocodingException('Nominatim HTTP ${res.statusCode}');
        }
        final list = parseResponse(utf8.decode(res.bodyBytes));
        _cache[q] = list;
        completer.complete(list);
      } on GeocodingException catch (e) {
        completer.completeError(e);
      } on TimeoutException {
        completer.completeError(GeocodingException('지오코딩 응답 시간 초과(12초)'));
      } catch (e) {
        completer.completeError(GeocodingException('네트워크 오류: $e'));
      }
    });
    return completer.future;
  }
}
