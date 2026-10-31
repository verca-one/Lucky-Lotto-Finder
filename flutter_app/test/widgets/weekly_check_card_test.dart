// 비서 주간 점검 카드 — 월요일 취합 / 토요일 변경점 없음 / 변경점 있음
import 'package:flutter/material.dart';
import 'package:flutter_app/widgets/weekly_check_card.dart';
import 'package:flutter_app/screens/saturday_final_changes_screen.dart';
import 'package:flutter_app/services/research/hypothesis_track.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(WidgetTester t, Map<String, dynamic>? payload) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: WeeklyCheckCard(
      target: 1247, loader: (_) async => payload == null ? null : WeeklyCheck.fromPayload(payload)))));
  await t.pumpAndSettle();
}

Map<String, dynamic> snap() => {
      'at': '2026-10-20T15:30:00Z', 'qualifying': [],
      'activity': {'hypotheses': 46, 'directions': {'Gemini': 3}, 'simulated': 1, 'sim_raised': 0},
    };

void main() {
  testWidgets('기록 없음 → 일정 안내', (t) async {
    await show(t, null);
    expect(find.text('이번 주 비서 점검'), findsOneWidget);
  });
  testWidgets('월요일 취합만 → 토요일 예정', (t) async {
    await show(t, {'round': 1246, 'next': 1247, 'wed': snap()});
    expect(find.text('월요일 취합 완료 · 토요일 아침 8시 최종 점검 예정'), findsOneWidget);
    expect(find.textContaining('이번 주 가설 46개'), findsOneWidget);
  });
  testWidgets('토요일 변경점 없음', (t) async {
    await show(t, {'round': 1246, 'next': 1247, 'wed': snap(),
      'sat': {...snap(), 'changes': [], 'verdict': '변경점 없음 — 월요일에 정한 구매할 번호 그대로 구매하시면 됩니다'}});
    expect(find.text('토요일 8시 최종 점검: 변경점 없음'), findsOneWidget);
  });
  testWidgets('토요일 변경점 있음 + 목록', (t) async {
    await show(t, {'round': 1246, 'next': 1247, 'wed': snap(),
      'sat': {...snap(), 'changes': [{'type': 'new_hypothesis', 'note': '새로 적용 후보가 된 가설: 판매액 급증일 때 1등 쏠림이 높다'}],
        'verdict': '변경점 있음 — 이번 주에 적용 후보 가설이 바뀌었습니다'}});
    expect(find.text('토요일 8시 최종 점검: 변경점 있음'), findsOneWidget);
    expect(find.textContaining('새로 적용 후보가 된 가설'), findsOneWidget);
  });

  testWidgets('토요일 반영 — 대기 중 → 반영 알림 · 변경점 있으면 색 → 누르면 표·그래프 / 없으면 흐리게', (t) async {
    Map<String, dynamic>? sat;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SaturdayFinalAlertButton(
      target: 1248, pollEvery: const Duration(seconds: 1), trackLoader: (_) async => null,
      loader: (_) async => WeeklyCheck.fromPayload({'round': 1247, 'next': 1248, 'wed': snap(), if (sat != null) 'sat': sat}),
    ))));
    await t.pump();
    expect(find.text('토요일 반영 알림 · 토 8시 최종 점검 대기 중'), findsOneWidget);
    sat = {...snap(), 'changes': [{'type': 'new_hypothesis', 'note': '새로 적용 후보가 된 가설: 홀수 적은 쪽'}], 'verdict': '변경점 있음 — 확인하세요'};
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.textContaining('토요일 8시 최종본이 반영됐습니다 — 변경점 있음'), findsOneWidget);
    expect(find.text('토요일 최종본 변경점 — 번호 0세트 · 명당 0곳 · 가설 1 (자세히)'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('sat_final_alert')));
    await t.pumpAndSettle();
    expect(find.text('1248회 토요일 최종본 변경점'), findsOneWidget);
    expect(find.text('＋ 홀수 적은 쪽'), findsOneWidget);
    expect(find.byType(Table), findsWidgets);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('토요일 반영 — 변경점 없으면 흐리게', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SaturdayFinalAlertButton(
      target: 1248, trackLoader: (_) async => null,
      loader: (_) async => WeeklyCheck.fromPayload({'round': 1247, 'next': 1248, 'wed': snap(),
        'sat': {...snap(), 'changes': [], 'verdict': '변경점 없음 — 그대로'}}),
    ))));
    await t.pump();
    expect(find.text('토요일 최종본 변경점 없음'), findsOneWidget);
    expect(t.widget<Opacity>(find.ancestor(of: find.byKey(const ValueKey('sat_final_alert')), matching: find.byType(Opacity))).opacity, 0.5);
    await t.pumpWidget(const SizedBox());
  });

  test('변경점 계산 — ①~③ 바뀐 세트 수 · ④ 가설 트랙 세트·명당', () {
    final w = WeeklyCheck.fromPayload({'round': 1247, 'next': 1248,
      'wed': {'buy': {'official': {'label': '① 공식', 'sets': [[1, 2, 3, 4, 5, 6], [7, 8, 9, 10, 11, 12]]}}, 'qualifying': []},
      'sat': {'buy': {'official': {'label': '① 공식', 'sets': [[6, 5, 4, 3, 2, 1], [7, 8, 9, 10, 11, 13]]}}, 'qualifying': [], 'changes': []}});
    final tr = HypothesisTrack.fromPayload({'target_round': 1248, 'final': true,
      'sets': [{'set': [1, 2, 3, 4, 5, 6]}, {'set': [2, 3, 4, 5, 6, 7]}],
      'wednesday': {'sets': [[1, 2, 3, 4, 5, 6], [8, 9, 10, 11, 12, 13]], 'stores': ['A']},
      'stores': [{'store_code': 'A'}, {'store_code': 'B'}]});
    final c = SaturdayChanges.of(w, tr);
    expect(c.areas, [('① 공식', 2, 2, 1), ('④ 제미나이 가설 트랙', 2, 2, 1)]);
    expect(c.storesChanged, 1);
    expect(c.any, isTrue);
  });
}
