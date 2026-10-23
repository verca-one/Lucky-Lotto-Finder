// AI 전략기획부 · 가설 공장 — 서버 저장본(research_v14_strategy.sql)만 읽는다. 앱은 쓰지 않는다.
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class StrategyDirection {
  final String id, source, title, rationale;
  final String? model, focus;
  final int afterRound;
  final DateTime? createdAt;
  const StrategyDirection({
    required this.id, required this.source, required this.title, required this.rationale, required this.afterRound,
    this.model, this.focus, this.createdAt,
  });
  factory StrategyDirection.fromRow(Map<String, dynamic> r) => StrategyDirection(
        id: '${r['id']}', source: '${r['source'] ?? 'ai'}', title: '${r['title'] ?? ''}', rationale: '${r['rationale'] ?? ''}',
        afterRound: (r['after_round'] as num?)?.toInt() ?? 0, model: r['model'] as String?, focus: r['focus'] as String?,
        createdAt: DateTime.tryParse('${r['created_at']}'),
      );
  bool get isAi => source == 'ai';

  /// 복권 종류: lotto · pension · speetto (방향의 focus 로 구분)
  String get lottery => focus == 'pension' ? 'pension' : (focus == 'speetto' ? 'speetto' : 'lotto');

  /// 'Claude' · 'Gemini' · null(관리자)
  String? get aiName {
    if (!isAi) return null;
    final m = (model ?? '').toLowerCase();
    return m.contains('gemini') ? 'Gemini' : (m.contains('claude') ? 'Claude' : 'AI');
  }
}

/// 가설 검정 한 단계 (발견 · 확인 · 새 회차 추적)
class StageResult {
  final int from, to, nCond, nOther;
  final double? meanCond, meanOther, p;
  final bool small, directionOk;

  /// 판매점 가설: 조건 판매점 1등 수(nCond) vs 지방장 기대(expectedCond), mean = 실제÷기대 배수
  final bool storeUnit;
  final double? expectedCond;
  const StageResult(this.from, this.to, this.nCond, this.nOther, this.meanCond, this.meanOther, this.p, this.small,
      this.directionOk, {this.storeUnit = false, this.expectedCond});
  static StageResult? fromJson(dynamic v) {
    if (v is! Map || v['n_cond'] == null) return null;
    final j = Map<String, dynamic>.from(v);
    return StageResult(
      (j['from'] as num?)?.toInt() ?? 0, (j['to'] as num?)?.toInt() ?? 0, (j['n_cond'] as num).toInt(),
      (j['n_other'] as num?)?.toInt() ?? 0, (j['mean_cond'] as num?)?.toDouble(), (j['mean_other'] as num?)?.toDouble(),
      (j['p'] as num?)?.toDouble(), j['status'] == 'small', j['direction_ok'] == true,
      storeUnit: j['unit'] == 'store', expectedCond: (j['expected_cond'] as num?)?.toDouble(),
    );
  }

  bool get passed => !small && p != null && p! < 0.05 && directionOk;
}

class StrategyHypothesis {
  final String id, statement, status, code;
  final String? directionId, verdict;
  final Map<String, dynamic> spec;
  final StageResult? discovery, confirm, forward;
  final int createdRound;

  /// 가설 모의 — 이 가설대로 번호를 골랐다면 5등 이상이 무작위보다 많았나 (서버 계산)
  final Map<String, dynamic> simulation;
  const StrategyHypothesis({
    required this.id, required this.statement, required this.status, required this.code, required this.spec,
    required this.createdRound, this.directionId, this.verdict, this.discovery, this.confirm, this.forward,
    this.simulation = const {},
  });
  factory StrategyHypothesis.fromRow(Map<String, dynamic> r) => StrategyHypothesis(
        id: '${r['id']}', statement: '${r['statement'] ?? ''}', status: '${r['status'] ?? 'proposed'}', code: '${r['code'] ?? ''}',
        spec: _m(r['spec']), createdRound: (r['created_round'] as num?)?.toInt() ?? 0,
        directionId: r['direction_id'] as String?, verdict: r['verdict'] as String?,
        discovery: StageResult.fromJson(r['discovery']), confirm: StageResult.fromJson(r['confirm']),
        forward: StageResult.fromJson(r['forward']),
        simulation: _m(r['simulation']),
      );

  /// 모의 결과가 있으면 (lift, 상승 여부)
  bool get simulated => simulation['status'] == 'done';
  double? get simLift => (simulation['lift'] as num?)?.toDouble();
  bool get simRaised => simulation['raised'] == true;

  /// 화면 표시 상태: 판정 보류(표본 부족)는 proposed 중 verdict 가 '판정 보류'로 시작
  String get displayStatus => status == 'proposed' && (verdict ?? '').startsWith('판정 보류') ? 'pending' : status;

  /// 가설 종류: base(기본) · supplement(보충회생) · revival(회생) · partial(임시 일부 발췌) · applied(응용)
  String get kind => '${spec['kind'] ?? 'base'}';

  /// 판매점 단위 가설 (명당)
  bool get isStore => spec['level'] == 'store';

  /// 연금복권 가설 (가설 트랙 전용 — 가설 공장 판정 없음) · 연금 판매점 가설 포함
  bool get isPension => spec['level'] == 'pension' || spec['level'] == 'pension_store';
  bool get isPensionStore => spec['level'] == 'pension_store';

  /// 스피또 가설 (판매 현황이 쌓이면 검정)
  bool get isSpeetto => spec['level'] == 'speetto';

  /// 파생 원본 가설 코드 (기본 가설이면 null)
  String? get parentCode => spec['parent'] as String?;
}

class StrategyRun {
  final String kind, status;
  final int? afterRound;
  final Map<String, dynamic> stats;
  final String? note;
  final DateTime? createdAt;
  const StrategyRun(this.kind, this.status, this.afterRound, this.stats, this.note, this.createdAt);
  factory StrategyRun.fromRow(Map<String, dynamic> r) => StrategyRun('${r['kind']}', '${r['status']}',
      (r['after_round'] as num?)?.toInt(), _m(r['stats']), r['note'] as String?, DateTime.tryParse('${r['created_at']}'));
}

class StrategyData {
  final List<StrategyDirection> directions;
  final List<StrategyHypothesis> hypotheses;
  final List<StrategyRun> runs;
  const StrategyData(this.directions, this.hypotheses, this.runs);

  List<StrategyHypothesis> of(String directionId) => hypotheses.where((h) => h.directionId == directionId).toList();
  StrategyHypothesis? byCode(String? code) => code == null ? null : hypotheses.where((h) => h.code == code).firstOrNull;
  List<StrategyHypothesis> childrenOf(String code) => hypotheses.where((h) => h.parentCode == code).toList();
  StrategyRun? lastRun(String kind) => runs.where((r) => r.kind == kind).firstOrNull;
  int count(Set<String> statuses) => hypotheses.where((h) => statuses.contains(h.displayStatus)).length;
}

class StrategyRepository {
  static Future<StrategyData> load() async {
    final db = Supabase.instance.client;
    final d = await db.from('strategy_directions').select().order('created_at', ascending: false).limit(40);
    final h = await db.from('strategy_hypotheses').select().order('created_at', ascending: true).limit(400);
    final r = await db.from('strategy_runs').select().order('created_at', ascending: false).limit(20);
    return StrategyData(
      List<Map<String, dynamic>>.from(d as List).map(StrategyDirection.fromRow).toList(),
      List<Map<String, dynamic>>.from(h as List).map(StrategyHypothesis.fromRow).toList(),
      List<Map<String, dynamic>>.from(r as List).map(StrategyRun.fromRow).toList(),
    );
  }
}
