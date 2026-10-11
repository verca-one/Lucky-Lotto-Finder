import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/research/agent_replay_repository.dart';
import 'package:flutter_app/services/research/agent_research_repository.dart';
import 'package:flutter_app/widgets/agent_store_widgets.dart' show agentPerformanceLines;

void main() {
  group('AgentLiveRef.pick (최신 실전 모델 선택)', () {
    test('ag-1.1 live 행이 있으면 ag-1.1 최대 목표 회차', () {
      final r = AgentLiveRef.pick([
        {'model_version': 'ag-1.0', 'target_round': 1246, 'mode': 'live'},
        {'model_version': 'ag-1.1', 'target_round': 1247, 'mode': 'live'},
        {'model_version': 'ag-1.1', 'target_round': 1248, 'mode': 'live'},
      ]);
      expect(r!.model, kAgentModelReplay);
      expect(r.target, 1248);
      expect(r.fallback, isFalse);
    });

    test('ag-1.1 live 행이 없으면 ag-1.0 으로 대체 (ag-1.1 backtest 행은 무시)', () {
      final r = AgentLiveRef.pick([
        {'model_version': 'ag-1.1', 'target_round': 1300, 'mode': 'backtest'},
        {'model_version': 'ag-1.0', 'target_round': 1246, 'mode': 'live'},
        {'model_version': 'ag-1.0', 'target_round': 1250, 'mode': 'backtest'},
      ]);
      expect(r!.model, kAgentModelLegacy);
      expect(r.target, 1246, reason: 'ag-1.0 은 live 우선');
      expect(r.fallback, isTrue);
    });

    test('ag-1.0 live 도 없으면 ag-1.0 아무 mode 최대, 아무것도 없으면 null', () {
      expect(
          AgentLiveRef.pick([
            {'model_version': 'ag-1.0', 'target_round': 1240, 'mode': 'backtest'},
          ])!
              .target,
          1240);
      expect(AgentLiveRef.pick(const []), isNull);
      expect(AgentLiveRef.pick([
        {'model_version': 'ag-1.1', 'target_round': null, 'mode': 'live'},
      ]), isNull);
    });

    test('모델 지정 시 그 모델만 (ag-1.0 1246 스냅샷 조회)', () {
      final rows = [
        {'model_version': 'ag-1.0', 'target_round': 1246, 'mode': 'live'},
        {'model_version': 'ag-1.1', 'target_round': 1250, 'mode': 'live'},
      ];
      final r = AgentLiveRef.pick(rows, model: kAgentModelLegacy);
      expect(r!.model, kAgentModelLegacy);
      expect(r.target, 1246);
      expect(r.fallback, isFalse);
    });
  });

  group('AgentHypothesis (재현 가설 매핑)', () {
    test('research_replay_hypotheses 행 → 확장 필드', () {
      final h = AgentHypothesis.fromMap({
        'replay_run_id': 'ag-1.1-r1',
        'hypothesis_id': 'H1',
        'model_version': 'ag-1.1',
        'agent_id': '서울|노원구',
        'kind': 'store_cycle',
        'first_discovered_round': 1100,
        'first_applied_live_round': 1120,
        'first_applied_explore_round': null,
        'applied_live_count': 7,
        'applied_explore_count': '3',
        'test_k': 4,
        'test_expected': 1.5,
        'k_off': 10,
        'e_off': 12.25,
        'relative_ratio': 2.4,
        'test_q': 0.03,
        'status': 'passed',
        'summary': '노원 A 판매점 반복',
      });
      expect(h.isReplay, isTrue);
      expect(h.discoveredRound, 1100);
      expect(h.firstAppliedLiveRound, 1120);
      expect(h.firstAppliedExploreRound, isNull);
      expect(h.appliedLiveCount, 7);
      expect(h.appliedExploreCount, 3);
      expect(h.kOff, 10);
      expect(h.eOff, 12.25);
      expect(h.relativeRatio, 2.4);
      expect(h.testQ, 0.03);
      expect(h.appliedLive, isTrue);
      expect(h.isStoreLevel, isTrue);
      expect(h.verified, isTrue);
      expect(h.summary, '노원 A 판매점 반복');
      expect(h.appliedLine, contains('첫 실전 반영 1120회'));
      expect(h.appliedLine, contains('탐색 반영 없음'));
    });

    test('ag-1.0 행은 재현 필드 없음 · discovered_round 유지', () {
      final h = AgentHypothesis.fromMap({'hypothesis_id': 'X', 'kind': 'region_lead', 'discovered_round': 1200});
      expect(h.isReplay, isFalse);
      expect(h.discoveredRound, 1200);
      expect(h.appliedLine, isNull);
      expect(h.appliedLive, isFalse);
      expect(h.isStoreLevel, isFalse);
    });

    test('판매점 단위 검증 통과 가설 판정', () {
      AgentHypothesis h(String kind, String status) =>
          AgentHypothesis(hypothesisId: '$kind$status', agentId: 'a', kind: kind, status: status);
      expect(hasPassedStoreLevelHypothesis([h('region_lead', 'passed'), h('store_lead', 'researching')]), isFalse);
      expect(hasPassedStoreLevelHypothesis([h('neighbor_spill', 'passed')]), isTrue);
      expect(hasPassedStoreLevelHypothesis(const []), isFalse);
    });
  });

  group('ReplayAgentRound.join (예측 + 검증)', () {
    test('prediction_snapshot_id·agent_id 로 결합, 최신순, 순위별 적중', () {
      final rounds = ReplayAgentRound.join([
        {
          'prediction_snapshot_id': 's1',
          'agent_id': 'A',
          'target_round': 1200,
          'store_ids': ['x', 'y', 'z'],
          'scores': [0.3, 0.2, null],
          'applied_hypothesis_ids': [
            ['H1'],
            [],
            null
          ],
          'replay_mode': 'sequential_replay',
        },
        {
          'prediction_snapshot_id': 's2',
          'agent_id': 'A',
          'target_round': 1201,
          'store_ids': ['x'],
          'replay_mode': 'live',
        },
      ], [
        {
          'prediction_snapshot_id': 's1',
          'agent_id': 'A',
          'target_round': 1200,
          'hits_any': 1,
          'hits_first': 0,
          'expected_uniform': 0.12,
          'evaluation_metrics': {
            'by_rank': [0, 1, 0, 0, 0],
            'history_hits': 2,
            'evaluated_stored_snapshot': true,
          },
        },
        {'prediction_snapshot_id': 's9', 'agent_id': 'A', 'hits_any': 5},
      ]);
      expect(rounds.map((r) => r.targetRound), [1201, 1200]);
      expect(rounds.first.eval, isNull);
      expect(rounds.first.isLive, isTrue);
      final r = rounds.last;
      expect(r.eval!.hitsAny, 1);
      expect(r.eval!.expectedUniform, 0.12);
      expect(r.eval!.historyHits, 2);
      expect(r.eval!.hitAtRank(2), 1);
      expect(r.eval!.hitAtRank(1), 0);
      expect(r.eval!.hitAtRank(9), isNull);
      expect(r.eval!.evaluatedStoredSnapshot, isTrue);
      expect(r.scoreAt(1), 0.2);
      expect(r.scoreAt(2), isNull);
      expect(r.scoreAt(5), isNull);
      expect(r.appliedAt(0), ['H1']);
      expect(r.appliedAt(2), isEmpty);
    });

    test('applied_hypothesis_ids 가 판매점 코드 맵이어도 처리', () {
      final r = ReplayAgentRound.fromRow({
        'store_ids': ['x', 'y'],
        'applied_hypothesis_ids': {
          'y': ['H2', 'H3']
        },
      });
      expect(r.appliedAt(0), isEmpty);
      expect(r.appliedAt(1), ['H2', 'H3']);
    });
  });

  group('ReplayCumulative.build', () {
    test('사후 브리핑 agents 합계 우선 · log-loss 누적 평균', () {
      final c = ReplayCumulative.build([
        {
          'target_round': 1101,
          'evaluation_metrics': {'logloss_model': 1.0, 'logloss_m0': 2.0, 'focus_hits': 1, 'focus_hits_m0': 0, 'focus_expected': 0.5}
        },
        {
          'target_round': 1100,
          'evaluation_metrics': {'logloss_model': 3.0, 'logloss_m0': 2.0, 'store_hits_any': 9}
        },
        {'target_round': 1102, 'evaluation_metrics': {}},
      ], postAgents: {
        1100: {'hits_any': 2, 'history_hits': 1, 'expected_uniform': 0.5},
        1102: {'hits_any': 1, 'history_hits': 3, 'expected_uniform': 0.25},
      }, modes: {
        1100: 'sequential_replay',
        1101: 'sequential_replay',
        1102: 'live',
      });
      expect(c.hitsSource, 'agents');
      expect(c.points.map((p) => p.targetRound), [1100, 1101, 1102]);
      expect(c.points[0].meanLlModel, 3.0);
      expect(c.points[1].meanLlModel, 2.0);
      expect(c.points[1].meanLlM0, 2.0);
      expect(c.points[2].meanLlModel, 2.0, reason: '값 없는 회차는 직전 평균 유지');
      expect(c.points[2].llRounds, 2);
      expect(c.points[1].cumHits, 2, reason: '1101 은 agents 자료 없음 → 누적 유지');
      expect(c.last!.cumHits, 3);
      expect(c.last!.cumHistoryHits, 4);
      expect(c.last!.cumExpectedUniform, closeTo(0.75, 1e-12));
      expect(c.last!.hitRounds, 2);
      expect(c.focusHits, 1);
      expect(c.focusExpected, 0.5);
      expect(c.focusRounds, 1);
      expect(c.liveRounds, 1);
      expect(c.replayRounds, 2);
      expect(c.llSkill, closeTo(0.0, 1e-12));
    });

    test('브리핑 없으면 중앙 store_* 지표로 대체, 자료 전무하면 null 유지', () {
      final c = ReplayCumulative.build([
        {
          'target_round': 5,
          'evaluation_metrics': {'store_hits_any': 2, 'store_hits_history': 1, 'store_expected_uniform': 0.4}
        },
      ]);
      expect(c.hitsSource, 'central_store');
      expect(c.last!.cumHits, 2);
      expect(c.last!.meanLlModel, isNull);
      expect(c.llSkill, isNull);

      final empty = ReplayCumulative.build(const []);
      expect(empty.points, isEmpty);
      expect(empty.hitsSource, 'none');
      expect(empty.last, isNull);
    });
  });

  group('ReplayPerformance (research_agents.performance ag-1.1)', () {
    final perf = <String, dynamic>{
      'rounds': 20,
      'delivered': 100,
      'hits_any': 3,
      'hits_first': 1,
      'history_hits': 2,
      'explore_hits': 4,
      'expected_uniform': 1.5,
      'expected_model': 2.5,
      'lift_vs_uniform': 2.0,
      'hits_vs_model': 1.2,
      'll_skill': 0.012,
      'recent': {
        '30': {'rounds': 20, 'hits_any': 3, 'expected_uniform': 1.5, 'll_skill': 0.01},
        '10': {'rounds': 10, 'hits_any': 0, 'expected_uniform': 0},
      },
      'hypotheses': {'passed': 1, 'researching': 4},
      'shared_in': {'count': 2, 'by_status': {'passed': 1}, 'mean_ratio': 1.3},
      'data_quality': {'region_events': 40, 'stores': 120, 'sample_flag': 'small'},
    };

    test('필드 파싱 · 구간 정렬 · lift', () {
      expect(ReplayPerformance.isReplayShape(perf), isTrue);
      expect(ReplayPerformance.isReplayShape({'agent_hits_live': 3, 'rounds': [1, 2]}), isFalse);
      final p = ReplayPerformance(perf);
      expect(p.rounds, 20);
      expect(p.llSkill, 0.012);
      expect(p.recent.keys.toList(), ['10', '30']);
      expect(p.recent['10']!.lift, isNull, reason: '기대 0 이면 배수 없음');
      expect(p.recent['30']!.lift, 2.0);
      expect(p.sharedInCount, 2);
      expect(p.sharedInByStatus, {'passed': 1});
      expect(p.stores, 120);
    });

    test('표본 경고: sample_flag · 기대 5건 미만 · 30회 미만', () {
      final w = ReplayPerformance(perf).sampleWarning!;
      expect(w, contains('small'));
      expect(w, contains('5건 미만'));
      expect(w, contains('30회 미만'));
      expect(
          ReplayPerformance(const {'rounds': 100, 'expected_uniform': 12.0, 'data_quality': {'sample_flag': false}})
              .sampleWarning,
          isNull);
    });

    test('빈 performance 는 모든 값 null', () {
      final p = ReplayPerformance(const {});
      expect(p.rounds, isNull);
      expect(p.recent, isEmpty);
      expect(p.sampleWarning, isNull);
    });

    test('agentPerformanceLines: ag-1.1 형식은 재현 전용 줄', () {
      final lines = agentPerformanceLines(perf);
      expect(lines.first, contains('실전형 재현 평가 20회차'));
      expect(lines.any((l) => l.contains('lift') && l.contains('×2.00')), isTrue);
      expect(lines.any((l) => l.startsWith('표본 경고')), isTrue);
      // ag-1.0 형식은 기존 처리 유지
      final old = agentPerformanceLines({'rounds': [1000, 1245], 'live_rounds_evaluated': 0, 'agent_hits_live': 5});
      expect(old.first, contains('backtest'));
    });
  });

  group('ReplayBriefing (payload 모든 필드 nullable)', () {
    test('pre payload', () {
      final b = ReplayBriefing.fromRow({
        'prediction_snapshot_id': 's',
        'kind': 'pre',
        'target_round': 1200,
        'payload': {
          'available_data_through_round': 1199,
          'replay_mode': 'sequential_replay',
          'focus_regions': [
            {'region_id': '서울|노원구', 'p': 0.1, 'rank': 1}
          ],
          'top_stores': [
            {'store_code': 'x', 'name': 'X', 'score': 0.2}
          ],
          'live_applied': [
            {'hypothesis_id': 'H', 'kind': 'store_lead', 'status': 'passed'}
          ],
          'new_hypotheses': {'count': 3, 'by_kind': {'store_lead': 2}},
          'status_counts': {'passed': 1},
          'lines': ['a', null, 'b'],
        },
      });
      expect(b.isPre, isTrue);
      expect(b.availableThrough, 1199);
      expect(b.focusRegions.single.regionId, '서울|노원구');
      expect(b.topStores.single.display, 'X');
      expect(b.liveApplied.single.verified, isTrue);
      expect(b.newHypothesesCount, 3);
      expect(b.newHypothesesByKind, {'store_lead': 2});
      expect(b.lines, ['a', 'b']);
    });

    test('post payload · 누락 필드', () {
      final b = ReplayBriefing.fromRow({
        'kind': 'post',
        'payload': {
          'target_round': 1201,
          'actual': {'first_regions': ['A'], 'first_stores': [{'store_code': 'x'}]},
          'agents': {'hits_any': 2, 'rank1_hits': [{'store_code': 'x'}]},
          'hypothesis_changes': {'counts': {'researching→passed': 2}},
        },
      });
      expect(b.isPre, isFalse);
      expect(b.targetRound, 1201);
      expect(b.actualFirstRegions, ['A']);
      expect(b.actualFirstStores.single['store_code'], 'x');
      expect(b.focusHitRegions, isEmpty);
      expect(b.rank1Hits, hasLength(1));
      expect(b.central, isEmpty);
      expect(b.hypothesisChangeCounts, {'researching→passed': 2});
      expect(b.hypothesisChangeExamples, isEmpty);
      expect(b.trend, isEmpty);

      final empty = ReplayBriefing.fromRow(const {});
      expect(empty.lines, isEmpty);
      expect(empty.availableThrough, isNull);
      expect(empty.agents, isEmpty);
    });
  });

  test('ReplayPrediction.regionOf · replay mode 라벨', () {
    final p = ReplayPrediction.fromRow({
      'target_round': 1200,
      'replay_mode': 'live',
      'focus_regions': [
        {'region_id': 'A', 'rank': 1}
      ],
      'regions': [
        {'region_id': 'B', 'rank': 40}
      ],
    });
    expect(p.isLive, isTrue);
    expect(p.regionOf('B')!.rank, 40);
    expect(p.regionOf('C'), isNull);
    expect(replayModeLong('live'), kReplayModeLiveLabel);
    expect(replayModeLong('sequential_replay'), kReplayModeReplayLabel);
    expect(replayModeLong(null), kReplayModeReplayLabel);
  });
}
