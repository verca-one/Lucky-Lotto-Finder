// 본 브리핑 번호 세트 표시 — 체크(산 번호: 흐리게 + 취소선, 폰에 기억) · ★(일반 모드 나의 번호 › 저장한 번호에 넣기/빼기)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kBriefingCheckedKey = 'briefing_set_checked';
const kMyNumbersKey = 'my_lotto_numbers';

String _numsKey(List<int> ns) => ([...ns]..sort()).join(',');

class BriefingSetMarks extends StatefulWidget {
  final String id; // 회차 · 영역 · 순번 (예: '1251:official:0')
  final List<int> numbers;
  final Widget child;
  const BriefingSetMarks({super.key, required this.id, required this.numbers, required this.child});
  @override
  State<BriefingSetMarks> createState() => _BriefingSetMarksState();
}

class _BriefingSetMarksState extends State<BriefingSetMarks> {
  bool _checked = false, _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static bool _hasNumbers(List<String> saved, String key) => saved.any((s) {
        try {
          return _numsKey([for (final n in (jsonDecode(s) as Map)['numbers'] as List) (n as num).toInt()]) == key;
        } catch (_) {
          return false;
        }
      });

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final checked = (prefs.getStringList(kBriefingCheckedKey) ?? const []).contains(widget.id);
    final saved = _hasNumbers(prefs.getStringList(kMyNumbersKey) ?? const [], _numsKey(widget.numbers));
    if (!mounted) return;
    setState(() {
      _checked = checked;
      _saved = saved;
    });
  }

  Future<void> _toggleCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final l = {...prefs.getStringList(kBriefingCheckedKey) ?? const <String>[]};
    _checked ? l.remove(widget.id) : l.add(widget.id);
    await prefs.setStringList(kBriefingCheckedKey, l.toList());
    if (mounted) setState(() => _checked = !_checked);
  }

  /// 저장한 번호 — 추천 메뉴들과 같은 형식 · 최대 50개
  Future<void> _toggleSave() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _numsKey(widget.numbers);
    var l = prefs.getStringList(kMyNumbersKey) ?? <String>[];
    if (_saved) {
      l = l.where((s) => !_hasNumbers([s], key)).toList();
    } else {
      l = [jsonEncode({'numbers': [...widget.numbers]..sort(), 'date': DateTime.now().toIso8601String(), 'type': 'briefing'}), ...l];
      if (l.length > 50) l = l.sublist(0, 50);
    }
    await prefs.setStringList(kMyNumbersKey, l);
    if (!mounted) return;
    setState(() => _saved = !_saved);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(_saved ? '나의 번호에 저장했습니다 (즐겨찾기 › 나의 번호)' : '나의 번호에서 뺐습니다'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(
          width: 28,
          child: Checkbox(
            key: ValueKey('set_check_${widget.id}'),
            value: _checked,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (_) => _toggleCheck(),
          ),
        ),
        Expanded(
          child: Stack(alignment: Alignment.center, children: [
            Opacity(opacity: _checked ? 0.32 : 1, child: widget.child),
            if (_checked)
              Positioned(
                left: 0, right: 0,
                child: IgnorePointer(child: Container(key: ValueKey('set_strike_${widget.id}'), height: 2.2, color: Colors.black54)),
              ),
          ]),
        ),
        IconButton(
          key: ValueKey('set_star_${widget.id}'),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: _saved ? '나의 번호에서 빼기' : '나의 번호에 저장',
          icon: Icon(_saved ? Icons.star_rounded : Icons.star_border_rounded, color: _saved ? const Color(0xFFFFB300) : Colors.grey, size: 22),
          onPressed: _toggleSave,
        ),
      ]);
}
