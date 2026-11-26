// 연구소 AI 부서 — 상태 계산(원활/문제) · 진행 막대 · 새로고침 요청 · 브리핑 안내
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/agent7183.dart';
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

  testWidgets('펼치면 이번 회차 추천번호가 따른 법칙 풀이 — 법칙 설명 · 번호별 표기', (t) async {
    final st = AiDeptStatus.fromRows(a7183: {'source': 'claude'}, review: {'source': 'gemini'}, nextRound: 1252);
    final a = Agent7183.fromPayload({
      'target_round': 1252, 'source': 'claude', 'sets_status': 'registered', 'sets_by': 'rule',
      'sets': [[7, 25, 27, 29, 37, 42]], 'sets_laws': [[1, 2]],
      'late_sets': [[7, 10, 15, 19, 34, 42]], 'late_sets_laws': [[1]], 'late_sets_by': 'claude',
      'trusted': [{'id': 1, 'law': '6번째 번호 · 앞앞 회차 + 그 회차 · 10로 나눈 나머지', 'mode': '주기 1회', 'run': 3, 'next': 0, 'chance': 0.114,
        'cond': '6번째 번호: 22 · 32 · 42', 'how': '값이 1회 간격으로 3번 연속 같았습니다.', 'why': '끝수 2에서 만남'}],
    });
    t.view.physicalSize = const Size(1080, 3200);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: AiDeptCard(loader: () async => st, lawsLoader: (_) async => a)))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai_dept_laws')), findsNothing); // 접힘
    await t.tap(find.byKey(const ValueKey('ai_dept_toggle')));
    await t.pumpAndSettle();
    expect(find.text('1252회 제미나이 추천번호(7183)가 따른 법칙'), findsOneWidget);
    expect(find.text('★ 법칙 1 — 6번째 번호: 22 · 32 · 42'), findsOneWidget);
    expect(find.text('무슨 법칙인가: 값이 1회 간격으로 3번 연속 같았습니다.'), findsOneWidget);
    expect(find.text('1번  7 · 25 · 27 · 29 · 37 · 42  →  법칙 ★1 · 2'), findsOneWidget);
    expect(find.text('번호별 — Claude(대행) 주중 추가'), findsOneWidget);
  });

  testWidgets('문제 있고 실행 중 아님 → [새로고침] 누르면 요청', (t) async {
    final idle = AiDeptStatus(bad.items, null);
    var asked = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AiDeptCard(loader: () async => idle, requester: (_) async => asked++))));
    await t.pumpAndSettle();
    expect(find.text('문제 3'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ai_dept_refresh')));
    await t.pumpAndSettle();
    expect(asked, 1);
  });

  testWidgets('단계별 [재시도] — 그 몫만 요청 · 요청 중인 단계는 [요청됨]', (t) async {
    final parts = <String?>[];
    final st = AiDeptStatus.fromRows(
      a7183: {'source': 'claude'}, review: {'source': 'gemini'},
      runs: [{'kind': 'ai_direction', 'status': 'failed', 'note': 'TimeoutError', 'created_at': '2026-11-25T18:32:00Z'},
             {'kind': 'ai_pension', 'status': 'failed', 'note': 'TimeoutError', 'created_at': '2026-11-25T18:44:00Z'}],
      requests: [{'id': 5, 'status': 'pending', 'parts': 'pension', 'requested_at': '2026-11-27T01:00:00Z'}],
    );
    expect(st.activeParts, {'pension'});
    t.view.physicalSize = const Size(1080, 2600);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: AiDeptCard(loader: () async => st, requester: (p) async => parts.add(p))))));
    await t.pump();
    await t.pump();
    await t.tap(find.byKey(const ValueKey('ai_dept_toggle')));
    await t.pump();
    expect(find.byKey(const ValueKey('ai_dept_retry_wait_pension')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_dept_retry_pension')), findsNothing);
    await t.tap(find.byKey(const ValueKey('ai_dept_retry_direction')));
    await t.pump();
    await t.pump();
    expect(parts, ['direction']);
    await t.pumpWidget(const SizedBox()); // 타이머 정리
  });

  test('7183 을 Claude 가 대신 쓴 주 — 문제 아님 · 이번 주 몫 완료', () {
    final s = AiDeptStatus.fromRows(a7183: {'source': 'claude'}, review: {'source': 'gemini'});
    expect(s.smooth, isTrue);
    expect(s.items.first.detail, contains('Claude 대행'));
    expect(s.week['a7183'], isTrue);
  });

  test('전략기획부를 Claude 가 대신 쓴 주 — 대행이라고 표시', () {
    final s = AiDeptStatus.fromRows(a7183: {'source': 'claude'}, review: {'source': 'gemini'}, runs: [
      {'kind': 'ai_direction', 'status': 'success', 'model': 'claude-fable-5-2 (gemini 대행)', 'created_at': '2026-11-27T03:00:00Z'},
    ]);
    expect(s.items[2].detail, 'Claude 대행 (이번 주만)');
    expect(s.items[2].ok, isTrue);
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
