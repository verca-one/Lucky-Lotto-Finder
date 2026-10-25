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
}
