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
    bool? won;
    final records = [
      PurchaseRecord(id: 'x', storeCode: 'S1', storeName: '스파', round: 1250,
          games: const [[1, 5, 18, 23, 40, 41], [2, 3, 4, 6, 7, 9]], createdAt: DateTime(2026, 11, 14)),
      PurchaseRecord(id: 'y', storeCode: 'S2', storeName: '행운', round: 1251,
          games: const [[1, 2, 3, 4, 5, 6]], createdAt: DateTime(2026, 11, 20)),

      PurchaseRecord(id: 'z', storeCode: 'S3', storeName: '판매점만', round: 1250, games: const [], createdAt: DateTime(2026, 11, 13)),
    ];
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PurchaseRecordsSection(
      loader: () async => records,
      winLoader: (r) async => r == 1250
          ? LottoWinningNumber(drawDate: '2026-11-14', round: 1250, numbers: const [1, 5, 18, 23, 27, 28], bonusNumber: 8)
          : null,
      onWin: (v) => won = v,
    )))));
    await t.pumpAndSettle();
    expect(find.text('구매한 번호 (3)'), findsOneWidget);
    expect(find.text('번호 없이 판매점만 기록'), findsOneWidget); // 판매점만 골라 저장한 기록
    expect(find.text('🎉 축하합니다! 4등 당첨!'), findsOneWidget); // 1 5 18 23 맞음 · 노란 축하 표시
    expect(won, isTrue); // 최근 추첨 회차(1250) 당첨 → 즐겨찾기 탭 당첨 그림
    expect(find.text('4등'), findsOneWidget);
    expect(find.text('0개'), findsOneWidget);
    expect(find.text('추첨 전 · 당첨번호 나오면 자동 확인'), findsOneWidget);
  });

  testWidgets('판매점 카드 안 — 그 판매점에서 산 번호만 · 제목 버튼 없이 · 없으면 안 그림', (t) async {
    final records = [
      PurchaseRecord(id: 'x', storeCode: 'S1', storeName: '스파', round: 1250, games: const [[1, 2, 3, 4, 5, 6]], createdAt: DateTime(2026, 11, 14)),
      PurchaseRecord(id: 'y', storeCode: 'S2', storeName: '행운', round: 1250, games: const [[7, 8, 9, 10, 11, 12]], createdAt: DateTime(2026, 11, 14)),
    ];
    Widget at(String code) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PurchaseRecordsSection(
      key: ValueKey(code), loader: () async => records, winLoader: (_) async => null,
      where: (r) => r.storeCode == code, listOnly: true))));
    await t.pumpWidget(at('S1'));
    await t.pumpAndSettle();
    expect(find.text('이 판매점에서 산 번호 (1)'), findsOneWidget);
    expect(find.byKey(const ValueKey('purchase_x')), findsOneWidget);
    expect(find.byKey(const ValueKey('purchase_y')), findsNothing);
    expect(find.byKey(const ValueKey('purchase_manual')), findsNothing);
    await t.pumpWidget(at('S9'));
    await t.pumpAndSettle();
    expect(find.textContaining('이 판매점에서 산 번호'), findsNothing);
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

  test('번호 쓰기 해석 — 띄어쓰기 · 쉼표 · 1~45 · 6개까지 · 겹침 없음', () {
    expect(parseNumberLine('3 17,40').$1, [3, 17, 40, null, null, null]);
    expect(parseNumberLine('3 17,40').$2, isTrue);
    expect(parseNumberLine('').$1, List<int?>.filled(6, null));
    expect(parseNumberLine('3 46').$2, isFalse);
    expect(parseNumberLine('3 3').$2, isFalse);
    expect(parseNumberLine('1 2 3 4 5 6 7').$2, isFalse);
  });

  testWidgets('번호 직접 입력 — 판매점 칸 · QR 없음 · 다섯 줄 글자칸 · 띄어 쓰면 번호공 · 겹치면 빨간 테두리 · 저장 막힘', (t) async {
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
      expect(find.byKey(ValueKey('manual_text_$r')), findsOneWidget);
    }
    await t.enterText(find.byKey(const ValueKey('manual_text_0')), '3 17 40');
    await t.pump();
    expect(find.descendant(of: find.byKey(const ValueKey('manual_row_0')), matching: find.text('17')), findsOneWidget); // 번호공
    expect(find.descendant(of: find.byKey(const ValueKey('manual_row_0')), matching: find.text('자동')), findsNWidgets(3));
    await t.enterText(find.byKey(const ValueKey('manual_text_0')), '3 3');
    await t.pump();
    final row = t.widget<Container>(find.byKey(const ValueKey('manual_row_0')));
    expect((row.decoration as BoxDecoration).border, Border.all(color: Colors.red));
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('purchase_save'))).onPressed, isNull);
  });

  testWidgets('번호 추가 — 판매점만 기록한 것을 열면 판매점 · 회차가 채워져 있고, 저장하면 같은 기록을 고침(새로 안 만듦)', (t) async {
    final r = PurchaseRecord(id: 'z', storeCode: 'S3', storeName: '판매점만', storeAddress: '서울', round: 1250, games: const [],
        createdAt: DateTime(2026, 11, 13));
    SharedPreferences.setMockInitialValues({'my_lotto_numbers': ['{"numbers":[1,2,3,4,5,6],"date":"2026-11-20T00:00:00"}']});
    await PurchaseRecords.add(r);
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: PurchaseRecordScreen(existing: r)));
    await t.pumpAndSettle();
    expect(find.text('번호 추가'), findsOneWidget);
    expect(find.text('판매점만'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('purchase_saved')));
    await t.pumpAndSettle();
    await t.tap(find.text('1  2  3  4  5  6   (11/20)').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('purchase_save')));
    await t.pumpAndSettle();
    final l = await PurchaseRecords.load();
    expect(l.length, 1);
    expect(l.single.id, 'z');
    expect(l.single.games, [[1, 2, 3, 4, 5, 6]]);
  });

  testWidgets('구입 기록 — 번호 직접 입력 버튼: 번호판에서 고르고 모자란 칸은 자동으로 한 게임 추가', (t) async {
    final r = PurchaseRecord(id: 'm', storeCode: 'S4', storeName: '명당', storeAddress: '경기', round: 1252, games: const [],
        createdAt: DateTime(2026, 11, 25));
    SharedPreferences.setMockInitialValues({});
    await PurchaseRecords.add(r);
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: PurchaseRecordScreen(existing: r)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('purchase_manual')));
    await t.pumpAndSettle();
    for (final n in [3, 17, 40]) {
      await t.tap(find.byKey(ValueKey('manual_pick_$n')));
      await t.pump();
    }
    expect(find.text('번호 직접 입력 — 3/6'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('manual_pick_add')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('purchase_save')));
    await t.pumpAndSettle();
    final g = (await PurchaseRecords.load()).single.games.single;
    expect(g.length, 6);
    expect(g.toSet().length, 6);
    expect(g.toSet().containsAll([3, 17, 40]), isTrue);
    // 판매점에서 산 번호 → 그 판매점이 즐겨찾기에 들어감 (즐겨찾기 판매점 카드 안에 보이게)
    expect((await SharedPreferences.getInstance()).getStringList('favorite_stores'), ['S4']);
  });
}
