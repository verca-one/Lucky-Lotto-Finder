// 브리핑 추천 당첨확인 (관리자) — 최신 회차 카드(4영역 추천번호 전부 · 당첨 표시) + 지난 회차 카드
//   → 지난 회차 게시판 (10개씩 · 페이지 번호) → 회차를 누르면 당첨내역 (좌우로 넘김)
import 'package:flutter/material.dart';

import '../services/research/briefing_hit_check.dart';
import '../widgets/winning_number_boxes.dart';

const kHitColor = Color(0xFF2E7D32);
const kHitPageSize = 10;

String wonText(int v) {
  final s = '$v';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b원';
}

String _dateText(String d) {
  final t = DateTime.tryParse(d);
  if (t == null) return d;
  const wd = ['월', '화', '수', '목', '금', '토', '일'];
  return '${t.year}.${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')} (${wd[t.weekday - 1]})';
}

/// 회차 결과 한 줄 요약
String hitSummary(HitRound r) {
  if (!r.drawn) return '추첨 전 · 추천 ${r.setCount}세트';
  if (r.wonCount == 0) return '낙첨 · 추천 ${r.setCount}세트';
  final ranks = r.rankCounts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  final (sum, known) = r.prizeTotal;
  return '당첨 ${r.wonCount}세트 (${ranks.map((e) => '${e.key}등 ${e.value}').join(' · ')})'
      ' · ${known ? wonText(sum) : '${wonText(sum)} + 당첨금 미확보'}';
}

/// 첫 화면에 펼쳐 보일 회차: 최신 등록 회차 (추첨 전이면 직전 추첨 회차도 함께) · 나머지는 '지난 회차'
(List<HitRound>, List<HitRound>) splitCurrent(List<HitRound> all) {
  if (all.isEmpty) return (const [], const []);
  final cur = [all.first];
  if (!all.first.drawn) {
    final d = all.skip(1).where((r) => r.drawn).firstOrNull;
    if (d != null) cur.add(d);
  }
  return (cur, all.where((r) => !cur.contains(r)).toList());
}

class AdminBriefingHitCheckScreen extends StatefulWidget {
  final Future<List<HitRound>> Function()? loader;
  const AdminBriefingHitCheckScreen({super.key, this.loader});
  @override
  State<AdminBriefingHitCheckScreen> createState() => _AdminBriefingHitCheckScreenState();
}

class _AdminBriefingHitCheckScreenState extends State<AdminBriefingHitCheckScreen> {
  late Future<List<HitRound>> _f;

  @override
  void initState() {
    super.initState();
    _f = (widget.loader ?? BriefingHitCheck.load)();
  }

  Future<void> _reload() async {
    setState(() => _f = (widget.loader ?? BriefingHitCheck.load)());
    await _f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('브리핑 추천 당첨확인', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: kHitColor,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<HitRound>>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('불러오지 못했습니다: ${snap.error}'));
          final all = snap.data ?? const <HitRound>[];
          final (cur, past) = splitCurrent(all);
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text('브리핑이 회차마다 추천한 번호 4영역(① 엔진 추천 · ② 비인기 · ③ 구매예측 · ④ 제미나이 가설)을 '
                  '그 회차 당첨번호와 맞춰 봅니다. 맞힌 번호는 색 공, 당첨 세트는 초록 칸입니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4)),
              const SizedBox(height: 4),
              Text('번호는 추첨 전에 사전 등록 장부에 올린 그대로입니다 · 당첨금은 각 세트를 1게임씩 샀다고 볼 때 금액',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              if (all.isEmpty) const Text('등록된 브리핑 추천번호가 아직 없습니다.'),
              for (final r in cur) HitRoundCard(round: r),
              if (all.isNotEmpty) _pastEntry(context, past),
            ]),
          );
        },
      ),
    );
  }

  /// 지난 회차 카드 → 게시판 (10개씩 · 페이지 번호)
  Widget _pastEntry(BuildContext context, List<HitRound> past) {
    final wonRounds = past.where((r) => r.wonCount > 0).length;
    return Card(
      key: const ValueKey('hit_past_entry'),
      margin: const EdgeInsets.only(top: 4, bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade300)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: past.isEmpty
            ? null
            : () => Navigator.push(context, MaterialPageRoute(builder: (_) => BriefingHitPastScreen(rounds: past))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: kHitColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.history_rounded, color: kHitColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('지난 회차', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                Text(
                    past.isEmpty
                        ? '아직 지난 회차 기록이 없습니다.'
                        : '${past.first.round}회 ~ ${past.last.round}회 · ${past.length}회차 · 당첨 나온 회차 $wonRounds',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }
}

/// 회차 카드 (펼친 모양) — 당첨번호 · 요약 · 4영역 추천번호 전부
class HitRoundCard extends StatelessWidget {
  final HitRound round;
  const HitRoundCard({super.key, required this.round});

  @override
  Widget build(BuildContext context) {
    final r = round;
    final c = hitColorOf(r);
    return Card(
      key: ValueKey('hit_round_${r.round}'),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.withValues(alpha: 0.35))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${r.round}회', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(width: 8),
            Expanded(child: Text(r.drawn ? _dateText(r.drawDate) : '', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600))),
            hitResultChip(r),
          ]),
          if (r.drawn) ...[
            const SizedBox(height: 6),
            miniWinBalls(r),
          ],
          const SizedBox(height: 6),
          Text(hitSummary(r), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
          const SizedBox(height: 4),
          // 4영역 추천번호 전부 (당첨 세트는 초록)
          for (final g in r.groups) HitGroupBlock(round: r, group: g, compact: true),
        ]),
      ),
    );
  }
}

Color hitColorOf(HitRound r) => !r.drawn ? Colors.grey.shade600 : (r.wonCount > 0 ? kHitColor : Colors.red.shade400);

Widget hitResultChip(HitRound r) {
  final c = hitColorOf(r);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Text(!r.drawn ? '추첨 전' : (r.wonCount > 0 ? '당첨 · 최고 ${r.bestRank}등' : '낙첨'),
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: c)),
  );
}

Widget miniWinBalls(HitRound r) => Wrap(spacing: 3, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final n in r.win!) numberBall('$n', lottoRangeColor(n), size: 24, fontSize: 10.5),
      const Text(' + ', style: TextStyle(fontWeight: FontWeight.w900)),
      numberBall('${r.bonus}', lottoRangeColor(r.bonus!), size: 24, fontSize: 10.5),
    ]);

/// 페이지 번호 (‹ 1 2 3 ›)
class HitPager extends StatelessWidget {
  final int page, pages;
  final ValueChanged<int> onPage;
  const HitPager({super.key, required this.page, required this.pages, required this.onPage});

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          IconButton(
            key: const ValueKey('hit_page_prev'),
            onPressed: page > 0 ? () => onPage(page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          for (var i = 0; i < pages; i++)
            InkWell(
              key: ValueKey('hit_page_${i + 1}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => onPage(i),
              child: Container(
                width: 34, height: 34, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == page ? kHitColor : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: i == page ? kHitColor : Colors.grey.shade300),
                ),
                child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: i == page ? Colors.white : Colors.black87)),
              ),
            ),
          IconButton(
            key: const ValueKey('hit_page_next'),
            onPressed: page < pages - 1 ? () => onPage(page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      );
}

/// 지난 회차 게시판 — 10개씩 · 페이지 번호 · 줄을 누르면 그 회차 당첨내역
class BriefingHitPastScreen extends StatefulWidget {
  final List<HitRound> rounds;
  const BriefingHitPastScreen({super.key, required this.rounds});
  @override
  State<BriefingHitPastScreen> createState() => _BriefingHitPastScreenState();
}

class _BriefingHitPastScreenState extends State<BriefingHitPastScreen> {
  int _page = 0;
  final _sc = ScrollController();

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  /// 페이지를 바꾸면 맨 위부터 보이게
  void _setPage(int p) {
    setState(() => _page = p);
    if (_sc.hasClients) _sc.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.rounds;
    final pages = (all.length / kHitPageSize).ceil();
    final page = pages == 0 ? 0 : _page.clamp(0, pages - 1);
    final items = all.skip(page * kHitPageSize).take(kHitPageSize).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('지난 회차 당첨확인', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: kHitColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(controller: _sc, padding: const EdgeInsets.all(16), children: [
        Text('총 ${all.length}회차 · ${page + 1} / ${pages == 0 ? 1 : pages} 페이지 · 회차를 누르면 당첨내역',
            key: const ValueKey('hit_past_head'), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300)),
          child: Column(children: [
            for (final e in items.asMap().entries) ...[
              if (e.key > 0) Divider(height: 1, color: Colors.grey.shade200),
              _row(context, e.value, all),
            ],
          ]),
        ),
        if (pages > 1) ...[
          const SizedBox(height: 8),
          HitPager(page: page, pages: pages, onPage: _setPage),
        ],
      ]),
    );
  }

  Widget _row(BuildContext context, HitRound r, List<HitRound> all) => InkWell(
        key: ValueKey('hit_past_row_${r.round}'),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => BriefingHitRoundScreen(rounds: all, initial: all.indexOf(r)))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            SizedBox(width: 62, child: Text('${r.round}회', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hitSummary(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: hitColorOf(r))),
                Text(
                  [
                    if (r.drawn) _dateText(r.drawDate),
                    for (final g in r.groups)
                      '${g.def.short} ${!g.registered ? '없음' : (!r.drawn ? '${g.sets.length}세트' : (g.bestRank == null ? '낙첨' : '${g.bestRank}등'))}',
                  ].join(' · '),
                  maxLines: 2,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                ),
              ]),
            ),
            const SizedBox(width: 6),
            hitResultChip(r),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ]),
        ),
      );
}

/// 회차별 당첨내역 — 좌우로 넘겨 다른 회차 (위에 n / 전체 페이지 번호)
class BriefingHitRoundScreen extends StatefulWidget {
  final List<HitRound> rounds;
  final int initial;
  const BriefingHitRoundScreen({super.key, required this.rounds, this.initial = 0});
  @override
  State<BriefingHitRoundScreen> createState() => _BriefingHitRoundScreenState();
}

class _BriefingHitRoundScreenState extends State<BriefingHitRoundScreen> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _go(int i) => _pc.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final n = widget.rounds.length;
    final r = widget.rounds[_i];
    return Scaffold(
      appBar: AppBar(
        title: Text('${r.round}회 당첨내역', style: const TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: kHitColor,
        foregroundColor: Colors.white,
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _pc,
            itemCount: n,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => _detail(widget.rounds[i]),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              // 목록이 최신 회차 먼저라 다음 페이지 = 이전 회차
              TextButton.icon(
                key: const ValueKey('hit_detail_older'),
                onPressed: _i < n - 1 ? () => _go(_i + 1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
                label: Text(_i < n - 1 ? '${widget.rounds[_i + 1].round}회' : ''),
              ),
              Expanded(
                child: Text('${_i + 1} / $n', key: const ValueKey('hit_detail_page'), textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              Directionality(
                textDirection: TextDirection.rtl,
                child: TextButton.icon(
                  key: const ValueKey('hit_detail_newer'),
                  onPressed: _i > 0 ? () => _go(_i - 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: Text(_i > 0 ? '${widget.rounds[_i - 1].round}회' : ''),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _detail(HitRound r) => ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kHitColor.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kHitColor.withValues(alpha: 0.25))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r.round}회 당첨번호${r.drawn ? ' · ${_dateText(r.drawDate)}' : ''}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (r.drawn)
              LottoWinningBoxes(numbers: r.win!, bonus: r.bonus!)
            else
              Text('아직 추첨 전이거나 당첨번호 수집 전입니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text(hitSummary(r), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            if (r.drawn && r.wonCount > 0) ...[
              const SizedBox(height: 4),
              for (final e in (r.rankCounts.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                Text('${e.key}등 ${e.value}세트 × ${r.amountOf(e.key) == null ? '당첨금 미확보' : wonText(r.amountOf(e.key)!)}',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        for (final g in r.groups) HitGroupBlock(round: r, group: g),
      ]);
}

/// 한 영역(① 엔진 추천 · ② 비인기 · ③ 구매예측 · ④ 제미나이)의 추천번호 전부 + 세트별 당첨 표시
class HitGroupBlock extends StatelessWidget {
  final HitRound round;
  final HitGroup group;
  final bool compact; // 목록 카드 안(작게)
  const HitGroupBlock({super.key, required this.round, required this.group, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final r = round, g = group;
    final res = !g.registered
        ? '등록 없음'
        : (!r.drawn ? '${g.sets.length}세트 · 추첨 전' : (g.bestRank == null ? '낙첨' : '${g.bestRank}등 ${g.won.length}세트 당첨'));
    final c = g.bestRank != null ? kHitColor : Colors.grey.shade600;
    return Container(
      key: ValueKey('hit_group_${r.round}_${g.def.key}${compact ? '_list' : ''}'),
      width: double.infinity,
      margin: EdgeInsets.only(top: compact ? 8 : 0, bottom: compact ? 0 : 12),
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(compact ? 10 : 14),
          border: Border.all(color: g.bestRank != null ? kHitColor.withValues(alpha: 0.5) : Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(g.def.label, style: TextStyle(fontSize: compact ? 12.5 : 14, fontWeight: FontWeight.w900))),
          Text(res, style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w900, color: c)),
          if (!compact && g.version != null) ...[
            const SizedBox(width: 6),
            Text(g.version!, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ]),
        const SizedBox(height: 6),
        if (!g.registered)
          Text('${r.round}회에는 이 영역의 사전 등록 번호가 없습니다 (이 영역 기록 시작 전).',
              style: TextStyle(fontSize: compact ? 11 : 12, color: Colors.grey.shade600))
        else
          for (final e in g.sets.asMap().entries) _setRow(r, e.key, e.value),
      ]),
    );
  }

  Widget _setRow(HitRound r, int i, HitSet s) {
    final won = s.rank != null;
    final label = !r.drawn
        ? '추첨 전'
        : '${won ? '${s.rank}등' : '낙첨'} · ${s.hits.length}개 일치${s.rank == 2 ? ' + 보너스' : ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: won ? kHitColor.withValues(alpha: 0.08) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: won ? kHitColor.withValues(alpha: 0.5) : Colors.grey.shade200),
      ),
      child: Row(children: [
        SizedBox(width: 18, child: Text(String.fromCharCode(65 + i), style: const TextStyle(fontWeight: FontWeight.w900))),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(children: [
              for (final n in s.numbers)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  // 맞힌 번호는 색 공, 못 맞힌 번호는 회색 공 (추첨 전이면 모두 색)
                  child: numberBall('$n',
                      !r.drawn || s.hits.contains(n) ? lottoRangeColor(n)
                          : (s.rank == 2 && n == r.bonus ? lottoRangeColor(n) : Colors.grey.shade300),
                      size: compact ? 24 : 28, fontSize: compact ? 10.5 : 12),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: compact ? 10.5 : 11.5, fontWeight: FontWeight.w900, color: won ? kHitColor : Colors.grey.shade600)),
      ]),
    );
  }
}
