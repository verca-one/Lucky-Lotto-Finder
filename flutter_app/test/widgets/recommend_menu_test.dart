// 복권연구 탭 — 예전 번호 추천 메뉴 대신 행운 게임 6개 · 게임 규칙 점검
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_app/models/lotto_winning_number.dart';
import 'package:flutter_app/screens/lucky_games_screen.dart';
import 'package:flutter_app/screens/random_recommend_content.dart';
import 'package:flutter_app/screens/recommend_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

  testWidgets('복권연구 — 게임 6개 · 예전 메뉴 없음', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RecommendScreen())));
    await tester.pumpAndSettle();
    for (final t in ['로또 공 뽑기', '긁는 복권', '번호 맞히기', '행운 룰렛', '모의 추첨', '오늘의 운세 번호']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('추천번호'), findsNothing);
    expect(find.text('AI 조합번호 생성'), findsNothing);
  });

  test('긁는 복권 — 6칸 · 당첨이면 같은 그림 3개, 꽝이면 같은 그림 2개까지', () {
    final rng = Random(3);
    var wins = 0;
    for (var i = 0; i < 300; i++) {
      final c = scratchCells(rng);
      expect(c.length, 6);
      if (scratchWinner(c) != null) wins++;
    }
    expect(wins, inInclusiveRange(60, 140)); // 약 1/3
  });

  test('모의 추첨 — 1,000번 합계 · 대부분 꽝', () {
    final r = simulateDraws([1, 2, 3, 4, 5, 6], 1000, Random(1));
    expect(r.values.fold<int>(0, (a, b) => a + b), 1000);
    expect(r[0]!, greaterThan(950)); // 5등 이상 약 2.4%
  });

  test('오늘의 운세 — 같은 생일 · 같은 날이면 늘 같음, 행운 번호는 서로 다른 6개', () {
    final a = fortuneFor(DateTime(1985, 3, 7), DateTime(2026, 11, 25));
    expect('${fortuneFor(DateTime(1985, 3, 7), DateTime(2026, 11, 25))}', '$a');
    expect(a.$2.toSet().length, 6);
  });

  testWidgets('번호 맞히기 — 6개 고르고 펼치면 맞힌 개수', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: GuessGame(
        loader: () async => LottoWinningNumber(drawDate: '2026-11-21', round: 1251, numbers: [14, 18, 19, 29, 40, 45], bonusNumber: 1))))));
    for (final n in [14, 18, 19, 2, 3, 4]) {
      await tester.ensureVisible(find.byKey(ValueKey('pick_$n')));
      await tester.tap(find.byKey(ValueKey('pick_$n')));
      await tester.pump();
    }
    await tester.ensureVisible(find.byKey(const ValueKey('guess_go')));
    await tester.tap(find.byKey(const ValueKey('guess_go')));
    await tester.pumpAndSettle();
    expect(find.text('1251회 (2026-11-21) 당첨번호'), findsOneWidget);
    expect(find.text('🎉 3개 맞힘 — 그 회차였다면 5등!'), findsOneWidget);
  });
}
