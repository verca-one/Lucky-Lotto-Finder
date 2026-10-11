// ══════════════════════════════════════════════════════════════
// 회차별 판매액·등수별 당첨자 수 (research_prize_stats) — 2026-10-09 수집 승인
//
// · 백필: research_prize_stats_collector.py (독립 스크립트, 기존 크롤러와 무관)
// · 주간 갱신: 앱 실행 시 동행복권 공개 당첨결과 JSON 최신 페이지(10회차)만 읽어 누락분 upsert
//   (요청 1~2회, 식별 가능한 User-Agent, 실패 시 조용히 건너뜀 — 서버·워크플로 불필요)
// · 용도: 구매예측 판매량 보정 실증 모델, 이월(1등 당첨자 0) 판정, 공정성 참고
// ══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'research_core.dart';

class PrizeStats {
  final int round;
  final String? drawDate;
  final List<int> numbers;
  final int bonus;
  final List<int?> rankWinners; // index 1..5 (0 unused)
  final List<int?> rankAmount;
  final int? totalSales;
  final int? prizePool;
  final int? autoWinners, manualWinners, semiAutoWinners;
  const PrizeStats({
    required this.round, this.drawDate, required this.numbers, required this.bonus,
    required this.rankWinners, required this.rankAmount, this.totalSales, this.prizePool,
    this.autoWinners, this.manualWinners, this.semiAutoWinners,
  });

  int? get rank1Winners => rankWinners[1];
  bool get isJackpotRolledOver => rank1Winners == 0; // 이 회차 1등 없음 → 다음 회차 이월

  /// 게임 가격 추정: 5등(3개 일치) 당첨자 수는 판매 게임수 × 182780/8145060 에 거의 정확히 비례
  int get gamePrice {
    final r5 = rankWinners[5];
    if (totalSales == null || r5 == null || r5 <= 0) return 1000;
    final gamesEst = r5 * kLottoTotalCombos / 182780.0;
    final implied = totalSales! / gamesEst;
    return implied > 1500 ? 2000 : 1000;
  }

  /// 판매 게임 수 (판매액 ÷ 게임 가격)
  double? get gamesSold => totalSales == null ? null : totalSales! / gamePrice;

  /// 균등분포 가정 시 기대 1등 당첨자 수
  double? get expectedRank1 => gamesSold == null ? null : gamesSold! / kLottoTotalCombos;

  /// 당첨 조합의 상대 인기도 = 관측 1등 / 기대 1등 (판매량 보정)
  double? get popularityRatioRank1 => (expectedRank1 == null || expectedRank1! <= 0 || rank1Winners == null)
      ? null : rank1Winners! / expectedRank1!;

  factory PrizeStats.fromRow(Map<String, dynamic> r) => PrizeStats(
        round: (r['round'] as num).toInt(), drawDate: r['draw_date'] as String?,
        numbers: [1, 2, 3, 4, 5, 6].map((i) => (r['num$i'] as num?)?.toInt() ?? 0).toList(),
        bonus: (r['bonus'] as num?)?.toInt() ?? 0,
        rankWinners: [null, ...[1, 2, 3, 4, 5].map((k) => (r['rank${k}_winners'] as num?)?.toInt())],
        rankAmount: [null, ...[1, 2, 3, 4, 5].map((k) => (r['rank${k}_amount'] as num?)?.toInt())],
        totalSales: (r['total_sales_amount'] as num?)?.toInt(), prizePool: (r['prize_pool_amount'] as num?)?.toInt(),
        autoWinners: (r['auto_winners'] as num?)?.toInt(), manualWinners: (r['manual_winners'] as num?)?.toInt(),
        semiAutoWinners: (r['semi_auto_winners'] as num?)?.toInt(),
      );
}

class PrizeStatsService {
  PrizeStatsService._();
  static final instance = PrizeStatsService._();
  final _db = Supabase.instance.client;
  Map<int, PrizeStats>? _cache;

  static const _api = 'https://www.dhlottery.co.kr/lt645/selectPstLt645InfoNew.do';
  static const _ua = 'LuckyLottoFinder-Research/1.0 (in-app weekly prize-stats sync)';

  Future<Map<int, PrizeStats>> loadAll({bool force = false}) async {
    if (!force && _cache != null) return _cache!;
    final out = <int, PrizeStats>{};
    try {
      int offset = 0;
      while (true) {
        final page = await _db.from('research_prize_stats').select().order('round', ascending: true).range(offset, offset + 999);
        final list = List<Map<String, dynamic>>.from(page as List);
        for (final r in list) { final s = PrizeStats.fromRow(r); out[s.round] = s; }
        if (list.length < 1000) break;
        offset += 1000;
      }
    } catch (e) {
      debugPrint('[PrizeStats] load skipped (table?): $e');
    }
    _cache = out;
    return out;
  }

  PrizeStats? get(int round) => _cache?[round];
  int get latestRound => _cache == null || _cache!.isEmpty ? 0 : _cache!.keys.reduce(max);

  /// 최신 회차가 DB에 없으면 공개 JSON 최신 페이지(10회차)만 읽어 누락분 저장. 실패해도 예외 없음.
  Future<int> syncLatest(int latestKnownRound) async {
    final have = await loadAll();
    if (have.containsKey(latestKnownRound)) return 0;
    try {
      final client = http.Client();
      String cookie = '';
      try {
        // 세션 워밍업 (쿠키 획득) — 공개 페이지 1회
        final warm = await client.get(Uri.parse('https://www.dhlottery.co.kr/lt645/result'),
            headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 15));
        final sc = warm.headers['set-cookie'];
        if (sc != null) cookie = sc.split(',').map((c) => c.split(';').first.trim()).where((c) => c.contains('=')).join('; ');
      } catch (_) {}
      final uri = Uri.parse('$_api?srchDir=center&srchLtEpsd=$latestKnownRound');
      final res = await client.get(uri, headers: {
        'User-Agent': _ua, 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest',
        'Referer': 'https://www.dhlottery.co.kr/lt645/result', if (cookie.isNotEmpty) 'Cookie': cookie,
      }).timeout(const Duration(seconds: 20));
      client.close();
      if (res.statusCode != 200 || !res.body.trim().startsWith('{')) return 0;
      final list = ((jsonDecode(res.body) as Map)['data'] as Map?)?['list'] as List? ?? [];
      final rows = <Map<String, dynamic>>[];
      for (final it in list.whereType<Map>()) {
        final round = (it['ltEpsd'] as num?)?.toInt();
        if (round == null || have.containsKey(round)) continue;
        final ymd = '${it['ltRflYmd'] ?? ''}';
        rows.add({
          'round': round,
          'draw_date': ymd.length == 8 ? '${ymd.substring(0, 4)}-${ymd.substring(4, 6)}-${ymd.substring(6, 8)}' : null,
          for (int i = 1; i <= 6; i++) 'num$i': (it['tm${i}WnNo'] as num?)?.toInt(),
          'bonus': (it['bnsWnNo'] as num?)?.toInt(),
          for (int k = 1; k <= 5; k++) ...{
            'rank${k}_winners': (it['rnk${k}WnNope'] as num?)?.toInt(),
            'rank${k}_amount': (it['rnk${k}WnAmt'] as num?)?.toInt(),
            'rank${k}_total': (it['rnk${k}SumWnAmt'] as num?)?.toInt(),
          },
          'total_sales_amount': (it['wholEpsdSumNtslAmt'] as num?)?.toInt(),
          'prize_pool_amount': (it['rlvtEpsdSumNtslAmt'] as num?)?.toInt(),
          'auto_winners': (it['winType1'] as num?)?.toInt(), 'manual_winners': (it['winType2'] as num?)?.toInt(),
          'semi_auto_winners': (it['winType3'] as num?)?.toInt(),
          'raw': it,
        });
      }
      if (rows.isEmpty) return 0;
      await _db.from('research_prize_stats').upsert(rows, onConflict: 'round');
      await loadAll(force: true);
      return rows.length;
    } catch (e) {
      debugPrint('[PrizeStats] syncLatest skipped: $e');
      return 0;
    }
  }
}
