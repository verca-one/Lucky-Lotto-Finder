// DB 사용량 경고 카드 (관리자 전용)
//
// 서버 Worker 가 research_replay_runs(replay_run_id='ag-1.1-r1').stats.usage 에 기록한 측정값만 표시한다.
// 값이 없으면 '측정 전' / '-' 로 두고 추정값을 만들지 않는다.
// 한도에 가까워지면 Worker 가 연구 저장을 일시 중지할 뿐, 유료 플랜으로 자동 전환하지 않는다.
import 'package:flutter/material.dart';

import '../services/research/agent_replay_repository.dart';
import '../services/route/region_research_repository.dart' show ResearchAvailability, ResearchLoad;

const String kDbCriticalLabel = '연구 저장 일시 중지 — 유료 전환하지 않음, 정리 필요';
const String kDbNoAutoUpgrade = '무료 한도 기준 표시 · 유료 플랜으로 자동 전환하지 않습니다.';

/// 측정값 → 표시 줄 (순수 함수, 단위 테스트 대상). usage 없으면 '측정 전'.
List<String> dbUsageLines(DbUsage? u) {
  if (u == null || !u.measured) return const ['DB 사용량 측정 전'];
  final pct = u.pct;
  final out = <String>[
    'DB 사용량 ${fmtMb(u.databaseBytes)} MB / ${fmtMb(u.limitBytes, 0)} MB (${pct == null ? '-' : '${pct.toStringAsFixed(1)}%'})',
  ];
  final g = u.weeklyGrowthBytes;
  final w = u.weeksToLimit;
  out.add('주간 증가 ${g == null ? '-' : '${fmtMb(g)} MB'} · 한도까지 ${w == null ? '-' : '약 ${w.toStringAsFixed(w < 10 ? 1 : 0)}주'}'
      '${u.researchBytes == null ? '' : ' · 연구 테이블 ${fmtMb(u.researchBytes)} MB'}');
  return out;
}

class DbUsageCard extends StatefulWidget {
  const DbUsageCard({super.key});

  @override
  State<DbUsageCard> createState() => _DbUsageCardState();
}

class _DbUsageCardState extends State<DbUsageCard> {
  final _repo = AgentReplayRepository();
  late Future<ResearchLoad<DbUsage?>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.loadDbUsage();
  }

  void _refresh() => setState(() => _future = _repo.loadDbUsage(force: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ResearchLoad<DbUsage?>>(
      future: _future,
      builder: (context, snap) {
        final done = snap.connectionState == ConnectionState.done;
        final load = snap.data;
        final u = load?.data;
        final level = u?.alertLevel;
        final critical = level == 'critical';
        final warn = level == 'warn';
        final MaterialColor accent = critical ? Colors.red : (warn ? Colors.orange : Colors.blueGrey);
        final lines = done ? dbUsageLines(u) : const ['DB 사용량 확인 중…'];
        final children = <Widget>[
          Row(children: [
            Icon(Icons.storage, size: 16, color: accent.shade700),
            const SizedBox(width: 6),
            Expanded(
                child: Text(lines.first,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: accent.shade900))),
            if (!done)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else
              InkWell(
                onTap: _refresh,
                child: const Padding(
                    padding: EdgeInsets.all(2), child: Icon(Icons.refresh, size: 16, color: Colors.black38)),
              ),
          ]),
          for (final l in lines.skip(1))
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(l, style: const TextStyle(fontSize: 11)),
            ),
        ];
        if (done && u == null && load != null && load.state != ResearchAvailability.noData) {
          children.add(Padding(
            padding: const EdgeInsets.only(left: 22, top: 2),
            child: Text(
                load.state == ResearchAvailability.notApplied
                    ? '실전형 재현 테이블 미적용 — 측정 기록 없음'
                    : '조회 오류${load.message == null ? '' : ': ${load.message}'}',
                style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
          ));
        }
        if (critical || warn) {
          children.add(Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: critical ? Colors.red.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: (critical ? Colors.red : Colors.orange).withValues(alpha: 0.5)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(critical ? kDbCriticalLabel : 'DB 사용량 경고 — 한도에 가까워지고 있습니다',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: critical ? Colors.red.shade900 : Colors.orange.shade900)),
              if (u?.alertMessage != null)
                Text(u!.alertMessage!, style: const TextStyle(fontSize: 11, height: 1.35)),
            ]),
          ));
        }
        if (done && u != null && u.measured) {
          final at = u.at?.replaceFirst('T', ' ').split('.').first;
          children.add(Padding(
            padding: const EdgeInsets.only(left: 22, top: 3),
            child: Text(
                '측정 ${at ?? '-'}${u.latestRound == null ? '' : ' · ${u.latestRound}회 기준'} · $kDbNoAutoUpgrade',
                style: const TextStyle(fontSize: 10, color: Colors.black45)),
          ));
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: critical || warn ? 0.6 : 0.25)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );
      },
    );
  }
}
