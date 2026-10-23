// 가설 트랙 (ht-1.0) — 제미나이 가설을 검증 전에 바로 쓰는 '상상 예측' 부서. 서버 저장본(research_results · hypothesis_track)만 읽는다.
import 'package:supabase_flutter/supabase_flutter.dart';

double? _dn(dynamic v) => (v as num?)?.toDouble();
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

class TrackHypothesis {
  final String code, statement, family, outcome, expect, status;

  /// 최근 200회 힘(z) · 실전 성적 배수 · 판매점 배수
  final double? z, w, m, factor;
  const TrackHypothesis({
    required this.code, required this.statement, required this.family, required this.outcome, required this.expect,
    required this.status, this.z, this.w, this.m, this.factor,
  });
  factory TrackHypothesis.fromJson(Map<String, dynamic> j) {
    final rc = j['recent'] is Map ? Map<String, dynamic>.from(j['recent']) : const <String, dynamic>{};
    return TrackHypothesis(
      code: '${j['code'] ?? ''}', statement: '${j['statement'] ?? ''}', family: '${j['family'] ?? ''}',
      outcome: '${j['outcome'] ?? ''}', expect: '${j['expect'] ?? ''}', status: '${j['status'] ?? ''}',
      z: _dn(rc['z']), w: _dn(j['w']), m: _dn(j['m']), factor: _dn(j['factor']),
    );
  }
  bool get isStore => family == 'store' || family == 'capital';
}

class TrackSet {
  final List<int> numbers;
  final double? popularityPct;
  const TrackSet(this.numbers, this.popularityPct);
}

class TrackStore {
  final String code, name, region, address;
  final double pFirst, factor, pAdj;
  final int first, second;
  final List<int> hyps;
  const TrackStore({
    required this.code, required this.name, this.region = '', this.address = '', required this.pFirst, this.factor = 1,
    required this.pAdj, this.first = 0, this.second = 0, this.hyps = const [],
  });
}

class HypothesisTrack {
  final int targetRound, trainingEndRound, hypothesesTotal;
  final String status; // registered | pending
  final List<int> window;
  final List<TrackSet> sets;
  final double? targetPct, drive;
  final List<TrackHypothesis> used;
  final List<TrackStore> stores;
  final Map<String, int> skipped;

  /// 누적 실전 성적 (가설 코드 → [사용, 맞힘])
  final Map<String, List<int>> record;

  /// 토요일 08:00 최종 점검 뒤 재선정본이면 true · 수요일 선정과 비교용
  final bool isFinal;
  final List<List<int>> wedSets;
  final List<String> wedStores;
  const HypothesisTrack({
    required this.targetRound, required this.trainingEndRound, this.hypothesesTotal = 0, this.status = 'pending',
    this.window = const [], this.sets = const [], this.targetPct, this.drive, this.used = const [], this.stores = const [],
    this.skipped = const {}, this.record = const {}, this.isFinal = false, this.wedSets = const [], this.wedStores = const [],
  });

  /// 수요일 선정과 다른 번호 세트 수 · 명당 수 (최종본일 때)
  int get changedSets {
    final w = {for (final s in wedSets) ([...s]..sort()).join(',')};
    return sets.where((s) => !w.contains(([...s.numbers]..sort()).join(','))).length;
  }

  int get changedStores => stores.where((s) => !wedStores.contains(s.code)).length;

  factory HypothesisTrack.fromPayload(Map<String, dynamic> p) {
    List<Map<String, dynamic>> maps(dynamic v) => [for (final x in (v as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    return HypothesisTrack(
      targetRound: _i(p['target_round']), trainingEndRound: _i(p['training_end_round']),
      hypothesesTotal: _i(p['hypotheses_total']), status: '${p['status'] ?? 'pending'}',
      window: [for (final x in (p['window'] as List? ?? const [])) (x as num).toInt()],
      sets: [
        for (final s in maps(p['sets']))
          TrackSet([for (final n in (s['set'] as List)) (n as num).toInt()], _dn(s['popularity_pct'])),
      ],
      targetPct: _dn(p['popularity_target_pct']), drive: _dn(p['popularity_drive']),
      used: maps(p['used']).map(TrackHypothesis.fromJson).toList(),
      stores: [
        for (final o in maps(p['stores']))
          TrackStore(
            code: '${o['store_code']}', name: '${o['name'] ?? o['store_code']}', region: '${o['region'] ?? ''}',
            address: '${o['address'] ?? ''}', pFirst: _dn(o['p_first']) ?? 0, factor: _dn(o['factor']) ?? 1,
            pAdj: _dn(o['p_adj']) ?? 0, first: _i(o['first']), second: _i(o['second']),
            hyps: [for (final k in (o['hyps'] as List? ?? const [])) (k as num).toInt()],
          ),
      ],
      skipped: {for (final e in (p['skipped'] as Map? ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
      record: {
        for (final e in (p['record'] as Map? ?? const {}).entries)
          '${e.key}': [for (final x in (e.value as List)) (x as num).toInt()],
      },
      isFinal: p['final'] == true,
      wedSets: [
        for (final s in ((p['wednesday'] as Map?)?['sets'] as List? ?? const []))
          [for (final n in (s as List? ?? const [])) (n as num).toInt()],
      ],
      wedStores: [for (final c in ((p['wednesday'] as Map?)?['stores'] as List? ?? const [])) '$c'],
    );
  }

  List<TrackHypothesis> get numberHyps => used.where((h) => !h.isStore).toList();
  List<TrackHypothesis> get storeHyps => used.where((h) => h.isStore).toList();

  /// 판매점이 뽑힌 이유 (가설 문장)
  String? whyOf(TrackStore s) => s.hyps.isEmpty || s.hyps.first >= used.length ? null : used[s.hyps.first].statement;

  /// 누적 실전 성적 합 (사용 · 맞힘)
  (int, int) get totalRecord {
    var p = 0, h = 0;
    for (final v in record.values) {
      if (v.length >= 2) {
        p += v[0];
        h += v[1];
      }
    }
    return (p, h);
  }

  static Future<HypothesisTrack?> load(int target) async {
    final rows = await Supabase.instance.client
        .from('research_results')
        .select('payload')
        .eq('research_type', 'hypothesis_track')
        .inFilter('model_version', ['ht-1.0-sat', 'ht-1.0'])
        .eq('target_round', target)
        .order('model_version', ascending: false) // 'ht-1.0-sat'(토요일 최종본) 우선
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return HypothesisTrack.fromPayload(Map<String, dynamic>.from(rows.first['payload'] as Map));
  }
}
