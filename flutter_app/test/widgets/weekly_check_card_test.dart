// 비서 주간 점검 카드 — 월요일 취합 / 토요일 변경점 없음 / 변경점 있음
import 'package:flutter/material.dart';
import 'package:flutter_app/widgets/weekly_check_card.dart';
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
}
