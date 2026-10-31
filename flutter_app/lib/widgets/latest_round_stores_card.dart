// 일반 모드 복권연구 로또 탭 — 당첨번호 아래 최신 회차 당첨 판매점 (1등 전부 · 2등은 5곳 + 더 보기 · ★ 저장)
import 'package:flutter/material.dart';

import '../models/lottery_store.dart';
import '../services/supabase_service.dart';
import 'briefing_store_widgets.dart' show FavoriteStoreStar;

class LatestRoundStoresCard extends StatefulWidget {
  final int round;
  final Future<List<LotteryStore>> Function(int round)? loader;
  const LatestRoundStoresCard({super.key, required this.round, this.loader});
  @override
  State<LatestRoundStoresCard> createState() => _LatestRoundStoresCardState();
}

class _LatestRoundStoresCardState extends State<LatestRoundStoresCard> {
  late final Future<List<LotteryStore>> _f =
      (widget.loader ?? (r) => SupabaseService.getStoresByRound(round: r, lotteryType: 'lotto'))(widget.round);
  bool _all = false;

  Widget _row(LotteryStore s, Color c) => Padding(
        key: ValueKey('latest_store_${s.dhlotteryCode}'),
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(Icons.storefront_rounded, size: 16, color: c),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.storeName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Text('${s.address}${(s.purchaseMethod ?? '').isEmpty ? '' : ' · ${s.purchaseMethod}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ]),
          ),
          if (s.dhlotteryCode.isNotEmpty) FavoriteStoreStar(code: s.dhlotteryCode, name: s.storeName),
        ]),
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LotteryStore>>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
          final all = snap.data ?? const <LotteryStore>[];
          bool first(LotteryStore s) => s.prizeTier == 'first' || s.prizeTier == '1';
          final firsts = all.where(first).toList();
          final seconds = all.where((s) => !first(s)).toList();
          final shownSeconds = _all ? seconds : seconds.take(5).toList();
          return Container(
            key: const ValueKey('latest_round_stores'),
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8EDF5)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${widget.round}회 당첨 판매점',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
              Text('★를 누르면 즐겨찾기에 저장됩니다', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              if (all.isEmpty)
                Text('${widget.round}회 당첨 판매점은 아직 수집 전입니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              if (firsts.isNotEmpty) ...[
                Text('1등 ${firsts.length}곳', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFB8860B))),
                const SizedBox(height: 4),
                for (final s in firsts) _row(s, const Color(0xFFB8860B)),
              ],
              if (seconds.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('2등 ${seconds.length}곳', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.blueGrey.shade600)),
                const SizedBox(height: 4),
                for (final s in shownSeconds) _row(s, Colors.blueGrey.shade600),
                if (seconds.length > 5)
                  TextButton(
                    key: const ValueKey('latest_stores_more'),
                    onPressed: () => setState(() => _all = !_all),
                    child: Text(_all ? '접기' : '2등 ${seconds.length - 5}곳 더 보기'),
                  ),
              ],
            ]),
          );
        },
      );
}
