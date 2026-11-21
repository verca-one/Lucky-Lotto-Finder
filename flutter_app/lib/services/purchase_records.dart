// 나의 번호 › 구입 기록 — 어느 판매점에서 몇 회 어떤 번호를 샀는지 (폰 안 SharedPreferences 'my_purchases')
//   번호 넣기: 로또 용지 QR(폰 안에서 글자만 읽음 — 동행복권 접속 없음) · 저장한 번호(my_lotto_numbers) 불러오기
//   당첨 확인: 그 회차 당첨번호(lotto_winning_numbers)가 들어오면 자동으로 맞춰 봄 (등수 계산은 briefing_hit_check.lottoRank)
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PurchaseRecord {
  final String id, storeCode, storeName, storeAddress;
  final int round;
  final List<List<int>> games; // 한 게임 = 정렬된 6개
  final DateTime createdAt;
  const PurchaseRecord({required this.id, required this.storeCode, required this.storeName, this.storeAddress = '',
      required this.round, required this.games, required this.createdAt});

  Map<String, dynamic> toJson() => {
        'id': id, 'store_code': storeCode, 'store_name': storeName, 'store_address': storeAddress,
        'round': round, 'games': games, 'created_at': createdAt.toIso8601String(),
      };

  factory PurchaseRecord.fromJson(Map<String, dynamic> j) => PurchaseRecord(
        id: '${j['id']}', storeCode: '${j['store_code'] ?? ''}', storeName: '${j['store_name'] ?? ''}',
        storeAddress: '${j['store_address'] ?? ''}', round: (j['round'] as num).toInt(),
        games: [for (final g in (j['games'] as List? ?? const [])) [for (final n in g as List) (n as num).toInt()]],
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
      );
}

class PurchaseRecords {
  static const key = 'my_purchases';

  /// 최신 기록 먼저
  static Future<List<PurchaseRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <PurchaseRecord>[];
    for (final s in prefs.getStringList(key) ?? const <String>[]) {
      try {
        out.add(PurchaseRecord.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {} // 깨진 기록은 건너뜀
    }
    return out..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> add(PurchaseRecord r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, [...prefs.getStringList(key) ?? const <String>[], jsonEncode(r.toJson())]);
  }

  static Future<void> remove(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final keep = (prefs.getStringList(key) ?? const <String>[]).where((s) {
      try {
        return '${(jsonDecode(s) as Map)['id']}' != id;
      } catch (_) {
        return true;
      }
    }).toList();
    await prefs.setStringList(key, keep);
  }
}

/// 로또 용지 QR 글자 → (회차, 게임들). 로또 QR 이 아니면 null (순수 함수)
///   예: http://m.dhlottery.co.kr/?v=1251m010203040506q071422283541...
///   'v=' 뒤 4자리 = 회차, 이어서 [영문 1자 + 숫자 12자리](두 자리씩 6개) = 한 게임. 1~45 · 중복 없는 것만 게임으로 본다.
(int, List<List<int>>)? parseLottoQr(String raw) {
  final m = RegExp(r'[?&]v=(\d{4})([0-9a-zA-Z]*)').firstMatch(raw.trim());
  if (m == null) return null;
  final round = int.parse(m.group(1)!);
  final games = <List<int>>[];
  for (final g in RegExp(r'[a-zA-Z](\d{12})').allMatches(m.group(2)!)) {
    final ns = [for (var i = 0; i < 12; i += 2) int.parse(g.group(1)!.substring(i, i + 2))];
    if (ns.every((n) => n >= 1 && n <= 45) && ns.toSet().length == 6) games.add(ns..sort());
    if (games.length == 5) break; // 용지 한 장 최대 5게임
  }
  return round > 0 && games.isNotEmpty ? (round, games) : null;
}
