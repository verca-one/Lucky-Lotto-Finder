// ignore_for_file: avoid_print
// 실제 DB 데이터로 통합 예측(활성 model_version)을 계산·검증합니다.
//
//   cd flutter_app
//   dart run tool/verify_unified_prediction.dart            # 계산 + 보고 (DB 쓰기 없음)
//   dart run tool/verify_unified_prediction.dart --write    # rpa_v11 마이그레이션 적용 후: 스냅샷/결과 저장
//
// 옵션: --target=1245 (기본: 최신 회차+1), --window=300

import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/services/rpa_number_core.dart';
import 'package:flutter_app/services/rpa_unified_prediction.dart';

import 'rpa_rest.dart';

Future<void> main(List<String> args) async {
  final write = args.contains('--write');
  String? opt(String k) => args
      .where((a) => a.startsWith('--$k='))
      .map((a) => a.split('=')[1])
      .firstOrNull;
  final rest = RpaRest.fromApp();
  try {
    final all = await rest.winningNumbers();
    final latest = all.map((w) => w.round).reduce((a, b) => a > b ? a : b);
    final target = int.tryParse(opt('target') ?? '') ?? latest + 1;
    final window = int.tryParse(opt('window') ?? '') ?? 300;
    final training = all.where((w) => w.round < target).toList()
      ..sort((a, b) => a.round.compareTo(b.round));
    final trainingEnd = training.last.round;
    print('═══ 통합 예측 검증: v$kRpaActiveModelVersion, ${trainingEnd}회까지 학습 → $target회 예측 ═══');
    print('학습 데이터 ${training.length}회 (${training.first.round}~$trainingEnd), 미래정보 사용 없음');

    // 1) 엔진 상태 / 가설
    final state = await rest.get('rpa_model_state?select=*&state_key=eq.current');
    final rawFlips = state.isNotEmpty ? state.first['active_flips'] : null;
    final flips = {
      for (final id in rpaIndicatorIds)
        id: rawFlips is Map ? (rawFlips[id] as bool? ?? false) : false,
    };
    final hypRows = await rest.get('rpa_hypotheses_v3?select=*&order=created_at.desc&limit=300');
    final hyps = hypRows.map(RpaHypothesisInput.fromRow).toList();
    final liveHyps = hyps.map(rpaEvaluateHypothesis).where((v) => v.live).toList();

    // 2) Number Base (Gate 통과 가설만 보정)
    final boost = liveHyps.isEmpty
        ? 0.0
        : (liveHyps.map((v) => v.h.currentWeight ?? 0).reduce((a, b) => a + b) /
                liveHyps.length * 0.3)
            .clamp(0.0, 0.3);
    final base = rpaComputeNumberBase(training,
        activeFlips: flips,
        hypothesisBoost: boost,
        activeHypCount: liveHyps.length,
        boostHypothesisIds: liveHyps.map((v) => v.h.id).toList());

    // 3) v2.0 스냅샷과 비교 (점수/순위가 같은지 증명)
    final oldSnaps = await rest.get(
        'rpa_prediction_snapshots?select=id,model_version,created_at,candidate_numbers,recommended_sets,final_prediction'
        '&target_round=eq.$target&training_end_round=eq.$trainingEnd&order=created_at.asc');
    print('\n[Number Base 재계산 vs 저장 스냅샷]');
    for (final s in oldSnaps) {
      final oldC = {for (final c in s['candidate_numbers'] as List) c['n'] as int: (c['s'] as num).toDouble()};
      final newC = {for (final c in base.candidates) c['n'] as int: c['s'] as double};
      final sameScores = oldC.length == newC.length &&
          oldC.entries.every((e) => newC[e.key] == e.value);
      final oldDirs = Map<String, dynamic>.from((s['final_prediction'] as Map)['directions'] as Map);
      final sameDirs = rpaIndicatorIds.every((id) => oldDirs[id] == base.finalDirections[id]);
      final oldOrder = (s['candidate_numbers'] as List).map((c) => c['n']).toList();
      final newOrder = base.candidates.map((c) => c['n']).toList();
      final tieSwaps = <String>[];
      for (int i = 0; i < oldOrder.length; i++) {
        if (oldOrder[i] != newOrder[i]) tieSwaps.add('${i + 1}위 ${oldOrder[i]}→${newOrder[i]}(점수 ${oldC[oldOrder[i]]})');
      }
      print(' v${s['model_version']} (${s['created_at']})');
      print('   지표 방향: ${sameDirs ? '동일' : '다름'} / 상위18 번호·점수: ${sameScores ? '동일' : '다름'}');
      print('   순위 차이: ${tieSwaps.isEmpty ? '없음' : tieSwaps.join(', ')}');
      print('   저장 조합(v2.0 셔플): ${s['recommended_sets']}');
    }
    print(' v$kRpaActiveModelVersion 결정적 조합: ${base.recommendedSets}');

    // 4) Walk-Forward
    final sw = Stopwatch()..start();
    final wf = rpaWalkForward(all, trainingEndRound: trainingEnd, window: window);
    print('\n[Historical Walk-Forward] ${wf.fromRound}~${wf.toRound}회 n=${wf.n} (${sw.elapsed.inSeconds}s)');
    print(' ${const JsonEncoder.withIndent('  ').convert(wf.toJson())}');

    // 5) Joint / Store gate 입력
    final jcRows = await rest.get(
        'rpa_joint_contextual_predictions?select=*&target_round=eq.$target&training_end_round=eq.$trainingEnd&order=created_at.desc&limit=1');
    final job = await rest.get('rpa_joint_historical_job?select=*&id=eq.1');
    final storeRows = await rest.get(
        'rpa_store_predictions?select=target_round,candidate_regions,region_hit,spatial_hit&region_hit=not.is.null&limit=2000');
    final regionRates = await _regionBaseRates(rest);
    final jointGate = rpaJointGate(
      numberWfImprovement: 0.0,
      numberWfN: 982,
      regionJob: job.isEmpty ? null : job.first,
      storeRows: storeRows,
      regionBaseRates: regionRates,
    );

    final bundle = rpaBuildUnifiedBundle(RpaUnifiedInputs(
      targetRound: target,
      trainingEndRound: trainingEnd,
      runId: 'verify_${trainingEnd}_${DateTime.now().millisecondsSinceEpoch}',
      numberEvaluations: base.numberEvaluations,
      finalDirections: base.finalDirections,
      hypotheses: hyps,
      trainingData: training,
      walkForward: wf,
      jointContextual: jcRows.isEmpty ? null : jcRows.first,
      jointGate: jointGate,
    ));

    print('\n[통합 결과]');
    for (final r in bundle.results) {
      print('■ ${r.predictionType}  gate=${r.gateStatus}  validation=${r.validationStatus}');
      print('  payload=${jsonEncode(r.payload)}');
    }
    print('\n[Joint/Store Gate] ${const JsonEncoder.withIndent('  ').convert(jointGate)}');
    print('\n[충돌 ${bundle.conflicts.length}건]');
    for (final c in bundle.conflicts) {
      print(' - ${c['reason']}');
    }

    if (write) {
      print('\n[DB 저장]');
      final snap = await rest.post('rpa_prediction_snapshots', {
        'target_round': target,
        'training_end_round': trainingEnd,
        'theory_snapshot': {'directions': base.theoryDirections, 'rates': base.rates},
        'correction_snapshot': {'flips': base.flips},
        'final_prediction': {'directions': base.finalDirections},
        'status': 'pending',
        'model_version': kRpaActiveModelVersion,
        'run_id': bundle.results.first.runId,
        'horizon': target - trainingEnd,
        'candidate_numbers': base.candidates,
        'recommended_sets': base.recommendedSets,
        'number_evaluations': base.numberEvaluations,
        'prediction_type': RpaPredictionType.numberBase,
        'gate_status': bundle.of(RpaPredictionType.numberBase)!.gateStatus,
        'validation_status': bundle.of(RpaPredictionType.numberBase)!.validationStatus,
        'score_definition': bundle.of(RpaPredictionType.numberBase)!.scoreDefinition,
        'evidence': bundle.of(RpaPredictionType.numberBase)!.evidence,
        'generated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'target_round,training_end_round,model_version', upsert: true);
      final snapId = (snap as List).first['id'];
      print(' snapshot id=$snapId');
      final rows = bundle.results.map((r) => {...r.toRow(), 'source_snapshot_id': snapId}).toList();
      await rest.post('rpa_prediction_results', rows,
          onConflict: 'target_round,training_end_round,model_version,prediction_type', upsert: true);
      print(' rpa_prediction_results ${rows.length}건 저장');
    }
  } on RpaRestError catch (e) {
    print('DB 오류: $e');
    exitCode = 2;
  } finally {
    rest.close();
  }
}

Future<Map<String, double>> _regionBaseRates(RpaRest rest) async {
  final rows = <Map<String, dynamic>>[];
  for (int offset = 0;; offset += 1000) {
    final page = await rest.get(
        'rpa_store_predictions?select=actual_region&actual_region=not.is.null&offset=$offset&limit=1000');
    rows.addAll(page);
    if (page.length < 1000) break;
  }
  final counts = <String, int>{};
  for (final r in rows) {
    final g = r['actual_region'] as String;
    counts[g] = (counts[g] ?? 0) + 1;
  }
  final total = rows.length;
  return counts.map((k, v) => MapEntry(k, total == 0 ? 0.0 : v / total));
}
