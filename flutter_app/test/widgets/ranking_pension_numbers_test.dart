// 홈 로또 상자 아래 연금복권 최신 당첨번호 상자
import 'package:flutter/material.dart';
import 'package:flutter_app/widgets/ranking_pension_numbers.dart';
import 'package:flutter_app/widgets/winning_number_boxes.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime kst(int d, int h, int m) => DateTime.utc(2026, 10, d, h, m).subtract(const Duration(hours: 9));

void main() {
  test('발표 당일(목) 단계 — 0시 추첨 예정 · 19:05 뒤 번호 수집 전 · 수집되면 없음', () {
    const last = PensionLatestWinning(338, 2, '060727', '293160', '2026-10-22');
    const now = PensionLatestWinning(339, 4, '104462', '123456', '2026-10-29');
    expect(pendingPensionStage(last, kst(28, 23, 59)), isNull); // 수요일 = 지난 회차 색
    final a = pendingPensionStage(last, kst(29, 0, 0))!;
    expect((a.$1, a.$3), (339, '추첨 예정'));
    expect(pendingPensionStage(last, kst(29, 19, 5))!.$3, '번호 수집 전');
    expect(pendingPensionStage(now, kst(29, 22, 0)), isNull);
    expect(pendingPensionStage(last, kst(31, 12, 1)), isNull); // 60시간 지나면 지난 번호
    expect(needsNewPensionNumbers(last, kst(29, 19, 0)), isFalse);
    expect(needsNewPensionNumbers(last, kst(29, 21, 30)), isTrue);
    expect(needsNewPensionNumbers(now, kst(29, 21, 30)), isFalse);
  });

  testWidgets('평소 — 회차 · 1등 조 + 6자리 · 보너스 각조 6자리', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RankingPensionNumbers(
      clock: () => kst(28, 12, 0),
      loader: () async => const PensionLatestWinning(338, 2, '060727', '293160', '2026-10-22'),
    ))));
    await tester.pump();
    expect(find.text('연금복권720+ 338회 당첨번호'), findsOneWidget);
    expect(find.text('2026.10.22 추첨'), findsOneWidget);
    expect(find.text('2조'), findsOneWidget);
    expect(find.text('각조'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('목 21:30 · 아직 338회면 회색 → 339회 들어오면 바로 색 + onNewRound', (tester) async {
    var w = const PensionLatestWinning(338, 2, '060727', '293160', '2026-10-22');
    var called = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RankingPensionNumbers(
      pollEvery: const Duration(seconds: 1),
      clock: () => kst(29, 21, 30),
      onNewRound: () => called++,
      loader: () async => w,
    ))));
    await tester.pump();
    expect(find.byKey(const ValueKey('ranking_pension_pending')), findsOneWidget);
    expect(find.text('번호 수집 전'), findsOneWidget);
    w = const PensionLatestWinning(339, 4, '104462', '123456', '2026-10-29');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('ranking_pension_numbers')), findsOneWidget);
    expect(find.text('연금복권720+ 339회 당첨번호'), findsOneWidget);
    expect(called, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
