// AI 전략기획부 — AI 는 방향만 제시, 가설 검증·유지·폐기는 비서(서버 가설 공장)가 한다. 저장본만 표시.
import 'package:flutter/material.dart';

import '../services/research/set_review.dart';
import '../services/research/strategy_repository.dart';
import '../widgets/set_review_card.dart';

const _ink = Color(0xFF1A1446);
const _ai = Color(0xFF6A1B9A);
const _manual = Color(0xFF455A64);

/// 상태 표시 (이름, 색, 아이콘)
(String, Color, IconData) strategyStatusStyle(String s) => switch (s) {
      'proposed' => ('검증 대기', const Color(0xFF1565C0), Icons.hourglass_top_rounded),
      'pending' => ('판정 보류', const Color(0xFF8D6E63), Icons.pause_circle_outline_rounded),
      'validated' => ('검증 통과', const Color(0xFF2E7D32), Icons.verified_rounded),
      'maintained' => ('유지', const Color(0xFF00796B), Icons.autorenew_rounded),
      'rejected' => ('기각', const Color(0xFF757575), Icons.block_rounded),
      'discarded' => ('폐기', const Color(0xFFC62828), Icons.delete_outline_rounded),
      'unsupported' => ('데이터 미확보', const Color(0xFFEF6C00), Icons.help_outline_rounded),
      'provisional' => ('임시', const Color(0xFFF9A825), Icons.timelapse_rounded),
      _ => (s, Colors.grey, Icons.circle_outlined),
    };

/// 가설 종류 표시 (이름, 색) — 기본은 표시 안 함
(String, Color)? strategyKindStyle(String k) => switch (k) {
      'revival' => ('회생', const Color(0xFF0277BD)),
      'supplement' => ('보충회생', const Color(0xFF5E35B1)),
      'partial' => ('임시 일부 발췌', const Color(0xFFF9A825)),
      'applied' => ('응용', const Color(0xFF00897B)),
      _ => null,
    };

const _focusLabel = {'popularity': '인기도', 'calendar': '달력', 'sales': '판매액', 'numbers': '번호', 'stores': '판매점'};

Widget _pill(String text, Color c, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 3)],
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
      ]),
    );

class AdminStrategyScreen extends StatefulWidget {
  final Future<StrategyData> Function()? loader;

  /// 추천번호 복기 (테스트용)
  final Future<SetReview?> Function()? reviewLoader;
  const AdminStrategyScreen({super.key, this.loader, this.reviewLoader});
  @override
  State<AdminStrategyScreen> createState() => _AdminStrategyScreenState();
}

class _AdminStrategyScreenState extends State<AdminStrategyScreen> {
  late Future<StrategyData> _f = (widget.loader ?? StrategyRepository.load)();
  String _src = 'all'; // all | ai | manual
  String _lottery = 'lotto'; // lotto | pension | speetto (탭)
  String _stage = 'all'; // all | open | passed | closed

  static const _stages = {
    'open': {'proposed', 'pending', 'unsupported', 'provisional'},
    'passed': {'validated', 'maintained'},
    'closed': {'rejected', 'discarded'},
  };

  Future<void> _reload() async {
    setState(() { _f = (widget.loader ?? StrategyRepository.load)(); });
    await _f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3FA),
      appBar: AppBar(
        backgroundColor: _ink,
        foregroundColor: Colors.white,
        title: const Text('AI 전략기획부', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(children: [
              for (final (k, label) in const [('lotto', '로또'), ('pension', '연금복권'), ('speetto', '스피또')])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      key: ValueKey('lot_$k'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _lottery = k),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _lottery == k ? Colors.white : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
                            color: _lottery == k ? _ink : Colors.white)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
      body: FutureBuilder<StrategyData>(
        future: _f,
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24),
                child: Text('전략기획부 자료를 불러오지 못했습니다.\n(research_v14_strategy.sql 실행 필요)\n${s.error}', textAlign: TextAlign.center)));
          }
          final d = s.data!;
          final dirs = d.directions
              .where((x) => (_src == 'all' || x.source == _src) && x.lottery == _lottery)
              .toList();
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _hero(d),
              const SizedBox(height: 12),
              // 로또: 매주 추천번호 복기 → 보완 규칙 → 제미나이 추천번호 반영
              if (_lottery == 'lotto') ...[
                SetReviewCard(loader: widget.reviewLoader),
                const SizedBox(height: 12),
              ],
              _pipeline(d),
              const SizedBox(height: 12),
              _filters(),
              const SizedBox(height: 8),
              if (dirs.isEmpty)
                const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('아직 제시된 방향이 없습니다.'))),
              for (final dir in dirs) _directionCard(dir, d.of(dir.id), d),
            ]),
          );
        },
      ),
    );
  }

  Widget _hero(StrategyData d) {
    final ai = d.lastRun('ai_direction');
    final fac = d.lastRun('factory');
    String aiLine;
    if (ai == null) {
      aiLine = 'AI 실행 기록 없음';
    } else if (ai.status == 'skipped') {
      aiLine = 'API 키 미등록 — 지금은 관리자 방향만 검증 중';
    } else if (ai.status == 'success') {
      aiLine = '${ai.afterRound}회 검증 후 AI 방향 ${ai.stats['directions'] ?? '-'}개 제시 · 가설 ${ai.stats['hypotheses'] ?? '-'}개';
    } else {
      aiLine = 'AI 실행 실패 (${ai.note ?? '-'})';
    }
    Widget step(IconData i, String t, String sub) => Expanded(
          child: Column(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(i, color: Colors.white, size: 21),
            ),
            const SizedBox(height: 5),
            Text(t, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
            Text(sub, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 10)),
          ]),
        );
    Widget arrow() => Padding(
          padding: const EdgeInsets.only(bottom: 26),
          child: Icon(Icons.arrow_forward_rounded, color: Colors.white.withValues(alpha: 0.6), size: 18),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1A1446), Color(0xFF5B2C9F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('AI는 방향만 제시하고, 검증은 비서가 합니다',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('AI는 번호·명당·엔진에 손대지 못합니다. 제시한 가설은 과거 데이터로 발견 → 확인 → 새 회차 추적을 거쳐야 남습니다.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5, height: 1.4)),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          step(Icons.psychology_alt_rounded, 'AI 방향', '매일 오후 5시'),
          arrow(),
          step(Icons.lightbulb_outline_rounded, '가설 생성', '새 20 · 응용 10'),
          arrow(),
          step(Icons.fact_check_rounded, '비서 검증', '검정 · 모의'),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI · $aiLine', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
            if (fac != null)
              Text('비서 · ${fac.afterRound}회까지 데이터로 가설 ${fac.stats['evaluated'] ?? 0}건 판정',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  Widget _pipeline(StrategyData d) {
    final tiles = [
      ('검증 대기', d.count({'proposed'}), 'proposed'),
      ('임시', d.count({'provisional'}), 'provisional'),
      ('검증 통과', d.count({'validated'}), 'validated'),
      ('유지', d.count({'maintained'}), 'maintained'),
      ('기각', d.count({'rejected'}), 'rejected'),
      ('폐기', d.count({'discarded'}), 'discarded'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        for (final t in tiles)
          Expanded(
            child: Column(children: [
              Text('${t.$2}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: strategyStatusStyle(t.$3).$2)),
              const SizedBox(height: 2),
              Text(t.$1, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }

  Widget _filters() {
    Widget chip(String label, bool on, VoidCallback tap, {Key? key}) => Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: ChoiceChip(key: key, label: Text(label, style: const TextStyle(fontSize: 12)), selected: on, onSelected: (_) => tap()),
        );
    return Wrap(children: [
      chip('전체', _src == 'all', () => setState(() => _src = 'all')),
      chip('AI 제안', _src == 'ai', () => setState(() => _src = 'ai'), key: const ValueKey('src_ai')),
      chip('관리자 제안', _src == 'manual', () => setState(() => _src = 'manual'), key: const ValueKey('src_manual')),
      const SizedBox(width: 10),
      chip('진행 중', _stage == 'open', () => setState(() => _stage = _stage == 'open' ? 'all' : 'open')),
      chip('통과·유지', _stage == 'passed', () => setState(() => _stage = _stage == 'passed' ? 'all' : 'passed'),
          key: const ValueKey('stage_passed')),
      chip('기각·폐기', _stage == 'closed', () => setState(() => _stage = _stage == 'closed' ? 'all' : 'closed'),
          key: const ValueKey('stage_closed')),
    ]);
  }

  /// 가설 + 그 아래 파생 가설들 (한 단계씩 들여쓰기, 파생이 많으면 접어서)
  List<Widget> _tree(StrategyHypothesis h, List<StrategyHypothesis> pool, StrategyData d, int depth) {
    final kids = pool.where((k) => k.parentCode == h.code).toList();
    final row = Padding(padding: EdgeInsets.only(left: depth * 14.0), child: _hypRow(h, d));
    if (kids.isEmpty) return [row];
    final byKind = <String, int>{};
    for (final k in kids) {
      byKind[k.kind] = (byKind[k.kind] ?? 0) + 1;
    }
    final summary = byKind.entries.map((e) => '${strategyKindStyle(e.key)?.$1 ?? e.key} ${e.value}').join(' · ');
    return [
      row,
      Padding(
        padding: EdgeInsets.only(left: depth * 14.0 + 14, bottom: 6),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('kids_${h.code}'),
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: EdgeInsets.zero,
            backgroundColor: const Color(0xFFF7F6FC),
            collapsedBackgroundColor: const Color(0xFFF7F6FC),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            leading: const Icon(Icons.account_tree_outlined, size: 18, color: Color(0xFF5E35B1)),
            title: Text('파생 가설 ${kids.length}건 — $summary',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF5E35B1))),
            children: [for (final k in kids) ..._tree(k, pool, d, 0)],
          ),
        ),
      ),
    ];
  }

  Widget _directionCard(StrategyDirection dir, List<StrategyHypothesis> all, StrategyData d) {
    final hyps = _stage == 'all' ? all : all.where((h) => _stages[_stage]!.contains(h.displayStatus)).toList();
    if (_stage != 'all' && hyps.isEmpty) return const SizedBox.shrink();
    final c = dir.aiName == 'Gemini' ? const Color(0xFF1A73E8) : (dir.isAi ? _ai : _manual);
    return Container(
      key: ValueKey('direction_${dir.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: c, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.fromLTRB(14, 6, 10, 0),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              _pill(dir.isAi ? '${dir.aiName} 제안' : '관리자 제안', dir.aiName == 'Gemini' ? const Color(0xFF1A73E8) : c,
                  icon: dir.isAi ? Icons.auto_awesome_rounded : Icons.person_rounded),
              _pill('${dir.afterRound}회 검증 후', Colors.blueGrey),
              if (dir.focus != null) _pill(_focusLabel[dir.focus] ?? dir.focus!, Colors.indigo),
            ]),
            const SizedBox(height: 8),
            Text(dir.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _ink, height: 1.3)),
            const SizedBox(height: 4),
          ]),
          subtitle: Text(dir.rationale, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.45)),
          children: [
            const Divider(height: 18),
            if (hyps.isEmpty) Text('가설 없음', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            for (final h in hyps.where((h) => h.parentCode == null || !hyps.any((p) => p.code == h.parentCode)))
              ..._tree(h, hyps, d, 0),
          ],
        ),
      ),
    );
  }

  Widget _hypRow(StrategyHypothesis h, StrategyData d) {
    final (label, color, icon) = strategyStatusStyle(h.displayStatus);
    final kind = strategyKindStyle(h.kind);
    final stage = h.forward ?? h.confirm ?? h.discovery;
    return InkWell(
      key: ValueKey('hyp_${h.code}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _detail(h, d),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.statement, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.35)),
              const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 4, children: [
                _pill(label, color),
                if (h.isStore) _pill('판매점', const Color(0xFFE65100), icon: Icons.storefront_rounded),
                if (h.isPension)
                  _pill(h.isPensionStore ? '연금 판매점 · 명당 반영' : '연금 · 가설 트랙', const Color(0xFFEF6C00),
                      icon: h.isPensionStore ? Icons.storefront_rounded : Icons.card_giftcard),
                if (h.isSpeetto) _pill('스피또 · 판매 현황 쌓이면 검정', const Color(0xFF00897B), icon: Icons.style_rounded),
                if (kind != null) _pill(kind.$1, kind.$2),
                if (h.simulated)
                  _pill('모의 ×${h.simLift?.toStringAsFixed(2) ?? '-'}', h.simRaised ? const Color(0xFF2E7D32) : Colors.blueGrey,
                      icon: Icons.casino_outlined),
              ]),
              if (stage != null && !stage.small && stage.meanCond != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                      stage.storeUnit
                          ? '실제/지방장 기대 ${stage.meanCond!.toStringAsFixed(2)} vs 나머지 ${stage.meanOther!.toStringAsFixed(2)}'
                          : '조건 ${stage.meanCond!.toStringAsFixed(3)} vs 나머지 ${stage.meanOther!.toStringAsFixed(3)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700), overflow: TextOverflow.ellipsis),
                ),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
        ]),
      ),
    );
  }

  void _detail(StrategyHypothesis h, StrategyData d) {
    final (label, color, icon) = strategyStatusStyle(h.displayStatus);
    final kind = strategyKindStyle(h.kind);
    final parent = d.byCode(h.parentCode);
    final kids = d.childrenOf(h.code);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (c, ctrl) => ListView(controller: ctrl, padding: const EdgeInsets.fromLTRB(18, 0, 18, 24), children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 6),
            _pill(label, color),
            if (kind != null) ...[const SizedBox(width: 6), _pill(kind.$1, kind.$2)],
          ]),
          const SizedBox(height: 10),
          Text(h.statement, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _ink, height: 1.35)),
          const SizedBox(height: 6),
          Text('가설 코드 ${h.code} · ${h.createdRound}회에 생성', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          _stageTile(1, '발견 구간', h.discovery, '269~1000회 — 여기서 차이가 있어야 다음 단계로'),
          _stageTile(2, '확인 구간', h.confirm, '1001회~ — 다중 비교 보정 후에도 재현돼야 통과'),
          _stageTile(3, '새 회차 추적', h.forward, '통과 이후 새로 쌓이는 회차에서도 같은 방향이면 유지, 뒤집히면 폐기'),
          _simTile(h),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
            child: Text('비서 판정: ${h.verdict ?? '아직 판정 전'}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color, height: 1.45)),
          ),
          if (parent != null || kids.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('계보', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 6),
            if (parent != null) _lineRow('원본', parent),
            _lineRow('이 가설', h, current: true),
            for (final k in kids) _lineRow(strategyKindStyle(k.kind)?.$1 ?? '파생', k, indent: true),
          ],
          const SizedBox(height: 10),
          Text('경향에 관한 검정입니다. 어떤 결과가 나와도 번호 조합의 1등 확률(1/8,145,060)은 바뀌지 않습니다.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
      ),
    );
  }

  /// ④ 가설 모의 — 이 가설대로 번호를 골랐다면 더 맞았나
  Widget _simTile(StrategyHypothesis h) {
    final s = h.simulation;
    final Color c;
    final String state;
    if (s.isEmpty) {
      c = Colors.grey.shade400;
      state = '아직';
    } else if (s['status'] == 'n/a') {
      c = Colors.grey.shade500;
      state = '대상 아님';
    } else if (s['status'] == 'small') {
      c = const Color(0xFF8D6E63);
      state = '표본 부족';
    } else if (h.simRaised) {
      c = const Color(0xFF2E7D32);
      state = '확률 상승';
    } else {
      c = const Color(0xFF757575);
      state = '상승 없음';
    }
    final store = s['unit'] == 'store';
    final ps = store ? (s['hits_hyp'] as num?)?.toDouble() : ((s['p_strategy'] as num?)?.toDouble() ?? 0) * 100;
    final pr = store ? (s['hits_base'] as num?)?.toDouble() : ((s['p_random'] as num?)?.toDouble() ?? 0) * 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26, height: 26, alignment: Alignment.center,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          child: const Icon(Icons.casino_outlined, color: Colors.white, size: 15),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('가설 모의', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              _pill(state, c),
            ]),
            const SizedBox(height: 2),
            Text(store ? '이 가설로 시·군·구 TOP5를 가중해 골랐다면 1001회~ 1등 적중이 지방장 이력 방식보다 많았나'
                : '이 가설대로 번호를 골랐다면 1001회~ 조건 회차에서 5등 이상(3개 이상 일치)이 무작위보다 많았나',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            if (s['status'] == 'done' && ps != null && pr != null && pr > 0) ...[
              const SizedBox(height: 6),
              _compareBar(ps, pr, c),
              const SizedBox(height: 4),
            ],
            if (s['note'] != null) Text('${s['note']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
          ]),
        ),
      ]),
    );
  }

  /// 계보 한 줄 — 원본 → 이 가설 → 파생
  Widget _lineRow(String role, StrategyHypothesis x, {bool current = false, bool indent = false}) {
    final (label, color, _) = strategyStatusStyle(x.displayStatus);
    return Container(
      margin: EdgeInsets.only(bottom: 6, left: indent ? 18 : 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: current ? const Color(0xFFEDE7F6) : const Color(0xFFF7F7F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 72, child: Text(role, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _ink))),
        Expanded(child: Text(x.statement, style: const TextStyle(fontSize: 11.5, height: 1.35))),
        const SizedBox(width: 6),
        _pill(label, color),
      ]),
    );
  }

  Widget _stageTile(int no, String title, StageResult? r, String help) {
    final Color c;
    final String state;
    if (r == null) {
      c = Colors.grey.shade400;
      state = '아직';
    } else if (r.small) {
      c = const Color(0xFF8D6E63);
      state = '표본 부족';
    } else if (r.passed) {
      c = const Color(0xFF2E7D32);
      state = '통과';
    } else {
      c = const Color(0xFF757575);
      state = '차이 없음';
    }
    final ratio = r?.meanCond != null && (r?.meanOther ?? 0) != 0 ? r!.meanCond! / r.meanOther! : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26, height: 26, alignment: Alignment.center,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          child: Text('$no', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              _pill(state, c),
            ]),
            const SizedBox(height: 2),
            Text(help, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            if (r != null && !r.small && r.meanCond != null) ...[
              const SizedBox(height: 6),
              _compareBar(r.meanCond!, r.meanOther!, c),
              const SizedBox(height: 4),
              Text(
                  r.storeUnit
                      ? '${r.from}~${r.to}회 · 조건 판매점 1등 ${r.nCond}곳 (지방장 기대 ${r.expectedCond?.toStringAsFixed(1) ?? '-'}) · '
                          '막대 = 실제÷기대 · p ${r.p?.toStringAsFixed(3) ?? '-'}'
                      : '${r.from}~${r.to}회 · 조건 ${r.nCond}회 vs 나머지 ${r.nOther}회 · p ${r.p?.toStringAsFixed(3) ?? '-'}'
                          '${ratio == null ? '' : ' · ×${ratio.toStringAsFixed(3)}'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
            ] else if (r != null && r.small)
              Text(r.storeUnit ? '조건 판매점 1등 ${r.nCond}곳 (지방장 기대 ${r.expectedCond?.toStringAsFixed(1) ?? '-'}) — 표본 부족'
                  : '조건 회차 ${r.nCond}회 — 15회 이상 쌓이면 판정', style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
          ]),
        ),
      ]),
    );
  }

  /// 조건 회차 평균 vs 나머지 평균 막대
  Widget _compareBar(double a, double b, Color c) {
    final mx = [a, b].reduce((x, y) => x > y ? x : y);
    Widget bar(String label, double v, Color col) => Row(children: [
          SizedBox(width: 42, child: Text(label, style: const TextStyle(fontSize: 10.5))),
          Expanded(
            child: LayoutBuilder(builder: (context, k) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(height: 10, width: mx == 0 ? 0 : k.maxWidth * (v / mx).clamp(0.0, 1.0),
                      decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(5))),
                )),
          ),
          SizedBox(width: 48, child: Text(' ${v.toStringAsFixed(3)}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700))),
        ]);
    return Column(children: [
      bar('조건', a, c),
      const SizedBox(height: 3),
      bar('나머지', b, Colors.grey.shade400),
    ]);
  }
}
