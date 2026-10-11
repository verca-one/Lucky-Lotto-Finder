// 랜덤확률분석엔진 추천번호 — 최종 결과 카드
//
// ① 최종 구매예측 추천번호: research_results(final_recommendation)에 목표 회차별로 저장된 결과
// ② Number 엔진 기본 조합: rpa_prediction_results(number_base)에 저장된 행
// 둘 다 선택한 목표 회차(target_round)의 행만 조회한다. 다른 회차 행을 재사용하거나
// 앱 내 계산으로 대체하지 않으며, 없으면 '저장 없음'을 그대로 보여준다.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/research/final_recommendation_engine.dart';
import '../services/research/prize_stats_service.dart';
import '../services/rpa_unified_prediction.dart';
import 'purchase_recommend_card.dart' show lottoBall, statusChip;

class RpaStoredPrediction {
  final int targetRound;
  final int trainingEndRound;
  final String modelVersion;
  final String? runId;
  final DateTime generatedAt;
  final String gateStatus;
  final String validationStatus;
  final List<List<int>> sets;
  final List<double?> setScores;
  final List<String> boostHypothesisIds; // 번호에 실제 반영된 Gate 통과 가설
  final int hypLiveCount;                // hypothesis 행 live_count
  final int hypResearchCount;            // hypothesis 행 research_count (미반영)
  final int rowsForTarget;               // 이 회차에 저장된 number_base 행 수 (학습 회차별)
  const RpaStoredPrediction({
    required this.targetRound, required this.trainingEndRound, required this.modelVersion, this.runId,
    required this.generatedAt, required this.gateStatus, required this.validationStatus,
    required this.sets, required this.setScores, required this.boostHypothesisIds,
    required this.hypLiveCount, required this.hypResearchCount, required this.rowsForTarget,
  });

  static Future<RpaStoredPrediction?> load(int targetRound) async {
    final db = Supabase.instance.client;
    final rows = await db
        .from('rpa_prediction_results')
        .select('target_round,training_end_round,model_version,run_id,prediction_type,payload,evidence,gate_status,validation_status,generated_at')
        .eq('target_round', targetRound)
        .eq('model_version', kRpaActiveModelVersion)
        .inFilter('prediction_type', [RpaPredictionType.numberBase, RpaPredictionType.hypothesis])
        .order('training_end_round', ascending: false);
    final list = List<Map<String, dynamic>>.from(rows as List);
    final nbRows = list.where((r) => r['prediction_type'] == RpaPredictionType.numberBase).toList();
    if (nbRows.isEmpty) return null;
    final nb = nbRows.first; // 가장 최근 학습 회차
    final te = nb['training_end_round'] as int;
    final hyp = list.where((r) => r['prediction_type'] == RpaPredictionType.hypothesis && r['training_end_round'] == te).firstOrNull;
    final payload = Map<String, dynamic>.from(nb['payload'] as Map? ?? {});
    final evidence = Map<String, dynamic>.from(nb['evidence'] as Map? ?? {});
    final rawSets = (payload['sets'] as List? ?? []);
    final sets = <List<int>>[];
    final scores = <double?>[];
    for (final s in rawSets) {
      final nums = s is Map ? s['numbers'] : s;
      if (nums is List && nums.length == 6) {
        sets.add(nums.map<int>((n) => (n as num).toInt()).toList());
        scores.add(s is Map ? (s['set_score'] as num?)?.toDouble() : null);
      }
    }
    final hp = Map<String, dynamic>.from(hyp?['payload'] as Map? ?? {});
    return RpaStoredPrediction(
      targetRound: targetRound, trainingEndRound: te, modelVersion: '${nb['model_version']}',
      runId: nb['run_id'] as String?,
      generatedAt: DateTime.tryParse('${nb['generated_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      gateStatus: '${nb['gate_status']}', validationStatus: '${nb['validation_status']}',
      sets: sets, setScores: scores,
      boostHypothesisIds: List<String>.from((evidence['hypothesis_boost_ids'] as List? ?? []).map((e) => '$e')),
      hypLiveCount: (hp['live_count'] as num?)?.toInt() ?? 0,
      hypResearchCount: (hp['research_count'] as num?)?.toInt() ?? 0,
      rowsForTarget: nbRows.length,
    );
  }
}

class _CardData {
  final RpaStoredPrediction? base;
  final FinalRecommendation? finalRec;
  final PrizeStats? prevStats; // 직전 회차 판매액·1등 당첨자 수 (이월 판정)
  const _CardData(this.base, this.finalRec, this.prevStats);
}

class RpaStoredPredictionCard extends StatefulWidget {
  final int targetRound;
  const RpaStoredPredictionCard({super.key, required this.targetRound});
  @override
  State<RpaStoredPredictionCard> createState() => _RpaStoredPredictionCardState();
}

class _RpaStoredPredictionCardState extends State<RpaStoredPredictionCard> {
  late Future<_CardData> _future;

  Future<_CardData> _load(int t) async {
    final base = await RpaStoredPrediction.load(t);
    // 최종 결과: 저장본 우선, 없고 기본 후보가 있으면 사전 고정 규칙으로 생성·저장 (덮어쓰기 없음)
    final fin = base == null ? await FinalRecommendationEngine.instance.loadStored(t)
                             : await FinalRecommendationEngine.instance.ensureStored(t);
    PrizeStats? prev;
    try { await PrizeStatsService.instance.loadAll(); prev = PrizeStatsService.instance.get(t - 1); } catch (_) {}
    return _CardData(base, fin, prev);
  }

  @override
  void initState() {
    super.initState();
    _future = _load(widget.targetRound);
  }

  @override
  void didUpdateWidget(RpaStoredPredictionCard old) {
    super.didUpdateWidget(old);
    if (old.targetRound != widget.targetRound) {
      _future = _load(widget.targetRound); // 회차 전환 → 해당 회차 행만 재조회
    }
  }

  static const _blue = Color(0xFF1565C0);
  static const _gold = Color(0xFFEF6C00);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _blue.withValues(alpha: 0.35), width: 1.2),
      ),
      child: FutureBuilder<_CardData>(
        future: _future,
        builder: (context, snap) {
          final header = Row(children: [
            const Icon(Icons.storage_rounded, size: 16, color: _blue),
            const SizedBox(width: 6),
            Expanded(child: Text('랜덤확률분석엔진 추천번호 · ${widget.targetRound}회',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _blue))),
            statusChip('DB 저장 결과', _blue),
          ]);
          if (snap.connectionState != ConnectionState.done) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              header, const SizedBox(height: 12),
              const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ]);
          }
          if (snap.hasError) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              header, const SizedBox(height: 8),
              Text('조회 실패: ${snap.error}', style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
            ]);
          }
          final data = snap.data!;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            header,
            const SizedBox(height: 10),
            _finalSection(data.finalRec),
            if (data.prevStats != null) ...[
              const SizedBox(height: 6),
              _kv('직전 ${data.prevStats!.round}회 1등', data.prevStats!.rank1Winners == 0
                  ? '당첨자 0명 → ${widget.targetRound}회 이월 (상금↑, 확률 동일 → 기대값↑)'
                  : '${data.prevStats!.rank1Winners}명 (자동 ${data.prevStats!.autoWinners ?? '-'}·수동 ${data.prevStats!.manualWinners ?? '-'}·반자동 ${data.prevStats!.semiAutoWinners ?? '-'}) · 판매 ${data.prevStats!.totalSales == null ? '-' : (data.prevStats!.totalSales! / 1e8).toStringAsFixed(0)}억원',
                  color: data.prevStats!.rank1Winners == 0 ? Colors.teal.shade800 : null),
            ],
            const SizedBox(height: 14),
            _baseSection(data.base),
          ]);
        },
      ),
    );
  }

  // ── ① 최종 구매예측 추천번호 ─────────────────────────────────
  Widget _finalSection(FinalRecommendation? f) {
    final title = Row(children: [
      const Icon(Icons.verified_rounded, size: 15, color: _gold),
      const SizedBox(width: 5),
      const Expanded(child: Text('최종 구매예측 추천번호', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _gold))),
      if (f != null)
        statusChip(f.verifiedEdge ? '검증 신호 반영' : '검증된 당첨확률 우위 없음', f.verifiedEdge ? Colors.teal.shade700 : Colors.grey.shade700),
    ]);
    if (f == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        title, const SizedBox(height: 6),
        Text('${widget.targetRound}회 최종 결과가 저장돼 있지 않습니다(기본 후보 미생성). 다른 회차 번호를 대신 표시하지 않습니다.',
            style: TextStyle(fontSize: 11, color: Colors.orange.shade900, height: 1.4)),
      ]);
    }
    final sig = f.signals;
    final hyp = Map<String, dynamic>.from(sig['hypothesis'] as Map? ?? {});
    final corr = Map<String, dynamic>.from(sig['correction'] as Map? ?? {});
    final joint = Map<String, dynamic>.from(sig['joint'] as Map? ?? {});
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      title,
      const SizedBox(height: 6),
      _kv('목표 회차', '${f.targetRound}회'),
      _kv('학습 기준 회차', '${f.trainingEndRound}회까지 (Number 엔진 v${f.baseModelVersion})'),
      _kv('최종 모델 버전', f.version),
      _kv('생성 시각', _fmt(f.generatedAt)),
      _kv('반영된 검증 통과 가설', '${hyp['validated_count'] ?? 0}개'
          '${(hyp['research_count'] ?? 0) > 0 ? ' (연구 중 ${hyp['research_count']}개 미반영)' : ''}'),
      _kv('Correction 신호', corr['applied'] == true
          ? '적용 (최근 ${corr['n']}회 효과 ${((corr['mean_effect'] as num?) ?? 0).toStringAsFixed(3)}, t=${((corr['t'] as num?) ?? 0).toStringAsFixed(2)})'
          : '미적용 (최근 ${corr['n'] ?? 0}회 t=${((corr['t'] as num?) ?? 0).toStringAsFixed(2)} — 유의하지 않음)'),
      _kv('Joint 신호', joint['applied'] == true ? '적용 (Gate 통과)' : '미적용 (Gate ${joint['gate']})'),
      _kv('Store/명당 연구', '번호 점수에 미반영 (확률 우위 미검증)'),
      const SizedBox(height: 8),
      ...f.sets.asMap().entries.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFCC80)),
            ),
            child: Row(children: [
              SizedBox(width: 22, child: Text('${e.key + 1}', textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _gold))),
              const SizedBox(width: 4),
              Expanded(child: Row(children: e.value.map((n) => Padding(
                  padding: const EdgeInsets.only(right: 5), child: lottoBall(n, size: 26))).toList())),
              if (e.key < f.setScores.length)
                Text('점수 ${f.setScores[e.key].toStringAsFixed(2)}', style: const TextStyle(fontSize: 9, color: Color(0xFF999999))),
            ]),
          )),
      Text(f.note, style: TextStyle(fontSize: 10, color: Colors.grey.shade700, height: 1.4, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('선정 규칙(사전 고정): ${f.rules.join(' · ')}', style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600, height: 1.4)),
    ]);
  }

  // ── ② Number 엔진 기본 조합 (DB 저장 행) ─────────────────────
  Widget _baseSection(RpaStoredPrediction? p) {
    final title = Row(children: [
      const Icon(Icons.functions_rounded, size: 14, color: _blue),
      const SizedBox(width: 5),
      Expanded(child: Text('Number 엔진 기본 조합 (rpa_prediction_results · number_base)',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _blue.withValues(alpha: 0.85)))),
    ]);
    if (p == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        title, const SizedBox(height: 6),
        Text('rpa_prediction_results에 ${widget.targetRound}회 활성 엔진(v$kRpaActiveModelVersion) number_base 행이 없습니다. '
            '임의 번호를 표시하지 않습니다. 새 회차 처리 후 자동 생성됩니다.',
            style: TextStyle(fontSize: 11, color: Colors.orange.shade900, height: 1.4)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      title,
      const SizedBox(height: 6),
      _kv('기준 회차 / 버전', '${p.trainingEndRound}회까지 학습 (+${p.targetRound - p.trainingEndRound}) · v${p.modelVersion}${p.runId != null ? ' · run ${_short(p.runId!)}' : ''}'),
      _kv('생성 시각', _fmt(p.generatedAt)),
      _kv('Gate / 검증', '${p.gateStatus} / ${p.validationStatus}'),
      _kv('가설 부스트', '${p.boostHypothesisIds.length}개${p.hypResearchCount > 0 ? ' (연구 중 ${p.hypResearchCount}개 미반영)' : ''}'),
      if (p.rowsForTarget > 1) _kv('저장 행', '학습 회차별 ${p.rowsForTarget}개 중 최신(${p.trainingEndRound}회) 표시'),
      const SizedBox(height: 6),
      ...p.sets.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 22, child: Text('${e.key + 1}', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _blue.withValues(alpha: 0.8)))),
              const SizedBox(width: 4),
              Expanded(child: Row(children: e.value.map((n) => Padding(
                  padding: const EdgeInsets.only(right: 4), child: lottoBall(n, size: 22))).toList())),
              if (p.setScores[e.key] != null)
                Text('점수합 ${p.setScores[e.key]!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 9, color: Color(0xFF999999))),
            ]),
          )),
      Text('※ 같은 학습 회차(${p.trainingEndRound}회)의 +1~+6 기본 조합은 엔진 설계상 동일할 수 있습니다. 각 회차는 자기 행에 저장된 값을 그대로 표시합니다. 점수는 당첨확률이 아닙니다.',
          style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600, height: 1.4)),
    ]);
  }

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 128, child: Text(k, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
          Expanded(child: Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color ?? const Color(0xFF1A1A2E)))),
        ]),
      );

  String _fmt(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)} (기기 시간대)';
  }

  String _short(String id) => id.length > 18 ? '…${id.substring(id.length - 16)}' : id;
}
