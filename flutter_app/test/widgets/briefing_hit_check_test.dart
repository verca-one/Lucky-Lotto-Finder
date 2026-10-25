// 브리핑 추천 당첨확인 — 등수 계산 · 등록본 고르기 · 목록 페이지 번호 · 회차별 당첨내역
import 'package:flutter/material.dart';
import 'package:flutter_app/screens/admin_briefing_hit_check_screen.dart';
import 'package:flutter_app/services/research/briefing_hit_check.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> reg(String algo, String ver, int t, List<List<int>> sets, [String at = '2026-10-20']) =>
    {'algorithm': algo, 'version': ver, 'target_round': t, 'sets': sets, 'generated_at': at};

void main() {
  test('등수 — 6개 1등 · 5개+보너스 2등 · 5개 3등 · 4개 4등 · 3개 5등 · 2개 낙첨', () {
    const win = [1, 2, 3, 4, 5, 6];
    expect(lottoRank([1, 2, 3, 4, 5, 6], win, 7), 1);
    expect(lottoRank([1, 2, 3, 4, 5, 7], win, 7), 2);
    expect(lottoRank([1, 2, 3, 4, 5, 8], win, 7), 3);
    expect(lottoRank([1, 2, 3, 4, 9, 8], win, 7), 4);
    expect(lottoRank([1, 2, 3, 10, 9, 8], win, 7), 5);
    expect(lottoRank([1, 2, 7, 10, 9, 8], win, 7), isNull);
  });

  test('회차별 결과 — 구매예측 최신 버전 · 제미나이 토요일 최종본 우선 · 당첨금 합계', () {
    final regs = [
      reg('official_final', 'fr-1.0', 1247, [[8, 14, 21, 30, 31, 32], [1, 2, 3, 4, 5, 6]]),
      reg('purchase_prediction', 'pp-0.2', 1247, [[8, 14, 21, 22, 42, 45]]),
      reg('purchase_prediction', 'pp-0.3', 1247, [[8, 14, 21, 22, 1, 2]]),
      reg('hypothesis_track', 'ht-1.0', 1247, [[8, 14, 21, 22, 42, 45]], '2026-10-22'),
      reg('hypothesis_track', 'ht-1.0-sat', 1247, [[8, 14, 21, 22, 42, 24]], '2026-10-24'),
      reg('number_engine', '2.1', 1247, [[1, 2, 3, 4, 5, 6]]), // 브리핑 아님 → 제외
      reg('official_final', 'fr-1.0', 1248, [[1, 2, 3, 4, 5, 6]]),
    ];
    final rounds = buildHitRounds(regs, {1247: ([8, 14, 21, 22, 42, 45], 24, '2026-10-24')},
        {1247: {1: 3637439250, 2: 65539446, 3: 1625853, 4: 50000, 5: 5000}});
    expect(rounds.map((r) => r.round), [1248, 1247]);
    expect(rounds.first.drawn, isFalse);
    final r = rounds[1];
    final g = {for (final x in r.groups) x.def.key: x};
    expect(g['official']!.sets.map((s) => s.rank), [5, null]);
    expect(g['popularity']!.registered, isFalse);
    expect(g['purchase']!.version, 'pp-0.3');
    expect(g['purchase']!.sets.single.rank, 4);
    expect(g['hypothesis']!.version, 'ht-1.0-sat');
    expect(g['hypothesis']!.sets.single.rank, 2);
    expect(r.bestRank, 2);
    expect(r.rankCounts, {5: 1, 4: 1, 2: 1});
    expect(r.prizeTotal, (65539446 + 50000 + 5000, true));
    expect(hitSummary(r), '당첨 3세트 (2등 1 · 4등 1 · 5등 1) · 65,594,446원');
  });

  testWidgets('목록 — 페이지 번호로 넘기고, 회차를 누르면 당첨내역 (좌우 회차 이동 · n / 전체)', (tester) async {
    final regs = [
      for (var t = 1235; t <= 1247; t++) reg('official_final', 'fr-1.0', t, [[1, 2, 3, 4, 5, 6], [7, 8, 9, 10, 11, 12]]),
    ];
    final wins = {for (var t = 1235; t <= 1247; t++) t: ([1, 2, 3, 40, 41, 42], 43, '2026-10-24')};
    final rounds = buildHitRounds(regs, wins, const {});
    await tester.pumpWidget(MaterialApp(home: AdminBriefingHitCheckScreen(loader: () async => rounds)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hit_round_1247')), findsOneWidget);
    expect(find.byKey(const ValueKey('hit_round_1237')), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('hit_page_2')), 300);
    await tester.tap(find.byKey(const ValueKey('hit_page_2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hit_round_1237')), findsOneWidget);
    expect(find.byKey(const ValueKey('hit_round_1247')), findsNothing);
    expect(find.textContaining('당첨 1세트 (5등 1) · 5,000원'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('hit_round_1237')));
    await tester.pumpAndSettle();
    expect(find.text('1237회 당첨내역'), findsOneWidget);
    expect(find.text('11 / 13'), findsOneWidget);
    expect(find.text('5등 · 3개 일치'), findsOneWidget);
    expect(find.text('낙첨 · 0개 일치'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hit_detail_older')));
    await tester.pumpAndSettle();
    expect(find.text('1236회 당첨내역'), findsOneWidget);
    expect(find.text('12 / 13'), findsOneWidget);
  });
}
