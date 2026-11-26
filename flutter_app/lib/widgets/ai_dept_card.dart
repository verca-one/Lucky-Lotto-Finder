// 연구소 'AI 부서' — AI 브리핑전담부서 · AI 전략기획부를 한 상자에 (접힘)
//   머리: 원활 / 문제 N / 실행 중 + [새로고침] (서버가 제미나이 작업 전체를 다시 돌림 — research_ai_requests)
//   펼침: 새로고침 진행 막대 · 부서별 상태 · 두 부서 화면 열기. 진행 상태는 DB 에 남아 앱을 다시 열어도 보인다.
import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/admin_briefing_desk_screen.dart';
import '../screens/admin_strategy_screen.dart';
import '../services/research/ai_dept_status.dart';

const _c = Color(0xFF4A148C);
const _ok = Color(0xFF2E7D32);
const _bad = Color(0xFFC62828);

class AiDeptCard extends StatefulWidget {
  final Future<AiDeptStatus> Function()? loader;
  final Future<void> Function()? requester;
  const AiDeptCard({super.key, this.loader, this.requester});
  @override
  State<AiDeptCard> createState() => _AiDeptCardState();
}

class _AiDeptCardState extends State<AiDeptCard> {
  AiDeptStatus? _s;
  Object? _err;
  bool _open = false, _sending = false;
  Timer? _poll, _tick;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await (widget.loader ?? AiDeptStatus.load)();
      if (!mounted) return;
      setState(() {
        _s = s;
        _err = null;
      });
      // 실행 중이면 30초마다 다시 읽어 막대를 움직임 (화면을 떠나면 멈춤)
      _poll?.cancel();
      _tick?.cancel();
      if (s.request?.active ?? false) {
        _poll = Timer(const Duration(seconds: 30), _load);
        _tick = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  Future<void> _refresh() async {
    setState(() => _sending = true);
    try {
      await (widget.requester ?? AiDeptStatus.requestRefresh)();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('새로고침 요청 — 서버가 제미나이 작업을 다시 돌립니다')));
      }
    } catch (e) {
      if (mounted) {
        final s = '$e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(s.contains('research_ai_requests') && !s.contains('row-level')
                ? 'DB에 요청 표가 없습니다 — research_v15_ai_requests.sql 을 실행해 주세요'
                : '방금 요청했거나 진행 중이라 지금은 요청할 수 없습니다 (20분 간격)')));
      }
    }
    if (mounted) setState(() => _sending = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s, req = s?.request;
    final running = req?.active ?? false;
    final (String label, Color col) = s == null
        ? (_err == null ? ('확인 중', Colors.grey) : ('읽기 실패', Colors.grey))
        : running
            ? ('실행 중', const Color(0xFF1565C0))
            : s.smooth
                ? ('원활', _ok)
                : ('문제 ${s.problems.length}', _bad);
    return Card(
      key: const ValueKey('ai_dept_card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            key: const ValueKey('ai_dept_toggle'),
            onTap: () => setState(() => _open = !_open),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: _c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.support_agent_rounded, color: _c, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('AI 부서', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      key: const ValueKey('ai_dept_state'),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(8)),
                      child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  const Text('브리핑전담부서 · 전략기획부 · 7183 · 연금 · 스피또 (제미나이)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ),
              IconButton(
                key: const ValueKey('ai_dept_refresh'),
                tooltip: '제미나이 작업 다시 돌리기',
                onPressed: _sending || running ? null : _refresh,
                icon: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, color: _c),
              ),
              Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Colors.grey.shade500),
            ]),
          ),
          // 진행 막대 — 접혀 있어도 실행 중이면 보임
          if (req != null && (running || _open)) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                key: const ValueKey('ai_dept_progress'),
                value: req.progress,
                minHeight: 7,
                backgroundColor: Colors.grey.shade200,
                color: req.failed ? _bad : running ? const Color(0xFF1565C0) : _ok,
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Text(req.stage, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
              Text('${running ? '실행 중' : '실행 시간'} ${AiRequest.fmt(req.elapsed(DateTime.now().toUtc()))}',
                  key: const ValueKey('ai_dept_elapsed'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: running ? const Color(0xFF1565C0) : Colors.black87)),
            ]),
            Text(
              [
                '요청 ${AiDeptStatus.kst(req.requestedAt)}',
                if (req.dispatchedAt != null) '서버 시작 ${AiDeptStatus.kst(req.dispatchedAt!)}',
                if (req.doneAt != null) '끝 ${AiDeptStatus.kst(req.doneAt!)}',
              ].join(' · '),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          if (_open && s != null) ...[
            const Divider(height: 20),
            for (final e in s.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(e.ok ? Icons.check_circle_rounded : Icons.error_rounded, size: 17, color: e.ok ? _ok : _bad),
                  const SizedBox(width: 6),
                  SizedBox(width: 118, child: Text(e.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
                  Expanded(
                    child: Text('${e.detail}${e.at == null ? '' : ' · ${AiDeptStatus.kst(e.at!)}'}',
                        style: TextStyle(fontSize: 12, color: e.ok ? Colors.black87 : _bad, fontWeight: e.ok ? FontWeight.w500 : FontWeight.w700)),
                  ),
                ]),
              ),
            if (!s.smooth && !running)
              Text('위 [새로고침]을 누르면 서버가 제미나이 작업을 다시 돌립니다. 하루 한도 초과면 17시(KST) 뒤에 눌러 주세요.',
                  style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900, height: 1.4)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('ai_dept_open_desk'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminBriefingDeskScreen())),
                  child: const Text('AI 브리핑전담부서 ›', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('ai_dept_open_strategy'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminStrategyScreen())),
                  child: const Text('AI 전략기획부 ›', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
