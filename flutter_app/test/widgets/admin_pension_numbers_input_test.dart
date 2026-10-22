// 관리자 연금복권 당첨번호 입력 — 회차·추첨일 자동 · 빈 회차 · 덮어쓰기 확인
import 'package:flutter/material.dart';
import 'package:flutter_app/screens/admin_pension_numbers_input_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('추첨일 · 최신 추첨 회차 (목 20시 KST 기준)', () {
    expect(ymd(pensionDrawDate(314)), '2026-05-07');
    expect(ymd(pensionDrawDate(338)), '2026-10-22');
    expect(pensionLatestDrawn(DateTime(2026, 10, 22, 15)), 337);
    expect(pensionLatestDrawn(DateTime(2026, 10, 22, 21)), 338);
    expect(pensionLatestDrawn(DateTime(2026, 10, 25, 9)), 338);
  });

  testWidgets('빈 최신 회차부터 입력 → 저장 후 다음 빈 회차 · 기존 회차는 확인 후 덮어쓰기', (tester) async {
    final db = <int, PensionRow>{314: const PensionRow(314, 2, '060727', '293160', '2026-05-07')};
    PensionNumbersStore.loadAll = () async => db.values.toList();
    PensionNumbersStore.save = (r) async => db[r.round] = r;
    await tester.pumpWidget(MaterialApp(home: AdminPensionNumbersInputScreen(now: DateTime(2026, 10, 22, 15))));
    await tester.pumpAndSettle();
    expect(find.text('입력 1 / 337회'), findsOneWidget);
    expect(find.text('빈 회차 336개 (최신부터)'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('pension_round'))).controller!.text, '337');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('pension_date'))).controller!.text, '2026-10-15');

    await tester.tap(find.byKey(const ValueKey('pension_group_3')));
    await tester.enterText(find.byKey(const ValueKey('pension_number')), '123456');
    await tester.enterText(find.byKey(const ValueKey('pension_bonus')), '654321');
    await tester.ensureVisible(find.byKey(const ValueKey('pension_save')));
    await tester.tap(find.byKey(const ValueKey('pension_save')));
    await tester.pumpAndSettle();
    expect(db[337]!.group, 3);
    expect(db[337]!.number, '123456');
    expect(db[337]!.drawDate, '2026-10-15');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('pension_round'))).controller!.text, '336');

    // 기존 314회 덮어쓰기 → 확인창
    await tester.enterText(find.byKey(const ValueKey('pension_round')), '314');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('pension_number'))).controller!.text, '060727');
    await tester.enterText(find.byKey(const ValueKey('pension_number')), '111111');
    await tester.ensureVisible(find.byKey(const ValueKey('pension_save')));
    await tester.tap(find.byKey(const ValueKey('pension_save')));
    await tester.pumpAndSettle();
    expect(find.text('314회 이미 저장됨'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(db[314]!.number, '060727');
  });
}
