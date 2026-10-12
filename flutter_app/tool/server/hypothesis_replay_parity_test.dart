// 서버 이관 동등성 검증 — 가설 순차 재현을 저장본과 같은 데이터 범위로 다시 실행해 요약 비교 (쓰기 없음)
//   flutter test tool/server/hypothesis_replay_parity_test.dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter_app/services/research/hypothesis_replay_engine.dart';
import 'package:flutter_app/services/research/research_runtime.dart';
import 'package:flutter_app/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'server_env.dart';

/// 키 순서와 무관한 비교용 (Postgres jsonb 는 키 순서를 바꿔 저장한다)
dynamic _canon(dynamic v) => v is Map
    ? {for (final k in (v.keys.map((e) => '$e').toList()..sort())) k: _canon(v[k])}
    : v is List
        ? [for (final x in v) _canon(x)]
        : v;
String _c(dynamic v) => jsonEncode(_canon(v));

void main() {
  test('가설 순차 재현 서버 계산 = 저장된 요약', () async {
    await initServerSupabase();
    expect(ResearchRuntime.serverWriter, isFalse);
    final engine = HypothesisReplayEngine.instance;
    final stored = await engine.loadLatest();
    expect(stored, isNotNull, reason: '저장된 재현 결과 없음');
    final end = (stored!['end_round'] as num).toInt();
    final all = (await SupabaseService.getAllWinningNumbers()).where((d) => d.round <= end).toList();
    final res = Map<String, dynamic>.from(await engine.run(all))..remove('round_logs');
    const skip = {'round_logs_count', 'round_logs_persisted', 'round_logs_existing', 'round_logs_error', 'generated_at', 'elapsed_ms'};
    final keys = stored.keys.where((k) => !skip.contains(k)).toList()..sort();
    final diff = [for (final k in keys) if (_c(stored[k]) != _c(res[k])) k];
    // ignore: avoid_print
    print('end_round=$end · 비교 항목 ${keys.length}개 · 다른 항목: $diff');
    for (final k in diff.take(4)) {
      // ignore: avoid_print
      print('  $k stored=${jsonEncode(stored[k]).substring(0, min(220, jsonEncode(stored[k]).length))}');
      // ignore: avoid_print
      print('  $k server=${jsonEncode(res[k]).substring(0, min(220, jsonEncode(res[k]).length))}');
    }
    // 결정성: 같은 입력으로 한 번 더 실행해 서버 결과끼리 비교
    final res2 = Map<String, dynamic>.from(await engine.run(all, force: true))..remove('round_logs');
    final nondet = [for (final k in keys) if (_c(res[k]) != _c(res2[k])) k];
    // ignore: avoid_print
    print('재실행 차이: $nondet');
    expect(nondet, isEmpty);
    expect(diff, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
