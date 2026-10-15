// 지방장 다음 회차 추천 판매점 — 추첨 전 동결된 지방장 TOP5 (관리자 전용, 저장된 결과만 조회)
// 전국 시·군·구 지방장 238명이 각자 지역 판매점을 순위화한 결과. 어느 지역이든 골라서 볼 수 있다.
import 'package:flutter/material.dart';

import '../services/research/agent_research_repository.dart';
import '../services/store_map_launcher.dart';
import 'store_map_buttons.dart';

/// 다음 회차 지방장 추천 (목표 회차 · 모델 · 지방장별 TOP5)
class AgentNextPicks {
  final int target;
  final String model;
  final Map<String, List<AgentDelivery>> byAgent;
  const AgentNextPicks(this.target, this.model, this.byAgent);

  /// 지역 이름(예: '충남 천안시', '충남 천안시 서북구', '서울 노원구') → 지방장 id ('충남|천안시')
  String? agentFor(String region) {
    final t = region.trim().split(RegExp(r'\s+'));
    if (t.isEmpty || t[0].isEmpty) return null;
    // 세종은 시·군·구 없이 '세종'만 오는 경우가 있음
    if (t[0].startsWith('세종')) return byAgent.containsKey('세종|세종시') ? '세종|세종시' : null;
    if (t.length < 2) return null;
    // 통합 행정명('전남광주 광산구')은 광주·전남 지방장 둘 다 찾아본다
    final sidos = t[0] == '전남광주' ? const ['광주', '전남'] : [t[0]];
    for (final sd in sidos) {
      final id = '$sd|${t[1]}';
      if (byAgent.containsKey(id)) return id;
    }
    // 시 하위 구가 따로 저장된 경우 (예: '경기|수원시' 안의 '팔달구')
    for (final sd in sidos) {
      for (final k in byAgent.keys) {
        if (k.startsWith('$sd|') && region.contains(k.split('|')[1])) return k;
      }
    }
    return null;
  }

  static Future<AgentNextPicks?>? _cache;
  static DateTime? _cachedAt;

  /// 최신 실전 목표 회차의 지방장 납품 전체 (5분 캐시)
  static Future<AgentNextPicks?> load({bool force = false}) {
    if (!force && _cache != null && _cachedAt != null && DateTime.now().difference(_cachedAt!).inMinutes < 5) return _cache!;
    _cachedAt = DateTime.now();
    return _cache = () async {
      final repo = AgentResearchRepository();
      final live = await repo.latestLive(force: force);
      final ref = live.data;
      if (ref == null) return null;
      final d = await repo.loadDeliveries(target: ref.target, model: ref.model);
      final by = <String, List<AgentDelivery>>{};
      for (final x in d.data) {
        by.putIfAbsent(x.agentId, () => []).add(x);
      }
      for (final l in by.values) {
        l.sort((a, b) => a.rank.compareTo(b.rank));
      }
      return AgentNextPicks(ref.target, ref.model, by);
    }();
  }
}

String agentLabel(String id) => id == 'internet' ? '인터넷 판매' : id.replaceAll('|', ' ');

int _histInt(Map<String, dynamic> h, String k) => (h[k] as num?)?.toInt() ?? 0;

/// 지방장 1명의 다음 회차 TOP5 카드
class AgentPicksCard extends StatelessWidget {
  final String agentId;
  final int target;
  final List<AgentDelivery> picks;
  const AgentPicksCard({super.key, required this.agentId, required this.target, required this.picks});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('agent_picks_$agentId'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8F6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF00695C).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.groups_2_rounded, size: 18, color: Color(0xFF00695C)),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${agentLabel(agentId)} 지방장 · $target회 추천 판매점',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF00695C))),
          ),
        ]),
        const SizedBox(height: 2),
        Text('추첨 전 동결된 지방장 TOP5 (과거 1·2등 당첨 이력 기반 순위 · 당첨확률 아님)',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        if (picks.isEmpty) Text('이 지역 추천 데이터가 없습니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        for (final p in picks) _row(context, p),
      ]),
    );
  }

  Widget _row(BuildContext context, AgentDelivery p) {
    final f = _histInt(p.history, 'first'), s = _histInt(p.history, 'second');
    final since = (p.history['rounds_since_last'] as num?)?.toInt();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.rank == 1 ? const Color(0xFFE0A100) : const Color(0xFF00695C), shape: BoxShape.circle),
            child: Text('${p.rank}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.storeName ?? p.storeCode, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              if ((p.address ?? '').isNotEmpty)
                Text(p.address!, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              Text('1등 $f회 · 2등 $s회${since != null ? ' · 마지막 당첨 후 $since회' : ''}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF14213D), fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 4),
        StoreMapButtons(
          target: StoreMapTarget(storeId: p.storeCode, name: p.storeName ?? p.storeCode, address: p.address ?? '', lat: p.lat, lng: p.lng),
        ),
      ]),
    );
  }
}

/// 지역 이름에 맞는 지방장 추천 카드 (지역을 모르면 아무것도 표시하지 않음)
class AgentPicksForRegion extends StatelessWidget {
  final String region;
  const AgentPicksForRegion({super.key, required this.region});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AgentNextPicks?>(
      future: AgentNextPicks.load(),
      builder: (context, s) {
        final p = s.data;
        if (p == null) return const SizedBox.shrink();
        final id = p.agentFor(region);
        if (id == null) return const SizedBox.shrink();
        return AgentPicksCard(agentId: id, target: p.target, picks: p.byAgent[id] ?? const []);
      },
    );
  }
}

/// 전국 어느 지역이든 골라 보는 화면 (시·도 → 시·군·구)
class AgentNextPicksScreen extends StatefulWidget {
  final String? initialRegion;
  final Future<AgentNextPicks?> Function()? loader;
  const AgentNextPicksScreen({super.key, this.initialRegion, this.loader});

  @override
  State<AgentNextPicksScreen> createState() => _AgentNextPicksScreenState();
}

class _AgentNextPicksScreenState extends State<AgentNextPicksScreen> {
  AgentNextPicks? _p;
  bool _loading = true;
  String? _sido, _agent;

  @override
  void initState() {
    super.initState();
    (widget.loader ?? AgentNextPicks.load)().then((p) {
      if (!mounted) return;
      String? agent = widget.initialRegion == null ? null : p?.agentFor(widget.initialRegion!);
      setState(() {
        _p = p;
        _loading = false;
        _agent = agent;
        _sido = agent?.split('|').first;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final ids = p == null ? <String>[] : (p.byAgent.keys.where((k) => k != 'internet').toList()..sort());
    final sidos = {for (final k in ids) k.split('|').first}.toList()..sort();
    final units = _sido == null ? <String>[] : ids.where((k) => k.startsWith('$_sido|')).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00695C),
        foregroundColor: Colors.white,
        title: Text(p == null ? '지방장 추천 판매점' : '${p.target}회 지방장 추천 판매점', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? const Center(child: Text('지방장 추천 데이터가 아직 없습니다.'))
              : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                    child: Text('시·도와 시·군·구를 고르면 그 지역 지방장이 추첨 전에 동결한 다음 회차 추천 판매점 TOP5가 나옵니다.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final s in sidos)
                        ChoiceChip(
                          key: ValueKey('sido_$s'),
                          label: Text(s, style: const TextStyle(fontSize: 12)),
                          selected: _sido == s,
                          onSelected: (_) => setState(() {
                            _sido = s;
                            _agent = null;
                          }),
                        ),
                    ]),
                  ),
                  if (units.isNotEmpty) ...[
                    const Divider(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final u in units)
                          ChoiceChip(
                            key: ValueKey('unit_$u'),
                            label: Text(u.split('|')[1], style: const TextStyle(fontSize: 12)),
                            selected: _agent == u,
                            onSelected: (_) => setState(() => _agent = u),
                          ),
                      ]),
                    ),
                  ],
                  if (_agent != null) AgentPicksCard(agentId: _agent!, target: p.target, picks: p.byAgent[_agent] ?? const []),
                  if (_agent == null && _sido != null)
                    for (final u in units) AgentPicksCard(agentId: u, target: p.target, picks: (p.byAgent[u] ?? const []).take(3).toList()),
                ]),
    );
  }
}
