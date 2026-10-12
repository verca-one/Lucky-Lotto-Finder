// ══════════════════════════════════════════════════════════════
// 연구 스케줄러 — 앱 실행 시 기존 DB(읽기 전용)로 연구·등록·채점을 자동 수행
//
// 1. 새 회차 확인 → 2. 미채점 예측 채점 → 3. 다음 회차 예측 등록(잠금)
// 4. 번호 빈도·WF 대조군·구매예측 모델 갱신 → 5. 결과 누적 저장(research_results)
// 크롤러·스케줄러·기존 엔진은 호출하지 않는다.
// ══════════════════════════════════════════════════════════════

import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/lotto_winning_number.dart';
import '../mnd_engine.dart';
import '../rpa_live_numbers.dart';
import '../rpa_monte_carlo_engine.dart';
import 'final_recommendation_engine.dart';
import '../rpa_store_engine.dart' show StoreModelEngine, StoreWinRecord;
import '../rpa_unified_prediction.dart' show kRpaActiveModelVersion;
import '../supabase_service.dart';
import 'draw_research_engine.dart';
import 'hypothesis_replay_engine.dart';
import 'prediction_registry.dart';
import 'prize_stats_service.dart';
import 'purchase_prediction_engine.dart';

class ResearchData {
  final List<LottoWinningNumber> allData;
  final List<StoreWinRecord> history;
  final LottoWinningNumber latest;
  final Map<int, PrizeStats> prizeStats; // 회차별 판매액·등수별 당첨자 수 (research_prize_stats, 없으면 빈 맵)
  int get latestRound => latest.round;
  int get targetRound => latest.round + 1;
  const ResearchData({required this.allData, required this.history, required this.latest, this.prizeStats = const {}});
}

/// 엔진 연구 단계 — 관리자 패널 표시용 3단계
enum ResearchPhase { idle, researching, predicted, done }

class ResearchStatus {
  final ResearchPhase phase;
  final int targetRound;
  final String message;
  final DateTime updatedAt;
  const ResearchStatus(this.phase, this.targetRound, this.message, this.updatedAt);

  String get label {
    switch (phase) {
      case ResearchPhase.researching: return '연구중';
      case ResearchPhase.predicted: return '연구중(다음회차 예측완료)';
      case ResearchPhase.done: return '완료';
      case ResearchPhase.idle: return '대기';
    }
  }

  bool get isRunning => phase == ResearchPhase.researching || phase == ResearchPhase.predicted;
}

class ResearchScheduler {
  ResearchScheduler._();
  static final instance = ResearchScheduler._();

  ResearchData? _data;
  Future<ResearchData?>? _loading;
  int _lastRunLatest = 0;
  bool _running = false;

  /// 실시간 상태 (관리자 패널·연구 현황 화면이 구독)
  final ValueNotifier<ResearchStatus> status =
      ValueNotifier(ResearchStatus(ResearchPhase.idle, 0, '아직 실행되지 않음', DateTime.now()));

  void _setStatus(ResearchPhase p, int target, String msg) {
    status.value = ResearchStatus(p, target, msg, DateTime.now());
  }

  Future<ResearchData?> load({bool force = false}) {
    if (!force && _data != null) return Future.value(_data);
    if (!force && _loading != null) return _loading!;
    _loading = () async {
      try {
        final all = await SupabaseService.getAllWinningNumbers();
        if (all.isEmpty) return null;
        final latest = all.reduce((a, b) => a.round > b.round ? a : b);
        List<StoreWinRecord> hist = [];
        try {
          hist = await StoreModelEngine.instance.loadWinHistory();
        } catch (e) {
          debugPrint('[Research] history load error: $e');
        }
        // 판매액·등수별 당첨자 수 (테이블 없으면 빈 맵) + 최신 회차 누락 시 공개 JSON 1페이지 동기화
        Map<int, PrizeStats> stats = {};
        try {
          await PrizeStatsService.instance.syncLatest(latest.round);
          stats = await PrizeStatsService.instance.loadAll();
        } catch (e) {
          debugPrint('[Research] prize stats: $e');
        }
        _data = ResearchData(allData: all, history: hist, latest: latest, prizeStats: stats);
        return _data;
      } catch (e) {
        debugPrint('[Research] load error: $e');
        return null;
      } finally {
        _loading = null;
      }
    }();
    return _loading!;
  }

  /// 앱 세션 중 최신 회차당 1회 실행. force=true면 즉시 재실행.
  Future<void> runIfNeeded({bool force = false}) async {
    if (_running) return;
    if (status.value.phase == ResearchPhase.idle) {
      _setStatus(ResearchPhase.researching, 0, '당첨번호·당첨 기록 로드 중');
    }
    final d = await load(force: force);
    if (d == null) {
      _setStatus(ResearchPhase.done, 0, '데이터 없음');
      return;
    }
    if (!force && d.latestRound == _lastRunLatest) {
      if (status.value.phase != ResearchPhase.done) {
        _setStatus(ResearchPhase.done, d.targetRound, '완료 · ${d.targetRound}회 예측 등록 · 연구 결과 저장');
      }
      return;
    }
    _running = true;
    try {
      final reg = PredictionRegistry.instance;
      final target = d.targetRound;
      _setStatus(ResearchPhase.researching, target, '${d.latestRound}회 결과로 이전 예측 채점 중');
      // 2. 채점
      try { await reg.verifyPending(d.allData); } catch (e) { debugPrint('[Research] verify: $e'); }

      // 3. 다음 회차 예측 등록
      _setStatus(ResearchPhase.researching, target, '$target회 예측 생성·등록 중 (번호예측·구매예측·무작위 대조군)');
      final deadline = PredictionRegistry.deadlineFor(target, d.latest);
      try {
        final live = await RpaLiveNumbers.load(target);
        if (live.trainingEndRound == d.latestRound && live.baseSets.isNotEmpty) {
          await reg.register(algorithm: PredictionRegistry.algoNumberEngine, version: kRpaActiveModelVersion,
              targetRound: target, dataEndRound: d.latestRound, sets: live.baseSets, deadline: deadline);
        }
      } catch (e) { debugPrint('[Research] number_engine register: $e'); }
      try {
        final report = PurchasePredictionEngine.instance.buildReport(
            allData: d.allData, history: d.history, targetRound: target, trainingEnd: d.latestRound, prizeStats: d.prizeStats);
        await reg.register(algorithm: PredictionRegistry.algoPurchase, version: kPurchaseModelVersion,
            targetRound: target, dataEndRound: d.latestRound,
            sets: report.recommendations.map((r) => r.numbers).toList(), deadline: deadline);
      } catch (e) { debugPrint('[Research] purchase register: $e'); }
      try {
        await reg.register(algorithm: PredictionRegistry.algoRandom, version: 'r1', targetRound: target,
            dataEndRound: d.latestRound, sets: reg.randomControlSets(target), deadline: deadline);
      } catch (e) { debugPrint('[Research] random register: $e'); }
      _setStatus(ResearchPhase.predicted, target, '$target회 예측 등록 완료 · 번호 빈도·WF 대조군 연구 갱신 중');

      // 4. 연구 갱신 (누적 저장)
      final dr = DrawResearchEngine.instance;
      try { await dr.persistNumberFrequency(dr.analyzeNumberFrequency(d.allData)); } catch (e) { debugPrint('[Research] freq: $e'); }
      try { await dr.evaluateEngineNumberWf(d.allData); } catch (e) { debugPrint('[Research] wf control: $e'); }
      try { dr.evaluateRegionWfControl(d.history, d.allData); } catch (e) { debugPrint('[Research] region control: $e'); }
      // 5. 가설 순차 재현 (500회 가설 → 501회 보정 → … → 최신) — isolate
      _setStatus(ResearchPhase.predicted, target, '$target회 예측 등록 완료 · 가설 순차 재현($kHypothesisReplayStart→${d.latestRound}회) 실행 중');
      try { await HypothesisReplayEngine.instance.runAndPersist(d.allData); } catch (e) { debugPrint('[Research] hyp replay: $e'); }
      // 6. Monte Carlo: 기준값 생성 + 미검증 가설 Random Control (화면 진입과 무관하게 엔진 내에서 실행)
      _setStatus(ResearchPhase.predicted, target, '$target회 예측 등록 완료 · Monte Carlo 기준값·가설 Random Control 실행 중');
      try {
        await MonteCarloEngine.instance.scheduleUnverifiedHypotheses();
        await MonteCarloEngine.instance.processQueueBatch(maxJobs: 30);
      } catch (e) { debugPrint('[Research] monte carlo: $e'); }
      // 7. 명당연구소 공간 밀집·신흥 명당 회차별 백필 (1200→최신, 누락 회차만)
      if (d.history.isNotEmpty) {
        try {
          await MndEngine.instance.runSpatialEmergingBackfill(d.history,
              onStatus: (m) => _setStatus(ResearchPhase.predicted, target, '$target회 예측 등록 완료 · $m'));
        } catch (e) { debugPrint('[Research] mnd backfill: $e'); }
        // 7b. 명당 가설 WF 재평가 — 발견 회차 이후(out-of-sample)만 집계, 판매량 미보정 유형은 pass 금지
        _setStatus(ResearchPhase.predicted, target, '$target회 예측 등록 완료 · 명당 가설 Walk-Forward 재평가 중');
        try { await MndEngine.instance.runIncrementalWalkForward(d.history, d.latestRound, 60); }
        catch (e) { debugPrint('[Research] mnd wf: $e'); }
      }
      // 8. 최종 추천번호 (목표 회차별, 저장된 결과는 덮어쓰지 않음)
      _setStatus(ResearchPhase.predicted, target, '$target회 예측 등록 완료 · 최종 추천번호 생성 중');
      for (int t = target; t < target + 6; t++) {
        try { await FinalRecommendationEngine.instance.ensureStored(t); } catch (e) { debugPrint('[Research] final rec $t: $e'); }
      }

      _lastRunLatest = d.latestRound;
      _setStatus(ResearchPhase.done, target, '완료 · $target회 예측 등록 · 연구 결과 저장 (${d.latestRound}회까지 데이터)');
    } catch (e) {
      _setStatus(ResearchPhase.done, d.targetRound, '완료(일부 오류): $e');
    } finally {
      _running = false;
    }
  }

  /// 구매예측 보고서 (대상 회차 기본 = 최신+1)
  Future<PurchaseModelReport?> purchaseReport({int? targetRound}) async {
    final d = await load();
    if (d == null) return null;
    final t = targetRound ?? d.targetRound;
    final te = min(d.latestRound, t - 1);
    return PurchasePredictionEngine.instance.buildReport(
        allData: d.allData, history: d.history, targetRound: t, trainingEnd: te, prizeStats: d.prizeStats);
  }
}
