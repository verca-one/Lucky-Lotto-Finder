// 브리핑 7183 에이전트 카드 — 번호 5세트 · 제미나이 참여/계산 표시 · 황금 상자(있을 때만) · 일하고 있다는 표시
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/agent7183.dart';
import 'package:flutter_app/widgets/agent7183_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> payload({String source = 'rule', List<int> gold = const [], List<String> done = const []}) => {
      'target_round': 1252, 'source': source, 'sets_status': 'registered', 'sets_by': source,
      'sets': [[7, 25, 27, 29, 37, 42], [7, 10, 22, 27, 28, 32]],
      'gold_numbers': gold, 'scanned': 28698, 'alive_total': 9, 'completed_now': done,
      'alive': [{'id': 1, 'law': '6번째 번호 · 그 회차 값 · 그대로', 'mode': '주기 1회', 'run': 3, 'next': 0, 'chance': 0.114}],
      'trusted': [{'law': '6번째 번호 · 그 회차 값 · 그대로', 'mode': '주기 1회', 'run': 3, 'next': 0, 'chance': 0.114, 'why': '가장 좁게 짚음'}],
      'cycles': [{'name': '7381', 'digits': [7, 3, 8, 1], 'by': 'seed', 'replay': [5, 63, 5.92], 'since': [5, 63, 5.92]}],
      'scout': {
        'gold': [if (gold.isNotEmpty) {'lag': 1, 'x': 5, 'y': gold.first, 'hits': 48, 'fired': 160}],
        'nearest': [{'ratio': 1.75, 'lag': 3, 'x': 25, 'y': 24, 'hits': 36, 'fired': 154, 'streak': 0}],
      },
      'scoreboard': {'from': 1001, 'to': 1251, 'sets': {'n': 1255, 'mean': 0.766, 'ge3': 22}},
      'record': {'trusted': [0, 0, 0.0], 'sets': [10, 9, 1], 'gold': [2, 1]},
      'dream': source == 'gemini' ? '끝수 순환이 맨 뒤 번호로 넘어가는 중입니다.' : '',
    };

Future<void> pump(WidgetTester t, Agent7183? a, {bool released = true}) async {
  SharedPreferences.setMockInitialValues({});
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: Agent7183Card(target: 1252, released: released, loader: (_) async => a)))));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('계산값 주 — 번호 5세트 · 계산 표시 · 황금 상자 없음 · 조수가 일한 표시 · 성적표', (t) async {
    await pump(t, Agent7183.fromPayload(payload()));
    expect(find.text('계산 · 제미나이 대기'), findsOneWidget);
    expect(find.text('42'), findsNothing); // 제미나이 대기 중이면 접혀 있음
    await t.tap(find.byKey(const ValueKey('a7183_toggle')));
    await t.pumpAndSettle();
    expect(find.text('사전 등록 · 계산'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.byKey(const ValueKey('a7183_gold')), findsNothing);
    expect(find.textContaining('패턴 28698개를 살펴봤습니다 · 확실한 패턴 없음'), findsOneWidget);
    expect(find.textContaining('25이 나오면 3회 뒤 24'), findsOneWidget);
    expect(find.textContaining('실전 10세트 평균 0.90개'), findsOneWidget);
    expect(find.textContaining('복기(1001~1251회) 1255세트 평균 0.77개'), findsOneWidget);
    expect(find.byKey(const ValueKey('a7183_dream')), findsNothing);
    await t.tap(find.byKey(const ValueKey('a7183_more')));
    await t.pumpAndSettle();
    expect(find.textContaining('7381: 7→3→8→1 (사장님)'), findsOneWidget);
  });

  testWidgets('제미나이 참여 · 조수의 황금 숫자 · 법칙 완성 알림', (t) async {
    await pump(t, Agent7183.fromPayload(payload(source: 'gemini', gold: [33], done: ['끝수돌기'])));
    expect(find.text('제미나이 참여'), findsOneWidget);
    expect(find.byKey(const ValueKey('a7183_gold')), findsOneWidget);
    expect(find.text('33'), findsOneWidget);
    expect(find.textContaining('5이 나오면 1회 뒤 33 — 과거 160번 중 48번 적중'), findsOneWidget);
    expect(find.textContaining('황금 숫자 누적 2개 중 1개 적중'), findsOneWidget);
    expect(find.byKey(const ValueKey('a7183_scout_working')), findsNothing);
    expect(find.textContaining('법칙 완성 — 끝수돌기'), findsOneWidget);
    expect(find.text('끝수 순환이 맨 뒤 번호로 넘어가는 중입니다.'), findsOneWidget);
  });

  testWidgets('주중에 제미나이가 답해 추가한 번호 — 월요일 계산 번호는 그대로, 따로 한 상자', (t) async {
    await pump(t, Agent7183.fromPayload({
      ...payload(source: 'gemini'), 'sets_by': 'rule',
      'late_sets': [[1, 2, 3, 4, 5, 6], [11, 12, 13, 14, 15, 16]], 'late_sets_at': '2026-11-26T12:00:00Z',
    }));
    expect(find.text('사전 등록 · 계산'), findsOneWidget); // 월요일 번호 표시는 그대로
    expect(find.byKey(const ValueKey('a7183_late_sets')), findsOneWidget);
    expect(find.text('제미나이 번호 5세트 — 주중 추가 (11/26)'), findsOneWidget);
  });

  testWidgets('Claude 대행 주 — 회색 대기 아님 · 대행 표시 · 주중 추가 번호도 대행 이름', (t) async {
    await pump(t, Agent7183.fromPayload({
      ...payload(source: 'gemini'), 'source': 'claude', 'sets_by': 'rule',
      'late_sets': [[1, 2, 3, 4, 5, 6]], 'late_sets_at': '2026-11-26T12:00:00Z', 'late_sets_by': 'claude',
    }));
    expect(find.byKey(const ValueKey('a7183_waiting')), findsNothing);
    expect(find.text('Claude 대행 (이번 주만)'), findsOneWidget);
    expect(find.text('제미나이 참여'), findsNothing);
    expect(find.text('Claude(대행) 번호 5세트 — 주중 추가 (11/26)'), findsOneWidget);
    expect(find.text('Claude(대행)가 믿는 법칙'), findsOneWidget);
  });

  testWidgets('번호에 실리는 힘 · 이어받기 표 (a7183-1.1 저장본)', (t) async {
    final p = payload(source: 'gemini');
    (p['scoreboard'] as Map)['mode_w'] = {'주기 1회': 0.0, '주기 2회': 0.0161};
    (p['scoreboard'] as Map)['handover'] = [
      {'dead': '앞', 'n': 157, 'born': {'앞': 1.07, '가운데': 1.01, '뒤': 0.94, '전체': 0.94}},
      {'dead': '전체', 'n': 0, 'born': {'앞': null}},
    ];
    (p['scoreboard'] as Map)['last_dead'] = ['앞', '뒤'];
    (p['scoreboard'] as Map)['rule_trust'] = [247, 714, 242.8];
    await pump(t, Agent7183.fromPayload(p));
    expect(find.textContaining('주기 2회 0.016'), findsOneWidget);
    expect(find.textContaining('앞에서 끊긴 뒤: 앞 1.07배'), findsOneWidget);
    expect(find.textContaining('전체에서 끊긴 뒤'), findsNothing);
    expect(find.text('· 지난 회차에 끊긴 자리: 앞, 뒤'), findsOneWidget);
    expect(find.textContaining('복기 714번 중 247번 적중 · 우연이면 242.8번'), findsOneWidget); // 제미나이 없는 주의 근거
  });

  testWidgets('예전 저장본(힘 · 이어받기 표 없음)에는 그 칸이 없음', (t) async {
    await pump(t, Agent7183.fromPayload(payload(source: 'gemini')));
    expect(find.byKey(const ValueKey('a7183_mode_w')), findsNothing);
    expect(find.byKey(const ValueKey('a7183_rule_trust')), findsNothing);
    expect(find.byKey(const ValueKey('a7183_handover')), findsNothing);
  });

  testWidgets('번호마다 따른 법칙 표기 (★ = 믿는 법칙) · 법칙 줄에 번호와 조건', (t) async {
    final p = payload(source: 'gemini');
    p['trusted'] = [
      {...Map<String, dynamic>.from((p['trusted'] as List).first as Map), 'id': 1, 'cond': '6번째 번호: 22 · 32 · 42', 'how': '설명'},
    ];
    p['sets_laws'] = [[1, 3], []];
    await pump(t, Agent7183.fromPayload(p));
    expect(find.text('법칙 ★1 · 3'), findsOneWidget);
    expect(find.text('만족하는 법칙 없음'), findsOneWidget);
    expect(find.textContaining('법칙 1 — 6번째 번호: 22 · 32 · 42 | '), findsOneWidget);
  });

  testWidgets('늦은 번호 없으면 상자 없음', (t) async {
    await pump(t, Agent7183.fromPayload(payload(source: 'gemini')));
    expect(find.byKey(const ValueKey('a7183_late_sets')), findsNothing);
  });

  testWidgets('공개 전 · 저장본 없음 안내', (t) async {
    await pump(t, null, released: false);
    expect(find.textContaining('월요일 0시(또는 수동 추천) 이후 서버가 뽑습니다'), findsOneWidget);
    await pump(t, null);
    expect(find.textContaining('7183 에이전트 저장본 없음'), findsOneWidget);
  });
}
