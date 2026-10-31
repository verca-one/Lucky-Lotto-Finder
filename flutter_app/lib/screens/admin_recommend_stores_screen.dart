import 'dart:async';
import 'dart:math' show max, sqrt;

import 'package:flutter/material.dart';
import 'combined_store_picks_screen.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import '../services/rpa_joint_engine.dart';
import '../services/rpa_live_numbers.dart';
import '../services/rpa_unified_prediction.dart' show kRpaActiveModelVersion;
import '../services/mnd_engine.dart';
import '../widgets/engine_reflection_badge.dart';
import '../widgets/purchase_recommend_card.dart';
import 'admin_comprehensive_prediction_screen.dart';
import 'nearby_screen.dart';
import 'admin_route_recommend_screen.dart';
import 'admin_region_recommend_screen.dart';
import 'admin_location_recommend_screen.dart';
import '../widgets/agent_next_picks.dart';
import '../widgets/agent_store_widgets.dart' show AgentCentralView;

class AdminRecommendStoresScreen extends StatefulWidget {
  const AdminRecommendStoresScreen({super.key});

  @override
  State<AdminRecommendStoresScreen> createState() => _AdminRecommendStoresScreenState();
}

class _AdminRecommendStoresScreenState extends State<AdminRecommendStoresScreen> {
  bool _isLoading = true;
  List<_RecommendStore> _stores = [];
  String _selectedType = 'lotto';
  int _latestRound = 0;
  bool _isAdmin = false;
  int _topTab = 0; // 0: 기존 추천, 1: 지역 추천, 2: 현 위치 추천, 3: 경로 기반 추천, 4: 전국 종합(지방장 중앙 엔진) (관리자 전용)
  String? _regionTabRegionId; // 현 위치 추천 → 지역 추천 이동 시 선택 지역

  // 지역별 추천 판매점 (회차유력 + 자동구매 종합 점수)
  List<_RegionStore> _regionStores = [];
  bool _regionLoading = false;
  bool _regionLoaded = false;

  // 백그라운드 위치 감시 (관리자 모드)
  Position? _currentPosition;
  StreamSubscription<Position>? _locationSub;
  bool _notifiedNearby = false; // 알림 스팸 방지

  // 판매점 검색
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  static const _typeLabels = {'lotto': '로또', 'pension': '연금'};
  static const int _window = 3;
  static const double _nearbyAlertM = 600.0; // 600m 이내 알림
  static const int _minFirstWins = 5;        // 최소 1등 당첨 횟수
  static const double _geoDedupM = 300.0;    // 지리적 중복 제거 반경 (m)

  @override
  void initState() {
    super.initState();
    _loadAdmin();
    _load();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final isAdmin = prefs.getBool('isAdmin') ?? false;
    if (mounted) setState(() => _isAdmin = isAdmin);
    if (isAdmin) _startLocationWatch();
  }

  // 관리자 모드: 백그라운드 위치 스트림 시작
  Future<void> _startLocationWatch() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;

    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 30, // 30m 이동시마다 갱신
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _currentPosition = pos);
      _checkNearbyAlert(pos);
    });
  }

  // 600m 이내 유력 판매점 감지 → 관리자 알림
  void _checkNearbyAlert(Position pos) {
    if (!_isAdmin || _stores.isEmpty) return;
    final nearby = _stores.where((s) {
      if (s.latitude == null || s.longitude == null) return false;
      return Geolocator.distanceBetween(
            pos.latitude, pos.longitude, s.latitude!, s.longitude!) <=
          _nearbyAlertM;
    }).toList();

    if (nearby.isNotEmpty && !_notifiedNearby) {
      _notifiedNearby = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange.shade700,
          duration: const Duration(seconds: 6),
          content: Row(
            children: [
              const Icon(Icons.location_on_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '600m 내 유력 판매점 ${nearby.length}곳 발견!',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: '보기',
            textColor: Colors.white,
            onPressed: _showNearbySheet,
          ),
        ),
      );
      // 5분 후 재알림 허용
      Future.delayed(const Duration(minutes: 5), () => _notifiedNearby = false);
    } else if (nearby.isEmpty) {
      _notifiedNearby = false;
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final stores = await _calcRecommendStores(_selectedType);
      if (mounted) setState(() {
        _stores = stores;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    }
  }

  Future<List<_RecommendStore>> _calcRecommendStores(String lt) async {
    final latestRound = (await SupabaseService.getLatestRound(lt)) ?? 0;
    if (latestRound == 0) return [];
    _latestRound = latestRound;

    final Map<String, List<int>> firstRoundsMap = {};
    final Map<String, ({int auto, int known})> purchaseMap = {};
    int offset = 0;
    while (true) {
      final batch = await SupabaseService.getWinningHistoryBatch(
        lotteryType: lt, prizeTier: 'first', offset: offset, limit: 1000,
      );
      for (final row in batch) {
        final code = row['dhlottery_code'] as String;
        final round = (row['round'] as num).toInt();
        firstRoundsMap.putIfAbsent(code, () => []).add(round);
        final method = row['purchase_method'] as String? ?? '';
        if (method.isNotEmpty) {
          final prev = purchaseMap[code] ?? (auto: 0, known: 0);
          purchaseMap[code] = (
            auto: prev.auto + (method == '자동' ? 1 : 0),
            known: prev.known + 1,
          );
        }
      }
      if (batch.length < 1000) break;
      offset += 1000;
    }

    final codes = firstRoundsMap.keys.toList();
    if (codes.isEmpty) return [];
    final storeInfoList = await SupabaseService.getStoreInfoByCodes(codes, lt);
    final storeInfoMap = <String, Map<String, dynamic>>{
      for (final s in storeInfoList) s['dhlottery_code'] as String: s,
    };

    final List<_RecommendStore> result = [];

    for (final entry in firstRoundsMap.entries) {
      final code = entry.key;
      final rounds = entry.value..sort();
      if (rounds.length < _minFirstWins) continue;

      final intervals = <int>[];
      for (int i = 1; i < rounds.length; i++) {
        intervals.add(rounds[i] - rounds[i - 1]);
      }
      final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;
      final predictedRound = rounds.last + avgInterval.round();
      final elapsed = latestRound - rounds.last;

      // 추격 기준: 다음 회차 (latestRound + 1)
      final targetRound = latestRound + 1;
      if ((predictedRound - targetRound).abs() > _window) continue;

      final info = storeInfoMap[code];
      if (info == null) continue;
      final storeName = info['store_name'] as String? ?? '';
      if (storeName.isEmpty) continue;

      final months = (avgInterval / 4.3).round();
      // roundDiff == 0 → 이번 회차(targetRound) 유력, +N → N회 후, -N → N회 경과
      final roundDiff = predictedRound - targetRound;

      // ── 추천 이유 태그 계산 ──────────────────────────────────
      final tags = <String>[];
      if (roundDiff == 0) {
        tags.add('$targetRound회차 유력당첨점');
        tags.add('자동 당첨주기 $targetRound회차 유력');
      } else if (roundDiff > 0) {
        tags.add('자동 당첨주기 $predictedRound회차 유력');
      } else {
        tags.add('자동 당첨주기 $predictedRound회차 (${roundDiff.abs()}회 경과)');
      }
      // 최근 당첨 흐름 우수: 최근 30회차 이내 2회 이상 당첨
      final recentWins = rounds.where((r) => (targetRound - r) <= 30 && r <= targetRound).length;
      if (recentWins >= 2) tags.add('최근 당첨 흐름 우수');
      // 홀수/짝수 회차 당첨 확률 우수
      if (rounds.length >= 5) {
        final oddWins = rounds.where((r) => r % 2 == 1).length;
        final evenWins = rounds.where((r) => r % 2 == 0).length;
        if (targetRound % 2 == 1 && oddWins / rounds.length >= 0.65) {
          tags.add('홀수 회차 당첨 확률 우수');
        }
        if (targetRound % 2 == 0 && evenWins / rounds.length >= 0.65) {
          tags.add('짝수 회차 당첨 확률 우수');
        }
      }

      final pm = purchaseMap[code];
      final autoRatio = (pm != null && pm.known > 0) ? pm.auto / pm.known : null;

      result.add(_RecommendStore(
        code: code,
        name: storeName,
        address: info['address'] as String? ?? '',
        firstCount: rounds.length,
        avgInterval: avgInterval,
        months: months,
        lastWinRound: rounds.last,
        elapsed: elapsed,
        latestRound: latestRound,
        predictedRound: predictedRound,
        roundDiff: roundDiff,
        latitude: (info['latitude'] as num?)?.toDouble(),
        longitude: (info['longitude'] as num?)?.toDouble(),
        tags: List.unmodifiable(tags),
        autoRatio: autoRatio,
      ));
    }

    result.sort((a, b) => a.roundDiff.abs().compareTo(b.roundDiff.abs()));
    return _geoDedup(result);
  }

  // 300m 이내 중복 판매점 제거 — 정렬 후 적용해야 높은 점수/예측 정확도 쪽이 살아남음
  static List<_RecommendStore> _geoDedup(List<_RecommendStore> sorted) {
    final result = <_RecommendStore>[];
    for (final s in sorted) {
      if (s.latitude == null || s.longitude == null) {
        result.add(s);
        continue;
      }
      final hasNearby = result.any((r) {
        if (r.latitude == null || r.longitude == null) return false;
        return Geolocator.distanceBetween(
          s.latitude!, s.longitude!, r.latitude!, r.longitude!,
        ) <= _geoDedupM;
      });
      if (!hasNearby) result.add(s);
    }
    return result;
  }

  // 주소에서 시/군/구 단위까지 포함한 세분화 지역명 추출
  // 예: "경기도 수원시 팔달구 ..." → "경기도 수원시"
  //     "경기도 화성시 ..."       → "경기도 화성시"
  //     "인천광역시 부평구 ..."    → "인천광역시 부평구"
  // (DB의 region 컬럼은 시/도 단위까지만 있어 경기/인천 등이 뭉쳐 보이므로
  //  화면 표시용 지역은 항상 주소에서 다시 계산한다)
  String _regionFromAddress(String address) {
    if (address.trim().isEmpty) return '기타';
    final parts = address.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '기타';
    final top = parts.first;
    if (parts.length >= 2) {
      final second = parts[1];
      if (second.endsWith('시') || second.endsWith('군') || second.endsWith('구')) {
        return '$top $second';
      }
    }
    return top;
  }

  // ══════════════════════════════════════════════════════════════
  // 지역에서 추천하는 판매점 — 회차 + 당첨이력 종합 점수
  // 우선순위: 엔진유력지역(25pt) > 회차유력(50%) > 자동구매(20%) > 당첨횟수(10%) > 흐름(5%)
  // ══════════════════════════════════════════════════════════════

  // Joint Model 유력 지역과 주소 매칭 (축약 지역명 → 주소 포함 여부)
  bool _addressMatchesEngineRegion(String address, Set<String> engineRegions) {
    if (engineRegions.isEmpty || address.isEmpty) return false;
    final addr = address;
    for (final r in engineRegions) {
      if (r.isEmpty || r.contains('dhlottery') || r.contains('동행복권')) continue;
      if (r == '전남광주') {
        if (addr.contains('전남') || addr.contains('전라남') || addr.contains('광주')) return true;
      } else if (r == '서울') {
        if (addr.contains('서울')) return true;
      } else if (r == '경남') {
        if (addr.contains('경남') || addr.contains('경상남')) return true;
      } else if (r == '경북') {
        if (addr.contains('경북') || addr.contains('경상북')) return true;
      } else if (r == '전북') {
        if (addr.contains('전북') || addr.contains('전라북')) return true;
      } else if (r == '충남') {
        if (addr.contains('충남') || addr.contains('충청남')) return true;
      } else if (r == '충북') {
        if (addr.contains('충북') || addr.contains('충청북')) return true;
      } else {
        if (addr.contains(r)) return true;
      }
    }
    return false;
  }

  Future<List<_RegionStore>> _calcRegionRecommendStores(String lt) async {
    final latestRound = (await SupabaseService.getLatestRound(lt)) ?? 0;
    if (latestRound == 0) return [];
    final targetRound = latestRound + 1;

    // ── Joint Model 유력 지역 로드 ──────────────────────────────
    Set<String> engineRegions = {};
    try {
      final preds = await JointModelEngine.instance.loadRecentPredictions(limit: 6);
      final targetPred = preds.where((p) => p['target_round'] == targetRound).firstOrNull
          ?? (preds.isNotEmpty ? preds.first : null);
      if (targetPred != null) {
        final regions = List<String>.from(
            targetPred['joint_candidate_regions'] as List? ?? []);
        engineRegions = regions.toSet();
      }
    } catch (_) {}

    // ── 명당 가설 연구소: Gate 통과 판매점 코드 로드 ─────────────
    Set<String> mndLiveCodes = {};
    try {
      final mndState = await MndEngine.instance.loadState(latestRound);
      mndLiveCodes = mndState.hypotheses
          .where((h) => h.livePredictionActive && h.subjectType == 'store')
          .map((h) => h.subjectId)
          .toSet();
    } catch (_) {}

    // code -> [(round, purchaseMethod)]
    final Map<String, List<_WinRecord>> historyMap = {};
    int offset = 0;
    while (true) {
      final batch = await SupabaseService.getWinningHistoryBatch(
        lotteryType: lt, prizeTier: 'first', offset: offset, limit: 1000,
      );
      for (final row in batch) {
        final code = row['dhlottery_code'] as String;
        final round = (row['round'] as num).toInt();
        final method = (row['purchase_method'] as String?) ?? '';
        historyMap.putIfAbsent(code, () => []).add(_WinRecord(round, method));
      }
      if (batch.length < 1000) break;
      offset += 1000;
    }

    final codes = historyMap.keys.toList();
    if (codes.isEmpty) return [];
    final storeInfoList = await SupabaseService.getStoreInfoByCodes(codes, lt);
    final storeInfoMap = <String, Map<String, dynamic>>{
      for (final s in storeInfoList) s['dhlottery_code'] as String: s,
    };

    // ── 사전 계산 (신규 지표용) ─────────────────────────────
    // ① 회차별 1등 판매점 수 → 단독/공동 1등 판별
    final Map<int, int> roundWinnerCount = {};
    for (final recs in historyMap.values) {
      for (final rec in recs) {
        roundWinnerCount[rec.round] = (roundWinnerCount[rec.round] ?? 0) + 1;
      }
    }

    // ② 지역별 최근 10회차 당첨 포화도
    final recentSatCutoff = latestRound - 10;
    final Map<String, int> regionRecentWins = {};
    for (final entry in historyMap.entries) {
      final info = storeInfoMap[entry.key];
      if (info == null) continue;
      final reg = _regionFromAddress(info['address'] as String? ?? '');
      for (final rec in entry.value) {
        if (rec.round > recentSatCutoff) {
          regionRecentWins[reg] = (regionRecentWins[reg] ?? 0) + 1;
        }
      }
    }

    // ③ 좌표 리스트 (인근 3km 분석용)
    final storeGeoList = <({String code, double lat, double lng, int lastWin})>[];
    for (final entry in historyMap.entries) {
      final info = storeInfoMap[entry.key];
      if (info == null) continue;
      final lat = (info['latitude'] as num?)?.toDouble();
      final lng = (info['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final lastWin = entry.value.map((r) => r.round).reduce(max);
      storeGeoList.add((code: entry.key, lat: lat, lng: lng, lastWin: lastWin));
    }

    // 회차 → 월 변환 (1회차 = 2002-12-07)
    int roundToMonth(int r) =>
        DateTime(2002, 12, 7).add(Duration(days: (r - 1) * 7)).month;

    final List<_RegionStore> result = [];

    for (final entry in historyMap.entries) {
      final code = entry.key;
      final records = entry.value..sort((a, b) => a.round.compareTo(b.round));
      if (records.length < 3) continue; // 최소 3회 이상 당첨이력 필요

      final info = storeInfoMap[code];
      if (info == null) continue;
      final storeName = info['store_name'] as String? ?? '';
      if (storeName.isEmpty) continue;
      final address = info['address'] as String? ?? '';
      final region = _regionFromAddress(address);

      final rounds = records.map((r) => r.round).toList();
      final elapsed = latestRound - rounds.last;

      // ── [필터 1] 너무 오래된 판매점 제외 ──────────────────
      // 마지막 당첨이 200회 이상 전이면 패턴 신뢰 불가 (약 4년)
      if (elapsed > 200) continue;

      // ── 간격 계산 ─────────────────────────────────────────
      final intervals = <int>[];
      for (int i = 1; i < rounds.length; i++) {
        intervals.add(rounds[i] - rounds[i - 1]);
      }
      final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;

      // ── [필터 2] 평균 간격 너무 긴 판매점 제외 ────────────
      // 평균 150회(약 3년) 이상 간격이면 예측 불가
      if (avgInterval > 150) continue;

      final predictedRound = rounds.last + avgInterval.round();
      final roundDiff = predictedRound - targetRound;

      // ── 회차유력 점수 (50%) ────────────────────────────────
      final roundScore = (100 - (roundDiff.abs() * 15)).clamp(0, 100).toDouble();

      // ── 자동구매 비율 점수 (20%) ───────────────────────────
      final known = records.where((r) => r.purchaseMethod.isNotEmpty).toList();
      final autoCount = known.where((r) => r.purchaseMethod == '자동').length;
      final double? autoRatio = known.isEmpty ? null : autoCount / known.length;
      final autoScore = autoRatio != null ? autoRatio * 100 : 50.0;

      // ── 당첨횟수 점수 (10%) ────────────────────────────────
      final freqScore = (rounds.length * 12).clamp(0, 100).toDouble();

      // ── 최근 당첨 흐름 점수 (5%) ──────────────────────────
      final recentWins =
          rounds.where((r) => (targetRound - r) <= 30 && r <= targetRound).length;
      final recentScore = recentWins >= 3 ? 100.0
          : recentWins == 2 ? 70.0
          : recentWins == 1 ? 40.0 : 0.0;

      // ── [신규] 주기 일관성 점수 (10%) ─────────────────────
      // CV(변동계수) = 표준편차 / 평균 → 낮을수록 규칙적
      double consistencyScore = 50.0;
      String consistencyLabel = '';
      if (intervals.length >= 2) {
        final mean = avgInterval;
        final variance = intervals
            .map((d) => (d - mean) * (d - mean))
            .reduce((a, b) => a + b) / intervals.length;
        final cv = mean > 0 ? sqrt(variance) / mean : 1.0;
        consistencyScore = ((1 - cv) * 100).clamp(0, 100).toDouble();
        if (cv < 0.25)       consistencyLabel = '주기 매우 규칙적';
        else if (cv < 0.50)  consistencyLabel = '주기 안정적';
        else if (cv > 0.80)  consistencyLabel = '주기 불규칙';
      }

      // ── [신규] 당첨 추세 점수 (5%) ────────────────────────
      // 최근 절반 간격 vs 이전 절반 간격 비교 → 가속/감속 감지
      double trendScore = 50.0;
      String trendLabel = '';
      if (intervals.length >= 4) {
        final half = intervals.length ~/ 2;
        final recentHalf = intervals.sublist(half);
        final oldHalf    = intervals.sublist(0, half);
        final recentAvg  = recentHalf.reduce((a, b) => a + b) / recentHalf.length;
        final oldAvg     = oldHalf.reduce((a, b) => a + b) / oldHalf.length;
        if (recentAvg < oldAvg * 0.80) {
          trendScore = 90.0;
          trendLabel = '↗ 가속 중';       // 간격 단축 → 핫해지는 중
        } else if (recentAvg < oldAvg * 0.95) {
          trendScore = 70.0;
          trendLabel = '↗ 약 가속';
        } else if (recentAvg > oldAvg * 1.20) {
          trendScore = 15.0;
          trendLabel = '↘ 감속 중';       // 간격 늘어남 → 식어가는 중
        } else if (recentAvg > oldAvg * 1.05) {
          trendScore = 35.0;
          trendLabel = '↘ 약 감속';
        } else {
          trendScore = 55.0;
          trendLabel = '→ 안정';
        }
      }

      // ── [신규] 황금 타이밍 보너스 ─────────────────────────
      // elapsed/avgInterval이 0.8~1.2이면 적중 황금 구간
      final elapsedRatio = avgInterval > 0 ? elapsed / avgInterval : 0.0;
      double timingBonus = 0;
      String timingLabel = '';
      if (elapsedRatio >= 0.8 && elapsedRatio <= 1.2) {
        timingBonus = 35; // 황금 타이밍 → 최우선 상단 배치
        timingLabel = '⏰ 황금 타이밍';
      } else if (elapsedRatio > 1.2 && elapsedRatio <= 1.6) {
        timingBonus = 12;
        timingLabel = '🔔 약 지연';
      } else if (elapsedRatio > 1.6 && elapsedRatio <= 2.0) {
        timingBonus = 0;
        timingLabel = '⚠️ 많이 지연';
      } else if (elapsedRatio > 2.0) {
        timingBonus = -15; // 2배 이상 경과 → 패턴 이탈 가능성, 강하게 감점
        timingLabel = '❌ 패턴 이탈?';
      }

      // ═══════════════════════════════════════════════════════
      // 신규 지표 계산
      // ═══════════════════════════════════════════════════════

      // [1] 단독 1등 비율 (공동 당첨 없이 혼자 맞춘 비율)
      final soloWins = rounds.where((r) => roundWinnerCount[r] == 1).length;
      final soloRatio = soloWins / rounds.length;
      final soloBonus = (soloRatio * 10).clamp(0.0, 10.0);

      // [2] 연속 당첨 공백 최대값 — 역대 최장 공백 초과 여부
      final maxGap = intervals.isEmpty ? 0 : intervals.reduce(max);
      double overdueBonus = 0.0;
      String overdueLabel = '';
      if (maxGap > 0 && elapsed > maxGap) {
        overdueBonus = 15.0;
        overdueLabel = '역대 최장 공백 초과 🔥';
      } else if (maxGap > 0 && elapsed > maxGap * 0.8) {
        overdueBonus = 8.0;
        overdueLabel = '역대 최장 공백 근접';
      }

      // [3] 홀짝 회차 패턴
      String oddEvenLabel = '';
      if (rounds.length >= 5) {
        final oddWins = rounds.where((r) => r % 2 == 1).length;
        final evenWins = rounds.where((r) => r % 2 == 0).length;
        final isOddTarget = targetRound % 2 == 1;
        if (isOddTarget && oddWins / rounds.length >= 0.65) {
          oddEvenLabel = '홀수 회차 유리';
        } else if (!isOddTarget && evenWins / rounds.length >= 0.65) {
          oddEvenLabel = '짝수 회차 유리';
        }
      }

      // [4] 계절성 (분기별 당첨 집중도)
      final targetQ = (roundToMonth(targetRound) - 1) ~/ 3;
      final sameQWins = rounds.where((r) {
        final m = roundToMonth(r);
        return (m - 1) ~/ 3 == targetQ;
      }).length;
      final qRatio = sameQWins / rounds.length;
      String seasonLabel = '';
      if (qRatio >= 0.4) {
        const qLabels = ['1분기(1~3월)', '2분기(4~6월)', '3분기(7~9월)', '4분기(10~12월)'];
        seasonLabel = '${qLabels[targetQ]} ${(qRatio * 100).round()}% 집중';
      }

      // [5] 지역 당첨 포화도 (최근 10회차 기준)
      final regionWins10 = regionRecentWins[region] ?? 0;
      double saturationBonus = 0.0;
      String saturationLabel = '';
      if (regionWins10 == 0) {
        saturationBonus = 12.0;
        saturationLabel = '지역 최근 10회차 미당첨 🌱';
      } else if (regionWins10 >= 3) {
        saturationBonus = -8.0;
        saturationLabel = '지역 최근 포화 ⚠️';
      }

      // [6] 인근 3km 최근 당첨 공백
      final storeLat = (info['latitude'] as num?)?.toDouble();
      final storeLng = (info['longitude'] as num?)?.toDouble();
      double nearbyBonus = 0.0;
      String nearbyLabel = '';
      if (storeLat != null && storeLng != null) {
        int? nearbyLastWin;
        for (final other in storeGeoList) {
          if (other.code == code) continue;
          final dist = Geolocator.distanceBetween(
              storeLat, storeLng, other.lat, other.lng);
          if (dist <= 3000) {
            if (nearbyLastWin == null || other.lastWin > nearbyLastWin) {
              nearbyLastWin = other.lastWin;
            }
          }
        }
        if (nearbyLastWin != null) {
          final nearbyGap = latestRound - nearbyLastWin;
          if (nearbyGap >= 10) {
            nearbyBonus = 8.0;
            nearbyLabel = '인근 3km ${nearbyGap}회차 공백';
          } else if (nearbyGap <= 2) {
            nearbyBonus = -5.0;
            nearbyLabel = '인근 3km 최근 당첨 📍';
          }
        }
      }

      final extraBonus = (soloBonus + overdueBonus + saturationBonus + nearbyBonus)
          .clamp(-30.0, 30.0);

      // ── 엔진 유력 지역 보너스 (Joint Model 예측 지역 일치) ──
      final engineMatch = _addressMatchesEngineRegion(address, engineRegions);
      final engineBonus = engineMatch ? 25.0 : 0.0;

      // ── 명당 연구소 보너스 (Gate 통과 가설 검증 판매점) ──────────
      final mndMatch = mndLiveCodes.contains(code);
      final mndBonus = mndMatch ? 15.0 : 0.0;

      // ── 최종 점수 (가중합 + 타이밍 보너스 + 신규 지표 + 엔진 보너스 + 명당 보너스) ───
      final score = (roundScore    * 0.50 +
                     autoScore     * 0.20 +
                     freqScore     * 0.10 +
                     recentScore   * 0.05 +
                     consistencyScore * 0.10 +
                     trendScore    * 0.05 +
                     timingBonus   +
                     extraBonus    +
                     engineBonus   +
                     mndBonus)
          .round().clamp(0, 200);

      // ── 태그 생성 ─────────────────────────────────────────
      final tags = <String>[];
      if (roundDiff == 0) {
        tags.add('$targetRound회차 유력');
      } else if (roundDiff > 0) {
        tags.add('$predictedRound회차 예상 (+$roundDiff)');
      } else {
        tags.add('$predictedRound회차 (${roundDiff.abs()}회 경과)');
      }
      if (timingLabel.isNotEmpty) tags.add(timingLabel);
      if (trendLabel.isNotEmpty && trendLabel != '→ 안정') tags.add(trendLabel);
      if (consistencyLabel.isNotEmpty && !consistencyLabel.contains('불규칙')) {
        tags.add(consistencyLabel);
      }
      if (autoRatio != null) {
        tags.add('자동구매 ${(autoRatio * 100).round()}%');
      }
      if (rounds.length >= 5) tags.add('1등 다회 당첨점');
      if (recentWins >= 2) tags.add('최근 당첨 흐름 우수');
      // ── 신규 지표 태그 ───────────────────────────────────
      if (soloRatio >= 0.8) tags.add('단독 1등 ${(soloRatio * 100).round()}%');
      else if (soloRatio >= 0.5) tags.add('단독 1등 위주');
      if (overdueLabel.isNotEmpty) tags.add(overdueLabel);
      if (oddEvenLabel.isNotEmpty) tags.add(oddEvenLabel);
      if (seasonLabel.isNotEmpty) tags.add(seasonLabel);
      if (saturationLabel.isNotEmpty) tags.add(saturationLabel);
      if (nearbyLabel.isNotEmpty) tags.add(nearbyLabel);
      if (engineMatch) tags.insert(0, '🔮 엔진 유력 지역');
      if (mndMatch) tags.insert(0, '🏆 명당 연구소 검증');

      result.add(_RegionStore(
        code: code,
        name: storeName,
        address: address,
        region: region,
        firstCount: rounds.length,
        lastWinRound: rounds.last,
        predictedRound: predictedRound,
        roundDiff: roundDiff,
        autoRatio: autoRatio,
        score: score,
        avgIntervalRounds: avgInterval.round(),
        elapsedRatio: elapsedRatio,
        trendLabel: trendLabel,
        consistencyLabel: consistencyLabel,
        latitude: (info['latitude'] as num?)?.toDouble(),
        longitude: (info['longitude'] as num?)?.toDouble(),
        tags: List.unmodifiable(tags),
        engineMatch: engineMatch,
      ));
    }

    result.sort((a, b) => b.score.compareTo(a.score));
    return _geoDedupRegion(result);
  }

  static List<_RegionStore> _geoDedupRegion(List<_RegionStore> sorted) {
    final result = <_RegionStore>[];
    for (final s in sorted) {
      if (s.latitude == null || s.longitude == null) {
        result.add(s);
        continue;
      }
      final hasNearby = result.any((r) {
        if (r.latitude == null || r.longitude == null) return false;
        return Geolocator.distanceBetween(
          s.latitude!, s.longitude!, r.latitude!, r.longitude!,
        ) <= _geoDedupM;
      });
      if (!hasNearby) result.add(s);
    }
    return result;
  }

  Future<void> _loadRegionAndShow() async {
    if (!_regionLoaded) {
      setState(() => _regionLoading = true);
      try {
        final result = await _calcRegionRecommendStores(_selectedType);
        if (mounted) {
          setState(() {
            _regionStores = result;
            _regionLoading = false;
            _regionLoaded = true;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _regionLoading = false);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('오류: $e')));
        }
        return;
      }
    }
    if (!mounted) return;
    _showRegionSheet();
  }

  void _showRegionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RegionRecommendSheet(
        stores: _regionStores,
        round: _latestRound + 1,
        typeLabel: _typeLabels[_selectedType] ?? '',
        initialPosition: _currentPosition,
        onRefresh: () async {
          setState(() => _regionLoaded = false);
          await _loadRegionAndShow();
        },
      ),
    );
  }

  Widget _buildEngineActionBar() {
    if (_latestRound == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFFF3E5F5),
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) =>
                    AdminComprehensivePredictionScreen(
                        targetRound: _latestRound + 1))),
            icon: const Icon(Icons.auto_graph_rounded, size: 15),
            label: Text('${_latestRound + 1}회 종합예측',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF7B1FA2),
              side: const BorderSide(color: Color(0xFF7B1FA2)),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NearbyScreen())),
            icon: const Icon(Icons.location_on_outlined, size: 15),
            label: const Text('주변에서 대안 찾기',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.teal.shade700,
              side: BorderSide(color: Colors.teal.shade700),
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ]),
    );
  }

  /// 종합 추천 판매점 — 지방장 · 연구소 · 엔진 · 제미나이 합산 (로또)
  Widget _buildCombinedPicksCard() {
    return GestureDetector(
      key: const ValueKey('combined_picks_card'),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CombinedStorePicksScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF4527A0), Color(0xFF7E57C2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: const Color(0xFF4527A0).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
            child: const Icon(Icons.hub_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('종합 추천 판매점 (로또)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
              Text('지방장 확률 × 연구소 검증 가설 × 제미나이 가설 · 엔진 순위 함께',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.88))),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
        ]),
      ),
    );
  }

  /// 지방장 238명이 추첨 전에 동결한 다음 회차 추천 판매점 — 시·도 → 시·군·구로 골라 보기
  Widget _buildAgentPicksCard() {
    return GestureDetector(
      key: const ValueKey('agent_next_picks_card'),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentNextPicksScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF00695C), Color(0xFF26A69A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: const Color(0xFF00695C).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
              child: const Icon(Icons.groups_2_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_latestRound > 0 ? '${_latestRound + 1}회 ' : ''}지방장 추천 판매점',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text('전국 시·군·구 지방장이 고른 다음 회차 TOP5 · 어느 지역이든 골라서 확인',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.88))),
              ]),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 26),
          ]),
        ),
      ),
    );
  }

  Widget _buildRegionCard() {
    final regionCount = _regionStores.map((s) => s.region).toSet().length;
    return GestureDetector(
      onTap: _regionLoading ? null : _loadRegionAndShow,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal.shade700, Colors.teal.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.teal.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: _regionLoading
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.travel_explore_rounded,
                        color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '지역에서 추천하는 판매점',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _regionLoaded
                          ? '회차유력 · 자동구매 종합 점수 · $regionCount개 지역'
                              '  →  점수순으로 확인'
                          : '회차+당첨이력 종합 점수 · 눌러서 지역별 확인',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white, size: 26),
            ],
          ),
        ),
      ),
    );
  }

  void _showNearbySheet() {
    if (_stores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('추천 판매점을 먼저 불러오세요')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NearbySheet(
        stores: _stores,
        round: _latestRound + 1, // targetRound = 다음 회차
        typeLabel: _typeLabels[_selectedType] ?? '',
        isAdmin: _isAdmin,
        currentPosition: _currentPosition,
      ),
    );
  }

  Widget _buildNearbyCard() {
    final hasData = _latestRound > 0 && _stores.isNotEmpty;
    final nowCount = _stores.where((s) => s.roundDiff == 0).length;
    // 위치 감시 중 표시
    final posLabel = _currentPosition != null
        ? '  📍 위치 감시 중'
        : '';
    return GestureDetector(
      onTap: _showNearbySheet,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepOrange.shade700, Colors.orange.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.deepOrange.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '현위치에서 추천하는 판매점',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasData
                          ? '${_latestRound + 1}회차 유력 ${_stores.length}곳'
                              '${nowCount > 0 ? ' · 이번회차 $nowCount곳' : ''}'
                              '$posLabel  →  지도앱으로 확인'
                          : '당첨주기 분석 기반 유력 판매지점$posLabel · 지도앱으로 확인',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white, size: 26),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAddress(String addr) => addr.split(' ').take(3).join(' ');

  Color _diffColor(int diff) {
    if (diff == 0) return Colors.deepOrange;
    if (diff > 0) return Colors.blue;
    return Colors.grey;
  }

  String _diffLabel(int diff, int predicted) {
    if (diff == 0) return '$predicted회차\n이번 회차 유력!';
    if (diff > 0) return '$predicted회차\n${diff}회 후 유력';
    return '$predicted회차\n${diff.abs()}회 경과';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        title: Row(children: [
          const Flexible(child: Text('추천 판매점',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.white, fontSize: 17),
              overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.amber.shade600,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('엔진 v$kRpaActiveModelVersion',
                style: TextStyle(fontSize: 11, color: Colors.white,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isAdmin && _currentPosition != null)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.gps_fixed, color: Colors.white, size: 18),
            ),
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _load),
        ],
      ),
      body: _wrapWithTopTabs(Column(
        children: [
          _buildCombinedPicksCard(),
          _buildAgentPicksCard(),
          _buildNearbyCard(),
          _buildRegionCard(),
          _buildEngineActionBar(),
          Container(
            color: Colors.deepOrange.shade50,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: _typeLabels.entries.map((e) {
                final selected = _selectedType == e.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: selected,
                    selectedColor: Colors.deepOrange,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) {
                      if (!selected) {
                        setState(() {
                          _selectedType = e.key;
                          _regionLoaded = false;
                          _regionStores = [];
                        });
                        _load();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.orange.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '현재 $_latestRound회차 기준 · 5회 이상 1등 당첨점 중 예측 당첨 회차가 ±${_window}회 이내인 판매점',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade800),
                      ),
                    ),
                  ],
                ),
                if (_latestRound > 0) ...[
                  const SizedBox(height: 6),
                  EngineReflectionBadge(
                    trainingRound: _latestRound,
                    targetRound: _latestRound + 1,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
          // ── 판매점 검색바 ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              decoration: InputDecoration(
                hintText: '판매점명 / 주소 검색',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.orange.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.orange.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.deepOrange, width: 1.5),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Builder(builder: (_) {
                    final displayed = _searchQuery.isEmpty
                        ? _stores
                        : _stores.where((s) =>
                            s.name.contains(_searchQuery) ||
                            s.address.contains(_searchQuery)).toList();
                    if (displayed.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? '\'$_searchQuery\' 검색 결과 없음'
                                  : '해당 회차 유력 판매점이 없습니다',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: displayed.length,
                        itemBuilder: (ctx, i) => _buildCard(i, displayed[i]),
                      ),
                    );
                  }),
          ),
        ],
      )),
    );
  }

  // ── 구매방법 추천 헬퍼 ──────────────────────────────────────

  Future<void> _openMapDirect(String address) async {
    final query = Uri.encodeComponent(address);
    final url = 'https://map.naver.com/v5/search/$query';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openStoreDetail(BuildContext ctx, _RecommendStore s) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RecommendStoreDetailSheet(
        store: s,
        round: _latestRound + 1,
        position: _currentPosition,
      ),
    );
  }

  List<({String label, Color color})> _recommendPurchaseMethod(double? autoRatio) {
    if (autoRatio == null) return [(label: '반자동', color: Colors.blue)];
    if (autoRatio >= 0.5) return [(label: '자동', color: Colors.green.shade700)];
    if (autoRatio >= 0.3) return [
      (label: '자동', color: Colors.green.shade700),
      (label: '반자동', color: Colors.blue),
    ];
    if (autoRatio >= 0.15) return [(label: '반자동', color: Colors.blue)];
    return [
      (label: '반자동', color: Colors.blue),
      (label: '수동', color: Colors.deepOrange),
    ];
  }

  Widget _buildCard(int index, _RecommendStore s) {
    final color = _diffColor(s.roundDiff);
    final label = _diffLabel(s.roundDiff, s.predictedRound);
    final isNow = s.roundDiff == 0;
    final methods = _recommendPurchaseMethod(s.autoRatio);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: color.withValues(alpha: 0.5), width: isNow ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openStoreDetail(context, s),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: index < 3 ? Colors.deepOrange : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('${index + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: index < 3 ? Colors.white : Colors.grey.shade700,
                          )),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(_formatAddress(s.address),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _chip('1등 ${s.firstCount}회', Colors.purple),
                            _chip('평균 ${s.months}개월 주기', Colors.blue),
                            _chip('마지막 ${s.lastWinRound}회차', Colors.teal),
                            _chip('${s.elapsed}회차 경과', Colors.orange),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isNow
                          ? Colors.deepOrange
                          : color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color, width: isNow ? 0 : 1),
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: isNow ? Colors.white : color,
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ...methods.map((m) => Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: m.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: m.color.withValues(alpha: 0.4)),
                    ),
                    child: Text(m.label,
                        style: TextStyle(
                            fontSize: 11,
                            color: m.color,
                            fontWeight: FontWeight.w700)),
                  )),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _openMapDirect(s.address),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.map_outlined, size: 13, color: Colors.green.shade700),
                        const SizedBox(width: 3),
                        Text('지도',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 관리자 전용 상단 탭: [기존 추천] 은 기존 body 그대로, [경로 기반 추천] 은 신규 위젯.
  /// 비관리자는 탭 없이 기존 body 만 본다 (기존 로직·위젯 변경 없음).
  Widget _wrapWithTopTabs(Widget legacyBody) {
    if (!_isAdmin) return legacyBody;
    return Column(
      children: [
        Container(
          color: Colors.deepOrange.shade700,
          child: Row(
            children: [
              for (final entry in const [
                (0, '기존 추천'),
                (1, '지역 추천'),
                (2, '현 위치 추천'),
                (3, '경로 기반 추천'),
                (4, '전국 종합'),
              ])
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _topTab = entry.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _topTab == entry.$1 ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        entry.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: _topTab == entry.$1 ? FontWeight.w800 : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (_topTab) {
            1 => AdminRegionRecommendContent(
                key: ValueKey('region_${_regionTabRegionId ?? ''}'),
                initialRegionId: _regionTabRegionId,
              ),
            2 => AdminLocationRecommendContent(
                onOpenRegion: (regionId) => setState(() {
                  _regionTabRegionId = regionId;
                  _topTab = 1;
                }),
              ),
            3 => const AdminRouteRecommendContent(),
            4 => const AgentCentralView(),
            _ => legacyBody,
          },
        ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 현위치 추천 판매점 바텀시트
// ════════════════════════════════════════════════════════════
class _NearbySheet extends StatefulWidget {
  final List<_RecommendStore> stores;
  final int round;
  final String typeLabel;
  final bool isAdmin;
  final Position? currentPosition; // 상위 화면에서 이미 취득한 위치

  const _NearbySheet({
    required this.stores,
    required this.round,
    required this.typeLabel,
    required this.isAdmin,
    this.currentPosition,
  });

  @override
  State<_NearbySheet> createState() => _NearbySheetState();
}

class _NearbySheetState extends State<_NearbySheet> {
  Position? _position;
  bool _locating = false;
  static const double _filterM = 600.0;       // 600m 필터
  static const double _filterKm = _filterM / 1000.0; // 0.6km

  @override
  void initState() {
    super.initState();
    if (widget.currentPosition != null) {
      _position = widget.currentPosition;
    } else {
      _getLocation();
    }
  }

  Future<void> _getLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (mounted) setState(() => _locating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (!mounted) return;
      setState(() { _position = pos; _locating = false; });
      // 관리자 모드 → 주변 유력 판매점 즉시 알림
      if (widget.isAdmin && mounted) {
        final nearby = _nearbyStores();
        if (nearby.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.deepOrange.shade700,
              duration: const Duration(seconds: 5),
              content: Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '📍 주변 ${widget.round}회차 유력 판매점 ${nearby.length}곳 발견!',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  double? _distanceTo(_RecommendStore s) {
    if (_position == null || s.latitude == null || s.longitude == null) {
      return null;
    }
    return Geolocator.distanceBetween(
          _position!.latitude, _position!.longitude,
          s.latitude!, s.longitude!) /
        1000.0; // km
  }

  /// 좌표가 확인된 판매점 중 실제 600m 이내인 것만 반환
  List<_RecommendStore> _nearbyStores() {
    if (_position == null) return [];
    return widget.stores.where((s) {
      final d = _distanceTo(s);
      return d != null && d <= _filterKm;
    }).toList();
  }

  List<_RecommendStore> _filteredStores() {
    if (_position == null) return widget.stores;
    return widget.stores.where((s) {
      final d = _distanceTo(s);
      return d == null || d <= _filterKm;
    }).toList();
  }

  Future<void> _openMap(BuildContext ctx, _RecommendStore s) async {
    final choice = await showDialog<String>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(s.name,
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Text(s.address, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'naver'),
            child: const Text('네이버 지도'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'kakao'),
            child: const Text('카카오 지도'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final query = Uri.encodeComponent(s.address);
    final url = choice == 'naver'
        ? 'https://map.naver.com/v5/search/$query'
        : 'https://map.kakao.com/link/search/$query';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // 판매점 탭 → 지도 + 엔진 추천번호 bottom sheet
  void _showStoreDetail(BuildContext ctx, _RecommendStore s) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RecommendStoreDetailSheet(
        store: s,
        round: widget.round,
        position: _position,
      ),
    );
  }

  Widget _buildLocationBar() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _locating ? null : _getLocation,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _locating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.my_location,
                          color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    _locating ? '탐색 중...' : '현위치',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _position != null
                  ? '${_position!.latitude.toStringAsFixed(4)}, ${_position!.longitude.toStringAsFixed(4)}'
                  : _locating
                      ? 'GPS 확인 중...'
                      : '위치 정보 없음',
              style: TextStyle(
                fontSize: 11,
                color: _position != null
                    ? Colors.blue.shade700
                    : Colors.grey.shade500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (_position == null) return const SizedBox.shrink();
    final center = LatLng(_position!.latitude, _position!.longitude);
    final storeMarkers = widget.stores
        .where((s) => s.latitude != null && s.longitude != null)
        .map((s) => Marker(
              point: LatLng(s.latitude!, s.longitude!),
              width: 24,
              height: 24,
              child: Icon(
                Icons.store_rounded,
                color: s.roundDiff == 0 ? Colors.deepOrange : Colors.purple,
                size: 20,
              ),
            ))
        .toList();

    return SizedBox(
      height: 160,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: 15, // 600m 기준으로 확대
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.hicl.lotto',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: center,
                width: 36,
                height: 36,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.person_pin_circle,
                      color: Colors.white, size: 20),
                ),
              ),
              ...storeMarkers,
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStores();
    final nearbyStores = _nearbyStores();
    final nearbyIds = nearbyStores.map((s) => s.code).toSet();
    // round는 이미 targetRound(latestRound+1) — roundDiff==0이 "이번 회차"
    // 주변 섹션에 이미 표시된 판매점은 하위 섹션에서 제외
    final nowStores = filtered.where((s) => s.roundDiff == 0 && !nearbyIds.contains(s.code)).toList();
    final otherStores = filtered.where((s) => s.roundDiff != 0 && !nearbyIds.contains(s.code)).toList();
    final nextRound = widget.round; // 이미 다음 회차

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.70,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Column(
        children: [
          // 핸들
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded,
                    color: Colors.deepOrange, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$nextRound회차 ${widget.typeLabel} 유력 판매지점',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          // 현위치 바
          _buildLocationBar(),
          // 지도
          _buildMap(),
          // 필터 정보
          if (_position != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  Icon(Icons.filter_list,
                      size: 14, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Text(
                    '${_filterM.toInt()}m 이내 ${filtered.length}곳 표시'
                    '${filtered.length < widget.stores.length ? ' (전체 ${widget.stores.length}곳 중)' : ''}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.blue.shade700),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          // 목록
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.only(bottom: 20),
              children: [
                // ── 주변 유력당첨지점 (위치 확인 + 600m 이내만) ────────
                if (nearbyStores.isNotEmpty) ...[
                  _sectionHeader(
                    '📍 주변 $nextRound회차 유력당첨지점',
                    Colors.deepOrange.shade50,
                    Colors.deepOrange,
                  ),
                  ...nearbyStores.map((s) => _buildNearbyTaggedTile(context, s)),
                  const Divider(height: 1),
                ],
                // ── 이번 회차 유력 (주변 제외) ───────────────────────
                if (nowStores.isNotEmpty) ...[
                  _sectionHeader('🔥 이번 $nextRound회차 유력',
                      Colors.deepOrange.shade50, Colors.deepOrange),
                  ...nowStores.map((s) => _storeTile(context, s)),
                ],
                if (otherStores.isNotEmpty) ...[
                  _sectionHeader('📌 근접 회차 유력',
                      Colors.blue.shade50, Colors.blue.shade700),
                  ...otherStores.map((s) => _storeTile(context, s)),
                ],
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        '600m 내 유력 판매점이 없습니다\n위치를 이동하거나 필터를 확인하세요',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bgColor,
      child: Text(title,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: textColor)),
    );
  }

  Widget _storeTile(BuildContext context, _RecommendStore s) {
    final isNow = s.roundDiff == 0;
    final dist = _distanceTo(s);
    final nextRound = widget.round; // 이미 targetRound

    String roundChipLabel;
    Color roundChipColor;
    if (s.roundDiff == 0) {
      roundChipLabel = '이번 $nextRound회차!';
      roundChipColor = Colors.deepOrange;
    } else if (s.roundDiff > 0) {
      roundChipLabel = '+${s.roundDiff}회 후 (${s.predictedRound}회차)';
      roundChipColor = Colors.blue;
    } else {
      roundChipLabel = '${s.roundDiff.abs()}회 경과 (${s.predictedRound}회차)';
      roundChipColor = Colors.grey;
    }

    String? distLabel;
    if (dist != null) {
      distLabel = dist < 1
          ? '${(dist * 1000).round()}m'
          : '${dist.toStringAsFixed(1)}km';
    }

    return InkWell(
      onTap: () => _showStoreDetail(context, s),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isNow
                    ? Colors.deepOrange.shade50
                    : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.store_rounded,
                color: isNow ? Colors.deepOrange : Colors.grey.shade600,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(s.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _miniChip('1등 ${s.firstCount}회', Colors.purple),
                      _miniChip('평균 ${s.months}개월', Colors.teal),
                      _miniChip(roundChipLabel, roundChipColor),
                      if (distLabel != null)
                        _miniChip(distLabel, Colors.indigo),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.map_outlined, color: Colors.blue, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600)),
    );
  }

  // ── 주변 유력당첨지점 타일 (태그 포함) ──────────────────────────
  Widget _buildNearbyTaggedTile(BuildContext context, _RecommendStore s) {
    final dist = _distanceTo(s);
    String? distLabel;
    if (dist != null) {
      distLabel = dist < 1
          ? '${(dist * 1000).round()}m'
          : '${dist.toStringAsFixed(1)}km';
    }

    return InkWell(
      onTap: () => _showStoreDetail(context, s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.deepOrange.shade50,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.deepOrange.shade200),
              ),
              child: const Icon(Icons.store_rounded,
                  color: Colors.deepOrange, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(s.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                      if (distLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(distLabel,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.indigo.shade700,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(s.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: s.tags.map(_buildTagChip).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.map_outlined, color: Colors.blue, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildTagChip(String tag) {
    final Color color;
    if (tag.contains('엔진 유력 지역')) {
      color = Colors.deepPurple;
    } else if (tag.contains('유력당첨점')) {
      color = Colors.deepOrange;
    } else if (tag.contains('자동 당첨주기')) {
      color = Colors.blue.shade700;
    } else if (tag.contains('수동 당첨주기')) {
      color = Colors.purple;
    } else if (tag.contains('반자동')) {
      color = Colors.teal;
    } else if (tag.contains('최근 당첨 흐름')) {
      color = Colors.green.shade700;
    } else if (tag.contains('홀수') || tag.contains('짝수')) {
      color = Colors.amber.shade800;
    } else {
      color = Colors.grey.shade600;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        tag,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RecommendStore {
  final String code;
  final String name;
  final String address;
  final int firstCount;
  final double avgInterval;
  final int months;
  final int lastWinRound;
  final int elapsed;
  final int latestRound;
  final int predictedRound;
  final int roundDiff;
  final double? latitude;
  final double? longitude;
  final List<String> tags;
  final double? autoRatio; // 자동구매 비율 (0.0~1.0)

  const _RecommendStore({
    required this.code,
    required this.name,
    required this.address,
    required this.firstCount,
    required this.avgInterval,
    required this.months,
    required this.lastWinRound,
    required this.elapsed,
    required this.latestRound,
    required this.predictedRound,
    required this.roundDiff,
    this.latitude,
    this.longitude,
    this.tags = const [],
    this.autoRatio,
  });
}

// ════════════════════════════════════════════════════════════
// 지역에서 추천하는 판매점 — 데이터 모델
// ════════════════════════════════════════════════════════════
class _WinRecord {
  final int round;
  final String purchaseMethod;
  const _WinRecord(this.round, this.purchaseMethod);
}

class _RegionStore {
  final String code;
  final String name;
  final String address;
  final String region;
  final int firstCount;
  final int lastWinRound;
  final int predictedRound;
  final int roundDiff;
  final double? autoRatio;
  final int score;
  // ── 패턴 분석 추가 필드 ──────────────────────────────────
  final int avgIntervalRounds;   // 평균 당첨 간격 (회차 단위)
  final double elapsedRatio;     // elapsed / avgInterval (1.0 = 평균 타이밍)
  final String trendLabel;       // ↗ 가속 중 / → 안정 / ↘ 감속 중
  final String consistencyLabel; // 주기 매우 규칙적 / 안정적 / 불규칙
  final double? latitude;
  final double? longitude;
  final List<String> tags;
  final bool engineMatch; // Joint Model 유력 지역 일치 여부

  const _RegionStore({
    required this.code,
    required this.name,
    required this.address,
    required this.region,
    required this.firstCount,
    required this.lastWinRound,
    required this.predictedRound,
    required this.roundDiff,
    required this.autoRatio,
    required this.score,
    this.avgIntervalRounds = 0,
    this.elapsedRatio = 0,
    this.trendLabel = '',
    this.consistencyLabel = '',
    this.latitude,
    this.longitude,
    this.tags = const [],
    this.engineMatch = false,
  });
}

// ════════════════════════════════════════════════════════════
// 지역에서 추천하는 판매점 바텀시트
// ════════════════════════════════════════════════════════════
class _RegionRecommendSheet extends StatefulWidget {
  final List<_RegionStore> stores;
  final int round; // latestRound + 1
  final String typeLabel;
  final Future<void> Function() onRefresh;
  final Position? initialPosition;

  const _RegionRecommendSheet({
    required this.stores,
    required this.round,
    required this.typeLabel,
    required this.onRefresh,
    this.initialPosition,
  });

  @override
  State<_RegionRecommendSheet> createState() => _RegionRecommendSheetState();
}

// 필터 종류
enum _StoreFilter { all, thisRound, notYetWon }

class _RegionRecommendSheetState extends State<_RegionRecommendSheet> {
  String? _selectedRegion;
  Position? _position;
  bool _locating = false;
  bool _nearbyMode = false;
  String? _myRegion;        // 현재위치로 감지된 내 지역 (예: "충남 천안시")
  _StoreFilter _filter = _StoreFilter.all;

  // 번호 추천 캐시

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      _position = widget.initialPosition;
      // 초기 위치가 있으면 내 지역도 감지
      _myRegion = _detectMyRegion(widget.initialPosition!);
    }
  }

  // ── 가장 가까운 판매점의 region으로 내 지역 감지 ────────────
  // 역지오코딩 없이 가장 가까운 판매점의 region 사용
  String? _detectMyRegion(Position pos) {
    final withCoord = widget.stores
        .where((s) => s.latitude != null && s.longitude != null)
        .toList();
    if (withCoord.isEmpty) return null;

    // 가장 가까운 판매점의 region 반환
    withCoord.sort((a, b) {
      final da = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, a.latitude!, a.longitude!);
      final db = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, b.latitude!, b.longitude!);
      return da.compareTo(db);
    });
    return withCoord.first.region;
  }

  // ── 위치 취득 ─────────────────────────────────────────────
  Future<void> _getLocation() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        if (mounted) setState(() => _locating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best);
      if (!mounted) return;
      final region = _detectMyRegion(pos);
      setState(() {
        _position = pos;
        _locating = false;
        _nearbyMode = true;
        _myRegion = region;
        _selectedRegion = null;
      });
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── 거리 계산 ─────────────────────────────────────────────
  double? _distKm(_RegionStore s) {
    if (_position == null || s.latitude == null || s.longitude == null) return null;
    return Geolocator.distanceBetween(
          _position!.latitude, _position!.longitude, s.latitude!, s.longitude!) /
        1000.0;
  }

  // ── 주차장 판별 ──────────────────────────────────────────
  bool _hasParking(_RegionStore s) =>
      s.address.contains('주차') || s.name.contains('주차') ||
      s.tags.any((t) => t.contains('주차'));

  // ── 내 지역 판매점 목록 ────────────────────────────────────
  List<_RegionStore> get _myRegionStores {
    if (_myRegion == null) return widget.stores;
    return widget.stores.where((s) => s.region == _myRegion).toList();
  }

  // ── 복합 정렬 점수 (지역 내 순위용) ───────────────────────
  // 이번회차 유력 > 미당첨 나올만 > 최신당첨 배제 > 기본점수
  double _sortScore(_RegionStore s) {
    double bonus = s.score.toDouble();
    final latestRound = widget.round - 1;
    final sinceLastWin = latestRound - s.lastWinRound;

    // ① 엔진 유력 지역 (Joint Model 예측 일치) → 가산
    if (s.engineMatch) bonus += 20;

    // ② 이번 회차 유력 → 최우선
    if (s.roundDiff == 0) {
      bonus += 50;
    }
    // ③ 패턴상 나와야 하는데 아직 안 나온 판매점 (미당첨 중, 오버듀)
    else if (s.roundDiff > 0 && s.roundDiff <= 5 && sinceLastWin > 5) {
      bonus += 25;
    }
    // ③ 패턴과 멀어질수록 점차 가산 감소
    else if (s.roundDiff > 5) {
      bonus += (10 - s.roundDiff).clamp(0, 10).toDouble();
    }

    // ④ 최신 당첨 배제: 방금 당첨됐으면 다음 사이클까지 제외
    if (sinceLastWin <= 2) {
      bonus -= 40; // 직전 2회 이내 당첨 → 강하게 배제
    } else if (sinceLastWin <= 5) {
      bonus -= 20;
    } else if (sinceLastWin <= 10) {
      bonus -= 5;
    }

    // ⑤ 위치 기반일 때 지역 내 거리 미세 가산 (최대 +10)
    if (_nearbyMode) {
      final d = _distKm(s);
      if (d != null) bonus += (10.0 - d * 2).clamp(0.0, 10.0);
    }

    return bonus;
  }

  // ── 필터 적용 ─────────────────────────────────────────────
  List<_RegionStore> _applyFilter(List<_RegionStore> list) {
    final latestRound = widget.round - 1;
    switch (_filter) {
      case _StoreFilter.thisRound:
        return list.where((s) => s.roundDiff == 0).toList();
      case _StoreFilter.notYetWon:
        return list.where((s) =>
            s.roundDiff != 0 && (latestRound - s.lastWinRound) > 5).toList();
      case _StoreFilter.all:
        return list;
    }
  }

  // ── 정렬된 전체 목록 ──────────────────────────────────────
  List<_RegionStore> get _sortedStores {
    final list = List<_RegionStore>.from(widget.stores);
    list.sort((a, b) => _sortScore(b).compareTo(_sortScore(a)));
    return list;
  }

  Map<String, List<_RegionStore>> get _grouped {
    final sorted = _sortedStores;
    final map = <String, List<_RegionStore>>{};
    for (final s in sorted) {
      map.putIfAbsent(s.region, () => []).add(s);
    }
    return map;
  }

  List<String> get _regionsSortedByTopScore {
    final grouped = _grouped;
    final regions = grouped.keys.toList();
    regions.sort((a, b) {
      final sa = _sortScore(grouped[a]!.first);
      final sb = _sortScore(grouped[b]!.first);
      return sb.compareTo(sa);
    });
    return regions;
  }

  Future<void> _openMap(BuildContext ctx, _RegionStore s) async {
    final choice = await showDialog<String>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(s.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Text(s.address, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'naver'), child: const Text('네이버 지도')),
          TextButton(onPressed: () => Navigator.pop(c, 'kakao'), child: const Text('카카오 지도')),
        ],
      ),
    );
    if (choice == null) return;
    final query = Uri.encodeComponent(s.address);
    final url = choice == 'naver'
        ? 'https://map.naver.com/v5/search/$query'
        : 'https://map.kakao.com/link/search/$query';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── 번호 추천 시트 (rank 0~2) ────────────────────────────────
  Future<void> _showNumberSheet(BuildContext ctx, _RegionStore store, int rank) async {
    // 로딩 중 표시
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NumberRecommendSheet(
        store: store,
        rank: rank,
        round: widget.round,
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 110) return Colors.deepOrange;
    if (score >= 90)  return Colors.teal;
    if (score >= 60)  return Colors.blue;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final regions = _regionsSortedByTopScore;
    final displayRegions = _selectedRegion == null ? regions : [_selectedRegion!];
    final sorted = _sortedStores;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.80,
      maxChildSize: 0.96,
      builder: (_, ctrl) => Column(
        children: [
          // 핸들
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),

          // ── 헤더 ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
            child: Row(children: [
              const Icon(Icons.travel_explore_rounded, color: Colors.teal, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text('지역별 ${widget.typeLabel} 추천 판매점',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              // 현재위치 버튼
              _buildLocationButton(),
              // 지도에서 위치 선택 버튼
              _buildMapPickButton(),
              // 새로고침
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () async {
                  await widget.onRefresh();
                  if (mounted) Navigator.of(context).pop();
                },
              ),
            ]),
          ),

          // ── 내 지역 배너 (위치 감지됐을 때) ─────────────────
          if (_nearbyMode && _myRegion != null)
            _buildMyRegionBanner()
          else if (_locating)
            _buildLocationBar(),

          // ── 필터 칩 ───────────────────────────────────────
          _buildFilterChips(),

          // ── 지역 탭 (일반 모드만) ──────────────────────────
          if (!_nearbyMode && regions.length > 1)
            _buildRegionTabs(regions, grouped),

          // ── 점수 기준 안내 ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.teal.shade50,
            child: Row(children: [
              Icon(Icons.info_outline, size: 13, color: Colors.teal.shade800),
              const SizedBox(width: 5),
              Expanded(child: Text(
                _nearbyMode
                    ? '순위: 🔥이번회차유력 > ⏳미당첨 나올만 > 최신당첨 배제 > 당첨패턴'
                    : '회차유력(60%)+자동구매(25%)+당첨횟수(10%)+최근흐름(5%) — 최신당첨점 후순위',
                style: TextStyle(fontSize: 10, color: Colors.teal.shade800),
              )),
            ]),
          ),

          const Divider(height: 1),

          // ── 목록 ──────────────────────────────────────────
          Expanded(
            child: widget.stores.isEmpty
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('분석 가능한 당첨이력이 부족합니다\n(2회 이상 1등 당첨 판매점 필요)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500)),
                  ))
                : ListView(
                    controller: ctrl,
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      // 지방장 다음 회차 추천 (선택 지역 또는 내 위치 지역)
                      if (_nearbyMode && _myRegion != null)
                        AgentPicksForRegion(key: ValueKey('picks_${_myRegion!}'), region: _myRegion!)
                      else if (_selectedRegion != null)
                        AgentPicksForRegion(key: ValueKey('picks_${_selectedRegion!}'), region: _selectedRegion!),
                      ...(_nearbyMode
                          ? _buildMyRegionList(context)
                          : _buildRegionList(context, _applyFilter(sorted), grouped, displayRegions)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── 현재위치 버튼 ─────────────────────────────────────────
  Widget _buildLocationButton() {
    return GestureDetector(
      onTap: _locating ? null : (_nearbyMode
          ? () => setState(() { _nearbyMode = false; })
          : _getLocation),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _nearbyMode ? Colors.teal : Colors.teal.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.teal.shade300),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _locating
              ? const SizedBox(width: 13, height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal))
              : Icon(Icons.my_location_rounded, size: 14,
                  color: _nearbyMode ? Colors.white : Colors.teal),
          const SizedBox(width: 5),
          Text(_locating ? '탐색 중' : (_nearbyMode ? '위치 ON' : '현재위치'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: _nearbyMode ? Colors.white : Colors.teal)),
        ]),
      ),
    );
  }

  // ── 지도에서 위치 선택 버튼 ──────────────────────────────────
  Widget _buildMapPickButton() {
    return GestureDetector(
      onTap: _pickLocationFromMap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.indigo.shade300),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.map_rounded, size: 14, color: Colors.indigo.shade700),
          const SizedBox(width: 5),
          Text('지도선택', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: Colors.indigo.shade700,
          )),
        ]),
      ),
    );
  }

  Future<void> _pickLocationFromMap() async {
    final initial = _position != null
        ? LatLng(_position!.latitude, _position!.longitude)
        : const LatLng(36.5, 127.9); // 한반도 중심 기본값
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => _MapPickerScreen(initial: initial),
      ),
    );
    if (picked == null || !mounted) return;
    final fakePos = Position(
      latitude: picked.latitude,
      longitude: picked.longitude,
      timestamp: DateTime.now(),
      accuracy: 0, altitude: 0, altitudeAccuracy: 0,
      heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
    );
    final region = _detectMyRegion(fakePos);
    setState(() {
      _position = fakePos;
      _myRegion = region;
      _nearbyMode = true;
    });
  }

  // ── GPS 탐색 중 바 ────────────────────────────────────────
  Widget _buildLocationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.shade50,
      child: Row(children: [
        const SizedBox(width: 13, height: 13,
            child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Text('내 위치 확인 중...', style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
      ]),
    );
  }

  // ── 내 지역 배너 ──────────────────────────────────────────
  Widget _buildMyRegionBanner() {
    final regionStores = _myRegionStores;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade700, Colors.teal.shade500],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
      ),
      child: Row(children: [
        const Icon(Icons.location_on_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('📍 내 지역: $_myRegion',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
          Text('${regionStores.length}개 판매점 · 조건별 최적 순위',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
        ])),
        GestureDetector(
          onTap: () => setState(() { _nearbyMode = false; _myRegion = null; }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12)),
            child: const Text('해제', style: TextStyle(fontSize: 11, color: Colors.white,
                fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  // ── 필터 칩 ──────────────────────────────────────────────
  Widget _buildFilterChips() {
    const filters = [
      (_StoreFilter.all,       '전체'),
      (_StoreFilter.thisRound, '🔥 이번회차 유력'),
      (_StoreFilter.notYetWon, '⏳ 아직 미당첨'),
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: filters.map((f) {
          final sel = _filter == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => setState(() => _filter = f.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: sel ? Colors.deepOrange : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? Colors.deepOrange : Colors.grey.shade300),
                ),
                child: Text(f.$2, style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : Colors.grey.shade700)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 지역 탭 ──────────────────────────────────────────────
  Widget _buildRegionTabs(List<String> regions, Map<String, List<_RegionStore>> grouped) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: const Text('전체'),
              selected: _selectedRegion == null,
              selectedColor: Colors.teal,
              labelStyle: TextStyle(
                color: _selectedRegion == null ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600, fontSize: 12,
              ),
              onSelected: (_) => setState(() => _selectedRegion = null),
            ),
          ),
          ...regions.map((r) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('$r (${grouped[r]!.length})'),
              selected: _selectedRegion == r,
              selectedColor: Colors.teal,
              labelStyle: TextStyle(
                color: _selectedRegion == r ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600, fontSize: 12,
              ),
              onSelected: (_) => setState(() => _selectedRegion = r),
            ),
          )),
        ],
      ),
    );
  }

  // ── 내 지역 판매점 목록 (현재위치 모드) ───────────────────
  List<Widget> _buildMyRegionList(BuildContext context) {
    final regionStores = _myRegionStores;
    final filtered = _applyFilter(regionStores);

    // 조건별 정렬
    final sorted = List<_RegionStore>.from(filtered)
      ..sort((a, b) => _sortScore(b).compareTo(_sortScore(a)));

    if (sorted.isEmpty) {
      return [Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(
          '$_myRegion 지역에서 조건에 맞는 판매점이 없습니다\n필터를 변경해 보세요',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500))),
      )];
    }

    final latestRound = widget.round - 1;

    // ① 이번 회차 유력
    final thisRound = sorted.where((s) => s.roundDiff == 0).toList();
    // ② 미당첨 중 나올만한 (오버듀)
    final overdue = sorted.where((s) =>
        s.roundDiff != 0 &&
        s.roundDiff <= 5 &&
        (latestRound - s.lastWinRound) > 5).toList();
    // ③ 나머지 (최신당첨 배제 포함)
    final thisRoundCodes = thisRound.map((s) => s.code).toSet();
    final overdueCodes   = overdue.map((s) => s.code).toSet();
    final others = sorted.where(
        (s) => !thisRoundCodes.contains(s.code) && !overdueCodes.contains(s.code)).toList();

    final widgets = <Widget>[];

    if (thisRound.isNotEmpty) {
      widgets.add(_sectionHeader('🔥 이번 ${widget.round}회차 유력', thisRound.length, highlight: true));
      widgets.addAll(thisRound.asMap().entries.map((e) => _storeTile(context, e.value, e.key)));
      widgets.add(const Divider(height: 1, thickness: 4, color: Color(0xFFF5F5F5)));
    }

    if (overdue.isNotEmpty) {
      widgets.add(_sectionHeader('⏳ 나올만한 판매점 (미당첨 중)', overdue.length));
      widgets.addAll(overdue.asMap().entries.map((e) => _storeTile(context, e.value, e.key)));
      widgets.add(const Divider(height: 1, thickness: 4, color: Color(0xFFF5F5F5)));
    }

    if (others.isNotEmpty) {
      widgets.add(_sectionHeader('📋 기타 후보', others.length));
      widgets.addAll(others.take(10).toList().asMap().entries.map(
          (e) => _storeTile(context, e.value, e.key)));
    }

    return widgets;
  }

  // ── 지역별 목록 ───────────────────────────────────────────
  List<Widget> _buildRegionList(
      BuildContext context, List<_RegionStore> filtered,
      Map<String, List<_RegionStore>> grouped, List<String> displayRegions) {
    final widgets = <Widget>[];

    // 전체 TOP 10
    if (_selectedRegion == null && filtered.isNotEmpty) {
      final top = filtered.take(10).toList();
      widgets.add(_sectionHeader('🏆 전체 종합 TOP 10 (회차유력 우선)', top.length, highlight: true));
      widgets.addAll(top.asMap().entries.map(
          (e) => _storeTile(context, e.value, e.key, showRegionTag: true)));
      widgets.add(const Divider(height: 1, thickness: 6));
    }

    for (final region in displayRegions) {
      final regionList = _applyFilter(grouped[region] ?? []);
      if (regionList.isEmpty) continue;
      widgets.add(_sectionHeader(region, regionList.length));
      widgets.addAll(regionList.take(8).toList().asMap().entries.map(
          (e) => _storeTile(context, e.value, e.key)));
    }

    if (widgets.isEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text('조건에 맞는 판매점이 없습니다',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500))),
      ));
    }
    return widgets;
  }

  Widget _sectionHeader(String title, int count, {bool highlight = false}) {
    final bg = highlight ? Colors.amber.shade50 : Colors.teal.shade50;
    final fg = highlight ? Colors.amber.shade900 : Colors.teal.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bg,
      child: Row(children: [
        Icon(highlight ? Icons.emoji_events_rounded : Icons.place_rounded, size: 14, color: fg),
        const SizedBox(width: 6),
        Text(highlight ? title : '$title  ·  $count곳',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: fg)),
      ]),
    );
  }

  Widget _storeTile(BuildContext context, _RegionStore s, int rank,
      {bool showRegionTag = false}) {
    final dynScore = _sortScore(s);
    final color = _scoreColor(dynScore);
    final dist = _distKm(s);
    final hasParking = _hasParking(s);
    final latestRound = widget.round - 1;
    final sinceLastWin = latestRound - s.lastWinRound;

    String? distLabel;
    if (dist != null) {
      distLabel = dist < 1 ? '${(dist * 1000).round()}m' : '${dist.toStringAsFixed(1)}km';
    }

    // 최신 당첨 경과 상태
    String winStatusLabel;
    Color winStatusColor;
    if (s.roundDiff == 0) {
      winStatusLabel = '🔥 이번회차 유력!';
      winStatusColor = Colors.deepOrange;
    } else if (sinceLastWin <= 2) {
      winStatusLabel = '최근 당첨 (${sinceLastWin}회 전)';
      winStatusColor = Colors.grey;
    } else if (s.roundDiff > 0) {
      winStatusLabel = '⏳ 미당첨 중 (+${s.roundDiff}회)';
      winStatusColor = Colors.blue;
    } else {
      winStatusLabel = '${s.roundDiff.abs()}회 경과';
      winStatusColor = Colors.grey.shade600;
    }

    return InkWell(
      onTap: () => rank < 3
          ? _showNumberSheet(context, s, rank)
          : _openMap(context, s),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
          color: s.roundDiff == 0 ? Colors.deepOrange.shade50.withValues(alpha: 0.4) : null,
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 순위 + 점수 원
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${rank + 1}위', style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
                Text(dynScore.toStringAsFixed(0),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
              ],
            )),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 이름 + 거리 + 주차
            Row(children: [
              Expanded(child: Text(s.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
              if (distLabel != null)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(distLabel,
                      style: TextStyle(fontSize: 10, color: Colors.indigo.shade700,
                          fontWeight: FontWeight.w700)),
                ),
              if (hasParking)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade300)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_parking_rounded, size: 11, color: Colors.green.shade700),
                    const SizedBox(width: 2),
                    Text('주차', style: TextStyle(fontSize: 9,
                        color: Colors.green.shade700, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
            const SizedBox(height: 2),
            Text(s.address.split(' ').take(3).join(' '),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 6),
            Wrap(spacing: 5, runSpacing: 4, children: [
              if (showRegionTag) _chip(s.region, Colors.teal),
              _chip('1등 ${s.firstCount}회', Colors.purple),
              // 회차 상태 칩
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: winStatusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: winStatusColor.withValues(alpha: 0.35)),
                ),
                child: Text(winStatusLabel, style: TextStyle(
                    fontSize: 10, color: winStatusColor, fontWeight: FontWeight.w700)),
              ),
              ...s.tags
                  .where((t) => !t.contains('회차'))
                  .map(_tagChip),
            ]),
            // ── 패턴 지표 바 ──────────────────────────────────
            const SizedBox(height: 6),
            _buildPatternBar(s),
            // ── TOP 3 번호추천 버튼 ───────────────────────────
            if (rank < 3) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showNumberSheet(context, s, rank),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_awesome, size: 13, color: Colors.white),
                    const SizedBox(width: 5),
                    Text('엔진 추천번호 보기',
                        style: const TextStyle(fontSize: 11, color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ],
          ])),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _openMap(context, s),
            child: const Icon(Icons.map_outlined, color: Colors.blue, size: 20),
          ),
        ]),
      ),
    );
  }

  // ── 패턴 분석 바 (타이밍 구간 + 추세 + 일관성) ─────────────
  Widget _buildPatternBar(_RegionStore s) {
    if (s.avgIntervalRounds == 0) return const SizedBox.shrink();

    // 포인터 위치: 0~2.0 범위를 0~1로 정규화 (2.0 이상은 끝에 고정)
    final pointerPos = (s.elapsedRatio / 2.0).clamp(0.0, 1.0);
    final isGolden   = s.elapsedRatio >= 0.8 && s.elapsedRatio <= 1.2;
    final isOverdue  = s.elapsedRatio > 1.6;
    final pointerColor = isGolden ? Colors.green.shade600
        : isOverdue ? Colors.red.shade600
        : s.elapsedRatio > 1.2 ? Colors.orange.shade700
        : Colors.blue.shade500;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── 타이밍 라벨 ───────────────────────────────────────
        Row(children: [
          Text('당첨 타이밍',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
          const SizedBox(width: 6),
          Text('(평균 ${s.avgIntervalRounds}회 주기 기준)',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: pointerColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(s.elapsedRatio * 100).toStringAsFixed(0)}% 경과',
              style: TextStyle(fontSize: 9, color: pointerColor, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        const SizedBox(height: 5),

        // ── 구간 바 + 포인터 ───────────────────────────────────
        // 전체 0~2.0 구간을 3색 구간으로 나눔
        // [이른편 0~0.8] [황금구간 0.8~1.2] [지연 1.2~2.0]
        LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final goldenStart  = w * 0.40;  // 0.8/2.0 = 40%
          final pointerX     = (w * pointerPos).clamp(0.0, w);

          return SizedBox(
            height: 22,
            child: Stack(clipBehavior: Clip.none, children: [
              // 구간 바 배경
              Positioned(top: 6, left: 0, right: 0, child: Row(children: [
                // 이른 구간 (0~0.8)
                Expanded(flex: 40, child: Container(
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDDE8F8),
                    borderRadius: BorderRadius.horizontal(left: Radius.circular(4)),
                  ),
                )),
                // 황금 구간 (0.8~1.2)
                Expanded(flex: 20, child: Container(
                  height: 10,
                  color: Colors.green.shade300,
                )),
                // 지연 구간 (1.2~2.0)
                Expanded(flex: 40, child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                  ),
                )),
              ])),
              // 구간 레이블
              Positioned(top: 0, left: 0,
                  child: Text('이른편', style: TextStyle(fontSize: 7, color: Colors.blue.shade300))),
              Positioned(top: 0, left: goldenStart + 2,
                  child: Text('황금구간', style: TextStyle(fontSize: 7, color: Colors.green.shade600,
                      fontWeight: FontWeight.w700))),
              Positioned(top: 0, right: 0,
                  child: Text('지연', style: TextStyle(fontSize: 7, color: Colors.orange.shade600))),
              // 포인터 삼각형 (▼)
              Positioned(
                top: 0,
                left: pointerX - 6,
                child: Column(children: [
                  Icon(Icons.arrow_drop_down_rounded, size: 16, color: pointerColor),
                ]),
              ),
            ]),
          );
        }),
        const SizedBox(height: 6),

        // ── 추세 + 일관성 ──────────────────────────────────────
        if (s.trendLabel.isNotEmpty || s.consistencyLabel.isNotEmpty)
          Row(children: [
            if (s.trendLabel.isNotEmpty) ...[
              Icon(
                s.trendLabel.contains('가속') ? Icons.trending_up_rounded
                    : s.trendLabel.contains('감속') ? Icons.trending_down_rounded
                    : Icons.trending_flat_rounded,
                size: 11,
                color: s.trendLabel.contains('가속') ? Colors.green.shade600
                    : s.trendLabel.contains('감속') ? Colors.orange.shade700
                    : Colors.grey.shade500,
              ),
              const SizedBox(width: 3),
              Text(s.trendLabel,
                  style: TextStyle(fontSize: 9,
                      color: s.trendLabel.contains('가속') ? Colors.green.shade600
                          : s.trendLabel.contains('감속') ? Colors.orange.shade700
                          : Colors.grey.shade500,
                      fontWeight: FontWeight.w600)),
            ],
            if (s.trendLabel.isNotEmpty && s.consistencyLabel.isNotEmpty)
              Text('  ·  ', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
            if (s.consistencyLabel.isNotEmpty)
              Text(s.consistencyLabel,
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
          ]),
      ]),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _tagChip(String tag) {
    final Color color;
    if (tag.contains('엔진 유력 지역')) color = Colors.deepPurple;
    else if (tag.contains('유력'))       color = Colors.deepOrange;
    else if (tag.contains('황금'))  color = Colors.amber.shade700;
    else if (tag.contains('가속'))  color = Colors.green.shade700;
    else if (tag.contains('감속'))  color = Colors.orange.shade700;
    else if (tag.contains('자동구매')) color = Colors.blue.shade700;
    else if (tag.contains('다회'))  color = Colors.indigo;
    else if (tag.contains('최근'))  color = Colors.green.shade700;
    else if (tag.contains('규칙'))  color = Colors.teal.shade700;
    else if (tag.contains('초과') || tag.contains('근접')) color = Colors.red.shade700;
    else if (tag.contains('미당첨') || tag.contains('공백')) color = Colors.green.shade700;
    else if (tag.contains('포화'))  color = Colors.orange.shade800;
    else if (tag.contains('단독'))  color = Colors.purple.shade700;
    else if (tag.contains('홀수') || tag.contains('짝수')) color = Colors.blueGrey.shade700;
    else if (tag.contains('분기'))  color = Colors.teal.shade600;
    else if (tag.contains('인근'))  color = Colors.blue.shade700;
    else                            color = Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(tag, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 판매점 번호 추천 시트 (활성 엔진 결과)
// ══════════════════════════════════════════════════════════════
class _NumberRecommendSheet extends StatefulWidget {
  final _RegionStore store;
  final int rank;
  final int round;

  const _NumberRecommendSheet({
    required this.store,
    required this.rank,
    required this.round,
  });

  @override
  State<_NumberRecommendSheet> createState() => _NumberRecommendSheetState();
}

class _NumberRecommendSheetState extends State<_NumberRecommendSheet> {
  RpaLiveNumbers? _live;
  String? _error;

  @override
  void initState() {
    super.initState();
    RpaLiveNumbers.load(widget.round).then((v) {
      if (mounted) setState(() => _live = v);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.60,
      maxChildSize: 0.85,
      builder: (_, ctrl) => Column(children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 28, height: 28,
                decoration: const BoxDecoration(color: Colors.deepPurple, shape: BoxShape.circle),
                child: Center(child: Text('${widget.rank + 1}',
                    style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w900))),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.store.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 4),
            Text(widget.store.address, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _error != null
              ? Center(child: Text('오류: $_error', style: const TextStyle(color: Colors.red)))
              : _live == null
                  ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
                  : ListView(
                      controller: ctrl,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: liveNumbersSection(_live!),
                    ),
        ),
      ]),
    );
  }
}

Widget _liveBall(int n, {bool dim = false}) {
  final bg = n <= 10
      ? const Color(0xFFFFB300)
      : n <= 20
          ? const Color(0xFF42A5F5)
          : n <= 30
              ? const Color(0xFFEF5350)
              : n <= 40
                  ? const Color(0xFF9E9E9E)
                  : const Color(0xFF66BB6A);
  return Opacity(
    opacity: dim ? 0.5 : 1,
    child: Container(
      width: 38, height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text('$n', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
    ),
  );
}

/// 기본 Number 추천(공통) + 판매점별 Joint 추천(Gate 결과)을 분리해서 보여줍니다.
List<Widget> liveNumbersSection(RpaLiveNumbers live) {
  Widget label(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w800)),
      );

  return [
    Row(children: [
      const Icon(Icons.auto_awesome, size: 15, color: Colors.deepPurple),
      const SizedBox(width: 6),
      Expanded(child: Text('${live.targetRound}회 엔진 기본 추천 (모든 판매점 공통)',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.deepPurple))),
      live.baseLive
          ? label('엔진 반영 · 실전', Colors.deepPurple)
          : label('실전 아님', Colors.grey),
    ]),
    const SizedBox(height: 4),
    Text(live.note, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    const SizedBox(height: 12),
    if (live.baseSets.isEmpty)
      Text('표시할 엔진 추천이 없습니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))
    else
      ...live.baseSets.asMap().entries.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.deepPurple.shade100),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('기본 조합 ${e.key + 1}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.deepPurple.shade700)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: e.value.map((n) => _liveBall(n, dim: !live.baseLive)).toList(),
              ),
            ]),
          )),
    const SizedBox(height: 8),
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: live.jointLive ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: live.jointLive ? Colors.green.shade200 : Colors.orange.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('판매점별 Joint 번호', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const Spacer(),
          live.jointLive
              ? label('Gate 통과 · 실전', Colors.green.shade700)
              : label('연구용 · 실전 미반영', Colors.orange.shade800),
        ]),
        const SizedBox(height: 6),
        Text(
          live.jointLive
              ? '번호 Joint Gate를 통과해 판매점 지역(${live.jointRegion ?? '-'}) 근거가 번호에 반영됩니다.'
              : '번호 Joint Gate 미통과 — 판매점별로 번호를 바꾸지 않습니다. 위 기본 추천을 사용합니다.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.4),
        ),
        if (live.jointLive && live.jointSets.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...live.jointSets.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: s.map(_liveBall).toList(),
                ),
              )),
        ],
      ]),
    ),
    const SizedBox(height: 14),
    // 구매예측 엔진 결과 (기존 Number Engine과 별개 — 혼합하지 않음)
    PurchaseRecommendCard(targetRound: live.targetRound, compact: true),
    const SizedBox(height: 10),
    Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '구매 시간대 연구: 동행복권 공식 API는 구매 시각을 공개하지 않습니다. '
              '판매량 보정 없는 시간대 당첨확률은 통계적으로 검증 불가하여 제공하지 않습니다.',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  ];
}

// ══════════════════════════════════════════════════════════════
// 추천 판매점 상세 시트 (지도 + 엔진 추천번호)
// ══════════════════════════════════════════════════════════════
class _RecommendStoreDetailSheet extends StatefulWidget {
  final _RecommendStore store;
  final int round;
  final Position? position;

  const _RecommendStoreDetailSheet({
    required this.store,
    required this.round,
    required this.position,
  });

  @override
  State<_RecommendStoreDetailSheet> createState() =>
      _RecommendStoreDetailSheetState();
}

class _RecommendStoreDetailSheetState
    extends State<_RecommendStoreDetailSheet> {
  RpaLiveNumbers? _live;
  String? _error;

  @override
  void initState() {
    super.initState();
    RpaLiveNumbers.load(widget.round).then((v) {
      if (mounted) setState(() => _live = v);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  List<({String label, Color color})> _recommendPurchaseMethod(double? autoRatio) {
    if (autoRatio == null) return [(label: '반자동', color: Colors.blue)];
    if (autoRatio >= 0.5) return [(label: '자동', color: Colors.green.shade700)];
    if (autoRatio >= 0.3) return [
      (label: '자동', color: Colors.green.shade700),
      (label: '반자동', color: Colors.blue),
    ];
    if (autoRatio >= 0.15) return [(label: '반자동', color: Colors.blue)];
    return [
      (label: '반자동', color: Colors.blue),
      (label: '수동', color: Colors.deepOrange),
    ];
  }

  Future<void> _openMap(String type) async {
    final query = Uri.encodeComponent(widget.store.address);
    final url = type == 'naver'
        ? 'https://map.naver.com/v5/search/$query'
        : 'https://map.kakao.com/link/search/$query';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.90,
      builder: (_, ctrl) => Column(children: [
        // 핸들
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        ),
        // 헤더 — 판매점명 + 주소
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(s.address,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 10),
            // 통계 칩 행
            Wrap(spacing: 8, runSpacing: 6, children: [
              _statChip(Icons.emoji_events_outlined,
                  '1등 ${s.firstCount}회', Colors.amber.shade700),
              _statChip(Icons.schedule_outlined,
                  '평균 ${s.avgInterval.toStringAsFixed(1)}회 간격',
                  Colors.teal.shade600),
              _statChip(Icons.history_rounded,
                  '마지막 ${s.lastWinRound}회', Colors.indigo.shade400),
              _statChip(Icons.flag_outlined,
                  '예측 ${s.predictedRound}회 (D${s.roundDiff > 0 ? '+' : ''}${s.roundDiff})',
                  s.roundDiff <= 3
                      ? Colors.red.shade600
                      : Colors.grey.shade600),
            ]),
            const SizedBox(height: 8),
            // 구매방법 추천 배지
            Row(children: [
              const Icon(Icons.shopping_cart_outlined, size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text('과거 구매방식 통계: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ..._recommendPurchaseMethod(s.autoRatio).map((m) => Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: m.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: m.color.withValues(alpha: 0.4)),
                ),
                child: Text(m.label,
                    style: TextStyle(
                        fontSize: 11, color: m.color, fontWeight: FontWeight.w700)),
              )),
            ]),
            const SizedBox(height: 12),
            // 지도 버튼
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openMap('naver'),
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('네이버 지도', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green.shade700,
                    side: BorderSide(color: Colors.green.shade300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openMap('kakao'),
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('카카오 지도', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.yellow.shade800,
                    side: BorderSide(color: Colors.yellow.shade600),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
        const Divider(height: 1),
        // 번호 추천 섹션 (기본 Number 공통 + Joint Gate 분리)
        Expanded(
          child: _error != null
              ? Center(child: Text('오류: $_error', style: const TextStyle(color: Colors.red)))
              : _live == null
                  ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
                  : ListView(
                      controller: ctrl,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: liveNumbersSection(_live!),
                    ),
        ),
      ]),
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 지도에서 위치 직접 선택 화면
// ══════════════════════════════════════════════════════════════
class _MapPickerScreen extends StatefulWidget {
  final LatLng initial;
  const _MapPickerScreen({required this.initial});

  @override
  State<_MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<_MapPickerScreen> {
  late LatLng _picked;
  late MapController _mapCtrl;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
    _mapCtrl = MapController();
  }

  @override
  void dispose() {
    _mapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        title: const Text('위치 선택', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _picked),
            child: const Text('이 위치로 설정',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _picked,
              initialZoom: 13.0,
              onTap: (tapPos, point) => setState(() => _picked = point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.nextleval.luckylotto',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _picked,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.location_pin,
                      color: Colors.indigo,
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 안내 배너
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '지도를 탭해서 내 위치를 설정하세요\n상단 "이 위치로 설정" 버튼을 누르면 적용됩니다',
                style: TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // 현재 선택 좌표 표시
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Text(
                '선택 위치: ${_picked.latitude.toStringAsFixed(5)}, ${_picked.longitude.toStringAsFixed(5)}',
                style: TextStyle(fontSize: 11, color: Colors.indigo.shade700),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
