// 추천 탭 — '추천번호' 메뉴는 모드 공통. 일반 모드는 엔진 없는 랜덤 추천, 관리자 모드는 엔진 추천번호
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_app/screens/random_recommend_content.dart';
import 'package:flutter_app/screens/recommend_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('번호 추천 메뉴 (모드 공통)', () {
    for (final admin in [false, true]) {
      expect(recommendNumberMenuFor(admin: admin).map((m) => m.title).toList(),
          ['AI 조합번호 생성', '나만의 번호 생성', '추천번호', '번호별 의미']);
    }
  });

  test('랜덤 추천: 5세트, 세트마다 1~45 서로 다른 6개, 오름차순', () {
    final sets = randomRecommendSets(rng: Random(7));
    expect(sets.length, 5);
    for (final s in sets) {
      expect(s.length, 6);
      expect(s.toSet().length, 6);
      expect(s.every((n) => n >= 1 && n <= 45), isTrue);
      expect(List.of(s)..sort(), s);
    }
  });

  for (final admin in [false, true]) {
    testWidgets('추천 탭 메뉴 — ${admin ? '관리자' : '일반'} 모드', (tester) async {
      SharedPreferences.setMockInitialValues({'isAdmin': admin});
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RecommendScreen())));
      await tester.pumpAndSettle();
      expect(find.text('추천번호'), findsOneWidget);
      expect(find.text('자리별 패턴 분석'), findsNothing);
      expect(find.text('구매예측'), findsNothing);
    });
  }

  testWidgets('일반 모드 추천번호 = 엔진 없는 랜덤 5세트', (tester) async {
    SharedPreferences.setMockInitialValues({'isAdmin': false});
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RecommendScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('추천번호'));
    await tester.pumpAndSettle();
    expect(find.byType(RandomRecommendContent), findsOneWidget);
    expect(find.byKey(const ValueKey('random_set_4')), findsOneWidget);
    expect(find.textContaining('fr-1.0'), findsNothing);
    expect(find.textContaining('엔진'), findsNothing);
  });
}
