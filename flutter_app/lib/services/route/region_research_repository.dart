// 지역 추천 · 현 위치 추천 — 공용 서비스 (관리자 전용 연구 기능)
//
// ── 데이터 원칙 ───────────────────────────────────────────────────────────
//   * 모든 테이블은 SELECT 만 한다 (읽기 전용). 새 테이블 생성·DB 쓰기 없음.
//   * 크롤러 테이블: lottery_stores, winning_history (읽기만).
//   * 지역 연구 테이블 (research_v4_regions.sql, 다른 작업자가 생성/적재):
//       research_region_units / research_region_stats / research_region_hypotheses /
//       research_store_cycles
//     → 테이블 없음(404/PGRST205/42P01) = "연구 미실행(SQL 미적용)", 행 없음 = "데이터 없음".
//   * MND 기존 테이블: mnd_hypotheses (gate_status='pass' 만 검증 통과).
//   * 지방장 연구 (research_v5_agents.sql): research_agent_store_scores 를 읽어 'agent' 항목에 사용.
//     점수가 있으면 weightsWithAgent, 없으면(테이블 없음 포함) 기존 weights 그대로.
//   * 판매량 데이터가 없으므로 판매점별 "한 장당 당첨확률 우위"를 주장하지 않는다.
//   * 결정적 정렬: 동점 tie-break = 판매점 코드.
//
// ── region_id 규칙 (research_v4_regions.sql 과 동일) ─────────────────────
//   광역시 '서울|노원구' · 도 '경기|수원시' · 세종 '세종|세종시' · 시도 '서울'
//   주소 첫 토큰 = 시도 약칭, 광역시는 2번째 토큰 = 구/군, 도는 2번째 토큰 = 시/군.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../research/agent_research_repository.dart' show AgentResearchRepository, AgentStoreScore;
import 'route_store_recommender.dart' show RouteGeo;

// ═══════════════════════════════════════════════════════════════════════
// 문구
// ═══════════════════════════════════════════════════════════════════════

const String kRegionNoVerifiedHeader = '검증된 당첨확률 우위 없음 — 과거 이력 중심';
const String kRegionSalesDisclaimer =
    '판매량 데이터가 없어 판매점별 한 장당 당첨확률 우위를 주장하지 않습니다. '
    '1등 배출 수는 판매량(유동인구)에 비례할 수 있으며, 점수는 당첨확률이 아닙니다.';
const String kResearchNotApplied = '연구 미실행(SQL 미적용)';
const String kResearchNoData = '데이터 없음';
const String kOpenHoursUnknown = '영업 여부 확인 필요 (영업시간 데이터 없음)';
const String kTransitionFiringRule =
    '발화 기준: 전이 가설의 출발 지역(chain 은 경유 지역)에서 최근 horizon 회차 이내 1등이 나와, '
    '다음 회차가 예측 창 안에 들어가는 경우';

// ═══════════════════════════════════════════════════════════════════════
// region_id
// ═══════════════════════════════════════════════════════════════════════

class RegionIds {
  RegionIds._();

  static const Set<String> metro = {'서울', '부산', '대구', '인천', '광주', '대전', '울산'};

  static const Map<String, String> _long = {
    '서울특별시': '서울', '서울시': '서울',
    '부산광역시': '부산', '부산시': '부산',
    '대구광역시': '대구', '대구시': '대구',
    '인천광역시': '인천', '인천시': '인천',
    '광주광역시': '광주',
    '대전광역시': '대전', '대전시': '대전',
    '울산광역시': '울산', '울산시': '울산',
    '세종특별자치시': '세종', '세종시': '세종',
    '경기도': '경기',
    '강원도': '강원', '강원특별자치도': '강원',
    '충청북도': '충북', '충청남도': '충남',
    '전라북도': '전북', '전북특별자치도': '전북',
    '전라남도': '전남',
    '경상북도': '경북', '경상남도': '경남',
    '제주특별자치도': '제주', '제주도': '제주',
  };

  static const Set<String> _short = {
    '서울', '부산', '대구', '인천', '광주', '대전', '울산', '세종',
    '경기', '강원', '충북', '충남', '전북', '전남', '경북', '경남', '제주', '전남광주',
  };

  static String normalizeSido(String s) {
    final t = s.trim();
    return _long[t] ?? t;
  }

  static bool isInternet(String region, String address) =>
      region.contains('dhlottery') ||
      address.contains('dhlottery') ||
      region.contains('인터넷') ||
      address.startsWith('인터넷');

  /// 판매점 region(시도 약칭) + address 로 시·군·구 region_id. 판정 불가/인터넷이면 null.
  static String? fromStore({required String region, required String address}) {
    if (isInternet(region, address)) return null;
    final tokens = address.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final regionSido = normalizeSido(region);
    String sido;
    var rest = tokens;
    if (tokens.isNotEmpty &&
        (_short.contains(normalizeSido(tokens.first)) ||
            normalizeSido(tokens.first) == regionSido)) {
      sido = normalizeSido(tokens.first);
      rest = tokens.sublist(1);
    } else if (regionSido.isNotEmpty) {
      sido = regionSido;
    } else {
      return null;
    }
    if (sido.isEmpty) return null;
    if (sido == '세종') return '세종|세종시';
    if (rest.isEmpty) return null;
    final t = rest.first;
    if (metro.contains(sido)) {
      if (t.endsWith('구') || t.endsWith('군')) return '$sido|$t';
      return null;
    }
    if (t.endsWith('시') || t.endsWith('군') || t.endsWith('구')) return '$sido|$t';
    return null;
  }

  static String sidoOf(String regionId) => regionId.split('|').first;
  static String unitOf(String regionId) {
    final p = regionId.split('|');
    return p.length > 1 ? p[1] : p[0];
  }

  /// "서울|노원구" → "서울 노원구"
  static String display(String regionId) => regionId.replaceAll('|', ' ');
}

// ═══════════════════════════════════════════════════════════════════════
// 모델
// ═══════════════════════════════════════════════════════════════════════

/// 연구 테이블 상태
enum ResearchAvailability { notApplied, noData, available, error }

extension ResearchAvailabilityLabel on ResearchAvailability {
  String get label => switch (this) {
        ResearchAvailability.notApplied => kResearchNotApplied,
        ResearchAvailability.noData => kResearchNoData,
        ResearchAvailability.available => '연구 결과 있음',
        ResearchAvailability.error => '조회 오류',
      };
}

class ResearchLoad<T> {
  final ResearchAvailability state;
  final T data;
  final String? message;
  const ResearchLoad(this.state, this.data, {this.message});
}

class RegionNeighbor {
  final String regionId;
  final double km;
  const RegionNeighbor(this.regionId, this.km);
}

class RegionUnit {
  final String regionId;
  final String sido;
  final String unitName;
  final String level;
  final List<String> subUnits;
  final int storeCount;
  final int geoStoreCount;
  final LatLng? center;
  final List<RegionNeighbor> neighbors;

  /// research_region_units 가 아니라 lottery_stores 주소로 만든 대체 단위인지
  final bool derived;

  const RegionUnit({
    required this.regionId,
    required this.sido,
    required this.unitName,
    this.level = 'sigungu',
    this.subUnits = const [],
    this.storeCount = 0,
    this.geoStoreCount = 0,
    this.center,
    this.neighbors = const [],
    this.derived = false,
  });

  String get display => '$sido $unitName';

  /// 검색: 공백으로 나눈 모든 토큰이 (시도·단위명·하위단위) 중 하나에 포함되면 일치.
  bool matches(String query) {
    final toks = query.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (toks.isEmpty) return false;
    final hay = [sido, unitName, ...subUnits, regionId].join(' ');
    return toks.every((t) => hay.contains(RegionIds.normalizeSido(t)) || hay.contains(t));
  }
}

class RegionStats {
  final String regionId;
  final int trainingEndRound;
  final int firstWins;
  final int secondWins;
  final double? shrunkRate;
  final double? baselineRate;
  final double? recent50Rate;
  final double? trendZ;
  final int? dormantRounds;
  final List<Map<String, dynamic>> topStores;
  final Map<String, dynamic> difficulty;
  const RegionStats({
    required this.regionId,
    required this.trainingEndRound,
    this.firstWins = 0,
    this.secondWins = 0,
    this.shrunkRate,
    this.baselineRate,
    this.recent50Rate,
    this.trendZ,
    this.dormantRounds,
    this.topStores = const [],
    this.difficulty = const {},
  });
}

class RegionHypothesis {
  final String hypothesisId;
  final String kind;
  final String? fromRegion;
  final String? toRegion;
  final String? viaRegion;
  final String? storeCode;
  final int? horizon;
  final String status; // discovered|researching|passed|weakened|rejected|combined
  final bool liveEligible;
  final double? testRate;
  final double? testBase;
  final double? testP;
  final int discoveredRound;
  const RegionHypothesis({
    required this.hypothesisId,
    required this.kind,
    this.fromRegion,
    this.toRegion,
    this.viaRegion,
    this.storeCode,
    this.horizon,
    required this.status,
    this.liveEligible = false,
    this.testRate,
    this.testBase,
    this.testP,
    this.discoveredRound = 0,
  });

  bool get passed => status == 'passed';

  /// "to_region 에서 1등이 나올 것"을 예측하는 양(+)의 전이 유형
  static const Set<String> positiveTransitionKinds = {
    'transition_up',
    'self_repeat',
    'chain',
    'distance_band',
  };

  bool get isPositiveTransition =>
      positiveTransitionKinds.contains(kind) && toRegion != null && toRegion!.isNotEmpty;

  /// 발화 판정에 쓰는 트리거 지역 (chain 은 via, 나머지는 from)
  String? get triggerRegion =>
      (kind == 'chain' && viaRegion != null && viaRegion!.isNotEmpty) ? viaRegion : fromRegion;

  String get summary {
    final path = [
      if (fromRegion != null && fromRegion!.isNotEmpty) RegionIds.display(fromRegion!),
      if (viaRegion != null && viaRegion!.isNotEmpty) RegionIds.display(viaRegion!),
      if (toRegion != null && toRegion!.isNotEmpty) RegionIds.display(toRegion!),
    ].join(' → ');
    final store = storeCode == null || storeCode!.isEmpty ? '' : ' 판매점 $storeCode';
    final h = horizon == null ? '' : ' h=$horizon';
    return '$kind$h $path$store'.trim();
  }
}

class StoreCycle {
  final String storeCode;
  final int trainingEndRound;
  final int firstCount;
  final int secondCount;
  final double? gapMean;
  final double? gapCv;
  final int? roundsSinceLast;
  final String? cls; // famous | emerging | regular | sparse
  final double? emergingP;
  const StoreCycle({
    required this.storeCode,
    required this.trainingEndRound,
    this.firstCount = 0,
    this.secondCount = 0,
    this.gapMean,
    this.gapCv,
    this.roundsSinceLast,
    this.cls,
    this.emergingP,
  });

  bool get famousOrEmerging => cls == 'famous' || cls == 'emerging';
}

/// 판매점 (lottery_stores lotto 스냅샷). 좌표가 무효면 point == null.
class RegionStore {
  final String code;
  final String name;
  final String address;
  final String region;
  final String? regionId;
  final LatLng? point;
  final int firstCount;
  final int secondCount;
  const RegionStore({
    required this.code,
    required this.name,
    required this.address,
    required this.region,
    required this.regionId,
    required this.point,
    this.firstCount = 0,
    this.secondCount = 0,
  });
}

/// winning_history 기반 이력 (lotto)
class StoreWinHistory {
  final List<int> firstRounds; // 내림차순
  final List<int> secondRounds;
  final Map<String, int> purchaseMethods;
  const StoreWinHistory({
    this.firstRounds = const [],
    this.secondRounds = const [],
    this.purchaseMethods = const {},
  });
  int get first => firstRounds.length;
  int get second => secondRounds.length;
  bool get isEmpty => firstRounds.isEmpty && secondRounds.isEmpty;
  static const empty = StoreWinHistory();
}

enum RegionSort { engine, distance }

extension RegionSortLabel on RegionSort {
  String get label => switch (this) {
        RegionSort.engine => '엔진 종합순',
        RegionSort.distance => '거리순',
      };
}

class RankedRegionStore {
  final int rank;
  final RegionStore store;
  final double total;
  final Map<String, double> components; // 0~1 정규화 값
  final StoreWinHistory history;
  final StoreCycle? cycle;
  final List<RegionHypothesis> storeHypotheses;
  final List<RegionHypothesis> firingTransitions;
  final bool mndVerified;
  final int mndHypothesisCount;
  final double? distanceM;
  final List<String> reasons;
  final String verification; // 검증 통과 / 연구 중 / 데이터 없음
  final int? dataRound;

  /// 이 점수 계산에 실제 사용한 가중치 (지방장 점수 유무에 따라 다름)
  final Map<String, double> weights;

  /// 지방장 연구 점수 (research_agent_score_sets → 없으면 research_agent_store_scores, 최신 live 목표 회차). 없으면 null.
  final AgentStoreScore? agentScore;
  const RankedRegionStore({
    required this.rank,
    required this.store,
    required this.total,
    required this.components,
    required this.history,
    required this.cycle,
    required this.storeHypotheses,
    required this.firingTransitions,
    required this.mndVerified,
    required this.mndHypothesisCount,
    required this.distanceM,
    required this.reasons,
    required this.verification,
    required this.dataRound,
    this.weights = RegionStoreRanker.weights,
    this.agentScore,
  });

  RankedRegionStore withRank(int r) => RankedRegionStore(
        rank: r,
        store: store,
        total: total,
        components: components,
        history: history,
        cycle: cycle,
        storeHypotheses: storeHypotheses,
        firingTransitions: firingTransitions,
        mndVerified: mndVerified,
        mndHypothesisCount: mndHypothesisCount,
        distanceM: distanceM,
        reasons: reasons,
        verification: verification,
        dataRound: dataRound,
        weights: weights,
        agentScore: agentScore,
      );

  bool get hasVerifiedSignal =>
      (components['cycle'] ?? 0) > 0 || (components['transition'] ?? 0) > 0;
}

class RegionRankingResult {
  final List<RankedRegionStore> items;
  final String header;
  final int verifiedSignalStores;
  final int? latestRound;
  final ResearchAvailability researchState;
  final String disclaimer;

  /// 실제 사용한 가중치 (지방장 점수가 있으면 [RegionStoreRanker.weightsWithAgent])
  final Map<String, double> weights;
  const RegionRankingResult({
    required this.items,
    required this.header,
    required this.verifiedSignalStores,
    required this.latestRound,
    required this.researchState,
    this.disclaimer = kRegionSalesDisclaimer,
    this.weights = RegionStoreRanker.weights,
  });
}

/// 화면에서 그대로 쓰는 엔진 입력 묶음
class RegionEngineInputs {
  final Map<String, StoreWinHistory> history;
  final bool historyLoaded;
  final Map<String, StoreCycle> cycles;
  final Map<String, List<RegionHypothesis>> storeHypotheses; // store_code → 가설
  final List<RegionHypothesis> transitions; // to_region ∈ 대상 지역
  final Map<String, int> mndHypothesisCount;
  final Set<String> mndVerified;
  final Map<String, int> lastFirstRoundByRegion;
  final int? latestRound;
  final ResearchAvailability researchState;

  /// 지방장 점수 (store_code → 점수). 비어 있으면 기존 가중치 그대로.
  final Map<String, AgentStoreScore> agentScores;
  const RegionEngineInputs({
    this.history = const {},
    this.historyLoaded = false,
    this.cycles = const {},
    this.storeHypotheses = const {},
    this.transitions = const [],
    this.mndHypothesisCount = const {},
    this.mndVerified = const {},
    this.lastFirstRoundByRegion = const {},
    this.latestRound,
    this.researchState = ResearchAvailability.notApplied,
    this.agentScores = const {},
  });
}

// ═══════════════════════════════════════════════════════════════════════
// 순위 (순수 함수, 단위 테스트 대상)
// ═══════════════════════════════════════════════════════════════════════

class RegionStoreRanker {
  RegionStoreRanker._();

  /// 사전 고정 가중치 (화면에 그대로 표시)
  static const Map<String, double> weights = {
    'history': 0.4,
    'cycle': 0.2,
    'transition': 0.2,
    'quality': 0.2,
  };

  /// 지방장 점수(research_agent_store_scores)가 있을 때의 사전 고정 가중치
  static const Map<String, double> weightsWithAgent = {
    'history': 0.30,
    'agent': 0.20,
    'cycle': 0.15,
    'transition': 0.15,
    'quality': 0.20,
  };

  /// 입력에 지방장 점수가 있으면 [weightsWithAgent], 없으면 [weights]
  static Map<String, double> weightsFor(RegionEngineInputs inputs) =>
      inputs.agentScores.isNotEmpty ? weightsWithAgent : weights;

  static const Map<String, String> componentLabels = {
    'history': '이력',
    'agent': '지방장',
    'cycle': '주기·신흥',
    'transition': '지역 전이',
    'quality': '데이터 품질',
  };

  static const Map<String, String> _shortLabels = {
    'history': '이력',
    'agent': '지방장',
    'cycle': '주기',
    'transition': '전이',
    'quality': '품질',
  };

  static double rawHistory(int first, int second) =>
      math.log(1 + first) + 0.3 * math.log(1 + second);

  /// 전이 가설 발화 여부: 트리거 지역의 마지막 1등 회차 r 에 대해
  /// latest - r < horizon 이면 다음 회차(latest+1)가 예측 창 r+1..r+horizon 안에 있다.
  static bool isFiring(RegionHypothesis h, Map<String, int> lastFirstRoundByRegion,
      int? latestRound) {
    if (latestRound == null) return false;
    final trig = h.triggerRegion;
    final hz = h.horizon;
    if (trig == null || trig.isEmpty || hz == null || hz <= 0) return false;
    final r = lastFirstRoundByRegion[trig];
    if (r == null) return false;
    return latestRound - r < hz && r <= latestRound;
  }

  /// 지역별 (검증 통과 + 양의 전이 + 발화 중) 가설
  static Map<String, List<RegionHypothesis>> firingByRegion(
      List<RegionHypothesis> transitions,
      Map<String, int> lastFirstRoundByRegion,
      int? latestRound) {
    final out = <String, List<RegionHypothesis>>{};
    for (final h in transitions) {
      if (!h.passed || !h.isPositiveTransition) continue;
      if (!isFiring(h, lastFirstRoundByRegion, latestRound)) continue;
      out.putIfAbsent(h.toRegion!, () => []).add(h);
    }
    for (final l in out.values) {
      l.sort((a, b) => a.hypothesisId.compareTo(b.hypothesisId));
    }
    return out;
  }

  static List<RankedRegionStore> rank({
    required List<RegionStore> stores,
    required RegionEngineInputs inputs,
    LatLng? origin,
    RegionSort sort = RegionSort.engine,
  }) {
    final firing = firingByRegion(
        inputs.transitions, inputs.lastFirstRoundByRegion, inputs.latestRound);
    final w = weightsFor(inputs);

    int firstOf(RegionStore s) =>
        inputs.historyLoaded ? (inputs.history[s.code]?.first ?? 0) : s.firstCount;
    int secondOf(RegionStore s) =>
        inputs.historyLoaded ? (inputs.history[s.code]?.second ?? 0) : s.secondCount;

    var maxRaw = 0.0;
    for (final s in stores) {
      maxRaw = math.max(maxRaw, rawHistory(firstOf(s), secondOf(s)));
    }

    final scored = <RankedRegionStore>[];
    for (final s in stores) {
      final hist = inputs.history[s.code] ?? StoreWinHistory.empty;
      final f = firstOf(s), sc = secondOf(s);
      final histN = maxRaw > 0 ? rawHistory(f, sc) / maxRaw : 0.0;
      final cycle = inputs.cycles[s.code];
      final sh = inputs.storeHypotheses[s.code] ?? const <RegionHypothesis>[];
      final storePassed = sh.any((h) => h.passed);
      final mndPass = inputs.mndVerified.contains(s.code);
      final verifiedStoreHyp = storePassed || mndPass;
      final cycleScore =
          (cycle != null && cycle.famousOrEmerging && verifiedStoreHyp) ? 1.0 : 0.0;
      final fire = s.regionId == null
          ? const <RegionHypothesis>[]
          : (firing[s.regionId!] ?? const <RegionHypothesis>[]);
      final transScore = fire.isNotEmpty ? 1.0 : 0.0;
      final hasCoord = s.point != null;
      final hasHist = f + sc > 0;
      final quality = (hasCoord ? 0.5 : 0.0) + (hasHist ? 0.5 : 0.0);
      final agent = inputs.agentScores[s.code];
      final comps = {
        'history': histN,
        'agent': agent?.normalized ?? 0.0,
        'cycle': cycleScore,
        'transition': transScore,
        'quality': quality,
      };
      var total = 0.0;
      w.forEach((k, wt) => total += wt * comps[k]!);
      final dist = (origin != null && s.point != null)
          ? RouteGeo.haversineM(origin, s.point!)
          : null;

      final mndCount = inputs.mndHypothesisCount[s.code] ?? 0;
      final String verification;
      if (verifiedStoreHyp || transScore > 0) {
        verification = '검증 통과';
      } else if (cycle != null || sh.isNotEmpty || mndCount > 0) {
        verification = '연구 중';
      } else {
        verification = '데이터 없음';
      }
      final rounds = <int>[
        if (cycle != null) cycle.trainingEndRound,
        ...sh.map((h) => h.discoveredRound),
      ].where((r) => r > 0);
      final dataRound = rounds.isNotEmpty ? rounds.reduce(math.max) : inputs.latestRound;

      scored.add(RankedRegionStore(
        rank: 0,
        store: s,
        total: total,
        components: comps,
        history: hist,
        cycle: cycle,
        storeHypotheses: sh,
        firingTransitions: fire,
        mndVerified: mndPass,
        mndHypothesisCount: mndCount,
        distanceM: dist,
        reasons: _reasons(s, f, sc, hist, cycle, sh, mndPass, fire, comps, total,
            inputs.historyLoaded, dist, w, agent),
        verification: verification,
        dataRound: dataRound,
        weights: w,
        agentScore: agent,
      ));
    }

    scored.sort((a, b) {
      int c;
      if (sort == RegionSort.distance) {
        c = (a.distanceM ?? double.infinity).compareTo(b.distanceM ?? double.infinity);
        if (c == 0) c = b.total.compareTo(a.total);
      } else {
        c = b.total.compareTo(a.total);
        if (c == 0) {
          c = (a.distanceM ?? double.infinity).compareTo(b.distanceM ?? double.infinity);
        }
      }
      return c != 0 ? c : a.store.code.compareTo(b.store.code);
    });
    return [for (var i = 0; i < scored.length; i++) scored[i].withRank(i + 1)];
  }

  static List<String> _reasons(
    RegionStore s,
    int first,
    int second,
    StoreWinHistory hist,
    StoreCycle? cycle,
    List<RegionHypothesis> sh,
    bool mndPass,
    List<RegionHypothesis> fire,
    Map<String, double> comps,
    double total,
    bool historyLoaded,
    double? dist,
    Map<String, double> w,
    AgentStoreScore? agent,
  ) {
    final r = <String>[];
    if (dist != null) r.add('현재 위치에서 직선 ${(dist / 1000).toStringAsFixed(2)}km');
    r.add('당첨 이력: 1등 $first회 · 2등 $second회'
        '${historyLoaded ? ' (winning_history)' : ' (lottery_stores 집계, 이력 조회 실패)'}');
    if (hist.firstRounds.isNotEmpty) {
      r.add('최근 1등 회차: ${hist.firstRounds.take(5).join(', ')}');
    }
    if (cycle != null) {
      r.add('주기 연구: ${cycle.cls ?? '-'}'
          '${cycle.gapMean == null ? '' : ' · 평균 간격 ${cycle.gapMean!.toStringAsFixed(1)}회'}'
          '${cycle.roundsSinceLast == null ? '' : ' · 마지막 1등 후 ${cycle.roundsSinceLast}회'}'
          ' (기준 ${cycle.trainingEndRound}회차)');
      if (comps['cycle'] == 0 && cycle.famousOrEmerging) {
        r.add('famous/emerging 이지만 검증 통과 판매점 가설 없음 → 주기 가점 0');
      }
    }
    for (final h in sh) {
      r.add('판매점 가설 ${h.kind} [${h.status}]'
          '${h.testRate == null ? '' : ' 검증 ${(h.testRate! * 100).toStringAsFixed(1)}%'}'
          '${h.testBase == null ? '' : ' vs 기준 ${(h.testBase! * 100).toStringAsFixed(1)}%'}');
    }
    if (mndPass) r.add('명당연구소(MND) gate pass 가설 보유');
    if (fire.isNotEmpty) {
      r.add('지역 전이 발화 중: ${fire.map((h) => h.summary).join(' / ')}');
    }
    if (agent != null) {
      r.add('지방장 ${agent.agentId} ${agent.agentRank}/${agent.agentSize}위 · '
          '점수 ${agent.score.toStringAsFixed(4)} (연구 기반 후보 점수, 판매량 미보정 · '
          '${agent.targetRound}회 목표${agent.liveApplied ? ' · 검증 가설 반영' : ' · 이력 기반'})');
    } else if (w.containsKey('agent')) {
      r.add('지방장 점수 없음 → 지방장 가점 0');
    }
    if (comps['cycle'] == 0 && comps['transition'] == 0) {
      r.add('검증 통과 신호 없음 → 과거 이력 중심');
    }
    String fmt(String k) => switch (k) {
          'history' || 'agent' => comps[k]!.toStringAsFixed(2),
          'quality' => comps[k]!.toStringAsFixed(1),
          _ => comps[k]!.toStringAsFixed(0),
        };
    r.add('점수 ${total.toStringAsFixed(3)} = '
        '${w.entries.map((e) => '${_fmtW(e.value)}×${_shortLabels[e.key] ?? e.key} ${fmt(e.key)}').join(' + ')}');
    if (s.point == null) r.add('좌표 없음 → 지도·거리 표시 불가');
    r.add(kOpenHoursUnknown);
    return r;
  }

  /// 0.4 → '0.4', 0.15 → '0.15'
  static String _fmtW(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('0') ? v.toStringAsFixed(1) : s;
  }

  static RegionRankingResult buildResult(
      List<RankedRegionStore> items, RegionEngineInputs inputs) {
    final verified = items.where((i) => i.hasVerifiedSignal).length;
    final header = verified == 0
        ? kRegionNoVerifiedHeader
        : '검증 통과 신호 판매점 $verified곳 (주기·전이 가점) — 그래도 당첨확률 보장 아님';
    return RegionRankingResult(
      items: items,
      header: header,
      verifiedSignalStores: verified,
      latestRound: inputs.latestRound,
      researchState: inputs.researchState,
      weights: weightsFor(inputs),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DB 조회 (읽기 전용)
// ═══════════════════════════════════════════════════════════════════════

class RegionResearchRepository {
  final SupabaseClient _db;
  RegionResearchRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  static const int _page = 1000;
  static const int _chunk = 150;

  /// 세션 메모리 캐시 (lottery_stores 전체 스캔 결과)
  static List<RegionUnit>? _derivedUnitsCache;

  /// 테이블 없음 판정: PGRST205(스키마 캐시에 없음) / 42P01 / 404
  static bool isMissingTable(Object e) {
    if (e is PostgrestException) {
      final code = e.code ?? '';
      if (code == 'PGRST205' || code == '42P01' || code == '404') return true;
      final m = e.message.toLowerCase();
      return m.contains('could not find the table') ||
          (m.contains('relation') && m.contains('does not exist'));
    }
    final s = e.toString();
    return s.contains('PGRST205') || s.contains('42P01');
  }

  static List<List<String>> _chunks(List<String> codes) {
    final out = <List<String>>[];
    for (var i = 0; i < codes.length; i += _chunk) {
      out.add(codes.sublist(i, math.min(codes.length, i + _chunk)));
    }
    return out;
  }

  // ── 지역 단위 ───────────────────────────────────────────────────────────

  /// research_region_units(level='sigungu'). 테이블 없음/행 없음이면 lottery_stores 로 대체 목록.
  Future<ResearchLoad<List<RegionUnit>>> loadUnits() async {
    try {
      final rows = await _db
          .from('research_region_units')
          .select('region_id, sido, unit_name, level, sub_units, store_count, '
              'geo_store_count, lat, lng, neighbors')
          .eq('level', 'sigungu')
          .order('region_id', ascending: true)
          .range(0, 1999);
      final list = List<Map<String, dynamic>>.from(rows);
      if (list.isEmpty) {
        final derived = await deriveUnitsFromStores();
        return ResearchLoad(ResearchAvailability.noData, derived,
            message: 'research_region_units 행 없음 → 판매점 주소로 지역 목록 생성');
      }
      return ResearchLoad(ResearchAvailability.available, list.map(_unit).toList());
    } catch (e) {
      final derived = await deriveUnitsFromStores();
      if (isMissingTable(e)) {
        return ResearchLoad(ResearchAvailability.notApplied, derived,
            message: '$kResearchNotApplied → 판매점 주소로 지역 목록 생성');
      }
      return ResearchLoad(ResearchAvailability.error, derived, message: '지역 단위 조회 오류: $e');
    }
  }

  static RegionUnit _unit(Map<String, dynamic> r) {
    final lat = _d(r['lat']), lng = _d(r['lng']);
    final nb = <RegionNeighbor>[];
    final raw = r['neighbors'];
    if (raw is List) {
      for (final n in raw) {
        if (n is Map && n['region_id'] != null) {
          nb.add(RegionNeighbor(n['region_id'].toString(), _d(n['km']) ?? 0));
        }
      }
    }
    final subs = r['sub_units'];
    return RegionUnit(
      regionId: (r['region_id'] ?? '').toString(),
      sido: (r['sido'] ?? '').toString(),
      unitName: (r['unit_name'] ?? '').toString(),
      level: (r['level'] ?? 'sigungu').toString(),
      subUnits: subs is List ? subs.map((e) => e.toString()).toList() : const [],
      storeCount: _i(r['store_count']),
      geoStoreCount: _i(r['geo_store_count']),
      center: RouteGeo.isValidKoreaCoord(lat, lng) ? LatLng(lat!, lng!) : null,
      neighbors: nb,
    );
  }

  /// lottery_stores(lotto) 전체 주소에서 시·군·구 목록 생성 (테이블 미적용 대체).
  Future<List<RegionUnit>> deriveUnitsFromStores() async {
    final cached = _derivedUnitsCache;
    if (cached != null) return cached;
    final counts = <String, int>{};
    final geo = <String, int>{};
    final sumLat = <String, double>{}, sumLng = <String, double>{};
    var offset = 0;
    try {
      while (true) {
        final rows = await _db
            .from('lottery_stores')
            .select('dhlottery_code, region, address, latitude, longitude')
            .eq('lottery_type', 'lotto')
            .order('dhlottery_code', ascending: true)
            .range(offset, offset + _page - 1);
        final list = List<Map<String, dynamic>>.from(rows);
        for (final r in list) {
          final id = RegionIds.fromStore(
              region: (r['region'] ?? '').toString(),
              address: (r['address'] ?? '').toString());
          if (id == null) continue;
          counts[id] = (counts[id] ?? 0) + 1;
          final lat = _d(r['latitude']), lng = _d(r['longitude']);
          if (RouteGeo.isValidKoreaCoord(lat, lng)) {
            geo[id] = (geo[id] ?? 0) + 1;
            sumLat[id] = (sumLat[id] ?? 0) + lat!;
            sumLng[id] = (sumLng[id] ?? 0) + lng!;
          }
        }
        if (list.length < _page) break;
        offset += _page;
      }
    } catch (_) {
      // 일부 페이지만 읽었어도 그대로 사용
    }
    final ids = counts.keys.toList()..sort();
    final out = [
      for (final id in ids)
        RegionUnit(
          regionId: id,
          sido: RegionIds.sidoOf(id),
          unitName: RegionIds.unitOf(id),
          storeCount: counts[id]!,
          geoStoreCount: geo[id] ?? 0,
          center: (geo[id] ?? 0) > 0
              ? LatLng(sumLat[id]! / geo[id]!, sumLng[id]! / geo[id]!)
              : null,
          derived: true,
        ),
    ];
    if (out.isNotEmpty) _derivedUnitsCache = out;
    return out;
  }

  // ── 판매점 ─────────────────────────────────────────────────────────────

  static RegionStore _store(Map<String, dynamic> r) {
    final lat = _d(r['latitude']), lng = _d(r['longitude']);
    final region = (r['region'] ?? '').toString();
    final address = (r['address'] ?? '').toString();
    return RegionStore(
      code: (r['dhlottery_code'] ?? '').toString(),
      name: (r['store_name'] ?? '').toString(),
      address: address,
      region: region,
      regionId: RegionIds.fromStore(region: region, address: address),
      point: RouteGeo.isValidKoreaCoord(lat, lng) ? LatLng(lat!, lng!) : null,
      firstCount: _i(r['first_count']),
      secondCount: _i(r['second_count']),
    );
  }

  static const String _storeCols =
      'dhlottery_code, store_name, address, region, latitude, longitude, first_count, second_count';

  /// region_id 에 속한 로또 판매점 (좌표 무효 포함, 주소로 정확 일치 재검증)
  Future<List<RegionStore>> loadStoresInRegion(String regionId) async {
    final sido = RegionIds.sidoOf(regionId);
    final unit = RegionIds.unitOf(regionId);
    final pattern = sido == '세종' ? '세종%' : '%$unit%';
    final out = <RegionStore>[];
    var offset = 0;
    while (true) {
      final rows = await _db
          .from('lottery_stores')
          .select(_storeCols)
          .eq('lottery_type', 'lotto')
          .ilike('address', pattern)
          .order('dhlottery_code', ascending: true)
          .range(offset, offset + _page - 1);
      final list = List<Map<String, dynamic>>.from(rows);
      for (final r in list) {
        final s = _store(r);
        if (s.code.isEmpty || s.regionId != regionId) continue;
        out.add(s);
      }
      if (list.length < _page) break;
      offset += _page;
    }
    final seen = <String>{};
    return out.where((s) => seen.add(s.code)).toList();
  }

  /// 중심 [center] 반경 [radiusKm] 내 판매점 (행정 경계 무관, Haversine 재검증)
  Future<List<RegionStore>> loadStoresNear(LatLng center, double radiusKm) async {
    final box = RouteGeo.boundingBox([center], radiusKm);
    final out = <RegionStore>[];
    var offset = 0;
    while (true) {
      final rows = await _db
          .from('lottery_stores')
          .select(_storeCols)
          .eq('lottery_type', 'lotto')
          .gte('latitude', box.minLat)
          .lte('latitude', box.maxLat)
          .gte('longitude', box.minLng)
          .lte('longitude', box.maxLng)
          .order('dhlottery_code', ascending: true)
          .range(offset, offset + _page - 1);
      final list = List<Map<String, dynamic>>.from(rows);
      for (final r in list) {
        final s = _store(r);
        if (s.code.isEmpty || s.point == null) continue;
        if (RouteGeo.haversineM(center, s.point!) <= radiusKm * 1000) out.add(s);
      }
      if (list.length < _page) break;
      offset += _page;
    }
    final seen = <String>{};
    return out.where((s) => seen.add(s.code)).toList();
  }

  // ── 엔진 입력 ───────────────────────────────────────────────────────────

  /// [stores] 와 대상 지역 [regionIds] 에 대한 엔진 입력을 묶음 조회.
  Future<RegionEngineInputs> loadEngineInputs(
      List<RegionStore> stores, Set<String> regionIds) async {
    final codes = stores.map((s) => s.code).toSet().toList()..sort();

    // 1) winning_history (크롤러 테이블, 읽기 전용)
    final firstR = <String, List<int>>{};
    final secondR = <String, List<int>>{};
    final methods = <String, Map<String, int>>{};
    var historyLoaded = true;
    try {
      for (final ch in _chunks(codes)) {
        final rows = await _db
            .from('winning_history')
            .select('dhlottery_code, round, prize_tier, purchase_method')
            .eq('lottery_type', 'lotto')
            .inFilter('dhlottery_code', ch)
            .range(0, 9999);
        for (final r in List<Map<String, dynamic>>.from(rows)) {
          final c = (r['dhlottery_code'] ?? '').toString();
          final round = _i(r['round']);
          final tier = (r['prize_tier'] ?? '').toString();
          if (tier == 'first') firstR.putIfAbsent(c, () => []).add(round);
          if (tier == 'second') secondR.putIfAbsent(c, () => []).add(round);
          final m = (r['purchase_method'] ?? '').toString().trim();
          final key = m.isEmpty ? '미상' : m;
          methods.putIfAbsent(c, () => {});
          methods[c]![key] = (methods[c]![key] ?? 0) + 1;
        }
      }
    } catch (_) {
      historyLoaded = false;
    }
    final history = <String, StoreWinHistory>{};
    for (final c in codes) {
      final f = (firstR[c] ?? [])..sort((a, b) => b.compareTo(a));
      final s = (secondR[c] ?? [])..sort((a, b) => b.compareTo(a));
      history[c] = StoreWinHistory(
          firstRounds: f, secondRounds: s, purchaseMethods: methods[c] ?? const {});
    }

    // 2) 최신 회차
    int? latestRound;
    try {
      final rows = await _db
          .from('winning_history')
          .select('round')
          .eq('lottery_type', 'lotto')
          .order('round', ascending: false)
          .limit(1);
      final l = List<Map<String, dynamic>>.from(rows);
      if (l.isNotEmpty) latestRound = _i(l.first['round']);
    } catch (_) {}

    // 3) 연구 테이블
    var missing = 0, empty = 0, ok = 0;
    void mark(ResearchAvailability a) {
      if (a == ResearchAvailability.notApplied) missing++;
      if (a == ResearchAvailability.noData) empty++;
      if (a == ResearchAvailability.available) ok++;
    }

    final cycles = <String, StoreCycle>{};
    try {
      var any = false;
      for (final ch in _chunks(codes)) {
        final rows = await _db
            .from('research_store_cycles')
            .select('store_code, training_end_round, first_count, second_count, gap_mean, '
                'gap_cv, rounds_since_last, class, emerging_p')
            .inFilter('store_code', ch)
            .order('training_end_round', ascending: false);
        for (final r in List<Map<String, dynamic>>.from(rows)) {
          any = true;
          final c = (r['store_code'] ?? '').toString();
          if (cycles.containsKey(c)) continue; // 최신만
          cycles[c] = StoreCycle(
            storeCode: c,
            trainingEndRound: _i(r['training_end_round']),
            firstCount: _i(r['first_count']),
            secondCount: _i(r['second_count']),
            gapMean: _d(r['gap_mean']),
            gapCv: _d(r['gap_cv']),
            roundsSinceLast: _iN(r['rounds_since_last']),
            cls: r['class']?.toString(),
            emergingP: _d(r['emerging_p']),
          );
        }
      }
      mark(any ? ResearchAvailability.available : ResearchAvailability.noData);
    } catch (e) {
      if (isMissingTable(e)) mark(ResearchAvailability.notApplied);
    }

    final storeHyps = <String, List<RegionHypothesis>>{};
    final transitions = <RegionHypothesis>[];
    try {
      var any = false;
      for (final ch in _chunks(codes)) {
        final rows = await _db
            .from('research_region_hypotheses')
            .select(_hypCols)
            .inFilter('store_code', ch);
        for (final r in List<Map<String, dynamic>>.from(rows)) {
          any = true;
          final h = _hyp(r);
          storeHyps.putIfAbsent(h.storeCode ?? '', () => []).add(h);
        }
      }
      final regions = regionIds.toList()..sort();
      for (final ch in _chunks(regions)) {
        final rows = await _db
            .from('research_region_hypotheses')
            .select(_hypCols)
            .inFilter('to_region', ch);
        for (final r in List<Map<String, dynamic>>.from(rows)) {
          any = true;
          final h = _hyp(r);
          if (h.storeCode == null || h.storeCode!.isEmpty) transitions.add(h);
        }
      }
      for (final l in storeHyps.values) {
        l.sort((a, b) => a.hypothesisId.compareTo(b.hypothesisId));
      }
      mark(any ? ResearchAvailability.available : ResearchAvailability.noData);
    } catch (e) {
      if (isMissingTable(e)) mark(ResearchAvailability.notApplied);
    }

    // 4) 전이 발화 판정용: 트리거 지역의 최근 1등 회차
    final lastFirst = <String, int>{};
    final passedTrans =
        transitions.where((h) => h.passed && h.isPositiveTransition).toList();
    if (passedTrans.isNotEmpty && latestRound != null) {
      final maxH = passedTrans.map((h) => h.horizon ?? 0).fold<int>(0, math.max);
      if (maxH > 0) {
        try {
          final rows = await _db
              .from('winning_history')
              .select('dhlottery_code, round')
              .eq('lottery_type', 'lotto')
              .eq('prize_tier', 'first')
              .gt('round', latestRound - maxH)
              .range(0, 4999);
          final wins = List<Map<String, dynamic>>.from(rows);
          final winCodes = wins.map((r) => (r['dhlottery_code'] ?? '').toString()).toSet().toList();
          final regionOf = <String, String>{};
          for (final ch in _chunks(winCodes)) {
            final srows = await _db
                .from('lottery_stores')
                .select('dhlottery_code, region, address')
                .eq('lottery_type', 'lotto')
                .inFilter('dhlottery_code', ch);
            for (final r in List<Map<String, dynamic>>.from(srows)) {
              final id = RegionIds.fromStore(
                  region: (r['region'] ?? '').toString(),
                  address: (r['address'] ?? '').toString());
              if (id != null) regionOf[(r['dhlottery_code'] ?? '').toString()] = id;
            }
          }
          for (final w in wins) {
            final id = regionOf[(w['dhlottery_code'] ?? '').toString()];
            if (id == null) continue;
            final rd = _i(w['round']);
            if ((lastFirst[id] ?? 0) < rd) lastFirst[id] = rd;
          }
        } catch (_) {}
      }
    }

    // 5) MND (기존 연구 테이블): gate_status='pass' 만 검증 통과
    final mndCount = <String, int>{};
    final mndPass = <String>{};
    try {
      for (final ch in _chunks(codes)) {
        final rows = await _db
            .from('mnd_hypotheses')
            .select('subject_id, gate_status')
            .inFilter('subject_id', ch);
        for (final r in List<Map<String, dynamic>>.from(rows)) {
          final c = (r['subject_id'] ?? '').toString();
          mndCount[c] = (mndCount[c] ?? 0) + 1;
          if ((r['gate_status'] ?? '').toString() == 'pass') mndPass.add(c);
        }
      }
    } catch (_) {}

    // 6) 지방장 점수 (최신 live 목표 회차). research_agent_score_sets(압축) 우선 → 없으면
    //    research_agent_store_scores. 지방장 id = RegionStore.regionId (하나라도 판정 불가면 회차 전체 조회).
    //    테이블 없음/오류 → 비어 있음.
    var agentScores = const <String, AgentStoreScore>{};
    try {
      final a = await AgentResearchRepository(client: _db).loadLatestStoreScores(codes,
          agentIds: AgentResearchRepository.agentIdsOf(stores.map((s) => s.regionId)));
      agentScores = a.data;
    } catch (_) {}

    final state = ok > 0
        ? ResearchAvailability.available
        : (missing > 0 && empty == 0)
            ? ResearchAvailability.notApplied
            : ResearchAvailability.noData;

    return RegionEngineInputs(
      history: history,
      historyLoaded: historyLoaded,
      cycles: cycles,
      storeHypotheses: storeHyps,
      transitions: transitions,
      mndHypothesisCount: mndCount,
      mndVerified: mndPass,
      lastFirstRoundByRegion: lastFirst,
      latestRound: latestRound,
      researchState: state,
      agentScores: agentScores,
    );
  }

  static const String _hypCols =
      'hypothesis_id, kind, from_region, to_region, via_region, store_code, horizon, '
      'status, live_eligible, test_rate, test_base, test_p, discovered_round';

  static RegionHypothesis _hyp(Map<String, dynamic> r) => RegionHypothesis(
        hypothesisId: (r['hypothesis_id'] ?? '').toString(),
        kind: (r['kind'] ?? '').toString(),
        fromRegion: r['from_region']?.toString(),
        toRegion: r['to_region']?.toString(),
        viaRegion: r['via_region']?.toString(),
        storeCode: r['store_code']?.toString(),
        horizon: _iN(r['horizon']),
        status: (r['status'] ?? 'discovered').toString(),
        liveEligible: r['live_eligible'] == true,
        testRate: _d(r['test_rate']),
        testBase: _d(r['test_base']),
        testP: _d(r['test_p']),
        discoveredRound: _i(r['discovered_round']),
      );

  // ── 지역 통계·가설 목록 ─────────────────────────────────────────────────

  /// [regionIds] 각각의 최신 training_end_round 통계
  Future<ResearchLoad<Map<String, RegionStats>>> loadLatestStats(
      List<String> regionIds) async {
    if (regionIds.isEmpty) {
      return const ResearchLoad(ResearchAvailability.noData, {});
    }
    try {
      final rows = await _db
          .from('research_region_stats')
          .select('region_id, training_end_round, first_wins, second_wins, shrunk_rate, '
              'baseline_rate, recent50_rate, trend_z, dormant_rounds, top_stores, difficulty')
          .inFilter('region_id', regionIds)
          .order('training_end_round', ascending: false)
          .range(0, 1999);
      final out = <String, RegionStats>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final id = (r['region_id'] ?? '').toString();
        if (out.containsKey(id)) continue;
        final top = r['top_stores'];
        final diff = r['difficulty'];
        out[id] = RegionStats(
          regionId: id,
          trainingEndRound: _i(r['training_end_round']),
          firstWins: _i(r['first_wins']),
          secondWins: _i(r['second_wins']),
          shrunkRate: _d(r['shrunk_rate']),
          baselineRate: _d(r['baseline_rate']),
          recent50Rate: _d(r['recent50_rate']),
          trendZ: _d(r['trend_z']),
          dormantRounds: _iN(r['dormant_rounds']),
          topStores: top is List
              ? top.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
              : const [],
          difficulty: diff is Map ? Map<String, dynamic>.from(diff) : const {},
        );
      }
      return ResearchLoad(
          out.isEmpty ? ResearchAvailability.noData : ResearchAvailability.available, out);
    } catch (e) {
      return ResearchLoad(
          isMissingTable(e) ? ResearchAvailability.notApplied : ResearchAvailability.error,
          const {},
          message: isMissingTable(e) ? kResearchNotApplied : '$e');
    }
  }

  /// 지역 내부(from=to)·지역 간 전이 가설 (from 또는 to 가 [regionId]). 상위 [limit].
  /// 정렬: status(passed→researching→discovered→weakened→combined→rejected), test_p 오름차순, id.
  Future<ResearchLoad<List<RegionHypothesis>>> loadRegionHypotheses(String regionId,
      {int limit = 10}) async {
    try {
      final byId = <String, RegionHypothesis>{};
      for (final col in const ['from_region', 'to_region']) {
        final rows = await _db
            .from('research_region_hypotheses')
            .select(_hypCols)
            .eq(col, regionId)
            .range(0, 999);
        for (final r in List<Map<String, dynamic>>.from(rows)) {
          final h = _hyp(r);
          if (h.storeCode != null && h.storeCode!.isNotEmpty) continue;
          byId[h.hypothesisId] = h;
        }
      }
      final list = sortHypotheses(byId.values.toList()).take(limit).toList();
      return ResearchLoad(
          list.isEmpty ? ResearchAvailability.noData : ResearchAvailability.available, list);
    } catch (e) {
      return ResearchLoad(
          isMissingTable(e) ? ResearchAvailability.notApplied : ResearchAvailability.error,
          const [],
          message: isMissingTable(e) ? kResearchNotApplied : '$e');
    }
  }

  static const List<String> statusOrder = [
    'passed', 'researching', 'discovered', 'weakened', 'combined', 'rejected',
  ];

  static List<RegionHypothesis> sortHypotheses(List<RegionHypothesis> l) {
    int si(String s) {
      final i = statusOrder.indexOf(s);
      return i < 0 ? statusOrder.length : i;
    }

    return l
      ..sort((a, b) {
        var c = si(a.status).compareTo(si(b.status));
        if (c != 0) return c;
        c = (a.testP ?? 1.0).compareTo(b.testP ?? 1.0);
        if (c != 0) return c;
        return a.hypothesisId.compareTo(b.hypothesisId);
      });
  }

  // ── 유틸 ───────────────────────────────────────────────────────────────

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _i(dynamic v) => _iN(v) ?? 0;
  static int? _iN(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
