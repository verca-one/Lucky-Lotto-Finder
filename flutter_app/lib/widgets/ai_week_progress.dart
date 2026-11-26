// 브리핑 — 제미나이 이번 주 진척도 (제미나이 추천번호 위)
//   제미나이는 매일 17:05 에 요일별 몫만 돈다: 월 7183 · 복기 / 화 전략기획부 / 수 연금 / 목 스피또 / 금 예비(실패한 것만 다시)
//   저장본만 읽는다. 문제가 있으면 연구소 › AI 부서 [새로고침] 안내.
import 'package:flutter/material.dart';

import '../services/research/ai_dept_status.dart';

class AiWeekProgress extends StatefulWidget {
  final Future<AiDeptStatus> Function()? loader;
  final DateTime Function()? clock;
  const AiWeekProgress({super.key, this.loader, this.clock});
  @override
  State<AiWeekProgress> createState() => _AiWeekProgressState();
}

class _AiWeekProgressState extends State<AiWeekProgress> {
  AiDeptStatus? _s;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await (widget.loader ?? AiDeptStatus.load)();
      if (mounted) setState(() => _s = s);
    } catch (_) {} // 못 읽으면 상자 숨김
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SizedBox.shrink();
    final now = (widget.clock ?? DateTime.now)();
    final st = s.weekStates(now);
    final done = s.weekDone(now);
    final today = now.toUtc().add(const Duration(hours: 9)).weekday - 1; // 월=0
    final trouble = st.any((e) => e == AiDayState.failed || e == AiDayState.missed);
    final running = s.request?.active ?? false;
    const c = Color(0xFF4527A0);
    return Container(
      key: const ValueKey('ai_week_progress'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.timeline_rounded, size: 18, color: c),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('제미나이 이번 주 진척도', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: c)),
          ),
          Text('$done/4${running ? ' · 새로고침 실행 중' : ''}',
              key: const ValueKey('ai_week_count'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: trouble ? const Color(0xFFC62828) : c)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: done / 4,
            minHeight: 7,
            backgroundColor: Colors.grey.shade200,
            color: trouble ? const Color(0xFFEF6C00) : const Color(0xFF2E7D32),
          ),
        ),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, d) in kAiWeekPlan.indexed)
            Expanded(
              child: Column(key: ValueKey('ai_week_day_$i'), children: [
                _mark(st[i], i == today),
                const SizedBox(height: 3),
                Text(d.$1, style: TextStyle(fontSize: 12, fontWeight: i == today ? FontWeight.w900 : FontWeight.w700)),
                Text(d.$2, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: Colors.grey.shade700, height: 1.2)),
                Text(_label(st[i]), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: _color(st[i]))),
              ]),
            ),
        ]),
        const SizedBox(height: 6),
        Text('매일 17:05 에 그날 몫만 돕니다 (하루 한도를 나눠 씀). 금요일은 실패한 것만 다시.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
        if (trouble && !running)
          const Padding(
            key: ValueKey('ai_week_hint'),
            padding: EdgeInsets.only(top: 4),
            child: Text('👉 실패 · 안 돈 날이 있습니다 — 연구소 › AI 부서에서 [새로고침]을 눌러 주세요.',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFFBF360C))),
          ),
      ]),
    );
  }

  static Color _color(AiDayState s) => switch (s) {
        AiDayState.done => const Color(0xFF2E7D32),
        AiDayState.failed => const Color(0xFFC62828),
        AiDayState.missed => const Color(0xFFEF6C00),
        AiDayState.wait => Colors.grey,
      };

  static String _label(AiDayState s) => switch (s) {
        AiDayState.done => '완료',
        AiDayState.failed => '실패',
        AiDayState.missed => '안 돎',
        AiDayState.wait => '예정',
      };

  Widget _mark(AiDayState s, bool today) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: s == AiDayState.wait ? Colors.white : _color(s),
          border: Border.all(color: today ? const Color(0xFF4527A0) : _color(s), width: today ? 2.2 : 1.2),
        ),
        child: Icon(
          switch (s) {
            AiDayState.done => Icons.check_rounded,
            AiDayState.failed => Icons.close_rounded,
            AiDayState.missed => Icons.priority_high_rounded,
            AiDayState.wait => Icons.schedule_rounded,
          },
          size: 15,
          color: s == AiDayState.wait ? Colors.grey : Colors.white,
        ),
      );
}
