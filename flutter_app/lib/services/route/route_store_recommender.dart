// 경로 기반 추천 — 핵심 수학/점수 모듈 (관리자 전용 연구 기능)
//
// 이 파일은 순수 Dart (Supabase·Flutter 의존 없음) 로 작성되어 단위 테스트가 가능하다.
// DB 조회는 route_store_repository.dart 가 담당하며, 이 모듈은 조회된 데이터를
// 읽기 전용으로만 사용한다. 기존 Number/Store/Joint/MND 엔진 로직은 변경하지 않는다.
//
// ── 단위 규약 ─────────────────────────────────────────────────────────────
//   * 거리: 내부 계산은 미터(M), 사용자 입력 반경은 킬로미터(Km) → 함수명에 단위 표기.
//   * 시간: 내부 계산은 초(S), 사용자 입력 최대 우회는 분(Min).
//   * 좌표: latlong2 LatLng(lat, lng). OSRM 변환은 routing_service.dart 에서만 수행.
//
// ── 핵심 원칙 ─────────────────────────────────────────────────────────────
//   * 우회시간 ΔT / 우회거리 ΔL 은 반드시 RouteProvider(S→P→D) 실제 경로값으로 계산한다.
//     직선거리로 우회시간을 추정하지 않는다. API 실패 시 "우회시간 미확인(API 실패)".
//   * 영업시간 데이터는 DB에 없다 → 모든 판매점 "영업 여부 확인 필요" (추정 금지).
//   * 점수는 당첨확률이 아니다 ([kScoreDisclaimer]).
//   * 결정적(deterministic): 같은 입력 → 같은 순위. 모든 정렬의 최종 tie-break 는 판매점 코드.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'routing_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// 상수 · 문구
// ═══════════════════════════════════════════════════════════════════════

const String kScoreDisclaimer =
    '점수는 당첨확률이 아닙니다. 접근성·과거 이력·연구 상태를 요약한 참고 지표입니다.';
const String kNoVerifiedEngineHeader = '검증된 당첨확률 우위 없음 — 우회시간·이력 중심';
const String kHistoryModeNote = '과거 이력 중심이며 당첨확률 우위 아님';
const String kOpenStatusUnknown = '영업 여부 확인 필요 (영업시간 데이터 없음)';
const String kDetourUnverified = '우회시간 미확인(API 실패)';
const String kEtaNote = '교통 미반영 추정';
const String kNoEngineResult = '엔진 분석 결과 없음(데이터 부족)';

/// 로또 판매 마감: 토요일 20:00
const int kLottoSalesCloseWeekday = DateTime.saturday;
const int kLottoSalesCloseHour = 20;

/// 2차 후보 상한 (OSRM 호출 횟수 = 후보 수 → fair-use 보호)
const int kMaxDetourCandidates = 12;

const double kEarthRadiusM = 6371008.8;

// ═══════════════════════════════════════════════════════════════════════
// 입력 모델
// ═══════════════════════════════════════════════════════════════════════

enum RouteRecommendMode { minDetour, history, engine }

extension RouteRecommendModeLabel on RouteRecommendMode {
  String get label => switch (this) {
        RouteRecommendMode.minDetour => '최소 우회',
        RouteRecommendMode.history => '이력 중심',
        RouteRecommendMode.engine => '엔진 종합',
      };
}

class RouteRecommendOptions {
  final double radiusKm; // 1 / 3 / 5
  final int maxDetourMin; // 5 / 10 / 15 / 30
  final RouteRecommendMode mode;
  final bool preferOpenCheck;
  final DateTime departureTime;
  final int maxCandidates;

  /// 도로 옵션: 무료도로만(기본) / 전체 도로. 무료도로 모드에서 유료구간 포함 후보는 후순위.
  final RoadOption roadOption;

  const RouteRecommendOptions({
    required this.radiusKm,
    required this.maxDetourMin,
    required this.mode,
    required this.departureTime,
    this.preferOpenCheck = false,
    this.maxCandidates = kMaxDetourCandidates,
    this.roadOption = RoadOption.freeOnly,
  });

  double get radiusM => radiusKm * 1000.0;
  double get maxDetourS => maxDetourMin * 60.0;
}

/// lottery_stores 에서 읽어온 판매점 (읽기 전용 스냅샷)
class RouteStoreCandidate {
  final String code; // dhlottery_code
  final String name;
  final String address;
  final String region;
  final LatLng point;
  final int firstCount;
  final int secondCount;
  final int? latestFirstWin;
  final int? latestSecondWin;

  /// 기본 경로 polyline 까지의 최소 거리(m). filterByRoute 이후 채워짐.
  final double distToRouteM;

  const RouteStoreCandidate({
    required this.code,
    required this.name,
    required this.address,
    required this.region,
    required this.point,
    this.firstCount = 0,
    this.secondCount = 0,
    this.latestFirstWin,
    this.latestSecondWin,
    this.distToRouteM = double.infinity,
  });

  RouteStoreCandidate withDistToRoute(double m) => RouteStoreCandidate(
        code: code,
        name: name,
        address: address,
        region: region,
        point: point,
        firstCount: firstCount,
        secondCount: secondCount,
        latestFirstWin: latestFirstWin,
        latestSecondWin: latestSecondWin,
        distToRouteM: m,
      );

  /// 1차 후보 선정에 쓰는 단순 이력 점수 (lottery_stores 카운트 기준)
  double get rawHistoryScore => firstCount * 1.0 + secondCount * 0.3;
}

// ── 엔진 연결 데이터 (판매점 코드별, 해당 코드의 행만) ────────────────────

class StoreAnomalyLite {
  final int totalWins;
  final double expectedWins;
  final double poissonZ;
  final double bayesianRate;
  final double bayesianLower;
  final double bayesianUpper;
  final String anomalyStatus;
  final int trainingEndRound;
  final String modelVersion;
  const StoreAnomalyLite({
    required this.totalWins,
    required this.expectedWins,
    required this.poissonZ,
    required this.bayesianRate,
    required this.bayesianLower,
    required this.bayesianUpper,
    required this.anomalyStatus,
    required this.trainingEndRound,
    this.modelVersion = '1.0',
  });
}

class StoreHypothesisLite {
  final String hypothesisId;
  final String hypothesisType; // persistence | transition | emerging
  final String status;
  final String gateStatus; // pass | fail | not_evaluated
  final int wfRounds;
  final double? wfSuccessRate;
  final double? wfBaselineRate;
  final double? wfImprovement;
  final bool livePredictionActive;
  final int trainingEndRound;
  const StoreHypothesisLite({
    required this.hypothesisId,
    required this.hypothesisType,
    required this.status,
    required this.gateStatus,
    this.wfRounds = 0,
    this.wfSuccessRate,
    this.wfBaselineRate,
    this.wfImprovement,
    this.livePredictionActive = false,
    this.trainingEndRound = 0,
  });

  bool get isVerified => gateStatus == 'pass';
}

class StoreChangePointLite {
  final int changePointRound;
  final double preRate;
  final double postRate;
  final int trainingEndRound;
  const StoreChangePointLite({
    required this.changePointRound,
    required this.preRate,
    required this.postRate,
    required this.trainingEndRound,
  });
}

/// 판매점 하나에 대한 엔진/이력 근거 묶음.
class StoreEngineInsight {
  /// winning_history 기준 1등/2등 수 (lottery_type='lotto')
  final int historyFirst;
  final int historySecond;

  /// 구매방식 분포 (자동/수동/반자동/미상 → 건수)
  final Map<String, int> purchaseMethods;
  final StoreAnomalyLite? anomaly;
  final List<StoreHypothesisLite> hypotheses;
  final List<StoreChangePointLite> changePoints;

  /// rpa_store_predictions 의 candidate_store_codes 에 포함된 경우 (테이블 없으면 null)
  final int? rpaCandidateTargetRound;

  const StoreEngineInsight({
    this.historyFirst = 0,
    this.historySecond = 0,
    this.purchaseMethods = const {},
    this.anomaly,
    this.hypotheses = const [],
    this.changePoints = const [],
    this.rpaCandidateTargetRound,
  });

  static const empty = StoreEngineInsight();

  bool get hasAnyAnalysis =>
      anomaly != null || hypotheses.isNotEmpty || changePoints.isNotEmpty;

  int get verifiedHypothesisCount => hypotheses.where((h) => h.isVerified).length;
  int get researchingHypothesisCount =>
      hypotheses.where((h) => !h.isVerified).length;

  /// 데이터 기준 회차 (가장 최신 training_end_round)
  int? get dataRound {
    final rounds = <int>[
      if (anomaly != null) anomaly!.trainingEndRound,
      ...hypotheses.map((h) => h.trainingEndRound),
      ...changePoints.map((c) => c.trainingEndRound),
    ].where((r) => r > 0);
    if (rounds.isEmpty) return null;
    return rounds.reduce(math.max);
  }

  /// 데이터 품질 0~1: 이상치 분석 0.5 + 가설 0.3 + 변화점 0.2
  double get qualityScore =>
      (anomaly != null ? 0.5 : 0.0) +
      (hypotheses.isNotEmpty ? 0.3 : 0.0) +
      (changePoints.isNotEmpty ? 0.2 : 0.0);
}

// ═══════════════════════════════════════════════════════════════════════
// 출력 모델
// ═══════════════════════════════════════════════════════════════════════

class ScoreBreakdown {
  final RouteRecommendMode mode;

  /// 구성요소 값 (예: access, history, quality, engine_bonus, delta_t_min)
  final Map<String, double> components;

  /// 가중치 (예: access 0.5 ...)
  final Map<String, double> weights;
  final double total;
  const ScoreBreakdown({
    required this.mode,
    required this.components,
    required this.weights,
    required this.total,
  });
}

/// 우회 검증 상태 그룹 (정렬 1차 키)
enum DetourGroup { withinLimit, overLimit, unverified }

class RouteStoreRecommendation {
  final int rank;
  final RouteStoreCandidate store;
  final StoreEngineInsight insight;

  /// S→P→D 경유 경로 (API 실패 시 null)
  final RouteResult? viaRoute;
  final double? deltaTimeS;
  final double? deltaDistM;
  final DetourGroup detourGroup;
  final DateTime? eta;
  final bool etaAfterSalesClose;
  final ScoreBreakdown score;
  final List<String> reasons;

  /// 항상 [kOpenStatusUnknown] — 영업시간 데이터 없음
  final String openStatus;

  /// 평가 시 도로 옵션
  final RoadOption roadOption;

  const RouteStoreRecommendation({
    required this.rank,
    required this.store,
    required this.insight,
    required this.viaRoute,
    required this.deltaTimeS,
    required this.deltaDistM,
    required this.detourGroup,
    required this.eta,
    required this.etaAfterSalesClose,
    required this.score,
    required this.reasons,
    this.openStatus = kOpenStatusUnknown,
    this.roadOption = RoadOption.freeOnly,
  });

  bool get detourVerified => deltaTimeS != null && deltaDistM != null;
  double? get deltaTimeMin => deltaTimeS == null ? null : deltaTimeS! / 60.0;
  double? get deltaDistKm => deltaDistM == null ? null : deltaDistM! / 1000.0;

  /// 통행료 회피가 실제로 적용된 요청인지 (무료도로 모드 + Valhalla 응답). OSRM 대체는 아니오.
  bool get tollAvoidApplied =>
      viaRoute != null && viaRoute!.tollAvoidRequested && !viaRoute!.fallbackUsed;

  /// 경유 경로 통행료 검증 상태 (경로 조회 실패 시 null)
  TollCheck? get tollCheck => viaRoute?.tollCheck;

  /// 무료도로 모드인데 경유 경로가 has_toll=true 로 검증됨 → 후순위
  bool get tollDemoted =>
      roadOption == RoadOption.freeOnly &&
      viaRoute != null &&
      viaRoute!.tollCheck == TollCheck.tollIncluded;

  /// 정렬 1차 키: 0 한도 내 / 1 한도 초과 / 2 유료구간 포함(무료 모드) / 3 우회 미확인
  int get sortGroup {
    if (detourGroup == DetourGroup.unverified) return 3;
    if (tollDemoted) return 2;
    return detourGroup.index;
  }

  /// 화면 표시용 통행료 문구
  String get tollApplyLabel => '통행료 회피 적용: ${tollAvoidApplied ? '예' : '아니오'}'
      '${viaRoute?.fallbackUsed == true ? ' ($kTollFallbackNote)' : ''}';

  String get tollCheckLabel => viaRoute == null
      ? '검증: 경로 조회 실패'
      : '검증: ${viaRoute!.tollCheck.label(fallback: viaRoute!.fallbackUsed, avoidRequested: roadOption.avoidTolls)}';

  RouteStoreRecommendation copyWithRank(int r) => RouteStoreRecommendation(
        rank: r,
        store: store,
        insight: insight,
        viaRoute: viaRoute,
        deltaTimeS: deltaTimeS,
        deltaDistM: deltaDistM,
        detourGroup: detourGroup,
        eta: eta,
        etaAfterSalesClose: etaAfterSalesClose,
        score: score,
        reasons: reasons,
        openStatus: openStatus,
        roadOption: roadOption,
      );
}

class RouteRecommendResult {
  final RouteResult baseRoute;
  final RouteRecommendOptions options;
  final List<RouteStoreRecommendation> items;

  /// 반경 내 판매점 수 (2차 필터 통과)
  final int candidatesInRadius;

  /// 우회 경로 조회를 수행한 후보 수
  final int candidatesEvaluated;

  /// 검증 통과(gate pass) 가설 보유 판매점 수
  final int verifiedEngineStores;
  final String headerNote;
  final String disclaimer;

  const RouteRecommendResult({
    required this.baseRoute,
    required this.options,
    required this.items,
    required this.candidatesInRadius,
    required this.candidatesEvaluated,
    required this.verifiedEngineStores,
    required this.headerNote,
    this.disclaimer = kScoreDisclaimer,
  });

  bool get isEmpty => items.isEmpty;

  /// 기본 경로 통행료 경고 (무료도로 모드에서만 의미)
  ///  * has_toll=true → [kTollNotConfirmedWarning]
  ///  * OSRM 대체 → [kTollFallbackNote]
  ///  * 그 외 null
  String? get baseRouteTollWarning {
    if (options.roadOption != RoadOption.freeOnly) return null;
    if (baseRoute.fallbackUsed) return kTollFallbackNote;
    if (!baseRoute.tollVerified) return '통행료 검증 불가(응답에 has_toll 없음)';
    if (baseRoute.hasToll == true) return kTollNotConfirmedWarning;
    return null;
  }

  /// 유료구간 포함으로 후순위가 된 후보 수
  int get tollDemotedCount => items.where((i) => i.tollDemoted).length;
}

// ═══════════════════════════════════════════════════════════════════════
// 기하 유틸 (Haversine · 선분 투영 · bounding box)
// ═══════════════════════════════════════════════════════════════════════

class GeoBox {
  final double minLat, maxLat, minLng, maxLng;
  const GeoBox({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  bool contains(LatLng p) =>
      p.latitude >= minLat &&
      p.latitude <= maxLat &&
      p.longitude >= minLng &&
      p.longitude <= maxLng;

  @override
  String toString() => 'GeoBox(lat $minLat..$maxLat, lng $minLng..$maxLng)';
}

class RouteGeo {
  RouteGeo._();

  static double _rad(double deg) => deg * math.pi / 180.0;

  /// 두 점 사이 대원거리 (미터)
  static double haversineM(LatLng a, LatLng b) {
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final la1 = _rad(a.latitude);
    final la2 = _rad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * kEarthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
  }

  /// 대한민국 범위 검사: 위도 33~39, 경도 124~132. null/0/범위 밖 제외.
  static bool isValidKoreaCoord(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat == 0 || lng == 0) return false;
    if (lat.isNaN || lng.isNaN) return false;
    return lat >= 33 && lat <= 39 && lng >= 124 && lng <= 132;
  }

  /// 점 [p] 와 선분 [a]-[b] 사이 최소 거리(미터).
  /// p 를 원점으로 한 국소 등거리 투영(equirectangular) 에서 선분 투영 매개변수 t 를 구해
  /// 최근접점을 복원한 뒤 Haversine 으로 거리를 계산한다 (수십 km 규모에서 충분히 정확).
  static double pointToSegmentDistanceM(LatLng p, LatLng a, LatLng b) {
    final nearest = nearestPointOnSegment(p, a, b);
    return haversineM(p, nearest);
  }

  static LatLng nearestPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final cosLat = math.cos(_rad(p.latitude));
    // 국소 평면 좌표 (미터)
    double x(LatLng q) => _rad(q.longitude - p.longitude) * cosLat * kEarthRadiusM;
    double y(LatLng q) => _rad(q.latitude - p.latitude) * kEarthRadiusM;
    final ax = x(a), ay = y(a), bx = x(b), by = y(b);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    double t;
    if (len2 <= 0) {
      t = 0;
    } else {
      // p 는 원점 (0,0)
      t = ((0 - ax) * dx + (0 - ay) * dy) / len2;
      t = t.clamp(0.0, 1.0);
    }
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  /// 점과 polyline 사이 최소 거리(미터). polyline 이 1점이면 그 점까지 거리.
  static double minDistanceToPolylineM(LatLng p, List<LatLng> polyline) {
    if (polyline.isEmpty) return double.infinity;
    if (polyline.length == 1) return haversineM(p, polyline.first);
    var best = double.infinity;
    for (var i = 0; i < polyline.length - 1; i++) {
      final d = pointToSegmentDistanceM(p, polyline[i], polyline[i + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  /// polyline bounding box + 여유 [marginKm].
  static GeoBox boundingBox(List<LatLng> polyline, double marginKm) {
    if (polyline.isEmpty) {
      return const GeoBox(minLat: 0, maxLat: 0, minLng: 0, maxLng: 0);
    }
    var minLat = polyline.first.latitude, maxLat = polyline.first.latitude;
    var minLng = polyline.first.longitude, maxLng = polyline.first.longitude;
    for (final p in polyline) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final midLat = (minLat + maxLat) / 2;
    final dLat = marginKm / 111.32;
    final cosMid = math.cos(_rad(midLat)).abs();
    final dLng = marginKm / (111.32 * (cosMid < 1e-6 ? 1e-6 : cosMid));
    return GeoBox(
      minLat: minLat - dLat,
      maxLat: maxLat + dLat,
      minLng: minLng - dLng,
      maxLng: maxLng + dLng,
    );
  }

  /// 장거리 polyline 의 2차 필터 비용을 줄이기 위한 균등 다운샘플 (최대 [maxPoints]).
  /// 반경 판정 오차를 피하려면 호출측이 반경에 여유(예: +100m)를 두거나
  /// 원본 polyline 을 그대로 쓴다. 본 모듈은 기본적으로 원본을 사용한다.
  static List<LatLng> downsample(List<LatLng> polyline, int maxPoints) {
    if (polyline.length <= maxPoints || maxPoints < 2) return polyline;
    final step = (polyline.length - 1) / (maxPoints - 1);
    final out = <LatLng>[];
    for (var i = 0; i < maxPoints; i++) {
      out.add(polyline[(i * step).round().clamp(0, polyline.length - 1)]);
    }
    return out;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 추천기
// ═══════════════════════════════════════════════════════════════════════

class RouteStoreRecommender {
  final RouteProvider provider;

  /// 후보별 우회 경로 조회 사이 간격 (데모 서버 fair-use 보호)
  final Duration perRequestDelay;

  const RouteStoreRecommender(this.provider,
      {this.perRequestDelay = const Duration(milliseconds: 250)});

  // ── 1차: bounding box, 2차: polyline 최소거리 ≤ 반경 ───────────────────

  /// [stores] 중 기본 경로에서 [radiusKm] 이내인 판매점을 distToRouteM 과 함께 반환.
  /// 결과는 (거리 오름차순, 코드) 로 정렬된다.
  static List<RouteStoreCandidate> filterByRoute(
    List<RouteStoreCandidate> stores,
    List<LatLng> polyline,
    double radiusKm,
  ) {
    if (polyline.isEmpty) return const [];
    final box = RouteGeo.boundingBox(polyline, radiusKm);
    final radiusM = radiusKm * 1000.0;
    final out = <RouteStoreCandidate>[];
    for (final s in stores) {
      if (!RouteGeo.isValidKoreaCoord(s.point.latitude, s.point.longitude)) {
        continue;
      }
      if (!box.contains(s.point)) continue; // 1차
      final d = RouteGeo.minDistanceToPolylineM(s.point, polyline); // 2차
      if (d <= radiusM) out.add(s.withDistToRoute(d));
    }
    out.sort((a, b) {
      final c = a.distToRouteM.compareTo(b.distToRouteM);
      return c != 0 ? c : a.code.compareTo(b.code);
    });
    return out;
  }

  /// 상위 후보 선정: 경로까지 가까운 순 절반 + 이력 상위 절반 혼합 (중복 제거, 최대 [max]).
  /// 결정적: 동률은 코드순.
  static List<RouteStoreCandidate> selectTopCandidates(
    List<RouteStoreCandidate> inRadius, {
    int max = kMaxDetourCandidates,
  }) {
    if (inRadius.length <= max) {
      final copy = List<RouteStoreCandidate>.from(inRadius);
      copy.sort((a, b) => _cmpDistThenCode(a, b));
      return copy;
    }
    final byDist = List<RouteStoreCandidate>.from(inRadius)
      ..sort(_cmpDistThenCode);
    final byHist = List<RouteStoreCandidate>.from(inRadius)
      ..sort((a, b) {
        final c = b.rawHistoryScore.compareTo(a.rawHistoryScore);
        return c != 0 ? c : _cmpDistThenCode(a, b);
      });
    final halfDist = (max / 2).ceil();
    final picked = <String>{};
    final out = <RouteStoreCandidate>[];
    for (final s in byDist) {
      if (out.length >= halfDist) break;
      if (picked.add(s.code)) out.add(s);
    }
    for (final s in byHist) {
      if (out.length >= max) break;
      if (picked.add(s.code)) out.add(s);
    }
    // 이력 상위가 거리 상위와 겹쳐 자리가 남으면 거리순으로 채움
    for (final s in byDist) {
      if (out.length >= max) break;
      if (picked.add(s.code)) out.add(s);
    }
    out.sort(_cmpDistThenCode);
    return out;
  }

  static int _cmpDistThenCode(RouteStoreCandidate a, RouteStoreCandidate b) {
    final c = a.distToRouteM.compareTo(b.distToRouteM);
    return c != 0 ? c : a.code.compareTo(b.code);
  }

  // ── ETA · 판매 마감 ─────────────────────────────────────────────────────

  static DateTime computeEta(DateTime departure, double durationS) =>
      departure.add(Duration(seconds: durationS.round()));

  /// 토요일 20:00 이후 도착이면 true (로또 판매 마감 경고)
  static bool isAfterLottoSalesClose(DateTime eta) =>
      eta.weekday == kLottoSalesCloseWeekday && eta.hour >= kLottoSalesCloseHour;

  // ── 점수 ────────────────────────────────────────────────────────────────

  static double historyScore(StoreEngineInsight ins) =>
      _log1p(ins.historyFirst.toDouble()) * 1.0 +
      _log1p(ins.historySecond.toDouble()) * 0.3;

  static double _log1p(double x) => math.log(1 + x);

  /// 엔진 가중: 검증 통과(gate pass) 가설당 +1.0, 최대 +2.0. 없으면 0.
  static double engineBonus(StoreEngineInsight ins) =>
      math.min(2.0, ins.verifiedHypothesisCount * 1.0);

  // ── 메인 ────────────────────────────────────────────────────────────────

  /// [stores] 는 lottery_stores(lotto, 좌표 유효) 스냅샷, [insights] 는 코드별 엔진 데이터.
  /// [onProgress] 는 (완료, 전체) 콜백.
  Future<RouteRecommendResult> recommend({
    required LatLng origin,
    required LatLng destination,
    required RouteResult baseRoute,
    required List<RouteStoreCandidate> stores,
    required Map<String, StoreEngineInsight> insights,
    required RouteRecommendOptions options,
    void Function(int done, int total)? onProgress,
  }) async {
    final inRadius = filterByRoute(stores, baseRoute.polyline, options.radiusKm);
    final top = selectTopCandidates(inRadius, max: options.maxCandidates);

    // 각 후보에 대해 S→P→D 실제 경로 조회 (순차, fair-use)
    final evaluated = <_Evaluated>[];
    for (var i = 0; i < top.length; i++) {
      final s = top[i];
      if (i > 0 && perRequestDelay > Duration.zero) {
        await Future.delayed(perRequestDelay);
      }
      final via = await provider.route([origin, s.point, destination]);
      final ins = insights[s.code] ?? StoreEngineInsight.empty;
      double? dT, dL;
      DateTime? eta;
      var group = DetourGroup.unverified;
      // 기본 경로와 경유 경로의 제공자가 다르면(예: 기본 Valhalla, 경유 OSRM 대체)
      // 비용 모델이 달라 ΔT/ΔL 이 의미 없으므로 "미확인"으로 둔다.
      final mismatch = via != null && via.provider != baseRoute.provider;
      if (via != null && !mismatch) {
        dT = via.durationS - baseRoute.durationS;
        dL = via.distanceM - baseRoute.distanceM;
        eta = computeEta(options.departureTime, via.durationS);
        group = dT <= options.maxDetourS
            ? DetourGroup.withinLimit
            : DetourGroup.overLimit;
      }
      evaluated.add(_Evaluated(s, ins, via, dT, dL, eta, group,
          providerMismatch: mismatch));
      onProgress?.call(i + 1, top.length);
    }

    // 정규화 기준 (engine 모드)
    final maxHist = evaluated.isEmpty
        ? 0.0
        : evaluated.map((e) => historyScore(e.insight)).reduce(math.max);

    final scored = <RouteStoreRecommendation>[];
    for (final e in evaluated) {
      final sb = _score(e, options, maxHist);
      final reasons = _reasons(e, options, sb);
      scored.add(RouteStoreRecommendation(
        rank: 0,
        store: e.store,
        insight: e.insight,
        viaRoute: e.via,
        deltaTimeS: e.dT,
        deltaDistM: e.dL,
        detourGroup: e.group,
        eta: e.eta,
        etaAfterSalesClose: e.eta != null && isAfterLottoSalesClose(e.eta!),
        score: sb,
        reasons: reasons,
        roadOption: options.roadOption,
      ));
    }

    scored.sort((a, b) => _compare(a, b, options.mode));
    final ranked = <RouteStoreRecommendation>[];
    for (var i = 0; i < scored.length; i++) {
      ranked.add(scored[i].copyWithRank(i + 1));
    }

    final verifiedStores =
        ranked.where((r) => r.insight.verifiedHypothesisCount > 0).length;
    final header = _headerNote(options.mode, verifiedStores, ranked.length,
        inRadius.length, options);

    return RouteRecommendResult(
      baseRoute: baseRoute,
      options: options,
      items: ranked,
      candidatesInRadius: inRadius.length,
      candidatesEvaluated: evaluated.length,
      verifiedEngineStores: verifiedStores,
      headerNote: header,
    );
  }

  static ScoreBreakdown _score(
      _Evaluated e, RouteRecommendOptions o, double maxHist) {
    final hist = historyScore(e.insight);
    switch (o.mode) {
      case RouteRecommendMode.minDetour:
        final dTmin = e.dT == null ? double.infinity : e.dT! / 60.0;
        return ScoreBreakdown(
          mode: o.mode,
          components: {
            'delta_t_min': dTmin,
            'delta_l_km': e.dL == null ? double.infinity : e.dL! / 1000.0,
            'history_ref': hist,
          },
          weights: const {'delta_t_min': 1.0},
          total: dTmin, // 낮을수록 우선
        );
      case RouteRecommendMode.history:
        final quality = e.insight.hasAnyAnalysis ? 0.2 : 0.0;
        return ScoreBreakdown(
          mode: o.mode,
          components: {
            'log1p_first': _log1p(e.insight.historyFirst.toDouble()),
            'log1p_second': _log1p(e.insight.historySecond.toDouble()),
            'quality': quality,
            'delta_t_min': e.dT == null ? double.infinity : e.dT! / 60.0,
          },
          weights: const {'log1p_first': 1.0, 'log1p_second': 0.3, 'quality': 1.0},
          total: hist + quality,
        );
      case RouteRecommendMode.engine:
        final access = e.dT == null
            ? 0.0
            : (1.0 - e.dT! / o.maxDetourS).clamp(0.0, 1.0).toDouble();
        final histN = maxHist > 0 ? hist / maxHist : 0.0;
        final quality = e.insight.qualityScore.clamp(0.0, 1.0).toDouble();
        final bonus = engineBonus(e.insight);
        const w = {'access': 0.5, 'history': 0.3, 'quality': 0.2, 'engine_bonus': 1.0};
        final total = w['access']! * access +
            w['history']! * histN +
            w['quality']! * quality +
            bonus;
        return ScoreBreakdown(
          mode: o.mode,
          components: {
            'access': access,
            'history': histN,
            'quality': quality,
            'engine_bonus': bonus,
            'verified_hypotheses': e.insight.verifiedHypothesisCount.toDouble(),
            'delta_t_min': e.dT == null ? double.infinity : e.dT! / 60.0,
          },
          weights: w,
          total: total,
        );
    }
  }

  /// 정렬: 1) 그룹(한도 내 < 한도 초과 < 유료구간 포함[무료 모드] < 우회 미확인)
  /// 2) 모드별 기준 3) 코드.
  static int _compare(RouteStoreRecommendation a, RouteStoreRecommendation b,
      RouteRecommendMode mode) {
    final g = a.sortGroup.compareTo(b.sortGroup);
    if (g != 0) return g;
    int c;
    switch (mode) {
      case RouteRecommendMode.minDetour:
        c = _cmpDouble(a.score.total, b.score.total); // 오름차순
        break;
      case RouteRecommendMode.history:
      case RouteRecommendMode.engine:
        c = _cmpDouble(b.score.total, a.score.total); // 내림차순
        if (c == 0) {
          // 동률이면 우회시간 짧은 쪽
          c = _cmpDouble(a.deltaTimeS ?? double.infinity,
              b.deltaTimeS ?? double.infinity);
        }
        break;
    }
    if (c != 0) return c;
    return a.store.code.compareTo(b.store.code);
  }

  static int _cmpDouble(double x, double y) {
    if (x.isNaN && y.isNaN) return 0;
    if (x.isNaN) return 1;
    if (y.isNaN) return -1;
    return x.compareTo(y);
  }

  static List<String> _reasons(
      _Evaluated e, RouteRecommendOptions o, ScoreBreakdown sb) {
    final r = <String>[];
    final ins = e.insight;
    final via = e.via;
    if (e.dT != null && e.dL != null && via != null) {
      r.add('경유 시 추가 ${(e.dT! / 60).toStringAsFixed(1)}분 · '
          '${(e.dL! / 1000).toStringAsFixed(1)}km (${via.provider} 실제 경로, 교통 미반영)');
      r.add('경유 경로 총 ${via.distanceKm.toStringAsFixed(1)}km · '
          '${via.durationMin.toStringAsFixed(0)}분');
      if (e.group == DetourGroup.overLimit) {
        r.add('최대 우회 ${o.maxDetourMin}분 초과');
      }
    } else if (e.providerMismatch && via != null) {
      r.add('$kDetourUnverified — 기본 경로와 경유 경로 제공자 불일치 '
          '(${via.provider}) → 추가시간 비교 불가');
    } else {
      r.add(kDetourUnverified);
    }
    // 통행료
    if (via != null) {
      final applied = via.tollAvoidRequested && !via.fallbackUsed;
      r.add('${o.roadOption.label} · 통행료 회피 적용: ${applied ? '예' : '아니오'}'
          '${via.fallbackUsed ? ' ($kTollFallbackNote)' : ''} · 검증: '
          '${via.tollCheck.label(fallback: via.fallbackUsed, avoidRequested: o.roadOption.avoidTolls)}');
      if (o.roadOption == RoadOption.freeOnly &&
          via.tollCheck == TollCheck.tollIncluded) {
        final legs = via.legHasToll;
        final where = legs.length == 2
            ? ' (${[
                if (legs[0] == true) '출발지→판매점',
                if (legs[1] == true) '판매점→목적지',
              ].join(', ')})'
            : '';
        r.add('⚠ $kTollNotConfirmedWarning$where → 후순위');
      }
    }
    r.add('경로에서 ${(e.store.distToRouteM / 1000).toStringAsFixed(2)}km 이내');
    r.add('당첨 이력: 1등 ${ins.historyFirst}회 · 2등 ${ins.historySecond}회'
        '${o.mode == RouteRecommendMode.minDetour ? ' (참고 표시)' : ''}');
    if (ins.purchaseMethods.isNotEmpty) {
      final parts = ins.purchaseMethods.entries
          .map((m) => '${m.key} ${m.value}')
          .join(', ');
      r.add('구매방식 분포: $parts');
    }
    if (!ins.hasAnyAnalysis) {
      r.add(kNoEngineResult);
    } else {
      final a = ins.anomaly;
      if (a != null) {
        r.add('명당연구소 이상치: ${a.anomalyStatus} '
            '(실제 ${a.totalWins} / 기대 ${a.expectedWins.toStringAsFixed(2)}, '
            'z=${a.poissonZ.toStringAsFixed(2)}, '
            '베이지안 ${a.bayesianRate.toStringAsFixed(4)} '
            '[${a.bayesianLower.toStringAsFixed(4)}~${a.bayesianUpper.toStringAsFixed(4)}], '
            '기준 ${a.trainingEndRound}회차)');
      }
      for (final h in ins.hypotheses) {
        final tag = h.isVerified ? '검증 통과' : '연구 중';
        final wf = h.wfSuccessRate == null
            ? ''
            : ' WF ${(h.wfSuccessRate! * 100).toStringAsFixed(1)}%'
                '${h.wfBaselineRate == null ? '' : ' vs 기준 ${(h.wfBaselineRate! * 100).toStringAsFixed(1)}%'}'
                ' (${h.wfRounds}회차)';
        r.add('가설 ${h.hypothesisType} [$tag · ${h.status}/${h.gateStatus}]$wf');
      }
      for (final c in ins.changePoints) {
        r.add('변화점 ${c.changePointRound}회차: '
            '${c.preRate.toStringAsFixed(4)} → ${c.postRate.toStringAsFixed(4)}');
      }
    }
    if (ins.rpaCandidateTargetRound != null) {
      r.add('Store 엔진 예측 후보 포함 (목표 ${ins.rpaCandidateTargetRound}회차)');
    }
    switch (o.mode) {
      case RouteRecommendMode.minDetour:
        r.add('최소 우회 모드: 추가 시간 오름차순 정렬');
        break;
      case RouteRecommendMode.history:
        r.add('이력 점수 ${sb.total.toStringAsFixed(3)} = '
            'log1p(1등)×1.0 + log1p(2등)×0.3 + 품질 ${sb.components['quality']!.toStringAsFixed(1)}');
        r.add(kHistoryModeNote);
        break;
      case RouteRecommendMode.engine:
        r.add('총점 ${sb.total.toStringAsFixed(3)} = '
            '0.5×접근성 ${sb.components['access']!.toStringAsFixed(2)} + '
            '0.3×이력 ${sb.components['history']!.toStringAsFixed(2)} + '
            '0.2×품질 ${sb.components['quality']!.toStringAsFixed(2)} + '
            '엔진 ${sb.components['engine_bonus']!.toStringAsFixed(1)}');
        if (ins.verifiedHypothesisCount == 0) {
          r.add('검증 통과 가설 없음 → 엔진 가중 0');
        }
        break;
    }
    if (e.eta != null) {
      r.add('예상 도착 ${_fmtTime(e.eta!)} ($kEtaNote)'
          '${isAfterLottoSalesClose(e.eta!) ? ' ⚠ 토요일 20:00 판매 마감 이후' : ''}');
    }
    r.add(kOpenStatusUnknown);
    return r;
  }

  static String _fmtTime(DateTime t) =>
      '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _headerNote(RouteRecommendMode mode, int verifiedStores,
      int ranked, int inRadius, RouteRecommendOptions o) {
    final base = '반경 ${o.radiusKm.toStringAsFixed(0)}km 내 $inRadius곳 중 '
        '$ranked곳 우회 경로 평가 · 최대 우회 ${o.maxDetourMin}분 · ${o.roadOption.label}';
    switch (mode) {
      case RouteRecommendMode.minDetour:
        return '$base · 최소 우회 순 (이력은 참고 표시)';
      case RouteRecommendMode.history:
        return '$base · $kHistoryModeNote';
      case RouteRecommendMode.engine:
        if (verifiedStores == 0) return '$base · $kNoVerifiedEngineHeader';
        return '$base · 검증 통과 판매점 $verifiedStores곳 엔진 가중 적용';
    }
  }
}

class _Evaluated {
  final RouteStoreCandidate store;
  final StoreEngineInsight insight;
  final RouteResult? via;
  final double? dT;
  final double? dL;
  final DateTime? eta;
  final DetourGroup group;
  final bool providerMismatch;
  _Evaluated(this.store, this.insight, this.via, this.dT, this.dL, this.eta,
      this.group,
      {this.providerMismatch = false});
}
