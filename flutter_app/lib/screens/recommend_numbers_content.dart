// 추천번호 화면 — A. 기존 번호예측(Number Engine) / B. 구매예측 추천번호 (서로 다른 엔진, 분리 표시)
import 'package:flutter/material.dart';

import '../services/research/research_scheduler.dart';
import '../services/rpa_live_numbers.dart';
import '../widgets/purchase_recommend_card.dart';

class RecommendNumbersContent extends StatefulWidget {
  const RecommendNumbersContent({super.key});
  @override
  State<RecommendNumbersContent> createState() => _RecommendNumbersContentState();
}

class _RecommendNumbersContentState extends State<RecommendNumbersContent> {
  late Future<RpaLiveNumbers?> _live;
  int? _target;

  @override
  void initState() {
    super.initState();
    _live = () async {
      final d = await ResearchScheduler.instance.load();
      if (d == null) return null;
      _target = d.targetRound;
      return RpaLiveNumbers.load(d.targetRound);
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F4F8),
      child: FutureBuilder<RpaLiveNumbers?>(
        future: _live,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final live = snap.data;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _section('A', '기존 번호예측', '추첨예측 Number Engine', Colors.deepPurple, _numberEngineBody(live)),
              const SizedBox(height: 14),
              Center(child: Text('── 아래는 다른 엔진(구매예측)의 결과입니다 ──',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
              const SizedBox(height: 14),
              _section('B', '구매예측 추천번호', '구매자 선택 경향 추정 엔진', kPurchaseColor,
                  _target == null ? const Text('데이터 없음') : PurchaseRecommendCard(targetRound: _target)),
            ]),
          );
        },
      ),
    );
  }

  Widget _section(String tag, String title, String sub, Color color, Widget body) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 26, height: 26, alignment: Alignment.center,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
              child: Text(tag, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
              Text(sub, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ])),
          ]),
          const SizedBox(height: 12),
          body,
        ]),
      );

  Widget _numberEngineBody(RpaLiveNumbers? live) {
    if (live == null) return Text('당첨번호 데이터를 불러오지 못했습니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('${live.targetRound}회 기존 번호예측', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.deepPurple))),
        live.baseLive ? statusChip('엔진 반영 · 실전', Colors.deepPurple) : statusChip('실전 아님', Colors.grey),
      ]),
      const SizedBox(height: 4),
      Text(live.note, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      const SizedBox(height: 10),
      if (live.baseSets.isEmpty)
        Text('표시할 엔진 추천이 없습니다. 새 회차 처리 후 자동 생성됩니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))
      else
        ...live.baseSets.asMap().entries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.deepPurple.shade100),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('기본 조합 ${e.key + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.deepPurple.shade700)),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: e.value.map((n) => Opacity(opacity: live.baseLive ? 1 : 0.5, child: lottoBall(n))).toList()),
              ]),
            )),
      Text('기존 Number Engine 결과를 그대로 표시합니다. 구매예측 결과와 혼합·덮어쓰기하지 않습니다.',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
    ]);
  }
}
