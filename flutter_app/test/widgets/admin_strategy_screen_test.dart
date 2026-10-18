// AI 전략기획부 화면 — 방향·가설·검증 단계 표시 (휴대폰 폭)
import 'package:flutter/material.dart';
import 'package:flutter_app/screens/admin_strategy_screen.dart';
import 'package:flutter_app/services/research/strategy_repository.dart';
import 'package:flutter_test/flutter_test.dart';

StrategyData data() {
  final dirs = [
    StrategyDirection.fromRow({'id': 'd1', 'source': 'manual', 'title': '날짜·회차 홀짝과 계절이 당첨 결과에 영향을 주는가',
      'rationale': '관리자 제안', 'after_round': 1246, 'focus': 'calendar'}),
    StrategyDirection.fromRow({'id': 'd2', 'source': 'ai', 'model': 'claude-opus-5-5', 'title': '판매액 급증 회차의 인기 조합 쏠림',
      'rationale': '이월 회차에 수동 구매가 몰린다는 가정', 'after_round': 1246, 'focus': 'sales'}),
  ];
  final hyps = [
    StrategyHypothesis.fromRow({'id': 'h1', 'direction_id': 'd1', 'code': 'round_odd|R2|higher', 'statement': '홀수 회차일 때 2등 당첨자 쏠림가 높다',
      'spec': {'condition': 'round_odd', 'outcome': 'R2', 'expect': 'higher'}, 'status': 'rejected', 'created_round': 1246,
      'discovery': {'from': 269, 'to': 1000, 'n_cond': 366, 'n_other': 366, 'mean_cond': 0.988, 'mean_other': 1.003, 'p': 0.871, 'direction_ok': false},
      'verdict': '기각 — 발견 구간에서 차이 없음'}),
    StrategyHypothesis.fromRow({'id': 'h2', 'direction_id': 'd2', 'code': 'sales_surge|R1|higher', 'statement': '판매액 급증일 때 1등 쏠림이 높다',
      'spec': {'condition': 'sales_surge', 'outcome': 'R1', 'expect': 'higher'}, 'status': 'validated', 'created_round': 1246,
      'discovery': {'from': 269, 'to': 1000, 'n_cond': 60, 'n_other': 600, 'mean_cond': 1.2, 'mean_other': 0.98, 'p': 0.01, 'direction_ok': true},
      'confirm': {'from': 1001, 'to': 1246, 'n_cond': 20, 'n_other': 200, 'mean_cond': 1.15, 'mean_other': 0.99, 'p': 0.02, 'direction_ok': true},
      'verdict': '검증 통과',
      'simulation': {'status': 'done', 'lift': 0.99, 'raised': false, 'p_strategy': 0.023, 'p_random': 0.0232,
        'note': '확률 상승 없음 — 5등 이상 2.30% vs 무작위 2.32%'}}),
    StrategyHypothesis.fromRow({'id': 'h3', 'direction_id': 'd1', 'code': 'first_half+winter|R1|higher',
      'statement': '상반기(1~6월)이면서 겨울(12~2월)일 때 1등 당첨자 쏠림가 높다',
      'spec': {'condition': 'first_half', 'condition2': 'winter', 'outcome': 'R1', 'expect': 'higher', 'kind': 'supplement', 'parent': 'round_odd|R2|higher'},
      'status': 'rejected', 'created_round': 1247, 'verdict': '기각'}),
    StrategyHypothesis.fromRow({'id': 'h4', 'direction_id': 'd1', 'code': 'round_odd|R2|higher#pt1247',
      'statement': '홀수 회차일 때 2등 당첨자 쏠림가 높다',
      'spec': {'condition': 'round_odd', 'outcome': 'R2', 'expect': 'higher', 'kind': 'partial', 'parent': 'round_odd|R2|higher'},
      'status': 'provisional', 'created_round': 1247, 'verdict': '임시 일부 발췌'}),
    StrategyHypothesis.fromRow({'id': 'h5', 'direction_id': 'd2', 'code': 'store:near_first_prev|first|higher',
      'statement': '반경 3km 안 다른 판매점에서 직전 회차 1등 판매점에서 다음 회차 1등가 지방장 기대보다 더 많이 나온다',
      'spec': {'condition': 'near_first_prev', 'outcome': 'first', 'expect': 'higher', 'kind': 'base', 'level': 'store'},
      'status': 'rejected', 'created_round': 1247, 'verdict': '기각',
      'discovery': {'from': 600, 'to': 1000, 'unit': 'store', 'n_cond': 176, 'n_other': 4000, 'expected_cond': 192.3,
        'mean_cond': 0.915, 'mean_other': 1.005, 'p': 0.895, 'direction_ok': false},
      'simulation': {'status': 'done', 'unit': 'store', 'hits_hyp': 1134, 'hits_base': 1143, 'lift': 0.99, 'raised': false,
        'note': '적중 상승 없음 — 시·군·구 TOP5 1등 적중 1134곳 vs 이력만 1143곳'}}),
  ];
  final runs = [StrategyRun.fromRow({'kind': 'ai_direction', 'status': 'skipped', 'after_round': 1246, 'stats': {}, 'note': 'API 키 미등록'}),
    StrategyRun.fromRow({'kind': 'factory', 'status': 'success', 'after_round': 1246, 'stats': {'evaluated': 6}})];
  return StrategyData(dirs, hyps, runs);
}

void main() {
  testWidgets('방향 카드 · 가설 상태 · 필터 · 상세 단계', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AdminStrategyScreen(loader: () async => data())));
    await tester.pumpAndSettle();
    expect(find.textContaining('API 키 미등록'), findsOneWidget);
    expect(find.text('AI 제안'), findsWidgets);
    expect(find.byKey(const ValueKey('hyp_round_odd|R2|higher')), findsOneWidget);
    // 원본 아래 파생 가설 묶음 (보충회생 1 · 임시 일부 발췌 1)
    expect(find.textContaining('파생 가설 2건'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('kids_round_odd|R2|higher')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kids_round_odd|R2|higher')));
    await tester.pumpAndSettle();
    expect(find.text('임시'), findsWidgets);
    expect(find.text('보충회생'), findsOneWidget);
    // 원본 상세: 계보
    await tester.ensureVisible(find.byKey(const ValueKey('hyp_round_odd|R2|higher')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hyp_round_odd|R2|higher')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('계보'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('계보'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20)); // 시트 닫기
    await tester.pumpAndSettle();
    // 통과·유지만
    await tester.scrollUntilVisible(find.byKey(const ValueKey('stage_passed')), -300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('stage_passed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hyp_round_odd|R2|higher')), findsNothing);
    expect(find.byKey(const ValueKey('hyp_sales_surge|R1|higher')), findsOneWidget);
    // 상세: 발견·확인·추적 단계
    await tester.ensureVisible(find.byKey(const ValueKey('hyp_sales_surge|R1|higher')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hyp_sales_surge|R1|higher')));
    await tester.pumpAndSettle();
    expect(find.text('발견 구간'), findsOneWidget);
    expect(find.text('확인 구간'), findsOneWidget);
    expect(find.text('새 회차 추적'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('가설 모의'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('상승 없음'), findsOneWidget);
  });

  testWidgets('판매점 가설 — 판매점 배지 · 지방장 기대 대비 · TOP5 모의', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AdminStrategyScreen(loader: () async => data())));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('hyp_store:near_first_prev|first|higher'));
    await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
    expect(find.descendant(of: row, matching: find.text('판매점')), findsOneWidget);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.textContaining('지방장 기대 192.3'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('가설 모의'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('시·군·구 TOP5'), findsWidgets);
  });
}
