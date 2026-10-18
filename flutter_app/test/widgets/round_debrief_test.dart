// 회차 검증 · 지방장보고 탭 — 서버 저장본(1246회 드라이런 결과) 표시
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/screens/round_debrief_view.dart';
import 'package:flutter_app/services/research/round_debrief.dart';
import 'package:flutter_app/services/research/recommend_release.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(File('test/fixtures/debrief_1246.json').readAsStringSync()) as Map<String, dynamic>;

/// 휴대폰 폭(360×780)에서 넘침 없는지 확인
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  test('저장본 해석 — 번호 그룹 · 판매점 · 검수 · 다음 회차', () {
    final r = RoundDebrief.fromPayload(Map<String, dynamic>.from(fixture()['main'] as Map));
    expect(r.round, 1246);
    expect(r.next, 1247);
    expect(r.actual, [16, 22, 23, 24, 27, 28]);
    final off = r.groups.firstWhere((g) => g.key == 'official');
    expect(off.sets.length, 5);
    expect(off.sets.expand((s) => s.hits), contains(23));
    expect(r.storesPrev.length, 5);
    expect(r.analyst, isNotEmpty);
    expect(r.mathematician.last, contains('1/8,145,060'));
    expect(r.nextOfficial['status'], 'ready');
  });

  testWidgets('회차 검증 탭 — 채점·검수·변경점 카드', (tester) async {
    phone(tester);
    final r = RoundDebrief.fromPayload(Map<String, dynamic>.from(fixture()['main'] as Map));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RoundDebriefView(loader: () async => r))));
    await tester.pumpAndSettle();
    expect(find.text('1246회 검증 보고'), findsOneWidget);
    expect(find.byKey(const ValueKey('debrief_numbers')), findsOneWidget);
    // 브리핑 3영역은 펼쳐 보이고, 비교용(Number 엔진·무작위 대조군)은 접힌 칸 안
    expect(find.text('브리핑 ①'), findsOneWidget);
    expect(find.text('브리핑 ③'), findsOneWidget);
    // 구매할 번호(①~③) 15세트 중 5등 1장 — 무작위 대조군의 5등은 참고 구역에서 따로
    expect(find.text('15세트 중 5등 1장'), findsOneWidget);
    expect(find.text('Number 엔진 기본 조합'), findsNothing); // 구매할 번호가 아니면 검증 화면에도 없음
    expect(find.text('무작위 대조군'), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('debrief_audit')), 400);
    expect(find.textContaining('실무 분석 관점'), findsOneWidget);
    expect(find.textContaining('수학 관점'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('debrief_next')), 400);
    expect(find.text('⑤ 1247회 변경점'), findsOneWidget);
  });

  test('요일별 배치 — 토·일 펼침 · 월·화 박스 · 수요일부터 탭', () {
    // 1246회 추첨 2026-10-17(토). kst(일, 시) = 한국시간
    DateTime kst(int d, int h) => DateTime.utc(2026, 10, d, h).subtract(const Duration(hours: 9));
    expect(debriefPlacement('2026-10-17', kst(17, 23)), DebriefPlacement.inline); // 토 밤
    expect(debriefPlacement('2026-10-17', kst(18, 23)), DebriefPlacement.inline); // 일
    expect(debriefPlacement('2026-10-17', kst(19, 0)), DebriefPlacement.box); // 월 0시
    expect(debriefPlacement('2026-10-17', kst(20, 23)), DebriefPlacement.box); // 화
    expect(debriefPlacement('2026-10-17', kst(21, 0)), DebriefPlacement.tabOnly); // 수
    expect(debriefPlacement(null, kst(21, 0)), DebriefPlacement.box);
  });

  testWidgets('브리핑 맨 위 — 일요일 펼침 · 월요일 보라색 박스 · 수요일 숨김', (tester) async {
    phone(tester);
    SharedPreferences.setMockInitialValues({});
    RecommendRelease.fetchRequest = (t) async => null;
    final r = RoundDebrief.fromPayload(Map<String, dynamic>.from(fixture()['main'] as Map));
    Future<void> at(int day) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
          child: RoundDebriefTop(key: ValueKey(day), loader: () async => r, nowUtc: DateTime.utc(2026, 10, day, 3))))));
      await tester.pumpAndSettle();
    }
    await at(18);
    expect(find.byKey(const ValueKey('debrief_inline')), findsOneWidget);
    await at(19);
    expect(find.byKey(const ValueKey('round_debrief_link_1246')), findsOneWidget);
    await at(21);
    expect(find.byKey(const ValueKey('round_debrief_link_1246')), findsNothing);
    expect(find.byKey(const ValueKey('debrief_inline')), findsNothing);
  });

  testWidgets('보고 상자 — 안건넘김 누르면 사라지고, 다음 회차 수동 엔진 실행 요청이 있으면 처음부터 넘김', (tester) async {
    phone(tester);
    SharedPreferences.setMockInitialValues({});
    RecommendRelease.fetchRequest = (t) async => null;
    final r = RoundDebrief.fromPayload(Map<String, dynamic>.from(fixture()['main'] as Map));
    Widget app() => MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: RoundDebriefTop(key: UniqueKey(), loader: () async => r, nowUtc: DateTime.utc(2026, 10, 18, 3)))));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('debrief_box')), findsOneWidget);
    expect(find.text('1246회 보고 — 지난주 추천 검증'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('debrief_handover')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('debrief_box')), findsNothing);
    // 새로 열어도 넘긴 상태 유지
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('debrief_box')), findsNothing);
    // 다른 기기(넘김 기록 없음)라도 1247회 수동 엔진 실행 요청이 있으면 넘김
    SharedPreferences.setMockInitialValues({});
    RecommendRelease.fetchRequest = (t) async => {'target_round': t, 'requested_at': '2026-10-18T06:00:00Z', 'status': 'pending'};
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('debrief_box')), findsNothing);
    RecommendRelease.fetchRequest = (t) async => null;
  });

  testWidgets('지난 회차 검증 탭 — 회차별 보라색 박스', (tester) async {
    phone(tester);
    final r = RoundDebrief.fromPayload(Map<String, dynamic>.from(fixture()['main'] as Map));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RoundDebriefHistoryView(loader: () async => [r]))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('round_debrief_link_1246')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('round_debrief_link_1246')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('debrief_numbers')), findsOneWidget);
  });

  testWidgets('브리핑 상단 박스 링크 → 회차 검증 화면', (tester) async {
    phone(tester);
    final r = RoundDebrief.fromPayload(Map<String, dynamic>.from(fixture()['main'] as Map));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RoundDebriefLinkCard(loader: () async => r))));
    await tester.pumpAndSettle();
    expect(find.text('1246회 검증 보고'), findsOneWidget);
    expect(find.textContaining('공식 5세트 최고 1개 일치'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('round_debrief_link')));
    await tester.pumpAndSettle();
    expect(find.text('회차 검증'), findsOneWidget);
    expect(find.byKey(const ValueKey('debrief_numbers')), findsOneWidget);
  });

  testWidgets('지방장보고 화면 — 당첨 지역 필터 · 카드 펼치기', (tester) async {
    phone(tester);
    final a = AgentDebrief.fromPayload(Map<String, dynamic>.from(fixture()['agents'] as Map));
    await tester.pumpWidget(MaterialApp(home: AgentReportScreen(loader: () async => a)));
    await tester.pumpAndSettle();
    expect(find.textContaining('지방장 보고 — 1246회'), findsOneWidget);
    final withFirst = a.agents.where((x) => x.hadFirst || x.secondHits > 0).length;
    expect(find.byType(AgentReportCard), findsNWidgets(withFirst));
    await tester.tap(find.byKey(const ValueKey('agent_only_first')));
    await tester.pumpAndSettle();
    expect(find.byType(AgentReportCard), findsNWidgets(a.agents.length));
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    expect(find.text('1246회 추천 TOP5 → 결과'), findsOneWidget);
    expect(find.text('1247회 TOP5 (변경점)'), findsOneWidget);
  });
}
