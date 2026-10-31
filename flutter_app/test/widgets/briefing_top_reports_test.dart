// 엔진 브리핑 맨 위 보고 — 수집 현황 · 지방장 적중 · 연구 요약 · 숨은 명당
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/agent_research_repository.dart';
import 'package:flutter_app/services/research/round_debrief.dart';
import 'package:flutter_app/services/round_status_service.dart';
import 'package:flutter_app/widgets/agent_hidden_stores_card.dart';
import 'package:flutter_app/widgets/briefing_top_reports.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime kst(int d, int h, int m) => DateTime.utc(2026, 10, d, h, m).subtract(const Duration(hours: 9));

RoundCardInfo card(String type, int round, int day, RoundStatus st) =>
    RoundCardInfo(type: type, round: round, drawDate: DateTime(2026, 10, day), status: st);

AgentDelivery dl(String agent, String code, int rank, double p, {int first = 0, int? since = 10}) => AgentDelivery.fromRow({
      'target_round': 1248, 'agent_id': agent, 'store_code': code, 'rank': rank, 'p_first': p, 'store_name': code,
      'history': {'first': first, 'second': 3, 'rounds_since_last': since},
    });

void main() {
  test('수집 현황 문장 — 완료 · 번호만 · 3시간 넘으면 지연 · 추첨 전', () {
    final now = kst(31, 22, 0);
    expect(collectLine('로또', card('lotto', 1248, 31, RoundStatus.complete), now).$1, '로또 1248회 — 당첨번호 ✓ · 판매점 ✓ 수집 완료');
    final n = collectLine('로또', card('lotto', 1248, 31, RoundStatus.numbersReady), now);
    expect(n, ('로또 1248회 — 당첨번호 ✓ · 판매점 수집 대기 (추첨 후 1시간 25분)', false));
    final late = collectLine('로또', card('lotto', 1248, 31, RoundStatus.awaiting), kst(31, 23, 59));
    expect(late.$2, isTrue);
    expect(late.$1, endsWith('· 지연'));
    expect(collectLine('연금', card('pension', 340, 29, RoundStatus.scheduled), kst(29, 10, 0)).$1, '연금 340회 — 추첨 전');
  });

  testWidgets('수집 현황 상자 — 지연이면 주황 · 안내', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CollectStatusReport(
      clock: () => kst(31, 23, 59),
      loader: () async => [('로또', card('lotto', 1248, 31, RoundStatus.numbersReady)), ('연금', card('pension', 339, 29, RoundStatus.complete))],
    ))));
    await tester.pump();
    expect(find.byKey(const ValueKey('collect_status_report')), findsOneWidget);
    expect(find.textContaining('로또 1248회 — 당첨번호 ✓ · 판매점 수집 대기'), findsOneWidget);
    expect(find.text('• 연금 339회 — 당첨번호 ✓ · 판매점 ✓ 수집 완료'), findsOneWidget);
    expect(find.textContaining('서버 예약 실행이 밀리는 중'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('지방장 적중 — TOP5 중 1·2등 난 판매점만 · 1등 먼저', () {
    final d = AgentDebrief.fromPayload({
      'round': 1247, 'next': 1248, 'summary': {},
      'agents': [
        {'id': '강원|영월군', 'label': '강원 영월군', 'prev': [['A', '영월복권', 3, 0.01, 2], ['B', '없음', 1, 0.02, 0]]},
        {'id': '서울|노원구', 'label': '서울 노원구', 'prev': [['C', '스파', 1, 0.03, 1]]},
        {'id': 'internet', 'label': '인터넷', 'prev': [['D', '인터넷', 1, 0.09, 0]]},
      ],
    });
    expect(agentHits(d), [('서울 노원구', '스파', 1, 1), ('강원 영월군', '영월복권', 2, 3)]);
  });

  test('연구 요약 — ③④⑤⑥ 문장 · 근거 수치(p값) 없음', () {
    final b = AgentBriefing(payload: {
      'famous_cycles': {'tested': 108, 'by_status': {'rejected': 41, 'weakened': 40, 'researching': 27},
        'examples': [{'summary': '행운의집 당첨 간격 5~26회 구간에 재당첨 증가', 'test_p': 0.027}]},
      'cowin': {'counts': {'store_pairs': 512, 'region_pairs': 0}, 'store_pairs': []},
      'lead_lag': {'counts': {'a': 3250, 'b': 2619}, 'examples': [{'summary': '전남|순천시 1등 +2회 후 서울|관악구 1등 증가'}]},
      'shared': {'templates': 12, 'new_this_checkpoint': 3, 'conflicts': 0},
    }, targetRound: 1248);
    final l = agentDigestLines(b);
    expect(l.length, 4);
    expect(l[0], startsWith('유명 명당 반복 당첨 — 108곳 살펴봄 ('));
    expect(l[0], contains('행운의집'));
    expect(l[1], contains('512건'));
    expect(l[2], contains('5869건'));
    expect(l[3], '새로 공유된 가설 — 지방장끼리 공유한 가설 12종, 이번에 새로 3건.');
    expect(l.any((x) => x.contains('p=') || x.contains('0.027')), isFalse);
  });

  test('숨은 명당 — 유명(1등 3회↑ · 전국 상위) · 인터넷 · 2년 넘게 조용한 곳 제외 · 시·도마다 1곳 · 확률×가설 배수 순', () {
    final all = [
      dl('서울|노원구', 'famous', 1, 0.05, first: 5),
      dl('서울|강남구', 'top20', 1, 0.04),
      dl('internet', 'net', 1, 0.09),
      dl('강원|영월군', 'old', 1, 0.03, since: 200),
      dl('서울|송파구', 's1', 2, 0.02),
      dl('서울|마포구', 's2', 1, 0.018),
      dl('경북|안동시', 'k1', 3, 0.01),
      dl('전남|순천시', 'j1', 2, 0.009),
    ];
    final r = pickHiddenStores(all, {'top20'}, (c) => c == 'j1' ? 1.5 : 1.0);
    expect(r.map((h) => h.d.storeCode), ['s1', 'j1', 'k1']);
    expect(r[1].value, closeTo(0.0135, 1e-9));
  });

  testWidgets('지방장 적중 아래 — 다음 회차 지방장 추천점(접힘 → 누르면 펼침) · 맞힌 지방장 TOP3만', (tester) async {
    final d = AgentDebrief.fromPayload({
      'round': 1247, 'next': 1248, 'summary': {},
      'agents': [
        {'id': '서울|노원구', 'label': '서울 노원구', 'prev': [['C', '스파', 1, 0.03, 1]],
          'next': [['C', '스파', 1, 0.03, 'kept', 1], ['E', '새가게', 2, 0.02, 'new', null], ['F', '넷째', 4, 0.01, 'new', null]]},
        {'id': '부산|동구', 'label': '부산 동구', 'prev': [['X', '빗나감', 1, 0.03, 0]], 'next': [['Y', '안보임', 1, 0.03, 'kept', 1]]},
      ],
    });
    expect(agentNextPicks(d), [('서울 노원구', '스파', 1, false), ('서울 노원구', '새가게', 2, true)]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AgentHitsReport(loader: () async => d)))));
    await tester.pumpAndSettle();
    expect(find.text('다음 회차(1248회) 지방장 추천점 · 2곳'), findsOneWidget);
    expect(find.text('서울 노원구 · 새가게'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('agent_next_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('서울 노원구 · 새가게'), findsOneWidget);
    expect(find.text('부산 동구 · 안보임'), findsNothing);
  });
}
