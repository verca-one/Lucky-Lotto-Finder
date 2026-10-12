// ══════════════════════════════════════════════════════════════
// 서버 연구 파이프라인 (GitHub Actions research-engine.yml) — 관리자 앱 없이 회차마다 자동 실행
//
// 기존 Dart 엔진을 그대로 헤드리스로 실행한다 (같은 코드 = 같은 결과). 순서는 관리자 RPA 화면이
// 화면 진입 시 하던 자동 처리와 같다:
//   1 Round Gate 동기화 → 2 준비된 회차 처리(직전 예측 채점·Number 엔진 예측) → 3 불완전 회차 복구
//   4 증분 업데이트 → 5 활성 버전 결과 보장 → 6 가설 연구소 자동 검증·신호 등록 → 7 MND 초기 연구
//   8 예측 연구(채점·예측 등록·구매예측·빈도·WF·가설 재현·Monte Carlo·MND 백필·최종 추천번호)
//   9 Monte Carlo 큐 → 10 저장 결과 확인(구매예측·공식 최종 추천번호·사전 등록·기존 스냅샷 보존)
// 공개용 3세트·공개 연구 저장은 다음 단계 research_public_worker.py 가 이어서 한다.
//
// 실행: SUPABASE_URL, SUPABASE_KEY(service_role) 환경변수 + flutter test tool/server/research_pipeline_test.dart
// 단계 실패는 삼키지 않고 research_pipeline_runs 에 기록하며, 하나라도 실패하면 success 로 표시하지 않는다.
// ══════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter_app/models/lotto_winning_number.dart';
import 'package:flutter_app/screens/admin_rpa_screen.dart' show kRpaReplayStartRound, runRpaHypothesisLabMaintenance;
import 'package:flutter_app/services/mnd_engine.dart';
import 'package:flutter_app/services/research/final_recommendation_engine.dart';
import 'package:flutter_app/services/research/purchase_prediction_engine.dart';
import 'package:flutter_app/services/research/research_runtime.dart';
import 'package:flutter_app/services/research/research_scheduler.dart';
import 'package:flutter_app/services/rpa_engine.dart';
import 'package:flutter_app/services/rpa_monte_carlo_engine.dart';
import 'package:flutter_app/services/rpa_unified_prediction.dart' show kRpaActiveModelVersion, RpaPredictionType;
import 'package:flutter_app/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'server_env.dart';

/// research_pipeline_gate.py 의 PIPELINE_VERSION 과 같아야 한다
const String kServerPipelineVersion = 'sp-1.0';

void main() {
  test('서버 연구 파이프라인', () async {
    await initServerSupabase();
    ResearchRuntime.serverWriter = true;
    final db = Supabase.instance.client;
    final started = DateTime.now().toUtc();

    final all = await SupabaseService.getAllWinningNumbers();
    expect(all, isNotEmpty, reason: '당첨번호 없음');
    final latest = all.map((d) => d.round).reduce((a, b) => a > b ? a : b);
    final target = latest + 1;

    // 성공 기록이 있으면 중복 실행하지 않음 (게이트가 1차로 막지만 직접 실행 대비)
    final done = await db.from('research_pipeline_runs').select('id')
        .eq('pipeline_version', kServerPipelineVersion).eq('target_round', target).eq('status', 'success').limit(1);
    if ((done as List).isNotEmpty) {
      // ignore: avoid_print
      print('$target회 이미 성공 — 실행하지 않음');
      return;
    }
    final prior = await db.from('research_pipeline_runs').select('id')
        .eq('pipeline_version', kServerPipelineVersion).eq('target_round', target).neq('status', 'waiting');

    // running 기록 (동시 실행은 uq_pipeline_running 이 막는다)
    final runRow = await db.from('research_pipeline_runs').insert({
      'pipeline_version': kServerPipelineVersion, 'latest_round': latest, 'target_round': target,
      'status': 'running', 'attempt': (prior as List).length + 1,
      'trigger': Platform.environment['GITHUB_EVENT_NAME'], 'runner': Platform.environment['GITHUB_RUN_ID'],
    }).select('id').single();
    final runId = runRow['id'] as String;

    final steps = <Map<String, dynamic>>[];
    void record(String name, Object? error) {
      steps.add({
        'name': name, 'ok': error == null, 'at': DateTime.now().toUtc().toIso8601String(),
        if (error != null) 'error': '$error'.length > 300 ? '${'$error'.substring(0, 300)}…' : '$error',
      });
      // ignore: avoid_print
      print('[pipeline] $name ${error == null ? 'OK' : 'FAIL: $error'}');
    }

    Future<void> step(String name, Future<void> Function() body) async {
      try {
        await body();
        record(name, null);
      } catch (e) {
        record(name, e);
      }
    }

    Future<void> saveRun({String? status, Map<String, dynamic>? outputs, String? error}) async {
      await db.from('research_pipeline_runs').update({
        'steps': steps,
        if (status != null) 'status': status,
        if (outputs != null) 'outputs': outputs,
        if (error != null) 'error': error,
        if (status != null && status != 'running') 'finished_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', runId);
    }

    // 기존 공식 최종 추천번호 스냅샷 (보존 확인용)
    final before = await _finalRecSnapshots(db, latest - 1, target + 5);

    try {
      final rpa = RpaEngine.instance;
      await step('rpa_sync_gates', () => rpa.syncMissingGates(all));
      await step('rpa_ready_rounds', () => rpa.checkAndProcessReadyRounds(all));
      await step('rpa_repair_incomplete', () => rpa.checkAndRepairIncompleteRounds(all));
      await step('rpa_incremental', () async {
        final state = await rpa.loadState();
        if (latest <= state.lastTrainedRound) return;
        final gap = latest - state.lastTrainedRound;
        if (gap <= 5) {
          final rounds = all.where((d) => d.round > state.lastTrainedRound && d.round <= latest).toList()
            ..sort((a, b) => a.round.compareTo(b.round));
          for (final r in rounds) {
            final res = await rpa.processNewRound(newRound: r, allData: all);
            if (!res.success && !res.waitingForStore) throw StateError('${r.round}회 처리 실패: ${res.error}');
          }
        } else if (!state.replayCompleted) {
          await rpa.runHistoricalReplay(allData: all, startRound: kRpaReplayStartRound);
        }
      });
      await step('rpa_active_version', () async {
        final r = await rpa.ensureActiveVersionPredictions(all);
        if (!r.ok) throw StateError('${r.status.name}: ${r.message}');
      });
      await step('hypothesis_lab', () async => runRpaHypothesisLabMaintenance(all));
      await step('mnd_initial', () => MndEngine.instance.autoStartIfNeeded(latest));
      await ResearchScheduler.instance.runIfNeeded(force: true, onStep: record);
      await step('monte_carlo_queue', () => MonteCarloEngine.instance.processQueueBatch(maxJobs: 5));
      await saveRun();

      // ── 저장 결과 확인 ──
      final outputs = await _verifyOutputs(db, all, latest, target, record);
      final after = await _finalRecSnapshots(db, latest - 1, target + 5);
      final changed = before.entries.where((e) => after[e.key] != e.value).map((e) => e.key).toList();
      record('snapshot_preserved', changed.isEmpty ? null : '기존 스냅샷 변경·삭제: $changed');
      outputs['preserved_snapshots'] = before.length;

      final ok = steps.every((s) => s['ok'] == true);
      await saveRun(status: ok ? 'success' : 'partial', outputs: outputs,
          error: ok ? null : '실패 단계: ${steps.where((s) => s['ok'] != true).map((s) => s['name']).join(', ')}');
      // ignore: avoid_print
      print('[pipeline] $target회 ${ok ? 'success' : 'partial'} · ${DateTime.now().toUtc().difference(started).inMinutes}분');
      expect(ok, isTrue, reason: '실패 단계가 있음 — 다음 실행에서 재시도');
    } catch (e) {
      await saveRun(status: 'failed', error: '$e');
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 165)));
}

/// 공식 최종 추천번호 스냅샷: id → 생성 시각 (목표 회차 범위)
Future<Map<String, String>> _finalRecSnapshots(SupabaseClient db, int from, int to) async {
  final rows = await db.from('research_results').select('id,payload')
      .eq('research_type', 'final_recommendation').eq('model_version', kFinalRecVersion)
      .gte('target_round', from).lte('target_round', to);
  return {for (final r in rows as List) '${r['id']}': '${(r['payload'] as Map?)?['generated_at']}'};
}

/// 이번 실행이 남겨야 하는 결과가 실제 DB에 있는지 확인
Future<Map<String, dynamic>> _verifyOutputs(SupabaseClient db, List<LottoWinningNumber> all, int latest, int target,
    void Function(String, Object?) record) async {
  final out = <String, dynamic>{'target_round': target, 'latest_round': latest};

  // 구매예측 (학습 ~latest → target)
  final pur = await db.from('research_results').select('id,payload')
      .eq('research_type', 'purchase_model').eq('model_version', kPurchaseModelVersion)
      .eq('target_round', target).eq('training_end_round', latest).limit(1);
  if ((pur as List).isEmpty) {
    record('output_purchase', '구매예측 결과 없음');
  } else {
    final recs = ((pur.first['payload'] as Map)['recommendations'] as List? ?? []);
    out['purchase'] = {'id': pur.first['id'], 'model_version': kPurchaseModelVersion, 'sets': recs.length,
      'status': (pur.first['payload'] as Map)['validation_status']};
    record('output_purchase', null);
  }

  // 공식 최종 추천번호 = 목표 회차 number_base 최신 학습 회차 스냅샷
  final nb = await db.from('rpa_prediction_results').select('training_end_round')
      .eq('target_round', target).eq('model_version', kRpaActiveModelVersion)
      .eq('prediction_type', RpaPredictionType.numberBase).order('training_end_round', ascending: false).limit(1);
  final nbTrain = (nb as List).isEmpty ? null : (nb.first['training_end_round'] as num).toInt();
  final fr = await FinalRecommendationEngine.instance.loadStored(target, trainingEndRound: nbTrain);
  if (nbTrain == null || fr == null || fr.sets.length != 5) {
    record('output_final_recommendation', 'number_base=$nbTrain · 공식 스냅샷=${fr?.snapshotId} · 세트=${fr?.sets.length}');
  } else {
    out['final_recommendation'] = {'id': fr.snapshotId, 'model_version': fr.version, 'training_end_round': fr.trainingEndRound,
      'sets': fr.sets.length};
    record('output_final_recommendation', null);
  }

  // 사전 등록 예측 (번호 엔진·구매예측·무작위 대조군)
  final reg = await db.from('research_predictions').select('algorithm,version').eq('target_round', target);
  out['registered'] = [for (final r in reg as List) '${r['algorithm']}:${r['version']}'];
  record('output_registry', (reg).length >= 2 ? null : '사전 등록 ${reg.length}건');
  return out;
}
