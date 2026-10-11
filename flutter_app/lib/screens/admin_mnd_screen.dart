// 명당 가설 연구소 화면 — 자동 연구 결과 대시보드 (수동 실행 없음)
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/mnd_engine.dart';
import 'admin_region_research_screen.dart';

class AdminMndScreen extends StatefulWidget {
  final int trainingEndRound;
  const AdminMndScreen({super.key, required this.trainingEndRound});

  @override
  State<AdminMndScreen> createState() => _AdminMndScreenState();
}

class _AdminMndScreenState extends State<AdminMndScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  MndState? _state;
  Map<String, dynamic>? _activeSession; // 진행 중인 세션 (DB)
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _loadAll();
  }

  @override
  void didUpdateWidget(AdminMndScreen old) {
    super.didUpdateWidget(old);
    // 부모가 trainingEndRound를 0→실제값으로 업데이트하면 다시 로드
    if (old.trainingEndRound != widget.trainingEndRound &&
        widget.trainingEndRound > 0) {
      _loadAll();
      // 초기 연구가 없으면 자동 시작
      if (!_isRunning) {
        MndEngine.instance.autoStartIfNeeded(widget.trainingEndRound).ignore();
      }
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        MndEngine.instance.loadState(widget.trainingEndRound),
        MndEngine.instance.getActiveSession(),
      ]);
      if (!mounted) return;
      final state = results[0] as MndState;
      final session = results[1] as Map<String, dynamic>?;
      setState(() {
        _state = state;
        _activeSession = session;
        _loading = false;
      });
      // 진행 중이면 5초마다 자동 새로고침
      if (session != null) {
        _refreshTimer?.cancel();
        _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshProgress());
      }
      // 데이터도 없고 세션도 없으면 → 아직 초기 연구 미실행 → 자동 시작
      if (session == null && widget.trainingEndRound > 0) {
        final hasData = state.hypotheses.isNotEmpty || state.lastAnalyzedRound > 0;
        if (!hasData) {
          MndEngine.instance.autoStartIfNeeded(widget.trainingEndRound).then((_) {
            if (mounted) _loadAll(); // 세션 시작됐으면 다시 로드해서 진행 배너 표시
          }).ignore();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _refreshProgress() async {
    if (!mounted) return;
    try {
      final session = await MndEngine.instance.getActiveSession();
      if (!mounted) return;
      if (session == null) {
        // 완료됨: 상태 다시 로드
        _refreshTimer?.cancel();
        _refreshTimer = null;
        final state = await MndEngine.instance.loadState(widget.trainingEndRound);
        if (!mounted) return;
        setState(() { _state = state; _activeSession = null; });
      } else {
        setState(() { _activeSession = session; });
      }
    } catch (_) {}
  }

  bool get _isRunning => _activeSession != null;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildHeader(),
      if (_isRunning) _buildProgressBanner(),
      if (_error != null) _buildErrorBanner(),
      TabBar(
        controller: _tab,
        isScrollable: true,
        labelColor: const Color(0xFF1565C0),
        unselectedLabelColor: Colors.grey,
        indicatorColor: const Color(0xFF1565C0),
        tabs: const [
          Tab(text: '요약'),
          Tab(text: '명당 지속성'),
          Tab(text: '공간 밀집'),
          Tab(text: '지역 전이'),
          Tab(text: '신흥 명당'),
        ],
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(controller: _tab, children: [
                _SummaryTab(state: _state, isRunning: _isRunning, session: _activeSession),
                _PersistenceTab(state: _state),
                _SpatialTab(state: _state),
                _TransitionTab(state: _state),
                _EmergingTab(state: _state),
              ]),
      ),
    ]);
  }

  Widget _buildHeader() {
    final s = _state;
    final sess = _activeSession;
    String subtitle;
    if (sess != null) {
      final stage = sess['current_stage'] as String? ?? '연구 진행 중';
      subtitle = '자동 연구 중 · $stage';
    } else if (s != null && s.lastAnalyzedRound > 0) {
      subtitle = '${s.lastAnalyzedRound}회차 기준 · 가설 ${s.totalHypotheses}개';
    } else {
      subtitle = '초기 연구 대기 중 · 새 회차 등록 시 자동 시작';
    }

    return Container(
      color: const Color(0xFF0D47A1),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        const Icon(Icons.location_searching_rounded, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('명당 가설 연구소',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ),
        if (_isRunning)
          const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white60),
          ),
        const SizedBox(width: 6),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminRegionResearchScreen())),
          icon: const Icon(Icons.travel_explore_rounded, size: 16),
          label: const Text('전국 지역 연구', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _buildProgressBanner() {
    final sess = _activeSession;
    final stage = sess?['current_stage'] as String? ?? '분석 진행 중...';
    final sessType = sess?['session_type'] as String? ?? '';
    final label = sessType == 'initial_historical' ? '초기 전체 연구' : '증분 연구';
    return Container(
      color: const Color(0xFFFFF9C4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF5D4037))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('명당연구소 $label',
                style: const TextStyle(fontSize: 10, color: Color(0xFF5D4037), fontWeight: FontWeight.w700)),
            Text(stage, style: const TextStyle(fontSize: 11, color: Color(0xFF5D4037))),
          ]),
        ),
      ]),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      color: const Color(0xFFFFEBEE),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 14),
        const SizedBox(width: 8),
        Expanded(child: Text(_error!, style: const TextStyle(fontSize: 11, color: Colors.red))),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Tab 1: 요약 (연구소장 브리핑 + 전체 통계)
// ══════════════════════════════════════════════════════════

class _SummaryTab extends StatelessWidget {
  final MndState? state;
  final bool isRunning;
  final Map<String, dynamic>? session;
  const _SummaryTab({required this.state, required this.isRunning, required this.session});

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s == null || s.lastAnalyzedRound == 0) {
      return _emptyView();
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _researchStatusRow(s),
        const SizedBox(height: 12),
        _briefingCard(s),
        const SizedBox(height: 12),
        _statsRow(s),
        const SizedBox(height: 12),
        _volumeNote(),
        const SizedBox(height: 12),
        _theoryStatusCard(),
      ],
    );
  }

  Widget _researchStatusRow(MndState s) {
    return Row(children: [
      _statusBox('최근 연구', '${s.lastAnalyzedRound}회차', Colors.indigo),
      _statusBox('발견 가설', '${s.totalHypotheses}개', Colors.blue),
      _statusBox('검증 통과', '${s.acceptedCount}개', Colors.green),
      _statusBox('실전 반영', '${s.liveCount}개', Colors.deepPurple),
    ].map((w) => Expanded(child: w)).toList());
  }

  Widget _statusBox(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: TextStyle(fontSize: 9, color: color)),
      ]),
    );
  }

  Widget _emptyView() {
    if (isRunning) {
      final stage = session?['current_stage'] as String? ?? '연구 준비 중...';
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text('명당연구소 초기 연구 진행 중',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(stage, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          const Text('앱을 닫아도 다시 열면 자동으로 재개됩니다',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      );
    }
    return const Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.science_outlined, size: 48, color: Colors.grey),
        SizedBox(height: 16),
        Text('연구 데이터 없음', style: TextStyle(fontSize: 14, color: Colors.grey)),
        SizedBox(height: 8),
        Text('새 회차를 등록하면 자동으로 연구를 시작합니다',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }

  Widget _briefingCard(MndState s) {
    final b = s.latestBriefing;
    if (b == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.person_rounded, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          const Text('연구소장 브리핑', style: TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        Text(b.briefingText.replaceAll('주인님', '마스터'),
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.6)),
        if (b.highlights.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: b.highlights.take(4).map((h) => _chip(h['label'] as String? ?? '')).toList(),
          ),
        ],
      ]),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }

  Widget _statsRow(MndState s) {
    return Row(children: [
      _statBox('전체 가설', '${s.totalHypotheses}개', Colors.blue),
      _statBox('검증 중', '${s.observingCount + s.validatingCount}개', Colors.orange),
      _statBox('검증 통과', '${s.acceptedCount}개', Colors.green),
      _statBox('실전 반영', '${s.liveCount}개', Colors.purple),
    ].map((w) => Expanded(child: w)).toList());
  }

  Widget _statBox(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: TextStyle(fontSize: 9, color: color)),
      ]),
    );
  }

  Widget _volumeNote() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, size: 14, color: Colors.orange.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '판매량 데이터 미확보 — 모든 점수는 당첨 횟수 기반이며 실제 판매량으로 보정되지 않았습니다. '
            '당첨 확률이 높다는 의미가 아닙니다.',
            style: TextStyle(fontSize: 10, color: Colors.orange.shade800, height: 1.4),
          ),
        ),
      ]),
    );
  }

  Widget _theoryStatusCard() {
    return _card('연구이론 현황', [
      _theoryRow('A', '포아송 이상 탐지', '구현', Colors.green),
      _theoryRow('B', '공간 자기상관 (Moran\'s I)', '구현', Colors.green),
      _theoryRow('C', '마르코프 지역 전이', '구현', Colors.green),
      _theoryRow('D', '베이지안 계층모형', '구현 (A와 통합)', Colors.green),
      _theoryRow('E', '시공간 점과정 (Hawkes)', '데이터 부족 · 연구 보류', Colors.orange),
      _theoryRow('F', 'CUSUM 변화점 탐지', '구현', Colors.green),
    ]);
  }

  Widget _theoryRow(String id, String name, String status, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Center(child: Text(id, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(name, style: const TextStyle(fontSize: 12))),
        Text(status, style: TextStyle(fontSize: 10, color: color)),
      ]),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Tab 2: 명당 지속성 (Theory A + D)
// ══════════════════════════════════════════════════════════

class _PersistenceTab extends StatelessWidget {
  final MndState? state;
  const _PersistenceTab({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s == null || s.topAnomalies.isEmpty) {
      return const Center(child: Text('연구 데이터 없음 — 자동 연구 완료 후 표시됩니다', style: TextStyle(color: Colors.grey)));
    }
    final anomalies = s.topAnomalies;
    final hyps = s.hypotheses.where((h) => h.hypothesisType == 'persistence').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader('이상 배출 판매점 (포아송 기반, 판매량 미보정)', anomalies.length),
        const SizedBox(height: 8),
        ...anomalies.take(20).map(_anomalyCard),
        if (hyps.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionHeader('명당 지속성 가설', hyps.length),
          const SizedBox(height: 8),
          ...hyps.take(10).map(_hypCard),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Row(children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
        child: Text('$count건', style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
      ),
    ]);
  }

  Widget _anomalyCard(MndStoreAnomaly a) {
    final isAnomalous = a.anomalyStatus == 'anomalous';
    final isResearch = a.anomalyStatus == 'research';
    final statusColor = isAnomalous ? Colors.red : isResearch ? Colors.orange : Colors.grey;
    final statusLabel = isAnomalous ? '이상' : isResearch ? '주목' : '정상';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(statusLabel, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(a.storeName.isEmpty ? a.code : a.storeName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          Text('z=${a.poissonZScore.toStringAsFixed(1)}',
              style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        Text('${a.sido} ${a.sigungu} · 총 ${a.totalWins}회 배출',
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 4),
        Row(children: [
          _mini('베이지안 비율', '${(a.bayesianRate * 100).toStringAsFixed(3)}%'),
          const SizedBox(width: 12),
          _mini('기대값', a.expectedWins.toStringAsFixed(1)),
          const SizedBox(width: 12),
          _mini('최근 당첨', a.lastWinRound != null ? '${a.lastWinRound}회' : '-'),
        ]),
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('판매량 미보정 · 구매 추천 아님',
              style: TextStyle(fontSize: 9, color: Colors.orange, fontStyle: FontStyle.italic)),
        ),
      ]),
    );
  }

  Widget _mini(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
      Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _hypCard(MndHypothesis h) => _baseHypCard(h);
}

// ══════════════════════════════════════════════════════════
// Tab 3: 공간 밀집 (Theory B)
// ══════════════════════════════════════════════════════════

class _SpatialTab extends StatelessWidget {
  final MndState? state;
  const _SpatialTab({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s == null) {
      return const Center(child: Text('데이터 없음', style: TextStyle(color: Colors.grey)));
    }
    final sr = s.spatialResult;
    final hyps = s.hypotheses.where((h) => h.hypothesisType == 'spatial_cluster').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _moransCard(sr),
        const SizedBox(height: 12),
        if (sr != null && sr.hotspotSidos.isNotEmpty) ...[
          _clusterCard('고밀집 지역 (Hot Spots)', sr.hotspotSidos, Colors.red),
          const SizedBox(height: 8),
        ],
        if (sr != null && sr.coldspotSidos.isNotEmpty) ...[
          _clusterCard('저밀집 지역 (Cold Spots)', sr.coldspotSidos, Colors.blue),
          const SizedBox(height: 8),
        ],
        if (hyps.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...hyps.map(_baseHypCard),
        ],
        const SizedBox(height: 8),
        _researchNote('공간 자기상관 분석은 당첨 판매점의 지역 집중도를 측정합니다. '
            'Moran\'s I > 0: 비슷한 지역끼리 집중. I < 0: 분산. I = 0: 무작위. '
            '클러스터 발견이 미래 당첨 우위를 의미하지 않습니다.'),
      ],
    );
  }

  Widget _moransCard(MndSpatialResult? sr) {
    if (sr == null) {
      return _infoCard('Moran\'s I 분석', '분석 데이터 없음');
    }
    final significant = sr.moransP < 0.05;
    final color = significant ? (sr.moransI > 0 ? Colors.red : Colors.blue) : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('공간 자기상관 (Moran\'s I)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(significant ? '유의함' : '비유의', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _statItem('Moran\'s I', sr.moransI.toStringAsFixed(4)),
          _statItem('Z-score', sr.moransZ.toStringAsFixed(2)),
          _statItem('p-value', sr.moransP.toStringAsFixed(4)),
        ].map((w) => Expanded(child: w)).toList()),
        const SizedBox(height: 6),
        Text(
          sr.moransI > 0.2 ? '당첨 판매점이 특정 지역에 집중되는 경향이 있습니다.'
              : sr.moransI < -0.2 ? '당첨 판매점이 지역 간 분산되는 경향이 있습니다.'
              : '당첨 판매점 분포가 무작위에 가깝습니다.',
          style: TextStyle(fontSize: 11, color: color, height: 1.4),
        ),
      ]),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _clusterCard(String title, List<String> sidos, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6, runSpacing: 4,
          children: sidos.map((sido) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(sido, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          )).toList(),
        ),
      ]),
    );
  }

  Widget _infoCard(String title, String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, size: 14, color: Colors.grey),
        const SizedBox(width: 8),
        Text('$title: $msg', style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }

  Widget _researchNote(String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: Colors.blue.shade700, height: 1.4)),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Tab 4: 지역 전이 (Theory C)
// ══════════════════════════════════════════════════════════

class _TransitionTab extends StatelessWidget {
  final MndState? state;
  const _TransitionTab({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s == null || s.topTransitions.isEmpty) {
      return const Center(child: Text('연구 데이터 없음 — 자동 연구 완료 후 표시됩니다', style: TextStyle(color: Colors.grey)));
    }

    final byHorizon = <int, List<MndTransition>>{};
    for (final t in s.topTransitions) {
      byHorizon.putIfAbsent(t.horizon, () => []).add(t);
    }

    final hyps = s.hypotheses.where((h) => h.hypothesisType == 'transition').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _researchNote('이전 당첨 지역 이후 다음 당첨 지역으로의 전이 확률을 분석합니다. '
            '무작위 기준(1/17 ≈ 5.9%)보다 높은 전이를 탐지합니다. '
            '패턴이 발견되더라도 인과관계로 단정하지 않습니다.'),
        const SizedBox(height: 12),
        ...List.generate(6, (i) => i + 1).where((h) => byHorizon.containsKey(h)).expand((h) => [
          _horizonHeader(h, byHorizon[h]!.length),
          const SizedBox(height: 6),
          ...byHorizon[h]!.take(5).map(_transCard),
          const SizedBox(height: 10),
        ]),
        if (hyps.isNotEmpty) ...[
          const Divider(),
          const SizedBox(height: 8),
          const Text('전이 가설', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...hyps.take(10).map(_baseHypCard),
        ],
      ],
    );
  }

  Widget _horizonHeader(int h, int count) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFF1565C0), borderRadius: BorderRadius.circular(8)),
        child: Text('+$h회차 전이', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: 8),
      Text('$count개 패턴', style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  Widget _transCard(MndTransition t) {
    final liftColor = t.lift > 3 ? Colors.red : t.lift > 2 ? Colors.orange : Colors.blue;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: liftColor.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Expanded(
          child: Text('${t.fromSido} → ${t.toSido}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('lift ${t.lift.toStringAsFixed(1)}x',
              style: TextStyle(fontSize: 11, color: liftColor, fontWeight: FontWeight.w700)),
          Text('${t.observedCount}/${t.totalFrom}회 · p=${t.pValue.toStringAsFixed(3)}',
              style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ]),
      ]),
    );
  }

  Widget _researchNote(String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: Colors.blue.shade700, height: 1.4)),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Tab 5: 신흥 명당 (Theory F CUSUM)
// ══════════════════════════════════════════════════════════

class _EmergingTab extends StatelessWidget {
  final MndState? state;
  const _EmergingTab({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s == null || s.recentChangePoints.isEmpty) {
      return const Center(child: Text('감지된 변화점 없음', style: TextStyle(color: Colors.grey)));
    }
    final emerging = s.recentChangePoints.where((c) => c.interpretation == 'emerging_hotspot').toList();
    final cooling = s.recentChangePoints.where((c) => c.interpretation == 'cooling_down').toList();
    final hyps = s.hypotheses.where((h) => h.hypothesisType == 'emerging').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _note('CUSUM 알고리즘으로 판매점별 당첨 빈도 변화를 탐지합니다. '
            '\'신흥 명당\'은 최근 배출 빈도 상승 관찰 표현이며 당첨 확률 상승을 의미하지 않습니다.'),
        const SizedBox(height: 12),
        if (emerging.isNotEmpty) ...[
          _sectionTitle('상승 추세 판매점', emerging.length, Colors.green),
          const SizedBox(height: 8),
          ...emerging.take(10).map(_cpCard),
        ],
        if (cooling.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle('하락 추세 판매점', cooling.length, Colors.blue),
          const SizedBox(height: 8),
          ...cooling.take(5).map(_cpCard),
        ],
        if (hyps.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('신흥 명당 가설', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...hyps.take(10).map(_baseHypCard),
        ],
      ],
    );
  }

  Widget _sectionTitle(String title, int count, Color color) {
    return Row(children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text('$count건', style: TextStyle(fontSize: 10, color: color)),
      ),
    ]);
  }

  Widget _cpCard(MndChangePoint cp) {
    final isEmerging = cp.interpretation == 'emerging_hotspot';
    final color = isEmerging ? Colors.green : Colors.blue;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isEmerging ? Icons.trending_up : Icons.trending_down, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(cp.subjectId, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          Text('${cp.changePointRound}회차~', style: TextStyle(fontSize: 10, color: color)),
        ]),
        const SizedBox(height: 4),
        Text(
          '변화 전 ${(cp.preRate * 100).toStringAsFixed(3)}% → 변화 후 ${(cp.postRate * 100).toStringAsFixed(3)}% '
          '(${isEmerging ? '+' : ''}${((cp.postRate - cp.preRate) * 100).toStringAsFixed(3)}%p)',
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ]),
    );
  }

  Widget _note(String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: Colors.orange.shade800, height: 1.4)),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 공통: 가설 카드
// ══════════════════════════════════════════════════════════

Widget _baseHypCard(MndHypothesis h) {
  final statusColor = switch (h.status) {
    'accepted'   => Colors.green,
    'validating' => Colors.blue,
    'observing'  => Colors.orange,
    'weakened'   => Colors.red.shade300,
    'rejected'   => Colors.grey,
    _            => Colors.purple,
  };
  final statusLabel = switch (h.status) {
    'accepted'   => '검증 통과',
    'validating' => '검증 중',
    'observing'  => '관찰 중',
    'weakened'   => '약화',
    'rejected'   => '기각',
    'discovered' => '발견',
    _            => h.status,
  };
  final gateColor = h.gateStatus == 'pass' ? Colors.green : h.gateStatus == 'fail' ? Colors.red : Colors.grey;
  final gateLabel = h.gateStatus == 'pass' ? '실전 반영' : h.gateStatus == 'fail' ? '실전 미반영' : '검증 대기';

  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(statusLabel, style: TextStyle(fontSize: 9, color: statusColor, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: gateColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(gateLabel, style: TextStyle(fontSize: 9, color: gateColor, fontWeight: FontWeight.w700)),
        ),
        const Spacer(),
        Text('n=${h.sampleSize}', style: const TextStyle(fontSize: 9, color: Colors.grey)),
      ]),
      const SizedBox(height: 6),
      Text(
        '${h.subjectName.isEmpty ? h.subjectId : h.subjectName}${h.horizon != null ? ' · +${h.horizon}회차' : ''}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        'lift ${h.effectSize.toStringAsFixed(2)}x · '
        '${h.wfRounds > 0 ? 'WF ${h.wfSuccesses}/${h.wfRounds}회 (${((h.wfSuccessRate ?? 0) * 100).toStringAsFixed(0)}%)' : 'WF 미검증'}',
        style: const TextStyle(fontSize: 10, color: Colors.grey),
      ),
      if (h.gateStatus == 'pass')
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: const Text('추천판매점 반영',
              style: TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.w600)),
        ),
    ]),
  );
}
