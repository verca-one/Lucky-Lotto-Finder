// 토요일 8시 최종본 변경점 — 월요일 선정 대비 무엇이 바뀌었나 (표 · 막대그래프, 저장본만 읽음)
//   ①~③ 구매할 번호: 주간 점검(weekly_digest) 월요일·토요일 스냅샷의 장부 세트 비교
//   ④ 제미나이 가설 트랙: 토요일 최종본(ht-1.0-sat)의 월요일 선정 대비 세트·명당
//   가설: 적용 후보로 새로 들어온 것 / 빠진 것 · 이번 주 AI·비서 활동 월요일 vs 토요일
import 'package:flutter/material.dart';

import '../services/research/hypothesis_track.dart';
import '../widgets/weekly_check_card.dart';

/// 영역별 비교 한 줄 (영역, 월요일 세트 수, 토요일 세트 수, 바뀐 세트 수)
typedef AreaDiff = (String, int, int, int);

String _key(List s) => ([for (final n in s) (n as num).toInt()]..sort()).join(',');

/// 변경점 계산 (순수 함수 — 테스트 대상)
class SaturdayChanges {
  final List<AreaDiff> areas;
  final int storesChanged, storesTotal;
  final List<String> added, dropped;
  final Map<String, (num, num)> activity; // 이름 → (월요일, 토요일)

  /// 영역 이름 → (월요일 세트, 토요일 세트)
  final Map<String, (List<List<int>>, List<List<int>>)> sets;
  const SaturdayChanges(this.areas, this.storesChanged, this.storesTotal, this.added, this.dropped, this.activity,
      {this.sets = const {}});

  /// 월요일에 없다가 토요일에 새로 등록된 영역은 '바뀜'이 아니라 '새로 등록'
  static bool isNew(AreaDiff a) => a.$2 == 0 && a.$3 > 0;
  int get setsChanged => areas.where((x) => !isNew(x)).fold(0, (a, x) => a + x.$4);
  int get setsNew => areas.where(isNew).fold(0, (a, x) => a + x.$3);
  bool get any => setsChanged > 0 || setsNew > 0 || storesChanged > 0 || added.isNotEmpty || dropped.isNotEmpty;

  factory SaturdayChanges.of(WeeklyCheck? w, HypothesisTrack? t) {
    final areas = <AreaDiff>[];
    final sets = <String, (List<List<int>>, List<List<int>>)>{};
    List<List<int>> ints(List l) => [for (final x in l) ([for (final n in x as List) (n as num).toInt()]..sort())];
    final wb = Map<String, dynamic>.from((w?.wed?['buy'] as Map?) ?? const {});
    final sb = Map<String, dynamic>.from((w?.sat?['buy'] as Map?) ?? const {});
    for (final k in const ['official', 'popularity', 'purchase']) {
      final a = ((wb[k] as Map?)?['sets'] as List?) ?? const [];
      final b = ((sb[k] as Map?)?['sets'] as List?) ?? const [];
      if (a.isEmpty && b.isEmpty) continue;
      final label = '${(sb[k] as Map?)?['label'] ?? (wb[k] as Map?)?['label'] ?? k}';
      final ka = {for (final s in a) _key(s as List)};
      areas.add((label, a.length, b.length, b.where((s) => !ka.contains(_key(s as List))).length));
      sets[label] = (ints(a), ints(b));
    }
    if (t != null && t.isFinal) {
      areas.add(('④ 제미나이 가설 트랙', t.wedSets.length, t.sets.length, t.changedSets));
      sets['④ 제미나이 가설 트랙'] = (t.wedSets, [for (final x in t.sets) x.numbers]);
    }
    final changes = w?.changes ?? const [];
    final act = <String, (num, num)>{};
    final wa = Map<String, dynamic>.from((w?.wed?['activity'] as Map?) ?? const {});
    final sa = Map<String, dynamic>.from((w?.sat?['activity'] as Map?) ?? const {});
    for (final (k, name) in const [('hypotheses', '이번 주 가설'), ('simulated', '모의 실험'), ('sim_raised', '확률 상승')]) {
      if (wa[k] != null || sa[k] != null) act[name] = ((wa[k] as num?) ?? 0, (sa[k] as num?) ?? 0);
    }
    final wq = (w?.wed?['qualifying'] as List?)?.length, sq = (w?.sat?['qualifying'] as List?)?.length;
    if (wq != null || sq != null) act['적용 후보 가설'] = (wq ?? 0, sq ?? 0);
    return SaturdayChanges(
      areas,
      t != null && t.isFinal ? t.changedStores : 0,
      t?.stores.length ?? 0,
      [for (final c in changes) if (c['type'] == 'new_hypothesis') '${c['note']}'.replaceFirst('새로 적용 후보가 된 가설: ', '')],
      [for (final c in changes) if (c['type'] == 'dropped_hypothesis') '${c['note']}'.replaceFirst('적용 후보에서 빠진 가설: ', '')],
      act,
      sets: sets,
    );
  }
}

class SaturdayFinalChangesScreen extends StatelessWidget {
  final int target;
  final WeeklyCheck? weekly;
  final HypothesisTrack? track;
  const SaturdayFinalChangesScreen({super.key, required this.target, this.weekly, this.track});

  @override
  Widget build(BuildContext context) {
    final c = SaturdayChanges.of(weekly, track);
    final color = c.any ? const Color(0xFFE65100) : Colors.blueGrey;
    return Scaffold(
      appBar: AppBar(
        title: Text('$target회 토요일 최종본 변경점', style: const TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: Text(
              c.any
                  ? '월요일 대비 바뀐 번호 ${c.setsChanged}세트${c.setsNew > 0 ? ' · 새로 등록 ${c.setsNew}세트' : ''} · 명당 ${c.storesChanged}곳 · 적용 후보 가설 +${c.added.length} / −${c.dropped.length}'
                  : '월요일 선정과 같습니다 — 바뀐 번호·명당·가설이 없습니다.',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: color)),
        ),
        if (weekly?.sat?['verdict'] != null) ...[
          const SizedBox(height: 6),
          Text('${weekly!.sat!['verdict']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
        const SizedBox(height: 16),
        _title('영역별 번호 세트 (월요일 → 토요일)'),
        _table(['영역', '월요일', '토요일', '바뀜'], [
          for (final x in c.areas)
            [x.$1, '${x.$2}세트', '${x.$3}세트',
              SaturdayChanges.isNew(x) ? '새로 등록 ${x.$3}세트' : x.$4 > 0 ? '바뀜 ${x.$4}세트' : '유지'],
          if (track != null && track!.isFinal) ['④ 가설 명당', '${track!.wedStores.length}곳', '${c.storesTotal}곳', c.storesChanged > 0 ? '${c.storesChanged}곳' : '없음'],
        ]),
        const SizedBox(height: 10),
        _title('영역별 세트 — 유지 · 바뀜 · 새로 등록'),
        for (final x in c.areas) _stack(x),
        Row(children: [
          _legend(const Color(0xFF43A047), '유지'),
          const SizedBox(width: 12),
          _legend(const Color(0xFFE65100), '바뀜'),
          const SizedBox(width: 12),
          _legend(const Color(0xFF1E88E5), '새로 등록'),
        ]),
        // 영역마다 번호 — 월요일 vs 토요일 (모든 영역)
        for (final e in c.sets.entries) ...[
          const SizedBox(height: 16),
          _title('${e.key} — 월요일 vs 토요일'),
          for (var i = 0; i < e.value.$2.length || i < e.value.$1.length; i++)
            _setPair(i, i < e.value.$1.length ? e.value.$1[i] : const [], i < e.value.$2.length ? e.value.$2[i] : const []),
        ],
        const SizedBox(height: 16),
        _title('적용 후보 가설 변화'),
        if (c.added.isEmpty && c.dropped.isEmpty) _small('바뀐 가설이 없습니다.'),
        for (final s in c.added) _small('＋ $s', color: const Color(0xFF2E7D32)),
        for (final s in c.dropped) _small('− $s', color: const Color(0xFFC62828)),
        if (c.activity.isNotEmpty) ...[
          const SizedBox(height: 16),
          _title('이번 주 AI 전략기획부 · 비서 활동 (월요일 → 토요일)'),
          _table(['항목', '월요일', '토요일', '차이'], [
            for (final e in c.activity.entries) [e.key, '${e.value.$1}', '${e.value.$2}', _diff(e.value.$2 - e.value.$1)],
          ]),
          const SizedBox(height: 10),
          for (final e in c.activity.entries) _pairBar(e.key, e.value.$1, e.value.$2),
          Row(children: [
            _legend(const Color(0xFF90A4AE), '월요일'),
            const SizedBox(width: 12),
            _legend(const Color(0xFF5E35B1), '토요일'),
          ]),
        ],
        const SizedBox(height: 16),
        _small('①~③ 구매할 번호는 사전 등록 장부에 잠겨 있어 자동으로 바뀌지 않습니다. ④ 제미나이 가설 트랙은 토요일 최종본을 따로 등록합니다.'),
      ]),
    );
  }

  static String _diff(num d) => d == 0 ? '0' : (d > 0 ? '+$d' : '$d');

  Widget _title(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)));

  Widget _small(String t, {Color? color}) =>
      Text(t, style: TextStyle(fontSize: 12, height: 1.45, color: color ?? Colors.grey.shade700, fontWeight: color == null ? null : FontWeight.w700));

  Widget _table(List<String> head, List<List<String>> rows) => Table(
        border: TableBorder.all(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
        columnWidths: const {0: FlexColumnWidth(2.2)},
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade100),
            children: [for (final h in head) _cell(h, bold: true)],
          ),
          for (final r in rows)
            TableRow(children: [
              for (var i = 0; i < r.length; i++) _cell(r[i], warn: i == r.length - 1 && r[i] != '없음' && r[i] != '0'),
            ]),
        ],
      );

  Widget _cell(String t, {bool bold = false, bool warn = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Text(t, style: TextStyle(fontSize: 12, fontWeight: bold || warn ? FontWeight.w800 : FontWeight.w500,
            color: warn ? const Color(0xFFE65100) : Colors.black87)),
      );

  Widget _bar(String label, num v, num max, Color c, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(7)),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: max <= 0 ? 0 : (v / max).clamp(0, 1).toDouble(),
                child: Container(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(7))),
              ),
            ),
          ),
          SizedBox(width: 44, child: Text(text, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
        ]),
      );

  /// 한 영역 막대 — 유지(초록) · 바뀜(주황) · 새로 등록(파랑)
  Widget _stack(AreaDiff x) {
    final total = x.$3 == 0 ? (x.$2 == 0 ? 5 : x.$2) : x.$3;
    final isNew = SaturdayChanges.isNew(x);
    final kept = isNew ? 0 : (x.$3 - x.$4).clamp(0, total);
    final changed = isNew ? 0 : x.$4;
    final fresh = isNew ? x.$3 : 0;
    Widget seg(int n, Color c) => n <= 0 ? const SizedBox.shrink() : Expanded(flex: n, child: Container(height: 14, color: c));
    return Padding(
      key: ValueKey('sat_stack_${x.$1}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 120, child: Text(x.$1, style: const TextStyle(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Container(
              color: Colors.grey.shade200,
              child: Row(children: [
                seg(kept, const Color(0xFF43A047)),
                seg(changed, const Color(0xFFE65100)),
                seg(fresh, const Color(0xFF1E88E5)),
                seg(total - kept - changed - fresh, Colors.grey.shade200),
              ]),
            ),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(isNew ? '신규 $fresh' : changed > 0 ? '바뀜 $changed' : '유지 $kept',
              textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _pairBar(String label, num a, num b) {
    final m = (a > b ? a : b) == 0 ? 1 : (a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
        _bar('월요일', a, m, const Color(0xFF90A4AE), '$a'),
        _bar('토요일', b, m, const Color(0xFF5E35B1), '$b'),
      ]),
    );
  }

  Widget _legend(Color c, String t) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 11)),
      ]);

  Widget _setPair(int i, List<int> wed, List<int> sat) {
    Widget nums(List<int> s, Set<int> other) => s.isEmpty
        ? Text('없음 (월요일엔 등록 전)', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600))
        : Wrap(spacing: 3, children: [
          for (final n in [...s]..sort())
            Container(
              width: 24, height: 24, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: other.contains(n) ? Colors.grey.shade200 : const Color(0xFFFFE0B2),
                shape: BoxShape.circle,
              ),
              child: Text('$n', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
            ),
        ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 18, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const SizedBox(width: 40, child: Text('월요일', style: TextStyle(fontSize: 10.5))), Expanded(child: nums(wed, sat.toSet()))]),
            const SizedBox(height: 3),
            Row(children: [const SizedBox(width: 40, child: Text('토요일', style: TextStyle(fontSize: 10.5))), Expanded(child: nums(sat, wed.toSet()))]),
          ]),
        ),
      ]),
    );
  }
}
