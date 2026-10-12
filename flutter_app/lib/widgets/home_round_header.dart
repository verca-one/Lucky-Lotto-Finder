// 홈 상단 헤더 — 최신 회차·추첨일·업데이트 시각을 크게 보여 준다
import 'package:flutter/material.dart';

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

/// 10/11 02:49
String formatUpdateTime(DateTime t) =>
    '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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

class HomeRoundHeader extends StatelessWidget {
  final int lottoRound;
  final int pensionRound;
  final DateTime? lottoDrawDate;
  final DateTime? pensionDrawDate;
  final Map<String, DateTime> updates;

  const HomeRoundHeader({
    super.key,
    required this.lottoRound,
    required this.pensionRound,
    this.lottoDrawDate,
    this.pensionDrawDate,
    this.updates = const {},
  });

  @override
  Widget build(BuildContext context) {
    final speeto = updates['speeto'];
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
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
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
              const Text('최신 당첨 회차',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 2),
              Text('실제 당첨 이력을 분석한 통계입니다.',
                  style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85))),
            ]),
          ),
        ]),
        if (lottoRound > 0 || pensionRound > 0) ...[
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: _RoundTile(
                  key: const ValueKey('header_lotto'),
                  label: '로또 6/45',
                  accent: const Color(0xFFF5A623),
                  round: lottoRound,
                  drawDate: lottoRound > 0 ? (lottoDrawDate ?? lottoDrawDateFor(lottoRound)) : null,
                  updatedAt: updates['lotto'],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RoundTile(
                  key: const ValueKey('header_pension'),
                  label: '연금복권720+',
                  accent: const Color(0xFF2EAD6B),
                  round: pensionRound,
                  drawDate: pensionRound > 0 ? (pensionDrawDate ?? pensionDrawDateFor(pensionRound)) : null,
                  updatedAt: updates['pension'],
                ),
              ),
            ]),
          ),
        ],
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

class _RoundTile extends StatelessWidget {
  final String label;
  final Color accent;
  final int round;
  final DateTime? drawDate;
  final DateTime? updatedAt;

  const _RoundTile({
    super.key,
    required this.label,
    required this.accent,
    required this.round,
    this.drawDate,
    this.updatedAt,
  });

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF14213D);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
          ),
        ]),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(round > 0 ? '$round' : '-',
                style: const TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w900, color: ink)),
            const SizedBox(width: 2),
            const Text('회', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
          ]),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            drawDate != null ? '${formatDrawDate(drawDate!)} 추첨' : '추첨일 정보 없음',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1565C0)),
          ),
        ),
        const SizedBox(height: 8),
        Divider(height: 1, color: Colors.grey.shade200),
        const SizedBox(height: 7),
        Row(children: [
          Icon(updatedAt != null ? Icons.check_circle_rounded : Icons.schedule_rounded,
              size: 13, color: updatedAt != null ? const Color(0xFF2EAD6B) : Colors.grey.shade500),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              updatedAt != null ? '${formatUpdateTime(updatedAt!)} 업데이트' : '업데이트 기록 없음',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
            ),
          ),
        ]),
      ]),
    );
  }
}
