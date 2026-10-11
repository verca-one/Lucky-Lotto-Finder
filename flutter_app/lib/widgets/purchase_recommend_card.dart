// 구매예측 추천번호 카드 (자체 로딩). 추천번호 화면·판매점 화면·구매예측 메뉴에서 공용.
import 'package:flutter/material.dart';

import '../services/research/purchase_prediction_engine.dart';
import '../services/research/research_scheduler.dart';

/// 검증 결과 한 줄 요약 (구매예측 카드·브리핑 공용)
String popularityValidationLine(PopularityModelReport p) =>
    '순방향 검증 ${p.testFrom}~${p.testTo}회(${p.nTest}회차): 판매 인기도 예측 상관 ${p.h1Corr.toStringAsFixed(2)} · '
    '덜 팔린 번호가 당첨된 회차는 1등 공동당첨자가 기대의 ${p.lowCoWinRatio.toStringAsFixed(2)}배, '
    '많이 팔린 번호는 ${p.highCoWinRatio.toStringAsFixed(2)}배 (p=${p.h2P.toStringAsFixed(3)})';

const Color kPurchaseColor = Color(0xFF00897B);

Color lottoBallColor(int n) {
  if (n <= 10) return const Color(0xFFFFB300);
  if (n <= 20) return const Color(0xFF42A5F5);
  if (n <= 30) return const Color(0xFFEF5350);
  if (n <= 40) return const Color(0xFF9E9E9E);
  return const Color(0xFF66BB6A);
}

Widget lottoBall(int n, {double size = 38}) => Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(color: lottoBallColor(n), shape: BoxShape.circle),
      child: Text('$n', style: TextStyle(fontSize: size * 0.37, fontWeight: FontWeight.w900, color: Colors.white)),
    );

Widget statusChip(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w800)),
    );

class PurchaseRecommendCard extends StatelessWidget {
  final int? targetRound;
  final bool compact;
  const PurchaseRecommendCard({super.key, this.targetRound, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PurchaseModelReport?>(
      future: ResearchScheduler.instance.purchaseReport(targetRound: targetRound),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final r = snap.data;
        if (r == null) {
          return Text('구매예측 데이터를 불러오지 못했습니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600));
        }
        return _body(r);
      },
    );
  }

  Widget _body(PurchaseModelReport r) {
    final ok = r.validated;
    final p = r.popularity;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.groups_rounded, size: 15, color: kPurchaseColor),
        const SizedBox(width: 6),
        Expanded(child: Text('${r.targetRound}회 구매예측 추천번호',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kPurchaseColor))),
        statusChip(ok ? '검증 통과' : '검증 실패 · 미제공', ok ? Colors.teal.shade700 : Colors.red.shade700),
      ]),
      const SizedBox(height: 4),
      Text('구매예측 엔진 $kPurchaseModelVersion · ${r.trainingEnd}회까지 데이터 · 다른 구매자와 번호가 겹칠 위험을 낮추는 것이 목표',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      if (ok) Text(popularityValidationLine(p), style: TextStyle(fontSize: 10.5, color: Colors.teal.shade800, height: 1.4)),
      const SizedBox(height: 10),
      if (!ok)
        Text('검증을 통과하지 못해 구매예측 번호를 제공하지 않습니다. ${p.gateReason}',
            style: TextStyle(fontSize: 12, color: Colors.red.shade700, height: 1.4))
      else
        ...r.recommendations.asMap().entries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kPurchaseColor.withValues(alpha: 0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('구매예측 조합 ${e.key + 1}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kPurchaseColor)),
                  const Spacer(),
                  Text('판매 인기도 ×${(e.value.popularityIndex ?? 1).toStringAsFixed(2)}${e.value.extrapolated ? ' (검증 범위 밖)' : ''}',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                ]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: e.value.numbers.map((n) => lottoBall(n)).toList()),
                if (!compact) ...[
                  const SizedBox(height: 8),
                  ...e.value.reasons.map((s) => Text('· $s', style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.4))),
                ],
              ]),
            )),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
        child: Text(
          '모든 조합의 1등 확률은 동일(1/8,145,060)합니다. 구매예측은 당첨 확률을 올리지 않으며, '
          '실제 판매 데이터(회차별 판매액·4등 당첨자 수)로 검증한 "덜 팔리는 조합"을 골라 당첨 시 상금을 나눌 사람을 줄이는 선택입니다. '
          '"검증 범위 밖"은 과거 당첨번호에서 관측된 인기도보다 더 낮게 예측된 조합으로, 방향은 같지만 크기는 외삽입니다.',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.4),
        ),
      ),
    ]);
  }
}
