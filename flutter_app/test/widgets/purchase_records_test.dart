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
}
