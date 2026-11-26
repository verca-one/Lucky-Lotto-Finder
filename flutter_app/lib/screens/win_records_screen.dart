// 즐겨찾기 › 당첨기록 탭 — 내 구매 기록 중 당첨된 것만 카드로 (추첨 날짜 · 등수 · 그 판매점에서 산 횟수)
//   폰 안 구매 기록(my_purchases) + 당첨번호만 읽음. 새로 저장하는 것 없음.
import 'package:flutter/material.dart';

import '../models/lotto_winning_number.dart';
import '../services/purchase_records.dart';
import '../services/research/briefing_hit_check.dart' show lottoRank;
import '../services/supabase_service.dart';
import '../widgets/winning_number_boxes.dart' show numberBall, lottoRangeColor;

/// 당첨된 기록 한 건
class WinEntry {
  final PurchaseRecord record;
  final LottoWinningNumber win;
  final int rank; // 가장 높은 등수
  final List<(List<int>, int)> games; // 당첨된 게임과 등수
  final int visits; // 이 판매점에서 산 횟수 (판매점 없는 기록은 0)
  const WinEntry(this.record, this.win, this.rank, this.games, this.visits);
}

/// 당첨 기록 고르기 (순수 함수) — 최근 회차 먼저
List<WinEntry> winEntries(List<PurchaseRecord> records, Map<int, LottoWinningNumber?> wins) {
  final out = <WinEntry>[];
  for (final r in records) {
    final w = wins[r.round];
    if (w == null) continue;
    final games = [
      for (final g in r.games)
        if (lottoRank(g, w.numbers, w.bonusNumber) case final k?) (g, k),
    ];
    if (games.isEmpty) continue;
    final visits = r.storeCode.isEmpty ? 0 : records.where((x) => x.storeCode == r.storeCode).length;
    out.add(WinEntry(r, w, games.map((e) => e.$2).reduce((a, b) => a < b ? a : b), games, visits));
  }
  out.sort((a, b) => b.record.round.compareTo(a.record.round));
  return out;
}

class WinRecordsScreen extends StatefulWidget {
  final Future<List<PurchaseRecord>> Function()? loader;
  final Future<LottoWinningNumber?> Function(int round)? winLoader;
  const WinRecordsScreen({super.key, this.loader, this.winLoader});
  @override
  State<WinRecordsScreen> createState() => _WinRecordsScreenState();
}

class _WinRecordsScreenState extends State<WinRecordsScreen> {
  List<WinEntry>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await (widget.loader ?? PurchaseRecords.load)();
    final wins = <int, LottoWinningNumber?>{};
    for (final round in {for (final r in records) r.round}) {
      try {
        wins[round] = await (widget.winLoader ?? SupabaseService.getWinningNumbersForRound)(round);
      } catch (_) {}
    }
    if (mounted) setState(() => _list = winEntries(records, wins));
  }

  Widget _card(WinEntry e) {
    final r = e.record;
    return Container(
      key: ValueKey('win_${r.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD54F), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('🎉 ${e.rank}등 당첨',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFB8860B))),
              const Spacer(),
              Text('${r.round}회 · ${e.win.drawDate}',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(r.storeName.isEmpty ? '판매점 없이 기록한 번호' : r.storeName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, color: r.storeName.isEmpty ? Colors.grey.shade600 : null)),
              ),
              if (e.visits > 0)
                Text('이 판매점 구매 ${e.visits}번',
                    key: ValueKey('win_visits_${r.id}'),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF1565C0))),
            ],
          ),
          const SizedBox(height: 8),
          for (final (g, k) in e.games)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (final n in g)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Opacity(
                        opacity: e.win.numbers.contains(n) || (k == 2 && n == e.win.bonusNumber) ? 1 : 0.28,
                        child: numberBall('$n', lottoRangeColor(n), size: 28, fontSize: 11.5),
                      ),
                    ),
                  const Spacer(),
                  Text('$k등', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFD84315))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = _list;
    if (l == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: Color(0xFFB8860B), size: 22),
              const SizedBox(width: 8),
              Text('당첨기록 (${l.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          if (l.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('아직 당첨 기록이 없습니다.\n즐겨찾기에서 산 번호를 넣어 두면 추첨 뒤 당첨되면 여기에 모입니다.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5)),
            )
          else
            ...l.map(_card),
        ],
      ),
    );
  }
}
