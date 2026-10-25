// 홈 랭킹 위 최신 로또 당첨번호
import 'package:flutter/material.dart';
import 'package:flutter_app/models/lotto_winning_number.dart';
import 'package:flutter_app/widgets/ranking_lotto_numbers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('최신 회차 · 추첨일 · 번호 6개(작은 순) + 보너스', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RankingLottoNumbers(loader: () async =>
        LottoWinningNumber(drawDate: '2026-10-24', round: 1247, numbers: [45, 8, 21, 14, 42, 22], bonusNumber: 24)))));
    await tester.pumpAndSettle();
    expect(find.text('로또 1247회 당첨번호'), findsOneWidget);
    expect(find.text('2026.10.24 추첨'), findsOneWidget);
    for (final n in ['8', '14', '21', '22', '42', '45', '24', '+']) {
      expect(find.text(n), findsOneWidget, reason: n);
    }
    expect(tester.getTopLeft(find.text('8')).dx < tester.getTopLeft(find.text('45')).dx, isTrue);
  });

  testWidgets('당첨번호 없으면 아무것도 안 보임', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RankingLottoNumbers(loader: () async => null))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ranking_lotto_numbers')), findsNothing);
  });

  test('새 번호 기다림 — 토 20:35 KST 뒤 36시간 안 · 보이는 번호가 지난주면 true', () {
    final last = LottoWinningNumber(drawDate: '2026-10-17', round: 1246, numbers: [1, 2, 3, 4, 5, 6], bonusNumber: 7);
    final now = LottoWinningNumber(drawDate: '2026-10-24', round: 1247, numbers: [1, 2, 3, 4, 5, 6], bonusNumber: 7);
    DateTime kst(int d, int h, int m) => DateTime.utc(2026, 10, d, h, m).subtract(const Duration(hours: 9));
    expect(needsNewLottoNumbers(last, kst(24, 20, 30)), isFalse); // 추첨 전
    expect(needsNewLottoNumbers(last, kst(24, 20, 40)), isTrue);
    expect(needsNewLottoNumbers(last, kst(25, 10, 0)), isTrue);
    expect(needsNewLottoNumbers(now, kst(24, 21, 0)), isFalse); // 이미 반영
    expect(needsNewLottoNumbers(last, kst(26, 9, 0)), isFalse); // 36시간 지나면 그만
  });

  testWidgets('추첨 뒤 새 회차가 들어오면 바로 바뀌고 onNewRound', (tester) async {
    var round = 1246;
    var called = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RankingLottoNumbers(
      pollEvery: const Duration(seconds: 1),
      clock: () => DateTime.utc(2026, 10, 24, 12, 0), // 토 21:00 KST
      onNewRound: () => called++,
      loader: () async => LottoWinningNumber(drawDate: round == 1246 ? '2026-10-17' : '2026-10-24', round: round,
          numbers: [1, 2, 3, 4, 5, 6], bonusNumber: 7),
    ))));
    await tester.pump();
    expect(find.text('로또 1246회 당첨번호'), findsOneWidget);
    round = 1247;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('로또 1247회 당첨번호'), findsOneWidget);
    expect(called, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
