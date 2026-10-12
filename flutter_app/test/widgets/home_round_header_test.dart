// 홈 상단 헤더 — 회차·추첨일·업데이트 시각 표시
import 'package:flutter/material.dart';
import 'package:flutter_app/widgets/home_round_header.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('추첨일 계산 (로또 토요일, 연금 목요일)', () {
    expect(lottoDrawDateFor(1), DateTime(2002, 12, 7));
    expect(lottoDrawDateFor(1245), DateTime(2026, 10, 10));
    expect(lottoDrawDateFor(1245).weekday, DateTime.saturday);
    expect(pensionDrawDateFor(1), DateTime(2020, 5, 7));
    expect(pensionDrawDateFor(336), DateTime(2026, 10, 8));
    expect(pensionDrawDateFor(336).weekday, DateTime.thursday);
  });

  test('DB 추첨일 문자열 해석', () {
    expect(parseDrawDate('2026-10-10'), DateTime(2026, 10, 10));
    expect(parseDrawDate('2026.10.10'), DateTime(2026, 10, 10));
    expect(parseDrawDate('20261010'), DateTime(2026, 10, 10));
    expect(parseDrawDate(''), isNull);
    expect(parseDrawDate(null), isNull);
    expect(formatDrawDate(DateTime(2026, 10, 10)), '2026.10.10 (토)');
    expect(formatUpdateTime(DateTime(2026, 10, 11, 2, 49)), '10/11 02:49');
  });

  test('종류별 최신 업데이트 시각', () {
    final m = latestUpdateTimes([
      {'lottery_type': 'lotto', 'completed_at': '2026-10-10T17:49:00Z'},
      {'lottery_type': 'lotto', 'completed_at': '2026-10-03T17:49:00Z'},
      {'lottery_type': 'speeto', 'completed_at': 'bad'},
      {'lottery_type': '', 'completed_at': '2026-10-10T17:49:00Z'},
    ]);
    expect(m.keys, ['lotto']);
    expect(m['lotto'], DateTime.parse('2026-10-10T17:49:00Z').toLocal());
  });

  testWidgets('회차·추첨일·업데이트가 각 타일에 표시', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 330,
          child: HomeRoundHeader(
            lottoRound: 1245,
            pensionRound: 336,
            updates: {
              'lotto': DateTime(2026, 10, 11, 2, 49),
              'speeto': DateTime(2026, 10, 10, 3, 50),
            },
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    final lotto = find.byKey(const ValueKey('header_lotto'));
    final pension = find.byKey(const ValueKey('header_pension'));
    expect(find.descendant(of: lotto, matching: find.text('1245')), findsOneWidget);
    expect(find.descendant(of: lotto, matching: find.text('2026.10.10 (토) 추첨')), findsOneWidget);
    expect(find.descendant(of: lotto, matching: find.text('10/11 02:49 업데이트')), findsOneWidget);
    expect(find.descendant(of: pension, matching: find.text('336')), findsOneWidget);
    expect(find.descendant(of: pension, matching: find.text('2026.10.08 (목) 추첨')), findsOneWidget);
    expect(find.descendant(of: pension, matching: find.text('업데이트 기록 없음')), findsOneWidget);
    expect(find.text('10/10 03:50 업데이트'), findsOneWidget);
  });
}
