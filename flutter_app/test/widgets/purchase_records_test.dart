// 나의 번호 › 구입 기록 — 로또 용지 QR 해석 · 저장/삭제 · 추첨 뒤 자동 당첨 확인
import 'package:flutter/material.dart';
import 'package:flutter_app/models/lotto_winning_number.dart';
import 'package:flutter_app/screens/purchase_record_screen.dart';
import 'package:flutter_app/services/purchase_records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('QR 해석 — 회차 4자리 + 게임(영문 1자 + 12자리) · 1~45 · 중복 없는 것만 · 로또 QR 아니면 null', () {
    final r = parseLottoQr('http://m.dhlottery.co.kr/?v=1251m010203040506q451020304045s070809101112n0000000000001234567890')!;
    expect(r.$1, 1251);
    expect(r.$2, [
      [1, 2, 3, 4, 5, 6],
      [7, 8, 9, 10, 11, 12],
    ]); // 두 번째 게임(45 중복)과 뒤 일련번호(n000…)는 게임으로 안 봄
    expect(parseLottoQr('https://example.com/?x=1'), isNull);
    expect(parseLottoQr('http://m.dhlottery.co.kr/?v=1251'), isNull);
  });

  test('QR 해석 — 정렬해서 저장', () {
    expect(parseLottoQr('http://qr.dhlottery.co.kr/?v=0964m450102030405')!.$2.single, [1, 2, 3, 4, 5, 45]);
  });

  test('저장 · 삭제 · 최신 먼저', () async {
    SharedPreferences.setMockInitialValues({});
    PurchaseRecord rec(String id, int day) => PurchaseRecord(id: id, storeCode: 'S$id', storeName: '가게$id', round: 1251,
        games: const [[1, 2, 3, 4, 5, 6]], createdAt: DateTime(2026, 11, day));
    await PurchaseRecords.add(rec('a', 20));
    await PurchaseRecords.add(rec('b', 21));
    expect((await PurchaseRecords.load()).map((r) => r.id), ['b', 'a']);
    await PurchaseRecords.remove('b');
    expect((await PurchaseRecords.load()).map((r) => r.id), ['a']);
  });

  testWidgets('구입 기록 목록 — 당첨번호 있으면 자동으로 등수 · 없으면 추첨 전', (t) async {
    final records = [
      PurchaseRecord(id: 'x', storeCode: 'S1', storeName: '스파', round: 1250,
          games: const [[1, 5, 18, 23, 40, 41], [2, 3, 4, 6, 7, 9]], createdAt: DateTime(2026, 11, 14)),
      PurchaseRecord(id: 'y', storeCode: 'S2', storeName: '행운', round: 1251,
          games: const [[1, 2, 3, 4, 5, 6]], createdAt: DateTime(2026, 11, 20)),
    ];
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PurchaseRecordsSection(
      loader: () async => records,
      winLoader: (r) async => r == 1250
          ? LottoWinningNumber(drawDate: '2026-11-14', round: 1250, numbers: const [1, 5, 18, 23, 27, 28], bonusNumber: 8)
          : null,
    )))));
    await t.pumpAndSettle();
    expect(find.text('구입한 기록 (2)'), findsOneWidget);
    expect(find.text('4등 당첨!'), findsOneWidget); // 1 5 18 23 맞음
    expect(find.text('4등'), findsOneWidget);
    expect(find.text('0개'), findsOneWidget);
    expect(find.text('추첨 전 · 당첨번호 나오면 자동 확인'), findsOneWidget);
  });

  test('빈 칸 자동 — 고른 번호 유지 · 겹치지 않게 6개 · 정렬 · 모두 비면 자동', () {
    final a = autoFill([3, null, 41, null, null, null]);
    expect(a.length, 6);
    expect(a.toSet().length, 6);
    expect(a, containsAll([3, 41]));
    expect(a, [...a]..sort());
    final b = autoFill(List<int?>.filled(6, null));
    expect(b.toSet().length, 6);
    expect(b.every((n) => n >= 1 && n <= 45), isTrue);
  });

  testWidgets('번호 직접 입력 — 판매점 칸 · QR 없음 · 다섯 줄 × 드롭다운 6칸 · 줄 안 중복이면 빨간 테두리 · 저장 막힘', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: PurchaseRecordScreen(manual: true)));
    await t.pumpAndSettle();
    expect(find.text('번호 직접 입력'), findsOneWidget);
    expect(find.byKey(const ValueKey('purchase_store')), findsNothing);
    expect(find.byKey(const ValueKey('purchase_qr')), findsNothing);
    for (var r = 0; r < 5; r++) {
      expect(find.byKey(ValueKey('manual_row_$r')), findsOneWidget);
    }
    Future<void> pick(int r, int k, int n) async {
      await t.tap(find.byKey(ValueKey('manual_dd_${r}_$k')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('$n').last, 40, scrollable: find.byType(Scrollable).last);
      await t.tap(find.text('$n').last);
      await t.pumpAndSettle();
    }
    await pick(0, 0, 3);
    await pick(0, 1, 3); // 같은 줄 중복
    final row = t.widget<Container>(find.byKey(const ValueKey('manual_row_0')));
    expect((row.decoration as BoxDecoration).border, Border.all(color: Colors.red));
  });
}
