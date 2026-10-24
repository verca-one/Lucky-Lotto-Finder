// 회차 당첨 결과 상세 (홈 '최신 당첨 회차' 카드 탭) — DB 저장 데이터만 읽기 전용으로 표시
import 'package:flutter/material.dart';

import '../models/lottery_store.dart';
import '../services/round_status_service.dart';
import '../services/supabase_service.dart';
import '../widgets/home_round_header.dart' show RoundStatusPill, formatDrawDate, formatUpdateTime;

class _RoundResult {
  final List<int>? lottoNumbers;
  final int? lottoBonus;
  final String? pensionNumber; // '3조 123456'
  final String? pensionBonus;
  final List<LotteryStore> stores;
  const _RoundResult({this.lottoNumbers, this.lottoBonus, this.pensionNumber, this.pensionBonus, this.stores = const []});
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
  String get _key => '${c.type}:${c.round}:${c.status.name}';

  @override
  void initState() {
    super.initState();
    _result = RoundResultScreen._cache[_key];
    if (_result == null && (c.status == RoundStatus.complete || c.status == RoundStatus.numbersReady)) _load();
  }

  Future<void> _load() async {
    try {
      final stores = await SupabaseService.getStoresByRound(round: c.round, lotteryType: c.type);
      _RoundResult r;
      if (_pension) {
        final w = await SupabaseService.getPensionWinningForRound(c.round);
        r = _RoundResult(
          pensionNumber: w == null || w.winningNumber.isEmpty ? null : '${w.winningGroup}조 ${w.winningNumber}',
          pensionBonus: w == null || w.bonusNumber.isEmpty ? null : w.bonusNumber,
          stores: stores,
        );
      } else {
        final w = await SupabaseService.getWinningNumbersForRound(c.round);
        r = _RoundResult(lottoNumbers: w?.numbers, lottoBonus: w?.bonusNumber, stores: stores);
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
      appBar: AppBar(title: Text(title), backgroundColor: Colors.white, foregroundColor: const Color(0xFF14213D), elevation: 0.5),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
        _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF14213D))),
          const SizedBox(height: 4),
          Text('${formatDrawDate(c.drawDate)} 추첨',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1565C0))),
          const SizedBox(height: 10),
          Row(children: [
            RoundStatusPill(status: c.status),
            const SizedBox(width: 8),
            if (c.status == RoundStatus.complete)
              Flexible(
                child: Text(c.updatedAt != null ? '${formatUpdateTime(c.updatedAt!)} 수집 완료' : '수집 시각 기록 없음',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ),
          ]),
        ])),
        const SizedBox(height: 12),
        ..._body(),
      ]),
    );
  }

  List<Widget> _body() {
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
          _notice(Icons.pin_rounded, '당첨번호는 수집됐고, 당첨 지점(판매점)은 아직 수집 전입니다.',
              '당첨 판매점이 수집·검증되면 이 화면에 함께 표시됩니다.'),
          const SizedBox(height: 12),
          if (r != null) _numbers(r)
          else if (_failed) _notice(Icons.cloud_off_rounded, '결과를 불러오지 못했습니다.', '잠시 후 다시 열어 주세요.')
          else const Padding(padding: EdgeInsets.all(24),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))),
        ];
      case RoundStatus.error:
        return [
          _notice(Icons.error_outline_rounded, '이 회차 결과를 수집하지 못했거나 검증이 맞지 않습니다.',
              '직전 완료 회차 정보는 그대로 유지됩니다. 서버에서 다시 수집하면 정상 표시됩니다.'),
        ];
      case RoundStatus.complete:
        if (_failed) return [_notice(Icons.cloud_off_rounded, '결과를 불러오지 못했습니다.', '잠시 후 다시 열어 주세요.')];
        final r = _result;
        if (r == null) {
          return [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          ];
        }
        return [_numbers(r), const SizedBox(height: 12), _stores(r)];
    }
  }

  Widget _numbers(_RoundResult r) {
    final missing = Text('당첨번호 데이터 미확보 (DB에 이 회차 당첨번호가 저장되어 있지 않습니다)',
        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600));
    return _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('당첨번호', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      if (_pension)
        r.pensionNumber == null
            ? missing
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('1등  ${r.pensionNumber}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1C7A49))),
                if (r.pensionBonus != null) ...[
                  const SizedBox(height: 4),
                  Text('보너스  각조 ${r.pensionBonus}', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                ],
              ])
      else if (r.lottoNumbers == null)
        missing
      else
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final n in r.lottoNumbers!) _ball(n),
          if (r.lottoBonus != null) ...[
            const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Icon(Icons.add, size: 16)),
            _ball(r.lottoBonus!),
          ],
        ]),
    ]));
  }

  Widget _stores(_RoundResult r) {
    bool first(LotteryStore s) => s.prizeTier == 'first' || s.prizeTier == '1';
    final firsts = r.stores.where(first).toList();
    final seconds = r.stores.where((s) => !first(s)).toList();
    Widget group(String label, List<LotteryStore> list, Color color) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label ${list.length}곳', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 6),
            for (final s in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.storefront_rounded, size: 16, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.storeName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      Text(s.address, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                    ]),
                  ),
                ]),
              ),
          ],
        );
    return _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('당첨 판매점', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      if (r.stores.isEmpty)
        Text('저장된 당첨 판매점 기록이 없습니다', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600))
      else ...[
        if (firsts.isNotEmpty) group('1등', firsts, const Color(0xFFB8860B)),
        if (firsts.isNotEmpty && seconds.isNotEmpty) const SizedBox(height: 6),
        if (seconds.isNotEmpty) group('2등', seconds, Colors.blueGrey.shade600),
      ],
    ]));
  }

  Widget _ball(int n) {
    final color = n <= 10
        ? Colors.amber.shade700
        : n <= 20
            ? Colors.blue
            : n <= 30
                ? Colors.red
                : n <= 40
                    ? Colors.grey.shade700
                    : Colors.green;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
    );
  }

  Widget _notice(IconData icon, String title, String body) => _box(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: const Color(0xFF1565C0)),
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8EDF5)),
        ),
        child: child,
      );
}
