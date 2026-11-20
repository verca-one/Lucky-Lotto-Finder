// 비서 주간 점검 — 월요일 취합(엔진 실행 시점) · 토요일 아침 최종 점검 '변경점 있음/없음' (서버 저장본만 표시)

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/saturday_final_changes_screen.dart';
import '../services/research/hypothesis_track.dart';

class WeeklyCheck {
  final int round, next;
  final Map<String, dynamic>? wed, sat;

  /// 토요일 점검 전 미리보기 (매일 전략 실행 뒤 서버가 계산 — 같은 비교, 반영은 안 됨)
  final Map<String, dynamic>? preview;
  const WeeklyCheck(this.round, this.next, this.wed, this.sat, {this.preview});

  factory WeeklyCheck.fromPayload(Map<String, dynamic> p) => WeeklyCheck(
        (p['round'] as num?)?.toInt() ?? 0, (p['next'] as num?)?.toInt() ?? 0,
        p['wed'] is Map ? Map<String, dynamic>.from(p['wed'] as Map) : null,
        p['sat'] is Map ? Map<String, dynamic>.from(p['sat'] as Map) : null,
        preview: p['preview'] is Map ? Map<String, dynamic>.from(p['preview'] as Map) : null,
      );

  /// 미리보기를 토요일 자리에 넣은 사본 — 변경점 화면을 그대로 쓰기 위해
  WeeklyCheck get asPreview => WeeklyCheck(round, next, wed, preview);

  List<Map<String, dynamic>> get changes =>
      ((sat?['changes'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  bool get noChange => sat != null && changes.isEmpty && '${sat!['verdict']}'.startsWith('변경점 없음');

  static Future<WeeklyCheck?> load(int target) async {
    final rows = await Supabase.instance.client
        .from('research_results')
        .select('payload')
        .eq('research_type', 'weekly_digest')
        .eq('model_version', 'wd-1.0')
        .eq('target_round', target)
        .limit(1);
    final l = List<Map<String, dynamic>>.from(rows as List);
    return l.isEmpty ? null : WeeklyCheck.fromPayload(Map<String, dynamic>.from(l.first['payload'] as Map));
  }
}

String _time(String? iso) {
  final t = DateTime.tryParse(iso ?? '')?.toUtc().add(const Duration(hours: 9));
  if (t == null) return '-';
  const wd = ['월', '화', '수', '목', '금', '토', '일'];
  return '${t.month}/${t.day}(${wd[t.weekday - 1]}) ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 구매할 번호 위 — 이번 주 비서 점검 상태
class WeeklyCheckCard extends StatelessWidget {
  final int target;
  final Future<WeeklyCheck?> Function(int)? loader;
  const WeeklyCheckCard({super.key, required this.target, this.loader});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeeklyCheck?>(
      future: (loader ?? WeeklyCheck.load)(target),
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const SizedBox.shrink();
        final w = s.data;
        final (Color c, IconData icon, String title, String sub) = switch (w) {
          null => (Colors.blueGrey, Icons.event_note_rounded, '이번 주 비서 점검',
              '월요일 엔진 실행 때 이번 주 가설을 취합하고, 토요일 아침 8시에 최종 점검합니다.'),
          WeeklyCheck(sat: null) => (const Color(0xFF1565C0), Icons.inventory_2_outlined, '월요일 취합 완료 · 토요일 아침 8시 최종 점검 예정',
              '취합 ${_time(w.wed?['at'] as String?)} · 이번 주 가설 ${(w.wed?['activity'] as Map?)?['hypotheses'] ?? 0}개 · '
                  '적용 후보 ${((w.wed?['qualifying'] as List?) ?? const []).length}개'),
          _ when w.noChange => (const Color(0xFF2E7D32), Icons.verified_rounded, '토요일 8시 최종 점검: 변경점 없음',
              '${w.sat!['verdict']} · 점검 ${_time(w.sat!['at'] as String?)}'),
          _ => (const Color(0xFFE65100), Icons.warning_amber_rounded, '토요일 8시 최종 점검: 변경점 있음',
              '${w.sat!['verdict']} · 점검 ${_time(w.sat!['at'] as String?)}'),
        };
        final act = Map<String, dynamic>.from((w?.sat ?? w?.wed)?['activity'] as Map? ?? const {});
        return Container(
          key: const ValueKey('weekly_check_card'),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.45), width: 1.3),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: c, size: 20),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c))),
              // 토요일 8시 최종 점검이 끝났으면 완료 표시
              if (w?.sat != null)
                Container(
                  key: const ValueKey('weekly_sat_done'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_rounded, size: 13, color: Colors.white),
                    SizedBox(width: 3),
                    Text('점검 완료', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
                  ]),
                ),
            ]),
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800, height: 1.4)),
            if (w != null && w.changes.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final ch in w.changes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('· ${ch['note']}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
                ),
            ],
            if (act.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('이번 주 AI 전략기획부: 방향 ${(act['directions'] as Map?)?.entries.map((e) => '${e.key} ${e.value}').join(' · ') ?? '-'}'
                  ' · 가설 ${act['hypotheses'] ?? 0}개 · 모의 ${act['simulated'] ?? 0}개(확률 상승 ${act['sim_raised'] ?? 0})',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            ],
          ]),
        );
      },
    );
  }
}

/// 토요일 최종본 [지금 반영] 요청 — 서버(research_request_poll.py, 10분마다)가 토요일 점검을 바로 실행 (회차당 1번)
class SaturdayApply {
  /// 요청 상태 (null = 요청 없음 · pending · dispatched · done)
  static Future<String?> status(int target) async {
    final rows = await Supabase.instance.client
        .from('research_weekly_requests').select('status').eq('target_round', target).limit(1);
    final l = rows as List;
    return l.isEmpty ? null : '${l.first['status']}';
  }

  static Future<void> request(int target) =>
      Supabase.instance.client.from('research_weekly_requests').insert({'target_round': target});
}

/// 주요 브리핑 머리 — 토요일 반영 버튼
///   반영 전: 미리보기 변경점이 있으면 ❗(주황) · 없으면 회색 '지금 반영'. 누르면 변경점 확인 → [지금 반영] → 서버 요청
///   요청 뒤: '반영 요청됨 · 서버 처리 중' → 반영되면 알림(스낵바)
///   반영 후: 변경점이 있으면 색 · 없으면 흐리게. 누르면 변경점 표·그래프 화면
class SaturdayFinalAlertButton extends StatefulWidget {
  final int target;
  final Future<WeeklyCheck?> Function(int)? loader;
  final Future<HypothesisTrack?> Function(int)? trackLoader;

  /// 테스트용: 반영 요청 상태 읽기 · 요청 넣기
  final Future<String?> Function(int)? requestStatus;
  final Future<void> Function(int)? requester;
  const SaturdayFinalAlertButton(
      {super.key, required this.target, this.loader, this.trackLoader, this.requestStatus, this.requester});
  @override
  State<SaturdayFinalAlertButton> createState() => _SaturdayFinalAlertButtonState();
}

class _SaturdayFinalAlertButtonState extends State<SaturdayFinalAlertButton> {
  WeeklyCheck? _w;
  HypothesisTrack? _t;
  String? _req; // 반영 요청 상태
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _check(first: true); // 자동 갱신 없음 — 버튼을 누르거나 브리핑 새로고침 때만 다시 확인
  }

  Future<void> _check({bool first = false}) async {
    WeeklyCheck? w;
    HypothesisTrack? t;
    try {
      w = await (widget.loader ?? WeeklyCheck.load)(widget.target);
    } catch (_) {
      return;
    }
    try {
      t = await (widget.trackLoader ?? HypothesisTrack.load)(widget.target);
    } catch (_) {}
    String? req;
    try {
      req = await (widget.requestStatus ?? SaturdayApply.status)(widget.target);
    } catch (_) {} // 요청 테이블 없음(research_v14 미적용) — 요청 없음으로
    if (!mounted) return;
    final newly = !first && _w?.sat == null && w?.sat != null;
    setState(() {
      _w = w;
      _t = t;
      _req = req;
      _loaded = true;
    });
    if (newly) {
      final c = SaturdayChanges.of(w, t);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text('${widget.target}회 토요일 8시 최종본이 반영됐습니다 — ${c.any ? '변경점 있음' : '변경점 없음'}'),
        duration: const Duration(seconds: 6),
      ));
    }
  }

  bool get _requested => _req == 'pending' || _req == 'dispatched';

  Future<void> _open() async {
    if (_w?.sat == null) {
      await _check();
      if (!mounted || _w?.sat != null) return;
      if (_requested) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
            content: Text('반영 요청됨 — 서버가 10분 안에 토요일 점검을 시작합니다 (실행 5~10분). 끝나면 이 버튼이 바뀝니다.')));
        return;
      }
      // 변경점 미리보기 → 확인 후 [지금 반영]
      await Navigator.push(context, MaterialPageRoute(
          builder: (_) => SaturdayFinalChangesScreen(target: widget.target, weekly: _w?.asPreview, track: _t,
              preview: true, previewReady: _w?.preview != null, onApply: _apply)));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => SaturdayFinalChangesScreen(target: widget.target, weekly: _w, track: _t)));
  }

  /// 변경점 화면의 [지금 반영] — 서버에 토요일 점검 즉시 실행 요청 (회차당 1번)
  Future<bool> _apply(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text('${widget.target}회 토요일 최종본 지금 반영'),
        content: const Text('토요일 아침 8시 자동 점검을 앞당겨 지금 실행합니다.\n'
            '가설 공장 → 판매점 다시 뽑기 → 추천번호 복기 → 제미나이 가설 최종본 등록 → 최종 점검 순서로 돌고, '
            '최종본은 등록 후 고정됩니다. 회차당 한 번만 요청할 수 있습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          FilledButton(key: const ValueKey('sat_apply_confirm'), onPressed: () => Navigator.pop(c, true), child: const Text('지금 반영')),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await (widget.requester ?? SaturdayApply.request)(widget.target);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('반영 요청 실패: $e')));
      }
      return false;
    }
    if (mounted) setState(() => _req = 'pending');
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('${widget.target}회 토요일 최종본 반영 요청 — 서버가 10분 안에 시작합니다 (실행 5~10분)')));
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final done = _w?.sat != null;
    final c = SaturdayChanges.of(_w, _t);
    final pc = done ? null : SaturdayChanges.of(_w?.asPreview, null); // 반영 전 미리보기 변경점
    final pending = !done && (pc?.any ?? false) && !_requested; // ❗ — 확인하고 반영할 변경점이 있음
    final label = done
        ? c.any
            ? '✓ 토 8시 점검 완료 · 변경점 — 번호 ${c.setsChanged}세트 · 명당 ${c.storesChanged}곳 · 가설 ${c.added.length + c.dropped.length} (자세히)'
            : '✓ 토 8시 점검 완료 · 변경점 없음'
        : _requested
            ? '토요일 최종본 반영 요청됨 · 서버 처리 중'
            : pending
                ? '변경점 ${_w!.asPreview.changes.length}건 — 확인하고 지금 반영'
                : '토요일 최종본 지금 반영 · 변경점 없음 (토 8시 자동)';
    final btn = SizedBox(
      width: double.infinity,
      child: (done && c.any) || pending
          ? FilledButton.icon(
              key: const ValueKey('sat_final_alert'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE65100), padding: const EdgeInsets.symmetric(vertical: 10)),
              onPressed: _open,
              icon: Icon(pending ? Icons.priority_high_rounded : Icons.notifications_active_rounded, size: 18,
                  key: pending ? const ValueKey('sat_pending_mark') : null),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
            )
          : OutlinedButton.icon(
              key: const ValueKey('sat_final_alert'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.blueGrey, side: BorderSide(color: Colors.blueGrey.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 10)),
              onPressed: _open,
              icon: Icon(done ? Icons.notifications_rounded : _requested ? Icons.hourglass_top_rounded : Icons.bolt_rounded, size: 18),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: done && !c.any ? Opacity(opacity: 0.5, child: btn) : btn,
    );
  }
}
