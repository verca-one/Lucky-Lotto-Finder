// 엔진 브리핑 맨 위 보고 3종 (저장본·DB 읽기만, 동행복권 접속 없음)
//   · 수집 현황 — 로또 · 연금 최신 회차 당첨번호 / 당첨 판매점 수집 여부 (2분마다 다시 확인)
//   · 지방장 적중 — 지난 회차 지방장 TOP5 중 실제 1·2등이 나온 판매점만 지역별로 (지방장보고 agent_debrief)
//   · 지방장 연구 요약 — 유명 명당 반복 · 지역 간 동시 당첨 · 선행·후행 공간전이 · 새로 공유된 가설을 짧은 문장으로 (근거 수치 생략)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../screens/admin_agent_research_screen.dart';
import '../services/research/agent_research_repository.dart';
import '../services/research/round_debrief.dart';
import '../services/round_status_service.dart';
import '../services/supabase_service.dart';
import 'agent_store_widgets.dart' show kAgentColor;
import 'briefing_store_widgets.dart' show FavoriteStoreStar;

String _ago(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes}분';
  final h = d.inHours;
  return h < 48 ? '$h시간 ${d.inMinutes % 60}분' : '${d.inDays}일';
}

/// 한 게임 수집 현황 한 줄 (순수 함수 — 테스트 대상). (문장, 지연 여부)
(String, bool) collectLine(String label, RoundCardInfo c, DateTime nowUtc) {
  final since = nowUtc.difference(drawTimeUtc(c.type, c.round));
  final late = since > const Duration(hours: 3);
  return switch (c.status) {
    RoundStatus.complete => ('$label ${c.round}회 — 당첨번호 ✓ · 판매점 ✓ 수집 완료', false),
    RoundStatus.numbersReady =>
      ('$label ${c.round}회 — 당첨번호 ✓ · 판매점 수집 대기 (추첨 후 ${_ago(since)})${late ? ' · 지연' : ''}', late),
    RoundStatus.awaiting =>
      ('$label ${c.round}회 — 당첨번호 · 판매점 수집 대기 (추첨 후 ${_ago(since)})${late ? ' · 지연' : ''}', late),
    RoundStatus.scheduled => ('$label ${c.round}회 — 추첨 전', false),
    RoundStatus.error => ('$label ${c.round}회 — 판매점 수집 확인 필요 (수집 실패 또는 기록 불일치)', true),
  };
}

class CollectStatusReport extends StatefulWidget {
  /// 테스트용: 게임별 회차 카드
  final Future<List<(String, RoundCardInfo)>> Function()? loader;
  final DateTime Function()? clock;
  const CollectStatusReport({super.key, this.loader, this.clock});
  @override
  State<CollectStatusReport> createState() => _CollectStatusReportState();
}

class _CollectStatusReportState extends State<CollectStatusReport> {
  List<(String, RoundCardInfo)>? _cards;
  DateTime? _at;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(minutes: 2), (_) => _load()); // 실시간 — DB 만 다시 읽음
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  DateTime _now() => (widget.clock ?? DateTime.now)().toUtc();

  static Future<List<(String, RoundCardInfo)>> _fetch() async {
    final runs = await SupabaseService.getRecentCrawlRuns();
    final now = DateTime.now().toUtc();
    final out = <(String, RoundCardInfo)>[];
    for (final (type, label) in const [('lotto', '로또'), ('pension', '연금')]) {
      final p = decideRoundPair(await RoundStatusService.load(type, crawlLogs: runs), now);
      if (p != null) out.add((label, p.front));
    }
    return out;
  }

  Future<void> _load() async {
    try {
      final c = await (widget.loader ?? _fetch)();
      if (!mounted) return;
      setState(() {
        _cards = c;
        _at = _now();
      });
    } catch (_) {
      // 읽기 실패 — 보이던 내용 유지
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    if (cards == null || cards.isEmpty) return const SizedBox.shrink();
    final lines = [for (final (l, c) in cards) collectLine(l, c, _now())];
    final late = lines.any((x) => x.$2);
    final c = late ? const Color(0xFFE65100) : const Color(0xFF2E7D32);
    return Container(
      key: const ValueKey('collect_status_report'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: late ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(late ? Icons.warning_amber_rounded : Icons.cloud_done_rounded, size: 18, color: c),
          const SizedBox(width: 6),
          Expanded(child: Text('수집 현황', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: c))),
          if (_at != null)
            Text('${_at!.toLocal().hour.toString().padLeft(2, '0')}:${_at!.toLocal().minute.toString().padLeft(2, '0')} 확인',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
          IconButton(
            visualDensity: VisualDensity.compact, iconSize: 18, tooltip: '다시 확인',
            icon: Icon(Icons.refresh, color: c), onPressed: _load,
          ),
        ]),
        for (final (s, bad) in lines)
          Text('• $s', style: TextStyle(fontSize: 12, height: 1.45, fontWeight: bad ? FontWeight.w800 : FontWeight.w600,
              color: bad ? const Color(0xFFBF360C) : Colors.black87)),
        if (late)
          Text('서버 예약 실행이 밀리는 중입니다. 판매점 크롤러는 그대로 두므로, 오래 늦어지면 수동 실행을 요청하세요.',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800)),
      ]),
    );
  }
}

/// 지방장 연구 요약 문장 (순수 함수 — 테스트 대상). 근거 수치(p · 기대 · 검증 건수)는 넣지 않는다.
List<String> agentDigestLines(AgentBriefing b) {
  String first(dynamic list) {
    final l = AgentBriefing.hyps(list);
    return l.isEmpty ? '' : ' 예: ${l.first.summary}';
  }

  String statuses(Map<String, dynamic> m) => [
        for (final s in kAgentHypStatusOrder)
          if (m[s] != null && m[s] != 0) '${kAgentHypStatusLabel[s]} ${m[s]}',
      ].join(' · ');

  int n(dynamic v) => (v as num?)?.toInt() ?? 0;
  final out = <String>[];
  final f = b.famousCycles;
  if (f.isNotEmpty) {
    final st = statuses(Map<String, dynamic>.from(f['by_status'] as Map? ?? const {}));
    out.add('유명 명당 반복 당첨 — ${n(f['tested'])}곳 살펴봄${st.isEmpty ? '' : ' ($st)'}.${first(f['examples'])}');
  }
  final c = b.cowin;
  if (c.isNotEmpty) {
    final cn = Map<String, dynamic>.from(c['counts'] as Map? ?? const {});
    out.add('지역 간 동시 당첨 — 같은 회차에 함께 당첨된 판매점 쌍 ${n(cn['store_pairs'])}건 관찰 (같은 회차 연관이라 예측에는 쓰지 않음).'
        '${first(c['store_pairs'])}');
  }
  final l = b.leadLag;
  if (l.isNotEmpty) {
    final total = Map<String, dynamic>.from(l['counts'] as Map? ?? const {}).values.fold<int>(0, (a, v) => a + n(v));
    out.add('선행·후행 공간전이 — 한 곳의 당첨 뒤 다른 곳 당첨이 느는지 $total건 연구 중.${first(l['examples'])}');
  }
  final s = b.shared;
  if (s.isNotEmpty) {
    out.add('새로 공유된 가설 — 지방장끼리 공유한 가설 ${n(s['templates'])}종, 이번에 새로 ${n(s['new_this_checkpoint'])}건'
        '${n(s['conflicts']) > 0 ? ', 서로 어긋나는 것 ${n(s['conflicts'])}건' : ''}.${first(s['examples'])}');
  }
  return out;
}

class AgentResearchDigest extends StatefulWidget {
  final Future<AgentBriefing?> Function()? loader;
  const AgentResearchDigest({super.key, this.loader});
  @override
  State<AgentResearchDigest> createState() => _AgentResearchDigestState();
}

class _AgentResearchDigestState extends State<AgentResearchDigest> {
  late final Future<AgentBriefing?> _f =
      (widget.loader ?? () async => (await AgentResearchRepository().loadBriefing()).data)();

  @override
  Widget build(BuildContext context) => FutureBuilder<AgentBriefing?>(
        future: _f,
        builder: (context, snap) {
          final b = snap.data;
          final lines = b == null ? const <String>[] : agentDigestLines(b);
          if (lines.isEmpty) return const SizedBox.shrink();
          return Container(
            key: const ValueKey('agent_research_digest'),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kAgentColor.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.groups_2, size: 18, color: kAgentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('지방장 연구 요약${b!.targetRound == null ? '' : ' · ${b.targetRound}회'}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: kAgentColor)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact, iconSize: 18, tooltip: '근거 자료 — 전국 지방장 연구소',
                  icon: const Icon(Icons.open_in_new, color: kAgentColor),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAgentResearchScreen())),
                ),
              ]),
              for (final l in lines) Text('• $l', style: const TextStyle(fontSize: 12, height: 1.5)),
              Text('근거 자료(검증 건수 · p값 등)는 전국 지방장 연구소에서 봅니다.',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            ]),
          );
        },
      );
}

/// 지방장 TOP5 적중 (지역, 판매점, 등수, TOP5 순위) — 1등 먼저, 같은 등수는 지역 이름순 (순수 함수 — 테스트 대상)
List<(String, String, int, int)> agentHits(AgentDebrief d) {
  final out = <(String, String, int, int)>[];
  for (final a in d.agents) {
    for (final p in a.prev) {
      final tier = p.length > 4 ? ((p[4] as num?)?.toInt() ?? 0) : 0;
      if (tier == 1 || tier == 2) out.add((a.label, '${p[1] ?? p[0]}', tier, (p[2] as num?)?.toInt() ?? 0));
    }
  }
  out.sort((x, y) => x.$3 != y.$3 ? x.$3.compareTo(y.$3) : x.$1.compareTo(y.$1));
  return out;
}

/// 이번에 맞힌 지방장들의 다음 회차 TOP3 (지역, 판매점, 순위, 새로 들어옴, 판매점 코드) — 순수 함수
List<(String, String, int, bool, String)> agentNextPicks(AgentDebrief d) {
  final hitIds = {
    for (final a in d.agents)
      if (a.prev.any((p) => p.length > 4 && ((p[4] as num?)?.toInt() ?? 0) > 0)) a.id,
  };
  final out = <(String, String, int, bool, String)>[];
  for (final a in d.agents.where((a) => hitIds.contains(a.id))) {
    for (final n in a.next) {
      final rank = (n[2] as num?)?.toInt() ?? 0;
      if (rank >= 1 && rank <= 3) out.add((a.label, '${n[1] ?? n[0]}', rank, n.length > 4 && n[4] == 'new', '${n[0]}'));
    }
  }
  out.sort((x, y) => x.$3 != y.$3 ? x.$3.compareTo(y.$3) : x.$1.compareTo(y.$1));
  return out;
}

/// 가까운 순 (거리 모르는 곳은 맨 뒤 · 순위 순) — 순수 함수
List<(String, String, int, bool, String)> sortByDistance(
    List<(String, String, int, bool, String)> picks, Map<String, double> dist) {
  final out = [...picks];
  out.sort((x, y) {
    final a = dist[x.$5], b = dist[y.$5];
    if (a == null || b == null) return a == null && b == null ? x.$3.compareTo(y.$3) : (a == null ? 1 : -1);
    return a.compareTo(b);
  });
  return out;
}

String distText(double m) => m < 1000 ? '${m.round()}m' : '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)}km';

class AgentHitsReport extends StatefulWidget {
  final Future<AgentDebrief?> Function()? loader;
  const AgentHitsReport({super.key, this.loader});
  @override
  State<AgentHitsReport> createState() => _AgentHitsReportState();
}

class _AgentHitsReportState extends State<AgentHitsReport> {
  late final Future<AgentDebrief?> _f = (widget.loader ?? RoundDebriefRepository.loadAgents)();
  bool _all = false, _nextOpen = false;
  Map<String, double>? _dist; // 판매점 코드 → 내 위치에서 거리(m). null = 순위 순
  bool _locating = false;

  /// 내 위치에서 가까운 순 (다시 누르면 순위 순)
  Future<void> _nearFirst(List<String> codes) async {
    if (_dist != null) {
      setState(() => _dist = null);
      return;
    }
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw '위치 서비스가 꺼져 있습니다.';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw '위치 권한이 없습니다.';
      final me = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 20));
      final stores = await SupabaseService.getStoresByCodes(codes);
      final d = <String, double>{
        for (final st in stores)
          if (st.latitude != null && st.longitude != null)
            st.dhlotteryCode: Geolocator.distanceBetween(me.latitude, me.longitude, st.latitude!, st.longitude!),
      };
      if (!mounted) return;
      setState(() {
        _dist = d;
        _nextOpen = true;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('내 위치를 확인하지 못했습니다: $e')));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// 다음 회차 지방장 추천점 — 접혀 있다가 누르면 펼침
  Widget _next(AgentDebrief d) {
    final base = agentNextPicks(d);
    final picks = _dist == null ? base : sortByDistance(base, _dist!);
    return Container(
      key: const ValueKey('agent_next_picks'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: kAgentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kAgentColor.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          key: const ValueKey('agent_next_toggle'),
          onTap: () => setState(() => _nextOpen = !_nextOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              const Icon(Icons.trending_up_rounded, size: 17, color: kAgentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text('다음 회차(${d.next}회) 지방장 추천점${picks.isEmpty ? '' : ' · ${picks.length}곳'}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: kAgentColor)),
              ),
              if (base.isNotEmpty)
                TextButton.icon(
                  key: const ValueKey('agent_next_near'),
                  style: TextButton.styleFrom(
                    foregroundColor: _dist == null ? kAgentColor : Colors.white,
                    backgroundColor: _dist == null ? Colors.white : kAgentColor,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: BorderSide(color: kAgentColor.withValues(alpha: 0.5)),
                  ),
                  onPressed: _locating ? null : () => _nearFirst([for (final p in base) p.$5]),
                  icon: _locating
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded, size: 15),
                  label: Text(_dist == null ? '가까운 순' : '순위 순', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                ),
              Icon(_nextOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: kAgentColor),
            ]),
          ),
        ),
        if (_nextOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('이번에 맞힌 지방장들이 ${d.next}회에 고른 TOP3${_dist == null ? '' : ' · 내 위치에서 가까운 순'}',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              if (picks.isEmpty)
                Text('${d.next}회 지방장 추천이 아직 없습니다 (서버 지방장 연구가 다음 회차 납품을 만들면 표시).',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
              for (final (region, store, rank, isNew, code) in picks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(width: 30, child: Text('$rank위', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: kAgentColor))),
                    Expanded(
                      child: Text('$region · $store', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    if (isNew) Text('새로', style: TextStyle(fontSize: 10.5, color: Colors.orange.shade800, fontWeight: FontWeight.w800)),
                    if (_dist != null) ...[
                      const SizedBox(width: 6),
                      Text(_dist![code] == null ? '위치 없음' : distText(_dist![code]!),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kAgentColor)),
                    ],
                    // ★ 즐겨찾기 저장
                    if (code.isNotEmpty) FavoriteStoreStar(code: code, name: store),
                  ]),
                ),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AgentDebrief?>(
        future: _f,
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) return const SizedBox.shrink();
          final hits = agentHits(d);
          final firsts = hits.where((h) => h.$3 == 1).length;
          final shown = _all ? hits : hits.take(10).toList();
          return Container(
            key: const ValueKey('agent_hits_report'),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kAgentColor.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.place_rounded, size: 18, color: kAgentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('지방장 적중 · ${d.round}회 — 1등 $firsts곳 · 2등 ${hits.length - firsts}곳',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: kAgentColor)),
                ),
              ]),
              const SizedBox(height: 2),
              if (hits.isEmpty)
                Text('${d.round}회에는 지방장 TOP5 안에서 1·2등이 나온 판매점이 없습니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              for (final (region, store, tier, rank) in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Container(
                      width: 34,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      decoration: BoxDecoration(
                        color: (tier == 1 ? const Color(0xFFFFB300) : Colors.blueGrey).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('$tier등', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                          color: tier == 1 ? const Color(0xFFE65100) : Colors.blueGrey.shade700)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('$region · $store', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    Text('TOP5 $rank위', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                  ]),
                ),
              if (hits.length > 10)
                TextButton(
                  key: const ValueKey('agent_hits_more'),
                  onPressed: () => setState(() => _all = !_all),
                  child: Text(_all ? '접기' : '${hits.length - 10}곳 더 보기'),
                ),
              if (hits.isNotEmpty) _next(d),
            ]),
          );
        },
      );
}
