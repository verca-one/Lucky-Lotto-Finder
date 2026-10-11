// 관리자 — 예측 연구 현황 (추첨예측 / 구매예측 / 판매점 분석 / 예측력 검증)
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/research/draw_research_engine.dart';
import '../services/research/hypothesis_replay_engine.dart';
import '../services/research/prediction_registry.dart';
import '../services/research/research_scheduler.dart';
import '../services/rpa_store_engine.dart' show StoreWinRecord;
import '../widgets/purchase_recommend_card.dart';
import 'purchase_prediction_screen.dart';

class AdminResearchScreen extends StatefulWidget {
  const AdminResearchScreen({super.key});
  @override
  State<AdminResearchScreen> createState() => _AdminResearchScreenState();
}

class _AdminResearchScreenState extends State<AdminResearchScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  ResearchData? _data;
  NumberFrequencyResult? _freq;
  List<EngineWfControl> _wf = [];
  RegionWfControl? _region;
  List<AlgorithmSummary> _summary = [];
  List<Map<String, dynamic>> _recent = [];
  Map<String, dynamic>? _store;
  Map<String, dynamic>? _replay;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await ResearchScheduler.instance.load();
      if (d == null) throw Exception('당첨번호 데이터 없음');
      final dr = DrawResearchEngine.instance;
      final freq = dr.analyzeNumberFrequency(d.allData);
      final wf = await dr.evaluateEngineNumberWf(d.allData);
      final region = dr.evaluateRegionWfControl(d.history, d.allData);
      final summary = await PredictionRegistry.instance.summarize();
      final recent = await PredictionRegistry.instance.recent();
      final store = await _storeAnalysis(d.history);
      final replay = await HypothesisReplayEngine.instance.loadLatest() ?? await HypothesisReplayEngine.instance.runAndPersist(d.allData);
      if (!mounted) return;
      setState(() {
        _data = d; _freq = freq; _wf = wf; _region = region; _summary = summary; _recent = recent; _store = store;
        _replay = replay;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _runNow() async {
    setState(() => _busy = true);
    try {
      await ResearchScheduler.instance.runIfNeeded(force: true);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 판매점 분석 (판매량 미보정) ─────────────────────────────
  Future<Map<String, dynamic>> _storeAnalysis(List<StoreWinRecord> history) async {
    final rounds = history.map((h) => h.round).toSet();
    final byStore = <String, int>{};
    final bySido = <String, int>{};
    final byMethod = <String, int>{};
    for (final h in history) {
      byStore[h.code] = (byStore[h.code] ?? 0) + 1;
      final s = h.region.trim().split(' ').first;
      if (s.isNotEmpty) bySido[s] = (bySido[s] ?? 0) + 1;
      final m = (h.purchaseMethod ?? '').trim();
      byMethod[m.isEmpty ? '미기재' : m] = (byMethod[m.isEmpty ? '미기재' : m] ?? 0) + 1;
    }
    final topStores = byStore.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topSido = bySido.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    // 인터넷 판매 식별 (판매점명 기준, 읽기 전용)
    int internetWins = 0; List<String> internetNames = [];
    try {
      final rows = await Supabase.instance.client
          .from('lottery_stores').select('dhlottery_code,store_name')
          .eq('lottery_type', 'lotto')
          .or('store_name.ilike.%인터넷%,store_name.ilike.%동행복권%')
          .limit(20);
      final codes = <String>{};
      for (final r in List<Map<String, dynamic>>.from(rows as List)) {
        codes.add('${r['dhlottery_code']}'); internetNames.add('${r['store_name']}');
      }
      internetWins = history.where((h) => codes.contains(h.code)).length;
    } catch (_) {}
    // 상위 판매점명
    final names = <String, String>{};
    try {
      final rows = await Supabase.instance.client.from('lottery_stores').select('dhlottery_code,store_name,region')
          .inFilter('dhlottery_code', topStores.take(10).map((e) => e.key).toList());
      for (final r in List<Map<String, dynamic>>.from(rows as List)) {
        names['${r['dhlottery_code']}'] = '${r['store_name']} (${r['region']})';
      }
    } catch (_) {}
    return {
      'rounds': rounds.length, 'min': rounds.isEmpty ? 0 : rounds.reduce((a, b) => a < b ? a : b),
      'max': rounds.isEmpty ? 0 : rounds.reduce((a, b) => a > b ? a : b), 'winners': history.length,
      'stores': byStore.length, 'top_stores': topStores.take(10).map((e) => {'code': e.key, 'name': names[e.key] ?? e.key, 'count': e.value}).toList(),
      'top_sido': topSido.take(10).map((e) => {'sido': e.key, 'count': e.value}).toList(),
      'by_method': byMethod, 'internet_wins': internetWins, 'internet_names': internetNames,
      'expected_wins_per_store_if_equal': history.isEmpty || byStore.isEmpty ? 0.0 : history.length / byStore.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo, foregroundColor: Colors.white,
        title: const Text('예측 연구 현황', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: '지금 등록·채점·연구 갱신',
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_circle_outline, color: Colors.white),
            onPressed: _busy ? null : _runNow,
          ),
        ],
        bottom: TabBar(
          controller: _tab, isScrollable: true, labelColor: Colors.white, unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amber,
          tabs: const [Tab(text: '추첨예측'), Tab(text: '구매예측'), Tab(text: '판매점 분석'), Tab(text: '예측력 검증')],
        ),
      ),
      body: _loading
          ? ValueListenableBuilder<ResearchStatus>(
              valueListenable: ResearchScheduler.instance.status,
              builder: (context, s, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('${s.label} · ${s.message}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ])))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('오류: $_error')))
              : TabBarView(controller: _tab, children: [
                  _drawTab(), const PurchasePredictionContent(), _storeTab(), _verifyTab(),
                ]),
    );
  }

  // ── 공통 위젯 ──────────────────────────────────────────────
  Widget _card(String title, Widget body, {Color? color}) => Container(
        width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: (color ?? Colors.indigo).withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color ?? Colors.indigo)),
          const SizedBox(height: 8), body,
        ]),
      );
  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
          Expanded(child: Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color, height: 1.3))),
        ]),
      );
  Widget _note(String s) => Container(
        margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
        child: Text(s, style: TextStyle(fontSize: 10, color: Colors.grey.shade700, height: 1.4)),
      );
  String _p(double v) => v.isNaN ? '-' : v < 0.0001 ? '<0.0001' : v.toStringAsFixed(4);

  // ── 탭 1: 추첨예측 ────────────────────────────────────────
  Widget _drawTab() {
    final f = _freq!;
    final sortedZ = List<NumberFreqRow>.of(f.main)..sort((a, b) => b.z.abs().compareTo(a.z.abs()));
    return ListView(padding: const EdgeInsets.all(14), children: [
      _card('A. 번호별 출현 빈도 (${f.rounds}회차, 본번호)', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _kv('기대 빈도/번호', '${f.main.first.expected.toStringAsFixed(1)}회'),
        _kv('χ² 적합도 (df=44)', '${f.chiSq.toStringAsFixed(1)} · p=${_p(f.chiP)}', color: f.chiP < 0.05 ? Colors.red.shade700 : Colors.teal.shade800),
        _kv('Holm 보정 후 유의 번호', '${f.significantAfterHolm}개 (α=0.05)'),
        _kv('보너스 χ² (df=44)', '${f.bonusChiSq.toStringAsFixed(1)} · p=${_p(f.bonusChiP)}'),
        _kv('전반/후반 편차 상관', '${f.halfCorrelation.toStringAsFixed(3)} (재현 편향이면 양의 상관)'),
        const SizedBox(height: 6),
        Text('편차 상위 번호 (|z| 기준)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
        ...sortedZ.take(8).map((r) => Row(children: [
              lottoBall(r.number, size: 26), const SizedBox(width: 8),
              Expanded(child: Text('관측 ${r.observed} / 기대 ${r.expected.toStringAsFixed(1)} · z=${r.z.toStringAsFixed(2)} · p=${_p(r.p)} · Holm p=${_p(r.pHolm)}',
                  style: const TextStyle(fontSize: 11))),
            ])),
        const SizedBox(height: 6),
        Text('시기별 χ²', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
        ...f.eras.map((e) => Text('${e['from']}~${e['to']}회 (${e['rounds']}회차): χ²=${(e['chi_sq'] as double).toStringAsFixed(1)}, p=${_p(e['chi_p'] as double)}',
            style: const TextStyle(fontSize: 11))),
        _note(f.conclusion),
      ])),
      if (_replay != null) _replayCard(_replay!),
      _card('B·C. 추첨 순서 · 추첨기·공 물리 편향', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...DrawResearchEngine.unavailable.entries.map((e) => _kv(e.key, '데이터 미확보 — ${e.value}', color: Colors.orange.shade900)),
      ]), color: Colors.orange.shade800),
      _card('D-1. 기존 Number Engine 번호 WF vs 무작위', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_wf.isEmpty) const Text('채점 가능한 스냅샷이 없습니다.', style: TextStyle(fontSize: 11)),
        ..._wf.where((w) => w.rounds == 0).map((w) => Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('엔진 v${w.modelVersion} · 사후 채점 불가', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.orange.shade900)),
                const SizedBox(height: 4),
                Text(w.note, style: TextStyle(fontSize: 11, color: Colors.grey.shade800, height: 1.4)),
              ]),
            )),
        ..._wf.where((w) => w.rounds > 0).map((w) => Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('엔진 v${w.modelVersion} · ${w.firstRound}~${w.lastRound}회 (${w.rounds}회차, ${w.sets}세트)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                _kv('세트당 평균 일치', '${w.meanMatches.toStringAsFixed(3)}개 vs 무작위 ${w.randomMean} (차이 ${(w.meanMatches - w.randomMean >= 0 ? '+' : '')}${(w.meanMatches - w.randomMean).toStringAsFixed(3)})',
                    color: w.meanMatches > w.randomMean ? Colors.teal.shade800 : Colors.red.shade700),
                _kv('t / p (회차 평균)', '${w.t.toStringAsFixed(2)} / ${_p(w.p)}'),
                _kv('3개+ 일치율', '${(w.atLeast3Rate * 100).toStringAsFixed(2)}% (CI ${(w.atLeast3Ci[0] * 100).toStringAsFixed(2)}~${(w.atLeast3Ci[1] * 100).toStringAsFixed(2)}%) vs 무작위 ${(w.randomAtLeast3 * 100).toStringAsFixed(2)}%'),
                _kv('달성 최고 등수', w.bestRank == 0 ? '없음' : '${w.bestRank}등 · 등수별 ${w.rankCounts}'),
              ]),
            )),
        _note('스냅샷 채점은 사후 재현(replay) WF이며 사전 등록 예측이 아니므로 참고용입니다. 무작위 기대: 세트당 0.80개, 3개+ 일치 2.38%. '
            '사전 등록·잠금된 예측의 결과는 [예측력 검증] 탭에서 누적됩니다.'),
      ])),
      if (_region != null)
        _card('D-2. 지역 WF(기존 Store/NR 지표) 기저율 대조군', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _kv('평가 회차', '${_region!.rounds}회차'),
          _kv('균등 무작위 3개 시/도', '${(_region!.uniformRandom3 * 100).toStringAsFixed(1)}%'),
          _kv('과거 전체 상위 3개 시/도', '${(_region!.baseRateTop3 * 100).toStringAsFixed(1)}% (확장 윈도우, 누수 없음)'),
          _kv('직전 30회 상위 3개', '${(_region!.baseRateTop3Recent30 * 100).toStringAsFixed(1)}% (기존 Store 지표 정의)'),
          _note('기존 WF의 Store 47.7%·Joint 53.4%는 서울·경기·부산 기저율과 비교해야 하며, NR 10.3%는 균등 무작위(17.6%)보다 낮습니다. '
              '판매점 수·판매량이 많은 지역이 더 자주 당첨되는 것은 당연한 결과이므로 "예측력"이 아닙니다.'),
        ])),
    ]);
  }

  // ── 가설 순차 재현 카드 ──────────────────────────────────
  Widget _replayCard(Map<String, dynamic> r) {
    final post = Map<String, dynamic>.from(r['post_accept'] as Map? ?? {});
    final eng = Map<String, dynamic>.from(r['engine_style'] as Map? ?? {});
    final hyps = List<Map<String, dynamic>>.from((r['hypotheses'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    final sc = Map<String, dynamic>.from(r['status_counts'] as Map? ?? {});
    String pct(dynamic v) => v == null ? '-' : '${((v as num) * 100).toStringAsFixed(1)}%';
    final postZ = post['z'] as num?;
    return _card('가설 순차 재현 ${r['start_round']}→${r['end_round']}회 (${r['rounds_replayed']}회차)', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kv('발견 가설', '${r['hypotheses_total']}개 · 상태 $sc'),
      _kv('채택 경험', '${r['ever_accepted']}개 · Holm p<0.05: ${r['significant_holm']}개'),
      _kv('채택 이후 적중률', '${pct(post['rate'])} (n=${post['n']}) vs 기준 ${pct(post['baseline'])} · z=${postZ == null ? '-' : postZ.toStringAsFixed(2)} p=${post['p'] == null ? '-' : _p((post['p'] as num).toDouble())}',
          color: postZ != null && postZ > 1.96 ? Colors.teal.shade800 : Colors.red.shade700),
      _kv('엔진 방식(매 회차)', '${pct(eng['rate'])} (n=${eng['n']}) vs 기준 ${pct(eng['baseline'])}'),
      if (r['holdout'] != null)
        _kv('홀드아웃 ${(r['holdout'] as Map)['from_round']}회~', '${pct((r['holdout'] as Map)['rate'])} (n=${(r['holdout'] as Map)['n']}) vs 기준 ${pct((r['holdout'] as Map)['baseline'])} · p=${(r['holdout'] as Map)['p'] == null ? '-' : _p(((r['holdout'] as Map)['p'] as num).toDouble())}'),
      _kv('회차별 로그', 'DB ${r['round_logs_count'] ?? '-'}건 (신규 저장 ${r['round_logs_persisted'] ?? 0} / 기존 ${r['round_logs_existing'] ?? 0})'),
      const SizedBox(height: 6),
      Text('가설별 (horizon 반영 검증 n 상위)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
      ...hyps.take(12).map((h) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              SizedBox(width: 96, child: Text('${h['label']}', style: const TextStyle(fontSize: 11))),
              Expanded(child: Text('${h['created_round']}회 발견 · ${h['status']} · ${h['success']}/${h['n']} (${pct(h['rate'])}, 기준 ${pct(h['baseline'])}) · 채택후 ${h['post_success']}/${h['post_n']}',
                  style: TextStyle(fontSize: 10.5, color: (h['p_holm'] as num) < 0.05 ? Colors.teal.shade800 : Colors.grey.shade700))),
            ]),
          )),
      _note('${r['note']}'),
    ]), color: Colors.deepPurple);
  }

  // ── 탭 3: 판매점 분석 ─────────────────────────────────────
  Widget _storeTab() {
    final s = _store!;
    return ListView(padding: const EdgeInsets.all(14), children: [
      _card('데이터 범위', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _kv('1등 당첨 기록', '${s['min']}~${s['max']}회 · ${s['rounds']}회차 · 당첨자 ${s['winners']}명 · 판매점 ${s['stores']}곳'),
        _kv('구매방식 분포', '${s['by_method']}'),
        _kv('판매점별 판매량', '미확보 → 판매량 효과와 판매점 고유 효과 분리 불가', color: Colors.orange.shade900),
        _kv('판매점 운영 기간', '미확보', color: Colors.orange.shade900),
        _kv('인터넷 구매', (s['internet_names'] as List).isEmpty ? '판매점명으로 식별된 인터넷 판매처 없음' : '식별 ${(s['internet_names'] as List).length}곳 · 1등 ${s['internet_wins']}건 (${(s['internet_names'] as List).join(', ')})'),
      ])),
      _card('지역별 1등 분포 (판매량 미보정)', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...(s['top_sido'] as List).map((e) => _kv('${e['sido']}', '${e['count']}건 (${((e['count'] as int) / (s['winners'] as int) * 100).toStringAsFixed(1)}%)')),
        _note('지역별 당첨 수는 그 지역의 판매점 수·판매량에 비례합니다. 판매량 자료 없이는 지역 효과를 주장할 수 없습니다.'),
      ])),
      _card('누적 당첨 상위 판매점 (판매량 미보정)', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...(s['top_stores'] as List).map((e) => _kv('${e['count']}회', '${e['name']}')),
        _kv('판매점당 평균', '${(s['expected_wins_per_store_if_equal'] as double).toStringAsFixed(2)}회 (1등 판매점 기준)'),
        _note('판매량이 많은 판매점일수록 당첨 횟수가 많은 것은 확률적으로 당연합니다. '
            '판매량 자료 없이 특정 판매점의 복권 한 장당 당첨 확률이 높다고 주장하지 않습니다.'),
      ])),
    ]);
  }

  // ── 탭 4: 예측력 검증 ─────────────────────────────────────
  Widget _verifyTab() {
    final d = _data!;
    final deadline = PredictionRegistry.deadlineFor(d.targetRound, d.latest).toLocal();
    return ListView(padding: const EdgeInsets.all(14), children: [
      _card('자동 처리 상태', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ValueListenableBuilder<ResearchStatus>(
          valueListenable: ResearchScheduler.instance.status,
          builder: (context, s, _) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              if (s.isRunning) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              if (s.isRunning) const SizedBox(width: 6),
              statusChip(s.label, s.isRunning ? Colors.orange.shade800 : Colors.teal.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text(s.message, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
            ]),
          ),
        ),
        _kv('최신 회차', '${d.latestRound}회 (${d.latest.drawDate})'),
        _kv('등록 대상', '${d.targetRound}회 · 마감 ${deadline.year}-${deadline.month.toString().padLeft(2, '0')}-${deadline.day.toString().padLeft(2, '0')} ${deadline.hour}:00'),
        _kv('알고리즘', 'number_engine(v2.1) · purchase_prediction($kPurchaseVersionLabel) · random_control(r1)'),
        _note('앱 실행 시 최신 회차당 1회 자동: 미채점 예측 채점 → 다음 회차 예측 등록(잠금) → 연구 갱신. '
            '마감 이후 생성된 예측은 사전 실적으로 인정하지 않습니다(invalid). 통계적 우위가 관측되어도 운영 엔진에 자동 반영하지 않습니다.'),
      ])),
      _card('알고리즘별 누적 검증', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_summary.isEmpty) Text('등록·채점된 예측이 없습니다. research_v1_schema.sql 적용 후 ▶ 버튼으로 실행하세요.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ..._summary.map((a) => Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${a.algorithm} ${a.version}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                  statusChip(a.status, _statusColor(a.status)),
                ]),
                _kv('등록/유효채점/무효', '${a.registered} / ${a.verified} / ${a.invalid}'),
                if (a.verified > 0) ...[
                  _kv('세트당 평균 일치', '${a.meanMatches.toStringAsFixed(3)} vs 0.800 (효과 ${a.diff >= 0 ? '+' : ''}${a.diff.toStringAsFixed(3)} ± ${a.se.toStringAsFixed(3)})',
                      color: a.diff > 0 ? Colors.teal.shade800 : Colors.red.shade700),
                  _kv('p / Holm p', '${_p(a.p)} / ${_p(a.pHolm)}'),
                  _kv('3개+ 일치', '${a.atLeast3Sets}/${a.totalSets} (CI ${(a.atLeast3Ci[0] * 100).toStringAsFixed(1)}~${(a.atLeast3Ci[1] * 100).toStringAsFixed(1)}%) vs 2.38%'),
                  _kv('최고 등수', a.bestRank == 0 ? '없음' : '${a.bestRank}등'),
                  if (a.firstHalfDiff != null) _kv('전반/후반 효과', '${a.firstHalfDiff!.toStringAsFixed(3)} / ${a.secondHalfDiff!.toStringAsFixed(3)} (후반 p=${_p(a.secondHalfP!)})'),
                ],
              ]),
            )),
        _note('상태 기준(고정): 연구 중 <20회차 · 검증 후보 ≥20 & 효과>0 · 통계적 우위 ≥52 & Holm p<0.01 · 재현 검증 ≥104 & 전·후반 모두 >0 · 성능 저하 효과≤0'),
      ])),
      _card('최근 등록 예측', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_recent.isEmpty) const Text('없음', style: TextStyle(fontSize: 11)),
        ..._recent.map((r) {
          final v = r['verification'] as Map?;
          final sets = (r['sets'] as List).map((s) => (s as List).join(',')).join(' | ');
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(r['pre_deadline'] == true ? Icons.lock : Icons.lock_open, size: 13, color: r['pre_deadline'] == true ? Colors.teal : Colors.orange),
                const SizedBox(width: 4),
                Expanded(child: Text('${r['target_round']}회 · ${r['algorithm']} ${r['version']} · ${r['status']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                if (v != null) Text('평균 ${(v['mean_matches'] as num).toStringAsFixed(2)} · 최고 ${v['best_rank'] == 0 ? '-' : '${v['best_rank']}등'}', style: const TextStyle(fontSize: 10)),
              ]),
              Text(sets, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ]),
          );
        }),
      ])),
    ]);
  }

  Color _statusColor(String s) {
    if (s.startsWith('재현')) return Colors.green.shade800;
    if (s.startsWith('통계적')) return Colors.teal.shade700;
    if (s.startsWith('검증 후보')) return Colors.blue.shade700;
    if (s.startsWith('성능')) return Colors.red.shade700;
    return Colors.grey.shade700;
  }
}

const String kPurchaseVersionLabel = 'pp-0.1';
