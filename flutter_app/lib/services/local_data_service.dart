import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/lottery_store.dart';
import 'supabase_service.dart';

class LocalDataService {
  static const String _lottoFile = 'assets/zero_base_lotto_stores_latest.json';
  static const String _pensionFile = 'assets/zero_base_pension_stores_latest.json';
  static const String _speedlotto2000File = 'assets/zero_base_speedlotto_2000_stores_latest.json';
  static const String _speedlotto1000File = 'assets/zero_base_speedlotto_1000_stores_latest.json';
  static const String _speedlotto500File = 'assets/zero_base_speedlotto_500_stores_latest.json';

  Future<List<LotteryStore>> getLottoStores() async {
    return await SupabaseService.getAllStores(lotteryType: 'lotto');
  }

  Future<List<LotteryStore>> getPensionStores() async {
    return await SupabaseService.getAllStores(lotteryType: 'pension');
  }

  Future<List<LotteryStore>> getSpeedlotto2000Stores() async {
    return await SupabaseService.getAllStores(lotteryType: 'speedlotto_2000');
  }

  Future<List<LotteryStore>> getSpeedlotto1000Stores() async {
    return await SupabaseService.getAllStores(lotteryType: 'speedlotto_1000');
  }

  Future<List<LotteryStore>> getSpeedlotto500Stores() async {
    return await SupabaseService.getAllStores(lotteryType: 'speedlotto_500');
  }

  Future<List<LotteryStore>> _loadStores(String filePath) async {
    try {
      final jsonString = await rootBundle.loadString(filePath);
      final jsonData = jsonDecode(jsonString);

      final storesList = jsonData['stores'] as List;
      return storesList
          .map((store) => LotteryStore.fromJson(store))
          .toList();
    } catch (e) {
      print('Error loading $filePath: $e');
      return [];
    }
  }
}
