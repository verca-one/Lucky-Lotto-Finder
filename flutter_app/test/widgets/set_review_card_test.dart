// AI 전략기획부 추천번호 복기 카드
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/set_review.dart';
import 'package:flutter_app/widgets/set_review_card.dart';
import 'package:flutter_test/flutter_test.dart';

final _payload = <String, dynamic>{
  'round': 1247, 'target_round': 1248, 'source': 'gemini', 'model': 'gemini-3.8-flash',
  'summary': '추천 20세트가 홀수 많은 쪽에 몰렸습니다.',
  'review': {
    'actual': [8, 14, 21, 22, 42, 45], 'bonus': 24, 'best_hits': 3, 'won_sets': 2,
    'sets': List.generate(20, (i) => {'nums': [1, 2, 3, 4, 5, 6]}),
    'areas': {
      'official': {'label': '① 엔진 추천번호', 'sets': 5, 'best_hits': 1, 'won': 0},
      'hypothesis': {'label': '④ 제미나이 가설 추천번호', 'sets': 5, 'best_hits': 1, 'won': 0},
    },
    'features': {
      'win_odd': {'name': '홀수 개수', 'actual': 2, 'median': 3.0, 'sets_mean': 3.75, 'actual_side': 'lower', 'same_side_sets': 2, 'missed': true},
      'win_sum': {'name': '번호 합', 'actual': 152, 'median': 139.5, 'sets_mean': 152.05, 'actual_side': 'higher', 'same_side_sets': 11, 'missed': false},
    },
    'missed_numbers': [8], 'over_numbers': [41, 43],
  },
  'rules': [
    {'code': 'SR:win_odd:lower', 'feature': 'win_odd', 'expect': 'lower', 'statement': '다음 회차는 홀수 개수가 낮은 쪽 조합을 더 고른다',
     'why': '최근 3회 중 2회 어긋남', 'source': 'gemini', 'w': 0.9, 'repeat': 2, 'weeks': 3},
  ],
  'persistence': {'rounds': [1247, 1246, 1245]},
};

void main() {
  testWidgets('복기 — 당첨번호 · 영역별 결과 · 아쉬운 부분 · 보완 규칙(가설 트랙 반영) · 특징 펼치기', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: SetReviewCard(loader: () async => SetReview.fromPayload(_payload))))));
    await tester.pumpAndSettle();
    expect(find.text('추천번호 복기 · 1247회 → 1248회 보완'), findsOneWidget);
    expect(find.text('제미나이'), findsOneWidget);
    expect(find.text('최고 3개 일치 · 당첨 2세트'), findsOneWidget);
    expect(find.text('① 엔진 추천번호: 최고 1개 일치 · 당첨 0세트'), findsOneWidget);
    expect(find.text('· 홀수 개수: 당첨 2 (낮은 쪽) — 같은 쪽 세트 2/20'), findsOneWidget);
    expect(find.text('· 20세트 어디에도 없던 당첨번호: 8'), findsOneWidget);
    expect(find.text('1248회 가설 트랙 반영'), findsOneWidget);
    expect(find.byKey(const ValueKey('set_review_rule_SR:win_odd:lower')), findsOneWidget);
    expect(find.text('힘 0.90 · 최근 3회 중 2회 같은 방향으로 어긋남'), findsOneWidget);
    expect(find.textContaining('번호 합: 당첨 152'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('set_review_toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('번호 합: 당첨 152'), findsOneWidget);
  });

  testWidgets('복기 없으면 안내', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SetReviewCard(loader: () async => null))));
    await tester.pumpAndSettle();
    expect(find.textContaining('아직 복기가 없습니다'), findsOneWidget);
  });
}
