// 연구소 AI 부서 — 상태 계산(원활/문제) · 진행 막대 · 새로고침 요청 · 브리핑 안내
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/ai_dept_status.dart';
import 'package:flutter_app/widgets/ai_dept_card.dart';
import 'package:flutter_app/widgets/ai_week_progress.dart';
import 'package:flutter_app/widgets/briefing_top_reports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ok = AiDeptStatus.fromRows(
    a7183: {'source': 'gemini'},
    review: {'source': 'gemini'},
    runs: [
      {'kind': 'ai_direction', 'status': 'success', 'created_at': '2026-11-25T08:30:00Z'},
      {'kind': 'ai_pension', 'status': 'skipped', 'created_at': '2026-11-25T08:31:00Z'},
    ],
  );
  final bad = AiDeptStatus.fromRows(
    a7183: {'source': 'rule', 'quota_until': '2026-11-26T08:04:00Z'},
    review: {'source': 'rule', 'ai_error': '429 RESOURCE_EXHAUSTED'},
    runs: [
      {'kind': 'ai_direction', 'status': 'failed', 'note': 'TimeoutError — 420초 안에 응답 없음', 'created_at': '2026-11-25T18:32:00Z'},
      {'kind': 'ai_direction', 'status': 'success', 'created_at': '2026-11-20T08:30:00Z'}, // 옛 기록 — 최신만 봄
    ],
    request: {'id': 3, 'status': 'dispatched', 'requested_at': '2026-11-26T07:00:00Z', 'dispatched_at': '2026-11-26T07:08:00Z'},
  );

  test('상태 — 모두 정상이면 원활 · 최신 기록만 · 한도 초과 시각 KST', () {
    expect(ok.smooth, isTrue);
    expect(bad.smooth, isFalse);
    expect(bad.problems.length, 3);
    expect(bad.problems.first, contains('11/26 17:04 이후 다시'));
    expect(bad.problems[1], contains('제미나이 하루 한도 초과'));
    expect(bad.problems[2], contains('시간 초과'));
    expect(bad.request!.active, isTrue);
    expect(bad.request!.progress, 0.55);
    // 실행 시간 — 실행 중이면 서버 요청부터 지금까지 · 끝나면 실제 시작~끝
    expect(bad.request!.elapsed(DateTime.utc(2026, 11, 26, 7, 20, 30)), const Duration(minutes: 12, seconds: 30));
    final done = AiRequest.fromRow({'id': 4, 'status': 'done', 'conclusion': 'success', 'requested_at': '2026-11-26T07:00:00Z',
      'dispatched_at': '2026-11-26T07:08:00Z', 'done_at': '2026-11-26T08:00:00Z',
      'run_started_at': '2026-11-26T07:09:00Z', 'run_ended_at': '2026-11-26T07:43:10Z'});
    expect(AiRequest.fmt(done.elapsed(DateTime.utc(2026, 11, 27))), '34분 10초');
    expect(AiRequest.fmt(const Duration(hours: 1, minutes: 5)), '1시간 5분');
  });

  testWidgets('접힘 · 원활 표시 → 펼치면 부서별 상태 / 실행 중이면 막대 · 새로고침 막힘', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AiDeptCard(loader: () async => ok))));
    await t.pumpAndSettle();
    expect(find.text('원활'), findsOneWidget);
    expect(find.text('AI 전략기획부'), findsNothing); // 접힘
    await t.tap(find.byKey(const ValueKey('ai_dept_toggle')));
    await t.pumpAndSettle();
    expect(find.text('AI 전략기획부'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_dept_open_desk')), findsOneWidget);

    await t.pumpWidget(MaterialApp(home: Scaffold(body: AiDeptCard(key: const ValueKey('b'), loader: () async => bad))));
    await t.pump();
    await t.pump();
    expect(find.text('실행 중'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_dept_progress')), findsOneWidget); // 접혀 있어도 막대
    expect(find.byKey(const ValueKey('ai_dept_elapsed')), findsOneWidget); // 실행 시간
    expect(t.widget<IconButton>(find.byKey(const ValueKey('ai_dept_refresh'))).onPressed, isNull);
    await t.pumpWidget(const SizedBox()); // 30초 타이머 정리
  });

  testWidgets('문제 있고 실행 중 아님 → [새로고침] 누르면 요청', (t) async {
    final idle = AiDeptStatus(bad.items, null);
    var asked = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AiDeptCard(loader: () async => idle, requester: () async => asked++))));
    await t.pumpAndSettle();
    expect(find.text('문제 3'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ai_dept_refresh')));
    await t.pumpAndSettle();
    expect(asked, 1);
  });

  test('이번 주 진척도 — 요일별 완료 · 실패 · 안 돎 · 예정', () {
    final wed = DateTime.utc(2026, 11, 25, 10); // 수 19:00 KST (수요일 몫까지 끝났어야 함)
    expect(AiDeptStatus.weekStart(wed), DateTime.utc(2026, 11, 22, 15));
    final s = AiDeptStatus.fromRows(
      now: wed,
      a7183: {'source': 'gemini'},
      review: {'source': 'gemini'},
      runs: [
        {'kind': 'ai_direction', 'status': 'failed', 'created_at': '2026-11-24T08:10:00Z'},
        {'kind': 'ai_pension', 'status': 'success', 'created_at': '2026-11-18T08:10:00Z'}, // 지난주 — 이번 주엔 안 돎
      ],
    );
    expect(s.weekStates(wed), [AiDayState.done, AiDayState.failed, AiDayState.missed, AiDayState.wait, AiDayState.wait]);
    expect(s.weekDone(wed), 1);
  });

  testWidgets('브리핑 진척도 상자 — 1/4 · 문제 있으면 연구소 새로고침 안내', (t) async {
    final wed = DateTime.utc(2026, 11, 25, 10);
    final s = AiDeptStatus.fromRows(now: wed, a7183: {'source': 'gemini'}, review: {'source': 'gemini'},
        runs: [{'kind': 'ai_direction', 'status': 'failed', 'created_at': '2026-11-24T08:10:00Z'}]);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AiWeekProgress(loader: () async => s, clock: () => wed))));
    await t.pumpAndSettle();
    expect(find.text('1/4'), findsOneWidget);
    expect(find.text('완료'), findsOneWidget);
    expect(find.text('실패'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_week_hint')), findsOneWidget);
  });

  test('브리핑 경고 — 제미나이 문제 줄', () {
    final w = pipelineWarnings(
        const PipelineSnapshot(latestWin: 1251, prizeLatest: 1251, aiProblems: ['AI 전략기획부: 제미나이 응답 없음']),
        DateTime.utc(2026, 11, 26));
    expect(w.single, '제미나이 · AI 전략기획부: 제미나이 응답 없음');
  });

  testWidgets('브리핑 경고 상자 — 연구소 새로고침 안내', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PipelineAlertReport(
      loader: () async => const PipelineSnapshot(latestWin: 1251, prizeLatest: 1251, aiProblems: ['7183 에이전트: 제미나이 답 없음']),
      clock: () => DateTime.utc(2026, 11, 26),
    ))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('pipeline_alert_refresh_hint')), findsOneWidget);
  });
}
