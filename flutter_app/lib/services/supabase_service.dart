import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/lottery_store.dart';
import '../models/lotto_winning_number.dart';
import '../models/pension_winning_number.dart';

class SupabaseService {
  static final _supabase = Supabase.instance.client;

  // 전체 판매점 조회 (lottery_stores 직접, 페이지네이션으로 전체 로드)
  static Future<List<LotteryStore>> getAllStores({
    String? lotteryType,
  }) async {
    try {
      final List<LotteryStore> allStores = [];
      const int pageSize = 1000;
      int offset = 0;
      bool hasMore = true;

      while (hasMore) {
        var query = _supabase.from('lottery_stores').select();

        if (lotteryType != null && lotteryType.isNotEmpty) {
          query = query.eq('lottery_type', lotteryType);
        }

        final response = await query
            .range(offset, offset + pageSize - 1)
            .order('dhlottery_code', ascending: true);

        final list = (response as List).map((json) => LotteryStore.fromJson(json)).toList();
        allStores.addAll(list);

        if (list.length < pageSize) {
          hasMore = false;
        } else {
          offset += pageSize;
        }
      }

      return allStores;
    } catch (e) {
      print('Supabase 전체 판매점 조회 오류: $e');
      return [];
    }
  }

  // Supabase에서 판매점 데이터 조회
  static Future<List<LotteryStore>> getNearbyStores({
    required double latitude,
    required double longitude,
    required double radiusKm,
    String? lotteryType,
  }) async {
    try {
      // 좌표가 있는 판매점만 조회 (대략적 위경도 범위 필터)
      // 1도 ≈ 111km, radiusKm을 도 단위로 변환
      final degreeRange = radiusKm / 111.0 * 1.5; // 여유분 1.5배
      final minLat = latitude - degreeRange;
      final maxLat = latitude + degreeRange;
      final minLng = longitude - degreeRange;
      final maxLng = longitude + degreeRange;

      var query = _supabase.from('lottery_stores').select()
          .not('latitude', 'is', null)
          .gte('latitude', minLat)
          .lte('latitude', maxLat)
          .gte('longitude', minLng)
          .lte('longitude', maxLng);

      if (lotteryType != null && lotteryType.isNotEmpty) {
        query = query.eq('lottery_type', lotteryType);
      }

      final response = await query;

      final stores = (response as List).map((json) {
        return LotteryStore.fromJson(json);
      }).toList();

      // 정확한 거리 계산 및 반경 필터링
      final nearbyStores = stores.where((store) {
        if (store.latitude == null || store.longitude == null) return false;
        final distance = _calculateDistance(
          latitude, longitude, store.latitude!, store.longitude!,
        );
        return distance <= radiusKm;
      }).toList();

      // 거리순 정렬
      nearbyStores.sort((a, b) {
        final distA = _calculateDistance(latitude, longitude, a.latitude ?? 0, a.longitude ?? 0);
        final distB = _calculateDistance(latitude, longitude, b.latitude ?? 0, b.longitude ?? 0);
        return distA.compareTo(distB);
      });

      return nearbyStores;
    } catch (e) {
      print('Supabase 오류: $e');
      return [];
    }
  }

  // 거리 계산 (Haversine 공식)
  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371; // 지구 반지름 (km)

    final dLat = _toRadian(lat2 - lat1);
    final dLon = _toRadian(lon2 - lon1);

    final a = (1 - math.cos(dLat)) / 2 +
        math.cos(_toRadian(lat1)) * math.cos(_toRadian(lat2)) * (1 - math.cos(dLon)) / 2;
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  static double _toRadian(double degree) => degree * math.pi / 180;

  // 지역별 판매점 조회
  static Future<List<LotteryStore>> getStoresByRegion({
    required String region,
    String? lotteryType,
  }) async {
    try {
      var query = _supabase.from('lottery_stores').select().eq('region', region);

      if (lotteryType != null && lotteryType.isNotEmpty) {
        query = query.eq('lottery_type', lotteryType);
      }

      final response = await query;
      return (response as List).map((json) => LotteryStore.fromJson(json)).toList();
    } catch (e) {
      print('Supabase 오류: $e');
      return [];
    }
  }

  // 회차별 판매점 조회 (winning_history 조인)
  static Future<List<LotteryStore>> getStoresByRound({
    required int round,
    String? lotteryType,
  }) async {
    try {
      // 1. winning_history에서 해당 회차의 당첨 기록 조회
      var historyQuery = _supabase.from('winning_history').select('dhlottery_code, prize_tier, purchase_method').eq('round', round);

      if (lotteryType != null && lotteryType.isNotEmpty) {
        historyQuery = historyQuery.eq('lottery_type', lotteryType);
      }

      final historyResponse = await historyQuery;
      final winningRecords = (historyResponse as List);

      if (winningRecords.isEmpty) return [];

      // 당첨 지점의 dhlottery_code 추출
      final winningCodes = winningRecords.map((r) => r['dhlottery_code']).toSet().toList();

      // 2. lottery_stores에서 해당 당첨 지점만 조회 (in_ 필터)
      var storeQuery = _supabase.from('lottery_stores')
          .select('dhlottery_code, store_name, address, region, lottery_type, first_count, second_count, total_count, purchase_method')
          .inFilter('dhlottery_code', winningCodes);

      if (lotteryType != null && lotteryType.isNotEmpty) {
        storeQuery = storeQuery.eq('lottery_type', lotteryType);
      }

      final storeResponse = await storeQuery;
      final allStores = (storeResponse as List).map((json) => LotteryStore.fromJson(json)).toList();

      // 3. 당첨 지점 정보와 회차 정보 결합
      final winningStores = <LotteryStore>[];
      for (var record in winningRecords) {
        final code = record['dhlottery_code'];
        final prizeTier = record['prize_tier'];
        final purchaseMethodFromHistory = record['purchase_method'];

        final store = allStores.firstWhere(
          (s) => s.dhlotteryCode == code,
          orElse: () => LotteryStore(
            dhlotteryCode: code,
            storeName: '정보 없음',
            address: '정보 없음',
            region: '정보 없음',
            lotteryType: lotteryType ?? '',
            round: round,
            prizeTier: prizeTier,
            purchaseMethod: purchaseMethodFromHistory,
          ),
        );

        winningStores.add(
          LotteryStore(
            dhlotteryCode: store.dhlotteryCode,
            storeName: store.storeName,
            address: store.address,
            region: store.region,
            lotteryType: store.lotteryType,
            round: round,
            prizeTier: prizeTier,
            firstCount: store.firstCount,
            secondCount: store.secondCount,
            totalCount: store.totalCount,
            purchaseMethod: purchaseMethodFromHistory ?? store.purchaseMethod,
          ),
        );
      }

      return winningStores;
    } catch (e) {
      print('Supabase 회차별 판매점 조회 오류: $e');
      return [];
    }
  }

  // 특정 회차의 당첨지점 조회 (로또만, 1등/2등 포함)
  static Future<List<LotteryStore>> getLottoWinningStoresForRound(int round) async {
    return getStoresByRound(round: round, lotteryType: 'lotto');
  }

  // 판매점별 당첨 회차 목록 조회 (배지 분석용)
  // 반환: { dhlottery_code: [round1, round2, ...] }
  static Future<Map<String, List<int>>> getWinningRoundsForStores(
    List<String> dhlotteryCodes, {
    String? lotteryType,
    String? prizeTier,
  }) async {
    try {
      if (dhlotteryCodes.isEmpty) return {};

      var query = _supabase
          .from('winning_history')
          .select('dhlottery_code, round')
          .inFilter('dhlottery_code', dhlotteryCodes);

      if (lotteryType != null) {
        query = query.eq('lottery_type', lotteryType);
      }
      if (prizeTier != null) {
        query = query.eq('prize_tier', prizeTier);
      }

      // 5회 이상 당첨 판매점은 많지 않으므로 충분한 limit 설정
      final response = await query.order('round', ascending: true).limit(5000);

      final Map<String, List<int>> result = {};
      for (var row in response) {
        final code = row['dhlottery_code'] as String;
        final round = row['round'] as int;
        result.putIfAbsent(code, () => []).add(round);
      }
      return result;
    } catch (e) {
      print('판매점별 당첨 회차 조회 오류: $e');
      return {};
    }
  }

  // 최신 회차 조회 (Supabase에서 직접)
  static Future<int?> getLatestRound(String lotteryType) async {
    try {
      final response = await _supabase
          .from('winning_history')
          .select('round')
          .eq('lottery_type', lotteryType)
          .order('round', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        return response[0]['round'] as int?;
      }
      return null;
    } catch (e) {
      print('최신 회차 조회 오류: $e');
      return null;
    }
  }

  // 모든 회차 목록 조회 (Supabase)
  static Future<List<int>> getAllRounds(String lotteryType) async {
    try {
      final response = await _supabase
          .from('winning_history')
          .select('DISTINCT round')
          .eq('lottery_type', lotteryType)
          .order('round', ascending: false);

      if (response.isNotEmpty) {
        return (response as List)
            .map((r) => r['round'] as int)
            .toList();
      }
      return [];
    } catch (e) {
      print('회차 목록 조회 오류: $e');
      return [];
    }
  }

  // 회차 페이지 생성 또는 업데이트
  static Future<void> createOrUpdateLottoRound(int round, String status) async {
    try {
      await _supabase.from('lottery_rounds').upsert({
        'round': round,
        'status': status,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'round');
    } catch (e) {
      print('Supabase 회차 생성/업데이트 오류: $e');
    }
  }

  // 회차 페이지 발행 (pending → published)
  static Future<void> publishLottoRound(int round) async {
    try {
      await _supabase
          .from('lottery_rounds')
          .update({
            'status': 'published',
            'published_at': DateTime.now().toIso8601String(),
          })
          .eq('round', round);
    } catch (e) {
      print('Supabase 회차 발행 오류: $e');
    }
  }

  // ========================
  // 당첨번호 (lotto_winning_numbers)
  // ========================

  // 특정 회차 당첨번호 조회
  static Future<LottoWinningNumber?> getWinningNumbersForRound(int round) async {
    try {
      final response = await _supabase
          .from('lotto_winning_numbers')
          .select()
          .eq('round', round)
          .maybeSingle();

      if (response == null) return null;

      return LottoWinningNumber(
        drawDate: response['draw_date'] ?? '',
        round: response['round'] as int,
        numbers: [
          response['num1'] as int,
          response['num2'] as int,
          response['num3'] as int,
          response['num4'] as int,
          response['num5'] as int,
          response['num6'] as int,
        ],
        bonusNumber: response['bonus'] as int,
      );
    } catch (e) {
      print('당첨번호 조회 오류: $e');
      return null;
    }
  }

  // 전체 당첨번호 회차 목록 (번호 포함, 페이지네이션으로 전체 로드)
  static Future<List<LottoWinningNumber>> getAllWinningNumbers() async {
    try {
      final List<LottoWinningNumber> allNumbers = [];
      const int pageSize = 1000;
      int offset = 0;
      bool hasMore = true;

      while (hasMore) {
        final response = await _supabase
            .from('lotto_winning_numbers')
            .select()
            .order('round', ascending: false)
            .range(offset, offset + pageSize - 1);

        final list = (response as List).map((json) => LottoWinningNumber(
          drawDate: json['draw_date'] ?? '',
          round: json['round'] as int,
          numbers: [
            json['num1'] as int,
            json['num2'] as int,
            json['num3'] as int,
            json['num4'] as int,
            json['num5'] as int,
            json['num6'] as int,
          ],
          bonusNumber: json['bonus'] as int,
        )).toList();

        allNumbers.addAll(list);

        if (list.length < pageSize) {
          hasMore = false;
        } else {
          offset += pageSize;
        }
      }

      return allNumbers;
    } catch (e) {
      print('전체 당첨번호 조회 오류: $e');
      return [];
    }
  }

  // 최신 N개 당첨번호 조회 (홈 화면용, 빠른 로딩)
  static Future<List<LottoWinningNumber>> getRecentWinningNumbers(int limit) async {
    try {
      final response = await _supabase
          .from('lotto_winning_numbers')
          .select()
          .order('round', ascending: false)
          .limit(limit);

      return (response as List).map((json) => LottoWinningNumber(
        drawDate: json['draw_date'] ?? '',
        round: json['round'] as int,
        numbers: [
          json['num1'] as int,
          json['num2'] as int,
          json['num3'] as int,
          json['num4'] as int,
          json['num5'] as int,
          json['num6'] as int,
        ],
        bonusNumber: json['bonus'] as int,
      )).toList();
    } catch (e) {
      print('최신 당첨번호 조회 오류: $e');
      return [];
    }
  }

  // 당첨번호 저장 (관리자용)
  static Future<void> saveWinningNumbers(LottoWinningNumber winning) async {
    try {
      await _supabase.from('lotto_winning_numbers').upsert({
        'round': winning.round,
        'num1': winning.numbers[0],
        'num2': winning.numbers[1],
        'num3': winning.numbers[2],
        'num4': winning.numbers[3],
        'num5': winning.numbers[4],
        'num6': winning.numbers[5],
        'bonus': winning.bonusNumber,
        'draw_date': winning.drawDate,
      }, onConflict: 'round');
    } catch (e) {
      print('당첨번호 저장 오류: $e');
    }
  }

  // ========================
  // 연금복권 (pension_winning_numbers)
  // ========================

  // 연금복권 당첨번호 저장
  static Future<void> savePensionWinningNumbers(PensionWinningNumber pension) async {
    try {
      await _supabase.from('pension_winning_numbers').upsert({
        'round': pension.round,
        'winning_group': pension.winningGroup,
        'winning_number': pension.winningNumber,
        'bonus_number': pension.bonusNumber,
        'draw_date': pension.drawDate,
      }, onConflict: 'round');
    } catch (e) {
      print('연금복권 당첨번호 저장 오류: $e');
    }
  }

  // 연금복권 특정 회차 조회
  static Future<PensionWinningNumber?> getPensionWinningForRound(int round) async {
    try {
      final response = await _supabase
          .from('pension_winning_numbers')
          .select()
          .eq('round', round)
          .maybeSingle();

      if (response == null) return null;
      return PensionWinningNumber.fromJson(response);
    } catch (e) {
      print('연금복권 당첨번호 조회 오류: $e');
      return null;
    }
  }

  // 연금복권 전체 당첨번호 조회
  static Future<List<PensionWinningNumber>> getAllPensionWinningNumbers() async {
    try {
      final response = await _supabase
          .from('pension_winning_numbers')
          .select()
          .order('round', ascending: false);

      return (response as List).map((json) => PensionWinningNumber.fromJson(json)).toList();
    } catch (e) {
      print('연금복권 전체 당첨번호 조회 오류: $e');
      return [];
    }
  }

  // ========================
  // pension_rounds 관리 (관리자 발행 추적)
  // ========================

  /// 관리자가 연금 회차 생성 시 호출
  static Future<void> createPensionRound(int round) async {
    try {
      await _supabase.from('pension_rounds').upsert({
        'round': round,
        'status': 'published',
        'stores_published': false,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'round');
    } catch (e) {
      print('pension_rounds 생성 오류: $e');
    }
  }

  /// 관리자가 연금 지점 발행 시 호출
  static Future<void> publishPensionStores(int round) async {
    try {
      await _supabase
          .from('pension_rounds')
          .update({
            'stores_published': true,
            'published_at': DateTime.now().toIso8601String(),
          })
          .eq('round', round);
    } catch (e) {
      print('pension_rounds 발행 오류: $e');
    }
  }

  /// 관리자가 생성한 연금 회차만 조회 (홈 화면용)
  static Future<List<PensionWinningNumber>> getAdminPensionRounds() async {
    try {
      // pension_rounds에 있는 회차 목록
      final roundsResponse = await _supabase
          .from('pension_rounds')
          .select('round')
          .order('round', ascending: false);

      final adminRounds = (roundsResponse as List)
          .map((e) => e['round'] as int)
          .toList();

      if (adminRounds.isEmpty) return [];

      // 해당 회차의 당첨번호 조회
      final numbersResponse = await _supabase
          .from('pension_winning_numbers')
          .select()
          .inFilter('round', adminRounds)
          .order('round', ascending: false);

      return (numbersResponse as List)
          .map((json) => PensionWinningNumber.fromJson(json))
          .toList();
    } catch (e) {
      print('관리자 연금 회차 조회 오류: $e');
      return [];
    }
  }

  /// 지점 발행된 회차인지 확인
  static Future<bool> isPensionStoresPublished(int round) async {
    try {
      final response = await _supabase
          .from('pension_rounds')
          .select('stores_published')
          .eq('round', round)
          .maybeSingle();

      if (response == null) return false;
      return response['stores_published'] == true;
    } catch (e) {
      return false;
    }
  }

  /// 지점 발행된 회차의 당첨지점 조회
  static Future<List<LotteryStore>> getPublishedPensionStores(int round) async {
    final published = await isPensionStoresPublished(round);
    if (!published) return [];
    return getPensionWinningStoresForRound(round);
  }

  // 연금복권 최신 회차 번호
  static Future<int?> getPensionLatestRound() async {
    try {
      final response = await _supabase
          .from('pension_winning_numbers')
          .select('round')
          .order('round', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        return response[0]['round'] as int?;
      }
      return null;
    } catch (e) {
      print('연금복권 최신 회차 조회 오류: $e');
      return null;
    }
  }

  // 연금복권 당첨지점 조회
  static Future<List<LotteryStore>> getPensionWinningStoresForRound(int round) async {
    return getStoresByRound(round: round, lotteryType: 'pension');
  }

  // store_badges 테이블에서 배지 조회
  static Future<List<Map<String, dynamic>>> getStoreBadges(
    List<String> dhlotteryCodes, {
    String? lotteryType,
  }) async {
    try {
      if (dhlotteryCodes.isEmpty) return [];

      final List<Map<String, dynamic>> allBadges = [];
      // in 필터 한번에 너무 많으면 안 됨 → 500개씩 분할
      const chunkSize = 500;
      for (int i = 0; i < dhlotteryCodes.length; i += chunkSize) {
        final chunk = dhlotteryCodes.sublist(
          i,
          i + chunkSize > dhlotteryCodes.length ? dhlotteryCodes.length : i + chunkSize,
        );

        var query = _supabase
            .from('store_badges')
            .select('dhlottery_code, badge_type, badge_label, priority')
            .inFilter('dhlottery_code', chunk);

        if (lotteryType != null && lotteryType.isNotEmpty) {
          query = query.eq('lottery_type', lotteryType);
        }

        final response = await query.order('priority', ascending: true);
        allBadges.addAll((response as List).cast<Map<String, dynamic>>());
      }

      return allBadges;
    } catch (e) {
      print('store_badges 조회 오류: $e');
      return [];
    }
  }

  // 특정 회차 페이지 조회
  static Future<Map<String, dynamic>?> getLottoRound(int round) async {
    try {
      final response = await _supabase
          .from('lottery_rounds')
          .select()
          .eq('round', round)
          .single();
      return response as Map<String, dynamic>?;
    } catch (e) {
      print('Supabase 회차 조회 오류: $e');
      return null;
    }
  }
}
