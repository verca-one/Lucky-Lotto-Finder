// 회차 검증 보고 · 지방장 보고 (db-1.0) — 서버(research_debrief_worker.py)가 저장한 결과만 읽는다.
// 앱은 계산·저장하지 않는다. 검수 문장은 저장된 수치로 만든 규칙 기반 자동 문장이다.
import 'package:supabase_flutter/supabase_flutter.dart';

List<int> _ints(dynamic v) =>
    ((v as List?) ?? const []).map((e) => (e as num).toInt()).toList();
Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(dynamic v) =>
    ((v as List?) ?? const []).map(_map).toList();
double? _d(dynamic v) => (v as num?)?.toDouble();
int? _i(dynamic v) => (v as num?)?.toInt();

const kRankLabel = {1: '1등', 2: '2등', 3: '3등', 4: '4등', 5: '5등', 0: '낙첨'};

class DebriefSet {
  final List<int> numbers, hits;
  final int matches, rank;
  final bool bonus;
  const DebriefSet(
    this.numbers,
    this.hits,
    this.matches,
    this.rank,
    this.bonus,
  );
  factory DebriefSet.fromJson(Map<String, dynamic> j) => DebriefSet(
    _ints(j['numbers']),
    _ints(j['hits']),
    _i(j['matches']) ?? 0,
    _i(j['rank']) ?? 0,
    (_i(j['bonus']) ?? 0) > 0,
  );
}

class DebriefTrack {
  final int rounds, sets, ge3;
  final double mean, expectedGe3, z, p;
  const DebriefTrack(
    this.rounds,
    this.sets,
    this.ge3,
    this.mean,
    this.expectedGe3,
    this.z,
    this.p,
  );
  static DebriefTrack? fromJson(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return DebriefTrack(
      _i(j['rounds']) ?? 0,
      _i(j['sets']) ?? 0,
      _i(j['ge3']) ?? 0,
      _d(j['mean']) ?? 0,
      _d(j['expected_ge3']) ?? 0,
      _d(j['z']) ?? 0,
      _d(j['p_one_sided']) ?? 1,
    );
  }
}

class DebriefGroup {
  final String key, label, role;
  final String? status, version;
  final List<DebriefSet> sets;
  final int bestMatches, bestRank;
  final double? mean, pBestOrMore;
  final DebriefTrack? track;
  final List<List<int>> nextSets;
  const DebriefGroup({
    required this.key,
    required this.label,
    required this.role,
    this.status,
    this.version,
    this.sets = const [],
    this.bestMatches = 0,
    this.bestRank = 0,
    this.mean,
    this.pBestOrMore,
    this.track,
    this.nextSets = const [],
  });
  factory DebriefGroup.fromJson(Map<String, dynamic> j) => DebriefGroup(
    key: '${j['key']}',
    label: '${j['label']}',
    role: '${j['role'] ?? ''}',
    status: j['status'] as String?,
    version: j['version'] as String?,
    sets: _maps(j['sets']).map(DebriefSet.fromJson).toList(),
    bestMatches: _i(j['best_matches']) ?? 0,
    bestRank: _i(j['best_rank']) ?? 0,
    mean: _d(j['mean']),
    pBestOrMore: _d(j['p_best_or_more']),
    track: DebriefTrack.fromJson(j['track']),
    nextSets: ((_map(j['next'])['sets'] as List?) ?? const [])
        .map(_ints)
        .toList(),
  );
}

/// 브리핑 추천 명당 (이전 회차 채점 · 다음 회차 비교)
class DebriefStore {
  final String code, name, agentId, source;
  final int tier; // 1 = 1등, 2 = 2등, 0 = 없음 (이전 회차)
  final String? status; // kept | new (다음 회차)
  final double? pFirst, pFirstPrev;
  final int? focusRank, topRank;
  const DebriefStore({
    required this.code,
    required this.name,
    required this.agentId,
    required this.source,
    this.tier = 0,
    this.status,
    this.pFirst,
    this.pFirstPrev,
    this.focusRank,
    this.topRank,
  });
  factory DebriefStore.fromJson(Map<String, dynamic> j) => DebriefStore(
    code: '${j['code']}',
    name: '${j['name'] ?? j['code']}',
    agentId: '${j['agent_id'] ?? ''}',
    source: '${j['source'] ?? ''}',
    tier: _i(j['tier']) ?? 0,
    status: j['status'] as String?,
    pFirst: _d(j['p_first']),
    pFirstPrev: _d(j['p_first_prev']),
    focusRank: _i(j['focus_rank']),
    topRank: _i(j['top_rank']),
  );
}

class RoundDebrief {
  final int round, next;
  final String status;
  final List<String> missing;
  final List<int> actual;
  final int? bonus;
  final String? drawDate;
  final List<DebriefGroup> groups;
  final Map<String, dynamic> traits,
      stores,
      popularity,
      nextRound,
      audit,
      hypotheses;
  const RoundDebrief({
    required this.round,
    required this.next,
    required this.status,
    required this.missing,
    required this.actual,
    this.bonus,
    this.drawDate,
    required this.groups,
    required this.traits,
    required this.stores,
    required this.popularity,
    required this.nextRound,
    required this.audit,
    required this.hypotheses,
  });

  factory RoundDebrief.fromPayload(Map<String, dynamic> p) {
    final n = _map(p['numbers']);
    return RoundDebrief(
      round: _i(p['round']) ?? 0,
      next: _i(p['next']) ?? 0,
      status: '${p['status'] ?? 'partial'}',
      missing: ((p['missing'] as List?) ?? const []).map((e) => '$e').toList(),
      actual: _ints(n['actual']),
      bonus: _i(n['bonus']),
      drawDate: n['draw_date'] as String?,
      groups: _maps(n['groups']).map(DebriefGroup.fromJson).toList(),
      traits: _map(n['traits']),
      stores: _map(p['stores']),
      popularity: _map(p['popularity_check']),
      nextRound: _map(p['next_round']),
      audit: _map(p['audit']),
      hypotheses: _map(p['hypotheses']),
    );
  }

  List<DebriefStore> get storesPrev =>
      _maps(stores['briefing_prev']).map(DebriefStore.fromJson).toList();
  List<DebriefStore> get storesNext =>
      _maps(stores['briefing_next']).map(DebriefStore.fromJson).toList();
  List<Map<String, dynamic>> get storesDropped => _maps(stores['dropped']);
  List<Map<String, dynamic>> get firstStores => _maps(stores['first_stores']);
  List<String> get analyst =>
      ((audit['analyst'] as List?) ?? const []).map((e) => '$e').toList();
  List<String> get mathematician =>
      ((audit['mathematician'] as List?) ?? const []).map((e) => '$e').toList();
  String get verdict => '${audit['verdict'] ?? ''}';
  String get auditNote => '${audit['note'] ?? ''}';
  Map<String, dynamic> get nextOfficial => _map(nextRound['official']);
  Map<String, dynamic> get probabilities => _map(nextRound['probabilities']);
}

/// 지방장 1명 보고
class AgentReport {
  final String id, label, note;
  final int? n;
  final List<List<dynamic>> prev, next, dropped, firsts;
  final List<int>? h;
  final List<double>? x;
  final int changes, liveChanges, routine, newHyp;
  final Map<String, int> hyp;
  const AgentReport({
    required this.id,
    required this.label,
    required this.note,
    this.n,
    required this.prev,
    required this.next,
    required this.dropped,
    required this.firsts,
    this.h,
    this.x,
    required this.changes,
    required this.liveChanges,
    required this.routine,
    required this.newHyp,
    required this.hyp,
  });
  factory AgentReport.fromJson(Map<String, dynamic> j) {
    List<List<dynamic>> rows(String k) => ((j[k] as List?) ?? const [])
        .map((e) => List<dynamic>.from(e as List))
        .toList();
    return AgentReport(
      id: '${j['id']}',
      label: '${j['label']}',
      note: '${j['note'] ?? ''}',
      n: _i(j['n']),
      prev: rows('prev'),
      next: rows('next'),
      dropped: rows('dropped'),
      firsts: rows('firsts'),
      h: j['h'] == null ? null : _ints(j['h']),
      x: j['x'] == null
          ? null
          : (j['x'] as List).map((e) => (e as num).toDouble()).toList(),
      changes: _i(j['changes']) ?? 0,
      liveChanges: _i(j['live_changes']) ?? 0,
      routine: _i(j['routine']) ?? 0,
      newHyp: _i(j['new_hyp']) ?? 0,
      hyp: {
        for (final e in _map(j['hyp']).entries) e.key: (e.value as num).toInt(),
      },
    );
  }

  String get sido => id.split('|').first;
  int get firstHits => prev.where((p) => p.length > 4 && p[4] == 1).length;
  int get secondHits => prev.where((p) => p.length > 4 && p[4] == 2).length;
  bool get hadFirst => firsts.isNotEmpty;
}

class AgentDebrief {
  final int round, next;
  final List<AgentReport> agents;
  final Map<String, dynamic> summary;
  const AgentDebrief(this.round, this.next, this.agents, this.summary);
  factory AgentDebrief.fromPayload(Map<String, dynamic> p) => AgentDebrief(
    _i(p['round']) ?? 0,
    _i(p['next']) ?? 0,
    _maps(p['agents']).map(AgentReport.fromJson).toList(),
    _map(p['summary']),
  );
}

class RoundDebriefRepository {
  static Future<Map<String, dynamic>?> _latest(String type) async {
    final rows = await Supabase.instance.client
        .from('research_results')
        .select('payload')
        .eq('research_type', type)
        .eq('model_version', 'db-1.0')
        .order('training_end_round', ascending: false)
        .limit(1);
    final l = List<Map<String, dynamic>>.from(rows as List);
    return l.isEmpty
        ? null
        : Map<String, dynamic>.from(l.first['payload'] as Map);
  }

  /// 가장 최근 추첨 회차의 검증 보고 (없으면 null)
  static Future<RoundDebrief?> loadRound() async {
    final p = await _latest('round_debrief');
    return p == null ? null : RoundDebrief.fromPayload(p);
  }

  /// 가장 최근 추첨 회차의 지방장 보고 (없으면 null)
  static Future<AgentDebrief?> loadAgents() async {
    final p = await _latest('agent_debrief');
    return p == null ? null : AgentDebrief.fromPayload(p);
  }
}
