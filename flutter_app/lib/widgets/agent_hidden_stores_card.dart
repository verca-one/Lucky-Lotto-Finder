// 엔진 브리핑 지방장 ② — 지방에서 가볼 만한 연구 추천 명당 (이미 다 아는 유명 명당 제외)
//   규칙(사전 고정):
//   1) 후보 = 최신 실전 지방장 납품 TOP5 전체 (인터넷 판매 제외)
//   2) 유명 명당 제외 = 누적 1등 3회 이상 · 중앙 엔진 전국 상위 후보 20곳
//   3) 최근 2년(104회) 안에 1·2등이 나온 곳만
//   4) 순위 = 지방장 1등 추정 확률 × 검증 가설 배수(없으면 1) · 시·도마다 1곳 → 최대 10곳
//   추정 확률은 판매량 미보정 모델 값이며 한 장당 당첨확률이 아니다.
import 'package:flutter/material.dart';

import '../services/research/agent_research_repository.dart';
import '../services/research/store_hit_ranking.dart';
import 'agent_store_widgets.dart' show kAgentColor, showAgentStoreSheet;

const kHiddenMaxFirst = 2;
const kHiddenRecent = 104;
const kHiddenFamousTop = 20;

class HiddenStore {
  final AgentDelivery d;
  final double factor;
  const HiddenStore(this.d, this.factor);
  double get value => (d.pFirst ?? 0) * factor;
  int get first => (d.history['first'] as num?)?.toInt() ?? 0;
  int get second => (d.history['second'] as num?)?.toInt() ?? 0;
  int? get since => (d.history['rounds_since_last'] as num?)?.toInt();
}

/// 숨은 명당 고르기 (순수 함수 — 테스트 대상)
List<HiddenStore> pickHiddenStores(List<AgentDelivery> all, Set<String> famous, double Function(String code) factorOf,
    {int max = 10}) {
  final c = <HiddenStore>[];
  for (final d in all) {
    final h = HiddenStore(d, factorOf(d.storeCode));
    if (d.agentId == 'internet' || d.storeCode.isEmpty || famous.contains(d.storeCode)) continue;
    if (h.first > kHiddenMaxFirst || h.since == null || h.since! > kHiddenRecent) continue;
    c.add(h);
  }
  c.sort((a, b) => b.value.compareTo(a.value));
  final out = <HiddenStore>[];
  final sido = <String>{};
  final seen = <String>{};
  for (final h in c) {
    final s = h.d.agentId.split('|').first;
    if (!seen.add(h.d.storeCode) || !sido.add(s)) continue;
    out.add(h);
    if (out.length == max) break;
  }
  return out;
}

class HiddenStoresCard extends StatefulWidget {
  final Future<(int, List<HiddenStore>)?> Function()? loader;
  const HiddenStoresCard({super.key, this.loader});
  @override
  State<HiddenStoresCard> createState() => _HiddenStoresCardState();
}

class _HiddenStoresCardState extends State<HiddenStoresCard> {
  late final Future<(int, List<HiddenStore>)?> _f = (widget.loader ?? _load)();

  static Future<(int, List<HiddenStore>)?> _load() async {
    final repo = AgentResearchRepository();
    final ref = (await repo.latestLive()).data;
    if (ref == null) return null;
    final deliv = (await repo.loadDeliveries(target: ref.target, model: ref.model)).data;
    final central = (await repo.loadCentral(ref.target, model: ref.model)).data;
    StoreHitRanking? hit;
    try {
      hit = await StoreHitRanking.load(ref.target);
    } catch (_) {}
    final famous = {for (final s in (central?.storeTop ?? const <AgentCentralStore>[]).take(kHiddenFamousTop)) s.storeCode};
    return (ref.target, pickHiddenStores(deliv, famous, hit?.factorOf ?? (_) => 1.0));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<(int, List<HiddenStore>)?>(
        future: _f,
        builder: (context, snap) {
          final r = snap.data;
          return Container(
            key: const ValueKey('hidden_stores_card'),
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kAgentColor.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kAgentColor.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.travel_explore_rounded, size: 18, color: kAgentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('지방에서 가볼 만한 연구 추천 명당${r == null ? '' : ' · ${r.$1}회'}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: kAgentColor)),
                ),
              ]),
              Text('이미 잘 알려진 유명 명당(1등 3회 이상 · 전국 상위 20곳)은 빼고, 최근 2년 안에 당첨이 나온 곳 중 '
                  '지방장 연구 점수가 높은 곳을 시·도마다 한 곳씩 골랐습니다.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.4)),
              const SizedBox(height: 6),
              if (snap.connectionState != ConnectionState.done)
                const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else if (r == null || r.$2.isEmpty)
                Text('추천할 곳이 없습니다 (지방장 납품 자료 확인 필요).', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))
              else
                for (final e in r.$2.asMap().entries) _row(context, e.key + 1, e.value),
              Text('추정 확률은 판매량을 모르는 모델 값이라 한 장당 당첨확률이 아닙니다.',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ]),
          );
        },
      );

  Widget _row(BuildContext context, int i, HiddenStore h) => InkWell(
        key: ValueKey('hidden_store_${h.d.storeCode}'),
        onTap: () => showAgentStoreSheet(context, h.d.storeCode, name: h.d.name),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 22, child: Text('$i', style: const TextStyle(fontWeight: FontWeight.w900, color: kAgentColor))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.d.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                Text('${agentLabel(h.d.agentId)} · 역대 1등 ${h.first}회 · 2등 ${h.second}회'
                    '${h.since == null ? '' : ' · 마지막 당첨 ${h.since}회 전'}',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                Text('지방장 ${h.d.rank}위${h.factor > 1 ? ' · 검증 가설 ×${h.factor.toStringAsFixed(2)}' : ''}'
                    '${h.d.firingHypothesisCount > 0 ? ' · 이번 회차 발화 가설 ${h.d.firingHypothesisCount}개' : ''}',
                    style: const TextStyle(fontSize: 10.5, color: kAgentColor)),
              ]),
            ),
            Text('${((h.value) * 100).toStringAsFixed(2)}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
          ]),
        ),
      );
}
