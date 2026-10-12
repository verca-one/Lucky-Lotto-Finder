// 관리자 — 서버 연구 파이프라인 실행 상태 (research_pipeline_runs, 읽기 전용)
// 연구·엔진은 서버(GitHub Actions)가 회차마다 자동 실행한다. 이 카드는 마지막 실행 결과와 오류만 보여 준다.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PipelineRun {
  final String id;
  final int targetRound, latestRound, attempt;
  final String status;
  final List<Map<String, dynamic>> steps;
  final Map<String, dynamic> outputs;
  final String? error;
  final DateTime? startedAt, finishedAt;
  const PipelineRun({
    required this.id,
    required this.targetRound,
    required this.latestRound,
    required this.attempt,
    required this.status,
    required this.steps,
    required this.outputs,
    this.error,
    this.startedAt,
    this.finishedAt,
  });

  factory PipelineRun.fromJson(Map<String, dynamic> j) => PipelineRun(
        id: '${j['id']}',
        targetRound: (j['target_round'] as num).toInt(),
        latestRound: (j['latest_round'] as num).toInt(),
        attempt: (j['attempt'] as num?)?.toInt() ?? 1,
        status: '${j['status']}',
        steps: [for (final s in (j['steps'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)],
        outputs: Map<String, dynamic>.from(j['outputs'] as Map? ?? const {}),
        error: j['error'] as String?,
        startedAt: DateTime.tryParse('${j['started_at']}'),
        finishedAt: DateTime.tryParse('${j['finished_at']}'),
      );

  List<Map<String, dynamic>> get failedSteps => steps.where((s) => s['ok'] != true).toList();

  String get statusLabel => switch (status) {
        'success' => '완료',
        'partial' => '일부 실패 (다음 실행에서 재시도)',
        'failed' => '실패 (다음 실행에서 재시도)',
        'running' => '실행 중',
        'waiting' => '데이터 준비 대기',
        _ => status,
      };
}

class ServerPipelineStatusCard extends StatefulWidget {
  /// 테스트용 데이터 주입 (null = 서버 조회)
  final Future<PipelineRun?> Function()? loader;
  const ServerPipelineStatusCard({super.key, this.loader});

  static Future<PipelineRun?> loadLatest() async {
    final r = await Supabase.instance.client
        .from('research_pipeline_runs')
        .select('id,target_round,latest_round,attempt,status,steps,outputs,error,started_at,finished_at')
        .order('started_at', ascending: false)
        .limit(1);
    final l = r as List;
    return l.isEmpty ? null : PipelineRun.fromJson(Map<String, dynamic>.from(l.first as Map));
  }

  @override
  State<ServerPipelineStatusCard> createState() => _ServerPipelineStatusCardState();
}

class _ServerPipelineStatusCardState extends State<ServerPipelineStatusCard> {
  late Future<PipelineRun?> _future;

  @override
  void initState() {
    super.initState();
    _future = (widget.loader ?? ServerPipelineStatusCard.loadLatest)();
  }

  static String _t(DateTime? t) {
    if (t == null) return '-';
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.month}/${l.day} ${two(l.hour)}:${two(l.minute)}';
  }

  static String _short(dynamic id) {
    final s = '${id ?? ''}';
    return s.length > 8 ? s.substring(0, 8) : (s.isEmpty ? '-' : s);
  }

  Color _color(String status) => switch (status) {
        'success' => const Color(0xFF1E7D4C),
        'running' || 'waiting' => const Color(0xFF1565C0),
        _ => const Color(0xFFC62828),
      };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PipelineRun?>(
      future: _future,
      builder: (context, snap) {
        Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        } else if (snap.hasError) {
          body = Text('실행 기록을 읽지 못했습니다 (research_v9_pipeline.sql 적용 여부 확인): ${snap.error}',
              style: TextStyle(fontSize: 11, color: Colors.red.shade700));
        } else if (snap.data == null) {
          body = Text('아직 서버 실행 기록이 없습니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700));
        } else {
          final r = snap.data!;
          final pur = r.outputs['purchase'] as Map?;
          final fr = r.outputs['final_recommendation'] as Map?;
          final pub = r.outputs['public'] as Map?;
          body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                key: const ValueKey('pipeline_status'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _color(r.status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(r.statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _color(r.status))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${r.targetRound}회 (${r.latestRound}회까지 데이터) · ${r.attempt}번째 실행',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            Text('시작 ${_t(r.startedAt)} · 종료 ${_t(r.finishedAt)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            if (r.steps.isNotEmpty)
              Text('단계 ${r.steps.length - r.failedSteps.length}/${r.steps.length} 성공',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            if (pur != null) Text('구매예측 #${_short(pur['id'])} · ${pur['model_version']} · ${pur['sets']}세트', style: const TextStyle(fontSize: 11)),
            if (fr != null)
              Text('공식 최종 추천번호 #${_short(fr['id'])} · ${fr['model_version']} · ${fr['training_end_round']}회까지 학습',
                  style: const TextStyle(fontSize: 11)),
            if (pub != null)
              Text('일반 공개 ${pub['sets'] ?? 0}세트 · 관리자 상위 3세트 ${pub['matches_admin_top3'] == true ? '일치' : '불일치'}',
                  style: const TextStyle(fontSize: 11)),
            for (final s in r.failedSteps)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('✕ ${s['name']}: ${s['error'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
              ),
            if (r.error != null && r.failedSteps.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(r.error!, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              ),
          ]);
        }
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.indigo.withValues(alpha: 0.25)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('서버 연구 실행 상태',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.indigo)),
            const SizedBox(height: 2),
            Text('엔진·연구는 서버가 회차마다 자동 실행합니다. 앱은 저장된 결과만 봅니다.',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            body,
          ]),
        );
      },
    );
  }
}
