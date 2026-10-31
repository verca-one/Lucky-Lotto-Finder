// 연구소 › 추천판매점 › 종합 추천 판매점 — 지방장 · 연구소 · 엔진 · 제미나이를 한 줄로 합친 로또 판매점 추천
//   규칙(사전 고정, 저장본만 읽음):
//   · 후보 = 지방장 실전 납품 TOP5 전체(인터넷 제외) + 제미나이 가설 트랙 명당
//   · 점수 = 지방장 1등 추정 확률 × 연구소 검증 가설 배수(hs-apply) × 제미나이 가설 배수(가설 트랙 명당이면)
//   · 엔진 = 중앙 엔진 전국 상위 후보 순위를 함께 표시 (점수가 같으면 엔진 순위 먼저)
//   추정 확률은 판매량 미보정 모델 값이며 한 장당 당첨확률이 아니다.
import 'package:flutter/material.dart';

import '../services/research/agent_research_repository.dart';
import '../services/research/hypothesis_track.dart';
import '../services/research/store_hit_ranking.dart';
import '../widgets/agent_store_widgets.dart' show showAgentStoreSheet;

class CombinedPick {
  final String code, name, region;
  final double pFirst, labFactor, geminiFactor;
  final int? agentRank, engineRank;
  final String? geminiWhy;
  const CombinedPick({required this.code, required this.name, required this.region, required this.pFirst,
      this.labFactor = 1, this.geminiFactor = 1, this.agentRank, this.engineRank, this.geminiWhy});
  double get score => pFirst * labFactor * geminiFactor;
}

/// 네 출처 합치기 (순수 함수 — 테스트 대상)
List<CombinedPick> combineStorePicks({
  required List<AgentDelivery> deliveries,
  required List<AgentCentralStore> engineTop,
  required double Function(String code) labFactor,
  List<TrackStore> gemini = const [],
  String Function(TrackStore s)? geminiWhy,
  int max = 30,
}) {
  final engine = {for (final (i, s) in engineTop.indexed) s.storeCode: i + 1};
  final g = {for (final s in gemini) s.code: s};
  final best = <String, CombinedPick>{};
  void add(CombinedPick p) {
    final cur = best[p.code];
    if (cur == null || p.score > cur.score) best[p.code] = p;
  }

  for (final d in deliveries) {
    if (d.agentId == 'internet' || d.storeCode.isEmpty) continue;
    final t = g[d.storeCode];
    add(CombinedPick(
      code: d.storeCode, name: d.name, region: agentLabel(d.agentId), pFirst: d.pFirst ?? 0,
      labFactor: labFactor(d.storeCode), geminiFactor: t?.factor ?? 1, agentRank: d.rank,
      engineRank: engine[d.storeCode], geminiWhy: t == null ? null : geminiWhy?.call(t),
    ));
  }
  for (final t in gemini) {
    if (best.containsKey(t.code)) continue;
    add(CombinedPick(
      code: t.code, name: t.name, region: t.region, pFirst: t.pFirst, labFactor: labFactor(t.code), geminiFactor: t.factor,
      engineRank: engine[t.code], geminiWhy: geminiWhy?.call(t),
    ));
  }
  final out = best.values.toList()
    ..sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : (a.engineRank ?? 1 << 20).compareTo(b.engineRank ?? 1 << 20);
    });
  return out.take(max).toList();
}

class CombinedStorePicksScreen extends StatefulWidget {
  final Future<(int, List<CombinedPick>)?> Function()? loader;
  const CombinedStorePicksScreen({super.key, this.loader});
  @override
  State<CombinedStorePicksScreen> createState() => _CombinedStorePicksScreenState();
}

class _CombinedStorePicksScreenState extends State<CombinedStorePicksScreen> {
  late final Future<(int, List<CombinedPick>)?> _f = (widget.loader ?? _load)();

  static Future<(int, List<CombinedPick>)?> _load() async {
    final repo = AgentResearchRepository();
    final ref = (await repo.latestLive()).data;
    if (ref == null) return null;
    final deliv = (await repo.loadDeliveries(target: ref.target, model: ref.model)).data;
    final central = (await repo.loadCentral(ref.target, model: ref.model)).data;
    StoreHitRanking? hit;
    HypothesisTrack? track;
    try {
      hit = await StoreHitRanking.load(ref.target);
    } catch (_) {}
    try {
      track = await HypothesisTrack.load(ref.target + 1) ?? await HypothesisTrack.load(ref.target);
    } catch (_) {}
    return (
      ref.target,
      combineStorePicks(
        deliveries: deliv,
        engineTop: central?.storeTop ?? const [],
        labFactor: hit?.factorOf ?? (_) => 1.0,
        gemini: track?.stores ?? const [],
        geminiWhy: (s) => track?.whyOf(s) ?? '',
      ),
    );
  }

  Widget _tag(String t, Color c) => Container(
        margin: const EdgeInsets.only(right: 4, top: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('종합 추천 판매점 (로또)', style: TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: const Color(0xFF4527A0),
          foregroundColor: Colors.white,
        ),
        body: FutureBuilder<(int, List<CombinedPick>)?>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final r = snap.data;
            if (r == null || r.$2.isEmpty) {
              return const Center(child: Text('추천할 판매점이 없습니다 (지방장 실전 납품 확인 필요).'));
            }
            return ListView(padding: const EdgeInsets.all(14), children: [
              Text('${r.$1}회 기준 · 지방장 확률 × 연구소 검증 가설 × 제미나이 가설 · 엔진(중앙 엔진 전국 순위) 함께 표시',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, height: 1.4)),
              const SizedBox(height: 8),
              for (final (i, p) in r.$2.indexed)
                InkWell(
                  key: ValueKey('combined_${p.code}'),
                  onTap: () => showAgentStoreSheet(context, p.code, name: p.name),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 26, child: Text('${i + 1}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF4527A0)))),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                          Text(p.region, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          Wrap(children: [
                            if (p.agentRank != null) _tag('지방장 ${p.agentRank}위', const Color(0xFF00695C)),
                            if (p.labFactor != 1) _tag('연구소 가설 ×${p.labFactor.toStringAsFixed(2)}', const Color(0xFF1565C0)),
                            if (p.engineRank != null) _tag('엔진 전국 ${p.engineRank}위', const Color(0xFFE65100)),
                            if (p.geminiFactor != 1 || p.geminiWhy != null) _tag('제미나이 ×${p.geminiFactor.toStringAsFixed(2)}', const Color(0xFF6A1B9A)),
                          ]),
                          if ((p.geminiWhy ?? '').isNotEmpty)
                            Text('제미나이: ${p.geminiWhy}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF6A1B9A), height: 1.35)),
                        ]),
                      ),
                      Text('${(p.score * 100).toStringAsFixed(2)}%', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ),
              Text('추정 확률은 판매량을 모르는 모델 값이라 한 장당 당첨확률이 아닙니다.',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            ]);
          },
        ),
      );
}
