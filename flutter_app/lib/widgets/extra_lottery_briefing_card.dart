// 엔진 브리핑 상단(지방장보고 아래) — 연금복권 · 스피또 요약 브리핑. 누르면 연구소의 연금 연구 · 스피또 연구 화면.
import 'package:flutter/material.dart';

import '../screens/admin_lottery_extra_screens.dart';
import '../services/research/pension_briefing.dart';
import 'pension_briefing_view.dart' show kPensionColor;
import 'speetto_briefing_view.dart';

class ExtraLotteryBriefingCard extends StatefulWidget {
  final Future<PensionBriefing?> Function()? pensionLoader;
  final Future<SpeettoBriefing?> Function()? speettoLoader;
  const ExtraLotteryBriefingCard({super.key, this.pensionLoader, this.speettoLoader});
  @override
  State<ExtraLotteryBriefingCard> createState() => _ExtraLotteryBriefingCardState();
}

class _ExtraLotteryBriefingCardState extends State<ExtraLotteryBriefingCard> {
  late final Future<PensionBriefing?> _p = _safe(widget.pensionLoader ?? PensionBriefing.loadAdmin);
  late final Future<SpeettoBriefing?> _s = _safe(widget.speettoLoader ?? SpeettoBriefing.loadAdmin);

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
          required VoidCallback onTap, Key? key}) =>
      InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
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
                const SizedBox(height: 3),
                ...lines,
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: color),
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
    final lines = <Widget>[];
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
    }
    return _box(
      key: const ValueKey('extra_pension'),
      color: kPensionColor,
      icon: Icons.card_giftcard,
      title: b == null ? '이번 주 연금복권' : '이번 주 연금복권 ${b.targetRound}회 · ${_md(b.drawDate)}(목) 추첨',
      lines: lines,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPensionResearchScreen())),
    );
  }

  Widget _speetto(SpeettoBriefing? b, bool done) {
    final lines = <Widget>[];
    if (!done) {
      lines.add(_line('불러오는 중…'));
    } else if (b == null) {
      lines.add(_line('스피또 브리핑 저장본 없음 (서버 매일 17시)'));
    } else {
      final newest = <String, SpeettoEdition>{};
      for (final e in b.editions) {
        if ((newest[e.game]?.edition ?? -1) < e.edition) newest[e.game] = e;
      }
      if (newest.isNotEmpty) {
        lines.add(_line('판매 중 · ${(newest.values.toList()..sort((a, c) => a.game.compareTo(c.game)))
            .map((e) => '${e.label} ${e.edition}회 (${_md(e.saleStart)} 출시)').join(' · ')}'));
      }
      final top = b.editions.isNotEmpty ? b.editions.first : null;
      lines.add(_line(top == null
          ? '판매 현황 수집 전 (매일 10시)'
          : '남은 1등 지수 1위 ${top.label} ${top.edition}회 · 출고율 ${(top.shipRate ?? 0).toStringAsFixed(0)}% · 1등 ${top.rnk1Left}/${top.rnk1Total}장 남음'));
      final ok = b.games.where((g) => g.ok).length;
      lines.add(_line(ok > 0 ? '1등 판매점 ${ok}개 게임 정리됨' : '1등 판매점: 예전 기록 정리 필요 (크롤러 수정 완료)'));
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
