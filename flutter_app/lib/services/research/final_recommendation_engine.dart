// ══════════════════════════════════════════════════════════════
// 최종 구매예측 추천번호 — 랜덤확률분석엔진의 최종 결과 카드용
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
// ══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../rpa_number_core.dart' show rpaActualIndicatorValues, rpaIndicatorBaselines;
import '../rpa_unified_prediction.dart';
import 'research_core.dart';

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
  const FinalRecommendation({
    required this.targetRound, required this.trainingEndRound, required this.version, required this.baseModelVersion,
    required this.generatedAt, required this.baseGeneratedAt, required this.sets, required this.setScores,
    required this.pool, required this.rules, required this.signals, required this.verifiedEdge, required this.note,
  });

  Map<String, dynamic> toJson() => {
        'target_round': targetRound, 'training_end_round': trainingEndRound, 'version': version,
        'base_model_version': baseModelVersion, 'generated_at': generatedAt.toUtc().toIso8601String(),
        'base_generated_at': baseGeneratedAt.toUtc().toIso8601String(),
        'sets': sets, 'set_scores': setScores, 'pool': pool, 'rules': rules, 'signals': signals,
        'verified_edge': verifiedEdge, 'note': note,
      };

  factory FinalRecommendation.fromJson(Map<String, dynamic> j) => FinalRecommendation(
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

  /// 저장된 결과가 있으면 반환, 없으면 기본 후보가 있을 때만 생성·저장 (덮어쓰기 없음)
  Future<FinalRecommendation?> ensureStored(int targetRound) async {
    final stored = await loadStored(targetRound);
    if (stored != null) return stored;
    return buildAndStore(targetRound);
  }

  Future<FinalRecommendation?> loadStored(int targetRound) async {
    try {
      final r = await _db.from('research_results').select('payload')
          .eq('research_type', 'final_recommendation').eq('model_version', kFinalRecVersion)
          .eq('target_round', targetRound).order('training_end_round', ascending: false).limit(1);
      final l = List<Map<String, dynamic>>.from(r as List);
      if (l.isEmpty) return null;
      return FinalRecommendation.fromJson(Map<String, dynamic>.from(l.first['payload'] as Map));
    } catch (_) {
      return null;
    }
  }

  Future<FinalRecommendation?> buildAndStore(int targetRound) async {
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
    try {
      await _db.from('research_results').upsert({
        'research_type': 'final_recommendation', 'model_version': kFinalRecVersion,
        'training_end_round': te, 'target_round': targetRound, 'payload': rec.toJson(),
      }, onConflict: 'research_type,model_version,training_end_round,target_round', ignoreDuplicates: true);
    } catch (e) {
      debugPrint('[FinalRec] persist skipped: $e');
    }
    return (await loadStored(targetRound)) ?? rec;
  }
}
