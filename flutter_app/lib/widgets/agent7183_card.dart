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

  /// 카드 맨 아래에 붙이는 것 (AI 브리핑전담부서 메모)
  final Widget? footer;
  const Agent7183Card({super.key, required this.target, this.released = true, this.loader, this.footer});
  @override
  State<Agent7183Card> createState() => _Agent7183CardState();
}

class _Agent7183CardState extends State<Agent7183Card> {
  late final Future<Agent7183?> _f = (widget.loader ?? Agent7183.load)(widget.target);
  bool _more = false;
  bool _open = false; // 제미나이 대기 중이면 접어 둠 — 제목 줄을 누르면 펼침

  @override
  Widget build(BuildContext context) => FutureBuilder<Agent7183?>(
        future: _f,
        builder: (context, snap) {
          final a = snap.data;
          final waiting = a != null && !a.byAi; // 제미나이 답을 아직 못 받은 주 — 번호 공만 빼고 카드 전체를 회색으로
          final accent = waiting ? Colors.grey.shade600 : k7183Color;
          final folded = waiting && !_open;
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
              InkWell(
                key: const ValueKey('a7183_toggle'),
                onTap: waiting ? () => setState(() => _open = !_open) : null,
                child: Row(children: [
                Icon(Icons.auto_awesome_rounded, color: accent, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${widget.target}회 7183 에이전트 — 제미나이 추천번호',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: accent)),
                ),
                if (a != null && a.byAi) statusChip(a.byGemini ? '제미나이 참여' : 'Claude 대행 (이번 주만)', k7183Color),
                if (waiting)
                  Container(
                    key: const ValueKey('a7183_waiting'),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.grey.shade500, borderRadius: BorderRadius.circular(8)),
                    child: const Text('계산 · 제미나이 대기', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                if (waiting) Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: accent),
              ]),
              ),
              if (!folded) ...[
              const SizedBox(height: 4),
              Text('법칙이 한동안 유효하다가 다른 법칙으로 넘어가는 흐름을 쫓습니다. 법칙 · 숫자 패턴은 서버가 세고, 추리는 제미나이가 합니다. '
                  '목표는 다음 회차 당첨 — 채점은 그것 하나로 합니다.',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
              const SizedBox(height: 10),
              if (waiting)
                Padding(
                  key: const ValueKey('a7183_refresh_hint'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _note('제미나이가 아직 답하지 못했습니다 — 연구소 › AI 부서에서 [새로고침]을 눌러 주세요.'),
                ),
              if (snap.connectionState != ConnectionState.done)
                const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
              else if (!widget.released)
                _note('${widget.target}회 번호는 월요일 0시(또는 수동 추천) 이후 서버가 뽑습니다.')
              else if (a == null)
                _note('${widget.target}회 7183 에이전트 저장본 없음 — 서버 실행 뒤 표시됩니다.')
              else
                ..._body(a),
              ?widget.footer,
              ],
            ]),
          );
        },
      );

  /// ' (11/26)' — 추가한 날 (KST)
  static String _lateDay(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toUtc().add(const Duration(hours: 9));
    return t == null ? '' : ' (${t.month}/${t.day})';
  }

  /// '번호에 힘이 실린 방식: 주기 2회 0.016 · 나머지는 성적이 우연 이하라 힘 0'
  static String _modeWLine(Map<String, num> w) {
    final on = [for (final e in w.entries) if (e.value > 0) '${e.key} ${e.value.toStringAsFixed(3)}'];
    return on.isEmpty
        ? '번호에 실리는 힘 — 지금은 우연을 넘은 방식이 없어 아래 고른 법칙 · 황금 숫자만 반영 (좁게 짚는다고 힘을 주지 않음)'
        : '번호에 실리는 힘 — ${on.join(' · ')} (성적이 우연을 넘은 만큼만 · 나머지 방식은 0)';
  }

  Widget _note(String s) => Text(s, style: TextStyle(fontSize: 12, color: Colors.orange.shade900));

  String _n(num v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

  List<Widget> _body(Agent7183 a) {
    final rs = a.recordSets, rep = a.replay;
    final waiting = !a.byAi; // 대기 중: 번호 공 · 황금 상자 · 법칙 완성 알림만 색을 남긴다
    final accent = waiting ? Colors.grey.shade600 : k7183Color;
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
        Icon(Icons.confirmation_number_rounded, size: 16, color: accent),
        const SizedBox(width: 4),
        const Text('7183 번호 5세트', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
        const Spacer(),
        if (a.registered)
          statusChip(a.setsBy == 'gemini' ? '사전 등록 · 제미나이 참여' : a.setsBy == 'claude' ? '사전 등록 · Claude 대행' : '사전 등록 · 계산', waiting ? Colors.grey.shade600 : Colors.green.shade700),
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SizedBox(width: 18, child: Text('${e.key + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: accent))),
                  ...e.value.map((n) => Padding(padding: const EdgeInsets.only(right: 3), child: lottoBall(n, size: 28))),
                ]),
                if (e.key < a.setsLaws.length) _tag(a.lawTag(a.setsLaws[e.key]), accent),
              ]),
            ),
          ),
      // ── 주중에 제미나이가 답해 추가한 번호 — 위 월요일 등록 번호는 그대로, 이건 별도 기록
      if (a.lateSets.isNotEmpty)
        Container(
          key: const ValueKey('a7183_late_sets'),
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: k7183Color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: k7183Color.withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${Agent7183.aiNameOf(a.lateSetsBy)} 번호 5세트 — 주중 추가${_lateDay(a.lateSetsAt)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: k7183Color)),
            Text('월요일엔 제미나이가 답하지 못해 계산 번호로 등록됐습니다. ${a.lateSetsBy == 'claude' ? '이번 주만 Claude 가 대신 추리해' : '제미나이가 답한 뒤'} 뽑은 번호를 따로 남깁니다 (위 번호는 그대로 · 채점은 위 번호).',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
            const SizedBox(height: 6),
            for (final e in a.lateSets.asMap().entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: BriefingSetMarks(
                  id: '${a.target}:hypothesis_late:${e.key}',
                  numbers: e.value,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      SizedBox(width: 18, child: Text('${e.key + 1}', style: const TextStyle(fontWeight: FontWeight.w900, color: k7183Color))),
                      ...e.value.map((n) => Padding(padding: const EdgeInsets.only(right: 3), child: lottoBall(n, size: 28))),
                    ]),
                    if (e.key < a.lateSetsLaws.length) _tag(a.lawTag(a.lateSetsLaws[e.key]), k7183Color),
                  ]),
                ),
              ),
          ]),
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
      // ── 번호에 실리는 힘(성적 기준) · 이어받기 표 — a7183-1.1 저장본부터
      if (a.modeW.isNotEmpty)
        Padding(
          key: const ValueKey('a7183_mode_w'),
          padding: const EdgeInsets.only(top: 6),
          child: Text(_modeWLine(a.modeW), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
        ),
      if (a.ruleTrust.length == 3 && a.ruleTrust[1] > 0)
        Padding(
          key: const ValueKey('a7183_rule_trust'),
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              '제미나이가 못 답한 주의 근거 — 계산이 고른 법칙(성적 좋은 방식 → 놀라운 연속 → 서로 다른 자리 3개): '
              '복기 ${_n(a.ruleTrust[1])}번 중 ${_n(a.ruleTrust[0])}번 적중 · 우연이면 ${a.ruleTrust[2].toStringAsFixed(1)}번',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
        ),
      if (a.handover.any((h) => (h['n'] as num? ?? 0) > 0))
        Padding(
          key: const ValueKey('a7183_handover'),
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('이어받기 표 — 법칙이 끊긴 다음 회차에 새 법칙이 살아난 자리 (평소의 몇 배)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: accent)),
            for (final h in a.handover)
              if ((h['n'] as num? ?? 0) > 0)
                Text('· ${h['dead']}에서 끊긴 뒤: ${[for (final e in (h['born'] as Map? ?? const {}).entries) if (e.value != null) '${e.key} ${e.value}배'].join(' · ')}',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
            if (a.lastDead.isNotEmpty)
              Text('· 지난 회차에 끊긴 자리: ${a.lastDead.join(', ')}', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
          ]),
        ),
      if (a.trusted.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(a.byAi ? '${a.aiName}가 믿는 법칙' : '계산이 고른 법칙 — 번호의 근거', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: accent)),
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
        child: Text(_more ? '접기' : '살아 있는 법칙 ${a.aliveTotal}개 · 순환 사전 ${a.cycles.length}개 보기',
            style: TextStyle(fontSize: 12, color: waiting ? Colors.grey.shade700 : null)),
      ),
      if (_more) ...[
        for (final t in a.alive) _law(t),
        const SizedBox(height: 6),
        const Text('순환 사전', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        for (final c in a.cycles)
          Text(
              '· ${c['name']}: ${(c['digits'] as List? ?? const []).join('→')} (${c['by'] == 'seed' ? '사장님' : c['by'] == 'claude' ? '7183이 꿈꿈 · Claude 대행' : '7183이 꿈꿈'})'
              ' — 복기 ${_stat(c['replay'])}${c['by'] == 'seed' ? '' : ' · 등록 뒤 ${_stat(c['since'])}'}${c['complete'] == true ? ' · 완성' : ''}',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800, height: 1.4)),
        if (a.recordTrusted.length == 3 && a.recordTrusted[1] > 0)
          Text('믿은 법칙 누적: ${_n(a.recordTrusted[1])}번 중 ${_n(a.recordTrusted[0])}번 적중 · 우연이면 ${a.recordTrusted[2].toStringAsFixed(1)}번',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800)),
        if (a.notes.isNotEmpty) Text('연구 노트: ${a.notes}', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800, height: 1.4)),
        if (a.newParts.isNotEmpty) Text('새 계산 제안: ${a.newParts}', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800, height: 1.4)),
        if (!a.byAi && (a.aiError ?? '').isNotEmpty)
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

  /// 번호 세트 아래 한 줄 — 이 번호가 만족하는 법칙 (★ = 믿는 법칙, 번호는 아래 법칙 목록의 번호)
  Widget _tag(String s, Color c) => Padding(
        padding: const EdgeInsets.only(left: 18, top: 2),
        child: Text(s, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
      );

  Widget _law(Map<String, dynamic> t, {bool why = false}) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
            '· ${t['id'] == null ? '' : '법칙 ${t['id']} — '}${t['cond'] == null ? '' : '${t['cond']} | '}'
            '${t['law']} [${t['mode']}] ${t['run']}번 연속 → 다음 값 ${t['next']} '
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
