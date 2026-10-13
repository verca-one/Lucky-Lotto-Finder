// 엔진 복기 연구소 — 서버 저장 형식 해석 · 브리핑 카드 표시
import 'package:flutter/material.dart';
import 'package:flutter_app/screens/admin_engine_review_screen.dart';
import 'package:flutter_app/services/research/engine_review_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('지방장 회차 복기 (compact) 해석', () {
    // research_review_agents.py round_review 가 저장하는 형식 그대로
    final e = AgentRoundEntry.fromJson({
      'n': 193, 'rf': 2, 're': 3, 'r2': 1,
      'w': [
        ['14110486', 32, null, 0],
        ['14140320', 4, 4, 1],
      ],
      'h': [0, 0, 1], 'a5': 1, 'hh': 0, 'x': [0.0104, 0.0311, 0.0518],
      'g': {'lead': [1, 1, 0.161, 0], 'spatial': [4, 4, 3.203, 0]},
      'c': [
        ['ag1-6f697a', 'region_lead', 'researching', 'passed', 0, 1, 1.0, 1.84, 31, 9, 3.2, 0.0012],
      ],
      'cc': 7, 'nw': 2,
    });
    expect(e.nStores, 193);
    expect(e.regionFirst, 2);
    expect(e.noWinner, isFalse);
    expect(e.hits, [0, 0, 1]);
    expect(e.winners.first.priorRank, 32);
    expect(e.winners.first.hitRank, isNull); // 추천 밖
    expect(e.winners.last.hitRank, 4);
    expect(e.winners.last.normalized, isTrue); // 같은 이름·주소의 다른 코드
    expect(e.groups['spatial'], [4, 4, 3.203, 0]);
    expect(e.changes.single.applied, isTrue); // 실전 배수 1.0 → 1.84
    expect(e.changes.single.factorAfter, 1.84);
    expect(e.routine, 7);
    expect(e.newHyp, 2);

    final none = AgentRoundEntry.fromJson({'n': 5, 'rf': 0, 're': 0, 'r2': 0, 'h': [0, 0, 0], 'a5': 0, 'hh': 0, 'x': [0, 0, 0]});
    expect(none.noWinner, isTrue); // 지역에 1등이 없음 (추천 미적중과 구분)
    expect(none.winners, isEmpty);
  });

  test('예측 방식·등수 표기', () {
    expect(reviewModeLabel('live'), '실전 사전 예측');
    expect(reviewModeLabel('sequential_replay'), '과거 순차 재현');
    expect(reviewRankLabel(0), '낙첨');
    expect(reviewRankLabel(5), '5등');
  });

  testWidgets('엔진 브리핑 복기 카드: 저장된 브리핑 문장 그대로 표시', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EngineReviewBriefingCard(loader: () async => {
                'target_round': 1246,
                'status': 'final',
                'briefing': {
                  'lines': ['마스터, 1246회 복기 결과를 보고드리겠습니다.', '① 중앙 엔진 총평: 추천 지역 TOP10 중 실제 1등 지역 2곳'],
                },
              }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1246회 복기 브리핑'), findsOneWidget);
    expect(find.text('확정'), findsOneWidget);
    expect(find.text('마스터, 1246회 복기 결과를 보고드리겠습니다.'), findsOneWidget);
    expect(find.text('엔진 복기 연구소 열기'), findsOneWidget);
  });

  testWidgets('복기 없음: 지어내지 않고 대기 안내', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: EngineReviewBriefingCard(loader: () async => null))));
    await tester.pumpAndSettle();
    expect(find.textContaining('아직 복기가 없습니다'), findsOneWidget);
  });
}
