// 전국 지방장 에이전트 ag-1.1 — 실전형 재현 기록 공용 위젯 (관리자 전용 연구 기능)
//
// * ReplayLineChart              : 외부 패키지 없이 CustomPainter 로 그리는 꺾은선 차트
// * ReplayBriefingView           : 사전(pre) / 사후(post) 브리핑 payload 표시
// * AgentReplayPostSummaryCard   : 최신 사후 브리핑 요약 + '회차별 사전·사후 브리핑 보기'
// * AgentFrozenRecommendation    : (지역, 목표 회차) 당시 동결된 추천 + 사후 검증
//
// 모든 데이터는 research_replay_* 읽기 전용 조회 결과이며, 값이 없으면 '-' / '데이터 없음'으로 표시한다.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/admin_agent_replay_screen.dart';
import '../services/research/agent_replay_repository.dart';
import '../services/research/agent_research_repository.dart';
import '../services/route/region_research_repository.dart';
import 'admin_region_store_widgets.dart' show regionTag, hypothesisStatusColor;
import 'agent_store_widgets.dart';

const Color kReplayColor = Color(0xFF37474F);

/// 실전 / 사후 재현 배지
Widget replayModeBadge(String? mode) =>
    regionTag(replayModeShort(mode), isReplayLiveMode(mode) ? Colors.green : Colors.deepOrange);

/// 재현 상태 안내 (미적용·데이터 없음·오류)
Widget replayStateNote(ResearchAvailability s, {String? message}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: s == ResearchAvailability.error ? Colors.red.shade50 : Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        s == ResearchAvailability.notApplied
            ? '$kReplayNotApplied — research_v6_replay.sql 적용 및 서버 재현 Worker 실행 후 표시됩니다.'
            : replayStateLabel(s, message: message),
        style: TextStyle(
            fontSize: 11.5, color: s == ResearchAvailability.error ? Colors.red.shade800 : Colors.blueGrey.shade800),
      ),
    );

String _n(dynamic v, [int d = 2]) => fmtNum(v, d);

/// 과거 회차 화면의 구역 머리말 ('사전 예측 (동결)' / '실제 결과' / '사후 검증')
Widget replaySectionHeader(String title, String subtitle, IconData icon, MaterialColor color) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: color.shade50,
        // 한쪽 테두리만 쓰므로 borderRadius 는 두지 않는다 (불균일 테두리 + radius 는 렌더링 오류)
        border: Border(left: BorderSide(color: color.shade400, width: 4)),
      ),
      child: Row(children: [
        Icon(icon, size: 17, color: color.shade800),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: color.shade900)),
            Text(subtitle, style: TextStyle(fontSize: 10.5, color: color.shade800)),
          ]),
        ),
      ]),
    );

// ═══════════════════════════════════════════════════════════════════════
// 꺾은선 차트 (CustomPainter)
// ═══════════════════════════════════════════════════════════════════════

class ReplayChartSeries {
  final String label;
  final Color color;
  final List<double?> values;
  const ReplayChartSeries(this.label, this.color, this.values);
}

class ReplayLineChart extends StatelessWidget {
  final List<int> xs;
  final List<ReplayChartSeries> series;
  final double height;
  final int yDecimals;
  const ReplayLineChart({super.key, required this.xs, required this.series, this.height = 180, this.yDecimals = 2});

  @override
  Widget build(BuildContext context) {
    final hasData = series.any((s) => s.values.any((v) => v != null && v.isFinite));
    if (xs.isEmpty || !hasData) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('차트 자료 없음 ($kResearchNoData)', style: TextStyle(fontSize: 11.5)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _LinePainter(xs: xs, series: series, yDecimals: yDecimals)),
      ),
      const SizedBox(height: 4),
      Wrap(spacing: 10, runSpacing: 2, children: [
        for (final s in series)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 14, height: 3, color: s.color),
            const SizedBox(width: 4),
            Text(s.label, style: const TextStyle(fontSize: 10.5)),
          ]),
      ]),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  final List<int> xs;
  final List<ReplayChartSeries> series;
  final int yDecimals;
  _LinePainter({required this.xs, required this.series, required this.yDecimals});

  void _text(Canvas c, String s, Offset o, {TextAlign align = TextAlign.left, double size = 9}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: Colors.black54)),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    var dx = o.dx;
    if (align == TextAlign.right) dx -= tp.width;
    if (align == TextAlign.center) dx -= tp.width / 2;
    tp.paint(c, Offset(dx, o.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, right = 8.0, top = 8.0, bottom = 18.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    if (w <= 0 || h <= 0) return;
    var lo = double.infinity, hi = -double.infinity;
    for (final s in series) {
      for (final v in s.values) {
        if (v == null || !v.isFinite) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (!lo.isFinite) return;
    if ((hi - lo).abs() < 1e-12) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.06;
    lo -= pad;
    hi += pad;
    final n = xs.length;
    double px(int i) => left + (n <= 1 ? w / 2 : w * i / (n - 1));
    double py(double v) => top + h * (1 - (v - lo) / (hi - lo));

    final grid = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final v = lo + (hi - lo) * g / 3;
      final y = py(v);
      canvas.drawLine(Offset(left, y), Offset(left + w, y), grid);
      _text(canvas, v.toStringAsFixed(yDecimals), Offset(left - 4, y), align: TextAlign.right);
    }
    _text(canvas, '${xs.first}회', Offset(left, size.height - 7));
    if (n > 1) _text(canvas, '${xs.last}회', Offset(left + w, size.height - 7), align: TextAlign.right);

    for (final s in series) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final dot = Paint()..color = s.color;
      var pts = <Offset>[];
      void flush() {
        if (pts.length == 1) {
          canvas.drawCircle(pts.first, 2, dot);
        } else if (pts.length > 1) {
          final path = Path()..moveTo(pts.first.dx, pts.first.dy);
          for (final o in pts.skip(1)) {
            path.lineTo(o.dx, o.dy);
          }
          canvas.drawPath(path, paint);
        }
        pts = <Offset>[];
      }

      for (var i = 0; i < n && i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null || !v.isFinite) {
          flush();
          continue;
        }
        pts.add(Offset(px(i), py(v)));
      }
      flush();
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.xs != xs || old.series != series;
}

// ═══════════════════════════════════════════════════════════════════════
// 사전 / 사후 브리핑
// ═══════════════════════════════════════════════════════════════════════

Widget _t(String s, {Color? color, double size = 11.5, FontWeight? weight}) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(s, style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.4)),
    );

Widget _sub(String s) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(s, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: kReplayColor)),
    );

Widget _hypLine(BuildContext context, AgentHypothesis h, {String? prefix}) {
  final stores = h.relatedStores;
  final regions = h.relatedRegions.where((r) => r != 'internet').toList();
  VoidCallback? onTap;
  if (stores.isNotEmpty) {
    onTap = () => showAgentStoreSheet(context, stores.first);
  } else if (regions.isNotEmpty) {
    onTap = () => openRegionResearch(context, regions.first);
  }
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${prefix ?? ''}${h.summary}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
            Text(
                '${h.agentId.isEmpty ? '' : '${agentLabel(h.agentId)} · '}${h.kindLabel}'
                ' · 검증 ${h.testK ?? '-'}건 / 기대 ${h.testExpected == null ? '-' : h.testExpected!.toStringAsFixed(2)}'
                ' · p=${fmtP(h.testP)}',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
            for (final l in agentVerdictDetailLines(h))
              Text(l, style: TextStyle(fontSize: 10, color: agentVerdictColor(h.verdict).shade800)),
          ]),
        ),
        const SizedBox(width: 6),
        agentVerdictTag(h),
      ]),
    ),
  );
}

Widget _countTags(Map<String, int> m, {bool status = false}) {
  if (m.isEmpty) return _t('-', color: Colors.grey.shade600);
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Wrap(spacing: 4, runSpacing: 3, children: [
      for (final e in m.entries)
        regionTag(
            '${kAgentHypStatusLabel[e.key] ?? kAgentHypKindLabel[e.key] ?? e.key} ${e.value}',
            status ? hypothesisStatusColor(e.key) : Colors.blueGrey),
    ]),
  );
}

class ReplayBriefingView extends StatelessWidget {
  final ReplayBriefing briefing;

  /// 브리핑 payload 에 replay_mode 가 없을 때 쓸 회차 모드
  final String? fallbackMode;
  const ReplayBriefingView({super.key, required this.briefing, this.fallbackMode});

  @override
  Widget build(BuildContext context) => briefing.isPre ? _pre(context) : _post(context);

  Widget _header(String text, IconData icon) => Row(children: [
        Icon(icon, color: kReplayColor, size: 18),
        const SizedBox(width: 6),
        Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: kReplayColor))),
      ]);

  List<Widget> _lines() => [
        if (briefing.lines.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final l in briefing.lines) _t('• $l'),
        ],
      ];

  Widget _pre(BuildContext context) {
    final b = briefing;
    final mode = b.replayMode ?? fallbackMode;
    final focus = b.focusRegions;
    final top = b.topStores;
    final live = b.liveApplied;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header('마스터, ${b.targetRound}회 사전 브리핑입니다.', Icons.schedule),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 3, children: [
        replayModeBadge(mode),
        regionTag('${b.availableThrough ?? '-'}회까지 데이터', Colors.blueGrey),
        regionTag('가설 ${b.activeHypotheses ?? '-'}건 보유', Colors.indigo),
        regionTag('실전 반영 ${live.length}건', live.isEmpty ? Colors.brown : Colors.green),
        regionTag('탐색 발화 ${b.exploreFired ?? '-'}건', Colors.blueGrey),
        regionTag('신규 가설 ${b.newHypothesesCount ?? '-'}건', Colors.deepPurple),
      ]),
      _t(replayModeLong(mode), size: 10.5, color: isReplayLiveMode(mode) ? Colors.green.shade800 : Colors.deepOrange.shade800),
      ..._lines(),
      _sub('주목 지역 (동결)'),
      if (focus.isEmpty) _t(kResearchNoData, color: Colors.grey.shade600) else ...focus.take(10).map((f) => agentFocusRegionRow(context, f)),
      _sub('전국 추천 상위 (동결)'),
      if (top.isEmpty)
        _t(kResearchNoData, color: Colors.grey.shade600)
      else
        for (var i = 0; i < top.length && i < 10; i++) agentCentralStoreRow(context, top[i], i + 1),
      _sub('실전 반영 가설'),
      if (live.isEmpty)
        _t('실전 반영된 검증 통과 가설 없음 — 이력 기반 후보', color: Colors.brown.shade700)
      else
        ...live.take(6).map((h) => _hypLine(context, h)),
      _sub('신규 가설 유형 · 상태'),
      _countTags(b.newHypothesesByKind),
      _countTags(b.statusCounts, status: true),
      _t('점수 = $kAgentScoreLabel. $kReplaySalesCaution', color: Colors.black45, size: 10),
    ]);
  }

  Widget _post(BuildContext context) {
    final b = briefing;
    final ag = b.agents;
    final ce = b.central;
    final trend = b.trend;
    final firstStores = b.actualFirstStores;
    final changes = b.hypothesisChangeCounts;
    final examples = b.hypothesisChangeExamples;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header('마스터, ${b.targetRound}회 사후 검증 브리핑입니다.', Icons.fact_check_outlined),
      ..._lines(),
      _sub('실제 결과 대조'),
      _t('1등 지역: ${b.actualFirstRegions.isEmpty ? '-' : b.actualFirstRegions.map(agentLabel).join(', ')}'),
      _t('주목 지역 적중: ${b.focusHitRegions.isEmpty ? '없음' : b.focusHitRegions.map(agentLabel).join(', ')}',
          color: b.focusHitRegions.isEmpty ? null : Colors.green.shade800),
      if (firstStores.isEmpty)
        _t('1등 판매점: -')
      else
        for (final s in firstStores.take(10))
          InkWell(
            onTap: (s['store_code'] ?? '').toString().isEmpty
                ? null
                : () => showAgentStoreSheet(context, s['store_code'].toString(), name: s['name']?.toString()),
            child: _t('1등 ${s['name'] ?? s['store_code'] ?? '-'} · ${agentLabel(s['agent_id']?.toString())}'),
          ),
      _sub('지방장 납품 합계'),
      _t('1·2등 적중 ${_n(ag['hits_any'])}건 (1등 ${_n(ag['hits_first'])}) · 무작위 기대 ${_n(ag['expected_uniform'])}건'),
      _t('이력 기준 ${_n(ag['history_hits'])}건 · 탐색 ${_n(ag['explore_hits'])}건'),
      if (b.rank1Hits.isNotEmpty)
        _t('1순위 적중: ${b.rank1Hits.take(6).map((h) => '${h['name'] ?? h['store_code'] ?? '-'}(${agentLabel(h['agent_id']?.toString())})').join(', ')}',
            color: Colors.green.shade800),
      _sub('중앙 엔진 vs 기준'),
      _t('log-loss 모델 ${_n(ce['logloss_model'], 4)} · m0(판매점 수 비례) ${_n(ce['logloss_m0'], 4)} (낮을수록 좋음)'),
      _t('주목 지역 1등 적중 ${_n(ce['focus_hits'])} · m0 ${_n(ce['focus_hits_m0'])}'),
      _sub('가설 상태 변화'),
      if (changes.isEmpty)
        _t('상태 변화 없음', color: Colors.grey.shade600)
      else
        Wrap(spacing: 4, runSpacing: 3, children: [
          for (final e in changes.entries) regionTag('${_transition(e.key)} ${e.value}', Colors.blueGrey),
        ]),
      for (final ex in examples.take(5))
        _hypLine(context, AgentHypothesis.fromMap(ex),
            prefix: '[${kAgentHypStatusLabel[ex['from']] ?? ex['from'] ?? '-'} → ${kAgentHypStatusLabel[ex['to']] ?? ex['to'] ?? '-'}] '),
      if (trend.isNotEmpty) ...[
        _sub('추세'),
        _t('이번 회차 skill ${_n(trend['skill_round'], 4)} · 최근 30회 skill ${_n(trend['skill_trailing30'], 4)}'),
        if (trend['reason'] != null) _t('${trend['reason']}', color: Colors.grey.shade700, size: 10.5),
      ],
      _t(kReplaySalesCaution, color: Colors.black45, size: 10),
    ]);
  }

  static String _transition(String k) {
    final parts = k.split(RegExp('→|->'));
    if (parts.length != 2) return k;
    return '${kAgentHypStatusLabel[parts[0].trim()] ?? parts[0]}→${kAgentHypStatusLabel[parts[1].trim()] ?? parts[1]}';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 엔진 브리핑용 최신 사후 브리핑 요약
// ═══════════════════════════════════════════════════════════════════════

class AgentReplayPostSummaryCard extends StatefulWidget {
  const AgentReplayPostSummaryCard({super.key});
  @override
  State<AgentReplayPostSummaryCard> createState() => _AgentReplayPostSummaryCardState();
}

class _AgentReplayPostSummaryCardState extends State<AgentReplayPostSummaryCard> {
  final _repo = AgentReplayRepository();
  late Future<ResearchLoad<ReplayBriefing?>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.loadLatestPostBriefing();
  }

  void _open(int? round) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => AdminAgentReplayScreen(initialRound: round)));

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kReplayColor.withValues(alpha: 0.25)),
      ),
      child: FutureBuilder<ResearchLoad<ReplayBriefing?>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('실전형 재현 사후 브리핑을 확인하고 있습니다…', style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
            ]);
          }
          final load = snap.data;
          final b = load?.data;
          final link = Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _open(b?.targetRound),
              icon: const Icon(Icons.history_edu, size: 16),
              label: const Text('회차별 사전·사후 브리핑 보기', style: TextStyle(fontSize: 12)),
            ),
          );
          if (b == null) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('지방장 실전형 재현 (${_repo.runId})',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kReplayColor)),
              replayStateNote(load?.state ?? ResearchAvailability.error, message: load?.message ?? '${snap.error}'),
              link,
            ]);
          }
          final ag = b.agents;
          final ce = b.central;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.fact_check_outlined, color: kReplayColor, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text('마스터, ${b.targetRound}회 사후 검증 브리핑입니다.',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: kReplayColor)),
              ),
              regionTag(_repo.runId, Colors.blueGrey),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 3, children: [
              regionTag('지방장 적중 ${_n(ag['hits_any'])} / 무작위 기대 ${_n(ag['expected_uniform'])}', Colors.indigo),
              regionTag('이력 기준 ${_n(ag['history_hits'])}', Colors.blueGrey),
              regionTag('log-loss ${_n(ce['logloss_model'], 3)} vs m0 ${_n(ce['logloss_m0'], 3)}', Colors.teal),
              regionTag('주목 지역 적중 ${_n(ce['focus_hits'])} (m0 ${_n(ce['focus_hits_m0'])})', Colors.teal),
            ]),
            const SizedBox(height: 4),
            for (final l in b.lines.take(4)) _t('• $l'),
            _t('사후 검증 = 추첨 결과 반영 후 동결 예측을 채점한 기록. $kReplaySalesCaution',
                color: Colors.black45, size: 10),
            link,
          ]);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 지역 추천 — 당시 동결된 추천
// ═══════════════════════════════════════════════════════════════════════

class _FrozenData {
  final ResearchLoad<ReplayAgentRound?> frozen;
  final ResearchLoad<ReplayPrediction?> prediction;
  final ResearchLoad<ReplayResult?> result;
  final Map<String, String> names;
  const _FrozenData(this.frozen, this.prediction, this.result, this.names);
}

/// (지역, 과거 목표 회차) — 세 구역으로 분리해 표시한다.
///   1) 사전 예측 (동결): 추첨 전 동결된 지방장 추천 + 당시 중앙 엔진 지역 평가 (적중 표시 없음)
///   2) 실제 결과: 그 회차 추첨 결과 중 이 지역 관련 사실 (research_replay_results · 지방장 검증 행)
///   3) 사후 검증: 동결 추천을 실제 결과로 채점한 기록 (research_replay_agent_evals)
class AgentFrozenRecommendation extends StatefulWidget {
  final String regionId;
  final int targetRound;
  const AgentFrozenRecommendation({super.key, required this.regionId, required this.targetRound});

  @override
  State<AgentFrozenRecommendation> createState() => _AgentFrozenRecommendationState();
}

class _AgentFrozenRecommendationState extends State<AgentFrozenRecommendation> {
  final _repo = AgentReplayRepository();
  late Future<_FrozenData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_FrozenData> _load() async {
    final f = await _repo.loadFrozen(widget.regionId, widget.targetRound);
    final p = await _repo.loadPredictionWithRegions(widget.targetRound);
    final res = await _repo.loadResult(widget.targetRound);
    final codes = <String>{...?f.data?.storeIds, ...?res.data?.firstStoreIds};
    final names = codes.isEmpty ? const <String, String>{} : await _repo.storeNames(codes);
    return _FrozenData(f, p, res, names);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FrozenData>(
      future: _future,
      builder: (context, snap) {
        final title = Text('${widget.targetRound}회 · ${RegionIds.display(widget.regionId)} — 과거 회차 기록',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kAgentColor));
        if (snap.connectionState != ConnectionState.done) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            title,
            const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
          ]);
        }
        if (snap.hasError || snap.data == null) {
          return replayStateNote(ResearchAvailability.error, message: '${snap.error}');
        }
        final d = snap.data!;
        final r = d.frozen.data;
        final p = d.prediction.data;
        final result = d.result.data;
        final e = r?.eval;
        final children = <Widget>[title, const SizedBox(height: 4)];

        // ── 1) 사전 예측 (동결) ─────────────────────────────────────────
        children.add(replaySectionHeader(
            '사전 예측 (동결)',
            r == null
                ? '$kReplayFrozenLabel 없음'
                : '$kReplayFrozenLabel — ${r.availableThrough ?? '-'}회까지 데이터, 결과를 모르는 상태',
            Icons.lock_clock,
            Colors.indigo));
        if (r == null) {
          children.add(replayStateNote(d.frozen.state,
              message: d.frozen.state == ResearchAvailability.noData
                  ? '이 회차에 이 지역의 동결 추천 기록 없음'
                  : d.frozen.message));
        } else {
          children.add(Wrap(spacing: 4, runSpacing: 3, children: [
            replayModeBadge(r.replayMode),
            regionTag('${r.availableThrough ?? '-'}회까지 데이터', Colors.blueGrey),
            regionTag('판매점 ${r.nStores ?? '-'}곳 중 상위 ${r.storeIds.length}', Colors.blueGrey),
          ]));
          children.add(_t(replayModeLong(r.replayMode),
              size: 10.5, color: r.isLive ? Colors.green.shade800 : Colors.deepOrange.shade800));
          final f = p?.regionOf(widget.regionId);
          children.add(_t(
              f == null
                  ? '당시 중앙 엔진 지역 평가: ${p == null ? kResearchNoData : '목록에 없음'}'
                  : '당시 중앙 엔진 지역 평가: ${f.rank ?? '-'}위 · p ${fmtNum(f.p, 3)} · 기준 ${fmtNum(f.base, 3)} · ×${fmtNum(f.ratio)}',
              weight: FontWeight.w700,
              color: f != null && (f.rank ?? 999) <= kAgentFocusTop ? Colors.green.shade800 : Colors.brown.shade700));
          for (var i = 0; i < r.storeIds.length; i++) {
            final code = r.storeIds[i];
            final applied = r.appliedAt(i);
            final lf = r.liveFactorAt(i);
            children.add(InkWell(
              onTap: () => showAgentStoreSheet(context, code, name: d.names[code]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                      width: 24,
                      child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kAgentColor))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.names[code] ?? code, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      Text(
                          '코드 $code · 점수 ${fmtScore(r.scoreAt(i))}'
                          '${lf == null ? '' : ' · live ×${lf.toStringAsFixed(3)}'}'
                          '${applied.isEmpty ? '' : ' · 실전 반영 가설 ${applied.length}건'}',
                          style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
                    ]),
                  ),
                ]),
              ),
            ));
          }
          children.add(_t('점수 = $kAgentScoreLabel. $kReplaySalesCaution', color: Colors.black45, size: 10));
        }

        // ── 2) 실제 결과 ───────────────────────────────────────────────
        children.add(replaySectionHeader(
            '실제 결과',
            result == null && e == null ? '추첨 결과 반영 전' : '${widget.targetRound}회 추첨 결과 (예측과 분리)',
            Icons.emoji_events_outlined,
            Colors.brown));
        if (result == null && e == null) {
          children.add(d.result.state == ResearchAvailability.noData || d.result.state == ResearchAvailability.available
              ? _t('추첨 결과 반영 전 — 실제 결과 없음', color: Colors.grey.shade700)
              : replayStateNote(d.result.state, message: d.result.message));
        } else {
          if (result != null) {
            final inRegion = result.firstRegions.contains(widget.regionId);
            children.add(_t(
                '이 지역 1등 발생: ${inRegion ? '있음' : '없음'} (전국 1등 지역 ${result.firstRegions.length}곳)',
                weight: FontWeight.w700,
                color: inRegion ? Colors.green.shade800 : null));
          }
          if (e != null) {
            children.add(_t('이 지역 실제 1·2등 판매점 ${e.regionEvents ?? '-'}곳 (1등 ${e.regionFirst ?? '-'}곳)'));
          }
          if (result != null && r != null) {
            final firstHere = result.firstStoreIds.where(r.storeIds.contains).toList();
            if (firstHere.isNotEmpty) {
              children.add(_t('추천 목록 안의 1등 판매점: ${firstHere.map((c) => d.names[c] ?? c).join(', ')}',
                  color: Colors.green.shade800));
            }
          }
          if (result?.verifiedAt != null) {
            children.add(_t('결과 확인 ${result!.verifiedAt!.replaceFirst('T', ' ').split('.').first}',
                size: 10, color: Colors.black45));
          }
        }

        // ── 3) 사후 검증 ───────────────────────────────────────────────
        children.add(replaySectionHeader(
            '사후 검증',
            e == null ? '검증 전 — 적중 여부 없음' : '동결 추천을 실제 결과로 채점',
            Icons.fact_check_outlined,
            Colors.teal));
        if (r == null) {
          children.add(_t('동결 추천이 없어 채점 대상 없음', color: Colors.grey.shade700));
        } else if (e == null) {
          children.add(_t('사후 검증 전 (추첨 결과 미반영) — 적중 여부 없음', color: Colors.grey.shade700));
        } else {
          children.add(_t(
              '1·2등 적중 ${e.hitsAny ?? '-'}건 (1등 ${e.hitsFirst ?? '-'}) · 무작위 기대 ${fmtNum(e.expectedUniform)}건'
              ' · 이력 기준 ${e.historyHits ?? '-'}건 · 탐색 ${e.exploreHits ?? '-'}건',
              weight: FontWeight.w700,
              color: (e.hitsAny ?? 0) > 0 ? Colors.green.shade800 : null));
          final rankTags = <Widget>[];
          for (var i = 0; i < r.storeIds.length; i++) {
            final hit = e.hitAtRank(i + 1);
            final code = r.storeIds[i];
            rankTags.add(regionTag(
                '${i + 1}위 ${d.names[code] ?? code} · ${hit == null ? '기록 없음' : (hit > 0 ? '적중' : '미적중')}',
                hit != null && hit > 0 ? Colors.green : Colors.grey));
          }
          if (rankTags.isNotEmpty) {
            children.add(Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 4, runSpacing: 3, children: rankTags),
            ));
          }
          children.add(_t('사후 검증 = 추첨 이후 동결 추천을 채점한 기록입니다. $kReplaySalesCaution',
              color: Colors.black45, size: 10));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
      },
    );
  }
}
