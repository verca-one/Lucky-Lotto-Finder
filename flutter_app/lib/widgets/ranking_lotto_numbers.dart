// 홈 랭킹 머리 아래 — 최신 로또 당첨번호 한 줄 (lotto_winning_numbers 최신 회차, 읽기만)
import 'package:flutter/material.dart';

import '../models/lotto_winning_number.dart';
import '../services/supabase_service.dart';
import 'winning_number_boxes.dart';

class RankingLottoNumbers extends StatefulWidget {
  final Future<LottoWinningNumber?> Function()? loader;
  const RankingLottoNumbers({super.key, this.loader});
  @override
  State<RankingLottoNumbers> createState() => _RankingLottoNumbersState();
}

Future<LottoWinningNumber?> _latest() async {
  final l = await SupabaseService.getRecentWinningNumbers(1);
  return l.isEmpty ? null : l.first;
}

String _date(String d) {
  final t = DateTime.tryParse(d);
  if (t == null) return d;
  return '${t.year}.${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')}';
}

class _RankingLottoNumbersState extends State<RankingLottoNumbers> {
  late final Future<LottoWinningNumber?> _f = (widget.loader ?? _latest)();

  @override
  Widget build(BuildContext context) => FutureBuilder<LottoWinningNumber?>(
        future: _f,
        builder: (context, snap) {
          final w = snap.data;
          if (w == null || w.numbers.length != 6) return const SizedBox.shrink();
          final nums = [...w.numbers]..sort();
          return Container(
            key: const ValueKey('ranking_lotto_numbers'),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFE082)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('로또 ${w.round}회 당첨번호',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Color(0xFF1A1A2E))),
                const Spacer(),
                Text('${_date(w.drawDate)} 추첨', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              ]),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(children: [
                  for (final n in nums)
                    Padding(padding: const EdgeInsets.only(right: 6), child: numberBall('$n', lottoRangeColor(n), size: 36)),
                  const Padding(
                    padding: EdgeInsets.only(left: 2, right: 8),
                    child: Text('+', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A2E))),
                  ),
                  numberBall('${w.bonusNumber}', lottoRangeColor(w.bonusNumber), size: 36),
                ]),
              ),
            ]),
          );
        },
      );
}
