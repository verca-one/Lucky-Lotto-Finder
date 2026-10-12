// 연구는 서버만 실행 — 앱은 저장된 결과만 읽는다
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/purchase_prediction_engine.dart';
import 'package:flutter_app/services/research/research_runtime.dart';
import 'package:flutter_app/services/research/research_scheduler.dart';
import 'package:flutter_app/widgets/server_pipeline_status_card.dart';
import 'package:flutter_test/flutter_test.dart';

final storedPayload = {
  'training_end': 1245,
  'target_round': 1246,
  'validation_status': '검증 통과 — 번호 인기도 모델 (1050~1245회 순방향 검증)',
  'ranking_source': 'popularity',
  'prize_stats_rounds': 977,
  'candidate_median_score': 0.12,
  'data_gaps': ['실제 구매 조합별 선택 빈도: 미확보'],
  'feature_insights': [
    {'name': '1~31 개수', 'direction': '인기↑ 추정', 'source': '휴리스틱(가정)', 'strength': 0.25},
  ],
  'empirical': {
    'available': true, 'n_train': 6323, 'n_test': 2693, 'train_rounds': [265, 1000], 'test_rounds': [1001, 1245],
    'improvement': 0.0019, 'improvement_ci': [-0.012, 0.015], 'gate_pass': false, 'gate_reason': '게이트 미통과',
    'coefs': [
      {'key': 'ge40', 'name': '40 이상', 'coef': -0.2, 'se': 0.05, 'z': -4.0, 'p': 0.0001, 'p_holm': 0.001},
    ],
    'replicated_keys': ['ge40'],
  },
  'volume': {'available': true, 'n_train': 781, 'n_test': 196, 'gate_pass': false, 'gate_reason': '게이트 미통과',
    'improvement': -56.6, 'improvement_ci': [-139.8, 20.1]},
  'popularity': {
    'available': true, 'gate_pass': true, 'gate_reason': '→ 통과', 'n_train': 781, 'n_test': 196,
    'train_rounds': [269, 1049], 'test_rounds': [1050, 1245], 'h1_corr': 0.78, 'h1_p': 0.00001, 'h1_r2': 0.6,
    'h2_coef': 1.0, 'h2_p': 0.0026, 'low_cowin_ratio': 0.8, 'high_cowin_ratio': 1.2, 'test_pred_range': [-0.3, 0.4],
    'least_popular_numbers': [21, 22, 29], 'most_popular_numbers': [17, 40, 27],
  },
  'recommendations': [
    {'numbers': [21, 22, 23, 29, 35, 36], 'heuristic_score': -0.1, 'heuristic_index': 0.9, 'empirical_manual_odds': null,
      'volume_ratio': null, 'expected_co_winners': 12.6, 'popularity_index': 0.83, 'extrapolated': false,
      'reasons': ['실제로 적게 팔리는 번호 21, 22, 29 포함']},
  ],
};

void main() {
  test('저장된 구매예측 보고서 → 화면용 보고서 (값 보존)', () {
    final r = PurchaseModelReport.fromJson(storedPayload);
    expect(r.targetRound, 1246);
    expect(r.trainingEnd, 1245);
    expect(r.validated, isTrue);
    expect(r.popularity.testFrom, 1050);
    expect(r.popularity.testTo, 1245);
    expect(r.popularity.h1Corr, 0.78);
    expect(r.popularity.coef, isNull); // 실전 점수 계수는 저장하지 않음 → 앱은 재계산 불가
    expect(r.empirical.gatePass, isFalse);
    expect(r.empirical.coefs.single.key, 'ge40');
    expect(r.volume.improvementCi, [-139.8, 20.1]);
    expect(r.recommendations.single.numbers, [21, 22, 23, 29, 35, 36]);
    expect(r.recommendations.single.popularityIndex, 0.83);
    expect(r.recommendations.single.empiricalManualOdds, isNull);
    // 다시 직렬화해도 핵심 값이 같다
    final again = PurchaseModelReport.fromJson(r.toJson());
    expect(again.recommendations.single.numbers, r.recommendations.single.numbers);
    expect(again.popularity.gateReason, r.popularity.gateReason);
  });

  test('앱(serverWriter=false)은 연구 파이프라인을 실행하지 않는다', () async {
    expect(ResearchRuntime.serverWriter, isFalse);
    final steps = <String>[];
    // Supabase 초기화 없이도 즉시 반환해야 한다 (DB·엔진 접근 없음)
    await ResearchScheduler.instance.runIfNeeded(force: true, onStep: (s, _) => steps.add(s));
    expect(steps, isEmpty);
    expect(ResearchScheduler.instance.status.value.phase, ResearchPhase.idle);
  });

  testWidgets('서버 실행 상태 카드: 상태·실패 단계·결과 id', (tester) async {
    final run = PipelineRun.fromJson({
      'id': 'r1', 'target_round': 1247, 'latest_round': 1246, 'attempt': 2, 'status': 'partial',
      'steps': [
        {'name': 'purchase_model', 'ok': true},
        {'name': 'hypothesis_replay', 'ok': false, 'error': 'timeout'},
      ],
      'outputs': {
        'purchase': {'id': '1fb9d366-9b43', 'model_version': 'pp-0.3', 'sets': 5},
        'public': {'sets': 3, 'matches_admin_top3': true},
      },
      'error': '실패 단계: hypothesis_replay',
      'started_at': '2026-10-17T13:00:00Z', 'finished_at': '2026-10-17T13:40:00Z',
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ServerPipelineStatusCard(loader: () async => run))));
    await tester.pumpAndSettle();
    expect(find.text('일부 실패 (다음 실행에서 재시도)'), findsOneWidget);
    expect(find.text('1247회 (1246회까지 데이터) · 2번째 실행'), findsOneWidget);
    expect(find.text('단계 1/2 성공'), findsOneWidget);
    expect(find.text('✕ hypothesis_replay: timeout'), findsOneWidget);
    expect(find.text('구매예측 #1fb9d366 · pp-0.3 · 5세트'), findsOneWidget);
    expect(find.text('일반 공개 3세트 · 관리자 상위 3세트 일치'), findsOneWidget);
  });
}
