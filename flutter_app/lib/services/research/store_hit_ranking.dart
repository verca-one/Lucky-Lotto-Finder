// 판매점 적중 예측 순위 (hs-apply-1.0) — 서버 저장본(research_results · store_hypothesis_apply)만 읽는다.
// 지방장 모델(ag-1.1)의 다음 회차 1등 추정 확률 × 가설 공장 검증 통과 판매점 가설 배수(여러 개면 가장 큰 것 하나).
import 'package:supabase_flutter/supabase_flutter.dart';

double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

class StoreHitHypothesis {
  final String code, label, statement, outcome, status;
  final double factor;
  final int storesNow;

  /// 과거 모의 (1001회~ 시·군·구 TOP5 1등 적중: 가설 가중 vs 이력만)
  final int? simHyp, simBase;
  final bool simRaised;
  const StoreHitHypothesis({
    required this.code, required this.label, required this.statement, required this.outcome, required this.status,
    required this.factor, this.storesNow = 0, this.simHyp, this.simBase, this.simRaised = false,
  });
  factory StoreHitHypothesis.fromJson(Map<String, dynamic> j) {
    final s = j['sim'] is Map ? Map<String, dynamic>.from(j['sim']) : const <String, dynamic>{};
    return StoreHitHypothesis(
      code: '${j['code'] ?? ''}', label: '${j['label'] ?? ''}', statement: '${j['statement'] ?? ''}',
      outcome: '${j['outcome'] ?? ''}', status: '${j['status'] ?? ''}', factor: _d(j['factor']),
      storesNow: _i(j['stores_now']),
      simHyp: (s['hits_hyp'] as num?)?.toInt(), simBase: (s['hits_base'] as num?)?.toInt(), simRaised: s['raised'] == true,
    );
  }
  String get outcomeLabel => outcome == 'first_second' ? '1·2등' : '1등';
}

class StoreHitEntry {
  final int rank, baseRank;
  final String code, name, address, region;
  final String? agentId;
  final double? lat, lng;
  final int first, second;

  /// 지방장 1등 추정 확률 · 가설 배수 · 반영 확률
  final double pFirst, factor, pAdj;
  final List<int> hyps;
  const StoreHitEntry({
    required this.rank, required this.baseRank, required this.code, required this.name, this.address = '', this.region = '',
    this.agentId, this.lat, this.lng, this.first = 0, this.second = 0,
    required this.pFirst, this.factor = 1, required this.pAdj, this.hyps = const [],
  });
  factory StoreHitEntry.fromJson(Map<String, dynamic> j) => StoreHitEntry(
        rank: _i(j['rank']), baseRank: _i(j['base_rank']), code: '${j['store_code'] ?? ''}', name: '${j['name'] ?? ''}',
        address: '${j['address'] ?? ''}', region: '${j['region'] ?? ''}', agentId: j['agent_id'] as String?,
        lat: (j['lat'] as num?)?.toDouble(), lng: (j['lng'] as num?)?.toDouble(),
        first: _i(j['first']), second: _i(j['second']),
        pFirst: _d(j['p_first']), factor: (j['factor'] as num?)?.toDouble() ?? 1, pAdj: _d(j['p_adj']),
        hyps: [for (final h in (j['hyps'] as List? ?? const [])) (h as num).toInt()],
      );
  bool get boosted => factor > 1;
  bool get isOnline => agentId == 'internet' || name.contains('인터넷');
}

class StoreHitRanking {
  final int targetRound, trainingEndRound, storesScored;
  final List<StoreHitHypothesis> hypotheses;
  final List<StoreHitEntry> ranking;
  final Map<String, ({double f, List<int> h})> factors;
  const StoreHitRanking({
    required this.targetRound, required this.trainingEndRound, this.storesScored = 0,
    this.hypotheses = const [], this.ranking = const [], this.factors = const {},
  });

  factory StoreHitRanking.fromPayload(Map<String, dynamic> p) {
    final f = <String, ({double f, List<int> h})>{};
    (p['factors'] as Map? ?? const {}).forEach((k, v) {
      final m = Map<String, dynamic>.from(v as Map);
      f['$k'] = (f: _d(m['f']), h: [for (final x in (m['h'] as List? ?? const [])) (x as num).toInt()]);
    });
    return StoreHitRanking(
      targetRound: _i(p['target_round']), trainingEndRound: _i(p['training_end_round']), storesScored: _i(p['stores_scored']),
      hypotheses: [for (final h in (p['hypotheses'] as List? ?? const [])) StoreHitHypothesis.fromJson(Map<String, dynamic>.from(h))],
      ranking: [for (final r in (p['ranking'] as List? ?? const [])) StoreHitEntry.fromJson(Map<String, dynamic>.from(r))],
      factors: f,
    );
  }

  /// 판매점 가설 배수 (없으면 1)
  double factorOf(String code) => factors[code]?.f ?? 1.0;

  /// 판매점에 맞는 검증 가설 (배수 큰 순)
  List<StoreHitHypothesis> hypothesesOf(String code) {
    final idx = factors[code]?.h ?? const <int>[];
    final out = [for (final i in idx) if (i >= 0 && i < hypotheses.length) hypotheses[i]]
      ..sort((a, b) => b.factor.compareTo(a.factor));
    return out;
  }

  /// 과거 모의에서 적중이 오른 반영 가설 수
  int get simRaisedCount => hypotheses.where((h) => h.simRaised).length;

  static Future<StoreHitRanking?> load(int target) async {
    final rows = await Supabase.instance.client
        .from('research_results')
        .select('payload')
        .eq('research_type', 'store_hypothesis_apply')
        .eq('target_round', target)
        .order('created_at', ascending: false)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return StoreHitRanking.fromPayload(Map<String, dynamic>.from(rows.first['payload'] as Map));
  }
}
