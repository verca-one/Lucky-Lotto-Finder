// ══════════════════════════════════════════════════════════════
// 최종 추천번호 — 랜덤확률분석엔진의 최종 결과 카드용
//
// 입력(모두 DB 저장 결과, 읽기 전용):
//   · Number 엔진 기본 후보: rpa_prediction_results(number_base, 활성 버전, 목표 회차 행)의 top_numbers
//   · 검증 통과 신호만 반영:
//       - Hypothesis: 같은 행의 hypothesis 결과에서 live(gate pass)인 지표 방향만
//       - Correction: rpa_round_scores 최근 100회 보정 효과가 t>1.96 & 평균>0 일 때만 지표 방향 조건 적용
//       - Joint: joint_contextual gate pass 일 때만 joint 번호에 소폭 가점
//       - Store/Spatial/MND: 번호 확률 우위가 검증되지 않았으므로 번호 점수에 섞지 않음
// 선정 규칙(사전 고정, 연구 결과를 보고 바꾸지 않음):
//   R1 후보 풀 = top_numbers 상위 18개
//   R2 모든 6조합(C(18,6)=18,564) 점수 = Σ final_score (+Joint 가점 0.1/번호, 검증 통과 시)
//   R3 제외: 4연속 이상, 같은 10단위에 4개 이상, 최대-최소 < 20, 홀수 0~1개 또는 5~6개
//   R4 점수 내림차순(동점은 번호 사전순) → 세트 간 중복 번호 ≤ 2 유지하며 5세트 선정 (난수 없음)
//   R5 결과는 (버전, 학습 회차, 목표 회차)별로 저장하며 덮어쓰지 않음
// 내부 점수는 당첨확률이 아님. 검증된 당첨확률 우위가 없으면 그 사실을 함께 저장한다.
//
// 공식 최종 예측(OfficialPredictionService) — 패턴 분석 · 엔진 브리핑 · 추천번호 화면의 단일 출처:
//   · 목표 회차의 최신 number_base 학습 회차(latestTrain) 스냅샷이 저장돼 있으면 그것이 공식
//   · 없고 추첨 전이면 latestTrain 기준으로 새 스냅샷을 만들어 저장(ignoreDuplicates, 기존 행 보존)
//   · 추첨 후면 다시 만들지 않고 최신 저장본을 '추첨 후 조회 · 재생성 안 함'으로 표시
//   · 아무것도 없으면 '해당 회차 최종 예측 준비 중' — 다른 회차 번호로 대체하지 않음
// ══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../rpa_number_core.dart' show rpaActualIndicatorValues, rpaIndicatorBaselines;
import '../rpa_unified_prediction.dart';
import '../supabase_service.dart';
import 'recommend_release.dart';
import 'research_core.dart';
import 'research_runtime.dart';

const String kFinalRecVersion = 'fr-1.0';

class FinalRecommendation {
  final int targetRound, trainingEndRound;
  final String version, baseModelVersion;
  final DateTime generatedAt, baseGeneratedAt;
  final List<List<int>> sets;
  final List<double> setScores;
  final List<int> pool;
  final List<String> rules;
  final Map<String, dynamic> signals;
  final bool verifiedEdge; // 검증된 당첨확률 우위 존재 여부 (현재 규칙상 false 가 기본)
  final String note;

  /// research_results.id (저장 행에서 읽었을 때만 채움, payload 에는 넣지 않음)
  final String? snapshotId;
  const FinalRecommendation({
    required this.targetRound, required this.trainingEndRound, required this.version, required this.baseModelVersion,
    required this.generatedAt, required this.baseGeneratedAt, required this.sets, required this.setScores,
    required this.pool, required this.rules, required this.signals, required this.verifiedEdge, required this.note,
    this.snapshotId,
  });

  Map<String, dynamic> toJson() => {
        'target_round': targetRound, 'training_end_round': trainingEndRound, 'version': version,
        'base_model_version': baseModelVersion, 'generated_at': generatedAt.toUtc().toIso8601String(),
        'base_generated_at': baseGeneratedAt.toUtc().toIso8601String(),
        'sets': sets, 'set_scores': setScores, 'pool': pool, 'rules': rules, 'signals': signals,
        'verified_edge': verifiedEdge, 'note': note,
      };

  factory FinalRecommendation.fromJson(Map<String, dynamic> j, {String? snapshotId}) => FinalRecommendation(
        targetRound: (j['target_round'] as num).toInt(), trainingEndRound: (j['training_end_round'] as num).toInt(),
        version: '${j['version']}', baseModelVersion: '${j['base_model_version']}',
        generatedAt: DateTime.tryParse('${j['generated_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        baseGeneratedAt: DateTime.tryParse('${j['base_generated_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        sets: (j['sets'] as List).map<List<int>>((s) => (s as List).map<int>((n) => (n as num).toInt()).toList()).toList(),
        setScores: (j['set_scores'] as List? ?? []).map<double>((v) => (v as num).toDouble()).toList(),
        pool: (j['pool'] as List? ?? []).map<int>((n) => (n as num).toInt()).toList(),
        rules: List<String>.from(j['rules'] as List? ?? []),
        signals: Map<String, dynamic>.from(j['signals'] as Map? ?? {}),
        verifiedEdge: j['verified_edge'] == true, note: '${j['note'] ?? ''}',
        snapshotId: snapshotId,
      );
}

class FinalRecommendationEngine {
  FinalRecommendationEngine._();
  static final instance = FinalRecommendationEngine._();
  final _db = Supabase.instance.client;

  static const List<String> kRules = [
    'R1 후보 풀 = Number 엔진 top_numbers 상위 18개',
    'R2 조합 점수 = Σ final_score (+Joint 가점 0.1/번호, Joint Gate 통과 시에만)',
    'R3 제외: 4연속 이상 · 같은 10단위 4개 이상 · 최대-최소 < 20 · 홀수 0~1개 또는 5~6개',
    'R4 점수 내림차순(동점 번호 사전순) → 세트 간 중복 ≤ 2 유지하며 5세트 (난수 없음)',
    'R5 (버전·학습 회차·목표 회차)별 저장, 덮어쓰지 않음',
    'Store/Spatial/MND 결과는 번호 확률 우위 미검증 → 번호 점수에 미반영',
  ];

  /// 공식 최종 예측 규칙([OfficialPredictionService])에 따라 저장본 반환 또는 생성·저장 (덮어쓰기 없음).
  /// 최신 학습 회차 스냅샷이 없으면 추첨 전일 때만 새로 만든다.
  Future<FinalRecommendation?> ensureStored(int targetRound) async =>
      (await OfficialPredictionService.instance.load(targetRound)).rec;

  /// 저장된 최종 추천 (research_results). [trainingEndRound] 지정 시 그 학습 회차 행만,
  /// 미지정 시 가장 최근 학습 회차 행. 없거나 조회 실패 = null.
  Future<FinalRecommendation?> loadStored(int targetRound, {int? trainingEndRound}) async {
    try {
      var q = _db.from('research_results').select('id,training_end_round,payload')
          .eq('research_type', 'final_recommendation').eq('model_version', kFinalRecVersion)
          .eq('target_round', targetRound);
      if (trainingEndRound != null) q = q.eq('training_end_round', trainingEndRound);
      final r = await q.order('training_end_round', ascending: false).limit(1);
      final l = List<Map<String, dynamic>>.from(r as List);
      if (l.isEmpty) return null;
      return FinalRecommendation.fromJson(Map<String, dynamic>.from(l.first['payload'] as Map),
          snapshotId: l.first['id']?.toString());
    } catch (_) {
      return null;
    }
  }

  /// 목표 회차에 저장된 최종 추천의 학습 회차 목록 (내림차순). 조회 실패는 예외로 전달.
  Future<List<int>> storedTrainings(int targetRound) async {
    final r = await _db.from('research_results').select('training_end_round')
        .eq('research_type', 'final_recommendation').eq('model_version', kFinalRecVersion)
        .eq('target_round', targetRound).order('training_end_round', ascending: false);
    return List<Map<String, dynamic>>.from(r as List)
        .map((m) => (m['training_end_round'] as num?)?.toInt())
        .whereType<int>()
        .toList();
  }

  /// 목표 회차의 활성 버전 number_base 최신 학습 회차 (없으면 null). 조회 실패는 예외로 전달.
  Future<int?> latestNumberBaseTraining(int targetRound) async {
    final r = await _db.from('rpa_prediction_results').select('training_end_round')
        .eq('target_round', targetRound).eq('model_version', kRpaActiveModelVersion)
        .eq('prediction_type', RpaPredictionType.numberBase)
        .order('training_end_round', ascending: false).limit(1);
    final l = List<Map<String, dynamic>>.from(r as List);
    return l.isEmpty ? null : (l.first['training_end_round'] as num?)?.toInt();
  }

  /// 서버 파이프라인만 생성·저장한다 (앱은 null → 저장본 또는 '준비 중').
  Future<FinalRecommendation?> buildAndStore(int targetRound) async {
    if (!ResearchRuntime.serverWriter) return null;
    final rec = await compute(targetRound);
    if (rec == null) return null;
    try {
      await _db.from('research_results').upsert({
        'research_type': 'final_recommendation', 'model_version': kFinalRecVersion,
        'training_end_round': rec.trainingEndRound, 'target_round': targetRound, 'payload': rec.toJson(),
      }, onConflict: 'research_type,model_version,training_end_round,target_round', ignoreDuplicates: true);
    } catch (e) {
      debugPrint('[FinalRec] persist skipped: $e');
    }
    return (await loadStored(targetRound, trainingEndRound: rec.trainingEndRound)) ?? rec;
  }

  /// 최종 추천 계산만 (저장 없음) — 저장된 Number 엔진 결과에서 결정적으로 만든다. 기본 후보가 없으면 null.
  Future<FinalRecommendation?> compute(int targetRound) async {
    // 1) 목표 회차의 Number 엔진 저장 결과 (가장 최근 학습 회차)
    final rows = await _db.from('rpa_prediction_results')
        .select('training_end_round,model_version,prediction_type,payload,gate_status,generated_at')
        .eq('target_round', targetRound).eq('model_version', kRpaActiveModelVersion)
        .inFilter('prediction_type', [RpaPredictionType.numberBase, RpaPredictionType.hypothesis, RpaPredictionType.jointContextual])
        .order('training_end_round', ascending: false);
    final list = List<Map<String, dynamic>>.from(rows as List);
    final nb = list.where((r) => r['prediction_type'] == RpaPredictionType.numberBase).firstOrNull;
    if (nb == null) return null; // 기본 후보 없음 → 임의 생성 금지
    final te = nb['training_end_round'] as int;
    final nbPayload = Map<String, dynamic>.from(nb['payload'] as Map? ?? {});
    final top = (nbPayload['top_numbers'] as List? ?? [])
        .whereType<Map>()
        .map((m) => MapEntry((m['n'] as num).toInt(), (m['final_score'] as num?)?.toDouble() ?? 0))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (top.length < 6) return null;
    final pool = top.take(18).toList();
    final score = {for (final e in pool) e.key: e.value};

    // 2) 검증 통과 신호
    final hypRow = list.where((r) => r['prediction_type'] == RpaPredictionType.hypothesis && r['training_end_round'] == te).firstOrNull;
    final hypPayload = Map<String, dynamic>.from(hypRow?['payload'] as Map? ?? {});
    final liveDirs = <String, String>{}; // indicator → direction (live=true 만)
    for (final g in (hypPayload['groups'] as List? ?? [])) {
      for (final m in ((g as Map)['members'] as List? ?? [])) {
        final mm = m as Map;
        if (mm['live'] == true && mm['indicator'] is String && mm['direction'] is String) {
          liveDirs[mm['indicator'] as String] = mm['direction'] as String;
        }
      }
    }
    final jointRow = list.where((r) => r['prediction_type'] == RpaPredictionType.jointContextual && r['training_end_round'] == te).firstOrNull;
    final jointPass = jointRow?['gate_status'] == RpaGate.pass;
    final jointNums = <int>{};
    if (jointPass) {
      for (final s in ((jointRow!['payload'] as Map?)?['joint_sets'] as List? ?? [])) {
        final nums = s is Map ? s['numbers'] : s;
        if (nums is List) jointNums.addAll(nums.map((n) => (n as num).toInt()));
      }
    }
    // Correction: 최근 100회 보정 효과 t 검정
    double corrMean = 0, corrT = 0; int corrN = 0; bool corrApplied = false;
    try {
      final sc = await _db.from('rpa_round_scores').select('correction_effect')
          .lte('target_round', te).order('target_round', ascending: false).limit(100);
      final eff = (sc as List).map((r) => ((r['correction_effect'] as num?) ?? 0).toDouble()).toList();
      if (eff.length >= 20) {
        final t = oneSampleT(eff, 0);
        corrMean = t[0]; corrT = t[2]; corrN = eff.length;
        corrApplied = corrT > 1.96 && corrMean > 0;
      }
    } catch (_) {}
    final finalDirs = Map<String, String>.from(nbPayload['final_directions'] as Map? ?? {});

    bool matchesDirs(List<int> set, Map<String, String> dirs) {
      if (dirs.isEmpty) return true;
      final v = rpaActualIndicatorValues(set);
      for (final e in dirs.entries) {
        if (e.value == 'neutral') continue;
        final above = (v[e.key] ?? 0) > (rpaIndicatorBaselines[e.key] ?? 0.5);
        if (e.value == 'above' && !above) return false;
        if (e.value == 'below' && above) return false;
      }
      return true;
    }

    // 3) 전수 조합 + 규칙
    final nums = pool.map((e) => e.key).toList()..sort();
    final cands = <MapEntry<List<int>, double>>[];
    final k = nums.length;
    for (int a = 0; a < k - 5; a++) {
      for (int b = a + 1; b < k - 4; b++) {
        for (int c = b + 1; c < k - 3; c++) {
          for (int d = c + 1; d < k - 2; d++) {
            for (int e = d + 1; e < k - 1; e++) {
              for (int f = e + 1; f < k; f++) {
                final set = [nums[a], nums[b], nums[c], nums[d], nums[e], nums[f]];
                final ft = ComboFeatures.of(set);
                if (ft.maxRun >= 4 || ft.maxDecade >= 4 || ft.spread < 20 || ft.oddCnt <= 1 || ft.oddCnt >= 5) continue;
                if (liveDirs.isNotEmpty && !matchesDirs(set, liveDirs)) continue;
                if (corrApplied && !matchesDirs(set, finalDirs)) continue;
                double s = 0;
                for (final n in set) { s += score[n] ?? 0; if (jointPass && jointNums.contains(n)) s += 0.1; }
                cands.add(MapEntry(set, s));
              }
            }
          }
        }
      }
    }
    cands.sort((x, y) {
      final c = y.value.compareTo(x.value);
      if (c != 0) return c;
      for (int i = 0; i < 6; i++) { final d = x.key[i].compareTo(y.key[i]); if (d != 0) return d; }
      return 0;
    });
    final picked = <List<int>>[], pickedScores = <double>[];
    for (final c in cands) {
      if (picked.length >= 5) break;
      final s = c.key.toSet();
      if (picked.every((p) => p.where(s.contains).length <= 2)) { picked.add(c.key); pickedScores.add(c.value); }
    }

    final verifiedEdge = liveDirs.isNotEmpty || corrApplied || jointPass;
    final rec = FinalRecommendation(
      targetRound: targetRound, trainingEndRound: te, version: kFinalRecVersion, baseModelVersion: '${nb['model_version']}',
      generatedAt: DateTime.now().toUtc(), baseGeneratedAt: DateTime.tryParse('${nb['generated_at']}') ?? DateTime.now().toUtc(),
      sets: picked, setScores: pickedScores, pool: nums, rules: kRules,
      signals: {
        'hypothesis': {'validated_count': liveDirs.length, 'applied': liveDirs.isNotEmpty, 'directions': liveDirs,
            'research_count': (hypPayload['research_count'] as num?)?.toInt() ?? 0},
        'correction': {'n': corrN, 'mean_effect': corrMean, 't': corrT, 'applied': corrApplied},
        'joint': {'gate': jointRow?['gate_status'] ?? 'none', 'applied': jointPass, 'numbers': jointNums.toList()..sort()},
        'store_spatial_mnd': {'applied': false, 'reason': '번호 확률 우위 미검증 — 번호 점수에 미반영'},
        'candidates_evaluated': cands.length,
      },
      verifiedEdge: verifiedEdge,
      note: verifiedEdge
          ? '검증 통과 신호가 반영됐으나 당첨확률 향상은 보장되지 않음 (내부 점수는 확률이 아님)'
          : '검증된 당첨확률 우위 없음 — 모든 조합의 1등 확률은 동일. 내부 점수는 정렬용이며 확률이 아님',
    );
    return rec;
  }
}

// ══════════════════════════════════════════════════════════════
// 공식 최종 예측 — 단일 출처
// ══════════════════════════════════════════════════════════════

/// 공식 최종 예측 결정 (순수 함수 결과)
enum OfficialAction {
  /// 최신 학습 회차(latestTrain) 스냅샷이 이미 저장됨 → 그대로 사용
  useStored,

  /// 추첨 전 + latestTrain 스냅샷 없음 → latestTrain 기준 새 스냅샷 생성·저장 (기존 행 보존)
  buildNew,

  /// 추첨 후(또는 판매 마감 후) + latestTrain 스냅샷 없음 → 재생성 없이 최신 저장본 (postDrawNoRebuild)
  latestStoredPostDraw,

  /// 기본 후보(number_base) 없음 또는 추첨 여부 미확인 → 재생성 없이 최신 저장본
  latestStored,

  /// 저장본도 기본 후보도 없음 → '해당 회차 최종 예측 준비 중'
  preparing,

  /// 추첨 전인데 직전 회차(목표−1)까지 학습한 스냅샷도 기본 후보도 없음 → 직전 회차가 엔진에 반영될 때까지 대기.
  /// 더 이전 회차까지만 학습한 번호를 이 회차 공식 번호로 대신 쓰지 않는다.
  awaitingEngine,

  /// 계산·등록은 끝났지만 앱 공개 전 (월요일 0시 KST 자동 공개 또는 관리자 수동 추천)
  scheduled,
}

class OfficialDecision {
  final OfficialAction action;

  /// 읽을(또는 만들) 학습 회차. preparing 이면 null.
  final int? training;

  /// 목표 회차가 아직 추첨 전(판매 마감 전)으로 확인된 경우만 true
  final bool isPreDraw;
  const OfficialDecision(this.action, this.training, {required this.isPreDraw});
}

/// 목표 회차 판매 마감 시각(UTC) — 추첨일(토) 20:00 KST = 11:00 UTC.
/// 기준 회차 [knownRound] 의 추첨일 [knownDrawDate]('YYYY-MM-DD' 또는 'YYYY.MM.DD')에서 주 단위로 계산. 해석 실패 = null.
DateTime? lottoSalesCloseUtc(int targetRound, {required int knownRound, required String knownDrawDate}) {
  final d = DateTime.tryParse(knownDrawDate.trim().replaceAll('.', '-'));
  if (d == null) return null;
  final day = DateTime.utc(d.year, d.month, d.day).add(Duration(days: 7 * (targetRound - knownRound)));
  return DateTime.utc(day.year, day.month, day.day, 11);
}

/// 공식 최종 예측 결정 규칙 (순수 함수, 단위 테스트 대상)
///   [latestTrain]     목표 회차의 활성 버전 number_base 최신 학습 회차 (없으면 null)
///   [storedTrainings] 목표 회차에 저장된 fr 스냅샷의 학습 회차들
///   [latestDrawn]     lotto_winning_numbers 최신 회차 (조회 실패 = null → 추첨 여부 미확인 → 새로 만들지 않음)
///   [salesCloseUtc]   목표 회차 판매 마감 시각 (모르면 null) — 지났으면 추첨 후로 본다
OfficialDecision decideOfficialAction({
  required int targetRound,
  required int? latestTrain,
  required List<int> storedTrainings,
  required int? latestDrawn,
  DateTime? salesCloseUtc,
  DateTime? nowUtc,
}) {
  final now = (nowUtc ?? DateTime.now()).toUtc();
  final salesClosed = salesCloseUtc != null && !now.isBefore(salesCloseUtc);
  final drawn = (latestDrawn != null && targetRound <= latestDrawn) || salesClosed;
  final preDraw = latestDrawn != null && targetRound > latestDrawn && !salesClosed;

  // 추첨 전 공식 번호는 직전 회차(목표−1)까지 학습한 것만 인정한다.
  // (예: 1246회 추첨 후 1247회 번호는 1246회까지 학습해야 함 — 1245회까지 학습한 번호를 대신 쓰지 않음)
  if (preDraw) {
    final need = targetRound - 1;
    if (targetRound > latestDrawn + 1) return OfficialDecision(OfficialAction.awaitingEngine, null, isPreDraw: true);
    if (storedTrainings.contains(need)) return OfficialDecision(OfficialAction.useStored, need, isPreDraw: true);
    if (latestTrain == need) return OfficialDecision(OfficialAction.buildNew, need, isPreDraw: true);
    return OfficialDecision(OfficialAction.awaitingEngine, null, isPreDraw: true);
  }

  if (latestTrain != null && storedTrainings.contains(latestTrain)) {
    return OfficialDecision(OfficialAction.useStored, latestTrain, isPreDraw: preDraw);
  }
  if (latestTrain != null && preDraw) {
    return OfficialDecision(OfficialAction.buildNew, latestTrain, isPreDraw: preDraw);
  }
  if (storedTrainings.isEmpty) {
    return OfficialDecision(OfficialAction.preparing, null, isPreDraw: preDraw);
  }
  final latestStored = storedTrainings.reduce((a, b) => a > b ? a : b);
  return OfficialDecision(drawn ? OfficialAction.latestStoredPostDraw : OfficialAction.latestStored, latestStored,
      isPreDraw: preDraw);
}

const String kOfficialStatusOk = 'official';
const String kOfficialStatusPostDraw = 'post_draw_no_rebuild';
const String kOfficialStatusStored = 'stored_no_rebuild';
const String kOfficialStatusPreparing = 'preparing';
const String kOfficialStatusAwaitingEngine = 'awaiting_engine';
const String kOfficialStatusScheduled = 'scheduled';
const String kOfficialPreparingMessage = '해당 회차 최종 예측 준비 중';

class OfficialPrediction {
  /// [kOfficialStatusOk] | [kOfficialStatusPostDraw] | [kOfficialStatusStored] | [kOfficialStatusPreparing]
  final String status;
  final OfficialAction action;
  final FinalRecommendation? rec;
  final int targetRound;

  /// 목표 회차의 number_base 최신 학습 회차 (없으면 null)
  final int? latestTrain;

  /// 조회 시점에 목표 회차가 추첨 전(판매 마감 전)으로 확인됐는지
  final bool isPreDraw;

  /// 공개 예정 표시 ('10/21(월) 0시') — [kOfficialStatusScheduled] 일 때
  final String? releaseLabel;
  const OfficialPrediction({
    required this.status,
    required this.action,
    required this.targetRound,
    required this.isPreDraw,
    this.rec,
    this.latestTrain,
    this.releaseLabel,
  });

  String? get snapshotId => rec?.snapshotId;
  String get version => rec?.version ?? kFinalRecVersion;
  int? get trainingEndRound => rec?.trainingEndRound;
  DateTime? get generatedAt => rec?.generatedAt;
  bool get hasSets => rec != null && rec!.sets.isNotEmpty;
  bool get postDrawNoRebuild => status == kOfficialStatusPostDraw;

  /// 스냅샷 표시용 짧은 id (uuid 앞 8자리). 저장되지 않았으면 null.
  String? get shortSnapshotId {
    final id = snapshotId;
    if (id == null || id.isEmpty) return null;
    return id.length > 8 ? id.substring(0, 8) : id;
  }

  /// 상태 안내 (정상 공식 예측이면 null)
  String? get statusNote => switch (status) {
        kOfficialStatusPreparing => '$targetRound회 $kOfficialPreparingMessage',
        kOfficialStatusScheduled => '$targetRound회 추천번호는 ${releaseLabel ?? '월요일 0시'}에 엔진이 자동으로 만듭니다 — '
            '그 전에 필요하면 브리핑 맨 위 [수동 추천]으로 지금 실행하세요',
        kOfficialStatusAwaitingEngine => '$targetRound회 엔진 실행 대기 — ${targetRound - 1}회 결과를 반영한 번호가 만들어지면 표시합니다 '
            '(이전 회차까지만 학습한 번호를 대신 표시하지 않음)',
        kOfficialStatusPostDraw => '추첨 후 조회 — 최신 학습 회차(${latestTrain ?? '-'}회) 기준 스냅샷이 없어 '
            '저장된 ${trainingEndRound ?? '-'}회 기준 스냅샷을 표시합니다 (추첨 후에는 새로 만들지 않음)',
        kOfficialStatusStored => '최신 학습 기준 스냅샷을 새로 만들지 않아 저장된 ${trainingEndRound ?? '-'}회 기준 스냅샷을 표시합니다',
        _ => null,
      };
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 생성 시각 표시 (기기 시간대)
String officialTimeLabel(DateTime t) {
  final l = t.toLocal();
  return '${l.year}-${_two(l.month)}-${_two(l.day)} ${_two(l.hour)}:${_two(l.minute)}';
}

/// 관리자용 출처 줄 — 모든 화면 동일
String officialProvenanceLine(OfficialPrediction p) {
  final snap = p.shortSnapshotId == null ? '스냅샷 미저장' : '스냅샷 #${p.shortSnapshotId}';
  final gen = p.generatedAt == null ? '-' : officialTimeLabel(p.generatedAt!);
  return '공식 최종 추천번호 · ${p.version} · ${p.trainingEndRound ?? '-'}회까지 학습 → ${p.targetRound}회 · $snap · 생성 $gen';
}

/// 일반 사용자용 출처 줄 (엔진 내부 정보 없음)
String officialPublicLine(OfficialPrediction p) => '${p.targetRound}회 · ${p.trainingEndRound ?? '-'}회까지 반영';

class OfficialPredictionService {
  OfficialPredictionService._();
  static final instance = OfficialPredictionService._();

  static const Duration _ttl = Duration(minutes: 10);
  final Map<int, (DateTime, Future<OfficialPrediction>)> _cache = {};

  void clearCache() => _cache.clear();

  /// 목표 회차의 공식 최종 예측. 화면 간 10분 메모리 캐시 공유(진행 중 요청도 공유),
  /// [force] 이면 캐시를 비우고 다시 조회한다 (새로고침 버튼).
  Future<OfficialPrediction> load(int targetRound, {bool force = false}) {
    if (force) _cache.clear();
    final hit = _cache[targetRound];
    if (hit != null && DateTime.now().difference(hit.$1) < _ttl) return hit.$2;
    final f = _resolve(targetRound);
    _cache[targetRound] = (DateTime.now(), f);
    // 실패는 캐시하지 않음 (호출자는 원래 Future 의 오류를 그대로 받는다)
    f.then((_) {}, onError: (Object _) {
      if (identical(_cache[targetRound]?.$2, f)) _cache.remove(targetRound);
    });
    return f;
  }

  Future<OfficialPrediction> _resolve(int targetRound) async {
    final engine = FinalRecommendationEngine.instance;
    final latestTrain = await engine.latestNumberBaseTraining(targetRound);
    final stored = await engine.storedTrainings(targetRound);
    final recent = await SupabaseService.getRecentWinningNumbers(1);
    final latestDrawn = recent.isEmpty ? null : recent.first.round;
    final close = recent.isEmpty
        ? null
        : lottoSalesCloseUtc(targetRound, knownRound: recent.first.round, knownDrawDate: recent.first.drawDate);
    final d = decideOfficialAction(
      targetRound: targetRound,
      latestTrain: latestTrain,
      storedTrainings: stored,
      latestDrawn: latestDrawn,
      salesCloseUtc: close,
    );

    OfficialPrediction out(String status, OfficialAction action, FinalRecommendation? rec, {String? release}) =>
        OfficialPrediction(
            status: status, action: action, rec: rec, targetRound: targetRound, latestTrain: latestTrain,
            isPreDraw: d.isPreDraw, releaseLabel: release);

    // 앱 공개 시점: 다음 회차 추천은 월요일 0시(KST) 또는 수동 추천 후에만 보여준다 (서버는 제한 없음)
    if (!ResearchRuntime.serverWriter && d.isPreDraw && latestDrawn == targetRound - 1) {
      final rs = await RecommendRelease.state(targetRound, prevDrawDate: recent.first.drawDate);
      if (!rs.released) return out(kOfficialStatusScheduled, OfficialAction.scheduled, null, release: rs.releaseLabel);
    }

    Future<OfficialPrediction> latestStoredOr(String status, OfficialAction action) async {
      if (stored.isEmpty) return out(kOfficialStatusPreparing, OfficialAction.preparing, null);
      final rec = await engine.loadStored(targetRound, trainingEndRound: stored.reduce((a, b) => a > b ? a : b));
      return rec == null ? out(kOfficialStatusPreparing, OfficialAction.preparing, null) : out(status, action, rec);
    }

    switch (d.action) {
      case OfficialAction.useStored:
        final rec = await engine.loadStored(targetRound, trainingEndRound: d.training);
        if (rec != null) return out(kOfficialStatusOk, d.action, rec);
        return out(kOfficialStatusPreparing, OfficialAction.preparing, null);
      case OfficialAction.buildNew:
        // buildAndStore 는 목표 회차의 최신 학습 회차 number_base 행으로 만든다 (= latestTrain)
        final built = await engine.buildAndStore(targetRound);
        if (built != null && built.trainingEndRound == latestTrain && built.sets.isNotEmpty) {
          return out(kOfficialStatusOk, d.action, built);
        }
        // 생성 불가 → 재생성 없이 최신 저장본 (없으면 준비 중)
        return latestStoredOr(kOfficialStatusStored, OfficialAction.latestStored);
      case OfficialAction.latestStoredPostDraw:
        return latestStoredOr(kOfficialStatusPostDraw, d.action);
      case OfficialAction.latestStored:
        return latestStoredOr(kOfficialStatusStored, d.action);
      case OfficialAction.preparing:
        return out(kOfficialStatusPreparing, OfficialAction.preparing, null);
      case OfficialAction.awaitingEngine:
        return out(kOfficialStatusAwaitingEngine, OfficialAction.awaitingEngine, null);
      case OfficialAction.scheduled:
        return out(kOfficialStatusScheduled, OfficialAction.scheduled, null);
    }
  }
}
