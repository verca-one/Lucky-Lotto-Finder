// 일반 모드 복권연구 — 당첨번호 아래 '지난 회차 번호' 버튼 → 회차별 당첨번호 목록 (로또 · 연금 공용, DB 읽기만)
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/winning_number_boxes.dart';

const kPastPageSize = 30;

/// 한 회차 (로또: nums 6개 + bonus / 연금: group 조 + number 6자리 + bonusNo 6자리)
class PastRound {
  final int round;
  final String drawDate;
  final List<int> nums;
  final int? bonus, group;
  final String number, bonusNo;
  const PastRound(this.round, this.drawDate,
      {this.nums = const [], this.bonus, this.group, this.number = '', this.bonusNo = ''});
}

Future<List<PastRound>> loadPastRounds(String type, int offset) async {
  final db = Supabase.instance.client;
  if (type == 'pension') {
    final rows = await db.from('pension_winning_numbers')
        .select('round,draw_date,winning_group,winning_number,bonus_number')
        .order('round', ascending: false).range(offset, offset + kPastPageSize - 1);
    return [
      for (final r in List<Map<String, dynamic>>.from(rows as List))
        PastRound((r['round'] as num).toInt(), '${r['draw_date'] ?? ''}',
            group: (r['winning_group'] as num?)?.toInt(), number: '${r['winning_number'] ?? ''}', bonusNo: '${r['bonus_number'] ?? ''}'),
    ];
  }
  final rows = await db.from('lotto_winning_numbers')
      .select('round,draw_date,num1,num2,num3,num4,num5,num6,bonus')
      .order('round', ascending: false).range(offset, offset + kPastPageSize - 1);
  return [
    for (final r in List<Map<String, dynamic>>.from(rows as List))
      PastRound((r['round'] as num).toInt(), '${r['draw_date'] ?? ''}',
          nums: [for (var i = 1; i <= 6; i++) (r['num$i'] as num).toInt()]..sort(), bonus: (r['bonus'] as num?)?.toInt()),
  ];
}

/// 당첨번호 헤더 안 — 지난 회차 번호 버튼 (흰 테두리)
class PastRoundsButton extends StatelessWidget {
  final String type; // lotto | pension
  const PastRoundsButton({super.key, required this.type});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton.icon(
          key: ValueKey('past_rounds_$type'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white70),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PastWinningNumbersScreen(type: type))),
          icon: const Icon(Icons.history_rounded, size: 16),
          label: const Text('지난 회차 번호', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        ),
      );
}

class PastWinningNumbersScreen extends StatefulWidget {
  final String type;
  final Future<List<PastRound>> Function(String type, int offset)? loader;
  const PastWinningNumbersScreen({super.key, required this.type, this.loader});
  @override
  State<PastWinningNumbersScreen> createState() => _PastWinningNumbersScreenState();
}

class _PastWinningNumbersScreenState extends State<PastWinningNumbersScreen> {
  final _rows = <PastRound>[];
  bool _busy = false, _end = false, _error = false;

  bool get _pension => widget.type == 'pension';

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_busy || _end) return;
    setState(() => _busy = true);
    try {
      final l = await (widget.loader ?? loadPastRounds)(widget.type, _rows.length);
      _rows.addAll(l);
      _end = l.length < kPastPageSize;
      _error = false;
    } catch (_) {
      _error = true;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final color = _pension ? const Color(0xFFEF6C00) : const Color(0xFF1565C0);
    return Scaffold(
      appBar: AppBar(
        title: Text(_pension ? '연금복권720+ 지난 회차 번호' : '로또 6/45 지난 회차 번호',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i == _rows.length) {
            if (_busy) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            if (_error) {
              return TextButton(onPressed: _more, child: const Text('불러오지 못했습니다 — 다시 시도'));
            }
            if (_end) return const SizedBox.shrink();
            return OutlinedButton(key: const ValueKey('past_more'), onPressed: _more, child: const Text('더 보기'));
          }
          return _pension ? _pensionRow(_rows[i]) : _lottoRow(_rows[i]);
        },
      ),
    );
  }

  Widget _head(PastRound r, Color c) => Row(children: [
        Text('${r.round}회', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c)),
        const SizedBox(width: 8),
        Text(r.drawDate.length >= 10 ? r.drawDate.substring(0, 10) : r.drawDate,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
      ]);

  BoxDecoration get _card => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      );

  Widget _lottoRow(PastRound r) => Container(
        key: ValueKey('past_row_${r.round}'),
        padding: const EdgeInsets.all(12),
        decoration: _card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _head(r, const Color(0xFF1565C0)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(children: [
              for (final n in r.nums) Padding(padding: const EdgeInsets.only(right: 5), child: numberBall('$n', lottoRangeColor(n), size: 34)),
              const Padding(padding: EdgeInsets.only(left: 2, right: 7), child: Text('+', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              if (r.bonus != null) numberBall('${r.bonus}', lottoRangeColor(r.bonus!), size: 34),
            ]),
          ),
        ]),
      );

  Widget _pensionRow(PastRound r) {
    Widget chip(String t, Color bg, Color fg) => Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Text(t, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12.5)),
        );
    Widget digits(String n) => Row(children: [
          for (final e in n.split('').asMap().entries)
            Padding(padding: const EdgeInsets.only(right: 4), child: numberBall(e.value, kPensionDigitColors[e.key % 6], size: 30, fontSize: 13)),
        ]);
    return Container(
      key: ValueKey('past_row_${r.round}'),
      padding: const EdgeInsets.all(12),
      decoration: _card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _head(r, const Color(0xFFEF6C00)),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(children: [chip('1등', const Color(0xFFFFF3E0), const Color(0xFFEF6C00)), chip('${r.group}조', const Color(0xFFEF6C00), Colors.white), digits(r.number)]),
        ),
        if (r.bonusNo.length == 6) ...[
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(children: [chip('보너스', Colors.grey.shade100, Colors.grey.shade700), chip('각조', Colors.grey.shade200, Colors.grey.shade800), digits(r.bonusNo)]),
          ),
        ],
      ]),
    );
  }
}
