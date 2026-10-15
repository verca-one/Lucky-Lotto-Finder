// 번호 인기도 (pop-1.0) — 서버(research_popularity.py --publish)가 저장한 결과만 읽는다. 앱은 계산·저장하지 않는다.
// 1등 확률은 모든 조합이 같다. 인기도는 '당첨 시 나눠 가질 사람 수'에 관한 값이다.
import 'package:supabase_flutter/supabase_flutter.dart';

class PopularityScore {
  final List<int> set;

  /// 무작위 조합 대비 인기도 백분위 (0 = 가장 덜 고름, 100 = 가장 많이 고름)
  final double pct;

  /// 무작위 조합 대비 예상 1등 몫 (모델 추정, 1.10 = 10% 많음)
  final double share;
  const PopularityScore(this.set, this.pct, this.share);

  factory PopularityScore.fromJson(Map<String, dynamic> j) => PopularityScore(
        (j['set'] as List).map((n) => (n as num).toInt()).toList()..sort(),
        (j['popularity_pct'] as num).toDouble(),
        (j['share_vs_random'] as num).toDouble(),
      );

  /// '인기 상위 5%' · '비인기 하위 13%' · '보통 (상위 33%)'
  String get label {
    if (pct >= 70) return '인기 상위 ${_fmt(100 - pct)}%';
    if (pct <= 30) return pct < 0.1 ? '비인기 최하위권' : '비인기 하위 ${_fmt(pct)}%';
    return '보통 (하위 ${_fmt(pct)}%)';
  }

  /// '몫 +8%' · '몫 −14%'
  String get shareLabel {
    final d = ((share - 1) * 100).round();
    return d == 0 ? '몫 ±0%' : (d > 0 ? '몫 +$d%' : '몫 −${-d}%');
  }

  /// 0 = 인기(불리) · 1 = 보통 · 2 = 비인기(유리)
  int get tier => pct >= 70 ? 0 : (pct <= 30 ? 2 : 1);

  static String _fmt(double v) => v < 1 ? v.toStringAsFixed(1) : v.round().toString();
}

class NumberPopularity {
  final int target;
  final int trainingEnd;
  final bool passed;
  final Map<String, double> spearman;
  final double? lowThirdR1, highThirdR1;
  final List<PopularityScore> official;
  final List<PopularityScore> picks;

  /// registered | pending | late | none
  final String picksStatus;
  final String pickRule;
  const NumberPopularity({
    required this.target, required this.trainingEnd, required this.passed, required this.spearman,
    this.lowThirdR1, this.highThirdR1, required this.official, required this.picks,
    required this.picksStatus, required this.pickRule,
  });

  factory NumberPopularity.fromRow(Map<String, dynamic> row) {
    final p = Map<String, dynamic>.from(row['payload'] as Map);
    final v = Map<String, dynamic>.from(p['validation'] as Map? ?? const {});
    final r1 = Map<String, dynamic>.from(v['rank1_actual_over_expected'] as Map? ?? const {});
    List<PopularityScore> list(String k) =>
        ((p[k] as List?) ?? const []).map((e) => PopularityScore.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    return NumberPopularity(
      target: (row['target_round'] as num).toInt(),
      trainingEnd: (row['training_end_round'] as num).toInt(),
      passed: v['passed'] == true,
      spearman: {
        for (final e in Map<String, dynamic>.from(v['test_spearman'] as Map? ?? const {}).entries)
          e.key: (e.value as num).toDouble(),
      },
      lowThirdR1: (r1['pred_low_third'] as num?)?.toDouble(),
      highThirdR1: (r1['pred_high_third'] as num?)?.toDouble(),
      official: list('official'),
      picks: list('picks'),
      picksStatus: '${p['picks_status'] ?? 'none'}',
      pickRule: '${p['pick_rule'] ?? ''}',
    );
  }

  /// 표시 중인 공식 세트에 맞는 인기도 (번호 순서 무관)
  PopularityScore? scoreOf(List<int> nums) {
    final k = ([...nums]..sort()).join(',');
    for (final s in official) {
      if (s.set.join(',') == k) return s;
    }
    return null;
  }

  /// '확인 구간 1001~1245회: 4등 쏠림 상관 0.59 · 1등 0.13 — 인기 낮게 본 회차 1등 0.93배, 높게 본 회차 1.10배'
  String get validationLine {
    final s4 = spearman['R4'], s1 = spearman['R1'];
    final b = StringBuffer('검증(확인 1001~1245회): 4등 쏠림 상관 ${s4?.toStringAsFixed(2) ?? '-'} · 1등 ${s1?.toStringAsFixed(2) ?? '-'}');
    if (lowThirdR1 != null && highThirdR1 != null) {
      b.write(' — 인기 낮게 본 회차 1등 ${lowThirdR1!.toStringAsFixed(2)}배, 높게 본 회차 ${highThirdR1!.toStringAsFixed(2)}배');
    }
    return b.toString();
  }

  /// 목표 회차의 최신 저장본 (없으면 null)
  static Future<NumberPopularity?> load(int target) async {
    final rows = await Supabase.instance.client
        .from('research_results')
        .select('target_round,training_end_round,payload')
        .eq('research_type', 'number_popularity')
        .eq('model_version', 'pop-1.0')
        .eq('target_round', target)
        .order('training_end_round', ascending: false)
        .limit(1);
    final l = List<Map<String, dynamic>>.from(rows as List);
    return l.isEmpty ? null : NumberPopularity.fromRow(l.first);
  }
}
