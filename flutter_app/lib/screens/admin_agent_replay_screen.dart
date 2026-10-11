// 관리자 — 지방장 실전형 재현 기록 (research_agent_replay.py 결과 조회 전용)
//
// 재현 실행 선택: research_replay_runs 의 실행 목록 (기본 = 현재 실행, 'ag-1.1-r1').
//   data_provenance.defect 가 있는 실행에만 결함 배지, integrity_check 가 있으면 무결성 검증 줄을 표시한다.
// 탭: 회차별 / 지방장 이력 / 가설 실전 성능 / 누적 성능 (모두 선택한 실행 기준)
// 데이터: research_v6_replay.sql 의 research_replay_* 테이블 + research_agents(ag-1.1) (SELECT 만).
// 테이블 없음 = '실전형 재현 미실행(SQL 미적용)'. 값이 없으면 '-' 로 표시하고 추정값을 만들지 않는다.
// 사후 재현 = 해당 회차 이전 데이터만 사용해 추첨 이후 계산한 기록, 실전 = 추첨 전 동결. 항상 구분해 표시한다.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/research/agent_replay_repository.dart';
import '../services/research/agent_research_repository.dart';
import '../services/research/agent_verdicts.dart';
import '../services/route/region_research_repository.dart';
import '../widgets/admin_region_store_widgets.dart' show regionTag, hypothesisStatusColor;
import '../widgets/agent_replay_widgets.dart';
import '../widgets/agent_store_widgets.dart';
import '../widgets/db_usage_card.dart';

const _c = kReplayColor;

class AdminAgentReplayScreen extends StatefulWidget {
  final int initialTab;
  final int? initialRound;
  const AdminAgentReplayScreen({super.key, this.initialTab = 0, this.initialRound});

  @override
  State<AdminAgentReplayScreen> createState() => _AdminAgentReplayScreenState();
}

class _AdminAgentReplayScreenState extends State<AdminAgentReplayScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _adminChecked = false;
  bool _isAdmin = false;
  int _reload = 0;

  /// 선택한 재현 실행 (null = 확인 중)
  String? _runId;
  List<ReplayRun> _runs = const [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));
    _checkAdmin();
    _initRuns();
  }

  Future<void> _initRuns({bool force = false}) async {
    final current = await AgentReplayRepository.resolveCurrentRunId(force: force);
    final runs = await AgentReplayRepository(runId: current).loadRuns(force: force);
    if (!mounted) return;
    setState(() {
      _runs = runs.data;
      _runId ??= current;
    });
  }

  Widget _runSelector() {
    final ids = {?_runId, ..._runs.map((r) => r.runId)}.toList()..sort();
    ReplayRun? runOf(String id) => _runs.where((r) => r.runId == id).firstOrNull;
    final sel = _runId == null ? null : runOf(_runId!);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('재현 실행  ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: true,
              value: _runId,
              hint: const Text('실행 확인 중…', style: TextStyle(fontSize: 12)),
              items: [
                for (final id in ids)
                  DropdownMenuItem(
                    value: id,
                    child: Text(
                        '$id · ${agentModelLabel(runOf(id)?.modelVersion ?? agentModelForRun(id))}'
                        '${id == AgentReplayRepository.currentRunId ? ' · 현재(기본)' : ''}'
                        '${runOf(id)?.hasDefect == true ? ' · 결함 표시' : ''}',
                        style: const TextStyle(fontSize: 12)),
                  ),
              ],
              onChanged: (v) {
                if (v != null && v != _runId) setState(() => _runId = v);
              },
            ),
          ),
        ]),
        if (sel != null && (sel.hasDefect || sel.integrityLine != null))
          Wrap(spacing: 4, runSpacing: 3, children: [
            if (replayRunDefectBadge(sel) != null) regionTag(replayRunDefectBadge(sel)!, Colors.red),
            if (sel.integrityLine != null) Text(sel.integrityLine!, style: TextStyle(fontSize: 10.5, color: Colors.green.shade800)),
          ]),
      ]),
    );
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
    AgentReplayRepository.clearCache();
    AgentResearchRepository.clearCache();
    setState(() => _reload++);
    _initRuns(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F7),
      appBar: AppBar(
        backgroundColor: _c,
        foregroundColor: Colors.white,
        title: const Text('지방장 실전형 재현 기록', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh, color: Colors.white))],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amber,
          tabs: const [Tab(text: '회차별'), Tab(text: '지방장 이력'), Tab(text: '가설 실전 성능'), Tab(text: '누적 성능')],
        ),
      ),
      body: !_adminChecked
          ? const Center(child: CircularProgressIndicator())
          : !_isAdmin
              ? const Center(child: Text('관리자 전용 기능입니다.'))
              : _runId == null
                  ? const Center(child: CircularProgressIndicator())
                  : Column(children: [
                      _runSelector(),
                      Expanded(
                        child: TabBarView(controller: _tab, children: [
                          _RoundTab(
                              key: ValueKey('round_${_reload}_$_runId'), runId: _runId!, initialRound: widget.initialRound),
                          _AgentListTab(key: ValueKey('agents_${_reload}_$_runId'), runId: _runId!),
                          _HypothesisTab(key: ValueKey('hyps_${_reload}_$_runId'), runId: _runId!),
                          _CumulativeTab(key: ValueKey('cum_${_reload}_$_runId'), runId: _runId!),
                        ]),
                      ),
                    ]),
    );
  }
}

// ── 공통 ─────────────────────────────────────────────────────────────────

Widget _card(String title, List<Widget> body, {Color color = _c, Widget? trailing}) => Container(
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
        SizedBox(width: 128, child: Text(k, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        Expanded(
            child: Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color, height: 1.35))),
      ]),
    );

Widget _note(String s, {Color? color}) => Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      padding: const EdgeInsets.all(8),
      width: double.infinity,
      decoration: BoxDecoration(color: color ?? Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: Text(s, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800, height: 1.4)),
    );

String _n(dynamic v, [int d = 2]) => fmtNum(v, d);

String _ratio(num? a, num? b) => a == null || b == null || b <= 0 ? '-' : '×${(a / b).toStringAsFixed(2)}';

const String _modeExplain = '사후 재현: 해당 회차 이전 데이터만 사용해 추첨 이후 계산한 기록 · 실전: 추첨 전 동결';

// ═══════════════════════════════════════════════════════════════════════
// 탭 1: 회차별
// ═══════════════════════════════════════════════════════════════════════

class _RoundTab extends StatefulWidget {
  final String runId;
  final int? initialRound;
  const _RoundTab({super.key, required this.runId, this.initialRound});
  @override
  State<_RoundTab> createState() => _RoundTabState();
}

class _RoundTabState extends State<_RoundTab> {
  late final _repo = AgentReplayRepository(runId: widget.runId);
  late Future<(ResearchLoad<ReplayRun?>, ResearchLoad<List<ReplayPrediction>>)> _meta;
  Future<(ResearchLoad<ReplayRoundDetail?>, Map<String, String>)>? _detail;
  int? _round;

  @override
  void initState() {
    super.initState();
    _meta = _loadMeta();
  }

  Future<(ResearchLoad<ReplayRun?>, ResearchLoad<List<ReplayPrediction>>)> _loadMeta() async {
    final run = await _repo.loadRun();
    final rounds = await _repo.loadRounds();
    final l = rounds.data;
    if (l.isNotEmpty) {
      final want = widget.initialRound;
      _round = want != null && l.any((p) => p.targetRound == want) ? want : l.last.targetRound;
      _detail = _loadDetail(_round!);
    }
    return (run, rounds);
  }

  Future<(ResearchLoad<ReplayRoundDetail?>, Map<String, String>)> _loadDetail(int round) async {
    final d = await _repo.loadRoundDetail(round);
    final codes = <String>{...?d.data?.result?.firstStoreIds};
    final names = codes.isEmpty ? const <String, String>{} : await _repo.storeNames(codes);
    return (d, names);
  }

  void _select(int round) => setState(() {
        _round = round;
        _detail = _loadDetail(round);
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(ResearchLoad<ReplayRun?>, ResearchLoad<List<ReplayPrediction>>)>(
      future: _meta,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError || snap.data == null) {
          return ListView(padding: const EdgeInsets.all(14), children: [
            replayStateNote(ResearchAvailability.error, message: '${snap.error}'),
          ]);
        }
        final (run, rounds) = snap.data!;
        final list = rounds.data;
        final children = <Widget>[
          const DbUsageCard(),
          const SizedBox(height: 10),
          _runCard(run),
        ];
        if (list.isEmpty) {
          children.add(replayStateNote(rounds.state, message: rounds.message));
          return ListView(padding: const EdgeInsets.all(12), children: children);
        }
        final desc = list.reversed.toList();
        final idx = desc.indexWhere((p) => p.targetRound == _round);
        final live = list.where((p) => p.isLive).length;
        children.add(_card('회차 선택', [
          Row(children: [
            IconButton(
              tooltip: '이전 회차',
              onPressed: idx >= 0 && idx < desc.length - 1 ? () => _select(desc[idx + 1].targetRound) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: _round,
                items: [
                  for (final p in desc)
                    DropdownMenuItem(
                      value: p.targetRound,
                      child: Text(
                          '${p.targetRound}회 · ${replayModeShort(p.replayMode)} · ${p.availableThrough ?? '-'}회까지 데이터',
                          style: const TextStyle(fontSize: 12)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) _select(v);
                },
              ),
            ),
            IconButton(
              tooltip: '다음 회차',
              onPressed: idx > 0 ? () => _select(desc[idx - 1].targetRound) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
          Text('전체 ${list.length}회차 (실전 $live · 사후 재현 ${list.length - live}) · '
              '${list.first.targetRound}~${list.last.targetRound}회',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
          _note(_modeExplain),
        ]));
        children.add(FutureBuilder<(ResearchLoad<ReplayRoundDetail?>, Map<String, String>)>(
          key: ValueKey('detail_$_round'),
          future: _detail,
          builder: (context, ds) {
            if (ds.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            }
            if (ds.hasError || ds.data == null) {
              return replayStateNote(ResearchAvailability.error, message: '${ds.error}');
            }
            final (load, names) = ds.data!;
            final d = load.data;
            if (d == null) return replayStateNote(load.state, message: load.message);
            return Column(children: _detailCards(d, names));
          },
        ));
        return ListView(padding: const EdgeInsets.all(12), children: children);
      },
    );
  }

  Widget _runCard(ResearchLoad<ReplayRun?> run) {
    final r = run.data;
    return _card('재현 실행 ${widget.runId}', [
      if (r == null)
        replayStateNote(run.state, message: run.message)
      else ...[
        if (r.hasDefect || r.integrityLine != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(spacing: 4, runSpacing: 3, children: [
              if (replayRunDefectBadge(r) != null) regionTag(replayRunDefectBadge(r)!, Colors.red),
            ]),
          ),
        if (r.defect != null) _kv('데이터 결함', r.defect!, color: Colors.red.shade700),
        if (r.statusNote != null) _kv('상태 메모', r.statusNote!),
        if (r.supersededBy != null) _kv('대체 실행', r.supersededBy!),
        if (r.integrityLine != null) _kv('무결성 검증', r.integrityLine!.replaceFirst('무결성 검증: ', ''),
            color: Colors.green.shade800),
        _kv('모델 · 모드', '${r.modelVersion ?? '-'} · ${r.replayMode ?? '-'}'),
        _kv('상태', r.status.isEmpty ? '-' : r.status,
            color: r.status == 'failed' ? Colors.red.shade700 : (r.status == 'completed' ? Colors.green.shade800 : null)),
        _kv('회차', '시작 ${r.startRound ?? '-'}회 · 검증·갱신 완료 ${r.lastCompletedRound ?? '-'}회 · 마지막 동결 예측 ${r.lastPredictionRound ?? '-'}회'),
        if (r.updatedAt != null) _kv('갱신', r.updatedAt!.replaceFirst('T', ' ').split('.').first),
        if (r.error != null) _kv('오류', r.error!, color: Colors.red.shade700),
      ],
    ]);
  }

  List<Widget> _detailCards(ReplayRoundDetail d, Map<String, String> names) {
    final p = d.prediction;
    final out = <Widget>[];
    // ── 1) 사전 예측 (동결): 추첨 전 결과를 모르는 상태의 예측·사전 브리핑 ──
    out.add(replaySectionHeader('사전 예측 (동결)', '${p.targetRound}회 · ${p.availableThrough ?? '-'}회까지 데이터로 만든 예측 — 결과를 모르는 상태',
        Icons.lock_clock, Colors.indigo));
    out.add(_card('${p.targetRound}회 예측 (동결)', [
      Wrap(spacing: 4, runSpacing: 3, children: [
        replayModeBadge(p.replayMode),
        regionTag('${p.availableThrough ?? '-'}회까지 데이터', Colors.blueGrey),
        regionTag('가설 ${p.activeHypotheses ?? '-'}건 보유', Colors.indigo),
        regionTag('실전 반영 가설 ${p.liveHypothesesApplied.length}건',
            p.liveHypothesesApplied.isEmpty ? Colors.brown : Colors.green),
        regionTag('탐색 발화 ${p.exploreFired ?? '-'}건', Colors.blueGrey),
      ]),
      const SizedBox(height: 4),
      Text(replayModeLong(p.replayMode),
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: p.isLive ? Colors.green.shade800 : Colors.deepOrange.shade800)),
      if (p.createdAt != null)
        Text('예측 동결 시각 ${p.createdAt!.replaceFirst('T', ' ').split('.').first}',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
    ]));
    out.add(_card('중앙 엔진 주목 지역 (동결)', [
      if (p.focusRegions.isEmpty) const Text(kResearchNoData, style: TextStyle(fontSize: 12)),
      for (final f in p.focusRegions) agentFocusRegionRow(context, f),
      const Text('p = 지역 단위 회차당 1등 발생 추정, 기준 = 판매점 수 비례(m0), × = p/기준. 판매량 미보정.',
          style: TextStyle(fontSize: 10, color: Colors.black45)),
    ]));
    out.add(_card('전국 통합 추천 상위 (동결)', [
      if (p.storeTop.isEmpty) const Text(kResearchNoData, style: TextStyle(fontSize: 12)),
      for (var i = 0; i < p.storeTop.length; i++) agentCentralStoreRow(context, p.storeTop[i], i + 1),
      const Text('점수 = $kAgentScoreLabel. 한 장당 당첨확률이 아닙니다.', style: TextStyle(fontSize: 10, color: Colors.black45)),
    ]));

    out.add(_card('사전 브리핑', [
      if (d.pre == null)
        const Text('사전 브리핑 없음', style: TextStyle(fontSize: 12))
      else
        ReplayBriefingView(briefing: d.pre!, fallbackMode: p.replayMode),
    ]));

    // ── 2) 실제 결과: 추첨 결과 (예측과 분리) ──
    final r = d.result;
    out.add(replaySectionHeader('실제 결과', r == null ? '추첨 결과 반영 전' : '${p.targetRound}회 추첨 결과 (research_replay_results)',
        Icons.emoji_events_outlined, Colors.brown));
    final focusIds = p.focusRegions.map((f) => f.regionId).toSet();
    final topIds = p.storeTop.map((s) => s.storeCode).toSet();
    out.add(_card('추첨 결과 상세', [
      if (r == null)
        const Text('추첨 결과 반영 전 — 사후 검증 없음', style: TextStyle(fontSize: 12))
      else ...[
        _kv('1등 지역', r.firstRegions.isEmpty
            ? '-'
            : r.firstRegions.map((x) => '${agentLabel(x)}${focusIds.contains(x) ? '(주목)' : ''}').join(', ')),
        _kv('1등 판매점', r.firstStoreIds.isEmpty
            ? '-'
            : r.firstStoreIds.map((x) => '${names[x] ?? x}${topIds.contains(x) ? '(추천 상위)' : ''}').join(', ')),
        _kv('1·2등 판매점 (매칭)', '${r.eventStoreCount ?? '-'}곳'),
        _kv('판매점 목록 미매칭', '1등 ${r.unmatchedFirst ?? '-'}건 · 2등 ${r.unmatchedSecond ?? '-'}건',
            color: (r.unmatchedFirst ?? 0) + (r.unmatchedSecond ?? 0) > 0 ? Colors.brown.shade700 : null),
        if (r.verifiedAt != null) _kv('결과 확인 시각', r.verifiedAt!.replaceFirst('T', ' ').split('.').first),
      ],
    ]));

    // ── 3) 사후 검증: 동결 예측을 실제 결과로 채점 ──
    final ce = d.centralEval;
    out.add(replaySectionHeader('사후 검증', d.verified ? '동결 예측을 실제 결과로 채점한 기록' : '검증 전 — 추첨 결과 반영 후 채점',
        Icons.fact_check_outlined, Colors.teal));
    out.add(_card('중앙 엔진 사후 검증 vs 기준', [
      if (ce == null)
        const Text('중앙 검증 기록 없음 (검증 전)', style: TextStyle(fontSize: 12))
      else ...[
        _kv('지역 log-loss', '모델 ${_n(ce.loglossModel, 4)} · m0(판매점 수 비례) ${_n(ce.loglossM0, 4)}'
            ' · m1(지역 빈도) ${_n(ce.loglossM1, 4)} — 낮을수록 좋음',
            color: ce.loglossModel != null && ce.loglossM0 != null
                ? (ce.loglossModel! < ce.loglossM0! ? Colors.green.shade800 : Colors.brown.shade700)
                : null),
        _kv('주목 지역 1등 적중', '모델 ${_n(ce.focusHits)} · m0 ${_n(ce.focusHitsM0)} · 기대 ${_n(ce.focusExpected)}'
            ' · 1등 발생 지역 ${_n(ce.regionsWithFirst)}곳'),
        _kv('통합 추천 판매점', '1·2등 ${_n(ce.storeHitsAny)} (1등 ${_n(ce.storeHitsFirst)}) · 이력 기준 ${_n(ce.storeHitsHistory)}'
            ' · 무작위 기대 ${_n(ce.storeExpectedUniform)}'),
        _kv('실제 1·2등 판매점', _n(ce.events)),
      ],
    ]));

    out.add(_card('사후 검증 브리핑', [
      if (d.post == null)
        const Text('사후 브리핑 없음 (검증 전)', style: TextStyle(fontSize: 12))
      else
        ReplayBriefingView(briefing: d.post!, fallbackMode: p.replayMode),
    ]));
    return out;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 탭 2: 지방장 이력
// ═══════════════════════════════════════════════════════════════════════

class _AgentListTab extends StatefulWidget {
  final String runId;
  const _AgentListTab({super.key, required this.runId});
  @override
  State<_AgentListTab> createState() => _AgentListTabState();
}

class _AgentListTabState extends State<_AgentListTab> {
  late final _repo = AgentReplayRepository(runId: widget.runId);
  late Future<(ResearchLoad<List<AgentInfo>>, bool)> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// 이 실행 모델의 지방장 (성능 포함). 없으면 ag-1.0 목록을 이름 용도로만 사용 (성능 숨김).
  Future<(ResearchLoad<List<AgentInfo>>, bool)> _load() async {
    final a = await _repo.loadAgents();
    if (a.data.isNotEmpty) return (a, true);
    final legacy = await AgentResearchRepository().loadAgents(model: kAgentModelLegacy);
    if (legacy.data.isNotEmpty) return (legacy, false);
    return (a, true);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(ResearchLoad<List<AgentInfo>>, bool)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final load = snap.data?.$1;
        final hasPerf = snap.data?.$2 ?? false;
        if (load == null || load.data.isEmpty) {
          return ListView(padding: const EdgeInsets.all(14), children: [
            agentStateNote(load?.state ?? ResearchAvailability.error, message: load?.message ?? '${snap.error}'),
          ]);
        }
        final list = load.data.where((a) => a.matches(_query)).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: '지방장 검색 (예: 노원, 수원, 제주, internet)', isDense: true),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _note(hasPerf
                ? '이름순 정렬입니다. 적중 건수는 판매점 수·표본에 좌우되므로 순위로 쓰지 않습니다. '
                    'lift(무작위 기대 대비 배수)와 skill(log-loss 기술 점수)을 표본 경고와 함께 보세요.'
                : '${_repo.model} 지방장 성능 기록(research_agents) 없음 — ag-1.0 목록으로 이름만 표시합니다. 이력은 재현 테이블에서 조회합니다.'),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final a = list[i];
                final p = ReplayPerformance(a.performance);
                final perfOk = hasPerf && ReplayPerformance.isReplayShape(a.performance);
                final warn = perfOk ? p.sampleWarning : null;
                final t1 = perfOk ? p.topAt(1) : null;
                final t5 = perfOk ? p.topAt(5) : null;
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AgentReplayHistoryScreen(
                                agentId: a.agentId, initial: hasPerf ? a : null, runId: widget.runId))),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                              child: Text(a.display, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800))),
                          if (warn != null) regionTag('표본 경고', Colors.orange),
                        ]),
                        const SizedBox(height: 3),
                        Text(
                            perfOk
                                ? '평가 ${_n(p.rounds)}회차 · lift ${p.liftVsUniform == null ? '-' : '×${_n(p.liftVsUniform)}'}'
                                    ' · skill ${_n(p.llSkill, 3)} · 적중 ${_n(p.hitsAny)} / 기대 ${_n(p.expectedUniform)}'
                                : '판매점 ${a.storeCount}곳 · 성능 기록 없음',
                            style: const TextStyle(fontSize: 11)),
                        if (t1 != null || t5 != null)
                          Text(
                              '1위 ${t1 == null ? '-' : '${_n(t1.hits)}/${_n(t1.expectedUniform)}${t1.lift == null ? '' : ' ×${_n(t1.lift)}'}'}'
                              ' · 5위 안 ${t5 == null ? '-' : '${_n(t5.hits)}/${_n(t5.expectedUniform)}${t5.lift == null ? '' : ' ×${_n(t5.lift)}'}'}'
                              ' (적중/무작위 기대)',
                              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
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

class AgentReplayHistoryScreen extends StatefulWidget {
  final String agentId;
  final AgentInfo? initial;

  /// null = 현재(기본) 재현 실행
  final String? runId;
  const AgentReplayHistoryScreen({super.key, required this.agentId, this.initial, this.runId});

  @override
  State<AgentReplayHistoryScreen> createState() => _AgentReplayHistoryScreenState();
}

class _AgentReplayHistoryScreenState extends State<AgentReplayHistoryScreen> {
  static const int _pageSize = 20;
  late final _repo = AgentReplayRepository(runId: widget.runId);
  ResearchLoad<AgentInfo?>? _agent;
  final List<ReplayAgentRound> _rows = [];
  final Map<String, String> _names = {};
  ResearchLoad<List<ReplayAgentRound>>? _lastPage;
  int _page = 0;
  bool _loading = true;
  bool _more = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final a = widget.initial != null
        ? ResearchLoad<AgentInfo?>(ResearchAvailability.available, widget.initial)
        : await AgentResearchRepository().loadAgent(widget.agentId, model: _repo.model);
    if (!mounted) return;
    setState(() => _agent = a);
    await _loadMore();
  }

  Future<void> _loadMore() async {
    setState(() => _loading = true);
    final page = await _repo.loadAgentHistory(widget.agentId, page: _page, pageSize: _pageSize);
    final names = await _repo.storeNames(page.data.expand((r) => r.storeIds));
    if (!mounted) return;
    setState(() {
      _lastPage = page;
      _rows.addAll(page.data);
      _names.addAll(names);
      _more = page.data.length >= _pageSize;
      _page++;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F7),
      appBar: AppBar(
        backgroundColor: _c,
        foregroundColor: Colors.white,
        title: Text('재현 이력 · ${agentLabel(widget.agentId)} · ${_repo.runId}',
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
      body: ListView(padding: const EdgeInsets.all(12), children: [
        _perfCard(),
        _historyCard(),
      ]),
    );
  }

  Widget _perfCard() {
    final a = _agent;
    if (a == null) return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
    final info = a.data;
    if (info == null || info.performance.isEmpty || !ReplayPerformance.isReplayShape(info.performance)) {
      return _card('누적 성능 (research_agents ${_repo.model})', [
        info == null
            ? agentStateNote(a.state, message: a.message)
            : Text('${_repo.model} 성능 기록 없음 ($kResearchNoData)', style: const TextStyle(fontSize: 11.5)),
      ]);
    }
    final p = ReplayPerformance(info.performance);
    final warn = p.sampleWarning;
    final rec = p.recent;
    TableRow row(List<String> cells, {bool head = false}) => TableRow(children: [
          for (final c in cells)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
              child: Text(c,
                  style: TextStyle(fontSize: 10.5, fontWeight: head ? FontWeight.w800 : FontWeight.w500)),
            ),
        ]);
    return _card('누적 성능 (research_agents ${_repo.model})', [
      if (warn != null) _note(warn, color: Colors.orange.shade50),
      AgentPerformanceView(performance: info.performance),
      if (rec.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('최근 구간', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.1)},
          children: [
            row(['구간', '회차', '적중', '무작위 기대', 'lift', '이력 기준', 'skill'], head: true),
            for (final e in rec.entries)
              row([
                '최근 ${e.key}',
                _n(e.value.rounds),
                _n(e.value.hitsAny),
                _n(e.value.expectedUniform),
                e.value.lift == null ? '-' : '×${_n(e.value.lift)}',
                _n(e.value.historyHits),
                _n(e.value.llSkill, 3),
              ]),
          ],
        ),
      ],
    ]);
  }

  Widget _historyCard() {
    final children = <Widget>[
      _note(_modeExplain),
    ];
    if (_rows.isEmpty && !_loading) {
      final s = _lastPage;
      children.add(replayStateNote(s?.state ?? ResearchAvailability.noData, message: s?.message));
    }
    for (final r in _rows) {
      children.add(_roundTile(r));
    }
    if (_loading) {
      children.add(const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())));
    } else if (_more && _rows.isNotEmpty) {
      children.add(Center(
        child: TextButton(onPressed: _loadMore, child: Text('더 보기 (${_rows.length}회차 표시 중)')),
      ));
    }
    return _card('회차별 동결 납품 · 사후 검증 (최신순)', children);
  }

  Widget _roundTile(ReplayAgentRound r) {
    final e = r.eval;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${r.targetRound}회', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _c)),
          const SizedBox(width: 6),
          replayModeBadge(r.replayMode),
          const SizedBox(width: 4),
          Expanded(
              child: Text('${r.availableThrough ?? '-'}회까지 데이터',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700))),
          if (e != null)
            regionTag('적중 ${e.hitsAny ?? '-'} / 기대 ${_n(e.expectedUniform)}',
                (e.hitsAny ?? 0) > 0 ? Colors.green : Colors.grey)
          else
            regionTag('검증 전', Colors.grey),
        ]),
        const SizedBox(height: 4),
        for (var i = 0; i < r.storeIds.length; i++)
          InkWell(
            onTap: () => showAgentStoreSheet(context, r.storeIds[i], name: _names[r.storeIds[i]]),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(children: [
                SizedBox(
                    width: 20,
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _c))),
                Expanded(
                    child: Text('${_names[r.storeIds[i]] ?? r.storeIds[i]} · 점수 ${fmtScore(r.scoreAt(i))}',
                        style: const TextStyle(fontSize: 11))),
                if (e != null && e.hitAtRank(i + 1) != null && e.hitAtRank(i + 1)! > 0)
                  regionTag('적중', Colors.green),
              ]),
            ),
          ),
        if (e != null)
          Text(
              '1등 ${e.hitsFirst ?? '-'} · 이력 기준 ${e.historyHits ?? '-'} · 탐색 ${e.exploreHits ?? '-'}'
              ' · 지역 실제 1·2등 ${e.regionEvents ?? '-'}곳 (1등 ${e.regionFirst ?? '-'})'
              ' · 판매점 ${e.nStores ?? r.nStores ?? '-'}곳',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 탭 3: 가설 실전 성능
// ═══════════════════════════════════════════════════════════════════════

class _HypothesisTab extends StatefulWidget {
  final String runId;
  const _HypothesisTab({super.key, required this.runId});
  @override
  State<_HypothesisTab> createState() => _HypothesisTabState();
}

class _HypothesisTabState extends State<_HypothesisTab> {
  late final _repo = AgentReplayRepository(runId: widget.runId);
  String? _status;

  /// 판정 필터 (화면에서 거름, null = 전체)
  String? _verdict;
  String? _kind;
  bool _sharedOnly = false;
  bool _appliedOnly = false;
  late Future<ResearchLoad<List<AgentHypothesis>>> _future;
  late Future<ResearchLoad<int>> _passedStore;

  @override
  void initState() {
    super.initState();
    _passedStore = _repo.countPassedStoreLevel();
    _reload();
  }

  bool get _filtered => _status != null || _kind != null || _sharedOnly || _appliedOnly || _verdict != null;

  int get _limit => _verdict == null ? 300 : 600;

  void _reload() {
    _future = _repo.loadHypotheses(
        status: _status, kind: _kind, sharedOnly: _sharedOnly, appliedLiveOnly: _appliedOnly, limit: _limit);
  }

  Widget _chips(List<(String?, String)> items, String? selected, ValueChanged<String?> onSel) => SizedBox(
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
      _chips([
        (null, '전체 상태'),
        for (final s in kAgentHypStatusOrder) (s, kAgentHypStatusLabel[s]!),
      ], _status, (v) => setState(() {
            _status = v;
            _reload();
          })),
      _chips([
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
            onSelected: (v) => setState(() {
              _sharedOnly = v;
              _reload();
            }),
          ),
          const SizedBox(width: 6),
          FilterChip(
            label: const Text('실전 반영된 가설만', style: TextStyle(fontSize: 11)),
            selected: _appliedOnly,
            visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() {
              _appliedOnly = v;
              _reload();
            }),
          ),
        ]),
      ),
      Expanded(
        child: FutureBuilder<ResearchLoad<List<AgentHypothesis>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final load = snap.data;
            final all = load?.data ?? const <AgentHypothesis>[];
            final list = all.where((h) => verdictMatches(h, _verdict)).toList();
            final vc = AgentVerdictCounts.of(all).all;
            return ListView(padding: const EdgeInsets.fromLTRB(12, 6, 12, 24), children: [
              _banner(),
              if (all.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Wrap(spacing: 4, runSpacing: 3, children: [
                    for (final v in kVerdictOrder)
                      if (vc[v] != null) regionTag('$v ${vc[v]}', agentVerdictColor(v)),
                  ]),
                ),
              _note('가설은 발견 시점 이하 데이터로만 찾고(first_discovered_round), 이후 회차로만 검증합니다. '
                  '실전 반영 = 검증 통과 후 실제 추천 점수에 쓰인 회차, 탐색 반영 = 연구용 탐색 목록에만 쓰인 회차. '
                  'k_off/e_off = 가설이 꺼져 있던(미발화) 회차의 실제/기대 건수, 상대비 = 발화 시 비율 ÷ 미발화 시 비율. '
                  '판정 = evidence.verdict (없으면 status 로 대체: passed/combined → 검증 통과, weakened/rejected → 검증 실패, 그 외 → 검증 중).'),
              if (list.isEmpty)
                (load?.state == ResearchAvailability.noData || all.isNotEmpty) && _filtered
                    ? const Text('조건에 맞는 가설 없음', style: TextStyle(fontSize: 12))
                    : replayStateNote(load?.state ?? ResearchAvailability.error, message: load?.message ?? '${snap.error}')
              else ...[
                Text('${list.length}건${_verdict == null ? '' : ' (불러온 ${all.length}건 중 판정 필터)'} (최근 갱신 순 최대 $_limit건, 상태순 정렬) · 탭하면 상태 변화 이력',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                for (final h in list) _tile(h),
              ],
            ]);
          },
        ),
      ),
    ]);
  }

  Widget _banner() => FutureBuilder<ResearchLoad<int>>(
        future: _passedStore,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
          final l = snap.data;
          if (l == null || l.state != ResearchAvailability.available) return const SizedBox.shrink();
          final none = l.data == 0;
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: none ? Colors.orange.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: (none ? Colors.orange : Colors.green).withValues(alpha: 0.4)),
            ),
            child: Text(
              none
                  ? '판매점 단위 검증 통과 가설 없음 — 판매점 추천은 이력 기반 후보이며 가설 근거가 검증되지 않았습니다.'
                  : '판매점 단위 검증 통과 가설 ${l.data >= 50 ? '50건 이상' : '${l.data}건'} (passed/combined)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: none ? Colors.orange.shade900 : Colors.green.shade900),
            ),
          );
        },
      );

  Widget _tile(AgentHypothesis h) => InkWell(
        onTap: () => _openEvents(h),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(h.summary, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
              const SizedBox(width: 6),
              agentVerdictTag(h),
            ]),
            const SizedBox(height: 3),
            Wrap(spacing: 4, runSpacing: 3, children: [
              regionTag('상태 ${h.statusLabel}', hypothesisStatusColor(h.status)),
              regionTag(h.kindLabel, Colors.blueGrey),
              if (h.agentId.isNotEmpty) regionTag('발견 ${agentLabel(h.agentId)}', Colors.indigo),
              if (h.isShared) regionTag('공유받음 ← ${agentLabel(h.sharedByAgent)}', Colors.deepPurple),
              if (h.sharedToCount > 0) regionTag('공유 ${h.sharedToCount}곳', Colors.deepPurple),
              if (h.appliedLive) regionTag('실전 반영', Colors.green),
            ]),
            const SizedBox(height: 3),
            Text(
                '발견 ${h.discoveredRound ?? '-'}회 · 첫 실전 반영 ${h.firstAppliedLiveRound ?? '-'}회 · 첫 탐색 반영 ${h.firstAppliedExploreRound ?? '-'}회'
                ' · 실전 ${h.appliedLiveCount}회 · 탐색 ${h.appliedExploreCount}회',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800)),
            Text(
                '검증 k ${h.testK ?? '-'} / 기대 ${h.testExpected == null ? '-' : h.testExpected!.toStringAsFixed(2)}'
                ' · 미발화 k_off ${h.kOff ?? '-'} / e_off ${h.eOff == null ? '-' : h.eOff!.toStringAsFixed(2)}'
                ' · 상대비 ${h.relativeRatio == null ? '-' : '×${h.relativeRatio!.toStringAsFixed(2)}'}'
                ' · p=${fmtP(h.testP)} · q=${fmtP(h.testQ)}',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800)),
            for (final l in agentVerdictDetailLines(h))
              Text(l, style: TextStyle(fontSize: 10.5, color: agentVerdictColor(h.verdict).shade800)),
            if (h.isShared) Text('원 가설 ${h.sharedFrom}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ]),
        ),
      );

  void _openEvents(AgentHypothesis h) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => FutureBuilder<ResearchLoad<List<ReplayHypothesisEvent>>>(
          future: _repo.loadHypothesisEvents(h.hypothesisId),
          builder: (ctx, snap) {
            final children = <Widget>[
              Text(h.summary, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              Text('${h.hypothesisId} · ${h.kindLabel} · 현재 ${h.statusLabel} · 판정 ${h.verdict}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45)),
              const SizedBox(height: 8),
            ];
            if (snap.connectionState != ConnectionState.done) {
              children.add(const LinearProgressIndicator());
            } else {
              final l = snap.data;
              final ev = l?.data ?? const <ReplayHypothesisEvent>[];
              if (ev.isEmpty) {
                children.add(replayStateNote(l?.state ?? ResearchAvailability.error, message: l?.message ?? '${snap.error}'));
              }
              for (final e in ev) {
                children.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                      width: 56,
                      child: Text('${e.round}회', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _c))),
                  Column(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: hypothesisStatusColor(e.statusTo), shape: BoxShape.circle)),
                    Container(width: 2, height: 34, color: Colors.black12),
                  ]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                          '${e.statusFrom == null ? '시작' : kAgentHypStatusLabel[e.statusFrom] ?? e.statusFrom} → '
                          '${kAgentHypStatusLabel[e.statusTo] ?? e.statusTo}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      Text(
                          '검증 ${e.testK ?? '-'}건/${e.testN ?? '-'}회 · 기대 ${e.testExpected == null ? '-' : e.testExpected!.toStringAsFixed(2)}'
                          ' · p=${fmtP(e.testP)} · 상대비 ${e.relativeRatio == null ? '-' : '×${e.relativeRatio!.toStringAsFixed(2)}'}',
                          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                    ]),
                  ),
                ]));
              }
            }
            children.add(const SizedBox(height: 8));
            children.add(const Text('각 행 = 그 회차 결과까지 반영한 시점의 상태 변화 (research_replay_hypothesis_events).',
                style: TextStyle(fontSize: 10, color: Colors.black45)));
            return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: children);
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 탭 4: 누적 성능
// ═══════════════════════════════════════════════════════════════════════

class _CumulativeTab extends StatefulWidget {
  final String runId;
  const _CumulativeTab({super.key, required this.runId});
  @override
  State<_CumulativeTab> createState() => _CumulativeTabState();
}

class _CumulativeTabState extends State<_CumulativeTab> {
  late final _repo = AgentReplayRepository(runId: widget.runId);
  late Future<ResearchLoad<ReplayCumulative>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.loadCumulative();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ResearchLoad<ReplayCumulative>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final load = snap.data;
        final c = load?.data;
        if (c == null || c.points.isEmpty) {
          return ListView(padding: const EdgeInsets.all(14), children: [
            replayStateNote(load?.state ?? ResearchAvailability.error, message: load?.message ?? '${snap.error}'),
          ]);
        }
        final xs = c.points.map((p) => p.targetRound).toList();
        final last = c.last!;
        final hitsLabel = switch (c.hitsSource) {
          'agents' => '지방장 납품 합계 (사후 브리핑 agents)',
          'central_store' => '중앙 통합 추천 판매점 (central_evals store_*)',
          _ => '적중 자료 없음',
        };
        TableRow row(String k, String v, {Color? color}) => TableRow(children: [
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(k, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color))),
            ]);
        final skill = c.llSkill;
        return ListView(padding: const EdgeInsets.all(12), children: [
          _card('중앙 엔진 지역 log-loss (누적 평균, 낮을수록 좋음)', [
            ReplayLineChart(
              xs: xs,
              yDecimals: 3,
              series: [
                ReplayChartSeries('모델', Colors.teal, c.points.map((p) => p.meanLlModel).toList()),
                ReplayChartSeries('m0 (판매점 수 비례)', Colors.grey, c.points.map((p) => p.meanLlM0).toList()),
              ],
            ),
            Text('평가 ${last.llRounds}회차 기준', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
          ]),
          _card('누적 적중 — $hitsLabel', [
            ReplayLineChart(
              xs: xs,
              yDecimals: 0,
              series: [
                ReplayChartSeries('실전 목록 1·2등 적중', Colors.indigo, c.points.map((p) => p.cumHits.toDouble()).toList()),
                ReplayChartSeries('이력 기준 목록', Colors.orange, c.points.map((p) => p.cumHistoryHits.toDouble()).toList()),
                ReplayChartSeries('무작위 기대', Colors.grey, c.points.map((p) => p.cumExpectedUniform).toList()),
              ],
            ),
            Text('적중 집계 ${last.hitRounds}회차', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
          ]),
          _card('요약', [
            Table(columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(2)}, children: [
              row('회차', '${c.rounds}회 (${xs.first}~${xs.last}회) · 실전 ${c.liveRounds} · 사후 재현 ${c.replayRounds}'),
              row('log-loss 평균', '모델 ${_n(last.meanLlModel, 4)} · m0 ${_n(last.meanLlM0, 4)}'),
              row('log-loss 기술 점수', skill == null ? '-' : '${skill.toStringAsFixed(4)} (1 − 모델/m0, 0 초과면 m0 보다 나음)',
                  color: skill == null ? null : (skill > 0 ? Colors.green.shade800 : Colors.brown.shade700)),
              row('주목 지역 1등 적중', '모델 ${c.focusHits} · m0 ${c.focusHitsM0} · 기대 ${c.focusExpected.toStringAsFixed(2)}'
                  ' (${c.focusRounds}회차)'),
              row('누적 적중', '${last.cumHits} · 이력 기준 ${last.cumHistoryHits} · 무작위 기대 ${last.cumExpectedUniform.toStringAsFixed(2)}'),
              row('무작위 대비', _ratio(last.cumHits, last.cumExpectedUniform)),
              row('이력 기준 대비', _ratio(last.cumHits, last.cumHistoryHits)),
            ]),
            _note('대부분의 회차는 사후 재현(해당 회차 이전 데이터만 사용, 추첨 이후 계산)이며 실전(추첨 전 동결) 회차는 '
                '${c.liveRounds}회입니다. 과거 당첨 빈도는 판매량 영향이며 한 장당 당첨확률이 아닙니다. '
                '무작위 기대보다 높아도 판매량이 많은 판매점을 고른 효과일 수 있으므로 이력 기준과 함께 보세요.',
                color: Colors.orange.shade50),
          ]),
        ]);
      },
    );
  }
}
