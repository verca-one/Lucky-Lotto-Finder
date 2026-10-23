// 엔진 브리핑 상단 — 연금복권 · 스피또 요약 브리핑
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/pension_briefing.dart';
import 'package:flutter_app/widgets/extra_lottery_briefing_card.dart';
import 'package:flutter_app/widgets/speetto_briefing_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('연금 · 스피또 요약 — 추천번호 · 명당 · 남은 1등 지수 1위', (tester) async {
    final p = PensionBriefing.fromPayload({
      'target_round': 339, 'draw_date': '2026-10-29',
      'engine': {'status': 'ok', 'tickets': [{'group': 3, 'number': '123456'}, {'group': 1, 'number': '654321'}]},
      'stores': {'stores': [{'name': '하당복권방'}, {'name': '목화휴게소'}]},
      'track': {'status': 'ok', 'tickets': [{'group': 2, 'number': '147599'}], 'used': []},
    });
    final s = SpeettoBriefing.fromPayload({'games': [], 'status': {'status': 'ok', 'snap_date': '2026-10-24', 'editions': [
      {'game': 'SP500', 'edition': 48, 'ship_rate': 58, 'rnk1_total': 5, 'rnk1_left': 3, 'index': 1.43,
        'sale_start': '2025-12-29T00:00:00+09:00'}]}});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ExtraLotteryBriefingCard(
        pensionLoader: () async => p, speettoLoader: () async => s)))));
    await tester.pumpAndSettle();
    expect(find.text('이번 주 연금복권 339회 · 10/29(목) 추첨'), findsOneWidget);
    expect(find.text('이번 주 스피또'), findsOneWidget);
    expect(find.text('판매 중 · 스피또500 48회 (12/29 출시)'), findsOneWidget);
    expect(find.text('추천번호 3조 123456 외 1장'), findsOneWidget);
    expect(find.text('명당 하당복권방 · 목화휴게소'), findsOneWidget);
    expect(find.textContaining('남은 1등 지수 1위 스피또500 48회 · 출고율 58% · 1등 3/5장 남음'), findsOneWidget);
    expect(find.textContaining('예전 기록 정리 필요'), findsOneWidget);
  });
}
