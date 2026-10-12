// 추천번호 화면 — A. 최종 추천번호(공식 최종 예측, 모든 사용자) / B. 구매예측 추천번호(관리자 전용)
//
// A 는 패턴 분석·엔진 브리핑과 같은 공식 최종 예측 스냅샷(OfficialPredictionService)을 그대로 표시한다.
// 일반 사용자에게는 엔진 내부 정보(버전·엔진 이름·스냅샷 등)를 보이지 않고, 관리자에게만 전체 출처를 보인다.
// Number 엔진 기본 조합(연구용)과 B(구매예측, 모델 내부 정보 포함)는 관리자 모드에서만 표시한다.
import 'package:flutter/material.dart';

import '../services/admin_gate.dart';
import '../services/research/final_recommendation_engine.dart';
import '../services/research/research_scheduler.dart';
import '../services/rpa_live_numbers.dart';
import '../widgets/purchase_recommend_card.dart';

class _RecommendData {
  final bool isAdmin;
  final int? target;
  final OfficialPrediction? official;
  final String? officialError;
  final RpaLiveNumbers? live; // 관리자 전용 · 연구용 Number 엔진 기본 조합
  const _RecommendData({required this.isAdmin, this.target, this.official, this.officialError, this.live});
}

class RecommendNumbersContent extends StatefulWidget {
  const RecommendNumbersContent({super.key});
  @override
  State<RecommendNumbersContent> createState() => _RecommendNumbersContentState();
}

class _RecommendNumbersContentState extends State<RecommendNumbersContent> {
  late Future<_RecommendData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RecommendData> _load() async {
    final admin = await AdminGate.isAdmin();
    final d = await ResearchScheduler.instance.load();
    if (d == null) return _RecommendData(isAdmin: admin);
    final target = d.targetRound;
    OfficialPrediction? official;
    String? err;
    try {
      official = await OfficialPredictionService.instance.load(target);
    } catch (e) {
      err = '$e';
    }
    RpaLiveNumbers? live;
    if (admin) {
      try {
        live = await RpaLiveNumbers.load(target);
      } catch (_) {}
    }
    return _RecommendData(isAdmin: admin, target: target, official: official, officialError: err, live: live);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F4F8),
      child: FutureBuilder<_RecommendData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data ?? const _RecommendData(isAdmin: false);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _section('A', '최종 추천번호',
                  data.isAdmin ? '공식 최종 예측 · $kFinalRecVersion' : '이번 회차 추천 조합',
                  Colors.deepPurple, _officialBody(data)),
              if (data.isAdmin) ...[
                const SizedBox(height: 14),
                Center(child: Text('── 아래는 다른 엔진(구매예측)의 결과입니다 · 관리자 전용 ──',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
                const SizedBox(height: 14),
                _section('B', '구매예측 추천번호', '구매자 선택 경향 추정 엔진', kPurchaseColor,
                    data.target == null ? const Text('데이터 없음') : PurchaseRecommendCard(targetRound: data.target)),
              ],
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

  // ── A. 공식 최종 추천번호 ─────────────────────────────────────
  Widget _officialBody(_RecommendData d) {
    final admin = d.isAdmin;
    if (d.target == null) {
      return Text('당첨번호 데이터를 불러오지 못했습니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600));
    }
    final o = d.official;
    if (o == null) {
      return Text(admin ? '${d.target}회 최종 예측을 불러오지 못했습니다: ${d.officialError}' : '추천번호를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600));
    }
    final f = o.hasSets ? o.rec : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('${o.targetRound}회 추천번호',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.deepPurple))),
        if (admin && f != null)
          statusChip(f.verifiedEdge ? '검증 신호 반영' : '검증된 당첨확률 우위 없음',
              f.verifiedEdge ? Colors.teal.shade700 : Colors.grey),
      ]),
      const SizedBox(height: 4),
      if (f != null)
        Text(admin ? officialProvenanceLine(o) : officialPublicLine(o),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.4)),
      if (admin && o.statusNote != null)
        Text(o.statusNote!, style: TextStyle(fontSize: 11, color: Colors.orange.shade900, height: 1.4)),
      const SizedBox(height: 10),
      if (f == null)
        Text('${o.targetRound}회 $kOfficialPreparingMessage', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))
      else
        ...f.sets.asMap().entries.map((e) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.deepPurple.shade100),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('추천 조합 ${e.key + 1}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.deepPurple.shade700)),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: e.value.map((n) => lottoBall(n)).toList()),
              ]),
            )),
      Text(admin && f != null ? f.note : '모든 번호 조합의 1등 당첨 확률은 같습니다. 추천번호는 참고용입니다.',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500, height: 1.4)),
      if (admin) _numberBaseResearchTile(d.live),
    ]);
  }

  // ── 관리자 전용 · 연구용 Number 엔진 기본 조합 (기본 접힘) ─────────
  Widget _numberBaseResearchTile(RpaLiveNumbers? live) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text('연구용 · Number 엔진 기본 조합 (최종 추천 아님)',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
        children: [
          if (live == null)
            Text('Number 엔진 기본 조합을 불러오지 못했습니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
          else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: live.baseLive ? statusChip('엔진 반영 · 실전', Colors.deepPurple) : statusChip('실전 아님', Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(live.note, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            if (live.baseSets.isEmpty)
              Text('표시할 엔진 기본 조합이 없습니다. 새 회차 처리 후 자동 생성됩니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500))
            else
              ...live.baseSets.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      SizedBox(width: 22, child: Text('${e.key + 1}', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade600))),
                      const SizedBox(width: 4),
                      Expanded(child: Row(children: e.value.map((n) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Opacity(opacity: live.baseLive ? 1 : 0.5, child: lottoBall(n, size: 24)))).toList())),
                    ]),
                  )),
            Text('Number Engine 기본 조합(연구용)입니다. 최종 추천번호와 혼합·덮어쓰기하지 않습니다.',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ],
        ],
      ),
    );
  }
}
