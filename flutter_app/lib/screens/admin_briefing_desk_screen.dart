// AI 브리핑전담부서 — 당첨번호와 지난 회차 브리핑 추천번호를 보고, 흐름을 유지할 곳은 두고 보완할 곳을 찾아 각 메뉴에 전달 (제미나이 상주)
//   서버 research_set_review.py (sr-1.0) 저장본만 읽는다. 엔진·비인기·구매예측 엔진 자체는 바꾸지 않는다.
//   전달: 브리핑 ①~④ 메뉴 카드(BriefingDeskMemo) · 제미나이 가설 트랙(보완 규칙) · AI 전략기획부 가설 생성 자료
import 'package:flutter/material.dart';

import '../services/research/set_review.dart';
import '../widgets/set_review_card.dart';

const _c = Color(0xFF4A148C);

class AdminBriefingDeskScreen extends StatefulWidget {
  final Future<SetReview?> Function()? loader;
  const AdminBriefingDeskScreen({super.key, this.loader});
  @override
  State<AdminBriefingDeskScreen> createState() => _AdminBriefingDeskScreenState();
}

class _AdminBriefingDeskScreenState extends State<AdminBriefingDeskScreen> {
  late final Future<SetReview?> _f = (widget.loader ?? SetReview.loadLatest)();

  Widget _card(Widget child, {Color? border}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: (border ?? _c).withValues(alpha: 0.25)),
        ),
        child: child,
      );

  Widget _tagLine(String tag, String text, Color c) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 1, right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
            child: Text(tag, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.45))),
        ]),
      );

  Widget _role() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF2A0A5E), _c, Color(0xFF7B1FA2)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.support_agent_rounded, color: Colors.white, size: 22),
            SizedBox(width: 6),
            Text('AI 브리핑전담부서', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          ]),
          const SizedBox(height: 8),
          for (final t in const [
            '① 매주 당첨번호와 지난 회차 브리핑 추천번호(엔진 · 비인기 · 구매예측 · 제미나이)를 영역별로 비교',
            '② 흐름이 맞은 곳은 유지, 반대였던 곳은 보완 — 제미나이가 영역별 지시를 씀',
            '③ 브리핑 각 메뉴 카드 · 제미나이 가설 번호 · AI 전략기획부 다음 가설 생성에 전달',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(t, style: TextStyle(fontSize: 12, height: 1.4, color: Colors.white.withValues(alpha: 0.9))),
            ),
          const SizedBox(height: 4),
          Text('모든 조합의 1등 확률은 같습니다(1/8,145,060). 부서의 보완은 흐름을 맞추려는 가설 기반 조정입니다.',
              style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.7))),
        ]),
      );

  Widget _areas(SetReview r) => _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${r.round}회 → ${r.targetRound}회 영역별 판정',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1A1446)))),
          Container(
            key: const ValueKey('desk_ai_status'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: (r.fromGemini ? _c : Colors.orange.shade800).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(r.fromGemini ? '제미나이 상주 · 판정 완료' : '제미나이 실패 → 기본 규칙 (다음 실행 때 다시)',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: r.fromGemini ? _c : Colors.orange.shade800)),
          ),
        ]),
        if (r.areas.every((a) => a.keep.isEmpty && a.improve.isEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('이 회차는 영역별 판정 전에 만든 복기입니다 — 다음 복기부터 유지/보완이 나옵니다.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
          ),
        for (final a in r.areas) ...[
          const Divider(height: 18),
          Text('${a.label} · 최고 ${a.bestHits}개 일치 · 당첨 ${a.won}세트',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          if (a.keep.isNotEmpty) _tagLine('유지', a.keep.replaceFirst(RegExp(r'^유지\s*[—-]\s*'), ''), const Color(0xFF2E7D32)),
          if (a.improve.isNotEmpty) _tagLine('보완', a.improve.replaceFirst(RegExp(r'^보완\s*[—-]\s*'), ''), const Color(0xFFE65100)),
        ],
      ]));

  Widget _delivered(SetReview r) => _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('전달 내역', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1A1446))),
        const SizedBox(height: 6),
        for (final (to, what) in [
          ('브리핑 ①~④ 메뉴 카드', '각 카드 아래 유지 / 보완 한 줄'),
          ('④ 제미나이 가설 번호 (${r.targetRound}회)', '보완 규칙 ${r.rules.length}개 — 가설처럼 함께 써서 번호 선정'),
          ('AI 전략기획부', '다음 가설 생성 자료에 보완 지시 포함 → 보완할 곳을 시험하는 가설 우선 제안'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.arrow_forward_rounded, size: 15, color: _c),
              const SizedBox(width: 4),
              Expanded(child: Text.rich(TextSpan(children: [
                TextSpan(text: '$to  ', style: const TextStyle(fontWeight: FontWeight.w900)),
                TextSpan(text: what),
              ]), style: const TextStyle(fontSize: 12, height: 1.4))),
            ]),
          ),
        for (final x in r.rules)
          Padding(
            padding: const EdgeInsets.only(left: 19, top: 2),
            child: Text('· ${x.statement}', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800)),
          ),
      ]));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF8F5FF),
        appBar: AppBar(
          title: const Text('AI 브리핑전담부서', style: TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: _c,
          foregroundColor: Colors.white,
        ),
        body: FutureBuilder<SetReview?>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final r = snap.data;
            return ListView(padding: const EdgeInsets.all(16), children: [
              _role(),
              if (r == null)
                _card(Text(snap.hasError ? '부서 자료를 불러오지 못했습니다.' : '아직 복기가 없습니다 — 추첨 뒤 매일 17시 서버가 복기합니다.',
                    style: const TextStyle(fontSize: 12.5)))
              else ...[
                _areas(r),
                _delivered(r),
                SetReviewCard(loader: () async => r),
              ],
            ]);
          },
        ),
      );
}
