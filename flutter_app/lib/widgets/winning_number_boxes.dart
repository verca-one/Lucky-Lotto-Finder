// 당첨번호 네모칸 — 로또 · 연금복권이 같은 모양으로 당첨번호를 보여 준다 (일반 모드 추천 상단)
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 흰 네모칸 하나 (숫자 · 글자)
Widget numberBox(String text, {double size = 36, Color? accent, double fontSize = 16}) => Container(
      width: size,
      height: size + 4,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border(bottom: BorderSide(color: accent ?? Colors.grey.shade400, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Text(text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: const Color(0xFF1A1A2E))),
    );

/// 로또 번호대 색 (네모칸 아래 줄)
Color lottoRangeColor(int n) {
  if (n <= 10) return const Color(0xFFFFB300);
  if (n <= 20) return const Color(0xFF42A5F5);
  if (n <= 30) return const Color(0xFFEF5350);
  if (n <= 40) return const Color(0xFF9E9E9E);
  return const Color(0xFF66BB6A);
}

/// 로또 당첨번호 6개 + 보너스 (네모칸)
class LottoWinningBoxes extends StatelessWidget {
  final List<int> numbers;
  final int bonus;
  const LottoWinningBoxes({super.key, required this.numbers, required this.bonus});

  @override
  Widget build(BuildContext context) {
    final nums = [...numbers]..sort();
    return Row(children: [
      for (final n in nums) Padding(padding: const EdgeInsets.only(right: 5), child: numberBox('$n', accent: lottoRangeColor(n))),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 3),
        child: Text('+', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w300)),
      ),
      numberBox('$bonus', accent: Colors.orange.shade600),
    ]);
  }
}

/// 연금복권 최신 당첨번호
class PensionLatestWinning {
  final int round, group;
  final String number, bonus, drawDate;
  const PensionLatestWinning(this.round, this.group, this.number, this.bonus, this.drawDate);

  static Future<PensionLatestWinning?> load() async {
    final rows = await Supabase.instance.client.from('pension_winning_numbers')
        .select('round,winning_group,winning_number,bonus_number,draw_date').order('round', ascending: false).limit(1);
    if ((rows as List).isEmpty) return null;
    final r = rows.first;
    return PensionLatestWinning((r['round'] as num).toInt(), (r['winning_group'] as num?)?.toInt() ?? 0,
        '${r['winning_number'] ?? ''}', '${r['bonus_number'] ?? ''}', '${r['draw_date'] ?? ''}');
  }
}

/// 연금복권 당첨번호 헤더 — [N조] + 6자리 네모칸 · 보너스 6자리 (각 조)
class PensionWinningHeader extends StatefulWidget {
  final Future<PensionLatestWinning?> Function()? loader;
  const PensionWinningHeader({super.key, this.loader});
  @override
  State<PensionWinningHeader> createState() => _PensionWinningHeaderState();
}

class _PensionWinningHeaderState extends State<PensionWinningHeader> {
  late final Future<PensionLatestWinning?> _f = (widget.loader ?? PensionLatestWinning.load)();
  static const _accent = Color(0xFFEF6C00);

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pension_winning_header'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFFEF6C00), Color(0xFFFFA726)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      child: FutureBuilder<PensionLatestWinning?>(
        future: _f,
        builder: (context, snap) {
          final w = snap.data;
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(height: 90, child: Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)));
          }
          if (w == null) {
            return const Text('연금복권 당첨번호를 준비하고 있습니다.', style: TextStyle(color: Colors.white, fontSize: 13));
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('연금복권720+ ${w.round}회 당첨번호',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.3)),
            const SizedBox(height: 4),
            Text(w.drawDate.length >= 10 ? w.drawDate.substring(0, 10) : w.drawDate,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
            const SizedBox(height: 12),
            Row(children: [
              _label('1등'),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: const Color(0xFF6D2C00), borderRadius: BorderRadius.circular(8)),
                child: Text('${w.group}조', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              for (final ch in w.number.split('')) Padding(padding: const EdgeInsets.only(right: 4), child: numberBox(ch, size: 30, accent: _accent)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _label('보너스'),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                child: const Text('각조', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
              ),
              for (final ch in w.bonus.split('')) Padding(padding: const EdgeInsets.only(right: 4), child: numberBox(ch, size: 30, accent: Colors.white70)),
            ]),
          ]);
        },
      ),
    );
  }

  Widget _label(String s) => SizedBox(
        width: 42,
        child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
      );
}
