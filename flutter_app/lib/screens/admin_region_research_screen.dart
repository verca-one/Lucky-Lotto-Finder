// 관리자 — 명당 가설 연구소 · 전국 지역 연구 (research_region_worker.py 결과 조회 전용)
//
// 탭: 전국 연구 / 지역별 독립 연구 / 지역 간 공간전이 / 유명 명당 주기 / 신흥 명당 / 지역별 예측 난이도 / 복합 가설
// 상태 구분: SQL 미적용(테이블 없음) · 연구 미실행(행 없음) · 데이터 있음. 검증 통과와 탐색 후보를 분리 표시한다.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String kRegionModel = 'rg-1.0';

const Map<String, String> kHypStatusLabel = {
  'discovered': '발견', 'researching': '연구 중', 'passed': '검증 통과',
  'weakened': '약화', 'rejected': '기각', 'combined': '결합(검증)',
};
const Map<String, Color> kHypStatusColor = {
  'discovered': Color(0xFF42A5F5), 'researching': Color(0xFF7E57C2), 'passed': Color(0xFF2E7D32),
  'weakened': Color(0xFFEF6C00), 'rejected': Color(0xFF9E9E9E), 'combined': Color(0xFF00897B),
};
const Map<String, String> kHypKindLabel = {
  'transition_up': '지역 전이(증가)', 'transition_down': '지역 전이(감소)', 'self_repeat': '같은 지역 반복',
  'chain': '복합 전이 A→B→C', 'distance_band': '거리별 전이', 'store_cycle': '판매점 주기 예측',
  'emerging_store': '신흥 명당 지속성', 'dormant_rebound': '휴면 지역 반등',
};

enum _Load { loading, noTable, empty, ok, error }

String regionLabel(String? rid) {
  if (rid == null) return '-';
  final p = rid.split('|');
  return p.length == 2 ? '${p[0]} ${p[1]}' : rid;
}

String _pct(dynamic v, [int d = 1]) => v == null ? '-' : '${((v as num) * 100).toStringAsFixed(d)}%';
String _p(dynamic v) => v == null ? '-' : ((v as num) < 0.0001 ? '<0.0001' : (v).toStringAsFixed(4));

class AdminRegionResearchScreen extends StatefulWidget {
  final int initialTab;
  final String? initialRegion;
  const AdminRegionResearchScreen({super.key, this.initialTab = 0, this.initialRegion});
  @override
  State<AdminRegionResearchScreen> createState() => _AdminRegionResearchScreenState();
}

class _AdminRegionResearchScreenState extends State<AdminRegionResearchScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _db = Supabase.instance.client;
  _Load _state = _Load.loading;
  String? _error;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _run;
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _hyps = [];
  List<Map<String, dynamic>> _latestStats = [];
  int _latestRound = 0;
  String? _selRegion;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 7, vsync: this, initialIndex: widget.initialTab.clamp(0, 6));
    _selRegion = widget.initialRegion;
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _all(String table, String select, {Map<String, Object>? eq, String? order, bool asc = true}) async {
    final out = <Map<String, dynamic>>[];
    int off = 0;
    while (true) {
      dynamic q = _db.from(table).select(select);
      eq?.forEach((k, v) => q = q.eq(k, v));
      if (order != null) q = q.order(order, ascending: asc);
      final page = List<Map<String, dynamic>>.from(await q.range(off, off + 999) as List);
      out.addAll(page);
      if (page.length < 1000) break;
      off += 1000;
    }
    return out;
  }

  Future<void> _load() async {
    setState(() { _state = _Load.loading; _error = null; });
    try {
      final runs = await _db.from('research_region_runs').select().eq('model_version', kRegionModel)
          .order('training_end_round', ascending: false).limit(1);
      _run = (runs as List).isEmpty ? null : Map<String, dynamic>.from(runs.first as Map);
      final units = await _all('research_region_units', '*', order: 'region_id');
      if (units.isEmpty) {
        setState(() => _state = _Load.empty);
        return;
      }
      final rr = await _db.from('research_results').select('payload,training_end_round')
          .eq('research_type', 'region_research').eq('model_version', kRegionModel)
          .order('training_end_round', ascending: false).limit(1);
      _summary = (rr as List).isEmpty ? null : Map<String, dynamic>.from((rr.first as Map)['payload'] as Map);
      _latestRound = (_summary?['latest_round'] as num?)?.toInt() ?? (_run?['training_end_round'] as num?)?.toInt() ?? 0;
      final hyps = await _all('research_region_hypotheses', '*', eq: {'model_version': kRegionModel});
      final stats = _latestRound > 0
          ? await _all('research_region_stats', '*', eq: {'model_version': kRegionModel, 'training_end_round': _latestRound})
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _units = units; _hyps = hyps; _latestStats = stats;
        _state = _Load.ok;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final missing = e.code == 'PGRST205' || e.code == '42P01' || (e.message).contains('does not exist') || (e.message).contains('schema cache');
      setState(() { _state = missing ? _Load.noTable : _Load.error; _error = e.message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _state = _Load.error; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1), foregroundColor: Colors.white,
        title: const Text('전국 지역 연구', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white))],
        bottom: TabBar(
          controller: _tab, isScrollable: true, labelColor: Colors.white, unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amber,
          tabs: const [
            Tab(text: '전국 연구'), Tab(text: '지역별 독립 연구'), Tab(text: '지역 간 공간전이'), Tab(text: '유명 명당 주기'),
            Tab(text: '신흥 명당'), Tab(text: '지역별 예측 난이도'), Tab(text: '복합 가설'),
          ],
        ),
      ),
      body: switch (_state) {
        _Load.loading => const Center(child: CircularProgressIndicator()),
        _Load.noTable => _message('SQL 미적용', 'research_v4_regions.sql 을 Supabase SQL Editor 에서 실행해야 지역 연구 결과를 저장·조회할 수 있습니다.', Colors.orange),
        _Load.empty => _message('연구 미실행', '지역 연구 테이블은 있으나 결과가 없습니다. 서버 Worker(Research Worker 워크플로) 또는 research_region_worker.py 실행 후 표시됩니다.\n최근 실행: ${_run == null ? '없음' : '${_run!['training_end_round']}회 ${_run!['status']}'}', Colors.blueGrey),
        _Load.error => _message('조회 실패', _error ?? '', Colors.red),
        _Load.ok => TabBarView(controller: _tab, children: [
            _nationalTab(), _regionTab(), _transitionTab(), _famousTab(), _emergingTab(), _difficultyTab(), _chainTab(),
          ]),
      },
    );
  }

  // ── 공통 위젯 ──────────────────────────────────────────────
  Widget _message(String title, String body, Color color) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.info_outline, color: color, size: 36),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5)),
          ]),
        ),
      );

  Widget _card(String title, Widget body, {Color color = const Color(0xFF0D47A1), Widget? trailing}) => Container(
        width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color))),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: 8),
          body,
        ]),
      );

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 132, child: Text(k, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
          Expanded(child: Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color, height: 1.35))),
        ]),
      );

  Widget _note(String s) => Container(
        margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(8), width: double.infinity,
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
        child: Text(s, style: TextStyle(fontSize: 10, color: Colors.grey.shade700, height: 1.4)),
      );

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.45))),
        child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w800)),
      );

  Widget _statusChip(String? s) => _chip(kHypStatusLabel[s] ?? (s ?? '-'), kHypStatusColor[s] ?? Colors.grey);

  Widget _hypTile(Map<String, dynamic> h) {
    final ev = Map<String, dynamic>.from(h['evidence'] as Map? ?? {});
    final cond = Map<String, dynamic>.from(h['condition'] as Map? ?? {});
    final title = switch (h['kind']) {
      'distance_band' => '+${h['horizon']}회 · ${h['distance_km']}km 이내 재당첨',
      'chain' => '${regionLabel(h['from_region'])} → ${regionLabel(h['via_region'])} → ${regionLabel(h['to_region'])}',
      'transition_up' || 'transition_down' || 'self_repeat' => '${regionLabel(h['from_region'])} → ${regionLabel(h['to_region'])} (+${h['horizon']}회)',
      _ => '${kHypKindLabel[h['kind']] ?? h['kind']} · ${h['discovered_round']}회 기준',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
          _statusChip(h['status'] as String?),
        ]),
        const SizedBox(height: 4),
        if (cond['rule'] != null) Text('${cond['rule']}', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
        _kv('유형 / 발견', '${kHypKindLabel[h['kind']] ?? h['kind']} · ${h['discovered_round']}회 이하 데이터로 발견'
            '${ev['origin'] != null ? ' · ${ev['origin']}' : ''}'),
        if (h['train_n'] != null)
          _kv('발견 구간', '${h['train_k']}/${h['train_n']} (${_pct(h['train_rate'])} vs 기준 ${_pct(h['train_base'])}) p=${_p(h['train_p'])}'
              '${h['train_q'] != null ? ' · FDR q=${_p(h['train_q'])}' : ''}'),
        _kv('순방향 검증', (h['test_n'] ?? 0) == 0 ? '아직 검증 회차 없음'
            : '${h['test_k']}/${h['test_n']}${h['test_rate'] != null ? ' (${_pct(h['test_rate'])} vs 기준 ${_pct(h['test_base'])})' : ' (기대 ${(h['test_base'] as num?)?.toStringAsFixed(1) ?? '-'})'} p=${_p(h['test_p'])}',
            color: h['status'] == 'passed' || h['status'] == 'combined' ? Colors.green.shade800 : null),
        _kv('실전 반영', h['live_eligible'] == true ? '가능 (검증 통과)' : '불가 — 연구용 참고 정보',
            color: h['live_eligible'] == true ? Colors.green.shade800 : Colors.grey.shade700),
        if (ev['note'] != null) Text('※ ${ev['note']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ]),
    );
  }

  // ── 탭 1: 전국 연구 ───────────────────────────────────────
  Widget _nationalTab() {
    final s = _summary ?? {};
    final byStatus = Map<String, dynamic>.from(s['by_status'] as Map? ?? {});
    final byKind = Map<String, dynamic>.from(s['by_kind'] as Map? ?? {});
    final rep = Map<String, dynamic>.from(s['transition_replication'] as Map? ?? {});
    final diff = Map<String, dynamic>.from(s['difficulty'] as Map? ?? {});
    final classes = Map<String, dynamic>.from(s['store_classes'] as Map? ?? {});
    final passed = _hyps.where((h) => h['status'] == 'passed' || h['status'] == 'combined').toList();
    final livePassed = passed.where((h) => h['live_eligible'] == true).toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      _card('실행 상태', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _kv('최근 실행', _run == null ? '없음' : '${_run!['training_end_round']}회 · ${_run!['status']} · ${_run!['runner'] ?? '-'} · ${(_run!['completed_at'] ?? _run!['started_at'] ?? '').toString().replaceFirst('T', ' ').split('.').first}'),
        _kv('모델', kRegionModel),
        _kv('연구 범위', '${(s['rounds_range'] as List?)?.join('~') ?? '-'}회 · 유효 ${s['valid_rounds'] ?? '-'}회차 (누락 ${s['missing_rounds'] ?? '-'})'),
        _kv('체크포인트', (s['checkpoints'] as List?)?.join(', ') ?? '-'),
        _kv('지역 단위', '${s['units'] ?? _units.where((u) => u['level'] == 'sigungu').length}개 시·군·구 · ${s['sidos'] ?? '-'}개 시·도'),
        _kv('판매점', '${s['stores_total'] ?? '-'}곳 (주소 해석 실패 ${s['stores_unparsed'] ?? '-'}) · 인터넷 1등 ${s['winners_internet'] ?? '-'}건은 지역 연구 제외'),
      ])),
      _card('가설 현황', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in byStatus.entries) _chip('${kHypStatusLabel[e.key] ?? e.key} ${e.value}', kHypStatusColor[e.key] ?? Colors.grey),
        ]),
        const SizedBox(height: 8),
        for (final e in byKind.entries) _kv(kHypKindLabel[e.key] ?? e.key, '${e.value}개 · 통과 ${_hyps.where((h) => h['kind'] == e.key && (h['status'] == 'passed' || h['status'] == 'combined')).length}'),
        _kv('실전 반영 가능', '${livePassed.length}개', color: livePassed.isEmpty ? Colors.grey.shade700 : Colors.green.shade800),
      ])),
      _card('지역 전이 재현성', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _kv('순방향 20회+ 검증', '${rep['tested_n20'] ?? 0}개'),
        _kv('같은 방향 재현', '${rep['same_direction'] ?? 0}개 (${_pct(rep['same_direction_rate'])}) vs 무작위 기대 50%',
            color: (rep['same_direction_rate'] as num?) != null && (rep['same_direction_rate'] as num) > 0.6 ? Colors.green.shade800 : Colors.red.shade700),
        _note('발견 구간에서 강했던 지역 전이가 이후 회차에서도 같은 방향으로 나타나는 비율입니다. 50% 근처면 발견은 우연(다중검정 잡음)이었다는 뜻입니다.'),
      ])),
      _card('판매점 분류 · 예측 난이도', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _kv('유명 명당(1등 5회+)', '${classes['famous'] ?? 0}곳'),
        _kv('신흥 명당', '${classes['emerging'] ?? 0}곳 (최근 100회 급증, 포아송 p<0.01)'),
        _kv('예측 난이도', '지역 빈도 모델이 무작위 기준보다 나은 지역 ${diff['m1_better_than_m0'] ?? '-'}/${diff['units'] ?? '-'} (검증 ${diff['test_rounds'] ?? '-'}회차)'),
        _note('모든 지역·판매점 분석은 판매량 미보정입니다. 당첨이 잦은 곳은 판매량이 많은 곳일 수 있으며, 복권 한 장당 당첨확률 우위를 뜻하지 않습니다.'),
      ])),
    ]);
  }

  // ── 탭 2: 지역별 독립 연구 ────────────────────────────────
  Widget _regionTab() {
    final units = _units.where((u) => u['level'] == 'sigungu').toList();
    final q = _query.trim();
    final filtered = q.isEmpty ? units : units.where((u) =>
        '${u['region_id']} ${u['unit_name']} ${(u['sub_units'] as List?)?.join(' ') ?? ''}'.contains(q)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '시·군·구 검색 (예: 천안, 수원, 인천, 노원)', isDense: true),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      if (_selRegion == null || q.isNotEmpty)
        Expanded(child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: filtered.take(80).map((u) {
            final st = _latestStats.where((s) => s['region_id'] == u['region_id']).firstOrNull;
            return ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text(regionLabel(u['region_id'] as String), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('판매점 ${u['store_count']}곳 · 1등 ${st?['first_wins'] ?? '-'}회 · 1등 회차율 ${_pct(st?['win_round_rate'], 2)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() { _selRegion = u['region_id'] as String; _query = ''; }),
            );
          }).toList(),
        ))
      else
        Expanded(child: _RegionDetail(regionId: _selRegion!, units: _units, hyps: _hyps, latestRound: _latestRound,
            onBack: () => setState(() => _selRegion = null), parent: this)),
    ]);
  }

  // ── 탭 3: 지역 간 공간전이 ────────────────────────────────
  Widget _transitionTab() {
    final list = _hyps.where((h) => const {'transition_up', 'transition_down', 'self_repeat', 'distance_band'}.contains(h['kind'])).toList()
      ..sort(_hypOrder);
    return ListView(padding: const EdgeInsets.all(14), children: [
      _note('+1~+6회 시차별로 "A 지역 1등 이후 B 지역 1등 증가/감소"를 회차별 전체 당첨 판매점 분포로 검정합니다. '
          '체크포인트마다 그 시점까지 데이터로만 발견하고(FDR 보정), 이후 회차로만 검증합니다. 당첨점이 실제로 이동한다고 가정하지 않습니다.'),
      const SizedBox(height: 8),
      if (list.isEmpty) const Text('전이 가설 없음', style: TextStyle(fontSize: 12)),
      ...list.map(_hypTile),
    ]);
  }

  int _hypOrder(Map<String, dynamic> a, Map<String, dynamic> b) {
    const rank = {'passed': 0, 'combined': 1, 'researching': 2, 'discovered': 3, 'weakened': 4, 'rejected': 5};
    final c = (rank[a['status']] ?? 9).compareTo(rank[b['status']] ?? 9);
    if (c != 0) return c;
    return ((a['test_p'] as num?) ?? 1).compareTo((b['test_p'] as num?) ?? 1);
  }

  // ── 탭 4: 유명 명당 주기 ──────────────────────────────────
  Widget _famousTab() => _StoreCycleList(cls: 'famous', latestRound: _latestRound,
      header: _hyps.where((h) => h['kind'] == 'store_cycle').toList()..sort((a, b) => (b['discovered_round'] as int).compareTo(a['discovered_round'] as int)),
      hypTile: _hypTile, note: '주기 창 예측 가설은 "4회 이상 1등 판매점의 다음 1등이 평균 간격 근처에 온다"를 체크포인트마다 순방향 검증합니다. '
          '주기성이 관찰돼도 다음 당첨 회차를 확정하지 않습니다.');

  // ── 탭 5: 신흥 명당 ───────────────────────────────────────
  Widget _emergingTab() => _StoreCycleList(cls: 'emerging', latestRound: _latestRound,
      header: _hyps.where((h) => h['kind'] == 'emerging_store' || h['kind'] == 'dormant_rebound').toList()
        ..sort((a, b) => (b['discovered_round'] as int).compareTo(a['discovered_round'] as int)),
      hypTile: _hypTile, note: '신흥 명당 = 최근 100회 1등이 첫 당첨 이후 평균보다 유의하게 많은 판매점(포아송 p<0.01). '
          '지속성 가설이 통과해도 판매량 증가(신규·인기 판매점)로 설명될 수 있어 실전 확률 근거로 쓰지 않습니다.');

  // ── 탭 6: 지역별 예측 난이도 ──────────────────────────────
  Widget _difficultyTab() {
    final rows = _latestStats.where((s) => (s['difficulty'] as Map?)?.isNotEmpty == true).toList()
      ..sort((a, b) => (((b['difficulty'] as Map)['gain_vs_m0'] as num?) ?? 0).compareTo(((a['difficulty'] as Map)['gain_vs_m0'] as num?) ?? 0));
    return ListView(padding: const EdgeInsets.all(14), children: [
      _note('각 지역에서 "다음 회차에 1등이 나올지"를 순방향으로 예측한 log-loss 비교입니다. '
          'm0 = 판매점 수 비례 무작위 기준, m1 = 지역 빈도(계층적 축소추정), m2 = 최근 50회 빈도. '
          '개선 = m0 대비 손실 감소율. m1 이 낫다는 것은 지역 판매량 차이를 반영할 뿐 당첨확률 우위가 아닙니다.'),
      const SizedBox(height: 8),
      ...rows.take(120).map((s) {
        final d = Map<String, dynamic>.from(s['difficulty'] as Map);
        final gain = (d['gain_vs_m0'] as num?)?.toDouble() ?? 0;
        return ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          title: Text(regionLabel(s['region_id'] as String), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: Text('${d['level'] ?? ''} · 최적 ${d['best']} · 검증 ${d['test_n']}회 중 1등 ${d['wins_in_test']}회', style: const TextStyle(fontSize: 11)),
          trailing: Text('${gain >= 0 ? '+' : ''}${(gain * 100).toStringAsFixed(1)}%',
              style: TextStyle(fontWeight: FontWeight.w800, color: gain > 0.002 ? Colors.green.shade800 : Colors.grey.shade600)),
          onTap: () => setState(() { _selRegion = s['region_id'] as String; _tab.animateTo(1); }),
        );
      }),
    ]);
  }

  // ── 탭 7: 복합 가설 ───────────────────────────────────────
  Widget _chainTab() {
    final list = _hyps.where((h) => h['kind'] == 'chain').toList()..sort(_hypOrder);
    return ListView(padding: const EdgeInsets.all(14), children: [
      _note('복합 가설 = 증가 방향 전이 후보 두 개를 이은 A→B→C. 구성 가설이 순방향에서 기각되지 않은 것만 결합하며, 결합 자체도 이후 회차로만 검증합니다.'),
      const SizedBox(height: 8),
      if (list.isEmpty) const Text('복합 가설 없음 (결합 가능한 전이 후보 부족)', style: TextStyle(fontSize: 12)),
      ...list.map(_hypTile),
    ]);
  }
}

// ── 지역 상세 ─────────────────────────────────────────────────
class _RegionDetail extends StatefulWidget {
  final String regionId;
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> hyps;
  final int latestRound;
  final VoidCallback onBack;
  final _AdminRegionResearchScreenState parent;
  const _RegionDetail({required this.regionId, required this.units, required this.hyps, required this.latestRound,
      required this.onBack, required this.parent});
  @override
  State<_RegionDetail> createState() => _RegionDetailState();
}

class _RegionDetailState extends State<_RegionDetail> {
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(_RegionDetail old) {
    super.didUpdateWidget(old);
    if (old.regionId != widget.regionId) _future = _load();
  }

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async {
    final db = Supabase.instance.client;
    final stats = List<Map<String, dynamic>>.from(await db.from('research_region_stats').select()
        .eq('region_id', widget.regionId).eq('model_version', kRegionModel).order('training_end_round') as List);
    final stores = List<Map<String, dynamic>>.from(await db.from('research_store_cycles').select()
        .eq('region_id', widget.regionId).eq('model_version', kRegionModel).eq('training_end_round', widget.latestRound)
        .order('first_count', ascending: false).limit(15) as List);
    return (stats, stores);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.parent;
    final unit = widget.units.where((u) => u['region_id'] == widget.regionId).firstOrNull;
    final related = widget.hyps.where((h) => h['from_region'] == widget.regionId || h['to_region'] == widget.regionId || h['via_region'] == widget.regionId).toList()
      ..sort(p._hypOrder);
    return FutureBuilder<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: Text('조회 실패: ${snap.error}'));
        final (stats, stores) = snap.data!;
        final latest = stats.isEmpty ? null : stats.last;
        return ListView(padding: const EdgeInsets.all(14), children: [
          Row(children: [
            IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
            Expanded(child: Text(regionLabel(widget.regionId), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ]),
          if (latest == null) p._note('이 지역의 연구 결과가 없습니다 (연구 미실행).')
          else ...[
            p._card('${latest['training_end_round']}회 기준 지역 통계', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              p._kv('판매점', '${unit?['store_count'] ?? '-'}곳 (좌표 ${unit?['geo_store_count'] ?? '-'}) · 하위 ${(unit?['sub_units'] as List?)?.take(8).join(', ') ?? '-'}'),
              p._kv('1등 / 2등', '${latest['first_wins']}회 / ${latest['second_wins']}회 (2등 수집 범위 일부)'),
              p._kv('1등 회차율', '${_pct(latest['win_round_rate'], 2)} (관측 ${latest['rounds_observed']}회차 중 ${latest['rounds_with_first']}회)'),
              p._kv('무작위 기준', '${_pct(latest['baseline_rate'], 2)} (판매점 수 비례, 판매량 미보정)'),
              p._kv('축소추정', '${_pct(latest['shrunk_rate'], 2)} (전국→시도→지역 부분 풀링)'),
              p._kv('최근 50회', '${_pct(latest['recent50_rate'], 2)} · 추세 z=${(latest['trend_z'] as num?)?.toStringAsFixed(2) ?? '-'}',
                  color: ((latest['trend_z'] as num?) ?? 0) > 2 ? Colors.red.shade700 : ((latest['trend_z'] as num?) ?? 0) < -2 ? Colors.blue.shade700 : null),
              p._kv('마지막 1등', latest['last_first_round'] == null ? '없음' : '${latest['last_first_round']}회 (${latest['dormant_rounds']}회 경과)'),
              p._kv('지역 내 집중도', latest['concentration_hhi'] == null ? '-' : 'HHI ${(latest['concentration_hhi'] as num).toStringAsFixed(3)} (1에 가까울수록 한 판매점 집중)'),
              p._kv('구매방식(1등)', '${latest['purchase_methods']}'),
              if ((latest['difficulty'] as Map?)?.isNotEmpty == true)
                p._kv('예측 난이도', '${(latest['difficulty'] as Map)['level']} (개선 ${(((latest['difficulty'] as Map)['gain_vs_m0'] as num) * 100).toStringAsFixed(1)}%)'),
              p._kv('인접 생활권', ((unit?['neighbors'] as List?) ?? []).map((n) => '${regionLabel((n as Map)['region_id'] as String)} ${n['km']}km').join(', ')),
            ])),
            p._card('체크포인트별 축소추정 1등 회차율', Column(children: [
              for (final s in stats)
                Row(children: [
                  SizedBox(width: 56, child: Text('${s['training_end_round']}회', style: const TextStyle(fontSize: 11))),
                  Expanded(child: LinearProgressIndicator(
                      value: (((s['shrunk_rate'] as num?) ?? 0) * 4).clamp(0.0, 1.0).toDouble(), minHeight: 6,
                      backgroundColor: Colors.grey.shade200)),
                  SizedBox(width: 56, child: Text(_pct(s['shrunk_rate'], 2), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
                ]),
            ])),
            p._card('주요 판매점 (1등 순)', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (stores.isEmpty) const Text('주기 연구 대상 판매점 없음', style: TextStyle(fontSize: 11)),
              for (final s in stores)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Expanded(child: Text('${s['store_name']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                    p._chip({'famous': '유명', 'emerging': '신흥', 'regular': '일반', 'sparse': '희소'}[s['class']] ?? '${s['class']}',
                        s['class'] == 'famous' ? Colors.deepOrange : s['class'] == 'emerging' ? Colors.purple : Colors.grey),
                    const SizedBox(width: 6),
                    Text('1등 ${s['first_count']} · 2등 ${s['second_count']} · 간격 ${(s['gap_mean'] as num?)?.toStringAsFixed(0) ?? '-'}회 · ${s['rounds_since_last']}회 경과',
                        style: const TextStyle(fontSize: 10.5)),
                  ]),
                ),
            ])),
          ],
          p._card('이 지역 관련 가설 (${related.length})', Column(children: [
            if (related.isEmpty) const Text('관련 가설 없음 — 이 지역이 포함된 전이 후보가 다중검정 기준을 넘지 못했습니다', style: TextStyle(fontSize: 11)),
            ...related.take(20).map(p._hypTile),
          ])),
        ]);
      },
    );
  }
}

// ── 판매점 주기 목록 (유명/신흥) ──────────────────────────────
class _StoreCycleList extends StatefulWidget {
  final String cls;
  final int latestRound;
  final List<Map<String, dynamic>> header;
  final Widget Function(Map<String, dynamic>) hypTile;
  final String note;
  const _StoreCycleList({required this.cls, required this.latestRound, required this.header, required this.hypTile, required this.note});
  @override
  State<_StoreCycleList> createState() => _StoreCycleListState();
}

class _StoreCycleListState extends State<_StoreCycleList> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = () async {
      final q = Supabase.instance.client.from('research_store_cycles').select()
          .eq('model_version', kRegionModel).eq('training_end_round', widget.latestRound).eq('class', widget.cls);
      final rows = await (widget.cls == 'emerging' ? q.order('emerging_p') : q.order('first_count', ascending: false)).limit(100);
      return List<Map<String, dynamic>>.from(rows as List);
    }();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final rows = snap.data ?? [];
        return ListView(padding: const EdgeInsets.all(14), children: [
          Container(
            padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text(widget.note, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
          ),
          const SizedBox(height: 8),
          if (widget.header.isNotEmpty) ...[
            Text('순방향 검증 (체크포인트별)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
            const SizedBox(height: 6),
            ...widget.header.take(6).map(widget.hypTile),
            const SizedBox(height: 8),
          ],
          Text(widget.cls == 'famous' ? '유명 명당 (1등 5회 이상, ${rows.length}곳)' : '신흥 명당 후보 (${rows.length}곳)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
          const SizedBox(height: 6),
          if (rows.isEmpty) const Text('해당 판매점 없음 (연구 미실행 또는 조건 충족 없음)', style: TextStyle(fontSize: 11)),
          for (final s in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${s['store_name']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
                  Text(regionLabel(s['region_id'] as String?), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ]),
                const SizedBox(height: 3),
                Text('1등 ${s['first_count']}회 · 2등 ${s['second_count']}회 · 마지막 1등 이후 ${s['rounds_since_last']}회 · 최근 100회 ${s['recent100_first']}회',
                    style: const TextStyle(fontSize: 11)),
                Text('간격 평균 ${(s['gap_mean'] as num?)?.toStringAsFixed(1) ?? '-'} · 중앙값 ${(s['gap_median'] as num?)?.toStringAsFixed(0) ?? '-'} · 변동계수 ${(s['gap_cv'] as num?)?.toStringAsFixed(2) ?? '-'}'
                    '${widget.cls == 'emerging' ? ' · 급증 p=${_p(s['emerging_p'])}' : ''}',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                Text('구매방식 ${s['purchase_methods']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ]),
            ),
          Text('변동계수(CV) ≈ 1 이면 무작위(기억 없는) 당첨 간격과 같고, 1보다 작을수록 규칙적입니다. 판매량 미보정.',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ]);
      },
    );
  }
}
