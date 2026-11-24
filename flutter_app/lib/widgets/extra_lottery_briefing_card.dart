// 엔진 브리핑 상단(지방장보고 아래) — 연금복권 · 스피또 요약 브리핑. 누르면 연구소의 연금 연구 · 스피또 연구 화면.
import 'package:flutter/material.dart';

import '../screens/admin_lottery_extra_screens.dart';
import '../services/research/pension_briefing.dart';
import 'pension_briefing_view.dart' show kPensionColor;
import 'speetto_briefing_view.dart';

/// 이번 로또 주의 추첨일(토) — 오늘이 토요일이면 오늘, 아니면 다음 토요일 (KST)
DateTime lottoWeekSaturday(DateTime nowKst) {
  final d = DateTime(nowKst.year, nowKst.month, nowKst.day);
  return d.add(Duration(days: (DateTime.saturday - d.weekday + 7) % 7));
}

/// 연금 추첨일이 이번 로또 주(토요일까지)를 넘으면 '다음 주'
bool isNextLottoWeek(String? drawDate, DateTime nowKst) {
  final d = DateTime.tryParse((drawDate ?? '').length >= 10 ? drawDate!.substring(0, 10) : '');
  if (d == null) return false;
  return d.isAfter(lottoWeekSaturday(nowKst));
}

class ExtraLotteryBriefingCard extends StatefulWidget {
  final Future<PensionBriefing?> Function()? pensionLoader;
  final Future<SpeettoBriefing?> Function()? speettoLoader;

  /// 테스트용 현재 시각 (KST)
  final DateTime? now;
  const ExtraLotteryBriefingCard({super.key, this.pensionLoader, this.speettoLoader, this.now});
  @override
  State<ExtraLotteryBriefingCard> createState() => _ExtraLotteryBriefingCardState();
}

class _ExtraLotteryBriefingCardState extends State<ExtraLotteryBriefingCard> {
  late final Future<PensionBriefing?> _p = _safe(widget.pensionLoader ?? PensionBriefing.loadAdmin);
  late final Future<SpeettoBriefing?> _s = _safe(widget.speettoLoader ?? SpeettoBriefing.loadAdmin);
  bool _pensionOpen = false; // 연금 카드는 제목(회차 · 추첨일)만 — 누르면 아래 내용

  static Future<T?> _safe<T>(Future<T?> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(key: const ValueKey('extra_lottery_briefing'), children: [
      FutureBuilder<PensionBriefing?>(future: _p, builder: (c, s) => _pension(s.data, s.connectionState == ConnectionState.done)),
      const SizedBox(height: 8),
      FutureBuilder<SpeettoBriefing?>(future: _s, builder: (c, s) => _speetto(s.data, s.connectionState == ConnectionState.done)),
    ]);
  }

  Widget _box({required Color color, required IconData icon, required String title, required List<Widget> lines,
          required VoidCallback onTap, Key? key, bool dim = false, bool? open}) =>
      InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: dim ? Colors.grey.shade100 : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34, height: 34, alignment: Alignment.center,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: color)),
                if (open != false) ...[const SizedBox(height: 3), ...lines],
              ]),
            ),
            // open == null: 누르면 화면 이동(›) / 그 외: 누르면 펼침 · 접힘
            Icon(open == null ? Icons.chevron_right_rounded : open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: color),
          ]),
        ),
      );

  /// '2026-10-29' · ISO → '10/29'
  static String _md(String? iso) {
    final s = iso ?? '';
    if (s.length < 10) return '-';
    return '${int.tryParse(s.substring(5, 7)) ?? 0}/${int.tryParse(s.substring(8, 10)) ?? 0}';
  }

  Widget _line(String s) => Text(s, maxLines: 2, overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800, height: 1.35));

  Widget _pension(PensionBriefing? b, bool done) {
    final nowKst = widget.now ?? DateTime.now().toUtc().add(const Duration(hours: 9));
    final next = b != null && isNextLottoWeek(b.drawDate, nowKst);
    final lines = <Widget>[];
    if (next) {
      lines.add(_line('이번 주 로또 추첨(${_md(lottoWeekSaturday(nowKst).toIso8601String())}) 뒤 이번 주로 바뀝니다'));
    }
    if (!done) {
      lines.add(_line('불러오는 중…'));
    } else if (b == null) {
      lines.add(_line('연금 브리핑 저장본 없음 (서버 매일 17시)'));
    } else {
      final t = b.engineTickets.isNotEmpty ? b.engineTickets.first : null;
      lines.add(_line(b.engineStatus == 'ok' && t != null
          ? '추천번호 ${t.group}조 ${t.number} 외 ${b.engineTickets.length - 1}장'
          : (b.engineNote ?? '연금 번호 엔진 대기')));
      if (b.stores.isNotEmpty) {
        lines.add(_line('명당 ${b.stores.take(3).map((s) => s.name).join(' · ')}'));
      }
      lines.add(_line(b.trackStatus == 'ok' ? '가설 트랙 ${b.trackTickets.length}장 · 가설 ${b.trackHyps.length}개 사용' : (b.trackNote ?? '연금 가설 트랙 대기')));
      lines.add(_line(b.isFinal ? '목요일 8시 최종본' : '초안 — 목요일 8시 최종본 예정'));
    }
    lines.add(GestureDetector(
      key: const ValueKey('extra_pension_open'),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPensionResearchScreen())),
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('연금 연구 화면 열기 ›', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: next ? Colors.grey.shade600 : kPensionColor)),
      ),
    ));
    return _box(
      key: const ValueKey('extra_pension'),
      color: next ? Colors.grey.shade500 : kPensionColor,
      dim: next,
      icon: Icons.card_giftcard,
      title: b == null ? '이번 주 연금복권' : '${next ? '다음 주' : '이번 주'} 연금복권 ${b.targetRound}회 · ${_md(b.drawDate)}(목) 추첨',
      lines: lines,
      open: _pensionOpen,
      onTap: () => setState(() => _pensionOpen = !_pensionOpen),
    );
  }

  Widget _speetto(SpeettoBriefing? b, bool done) {
    final lines = <Widget>[];
    if (!done) {
      lines.add(_line('불러오는 중…'));
    } else if (b == null) {
      lines.add(_line('스피또 브리핑 저장본 없음 (서버 매일 17시)'));
    } else {
      // 출고율 90%를 넘는 회차만 (거의 다 풀린 회차 — 나머지는 스피또 탭의 출고율 대시보드에서)
      final hot = b.editions.where((e) => (e.shipRate ?? 0) > 90).toList()
        ..sort((a, c) => (c.shipRate ?? 0).compareTo(a.shipRate ?? 0));
      if (b.editions.isEmpty) {
        lines.add(_line('판매 현황 수집 전 (매일 10시)'));
      } else if (hot.isEmpty) {
        lines.add(_line('출고율 90%를 넘는 회차 없음'));
      }
      for (final e in hot) {
        lines.add(_line('${e.label} ${e.edition}회 · 출고율 ${(e.shipRate ?? 0).toStringAsFixed(0)}% · 1등 ${e.rnk1Left ?? '-'}/${e.rnk1Total ?? '-'}장 남음'));
      }
    }
    return _box(
      key: const ValueKey('extra_speetto'),
      color: kSpeettoColor,
      icon: Icons.style_rounded,
      title: '이번 주 스피또',
      lines: lines,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSpeettoResearchScreen())),
    );
  }
}
