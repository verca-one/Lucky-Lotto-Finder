// 브리핑 — 7183 에이전트 (제미나이 추천번호 자리). 법칙 생태계를 추적해 번호 5세트 · 조수의 황금 숫자 · 성적표를 보여 준다.
//   서버 저장본(research_results · agent_7183)만 읽는다. 번호는 월요일에 한 번 등록 후 고정.
import 'package:flutter/material.dart';

import '../services/research/agent7183.dart';
import 'briefing_set_marks.dart';
import 'purchase_recommend_card.dart' show lottoBall, statusChip;

const k7183Color = Color(0xFF4527A0);
const _goldBg = Color(0xFFFFF8E1), _goldLine = Color(0xFFFFB300), _goldInk = Color(0xFF7A5C00);

class Agent7183Card extends StatefulWidget {
  final int target;

  /// 이번 회차 추천번호 공개 여부 (월요일 0시 · 수동 추천)
  final bool released;

  /// 테스트용 (null = 서버 조회)
  final Future<Agent7183?> Function(int target)? loader;
  const Agent7183Card({super.key, required this.target, this.released = true, this.loader});
  @override
  State<Agent7183Card> createState() => _Agent7183CardState();
}

class _Agent7183CardState extends State<Agent7183Card> {
  late final Future<Agent7183?> _f = (widget.loader ?? Agent7183.load)(widget.target);
  bool _more = false;

  @override
  Widget build(BuildContext context) => FutureBuilder<Agent7183?>(
        future: _f,
        builder: (context, snap) {
          final a = snap.data;
          final waiting = a != null && !a.byGemini; // 제미나이 답을 아직 못 받은 주 — 카드 전체를 흐린 회색으로
          return Container(
            key: const ValueKey('agent7183'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: waiting ? const Color(0xFFEEEEEE) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: waiting ? Colors.grey.shade400 : k7183Color.withValues(alpha: 0.35), width: 1.4),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.auto_awesome_rounded, color: k7183Color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${widget.target}회 7183 에이전트 — 제미나이 추천번호',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: k7183Color)),
                ),
                if (a != null && a.byGemini) statusChip('제미나이 참여', k7183Color),
                if (waiting)
                  Container(
                    key: const ValueKey('a7183_waiting'),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.grey.shade500, borderRadius: BorderRadius.circular(8)),
                    child: const Text('계산 · 제미나이 대기', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
              ]),
              const SizedBox(height: 4),
              Text('법칙이 한동안 유효하다가 다른 법칙으로 넘어가는 흐름을 쫓습니다. 법칙 · 숫자 패턴은 서버가 세고, 추리는 제미나이가 합니다. '
                  '목표는 다음 회차 당첨 — 채점은 그것 하나로 합니다.',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
              const SizedBox(height: 10),
              if (snap.connectionState != ConnectionState.done)
                const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
              else if (!widget.released)
                _note('${widget.target}회 번호는 월요일 0시(또는 수동 추천) 이후 서버가 뽑습니다.')
              else if (a == null)
                _note('${widget.target}회 7183 에이전트 저장본 없음 — 서버 실행 뒤 표시됩니다.')
              else
                ..._body(a),
            ]),
          );
        },
      );

  Widget _note(String s) => Text(s, style: TextStyle(fontSize: 12, color: Colors.orange.shade900));

  String _n(num v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

  List<Widget> _body(Agent7183 a) {
    final rs = a.recordSets, rep = a.replay;
    return [
      if (a.completedNow.isNotEmpty)
        Container(
          key: const ValueKey('a7183_complete'),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: _goldBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _goldLine, width: 1.5)),
          child: Text('🎉 법칙 완성 — ${a.completedNow.join(' · ')} (과거 복기와 등록 뒤 새 회차 모두 우연을 넘었습니다)',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: _goldInk)),
        ),
      // ── 번호 5세트
      Row(children: [
        const Icon(Icons.confirmation_number_rounded, size: 16, color: k7183Color),
        const SizedBox(width: 4),
        const Text('7183 번호 5세트', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
        const Spacer(),
        if (a.registered) statusChip(a.setsBy == 'gemini' ? '사전 등록 · 제미나이 참여' : '사전 등록 · 계산', Colors.green.shade700),
      ]),
      const SizedBox(height: 6),
      if (a.sets.isEmpty)
        _note(a.setsNote ?? '월요일 0시 이후 서버가 번호를 뽑아 등록합니다.')
      else
        for (final e in a.sets.asMap().entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: BriefingSetMarks(
              id: '${a.target}:hypothesis:${e.key}',
              numbers: e.value,
              child: Row(children: [
                SizedBox(width: 18, child: Text('${e.key + 1}', style: const TextStyle(fontWeight: FontWeight.w900, color: k7183Color))),
                ...e.value.map((n) => Padding(padding: const EdgeInsets.only(right: 3), child: lottoBall(n, size: 28))),
              ]),
            ),
          ),
      // ── 조수의 황금 숫자 (확실한 패턴이 있을 때만) · 없으면 일하고 있다는 표시
      _goldBox(a),
      const SizedBox(height: 8),
      Text(
          '성적표 — 실전 ${rs.isEmpty || rs[0] == 0 ? '아직 없음' : '${_n(rs[0])}세트 평균 ${(rs[1] / rs[0]).toStringAsFixed(2)}개 · 3개 이상 ${_n(rs[2])}세트'}'
          '${rep['n'] != null ? ' · 복기(${rep['from']}~${rep['to']}회) ${rep['n']}세트 평균 ${(rep['mean'] as num).toStringAsFixed(2)}개' : ''}'
          ' · 무작위면 0.80개',
          key: const ValueKey('a7183_score'),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      if (a.trusted.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(a.byGemini ? '제미나이가 믿는 법칙' : '가장 좁게 짚는 법칙 (계산)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: k7183Color)),
        for (final t in a.trusted) _law(t, why: true),
      ],
      if (a.dream.isNotEmpty)
        Container(
          key: const ValueKey('a7183_dream'),
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: k7183Color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('7183의 추리', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: k7183Color)),
            const SizedBox(height: 2),
            Text(a.dream, style: const TextStyle(fontSize: 11.5, height: 1.45)),
          ]),
        ),
      TextButton(
        key: const ValueKey('a7183_more'),
        onPressed: () => setState(() => _more = !_more),
        child: Text(_more ? '접기' : '살아 있는 법칙 ${a.aliveTotal}개 · 순환 사전 ${a.cycles.length}개 보기', style: const TextStyle(fontSize: 12)),
      ),
      if (_more) ...[
        for (final t in a.alive) _law(t),
        const SizedBox(height: 6),
        const Text('순환 사전', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        for (final c in a.cycles)
          Text(
              '· ${c['name']}: ${(c['digits'] as List? ?? const []).join('→')} (${c['by'] == 'seed' ? '사장님' : '7183이 꿈꿈'})'
              ' — 복기 ${_stat(c['replay'])}${c['by'] == 'seed' ? '' : ' · 등록 뒤 ${_stat(c['since'])}'}${c['complete'] == true ? ' · 완성' : ''}',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800, height: 1.4)),
        if (a.recordTrusted.length == 3 && a.recordTrusted[1] > 0)
          Text('믿은 법칙 누적: ${_n(a.recordTrusted[1])}번 중 ${_n(a.recordTrusted[0])}번 적중 · 우연이면 ${a.recordTrusted[2].toStringAsFixed(1)}번',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800)),
        if (a.notes.isNotEmpty) Text('연구 노트: ${a.notes}', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800, height: 1.4)),
        if (a.newParts.isNotEmpty) Text('새 계산 제안: ${a.newParts}', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800, height: 1.4)),
        if (!a.byGemini && (a.aiError ?? '').isNotEmpty)
          Text('제미나이 대기 사유: ${a.aiError}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
      Text('법칙 기반 예측입니다 — 측정된 확률이 아닙니다. 복권 한 장의 1등 확률(1/8,145,060)은 어떤 번호든 같습니다.',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.4)),
    ];
  }

  String _stat(dynamic v) {
    final l = [for (final x in (v as List? ?? const [])) if (x is num) x];
    return l.length < 3 ? '-' : '${_n(l[1])}번 중 ${_n(l[0])}번(우연 ${l[2].toStringAsFixed(1)})';
  }

  Widget _law(Map<String, dynamic> t, {bool why = false}) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
            '· ${t['law']} [${t['mode']}] ${t['run']}번 연속 → 다음 값 ${t['next']} '
            '(우연히 맞을 확률 ${(((t['chance'] as num?) ?? 0) * 100).toStringAsFixed(0)}%)'
            '${why && '${t['why'] ?? ''}'.isNotEmpty ? ' — ${t['why']}' : ''}',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800, height: 1.4)),
      );

  Widget _goldBox(Agent7183 a) {
    if (a.goldNumbers.isEmpty) {
      final n = a.nearest.isEmpty ? null : a.nearest.first;
      return Padding(
        key: const ValueKey('a7183_scout_working'),
        padding: const EdgeInsets.only(top: 2),
        child: Text(
            '조수: 패턴 ${a.scanned}개를 살펴봤습니다 · 확실한 패턴 없음'
            '${n == null ? '' : ' · 가장 가까운 것: ${n['x']}이 나오면 ${n['lag']}회 뒤 ${n['y']} (과거 ${n['fired']}번 중 ${n['hits']}번, 우연의 ${n['ratio']}배 · 기준 2배)'}',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, height: 1.4)),
      );
    }
    final rg = a.recordGold;
    return Container(
      key: const ValueKey('a7183_gold'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: _goldBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _goldLine, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🥇 조수의 황금 숫자', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _goldInk)),
          const SizedBox(width: 8),
          for (final n in a.goldNumbers)
            Container(
              width: 30, height: 30, alignment: Alignment.center, margin: const EdgeInsets.only(right: 4),
              decoration: const BoxDecoration(color: _goldLine, shape: BoxShape.circle),
              child: Text('$n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
        ]),
        const SizedBox(height: 4),
        for (final g in a.gold)
          Text('· ${g['x']}이 나오면 ${g['lag']}회 뒤 ${g['y']} — 과거 ${g['fired']}번 중 ${g['hits']}번 적중, 지금 연속 적중 중',
              style: const TextStyle(fontSize: 11, color: _goldInk, height: 1.4)),
        Text('확실한 패턴 기준: 지금 연속 적중 · 과거 30번 이상 적중 · 우연의 2배 이상 · 숨겨 둔 구간에서도 2배 이상'
            '${rg.length == 2 && rg[0] > 0 ? ' — 황금 숫자 누적 ${_n(rg[0])}개 중 ${_n(rg[1])}개 적중' : ''}',
            style: const TextStyle(fontSize: 10, color: _goldInk, height: 1.4)),
      ]),
    );
  }
}
