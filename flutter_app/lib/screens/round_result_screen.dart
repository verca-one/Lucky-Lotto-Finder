// 회차 당첨 결과 상세 (홈 '최신 당첨회차' 카드 탭) — DB 저장 데이터만 읽기 전용으로 표시
//   로또 금색 · 연금 녹색 머리띠 · 당첨번호 공 · 로또 등수별 당첨금(저장본 있으면) · 당첨 판매점 카드(지도 · ★)
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/lottery_store.dart';
import '../services/round_status_service.dart';
import '../services/store_map_launcher.dart' show StoreMapTarget;
import '../services/supabase_service.dart';
import '../widgets/briefing_store_widgets.dart' show FavoriteStoreStar;
import '../widgets/home_round_header.dart' show RoundStatusPill, formatDrawDate, formatUpdateTime;
import '../widgets/store_map_buttons.dart' show showStoreMapSheet;
import '../widgets/winning_number_boxes.dart' show numberBall, lottoRangeColor, kPensionDigitColors;

class _RoundResult {
  final List<int>? lottoNumbers;
  final int? lottoBonus;
  final int? pensionGroup;
  final String? pensionNumber; // 6자리
  final String? pensionBonus; // 6자리
  final List<(int, int?, int?)> prizes; // 로또 (등수, 당첨자 수, 1게임 당첨금)
  final List<LotteryStore> stores;
  const _RoundResult({this.lottoNumbers, this.lottoBonus, this.pensionGroup, this.pensionNumber, this.pensionBonus,
      this.prizes = const [], this.stores = const []});
}

/// 게임별 색 (머리띠 그라데이션 2색 · 글씨)
class _Look {
  final Color a, b, ink, soft;
  const _Look(this.a, this.b, this.ink, this.soft);
}

const _lottoLook = _Look(Color(0xFFF9A825), Color(0xFFEF6C00), Color(0xFF8A4B00), Color(0xFFFFF8E1));
const _pensionLook = _Look(Color(0xFF2EAD6B), Color(0xFF1C7A49), Color(0xFF145A36), Color(0xFFE8F5E9));

String _won(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b원';
}

class RoundResultScreen extends StatefulWidget {
  final RoundCardInfo card;
  const RoundResultScreen({super.key, required this.card});

  /// 회차별 캐시 (키: '종류:회차:상태') — 상태가 바뀌면 다시 읽는다
  static final Map<String, _RoundResult> _cache = {};

  @override
  State<RoundResultScreen> createState() => _RoundResultScreenState();
}

class _RoundResultScreenState extends State<RoundResultScreen> {
  _RoundResult? _result;
  bool _failed = false;

  RoundCardInfo get c => widget.card;
  bool get _pension => c.type == 'pension';
  _Look get _look => _pension ? _pensionLook : _lottoLook;
  String get _key => '${c.type}:${c.round}:${c.status.name}';

  @override
  void initState() {
    super.initState();
    _result = RoundResultScreen._cache[_key];
    if (_result == null && (c.status == RoundStatus.complete || c.status == RoundStatus.numbersReady)) _load();
  }

  /// 로또 등수별 당첨자 수 · 1게임 당첨금 (research_prize_stats 저장본, 없으면 빈 목록)
  Future<List<(int, int?, int?)>> _prizes() async {
    try {
      final rows = await Supabase.instance.client.from('research_prize_stats')
          .select('rank1_winners,rank1_amount,rank2_winners,rank2_amount,rank3_winners,rank3_amount,rank4_winners,rank4_amount,rank5_winners,rank5_amount')
          .eq('round', c.round).limit(1);
      final l = rows as List;
      if (l.isEmpty) return const [];
      final r = l.first as Map<String, dynamic>;
      return [for (var k = 1; k <= 5; k++) (k, (r['rank${k}_winners'] as num?)?.toInt(), (r['rank${k}_amount'] as num?)?.toInt())];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _load() async {
    try {
      final stores = await SupabaseService.getStoresByRound(round: c.round, lotteryType: c.type);
      _RoundResult r;
      if (_pension) {
        final w = await SupabaseService.getPensionWinningForRound(c.round);
        r = _RoundResult(
          pensionGroup: w?.winningGroup,
          pensionNumber: w == null || w.winningNumber.isEmpty ? null : w.winningNumber,
          pensionBonus: w == null || w.bonusNumber.isEmpty ? null : w.bonusNumber,
          stores: stores,
        );
      } else {
        final w = await SupabaseService.getWinningNumbersForRound(c.round);
        r = _RoundResult(lottoNumbers: w?.numbers, lottoBonus: w?.bonusNumber, prizes: await _prizes(), stores: stores);
      }
      RoundResultScreen._cache[_key] = r;
      if (mounted) setState(() => _result = r);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = '${_pension ? '연금복권720+' : '로또 6/45'} ${c.round}회';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), backgroundColor: _look.b,
          foregroundColor: Colors.white, elevation: 0),
      body: ListView(padding: EdgeInsets.zero, children: [
        _hero(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _body()),
        ),
      ]),
    );
  }

  Widget _hero() => Container(
        key: const ValueKey('round_hero'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_look.b, _look.a], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(20)),
            child: Text(_pension ? '연금복권720+' : '로또 6/45',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${c.round}', style: const TextStyle(fontSize: 46, height: 1, fontWeight: FontWeight.w900, color: Colors.white)),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 4),
              child: Text('회', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${formatDrawDate(c.drawDate)} 추첨', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.92))),
          const SizedBox(height: 10),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: RoundStatusPill(status: c.status),
            ),
            const SizedBox(width: 8),
            if (c.status == RoundStatus.complete)
              Flexible(
                child: Text(c.updatedAt != null ? '${formatUpdateTime(c.updatedAt!)} 수집 완료' : '수집 시각 기록 없음',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9))),
              ),
          ]),
        ]),
      );

  List<Widget> _body() {
    Widget loading() => const Padding(
        padding: EdgeInsets.all(24), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))));
    switch (c.status) {
      case RoundStatus.scheduled:
        final d = drawTimeUtc(c.type, c.round).toLocal();
        return [
          _notice(Icons.event_rounded, '아직 추첨 전입니다.',
              '추첨 시각: ${formatDrawDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}\n추첨 후 공식 결과가 수집되면 이 화면에 표시됩니다.'),
        ];
      case RoundStatus.awaiting:
        return [
          _notice(Icons.hourglass_top_rounded, '추첨은 끝났고 공식 당첨 결과를 수집하기 전입니다.',
              '공식 데이터가 수집·검증되면 당첨번호와 당첨 판매점이 표시됩니다.'),
        ];
      case RoundStatus.numbersReady:
        final r = _result;
        return [
          if (r != null) _numbers(r)
          else if (_failed) _notice(Icons.cloud_off_rounded, '결과를 불러오지 못했습니다.', '잠시 후 다시 열어 주세요.')
          else loading(),
          const SizedBox(height: 12),
          _notice(Icons.pin_rounded, '당첨 지점(판매점)은 아직 수집 전입니다.', '당첨 판매점이 수집·검증되면 이 화면에 함께 표시됩니다.'),
        ];
      case RoundStatus.error:
        return [
          _notice(Icons.error_outline_rounded, '이 회차 결과를 수집하지 못했거나 검증이 맞지 않습니다.',
              '직전 완료 회차 정보는 그대로 유지됩니다. 서버에서 다시 수집하면 정상 표시됩니다.'),
        ];
      case RoundStatus.complete:
        if (_failed) return [_notice(Icons.cloud_off_rounded, '결과를 불러오지 못했습니다.', '잠시 후 다시 열어 주세요.')];
        final r = _result;
        if (r == null) return [loading()];
        return [
          _numbers(r),
          if (r.prizes.isNotEmpty) ...[const SizedBox(height: 12), _prizeTable(r.prizes)],
          const SizedBox(height: 12),
          _stores(r),
        ];
    }
  }

  Widget _title(String t, IconData icon) => Row(children: [
        Container(
          width: 28, height: 28, alignment: Alignment.center,
          decoration: BoxDecoration(color: _look.soft, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 17, color: _look.b),
        ),
        const SizedBox(width: 8),
        Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF14213D))),
      ]);

  Widget _numbers(_RoundResult r) {
    final missing = Text('당첨번호 데이터 미확보 (DB에 이 회차 당첨번호가 저장되어 있지 않습니다)',
        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600));
    Widget chip(String t, Color bg, Color fg) => Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
          child: Text(t, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 13.5)),
        );
    Widget digits(String n, {double size = 36}) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (final e in n.split('').asMap().entries)
            Padding(padding: const EdgeInsets.only(right: 4), child: numberBall(e.value, kPensionDigitColors[e.key % 6], size: size, fontSize: 15)),
        ]);
    return _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('당첨번호', Icons.emoji_events_rounded),
      const SizedBox(height: 14),
      if (_pension)
        r.pensionNumber == null
            ? missing
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(children: [
                    chip('1등', _look.soft, _look.b),
                    if (r.pensionGroup != null) chip('${r.pensionGroup}조', _look.b, Colors.white),
                    digits(r.pensionNumber!),
                  ]),
                ),
                if (r.pensionBonus != null) ...[
                  const SizedBox(height: 10),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(children: [
                      chip('보너스', Colors.grey.shade100, Colors.grey.shade700),
                      chip('각조', Colors.grey.shade200, Colors.grey.shade800),
                      digits(r.pensionBonus!, size: 32),
                    ]),
                  ),
                ],
              ])
      else if (r.lottoNumbers == null)
        missing
      else
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(children: [
            for (final n in [...r.lottoNumbers!]..sort())
              Padding(padding: const EdgeInsets.only(right: 6), child: numberBall('$n', lottoRangeColor(n), size: 42, fontSize: 16)),
            if (r.lottoBonus != null) ...[
              const Padding(padding: EdgeInsets.only(left: 2, right: 8), child: Icon(Icons.add_rounded, size: 20, color: Colors.grey)),
              Column(children: [
                numberBall('${r.lottoBonus}', lottoRangeColor(r.lottoBonus!), size: 42, fontSize: 16),
                const SizedBox(height: 2),
                Text('보너스', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ]),
            ],
          ]),
        ),
    ]));
  }

  Widget _prizeTable(List<(int, int?, int?)> prizes) => _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('등수별 당첨', Icons.payments_rounded),
        const SizedBox(height: 10),
        for (final (rank, winners, amount) in prizes)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: rank == 1 ? _look.soft : const Color(0xFFF7F8FB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              SizedBox(width: 40, child: Text('$rank등', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: rank == 1 ? _look.b : const Color(0xFF14213D)))),
              Text(winners == null ? '-' : '$winners명', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(amount == null ? '-' : '1게임 ${_won(amount)}', style: TextStyle(fontSize: 13, fontWeight: rank == 1 ? FontWeight.w900 : FontWeight.w600)),
            ]),
          ),
      ]));

  Widget _stores(_RoundResult r) {
    bool first(LotteryStore s) => s.prizeTier == 'first' || s.prizeTier == '1';
    final firsts = r.stores.where(first).toList();
    final seconds = r.stores.where((s) => !first(s)).toList();
    Widget row(LotteryStore s, bool isFirst) {
      final online = s.address.contains('dhlottery');
      final medal = isFirst ? const Color(0xFFD4A017) : const Color(0xFF90A4AE);
      return Container(
        key: ValueKey('round_store_${s.dhlotteryCode}'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: isFirst ? const Color(0xFFFFFBEA) : const Color(0xFFF7F8FB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: medal.withValues(alpha: 0.45)),
        ),
        child: Row(children: [
          Container(
            width: 34, height: 34, alignment: Alignment.center,
            decoration: BoxDecoration(color: medal, shape: BoxShape.circle),
            child: Text(isFirst ? '1등' : '2등', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(s.storeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                if ((s.purchaseMethod ?? '').isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: _look.soft, borderRadius: BorderRadius.circular(6)),
                    child: Text(s.purchaseMethod!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _look.ink)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(s.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            ]),
          ),
          if (!online)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '지도',
              icon: Icon(Icons.map_rounded, color: _look.b, size: 21),
              onPressed: () => showStoreMapSheet(context,
                  StoreMapTarget(storeId: s.dhlotteryCode, name: s.storeName, address: s.address, lat: s.latitude, lng: s.longitude)),
            ),
          if (s.dhlotteryCode.isNotEmpty && !online) FavoriteStoreStar(code: s.dhlotteryCode, name: s.storeName),
        ]),
      );
    }

    Widget group(String label, List<LotteryStore> list, bool isFirst) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('$label ${list.length}곳',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: isFirst ? const Color(0xFFB8860B) : Colors.blueGrey.shade600)),
          ),
          for (final s in list) row(s, isFirst),
        ]);
    return _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('당첨 판매점', Icons.storefront_rounded),
      const SizedBox(height: 12),
      if (r.stores.isEmpty)
        Text('저장된 당첨 판매점 기록이 없습니다', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600))
      else ...[
        if (firsts.isNotEmpty) group('1등', firsts, true),
        if (firsts.isNotEmpty && seconds.isNotEmpty) const SizedBox(height: 6),
        if (seconds.isNotEmpty) group('2등', seconds, false),
      ],
    ]));
  }

  Widget _notice(IconData icon, String title, String body) => _box(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: _look.b),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(body, style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.grey.shade700)),
          ]),
        ),
      ]));

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: child,
      );
}
