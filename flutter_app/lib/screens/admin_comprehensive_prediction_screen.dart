// 이번 회차 종합예측 화면
// Number Model + Store Model + Joint Model 결과를 통합하여 표시

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/rpa_store_engine.dart';
import '../services/rpa_joint_engine.dart';

class AdminComprehensivePredictionScreen extends StatefulWidget {
  final int targetRound;
  const AdminComprehensivePredictionScreen({super.key, required this.targetRound});

  @override
  State<AdminComprehensivePredictionScreen> createState() =>
      _AdminComprehensivePredictionScreenState();
}

class _AdminComprehensivePredictionScreenState
    extends State<AdminComprehensivePredictionScreen> {

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _numberPred;
  Map<String, dynamic>? _storePred;
  Map<String, dynamic>? _jointPred;
  JointModelState? _jointState;
  StoreModelState? _storeState;
  Map<String, dynamic>? _gateData; // rpa_round_gate for training round

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final db = Supabase.instance.client;
      final results = await Future.wait<dynamic>([
        // 번호 모델 예측
        // 최신 학습 회차의 Snapshot 우선 (같은 회차는 최신 생성 = 활성 버전)
        db.from('rpa_prediction_snapshots')
            .select()
            .eq('target_round', widget.targetRound)
            .order('training_end_round', ascending: false)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        // Store 모델 예측 (가장 최신 training_end_round)
        db.from('rpa_store_predictions')
            .select()
            .eq('target_round', widget.targetRound)
            .order('training_end_round', ascending: false)
            .limit(1)
            .maybeSingle(),
        // Joint 모델 예측 (가장 최신)
        db.from('rpa_joint_predictions')
            .select()
            .eq('target_round', widget.targetRound)
            .order('training_end_round', ascending: false)
            .limit(1)
            .maybeSingle(),
        // 모델 상태
        JointModelEngine.instance.loadState(),
        StoreModelEngine.instance.loadState(),
      ]);

      // load gate status for training round (targetRound - 1)
      final gateRaw = await db
          .from('rpa_round_gate')
          .select()
          .eq('round', widget.targetRound - 1)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _numberPred = results[0] as Map<String, dynamic>?;
        _storePred  = results[1] as Map<String, dynamic>?;
        _jointPred  = results[2] as Map<String, dynamic>?;
        _jointState = results[3] as JointModelState?;
        _storeState = results[4] as StoreModelState?;
        _gateData   = gateRaw;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      appBar: AppBar(
        title: Text(
          '${widget.targetRound}회 종합예측',
          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildHeader(),
        const SizedBox(height: 14),
        _buildJointSection(),
        const SizedBox(height: 12),
        _buildNumberSection(),
        const SizedBox(height: 12),
        _buildStoreSection(),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── 헤더: 종합 요약 ────────────────────────────────────────
  Widget _buildHeader() {
    final jointCandidates = _jointCandidates();
    final methodHint = _jointPred?['purchase_method_hint'] as String?;
    final jointScore = (_jointPred?['joint_score'] as num?)?.toDouble() ?? 0.0;
    final synergy = _jointState?.synergyScore ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF283593)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_graph_rounded, color: Colors.amber, size: 20),
          const SizedBox(width: 8),
          Text('${widget.targetRound}회 이번 회차 종합예측',
              style: const TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        // 유력 지역
        if (jointCandidates.isNotEmpty) ...[
          const Text('유력 지역', style: TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final region in jointCandidates.take(5))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: Text(region,
                    style: const TextStyle(color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 12),
        ],
        // 구매방식 + 점수
        Row(children: [
          if (methodHint != null) ...[
            _infoChip(Icons.shopping_cart_outlined, methodHint, Colors.amber),
            const SizedBox(width: 8),
          ],
          _infoChip(Icons.bar_chart_rounded,
              '결합점수 ${(jointScore * 100).toStringAsFixed(0)}%', Colors.teal[200]!),
          if (synergy != 0) ...[
            const SizedBox(width: 8),
            _infoChip(Icons.merge_type_rounded,
                'Synergy ${synergy >= 0 ? '+' : ''}${(synergy * 100).toStringAsFixed(1)}%',
                synergy > 0 ? Colors.green[200]! : Colors.red[200]!),
          ],
        ]),
      ]),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color,
            fontWeight: FontWeight.w700)),
      ]),
    );
  }

  List<String> _jointCandidates() {
    final raw = _jointPred?['joint_candidate_regions'];
    if (raw is List) return List<String>.from(raw);
    return [];
  }

  // ── Joint Model 섹션 ──────────────────────────────────────
  Widget _buildJointSection() {
    if (_jointPred == null && _jointState == null) {
      return _emptyCard('Joint Model', _gateStatusMsg(), Colors.indigo);
    }

    final candidates = _jointCandidates();
    final numPred = _jointPred?['number_prediction'] as Map? ?? {};
    final storePred = _jointPred?['store_prediction'] as Map? ?? {};

    return _sectionCard(
      title: 'Joint Model 예측',
      color: Colors.indigo,
      icon: Icons.merge_type_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 모델 성능 비교
        if (_jointState != null) ...[
          Row(children: [
            _modelBadge('번호',
                _jointState!.numberModelAccuracy, Colors.blue),
            const SizedBox(width: 8),
            _modelBadge('판매점',
                _jointState!.storeModelAccuracy, Colors.green),
            const SizedBox(width: 8),
            _modelBadge('결합',
                _jointState!.jointModelAccuracy, Colors.indigo),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
        ],
        // 지역 예측
        if (candidates.isNotEmpty) ...[
          const Text('유력 지역 (Joint)', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final r in candidates)
              _regionChip(r, Colors.indigo),
          ]),
          const SizedBox(height: 10),
        ],
        // 번호 모델 기여
        if (numPred.isNotEmpty) ...[
          const Text('번호 모델 기여 지역', style: TextStyle(
              fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            (numPred['candidate_regions'] as List?)?.join(', ') ?? '-',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
        ],
        // Store 모델 기여
        if (storePred.isNotEmpty) ...[
          const Text('Store 모델 기여 지역', style: TextStyle(
              fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            (storePred['candidate_regions'] as List?)?.join(', ') ?? '-',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ]),
    );
  }

  Widget _modelBadge(String label, double? acc, Color color) {
    final pct = acc != null ? '${(acc * 100).toStringAsFixed(0)}%' : '-';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 10, color: color)),
        Text(pct, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }

  // ── 번호 모델 섹션 ────────────────────────────────────────
  Widget _buildNumberSection() {
    if (_numberPred == null) {
      return _emptyCard('번호 모델', _gateStatusMsg(), Colors.blue);
    }

    final directions = Map<String, dynamic>.from(
        (_numberPred!['final_directions'] as Map?) ?? {});
    final indicatorOrder = ['oe33', 'lh33', 'cons', 'sp', 'rhi', 'phi'];
    final labels = {
      'oe33': '홀짝3:3', 'lh33': '저번호3', 'cons': '연속1쌍+',
      'sp': '합짝수', 'rhi': '폭>32', 'phi': '소수>1',
    };

    return _sectionCard(
      title: '번호 모델 예측',
      color: Colors.blue,
      icon: Icons.numbers_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('이번 회차 번호 방향 예측',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final id in indicatorOrder)
            if (directions.containsKey(id))
              _indicatorChip(labels[id] ?? id,
                  directions[id].toString(), Colors.blue),
        ]),
        if (_numberPred!['training_end_round'] != null) ...[
          const SizedBox(height: 8),
          Text(
            '학습 기준: ${_numberPred!['training_end_round']}회차',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ]),
    );
  }

  Widget _indicatorChip(String label, String value, Color color) {
    final isUp = value.contains('up') || value == '1' || value == 'true';
    final isDown = value.contains('down') || value == '0' || value == 'false';
    final displayColor = isUp ? Colors.green.shade600
        : isDown ? Colors.red.shade600
        : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: displayColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: displayColor.withValues(alpha: 0.35)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: displayColor)),
      ]),
    );
  }

  // ── Store 모델 섹션 ────────────────────────────────────────
  Widget _buildStoreSection() {
    if (_storePred == null) {
      return _emptyCard('Store 모델', _gateStatusMsg(), Colors.green);
    }

    final candidateRegions = List<String>.from(
        _storePred!['candidate_regions'] as List? ?? []);
    final candidateStores = List<String>.from(
        _storePred!['candidate_store_codes'] as List? ?? []);
    final distanceBand = _storePred!['best_distance_band'] as String? ?? '-';
    final regionScore = (_storePred!['region_score'] as num?)?.toDouble() ?? 0.0;

    return _sectionCard(
      title: 'Store 모델 예측',
      color: Colors.green,
      icon: Icons.store_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 모델 성능
        if (_storeState != null) ...[
          Row(children: [
            _modelBadge('지역정확도',
                _storeState!.replayRegionAccuracy, Colors.green),
            const SizedBox(width: 8),
            _modelBadge('공간정확도',
                _storeState!.replaySpatialAccuracy, Colors.teal),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
        ],
        // 유력 지역
        if (candidateRegions.isNotEmpty) ...[
          const Text('유력 지역', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final r in candidateRegions)
              _regionChip(r, Colors.green),
          ]),
          const SizedBox(height: 8),
        ],
        // 거리 패턴
        Row(children: [
          _infoChip(Icons.radar_rounded, '직전 대비 $distanceBand', Colors.teal[300]!),
          const SizedBox(width: 8),
          _infoChip(Icons.analytics_rounded,
              '지역점수 ${(regionScore * 100).toStringAsFixed(0)}%',
              Colors.green[300]!),
        ]),
        if (candidateStores.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('후보 판매점 ${candidateStores.length}곳',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ]),
    );
  }

  Widget _regionChip(String region, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(region, style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.85),
          fontWeight: FontWeight.w600)),
    );
  }

  // ── 공통 카드 ────────────────────────────────────────────
  Widget _sectionCard({
    required String title,
    required Color color,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
            border: Border(bottom: BorderSide(
                color: color.withValues(alpha: 0.2))),
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 7),
            Text(title, style: TextStyle(fontSize: 13,
                fontWeight: FontWeight.w800, color: color)),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(14), child: child),
      ]),
    );
  }

  String _gateStatusMsg() {
    final trainingRound = widget.targetRound - 1;
    if (_gateData == null) return '$trainingRound회 데이터 처리 대기 중';
    final status = _gateData!['engine_status'] as String? ?? '';
    final hasNum = _gateData!['has_winning_numbers'] as bool? ?? false;
    final hasStore = _gateData!['has_store_data'] as bool? ?? false;
    switch (status) {
      case 'waiting_number': return '$trainingRound회 당첨번호 등록 대기 중';
      case 'waiting_store':  return '$trainingRound회 당첨판매점 수집 대기 중';
      case 'ready':          return '$trainingRound회 엔진 실행 대기 중';
      case 'processing':     return '$trainingRound회 엔진 분석 중...';
      case 'failed':         return '$trainingRound회 처리 오류 — 재처리 필요';
      case 'completed':      return '${widget.targetRound}회 예측 생성 중';
      default:
        if (!hasNum) return '$trainingRound회 당첨번호 등록 대기 중';
        if (!hasStore) return '$trainingRound회 당첨판매점 수집 대기 중';
        return '$trainingRound회 처리 중';
    }
  }

  Widget _emptyCard(String title, String msg, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Icon(Icons.hourglass_empty_rounded, size: 16,
            color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w700, color: color)),
          Text(msg, style: TextStyle(fontSize: 11,
              color: Colors.grey.shade500)),
        ]),
      ]),
    );
  }
}
