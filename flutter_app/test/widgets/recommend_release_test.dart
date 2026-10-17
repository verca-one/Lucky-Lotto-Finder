// 추천번호 공개 시점 — 수요일 0시(KST) 자동 공개 · 그 전엔 수동 추천 버튼
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/recommend_release.dart';
import 'package:flutter_app/widgets/master_briefing_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('수동 추천 버튼 — 누르고 확인하면 공개 상태로 바뀜 (회차별 저장)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var notified = 0;
    void l() => notified++;
    RecommendRelease.changes.addListener(l);
    addTearDown(() => RecommendRelease.changes.removeListener(l));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManualRecommendCard(
        target: () async => (1247, '2026-10-17'), nowUtc: DateTime.utc(2026, 10, 18, 3)))));
    await tester.pumpAndSettle();
    expect(find.text('1247회 추천번호 — 10/21(수) 0시 공개 예정'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('manual_recommend_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지금 공개'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manual_recommend_done')), findsOneWidget);
    expect(find.textContaining('수동 추천으로 공개'), findsOneWidget);
    expect(notified, 1);
    expect((await RecommendRelease.state(1247, prevDrawDate: '2026-10-17', nowUtc: DateTime.utc(2026, 10, 18))).released, isTrue);
    expect((await RecommendRelease.state(1248, prevDrawDate: '2026-10-24', nowUtc: DateTime.utc(2026, 10, 25))).released, isFalse);
  });

  testWidgets('수요일 이후엔 버튼 없이 자동 공개 표시', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManualRecommendCard(
        target: () async => (1247, '2026-10-17'), nowUtc: DateTime.utc(2026, 10, 21, 3)))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('manual_recommend_button')), findsNothing);
    expect(find.textContaining('수요일 자동 공개'), findsOneWidget);
  });
}
