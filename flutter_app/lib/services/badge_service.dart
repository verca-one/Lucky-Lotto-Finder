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
  // 캐시: dhlottery_code → badges
  static Map<String, List<StoreBadge>>? _badgeCache;

  // 배지 로딩 실패 여부
  static bool _loadFailed = false;
  static bool get loadFailed => _loadFailed;

  /// store_badges 테이블에서 배지 데이터 로드
  static Future<void> loadBadges(List<String> dhlotteryCodes, {String? lotteryType}) async {
    _badgeCache ??= {};
    _loadFailed = false;

    if (dhlotteryCodes.isEmpty) return;

    try {
      final rawBadges = await SupabaseService.getStoreBadges(
        dhlotteryCodes,
        lotteryType: lotteryType,
      );

      for (var row in rawBadges) {
        final code = row['dhlottery_code'] as String;
        final badgeType = _parseBadgeType(row['badge_type'] as String);
        final label = row['badge_label'] as String;

        _badgeCache!.putIfAbsent(code, () => []);
        // 중복 방지
        final exists = _badgeCache![code]!.any((b) => b.label == label);
        if (!exists) {
          _badgeCache![code]!.add(StoreBadge(label, badgeType));
        }
      }

      // priority 기준 정렬
      for (var entry in _badgeCache!.entries) {
        // hot → first → second → streak → regional → rank → pattern 순
        entry.value.sort((a, b) => _typeOrder(a.type).compareTo(_typeOrder(b.type)));
      }
    } catch (_) {
      _loadFailed = true;
    }
  }

  /// 특정 판매점의 배지 목록 반환
  static List<StoreBadge> getBadges(String dhlotteryCode) {
    return _badgeCache?[dhlotteryCode] ?? [];
  }

  /// 캐시 초기화
  static void clearCache() {
    _badgeCache = null;
  }

  static StoreBadgeType _parseBadgeType(String type) {
    switch (type) {
      case 'hot': return StoreBadgeType.hot;
      case 'matjip': return StoreBadgeType.matjip;
      case 'first': return StoreBadgeType.first;
      case 'second': return StoreBadgeType.second;
      case 'regional': return StoreBadgeType.regional;
      case 'streak': return StoreBadgeType.streak;
      case 'rank': return StoreBadgeType.rank;
      case 'pattern': return StoreBadgeType.pattern;
      case 'myeongdang': return StoreBadgeType.myeongdang;
      default: return StoreBadgeType.pattern;
    }
  }

  static int _typeOrder(StoreBadgeType type) {
    switch (type) {
      case StoreBadgeType.hot: return 0;
      case StoreBadgeType.myeongdang: return 1;
      case StoreBadgeType.matjip: return 2;
      case StoreBadgeType.first: return 3;
      case StoreBadgeType.second: return 4;
      case StoreBadgeType.streak: return 5;
      case StoreBadgeType.regional: return 6;
      case StoreBadgeType.rank: return 7;
      case StoreBadgeType.pattern: return 8;
    }
  }
}
