// 브리핑 '회차 검증' · '지방장보고' 탭 — 서버 저장본(research_results db-1.0)만 표시
import 'package:flutter/material.dart';

import '../services/research/recommend_release.dart';
import '../services/research/round_debrief.dart';
import '../widgets/purchase_recommend_card.dart' show lottoBall, statusChip;

const _purple = Color(0xFF4527A0);
const _green = Color(0xFF2E7D32);
const _red = Color(0xFFC62828);

Widget _card({required Widget child, Key? key}) => Container(
  key: key,
  width: double.infinity,
  margin: const EdgeInsets.only(bottom: 12),
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: const Color(0xFFEDE7F6)),
  ),
  child: child,
);

Widget _title(String t, {Color color = _purple, Widget? chip}) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Row(
    children: [
      Expanded(
        child: Text(
          t,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
      if (chip != null) chip,
    ],
  ),
);

Widget _small(String t, {Color? color, FontWeight? weight}) => Text(
  t,
  style: TextStyle(
    fontSize: 11,
    color: color ?? Colors.grey.shade700,
    height: 1.45,
    fontWeight: weight,
  ),
);

/// 맞은 번호는 원래 색, 안 맞은 번호는 회색 테두리
Widget hitBall(int n, bool hit, {double size = 26}) => hit
    ? lottoBall(n, size: size)
    : Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade300, width: 1.4),
        ),
        child: Text(
          '$n',
          style: TextStyle(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500,
          ),
        ),
      );

String _pct(double v, {int d = 1}) => '${(v * 100).toStringAsFixed(d)}%';

String _probText(double p) {
  if (p >= 0.001) return _pct(p, d: 2);
  return '1/${(1 / p).round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';
}

Widget tierBadge(int tier) {
  final (t, c) = switch (tier) {
    1 => ('1등', _red),
    2 => ('2등', Colors.orange.shade800),
    _ => ('낙첨', Colors.grey.shade600),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: tier == 0 ? 0.08 : 0.14),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      t,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: c),
    ),
  );
}

// ═══════════════════════ 회차 검증 ═══════════════════════
class RoundDebriefView extends StatefulWidget {
  final Future<RoundDebrief?> Function()? loader;

  /// true = 브리핑 목록 안에 펼쳐 넣는 형태 (스크롤 없음)
  final bool embedded;
  const RoundDebriefView({super.key, this.loader, this.embedded = false});
  @override
  State<RoundDebriefView> createState() => _RoundDebriefViewState();
}

class _RoundDebriefViewState extends State<RoundDebriefView> {
  late Future<RoundDebrief?> _f;
  ReleaseState? _release;
  @override
  void initState() {
    super.initState();
    _f = (widget.loader ?? RoundDebriefRepository.loadRound)();
    _f.then((r) => _loadRelease(r), onError: (_) {});
    RecommendRelease.changes.addListener(_onRelease);
  }

  @override
  void dispose() {
    RecommendRelease.changes.removeListener(_onRelease);
    super.dispose();
  }

  void _onRelease() => _f.then((r) => _loadRelease(r), onError: (_) {});

  Future<void> _loadRelease(RoundDebrief? r) async {
    if (r == null) return;
    final s = await RecommendRelease.state(r.next, prevDrawDate: r.drawDate);
    if (mounted) setState(() => _release = s);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RoundDebrief?>(
      future: _f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (s.hasError)
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('검증 보고를 불러오지 못했습니다: ${s.error}'),
            ),
          );
        final r = s.data;
        if (r == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '아직 검증 보고가 없습니다. 추첨 후 서버가 결과를 반영하면 자동으로 만들어집니다.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final children = [
          _header(r),
          _numbersCard(r),
          _storesCard(r),
          _auditCard(r),
          _hypothesesCard(r),
          _nextCard(r),
          _probCard(r),
        ];
        if (widget.embedded) return Column(children: children);
        return RefreshIndicator(
          onRefresh: () async {
            setState(
              () => _f = (widget.loader ?? RoundDebriefRepository.loadRound)(),
            );
            await _f;
          },
          child: ListView(padding: const EdgeInsets.all(16), children: children),
        );
      },
    );
  }

  Widget _header(RoundDebrief r) {
    final pc = r.popularity;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF311B92), Color(0xFF5E35B1)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r.round}회 검증 보고',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.status == 'final' ? '확정' : '일부 대기',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '지난주 브리핑이 ${r.round}회에 추천한 번호·명당을 그대로 채점하고 ${r.next}회 변경점을 비교합니다.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 10),
          if (r.actual.isNotEmpty)
            Row(
              children: [
                ...r.actual.map(
                  (n) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: lottoBall(n, size: 30),
                  ),
                ),
                const Text(
                  ' + ',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (r.bonus != null) lottoBall(r.bonus!, size: 30),
              ],
            ),
          const SizedBox(height: 8),
          if (pc['rank1_winners'] != null)
            Text(
              '1등 ${pc['rank1_winners']}명 (무작위 기대 ${(pc['rank1_expected'] as num).toStringAsFixed(1)}명) · '
              '1등 판매점 ${r.stores['first_count'] ?? '-'}곳 · 2등 판매점 ${r.stores['second_count'] ?? '-'}곳',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (r.missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '대기 중: ${r.missing.join(', ')}',
                style: const TextStyle(color: Color(0xFFFFE082), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _numbersCard(RoundDebrief r) {
    return _card(
      key: const ValueKey('debrief_numbers'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('① 추천번호 채점 — 지난주 브리핑 그대로'),
          _small('색이 있는 공 = 맞힌 번호 · 회색 = 빗나간 번호. 기준: 무작위 세트의 평균 일치 0.8개.'),
          const SizedBox(height: 8),
          // 브리핑과 같은 구역: 구매할 번호(①~③) · 참고(④⑤, 구매 대상 아님)
          _sectionHead('구매할 번호 채점 (①~③)', _buySummary(r), const Color(0xFFD84315)),
          for (final g in r.groups.where((g) => _briefed.contains(g.key))) _group(g, r),
          const SizedBox(height: 4),
          _meanChart(r),
        ],
      ),
    );
  }

  Widget _group(DebriefGroup g, RoundDebrief r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  g.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              statusChip(_roleLabel[g.key] ?? g.role, Colors.grey.shade700),
            ],
          ),
          if (g.sets.isEmpty)
            _small(g.status ?? '데이터 미확보', color: Colors.orange.shade900)
          else ...[
            const SizedBox(height: 4),
            for (final s in g.sets)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    ...s.numbers.map(
                      (n) => Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: hitBall(n, s.hits.contains(n)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${s.matches}개${s.bonus ? '+보너스' : ''}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: s.matches >= 3 ? _green : Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (s.rank > 0) tierBadgeText(kRankLabel[s.rank]!),
                  ],
                ),
              ),
            _small(
              '최고 ${g.bestMatches}개 · 평균 ${g.mean?.toStringAsFixed(2) ?? '-'}개'
              '${g.pBestOrMore == null ? '' : ' · 무작위로 뽑아도 이 이상 나올 확률 ${_pct(g.pBestOrMore!)}'}',
            ),
            if (g.track != null)
              _small(
                '사전 등록 누적 ${g.track!.rounds}회·${g.track!.sets}세트: 평균 ${g.track!.mean.toStringAsFixed(2)}개 · '
                '3개 이상 ${g.track!.ge3}번 (기대 ${g.track!.expectedGe3.toStringAsFixed(1)}번)',
                color: Colors.grey.shade600,
              ),
          ],
        ],
      ),
    );
  }

  Widget tierBadgeText(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: _green.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w900,
        color: _green,
      ),
    ),
  );

  /// 그룹별 이번 회차 평균 일치 막대 (무작위 기대 0.8 기준선)
  static const _briefed = {'official', 'popularity', 'purchase'};

  /// 구매할 번호(①~③) 전체 당첨 요약 — '15세트 중 5등 1장'
  static String _buySummary(RoundDebrief r) {
    final sets = r.groups.where((g) => _briefed.contains(g.key)).expand((g) => g.sets).toList();
    if (sets.isEmpty) return '채점할 세트 없음';
    final won = <int, int>{};
    for (final s in sets) {
      if (s.rank > 0) won[s.rank] = (won[s.rank] ?? 0) + 1;
    }
    final w = (won.keys.toList()..sort()).map((k) => '${kRankLabel[k]} ${won[k]}장').join(' · ');
    return '${sets.length}세트 중 ${w.isEmpty ? '당첨 없음' : w}';
  }

  Widget _sectionHead(String title, String sub, Color c) => Container(
        key: ValueKey('debrief_head_$title'),
        width: double.infinity,
        margin: const EdgeInsets.only(top: 4, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: c))),
          Text(sub, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
        ]),
      );
  static const _roleLabel = {
    'official': '브리핑 ①',
    'popularity': '브리핑 ②',
    'purchase': '브리핑 ③',
    'number_engine': '브리핑 ④ 연구용',
    'random': '브리핑 ⑤ 비교 기준',
  };

  Widget _meanChart(RoundDebrief r) {
    // 브리핑 3영역 + 비교 기준(무작위)만 — Number 엔진 연구용은 접힌 칸에서만
    final gs = r.groups.where((g) => g.mean != null && _briefed.contains(g.key)).toList();
    if (gs.isEmpty) return const SizedBox.shrink();
    const maxV = 3.0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5FC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '이번 회차 평균 일치 개수',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          for (final g in gs)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      g.key == 'random' ? '무작위(비교)' : g.label,
                      style: const TextStyle(fontSize: 10.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth;
                        return Stack(
                          children: [
                            Container(
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Container(
                              height: 14,
                              width: w * (g.mean! / maxV).clamp(0.0, 1.0),
                              decoration: BoxDecoration(
                                color: g.mean! > 0.8 ? _green : Colors.blueGrey,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Positioned(
                              left: w * 0.8 / maxV,
                              child: Container(
                                width: 2,
                                height: 14,
                                color: _red,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      ' ${g.mean!.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _small(
            '빨간 선 = 무작위 기대 0.8개. 한 회차 막대는 우연 오차가 큽니다.',
            color: Colors.grey.shade600,
          ),
        ],
      ),
    );
  }

  Widget _storesCard(RoundDebrief r) {
    final prev = r.storesPrev;
    final ag = Map<String, dynamic>.from(
      r.stores['agents'] as Map? ?? const {},
    );
    final top = (ag['top_first_hits'] as List?)?.cast<num>();
    final uni = (ag['uniform_expected'] as List?)?.cast<num>();
    return _card(
      key: const ValueKey('debrief_stores'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('② 추천 명당 채점 (브리핑 ④)'),
          if (prev.isEmpty)
            _small('지난 회차 브리핑 명당 자료 미확보', color: Colors.orange.shade900)
          else
            for (final p in prev)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    tierBadge(p.tier),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          _small(
                            '${p.agentId.replaceAll('|', ' ')} · ${p.source == 'focus' ? '중앙 주목 지역 ${p.focusRank}위의 지방장 1위' : '전국 상위 후보 ${p.topRank}위'}'
                            '${p.pFirst == null ? '' : ' · 모델 추정 p_first ${_pct(p.pFirst!, d: 2)}'}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          _small(
            '1등 ${r.stores['prev_hits_first'] ?? 0}곳 · 2등 ${r.stores['prev_hits_second'] ?? 0}곳 '
            '(모델 추정 기대 1등 ${(r.stores['prev_expected_first'] as num? ?? 0).toStringAsFixed(2)}곳)',
            weight: FontWeight.w700,
          ),
          if (top != null && uni != null)
            _small(
              '지방장 238명 TOP5 안 1등 ${top[2]}곳 · 지역 내 무작위 기대 ${uni[2].toStringAsFixed(2)}곳 · 과거 빈도만 써도 ${ag['history_top5']}곳 · '
              '지방장 범위 밖 1등 ${ag['outside']}곳',
            ),
          if (r.firstStores.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              '이번 회차 1등 판매점',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final f in r.firstStores)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${f['name'] ?? f['code']}',
                      style: const TextStyle(fontSize: 10.5),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _auditCard(RoundDebrief r) {
    Widget block(String title, IconData icon, Color c, List<String> lines) =>
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: c),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: c,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: _small('· $l', color: const Color(0xFF333333)),
                ),
            ],
          ),
        );
    return _card(
      key: const ValueKey('debrief_audit'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('③ 검수'),
          block(
            '실무 분석 관점 — 무엇이 근접했고 무엇을 놓쳤나',
            Icons.insights_rounded,
            const Color(0xFF1565C0),
            r.analyst,
          ),
          block(
            '수학 관점 — 무작위와 구별되는가',
            Icons.functions_rounded,
            const Color(0xFF6A1B9A),
            r.mathematician,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '결론: ${r.verdict}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 4),
          _small(r.auditNote, color: Colors.grey.shade500),
        ],
      ),
    );
  }

  Widget _hypothesesCard(RoundDebrief r) {
    final h = r.hypotheses;
    final by = Map<String, dynamic>.from(h['corrections'] as Map? ?? const {});
    final sp = Map<String, dynamic>.from(h['spatial'] as Map? ?? const {});
    const statusLabel = {
      'rejected': '기각',
      'weakened': '약화',
      'validated': '검증 통과',
      'testing': '검증 중',
      'candidate': '후보',
    };
    return _card(
      key: const ValueKey('debrief_hypotheses'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('④ 가설 점검 — 기존·새 가설'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              statusChip('새 가설 ${h['new'] ?? 0}건', Colors.teal.shade700),
              statusChip('실전 반영 변경 ${h['applied'] ?? 0}건', Colors.indigo),
              for (final e in by.entries)
                statusChip(
                  '${statusLabel[e.key] ?? e.key} ${e.value}건',
                  Colors.grey.shade700,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (sp.isNotEmpty) ...[
            const Text(
              '가설 종류별 이번 회차 발화·적중 (대조 기대)',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            for (final e in sp.entries)
              Builder(
                builder: (_) {
                  final v = Map<String, dynamic>.from(e.value as Map);
                  final fired = (v['fired'] as num? ?? 0),
                      succ = (v['success'] as num? ?? 0),
                      exp = (v['expected'] as num? ?? 0);
                  final better = succ > exp;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${v['label'] ?? e.key}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        Flexible(
                          flex: 3,
                          child: Text(
                            '발화 $fired · 적중 $succ · 기대 ${exp.toStringAsFixed(1)}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: better ? _green : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
          _small(
            '판정은 누적 검정(최소 표본·다중 검정 보정) 기준이며 한 회차로 채택·폐기하지 않습니다.',
            color: Colors.grey.shade600,
          ),
        ],
      ),
    );
  }

  Widget _nextCard(RoundDebrief r) {
    final o = r.nextOfficial;
    final hidden = _release != null && !_release!.released;
    final sets = hidden ? <Map<String, dynamic>>[] : ((o['sets'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final added = ((o['numbers_added'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final removed = ((o['numbers_removed'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final next = r.storesNext;
    final dropped = r.storesDropped;
    return _card(
      key: const ValueKey('debrief_next'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            '⑤ ${r.next}회 변경점',
            chip: statusChip(
              o['status'] == 'ready'
                  ? '${o['training_end']}회까지 학습'
                  : '엔진 반영 대기',
              o['status'] == 'ready' ? _green : Colors.orange.shade800,
            ),
          ),
          const Text(
            '공식 5세트',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          if (sets.isEmpty)
            _small(
              hidden
                  ? '${r.next}회 추천번호는 ${_release!.releaseLabel}에 공개됩니다 (브리핑 맨 위 수동 추천으로 먼저 받을 수 있음).'
                  : '${r.round}회 결과가 엔진에 반영되면 표시됩니다.',
              color: Colors.orange.shade900,
            )
          else
            for (final s in sets)
              Builder(
                builder: (_) {
                  final nums = ((s['numbers'] as List?) ?? const [])
                      .map((e) => (e as num).toInt())
                      .toList();
                  final pop = s['popularity'] as Map?;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        ...nums.map(
                          (n) => Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: lottoBall(n, size: 24),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (pop != null)
                          Expanded(
                            child: Text(
                              '인기 백분위 ${(pop['popularity_pct'] as num).round()} · 몫 ×${(pop['share_vs_random'] as num).toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 10.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
          if (sets.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _small('새로 들어온 번호', weight: FontWeight.w800),
                for (final n in added) _chip('+$n', _green),
                const SizedBox(width: 8),
                _small('빠진 번호', weight: FontWeight.w800),
                for (final n in removed) _chip('−$n', _red),
              ],
            ),
          ],
          const Divider(height: 22),
          const Text(
            '추천 명당',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          if (next.isEmpty)
            _small('${r.next}회 지방장 예측 대기', color: Colors.orange.shade900),
          for (final p in next)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  _chip(
                    p.status == 'kept' ? '유지' : '신규',
                    p.status == 'kept' ? Colors.blueGrey : _green,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      p.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _pFirstChange(p),
                    style: const TextStyle(fontSize: 10.5),
                  ),
                ],
              ),
            ),
          for (final d in dropped)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  _chip('제외', _red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${d['name'] ?? d['code']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _small(
            'p_first = 지방장 모델이 추정한 그 판매점의 회차당 1등 발생 확률 (판매량 미보정 · 한 장당 당첨확률 아님).',
            color: Colors.grey.shade600,
          ),
        ],
      ),
    );
  }

  String _pFirstChange(DebriefStore p) {
    if (p.pFirst == null) return '';
    final now = _pct(p.pFirst!, d: 2);
    if (p.pFirstPrev == null) return 'p_first $now';
    final diff = p.pFirst! - p.pFirstPrev!;
    final arrow = diff.abs() < 1e-5 ? '→' : (diff > 0 ? '↑' : '↓');
    return 'p_first ${_pct(p.pFirstPrev!, d: 2)} $arrow $now';
  }

  Widget _chip(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      t,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c),
    ),
  );

  Widget _probCard(RoundDebrief r) {
    final p = r.probabilities;
    if (p.isEmpty) return const SizedBox.shrink();
    final rows = [
      ('1등 (6개)', _d(p['rank1'])),
      ('2등 (5개+보너스)', _d(p['rank2'])),
      ('3등 (5개)', _d(p['rank3'])),
      ('4등 (4개)', _d(p['rank4'])),
      ('5등 (3개)', _d(p['rank5'])),
      ('5등 이상 (한 세트)', _d(p['any_prize'])),
      ('5세트 중 하나라도 5등 이상', _d(p['any_prize_5sets'])),
    ];
    return _card(
      key: const ValueKey('debrief_prob'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('⑥ ${r.next}회 확률 — 모든 세트 동일'),
          for (final (label, v) in rows)
            if (v != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    Text(
                      _probText(v),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
          _small(
            '추천번호든 무작위든 한 세트의 당첨 확률은 위와 같습니다. 엔진·비인기 추천이 바꿀 수 있는 것은 확률이 아니라 '
            '당첨 시 나눠 가질 사람 수(비인기)와 판매점 선택 근거입니다.',
            color: Colors.grey.shade600,
          ),
        ],
      ),
    );
  }

  double? _d(dynamic v) => (v as num?)?.toDouble();
}

/// 회차 검증 전체 화면 (브리핑 상단 링크에서 이동)
class RoundDebriefScreen extends StatelessWidget {
  final Future<RoundDebrief?> Function()? loader;
  const RoundDebriefScreen({super.key, this.loader});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF8F5FF),
        appBar: AppBar(
          backgroundColor: _purple,
          foregroundColor: Colors.white,
          title: const Text('회차 검증', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: RoundDebriefView(loader: loader),
      );
}

/// 이번 회차 브리핑 맨 위 — 지난 회차 검증 보고로 가는 박스 링크
class RoundDebriefLinkCard extends StatefulWidget {
  final Future<RoundDebrief?> Function()? loader;

  /// 이미 불러온 보고 (회차별 목록에서 사용) — 있으면 loader 대신 사용
  final RoundDebrief? report;
  const RoundDebriefLinkCard({super.key, this.loader, this.report});
  @override
  State<RoundDebriefLinkCard> createState() => _RoundDebriefLinkCardState();
}

class _RoundDebriefLinkCardState extends State<RoundDebriefLinkCard> {
  late final Future<RoundDebrief?> _f =
      widget.report != null ? Future.value(widget.report) : (widget.loader ?? RoundDebriefRepository.loadRound)();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RoundDebrief?>(
      future: _f,
      builder: (context, s) {
        final r = s.data;
        final title = r == null ? '지난 회차 검증 보고' : '${r.round}회 검증 보고';
        String sub;
        if (s.connectionState != ConnectionState.done) {
          sub = '불러오는 중…';
        } else if (r == null) {
          sub = '추첨 후 서버가 결과를 반영하면 자동으로 만들어집니다.';
        } else {
          final off = r.groups.where((g) => g.key == 'official' && g.sets.isNotEmpty).firstOrNull;
          sub = '지난주 추천 채점 · 검수 · ${r.next}회 변경점'
              '${off == null ? '' : ' — 공식 5세트 최고 ${off.bestMatches}개 일치'}'
              ' · 추천 명당 1등 ${r.stores['prev_hits_first'] ?? 0}곳';
        }
        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey(widget.report == null ? 'round_debrief_link' : 'round_debrief_link_${widget.report!.round}'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => RoundDebriefScreen(loader: r != null ? () async => r : widget.loader))),
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF311B92), Color(0xFF5E35B1)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: const Icon(Icons.fact_check_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900))),
                      if (r != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6)),
                          child: Text(r.status == 'final' ? '확정' : '일부 대기',
                              style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 11.5)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 26),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════ 지방장보고 ═══════════════════════
/// 지방장보고 전체 화면 (브리핑 보라색 박스 버튼에서 이동)
class AgentReportScreen extends StatelessWidget {
  final Future<AgentDebrief?> Function()? loader;
  const AgentReportScreen({super.key, this.loader});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFF00695C),
          foregroundColor: Colors.white,
          title: const Text('지방장보고', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: AgentReportView(loader: loader),
      );
}

class AgentReportView extends StatefulWidget {
  final Future<AgentDebrief?> Function()? loader;
  const AgentReportView({super.key, this.loader});
  @override
  State<AgentReportView> createState() => _AgentReportViewState();
}

class _AgentReportViewState extends State<AgentReportView> {
  late Future<AgentDebrief?> _f;
  bool _onlyFirst = true;
  String? _sido;

  @override
  void initState() {
    super.initState();
    _f = (widget.loader ?? RoundDebriefRepository.loadAgents)();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AgentDebrief?>(
      future: _f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (s.hasError)
          return Center(child: Text('지방장 보고를 불러오지 못했습니다: ${s.error}'));
        final d = s.data;
        if (d == null) return const Center(child: Text('아직 지방장 보고가 없습니다.'));
        final sidos = {for (final a in d.agents) a.sido}.toList()..sort();
        final list =
            d.agents
                .where(
                  (a) =>
                      (!_onlyFirst || a.hadFirst || a.secondHits > 0) &&
                      (_sido == null || a.sido == _sido),
                )
                .toList()
              ..sort((a, b) {
                final c = (b.firstHits * 10 + b.secondHits).compareTo(
                  a.firstHits * 10 + a.secondHits,
                );
                return c != 0 ? c : b.firsts.length.compareTo(a.firsts.length);
              });
        final sm = d.summary;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00695C),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '지방장 보고 — ${d.round}회 추천 채점 → ${d.next}회 변경',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '지방장 ${sm['agents']}명 · 1등이 나온 지역 ${sm['with_first']}곳 · TOP5 안 1등 ${sm['top5_first_hits']}곳 · 2등 ${sm['top5_second_hits']}곳',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '각 지방장은 자기 지역 판매점을 순위화합니다. 점수는 과거 1·2등 이력 기반이며 판매량 미보정입니다.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilterChip(
                        key: const ValueKey('agent_only_first'),
                        label: const Text(
                          '당첨 나온 지역만',
                          style: TextStyle(fontSize: 12),
                        ),
                        selected: _onlyFirst,
                        onSelected: (v) => setState(() => _onlyFirst = v),
                      ),
                      ChoiceChip(
                        label: const Text('전국', style: TextStyle(fontSize: 12)),
                        selected: _sido == null,
                        onSelected: (_) => setState(() => _sido = null),
                      ),
                      for (final s in sidos)
                        ChoiceChip(
                          key: ValueKey('agent_sido_$s'),
                          label: Text(
                            s == 'internet' ? '인터넷' : s,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: _sido == s,
                          onSelected: (_) => setState(() => _sido = s),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('조건에 맞는 지방장이 없습니다.'),
                    ),
                ],
              );
            }
            return AgentReportCard(
              report: list[i - 1],
              round: d.round,
              next: d.next,
            );
          },
        );
      },
    );
  }
}

class AgentReportCard extends StatelessWidget {
  final AgentReport report;
  final int round, next;
  const AgentReportCard({
    super.key,
    required this.report,
    required this.round,
    required this.next,
  });

  @override
  Widget build(BuildContext context) {
    final a = report;
    final good = a.firstHits > 0;
    return Container(
      key: ValueKey('agent_report_${a.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: good ? _red.withValues(alpha: 0.4) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  '${a.label} 지방장',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (a.firstHits > 0) tierBadge(1),
              if (a.firstHits == 0 && a.secondHits > 0) tierBadge(2),
            ],
          ),
          subtitle: Text(
            a.note,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          children: [
            Text(
              '$round회 추천 TOP5 → 결과',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            for (final p in a.prev)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text(
                        '${p[2]}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${p[1] ?? p[0]}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      'p ${((p[3] as num) * 100).toStringAsFixed(2)}%  ',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    tierBadge((p[4] as num).toInt()),
                  ],
                ),
              ),
            if (a.firsts.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '이 지역 $round회 1등',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              for (final f in a.firsts)
                _small(
                  '· ${f[1] ?? f[0]} — 사전 ${f[2] ?? '-'}위/${a.n ?? '-'}곳 ${f[3] == null ? '(TOP5 밖 · 놓침)' : '(TOP5 ${f[3]}위 · 적중)'}',
                  color: f[3] == null ? Colors.grey.shade800 : _red,
                ),
              if (a.x != null)
                _small(
                  '지역 내 무작위로 5곳을 골랐을 때 1등 적중 기대 ${a.x![2].toStringAsFixed(2)}곳',
                  color: Colors.grey.shade600,
                ),
            ],
            const SizedBox(height: 6),
            Text(
              '가설 점검',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                statusChip('이번 판정 변화 ${a.changes}건', Colors.grey.shade700),
                statusChip(
                  '실전 배수 변경 ${a.liveChanges}건',
                  a.liveChanges > 0 ? Colors.indigo : Colors.grey.shade700,
                ),
                statusChip('새 가설 ${a.newHyp}건', Colors.teal.shade700),
                for (final e in a.hyp.entries)
                  statusChip('${e.key} ${e.value}', Colors.blueGrey),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$next회 TOP5 (변경점)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            if (a.next.isEmpty)
              _small('$next회 납품 대기', color: Colors.orange.shade900),
            for (final p in a.next)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text(
                        '${p[2]}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${p[1] ?? p[0]}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      'p ${((p[3] as num) * 100).toStringAsFixed(2)}%  ',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    _moveChip(p),
                  ],
                ),
              ),
            for (final dpp in a.dropped)
              _small('· 제외: ${dpp[1] ?? dpp[0]} (이전 ${dpp[2]}위)', color: _red),
          ],
        ),
      ),
    );
  }

  Widget _moveChip(List<dynamic> p) {
    final kept = p[4] == 'kept';
    final prevRank = p.length > 5 ? p[5] as num? : null;
    final rank = (p[2] as num).toInt();
    final t = !kept
        ? '신규'
        : (prevRank == null || prevRank.toInt() == rank
              ? '유지'
              : (prevRank.toInt() > rank
                    ? '↑ ${prevRank.toInt()}→$rank'
                    : '↓ ${prevRank.toInt()}→$rank'));
    final c = !kept ? _green : Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        t,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c),
      ),
    );
  }
}


// ═══════════════════════ 요일별 배치 ═══════════════════════
/// 회차 검증 배치 (추첨일 토요일 기준 한국시간)
///   토·일 = 브리핑 맨 위에 전체 펼침 · 월·화 = 보라색 박스 링크 · 수요일부터 = '지난 회차 검증' 탭에만
enum DebriefPlacement { inline, box, tabOnly }

DebriefPlacement debriefPlacement(String? drawDate, DateTime nowUtc) {
  final d = DateTime.tryParse((drawDate ?? '').replaceAll('.', '-'));
  if (d == null) return DebriefPlacement.box;
  final kst = nowUtc.toUtc().add(const Duration(hours: 9));
  final today = DateTime.utc(kst.year, kst.month, kst.day);
  final days = today.difference(DateTime.utc(d.year, d.month, d.day)).inDays;
  if (days <= 1) return DebriefPlacement.inline;
  if (days <= 3) return DebriefPlacement.box;
  return DebriefPlacement.tabOnly;
}

/// 이번 회차 브리핑 맨 위 — 요일에 따라 펼침 / 보라색 박스 / 표시 안 함
class RoundDebriefTop extends StatefulWidget {
  final Future<RoundDebrief?> Function()? loader;
  final DateTime? nowUtc;
  const RoundDebriefTop({super.key, this.loader, this.nowUtc});
  @override
  State<RoundDebriefTop> createState() => _RoundDebriefTopState();
}

class _RoundDebriefTopState extends State<RoundDebriefTop> {
  late final Future<RoundDebrief?> _f = (widget.loader ?? RoundDebriefRepository.loadRound)();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RoundDebrief?>(
      future: _f,
      builder: (context, s) {
        final r = s.data;
        if (r == null) return const SizedBox.shrink();
        switch (debriefPlacement(r.drawDate, widget.nowUtc ?? DateTime.now().toUtc())) {
          case DebriefPlacement.inline:
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RoundDebriefView(key: const ValueKey('debrief_inline'), embedded: true, loader: () async => r),
            );
          case DebriefPlacement.box:
            return Padding(padding: const EdgeInsets.only(bottom: 12), child: RoundDebriefLinkCard(report: r));
          case DebriefPlacement.tabOnly:
            return const SizedBox.shrink();
        }
      },
    );
  }
}

/// '지난 회차 검증' 탭 — 회차별 보라색 박스 (최신 회차부터)
class RoundDebriefHistoryView extends StatefulWidget {
  final Future<List<RoundDebrief>> Function()? loader;
  const RoundDebriefHistoryView({super.key, this.loader});
  @override
  State<RoundDebriefHistoryView> createState() => _RoundDebriefHistoryViewState();
}

class _RoundDebriefHistoryViewState extends State<RoundDebriefHistoryView> {
  late Future<List<RoundDebrief>> _f = (widget.loader ?? RoundDebriefRepository.loadHistory)();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RoundDebrief>>(
      future: _f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return Center(child: Text('지난 회차 검증을 불러오지 못했습니다: ${s.error}'));
        final list = s.data ?? const <RoundDebrief>[];
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _f = (widget.loader ?? RoundDebriefRepository.loadHistory)());
            await _f;
          },
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _small('회차마다 지난주 브리핑의 추천을 그대로 채점한 기록입니다. 박스를 누르면 전체 검증 보고가 열립니다.'),
            const SizedBox(height: 10),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('아직 검증 기록이 없습니다.')),
            for (final r in list)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: RoundDebriefLinkCard(key: ValueKey('hist_${r.round}'), report: r)),
          ]),
        );
      },
    );
  }
}
