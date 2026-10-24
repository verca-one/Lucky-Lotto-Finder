// 홈 '최신 당첨 회차' 겹침 카드 — 회차 상태 판단 시나리오 + 카드 표시·탭
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/services/round_status_service.dart';
import 'package:flutter_app/widgets/home_round_header.dart';
import 'package:flutter_test/flutter_test.dart';

/// KST 시각 → UTC
DateTime kst(int y, int m, int d, int h, [int min = 0]) => DateTime.utc(y, m, d, h - 9, min);

final t1245 = DateTime.utc(2026, 10, 10, 17, 38); // 1245회 실제 수집 성공 시각 (round_crawl_status)
final t1244 = DateTime.utc(2026, 10, 3, 16, 58);
final t336 = DateTime.utc(2026, 10, 8, 19, 7);
final t335 = DateTime.utc(2026, 10, 1, 18, 40);

GameRoundData lotto({List<RoundCrawlRow> extra = const [], Set<int> winners = const {}, DateTime? fail, DateTime? ok}) =>
    GameRoundData(
      type: 'lotto',
      crawlRows: [...extra, RoundCrawlRow(1245, 'success', t1245), RoundCrawlRow(1244, 'success', t1244)],
      roundsWithWinners: {1245, 1244, ...winners},
      dbDrawDates: {1245: DateTime(2026, 10, 10), 1244: DateTime(2026, 10, 3)},
      lastRunFailureAt: fail,
      lastRunSuccessAt: ok ?? DateTime.utc(2026, 10, 10, 17, 49),
    );

GameRoundData pension({List<RoundCrawlRow> extra = const [], Set<int> winners = const {}}) => GameRoundData(
      type: 'pension',
      crawlRows: [...extra, RoundCrawlRow(336, 'success', t336), RoundCrawlRow(335, 'success', t335)],
      roundsWithWinners: {336, 335, ...winners},
    );

void main() {
  group('추첨 일정', () {
    test('로또 토요일 20:35, 연금 목요일 19:05 (KST)', () {
      expect(lottoDrawDateFor(1245), DateTime(2026, 10, 10));
      expect(lottoDrawDateFor(1245).weekday, DateTime.saturday);
      expect(pensionDrawDateFor(336), DateTime(2026, 10, 8));
      expect(pensionDrawDateFor(336).weekday, DateTime.thursday);
      expect(drawTimeUtc('lotto', 1246), kst(2026, 10, 17, 20, 35));
      expect(drawTimeUtc('pension', 337), kst(2026, 10, 15, 19, 5));
    });

    test('DB 추첨일 문자열 해석', () {
      expect(parseDrawDate('2026-10-10'), DateTime(2026, 10, 10));
      expect(parseDrawDate('2026.10.10'), DateTime(2026, 10, 10));
      expect(parseDrawDate('20261010'), DateTime(2026, 10, 10));
      expect(parseDrawDate(null), isNull);
      expect(formatDrawDate(DateTime(2026, 10, 10)), '2026.10.10 (토)');
    });
  });

  group('카드 교체 기준', () {
    test('평상시: 앞 = 최신 완료 회차, 뒤 = 직전 회차 (각자 실제 수집 시각)', () {
      final p = decideRoundPair(lotto(), kst(2026, 10, 12, 16))!;
      expect([p.front.round, p.front.status], [1245, RoundStatus.complete]);
      expect(p.front.updatedAt, t1245);
      expect([p.back!.round, p.back!.status, p.back!.updatedAt], [1244, RoundStatus.complete, t1244]);
    });

    test('추첨일 도래 (추첨 전): 앞 = 새 회차 추첨 예정, 뒤 = 직전 완료 회차', () {
      final p = decideRoundPair(lotto(), kst(2026, 10, 17, 10))!;
      expect([p.front.round, p.front.status], [1246, RoundStatus.scheduled]);
      expect(p.front.updatedAt, isNull);
      expect([p.back!.round, p.back!.status, p.back!.updatedAt], [1245, RoundStatus.complete, t1245]);
    });

    test('추첨 시각 경과·수집 전: 결과 대기 (추첨일 도래만으로 완료 표시 안 함)', () {
      final p = decideRoundPair(lotto(), kst(2026, 10, 17, 21))!;
      expect([p.front.round, p.front.status], [1246, RoundStatus.awaiting]);
      // 수집 중(pending) 행이 있어도 완료가 아니다
      final q = decideRoundPair(lotto(extra: [const RoundCrawlRow(1246, 'pending', null)]), kst(2026, 10, 17, 21))!;
      expect(q.front.status, RoundStatus.awaiting);
    });

    test('당첨번호만 수집 · 지점 수집 전: 번호 수집 완료 (3단계 중 2단계)', () {
      final d = lotto();
      final withNumbers = GameRoundData(type: d.type, crawlRows: d.crawlRows, roundsWithWinners: d.roundsWithWinners,
          dbDrawDates: d.dbDrawDates, latestNumbersRound: 1246);
      final p = decideRoundPair(withNumbers, kst(2026, 10, 17, 22))!;
      expect([p.front.round, p.front.status], [1246, RoundStatus.numbersReady]);
      expect(RoundStatus.numbersReady.label, '번호 수집 완료');
      // 번호 표가 직전 회차까지면 그대로 결과 대기
      final older = GameRoundData(type: d.type, crawlRows: d.crawlRows, roundsWithWinners: d.roundsWithWinners,
          dbDrawDates: d.dbDrawDates, latestNumbersRound: 1245);
      expect(decideRoundPair(older, kst(2026, 10, 17, 22))!.front.status, RoundStatus.awaiting);
    });

    test('결과 수집 완료: 앞 카드 갱신, 뒤 = 직전 회차', () {
      final t1246 = DateTime.utc(2026, 10, 17, 17, 40);
      final p = decideRoundPair(
          lotto(extra: [RoundCrawlRow(1246, 'success', t1246)], winners: {1246}), kst(2026, 10, 18, 9))!;
      expect([p.front.round, p.front.status, p.front.updatedAt], [1246, RoundStatus.complete, t1246]);
      expect([p.back!.round, p.back!.updatedAt], [1245, t1245]);
    });

    test('수집 실패: 데이터 오류 + 직전 완료 회차 유지', () {
      final now = kst(2026, 10, 18, 1);
      final failedRow = decideRoundPair(lotto(extra: [const RoundCrawlRow(1246, 'failed', null)]), now)!;
      expect([failedRow.front.round, failedRow.front.status], [1246, RoundStatus.error]);
      expect(failedRow.back!.round, 1245);

      final failedRun = decideRoundPair(lotto(fail: kst(2026, 10, 17, 23)), now)!;
      expect(failedRun.front.status, RoundStatus.error);

      // 수집 성공 표시인데 당첨 판매점 기록이 없음 = 검증 불일치
      final mismatch = decideRoundPair(lotto(extra: [RoundCrawlRow(1246, 'success', now)]), now)!;
      expect([mismatch.front.round, mismatch.front.status], [1246, RoundStatus.error]);
      expect(mismatch.back!.round, 1245);

      // 추첨 전 실패 로그는 새 회차 오류로 보지 않는다
      final oldFail = decideRoundPair(lotto(fail: kst(2026, 10, 16, 3)), kst(2026, 10, 17, 21))!;
      expect(oldFail.front.status, RoundStatus.awaiting);
    });

    test('여러 주 수집 누락: 앞 = 추첨일이 지난 최신 회차, 뒤 = 마지막 완료 회차', () {
      final p = decideRoundPair(lotto(), kst(2026, 10, 25, 12))!;
      expect([p.front.round, p.front.status, p.back!.round], [1247, RoundStatus.awaiting, 1245]);
    });

    test('로또만 새 회차: 연금 카드는 그대로', () {
      final now = kst(2026, 10, 17, 21);
      expect(decideRoundPair(lotto(), now)!.front.round, 1246);
      final pp = decideRoundPair(pension(extra: [RoundCrawlRow(337, 'success', kst(2026, 10, 16, 4))], winners: {337}), now)!;
      expect([pp.front.round, pp.front.status, pp.back!.round], [337, RoundStatus.complete, 336]);
    });

    test('연금만 새 회차: 로또 카드는 그대로', () {
      final now = kst(2026, 10, 15, 21);
      final pp = decideRoundPair(pension(), now)!;
      expect([pp.front.round, pp.front.status, pp.back!.round], [337, RoundStatus.awaiting, 336]);
      final lp = decideRoundPair(lotto(), now)!;
      expect([lp.front.round, lp.front.status, lp.back!.round], [1245, RoundStatus.complete, 1244]);
      // 연금 추첨일 오전 = 추첨 예정
      expect(decideRoundPair(pension(), kst(2026, 10, 15, 10))!.front.status, RoundStatus.scheduled);
    });

    test('회차 상태표를 못 읽으면 winning_history 최신 회차 (수집 시각은 만들지 않음)', () {
      final p = decideRoundPair(const GameRoundData(type: 'lotto', fallbackLatestRound: 1245), kst(2026, 10, 12, 16))!;
      expect([p.front.round, p.front.status, p.front.updatedAt], [1245, RoundStatus.complete, null]);
      expect(p.back!.updatedAt, isNull);
      expect(decideRoundPair(const GameRoundData(type: 'lotto'), kst(2026, 10, 12, 16)), isNull);
    });
  });

  group('겹침 카드 화면', () {
    Widget app(Widget child, {double width = 393}) => MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: SizedBox(width: width, child: child))),
        );

    testWidgets('앞·뒤 카드에 회차·추첨일·상태·실제 수집 시각 표시', (tester) async {
      await tester.pumpWidget(app(HomeRoundHeader(
        lotto: lotto(),
        pension: pension(),
        speetoUpdatedAt: DateTime(2026, 10, 10, 3, 50),
        clock: () => kst(2026, 10, 12, 16),
      )));
      expect(tester.takeException(), isNull);
      final front = find.byKey(const ValueKey('header_lotto_front_1245_complete'));
      expect(find.descendant(of: front, matching: find.text('1245')), findsOneWidget);
      expect(find.descendant(of: front, matching: find.text('2026.10.10 (토) 추첨')), findsOneWidget);
      expect(find.descendant(of: front, matching: find.text('번호 수집 완료')), findsOneWidget);
      expect(find.descendant(of: front, matching: find.text('판매점 수집 완료')), findsOneWidget);
      expect(find.descendant(of: front, matching: find.text('${formatUpdateTime(t1245)} 수집')), findsOneWidget);
      expect(find.text('로또 1244회 · ${formatUpdateTime(t1244)} 업데이트'), findsOneWidget);
      expect(find.byKey(const ValueKey('header_pension_front_336_complete')), findsOneWidget);
      expect(find.text('연금 335회 · ${formatUpdateTime(t335)} 업데이트'), findsOneWidget);
      expect(find.byKey(const ValueKey('header_speeto')), findsOneWidget);
    });

    testWidgets('추첨일 도래 → 결과 대기 상태 카드', (tester) async {
      await tester.pumpWidget(app(HomeRoundHeader(lotto: lotto(), pension: pension(), clock: () => kst(2026, 10, 17, 21))));
      final front = find.byKey(const ValueKey('header_lotto_front_1246_awaiting'));
      expect(find.descendant(of: front, matching: find.text('번호 수집 전')), findsOneWidget);
      expect(find.descendant(of: front, matching: find.text('판매점 수집 전')), findsOneWidget);
      // 연금 337회(목 추첨)도 수집 전이면 독립적으로 결과 대기
      expect(find.byKey(const ValueKey('header_pension_front_337_awaiting')), findsOneWidget);
      expect(find.text('로또 1245회 · ${formatUpdateTime(t1245)} 업데이트'), findsOneWidget);
    });

    testWidgets('앞 카드·뒤 카드 탭은 각 회차로, 열려 있는 동안 중복 이동 없음', (tester) async {
      final opened = <int>[];
      var pending = Completer<void>();
      await tester.pumpWidget(app(HomeRoundHeader(
        lotto: lotto(),
        pension: pension(),
        clock: () => kst(2026, 10, 12, 16),
        onOpen: (c) {
          opened.add(c.round);
          return pending.future;
        },
      )));
      await tester.tap(find.byKey(const ValueKey('header_lotto_front_1245_complete')));
      await tester.tap(find.byKey(const ValueKey('header_lotto_front_1245_complete')));
      await tester.pump();
      expect(opened, [1245]);
      pending.complete();
      await tester.pump();

      pending = Completer<void>();
      // 뒤 카드는 앞 카드 위로 드러난 띠 부분을 탭
      final back = tester.getTopLeft(find.byKey(const ValueKey('header_lotto_back')));
      await tester.tapAt(back + const Offset(30, 8));
      await tester.pump();
      expect(opened, [1245, 1244]);
      pending.complete();
      await tester.pump();
    });

    Color? colorOf(WidgetTester tester, Finder scope, String text) =>
        tester.widget<Text>(find.descendant(of: scope, matching: find.text(text))).style?.color;

    testWidgets('신규 회차 대기 카드: 흰 배경, 글자·상태 모두 옅은 회색, 완료 표시 없음, 뒤 카드는 테마색을 흐릿하게', (tester) async {
      for (final (now, key, label) in [
        (kst(2026, 10, 17, 10), 'header_lotto_front_1246_scheduled', '추첨 예정'),
        (kst(2026, 10, 17, 21), 'header_lotto_front_1246_awaiting', '번호 수집 전'),
      ]) {
        await tester.pumpWidget(app(HomeRoundHeader(lotto: lotto(), pension: pension(), clock: () => now)));
        await tester.pumpAndSettle();
        final front = find.byKey(ValueKey(key));
        expect(front, findsOneWidget);
        for (final t in ['로또 6/45', '1246', '회', '2026.10.17 (토) 추첨']) {
          expect(colorOf(tester, front, t), kPendingText, reason: t);
        }
        expect([kPendingText, kPendingSubText], contains(colorOf(tester, front, label)), reason: label);
        expect(find.descendant(of: front, matching: find.text('업데이트 완료')), findsNothing);
        expect(find.descendant(of: front, matching: find.byIcon(Icons.check_circle_rounded)), findsNothing);
        for (final icon in tester.widgetList<Icon>(find.descendant(of: front, matching: find.byType(Icon)))) {
          expect([kPendingText, kPendingSubText], contains(icon.color));
        }
        // 카드 전체 투명도는 쓰지 않는다 (전환이 끝난 뒤 불투명)
        final fades = tester.widgetList<FadeTransition>(find.ancestor(of: front, matching: find.byType(FadeTransition)));
        expect(fades.every((f) => f.opacity.value == 1.0), isTrue);
        // 뒤 카드(직전 완료 회차)는 로또 금색 테마 그대로
        final back = find.byKey(const ValueKey('header_lotto_back'));
        expect(colorOf(tester, back, '로또 1245회 · ${formatUpdateTime(t1245)} 업데이트'), const Color(0xFF8A6100).withValues(alpha: 0.38));
      }
    });

    testWidgets('완료 카드는 선명한 색 + 초록 체크·업데이트 완료·실제 수집 시각', (tester) async {
      await tester.pumpWidget(app(HomeRoundHeader(lotto: lotto(), pension: pension(), clock: () => kst(2026, 10, 12, 16))));
      final lf = find.byKey(const ValueKey('header_lotto_front_1245_complete'));
      expect(colorOf(tester, lf, '1245'), const Color(0xFF14213D));
      expect(colorOf(tester, lf, '로또 6/45'), const Color(0xFF8A6100));
      expect(colorOf(tester, lf, '판매점 수집 완료'), const Color(0xFF1E7D4C));
      expect(find.descendant(of: lf, matching: find.byIcon(Icons.check_circle_rounded)), findsNWidgets(2));
      final pf = find.byKey(const ValueKey('header_pension_front_336_complete'));
      expect(colorOf(tester, pf, '연금복권720+'), const Color(0xFF1C7A49));
    });

    testWidgets('대기 → 완료 전환: 같은 자리에서 색만 바뀌고 스크롤 위치 그대로', (tester) async {
      final now = kst(2026, 10, 18, 9);
      final scroll = ScrollController();
      Widget build(GameRoundData l) => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                controller: scroll,
                child: Column(children: [
                  HomeRoundHeader(lotto: l, pension: pension(), clock: () => now),
                  const SizedBox(height: 2000),
                ]),
              ),
            ),
          );
      await tester.pumpWidget(build(lotto()));
      scroll.jumpTo(120);
      await tester.pump();
      expect(find.byKey(const ValueKey('header_lotto_front_1246_awaiting')), findsOneWidget);

      final t1246 = DateTime.utc(2026, 10, 17, 17, 40);
      await tester.pumpWidget(build(lotto(extra: [RoundCrawlRow(1246, 'success', t1246)], winners: {1246})));
      await tester.pump(const Duration(milliseconds: 200)); // 전환 중
      await tester.pumpAndSettle();
      final front = find.byKey(const ValueKey('header_lotto_front_1246_complete'));
      expect(front, findsOneWidget);
      expect(find.byKey(const ValueKey('header_lotto_front_1246_awaiting')), findsNothing);
      expect(colorOf(tester, front, '1246'), const Color(0xFF14213D));
      expect(find.descendant(of: front, matching: find.text('${formatUpdateTime(t1246)} 수집')), findsOneWidget);
      expect(scroll.offset, 120);
    });

    testWidgets('작은 화면(320)·큰 글씨에서도 오버플로 없음', (tester) async {
      for (final now in [kst(2026, 10, 12, 16), kst(2026, 10, 17, 10), kst(2026, 10, 17, 21)]) {
        await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: app(HomeRoundHeader(lotto: lotto(), pension: pension(), clock: () => now), width: 320),
        ));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('불러오는 중에는 회차를 만들지 않고 안내만', (tester) async {
      await tester.pumpWidget(app(const HomeRoundHeader()));
      expect(find.text('회차 정보를 불러오는 중…'), findsNWidgets(2));
      expect(find.textContaining('회 ·'), findsNothing);
    });
  });

  testWidgets('수집 단계 표시 — 번호 · 판매점 각각 색', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Row(children: [
      CollectStageChip(key: ValueKey('n'), label: '번호', done: true),
      CollectStageChip(key: ValueKey('s'), label: '판매점', done: false),
    ]))));
    expect(find.text('번호 수집 완료'), findsOneWidget);
    expect(find.text('판매점 수집 전'), findsOneWidget);
  });
}
