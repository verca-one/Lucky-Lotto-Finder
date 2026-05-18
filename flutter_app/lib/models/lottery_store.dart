class LotteryStore {
  final String dhlotteryCode;
  final String storeName;
  final String address;
  final String region;
  final String lotteryType;
  final int round;
  final String prizeTier;
  final List<int>? firstWins;
  final List<int>? secondWins;
  final int? firstCount;
  final int? secondCount;
  final int? totalCount;
  final String? purchaseMethod;

  // Legacy 필드 (호환성)
  final String? gameStoreId;
  final String? method;
  final double? latitude;
  final double? longitude;
  final int? storeRank;
  final int? winningAmount;
  final String? createdAt;
  final String? crawledAt;

  LotteryStore({
    required this.dhlotteryCode,
    required this.storeName,
    required this.address,
    required this.region,
    required this.lotteryType,
    required this.round,
    required this.prizeTier,
    this.firstWins,
    this.secondWins,
    this.firstCount,
    this.secondCount,
    this.totalCount,
    this.purchaseMethod,
    this.gameStoreId,
    this.method,
    this.latitude,
    this.longitude,
    this.storeRank,
    this.winningAmount,
    this.createdAt,
    this.crawledAt,
  });

  factory LotteryStore.fromJson(Map<String, dynamic> json) {
    // first_wins, second_wins 파싱
    List<int> parseWins(dynamic data) {
      if (data == null) return [];
      if (data is List) {
        return data.whereType<int>().toList();
      }
      return [];
    }

    return LotteryStore(
      dhlotteryCode: json['dhlottery_code'] ?? '',
      storeName: json['store_name'] ?? '',
      address: json['address'] ?? '',
      region: json['region'] ?? '',
      lotteryType: json['lottery_type'] ?? '',
      round: json['round'] ?? 0,
      prizeTier: json['prize_tier'] ?? '',
      firstWins: parseWins(json['first_wins']),
      secondWins: parseWins(json['second_wins']),
      firstCount: json['first_count'],
      secondCount: json['second_count'],
      totalCount: json['total_count'],
      purchaseMethod: json['purchase_method'],
      gameStoreId: json['game_store_id'],
      method: json['method'],
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      storeRank: json['store_rank'],
      winningAmount: json['winning_amount'],
      createdAt: json['created_at'],
      crawledAt: json['crawled_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dhlottery_code': dhlotteryCode,
      'store_name': storeName,
      'address': address,
      'region': region,
      'lottery_type': lotteryType,
      'round': round,
      'prize_tier': prizeTier,
      'first_wins': firstWins,
      'second_wins': secondWins,
      'first_count': firstCount,
      'second_count': secondCount,
      'total_count': totalCount,
      'purchase_method': purchaseMethod,
      'game_store_id': gameStoreId,
      'method': method,
      'latitude': latitude,
      'longitude': longitude,
      'store_rank': storeRank,
      'winning_amount': winningAmount,
      'created_at': createdAt,
      'crawled_at': crawledAt,
    };
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
