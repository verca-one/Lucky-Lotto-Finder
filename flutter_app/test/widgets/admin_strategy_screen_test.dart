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
      'verdict': '검증 통과'}),
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
    // 통과·유지만
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
  });
}
