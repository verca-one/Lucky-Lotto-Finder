import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/research/agent_replay_repository.dart';
import 'package:flutter_app/services/research/agent_research_repository.dart';
import 'package:flutter_app/services/research/agent_verdicts.dart';
import 'package:flutter_app/services/research/master_briefing_service.dart';

AgentHypothesis _h(String kind, String status, {String? verdict, String id = 'H'}) => AgentHypothesis.fromMap({
      'hypothesis_id': id,
      'kind': kind,
      'status': status,
      if (verdict != null) 'evidence': {'verdict': verdict},
    });

void main() {
  group('판정 대체 매핑 (evidence.verdict 없을 때 status)', () {
    test('passed/combined → 검증 통과, weakened/rejected → 검증 실패, 그 외 → 검증 중', () {
      expect(agentVerdictFromStatus('passed'), kVerdictPassed);
      expect(agentVerdictFromStatus('combined'), kVerdictPassed);
      expect(agentVerdictFromStatus('weakened'), kVerdictFailed);
      expect(agentVerdictFromStatus('rejected'), kVerdictFailed);
      expect(agentVerdictFromStatus('researching'), kVerdictPending);
      expect(agentVerdictFromStatus('discovered'), kVerdictPending);
      expect(agentVerdictFromStatus(null), kVerdictPending);
    });

    test('evidence.verdict 가 있으면 status 보다 우선, 빈 문자열은 무시', () {
      expect(agentVerdictOf({'verdict': kVerdictLowSample}, 'passed'), kVerdictLowSample);
      expect(agentVerdictOf({'verdict': '  '}, 'rejected'), kVerdictFailed);
      expect(agentVerdictOf(const {}, 'combined'), kVerdictPassed);
    });

    test('AgentHypothesis: verdict · verdict_detail · power · control · relative_ratio', () {
      final h = AgentHypothesis.fromMap({
        'hypothesis_id': 'X1',
        'kind': 'store_cycle',
        'status': 'researching',
        'evidence': {
          'verdict': kVerdictAccumulating,
          'verdict_detail': '미래 12회 관측',
          'power': {'expected': 0.8, 'min_k_p05': 4, 'min_detectable_ratio': 5.0},
          'control': {'k_off': 3, 'e_off': 2.5},
          'relative_ratio': 1.4,
        },
      });
      expect(h.verdict, kVerdictAccumulating);
      expect(h.verdictFromEvidence, isTrue);
      expect(h.verdictDetail, '미래 12회 관측');
      expect(h.powerExpected, 0.8);
      expect(h.powerMinK, 4);
      expect(h.minDetectableRatio, 5.0);
      expect(h.minDetectableLine, '이 표본으로는 ×5.0배 이상 차이여야 판정 가능');
      expect(h.kOff, 3);
      expect(h.eOff, 2.5);
      expect(h.relativeRatio, 1.4);
      expect(h.verdictPassed, isFalse);
    });

    test('컬럼 값(k_off·relative_ratio)이 있으면 evidence 보다 우선, 별칭 verdict 도 인식', () {
      final h = AgentHypothesis.fromMap({
        'hypothesis_id': 'X2',
        'status': 'passed',
        'k_off': 7,
        'relative_ratio': 2.0,
        'verdict': kVerdictFailed,
        'evidence': {'control': {'k_off': 1}, 'relative_ratio': 9.0},
      });
      expect(h.kOff, 7);
      expect(h.relativeRatio, 2.0);
      expect(h.verdict, kVerdictFailed);
      final old = _h('store_lead', 'passed');
      expect(old.verdict, kVerdictPassed);
      expect(old.verdictFromEvidence, isFalse);
      expect(old.minDetectableLine, isNull);
    });
  });

  group('판매점 우위 문구', () {
    test('판매점 단위 가설이 있고 통과 0 → 검증했으나 우위 미확인 (판정별 건수)', () {
      final c = AgentVerdictCounts.of([
        _h('store_cycle', 'rejected', verdict: kVerdictFailed, id: 'a'),
        _h('store_lead', 'researching', verdict: kVerdictLowSample, id: 'b'),
        _h('store_cowin', 'researching', verdict: kVerdictLowSample, id: 'c'),
        _h('store_spill', 'researching', verdict: kVerdictAccumulating, id: 'd'),
        _h('region_lead', 'passed', id: 'e'), // 지역 단위 — 판매점 판정에서 제외
      ]);
      final w = storeEdgeWording(c, verifiedRounds: 246);
      expect(w.kind, StoreEdgeKind.testedNoEdge);
      expect(w.text, '판매점 우위: 246회 순방향 검증에서 확인 안 됨 (검증 실패 1 · 표본 부족 2 · 관측 누적 1)');
      expect(c.total, 5);
      expect(c.storeLevelTotal, 4);
    });

    test('회차 수를 모르면 생략, status 기반 검증 중은 따로 표시', () {
      final c = AgentVerdictCounts.of([_h('store_cycle', 'discovered', id: 'a')]);
      final w = storeEdgeWording(c);
      expect(w.kind, StoreEdgeKind.testedNoEdge);
      expect(w.text, '판매점 우위: 순방향 검증에서 확인 안 됨 (검증 실패 0 · 표본 부족 0 · 관측 누적 0 · 검증 중(세부 판정 없음) 1)');
    });

    test('통과 가설이 있으면 검증 통과 n건', () {
      final c = AgentVerdictCounts.of([
        _h('store_cycle', 'passed', id: 'a'),
        _h('composite', 'researching', verdict: kVerdictPassed, id: 'b'),
        _h('store_lead', 'rejected', id: 'c'),
      ]);
      final w = storeEdgeWording(c, verifiedRounds: 246);
      expect(w.kind, StoreEdgeKind.passed);
      expect(w.text, '검증 통과 가설 2건');
    });

    test('판매점 단위 가설 없음 → 검증하지 않음, 조회 불가 → 데이터 없음', () {
      final none = storeEdgeWording(AgentVerdictCounts.of([_h('region_lead', 'passed')]));
      expect(none.kind, StoreEdgeKind.notTested);
      expect(none.text, '판매점 가설 없음 (당첨 이력 부족 — 데이터 부족)');
      expect(none.kind.label, '검증하지 않음');
      final unknown = storeEdgeWording(null);
      expect(unknown.kind, StoreEdgeKind.unknown);
      expect(StoreEdgeKind.testedNoEdge.label, '검증했으나 우위 미확인');
    });

    test('여러 판매점 요약 칩', () {
      expect(storeEdgeSummaryChip(const []), '판매점 가설 판정: 데이터 없음');
      expect(storeEdgeSummaryChip(const [StoreEdgeKind.testedNoEdge, StoreEdgeKind.passed]), '검증 통과 가설 보유 1곳');
      expect(storeEdgeSummaryChip(const [StoreEdgeKind.testedNoEdge, StoreEdgeKind.notTested]),
          '판매점 우위: 검증했으나 확인 안 됨');
      expect(storeEdgeSummaryChip(const [StoreEdgeKind.notTested]), '판매점 우위: 검증하지 않음 (가설 없음)');
    });

    test('판정 필터', () {
      final h = _h('store_cycle', 'rejected');
      expect(verdictMatches(h, null), isTrue);
      expect(verdictMatches(h, kVerdictFailed), isTrue);
      expect(verdictMatches(h, kVerdictPassed), isFalse);
    });
  });

  group('계보 선택', () {
    test('live 우선순위 ag-1.1 → ag-1.0', () {
      expect(kAgentLiveModelPriority, [kAgentModelReplay, kAgentModelLegacy]);
      final r = AgentLiveRef.pick([
        {'model_version': 'ag-1.0', 'target_round': 1246, 'mode': 'live'},
        {'model_version': 'ag-1.1', 'target_round': 1247, 'mode': 'live'},
      ]);
      expect(r!.model, kAgentModelReplay);
      expect(r.fallbackNote, isNull);
      expect(r.runId, kAgentReplayRunId);
      final l = AgentLiveRef.pick([
        {'model_version': 'ag-1.0', 'target_round': 1246, 'mode': 'live'},
      ]);
      expect(l!.fallback, isTrue);
      expect(l.fallbackNote, isNotNull);
      expect(l.runId, isNull);
    });

    test('기본 재현 실행: ag-1.1-r1 (행 있으면) → 결함 없는 다른 실행 → ag-1.1-r1', () {
      expect(pickDefaultReplayRun({'ag-1.1-r1', 'ag-9-r1'}), 'ag-1.1-r1');
      expect(pickDefaultReplayRun(const {}), 'ag-1.1-r1');
      expect(pickDefaultReplayRun({'ag-1.3-r1'}), 'ag-1.3-r1');
      expect(pickDefaultReplayRun({'ag-1.1-r1', 'ag-1.3-r1'}, defective: {'ag-1.1-r1'}), 'ag-1.3-r1');
      expect(pickDefaultReplayRun({'ag-1.1-r1'}, defective: {'ag-1.1-r1'}), 'ag-1.1-r1');
    });

    test('실행 ↔ 모델', () {
      expect(agentModelForRun('ag-1.1-r1'), 'ag-1.1');
      expect(agentModelForRun('custom'), 'custom');
      expect(agentRunIdForModel('ag-1.1'), 'ag-1.1-r1');
      expect(agentRunIdForModel(kAgentModelLegacy), isNull);
      expect(agentRunIdForModel(null), isNull);
    });

    test('ReplayRun: 결함 표시는 data_provenance.defect 가 있을 때만, 무결성 검증 줄', () {
      final ok = ReplayRun.fromRow({
        'replay_run_id': 'ag-1.1-r1',
        'start_round': 1000,
        'last_completed_round': 1246,
        'data_provenance': {
          'integrity_check': {'date': '2026-10-12', 'method': '스냅샷 해시 재계산 비교', 'result': '247/247 일치'},
        },
      });
      expect(ok.hasDefect, isFalse);
      expect(replayRunDefectBadge(ok), isNull);
      expect(ok.integrityLine, '무결성 검증: 2026-10-12 · 스냅샷 해시 재계산 비교 · 247/247 일치');
      expect(ok.verifiedRounds, 247);
      expect(ok.roundRange, '1000~1246회');

      final bad = ReplayRun.fromRow({
        'replay_run_id': 'x-r1',
        'superseded_by': 'x-r2',
        'data_provenance': {'defect': 'unordered offset pagination'},
      });
      expect(bad.hasDefect, isTrue);
      expect(bad.defect, 'unordered offset pagination');
      expect(bad.supersededBy, 'x-r2');
      expect(replayRunDefectBadge(bad), isNotNull);
      expect(bad.integrityLine, isNull);

      expect(ReplayRun.fromRow({'replay_run_id': 'y', 'data_provenance': {'defect': ''}}).hasDefect, isFalse);
      expect(replayIntegrityLine(const {}), isNull);
      expect(replayIntegrityLine({'result': 'ok'}), '무결성 검증: ok');
    });
  });

  group('performance.top · contribution · baselines', () {
    test('파싱 · lift 대체 계산', () {
      final p = ReplayPerformance({
        'rounds': 247,
        'top': {
          '5': {'hits': 6, 'expected_uniform': 4.0},
          '1': {'hits': 2, 'expected_uniform': 1.0, 'lift': 2.0},
        },
        'recent': {
          '10': {'hits_any': 1, 'top': {'1': {'hits': 0, 'expected_uniform': 0.1}}},
        },
        'contribution': {'verified_hypotheses_hits': 0, 'unverified_signals_hits': 3, 'note': '미검증'},
        'baselines': {'sales_volume': '데이터 미확보 (판매량)'},
      });
      expect(ReplayPerformance.isReplayShape({'top': {}}), isTrue);
      expect(p.top.keys.toList(), ['1', '5']);
      expect(p.topAt(1)!.lift, 2.0);
      expect(p.topAt(5)!.lift, 1.5);
      expect(p.topAt(3), isNull);
      expect(p.recent['10']!.top['1']!.hits, 0);
      expect(p.verifiedHypothesesHits, 0);
      expect(p.unverifiedSignalsHits, 3);
      expect(p.contributionNote, '미검증');
      expect(p.baselines['sales_volume'], '데이터 미확보 (판매량)');
      expect(const ReplayTopPerf(hits: 1).lift, isNull);
    });
  });

  group('점수 설명 · 최종 추천 이유', () {
    const w = {'history': 0.30, 'agent': 0.20, 'cycle': 0.15, 'transition': 0.15, 'quality': 0.20};
    const c = {'history': 0.5, 'agent': 1.0, 'cycle': 0.0, 'transition': 0.0, 'quality': 1.0};

    test('공식 · 구성', () {
      expect(scoreFormula(w), '총점 = 0.3×이력 + 0.2×지방장 + 0.15×주기 + 0.15×전이 + 0.2×품질');
      expect(scoreBreakdown(w, c), startsWith('이력 0.3×0.50=0.15 · 지방장 0.2×1.00=0.20'));
      expect(topContributors(w, c), ['지방장', '품질']);
    });

    test('추천 이유 한 줄', () {
      final r = finalRecommendReason(
        weights: w,
        components: c,
        first: 2,
        second: 5,
        agentRank: 1,
        agentSize: 40,
        edge: const StoreEdgeWording(StoreEdgeKind.notTested, ''),
      );
      expect(r, '지방장·품질 기여가 가장 큼 · 1등 2·2등 5 · 지방장 내 1/40위 · 반영된 검증 가설 없음 → 이력 기반 후보 · 검증하지 않음');
      expect(finalRecommendReason(weights: w, components: const {}), contains('뚜렷한 기여 항목 없음'));
    });
  });

  group('명당 ③ 지방장 파이프라인 선정', () {
    AgentDelivery d(String agent, String code) =>
        AgentDelivery(targetRound: 1247, agentId: agent, storeCode: code, rank: 1, score: 0.1);

    test('주목 지역 순위순 1위 납품 → 부족분은 전국 상위로, 중복 제외, 최대 5', () {
      final picks = selectAgentPicks(
        focus: const [
          AgentFocusRegion(regionId: 'B', rank: 2),
          AgentFocusRegion(regionId: 'A', rank: 1),
          AgentFocusRegion(regionId: 'C', rank: 3),
        ],
        rank1ByAgent: {'A': d('A', 's1'), 'B': d('B', 's2')},
        storeTop: const [
          AgentCentralStore(storeCode: 's2', agentId: 'B'),
          AgentCentralStore(storeCode: 's3', agentId: 'C'),
          AgentCentralStore(storeCode: 's4'),
          AgentCentralStore(storeCode: 's5'),
          AgentCentralStore(storeCode: 's6'),
        ],
      );
      expect(picks.map((p) => p.code).toList(), ['s1', 's2', 's3', 's4', 's5']);
      expect(picks[0].source, MasterPickSource.agentFocus);
      expect(picks[0].regionId, 'A');
      expect(picks[2].source, MasterPickSource.agentStoreTop);
      expect(picks[2].why, contains('전국 상위 후보 2위'));
    });

    test('자료 없음 → 빈 목록 (이전 규칙으로 대체)', () {
      expect(selectAgentPicks(focus: const [], rank1ByAgent: const {}, storeTop: const []), isEmpty);
    });
  });

  group('브리핑 요약 줄', () {
    test('agent_performance totals · 미검증 신호 변화', () {
      final l = agentPerformanceTotalsLines({
        'totals': {
          'top1_hits': 3, 'top1_expected': 2.0,
          'top5_hits': 10, 'top5_expected': 10.0,
          'history_hits': 12, 'explore_hits': 10,
        },
      });
      expect(l[0], '상위 1위 적중 3건 / 무작위 기대 2.00건 (×1.50)');
      expect(l[1], '상위 5위 적중 10건 / 무작위 기대 10.00건 (×1.00)');
      expect(l[2], contains('미검증 신호 반영 시 적중 변화 -2건'));
      expect(agentPerformanceTotalsLines(const {}), isEmpty);
      final (line, low) = agentPerformanceEntryLine({
        'agent_id': '서울|노원구', 'll_skill': 0.01, 'rounds': 247,
        'top1': {'hits': 1, 'expected_uniform': 0.5}, 'top5': {'hits': 2, 'expected_uniform': 2.5},
      });
      expect(line, startsWith('서울 노원구'));
      expect(low, isTrue, reason: '5위 기대 5건 미만');
    });

    test('hypothesis_verdicts.store_level 설명 — 통과 0 이면 이유 문장', () {
      final l = storeLevelVerdictLines({
        'store_level': {
          'store_level_total': 100,
          'by_verdict': {kVerdictFailed: 10, kVerdictLowSample: 80, kVerdictAccumulating: 10, kVerdictPassed: 0},
          'median_expected_events': 0.9,
          'share_expected_below_3': 0.85,
          'min_detectable_ratio_at_median': 5.6,
          'decided': 10,
          'decided_ratio_median': 0.8,
          'decided_ratio_gt1_share': 0.3,
        },
      });
      expect(l.first, startsWith('판매점 단위 가설 100건: 검증 통과 0 · 검증 실패 10'));
      expect(l.any((x) => x.contains('기대 3건 미만 가설 85%')), isTrue);
      expect(l.any((x) => x.contains('×5.6배')), isTrue);
      expect(l.last, startsWith('→ 판매점 하나의'));
      expect(storeLevelVerdictLines(const {}), isEmpty);
    });
  });
}
