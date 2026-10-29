// 추천번호 복기 (sr-1.0) — 서버 저장본(research_results · set_review)만 읽는다.
//   지난 회차 추천 20세트(4영역) vs 당첨번호 → 아쉬운 부분 → 제미나이 보완 규칙 → 다음 회차 가설 트랙에 반영
import 'package:supabase_flutter/supabase_flutter.dart';

int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
double? _d(dynamic v) => (v as num?)?.toDouble();
List<int> _ints(dynamic v) => [for (final x in (v as List? ?? const [])) (x as num).toInt()];

class SetReviewFeature {
  final String key, name, actualSide;
  final num actual;
  final double? median, setsMean;
  final int sameSets;
  final bool missed;
  const SetReviewFeature({required this.key, required this.name, required this.actualSide, required this.actual,
      this.median, this.setsMean, this.sameSets = 0, this.missed = false});
}

class SetReviewArea {
  final String label;
  final int sets, bestHits, won;
  const SetReviewArea(this.label, this.sets, this.bestHits, this.won);
}

class SetReviewRule {
  final String code, feature, expect, statement, why, source;
  final double w;
  final int repeat, weeks;
  const SetReviewRule({required this.code, required this.feature, required this.expect, required this.statement,
      required this.why, required this.source, required this.w, this.repeat = 0, this.weeks = 0});
}

class SetReview {
  final int round, targetRound, setCount, bestHits, wonSets;
  final List<int> actual;
  final int bonus;
  final String summary, source;
  final String? model, aiError;
  final List<SetReviewArea> areas;
  final List<SetReviewFeature> features;
  final List<int> missedNumbers, overNumbers;
  final List<SetReviewRule> rules;
  final List<int> lookback;
  const SetReview({
    required this.round, required this.targetRound, required this.actual, required this.bonus, this.setCount = 0,
    this.bestHits = 0, this.wonSets = 0, this.summary = '', this.source = 'rule', this.model, this.aiError,
    this.areas = const [], this.features = const [], this.missedNumbers = const [], this.overNumbers = const [],
    this.rules = const [], this.lookback = const [],
  });

  bool get fromGemini => source == 'gemini';

  factory SetReview.fromPayload(Map<String, dynamic> p) {
    final rv = Map<String, dynamic>.from(p['review'] as Map? ?? const {});
    final feats = Map<String, dynamic>.from(rv['features'] as Map? ?? const {});
    final areas = Map<String, dynamic>.from(rv['areas'] as Map? ?? const {});
    return SetReview(
      round: _i(p['round']),
      targetRound: _i(p['target_round']),
      actual: _ints(rv['actual']),
      bonus: _i(rv['bonus']),
      setCount: (rv['sets'] as List? ?? const []).length,
      bestHits: _i(rv['best_hits']),
      wonSets: _i(rv['won_sets']),
      summary: '${p['summary'] ?? ''}',
      source: '${p['source'] ?? 'rule'}',
      model: p['model'] as String?,
      aiError: p['ai_error'] as String?,
      areas: [
        for (final k in const ['official', 'popularity', 'purchase', 'hypothesis'])
          if (areas[k] is Map)
            SetReviewArea('${areas[k]['label']}', _i(areas[k]['sets']), _i(areas[k]['best_hits']), _i(areas[k]['won'])),
      ],
      features: [
        for (final e in feats.entries)
          SetReviewFeature(
            key: e.key,
            name: '${(e.value as Map)['name'] ?? e.key}',
            actualSide: '${(e.value as Map)['actual_side'] ?? ''}',
            actual: ((e.value as Map)['actual'] as num?) ?? 0,
            median: _d((e.value as Map)['median']),
            setsMean: _d((e.value as Map)['sets_mean']),
            sameSets: _i((e.value as Map)['same_side_sets']),
            missed: (e.value as Map)['missed'] == true,
          ),
      ],
      missedNumbers: _ints(rv['missed_numbers']),
      overNumbers: _ints(rv['over_numbers']),
      rules: [
        for (final r in (p['rules'] as List? ?? const []))
          SetReviewRule(
            code: '${r['code'] ?? ''}', feature: '${r['feature'] ?? ''}', expect: '${r['expect'] ?? ''}',
            statement: '${r['statement'] ?? ''}', why: '${r['why'] ?? ''}', source: '${r['source'] ?? ''}',
            w: _d(r['w']) ?? 0, repeat: _i(r['repeat']), weeks: _i(r['weeks']),
          ),
      ],
      lookback: _ints((p['persistence'] as Map?)?['rounds']),
    );
  }

  /// 최신 복기 1건 (없으면 null)
  static Future<SetReview?> loadLatest() async {
    final rows = await Supabase.instance.client
        .from('research_results')
        .select('payload')
        .eq('research_type', 'set_review')
        .eq('model_version', 'sr-1.0')
        .order('target_round', ascending: false)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return SetReview.fromPayload(Map<String, dynamic>.from(rows.first['payload'] as Map));
  }
}
