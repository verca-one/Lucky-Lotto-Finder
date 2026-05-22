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

  // 특정 코드 목록으로 판매점 조회 (즐겨찾기용)
  static Future<List<LotteryStore>> getStoresByCodes(List<String> codes) async {
    if (codes.isEmpty) return [];
    try {
      final response = await _supabase
          .from('lottery_stores')
          .select()
          .inFilter('dhlottery_code', codes)
          .eq('lottery_type', 'lotto');
      return (response as List).map((json) => LotteryStore.fromJson(json)).toList();
    } catch (e) {
      print('즐겨찾기 판매점 조회 오류: $e');
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

  /// 홈 랭킹: 로또 1등 당첨 횟수 기준 TOP N 지점 조회
  /// first_count 내림차순 + latest_first_win 내림차순 (최근 가중치)
  static Future<List<Map<String, dynamic>>> getTopRankedStores({
    int limit = 30,
  }) async {
    try {
      final response = await _supabase
          .from('lottery_stores')
          .select('dhlottery_code, store_name, address, region, lottery_type, first_count, second_count, total_count, purchase_method, latest_first_win, latest_second_win')
          .eq('lottery_type', 'lotto')
          .gt('first_count', 0)
          .order('first_count', ascending: false)
          .order('latest_first_win', ascending: false)
          .limit(limit);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('TOP 랭킹 조회 오류: $e');
      return [];
    }
  }

  /// 특정 지점의 연금복권 당첨 정보 조회 (배지용)
  static Future<Map<String, Map<String, dynamic>>> getPensionInfoForStores(
    List<String> dhlotteryCodes,
  ) async {
    try {
      if (dhlotteryCodes.isEmpty) return {};
      final response = await _supabase
          .from('lottery_stores')
          .select('dhlottery_code, first_count, second_count, total_count')
          .eq('lottery_type', 'pension')
          .inFilter('dhlottery_code', dhlotteryCodes)
          .gt('total_count', 0);
      final Map<String, Map<String, dynamic>> result = {};
      for (final row in (response as List)) {
        result[row['dhlottery_code'] as String] = Map<String, dynamic>.from(row);
      }
      return result;
    } catch (e) {
      print('연금복권 정보 조회 오류: $e');
      return {};
    }
  }

  /// 특정 판매점의 당첨 이력 조회 (로또 + 연금 모두)
  static Future<List<Map<String, dynamic>>> getWinningHistoryForStore(
    String dhlotteryCode,
  ) async {
    try {
      final response = await _supabase
          .from('winning_history')
          .select('dhlottery_code, lottery_type, round, prize_tier')
          .eq('dhlottery_code', dhlotteryCode)
          .order('round', ascending: false)
          .limit(200);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('당첨 이력 조회 오류: $e');
      return [];
    }
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

  // ========================
  // 쿠폰 시스템
  // ========================

  /// 쿠폰 유효성 검증 + 사용 처리 (원자적)
  /// 반환: {'success': bool, 'message': String, 'type': String?}
  static Future<Map<String, dynamic>> redeemCoupon({
    required String couponCode,
    required String deviceId,
  }) async {
    try {
      // 1. 쿠폰 조회
      final couponResp = await _supabase
          .from('coupons')
          .select()
          .eq('code', couponCode)
          .maybeSingle();

      if (couponResp == null) {
        return {'success': false, 'message': '존재하지 않는 쿠폰입니다'};
      }

      // 2. 활성 여부
      if (couponResp['is_active'] != true) {
        return {'success': false, 'message': '비활성화된 쿠폰입니다'};
      }

      // 3. 만료일 체크
      if (couponResp['expires_at'] != null) {
        final expiresAt = DateTime.parse(couponResp['expires_at']);
        if (DateTime.now().isAfter(expiresAt)) {
          return {'success': false, 'message': '만료된 쿠폰입니다'};
        }
      }

      // 4. 사용 횟수 체크
      final usedCount = couponResp['used_count'] ?? 0;
      final maxUses = couponResp['max_uses'] ?? 1;
      if (usedCount >= maxUses) {
        return {'success': false, 'message': '사용 횟수를 초과한 쿠폰입니다'};
      }

      // 5. 디바이스 중복 체크
      final dupResp = await _supabase
          .from('coupon_redemptions')
          .select('id')
          .eq('coupon_code', couponCode)
          .eq('device_id', deviceId)
          .maybeSingle();

      if (dupResp != null) {
        return {'success': false, 'message': '이미 사용한 쿠폰입니다'};
      }

      // 6. 사용 기록 추가
      await _supabase.from('coupon_redemptions').insert({
        'coupon_code': couponCode,
        'device_id': deviceId,
      });

      // 7. used_count 증가
      await _supabase
          .from('coupons')
          .update({'used_count': usedCount + 1})
          .eq('code', couponCode);

      return {
        'success': true,
        'message': '쿠폰이 적용되었습니다!',
        'type': couponResp['type'],
      };
    } catch (e) {
      print('쿠폰 사용 오류: $e');
      return {'success': false, 'message': '쿠폰 처리 중 오류가 발생했습니다'};
    }
  }

  /// 관리자: 쿠폰 생성
  static Future<bool> createCoupon({
    required String code,
    required String type,
    required int maxUses,
    DateTime? expiresAt,
  }) async {
    try {
      await _supabase.from('coupons').insert({
        'code': code,
        'type': type,
        'max_uses': maxUses,
        'used_count': 0,
        'is_active': true,
        'expires_at': expiresAt?.toIso8601String(),
      });
      return true;
    } catch (e) {
      print('쿠폰 생성 오류: $e');
      return false;
    }
  }

  // ========================
  // 스피또 크롤링 상태 (관리자용)
  // ========================

  /// 스피또 회차별 당첨지점 수 조회
  static Future<Map<int, Map<String, int>>> getSpeetoStoreCountsByRound() async {
    try {
      final response = await _supabase
          .from('winning_history')
          .select('round, prize_tier')
          .or('lottery_type.eq.speedlotto_2000,lottery_type.eq.speedlotto_1000,lottery_type.eq.speedlotto_500');

      final Map<int, Map<String, int>> result = {};
      for (var row in (response as List)) {
        final round = row['round'] as int;
        final tier = row['prize_tier'] as String? ?? '';
        result.putIfAbsent(round, () => {'total': 0, 'first': 0, 'second': 0});
        result[round]!['total'] = (result[round]!['total'] ?? 0) + 1;
        if (tier == '1') result[round]!['first'] = (result[round]!['first'] ?? 0) + 1;
        if (tier == '2') result[round]!['second'] = (result[round]!['second'] ?? 0) + 1;
      }
      return result;
    } catch (e) {
      print('스피또 지점 수 조회 오류: $e');
      return {};
    }
  }

  /// 스피또 당첨번호 전체 조회 (회차 목록 대용)
  static Future<List<Map<String, dynamic>>> getSpeetoRounds() async {
    try {
      // winning_history에서 스피또 회차만 distinct하게 가져옴
      final response = await _supabase
          .from('winning_history')
          .select('round')
          .or('lottery_type.eq.speedlotto_2000,lottery_type.eq.speedlotto_1000,lottery_type.eq.speedlotto_500')
          .order('round', ascending: false);

      // 중복 제거
      final Set<int> seen = {};
      final List<Map<String, dynamic>> unique = [];
      for (var row in (response as List)) {
        final round = row['round'] as int;
        if (seen.add(round)) {
          unique.add({'round': round});
        }
      }
      return unique;
    } catch (e) {
      print('스피또 회차 조회 오류: $e');
      return [];
    }
  }

  // ========================
  // 크롤링 로그 (관리자용)
  // ========================

  /// 최근 크롤링 로그 조회
  static Future<List<Map<String, dynamic>>> getCrawlLogs({int limit = 30}) async {
    try {
      final response = await _supabase
          .from('crawl_logs')
          .select()
          .order('started_at', ascending: false)
          .limit(limit);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('크롤링 로그 조회 오류: $e');
      return [];
    }
  }

  /// 최근 성공한 크롤링 로그 조회 (앱 안내문용)
  static Future<List<Map<String, dynamic>>> getRecentSuccessLogs({int hours = 24}) async {
    try {
      final since = DateTime.now().subtract(Duration(hours: hours)).toUtc().toIso8601String();
      final response = await _supabase
          .from('crawl_logs')
          .select()
          .eq('status', 'success')
          .gte('completed_at', since)
          .order('completed_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('최근 크롤링 로그 조회 오류: $e');
      return [];
    }
  }

  /// 관리자: 전체 쿠폰 목록 조회
  static Future<List<Map<String, dynamic>>> getAllCoupons() async {
    try {
      final response = await _supabase
          .from('coupons')
          .select()
          .order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('쿠폰 목록 조회 오류: $e');
      return [];
    }
  }

  /// 관리자: 쿠폰 활성/비활성 토글
  static Future<bool> toggleCouponActive(String code, bool isActive) async {
    try {
      await _supabase
          .from('coupons')
          .update({'is_active': isActive})
          .eq('code', code);
      return true;
    } catch (e) {
      print('쿠폰 상태 변경 오류: $e');
      return false;
    }
  }

  // ========================
  // 판매점 평가 (store_reviews)
  // ========================

  /// 평가 투표 (upsert) - 같은 vote_type이면 삭제(취소), 다른 vote_type이면 변경
  static Future<bool> vote({
    required String dhlotteryCode,
    required String reviewKey,
    required String deviceId,
    required String voteType, // 'up' or 'down'
  }) async {
    try {
      // 기존 투표 확인
      final existing = await _supabase
          .from('store_reviews')
          .select('id, vote_type')
          .eq('dhlottery_code', dhlotteryCode)
          .eq('review_key', reviewKey)
          .eq('device_id', deviceId)
          .maybeSingle();

      if (existing != null) {
        if (existing['vote_type'] == voteType) {
          // 같은 버튼 다시 누름 → 취소(삭제)
          await _supabase.from('store_reviews').delete().eq('id', existing['id']);
        } else {
          // 다른 버튼 → 변경
          await _supabase.from('store_reviews').update({
            'vote_type': voteType,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', existing['id']);
        }
      } else {
        // 신규 투표 (pending 상태로 저장)
        await _supabase.from('store_reviews').insert({
          'dhlottery_code': dhlotteryCode,
          'review_key': reviewKey,
          'device_id': deviceId,
          'vote_type': voteType,
          'status': 'pending',
        });
      }
      return true;
    } catch (e) {
      print('평가 투표 오류: $e');
      return false;
    }
  }

  /// 판매점 평가 집계 조회 (승인된 것만, 항목별 up/down 수)
  static Future<Map<String, Map<String, int>>> getReviewSummary(String dhlotteryCode) async {
    try {
      final response = await _supabase
          .from('store_reviews')
          .select('review_key, vote_type')
          .eq('dhlottery_code', dhlotteryCode)
          .eq('status', 'approved');

      final Map<String, Map<String, int>> result = {};
      for (var row in (response as List)) {
        final key = row['review_key'] as String;
        final type = row['vote_type'] as String;
        result.putIfAbsent(key, () => {'up': 0, 'down': 0});
        result[key]![type] = (result[key]![type] ?? 0) + 1;
      }
      return result;
    } catch (e) {
      print('평가 집계 조회 오류: $e');
      return {};
    }
  }

  /// 내 기기의 투표 현황 조회 (해당 판매점)
  static Future<Map<String, String>> getMyVotes({
    required String dhlotteryCode,
    required String deviceId,
  }) async {
    try {
      final response = await _supabase
          .from('store_reviews')
          .select('review_key, vote_type')
          .eq('dhlottery_code', dhlotteryCode)
          .eq('device_id', deviceId);

      final Map<String, String> result = {};
      for (var row in (response as List)) {
        result[row['review_key']] = row['vote_type'];
      }
      return result;
    } catch (e) {
      print('내 투표 조회 오류: $e');
      return {};
    }
  }

  // ========================
  // 판매점 신고 (store_reports)
  // ========================

  /// 신고 생성 (기기별 주 1회 제한)
  static Future<Map<String, dynamic>> createReport({
    required String dhlotteryCode,
    required String deviceId,
    required String reason,
    String? detail,
  }) async {
    try {
      // 최근 7일 내 이 기기로 신고한 적 있는지 체크
      final weekAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      final recent = await _supabase
          .from('store_reports')
          .select('id')
          .eq('device_id', deviceId)
          .gte('created_at', weekAgo)
          .limit(1);

      if ((recent as List).isNotEmpty) {
        return {'success': false, 'message': '신고는 일주일에 1회만 가능합니다.'};
      }

      await _supabase.from('store_reports').insert({
        'dhlottery_code': dhlotteryCode,
        'device_id': deviceId,
        'reason': reason,
        'detail': detail,
      });

      return {'success': true, 'message': '신고가 접수되었습니다.'};
    } catch (e) {
      print('신고 생성 오류: $e');
      return {'success': false, 'message': '신고 처리 중 오류가 발생했습니다.'};
    }
  }

  /// 관리자: 전체 신고 목록 조회
  static Future<List<Map<String, dynamic>>> getAllReports({String? status}) async {
    try {
      var query = _supabase.from('store_reports').select();
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }
      final response = await query.order('created_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('신고 목록 조회 오류: $e');
      return [];
    }
  }

  /// 관리자: 신고 상태 변경
  static Future<bool> updateReportStatus(String reportId, String status) async {
    try {
      await _supabase.from('store_reports').update({
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', reportId);
      return true;
    } catch (e) {
      print('신고 상태 변경 오류: $e');
      return false;
    }
  }

  /// 관리자: 신고 삭제
  static Future<bool> deleteReport(String reportId) async {
    try {
      await _supabase.from('store_reports').delete().eq('id', reportId);
      return true;
    } catch (e) {
      print('신고 삭제 오류: $e');
      return false;
    }
  }

  // ========================
  // 크롤링 상태 조회 (관리자용)
  // ========================

  /// 로또 회차별 당첨지점 수 조회
  static Future<Map<int, Map<String, int>>> getLottoStoreCountsByRound() async {
    try {
      final response = await _supabase
          .from('winning_history')
          .select('round, prize_tier')
          .eq('lottery_type', 'lotto');

      final Map<int, Map<String, int>> result = {};
      for (var row in (response as List)) {
        final round = row['round'] as int;
        final tier = row['prize_tier'] as String? ?? '';
        result.putIfAbsent(round, () => {'total': 0, 'first': 0, 'second': 0});
        result[round]!['total'] = (result[round]!['total'] ?? 0) + 1;
        if (tier == '1') result[round]!['first'] = (result[round]!['first'] ?? 0) + 1;
        if (tier == '2') result[round]!['second'] = (result[round]!['second'] ?? 0) + 1;
      }
      return result;
    } catch (e) {
      print('로또 지점 수 조회 오류: $e');
      return {};
    }
  }

  /// 연금 회차별 당첨지점 수 조회
  static Future<Map<int, Map<String, int>>> getPensionStoreCountsByRound() async {
    try {
      final response = await _supabase
          .from('winning_history')
          .select('round, prize_tier')
          .eq('lottery_type', 'pension');

      final Map<int, Map<String, int>> result = {};
      for (var row in (response as List)) {
        final round = row['round'] as int;
        final tier = row['prize_tier'] as String? ?? '';
        result.putIfAbsent(round, () => {'total': 0, 'first': 0, 'second': 0});
        result[round]!['total'] = (result[round]!['total'] ?? 0) + 1;
        if (tier == '1') result[round]!['first'] = (result[round]!['first'] ?? 0) + 1;
        if (tier == '2') result[round]!['second'] = (result[round]!['second'] ?? 0) + 1;
      }
      return result;
    } catch (e) {
      print('연금 지점 수 조회 오류: $e');
      return {};
    }
  }

  /// lottery_rounds 전체 조회 (로또)
  static Future<List<Map<String, dynamic>>> getAllLottoRounds() async {
    try {
      final response = await _supabase
          .from('lottery_rounds')
          .select()
          .order('round', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('lottery_rounds 조회 오류: $e');
      return [];
    }
  }

  /// pension_rounds 전체 조회
  static Future<List<Map<String, dynamic>>> getAllPensionRounds() async {
    try {
      final response = await _supabase
          .from('pension_rounds')
          .select()
          .order('round', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('pension_rounds 조회 오류: $e');
      return [];
    }
  }

  /// 로또 회차 삭제 (당첨번호 + 회차 + 지점 데이터)
  static Future<bool> deleteLottoRound(int round) async {
    try {
      await _supabase.from('winning_history').delete()
          .eq('round', round).eq('lottery_type', 'lotto');
      await _supabase.from('lotto_winning_numbers').delete().eq('round', round);
      await _supabase.from('lottery_rounds').delete().eq('round', round);
      return true;
    } catch (e) {
      print('로또 회차 삭제 오류: $e');
      return false;
    }
  }

  /// 연금 회차 삭제 (당첨번호 + 회차 + 지점 데이터)
  static Future<bool> deletePensionRound(int round) async {
    try {
      await _supabase.from('winning_history').delete()
          .eq('round', round).eq('lottery_type', 'pension');
      await _supabase.from('pension_winning_numbers').delete().eq('round', round);
      await _supabase.from('pension_rounds').delete().eq('round', round);
      return true;
    } catch (e) {
      print('연금 회차 삭제 오류: $e');
      return false;
    }
  }

  // ========================
  // 평가 승인 관리 (관리자용)
  // ========================

  /// 지점별 pending 평가 수 조회
  static Future<List<Map<String, dynamic>>> getPendingReviewStats() async {
    try {
      final response = await _supabase
          .from('store_reviews')
          .select('dhlottery_code, review_key, vote_type')
          .eq('status', 'pending');

      // 지점별 집계
      final Map<String, Map<String, int>> stats = {};
      for (var row in (response as List)) {
        final code = row['dhlottery_code'] as String;
        stats.putIfAbsent(code, () => {'pending': 0, 'up': 0, 'down': 0});
        stats[code]!['pending'] = (stats[code]!['pending'] ?? 0) + 1;
        final type = row['vote_type'] as String;
        stats[code]![type] = (stats[code]![type] ?? 0) + 1;
      }

      // 지점 이름 조회
      if (stats.isEmpty) return [];
      final codes = stats.keys.toList();
      final stores = await _supabase
          .from('lottery_stores')
          .select('dhlottery_code, store_name, address')
          .inFilter('dhlottery_code', codes);

      final Map<String, Map<String, dynamic>> storeMap = {};
      for (var s in (stores as List)) {
        storeMap[s['dhlottery_code']] = s;
      }

      return stats.entries.map((e) {
        final store = storeMap[e.key];
        return {
          'dhlottery_code': e.key,
          'store_name': store?['store_name'] ?? e.key,
          'address': store?['address'] ?? '',
          'pending_count': e.value['pending'] ?? 0,
          'up_count': e.value['up'] ?? 0,
          'down_count': e.value['down'] ?? 0,
        };
      }).toList()
        ..sort((a, b) => (b['pending_count'] as int).compareTo(a['pending_count'] as int));
    } catch (e) {
      print('대기 평가 통계 오류: $e');
      return [];
    }
  }

  /// 특정 지점의 pending 평가 일괄 승인
  static Future<int> approveStoreReviews(String dhlotteryCode) async {
    try {
      final response = await _supabase
          .from('store_reviews')
          .update({'status': 'approved'})
          .eq('dhlottery_code', dhlotteryCode)
          .eq('status', 'pending')
          .select();
      return (response as List).length;
    } catch (e) {
      print('지점 평가 승인 오류: $e');
      return 0;
    }
  }

  /// 전체 pending 평가 일괄 승인 (보류 지점 제외)
  static Future<int> approveAllPendingReviews() async {
    try {
      // 보류 지점 목록
      final holds = await _supabase.from('review_holds').select('dhlottery_code');
      final holdCodes = (holds as List).map((h) => h['dhlottery_code'] as String).toSet();

      // pending 평가 조회
      final pending = await _supabase
          .from('store_reviews')
          .select('id, dhlottery_code')
          .eq('status', 'pending');

      // 보류 지점 제외한 ID 목록
      final idsToApprove = (pending as List)
          .where((r) => !holdCodes.contains(r['dhlottery_code']))
          .map((r) => r['id'])
          .toList();

      if (idsToApprove.isEmpty) return 0;

      // 배치 승인
      int approved = 0;
      for (int i = 0; i < idsToApprove.length; i += 100) {
        final batch = idsToApprove.sublist(i, i + 100 > idsToApprove.length ? idsToApprove.length : i + 100);
        final resp = await _supabase
            .from('store_reviews')
            .update({'status': 'approved'})
            .inFilter('id', batch)
            .select();
        approved += (resp as List).length;
      }
      return approved;
    } catch (e) {
      print('전체 평가 승인 오류: $e');
      return 0;
    }
  }

  /// 보류 목록 조회
  static Future<List<Map<String, dynamic>>> getReviewHolds() async {
    try {
      final response = await _supabase
          .from('review_holds')
          .select()
          .order('held_at', ascending: false);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print('보류 목록 조회 오류: $e');
      return [];
    }
  }

  /// 보류 추가
  static Future<bool> addReviewHold(String dhlotteryCode, {String? reason}) async {
    try {
      await _supabase.from('review_holds').upsert({
        'dhlottery_code': dhlotteryCode,
        'held_at': DateTime.now().toIso8601String(),
        'reason': reason,
      });
      return true;
    } catch (e) {
      print('보류 추가 오류: $e');
      return false;
    }
  }

  /// 보류 해제
  static Future<bool> removeReviewHold(String dhlotteryCode) async {
    try {
      await _supabase.from('review_holds').delete().eq('dhlottery_code', dhlotteryCode);
      return true;
    } catch (e) {
      print('보류 해제 오류: $e');
      return false;
    }
  }

  /// 특정 지점의 pending 평가 거절 (삭제)
  static Future<int> rejectStoreReviews(String dhlotteryCode) async {
    try {
      final response = await _supabase
          .from('store_reviews')
          .delete()
          .eq('dhlottery_code', dhlotteryCode)
          .eq('status', 'pending')
          .select();
      return (response as List).length;
    } catch (e) {
      print('지점 평가 거절 오류: $e');
      return 0;
    }
  }
}
