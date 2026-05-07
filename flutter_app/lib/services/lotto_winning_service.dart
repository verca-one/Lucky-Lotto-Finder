import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/lotto_winning_number.dart';
import '../models/lottery_store.dart';
import '../models/pension_winning_number.dart';
import 'supabase_service.dart';

class LottoWinningService {
  static const String _lottoWinningKey = 'admin_lotto_winning_rounds';
  static const String _lottoLoadedStoresByRoundKey = 'admin_lotto_loaded_stores_by_round';
  static const String _pensionWinningKey = 'admin_pension_winning_rounds';
  static const String _pensionLoadedStoresByRoundKey = 'admin_pension_loaded_stores_by_round';

  Future<List<LottoWinningNumber>> getAllRounds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lottoWinningKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final rounds = decoded
          .map((e) => LottoWinningNumber.fromJson(e as Map<String, dynamic>))
          .toList();
      rounds.sort((a, b) => b.round.compareTo(a.round));
      return rounds;
    } catch (_) {
      return [];
    }
  }

  Future<LottoWinningNumber?> getLatestRound() async {
    // Get latest round from SharedPreferences
    final rounds = await getAllRounds();
    if (rounds.isEmpty) return null;
    return rounds.first;
  }

  Future<void> saveRound(LottoWinningNumber newRound) async {
    final prefs = await SharedPreferences.getInstance();
    final rounds = await getAllRounds();

    final filtered = rounds.where((e) => e.round != newRound.round).toList();
    filtered.add(newRound);
    filtered.sort((a, b) => b.round.compareTo(a.round));

    final encoded = jsonEncode(filtered.map((e) => e.toJson()).toList());
    await prefs.setString(_lottoWinningKey, encoded);
  }

  Future<void> deleteRound(int round) async {
    final prefs = await SharedPreferences.getInstance();
    final rounds = await getAllRounds();
    final filtered = rounds.where((e) => e.round != round).toList();
    await prefs.setString(_lottoWinningKey, jsonEncode(filtered.map((e) => e.toJson()).toList()));

    final loadedMap = await _getLoadedStoresMap();
    loadedMap.remove(round.toString());
    await prefs.setString(_lottoLoadedStoresByRoundKey, jsonEncode(loadedMap));
  }

  Future<void> saveLoadedStoresForRound(int round, List<LotteryStore> stores) async {
    final prefs = await SharedPreferences.getInstance();
    final loadedMap = await _getLoadedStoresMap();
    loadedMap[round.toString()] = stores
        .map((e) => {
              'game_store_id': e.gameStoreId,
              'dhlottery_code': e.dhlotteryCode,
              'store_name': e.storeName,
              'address': e.address,
              'region': e.region,
              'method': e.method,
              'purchase_method': e.purchaseMethod,
              'latitude': e.latitude,
              'longitude': e.longitude,
              'lottery_type': e.lotteryType,
              'round': e.round,
              'prize_tier': e.prizeTier,
              'store_rank': e.storeRank,
              'winning_amount': e.winningAmount,
              'created_at': e.createdAt,
              'crawled_at': e.crawledAt,
            })
        .toList();
    await prefs.setString(_lottoLoadedStoresByRoundKey, jsonEncode(loadedMap));
  }

  Future<List<LotteryStore>> getLoadedStoresForRound(int round) async {
    try {
      // Try to get winning stores from Supabase
      final supabaseStores = await SupabaseService.getLottoWinningStoresForRound(round);
      if (supabaseStores.isNotEmpty) {
        // Save to SharedPreferences for offline caching
        await saveLoadedStoresForRound(round, supabaseStores);
        return supabaseStores;
      }
    } catch (e) {
      print('Supabase 당첨지점 조회 오류: $e');
    }

    // Fall back to SharedPreferences cache
    final loadedMap = await _getLoadedStoresMap();
    final rawList = loadedMap[round.toString()];
    if (rawList is! List) return [];

    return rawList
        .whereType<Map>()
        .map((e) => LotteryStore.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> _getLoadedStoresMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lottoLoadedStoresByRoundKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  // ========================
  // 연금복권 당첨회차 로컬 관리
  // ========================

  Future<List<PensionWinningNumber>> getAllPensionRounds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pensionWinningKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final rounds = decoded
          .map((e) => PensionWinningNumber.fromJson(e as Map<String, dynamic>))
          .toList();
      rounds.sort((a, b) => b.round.compareTo(a.round));
      return rounds;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePensionRound(PensionWinningNumber newRound) async {
    final prefs = await SharedPreferences.getInstance();
    final rounds = await getAllPensionRounds();
    final filtered = rounds.where((e) => e.round != newRound.round).toList();
    filtered.add(newRound);
    filtered.sort((a, b) => b.round.compareTo(a.round));
    await prefs.setString(
        _pensionWinningKey, jsonEncode(filtered.map((e) => e.toJson()).toList()));
  }

  Future<void> deletePensionRound(int round) async {
    final prefs = await SharedPreferences.getInstance();
    final rounds = await getAllPensionRounds();
    final filtered = rounds.where((e) => e.round != round).toList();
    await prefs.setString(
        _pensionWinningKey, jsonEncode(filtered.map((e) => e.toJson()).toList()));
  }

  // ========================
  // 연금복권 당첨지점 로컬 저장
  // ========================

  Future<void> savePensionStoresForRound(int round, List<LotteryStore> stores) async {
    final prefs = await SharedPreferences.getInstance();
    final loadedMap = await _getPensionLoadedStoresMap();
    loadedMap[round.toString()] = stores
        .map((e) => {
              'game_store_id': e.gameStoreId,
              'dhlottery_code': e.dhlotteryCode,
              'store_name': e.storeName,
              'address': e.address,
              'region': e.region,
              'method': e.method,
              'purchase_method': e.purchaseMethod,
              'latitude': e.latitude,
              'longitude': e.longitude,
              'lottery_type': e.lotteryType,
              'round': e.round,
              'prize_tier': e.prizeTier,
              'store_rank': e.storeRank,
              'winning_amount': e.winningAmount,
              'created_at': e.createdAt,
              'crawled_at': e.crawledAt,
            })
        .toList();
    await prefs.setString(_pensionLoadedStoresByRoundKey, jsonEncode(loadedMap));
  }

  /// 관리자가 발행한 연금 당첨지점만 반환 (로컬 전용, Supabase 안 감)
  Future<List<LotteryStore>> getPublishedPensionStoresForRound(int round) async {
    final loadedMap = await _getPensionLoadedStoresMap();
    final rawList = loadedMap[round.toString()];
    if (rawList is! List) return [];
    return rawList
        .whereType<Map>()
        .map((e) => LotteryStore.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> _getPensionLoadedStoresMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pensionLoadedStoresByRoundKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }
}
