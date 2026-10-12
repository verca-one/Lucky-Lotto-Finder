// ══════════════════════════════════════════════════════════════
// 추첨예측 연구 엔진 (기존 Number Engine과 독립, 기존 DB 읽기 전용)
//
// A. 번호별 출현 빈도 검정 (관측 vs 기대, 다중검정 보정, 시기별 안정성)
// B. 실제 추첨 순서 — 데이터 미확보 (오름차순 정렬 번호를 순서로 쓰지 않음)
// C. 추첨기·공 물리 편향 — 데이터 미확보
// D. 기존 엔진 번호 WF 무작위 대조군 (rpa_prediction_snapshots 채점)
//    + 지역 WF 기저율 대조군 (상위 3개 시/도 vs 균등 3/17)
// ══════════════════════════════════════════════════════════════

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/lotto_winning_number.dart';
import '../rpa_store_engine.dart' show StoreWinRecord;
import 'research_core.dart';
import 'research_runtime.dart';

const String kDrawResearchVersion = 'dr-1.0';

class NumberFreqRow {
  final int number;
  final int observed;
  final double expected;
  final double z;
  final double p;
  final double pHolm;
  const NumberFreqRow(this.number, this.observed, this.expected, this.z, this.p, this.pHolm);
  Map<String, dynamic> toJson() => {
        'n': number, 'obs': observed, 'exp': expected, 'z': z, 'p': p, 'p_holm': pHolm,
      };
}

class NumberFrequencyResult {
  final int trainingEnd;
  final int rounds;
  final List<NumberFreqRow> main;      // 본번호 6개 기준
  final List<NumberFreqRow> bonus;     // 보너스 기준
  final double chiSq;                  // 본번호 적합도 χ² (df=44)
  final double chiP;
  final double bonusChiSq;
  final double bonusChiP;
  final int significantAfterHolm;      // Holm 보정 후 p<0.05 번호 수 (본번호)
  final List<Map<String, dynamic>> eras; // 시기별 χ²
  final double halfCorrelation;        // 전반/후반 z 상관 (안정성; 무작위면 ≈0)
  final String conclusion;

  const NumberFrequencyResult({
    required this.trainingEnd, required this.rounds, required this.main, required this.bonus,
    required this.chiSq, required this.chiP, required this.bonusChiSq, required this.bonusChiP,
    required this.significantAfterHolm, required this.eras, required this.halfCorrelation,
    required this.conclusion,
  });

  Map<String, dynamic> toJson() => {
        'training_end': trainingEnd, 'rounds': rounds,
        'main': main.map((r) => r.toJson()).toList(),
        'bonus': bonus.map((r) => r.toJson()).toList(),
        'chi_sq': chiSq, 'chi_p': chiP, 'bonus_chi_sq': bonusChiSq, 'bonus_chi_p': bonusChiP,
        'significant_after_holm': significantAfterHolm, 'eras': eras,
        'half_correlation': halfCorrelation, 'conclusion': conclusion,
      };
}

/// 기존 엔진(스냅샷) 번호 단위 WF를 무작위 기대와 비교한 결과
class EngineWfControl {
  final String modelVersion;
  final int rounds;              // 채점된 회차 수 (horizon 1)
  final int sets;                // 채점된 세트 수
  final double meanMatches;      // 세트당 평균 일치 개수
  final double randomMean;       // 무작위 기대 0.8
  final double se;               // 회차 평균 기준 표준오차
  final double t;
  final double p;
  final int atLeast3;            // 3개 이상 일치 세트 수
  final double atLeast3Rate;
  final double randomAtLeast3;   // 0.0238
  final List<double> atLeast3Ci; // Wilson 95%
  final int bestRank;            // 달성한 최고 등수 (0=없음)
  final Map<int, int> rankCounts;
  final int firstRound;
  final int lastRound;
  final String note;
  const EngineWfControl({
    required this.modelVersion, required this.rounds, required this.sets, required this.meanMatches,
    required this.randomMean, required this.se, required this.t, required this.p,
    required this.atLeast3, required this.atLeast3Rate, required this.randomAtLeast3,
    required this.atLeast3Ci, required this.bestRank, required this.rankCounts,
    required this.firstRound, required this.lastRound, required this.note,
  });
  Map<String, dynamic> toJson() => {
        'model_version': modelVersion, 'rounds': rounds, 'sets': sets, 'mean_matches': jsonNum(meanMatches),
        'random_mean': randomMean, 'se': jsonNum(se), 't': jsonNum(t), 'p': jsonNum(p), 'at_least3': atLeast3,
        'at_least3_rate': atLeast3Rate, 'random_at_least3': randomAtLeast3, 'at_least3_ci': atLeast3Ci,
        'best_rank': bestRank, 'rank_counts': rankCounts.map((k, v) => MapEntry('$k', v)),
        'first_round': firstRound, 'last_round': lastRound, 'note': note,
      };
}

/// 지역 WF(기존 Store/NR 지표)의 기저율 대조군
class RegionWfControl {
  final int rounds;
  final double uniformRandom3;    // 3/17
  final double baseRateTop3;      // 과거 상위 3개 시/도 (확장 윈도우, 누수 없음)
  final double baseRateTop3Recent30; // 직전 30회 상위 3 (기존 Store 지표와 동일 정의)
  final Map<String, int> sidoCounts;
  const RegionWfControl({
    required this.rounds, required this.uniformRandom3, required this.baseRateTop3,
    required this.baseRateTop3Recent30, required this.sidoCounts,
  });
  Map<String, dynamic> toJson() => {
        'rounds': rounds, 'uniform_random3': uniformRandom3, 'base_rate_top3': baseRateTop3,
        'base_rate_top3_recent30': baseRateTop3Recent30, 'sido_counts': sidoCounts,
      };
}

class DrawResearchEngine {
  DrawResearchEngine._();
  static final instance = DrawResearchEngine._();
  final _db = Supabase.instance.client;

  // ── 데이터 미확보 항목 (고정 보고) ──────────────────────────
  static const Map<String, String> unavailable = {
    '실제 공 추첨 순서': '공식 미공개. 오름차순 정렬 번호를 추첨 순서로 취급하지 않음 → 순서 편향 연구 불가',
    '추첨기 식별 정보': '공식 미공개 → 추첨기별 분포 연구 불가',
    '추첨기·공 세트 교체 이력': '공식 자료 없음(언론 보도 수준) → 교체 전후 비교 불가',
    '공 물리 측정 자료': '없음 → 과거 번호 빈도만으로 물리적 편향을 확정하지 않음',
  };

  // ── A. 번호별 출현 빈도 ─────────────────────────────────────
  NumberFrequencyResult analyzeNumberFrequency(List<LottoWinningNumber> allData, {int? trainingEnd}) {
    final te = trainingEnd ?? allData.map((d) => d.round).fold<int>(0, (a, b) => a > b ? a : b);
    final data = allData.where((d) => d.round <= te).toList()..sort((a, b) => a.round.compareTo(b.round));
    final n = data.length;

    List<NumberFreqRow> freqRows(int Function(LottoWinningNumber, int) counter, double expectedPer, double pPer) {
      final obs = List<int>.filled(46, 0);
      for (final d in data) {
        for (int k = 1; k <= 45; k++) {
          obs[k] += counter(d, k);
        }
      }
      final rows = <NumberFreqRow>[];
      final ps = <double>[];
      final sd = sqrt(n * pPer * (1 - pPer));
      for (int k = 1; k <= 45; k++) {
        final z = sd > 0 ? (obs[k] - expectedPer) / sd : 0.0;
        final p = twoSidedP(z);
        ps.add(p);
        rows.add(NumberFreqRow(k, obs[k], expectedPer, z, p, 1));
      }
      final adj = holmAdjust(ps);
      return List.generate(45, (i) => NumberFreqRow(rows[i].number, rows[i].observed, rows[i].expected, rows[i].z, rows[i].p, adj[i]));
    }

    double chi(List<NumberFreqRow> rows) =>
        rows.fold(0.0, (s, r) => s + (r.observed - r.expected) * (r.observed - r.expected) / r.expected);

    final main = freqRows((d, k) => d.numbers.contains(k) ? 1 : 0, n * 6 / 45, 6 / 45);
    final bonus = freqRows((d, k) => d.bonusNumber == k ? 1 : 0, n / 45, 1 / 45);
    final chiMain = chi(main);
    final chiBonus = chi(bonus);

    // 시기별 안정성: 4등분
    final eras = <Map<String, dynamic>>[];
    final q = max(1, n ~/ 4);
    for (int e = 0; e < 4; e++) {
      final slice = data.sublist(e * q, e == 3 ? n : min(n, (e + 1) * q));
      if (slice.isEmpty) continue;
      final obs = List<int>.filled(46, 0);
      for (final d in slice) { for (final x in d.numbers) { obs[x]++; } }
      final exp = slice.length * 6 / 45;
      final c = List.generate(45, (i) => (obs[i + 1] - exp) * (obs[i + 1] - exp) / exp).reduce((a, b) => a + b);
      eras.add({
        'from': slice.first.round, 'to': slice.last.round, 'rounds': slice.length,
        'chi_sq': c, 'chi_p': chiSquareSf(c, 44),
      });
    }
    // 전반/후반 z 상관
    double halfCorr = 0;
    if (n >= 100) {
      final half = n ~/ 2;
      List<double> zs(List<LottoWinningNumber> s) {
        final obs = List<int>.filled(46, 0);
        for (final d in s) { for (final x in d.numbers) { obs[x]++; } }
        final exp = s.length * 6 / 45;
        final sd = sqrt(s.length * (6 / 45) * (39 / 45));
        return List.generate(45, (i) => (obs[i + 1] - exp) / sd);
      }
      halfCorr = _pearson(zs(data.sublist(0, half)), zs(data.sublist(half)));
    }

    final sig = main.where((r) => r.pHolm < 0.05).length;
    final chiP = chiSquareSf(chiMain, 44);
    final conclusion = sig == 0 && chiP > 0.05
        ? '$n회차 기준 번호별 출현 빈도는 균등분포와 통계적으로 구분되지 않음(χ² p=${chiP.toStringAsFixed(3)}, Holm 보정 후 유의 번호 0개). 전반·후반 편차 상관 ${halfCorr.toStringAsFixed(2)} → 시기 간 재현되는 편향 없음.'
        : '일부 번호에서 편차가 관측됨(Holm 보정 후 유의 $sig개, χ² p=${chiP.toStringAsFixed(4)}). 전반·후반 상관 ${halfCorr.toStringAsFixed(2)}. 물리적 원인 자료가 없으므로 편향으로 확정하지 않고 미래 회차에서 재현되는지 추적함.';

    return NumberFrequencyResult(
      trainingEnd: te, rounds: n, main: main, bonus: bonus,
      chiSq: chiMain, chiP: chiP, bonusChiSq: chiBonus, bonusChiP: chiSquareSf(chiBonus, 44),
      significantAfterHolm: sig, eras: eras, halfCorrelation: halfCorr, conclusion: conclusion,
    );
  }

  double _pearson(List<double> a, List<double> b) {
    final n = a.length;
    final ma = a.reduce((x, y) => x + y) / n, mb = b.reduce((x, y) => x + y) / n;
    double sab = 0, saa = 0, sbb = 0;
    for (int i = 0; i < n; i++) {
      sab += (a[i] - ma) * (b[i] - mb); saa += (a[i] - ma) * (a[i] - ma); sbb += (b[i] - mb) * (b[i] - mb);
    }
    return saa > 0 && sbb > 0 ? sab / sqrt(saa * sbb) : 0;
  }

  // ── D-1. 기존 엔진 번호 WF 무작위 대조군 ─────────────────────
  /// rpa_prediction_snapshots(horizon 1, 읽기 전용)의 recommended_sets를 실제 번호로 채점.
  /// 주의: 스냅샷은 사후 재현(replay) WF이며 사전 등록 예측이 아님 → 보고서에 명시.
  Future<List<EngineWfControl>> evaluateEngineNumberWf(List<LottoWinningNumber> allData) async {
    final byRound = {for (final d in allData) d.round: d};
    List<Map<String, dynamic>> rows;
    try {
      final r = await _db
          .from('rpa_prediction_snapshots')
          .select('target_round,training_end_round,model_version,recommended_sets,candidate_numbers')
          .order('target_round', ascending: true)
          .limit(5000);
      rows = List<Map<String, dynamic>>.from(r as List);
    } catch (e) {
      debugPrint('[DrawResearch] snapshots load error: $e');
      return [];
    }
    final byVersion = <String, List<Map<String, dynamic>>>{};
    final noDataByVersion = <String, int>{}; // 번호 세트·후보가 모두 없어 채점 불가한 회차 수
    for (final r in rows) {
      final tr = r['target_round'] as int, te = r['training_end_round'] as int;
      if (tr - te != 1) continue; // horizon 1만 (데이터 누수 없는 직후 회차)
      if (!byRound.containsKey(tr)) continue;
      final hasSets = (r['recommended_sets'] as List? ?? []).isNotEmpty;
      final hasCand = r['candidate_numbers'] is List && (r['candidate_numbers'] as List).isNotEmpty;
      final ver = '${r['model_version']}';
      if (!hasSets && !hasCand) {
        noDataByVersion[ver] = (noDataByVersion[ver] ?? 0) + 1;
        continue;
      }
      // 세트가 비어 있고 후보 번호(점수순)만 있으면 상위 6개를 1세트로 채점
      final key = hasSets ? ver : '$ver (상위6 후보)';
      byVersion.putIfAbsent(key, () => []).add(r);
    }
    final out = <EngineWfControl>[];
    noDataByVersion.forEach((ver, n) {
      out.add(EngineWfControl(
        modelVersion: ver, rounds: 0, sets: 0, meanMatches: double.nan, randomMean: kExpectedMatches,
        se: double.nan, t: double.nan, p: double.nan, atLeast3: 0, atLeast3Rate: 0,
        randomAtLeast3: kProbAtLeast3, atLeast3Ci: const [0, 0], bestRank: 0, rankCounts: const {},
        firstRound: 0, lastRound: 0,
        note: 'v$ver 재현(replay) 스냅샷 $n회차는 번호 세트·후보 번호가 저장되지 않아 사후 채점 불가. '
            '기존 엔진의 과거 번호 WF는 저장 데이터로 검증할 수 없으며, 사전 등록 레지스트리(research_predictions)가 유일한 검증 경로입니다.',
      ));
    });
    byVersion.forEach((ver, list) {
      final perRoundMean = <double>[];
      int sets = 0, atLeast3 = 0, bestRank = 0;
      final rankCounts = <int, int>{};
      int first = 1 << 30, last = 0;
      for (final r in list) {
        final actual = byRound[r['target_round'] as int]!;
        final raw = r['recommended_sets'] as List? ?? [];
        var predSets = raw.map((s) => s is Map ? s['numbers'] : s)
            .where((s) => s is List && s.length == 6)
            .map<List<int>>((s) => (s as List).map<int>((n) => (n as num).toInt()).toList())
            .toList();
        if (predSets.isEmpty) {
          try {
            final rawCand = r['candidate_numbers'];
            final cand = (rawCand is List ? rawCand : const [])
                .whereType<Map>()
                .where((c) => c['n'] is num)
                .map((c) => MapEntry((c['n'] as num).toInt(), (c['s'] is num) ? (c['s'] as num).toDouble() : 0.0))
                .where((e) => e.key >= 1 && e.key <= 45)
                .toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final top6 = cand.map((e) => e.key).toSet().take(6).toList()..sort();
            if (top6.length == 6) predSets = [top6];
          } catch (e) {
            debugPrint('[DrawResearch] candidate parse skip round ${r['target_round']}: $e');
          }
        }
        if (predSets.isEmpty) continue;
        double sum = 0;
        for (final ps in predSets) {
          final sc = scoreSet(ps, actual.numbers, actual.bonusNumber);
          sum += sc[0];
          sets++;
          if (sc[0] >= 3) atLeast3++;
          if (sc[2] > 0) {
            rankCounts[sc[2]] = (rankCounts[sc[2]] ?? 0) + 1;
            if (bestRank == 0 || sc[2] < bestRank) bestRank = sc[2];
          }
        }
        perRoundMean.add(sum / predSets.length);
        first = min(first, actual.round); last = max(last, actual.round);
      }
      if (perRoundMean.isEmpty) return;
      final t = oneSampleT(perRoundMean, kExpectedMatches);
      final rate = sets > 0 ? atLeast3 / sets : 0.0;
      out.add(EngineWfControl(
        modelVersion: ver, rounds: perRoundMean.length, sets: sets,
        meanMatches: t[0], randomMean: kExpectedMatches, se: t[1], t: t[2], p: t[3],
        atLeast3: atLeast3, atLeast3Rate: rate, randomAtLeast3: kProbAtLeast3,
        atLeast3Ci: wilsonCi(atLeast3, sets), bestRank: bestRank, rankCounts: rankCounts,
        firstRound: first, lastRound: last,
        note: '사후 재현(replay) WF 스냅샷 채점 — 사전 등록 예측이 아니므로 참고용. 무작위 기대: 세트당 0.80개, 3개+ 일치 2.38%.',
      ));
    });
    out.sort((a, b) => b.rounds.compareTo(a.rounds));
    _persist('engine_wf_control', allData.map((d) => d.round).fold<int>(0, (a, b) => a > b ? a : b), {'versions': out.map((e) => e.toJson()).toList()});
    return out;
  }

  // ── D-2. 지역 WF 기저율 대조군 ───────────────────────────────
  RegionWfControl evaluateRegionWfControl(List<StoreWinRecord> history, List<LottoWinningNumber> allData) {
    // 회차별 대표 시/도 (기존 WF와 동일: 해당 회차 첫 1등 판매점 지역의 첫 토큰)
    final sidoByRound = <int, String>{};
    final sorted = List<StoreWinRecord>.of(history)..sort((a, b) => a.round.compareTo(b.round));
    for (final r in sorted) {
      final s = r.region.trim().split(' ').first;
      if (s.isNotEmpty) sidoByRound.putIfAbsent(r.round, () => s);
    }
    final rounds = sidoByRound.keys.toList()..sort();
    final counts = <String, int>{};
    int hitsExpanding = 0, hitsRecent = 0, evaluated = 0;
    final seq = <String>[];
    for (final r in rounds) {
      final actual = sidoByRound[r]!;
      if (seq.length >= 30) {
        List<String> top3(Iterable<String> src) {
          final c = <String, int>{};
          for (final s in src) { c[s] = (c[s] ?? 0) + 1; }
          final e = c.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          return e.take(3).map((x) => x.key).toList();
        }
        if (top3(seq).contains(actual)) hitsExpanding++;
        if (top3(seq.sublist(seq.length - 30)).contains(actual)) hitsRecent++;
        evaluated++;
      }
      seq.add(actual);
      counts[actual] = (counts[actual] ?? 0) + 1;
    }
    final res = RegionWfControl(
      rounds: evaluated, uniformRandom3: 3 / 17,
      baseRateTop3: evaluated > 0 ? hitsExpanding / evaluated : 0,
      baseRateTop3Recent30: evaluated > 0 ? hitsRecent / evaluated : 0,
      sidoCounts: counts,
    );
    _persist('region_wf_control', allData.map((d) => d.round).fold<int>(0, (a, b) => a > b ? a : b), res.toJson());
    return res;
  }

  Future<void> persistNumberFrequency(NumberFrequencyResult r) =>
      _persist('number_frequency', r.trainingEnd, r.toJson());

  Future<void> _persist(String type, int trainingEnd, Map<String, dynamic> payload) async {
    if (!ResearchRuntime.serverWriter) return; // 연구 결과 저장은 서버 파이프라인만
    try {
      await _db.from('research_results').upsert({
        'research_type': type, 'model_version': kDrawResearchVersion,
        'training_end_round': trainingEnd, 'target_round': 0, 'payload': payload,
      }, onConflict: 'research_type,model_version,training_end_round,target_round');
    } catch (e) {
      debugPrint('[DrawResearch] persist $type skipped: $e'); // 테이블 미생성 시 무시
    }
  }
}
