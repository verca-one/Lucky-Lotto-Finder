// 홈 랭킹 머리 아래 — 최신 로또 당첨번호 한 줄 (lotto_winning_numbers 최신 회차, 읽기만)
//   번호 수집되면 바로 반영: 추첨(토 20:35 KST) 뒤 새 회차 번호가 아직 없으면 2분마다 다시 읽고,
//   앱으로 돌아올 때도 다시 읽는다. 새 회차가 들어오면 [onNewRound] (홈 회차 카드도 다시 읽기)
//   발표 당일(토): 0시부터 다음 회차 회색 '추첨 예정' → 20:35 추첨 뒤 회색 '번호 수집 전' → 번호 수집되면 색 공
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/lotto_winning_number.dart';
import '../services/supabase_service.dart';
import 'home_round_header.dart' show kPendingText, kPendingSubText, kPendingLine;
import 'winning_number_boxes.dart';

/// 가장 최근 추첨(토 20:35 KST)이 지났고 36시간 안인데, 보이는 번호가 그 전 회차면 true (순수 함수)
bool needsNewLottoNumbers(LottoWinningNumber? shown, DateTime nowUtc) {
  final k = nowUtc.toUtc().add(const Duration(hours: 9)); // KST 벽시계 (UTC 표기)
  var sat = DateTime.utc(k.year, k.month, k.day);
  while (sat.weekday != DateTime.saturday) {
    sat = sat.subtract(const Duration(days: 1));
  }
  final drawAt = sat.add(const Duration(hours: 20, minutes: 35));
  if (k.isBefore(drawAt) || k.difference(drawAt) > const Duration(hours: 36)) return false;
  final d = shown == null ? null : DateTime.tryParse(shown.drawDate);
  return d == null || DateTime.utc(d.year, d.month, d.day).isBefore(sat);
}

/// 발표 당일 회색 단계 — 가장 최근 토요일 0시(KST)가 지났는데 보이는 번호가 그 전 회차면 (다음 회차, 추첨일, 단계 이름).
/// 60시간(월 12시)이 지나도 안 들어오면 지난 번호를 그대로 보여 준다 (null). 순수 함수.
(int, DateTime, String)? pendingLottoStage(LottoWinningNumber? shown, DateTime nowUtc) {
  if (shown == null) return null;
  final k = nowUtc.toUtc().add(const Duration(hours: 9)); // KST 벽시계 (UTC 표기)
  var sat = DateTime.utc(k.year, k.month, k.day);
  while (sat.weekday != DateTime.saturday) {
    sat = sat.subtract(const Duration(days: 1));
  }
  final d = DateTime.tryParse(shown.drawDate);
  if (d == null || !DateTime.utc(d.year, d.month, d.day).isBefore(sat)) return null;
  if (k.difference(sat) > const Duration(hours: 60)) return null;
  final drawn = !k.isBefore(sat.add(const Duration(hours: 20, minutes: 35)));
  return (shown.round + 1, sat, drawn ? '번호 수집 전' : '추첨 예정');
}

class RankingLottoNumbers extends StatefulWidget {
  final Future<LottoWinningNumber?> Function()? loader;
  final VoidCallback? onNewRound;
  final DateTime Function()? clock;
  final Duration pollEvery;
  const RankingLottoNumbers({super.key, this.loader, this.onNewRound, this.clock, this.pollEvery = const Duration(minutes: 2)});
  @override
  State<RankingLottoNumbers> createState() => _RankingLottoNumbersState();
}

Future<LottoWinningNumber?> _latest() async {
  final l = await SupabaseService.getRecentWinningNumbers(1);
  return l.isEmpty ? null : l.first;
}

String _date(String d) {
  final t = DateTime.tryParse(d);
  if (t == null) return d;
  return '${t.year}.${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')}';
}

class _RankingLottoNumbersState extends State<RankingLottoNumbers> with WidgetsBindingObserver {
  LottoWinningNumber? _w;
  Timer? _poll;
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read(first: true);
    _poll = Timer.periodic(widget.pollEvery, (_) {
      if (needsNewLottoNumbers(_w, (widget.clock ?? DateTime.now)())) _read();
    });
    // 0시 · 20:35 에 단계가 바뀌도록 1분마다 다시 그림 (읽기 없음)
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
      final w = await (widget.loader ?? _latest)();
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

  @override
  Widget build(BuildContext context) {
    final w = _w;
    if (w == null || w.numbers.length != 6) return const SizedBox.shrink();
    final stage = pendingLottoStage(w, (widget.clock ?? DateTime.now)());
    if (stage != null) return _pending(stage);
    final nums = [...w.numbers]..sort();
    return Container(
      key: const ValueKey('ranking_lotto_numbers'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE082)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('로또 ${w.round}회 당첨번호',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Color(0xFF1A1A2E))),
          const Spacer(),
          Text('${_date(w.drawDate)} 추첨', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(children: [
            for (final n in nums)
              Padding(padding: const EdgeInsets.only(right: 6), child: numberBall('$n', lottoRangeColor(n), size: 36)),
            const Padding(
              padding: EdgeInsets.only(left: 2, right: 8),
              child: Text('+', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A2E))),
            ),
            numberBall('${w.bonusNumber}', lottoRangeColor(w.bonusNumber), size: 36),
          ]),
        ),
      ]),
    );
  }

  /// 회색 — 다음 회차 번호 수집 전 (회색 빈 공 6개 + 보너스)
  Widget _pending((int, DateTime, String) st) {
    final (round, sat, label) = st;
    Widget ball() => Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: const Color(0xFFF1F3F6), shape: BoxShape.circle, border: Border.all(color: kPendingLine)),
          alignment: Alignment.center,
          child: const Text('?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: kPendingSubText)),
        );
    return Container(
      key: const ValueKey('ranking_lotto_pending'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPendingLine),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('로또 $round회 당첨번호', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: kPendingText)),
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
          Text('${_date(sat.toIso8601String())} 추첨', style: const TextStyle(fontSize: 11.5, color: kPendingSubText)),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(children: [
            for (var i = 0; i < 6; i++) Padding(padding: const EdgeInsets.only(right: 6), child: ball()),
            const Padding(
              padding: EdgeInsets.only(left: 2, right: 8),
              child: Text('+', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kPendingSubText)),
            ),
            ball(),
          ]),
        ),
      ]),
    );
  }
}
