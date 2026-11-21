// 본 브리핑 — 번호 세트 체크(흐림 · 취소선) · ★ 나의 번호 저장 / 내 위치 가까운 추천 명당
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app/widgets/briefing_nearby_picks.dart';
import 'package:flutter_app/widgets/briefing_set_marks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('체크하면 흐려지고 취소선 · 다시 열어도 기억 / ★ 누르면 나의 번호(my_lotto_numbers)에 저장 · 다시 누르면 빠짐', (t) async {
    SharedPreferences.setMockInitialValues({});
    Widget w() => MaterialApp(home: Scaffold(body: BriefingSetMarks(id: '1251:official:0', numbers: const [33, 1, 5, 12, 20, 41], child: const Text('세트'))));
    await t.pumpWidget(w());
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('set_strike_1251:official:0')), findsNothing);
    await t.tap(find.byKey(const ValueKey('set_check_1251:official:0')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('set_strike_1251:official:0')), findsOneWidget);
    expect(t.widget<Opacity>(find.ancestor(of: find.text('세트'), matching: find.byType(Opacity))).opacity, closeTo(0.32, 0.01));
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(w()); // 다시 열어도 체크 유지
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('set_strike_1251:official:0')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('set_star_1251:official:0')));
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('my_lotto_numbers')!;
    expect((jsonDecode(saved.single) as Map)['numbers'], [1, 5, 12, 20, 33, 41]);
    await t.tap(find.byKey(const ValueKey('set_star_1251:official:0')));
    await t.pumpAndSettle();
    expect(prefs.getStringList('my_lotto_numbers'), isEmpty);
  });

  test('가까운 추천 명당 — 같은 판매점은 한 줄(출처 합침) · 좌표 없는 곳 제외 · 거리 순', () {
    NearbyPick p(String c, double? lat, double? lng, String tag) => (code: c, name: c, address: '', lat: lat, lng: lng, tag: tag);
    final r = nearestPicks([
      p('far', 35.18, 129.07, '④ 이번 주 추천 1위'),
      p('near', 37.561, 126.971, '적중 예측 3위'),
      p('near', null, null, '제미나이 가설 명당'),
      p('nocoord', null, null, '적중 예측 9위'),
    ], 37.56, 126.97);
    expect(r.map((x) => x.$1.code), ['near', 'far']);
    expect(r.first.$1.tag, '적중 예측 3위 · 제미나이 가설 명당');
  });
}
