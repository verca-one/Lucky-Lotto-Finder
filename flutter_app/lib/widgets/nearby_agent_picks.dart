// 내 위치 넓게 보기 — 반경 안에 있는 시·군·구 지방장들의 다음 회차 추천 판매점 (예: 수원 → 용인·오산·안양·화성…)
// 저장된 지방장 납품(research_agent_deliveries)만 읽는다. 거리는 각 지방장 TOP 판매점 중 가장 가까운 곳 기준.
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/research/agent_research_repository.dart' show AgentDelivery;
import 'agent_next_picks.dart';

class NearbyAgent {
  final String agentId;
  final double km; // 내 위치 → 이 지방장 TOP 판매점 중 가장 가까운 곳
  final List<AgentDelivery> picks;
  const NearbyAgent(this.agentId, this.km, this.picks);
}

/// 반경 [km] 안에 TOP 판매점이 있는 지방장 — 가까운 순 (인터넷 제외, 좌표 없는 판매점 제외)
List<NearbyAgent> nearbyAgents(AgentNextPicks p, LatLng me, double km) {
  const dist = Distance();
  final out = <NearbyAgent>[];
  p.byAgent.forEach((id, picks) {
    if (id == 'internet') return;
    double? best;
    for (final d in picks) {
      if (d.lat == null || d.lng == null) continue;
      final x = dist.as(LengthUnit.Meter, me, LatLng(d.lat!, d.lng!)) / 1000;
      if (best == null || x < best) best = x;
    }
    if (best != null && best <= km) out.add(NearbyAgent(id, best, picks));
  });
  out.sort((a, b) => a.km.compareTo(b.km));
  return out;
}

class NearbyAgentPicksSection extends StatefulWidget {
  final LatLng me;
  final int target;
  final Future<AgentNextPicks?> Function()? loader;
  const NearbyAgentPicksSection({super.key, required this.me, required this.target, this.loader});
  @override
  State<NearbyAgentPicksSection> createState() => _NearbyAgentPicksSectionState();
}

class _NearbyAgentPicksSectionState extends State<NearbyAgentPicksSection> {
  late final Future<AgentNextPicks?> _f = (widget.loader ?? AgentNextPicks.load)();
  double _km = 20;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AgentNextPicks?>(
      future: _f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        }
        final p = s.data;
        if (p == null) return const SizedBox.shrink();
        final list = nearbyAgents(p, widget.me, _km);
        return Container(
          key: const ValueKey('nearby_agents'),
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F8F6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF00695C).withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.travel_explore_rounded, color: Color(0xFF00695C), size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text('주변 지역 지방장 추천 — ${p.target}회 (반경 ${_km.toStringAsFixed(0)}km · ${list.length}개 지역)',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF00695C))),
              ),
            ]),
            const SizedBox(height: 4),
            Text('내 시·군·구만이 아니라 반경 안 이웃 지역 지방장들의 TOP 판매점을 가까운 순으로 보여줍니다.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final v in const [10.0, 20.0, 30.0])
                ChoiceChip(
                  key: ValueKey('nearby_km_${v.toInt()}'),
                  label: Text('${v.toStringAsFixed(0)}km', style: const TextStyle(fontSize: 12)),
                  selected: _km == v,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() { _km = v; }),
                ),
            ]),
            const SizedBox(height: 6),
            if (list.isEmpty)
              Text('반경 안에 지방장 추천 판매점이 없습니다. 반경을 늘려 보세요.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
            for (final a in list)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: ValueKey('nearby_agent_${a.agentId}'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  initiallyExpanded: list.indexOf(a) < 2,
                  title: Text('${agentLabel(a.agentId)} · 약 ${a.km.toStringAsFixed(1)}km',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  subtitle: Text('1위 ${a.picks.first.storeName ?? a.picks.first.storeCode}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  children: [AgentPicksCard(agentId: a.agentId, target: p.target, picks: a.picks.take(3).toList())],
                ),
              ),
          ]),
        );
      },
    );
  }
}
