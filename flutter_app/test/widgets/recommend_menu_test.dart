// 추천 탭 메뉴 — 일반·관리자 모드 모두 '추천번호' 표시, '자리별 패턴 분석'·'구매예측' 미표시
import 'package:flutter/material.dart';
import 'package:flutter_app/screens/recommend_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('번호 추천 메뉴 목록 (모드 무관)', () {
    expect(kRecommendNumberMenu.map((m) => m.title).toList(), ['AI 조합번호 생성', '나만의 번호 생성', '추천번호', '번호별 의미']);
    expect(kRecommendNumberMenu.map((m) => m.sub), isNot(contains('purchase')));
    expect(kRecommendNumberMenu.map((m) => m.title), isNot(contains('자리별 패턴 분석')));
    expect(kRecommendNumberMenu.map((m) => m.title), isNot(contains('구매예측')));
  });

  for (final admin in [false, true]) {
    testWidgets('추천 탭 메뉴 — ${admin ? '관리자' : '일반'} 모드', (tester) async {
      SharedPreferences.setMockInitialValues({'isAdmin': admin});
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RecommendScreen())));
      await tester.pump();
      expect(find.text('추천번호'), findsOneWidget);
      expect(find.text('자리별 패턴 분석'), findsNothing);
      expect(find.text('구매예측'), findsNothing);
      expect(find.text('AI 조합번호 생성'), findsOneWidget);
      expect(find.text('번호별 의미'), findsOneWidget);
    });
  }
}
