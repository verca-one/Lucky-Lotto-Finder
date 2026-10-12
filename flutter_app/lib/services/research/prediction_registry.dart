// ══════════════════════════════════════════════════════════════
// 예측력 자동 검증 — 사전 등록·잠금·추첨 후 채점·무작위 대조군 비교
//
// 흐름: 새 회차 데이터 확보 → 다음 회차 예측을 알고리즘별로 등록(잠금)
//       → 추첨 결과가 DB에 들어오면 자동 채점 → 알고리즘별 누적 통계·상태 판정
// 상태 기준(평가 시작 전 고정):
//   연구 중            : 유효 채점 < 20회차
//   검증 후보          : ≥20회차, 무작위 대비 평균 일치 개수 차이 > 0
//   통계적 우위 확인   : ≥52회차, 차이 > 0, Holm 보정 p < 0.01
//   재현 검증          : ≥104회차, 전반·후반 모두 차이 > 0, 후반 p < 0.05
//   성능 저하·재검증   : ≥20회차, 차이 ≤ 0
// 통계적 우위가 관측되어도 운영 엔진에 자동 반영하지 않는다.
// ══════════════════════════════════════════════════════════════

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/lotto_winning_number.dart';
import 'research_core.dart';
import 'research_runtime.dart';

class AlgorithmSummary {
  final String algorithm, version;
  final int registered, verified, invalid;
  final double meanMatches, diff, se, t, p, pHolm;
  final int atLeast3Sets, totalSets;
  final List<double> atLeast3Ci;
  final int bestRank;
  final String status;
  final double? firstHalfDiff, secondHalfDiff, secondHalfP;
  const AlgorithmSummary({
    required this.algorithm, required this.version, required this.registered, required this.verified,
    required this.invalid, required this.meanMatches, required this.diff, required this.se,
    required this.t, required this.p, required this.pHolm, required this.atLeast3Sets,
    required this.totalSets, required this.atLeast3Ci, required this.bestRank, required this.status,
    this.firstHalfDiff, this.secondHalfDiff, this.secondHalfP,
  });
}

class PredictionRegistry {
  PredictionRegistry._();
  static final instance = PredictionRegistry._();
  final _db = Supabase.instance.client;

  static const String algoNumberEngine = 'number_engine';
  static const String algoPurchase = 'purchase_prediction';
  static const String algoRandom = 'random_control';

  /// 대상 회차의 판매 마감 시각(토 20:00 KST = 11:00 UTC). 최신 추첨일에서 주 단위로 계산.
  static DateTime deadlineFor(int targetRound, LottoWinningNumber latest) {
    final d = DateTime.tryParse(latest.drawDate.replaceAll('.', '-')) ?? DateTime.now();
    final drawDay = DateTime.utc(d.year, d.month, d.day).add(Duration(days: 7 * (targetRound - latest.round)));
    return DateTime.utc(drawDay.year, drawDay.month, drawDay.day, 11);
  }

  /// 예측 등록 (이미 있으면 무시 — 번호 변경 불가)
  Future<bool> register({
    required String algorithm, required String version, required int targetRound,
    required int dataEndRound, required List<List<int>> sets, required DateTime deadline,
  }) async {
    if (!ResearchRuntime.serverWriter) return false; // 등록은 서버 파이프라인만
    if (sets.isEmpty) return false;
    final now = DateTime.now().toUtc();
    try {
      await _db.from('research_predictions').upsert({
        'algorithm': algorithm, 'version': version, 'target_round': targetRound,
        'data_end_round': dataEndRound, 'sets': sets, 'generated_at': now.toIso8601String(),
        'deadline_at': deadline.toIso8601String(), 'pre_deadline': now.isBefore(deadline),
        'locked': true, 'status': 'pending',
      }, onConflict: 'algorithm,version,target_round', ignoreDuplicates: true);
      return true;
    } catch (e) {
      debugPrint('[Registry] register skipped: $e');
      return false;
    }
  }

  List<List<int>> randomControlSets(int targetRound, {int count = 5}) {
    final rng = SeededRandom(targetRound * 104729 + 17);
    return List.generate(count, (_) => rng.combo());
  }

  /// 추첨 결과가 들어온 회차의 미채점 예측을 채점
  Future<int> verifyPending(List<LottoWinningNumber> allData) async {
    if (!ResearchRuntime.serverWriter) return 0; // 채점은 서버 파이프라인만
    final byRound = {for (final d in allData) d.round: d};
    List<Map<String, dynamic>> rows;
    try {
      final r = await _db.from('research_predictions')
          .select('id,algorithm,version,target_round,sets,generated_at,deadline_at,pre_deadline')
          .eq('status', 'pending').limit(2000);
      rows = List<Map<String, dynamic>>.from(r as List);
    } catch (_) {
      return 0;
    }
    int done = 0;
    for (final r in rows) {
      final actual = byRound[r['target_round'] as int];
      if (actual == null) continue;
      final sets = (r['sets'] as List).map<List<int>>((s) => (s as List).map<int>((n) => (n as num).toInt()).toList()).toList();
      final scored = sets.map((s) => scoreSet(s, actual.numbers, actual.bonusNumber)).toList();
      final matches = scored.map((s) => s[0]).toList();
      final ranks = scored.map((s) => s[2]).where((x) => x > 0).toList();
      final gen = DateTime.tryParse('${r['generated_at']}');
      final dl = DateTime.tryParse('${r['deadline_at']}');
      final valid = (r['pre_deadline'] as bool? ?? false) && gen != null && dl != null && gen.isBefore(dl);
      final verification = {
        'actual_numbers': actual.numbers, 'bonus': actual.bonusNumber,
        'matches': matches, 'bonus_hit': scored.map((s) => s[1]).toList(), 'ranks': scored.map((s) => s[2]).toList(),
        'mean_matches': matches.reduce((a, b) => a + b) / matches.length,
        'best_rank': ranks.isEmpty ? 0 : ranks.reduce(min),
        'at_least3': matches.where((m) => m >= 3).length,
        'random_expected_mean': kExpectedMatches,
        'valid_pre_deadline': valid, 'verified_at': DateTime.now().toUtc().toIso8601String(),
      };
      try {
        await _db.from('research_predictions').update({
          'verification': verification, 'status': valid ? 'verified' : 'invalid',
        }).eq('id', r['id']);
        done++;
      } catch (e) {
        debugPrint('[Registry] verify update error: $e');
      }
    }
    return done;
  }

  /// 알고리즘별 누적 요약 (유효 채점만)
  Future<List<AlgorithmSummary>> summarize() async {
    List<Map<String, dynamic>> rows;
    try {
      final r = await _db.from('research_predictions')
          .select('algorithm,version,target_round,status,verification').order('target_round', ascending: true).limit(5000);
      rows = List<Map<String, dynamic>>.from(r as List);
    } catch (_) {
      return [];
    }
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) { groups.putIfAbsent('${r['algorithm']}|${r['version']}', () => []).add(r); }
    final prelim = <Map<String, dynamic>>[];
    groups.forEach((k, list) {
      final parts = k.split('|');
      final verified = list.where((r) => r['status'] == 'verified').toList();
      final invalid = list.where((r) => r['status'] == 'invalid').length;
      final means = verified.map((r) => ((r['verification'] as Map)['mean_matches'] as num).toDouble()).toList();
      int atLeast3 = 0, total = 0, best = 0;
      for (final r in verified) {
        final v = r['verification'] as Map;
        atLeast3 += (v['at_least3'] as num).toInt();
        total += (v['matches'] as List).length;
        final br = (v['best_rank'] as num).toInt();
        if (br > 0 && (best == 0 || br < best)) best = br;
      }
      final t = oneSampleT(means, kExpectedMatches);
      double? h1, h2, h2p;
      if (means.length >= 104) {
        final half = means.length ~/ 2;
        final a = oneSampleT(means.sublist(0, half), kExpectedMatches);
        final b = oneSampleT(means.sublist(half), kExpectedMatches);
        h1 = a[0] - kExpectedMatches; h2 = b[0] - kExpectedMatches; h2p = b[3];
      }
      prelim.add({
        'algorithm': parts[0], 'version': parts[1], 'registered': list.length, 'verified': verified.length,
        'invalid': invalid, 'mean': t[0], 'se': t[1], 't': t[2], 'p': t[3], 'atLeast3': atLeast3,
        'total': total, 'best': best, 'h1': h1, 'h2': h2, 'h2p': h2p,
      });
    });
    final ps = prelim.map((m) => (m['p'] as double).isNaN ? 1.0 : m['p'] as double).toList();
    final adj = holmAdjust(ps);
    final out = <AlgorithmSummary>[];
    for (int i = 0; i < prelim.length; i++) {
      final m = prelim[i];
      final n = m['verified'] as int;
      final mean = m['mean'] as double;
      final diff = mean.isNaN ? double.nan : mean - kExpectedMatches;
      String status;
      if (n < 20) {
        status = '연구 중';
      } else if (diff <= 0) {
        status = '성능 저하·재검증 필요';
      } else if (n >= 104 && (m['h1'] as double? ?? -1) > 0 && (m['h2'] as double? ?? -1) > 0 && (m['h2p'] as double? ?? 1) < 0.05) {
        status = '재현 검증';
      } else if (n >= 52 && adj[i] < 0.01) {
        status = '통계적 우위 확인';
      } else {
        status = '검증 후보';
      }
      out.add(AlgorithmSummary(
        algorithm: m['algorithm'] as String, version: m['version'] as String,
        registered: m['registered'] as int, verified: n, invalid: m['invalid'] as int,
        meanMatches: mean, diff: diff, se: m['se'] as double, t: m['t'] as double, p: m['p'] as double, pHolm: adj[i],
        atLeast3Sets: m['atLeast3'] as int, totalSets: m['total'] as int,
        atLeast3Ci: wilsonCi(m['atLeast3'] as int, m['total'] as int), bestRank: m['best'] as int, status: status,
        firstHalfDiff: m['h1'] as double?, secondHalfDiff: m['h2'] as double?, secondHalfP: m['h2p'] as double?,
      ));
    }
    out.sort((a, b) => a.algorithm.compareTo(b.algorithm));
    return out;
  }

  /// 최근 등록 예측 목록 (화면 표시용)
  Future<List<Map<String, dynamic>>> recent({int limit = 30}) async {
    try {
      final r = await _db.from('research_predictions')
          .select('algorithm,version,target_round,data_end_round,sets,generated_at,deadline_at,pre_deadline,status,verification')
          .order('target_round', ascending: false).limit(limit);
      return List<Map<String, dynamic>>.from(r as List);
    } catch (_) {
      return [];
    }
  }
}
