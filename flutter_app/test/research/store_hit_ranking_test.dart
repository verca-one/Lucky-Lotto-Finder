// 판매점 적중 예측 순위 (hs-apply) — 검증 가설 배수 반영 선정 · 순위 카드
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/agent_research_repository.dart';
import 'package:flutter_app/services/research/master_briefing_service.dart';
import 'package:flutter_app/services/research/store_hit_ranking.dart';
import 'package:flutter_app/widgets/briefing_store_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AgentDelivery _d(String agent, String code, int rank, double p) => AgentDelivery.fromRow({
      'model_version': 'ag-1.1', 'target_round': 1247, 'agent_id': agent, 'store_code': code, 'mode': 'live',
      'rank': rank, 'score': p * 7, 'p_first': p,
    });

final _payload = <String, dynamic>{
  'target_round': 1247, 'training_end_round': 1246, 'stores_scored': 8800,
  'hypotheses': [
    {'code': 'store:famous_10|first|higher', 'label': '로또 1등 10회 이상 (유명 명당)', 'statement': 's', 'outcome': 'first',
      'status': 'validated', 'factor': 1.33, 'stores_now': 52,
      'sim': {'status': 'done', 'hits_hyp': 1143, 'hits_base': 1143, 'raised': false}},
    {'code': 'store:own_first_52|first_second|higher', 'label': '본인이 최근 52회 안에 1등', 'statement': 's',
      'outcome': 'first_second', 'status': 'validated', 'factor': 1.16, 'stores_now': 604, 'sim': {}},
  ],
  'ranking': [
    {'rank': 1, 'base_rank': 1, 'store_code': 'NET', 'agent_id': 'internet', 'name': '인터넷 복권판매사이트', 'region': '',
      'first': 90, 'second': 300, 'p_first': 0.093, 'factor': 1.0, 'p_adj': 0.093, 'hyps': []},
    {'rank': 2, 'base_rank': 3, 'store_code': 'A', 'agent_id': '부산|부산진구', 'name': '부일카서비스', 'region': '부산',
      'first': 40, 'second': 90, 'p_first': 0.036, 'factor': 1.33, 'p_adj': 0.0479, 'hyps': [0, 1]},
    {'rank': 3, 'base_rank': 2, 'store_code': 'B', 'agent_id': '서울|노원구', 'name': '스파', 'region': '서울',
      'first': 5, 'second': 20, 'p_first': 0.04, 'factor': 1.0, 'p_adj': 0.04, 'hyps': []},
  ],
  'factors': {'A': {'f': 1.33, 'h': [0, 1]}, 'C': {'f': 1.16, 'h': [1]}},
};

void main() {
  test('지방장별 납품 중 1등 확률 × 가설 배수 최대 1곳 — 가설 없으면 납품 1위', () {
    final ds = [_d('경기|수원시', 'X', 1, 0.010), _d('경기|수원시', 'C', 2, 0.009), _d('부산|부산진구', 'A', 1, 0.036),
      _d('부산|부산진구', 'Z', 2, 0.030)];
    final hit = StoreHitRanking.fromPayload(_payload);
    final p = pickByHit(ds, hit.factorOf);
    expect(p['경기|수원시']!.storeCode, 'C'); // 0.009 × 1.16 = 0.01044 > 0.010
    expect(p['부산|부산진구']!.storeCode, 'A');
    final plain = pickByHit(ds, (_) => 1.0);
    expect(plain['경기|수원시']!.storeCode, 'X');
  });

  test('저장본 해석 — 배수 · 맞는 가설(배수 큰 순)', () {
    final hit = StoreHitRanking.fromPayload(_payload);
    expect(hit.factorOf('A'), 1.33);
    expect(hit.factorOf('none'), 1.0);
    expect(hit.hypothesesOf('A').map((h) => h.factor), [1.33, 1.16]);
    expect(hit.ranking[1].boosted, isTrue);
    expect(hit.ranking.first.isOnline, isTrue);
    expect(hit.simRaisedCount, 0);
  });

  testWidgets('적중 예측 높은 순 카드 — 인터넷 판매 기본 제외 · 가설 배수 · 순위 변화 · 이번 주 추천', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final hit = StoreHitRanking.fromPayload(_payload);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: StoreHitRankingCard(ranking: hit, targetRound: 1247, pickCodes: const {'B'})))));
    await tester.pumpAndSettle();
    expect(find.text('적중 예측 높은 순 — 1247회 전국'), findsOneWidget);
    expect(find.textContaining('누르면'), findsOneWidget); // 처음엔 접힘 (위 3곳 미리보기)
    expect(find.text('부일카서비스'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('store_hit_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('인터넷 복권판매사이트'), findsNothing);
    expect(find.text('부일카서비스'), findsOneWidget);
    expect(find.text('가설 ×1.33'), findsOneWidget);
    expect(find.text('▲1'), findsOneWidget);
    expect(find.text('▼1'), findsOneWidget);
    expect(find.text('이번 주 추천'), findsOneWidget);
    expect(find.text('4.79%'), findsOneWidget);
    expect(find.textContaining('1등 적중이 늘지 않았습니다'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hit_online_filter')));
    await tester.pumpAndSettle();
    expect(find.text('인터넷 복권판매사이트'), findsOneWidget);
  });

  testWidgets('다른 회차 저장본이면 안내만', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StoreHitRankingCard(
        ranking: StoreHitRanking.fromPayload(_payload), targetRound: 1248))));
    expect(find.byKey(const ValueKey('store_hit_ranking_empty')), findsOneWidget);
  });

  testWidgets('추천 명당 예측 줄 — 지방장 추정 × 가설 배수', (tester) async {
    final hit = StoreHitRanking.fromPayload(_payload);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StoreHitLine(
        pFirst: 0.036, factor: 1.33, hypotheses: hit.hypothesesOf('A')))));
    expect(find.text('4.79%'), findsOneWidget);
    expect(find.text('지방장 추정 3.60% × 검증 가설 ×1.33'), findsOneWidget);
  });
}
