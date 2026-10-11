// 검증 스크립트용 Supabase REST 클라이언트 (dart:io만 사용)
// 키는 앱과 동일한 anon 키를 lib/screens/splash_screen.dart에서 읽거나
// 환경변수 SUPABASE_URL / SUPABASE_ANON_KEY로 덮어쓸 수 있습니다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/models/lotto_winning_number.dart';

class RpaRest {
  final String url;
  final String key;
  final _http = HttpClient();

  RpaRest._(this.url, this.key);

  factory RpaRest.fromApp() {
    final envUrl = Platform.environment['SUPABASE_URL'];
    final envKey = Platform.environment['SUPABASE_ANON_KEY'];
    if (envUrl != null && envKey != null) return RpaRest._(envUrl, envKey);
    final src = File('lib/screens/splash_screen.dart').readAsStringSync();
    final u = RegExp(r"url:\s*'([^']+)'").firstMatch(src)!.group(1)!;
    final k = RegExp(r"anonKey:\s*'([^']+)'").firstMatch(src)!.group(1)!;
    return RpaRest._(u, k);
  }

  Future<dynamic> _send(String method, String pathAndQuery,
      {Object? body, Map<String, String> headers = const {}}) async {
    final req = await _http.openUrl(method, Uri.parse('$url/rest/v1/$pathAndQuery'));
    req.headers.set('apikey', key);
    req.headers.set('Authorization', 'Bearer $key');
    req.headers.contentType = ContentType.json;
    headers.forEach(req.headers.set);
    if (body != null) req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) {
      throw RpaRestError(res.statusCode, text);
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<List<Map<String, dynamic>>> get(String pathAndQuery) async {
    final r = await _send('GET', pathAndQuery);
    return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<dynamic> post(String table, Object body, {String? onConflict, bool upsert = false}) =>
      _send('POST', onConflict != null ? '$table?on_conflict=$onConflict' : table,
          body: body,
          headers: {
            'Prefer': upsert
                ? 'resolution=merge-duplicates,return=representation'
                : 'return=representation',
          });

  Future<List<LottoWinningNumber>> winningNumbers() async {
    final out = <LottoWinningNumber>[];
    for (int offset = 0;; offset += 1000) {
      final rows = await _send('GET',
          'lotto_winning_numbers?select=round,draw_date,num1,num2,num3,num4,num5,num6,bonus&order=round.asc',
          headers: {'Range': '$offset-${offset + 999}'}) as List;
      for (final j in rows) {
        out.add(LottoWinningNumber(
          drawDate: j['draw_date']?.toString() ?? '',
          round: j['round'] as int,
          numbers: [j['num1'], j['num2'], j['num3'], j['num4'], j['num5'], j['num6']]
              .cast<int>(),
          bonusNumber: j['bonus'] as int? ?? 0,
        ));
      }
      if (rows.length < 1000) break;
    }
    return out;
  }

  void close() => _http.close(force: true);
}

class RpaRestError implements Exception {
  final int status;
  final String body;
  RpaRestError(this.status, this.body);
  @override
  String toString() => 'HTTP $status: $body';
}
