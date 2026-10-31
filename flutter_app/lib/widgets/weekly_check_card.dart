// 비서 주간 점검 — 월요일 취합(엔진 실행 시점) · 토요일 아침 최종 점검 '변경점 있음/없음' (서버 저장본만 표시)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/saturday_final_changes_screen.dart';
import '../services/research/hypothesis_track.dart';

class WeeklyCheck {
  final int round, next;
  final Map<String, dynamic>? wed, sat;
  const WeeklyCheck(this.round, this.next, this.wed, this.sat);

  factory WeeklyCheck.fromPayload(Map<String, dynamic> p) => WeeklyCheck(
        (p['round'] as num?)?.toInt() ?? 0, (p['next'] as num?)?.toInt() ?? 0,
        p['wed'] is Map ? Map<String, dynamic>.from(p['wed'] as Map) : null,
        p['sat'] is Map ? Map<String, dynamic>.from(p['sat'] as Map) : null,
      );

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

/// 주요 브리핑 머리 — 토요일 반영 알림 버튼
///   반영 전: 회색 '대기 중' (브리핑을 열어 둔 동안 2분마다 확인) → 반영되면 알림(스낵바)
///   반영 후: 변경점이 있으면 색 · 없으면 흐리게. 누르면 변경점 표·그래프 화면
class SaturdayFinalAlertButton extends StatefulWidget {
  final int target;
  final Future<WeeklyCheck?> Function(int)? loader;
  final Future<HypothesisTrack?> Function(int)? trackLoader;
  final Duration pollEvery;
  const SaturdayFinalAlertButton(
      {super.key, required this.target, this.loader, this.trackLoader, this.pollEvery = const Duration(minutes: 2)});
  @override
  State<SaturdayFinalAlertButton> createState() => _SaturdayFinalAlertButtonState();
}

class _SaturdayFinalAlertButtonState extends State<SaturdayFinalAlertButton> {
  WeeklyCheck? _w;
  HypothesisTrack? _t;
  bool _loaded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _check(first: true);
    _timer = Timer.periodic(widget.pollEvery, (_) {
      if (_w?.sat == null) _check();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
    if (!mounted) return;
    final newly = !first && _w?.sat == null && w?.sat != null;
    setState(() {
      _w = w;
      _t = t;
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

  Future<void> _open() async {
    if (_w?.sat == null) {
      await _check();
      if (!mounted || _w?.sat != null) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('아직 반영 전입니다 — 토요일 아침 8시 최종 점검이 반영되면 이 버튼이 바뀝니다.')));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => SaturdayFinalChangesScreen(target: widget.target, weekly: _w, track: _t)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final done = _w?.sat != null;
    final c = SaturdayChanges.of(_w, _t);
    final label = !done
        ? '토요일 반영 알림 · 토 8시 최종 점검 대기 중'
        : c.any
            ? '✓ 토 8시 점검 완료 · 변경점 — 번호 ${c.setsChanged}세트 · 명당 ${c.storesChanged}곳 · 가설 ${c.added.length + c.dropped.length} (자세히)'
            : '✓ 토 8시 점검 완료 · 변경점 없음';
    final btn = SizedBox(
      width: double.infinity,
      child: done && c.any
          ? FilledButton.icon(
              key: const ValueKey('sat_final_alert'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE65100), padding: const EdgeInsets.symmetric(vertical: 10)),
              onPressed: _open,
              icon: const Icon(Icons.notifications_active_rounded, size: 18),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
            )
          : OutlinedButton.icon(
              key: const ValueKey('sat_final_alert'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.blueGrey, side: BorderSide(color: Colors.blueGrey.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 10)),
              onPressed: _open,
              icon: Icon(done ? Icons.notifications_rounded : Icons.notifications_none_rounded, size: 18),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: done && !c.any ? Opacity(opacity: 0.5, child: btn) : btn,
    );
  }
}
