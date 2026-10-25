// 브리핑 추천 당첨확인 — 브리핑이 회차별로 추천한 번호를 그 회차 당첨번호와 맞춰 본다 (관리자 메뉴)
//
// 번호 출처 = 사전 등록 장부(research_predictions, 등록 후 변경 불가) — 회차 검증(db-1.0)과 같은 세트 고르기 규칙
//   ① 공식 5세트 (official_final · fr-1.0) · ② 비인기 5세트 (popularity_pick · pop-1.0)
//   ③ 구매예측 5세트 (purchase_prediction · 최신 버전) · 제미나이 가설 트랙 (hypothesis_track · 토요일 최종본 ht-1.0-sat 우선)
// 당첨번호 = lotto_winning_numbers · 등수별 당첨금 = research_prize_stats (읽기만, 새 계산 규칙 없음 — 일치 개수로 등수만 셈)
import 'package:supabase_flutter/supabase_flutter.dart';

class HitGroupDef {
  final String key, algorithm, label, short;
  final String? version; // 고정 버전 (null = 최신)
  final List<String> prefer; // 먼저 고를 버전 순서
  const HitGroupDef(this.key, this.algorithm, this.label, this.short, {this.version, this.prefer = const []});
}

const kHitGroups = [
  HitGroupDef('official', 'official_final', '① 공식 추천번호', '공식', version: 'fr-1.0'),
  HitGroupDef('popularity', 'popularity_pick', '② 비인기 추천조합', '비인기', version: 'pop-1.0'),
  HitGroupDef('purchase', 'purchase_prediction', '③ 구매예측 번호', '구매예측'),
  HitGroupDef('hypothesis', 'hypothesis_track', '제미나이 가설 추천번호', '제미나이', prefer: ['ht-1.0-sat', 'ht-1.0']),
];

/// 4등 · 5등은 고정 당첨금 (1~3등은 회차별 research_prize_stats)
const kFixedPrize = {4: 50000, 5: 5000};

/// 로또 등수 (1~5등, 낙첨 null)
int? lottoRank(List<int> set, List<int> win, int bonus) {
  final m = set.where(win.contains).length;
  if (m == 6) return 1;
  if (m == 5) return set.contains(bonus) ? 2 : 3;
  if (m == 4) return 4;
  if (m == 3) return 5;
  return null;
}

class HitSet {
  final List<int> numbers;
  final List<int> hits; // 맞힌 번호
  final bool bonusHit;
  final int? rank; // null = 낙첨 (추첨 전이면 의미 없음)
  const HitSet(this.numbers, {this.hits = const [], this.bonusHit = false, this.rank});
}

class HitGroup {
  final HitGroupDef def;
  final String? version;
  final List<HitSet> sets; // 비어 있으면 그 회차에 등록 없음
  const HitGroup(this.def, {this.version, this.sets = const []});

  bool get registered => sets.isNotEmpty;
  List<HitSet> get won => sets.where((s) => s.rank != null).toList();
  int? get bestRank => won.isEmpty ? null : won.map((s) => s.rank!).reduce((a, b) => a < b ? a : b);
}

class HitRound {
  final int round;
  final String drawDate;
  final List<int>? win; // null = 추첨 전 (당첨번호 미수집)
  final int? bonus;
  final List<HitGroup> groups;
  final Map<int, int> amounts; // 등수 → 1게임 당첨금 (원)
  const HitRound({required this.round, this.drawDate = '', this.win, this.bonus, this.groups = const [], this.amounts = const {}});

  bool get drawn => win != null;
  List<HitGroup> get registered => groups.where((g) => g.registered).toList();
  int get setCount => groups.fold(0, (a, g) => a + g.sets.length);
  int get wonCount => groups.fold(0, (a, g) => a + g.won.length);
  int? get bestRank {
    final r = [for (final g in groups) if (g.bestRank != null) g.bestRank!];
    return r.isEmpty ? null : r.reduce((a, b) => a < b ? a : b);
  }

  /// 등수 → 당첨 세트 수
  Map<int, int> get rankCounts {
    final m = <int, int>{};
    for (final g in groups) {
      for (final s in g.won) {
        m[s.rank!] = (m[s.rank!] ?? 0) + 1;
      }
    }
    return m;
  }

  int? amountOf(int rank) => amounts[rank] ?? kFixedPrize[rank];

  /// 당첨금 합계 (1게임씩 샀다고 볼 때) · 당첨금 미확보 등수가 있으면 false
  (int, bool) get prizeTotal {
    var sum = 0;
    var known = true;
    for (final e in rankCounts.entries) {
      final a = amountOf(e.key);
      if (a == null) {
        known = false;
      } else {
        sum += a * e.value;
      }
    }
    return (sum, known);
  }
}

int _verNum(String v) {
  final m = RegExp(r'(\d+)\.(\d+)').firstMatch(v);
  return m == null ? 0 : int.parse(m.group(1)!) * 1000 + int.parse(m.group(2)!);
}

/// 회차·묶음별로 등록본 하나 고르기 (회차 검증과 같은 규칙: 고정 버전 → 선호 버전 → 버전 숫자·등록 시각 최신)
Map<String, dynamic>? pickRegistration(List<Map<String, dynamic>> regs, int round, HitGroupDef d) {
  final rows = regs.where((r) => (r['target_round'] as num).toInt() == round && r['algorithm'] == d.algorithm &&
      (d.version == null || r['version'] == d.version)).toList();
  if (rows.isEmpty) return null;
  for (final v in d.prefer) {
    final p = rows.where((r) => r['version'] == v).toList();
    if (p.isNotEmpty) return p.first;
  }
  rows.sort((a, b) {
    final c = _verNum('${a['version']}').compareTo(_verNum('${b['version']}'));
    return c != 0 ? c : '${a['generated_at'] ?? ''}'.compareTo('${b['generated_at'] ?? ''}');
  });
  return rows.last;
}

/// 장부 · 당첨번호 · 당첨금 → 회차별 결과 (최신 회차 먼저, 순수 함수)
List<HitRound> buildHitRounds(
  List<Map<String, dynamic>> regs,
  Map<int, (List<int>, int, String)> wins,
  Map<int, Map<int, int>> amounts,
) {
  final rounds = {
    for (final r in regs)
      if (kHitGroups.any((d) => d.algorithm == r['algorithm'])) (r['target_round'] as num).toInt(),
  }.toList()
    ..sort((a, b) => b.compareTo(a));
  final out = <HitRound>[];
  for (final t in rounds) {
    final w = wins[t];
    final groups = <HitGroup>[];
    for (final d in kHitGroups) {
      final r = pickRegistration(regs, t, d);
      if (r == null) {
        groups.add(HitGroup(d));
        continue;
      }
      final sets = <HitSet>[];
      for (final s in (r['sets'] as List? ?? const [])) {
        final ns = [for (final n in (s as List)) (n as num).toInt()]..sort();
        if (ns.length != 6) continue;
        sets.add(w == null
            ? HitSet(ns)
            : HitSet(ns, hits: ns.where(w.$1.contains).toList(), bonusHit: ns.contains(w.$2), rank: lottoRank(ns, w.$1, w.$2)));
      }
      groups.add(HitGroup(d, version: '${r['version']}', sets: sets));
    }
    out.add(HitRound(round: t, drawDate: w?.$3 ?? '', win: w?.$1, bonus: w?.$2, groups: groups, amounts: amounts[t] ?? const {}));
  }
  return out;
}

class BriefingHitCheck {
  static Future<List<HitRound>> load() async {
    final db = Supabase.instance.client;
    final regs = <Map<String, dynamic>>[];
    for (var off = 0;; off += 1000) {
      final rows = await db
          .from('research_predictions')
          .select('algorithm,version,target_round,sets,generated_at')
          .inFilter('algorithm', [for (final d in kHitGroups) d.algorithm])
          .order('target_round', ascending: false)
          .range(off, off + 999);
      regs.addAll(List<Map<String, dynamic>>.from(rows as List));
      if (rows.length < 1000) break;
    }
    final rounds = {for (final r in regs) (r['target_round'] as num).toInt()}.toList();
    final wins = <int, (List<int>, int, String)>{};
    final amounts = <int, Map<int, int>>{};
    for (var i = 0; i < rounds.length; i += 200) {
      final part = rounds.sublist(i, i + 200 > rounds.length ? rounds.length : i + 200);
      final w = await db.from('lotto_winning_numbers').select('round,draw_date,num1,num2,num3,num4,num5,num6,bonus')
          .inFilter('round', part);
      for (final r in List<Map<String, dynamic>>.from(w as List)) {
        wins[(r['round'] as num).toInt()] = (
          [for (var k = 1; k <= 6; k++) (r['num$k'] as num).toInt()]..sort(),
          (r['bonus'] as num).toInt(),
          '${r['draw_date'] ?? ''}',
        );
      }
      try {
        final p = await db.from('research_prize_stats')
            .select('round,rank1_amount,rank2_amount,rank3_amount,rank4_amount,rank5_amount').inFilter('round', part);
        for (final r in List<Map<String, dynamic>>.from(p as List)) {
          amounts[(r['round'] as num).toInt()] = {
            for (var k = 1; k <= 5; k++)
              if (r['rank${k}_amount'] != null) k: (r['rank${k}_amount'] as num).toInt(),
          };
        }
      } catch (_) {
        // 당첨금 자료 없으면 4·5등 고정 금액만 쓴다
      }
    }
    return buildHitRounds(regs, wins, amounts);
  }
}
