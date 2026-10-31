// 일반 모드 복권연구 로또 탭 — 당첨번호 아래 최신 회차 당첨 판매점 (연금 판매점과 같은 모양 · 1등 전부 · 2등은 5곳 + 더 보기 · ★ 저장)
import 'package:flutter/material.dart';

import '../models/lottery_store.dart';
import '../services/supabase_service.dart';
import 'briefing_store_widgets.dart' show FavoriteStoreStar;

const kLottoColor = Color(0xFF1565C0);

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

  // 연금 판매점과 같은 모양 — 번호 · 이름 · 지역/회차 · 역대 1·2등 · ★
  Widget _row(int i, LotteryStore s, bool first) => Container(
        key: ValueKey('latest_store_${s.dhlotteryCode}'),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: kLottoColor.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          SizedBox(width: 24, child: Text('$i', style: const TextStyle(fontWeight: FontWeight.w900, color: kLottoColor))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.storeName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              Text('${s.region.isEmpty ? s.address : s.region} · ${widget.round}회 ${first ? '1등' : '2등'}'
                  '${(s.purchaseMethod ?? '').isEmpty ? '' : ' · ${s.purchaseMethod}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            ]),
          ),
          if (s.firstCount != null || s.secondCount != null)
            Text('역대 1등 ${s.firstCount ?? 0}회 · 2등 ${s.secondCount ?? 0}회',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          if (s.dhlotteryCode.isNotEmpty) FavoriteStoreStar(code: s.dhlotteryCode, name: s.storeName),
        ]),
      );

  Widget _sub(String t, Color c) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(t, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: c)),
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
          var i = 0;
          return Container(
            key: const ValueKey('latest_round_stores'),
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kLottoColor.withValues(alpha: 0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 26, height: 26, alignment: Alignment.center,
                  decoration: BoxDecoration(color: kLottoColor, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('${widget.round}회 로또 당첨 판매점', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
              ]),
              const SizedBox(height: 8),
              Text('${widget.round}회 1·2등이 나온 판매점 · ★를 누르면 즐겨찾기에 저장됩니다',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
              const SizedBox(height: 4),
              if (all.isEmpty)
                Text('${widget.round}회 당첨 판매점은 아직 수집 전입니다.', style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
              if (firsts.isNotEmpty) ...[
                _sub('1등 ${firsts.length}곳', const Color(0xFFB8860B)),
                for (final s in firsts) _row(++i, s, true),
              ],
              if (seconds.isNotEmpty) ...[
                _sub('2등 ${seconds.length}곳', Colors.blueGrey.shade700),
                for (final s in shownSeconds) _row(++i, s, false),
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
