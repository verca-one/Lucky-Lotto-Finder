// ══════════════════════════════════════════════════════════════
// 가설 순차 재현 (500회 가설 생성 → 501회 보정 → … → 최신 회차)
//
// 기존 HypothesisEngine은 가설 생성 시점 이후의 "미래 검증"만 실시간으로 쌓는다.
// 이 모듈은 과거를 회차 순서대로 재현해 같은 규칙으로 가설을 발견·검증·전환하고,
// 그 결과를 연구 테이블(research_results)에만 저장한다. 운영 가설 테이블은 건드리지 않는다.
//
// 재현 규칙(기존 엔진과 동일):
//   - 발견: 각 회차 t에서 SequentialPatternFinder.find(데이터 ≤ t) 상위 10개, 같은 (지표,방향,horizon)은 1회만
//   - 전환: discovered→observing(다음 회차), n≥5 & rate≥0.65→validating, ≥0.72→accepted,
//           <0.35→weakened, weakened & n≥10 & <0.35→rejected
// 전문가 보정(기존 엔진과 다른 점, 보고서에 명시):
//   - horizon 반영: 트리거 상태(6지표 중 4개 일치)가 재현된 회차 t에서만 t+h 회차를 검증한다.
//     (기존 엔진은 horizon·트리거를 무시하고 매 회차 검증 — 비교용으로 함께 계산)
//   - 기준선은 방향 반영(above→base, below→1-base)
//   - 핵심 지표: "채택(accepted) 이후"의 적중률 vs 기준선 — 채택 전 데이터는 선택 편향이 있으므로 제외
// ══════════════════════════════════════════════════════════════

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/lotto_winning_number.dart';
import '../rpa_hypothesis_engine.dart' show SequentialPatternFinder;
import '../rpa_number_core.dart' show rpaActualIndicatorValues, rpaIndicatorBaselines, rpaIndicatorIds, rpaIndicatorLabels;
import 'research_core.dart';

const String kHypothesisReplayVersion = 'hr-1.0';
const int kHypothesisReplayStart = 500;

class _RHyp {
  final String key;
  final String indicator, direction;
  final int horizon;
  final int createdRound;
  final Map<String, String> trigger;
  final int histN;
  final double histRate;
  String status = 'discovered';
  int n = 0, success = 0;          // horizon 반영 검증
  int engN = 0, engSuccess = 0;    // 기존 엔진 방식(매 회차) 비교용
  int postN = 0, postSuccess = 0;  // accepted 이후
  int? acceptedRound, rejectedRound, weakenedRound;
  _RHyp(this.key, this.indicator, this.direction, this.horizon, this.createdRound, this.trigger, this.histN, this.histRate);
}

Map<String, dynamic> _replayIsolate(Map<String, dynamic> p) {
  final data = (p['data'] as List).map((m) => LottoWinningNumber(
        drawDate: '${m['d']}', round: m['r'] as int,
        numbers: List<int>.from(m['n'] as List), bonusNumber: m['b'] as int,
      )).toList()..sort((a, b) => a.round.compareTo(b.round));
  final start = p['start'] as int;
  final n = data.length;
  final vals = data.map((d) => rpaActualIndicatorValues(d.numbers)).toList();
  final roundIdx = {for (int i = 0; i < n; i++) data[i].round: i};

  String dirOf(double rate, double base) => rate > base + 0.05 ? 'above' : rate < base - 0.05 ? 'below' : 'neutral';
  // 10회 롤링 상태 (SequentialPatternFinder와 동일 규칙)
  final stateAt = List<Map<String, String>>.generate(n, (i) {
    final s = i >= 9 ? i - 9 : 0;
    final st = <String, String>{};
    for (final id in rpaIndicatorIds) {
      double sum = 0;
      for (int k = s; k <= i; k++) { sum += vals[k][id] ?? 0; }
      st[id] = dirOf(sum / (i - s + 1), rpaIndicatorBaselines[id] ?? 0.5);
    }
    return st;
  });

  final hyps = <String, _RHyp>{};
  final pending = <int, List<MapEntry<String, String>>>{}; // targetRound → [(hypKey, dir)]
  final timeline = <Map<String, dynamic>>[];
  final roundLogs = <Map<String, dynamic>>[]; // 회차별 실행 로그 (DB 저장용)
  const holdoutFrom = 1101; // 홀드아웃: 1101회 이후 채택-후 성과를 별도 집계
  int hoN = 0, hoS = 0; double hoBase = 0;
  int startIdx = roundIdx[start] ?? data.indexWhere((d) => d.round >= start);
  if (startIdx < 0) startIdx = 0;

  void transition(_RHyp h, String next, int round, String why) {
    timeline.add({'round': round, 'key': h.key, 'from': h.status, 'to': next, 'why': why});
    h.status = next;
    if (next == 'accepted') h.acceptedRound ??= round;
    if (next == 'weakened') h.weakenedRound = round;
    if (next == 'rejected') h.rejectedRound = round;
  }

  for (int i = startIdx; i < n; i++) {
    final t = data[i].round;
    int verifiedNow = 0, hitsNow = 0, createdNow = 0;
    final transitionsBefore = timeline.length;

    // 1) 이번 회차 결과로 보정 (horizon 반영 pending + 엔진 방식 매 회차)
    final due = pending.remove(t) ?? const [];
    for (final e in due) {
      final h = hyps[e.key];
      if (h == null || h.status == 'rejected') continue;
      final base = rpaIndicatorBaselines[h.indicator] ?? 0.5;
      final actualDir = (vals[i][h.indicator] ?? 0) > base * 0.99 ? 'above' : 'below';
      final hit = actualDir == h.direction;
      h.n++; if (hit) h.success++;
      verifiedNow++; if (hit) hitsNow++;
      if (h.status == 'accepted') {
        h.postN++; if (hit) h.postSuccess++;
        if (t >= holdoutFrom) { hoN++; if (hit) hoS++; hoBase += h.direction == 'above' ? base : 1 - base; }
      }
      if (h.n >= 5) {
        final rate = h.success / h.n;
        if (rate >= 0.65 && h.status == 'observing') transition(h, 'validating', t, '누적 ${h.success}/${h.n}');
        if (rate >= 0.72 && h.status == 'validating') transition(h, 'accepted', t, '누적 ${h.success}/${h.n}');
        if (rate < 0.35 && h.status != 'weakened' && h.status != 'rejected') transition(h, 'weakened', t, '누적 ${h.success}/${h.n}');
      }
    }
    for (final h in hyps.values) {
      if (h.status == 'rejected' || h.createdRound >= t) continue;
      final base = rpaIndicatorBaselines[h.indicator] ?? 0.5;
      final actualDir = (vals[i][h.indicator] ?? 0) > base * 0.99 ? 'above' : 'below';
      h.engN++; if (actualDir == h.direction) h.engSuccess++;
    }
    // 2) 상태 전진: discovered → observing, weakened 지속 → rejected
    for (final h in hyps.values) {
      if (h.status == 'discovered' && t > h.createdRound) transition(h, 'observing', t, '발견 후 다음 회차');
      if (h.status == 'weakened' && h.n >= 10 && h.success / h.n < 0.35) transition(h, 'rejected', t, '지속 실패');
    }
    // 3) 발견 (데이터 ≤ t)
    if (i >= 30) {
      final patterns = SequentialPatternFinder.find(data.sublist(0, i + 1));
      for (final pat in patterns.take(10)) {
        final key = '${pat.phenIndicator}_h${pat.horizon}_${pat.phenDirection}';
        if (hyps.containsKey(key)) continue;
        hyps[key] = _RHyp(key, pat.phenIndicator, pat.phenDirection, pat.horizon, t,
            Map<String, String>.from(pat.triggerState), pat.totalOccurrences, pat.successRate);
        createdNow++;
        timeline.add({'round': t, 'key': key, 'from': '-', 'to': 'discovered',
            'why': '표본 ${pat.totalOccurrences} 성공률 ${(pat.successRate * 100).toStringAsFixed(0)}%'});
      }
    }
    // 4) 트리거 발화 → t+h 검증 예약 (horizon 반영) = "다음 회차 예측" 저장 대상
    final predictionsNext = <Map<String, dynamic>>[];
    for (final h in hyps.values) {
      if (h.status == 'rejected' || h.createdRound > t) continue;
      int match = 0;
      for (final id in rpaIndicatorIds) { if (stateAt[i][id] == h.trigger[id]) match++; }
      if (match >= 4) {
        pending.putIfAbsent(t + h.horizon, () => []).add(MapEntry(h.key, h.direction));
        if (h.status == 'accepted' || h.status == 'validating') {
          predictionsNext.add({'key': h.key, 'target_round': t + h.horizon, 'indicator': h.indicator, 'direction': h.direction, 'status': h.status});
        }
      }
    }
    final sc = <String, int>{};
    for (final h in hyps.values) { sc[h.status] = (sc[h.status] ?? 0) + 1; }
    roundLogs.add({
      'round': t, 'data_end_round': t, 'created': createdNow, 'verified': verifiedNow, 'hits': hitsNow,
      'transitions': timeline.length - transitionsBefore, 'status_counts': sc,
      'accepted_keys': hyps.values.where((h) => h.status == 'accepted').map((h) => h.key).toList(),
      'predictions_next': predictionsNext.take(30).toList(),
    });
  }

  // 요약
  final rows = <Map<String, dynamic>>[];
  final ps = <double>[];
  int postN = 0, postS = 0; double postBase = 0;
  int engAllN = 0, engAllS = 0; double engBase = 0;
  for (final h in hyps.values) {
    final base = rpaIndicatorBaselines[h.indicator] ?? 0.5;
    final p0 = h.direction == 'above' ? base : 1 - base;
    final z = h.n > 0 ? (h.success - h.n * p0) / sqrt(h.n * p0 * (1 - p0)) : 0.0;
    final pv = h.n >= 20 ? twoSidedP(z) : 1.0;
    ps.add(pv);
    postN += h.postN; postS += h.postSuccess; postBase += h.postN * p0;
    engAllN += h.engN; engAllS += h.engSuccess; engBase += h.engN * p0;
    rows.add({
      'key': h.key, 'label': '${rpaIndicatorLabels[h.indicator] ?? h.indicator}${h.direction == 'above' ? '↑' : '↓'} @+${h.horizon}',
      'created_round': h.createdRound, 'status': h.status, 'hist_n': h.histN, 'hist_rate': h.histRate,
      'n': h.n, 'success': h.success, 'rate': h.n > 0 ? h.success / h.n : null, 'baseline': p0, 'z': z, 'p': pv,
      'eng_n': h.engN, 'eng_rate': h.engN > 0 ? h.engSuccess / h.engN : null,
      'post_n': h.postN, 'post_success': h.postSuccess, 'post_rate': h.postN > 0 ? h.postSuccess / h.postN : null,
      'accepted_round': h.acceptedRound, 'weakened_round': h.weakenedRound, 'rejected_round': h.rejectedRound,
    });
  }
  final adj = holmAdjust(ps);
  for (int k = 0; k < rows.length; k++) { rows[k]['p_holm'] = adj[k]; }
  rows.sort((a, b) => ((b['n'] as int)).compareTo(a['n'] as int));
  final statusCounts = <String, int>{};
  for (final h in hyps.values) { statusCounts[h.status] = (statusCounts[h.status] ?? 0) + 1; }
  final everAccepted = hyps.values.where((h) => h.acceptedRound != null).length;
  final postRate = postN > 0 ? postS / postN : null;
  final postBaseRate = postN > 0 ? postBase / postN : null;
  final postZ = (postN > 0 && postBaseRate != null) ? (postS - postBase) / sqrt(postN * postBaseRate * (1 - postBaseRate)) : null;
  final hoBaseRate = hoN > 0 ? hoBase / hoN : null;
  final hoZ = (hoN > 0 && hoBaseRate != null) ? (hoS - hoBase) / sqrt(hoN * hoBaseRate * (1 - hoBaseRate)) : null;
  return {
    'version': kHypothesisReplayVersion, 'start_round': start, 'end_round': data.last.round,
    'rounds_replayed': n - startIdx, 'hypotheses_total': hyps.length, 'status_counts': statusCounts,
    'ever_accepted': everAccepted, 'significant_holm': rows.where((r) => (r['p_holm'] as double) < 0.05).length,
    'post_accept': {'n': postN, 'success': postS, 'rate': postRate, 'baseline': postBaseRate, 'z': postZ,
        'p': postZ == null ? null : twoSidedP(postZ)},
    'holdout': {'from_round': holdoutFrom, 'n': hoN, 'success': hoS, 'rate': hoN > 0 ? hoS / hoN : null,
        'baseline': hoBaseRate, 'z': hoZ, 'p': hoZ == null ? null : twoSidedP(hoZ)},
    'round_logs': roundLogs,
    'engine_style': {'n': engAllN, 'success': engAllS, 'rate': engAllN > 0 ? engAllS / engAllN : null,
        'baseline': engAllN > 0 ? engBase / engAllN : null},
    'hypotheses': rows,
    'timeline_tail': timeline.length > 60 ? timeline.sublist(timeline.length - 60) : timeline,
    'timeline_count': timeline.length,
    'note': 'horizon·트리거 반영 재현. 기존 엔진은 horizon을 무시하고 매 회차 검증(engine_style)하므로 두 수치를 함께 제시. '
        '채택 이후(post_accept) 적중률만이 선택 편향 없는 성능 지표임.',
  };
}

class HypothesisReplayEngine {
  HypothesisReplayEngine._();
  static final instance = HypothesisReplayEngine._();
  final _db = Supabase.instance.client;
  Map<String, dynamic>? _cache;
  int _cacheEnd = 0;

  Future<Map<String, dynamic>> run(List<LottoWinningNumber> allData, {int start = kHypothesisReplayStart}) async {
    final end = allData.map((d) => d.round).fold<int>(0, (a, b) => a > b ? a : b);
    if (_cache != null && _cacheEnd == end) return _cache!;
    final ser = allData.map((d) => {'r': d.round, 'd': d.drawDate, 'n': d.numbers, 'b': d.bonusNumber}).toList();
    final res = await compute(_replayIsolate, {'data': ser, 'start': start});
    _cache = res; _cacheEnd = end;
    return res;
  }

  Future<Map<String, dynamic>> runAndPersist(List<LottoWinningNumber> allData) async {
    final res = await run(allData);
    final logs = List<Map<String, dynamic>>.from(res['round_logs'] as List? ?? []);
    final summary = Map<String, dynamic>.from(res)..remove('round_logs');
    summary['round_logs_count'] = logs.length;
    // 회차별 실행 로그·가설 상태·다음 회차 예측 → research_replay_rounds (체크포인트: 저장된 회차는 건너뜀)
    try {
      Set<int> done = {};
      try {
        final r = await _db.from('research_replay_rounds').select('round')
            .eq('model_version', kHypothesisReplayVersion).limit(5000);
        done = (r as List).map((x) => (x['round'] as num).toInt()).toSet();
      } catch (_) {}
      final rows = logs.where((l) => !done.contains(l['round'] as int)).map((l) => {
            'model_version': kHypothesisReplayVersion, 'round': l['round'], 'data_end_round': l['data_end_round'],
            'created': l['created'], 'verified': l['verified'], 'hits': l['hits'], 'transitions': l['transitions'],
            'status_counts': l['status_counts'], 'accepted_keys': l['accepted_keys'],
            'predictions_next': l['predictions_next'], 'status': 'completed',
          }).toList();
      for (int i = 0; i < rows.length; i += 100) {
        await _db.from('research_replay_rounds').upsert(rows.sublist(i, i + 100 > rows.length ? rows.length : i + 100),
            onConflict: 'model_version,round', ignoreDuplicates: true);
      }
      summary['round_logs_persisted'] = rows.length;
      summary['round_logs_existing'] = done.length;
    } catch (e) {
      debugPrint('[HypReplay] round log persist skipped (table?): $e');
      summary['round_logs_persisted'] = 0;
      summary['round_logs_error'] = '$e'.length > 160 ? '$e'.substring(0, 160) : '$e';
    }
    try {
      await _db.from('research_results').upsert({
        'research_type': 'hypothesis_replay', 'model_version': kHypothesisReplayVersion,
        'training_end_round': res['end_round'], 'target_round': 0, 'payload': summary,
      }, onConflict: 'research_type,model_version,training_end_round,target_round');
    } catch (e) {
      debugPrint('[HypReplay] persist skipped: $e');
    }
    return summary;
  }

  /// 저장된 최신 재현 결과 (없으면 null)
  Future<Map<String, dynamic>?> loadLatest() async {
    try {
      final r = await _db.from('research_results').select('payload')
          .eq('research_type', 'hypothesis_replay').eq('model_version', kHypothesisReplayVersion)
          .order('training_end_round', ascending: false).limit(1);
      final l = List<Map<String, dynamic>>.from(r as List);
      return l.isEmpty ? null : Map<String, dynamic>.from(l.first['payload'] as Map);
    } catch (_) {
      return null;
    }
  }
}
