// 홈 상단 '최신 당첨 회차' — 로또·연금복권 각각 겹침 카드 (앞 = 최신 목표 회차, 뒤 = 직전 회차)
import 'dart:async';

import 'package:flutter/material.dart';

import '../services/round_status_service.dart';

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 로또 6/45 추첨일 (1회 = 2002-12-07 토요일, 매주)
DateTime lottoDrawDateFor(int round) => DateTime(2002, 12, 7).add(Duration(days: (round - 1) * 7));

/// 연금복권720+ 추첨일 (1회 = 2020-05-07 목요일, 매주)
DateTime pensionDrawDateFor(int round) => DateTime(2020, 5, 7).add(Duration(days: (round - 1) * 7));

/// DB 추첨일 문자열(2026-10-10 / 2026.10.10 / 20261010 등) → 날짜. 해석 불가면 null
DateTime? parseDrawDate(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'(\d{4})\D?(\d{1,2})\D?(\d{1,2})').firstMatch(raw);
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d);
}

/// 2026.10.10 (토)
String formatDrawDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} (${_weekdays[d.weekday - 1]})';

/// 10/11 02:49 (기기 시간대)
String formatUpdateTime(DateTime t) {
  final l = t.toLocal();
  return '${l.month}/${l.day} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// 크롤링 성공 로그 → 종류별(lotto/pension/speeto) 최신 완료 시각 (기기 시간대)
Map<String, DateTime> latestUpdateTimes(List<Map<String, dynamic>> logs) {
  final out = <String, DateTime>{};
  for (final log in logs) {
    final type = log['lottery_type'] as String? ?? '';
    final t = DateTime.tryParse(log['completed_at'] as String? ?? '')?.toLocal();
    if (type.isEmpty || t == null) continue;
    final prev = out[type];
    if (prev == null || t.isAfter(prev)) out[type] = t;
  }
  return out;
}

class _Theme {
  final String label;
  final Color accent;
  final Color ink;
  const _Theme(this.label, this.accent, this.ink);
  static _Theme of(String type) => type == 'pension'
      ? const _Theme('연금복권720+', Color(0xFF2EAD6B), Color(0xFF1C7A49))
      : const _Theme('로또 6/45', Color(0xFFE0A100), Color(0xFF8A6100));
}

/// 뒤 카드가 앞 카드 위로 드러나는 높이
const double kBackCardPeek = 20;

class HomeRoundHeader extends StatefulWidget {
  /// null = 아직 불러오는 중
  final GameRoundData? lotto;
  final GameRoundData? pension;
  final DateTime? speetoUpdatedAt;

  /// 카드 탭 (앞/뒤 각각). 중복 탭 방지는 호출 측이 Future 완료까지 막는다.
  final Future<void> Function(RoundCardInfo card)? onOpen;

  /// 테스트용 시계 (기본 = 현재 시각)
  final DateTime Function()? clock;

  const HomeRoundHeader({
    super.key,
    this.lotto,
    this.pension,
    this.speetoUpdatedAt,
    this.onOpen,
    this.clock,
  });

  @override
  State<HomeRoundHeader> createState() => _HomeRoundHeaderState();
}

class _HomeRoundHeaderState extends State<HomeRoundHeader> {
  Timer? _tick;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    // 추첨 시각이 지나면 '추첨 예정' → '결과 대기'로 바뀌도록 1분마다 다시 그림 (화면 이동 없음)
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _open(RoundCardInfo card) async {
    if (_opening || widget.onOpen == null) return;
    _opening = true;
    try {
      await widget.onOpen!(card);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = (widget.clock ?? DateTime.now)().toUtc();
    final lotto = widget.lotto == null ? null : decideRoundPair(widget.lotto!, now);
    final pension = widget.pension == null ? null : decideRoundPair(widget.pension!, now);
    final speeto = widget.speetoUpdatedAt;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x881565C0), Color(0x881E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('최신 당첨 회차', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 2),
              Text('실제 당첨 이력을 분석한 통계입니다.',
                  style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85))),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _GameStack(type: 'lotto', pair: lotto, loading: widget.lotto == null, onOpen: _open)),
            const SizedBox(width: 10),
            Expanded(child: _GameStack(type: 'pension', pair: pension, loading: widget.pension == null, onOpen: _open)),
          ]),
        ),
        if (speeto != null) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('header_speeto'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Text('스피또', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
              const Spacer(),
              const Icon(Icons.check_circle_rounded, color: Colors.lightGreenAccent, size: 14),
              const SizedBox(width: 4),
              Text('${formatUpdateTime(speeto)} 업데이트',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.info_outline_rounded, size: 13, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '당첨을 보장하지 않으며, 당첨주기 예상은 참고 정보입니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85)),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// 한 게임의 겹침 카드: 뒤 카드(직전 회차) 위쪽 [kBackCardPeek] 만큼 노출 + 앞 카드(최신 목표 회차)
class _GameStack extends StatelessWidget {
  final String type;
  final RoundPair? pair;
  final bool loading;
  final Future<void> Function(RoundCardInfo) onOpen;

  const _GameStack({required this.type, required this.pair, required this.loading, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = _Theme.of(type);
    final back = pair?.back;
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        if (back != null)
          Positioned(
            top: 0,
            left: 7,
            right: 7,
            height: kBackCardPeek + 24,
            child: _BackCard(key: ValueKey('header_${type}_back'), card: back, theme: t, onTap: () => onOpen(back)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: kBackCardPeek),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOut,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.passthrough, children: [...previous, if (current != null) current]),
            child: pair == null
                ? _FrontPlaceholder(key: ValueKey('header_${type}_placeholder'), theme: t, loading: loading)
                : _FrontCard(
                    key: ValueKey('header_${type}_front_${pair!.front.round}_${pair!.front.status.name}'),
                    card: pair!.front,
                    theme: t,
                    onTap: () => onOpen(pair!.front),
                  ),
          ),
        ),
      ],
    );
  }
}

BoxDecoration _frontDecoration(_Theme t) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: t.accent.withValues(alpha: 0.45), width: 1.2),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 10, offset: const Offset(0, 3)),
      ],
    );

class _FrontCard extends StatelessWidget {
  final RoundCardInfo card;
  final _Theme theme;
  final VoidCallback onTap;
  const _FrontCard({super.key, required this.card, required this.theme, required this.onTap});

  String get _detail {
    switch (card.status) {
      case RoundStatus.complete:
        return card.updatedAt != null ? '${formatUpdateTime(card.updatedAt!)} 수집' : '수집 시각 기록 없음';
      case RoundStatus.scheduled:
        final d = drawTimeUtc(card.type, card.round).toLocal();
        return '${_weekdays[d.weekday - 1]} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} 추첨';
      case RoundStatus.awaiting:
        return '공식 결과 수집 전';
      case RoundStatus.error:
        return '수집 실패 · 확인 중';
    }
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF14213D);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: _frontDecoration(theme),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(theme.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: theme.ink)),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
            ]),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text('${card.round}',
                    style: const TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w900, color: ink)),
                const SizedBox(width: 2),
                const Text('회', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
              ]),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('${formatDrawDate(card.drawDate)} 추첨',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1565C0))),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 7),
            RoundStatusPill(status: card.status),
            const SizedBox(height: 4),
            Text(_detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          ]),
        ),
      ),
    );
  }
}

class _BackCard extends StatelessWidget {
  final RoundCardInfo card;
  final _Theme theme;
  final VoidCallback onTap;
  const _BackCard({super.key, required this.card, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final time = card.updatedAt != null ? '${formatUpdateTime(card.updatedAt!)} 업데이트' : '업데이트 기록 없음';
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Color.lerp(Colors.white, theme.accent, 0.22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.accent.withValues(alpha: 0.55)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          padding: const EdgeInsets.fromLTRB(10, 3, 10, 0),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: kBackCardPeek - 4,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('이전 ${card.round}회 · $time',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: theme.ink)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FrontPlaceholder extends StatelessWidget {
  final _Theme theme;
  final bool loading;
  const _FrontPlaceholder({super.key, required this.theme, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _frontDecoration(theme),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(theme.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: theme.ink)),
        const SizedBox(height: 10),
        Text(loading ? '회차 정보를 불러오는 중…' : '회차 정보를 불러오지 못했습니다',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ]),
    );
  }
}

/// 회차 상태 표시 (추첨 예정 / 결과 대기 / 업데이트 완료 / 데이터 오류)
class RoundStatusPill extends StatelessWidget {
  final RoundStatus status;
  const RoundStatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = switch (status) {
      RoundStatus.scheduled => (const Color(0xFF1565C0), const Color(0xFFE3F0FF), Icons.event_rounded),
      RoundStatus.awaiting => (const Color(0xFFB45309), const Color(0xFFFFF1DC), Icons.hourglass_top_rounded),
      RoundStatus.complete => (const Color(0xFF1E7D4C), const Color(0xFFE3F6EA), Icons.check_circle_rounded),
      RoundStatus.error => (const Color(0xFFC62828), const Color(0xFFFDE4E4), Icons.error_outline_rounded),
    };
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 3),
          Text(status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
        ]),
      ),
    );
  }
}
