import 'supabase_service.dart';

/// 판매점 분석 배지 정보
class StoreBadge {
  final String label;
  final StoreBadgeType type;

  StoreBadge(this.label, this.type);
}

enum StoreBadgeType {
  hot,        // 이번주 유력 (빨간색 강조)
  matjip,     // 맛집 (골드/노란)
  first,      // 1등 관련 (빨간)
  second,     // 2등 관련 (주황)
  regional,   // 지역 최다 (보라)
  streak,     // 연속/최근 (파란)
  rank,       // 지역 등수 (초록)
  pattern,    // 평균 주기 (회색)
  myeongdang, // 복권명당 TOP (금색)
}

class BadgeService {
  // 세션 캐시: dhlottery_code → badges
  // DB에 미리 계산된 결과를 읽어 저장. 화면 진입 시 필요한 코드만 추가.
  static final Map<String, List<StoreBadge>> _cache = {};

  // 배지 로딩 실패 여부 (홈 화면 배너용)
  static bool _loadFailed = false;
  static bool get loadFailed => _loadFailed;

  /// 여러 판매점의 배지를 DB에서 한 번에 로드하여 캐시에 저장.
  /// 이미 캐시된 코드는 건너뛰어 중복 요청을 방지.
  static Future<void> loadBadges(
    List<String> dhlotteryCodes, {
    String? lotteryType,
  }) async {
    _loadFailed = false;

    // 캐시에 없는 코드만 요청
    final missing = dhlotteryCodes.where((c) => !_cache.containsKey(c)).toList();
    if (missing.isEmpty) return;

    try {
      final rawBadges = await SupabaseService.getStoreBadges(
        missing,
        lotteryType: lotteryType,
      );

      // 먼저 missing 코드를 빈 리스트로 초기화 (배지 없음도 캐시)
      for (final code in missing) {
        _cache.putIfAbsent(code, () => []);
      }

      for (var row in rawBadges) {
        final code = row['dhlottery_code'] as String;
        final badgeType = _parseBadgeType(row['badge_type'] as String);
        final label = row['badge_label'] as String;

        _cache.putIfAbsent(code, () => []);
        final exists = _cache[code]!.any((b) => b.label == label);
        if (!exists) {
          _cache[code]!.add(StoreBadge(label, badgeType));
        }
      }

      // priority 기준 정렬
      for (final entry in _cache.entries) {
        entry.value.sort((a, b) => _typeOrder(a.type).compareTo(_typeOrder(b.type)));
      }
    } catch (_) {
      _loadFailed = true;
    }
  }

  /// 특정 판매점 1개의 배지를 보장 로드 (캐시 미스 시 DB 조회).
  /// store detail popup 등에서 단건 호출용.
  static Future<List<StoreBadge>> loadBadgesForStore(
    String dhlotteryCode, {
    String? lotteryType,
  }) async {
    if (_cache.containsKey(dhlotteryCode)) return _cache[dhlotteryCode]!;
    await loadBadges([dhlotteryCode], lotteryType: lotteryType);
    return _cache[dhlotteryCode] ?? [];
  }

  /// 특정 판매점의 배지 목록 반환 (동기 — 이미 캐시된 경우만 유효).
  static List<StoreBadge> getBadges(String dhlotteryCode) {
    return _cache[dhlotteryCode] ?? [];
  }

  /// 캐시 초기화 (앱 재시작/로그아웃 시)
  static void clearCache() {
    _cache.clear();
    _loadFailed = false;
  }

  static StoreBadgeType _parseBadgeType(String type) {
    switch (type) {
      case 'hot':        return StoreBadgeType.hot;
      case 'matjip':     return StoreBadgeType.matjip;
      case 'first':      return StoreBadgeType.first;
      case 'second':     return StoreBadgeType.second;
      case 'regional':   return StoreBadgeType.regional;
      case 'streak':     return StoreBadgeType.streak;
      case 'rank':       return StoreBadgeType.rank;
      case 'pattern':    return StoreBadgeType.pattern;
      case 'myeongdang': return StoreBadgeType.myeongdang;
      default:           return StoreBadgeType.pattern;
    }
  }

  static int _typeOrder(StoreBadgeType type) {
    switch (type) {
      case StoreBadgeType.hot:        return 0;
      case StoreBadgeType.myeongdang: return 1;
      case StoreBadgeType.matjip:     return 2;
      case StoreBadgeType.first:      return 3;
      case StoreBadgeType.second:     return 4;
      case StoreBadgeType.streak:     return 5;
      case StoreBadgeType.regional:   return 6;
      case StoreBadgeType.rank:       return 7;
      case StoreBadgeType.pattern:    return 8;
    }
  }
}
