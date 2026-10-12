// 구매예측 메뉴 — 구매자 선택 경향 분석 · 추천번호 · 근거 · 검증 상태
import 'package:flutter/material.dart';

import '../services/research/purchase_prediction_engine.dart';
import '../services/research/research_scheduler.dart';
import '../widgets/purchase_recommend_card.dart';

/// Navigator.push 용 (관리자 패널 등)
class PurchasePredictionScreen extends StatelessWidget {
  const PurchasePredictionScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('구매예측')),
        body: const PurchasePredictionContent(),
      );
}

/// 추천 탭 하위 화면용 (Scaffold 없음)
class PurchasePredictionContent extends StatefulWidget {
  const PurchasePredictionContent({super.key});
  @override
  State<PurchasePredictionContent> createState() => _PurchasePredictionContentState();
}

class _PurchasePredictionContentState extends State<PurchasePredictionContent> {
  late Future<PurchaseModelReport?> _future;

  @override
  void initState() {
    super.initState();
    _future = ResearchScheduler.instance.purchaseReport();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F4F8),
      child: FutureBuilder<PurchaseModelReport?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final r = snap.data;
          if (r == null) return const Center(child: Text('서버가 이번 회차 구매예측을 아직 저장하지 않았습니다 (서버 연구 대기).'));
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _header(r),
              const SizedBox(height: 12),
              _card('모델 검증 상태', Icons.verified_outlined, _statusBody(r)),
              const SizedBox(height: 12),
              _card('번호 인기도 모델 (판매액·4등 당첨자 수, 순방향 검증)', Icons.fact_check_rounded, _popularityBody(r)),
              const SizedBox(height: 12),
              _card('구매예측 추천번호', Icons.groups_rounded, PurchaseRecommendCard(targetRound: r.targetRound)),
              const SizedBox(height: 12),
              _card('보조 연구: 1등 당첨자 수동 비율', Icons.insights_rounded, _patternBody(r)),
              const SizedBox(height: 12),
              _card('보조 연구: 1등 당첨자 수 직접 모델', Icons.bar_chart_rounded, _volumeBody(r)),
              const SizedBox(height: 12),
              _card('구매예측 원칙', Icons.gavel_rounded, _principles()),
            ]),
          );
        },
      ),
    );
  }

  Widget _header(PurchaseModelReport r) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF00897B), Color(0xFF26A69A)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r.targetRound}회 구매예측', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 4),
          Text('${r.trainingEnd}회까지의 회차별 판매액·등수별 당첨자 수(${r.prizeStatsRounds}회차)로 다른 구매자들이 어떤 번호를 많이 사는지 추정하고, '
              '순방향 검증을 통과한 경우에만 덜 팔리는 조합을 추천합니다. 추첨 결과를 예측하는 기능이 아닙니다.',
              style: const TextStyle(fontSize: 11, color: Colors.white70, height: 1.4)),
        ]),
      );

  Widget _card(String title, IconData icon, Widget body) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8EDF5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: kPurchaseColor),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
          ]),
          const SizedBox(height: 10),
          body,
        ]),
      );

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 118, child: Text(k, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
          Expanded(child: Text(v, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color ?? const Color(0xFF1A1A2E), height: 1.3))),
        ]),
      );

  Widget _statusBody(PurchaseModelReport r) {
    final ok = r.validated;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(children: [
        statusChip(ok ? '검증 통과' : '검증 실패 · 번호 미제공', ok ? Colors.teal.shade700 : Colors.red.shade700),
      ]),
      const SizedBox(height: 8),
      _kv('추천 순위 기준', ok ? '번호 인기도 모델 (검증 통과)' : '없음 — 검증 실패 시 휴리스틱으로 대체하지 않음'),
      _kv('검증 결과', r.popularity.gateReason, color: ok ? Colors.teal.shade800 : Colors.red.shade700),
      _kv('검증 기준(사전 고정)', '① 판매 인기도 예측 상관 > 0, p < 0.01  ② 1등 공동당첨자 예측 계수 > 0, p < 0.05'),
      const SizedBox(height: 6),
      Text('데이터 부족 항목', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
      ...r.dataGaps.map((g) => Text('· $g', style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.4))),
    ]);
  }

  Widget _popularityBody(PurchaseModelReport r) {
    final p = r.popularity;
    if (!p.available || p.nTest == 0) {
      return Text(p.gateReason.isEmpty ? '판매액·등수별 당첨자 수 데이터가 없습니다.' : p.gateReason,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700));
    }
    String f(double v, [int d = 3]) => v.isNaN ? '-' : v.toStringAsFixed(d);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('원리: 4등(4개 일치) 당첨자는 회당 약 18만 명이라, 당첨번호를 사람들이 평균보다 얼마나 많이 샀는지를 거의 정확히 보여줍니다. '
          '(관측 4등 ÷ 판매게임수×4등확률) 의 로그를 조합 특징 10개 + 번호별 효과 45개로 학습합니다.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.4)),
      const SizedBox(height: 8),
      _kv('학습 / 검증', '${p.trainFrom}~${p.trainTo}회 ${p.nTrain}회차 / ${p.testFrom}~${p.testTo}회 ${p.nTest}회차'),
      _kv('① 인기도 예측', '상관 ${f(p.h1Corr, 2)} · 설명력 ${(p.h1R2 * 100).toStringAsFixed(0)}% · p=${p.h1P < 1e-4 ? '<0.0001' : f(p.h1P, 4)}',
          color: p.h1P < 0.01 ? Colors.teal.shade800 : Colors.red.shade700),
      _kv('② 1등 공동당첨 예측', '계수 ${f(p.h2Coef, 2)} · p=${f(p.h2P, 4)}', color: p.h2P < 0.05 ? Colors.teal.shade800 : Colors.red.shade700),
      _kv('실제 효과', '덜 팔린 번호가 당첨된 회차 1등 공동당첨자 기대의 ${f(p.lowCoWinRatio, 2)}배 vs 많이 팔린 번호 ${f(p.highCoWinRatio, 2)}배'),
      if (p.leastPopularNumbers.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('적게 팔리는 번호', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.blue.shade700)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: p.leastPopularNumbers.map((n) => lottoBall(n, size: 28)).toList()),
        const SizedBox(height: 6),
        Text('많이 팔리는 번호 (생일·행운 숫자)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.red.shade700)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: p.mostPopularNumbers.map((n) => lottoBall(n, size: 28)).toList()),
      ],
    ]);
  }

  Widget _patternBody(PurchaseModelReport r) {
    final e = r.empirical;
    if (!e.available) {
      return Text('1등 당첨자 자동/수동 데이터가 없어 실증 분석을 할 수 없습니다. 휴리스틱만 사용합니다.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700));
    }
    String f(double v, [int d = 4]) => v.isNaN ? '-' : v.toStringAsFixed(d);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('원리: 자동 선택은 균등분포이므로, 당첨 조합의 특징이 1등 당첨자 중 "수동 선택 비율"을 바꾼다면 '
          '그 특징은 사람이 선호(또는 회피)하는 특징입니다. 판매량 없이도 선호 방향을 추정할 수 있습니다.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.4)),
      const SizedBox(height: 8),
      _kv('학습 구간', '${e.trainRoundFrom}~${e.trainRoundTo}회 · ${e.nTrain}명 (수동 ${(e.manualShareTrain * 100).toStringAsFixed(1)}%)'),
      _kv('검증 구간', '${e.testRoundFrom}~${e.testRoundTo}회 · ${e.nTest}명 (수동 ${(e.manualShareTest * 100).toStringAsFixed(1)}%)'),
      _kv('검증 로그손실', '모델 ${f(e.testLogLoss)} vs 기준 ${f(e.baselineLogLoss)}'),
      _kv('개선 (95% CI)', '${f(e.improvement)} (${f(e.improvementCi[0])} ~ ${f(e.improvementCi[1])})',
          color: e.improvement > 0 ? Colors.teal.shade800 : Colors.red.shade700),
      const SizedBox(height: 8),
      Text('특징별 계수 — 학습 구간 / 검증 구간 단독 재적합 (양수 = 수동 선택↑ = 사람이 더 고름)',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      ...e.coefs.asMap().entries.map((en) {
        final c = en.value;
        final t = en.key < e.testCoefs.length ? e.testCoefs[en.key] : null;
        final rep = e.replicatedKeys.contains(c.key);
        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            SizedBox(width: 100, child: Text(c.name, style: const TextStyle(fontSize: 11))),
            Expanded(child: Text('${c.coef >= 0 ? '+' : ''}${c.coef.toStringAsFixed(3)}±${c.se.toStringAsFixed(3)}'
                '${t == null ? '' : '  /  ${t.coef >= 0 ? '+' : ''}${t.coef.toStringAsFixed(3)}±${t.se.toStringAsFixed(3)}'}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: c.pHolm < 0.05 ? (c.coef > 0 ? Colors.red.shade700 : Colors.blue.shade700) : Colors.grey.shade600))),
            Text(rep ? '재현 ✓' : c.pHolm < 0.05 ? 'Holm p=${c.pHolm.toStringAsFixed(3)}' : '유의X',
                style: TextStyle(fontSize: 10, fontWeight: rep ? FontWeight.w800 : FontWeight.w400,
                    color: rep ? Colors.teal.shade800 : Colors.grey.shade500)),
          ]),
        );
      }),
      const SizedBox(height: 4),
      Text('재현 ✓ = 학습·검증 구간 모두 같은 부호이고 |z|>1.96. 예측 성능 게이트(로그손실)와 별개의 특징 수준 검증입니다.',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.4)),
    ]);
  }

  Widget _volumeBody(PurchaseModelReport r) {
    final v = r.volume;
    if (!v.available) {
      return Text('판매액·등수별 당첨자 수 데이터가 없습니다 (research_prize_stats). 수집·적용 후 자동으로 모델이 학습됩니다.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.4));
    }
    String f(double x, [int d = 1]) => x.isNaN ? '-' : x.toStringAsFixed(d);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('원리: 1등 당첨자 수 = 판매 게임수 × (1/8,145,060) × 그 조합의 상대 인기도. '
          '판매량을 오프셋으로 넣은 포아송 회귀로 "어떤 특징의 조합이 더 많이 팔리는지"를 추정합니다. 추첨 확률과는 무관합니다.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.4)),
      const SizedBox(height: 8),
      _kv('데이터', '${r.prizeStatsRounds}회차 (판매액·등수별 당첨자 수)'),
      if (v.nTest > 0) ...[
        _kv('학습 / 검증', '${v.trainRoundFrom}~${v.trainRoundTo}회 ${v.nTrain}회차 / ${v.testRoundFrom}~${v.testRoundTo}회 ${v.nTest}회차'),
        _kv('평균 인기도 비율', '${f(v.meanRatio, 3)} (1.0 = 균등 선택과 동일)'),
        _kv('검증 이탈도', '모델 ${f(v.testDeviance)} vs 기준 ${f(v.baselineDeviance)} → 감소 ${f(v.improvement)} (CI ${f(v.improvementCi[0])}~${f(v.improvementCi[1])})',
            color: v.improvement > 0 ? Colors.teal.shade800 : Colors.red.shade700),
      ],
      _kv('게이트', v.gateReason, color: v.gatePass ? Colors.teal.shade800 : Colors.orange.shade900),
      if (v.coefs.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('특징별 계수 — 학습 / 검증 재적합 (양수 = 그 특징 조합이 더 많이 팔림)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        ...v.coefs.asMap().entries.map((en) {
          final c = en.value;
          final t = en.key < v.testCoefs.length ? v.testCoefs[en.key] : null;
          final rep = v.replicatedKeys.contains(c.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              SizedBox(width: 100, child: Text(c.name, style: const TextStyle(fontSize: 11))),
              Expanded(child: Text('${c.coef >= 0 ? '+' : ''}${c.coef.toStringAsFixed(3)}±${c.se.toStringAsFixed(3)}'
                  '${t == null ? '' : '  /  ${t.coef >= 0 ? '+' : ''}${t.coef.toStringAsFixed(3)}±${t.se.toStringAsFixed(3)}'}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: c.pHolm < 0.05 ? (c.coef > 0 ? Colors.red.shade700 : Colors.blue.shade700) : Colors.grey.shade600))),
              Text(rep ? '재현 ✓' : c.pHolm < 0.05 ? 'Holm p=${c.pHolm.toStringAsFixed(3)}' : '유의X',
                  style: TextStyle(fontSize: 10, fontWeight: rep ? FontWeight.w800 : FontWeight.w400,
                      color: rep ? Colors.teal.shade800 : Colors.grey.shade500)),
            ]),
          );
        }),
      ],
    ]);
  }

  Widget _principles() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        Text('· 모든 유효한 로또 6/45 조합의 1등 당첨 확률은 동일합니다.', style: TextStyle(fontSize: 11, height: 1.5)),
        Text('· 구매예측은 당첨 확률 향상을 주장하지 않습니다.', style: TextStyle(fontSize: 11, height: 1.5)),
        Text('· 목표는 다른 구매자와 번호가 겹칠 위험을 추정하는 것입니다.', style: TextStyle(fontSize: 11, height: 1.5)),
        Text('· 당첨 시 실제 상금 분배 감소 효과는 검증 전까지 보장하지 않습니다.', style: TextStyle(fontSize: 11, height: 1.5)),
        Text('· 순방향 검증을 통과하지 못하면 휴리스틱으로 대체하지 않고 번호를 제공하지 않습니다.', style: TextStyle(fontSize: 11, height: 1.5)),
        Text('· 검증되지 않은 정확도·기대 수령액 증가율·인기 점수를 사실처럼 출력하지 않습니다.', style: TextStyle(fontSize: 11, height: 1.5)),
      ]);
}
