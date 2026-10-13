// 엔진 복기 연구소 (관리자 전용) — 중앙 엔진 · 전국 지방장 회차별 복기, 공간전이 복기, 보정 이력
// 서버가 회차마다 저장한 복기 결과만 읽는다 (계산·수정 없음).
import 'package:flutter/material.dart';

import '../services/research/engine_review_repository.dart';

const _ink = Color(0xFF14213D);
const _accent = Color(0xFF4527A0);

class AdminEngineReviewScreen extends StatefulWidget {
  const AdminEngineReviewScreen({super.key});

  @override
  State<AdminEngineReviewScreen> createState() => _AdminEngineReviewScreenState();
}

class _AdminEngineReviewScreenState extends State<AdminEngineReviewScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);
  List<Map<String, dynamic>> _rounds = [];
  int? _sel;
  Map<String, dynamic>? _round, _agentRound;
  List<Map<String, dynamic>> _cards = [];
  Map<String, String> _names = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rounds = await EngineReviewRepository.rounds();
      final cards = await EngineReviewRepository.cards();
      if (!mounted) return;
      setState(() {
        _rounds = rounds;
        _cards = cards;
      });
      if (rounds.isNotEmpty) await _select((rounds.first['target_round'] as num).toInt());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(int t) async {
    setState(() => _sel = t);
    final r = await EngineReviewRepository.round(t);
    final ar = await EngineReviewRepository.agentRound(t);
    final codes = <String>{};
    for (final e in (ar?['entries'] as List? ?? const [])) {
      for (final w in ((e as Map)['w'] as List? ?? const [])) {
        codes.add('${(w as List)[0]}');
      }
    }
    final names = await EngineReviewRepository.storeNames(codes);
    if (!mounted || _sel != t) return;
    setState(() {
      _round = r;
      _agentRound = ar;
      _names = {..._names, ...names};
    });
  }

  Map<String, Map<String, dynamic>> get _cardById => {for (final c in _cards) '${c['agent_id']}': c};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        title: const Text('엔진 복기 연구소', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(tooltip: '새로고침', icon: const Icon(Icons.refresh_rounded), onPressed: _loadAll)],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amber,
          tabs: const [Tab(text: '중앙 엔진 복기'), Tab(text: '전국 지방장 복기'), Tab(text: '공간전이 복기'), Tab(text: '보정 이력')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _message('복기 기록을 불러오지 못했습니다: $_error')
              : _rounds.isEmpty
                  ? _message('아직 저장된 복기가 없습니다. 서버가 회차 결과를 확인한 뒤 자동으로 복기합니다.')
                  : Column(children: [
                      _roundBar(),
                      Expanded(
                        child: TabBarView(controller: _tab, children: [
                          _centralTab(),
                          _agentsTab(),
                          _spatialTab(),
                          _correctionsTab(),
                        ]),
                      ),
                    ]),
    );
  }

  Widget _message(String m) => Center(
      child: Padding(padding: const EdgeInsets.all(24), child: Text(m, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700))));

  Widget _roundBar() {
    final cur = _rounds.firstWhere((r) => r['target_round'] == _sel, orElse: () => _rounds.first);
    final mode = cur['prediction_mode'] as String?;
    final status = cur['status'] as String?;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(children: [
        const Text('복기 회차', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        DropdownButton<int>(
          key: const ValueKey('review_round_picker'),
          value: _sel,
          isDense: true,
          items: [
            for (final r in _rounds)
              DropdownMenuItem(value: (r['target_round'] as num).toInt(), child: Text('${r['target_round']}회')),
          ],
          onChanged: (v) => v == null ? null : _select(v),
        ),
        const SizedBox(width: 8),
        _chip(reviewModeLabel(mode), mode == 'live' ? const Color(0xFF1E7D4C) : const Color(0xFF6D4C41)),
        const SizedBox(width: 6),
        _chip(status == 'final' ? '복기 확정' : '일부 데이터 미확보', status == 'final' ? _accent : Colors.orange.shade800),
      ]),
    );
  }

  // ── A. 중앙 엔진 복기 ────────────────────────────────────────
  Widget _centralTab() {
    final r = _round;
    if (r == null) return const Center(child: CircularProgressIndicator());
    final briefing = (r['briefing'] as Map?)?['lines'] as List? ?? const [];
    final nums = Map<String, dynamic>.from(r['numbers'] as Map? ?? {});
    final regions = Map<String, dynamic>.from(r['regions'] as Map? ?? {});
    final stores = Map<String, dynamic>.from(r['stores'] as Map? ?? {});
    final sig = Map<String, dynamic>.from(r['signals'] as Map? ?? {});
    return ListView(padding: const EdgeInsets.all(14), children: [
      _card('비서 복기 브리핑', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final l in briefing)
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('$l', style: const TextStyle(fontSize: 12.5, height: 1.45))),
      ])),
      _card('추천번호 vs 실제 당첨번호', _numbers(nums)),
      _card('추천 지역 vs 실제 1등 지역', _regions(regions)),
      _card('추천 판매점 vs 실제 1등 판매점', _stores(stores)),
      _card('적용 신호 · 다음 회차 반영', _signals(sig)),
    ]);
  }

  Widget _numbers(Map<String, dynamic> n) {
    if (n['actual'] == null) return _muted('${n['status'] ?? '당첨번호 미확보'}');
    Widget src(String label, dynamic v) {
      if (v is! Map) return const SizedBox.shrink();
      if (v['sets'] == null) return _kv(label, '${v['status'] ?? '데이터 미확보'}');
      final pre = v['pre_draw'];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label · 최고 ${v['best_matches']}개 일치(${reviewRankLabel(v['best_rank'] as int?)}) · 평균 ${(v['mean_matches'] as num).toStringAsFixed(2)}개'
              '${pre == false ? ' · 추첨 후 생성본(사전 예측 아님)' : ''}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pre == false ? Colors.orange.shade800 : _ink)),
          const SizedBox(height: 4),
          for (final s in v['sets'] as List)
            Text('  ${((s as Map)['numbers'] as List).join(' · ')}  →  ${s['matches']}개${s['bonus'] == 1 ? '+보너스' : ''} (${reviewRankLabel(s['rank'] as int?)})',
                style: const TextStyle(fontSize: 11.5, fontFeatures: [])),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kv('실제 당첨번호', '${(n['actual'] as List).join(' · ')} + ${n['bonus']}'),
      const SizedBox(height: 6),
      src('공식 최종 추천번호', n['official']),
      src('구매예측번호', n['purchase']),
      if (n['public'] != null) src('일반 공개 3세트', n['public']),
      if (n['number_engine'] != null) src('번호 엔진 기본 조합', n['number_engine']),
      for (final x in (n['registry'] as List? ?? const []))
        if ((x as Map)['algorithm'] == 'random_control') src('무작위 대조군', x),
      _muted('모든 번호 조합의 1등 당첨확률은 같습니다. 일치 개수는 판매점 적중과 섞지 않습니다. 무작위 기대 평균 0.8개.'),
    ]);
  }

  Widget _regions(Map<String, dynamic> r) {
    if (r['focus_top10'] == null) return _muted('${r['status'] ?? '데이터 미확보'}');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final f in r['focus_top10'] as List)
          _chip('${(f as Map)['region_id']}'.replaceAll('|', ' '), f['hit'] == true ? const Color(0xFF1E7D4C) : Colors.grey.shade600),
      ]),
      const SizedBox(height: 8),
      _kv('TOP10 중 1등 지역', '${r['focus_hits']}곳 (판매점 수 비례 기준 ${r['focus_hits_store_count_baseline']}곳 · 모델 기대 ${(r['focus_expected'] as num?)?.toStringAsFixed(1)}곳)'),
      _kv('이번 회차 1등 지역 수', '${r['regions_with_first']}곳'),
    ]);
  }

  Widget _stores(Map<String, dynamic> s) {
    if (s['first_stores'] == null) return _muted('${s['status'] ?? '데이터 미확보'}');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kv('추천 TOP20 1등 적중', '${s['hits_first']}곳 (1·2등 ${s['hits_any']}곳 · 무작위 기대 ${(s['uniform_expected_any'] as num?)?.toStringAsFixed(2)}곳 · 과거 빈도 기준 ${s['history_baseline_hits_any']}곳)'),
      const SizedBox(height: 6),
      for (final f in s['first_stores'] as List)
        Text('• ${(f as Map)['name'] ?? f['store_code']}  ${f['in_top20'] == true ? '(추천 TOP20 포함)' : ''}',
            style: TextStyle(fontSize: 11.5, color: f['in_top20'] == true ? const Color(0xFF1E7D4C) : _ink)),
      if ((s['unmatched_first'] ?? 0) != 0) _muted('판매점 목록에 없는 1등 기록 ${s['unmatched_first']}건은 평가에서 제외'),
    ]);
  }

  Widget _signals(Map<String, dynamic> s) {
    String yn(dynamic v) => v == true ? '적용' : v == false ? '미적용' : '-';
    final t = s['this_round'] as Map?, n = s['next_round'] as Map?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (t != null) _kv('이번 회차 공식 번호', '가설 ${yn(t['hypothesis_applied'])} · 보정 ${yn(t['correction_applied'])} · Joint ${yn(t['joint_applied'])}'),
      if (n != null) _kv('다음 회차 공식 번호', '가설 ${yn(n['hypothesis_applied'])} · 보정 ${yn(n['correction_applied'])} · Joint ${yn(n['joint_applied'])}'),
      _kv('지방장 실전 적용 가설', '${s['agent_live_hypotheses_this'] ?? '-'} → ${s['agent_live_hypotheses_next'] ?? '-'}개'
          '${s['next_prediction_frozen'] == true ? '' : ' (다음 회차 동결 전)'}'),
      if (t?['store_spatial_mnd'] != null) _muted('Store·Spatial·MND: ${t!['store_spatial_mnd']}'),
    ]);
  }

  // ── B. 전국 지방장 복기 ──────────────────────────────────────
  String _sidoFilter = '전체';
  bool _onlyWinners = false;

  Widget _agentsTab() {
    final ar = _agentRound;
    if (ar == null) return _message('이 회차 지방장 복기가 아직 없습니다 (서버 복기 대기).');
    final ids = [for (final a in ar['agent_ids'] as List) '$a'];
    final entries = [for (final e in ar['entries'] as List) AgentRoundEntry.fromJson(e as Map)];
    final sidos = ['전체', ...{for (final id in ids) id.split('|').first}];
    final rows = <int>[
      for (var i = 0; i < ids.length; i++)
        if ((_sidoFilter == '전체' || ids[i].startsWith('$_sidoFilter|') || ids[i] == _sidoFilter) &&
            (!_onlyWinners || entries[i].regionFirst > 0))
          i,
    ];
    final sm = Map<String, dynamic>.from(ar['summary'] as Map? ?? {});
    final integ = Map<String, dynamic>.from(ar['integrity'] as Map? ?? {});
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('복기 ${sm['reviewed']}/${sm['agents']}명 · 1등 지역 ${sm['region_first_agents']}곳 · TOP1/3/5 1등 적중 ${(sm['top_first_hits'] as List?)?.join('/')} '
              '(무작위 기대 ${(sm['top_expected_uniform'] as List?)?.map((e) => (e as num).toStringAsFixed(2)).join('/')}) · 과거 빈도 TOP5 ${sm['history_first_hits5']}',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          if (integ['stored_snapshot_used'] == true)
            Text('동결 사전 예측 사용 · 재계산 일치 ${integ['recompute_matches_stored'] == true ? '예' : '아니오'}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          Row(children: [
            DropdownButton<String>(
              value: _sidoFilter,
              isDense: true,
              items: [for (final s in sidos) DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12)))],
              onChanged: (v) => setState(() => _sidoFilter = v ?? '전체'),
            ),
            const Spacer(),
            FilterChip(
              label: const Text('1등 나온 지역만', style: TextStyle(fontSize: 11)),
              selected: _onlyWinners,
              onSelected: (v) => setState(() => _onlyWinners = v),
            ),
          ]),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, k) {
            final i = rows[k];
            final e = entries[i];
            final id = ids[i];
            return ListTile(
              key: ValueKey('agent_row_$id'),
              dense: true,
              title: Text(id.replaceAll('|', ' '), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: Text(
                e.noWinner
                    ? '지역 1등 없음 (추천 미적중과 구분) · 판매점 ${e.nStores}곳'
                    : 'TOP1/3/5 1등 적중 ${e.hits.join('/')} (기대 ${e.expected.map((x) => x.toStringAsFixed(2)).join('/')}) · '
                        '실제 1등 ${e.regionFirst}곳: ${e.winners.map((w) => '${_names[w.code] ?? w.code} 사전 ${w.priorRank ?? '-'}위').join(', ')}',
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AgentReviewDetailScreen(
                    agentId: id, agentIndex: i, round: _sel!, entry: e, card: _cardById[id], names: _names,
                    mode: ar['prediction_mode'] as String?))),
            );
          },
        ),
      ),
    ]);
  }

  // ── C. 공간전이 복기 ─────────────────────────────────────────
  Widget _spatialTab() {
    final cur = Map<String, dynamic>.from((_round?['spatial'] as Map?) ?? {});
    final cum = <String, List<num>>{};
    for (final r in _rounds) {
      for (final e in ((r['spatial'] as Map?) ?? const {}).entries) {
        final v = e.value as Map;
        final c = cum.putIfAbsent('${e.key}', () => [0, 0, 0.0]);
        c[0] += (v['fired'] as num? ?? 0);
        c[1] += (v['success'] as num? ?? 0);
        c[2] += (v['expected'] as num? ?? 0);
      }
    }
    Widget table(Map<String, List<num>> m) => Column(children: [
          for (final e in m.entries)
            _kv(kReviewGroupLabel[e.key] ?? e.key,
                '발화 ${e.value[0]} · 적중 ${e.value[1]} · 대조 기대 ${e.value[2].toStringAsFixed(1)}'
                '${e.value[2] > 0 ? ' · 적중/기대 ${(e.value[1] / e.value[2]).toStringAsFixed(2)}' : ''}'),
        ]);
    return ListView(padding: const EdgeInsets.all(14), children: [
      _card('$_sel회 관계 가설 발화·적중', cur.isEmpty
          ? _muted('이 회차 발화 기록 없음')
          : table({for (final e in cur.entries) e.key: [(e.value as Map)['fired'] as num, e.value['success'] as num, e.value['expected'] as num]})),
      _card('누적 (${_rounds.length}개 회차)', table(cum)),
      _card('읽는 법', _muted(
          '동시 당첨(같은 회차)과 선행·후행(다음 회차 이후)을 구분해 셉니다. 대조 기대는 같은 회차에 발화하지 않은 대조군의 적중률로 계산합니다. '
          '여러 지역·판매점 관계를 동시에 탐색하므로 우연 발견을 막기 위해 가설 판정은 발견 데이터와 검증 데이터를 나누고 최소 표본·다중 검정 보정을 통과해야 합니다. '
          '이 표의 적중/기대 비율만으로 검증 통과를 뜻하지 않습니다.')),
    ]);
  }

  // ── D. 보정 이력 ─────────────────────────────────────────────
  bool _appliedOnly = false;

  Widget _correctionsTab() {
    final corr = Map<String, dynamic>.from((_round?['corrections'] as Map?) ?? {});
    final items = [for (final c in (corr['items'] as List? ?? const [])) Map<String, dynamic>.from(c as Map)]
        .where((c) => !_appliedOnly || c['applied'] == true)
        .toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      _card('$_sel회 보정', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _kv('주요 판정 변화', '${corr['count'] ?? 0}건 (실전 배수 변경 ${corr['applied'] ?? 0}건)'),
        _kv('일상 전환 · 신규 후보', '${corr['routine_transitions'] ?? 0}건 · ${corr['new_hypotheses'] ?? 0}건'),
        Row(children: [
          const Spacer(),
          FilterChip(label: const Text('실전 반영만', style: TextStyle(fontSize: 11)), selected: _appliedOnly,
              onSelected: (v) => setState(() => _appliedOnly = v)),
        ]),
        if (items.isEmpty) _muted('표시할 보정이 없습니다. 실패 한 번으로 가중치를 바꾸지 않으며, 누적 검정 기준을 넘을 때만 실전 배수가 바뀝니다.'),
        for (final c in items)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c['applied'] == true ? const Color(0xFFEDE7F6) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${'${c['agent_id']}'.replaceAll('|', ' ')} · ${c['kind']} · ${c['from']} → ${c['to']}\n'
              '실전 배수 ${c['factor_before']} → ${c['factor_after']} · 검증 ${c['test_k']}/${c['test_n']} (대조 기대 ${c['test_expected']}, p=${c['test_p']})\n'
              '${c['reason']}',
              style: const TextStyle(fontSize: 11.5, height: 1.4),
            ),
          ),
      ])),
      _card('회차별 보정 기록', Column(children: [
        for (final r in _rounds.take(40))
          _kv('${r['target_round']}회', '주요 변화 ${r['corr_count'] ?? 0}건 · 실전 반영 ${r['corr_applied'] ?? 0}건'),
      ])),
    ]);
  }

  // ── 공통 ─────────────────────────────────────────────────────
  Widget _card(String title, Widget body) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _accent.withValues(alpha: 0.18))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _accent)),
          const SizedBox(height: 8),
          body,
        ]),
      );
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(k, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600))),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _ink, height: 1.35))),
      ]),
    );

Widget _muted(String s) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(s, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.4)),
    );

Widget _chip(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
    );

// ── 지방장 상세 ────────────────────────────────────────────────
class AgentReviewDetailScreen extends StatefulWidget {
  final String agentId;
  final int agentIndex, round;
  final AgentRoundEntry entry;
  final Map<String, dynamic>? card;
  final Map<String, String> names;
  final String? mode;
  const AgentReviewDetailScreen({
    super.key,
    required this.agentId,
    required this.agentIndex,
    required this.round,
    required this.entry,
    required this.card,
    required this.names,
    required this.mode,
  });

  @override
  State<AgentReviewDetailScreen> createState() => _AgentReviewDetailScreenState();
}

class _AgentReviewDetailScreenState extends State<AgentReviewDetailScreen> {
  (List<String>, List<double>)? _top5;
  List<(int, String?, AgentRoundEntry)> _history = [];
  Map<String, String> _names = {};

  @override
  void initState() {
    super.initState();
    _names = Map.of(widget.names);
    _load();
  }

  Future<void> _load() async {
    final top = await EngineReviewRepository.frozenTop5(widget.round, widget.agentId);
    final hist = await EngineReviewRepository.agentHistory(widget.agentIndex);
    final names = await EngineReviewRepository.storeNames([...?top?.$1, for (final h in hist) for (final w in h.$3.winners) w.code]);
    if (!mounted) return;
    setState(() {
      _top5 = top;
      _history = hist;
      _names.addAll(names);
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final cards = Map<String, dynamic>.from((widget.card?['cards'] as Map?) ?? {});
    final hyp = Map<String, dynamic>.from((widget.card?['hypotheses'] as Map?) ?? {});
    final winnerCodes = {for (final w in e.winners) w.code};
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(backgroundColor: _accent, foregroundColor: Colors.white,
          title: Text('${widget.agentId.replaceAll('|', ' ')} 지방장 복기', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        _box('${widget.round}회 예측 vs 실제 · ${reviewModeLabel(widget.mode)}', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('① 사전 추천 TOP5', style: _h),
          if (_top5 == null) _muted('불러오는 중…'),
          if (_top5 != null)
            for (var r = 0; r < _top5!.$1.length; r++)
              Text('  ${r + 1}위 ${_names[_top5!.$1[r]] ?? _top5!.$1[r]}'
                  '${r < _top5!.$2.length ? ' · 점수 ${_top5!.$2[r].toStringAsFixed(4)}' : ''}'
                  '${winnerCodes.contains(_top5!.$1[r]) ? '  ✔ 1등' : ''}',
                  style: TextStyle(fontSize: 12, color: winnerCodes.contains(_top5!.$1[r]) ? const Color(0xFF1E7D4C) : _ink)),
          const SizedBox(height: 6),
          Text('② 실제 결과', style: _h),
          if (e.noWinner)
            _muted('이 지역에서는 1등 판매점이 나오지 않았습니다 (추천 판매점 미당첨과 구분). 2등 ${e.second}곳.')
          else
            for (final w in e.winners)
              Text('  ${_names[w.code] ?? w.code} · 추첨 전 순위 ${w.priorRank ?? '-'}위/${e.nStores}곳 · '
                  '${w.hitRank != null ? 'TOP5 ${w.hitRank}위로 적중${w.normalized ? ' (코드 정규화)' : ''}' : '추천 밖'}',
                  style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Text('③·④ 맞힌 부분 / 틀린 부분', style: _h),
          _kv('TOP1/3/5 1등 적중', '${e.hits.join('/')} (지역 내 무작위 기대 ${e.expected.map((x) => x.toStringAsFixed(2)).join('/')})'),
          _kv('TOP5 1·2등 적중', '${e.any5}곳 · 과거 빈도만 쓴 TOP5 1등 ${e.history5}곳'),
          _kv('추천 밖 1등', '${e.winners.where((w) => w.hitRank == null).length}곳'),
          const SizedBox(height: 6),
          Text('⑤ 원인 분석 — 이번 회차 가설 발화', style: _h),
          if (e.groups.isEmpty) _muted('발화한 가설 없음'),
          for (final g in e.groups.entries)
            _kv(kReviewGroupLabel[g.key] ?? g.key,
                '발화 ${g.value[0]} · 적중 ${g.value[1]} · 대조 기대 ${g.value[2].toStringAsFixed(2)} · 실전 적용 ${g.value[3]}'),
          const SizedBox(height: 6),
          Text('⑥·⑦ 가설 판정 · 다음 회차 보정', style: _h),
          if (e.changes.isEmpty) _muted('주요 판정 변화 없음 (일상 전환 ${e.routine}건 · 신규 후보 ${e.newHyp}건). 실전 배수는 그대로 유지.'),
          for (final c in e.changes)
            Text('  ${c.kind} ${c.from}→${c.to} · 배수 ${c.factorBefore}→${c.factorAfter} ${c.applied ? '(실전 반영 변경)' : '(실전 반영 변화 없음)'} · 검증 ${c.k}/${c.n}, p=${c.p}',
                style: const TextStyle(fontSize: 11.5)),
        ])),
        _box('성적표 (최근 10·30·100회 · 전체)', Column(children: [
          for (final w in const ['10', '30', '100', 'all', 'live_rounds'])
            if (cards[w] is Map && (cards[w]['rounds'] ?? 0) > 0) _cardRow(w == 'all' ? '전체' : w == 'live_rounds' ? '실전 회차' : '최근 $w회', Map<String, dynamic>.from(cards[w] as Map)),
        ])),
        _box('가설 판정 현황 (현재)', hyp.isEmpty
            ? _muted('가설 없음')
            : Wrap(spacing: 6, runSpacing: 6, children: [for (final h in hyp.entries) _chip('${h.key} ${h.value}', _accent)])),
        _box('최근 회차 이력', Column(children: [
          if (_history.isEmpty) _muted('불러오는 중…'),
          for (final h in _history.take(20))
            _kv('${h.$1}회${h.$2 == 'live' ? ' (실전)' : ''}',
                h.$3.noWinner ? '지역 1등 없음' : 'TOP1/3/5 ${h.$3.hits.join('/')} · 1등 ${h.$3.regionFirst}곳 (사전 순위 ${h.$3.winners.map((w) => w.priorRank ?? '-').join(', ')})'),
        ])),
        _muted('판매량 분모가 없어 판매점별 한 장당 당첨확률을 계산하지 않습니다. 성적은 지역 내 무작위·과거 빈도 기준과 비교한 적중 수입니다.'),
      ]),
    );
  }

  Widget _cardRow(String label, Map<String, dynamic> c) {
    final h = (c['top_hits'] as List?) ?? const [0, 0, 0];
    final x = (c['top_expected_uniform'] as List?) ?? const [0, 0, 0];
    return _kv(label,
        '${c['rounds']}회 · 1등 나온 회차 ${c['rounds_with_first']} · TOP1/3/5 ${h.join('/')} (기대 ${x.map((v) => (v as num).toStringAsFixed(2)).join('/')}) · '
        '과거빈도 ${c['history_top5_hits']} · 추천 밖 ${c['outside_winners']} · 당첨점 사전순위 중앙값 ${c['winner_prior_rank_median'] ?? '-'}'
        '${c['top5_p_value'] != null ? ' · p=${c['top5_p_value']}' : ''}${c['sample_flag'] != null ? ' · ${c['sample_flag']}' : ''}');
  }

  static const _h = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _accent);

  Widget _box(String title, Widget body) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 8),
          body,
        ]),
      );
}

/// 엔진 브리핑용 — 최신 복기 브리핑 (저장 수치로 생성된 문장 그대로)
class EngineReviewBriefingCard extends StatefulWidget {
  final Future<Map<String, dynamic>?> Function()? loader;
  const EngineReviewBriefingCard({super.key, this.loader});

  @override
  State<EngineReviewBriefingCard> createState() => _EngineReviewBriefingCardState();
}

class _EngineReviewBriefingCardState extends State<EngineReviewBriefingCard> {
  late final Future<Map<String, dynamic>?> _f = (widget.loader ?? EngineReviewRepository.latestBriefing)();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _f,
      builder: (context, s) {
        final r = s.data;
        final lines = (r?['briefing'] as Map?)?['lines'] as List? ?? const [];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _accent.withValues(alpha: 0.25))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.fact_check_rounded, color: _accent, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(r == null ? '회차 복기 브리핑' : '${r['target_round']}회 복기 브리핑',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _accent))),
              if (r != null) _chip(r['status'] == 'final' ? '확정' : '일부 미확보', r['status'] == 'final' ? _accent : Colors.orange.shade800),
            ]),
            const SizedBox(height: 8),
            if (s.connectionState != ConnectionState.done)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else if (s.hasError || r == null)
              _muted(s.hasError ? '복기 브리핑을 불러오지 못했습니다 (research_v10_review.sql 적용 여부 확인)' : '아직 복기가 없습니다. 회차 결과가 준비되면 서버가 자동으로 복기합니다.')
            else
              for (final l in lines.take(13))
                Padding(padding: const EdgeInsets.only(bottom: 5), child: Text('$l', style: const TextStyle(fontSize: 12, height: 1.45))),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminEngineReviewScreen())),
                child: const Text('엔진 복기 연구소 열기'),
              ),
            ),
          ]),
        );
      },
    );
  }
}
