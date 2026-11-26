// 즐겨찾기 › 당첨기록 — 당첨된 구매 기록만 · 날짜 · 등수 · 그 판매점 구매 횟수
import 'package:flutter/material.dart';
import 'package:flutter_app/models/lotto_winning_number.dart';
import 'package:flutter_app/screens/win_records_screen.dart';
import 'package:flutter_app/services/purchase_records.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PurchaseRecord rec(String id, String code, int round, List<List<int>> games) => PurchaseRecord(
      id: id, storeCode: code, storeName: code.isEmpty ? '' : '명당$code', round: round, games: games, createdAt: DateTime(2026, 11, 1));
  final w = LottoWinningNumber(drawDate: '2026-11-14', round: 1250, numbers: const [1, 5, 18, 23, 27, 28], bonusNumber: 8);
  final records = [
    rec('a', 'S1', 1250, const [[1, 5, 18, 23, 40, 41], [2, 3, 4, 6, 7, 9]]), // 4등
    rec('b', 'S1', 1249, const [[1, 2, 3, 4, 5, 6]]), // 당첨번호 없음
    rec('c', 'S1', 1250, const [[2, 3, 4, 6, 7, 9]]), // 낙첨
    rec('d', '', 1250, const [[1, 5, 18, 23, 27, 8]]), // 2등 · 판매점 없음
  ];

  test('당첨된 기록만 · 판매점 구매 횟수 · 가장 높은 등수', () {
    final l = winEntries(records, {1250: w, 1249: null});
    expect(l.map((e) => e.record.id), ['a', 'd']);
    expect(l[0].rank, 4);
    expect(l[0].visits, 3); // S1 에서 3번 삼
    expect(l[0].games.length, 1);
    expect(l[1].rank, 2);
    expect(l[1].visits, 0);
  });

  testWidgets('카드 — 등수 · 회차 날짜 · 구매 횟수 / 없으면 안내', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WinRecordsScreen(
        loader: () async => records, winLoader: (r) async => r == 1250 ? w : null))));
    await t.pumpAndSettle();
    expect(find.text('당첨기록 (2)'), findsOneWidget);
    expect(find.text('🎉 4등 당첨'), findsOneWidget);
    expect(find.text('🎉 2등 당첨'), findsOneWidget);
    expect(find.text('1250회 · 2026-11-14'), findsNWidgets(2));
    expect(find.text('이 판매점 구매 3번'), findsOneWidget);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: WinRecordsScreen(
        key: const ValueKey('empty'), loader: () async => const [], winLoader: (_) async => null))));
    await t.pumpAndSettle();
    expect(find.textContaining('아직 당첨 기록이 없습니다'), findsOneWidget);
  });
}
