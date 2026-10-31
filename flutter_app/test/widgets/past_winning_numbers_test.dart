// 일반 모드 복권연구 — 지난 회차 번호 목록 · 최신 회차 당첨 판매점(크롤링 기록)
import 'package:flutter/material.dart';
import 'package:flutter_app/models/lottery_store.dart';
import 'package:flutter_app/screens/past_winning_numbers_screen.dart';
import 'package:flutter_app/widgets/latest_round_stores_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LotteryStore st(String code, String tier) => LotteryStore(
    dhlotteryCode: code, storeName: '판매점$code', address: '서울', region: '서울', lotteryType: 'lotto', round: 1248, prizeTier: tier);

void main() {
  testWidgets('로또 지난 회차 — 30회씩 · 더 보기로 이어 붙임', (tester) async {
    final offsets = <int>[];
    await tester.pumpWidget(MaterialApp(home: PastWinningNumbersScreen(type: 'lotto', loader: (_, off) async {
      offsets.add(off);
      final n = off == 0 ? kPastPageSize : 5;
      return [for (var i = 0; i < n; i++) PastRound(1248 - off - i, '2026-10-31', nums: const [1, 2, 3, 4, 5, 6], bonus: 7)];
    })));
    await tester.pumpAndSettle();
    expect(find.text('로또 6/45 지난 회차 번호'), findsOneWidget);
    expect(find.byKey(const ValueKey('past_row_1248')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('past_more')), 400);
    await tester.ensureVisible(find.byKey(const ValueKey('past_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('past_more')));
    await tester.pumpAndSettle();
    expect(offsets, [0, kPastPageSize]);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('past_row_1214')), 400);
    expect(find.byKey(const ValueKey('past_more')), findsNothing);
  });

  testWidgets('연금 지난 회차 — 회차 · 조 · 6자리 · 보너스', (tester) async {
    await tester.pumpWidget(MaterialApp(home: PastWinningNumbersScreen(type: 'pension', loader: (_, _) async =>
        const [PastRound(339, '2026-10-29', group: 3, number: '136515', bonusNo: '123456')])));
    await tester.pumpAndSettle();
    expect(find.text('339회'), findsOneWidget);
    expect(find.text('3조'), findsOneWidget);
    expect(find.text('각조'), findsOneWidget);
  });

  testWidgets('최신 회차 당첨 판매점 — 1등 전부 · 2등 5곳 + 더 보기 · ★', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: LatestRoundStoresCard(round: 1248,
        loader: (_) async => [st('A', 'first'), st('B', 'first'), for (var i = 0; i < 8; i++) st('S$i', 'second')])))));
    await tester.pumpAndSettle();
    expect(find.text('1248회 로또 당첨 판매점'), findsOneWidget);
    expect(find.text('1등 2곳'), findsOneWidget);
    expect(find.text('2등 8곳'), findsOneWidget);
    expect(find.byKey(const ValueKey('latest_store_S6')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('latest_stores_more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('latest_store_S6')), findsOneWidget);
    expect(find.byKey(const ValueKey('fav_star_A')), findsOneWidget);
  });
}
