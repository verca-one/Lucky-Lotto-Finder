// 추천번호 공개 시점 — 월요일 0시(KST) 자동 공개 · 그 전엔 수동 추천 버튼
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/recommend_release.dart';
import 'package:flutter_app/widgets/master_briefing_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 1246회 추첨 2026-10-17(토) → 1247회 공개 2026-10-19(월) 0시 KST = 10-18 15:00 UTC (2026-10-29 수요일 → 월요일)
  test('공개 시각 = 직전 추첨일 + 2일 0시 KST', () {
    expect(RecommendRelease.releaseAtUtc('2026-10-17'), DateTime.utc(2026, 10, 18, 15));
    expect(RecommendRelease.releaseAtUtc('2026.10.17'), DateTime.utc(2026, 10, 18, 15));
    expect(RecommendRelease.releaseAtUtc(null), isNull);
  });

  test('공개 여부 — 토·일 숨김 · 월요일 0시부터 공개 · 수동 추천은 즉시 공개', () {
    final at = DateTime.utc(2026, 10, 18, 15);
    expect(RecommendRelease.releasedAt(releaseAtUtc: at, manualAt: null, nowUtc: DateTime.utc(2026, 10, 18, 3)), isFalse); // 일 12시
    expect(RecommendRelease.releasedAt(releaseAtUtc: at, manualAt: null, nowUtc: DateTime.utc(2026, 10, 18, 14, 59)), isFalse); // 일 23:59 KST
    expect(RecommendRelease.releasedAt(releaseAtUtc: at, manualAt: null, nowUtc: DateTime.utc(2026, 10, 18, 15)), isTrue); // 월 0시
    expect(RecommendRelease.releasedAt(releaseAtUtc: at, manualAt: DateTime.utc(2026, 10, 18), nowUtc: DateTime.utc(2026, 10, 18, 3)), isTrue);
    expect(RecommendRelease.releasedAt(releaseAtUtc: null, manualAt: null, nowUtc: DateTime.utc(2026, 10, 18)), isTrue); // 추첨일 모르면 공개
  });

  testWidgets('수동 추천 — 확인하면 서버에 엔진 실행 요청, 생성 전엔 대기 표시', (tester) async {
    final store = <int, Map<String, dynamic>>{};
    RecommendRelease.fetchRequest = (t) async => store[t];
    RecommendRelease.insertRequest = (t) async => store[t] = {'target_round': t, 'requested_at': '2026-10-18T06:00:00Z', 'status': 'pending'};
    var notified = 0;
    void l() => notified++;
    RecommendRelease.changes.addListener(l);
    addTearDown(() => RecommendRelease.changes.removeListener(l));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManualRecommendCard(
        target: () async => (1247, '2026-10-17'), generated: (_) async => false, nowUtc: DateTime.utc(2026, 10, 18, 3)))));
    await tester.pumpAndSettle();
    expect(find.text('1247회 추천번호 — 10/19(월) 0시 엔진 자동 실행'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('manual_recommend_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('엔진 실행'));
    await tester.pumpAndSettle();
    expect(store.keys, [1247]);
    expect(notified, 1);
    expect(find.byKey(const ValueKey('manual_recommend_waiting')), findsOneWidget);
    expect(find.textContaining('수동 추천'), findsOneWidget);
    // 이미 요청했으면 '엔진 바로 시작'은 요청됨 표시(누를 수 없음)
    expect(find.text('1247회 엔진 시작 요청됨 · 서버 처리 중'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('월요일 실행 대기 — 위에 엔진 바로 시작 버튼 → 서버 요청 · 만들어지면 흐릿한 가동 완료', (tester) async {
    final store = <int, Map<String, dynamic>>{};
    RecommendRelease.fetchRequest = (t) async => store[t];
    RecommendRelease.insertRequest = (t) async => store[t] = {'target_round': t, 'requested_at': '2026-10-28T03:00:00Z', 'status': 'pending'};
    var made = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManualRecommendCard(
        target: () async => (1248, '2026-10-24'), generated: (_) async => made, nowUtc: DateTime.utc(2026, 10, 28, 3)))));
    await tester.pumpAndSettle();
    final btn = find.byKey(const ValueKey('engine_start_now'));
    expect(btn, findsOneWidget);
    expect(find.text('엔진 바로 시작 · 1248회'), findsOneWidget);
    expect(tester.getTopLeft(btn).dy < tester.getTopLeft(find.byKey(const ValueKey('manual_recommend_waiting'))).dy, isTrue);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(store.keys, [1248]);
    expect(find.text('1248회 엔진 시작 요청됨 · 서버 처리 중'), findsOneWidget);
    // 서버가 만들면 1분 확인에서 가동 완료로 바뀌고 흐려짐
    made = true;
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('엔진 1248회 가동 완료 · 수동 추천'), findsOneWidget);
    final op = tester.widget<Opacity>(find.ancestor(of: find.byKey(const ValueKey('manual_recommend_done')), matching: find.byType(Opacity)).first);
    expect(op.opacity, closeTo(0.5, 0.01));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('번호가 만들어지면 완료 표시 · 월요일 이후엔 버튼 없음', (tester) async {
    RecommendRelease.fetchRequest = (t) async => null;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManualRecommendCard(
        target: () async => (1247, '2026-10-17'), generated: (_) async => true, nowUtc: DateTime.utc(2026, 10, 21, 3)))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manual_recommend_button')), findsNothing);
    expect(find.byKey(const ValueKey('manual_recommend_done')), findsOneWidget);
    expect(find.text('엔진 1247회 가동 완료 · 월요일 자동 실행'), findsOneWidget);
    expect(find.byKey(const ValueKey('engine_start_now')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
