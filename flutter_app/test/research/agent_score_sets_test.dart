import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/research/agent_replay_repository.dart';
import 'package:flutter_app/services/research/agent_research_repository.dart';
import 'package:flutter_app/widgets/db_usage_card.dart' show dbUsageLines;

void main() {
  group('AgentScoreSet 펼치기 (research_agent_score_sets)', () {
    final row = <String, dynamic>{
      'model_version': 'ag-1.1',
      'target_round': 1247,
      'agent_id': '서울|노원구',
      'store_codes': ['A', 'B', 'C'],
      'scores': [0.3, 0.2, 0.1],
      'live_factors': [1.2, 1.0, 0.9],
      'explore_factors': <double>[],
      'hyp_counts': [2, 0, 1],
      'first_share': 0.25,
      'training_end_round': 1246,
    };

    test('순위 = index+1, 크기 = 배열 길이, p_first = score × first_share', () {
      final s = AgentScoreSet.fromRow(row);
      final l = s.expand();
      expect(l.map((e) => e.storeCode), ['A', 'B', 'C']);
      expect(l.map((e) => e.agentRank), [1, 2, 3]);
      expect(l.every((e) => e.agentSize == 3), isTrue);
      expect(l[0].score, 0.3);
      expect(l[0].pFirst, closeTo(0.075, 1e-12));
      expect(l[2].pFirst, closeTo(0.025, 1e-12));
      expect(l[0].liveFactor, 1.2);
      expect(l[0].liveApplied, isTrue);
      expect(l[1].liveApplied, isFalse);
      expect(l[0].hypCount, 2);
      expect(l[0].trainingEndRound, 1246);
      expect(l[0].targetRound, 1247);
      expect(l[0].agentId, '서울|노원구');
      expect(l[0].modelVersion, 'ag-1.1');
      expect(l[0].fromScoreSet, isTrue);
      expect(l[0].normalized, 1.0);
      expect(l[2].normalized, 0.0);
    });

    test('빈 계수 배열 = 전부 1, 빈 hyp_counts = 0', () {
      final s = AgentScoreSet.fromRow({
        ...row,
        'live_factors': <double>[],
        'explore_factors': <double>[],
        'hyp_counts': <int>[],
      });
      for (final e in s.expand()) {
        expect(e.liveFactor, 1.0);
        expect(e.exploreFactor, 1.0);
        expect(e.hypCount, 0);
      }
    });

    test('first_share 없으면 p_first = null (만들어내지 않음)', () {
      final s = AgentScoreSet.fromRow({...row, 'first_share': null});
      expect(s.expand().every((e) => e.pFirst == null), isTrue);
    });

    test('점수가 없는 위치는 건너뛰되 순위·크기는 원래 배열 기준', () {
      final s = AgentScoreSet.fromRow({
        ...row,
        'scores': [0.3, null],
      });
      final l = s.expand();
      expect(l.map((e) => e.storeCode), ['A']);
      expect(l.single.agentSize, 3);
      expect(s.expandAt(1), isNull);
      expect(s.expandAt(2), isNull);
      expect(s.expandAt(-1), isNull);
    });

    test('숫자 문자열 배열도 파싱', () {
      final s = AgentScoreSet.fromRow({
        ...row,
        'scores': ['0.5', '0.4', '0.3'],
        'first_share': '0.5',
      });
      expect(s.expand().first.score, 0.5);
      expect(s.expand().first.pFirst, 0.25);
    });

    test('expandRows: 코드 필터 · 여러 지방장 병합 · 중복 코드는 처음 것 유지', () {
      final a = AgentScoreSet.fromRow(row);
      final b = AgentScoreSet.fromRow({
        ...row,
        'agent_id': '경기|수원시',
        'store_codes': ['D', 'A'],
        'scores': [0.9, 0.8],
        'live_factors': <double>[],
        'hyp_counts': <int>[],
      });
      final all = AgentScoreSet.expandRows([a, b]);
      expect(all.keys.toSet(), {'A', 'B', 'C', 'D'});
      expect(all['A']!.agentId, '서울|노원구');
      expect(all['D']!.agentRank, 1);
      expect(all['D']!.agentSize, 2);

      final some = AgentScoreSet.expandRows([a, b], codes: ['C', 'D', 'Z']);
      expect(some.keys.toSet(), {'C', 'D'});
      expect(some['C']!.agentRank, 3);
    });

    test('빈 행 · 누락 필드', () {
      final s = AgentScoreSet.fromRow({'agent_id': 'internet'});
      expect(s.expand(), isEmpty);
      expect(s.size, 0);
      expect(AgentScoreSet.expandRows(const []), isEmpty);
    });

    test('agentIdsOf: 하나라도 판정 불가면 null (회차 전체 조회)', () {
      expect(AgentResearchRepository.agentIdsOf(['서울|노원구', '서울|노원구', '경기|수원시']), {'서울|노원구', '경기|수원시'});
      expect(AgentResearchRepository.agentIdsOf(['서울|노원구', null]), isNull);
      expect(AgentResearchRepository.agentIdsOf(['']), isNull);
      expect(AgentResearchRepository.agentIdsOf(const <String?>[]), isNull);
    });
  });

  group('DbUsage (research_replay_runs.stats.usage)', () {
    test('usage 없음 → 측정 전', () {
      expect(DbUsage.fromStats(null), isNull);
      expect(DbUsage.fromStats({}), isNull);
      expect(DbUsage.fromStats({'usage': 'x'}), isNull);
      expect(dbUsageLines(null), ['DB 사용량 측정 전']);
      expect(dbUsageLines(const DbUsage({})), ['DB 사용량 측정 전']);
    });

    test('측정값 파싱 · 경고 수준', () {
      final u = DbUsage.fromStats({
        'usage': {
          'latest': {
            'at': '2026-10-11T03:00:00Z',
            'database_bytes': 250000000,
            'research_bytes': 100000000,
            'free_tier_bytes': 500000000,
            'pct': 50.0,
          },
          'history': [
            {'at': '2026-10-04', 'database_bytes': 230000000, 'latest_round': 1245},
            {'at': '2026-10-11', 'database_bytes': 250000000, 'latest_round': 1246},
          ],
          'weekly_growth_bytes': 10000000,
          'weeks_to_limit': 25,
          'alert': {'level': 'warn', 'message': '증가 속도 주의'},
        }
      })!;
      expect(u.measured, isTrue);
      expect(u.pct, 50.0);
      expect(u.limitBytes, 500000000);
      expect(u.latestRound, 1246);
      expect(u.alertLevel, 'warn');
      expect(u.alertMessage, '증가 속도 주의');
      final lines = dbUsageLines(u);
      expect(lines.first, 'DB 사용량 250.0 MB / 500 MB (50.0%)');
      expect(lines[1], contains('주간 증가 10.0 MB'));
      expect(lines[1], contains('약 25주'));
      expect(lines[1], contains('연구 테이블 100.0 MB'));
    });

    test('pct 없으면 측정값으로 계산, 한도 없으면 500 MB 표기, 나머지는 -', () {
      final u = DbUsage.fromStats({
        'usage': {
          'latest': {'database_bytes': 50000000},
        }
      })!;
      expect(u.limitBytes, kDbFreeTierBytesDefault);
      expect(u.pct, closeTo(10.0, 1e-9));
      expect(u.alertLevel, isNull);
      final lines = dbUsageLines(u);
      expect(lines.first, 'DB 사용량 50.0 MB / 500 MB (10.0%)');
      expect(lines[1], '주간 증가 - · 한도까지 -');
    });
  });
}
