// 관리자 — 전국 지방장 연구소 (전국 지방장 에이전트, research_agent_worker.py · research_agent_replay.py 결과 조회 전용)
//
// 탭: 중앙 엔진 / 지방장 / 가설 저장소 / 성능
// 모델 선택: 자동(최신 실전 ag-1.1 → 없으면 ag-1.0) / ag-1.1 / ag-1.0(이전 스냅샷, 예: 1246회 실전 납품).
// 데이터: research_v5_agents.sql 의 research_agent* 테이블 (SELECT 만). 테이블 없음 = 연구 미실행(SQL 미적용).
// 점수는 연구 기반 후보 점수(회차당 1·2등 기대 빈도, 판매량 미보정)이며 한 장당 당첨확률이 아니다.
// 가설 판정은 evidence.verdict (없으면 status 대체: passed/combined → 검증 통과, weakened/rejected → 검증 실패, 그 외 → 검증 중).
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/research/agent_replay_repository.dart' show AgentReplayRepository;
import '../services/research/agent_research_repository.dart';
import '../services/research/agent_verdicts.dart';
import '../services/route/region_research_repository.dart';
import 'admin_agent_replay_screen.dart';
import '../widgets/admin_region_store_widgets.dart' show regionTag, hypothesisStatusColor;
import '../widgets/agent_store_widgets.dart';

const _teal = kAgentColor;

class AdminAgentResearchScreen extends StatefulWidget {
  final int initialTab;
  const AdminAgentResearchScreen({super.key, this.initialTab = 0});

  @override
  State<AdminAgentResearchScreen> createState() => _AdminAgentResearchScreenState();
}

class _AdminAgentResearchScreenState extends State<AdminAgentResearchScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _adminChecked = false;
  bool _isAdmin = false;
  int _reload = 0;

  /// null = 자동 (최신 실전: ag-1.1 → 없으면 ag-1.0)
  String? _model;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isAdmin = prefs.getBool('isAdmin') ?? false;
      _adminChecked = true;
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _refresh() {
    AgentResearchRepository.clearCache();
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text('전국 지방장 연구소${_model == null ? '' : ' · $_model'}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            tooltip: '모델 선택',
            icon: const Icon(Icons.layers_outlined, color: Colors.white),
            initialValue: _model ?? 'auto',
            onSelected: (v) => setState(() => _model = v == 'auto' ? null : v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'auto', child: Text('자동 (최신 실전: ag-1.1 → 없으면 ag-1.0)')),
              PopupMenuItem(value: kAgentModelReplay, child: Text(agentModelLabel(kAgentModelReplay))),
              PopupMenuItem(value: kAgentModelLegacy, child: Text(agentModelLabel(kAgentModelLegacy))),
            ],
          ),
          IconButton(
            tooltip: '지방장 실전형 재현 기록',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAgentReplayScreen())),
            icon: const Icon(Icons.history_edu, color: Colors.white),
          ),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh, color: Colors.white)),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amber,
          tabs: const [Tab(text: '중앙 엔진'), Tab(text: '지방장'), Tab(text: '가설 저장소'), Tab(text: '성능')],
        ),
      ),
      body: !_adminChecked
          ? const Center(child: CircularProgressIndicator())
          : !_isAdmin
              ? const Center(child: Text('관리자 전용 기능입니다.'))
              : TabBarView(controller: _tab, children: [
                  AgentCentralView(key: ValueKey('central_${_reload}_$_model'), model: _model),
                  _AgentListTab(key: ValueKey('agents_${_reload}_$_model'), model: _model),
                  _HypothesisTab(key: ValueKey('hyps_${_reload}_$_model'), model: _model),
                  _PerformanceTab(key: ValueKey('perf_${_reload}_$_model'), model: _model),
                ]),
    );
  }
}

// ── 공통 ─────────────────────────────────────────────────────────────────

Widget _card(String title, List<Widget> body, {Color color = _teal, Widget? trailing}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color))),
          ?trailing,
        ]),
        const SizedBox(height: 6),
        ...body,
      ]),
    );

Widget _kv(String k, String v, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(k, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        Expanded(
            child: Text(v,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color, height: 1.35))),
      ]),
    );

Widget _note(String s) => Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      padding: const EdgeInsets.all(8),
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: Text(s, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
    );

Color _agentStatusColor(String s) => switch (s) {
      'completed' => Colors.green,
      'running' => Colors.blue,
      'failed' => Colors.red,
      _ => Colors.grey,
    };

String _numericSummary(Map<String, dynamic> m, {int take = 3}) {
  final l = m.entries.where((e) => e.value is num).take(take).map((e) => '${kAgentPerfLabels[e.key] ?? e.key} ${fmtNum(e.value)}');
  return l.isEmpty ? '성능 기록 없음' : l.join(' · ');
}

// ── 탭 2: 지방장 목록 ─────────────────────────────────────────────────────

class _AgentListTab extends StatefulWidget {
  final String? model;
  const _AgentListTab({super.key, this.model});
  @override
  State<_AgentListTab> createState() => _AgentListTabState();
}

class _AgentListTabState extends State<_AgentListTab> {
  final _repo = AgentResearchRepository();
  late Future<ResearchLoad<List<AgentInfo>>> _future;
  String _query = '';
  String? _status;

  @override
  void initState() {
    super.initState();
    _future = _repo.loadAgents(model: widget.model);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ResearchLoad<List<AgentInfo>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final load = snap.data;
        if (load == null || load.data.isEmpty) {
          return ListView(padding: const EdgeInsets.all(14), children: [
            agentStateNote(load?.state ?? ResearchAvailability.error, message: load?.message ?? '${snap.error}'),
          ]);
        }
        final all = load.data;
        final counts = <String, int>{};
        for (final a in all) {
          counts[a.status] = (counts[a.status] ?? 0) + 1;
        }
        final list = all.where((a) => (_status == null || a.status == _status) && a.matches(_query)).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: '지방장 검색 (예: 노원, 수원, 제주, internet)', isDense: true),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('전체 ${all.length}', style: const TextStyle(fontSize: 11)),
                  selected: _status == null,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _status = null),
                ),
              ),
              for (final s in const ['completed', 'running', 'idle', 'failed'])
                if (counts[s] != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('${kAgentStatusLabel[s]} ${counts[s]}', style: const TextStyle(fontSize: 11)),
                      selected: _status == s,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _status = _status == s ? null : s),
                    ),
                  ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final a = list[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => AgentDetailScreen(agentId: a.agentId, initial: a, model: a.modelVersion))),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                              child: Text(a.display,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800))),
                          regionTag(kAgentStatusLabel[a.status] ?? a.status, _agentStatusColor(a.status)),
                        ]),
                        const SizedBox(height: 3),
                        Text(
                            '판매점 ${a.storeCount}곳 (최근 활동 ${a.activeStoreCount}) · 가설 ${a.hypothesisTotal}건'
                            ' (검증 통과 ${a.verifiedHypotheses}) · 납품 ${a.deliveryCount}건'
                            ' · 평가 ${a.lastProcessedRound ?? '-'}회까지',
                            style: const TextStyle(fontSize: 11)),
                        Text(_numericSummary(a.performance),
                            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                        if (a.error != null)
                          Text('오류: ${a.error}', style: TextStyle(fontSize: 10.5, color: Colors.red.shade700)),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}

// ── 지방장 상세 ──────────────────────────────────────────────────────────

class _AgentDetailData {
  final ResearchLoad<AgentInfo?> agent;
  final ResearchLoad<AgentLiveRef?> target;
  final ResearchLoad<List<AgentDelivery>>? deliveries;
  final ResearchLoad<List<AgentHypothesis>> hyps;
  final ResearchLoad<AgentRoundEvalSummary> eval;
  const _AgentDetailData(this.agent, this.target, this.deliveries, this.hyps, this.eval);
}

class AgentDetailScreen extends StatefulWidget {
  final String agentId;
  final AgentInfo? initial;

  /// null = 자동 (최신 실전 모델)
  final String? model;
  const AgentDetailScreen({super.key, required this.agentId, this.initial, this.model});

  @override
  State<AgentDetailScreen> createState() => _AgentDetailScreenState();
}

class _AgentDetailScreenState extends State<AgentDetailScreen> {
  final _repo = AgentResearchRepository();
  late Future<_AgentDetailData> _future;
  String? _hypStatus;
  String? _hypVerdict;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AgentDetailData> _load() async {
    final id = widget.agentId;
    final agent = widget.initial != null
        ? ResearchLoad<AgentInfo?>(ResearchAvailability.available, widget.initial)
        : await _repo.loadAgent(id, model: widget.model);
    final target = await _repo.latestLive(model: widget.model);
    final ref = target.data;
    final deliveries =
        ref == null ? null : await _repo.loadDeliveries(agentId: id, target: ref.target, model: ref.model);
    final hyps = await _repo.loadHypothesesForAgent(id, limit: 200, model: widget.model);
    final eval = await _repo.loadEvalSummary(id);
    return _AgentDetailData(agent, target, deliveries, hyps, eval);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text('지방장 ${agentLabel(widget.agentId)}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (widget.agentId != 'internet')
            IconButton(
              tooltip: '지역 연구 보기',
              onPressed: () => openRegionResearch(context, widget.agentId),
              icon: const Icon(Icons.travel_explore, color: Colors.white),
            ),
        ],
      ),
      body: FutureBuilder<_AgentDetailData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError || snap.data == null) {
            return ListView(padding: const EdgeInsets.all(14), children: [
              agentStateNote(ResearchAvailability.error, message: '${snap.error}'),
            ]);
          }
          return _body(snap.data!);
        },
      ),
    );
  }

  Widget _body(_AgentDetailData d) {
    final a = d.agent.data;
    final children = <Widget>[];
    if (a == null) {
      children.add(agentStateNote(d.agent.state, message: d.agent.message));
    } else {
      children.add(_card('기본 정보', [
        _kv('지방장', '${a.display} (${a.level == 'internet' ? '인터넷 판매' : '시·군·구'})'),
        _kv('상태', '${kAgentStatusLabel[a.status] ?? a.status}${a.lastRunAt == null ? '' : ' · ${a.lastRunAt!.replaceFirst('T', ' ').split('.').first}'}',
            color: _agentStatusColor(a.status)),
        _kv('판매점', '${a.storeCount}곳 · 최근 200회 1·2등 ${a.activeStoreCount}곳 · 좌표 ${a.geoStoreCount}곳'
            ' · 동일 이름·주소 다중 코드 ${a.duplicateGroups}묶음'),
        _kv('평가 완료', a.lastProcessedRound == null ? '-' : '${a.lastProcessedRound}회까지'),
        _kv('마지막 납품', a.lastTargetRound == null ? '-' : '목표 ${a.lastTargetRound}회 · 누적 납품 ${a.deliveryCount}건'),
        _kv('가설', a.hypothesisCounts.isEmpty
            ? '없음'
            : kAgentHypStatusOrder
                .where((s) => a.hypothesisCounts[s] != null)
                .map((s) => '${kAgentHypStatusLabel[s]} ${a.hypothesisCounts[s]}')
                .join(' · ')),
        if (a.error != null) _kv('오류', a.error!, color: Colors.red.shade700),
      ]));
      children.add(_card('하위 구·읍·면·동 연구 (${a.subUnits.length})', [
        if (a.subUnits.isEmpty) const Text('하위 단위 기록 없음', style: TextStyle(fontSize: 11.5)),
        for (final u in a.subUnits.take(40))
          _kv('${u['name'] ?? '-'}',
              '판매점 ${u['stores'] ?? '-'} · 1·2등 ${u['events'] ?? '-'}건 · 1등 ${u['first'] ?? '-'}건'),
      ]));
      children.add(_card('성능 요약 (research_agents.performance · ${a.modelVersion ?? '-'})',
          [AgentPerformanceView(performance: a.performance)]));
    }

    // 납품
    final t = d.target.data?.target;
    final tm = d.target.data?.model;
    final dl = d.deliveries?.data ?? const <AgentDelivery>[];
    children.add(_card('실전 납품${t == null ? '' : ' (목표 $t회 · $tm)'}', [
      if (t == null) agentStateNote(d.target.state, message: d.target.message)
      else if (dl.isEmpty) agentStateNote(d.deliveries?.state ?? ResearchAvailability.noData, message: d.deliveries?.message)
      else ...[
        for (final x in dl.take(30)) _deliveryTile(x),
        if (dl.length > 30) Text('외 ${dl.length - 30}곳', style: const TextStyle(fontSize: 11)),
      ],
      const SizedBox(height: 4),
      const Text('점수 = $kAgentScoreLabel. 한 장당 당첨확률이 아닙니다.',
          style: TextStyle(fontSize: 10, color: Colors.black45)),
    ]));

    // 가설
    final hyps = d.hyps.data
        .where((h) => (_hypStatus == null || h.status == _hypStatus) && verdictMatches(h, _hypVerdict))
        .toList();
    final vc = AgentVerdictCounts.of(d.hyps.data).all;
    children.add(_card('가설 (소유 + 관련 지역) ${d.hyps.data.length}건', [
      if (d.hyps.data.isEmpty) agentStateNote(d.hyps.state, message: d.hyps.message)
      else ...[
        Wrap(spacing: 6, runSpacing: 4, children: [
          ChoiceChip(
            label: const Text('전체', style: TextStyle(fontSize: 11)),
            selected: _hypStatus == null,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => _hypStatus = null),
          ),
          for (final s in kAgentHypStatusOrder)
            if (d.hyps.data.any((h) => h.status == s))
              ChoiceChip(
                label: Text('${kAgentHypStatusLabel[s]} ${d.hyps.data.where((h) => h.status == s).length}',
                    style: const TextStyle(fontSize: 11)),
                selected: _hypStatus == s,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _hypStatus = _hypStatus == s ? null : s),
              ),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          ChoiceChip(
            label: const Text('전체 판정', style: TextStyle(fontSize: 11)),
            selected: _hypVerdict == null,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => _hypVerdict = null),
          ),
          for (final v in kVerdictOrder)
            if (vc[v] != null)
              ChoiceChip(
                label: Text('${verdictShort(v)} ${vc[v]}', style: const TextStyle(fontSize: 11)),
                selected: _hypVerdict == v,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _hypVerdict = _hypVerdict == v ? null : v),
              ),
        ]),
        const SizedBox(height: 6),
        if (hyps.isEmpty) const Text('조건에 맞는 가설 없음', style: TextStyle(fontSize: 11.5)),
        for (final h in hyps.take(60)) agentHypTile(h, showOwner: h.agentId != widget.agentId),
      ],
    ]));

    // 실전형 재현 이력 (ag-1.1)
    children.add(_card('실전형 재현 이력 (${AgentReplayRepository.currentRunId})', [
      const Text('회차별 동결 납품 · 사후 검증 · 최근 10/30/50/100회 성능은 재현 기록에서 봅니다.',
          style: TextStyle(fontSize: 11.5)),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => AgentReplayHistoryScreen(agentId: widget.agentId))),
          icon: const Icon(Icons.history_edu, size: 16),
          label: const Text('재현 이력 보기', style: TextStyle(fontSize: 12)),
        ),
      ),
    ]));

    // 평가
    final e = d.eval.data;
    children.add(_card('회차 평가 합산 (research_agent_round_evals · $kAgentModelLegacy)', [
      if (e.isEmpty) agentStateNote(d.eval.state, message: d.eval.message)
      else ...[
        for (final m in const ['live', 'backtest'])
          if (e.byMode[m] != null) ..._evalLines(e.byMode[m]!),
        _note(kAgentBacktestCaution),
      ],
    ]));
    return ListView(padding: const EdgeInsets.all(12), children: children);
  }

  List<Widget> _evalLines(AgentModeEval m) {
    final title = m.mode == 'live' ? '실전(live, 추첨 전 저장 납품)' : 'backtest(사후 순차 재현)';
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text('$title · ${m.rounds}회차 (${m.firstRound ?? '-'}~${m.lastRound ?? '-'}회)',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: m.mode == 'live' ? Colors.green.shade800 : Colors.blueGrey.shade700)),
      ),
      _kv('실전 목록 적중', '1·2등 ${m.hitsAny}건 (1등 ${m.hitsFirst}) vs 무작위 기대 ${m.expectedUniform.toStringAsFixed(2)}건',
          color: m.hitsAny > m.expectedUniform ? Colors.green.shade800 : null),
      _kv('탐색 / 이력 목록', '탐색 ${m.exploreHitsAny}건 · 이력만 ${m.historyHitsAny}건'),
      _kv('지역 실제 당첨', '1·2등 판매점 ${m.regionEvents}곳 (1등 ${m.regionFirst})'),
    ];
  }

  Widget _deliveryTile(AgentDelivery x) => InkWell(
        onTap: () => showAgentStoreSheet(context, x.storeCode, name: x.storeName),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(
                  width: 24,
                  child: Text('${x.rank}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: _teal))),
              Expanded(child: Text(x.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
              regionTag(x.verification.isEmpty ? '-' : x.verification,
                  x.verification.contains('검증 가설 반영') ? Colors.green : Colors.grey),
            ]),
            Text('점수 ${fmtScore(x.score)} · p_first ${fmtScore(x.pFirst)}'
                '${x.history.isEmpty ? '' : ' · 1등 ${x.history['first'] ?? '-'} · 2등 ${x.history['second'] ?? '-'} · 마지막 ${x.history['last_event_round'] ?? '-'}회'}',
                style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
            if (x.hypotheses.isNotEmpty)
              Wrap(spacing: 4, runSpacing: 3, children: [
                for (final h in x.hypotheses.take(6))
                  regionTag(
                      '${h['summary'] ?? kAgentHypKindLabel[h['kind']] ?? h['kind'] ?? '-'}'
                      ' · ${agentVerdictOf(h['evidence'] is Map ? Map<String, dynamic>.from(h['evidence'] as Map) : {if (h['verdict'] != null) 'verdict': h['verdict']}, h['status']?.toString())}'
                      '${(h['applied_live'] ?? h['applied']) == true ? ' · 실전 ×${fmtNum(h['factor_live'] ?? h['factor'])}' : (h['firing'] == true ? ' · 발화(실전 미반영)' : ' · 관련')}',
                      hypothesisStatusColor('${h['status'] ?? ''}')),
              ]),
          ]),
        ),
      );
}

// ── 탭 3: 가설 저장소 ─────────────────────────────────────────────────────

class _HypothesisTab extends StatefulWidget {
  final String? model;
  const _HypothesisTab({super.key, this.model});
  @override
  State<_HypothesisTab> createState() => _HypothesisTabState();
}

class _HypothesisTabState extends State<_HypothesisTab> {
  final _repo = AgentResearchRepository();
  String? _status;
  String? _kind;
  String? _verdict;
  bool _sharedOnly = false;
  late Future<ResearchLoad<List<AgentHypothesis>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  int get _limit => _verdict == null ? 300 : 600;

  void _reload() {
    _future = _repo.loadHypotheses(kind: _kind, status: _status, limit: _limit, model: widget.model);
  }

  Widget _chips<T>(List<(T?, String)> items, T? selected, ValueChanged<T?> onSel) => SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(it.$2, style: const TextStyle(fontSize: 11)),
                selected: selected == it.$1,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onSel(it.$1),
              ),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 6),
      _chips<String>([
        (null, '전체 상태'),
        for (final s in kAgentHypStatusOrder) (s, kAgentHypStatusLabel[s]!),
      ], _status, (v) => setState(() {
            _status = v;
            _reload();
          })),
      _chips<String>([
        (null, '전체 유형'),
        for (final e in kAgentHypKindLabel.entries) (e.key, e.value),
      ], _kind, (v) => setState(() {
            _kind = v;
            _reload();
          })),
      agentVerdictFilterChips(_verdict, (v) => setState(() {
            final grow = (_verdict == null) != (v == null);
            _verdict = v;
            if (grow) _reload();
          })),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          FilterChip(
            label: const Text('공유된 가설만', style: TextStyle(fontSize: 11)),
            selected: _sharedOnly,
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() => _sharedOnly = v),
          ),
        ]),
      ),
      Expanded(
        child: FutureBuilder<ResearchLoad<List<AgentHypothesis>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final load = snap.data;
            final list = (load?.data ?? const <AgentHypothesis>[])
                .where((h) => (!_sharedOnly || h.isShared) && verdictMatches(h, _verdict))
                .toList();
            final runIds = list.map((h) => h.replayRunId).whereType<String>().toSet();
            return ListView(padding: const EdgeInsets.fromLTRB(12, 6, 12, 24), children: [
              _note('공유 가설 저장소: 각 지방장이 자기 지역 데이터로 발견한 가설을 다른 지방장에게 공유하며, '
                  '발견 시점 이하 데이터로만 찾고 이후 회차로만 검증합니다. FDR 유의 = 발견 구간 다중검정 보정 통과(q<0.10), '
                  '탐색 후보 = 상위 후보지만 유의하지 않음. "동시 연관" 가설은 같은 회차 연관이라 다음 회차 예측에 쓰지 않습니다. '
                  '판정 = evidence.verdict (없으면 status 대체). 판정 필터는 불러온 목록(최대 $_limit건) 안에서 거릅니다.'),
              if (load == null || (load.data.isEmpty))
                agentStateNote(load?.state ?? ResearchAvailability.error, message: load?.message ?? '${snap.error}')
              else if (list.isEmpty)
                const Text('조건에 맞는 가설 없음', style: TextStyle(fontSize: 12))
              else ...[
                Text('${list.length}건 (최근 갱신 순 최대 $_limit건, 상태순 정렬) · 출처 '
                    '${runIds.isNotEmpty ? 'research_replay_hypotheses (${runIds.join(', ')})' : 'research_agent_hypotheses ($kAgentModelLegacy)'}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                for (final h in list) agentHypTile(h),
              ],
            ]);
          },
        ),
      ),
    ]);
  }
}

// ── 탭 4: 성능 ───────────────────────────────────────────────────────────

class _PerformanceTab extends StatefulWidget {
  final String? model;
  const _PerformanceTab({super.key, this.model});
  @override
  State<_PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends State<_PerformanceTab> {
  final _repo = AgentResearchRepository();
  late Future<(ResearchLoad<AgentBriefing?>, ResearchLoad<List<AgentInfo>>)> _future;
  String? _metric;

  @override
  void initState() {
    super.initState();
    _future = _loadAll();
  }

  Future<(ResearchLoad<AgentBriefing?>, ResearchLoad<List<AgentInfo>>)> _loadAll() async =>
      (await _repo.loadBriefing(model: widget.model), await _repo.loadAgents(model: widget.model));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(ResearchLoad<AgentBriefing?>, ResearchLoad<List<AgentInfo>>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError || snap.data == null) {
          return ListView(padding: const EdgeInsets.all(14), children: [
            agentStateNote(ResearchAvailability.error, message: '${snap.error}'),
          ]);
        }
        final (bl, al) = snap.data!;
        final b = bl.data;
        final children = <Widget>[];
        children.add(_card(
            '중앙 엔진 · 지방장 미래 검증 성능${b == null ? '' : ' (목표 ${b.targetRound ?? '-'}회 브리핑, ${b.trainingEndRound ?? '-'}회 기준)'}',
            [
              if (b == null) agentStateNote(bl.state, message: bl.message)
              else AgentPerformanceView(performance: b.performance),
            ]));

        // 지방장별 성능 (research_agents.performance 숫자 키)
        final agents = al.data;
        final keys = <String>{};
        for (final a in agents) {
          for (final e in a.performance.entries) {
            if (e.value is num) keys.add(e.key);
          }
        }
        final keyList = keys.toList()..sort();
        // 원시 적중 건수가 아닌 상대 지표(lift / skill)를 기본 정렬로 사용
        final metric = _metric != null && keys.contains(_metric)
            ? _metric
            : (const ['lift_vs_uniform', 'll_skill', 'hits_vs_model'].where(keys.contains).firstOrNull ??
                keyList.where((k) => k.contains('hits')).firstOrNull ??
                keyList.firstOrNull);
        final ranked = metric == null
            ? <AgentInfo>[]
            : (agents.where((a) => a.performance[metric] is num).toList()
              ..sort((x, y) {
                final c = (y.performance[metric] as num).compareTo(x.performance[metric] as num);
                return c != 0 ? c : x.agentId.compareTo(y.agentId);
              }));
        children.add(_card('지방장별 성능 (상위·하위)', [
          if (agents.isEmpty)
            agentStateNote(al.state, message: al.message)
          else if (metric == null)
            const Text('지방장 성능 기록 없음 (research_agents.performance 비어 있음)', style: TextStyle(fontSize: 11.5))
          else ...[
            Row(children: [
              const Text('정렬 기준  ', style: TextStyle(fontSize: 11.5)),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: metric,
                  items: [
                    for (final k in keyList)
                      DropdownMenuItem(
                          value: k, child: Text(kAgentPerfLabels[k] ?? k, style: const TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) => setState(() => _metric = v),
                ),
              ),
            ]),
            Text('상위 10', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.green.shade800)),
            for (final a in ranked.take(10)) _agentPerfRow(a, metric),
            const SizedBox(height: 6),
            Text('하위 10', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.brown.shade700)),
            for (final a in ranked.reversed.take(10)) _agentPerfRow(a, metric),
            _note('지방장별 수치는 대부분 backtest(사후 순차 재현) 회차에서 나온 값입니다. 판매점 수가 많은 지역일수록 적중 건수가 커지므로 '
                '무작위 기대 적중과 함께 보세요. $kAgentBacktestCaution'),
          ],
        ]));
        return ListView(padding: const EdgeInsets.all(12), children: children);
      },
    );
  }

  Widget _agentPerfRow(AgentInfo a, String metric) => InkWell(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => AgentDetailScreen(agentId: a.agentId, initial: a, model: a.modelVersion))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a.display, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
            Text('${fmtNum(a.performance[metric])}  ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            Text('판매점 ${a.storeCount}', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ]),
        ),
      );
}
