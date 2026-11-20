// AI 브리핑전담부서 — 영역별 유지/보완 · 브리핑 메뉴 카드 한 줄 · 부서 화면
import 'package:flutter/material.dart';
import 'package:flutter_app/screens/admin_briefing_desk_screen.dart';
import 'package:flutter_app/services/research/set_review.dart';
import 'package:flutter_app/widgets/set_review_card.dart';
import 'package:flutter_test/flutter_test.dart';

final _payload = <String, dynamic>{
  'round': 1250, 'target_round': 1251, 'source': 'gemini', 'summary': '40 이상 번호가 많았습니다.',
  'review': {
    'actual': [1, 5, 18, 23, 27, 28], 'bonus': 8, 'best_hits': 2, 'won_sets': 0, 'sets': [], 'features': {},
    'areas': {
      'official': {'label': '① 엔진 추천번호', 'sets': 5, 'best_hits': 2, 'won': 0},
      'purchase': {'label': '③ 구매예측 번호', 'sets': 5, 'best_hits': 2, 'won': 0},
    },
  },
  'desk': {
    'official': {'keep': '유지 — 번호 합 낮은 쪽 흐름이 맞았음', 'improve': '보완 — 40 이상 번호를 줄일 것'},
    'purchase': {'keep': '특별히 없음', 'improve': '홀수 개수를 늘릴 것'},
  },
  'rules': [{'code': 'SR:win_high40:lower', 'feature': 'win_high40', 'expect': 'lower', 'statement': '40 이상 번호가 적은 조합을 더 고른다', 'why': '', 'source': 'gemini', 'w': 0.75}],
};

void main() {
  test('영역별 유지/보완 읽기 — 없는 영역은 null', () {
    final r = SetReview.fromPayload(_payload);
    expect(r.area('official')!.improve, '보완 — 40 이상 번호를 줄일 것');
    expect(r.area('purchase')!.keep, '특별히 없음');
    expect(r.area('popularity'), isNull);
  });

  testWidgets('브리핑 메뉴 카드 아래 — 유지 · 보완 한 줄 (앞의 "유지 —" 는 떼고) · 자료 없는 영역은 안 보임', (t) async {
    Future<SetReview?> load(int _) async => SetReview.fromPayload(_payload);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      BriefingDeskMemo(area: 'official', target: 1251, loader: load),
      BriefingDeskMemo(area: 'popularity', target: 1251, loader: load),
    ]))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('desk_memo_official')), findsOneWidget);
    expect(find.byKey(const ValueKey('desk_memo_popularity')), findsNothing);
    expect(find.text('AI 브리핑전담부서 · 1250회 복기 (제미나이)'), findsOneWidget);
    expect(find.text('번호 합 낮은 쪽 흐름이 맞았음'), findsOneWidget);
    expect(find.text('40 이상 번호를 줄일 것'), findsOneWidget);
  });

  testWidgets('부서 화면 — 제미나이 상주 · 영역별 판정 · 전달 내역', (t) async {
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: AdminBriefingDeskScreen(loader: () async => SetReview.fromPayload(_payload))));
    await t.pumpAndSettle();
    expect(find.text('제미나이 상주 · 판정 완료'), findsOneWidget);
    expect(find.text('1250회 → 1251회 영역별 판정'), findsOneWidget);
    expect(find.text('홀수 개수를 늘릴 것'), findsOneWidget);
    expect(find.textContaining('보완 규칙 1개'), findsOneWidget);
    expect(find.text('· 40 이상 번호가 적은 조합을 더 고른다'), findsOneWidget);
  });
}
