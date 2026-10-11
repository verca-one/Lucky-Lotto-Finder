// 환경 데이터 인터페이스 (Phase 5-14)
// 실제 데이터 소스 없음. 향후 연동을 위한 구조만 정의.

// 환경 특성값 (실제 데이터 연동 시 채울 필드)
class EnvironmentalFeature {
  final DateTime timestamp;
  final int? moonPhase;          // 월령 (0~29일)
  final String? weatherPattern;  // 'clear' | 'rainy' | 'cloudy' | 'snow'
  final double? temperature;     // 섭씨
  final bool? isHoliday;         // 공휴일 여부
  final String? economicSignal;  // 'bullish' | 'bearish' | 'neutral'

  const EnvironmentalFeature({
    required this.timestamp,
    this.moonPhase,
    this.weatherPattern,
    this.temperature,
    this.isHoliday,
    this.economicSignal,
  });

  bool get hasAnyData =>
      moonPhase != null || weatherPattern != null ||
      temperature != null || isHoliday != null || economicSignal != null;
}

// 환경 데이터 제공자 인터페이스
abstract class EnvironmentalDataProvider {
  Future<EnvironmentalFeature?> getForRound(int round, DateTime drawDate);
}

// 미구현 스텁 — 실제 데이터 소스 연동 전까지 null 반환
class StubEnvironmentalProvider implements EnvironmentalDataProvider {
  const StubEnvironmentalProvider();

  @override
  Future<EnvironmentalFeature?> getForRound(int round, DateTime drawDate) async {
    return null;
  }
}

// 싱글턴 레지스트리
class EnvironmentalRegistry {
  static EnvironmentalDataProvider _provider = const StubEnvironmentalProvider();

  static EnvironmentalDataProvider get provider => _provider;

  static void setProvider(EnvironmentalDataProvider p) => _provider = p;
}
