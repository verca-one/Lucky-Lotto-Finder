// AI 부서 상태 — 제미나이를 쓰는 서버 작업들(7183 · 브리핑전담부서 · 전략기획부 · 연금 · 스피또)의 마지막 결과와
//   연구소 [새로고침] 요청(research_ai_requests)의 진행 상태. 저장본만 읽는다 (앱은 요청 insert 만).
import 'package:supabase_flutter/supabase_flutter.dart';

/// 부서 하나의 상태
class AiDeptItem {
  final String name;
  final bool ok;
  final String detail;
  final DateTime? at;
  const AiDeptItem(this.name, this.ok, this.detail, [this.at]);
}

/// 새로고침 요청 한 건
class AiRequest {
  final int id;
  final String status; // pending | dispatched | done
  final DateTime requestedAt;
  final DateTime? dispatchedAt, doneAt, runStartedAt, runEndedAt;
  final String? conclusion;
  const AiRequest(this.id, this.status, this.requestedAt,
      {this.dispatchedAt, this.doneAt, this.conclusion, this.runStartedAt, this.runEndedAt});

  factory AiRequest.fromRow(Map<String, dynamic> r) => AiRequest(
        (r['id'] as num).toInt(),
        '${r['status']}',
        DateTime.parse('${r['requested_at']}'),
        dispatchedAt: DateTime.tryParse('${r['dispatched_at']}'),
        doneAt: DateTime.tryParse('${r['done_at']}'),
        conclusion: r['conclusion'] as String?,
        runStartedAt: DateTime.tryParse('${r['run_started_at']}'),
        runEndedAt: DateTime.tryParse('${r['run_ended_at']}'),
      );

  /// 실행 시간 — 실제 시작(없으면 서버 요청 · 접수 시각)부터 끝(실행 중이면 지금)까지
  Duration elapsed(DateTime now) {
    final from = runStartedAt ?? dispatchedAt ?? requestedAt;
    final to = runEndedAt ?? (active ? now : (doneAt ?? now));
    final d = to.difference(from);
    return d.isNegative ? Duration.zero : d;
  }

  /// '12분 30초' · '1시간 5분'
  static String fmt(Duration d) => d.inHours > 0
      ? '${d.inHours}시간 ${d.inMinutes % 60}분'
      : d.inMinutes > 0
          ? '${d.inMinutes}분 ${d.inSeconds % 60}초'
          : '${d.inSeconds}초';

  bool get active => status != 'done';
  bool get failed => status == 'done' && conclusion != 'success';

  /// 진행 막대 0~1
  double get progress => switch (status) { 'pending' => 0.15, 'dispatched' => 0.55, _ => 1.0 };

  String get stage => switch (status) {
        'pending' => '요청 접수 — 서버가 10분 안에 시작합니다',
        'dispatched' => '서버 실행 중 — 7183 → 브리핑전담부서 → 전략기획부 → 연금 · 스피또 (보통 20~40분)',
        _ => switch (conclusion) {
            'success' => '끝남 — 서버 실행 완료',
            'timeout' => '끝남 — 90분 넘게 안 끝나 기다림을 멈췄습니다',
            'dispatch_failed' => '서버 실행 요청 실패',
            final c => '끝남 — 서버 실행 ${c ?? '결과 미상'}',
          },
      };
}

/// 제미나이 요일 나눠 돌리기 — 서버 research_ai_week.py PLAN 과 같은 표 (바꾸면 같이 바꿀 것)
///   (요일 글자, 이름, 몫) · 금요일은 예비(이번 주 실패한 것만 다시)
const kAiWeekPlan = <(String, String, List<String>)>[
  ('월', '7183 · 복기', ['a7183', 'review']),
  ('화', '전략기획부', ['direction']),
  ('수', '연금 추리', ['pension']),
  ('목', '스피또 추리', ['speetto']),
  ('금', '예비 · 재시도', []),
];

enum AiDayState { done, failed, missed, wait }

class AiDeptStatus {
  final List<AiDeptItem> items;
  final AiRequest? request;
  /// 이번 주 몫별 결과 — true 성공 · false 실패 · null 아직 안 돎
  final Map<String, bool?> week;
  /// 다음 추첨 회차 (0 = 모름) — AI 부서의 '이번 회차 추천번호가 따른 법칙' 풀이에 씀
  final int nextRound;
  const AiDeptStatus(this.items, this.request, {this.week = const {}, this.nextRound = 0});

  /// 이번 주 월요일 0시 KST
  static DateTime weekStart(DateTime now) {
    final k = now.toUtc().add(const Duration(hours: 9));
    return DateTime.utc(k.year, k.month, k.day).subtract(Duration(days: k.weekday - 1, hours: 9));
  }

  /// 요일별 상태 (월~금) — 실행 시각은 매일 17:05 KST, 그날 18시가 지나도 기록이 없으면 '안 돎'
  List<AiDayState> weekStates(DateTime now) {
    final k = now.toUtc().add(const Duration(hours: 9));
    final passed = (k.weekday - 1) + (k.hour >= 18 ? 1 : 0); // 실행이 끝났어야 할 요일 수
    final all = [for (final d in kAiWeekPlan) ...d.$3];
    return [
      for (final (i, d) in kAiWeekPlan.indexed)
        () {
          final parts = d.$3.isEmpty ? all : d.$3; // 금요일 = 전체가 다 됐는지
          if (parts.every((p) => week[p] == true)) return AiDayState.done;
          if (d.$3.isEmpty) return i < passed ? AiDayState.failed : AiDayState.wait;
          if (parts.any((p) => week[p] == false)) return AiDayState.failed;
          // 토 추첨 뒤 · 일요일엔 월요일 몫(7183 · 복기)이 새 회차 것으로 바뀌어 비어 보임 → '안 돎'이 아니라 예정
          if (i == 0 && k.weekday >= 6) return AiDayState.wait;
          return i < passed ? AiDayState.missed : AiDayState.wait;
        }(),
    ];
  }

  /// 이번 주 끝난 몫 수 / 전체 (월~목 4일)
  int weekDone(DateTime now) => weekStates(now).take(4).where((e) => e == AiDayState.done).length;

  /// 모두 정상이면 '원활'
  bool get smooth => items.every((e) => e.ok);
  List<String> get problems => [for (final e in items) if (!e.ok) '${e.name}: ${e.detail}'];

  static String _err(String? note) {
    final s = note ?? '';
    if (RegExp(r'429|RESOURCE_EXHAUSTED|quota', caseSensitive: false).hasMatch(s)) return '제미나이 하루 한도 초과';
    if (RegExp(r'timed? ?out|Timeout|응답 없음', caseSensitive: false).hasMatch(s)) return '제미나이 응답 없음 (시간 초과 — 한도 초과일 때도 이렇게 보임)';
    if (RegExp(r'503|high demand|unavailable', caseSensitive: false).hasMatch(s)) return '제미나이 서버 붐빔';
    if (s.contains('GEMINI_API_KEY')) return '제미나이 키 없음';
    return s.isEmpty ? '실패 (원인 미상)' : (s.length > 50 ? '${s.substring(0, 50)}…' : s);
  }

  /// 저장본 → 상태 (순수 함수 — 테스트 대상)
  ///   a7183: 다음 회차 7183 결과(payload: source · quota_until) · review: 다음 회차 복기(source) · runs: strategy_runs 최신순
  static AiDeptStatus fromRows({
    Map<String, dynamic>? a7183,
    Map<String, dynamic>? review,
    List<Map<String, dynamic>> runs = const [],
    Map<String, dynamic>? request,
    DateTime? now,
    int nextRound = 0,
  }) {
    final items = <AiDeptItem>[];
    final since = weekStart(now ?? DateTime.now());
    final week = <String, bool?>{
      'a7183': a7183 == null ? null : (a7183['source'] == 'gemini' || a7183['source'] == 'claude'),
      'review': review == null ? null : review['source'] == 'gemini',
    };
    for (final (kind, part) in [('ai_direction', 'direction'), ('ai_pension', 'pension'), ('ai_speetto', 'speetto')]) {
      final mine = runs.where((x) => x['kind'] == kind && (DateTime.tryParse('${x['created_at']}')?.isBefore(since) == false));
      // 이번 주에 한 번이라도 성공했으면 성공 (금요일 재시도 포함)
      week[part] = mine.isEmpty ? null : mine.any((x) => x['status'] != 'failed');
    }
    if (a7183 == null) {
      items.add(const AiDeptItem('7183 에이전트', true, '다음 회차 실행 전'));
    } else if (a7183['source'] == 'gemini') {
      items.add(const AiDeptItem('7183 에이전트', true, '제미나이 참여'));
    } else if (a7183['source'] == 'claude') {
      items.add(const AiDeptItem('7183 에이전트', true, 'Claude 대행 (제미나이가 못 답한 주)'));
    } else {
      final until = DateTime.tryParse('${a7183['quota_until']}');
      items.add(AiDeptItem('7183 에이전트', false,
          until == null ? '제미나이 답 없음 (계산 번호만)' : '제미나이 하루 한도 초과 — ${_kst(until)} 이후 다시'));
    }
    final src = review?['source'];
    items.add(review == null
        ? const AiDeptItem('AI 브리핑전담부서', true, '다음 회차 복기 전')
        : src == 'gemini'
            ? const AiDeptItem('AI 브리핑전담부서', true, '제미나이 복기')
            : AiDeptItem('AI 브리핑전담부서', false, '제미나이 실패로 기본 규칙 복기 (${_err(review['ai_error'] as String?)})'));
    for (final (kind, name) in [('ai_direction', 'AI 전략기획부'), ('ai_pension', '연금 추리'), ('ai_speetto', '스피또 추리')]) {
      final r = runs.where((x) => x['kind'] == kind).firstOrNull;
      final at = DateTime.tryParse('${r?['created_at']}');
      if (r == null) {
        items.add(AiDeptItem(name, true, '기록 없음'));
      } else if (r['status'] == 'failed') {
        items.add(AiDeptItem(name, false, _err(r['note'] as String?), at));
      } else {
        items.add(AiDeptItem(name, true, r['status'] == 'skipped' ? '이번엔 건너뜀' : '정상', at));
      }
    }
    return AiDeptStatus(items, request == null ? null : AiRequest.fromRow(request), week: week, nextRound: nextRound);
  }

  static String _kst(DateTime t) {
    final k = t.toUtc().add(const Duration(hours: 9));
    return '${k.month}/${k.day} ${k.hour.toString().padLeft(2, '0')}:${k.minute.toString().padLeft(2, '0')}';
  }

  static String kst(DateTime t) => _kst(t);

  static Future<AiDeptStatus> load() async {
    final db = Supabase.instance.client;
    final w = await db.from('lotto_winning_numbers').select('round').order('round', ascending: false).limit(1);
    final next = (w as List).isEmpty ? 0 : (w.first['round'] as num).toInt() + 1;
    final a = await db.from('research_results').select('payload->>source,payload->>quota_until')
        .eq('research_type', 'agent_7183').eq('target_round', next).order('created_at', ascending: false).limit(1);
    final rv = await db.from('research_results').select('payload->>source,payload->>ai_error')
        .eq('research_type', 'set_review').eq('model_version', 'sr-1.0').eq('target_round', next).limit(1);
    final runs = await db.from('strategy_runs').select('kind,status,note,created_at')
        .inFilter('kind', ['ai_direction', 'ai_pension', 'ai_speetto']).order('created_at', ascending: false).limit(30);
    List req = const [];
    try {
      req = await db.from('research_ai_requests').select().order('id', ascending: false).limit(1);
    } catch (_) {} // 표가 아직 없으면(SQL 미실행) 요청 없음으로
    return fromRows(
      nextRound: next,
      a7183: (a as List).isEmpty ? null : Map<String, dynamic>.from(a.first),
      review: (rv as List).isEmpty ? null : Map<String, dynamic>.from(rv.first),
      runs: [for (final r in runs as List) Map<String, dynamic>.from(r)],
      request: req.isEmpty ? null : Map<String, dynamic>.from(req.first),
    );
  }

  /// [새로고침] — 서버가 제미나이 작업 전체를 다시 돌리도록 요청 1행
  static Future<void> requestRefresh() => Supabase.instance.client.from('research_ai_requests').insert({});
}
