// AI 전략기획부 로또 탭 — 추천번호 복기 (지난 회차 추천 20세트 vs 당첨번호 → 아쉬운 부분 → 보완 규칙 → 제미나이 추천번호 반영)
import 'package:flutter/material.dart';

import '../services/research/set_review.dart';
import 'winning_number_boxes.dart';

const _c = Color(0xFF6A1B9A);

class SetReviewCard extends StatefulWidget {
  final Future<SetReview?> Function()? loader;
  const SetReviewCard({super.key, this.loader});
  @override
  State<SetReviewCard> createState() => _SetReviewCardState();
}

class _SetReviewCardState extends State<SetReviewCard> {
  late final Future<SetReview?> _f = (widget.loader ?? SetReview.loadLatest)();
  bool _open = false;

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
      );

  Widget _small(String s, {Color? color}) =>
      Text(s, style: TextStyle(fontSize: 11.5, color: color ?? Colors.grey.shade700, height: 1.4));

  @override
  Widget build(BuildContext context) => FutureBuilder<SetReview?>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
          final r = snap.data;
          return Container(
            key: const ValueKey('set_review_card'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _c.withValues(alpha: 0.3)),
            ),
            child: r == null ? _empty(snap.hasError) : _body(r),
          );
        },
      );

  Widget _title(String t, {Widget? chip}) => Row(children: [
        const Icon(Icons.fact_check_rounded, color: _c, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1A1446)))),
        ?chip,
      ]);

  Widget _empty(bool error) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('추천번호 복기'),
        const SizedBox(height: 6),
        _small(error
            ? '복기 자료를 불러오지 못했습니다.'
            : '아직 복기가 없습니다 — 추첨 뒤 매일 17시(AI 전략기획부)에 지난 회차 추천 20세트를 당첨번호와 맞춰 보고 보완 규칙을 만듭니다.'),
      ]);

  Widget _body(SetReview r) {
    final missed = r.features.where((f) => f.missed).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('추천번호 복기 · ${r.round}회 → ${r.targetRound}회 보완',
          chip: _pill(r.fromGemini ? '제미나이' : '규칙 대체', r.fromGemini ? _c : Colors.grey.shade700)),
      const SizedBox(height: 4),
      _small('브리핑 4영역 추천 ${r.setCount}세트를 ${r.round}회 당첨번호와 맞춰 보고, 아쉬운 부분을 다음 회차 제미나이 추천번호(가설 트랙)에 반영합니다.'),
      const SizedBox(height: 8),
      Wrap(spacing: 3, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final n in r.actual) numberBall('$n', lottoRangeColor(n), size: 26, fontSize: 11),
        const Text(' + ', style: TextStyle(fontWeight: FontWeight.w900)),
        numberBall('${r.bonus}', lottoRangeColor(r.bonus), size: 26, fontSize: 11),
      ]),
      const SizedBox(height: 6),
      Text('최고 ${r.bestHits}개 일치 · 당첨 ${r.wonSets}세트',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
      for (final a in r.areas) _small('${a.label}: 최고 ${a.bestHits}개 일치 · 당첨 ${a.won}세트'),
      if (r.summary.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: _c.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
          child: Text(r.summary, style: const TextStyle(fontSize: 12, height: 1.45)),
        ),
      ],
      const SizedBox(height: 10),
      const Text('아쉬운 부분', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      if (missed.isEmpty) _small('특징 방향은 추천 세트가 대체로 맞혔습니다.'),
      for (final f in missed)
        _small('· ${f.name}: 당첨 ${f.actual} (${f.actualSide == 'higher' ? '높은' : '낮은'} 쪽) — 같은 쪽 세트 ${f.sameSets}/${r.setCount}',
            color: Colors.red.shade700),
      if (r.missedNumbers.isNotEmpty) _small('· 20세트 어디에도 없던 당첨번호: ${r.missedNumbers.join(', ')}', color: Colors.red.shade700),
      if (r.overNumbers.isNotEmpty) _small('· 여러 세트에 몰렸지만 안 나온 번호: ${r.overNumbers.join(', ')}'),
      const SizedBox(height: 10),
      Row(children: [
        const Expanded(child: Text('보완 규칙 → 제미나이 추천번호', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900))),
        _pill('${r.targetRound}회 가설 트랙 반영', const Color(0xFF2E7D32)),
      ]),
      const SizedBox(height: 4),
      if (r.rules.isEmpty) _small('이번 주는 보완할 규칙이 없습니다.'),
      for (final x in r.rules)
        Container(
          key: ValueKey('set_review_rule_${x.code}'),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF3E5F5), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(x.statement, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            if (x.why.isNotEmpty) _small(x.why),
            _small('힘 ${x.w.toStringAsFixed(2)} · 최근 ${x.weeks}회 중 ${x.repeat}회 같은 방향으로 어긋남', color: _c),
          ]),
        ),
      InkWell(
        key: const ValueKey('set_review_toggle'),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Text(_open ? '특징별 비교 접기' : '특징별 비교 보기', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _c)),
            Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: _c, size: 18),
          ]),
        ),
      ),
      if (_open)
        for (final f in r.features)
          _small('${f.name}: 당첨 ${f.actual} · 최근 200회 중앙값 ${f.median?.toStringAsFixed(1) ?? '-'} · '
              '추천 평균 ${f.setsMean?.toStringAsFixed(1) ?? '-'} · 같은 쪽 ${f.sameSets}/${r.setCount}${f.missed ? ' · 어긋남' : ''}'),
      if (r.lookback.isNotEmpty) _small('반복 확인 회차: ${r.lookback.join(', ')}'),
      _small('모든 조합의 1등 확률은 같습니다(1/8,145,060). 보완 규칙은 가설 기반입니다.'),
    ]);
  }
}
