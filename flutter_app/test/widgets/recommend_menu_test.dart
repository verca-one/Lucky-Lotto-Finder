// 추천 탭 메뉴 — 일반 모드: 엔진 도입 이전 메뉴만 (엔진 '추천번호' 없음), 관리자 모드: '추천번호' 추가
import 'package:flutter/material.dart';
import 'package:flutter_app/screens/recommend_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('일반 모드 번호 추천 메뉴 = 엔진 도입 이전 버전', () {
    expect(recommendNumberMenuFor(admin: false).map((m) => m.title).toList(), ['AI 조합번호 생성', '나만의 번호 생성', '번호별 의미']);
    expect(recommendNumberMenuFor(admin: false).map((m) => m.sub), isNot(contains('numbers')));
  });

  test('관리자 모드에만 엔진 추천번호', () {
    expect(recommendNumberMenuFor(admin: true).map((m) => m.title).toList(), ['AI 조합번호 생성', '나만의 번호 생성', '추천번호', '번호별 의미']);
  });

  for (final admin in [false, true]) {
    testWidgets('추천 탭 메뉴 — ${admin ? '관리자' : '일반'} 모드', (tester) async {
      SharedPreferences.setMockInitialValues({'isAdmin': admin});
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RecommendScreen())));
      await tester.pumpAndSettle();
      expect(find.text('추천번호'), admin ? findsOneWidget : findsNothing);
      expect(find.text('자리별 패턴 분석'), findsNothing);
      expect(find.text('구매예측'), findsNothing);
      expect(find.text('AI 조합번호 생성'), findsOneWidget);
      expect(find.text('나만의 번호 생성'), findsOneWidget);
      expect(find.text('번호별 의미'), findsOneWidget);
    });
  }
}
