// 홈 — 로또 당첨번호 상자 아래 연금복권720+ 최신 당첨번호 상자 (pension_winning_numbers 최신 회차, 읽기만)
//   로또 상자와 같은 방식: 추첨(목 19:05 KST) 뒤 새 회차 번호가 없으면 2분마다 · 앱으로 돌아올 때 다시 읽기
//   발표 당일(목): 0시부터 다음 회차 회색 '추첨 예정' → 19:05 추첨 뒤 회색 '번호 수집 전' → 번호 수집되면 색 공
import 'dart:async';

import 'package:flutter/material.dart';

import 'home_round_header.dart' show kPendingText, kPendingSubText, kPendingLine;
import 'winning_number_boxes.dart';

const kPensionBoxColor = Color(0xFFEF6C00);

/// 가장 최근 목요일 0시(KST) (UTC 표기 KST 벽시계)
DateTime _lastThursday(DateTime k) {
  var d = DateTime.utc(k.year, k.month, k.day);
  while (d.weekday != DateTime.thursday) {
    d = d.subtract(const Duration(days: 1));
  }
  return d;
}

bool _before(String drawDate, DateTime day) {
  final d = DateTime.tryParse(drawDate);
  return d == null || DateTime.utc(d.year, d.month, d.day).isBefore(day);
}

/// 가장 최근 추첨(목 19:05 KST)이 지났고 36시간 안인데, 보이는 번호가 그 전 회차면 true (순수 함수)
bool needsNewPensionNumbers(PensionLatestWinning? shown, DateTime nowUtc) {
  final k = nowUtc.toUtc().add(const Duration(hours: 9));
  final thu = _lastThursday(k);
  final drawAt = thu.add(const Duration(hours: 19, minutes: 5));
  if (k.isBefore(drawAt) || k.difference(drawAt) > const Duration(hours: 36)) return false;
  return shown == null || _before(shown.drawDate, thu);
}

/// 발표 당일 회색 단계 — (다음 회차, 추첨일, 단계 이름). 60시간(토 12시)이 지나도 안 들어오면 null. 순수 함수.
(int, DateTime, String)? pendingPensionStage(PensionLatestWinning? shown, DateTime nowUtc) {
  if (shown == null) return null;
  final k = nowUtc.toUtc().add(const Duration(hours: 9));
  final thu = _lastThursday(k);
  if (!_before(shown.drawDate, thu) || k.difference(thu) > const Duration(hours: 60)) return null;
  final drawn = !k.isBefore(thu.add(const Duration(hours: 19, minutes: 5)));
  return (shown.round + 1, thu, drawn ? '번호 수집 전' : '추첨 예정');
}

String _date(String d) {
  final t = DateTime.tryParse(d);
  if (t == null) return d;
  return '${t.year}.${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')}';
}

class RankingPensionNumbers extends StatefulWidget {
  final Future<PensionLatestWinning?> Function()? loader;
  final VoidCallback? onNewRound;
  final DateTime Function()? clock;
  final Duration pollEvery;
  const RankingPensionNumbers({super.key, this.loader, this.onNewRound, this.clock, this.pollEvery = const Duration(minutes: 2)});
  @override
  State<RankingPensionNumbers> createState() => _RankingPensionNumbersState();
}

class _RankingPensionNumbersState extends State<RankingPensionNumbers> with WidgetsBindingObserver {
  PensionLatestWinning? _w;
  Timer? _poll;
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read(first: true);
    _poll = Timer.periodic(widget.pollEvery, (_) {
      if (needsNewPensionNumbers(_w, (widget.clock ?? DateTime.now)())) _read();
    });
    // 0시 · 19:05 에 단계가 바뀌도록 1분마다 다시 그림 (읽기 없음)
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _read();
  }

  Future<void> _read({bool first = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      final w = await (widget.loader ?? PensionLatestWinning.load)();
      if (!mounted || w == null) return;
      final newer = _w != null && w.round > _w!.round;
      if (_w == null || w.round >= _w!.round) setState(() => _w = w);
      if (newer && !first) widget.onNewRound?.call();
    } catch (_) {
      // 읽기 실패 — 보이던 번호 유지
    } finally {
      _busy = false;
    }
  }

  Widget _groupChip(String t, Color bg, Color fg) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 13)),
      );

  Widget _label(String t, Color c) =>
      SizedBox(width: 44, child: Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)));

  Widget _box({required Key key, required Color border, required Widget title, required List<Widget> rows}) => Container(
        key: key,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 8), ...rows]),
      );

  @override
  Widget build(BuildContext context) {
    final w = _w;
    if (w == null || w.number.length != 6) return const SizedBox.shrink();
    final stage = pendingPensionStage(w, (widget.clock ?? DateTime.now)());
    if (stage != null) return _pending(stage);
    Widget digits(String n) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(children: [
            for (final e in n.split('').asMap().entries)
              Padding(padding: const EdgeInsets.only(right: 5), child: numberBall(e.value, kPensionDigitColors[e.key % 6], size: 32, fontSize: 14)),
          ]),
        );
    return _box(
      key: const ValueKey('ranking_pension_numbers'),
      border: const Color(0xFFFFCC80),
      title: Row(children: [
        Text('연금복권720+ ${w.round}회 당첨번호',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Color(0xFF1A1A2E))),
        const Spacer(),
        Text('${_date(w.drawDate)} 추첨', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
      ]),
      rows: [
        Row(children: [
          _label('1등', kPensionBoxColor),
          _groupChip('${w.group}조', kPensionBoxColor, Colors.white),
          Expanded(child: digits(w.number)),
        ]),
        if (w.bonus.length == 6) ...[
          const SizedBox(height: 6),
          Row(children: [
            _label('보너스', Colors.grey.shade700),
            _groupChip('각조', const Color(0xFFFFF3E0), kPensionBoxColor),
            Expanded(child: digits(w.bonus)),
          ]),
        ],
      ],
    );
  }

  /// 회색 — 다음 회차 번호 수집 전
  Widget _pending((int, DateTime, String) st) {
    final (round, thu, label) = st;
    Widget ball() => Container(
          width: 32, height: 32, margin: const EdgeInsets.only(right: 5),
          decoration: BoxDecoration(color: const Color(0xFFF1F3F6), shape: BoxShape.circle, border: Border.all(color: kPendingLine)),
          alignment: Alignment.center,
          child: const Text('?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: kPendingSubText)),
        );
    return _box(
      key: const ValueKey('ranking_pension_pending'),
      border: kPendingLine,
      title: Row(children: [
        Flexible(
          child: Text('연금복권720+ $round회 당첨번호', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: kPendingText)),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.hourglass_top_rounded, size: 11, color: kPendingSubText),
            const SizedBox(width: 2),
            Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: kPendingSubText)),
          ]),
        ),
        const Spacer(),
        Text('${_date(thu.toIso8601String())} 추첨', style: const TextStyle(fontSize: 11.5, color: kPendingSubText)),
      ]),
      rows: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(children: [
            _label('1등', kPendingSubText),
            _groupChip('?조', const Color(0xFFF1F3F6), kPendingSubText),
            for (var i = 0; i < 6; i++) ball(),
          ]),
        ),
      ],
    );
  }
}
