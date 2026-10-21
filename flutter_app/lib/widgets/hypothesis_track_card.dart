// 브리핑 ⑤ 가설 트랙 — 제미나이 가설을 검증 전에 바로 쓰는 '상상 예측' (번호 5세트 · 명당 5곳)
import 'package:flutter/material.dart';

import '../services/research/hypothesis_track.dart';
import 'briefing_store_widgets.dart' show FavoriteStoreStar, pct;
import 'purchase_recommend_card.dart' show lottoBall, statusChip;

const kTrackColor = Color(0xFF6A1B9A);

class HypothesisTrackCard extends StatefulWidget {
  final int target;

  /// 이번 회차 추천번호 공개 여부 (수요일 0시 · 수동 추천)
  final bool released;

  /// 테스트용 (null = 서버 조회)
  final Future<HypothesisTrack?> Function(int target)? loader;
  const HypothesisTrackCard({super.key, required this.target, this.released = true, this.loader});
  @override
  State<HypothesisTrackCard> createState() => _HypothesisTrackCardState();
}

class _HypothesisTrackCardState extends State<HypothesisTrackCard> {
  late Future<HypothesisTrack?> _f;
  bool _showHyps = false;

  @override
  void initState() {
    super.initState();
    _f = (widget.loader ?? HypothesisTrack.load)(widget.target);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('hypothesis_track'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kTrackColor.withValues(alpha: 0.35), width: 1.4),
      ),
      child: FutureBuilder<HypothesisTrack?>(
        future: _f,
        builder: (context, snap) {
          final t = snap.data;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 26, height: 26, alignment: Alignment.center,
                decoration: BoxDecoration(color: kTrackColor, borderRadius: BorderRadius.circular(8)),
                child: const Text('5', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('${widget.target}회 가설 트랙 — 제미나이 가설',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kTrackColor))),
              statusChip('가설 기반 · 검증 전', kTrackColor),
            ]),
            const SizedBox(height: 4),
            Text('AI 전략기획부(제미나이) 가설을 검증 통과를 기다리지 않고 바로 씁니다. 최근 200회에서 방향이 맞은 가설만 힘을 받고, '
                '실전에서 맞히면 커지고 틀리면 작아집니다. 기존 엔진(①~④)은 그대로 — 이 부서는 그 도구를 빌려 씁니다.',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
            const SizedBox(height: 10),
            if (snap.connectionState != ConnectionState.done)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
            else if (!widget.released)
              _note('${widget.target}회 가설 트랙은 수요일 0시(또는 수동 추천) 이후 서버가 만듭니다.')
            else if (t == null)
              _note('${widget.target}회 가설 트랙 저장본 없음 — 공개 후 서버 실행(엔진 실행 직후 · 매일 17시) 뒤 표시됩니다.')
            else
              ..._body(t),
          ]);
        },
      ),
    );
  }

  Widget _note(String s) => Text(s, style: TextStyle(fontSize: 12, color: Colors.orange.shade900));

  List<Widget> _body(HypothesisTrack t) {
    final nh = t.numberHyps;
    final (plays, hits) = t.totalRecord;
    final skipped = t.skipped.values.fold<int>(0, (a, b) => a + b);
    return [
      Text(
          '가설 ${t.hypothesesTotal}개 중 이번 회차 사용: 번호 ${nh.length}개 · 명당 ${t.storeHyps.length}개 '
          '(조건이 이번 회차와 안 맞거나 최근 200회 방향이 반대인 $skipped개 제외)'
          '${t.window.length == 2 ? ' · 기준 ${t.window[0]}~${t.window[1]}회' : ''}',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      if (plays > 0)
        Text('실전 성적: 가설 사용 $plays번 중 방향 맞힘 $hits번', style: TextStyle(fontSize: 11, color: Colors.green.shade800)),
      const SizedBox(height: 10),
      // 번호
      Row(children: [
        const Icon(Icons.confirmation_number_rounded, size: 16, color: kTrackColor),
        const SizedBox(width: 4),
        const Text('가설 번호 5세트', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
        const Spacer(),
        if (t.status == 'registered') statusChip('사전 등록', Colors.green.shade700),
      ]),
      Text(
          nh.isEmpty
              ? '이번 회차 조건에 맞는 번호 가설이 없어 인기 중간(50%) 조합입니다.'
              : '1~4등 당첨자 쏠림 가설 ${nh.length}개 → 인기 백분위 ${t.targetPct?.toStringAsFixed(0) ?? '-'}% 쪽 조합'
                  '${(t.drive ?? 0) > 0 ? ' (당첨조합이 인기 조합일 것)' : (t.drive ?? 0) < 0 ? ' (당첨조합이 비인기 조합일 것)' : ''}',
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
      const SizedBox(height: 6),
      for (final e in t.sets.asMap().entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(width: 18, child: Text('${e.key + 1}', style: const TextStyle(fontWeight: FontWeight.w900, color: kTrackColor))),
            ...e.value.numbers.map((n) => Padding(padding: const EdgeInsets.only(right: 3), child: lottoBall(n, size: 28))),
            const Spacer(),
            if (e.value.popularityPct != null)
              Text('인기 ${e.value.popularityPct!.toStringAsFixed(0)}%', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
          ]),
        ),
      const SizedBox(height: 8),
      // 명당
      const Row(children: [
        Icon(Icons.storefront_rounded, size: 16, color: kTrackColor),
        SizedBox(width: 4),
        Text('가설 명당 5곳', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
      ]),
      Text('가설마다 한 곳 — 그 가설 조건에 맞는 판매점 중 지방장 확률이 가장 높은 곳 (이력 전국 상위 20곳은 ④ 몫이라 제외)',
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
      const SizedBox(height: 6),
      if (t.stores.isEmpty) _note('이번 회차 명당 가설 없음'),
      for (final s in t.stores)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
          decoration: BoxDecoration(
            color: kTrackColor.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kTrackColor.withValues(alpha: 0.2)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(s.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
                  Text(pct(s.pAdj), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: kTrackColor)),
                ]),
                Text('${s.region.isEmpty ? s.address : s.region} · 1등 ${s.first} · 2등 ${s.second} · 지방장 ${pct(s.pFirst)} × 가설 ×${s.factor.toStringAsFixed(2)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
                if (t.whyOf(s) != null)
                  Text('가설: ${t.whyOf(s)}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: kTrackColor)),
              ]),
            ),
            FavoriteStoreStar(code: s.code, name: s.name),
          ]),
        ),
      TextButton(
        key: const ValueKey('track_hyps_toggle'),
        onPressed: () => setState(() => _showHyps = !_showHyps),
        child: Text(_showHyps ? '사용한 가설 접기' : '사용한 가설 ${t.used.length}개 보기', style: const TextStyle(fontSize: 12)),
      ),
      if (_showHyps)
        for (final h in t.used)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
                '· ${h.statement}'
                '${h.z != null ? ' — 최근 200회 z ${h.z!.toStringAsFixed(2)}' : ''}'
                '${h.factor != null ? ' · 배수 ×${h.factor!.toStringAsFixed(2)}' : ''}'
                '${h.m != null ? ' · 실전 성적 ×${h.m!.toStringAsFixed(2)}' : ''}'
                '${h.status == 'rejected' ? ' (가설 공장 기각 · 그래도 사용)' : h.status == 'validated' || h.status == 'maintained' ? ' (검증 통과)' : ''}',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800)),
          ),
      const SizedBox(height: 4),
      Text('가설 기반 예측입니다 — 측정된 확률이 아닙니다. 복권 한 장의 1등 확률(1/8,145,060)은 어떤 번호·가게든 같습니다.',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.4)),
    ];
  }
}
