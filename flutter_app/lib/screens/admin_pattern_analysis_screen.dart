// 패턴분석 화면 — 단일 RPA 예측 체계 표시
//
// 모든 추천/가설/제외/자리별/대안/Joint 항목은
// "활성 model_version + 학습 회차 + 대상 회차"의 통합 Prediction Result에서 옵니다.
//   · DB 저장 결과(rpa_prediction_results)가 있으면 그것을 그대로 표시
//   · 아직 저장 전(마이그레이션 미적용/생성 중)이면 같은 엔진 코드로 앱 내 계산하고 "미저장"으로 표시
// 실전 = Gate PASS만. 그 외는 '연구용' 또는 '통계 참고'로 구분합니다.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/lotto_winning_number.dart';
import '../services/admin_gate.dart';
import '../services/rpa_engine.dart';
import '../services/rpa_joint_engine.dart';
import '../services/rpa_number_core.dart';
import '../services/rpa_unified_prediction.dart';
import '../services/supabase_service.dart';
import '../widgets/engine_reflection_badge.dart';
import '../widgets/rpa_stored_prediction_card.dart';

/// 대상 회차(+horizon) 하나에 대한 화면 데이터
class _HorizonData {
  final RpaPredSnapshot? snap;     // 활성 버전 (DB 또는 앱 내 계산)
  final RpaPredSnapshot? legacy;   // 이전 버전 Snapshot (보존 표시용)
  final Map<String, RpaPredictionResult> results;
  final List<Map<String, dynamic>> conflicts;
  final bool fromDb;               // true = DB 저장 결과, false = 앱 내 계산(미저장)

  const _HorizonData({
    required this.snap,
    required this.legacy,
    required this.results,
    required this.conflicts,
    required this.fromDb,
  });

  RpaPredictionResult? operator [](String type) => results[type];
}

class AdminPatternAnalysisScreen extends StatefulWidget {
  const AdminPatternAnalysisScreen({super.key});
  @override
  State<AdminPatternAnalysisScreen> createState() => _AdminPatternAnalysisScreenState();
}

class _AdminPatternAnalysisScreenState extends State<AdminPatternAnalysisScreen>
    with SingleTickerProviderStateMixin {
  /// 관리자 여부 확인 후 생성 (관리자: 엔진 · 패턴 도구 / 비관리자: 패턴 도구만)
  TabController? _tabController;

  /// 안전장치: 비관리자가 열면 '엔진' 탭과 연구 상세(버전·Gate·가설)를 숨긴다
  bool _isAdmin = false;

  bool _isLoading = true;
  String? _error;
  List<LottoWinningNumber> _rounds = [];
  int _trainingEnd = 0;
  final Map<int, _HorizonData> _data = {};
  Map<String, dynamic>? _gateData;

  // 자동 생성 상태
  bool _ensureRunning = false;
  String? _ensureMessage;
  RpaEnsureStatus? _ensureStatus;

  int _selectedHorizon = 1;
  int _patternSubTab = 0;
  int _engineSubTab = 0;

  @override
  void initState() {
    super.initState();
    AdminGate.isAdmin().then((admin) {
      if (!mounted) return;
      setState(() {
        _isAdmin = admin;
        _tabController = TabController(length: admin ? 2 : 1, vsync: this);
      });
    });
    _load();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════
  // 데이터 로드
  // ══════════════════════════════════════════════════════════

  Future<void> _load() async {
    setState(() { _isLoading = _data.isEmpty; _error = null; });
    try {
      final rounds = await SupabaseService.getAllWinningNumbers();
      rounds.sort((a, b) => a.round.compareTo(b.round));
      final engine = RpaEngine.instance;
      final trainingEnd = await engine.resolveTrainingEndRound(rounds);
      final view = await engine.loadActiveView(trainingEnd);

      Map<String, dynamic>? gateData;
      try {
        gateData = await Supabase.instance.client
            .from('rpa_round_gate')
            .select()
            .order('round', ascending: false)
            .limit(1)
            .maybeSingle();
      } catch (_) {}

      final data = await _buildHorizonData(rounds, trainingEnd, view);
      if (!mounted) return;
      setState(() {
        _rounds = rounds;
        _trainingEnd = trainingEnd;
        _data
          ..clear()
          ..addAll(data);
        _gateData = gateData;
        _isLoading = false;
      });

      // 활성 버전 결과가 DB에 없으면 자동 생성 (버튼 없이)
      final complete = view.activeSnapshots.length >= 6 &&
          view.results.values.where((m) => m.length >= RpaPredictionType.all.length).length >= 6;
      // 결과가 없으면 앱에서 만들지 않는다 — 서버 파이프라인이 생성 (화면은 대기 안내만)
      if (!complete && mounted) {
        setState(() => _ensureMessage = '활성 엔진 결과를 서버가 생성하는 중입니다 (앱에서는 계산하지 않음)');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  /// DB 결과가 있으면 사용, 없으면 같은 엔진 코드로 앱 내 계산
  Future<Map<int, _HorizonData>> _buildHorizonData(
    List<LottoWinningNumber> rounds,
    int trainingEnd,
    RpaActiveView view,
  ) async {
    final out = <int, _HorizonData>{};
    final missing = <int>[];
    for (int h = 1; h <= 6; h++) {
      final snap = view.activeSnapshots[h];
      final res = view.results[h] ?? {};
      if (snap != null && res.length >= RpaPredictionType.all.length) {
        final conflicts = List<Map<String, dynamic>>.from(
            (res[RpaPredictionType.numberBase]?.evidence['conflicts'] as List?) ?? []);
        out[h] = _HorizonData(
            snap: snap, legacy: view.legacySnapshots[h], results: res,
            conflicts: conflicts, fromDb: true);
      } else {
        missing.add(h);
      }
    }
    if (missing.isEmpty || trainingEnd <= 0) return out;

    // ── 앱 내 계산 (미저장) ──────────────────────────────
    final training = rounds.where((d) => d.round <= trainingEnd).toList();
    final engine = RpaEngine.instance;
    final state = await engine.loadState();
    final hyps = await engine.loadHypothesisInputs();
    final live = hyps.map(rpaEvaluateHypothesis).where((v) => v.live).toList();
    final boost = live.isEmpty
        ? 0.0
        : (live.map((v) => v.h.currentWeight ?? 0).reduce((a, b) => a + b) / live.length * 0.3)
            .clamp(0.0, 0.3);
    final base = rpaComputeNumberBase(training,
        activeFlips: state.activeFlips,
        hypothesisBoost: boost,
        activeHypCount: live.length,
        boostHypothesisIds: live.map((v) => v.h.id).toList());
    final wf = await compute(_wfIsolate, {'data': training, 'end': trainingEnd});
    final jointGate = rpaJointGate(
      numberWfImprovement: JointModelEngine.numberGateWfImprovement,
      numberWfN: JointModelEngine.numberGateWfN,
    );

    for (final h in missing) {
      final target = trainingEnd + h;
      final jc = await JointModelEngine.instance.loadJointContextual(
            target, trainingEndRound: trainingEnd, modelVersion: kRpaActiveModelVersion) ??
          await JointModelEngine.instance.loadJointContextual(target, trainingEndRound: trainingEnd);
      final bundle = rpaBuildUnifiedBundle(RpaUnifiedInputs(
        targetRound: target,
        trainingEndRound: trainingEnd,
        runId: 'local',
        numberEvaluations: base.numberEvaluations,
        finalDirections: base.finalDirections,
        hypotheses: hyps,
        trainingData: training,
        walkForward: wf,
        jointContextual: jc,
        jointGate: jointGate,
      ));
      final snap = RpaPredSnapshot(
        id: 'local',
        targetRound: target,
        trainingEndRound: trainingEnd,
        theoryDirections: base.theoryDirections,
        finalDirections: base.finalDirections,
        correctionSnapshot: {'flips': base.flips},
        status: 'local',
        createdAt: DateTime.now(),
        horizon: h,
        candidateNumbers: base.candidates,
        recommendedSets: base.recommendedSets,
        numberEvaluations: base.numberEvaluations,
        modelVersion: kRpaActiveModelVersion,
      );
      out[h] = _HorizonData(
        snap: snap,
        legacy: view.legacySnapshots[h],
        results: {for (final r in bundle.results) r.predictionType: r},
        conflicts: bundle.conflicts,
        fromDb: false,
      );
    }
    return out;
  }

  _HorizonData? get _cur => _data[_selectedHorizon];
  int get _targetRound => _trainingEnd + _selectedHorizon;

  // ══════════════════════════════════════════════════════════
  // Scaffold
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final tc = _tabController;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      appBar: AppBar(
        title: Row(children: [
          const Text('패턴분석',
              style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(width: 8),
          if (_isAdmin) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.7)),
            ),
            child: const Text('엔진 v$kRpaActiveModelVersion',
                style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.w800)),
          ),
        ]),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        bottom: tc == null
            ? null
            : TabBar(
                controller: tc,
                indicatorColor: Colors.amber,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                tabs: _isAdmin
                    ? const [Tab(text: '엔진'), Tab(text: '패턴 도구')]
                    : const [Tab(text: '패턴 도구')],
              ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: () => _load()),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading || tc == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : Column(children: [
                  _buildContextBar(),
                  Expanded(
                    child: TabBarView(
                      controller: tc,
                      children: _isAdmin
                          ? [_buildEngineTab(), _buildPatternToolTab()]
                          : [_buildPatternToolTab()],
                    ),
                  ),
                ]),
    );
  }

  Widget _buildError() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.error_outline, size: 48, color: Colors.red),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
      ),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: () => _load(), child: const Text('다시 시도')),
    ],
  ));

  // ── 두 탭 공통: 회차 · 버전 · 상태 · 회차 선택 ──────────────
  Widget _buildContextBar() {
    // 비관리자: 회차 선택만 (버전·Gate·생성 상태 등 연구 상세 숨김)
    if (!_isAdmin) {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: _buildHorizonSelector(),
      );
    }
    final d = _cur;
    final nb = d?[RpaPredictionType.numberBase];
    final hyp = d?[RpaPredictionType.hypothesis];
    final ex = d?[RpaPredictionType.exclusion];
    final generated = d?.snap?.generatedAt ?? (d?.fromDb == true ? d?.snap?.createdAt : null);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              '$_trainingEnd회까지 학습 → $_targetRound회 예측 · v$kRpaActiveModelVersion',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)),
            ),
          ),
          _sourceChip(d),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (nb != null) _statusChip('번호', nb.isLive ? '실전' : '미통과', nb.isLive),
          if (hyp != null)
            _statusChip('가설', '실전 ${hyp.payload['live_count'] ?? 0} · 연구 ${hyp.payload['research_count'] ?? 0}',
                hyp.isLive),
          if (ex != null)
            _statusChip('제외', '실전 ${(ex.payload['live_excluded'] as List?)?.length ?? 0}개', ex.isLive),
          if (d != null)
            _statusChip('충돌', '${d.conflicts.length}건', d.conflicts.isEmpty),
          if (generated != null)
            Text('생성 ${_fmtTime(generated)}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF888888))),
        ]),
        if (_ensureRunning || (_ensureMessage != null && _ensureStatus != RpaEnsureStatus.upToDate)) ...[
          const SizedBox(height: 6),
          _ensureBanner(),
        ],
        const SizedBox(height: 8),
        _buildHorizonSelector(),
      ]),
    );
  }

  Widget _sourceChip(_HorizonData? d) {
    final (label, color) = d == null
        ? ('결과 없음', Colors.grey)
        : d.fromDb
            ? ('DB 저장 결과', const Color(0xFF2E7D32))
            : ('앱 내 계산 · 미저장', Colors.orange.shade800);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }

  Widget _statusChip(String label, String value, bool good) {
    final color = good ? const Color(0xFF2E7D32) : const Color(0xFF8D6E63);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label $value',
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }

  Widget _ensureBanner() {
    final migration = _ensureStatus == RpaEnsureStatus.migrationRequired;
    final failed = _ensureStatus == RpaEnsureStatus.failed;
    final color = migration || failed ? Colors.deepOrange : const Color(0xFF1565C0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        if (_ensureRunning)
          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
        else
          Icon(migration || failed ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(
          migration
              ? '${_ensureMessage ?? ''}\n지금 보이는 결과는 같은 엔진 코드로 앱에서 계산한 값이며 DB에 저장되지 않았습니다.'
              : _ensureMessage ?? '',
          style: TextStyle(fontSize: 10, color: color, height: 1.4),
        )),
      ]),
    );
  }

  Widget _buildHorizonSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: List.generate(6, (i) {
        final h = i + 1;
        final selected = h == _selectedHorizon;
        final d = _data[h];
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => setState(() => _selectedHorizon = h),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF1565C0) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: selected ? const Color(0xFF1565C0) : const Color(0xFFDDE0E8)),
              ),
              child: Column(children: [
                Text('${_trainingEnd + h}회',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : const Color(0xFF333333))),
                Text(d == null ? '+$h · 없음' : d.fromDb ? '+$h · 저장' : '+$h · 미저장',
                    style: TextStyle(fontSize: 9,
                        color: selected ? Colors.white70 : const Color(0xFF1565C0))),
              ]),
            ),
          ),
        );
      })),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 탭0: 엔진
  // ══════════════════════════════════════════════════════════

  Widget _buildEngineTab() {
    return Column(children: [
      Container(
        color: const Color(0xFF1565C0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          _subTabBtn('번호추천', 0, isEngine: true),
          const SizedBox(width: 10),
          _subTabBtn('당첨흐름', 1, isEngine: true),
        ]),
      ),
      Expanded(child: IndexedStack(
        index: _engineSubTab,
        children: [_buildEnginePredTab(), _buildFlowTab()],
      )),
    ]);
  }

  Widget _buildEnginePredTab() {
    final d = _cur;
    final snap = d?.snap;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (d == null || snap == null) ...[
          _buildNoSnapCard(),
          const SizedBox(height: 12),
          RpaStoredPredictionCard(targetRound: _targetRound),
        ] else ...[
          if (d.fromDb)
            EngineReflectionBadge(
              trainingRound: snap.trainingEndRound,
              targetRound: snap.targetRound,
              modelVersion: snap.modelVersion,
            ),
          if (d.fromDb) const SizedBox(height: 12),
          // 최종 결과 카드 하나로 통합: 기존 '추천 조합' 카드는 중복이라 제거하고,
          // DB에 실제 저장된 활성 엔진 예측 + 최종 추천번호를 이 카드에서 표시 (해당 회차 행만)
          RpaStoredPredictionCard(targetRound: _targetRound),
          const SizedBox(height: 12),
          if (d.legacy != null) ...[
            _buildLegacyCard(d),
            const SizedBox(height: 12),
          ],
          if (d.conflicts.isNotEmpty) ...[
            _buildConflictCard(d),
            const SizedBox(height: 12),
          ],
          if (snap.numberEvaluations.isNotEmpty) ...[
            _buildNumberClassificationCard(snap),
            const SizedBox(height: 12),
          ],
          _buildJointContextualCard(d),
          const SizedBox(height: 12),
          _buildProvenanceCard(d),
          const SizedBox(height: 12),
          _buildIndicatorDirectionCard(snap),
          const SizedBox(height: 12),
          if (snap.candidateNumbers.isNotEmpty) _buildCandidateNumbersCard(snap),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  // (기존 '추천 조합' 카드는 랜덤확률분석엔진 추천번호 카드와 중복이라 제거됨 — RpaStoredPredictionCard 참조)

  Widget _buildLegacyCard(_HorizonData d) {
    final legacy = d.legacy!;
    final same = legacy.recommendedSets.toString() == d.snap!.recommendedSets.toString();
    return _card(
      title: '이전 버전 v${legacy.modelVersion} Snapshot (보존)',
      icon: Icons.history_rounded,
      iconColor: Colors.grey,
      tag: _tag('기록 보존 · 실전 아님', Colors.grey),
      subtitle: same
          ? '현재 버전과 동일한 조합입니다.'
          : '${kRpaModelVersionNotes[legacy.modelVersion] ?? ''}. '
              '번호 점수·순위는 같은지 검증 도구(tool/verify_unified_prediction.dart)로 확인합니다.',
      children: legacy.recommendedSets.asMap().entries.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(width: 22, child: Text('${e.key + 1}',
              style: const TextStyle(fontSize: 11, color: Colors.grey))),
          ...e.value.map((n) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Opacity(opacity: 0.6, child: _ball(n, small: true)),
          )),
        ]),
      )).toList(),
    );
  }

  Widget _buildConflictCard(_HorizonData d) {
    return _card(
      title: '추천 ↔ 제외 충돌 ${d.conflicts.length}건',
      icon: Icons.compare_arrows_rounded,
      iconColor: Colors.deepOrange,
      subtitle: '충돌 번호를 숨기거나 삭제하지 않고 이유를 표시합니다.',
      children: d.conflicts.map((c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ball(c['number'] as int, small: true),
          const SizedBox(width: 8),
          Expanded(child: Text('${c['reason']}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF444444), height: 1.4))),
        ]),
      )).toList(),
    );
  }

  // ── Joint Contextual ────────────────────────────────────
  Widget _buildJointContextualCard(_HorizonData d) {
    final j = d[RpaPredictionType.jointContextual];
    if (j == null || j.payload['available'] != true) {
      return _card(
        title: 'Joint Contextual 번호',
        icon: Icons.join_inner_rounded,
        iconColor: const Color(0xFF7B1FA2),
        tag: _tag('연구용', Colors.orange.shade700),
        subtitle: '이 회차의 Joint Contextual 결과가 아직 없습니다. 엔진 처리 시 자동 생성됩니다.',
        children: const [],
      );
    }
    final live = j.isLive;
    final sets = ((j.payload['joint_sets'] as List?) ?? [])
        .map((s) => List<int>.from(s as List))
        .toList();
    final baseFirst = d.snap!.recommendedSets.isNotEmpty ? d.snap!.recommendedSets.first.toSet() : <int>{};
    final imp = (j.evidence['number_wf_improvement'] as num?)?.toDouble() ?? 0;
    final n = j.evidence['number_wf_n'];
    final srcVer = j.payload['source_model_version'];
    final subtitle = '예측 지역: ${j.payload['predicted_region'] ?? '-'}'
        '${srcVer != null && '$srcVer' != kRpaActiveModelVersion ? ' · 원본 v$srcVer (활성 버전 Joint 미생성)' : ''}';

    if (!live) {
      // Gate FAIL — 실전 미반영: 기본 숫자 노출 금지, 접힌 연구 현황만 표시
      return _card(
        title: 'Joint Contextual 번호',
        icon: Icons.join_inner_rounded,
        iconColor: const Color(0xFF7B1FA2),
        tag: _tag('연구용 · 실전 미반영', Colors.orange.shade700),
        subtitle: subtitle,
        children: [
          Text(
            '번호 Joint Gate: Walk-Forward 개선 ${(imp * 100).toStringAsFixed(2)}% (n=$n) — 미통과\n'
            '측정 출처: ${j.evidence['number_gate_source'] ?? '-'}',
            style: TextStyle(fontSize: 10, color: Colors.orange.shade800, height: 1.5),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: ExpansionTile(
              dense: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: const Text('연구 현황 자세히 보기',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF5D4037))),
              subtitle: const Text('Gate 미통과 · 실전 미반영 · 연구용 번호 포함',
                  style: TextStyle(fontSize: 10, color: Color(0xFF8D6E63))),
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '아래 번호는 연구용이며 구매 추천 아님',
                    style: TextStyle(fontSize: 10, color: Color(0xFF8D6E63), fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 8),
                ...sets.map((s) => _numberRow(s, Colors.orange.shade400, baseFirst)),
                const SizedBox(height: 6),
                Text(
                  'Store Gate: ${_gateLabel(j.evidence['store_gate'])} (검증 ${j.evidence['store_n']}건) · '
                  'Spatial: ${_gateLabel(j.evidence['spatial_gate'])} · Temporal: ${_gateLabel(j.evidence['temporal_gate'])}\n'
                  '${j.evidence['temporal_note'] ?? ''}',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Gate PASS — 실전 반영
    return _card(
      title: 'Joint Contextual 번호',
      icon: Icons.join_inner_rounded,
      iconColor: const Color(0xFF7B1FA2),
      tag: _tag('판매점별 실전 반영', const Color(0xFF388E3C)),
      subtitle: subtitle,
      children: [
        Text(
          '번호 Joint Gate: Walk-Forward 개선 ${(imp * 100).toStringAsFixed(2)}% (n=$n) — 통과\n'
          '측정 출처: ${j.evidence['number_gate_source'] ?? '-'}',
          style: const TextStyle(fontSize: 10, color: Color(0xFF388E3C), height: 1.5),
        ),
        const SizedBox(height: 8),
        ...sets.map((s) => _numberRow(s, const Color(0xFF7B1FA2), baseFirst)),
        const SizedBox(height: 6),
        Text(
          'Store Gate: ${_gateLabel(j.evidence['store_gate'])} (검증 ${j.evidence['store_n']}건) · '
          'Spatial: ${_gateLabel(j.evidence['spatial_gate'])} · Temporal: ${_gateLabel(j.evidence['temporal_gate'])}\n'
          '${j.evidence['temporal_note'] ?? ''}',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.5),
        ),
      ],
    );
  }

  String _gateLabel(dynamic g) => switch (g) {
        'pass' => '통과',
        'fail' => '미통과',
        _ => '미평가',
      };

  String _snapStatusLabel(String status) => switch (status) {
        'pending'    => '예측 완료 · 검증 대기',
        'verified'   => '검증 완료',
        'processing' => '처리 중',
        'failed'     => '처리 실패',
        _            => status,
      };

  Widget _numberRow(List<int> nums, Color color, Set<int> baseSet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: nums.map((n) {
        final isNew = baseSet.isNotEmpty && !baseSet.contains(n);
        return Container(
          margin: const EdgeInsets.only(right: 6),
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: isNew ? color : color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Center(child: Text('$n',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: isNew ? Colors.white : color))),
        );
      }).toList()),
    );
  }

  // ── 1~45 번호 평가 ──────────────────────────────────────
  Widget _buildNumberClassificationCard(RpaPredSnapshot snap) {
    final evals = snap.numberEvaluations;
    List<Map<String, dynamic>> of(String c) => evals.where((e) => e['classification'] == c).toList();
    return _card(
      title: '엔진 번호 평가 (1~45)',
      icon: Icons.analytics_rounded,
      iconColor: const Color(0xFF1565C0),
      subtitle: '숫자는 엔진 내부 점수(0~1, 지표 조건 일치 회차 출현 빈도 정규화)이며 확률이 아닙니다. 번호를 누르면 근거를 봅니다.',
      children: [
        _classRow('핵심', of('CORE'), const Color(0xFFE53935), const Color(0xFFFFEBEE)),
        _classRow('강세', of('STRONG'), const Color(0xFF1565C0), const Color(0xFFE3F2FD)),
        _classRow('보조', of('SUPPORT'), const Color(0xFF2E7D32), const Color(0xFFE8F5E9)),
        _classRow('약세', of('WEAK'), const Color(0xFF9E9E9E), const Color(0xFFF5F5F5)),
        _classRow('약세 후보', of('EXCLUDE_CANDIDATE'), const Color(0xFF616161), const Color(0xFFF5F5F5)),
      ],
    );
  }

  Widget _classRow(String label, List<Map<String, dynamic>> entries, Color color, Color bg) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 56,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8)),
          child: Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Wrap(
          spacing: 6, runSpacing: 4,
          children: entries.map((e) {
            final n = e['n'] as int;
            final score = (e['final_score'] as num).toDouble();
            return GestureDetector(
              onTap: () => _showNumberEvidence(e, color),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.3))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _ball(n, small: true),
                  Text(score.toStringAsFixed(2),
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: color)),
                ]),
              ),
            );
          }).toList(),
        )),
      ]),
    );
  }

  void _showNumberEvidence(Map<String, dynamic> eval, Color classColor) {
    final evidence = eval['evidence'] as Map?;
    final n = eval['n'] as int;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _ball(n),
              const SizedBox(width: 12),
              Expanded(child: Text('$n번 · ${eval['classification']} · ${eval['rank']}위',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white))),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ]),
            const SizedBox(height: 12),
            if (evidence != null) ...[
              _evidenceRow('지표 일치 회차 등장', '${evidence['match_rounds']}회 / ${evidence['total_match_rounds']}회'),
              _evidenceRow('최근 1/3 회차 등장', '${evidence['recent_match_rounds']}회 / ${evidence['recent_window_rounds']}회 (2배 가중)'),
              _evidenceRow('학습 전체 회차', '${evidence['total_training_rounds']}회'),
              _evidenceRow('내부 원점수', '${eval['raw_score']}'),
              _evidenceRow('가설 보정',
                  (evidence['active_hyp_count'] as int? ?? 0) > 0
                      ? '${evidence['hyp_boost']} (Gate 통과 가설 ${evidence['active_hyp_count']}개)'
                      : '없음 (Gate 통과 가설 0개)'),
              _evidenceRow('내부 최종 점수', '${eval['final_score']}'),
            ] else
              const Text('이 Snapshot에는 근거 데이터가 없습니다.',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 8),
            const Text('점수는 순위 산정용 내부 값이며 당첨 확률이 아닙니다.',
                style: TextStyle(fontSize: 10, color: Colors.white38)),
          ],
        ),
      ),
    );
  }

  Widget _evidenceRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 130, child: Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8899AA)))),
          Expanded(child: Text(value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white))),
        ]),
      );

  Widget _buildNoSnapCard() {
    final gate = _gateData;
    final gateStatus = gate?['engine_status'] as String? ?? '';
    final hasStore = gate?['has_store_data'] as bool? ?? false;
    String msg;
    if (_ensureRunning) {
      msg = '활성 엔진 결과를 자동 생성하는 중입니다.';
    } else if (gateStatus == 'processing') {
      msg = '엔진 처리 중입니다. 완료되면 자동으로 표시됩니다.';
    } else if (!hasStore && gate != null) {
      msg = '당첨판매점 데이터 대기 중 — 수집되면 엔진이 자동 실행됩니다.';
    } else {
      msg = '$_targetRound회 예측 결과가 없습니다. ${_ensureMessage ?? ''}';
    }
    return _card(
      title: '$_targetRound회 예측 없음',
      icon: Icons.hourglass_empty_rounded,
      iconColor: Colors.grey,
      subtitle: msg,
      children: const [],
    );
  }

  Widget _buildProvenanceCard(_HorizonData d) {
    final snap = d.snap!;
    final nb = d[RpaPredictionType.numberBase];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.verified_rounded, color: Colors.white70, size: 14),
          const SizedBox(width: 6),
          const Text('출처', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const Spacer(),
          Text(d.fromDb ? _snapStatusLabel(snap.status) : '앱 내 계산',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _provItem('학습 기준', '${snap.trainingEndRound}회'),
          _provItem('예측 대상', '${snap.targetRound}회'),
          _provItem('model_version', 'v${snap.modelVersion}'),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _provItem('Gate', nb?.gateStatus ?? '-'),
          _provItem('검증', nb?.validationStatus ?? '-'),
          _provItem('run_id', _short(nb?.runId ?? snap.runId)),
        ]),
      ]),
    );
  }

  Widget _provItem(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _buildIndicatorDirectionCard(RpaPredSnapshot snap) {
    final dirs = snap.finalDirections.isNotEmpty ? snap.finalDirections : snap.theoryDirections;
    if (dirs.isEmpty) return const SizedBox.shrink();
    final wf = _cur?[RpaPredictionType.alternative]?.evidence['direction_rule_validation'] as Map?;
    return _card(
      title: '지표 방향 예측',
      icon: Icons.compass_calibration_rounded,
      iconColor: const Color(0xFF1565C0),
      subtitle: wf == null
          ? '엔진이 예측한 각 지표의 방향'
          : '과거검증: 방향 적중 ${wf['correct']}/${wf['total']} (랜덤 기대 ${wf['expected']}, z=${wf['z']})',
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: dirs.entries.map((e) {
          final label = rpaIndicatorLabels[e.key] ?? e.key;
          final (bg, fg, icon) = switch (e.value) {
            'above' => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32), Icons.arrow_upward_rounded),
            'below' => (const Color(0xFFFFEBEE), const Color(0xFFC62828), Icons.arrow_downward_rounded),
            _ => (const Color(0xFFF5F5F5), const Color(0xFF757575), Icons.remove_rounded),
          };
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 12, color: fg),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w700)),
            ]),
          );
        }).toList()),
      ],
    );
  }

  Widget _buildCandidateNumbersCard(RpaPredSnapshot snap) {
    final c = snap.candidateNumbers;
    final maxScore = (c.first['s'] as num).toDouble();
    return _card(
      title: '후보 번호 (상위 18)',
      icon: Icons.filter_list_rounded,
      iconColor: const Color(0xFF6A1B9A),
      subtitle: '엔진 내부 점수 순위 (동점은 번호순). 막대는 1위 대비 상대값입니다.',
      children: c.take(18).toList().asMap().entries.map((entry) {
        final s = (entry.value['s'] as num).toDouble();
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(width: 22, child: Text('${entry.key + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500))),
            const SizedBox(width: 6),
            _ball(entry.value['n'] as int, small: true),
            const SizedBox(width: 8),
            Expanded(child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: maxScore > 0 ? s / maxScore : 0, minHeight: 8,
                backgroundColor: const Color(0xFFF0F2F8),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFAB47BC)),
              ),
            )),
            const SizedBox(width: 8),
            Text(s.toStringAsFixed(3), style: const TextStyle(fontSize: 10, color: Color(0xFF555555))),
          ]),
        );
      }).toList(),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 탭1: 패턴 도구 (자리별 패턴 · 대안 · 제외 / 가설)
  // ══════════════════════════════════════════════════════════

  Widget _buildPatternToolTab() {
    return Column(children: [
      Container(
        color: const Color(0xFF1565C0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          _subTabBtn('자리별 · 대안 · 제외', 0),
          if (_isAdmin) ...[
            const SizedBox(width: 10),
            _subTabBtn('가설', 1),
          ],
        ]),
      ),
      Expanded(child: IndexedStack(
        index: _isAdmin ? _patternSubTab : 0,
        children: [_buildPositionalTab(), _buildHypothesisTab()],
      )),
    ]);
  }

  Widget _buildPositionalTab() {
    final d = _cur;
    if (d == null) return Center(child: Text('$_targetRound회 결과 없음'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPositionalCard(d),
        const SizedBox(height: 12),
        _buildAlternativeCard(d),
        const SizedBox(height: 12),
        _buildExclusionCard(d),
        if (d.conflicts.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildConflictCard(d),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildPositionalCard(_HorizonData d) {
    final p = d[RpaPredictionType.positional];
    if (p == null) return const SizedBox.shrink();
    final positions = (p.payload['positions'] as List).cast<Map>();
    final wf = p.evidence['walk_forward'] as Map;
    return _card(
      title: '자리별 패턴',
      icon: Icons.grid_view_rounded,
      iconColor: const Color(0xFF1565C0),
      tag: p.isLive ? _tag('보조 Evidence', const Color(0xFF2E7D32)) : _tag('통계 참고', Colors.blueGrey),
      subtitle: '직전 회차 각 자리 번호의 후속·차이·끝자리 통계. 엔진 순위를 함께 표시합니다.',
      children: [
        ...positions.map((pos) {
          final ranked = (pos['ranked'] as List).cast<Map>();
          final top = ranked.isNotEmpty ? ranked.first : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(width: 34, child: Text('${pos['position']}번',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF888888)))),
              Text('기준 ${pos['ref']} →', style: const TextStyle(fontSize: 10, color: Color(0xFF999999))),
              const SizedBox(width: 6),
              if (top != null) ...[
                _ball(top['n'] as int, small: true),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  '통계점수 ${(top['stat_score'] as num).toStringAsFixed(2)} · 엔진 ${top['engine_rank']}위 ${_classKo(top['engine_class'])}',
                  style: TextStyle(fontSize: 10,
                      color: _isWeak(top['engine_class']) ? Colors.deepOrange : const Color(0xFF555555)),
                )),
              ],
            ]),
          );
        }),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF5F7FA), borderRadius: BorderRadius.circular(10)),
          child: Text(
            'Historical Walk-Forward (n=${wf['n']}, 미래정보 없음)\n'
            '자리별 1위 6개 평균 적중 ${wf['positional_top6_hits']}개 vs 엔진 상위 6개 ${wf['base_top6_hits']}개 '
            '(차이 ${wf['diff_mean']}, t=${wf['t']})\n'
            '${p.isLive ? '→ 개선 검증됨: 보조 Evidence로 사용' : '→ Number Base 대비 개선 없음: 실전 추천에 반영하지 않는 연구 도구'}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF555555), height: 1.5),
          ),
        ),
      ],
    );
  }

  Widget _buildAlternativeCard(_HorizonData d) {
    final a = d[RpaPredictionType.alternative];
    if (a == null) return const SizedBox.shrink();
    final sets = (a.payload['sets'] as List).cast<Map>();
    final dirApplied = a.payload['direction_rule_applied'] == true;
    return _card(
      title: '대안 조합',
      icon: Icons.alt_route_rounded,
      iconColor: const Color(0xFF00897B),
      tag: a.isLive
          ? (d.fromDb ? _tag('엔진 반영', const Color(0xFF00897B)) : _tag('엔진 계산 · 미저장', Colors.orange.shade800))
          : _tag('연구용', Colors.grey),
      subtitle: '활성 Number 후보 점수로 만든 기본 조합 다음 순위 조합 (난수 없음). '
          '${dirApplied ? '지표 방향 규칙(과거검증 통과) 적용.' : '지표 방향 규칙 미검증 → 미적용.'}',
      children: sets.isEmpty
          ? [const Text('조건을 만족하는 대안 조합 없음', style: TextStyle(fontSize: 11, color: Colors.grey))]
          : sets.asMap().entries.map((e) {
              final nums = List<int>.from(e.value['numbers'] as List);
              final overlap = (e.value['overlap_with_base'] as List).join('/');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(width: 22, child: Text('${e.key + 1}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF00897B)))),
                  ...nums.map((n) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _ball(n, small: true),
                  )),
                  const Spacer(),
                  Text('기본과 중복 $overlap',
                      style: const TextStyle(fontSize: 9, color: Color(0xFF999999))),
                ]),
              );
            }).toList(),
    );
  }

  Widget _buildExclusionCard(_HorizonData d) {
    final x = d[RpaPredictionType.exclusion];
    if (x == null) return const SizedBox.shrink();
    final live = List<int>.from(x.payload['live_excluded'] as List? ?? []);
    final research = List<int>.from(x.payload['research_excluded'] as List? ?? []);
    final rates = (x.evidence['walk_forward_class_rates'] as Map?) ?? {};
    String rateLine(String cls, String label) {
      final r = rates[cls] as Map?;
      if (r == null) return '';
      return '$label 실제 출현율 ${((r['rate'] as num) * 100).toStringAsFixed(1)}% '
          '(랜덤 13.3%, z=${r['z']})';
    }
    return _card(
      title: '제외 후보',
      icon: Icons.block_rounded,
      iconColor: const Color(0xFF6D4C41),
      tag: live.isNotEmpty ? _tag('실전 제외 ${live.length}개', const Color(0xFF6D4C41)) : _tag('실전 제외 없음', Colors.grey),
      subtitle: '엔진 WEAK/EXCLUDE_CANDIDATE 번호를 과거검증으로 확인한 결과입니다. 근거 없이 번호를 삭제하지 않습니다.',
      children: [
        Text(live.isEmpty ? '실전 제외번호 없음' : '실전 제외번호',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF333333))),
        if (live.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: live.map((n) => _ball(n, small: true)).toList()),
        ],
        const SizedBox(height: 10),
        const Text('연구용 제외 후보 (엔진 약세 · 미검증)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF777777))),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4,
            children: research.map((n) => Opacity(opacity: 0.55, child: _ball(n, small: true))).toList()),
        const SizedBox(height: 8),
        Text('${rateLine('WEAK', '약세(31~40위)')}\n${rateLine('EXCLUDE_CANDIDATE', '약세 후보(41~45위)')}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF777777), height: 1.5)),
      ],
    );
  }

  // ── 가설 ────────────────────────────────────────────────
  Widget _buildHypothesisTab() {
    final d = _cur;
    final h = d?[RpaPredictionType.hypothesis];
    if (d == null || h == null) return Center(child: Text('$_targetRound회 결과 없음'));
    final groups = (h.payload['groups'] as List).cast<Map>();
    final liveCount = h.payload['live_count'] as int? ?? 0;
    final researchCount = h.payload['research_count'] as int? ?? 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          title: '가설 반영 현황',
          icon: Icons.science_rounded,
          iconColor: Colors.deepPurple,
          tag: liveCount > 0 ? _tag('실전 $liveCount', const Color(0xFF2E7D32)) : _tag('실전 0', Colors.grey),
          subtitle: liveCount == 0
              ? '현재 실전 반영 가능한 가설 없음. 연구용 $researchCount개 — 자동 연구는 새 회차마다 계속됩니다.'
              : '실전 $liveCount개 · 연구용 $researchCount개',
          children: [
            Text(
              '실전 자격: 검증 단계 상태 + 실제 미래검증 ${RpaHypothesisGateConfig.minFutureVerifications}회 이상 + '
              '랜덤 대비 유의(z≥${RpaHypothesisGateConfig.minFutureZ}) + Monte Carlo p≤${RpaHypothesisGateConfig.maxMonteCarloP}\n'
              '가설은 번호를 직접 고르지 않으며, 기본 조합이 가설 방향과 일치하는지만 표시합니다.',
              style: const TextStyle(fontSize: 10, color: Color(0xFF666666), height: 1.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...groups.map(_hypothesisGroupCard),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _hypothesisGroupCard(Map g) {
    final members = (g['members'] as List).cast<Map>();
    final liveCount = g['live_count'] as int? ?? 0;
    final supported = List<int>.from(g['supported_base_sets'] as List? ?? []);
    final horizons = (g['horizons'] as List).join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.15)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          title: Row(children: [
            Expanded(child: Text('${g['label']}  ·  가설 ${g['hypothesis_count']}개',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
            liveCount > 0 ? _tag('실전 $liveCount', const Color(0xFF2E7D32)) : _tag('연구용', Colors.orange.shade700),
          ]),
          subtitle: Text(
            '대상 +$horizons회'
            '${g['applies_to_target'] == true ? ' (이 회차 포함)' : ''}'
            '${supported.isNotEmpty ? ' · 기본 조합 ${supported.join(', ')}번이 같은 방향' : ''}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF777777)),
          ),
          children: members.map((m) => Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m['evidence']}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF333333))),
              Text(
                '상태 ${m['status']} · 미래검증 ${m['future']} (z=${m['future_z']}) · '
                '과거 성공률 ${((m['historical_success_rate'] as num) * 100).toStringAsFixed(1)}% '
                '(랜덤 ${((m['random_baseline'] as num) * 100).toStringAsFixed(1)}%)',
                style: const TextStyle(fontSize: 10, color: Color(0xFF666666)),
              ),
              ...((m['failed_reasons'] as List?) ?? []).map((r) => Text('· $r',
                  style: TextStyle(fontSize: 10, color: Colors.orange.shade800))),
            ]),
          )).toList(),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 당첨흐름 (실제 과거 데이터 — 예측 아님)
  // ══════════════════════════════════════════════════════════

  Widget _buildFlowTab() {
    final recent = (_rounds.length > 20 ? _rounds.sublist(_rounds.length - 20) : List.of(_rounds))
      ..sort((a, b) => b.round.compareTo(a.round));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionLabel('당첨흐름', Icons.trending_up_rounded, const Color(0xFF00897B)),
        const SizedBox(height: 4),
        Text('최근 ${recent.length}회차 실제 당첨번호 (통계 참고 · 예측 아님)',
            style: const TextStyle(fontSize: 11, color: Color(0xFF888888))),
        const SizedBox(height: 16),
        _flowCard(recent),
        const SizedBox(height: 16),
        _trendRow(recent),
        const SizedBox(height: 16),
        _zoneFlowCard(recent),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _flowCard(List<LottoWinningNumber> recent) {
    return _card(
      title: '번호 합계 흐름',
      icon: Icons.functions_rounded,
      iconColor: const Color(0xFF1565C0),
      subtitle: '최근 회차 실제 합계',
      children: recent.take(10).map((r) {
        final nums = [...r.numbers]..sort();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 42, child: Text('${r.round}회',
                style: const TextStyle(fontSize: 11, color: Color(0xFF888888), fontWeight: FontWeight.w600))),
            Expanded(child: Row(children: nums.map((n) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _ball(n, small: true),
            )).toList())),
            Text('합${nums.fold(0, (a, b) => a + b)}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF1565C0), fontWeight: FontWeight.w700)),
          ]),
        );
      }).toList(),
    );
  }

  Widget _trendRow(List<LottoWinningNumber> recent) {
    return _card(
      title: '홀짝 · 저고 추세',
      icon: Icons.stacked_bar_chart_rounded,
      iconColor: const Color(0xFFE65100),
      subtitle: '파랑 = 홀수 개수, 주황 = 22 이하 개수',
      children: recent.take(10).map((r) {
        final odd = r.numbers.where((n) => n % 2 == 1).length;
        final low = r.numbers.where((n) => n <= 22).length;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 42, child: Text('${r.round}회',
                style: const TextStyle(fontSize: 11, color: Color(0xFF888888), fontWeight: FontWeight.w600))),
            Expanded(child: _miniBar(odd, const Color(0xFF1565C0))),
            const SizedBox(width: 8),
            Expanded(child: _miniBar(low, const Color(0xFFE65100))),
          ]),
        );
      }).toList(),
    );
  }

  Widget _miniBar(int count, Color color) => Row(children: List.generate(6, (i) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          height: 14,
          decoration: BoxDecoration(
            color: i < count ? color : const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      )));

  Widget _zoneFlowCard(List<LottoWinningNumber> recent) {
    const zoneColors = [
      Color(0xFFFFB300), Color(0xFF42A5F5), Color(0xFFEF5350), Color(0xFF9E9E9E), Color(0xFF66BB6A),
    ];
    return _card(
      title: '번호 구간 분포 흐름',
      icon: Icons.view_week_rounded,
      iconColor: const Color(0xFF66BB6A),
      subtitle: '1~9 / 10~19 / 20~29 / 30~39 / 40~45',
      children: recent.take(10).map((r) {
        final zones = [0, 0, 0, 0, 0];
        for (final n in r.numbers) {
          zones[n <= 9 ? 0 : n <= 19 ? 1 : n <= 29 ? 2 : n <= 39 ? 3 : 4]++;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 42, child: Text('${r.round}회',
                style: const TextStyle(fontSize: 11, color: Color(0xFF888888), fontWeight: FontWeight.w600))),
            Expanded(child: Row(children: List.generate(5, (i) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: zones[i] > 0 ? zoneColors[i] : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(zones[i] > 0 ? '${zones[i]}' : '',
                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            )))),
          ]),
        );
      }).toList(),
    );
  }

  // ══════════════════════════════════════════════════════════
  // 공통 UI
  // ══════════════════════════════════════════════════════════

  Widget _card({
    required String title,
    required IconData icon,
    required Color iconColor,
    String? subtitle,
    Widget? tag,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Expanded(child: Text(title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A)))),
          if (tag != null) tag,
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF888888), height: 1.4)),
        ],
        if (children.isNotEmpty) const SizedBox(height: 12),
        ...children,
      ]),
    );
  }

  Widget _tag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
      );

  Widget _subTabBtn(String label, int index, {bool isEngine = false}) {
    final selected = isEngine ? _engineSubTab == index : _patternSubTab == index;
    return GestureDetector(
      onTap: () => setState(() {
        if (isEngine) {
          _engineSubTab = index;
        } else {
          _patternSubTab = index;
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: selected ? const Color(0xFF1565C0) : Colors.white,
        )),
      ),
    );
  }

  Widget _sectionLabel(String text, IconData icon, Color color) => Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 5),
            Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
          ]),
        ),
      ]);

  static const _classKoMap = {
    'CORE': '핵심', 'STRONG': '강세', 'SUPPORT': '보조', 'NEUTRAL': '중립',
    'WEAK': '약세', 'EXCLUDE_CANDIDATE': '약세 후보',
  };
  String _classKo(dynamic c) => _classKoMap[c] ?? '$c';
  bool _isWeak(dynamic c) => c == 'WEAK' || c == 'EXCLUDE_CANDIDATE';

  String _fmtTime(DateTime t) {
    final l = t.toLocal();
    return '${l.month.toString().padLeft(2, '0')}.${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  String _short(String? id) {
    if (id == null) return '-';
    return id.length > 14 ? '…${id.substring(id.length - 12)}' : id;
  }

  Color _ballColor(int n) {
    if (n <= 10) return const Color(0xFFFFB300);
    if (n <= 20) return const Color(0xFF42A5F5);
    if (n <= 30) return const Color(0xFFEF5350);
    if (n <= 40) return const Color(0xFF9E9E9E);
    return const Color(0xFF66BB6A);
  }

  Widget _ball(int n, {bool small = false}) {
    final size = small ? 26.0 : 36.0;
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _ballColor(n), shape: BoxShape.circle),
      child: Text('$n', style: TextStyle(
          fontSize: small ? 10.5 : 15, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }
}

RpaWalkForwardReport _wfIsolate(Map<String, dynamic> p) => rpaWalkForward(
      List<LottoWinningNumber>.from(p['data'] as List),
      trainingEndRound: p['end'] as int,
    );
