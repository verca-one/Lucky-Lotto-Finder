// 추천번호 공개 시점 — 수요일 0시(KST) 자동 공개 · 그 전엔 수동 추천 버튼
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/recommend_release.dart';
import 'package:flutter_app/widgets/master_briefing_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 1246회 추첨 2026-10-17(토) → 1247회 공개 2026-10-21(수) 0시 KST = 10-20 15:00 UTC
  test('공개 시각 = 직전 추첨일 + 4일 0시 KST', () {
    expect(RecommendRelease.releaseAtUtc('2026-10-17'), DateTime.utc(2026, 10, 20, 15));
    expect(RecommendRelease.releaseAtUtc('2026.10.17'), DateTime.utc(2026, 10, 20, 15));
    expect(RecommendRelease.releaseAtUtc(null), isNull);
  });

  test('공개 여부 — 일·화 숨김 · 수요일 0시부터 공개 · 수동 추천은 즉시 공개', () {
    final at = DateTime.utc(2026, 10, 20, 15);
    expect(RecommendRelease.releasedAt(releaseAtUtc: at, manualAt: null, nowUtc: DateTime.utc(2026, 10, 18, 3)), isFalse); // 일
    expect(RecommendRelease.releasedAt(releaseAtUtc: at, manualAt: null, nowUtc: DateTime.utc(2026, 10, 20, 14, 59)), isFalse); // 화 23:59 KST
    expect(RecommendRelease.releasedAt(releaseAtUtc: at, manualAt: null, nowUtc: DateTime.utc(2026, 10, 20, 15)), isTrue); // 수 0시
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
    expect(find.text('1247회 추천번호 — 10/21(수) 0시 엔진 자동 실행'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('manual_recommend_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('엔진 실행'));
    await tester.pumpAndSettle();
    expect(store.keys, [1247]);
    expect(notified, 1);
    expect(find.byKey(const ValueKey('manual_recommend_waiting')), findsOneWidget);
    expect(find.textContaining('수동 추천'), findsOneWidget);
  });

  testWidgets('번호가 만들어지면 완료 표시 · 수요일 이후엔 버튼 없음', (tester) async {
    RecommendRelease.fetchRequest = (t) async => null;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManualRecommendCard(
        target: () async => (1247, '2026-10-17'), generated: (_) async => true, nowUtc: DateTime.utc(2026, 10, 21, 3)))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manual_recommend_button')), findsNothing);
    expect(find.byKey(const ValueKey('manual_recommend_done')), findsOneWidget);
    expect(find.textContaining('수요일 자동 실행'), findsOneWidget);
  });
}
