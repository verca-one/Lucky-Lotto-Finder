// 브리핑 ⑤ 가설 트랙 — 제미나이 가설 번호 5세트 · 명당 5곳
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/hypothesis_track.dart';
import 'package:flutter_app/widgets/hypothesis_track_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _payload = <String, dynamic>{
  'target_round': 1247, 'training_end_round': 1246, 'hypotheses_total': 164, 'status': 'registered',
  'window': [1047, 1246], 'popularity_target_pct': 56.4, 'popularity_drive': 0.287,
  'sets': [
    {'set': [7, 15, 17, 37, 38, 43], 'popularity_pct': 56.4},
    {'set': [6, 18, 20, 30, 33, 44], 'popularity_pct': 56.0},
  ],
  'used': [
    {'code': 'prev_rank1_many|R1|higher', 'statement': '직전 회차 1등 15명 이상일 때 1등 당첨자 쏠림이 높다', 'family': 'pop',
      'outcome': 'R1', 'expect': 'higher', 'status': 'rejected', 'recent': {'z': 1.197}, 'w': 1.197, 'm': 1.0},
    {'code': 'store:famous_10+dense_1km|first_second|higher', 'statement': '유명 명당 · 상권 밀집 판매점에서 1·2등이 더 나온다',
      'family': 'store', 'outcome': 'first_second', 'expect': 'higher', 'status': 'rejected', 'recent': {'mean_cond': 1.25},
      'factor': 1.25, 'm': 1.0},
  ],
  'stores': [
    {'store_code': 'S1', 'name': '월드24시', 'region': '서울', 'p_first': 0.01134, 'factor': 1.25, 'p_adj': 0.0142,
      'first': 6, 'second': 20, 'hyps': [1]},
  ],
  'skipped': {'condition_false': 55, 'unknown': 56, 'weak': 16, 'other': 3},
  'record': {'prev_rank1_many|R1|higher': [3, 2]},
};

void main() {
  testWidgets('가설 트랙 — 번호 · 명당(가설 이유) · 사용 가설 · 성적', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: HypothesisTrackCard(target: 1247, loader: (_) async => HypothesisTrack.fromPayload(_payload))))));
    await tester.pumpAndSettle();
    expect(find.text('1247회 가설 트랙 — 제미나이 가설'), findsOneWidget);
    expect(find.text('사전 등록'), findsOneWidget);
    expect(find.textContaining('토요일 아침 8시 최종 점검 뒤 이번 주 가설로 다시 뽑습니다'), findsOneWidget);
    expect(find.textContaining('가설 164개 중 이번 회차 사용: 번호 1개 · 명당 1개'), findsOneWidget);
    expect(find.textContaining('인기 백분위 56%'), findsOneWidget);
    expect(find.text('실전 성적: 가설 사용 3번 중 방향 맞힘 2번'), findsOneWidget);
    expect(find.text('월드24시'), findsOneWidget);
    expect(find.text('가설: 유명 명당 · 상권 밀집 판매점에서 1·2등이 더 나온다'), findsOneWidget);
    expect(find.text('1.42%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('track_hyps_toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('가설 공장 기각 · 그래도 사용'), findsNWidgets(2));
  });

  testWidgets('공개 전이면 안내만', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HypothesisTrackCard(
        target: 1248, released: false, loader: (_) async => null))));
    await tester.pumpAndSettle();
    expect(find.textContaining('수요일 0시(또는 수동 추천) 이후'), findsOneWidget);
  });
}
