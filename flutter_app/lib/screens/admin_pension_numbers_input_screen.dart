// 관리자 — 연금복권720+ 당첨번호 입력 (연구용 · 과거 회차까지)
// pension_winning_numbers 에 회차·추첨일·1등 조·6자리·보너스를 저장한다. 일반 화면 '발행'(pension_rounds)은 하지 않는다
// (발행은 기존 '연금 당첨회차 생성' 메뉴). 이미 있는 회차는 덮어쓰기 전에 확인을 받는다.
// 입력한 당첨번호는 서버의 연금 번호 엔진 · 가설 트랙이 읽는다 (최소 50회부터 가동).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 연금복권720+ 1회 추첨일 (목) — 회차 r 추첨일 = 1회 + 7(r−1)일
final DateTime kPensionDay1 = DateTime(2020, 5, 7);
DateTime pensionDrawDate(int round) => kPensionDay1.add(Duration(days: 7 * (round - 1)));
String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 입력 대상 최신 회차 = 오늘(목 20시 KST 이후면 이번 주 포함)까지 추첨된 회차
int pensionLatestDrawn(DateTime nowKst) {
  final days = nowKst.difference(kPensionDay1).inDays;
  var r = days ~/ 7 + 1;
  if (ymd(pensionDrawDate(r)) == ymd(nowKst) && nowKst.hour < 20) r -= 1;
  return r;
}

class PensionRow {
  final int round, group;
  final String number, bonus, drawDate;
  const PensionRow(this.round, this.group, this.number, this.bonus, this.drawDate);
  factory PensionRow.fromJson(Map<String, dynamic> j) => PensionRow(
        (j['round'] as num).toInt(), (j['winning_group'] as num?)?.toInt() ?? 0, '${j['winning_number'] ?? ''}',
        '${j['bonus_number'] ?? ''}', '${j['draw_date'] ?? ''}');
}

/// 저장소 (테스트에서 교체)
class PensionNumbersStore {
  static Future<List<PensionRow>> Function() loadAll = () async {
    final out = <PensionRow>[];
    for (var off = 0;; off += 1000) {
      final rows = await Supabase.instance.client.from('pension_winning_numbers')
          .select('round,winning_group,winning_number,bonus_number,draw_date').order('round').range(off, off + 999);
      out.addAll(List<Map<String, dynamic>>.from(rows as List).map(PensionRow.fromJson));
      if ((rows).length < 1000) break;
    }
    return out;
  };
  static Future<void> Function(PensionRow r) save = (r) async {
    await Supabase.instance.client.from('pension_winning_numbers').upsert({
      'round': r.round, 'winning_group': r.group, 'winning_number': r.number, 'bonus_number': r.bonus,
      'draw_date': r.drawDate,
    }, onConflict: 'round');
  };
}

class AdminPensionNumbersInputScreen extends StatefulWidget {
  /// 테스트용 현재 시각 (KST)
  final DateTime? now;
  const AdminPensionNumbersInputScreen({super.key, this.now});
  @override
  State<AdminPensionNumbersInputScreen> createState() => _AdminPensionNumbersInputScreenState();
}

class _AdminPensionNumbersInputScreenState extends State<AdminPensionNumbersInputScreen> {
  static const _orange = Color(0xFFEF6C00);
  static const kEngineMin = 50;
  final _round = TextEditingController();
  final _date = TextEditingController();
  final _number = TextEditingController();
  final _bonus = TextEditingController();
  final _numberFocus = FocusNode();
  int _group = 0;
  Map<int, PensionRow> _rows = {};
  bool _loading = true, _saving = false;
  String? _error;

  int get _latest => pensionLatestDrawn(widget.now ?? DateTime.now().toUtc().add(const Duration(hours: 9)));
  List<int> get _missing => [for (var r = 1; r <= _latest; r++) if (!_rows.containsKey(r)) r];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_round, _date, _number, _bonus]) {
      c.dispose();
    }
    _numberFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final all = await PensionNumbersStore.loadAll();
      if (!mounted) return;
      setState(() {
        _rows = {for (final r in all) r.round: r};
        _loading = false;
        _error = null;
      });
      _prepare(_missing.isEmpty ? null : _missing.last);
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// 입력 칸 채우기 (회차만 정하고 번호는 비움 · 기존 회차면 기존 값)
  void _prepare(int? round) {
    final r = round ?? (_latest);
    final ex = _rows[r];
    _round.text = '$r';
    _date.text = ex?.drawDate.isNotEmpty == true ? ex!.drawDate.substring(0, 10) : ymd(pensionDrawDate(r));
    _number.text = ex?.number ?? '';
    _bonus.text = ex?.bonus ?? '';
    setState(() => _group = ex?.group ?? 0);
  }

  void _snack(String s) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(s), duration: const Duration(seconds: 2)));

  Future<void> _save() async {
    final r = int.tryParse(_round.text.trim());
    final n = _number.text.trim(), b = _bonus.text.trim(), d = _date.text.trim();
    if (r == null || r < 1 || r > _latest) return _snack('회차를 확인하세요 (1~$_latest회)');
    if (_group < 1 || _group > 5) return _snack('1등 조(1~5조)를 고르세요');
    if (!RegExp(r'^\d{6}$').hasMatch(n)) return _snack('1등 번호는 6자리 숫자입니다');
    if (!RegExp(r'^\d{6}$').hasMatch(b)) return _snack('보너스 번호는 6자리 숫자입니다');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) return _snack('추첨일은 YYYY-MM-DD 형식입니다');
    final ex = _rows[r];
    if (ex != null && (ex.group != _group || ex.number != n || ex.bonus != b)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('$r회 이미 저장됨'),
          content: Text('저장된 값: ${ex.group}조 ${ex.number} · 보너스 ${ex.bonus}\n새 값: $_group조 $n · 보너스 $b\n\n바꿔서 저장할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('바꿔서 저장')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _saving = true);
    try {
      final row = PensionRow(r, _group, n, b, d);
      await PensionNumbersStore.save(row);
      if (!mounted) return;
      setState(() {
        _rows[r] = row;
        _saving = false;
      });
      _snack('$r회 저장 — $_group조 $n');
      // 다음 빈 회차로 (최신부터 거꾸로)
      final next = _missing.where((x) => x < r).toList();
      _prepare(next.isNotEmpty ? next.last : (_missing.isNotEmpty ? _missing.last : null));
      _numberFocus.requestFocus();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('저장 실패: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('연금복권 당첨번호 입력'), backgroundColor: _orange, foregroundColor: Colors.white),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_error != null)
                Text('불러오기 실패: $_error', style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
              _progress(),
              const SizedBox(height: 12),
              _form(),
              const SizedBox(height: 16),
              _missingBox(),
              const SizedBox(height: 16),
              _recent(),
            ]),
    );
  }

  Widget _progress() {
    final have = _rows.keys.where((r) => r <= _latest).length;
    final ratio = _latest == 0 ? 0.0 : have / _latest;
    return Container(
      key: const ValueKey('pension_progress'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('입력 $have / $_latest회', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _orange)),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: ratio, minHeight: 8, color: _orange, backgroundColor: Colors.white,
            borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 6),
        Text(
            have >= kEngineMin
                ? '연금 번호 엔진 · 가설 트랙 가동 중 (최근 최대 200회 기준)'
                : '연금 번호 엔진은 $kEngineMin회부터 가동 — ${kEngineMin - have}회 더 입력하면 시작합니다 (최근 회차부터 입력 추천)',
            style: TextStyle(fontSize: 11.5, color: Colors.brown.shade700)),
        Text('여기서 입력한 번호는 연구용입니다. 일반 화면 발행은 기존 \'연금 당첨회차 생성\' 메뉴에서 합니다.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
      ]),
    );
  }

  Widget _form() {
    final r = int.tryParse(_round.text);
    final exists = r != null && _rows.containsKey(r);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _orange.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('pension_round'),
              controller: _round,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '회차', suffixText: '회', isDense: true),
              onSubmitted: (v) => _prepare(int.tryParse(v)),
              onChanged: (v) {
                final x = int.tryParse(v);
                if (x != null && x >= 1) _date.text = _rows[x]?.drawDate.isNotEmpty == true ? _rows[x]!.drawDate.substring(0, 10) : ymd(pensionDrawDate(x));
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const ValueKey('pension_date'),
              controller: _date,
              decoration: const InputDecoration(labelText: '추첨일 (자동)', isDense: true),
            ),
          ),
        ]),
        if (exists)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('이미 저장된 회차 — 바꾸면 확인 후 덮어씁니다', style: TextStyle(fontSize: 11, color: Colors.orange.shade900)),
          ),
        const SizedBox(height: 12),
        const Text('1등 조', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Row(children: [
          for (var g = 1; g <= 5; g++) ...[
            Expanded(
              child: ChoiceChip(
                key: ValueKey('pension_group_$g'),
                label: SizedBox(width: double.infinity, child: Text('$g조', textAlign: TextAlign.center)),
                selected: _group == g,
                selectedColor: _orange,
                labelStyle: TextStyle(fontWeight: FontWeight.w900, color: _group == g ? Colors.white : Colors.black87),
                onSelected: (_) {
                  setState(() => _group = g);
                  _numberFocus.requestFocus();
                },
              ),
            ),
            if (g < 5) const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('pension_number'),
          controller: _number,
          focusNode: _numberFocus,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 8),
          decoration: const InputDecoration(labelText: '1등 번호 6자리', counterText: ''),
        ),
        TextField(
          key: const ValueKey('pension_bonus'),
          controller: _bonus,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 6),
          decoration: const InputDecoration(labelText: '보너스 번호 6자리', counterText: ''),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('pension_save'),
            style: FilledButton.styleFrom(backgroundColor: _orange, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: Text(_saving ? '저장 중…' : '저장하고 다음 빈 회차로', style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ]),
    );
  }

  Widget _missingBox() {
    final m = _missing;
    final show = m.reversed.take(40).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('빈 회차 ${m.length}개 (최신부터)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      if (m.isEmpty)
        Text('모든 회차 입력 완료', style: TextStyle(fontSize: 12, color: Colors.green.shade800))
      else
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in show)
            ActionChip(
              key: ValueKey('missing_$r'),
              label: Text('$r회', style: const TextStyle(fontSize: 11.5)),
              visualDensity: VisualDensity.compact,
              onPressed: () => _prepare(r),
            ),
          if (m.length > show.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('외 ${m.length - show.length}개', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ),
        ]),
    ]);
  }

  Widget _recent() {
    final rows = _rows.values.toList()..sort((a, b) => b.round.compareTo(a.round));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('저장된 회차 (최신 20개)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      for (final r in rows.take(20))
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${r.round}회 · ${r.group}조 ${r.number}', style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
          subtitle: Text('보너스 ${r.bonus} · ${r.drawDate.length >= 10 ? r.drawDate.substring(0, 10) : r.drawDate}'),
          trailing: const Icon(Icons.edit_rounded, size: 18),
          onTap: () => _prepare(r.round),
        ),
    ]);
  }
}
