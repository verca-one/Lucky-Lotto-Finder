// 지역 추천 (관리자 전용 연구 기능)
//
// 시·군·구를 검색해 그 지역 로또 판매점 목록과 엔진 평가 순위를 보여준다.
// 데이터: lottery_stores / winning_history (크롤러 테이블, 읽기 전용) +
//        research_region_* / research_store_cycles (research_v4_regions.sql, 읽기 전용) +
//        mnd_hypotheses (읽기 전용) + research_agent_* (research_v5_agents.sql, 지방장 납품·점수, 읽기 전용).
//        DB 쓰기 없음.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/research/agent_store_evidence.dart';
import '../services/route/region_research_repository.dart';
import '../widgets/admin_region_store_widgets.dart';
import '../widgets/agent_store_widgets.dart' show AgentRegionDeliverySection;

class AdminRegionRecommendContent extends StatefulWidget {
  /// 다른 탭(현 위치 추천)에서 지역을 넘겨 열 때 사용
  final String? initialRegionId;
  const AdminRegionRecommendContent({super.key, this.initialRegionId});

  @override
  State<AdminRegionRecommendContent> createState() =>
      _AdminRegionRecommendContentState();
}

class _AdminRegionRecommendContentState extends State<AdminRegionRecommendContent> {
  final _repo = RegionResearchRepository();
  final _searchCtrl = TextEditingController();

  bool _adminChecked = false;
  bool _isAdmin = false;

  // 지역 단위
  bool _unitsLoading = true;
  List<RegionUnit> _units = [];
  ResearchAvailability _unitsState = ResearchAvailability.notApplied;
  String? _unitsMessage;
  List<RegionUnit> _matches = [];

  // 선택 지역 결과
  RegionUnit? _selectedUnit;
  bool _loading = false;
  String _progress = '';
  String? _error;
  RegionRankingResult? _result;
  ResearchLoad<Map<String, RegionStats>>? _stats;
  ResearchLoad<List<RegionHypothesis>>? _hyps;
  String? _selectedCode;

  // 판매점별 지방장 근거 (목록 일괄 조회)
  AgentEvidenceBundle? _bundle;
  bool _bundleLoading = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final isAdmin = prefs.getBool('isAdmin') ?? false;
    if (!mounted) return;
    setState(() {
      _isAdmin = isAdmin;
      _adminChecked = true;
    });
    if (!isAdmin) return;
    try {
      final u = await _repo.loadUnits();
      if (!mounted) return;
      setState(() {
        _units = u.data;
        _unitsState = u.state;
        _unitsMessage = u.message;
      });
      final init = widget.initialRegionId;
      if (init != null) {
        final hit = _units.where((x) => x.regionId == init).toList();
        _select(hit.isNotEmpty
            ? hit.first
            : RegionUnit(
                regionId: init,
                sido: RegionIds.sidoOf(init),
                unitName: RegionIds.unitOf(init),
                derived: true));
      }
    } catch (e) {
      if (mounted) setState(() => _unitsMessage = '지역 목록 조회 실패: $e');
    } finally {
      if (mounted) setState(() => _unitsLoading = false);
    }
  }

  void _search() {
    final q = _searchCtrl.text.trim();
    FocusScope.of(context).unfocus();
    if (q.isEmpty) {
      setState(() => _matches = []);
      return;
    }
    final m = _units.where((u) => u.matches(q)).toList()
      ..sort((a, b) {
        final c = b.storeCount.compareTo(a.storeCount);
        return c != 0 ? c : a.regionId.compareTo(b.regionId);
      });
    setState(() => _matches = m);
    if (m.length == 1) _select(m.first);
    if (m.isEmpty) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('"$q" 와 일치하는 시·군·구가 없습니다.')));
    }
  }

  Future<void> _select(RegionUnit u) async {
    setState(() {
      _selectedUnit = u;
      _matches = [];
      _searchCtrl.text = u.display;
      _loading = true;
      _error = null;
      _result = null;
      _stats = null;
      _hyps = null;
      _selectedCode = null;
      _bundle = null;
      _progress = '${u.display} 판매점 조회 중…';
    });
    try {
      final stores = await _repo.loadStoresInRegion(u.regionId);
      if (!mounted) return;
      if (stores.isEmpty) {
        throw '${u.display} 에 로또 판매점이 없습니다 (주소 기준 판정).';
      }
      setState(() => _progress = '엔진 근거 조회 중 (${stores.length}곳)…');
      final inputs = await _repo.loadEngineInputs(stores, {u.regionId});
      final ranked = RegionStoreRanker.rank(stores: stores, inputs: inputs);
      final res = RegionStoreRanker.buildResult(ranked, inputs);
      setState(() => _progress = '지역 연구 결과 조회 중…');
      final stats = await _repo.loadLatestStats([u.regionId]);
      final hyps = await _repo.loadRegionHypotheses(u.regionId);
      if (!mounted) return;
      setState(() {
        _result = res;
        _stats = stats;
        _hyps = hyps;
      });
      _loadBundle(res);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _loadBundle(RegionRankingResult res) async {
    setState(() => _bundleLoading = true);
    try {
      final b = await loadEvidenceForRanked(res.items);
      if (mounted && identical(_result, res)) setState(() => _bundle = b);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _bundleLoading = false);
    }
  }

  void _openDetail(RankedRegionStore item) {
    setState(() => _selectedCode = item.store.code);
    showRegionStoreDetailSheet(context, item, evidence: _bundle?.of(item.store.code, agentId: item.store.regionId));
  }

  @override
  Widget build(BuildContext context) {
    if (!_adminChecked) return const Center(child: CircularProgressIndicator());
    if (!_isAdmin) return const Center(child: Text('관리자 전용 기능입니다.'));
    final r = _result;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _buildSearch(),
        if (_matches.isNotEmpty) _buildMatches(),
        if (_loading)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(_progress, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        if (_error != null) _errorBox(_error!),
        if (r != null && _selectedUnit != null) ...[
          _buildRegionStats(),
          AgentRegionDeliverySection(
            key: ValueKey('agent_${_selectedUnit!.regionId}'),
            regionId: _selectedUnit!.regionId,
          ),
          RegionStoresMap(
            items: r.items,
            selectedCode: _selectedCode,
            onTapStore: _openDetail,
          ),
          RegionRankingHeader(
            result: r,
            title: '${_selectedUnit!.display} 판매점 ${r.items.length}곳 · 엔진 평가 순위',
          ),
          for (final item in r.items)
            RegionStoreCard(
              item: item,
              selected: item.store.code == _selectedCode,
              onTap: () => _openDetail(item),
              onNav: () => showStoreNavSheet(context,
                  name: item.store.name, point: item.store.point!),
              evidence: _bundle?.of(item.store.code, agentId: item.store.regionId),
              evidenceLoading: _bundleLoading,
            ),
          _buildHypotheses(),
        ],
      ],
    );
  }

  Widget _buildSearch() {
    return Container(
      color: Colors.deepOrange.shade50,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              isDense: true,
              labelText: '시·군·구 검색',
              hintText: '예: 천안, 수원, 화성, 인천, 서울 노원구',
              prefixIcon: const Icon(Icons.location_city, size: 18),
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search),
              filled: true,
              fillColor: Colors.white,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 4),
          if (_unitsLoading)
            const Text('지역 목록 불러오는 중… (연구 테이블 없으면 판매점 주소로 생성)',
                style: TextStyle(fontSize: 11, color: Colors.black54))
          else
            Text(
              '지역 ${_units.length}개 · 연구 지역 단위: ${_unitsState.label}'
              '${_unitsMessage == null ? '' : ' — $_unitsMessage'}',
              style: TextStyle(
                  fontSize: 11,
                  color: _unitsState == ResearchAvailability.available
                      ? Colors.green.shade800
                      : Colors.brown.shade700),
            ),
        ],
      ),
    );
  }

  Widget _buildMatches() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        children: [
          for (final u in _matches.take(30))
            ListTile(
              dense: true,
              leading: const Icon(Icons.place_outlined, size: 18),
              title: Text(u.display),
              subtitle: Text(
                  '판매점 ${u.storeCount}곳 (좌표 ${u.geoStoreCount})'
                  '${u.subUnits.isEmpty ? '' : ' · ${u.subUnits.take(4).join(', ')}'}',
                  style: const TextStyle(fontSize: 11)),
              onTap: () => _select(u),
            ),
          if (_matches.length > 30)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('외 ${_matches.length - 30}개 — 검색어를 더 구체적으로 입력하세요.',
                  style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _buildRegionStats() {
    final u = _selectedUnit!;
    final st = _stats;
    final s = st?.data[u.regionId];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${u.display} 지역 연구',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          if (st == null)
            const Text('-', style: TextStyle(fontSize: 11))
          else if (s == null)
            Text('지역 통계: ${st.state.label}${st.message == null ? '' : ' (${st.message})'}',
                style: TextStyle(fontSize: 11, color: Colors.brown.shade700))
          else ...[
            Text('기준 ${s.trainingEndRound}회차 · 1등 ${s.firstWins}회 · 2등 ${s.secondWins}회',
                style: const TextStyle(fontSize: 11.5)),
            Text(
              '축소추정 ${_pct(s.shrunkRate)} · 판매점 수 기준선 ${_pct(s.baselineRate)} · '
              '최근50회 ${_pct(s.recent50Rate)} · 추세 z ${s.trendZ?.toStringAsFixed(2) ?? '-'} · '
              '1등 공백 ${s.dormantRounds ?? '-'}회',
              style: const TextStyle(fontSize: 11),
            ),
            if (s.difficulty.isNotEmpty)
              Text('예측 난이도: ${s.difficulty.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
                  style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
            if (s.topStores.isNotEmpty)
              Text(
                  '상위 판매점: ${s.topStores.take(5).map((m) => '${m['name'] ?? m['code']}(${m['first'] ?? 0})').join(', ')}',
                  style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
            const Text('기준선은 판매점 수 비례(판매량 미보정)입니다.',
                style: TextStyle(fontSize: 10, color: Colors.black45)),
          ],
        ],
      ),
    );
  }

  Widget _buildHypotheses() {
    final h = _hyps;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('지역 내부·지역 간 전이 가설 (상위 10)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          const Text(kTransitionFiringRule,
              style: TextStyle(fontSize: 10, color: Colors.black45)),
          const SizedBox(height: 6),
          if (h == null)
            const Text('-')
          else if (h.data.isEmpty)
            Text(h.state.label + (h.message == null ? '' : ' (${h.message})'),
                style: TextStyle(fontSize: 11, color: Colors.brown.shade700))
          else
            for (final x in h.data)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    regionTag(x.status, hypothesisStatusColor(x.status)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${x.summary}'
                        '${x.testRate == null ? '' : ' · 검증 ${(x.testRate! * 100).toStringAsFixed(1)}%'}'
                        '${x.testBase == null ? '' : ' vs ${(x.testBase! * 100).toStringAsFixed(1)}%'}'
                        '${x.testP == null ? '' : ' p=${x.testP!.toStringAsFixed(4)}'}'
                        ' · 발견 ${x.discoveredRound}회차'
                        '${x.liveEligible ? ' · 실전 반영 가능' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static String _pct(double? v) => v == null ? '-' : '${(v * 100).toStringAsFixed(2)}%';

  Widget _errorBox(String msg) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text(msg, style: TextStyle(fontSize: 12, color: Colors.red.shade900)),
      );
}
