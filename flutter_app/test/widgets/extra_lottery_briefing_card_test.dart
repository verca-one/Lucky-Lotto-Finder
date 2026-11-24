// 엔진 브리핑 상단 — 연금복권 · 스피또 요약 브리핑
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/pension_briefing.dart';
import 'package:flutter_app/widgets/extra_lottery_briefing_card.dart';
import 'package:flutter_app/widgets/speetto_briefing_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('연금은 제목만(누르면 내용) · 스피또는 출고율 90% 넘는 회차만', (tester) async {
    final p = PensionBriefing.fromPayload({
      'target_round': 339, 'draw_date': '2026-10-29',
      'engine': {'status': 'ok', 'tickets': [{'group': 3, 'number': '123456'}, {'group': 1, 'number': '654321'}]},
      'stores': {'stores': [{'name': '하당복권방'}, {'name': '목화휴게소'}]},
      'track': {'status': 'ok', 'tickets': [{'group': 2, 'number': '147599'}], 'used': []},
    });
    final s = SpeettoBriefing.fromPayload({'games': [], 'status': {'status': 'ok', 'snap_date': '2026-10-24', 'editions': [
      {'game': 'SP500', 'edition': 48, 'ship_rate': 58, 'rnk1_total': 5, 'rnk1_left': 3, 'index': 1.43,
        'sale_start': '2025-12-29T00:00:00+09:00'},
      {'game': 'SP2000', 'edition': 69, 'ship_rate': 99.2, 'rnk1_total': 10, 'rnk1_left': 1}]}});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ExtraLotteryBriefingCard(
        now: DateTime(2026, 10, 25, 10), pensionLoader: () async => p, speettoLoader: () async => s)))));
    await tester.pumpAndSettle();
    expect(find.text('이번 주 연금복권 339회 · 10/29(목) 추첨'), findsOneWidget);
    expect(find.text('이번 주 스피또'), findsOneWidget);
    // 스피또: 출고율 90% 넘는 회차만
    expect(find.text('스피또2000 69회 · 출고율 99% · 1등 1/10장 남음'), findsOneWidget);
    expect(find.textContaining('48회'), findsNothing);
    // 연금: 제목(회차 · 추첨일)만 → 누르면 내용
    expect(find.text('추천번호 3조 123456 외 1장'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('extra_pension')));
    await tester.pumpAndSettle();
    expect(find.text('추천번호 3조 123456 외 1장'), findsOneWidget);
    expect(find.text('명당 하당복권방 · 목화휴게소'), findsOneWidget);
    expect(find.text('연금 연구 화면 열기 ›'), findsOneWidget);
  });

  test('로또 주 기준 이번 주 / 다음 주', () {
    expect(lottoWeekSaturday(DateTime(2026, 10, 24, 15)), DateTime(2026, 10, 24));
    expect(lottoWeekSaturday(DateTime(2026, 10, 25, 9)), DateTime(2026, 10, 31));
    expect(isNextLottoWeek('2026-10-29', DateTime(2026, 10, 24, 15)), isTrue);
    expect(isNextLottoWeek('2026-10-29', DateTime(2026, 10, 25, 9)), isFalse);
  });

  testWidgets('다음 주 연금 카드 — 회색 · 다음 주 표기 · 초안 안내', (tester) async {
    final p = PensionBriefing.fromPayload({'target_round': 339, 'draw_date': '2026-10-29',
      'engine': {'status': 'waiting'}, 'stores': {'stores': []}, 'track': {'status': 'waiting'}});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ExtraLotteryBriefingCard(
        now: DateTime(2026, 10, 24, 15), pensionLoader: () async => p, speettoLoader: () async => null)))));
    await tester.pumpAndSettle();
    expect(find.text('다음 주 연금복권 339회 · 10/29(목) 추첨'), findsOneWidget);
    expect(find.text('스피또 브리핑 저장본 없음 (서버 매일 17시)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('extra_pension')));
    await tester.pumpAndSettle();
    expect(find.textContaining('이번 주 로또 추첨(10/24) 뒤 이번 주로 바뀝니다'), findsOneWidget);
    expect(find.textContaining('초안'), findsOneWidget);
  });
}
