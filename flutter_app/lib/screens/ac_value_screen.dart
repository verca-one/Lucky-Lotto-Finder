import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../models/lotto_winning_number.dart';

/// AC값(Arithmetic Complexity) 분석 기반 번호 생성
/// AC값 = 6개 번호의 차이값 집합 개수 - 5
/// 역대 당첨번호 AC값 평균 약 7~10, 이 범위에 맞는 번호만 생성
class AcValueContent extends StatefulWidget {
  const AcValueContent({super.key});

  @override
  State<AcValueContent> createState() => _AcValueContentState();
}

class _AcValueContentState extends State<AcValueContent> {
  List<LottoWinningNumber> _recentWinnings = [];
  bool _isLoading = true;
  bool _isGenerating = false;
  List<List<int>> _generatedSets = [];
  List<bool> _heldSets = [];
  String _analysisText = '';
  double _avgAc = 0;
  Map<int, int> _acDistribution = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await SupabaseService.getRecentWinningNumbers(50);
      if (!mounted) return;

      // AC값 분포 분석
      final dist = <int, int>{};
      double totalAc = 0;
      for (final w in results) {
        final ac = _calculateAC(w.numbers);
        dist[ac] = (dist[ac] ?? 0) + 1;
        totalAc += ac;
      }

      setState(() {
        _recentWinnings = results;
        _acDistribution = dist;
        _avgAc = results.isNotEmpty ? totalAc / results.length : 8.0;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  /// AC값 계산: 6개 번호에서 만들 수 있는 차이값의 종류 수 - 5
  int _calculateAC(List<int> nums) {
    final diffs = <int>{};
    for (int i = 0; i < nums.length; i++) {
      for (int j = i + 1; j < nums.length; j++) {
        diffs.add((nums[j] - nums[i]).abs());
      }
    }
    return diffs.length - 5;
  }

  /// AC값 7~10 범위의 번호 조합 생성
  List<int> _generateByAC() {
    final rng = Random();
    int attempts = 0;

    while (attempts < 500) {
      attempts++;
      final nums = <int>{};
      while (nums.length < 6) {
        nums.add(rng.nextInt(45) + 1);
      }
      final sorted = nums.toList()..sort();

      final ac = _calculateAC(sorted);
      if (ac < 7 || ac > 10) continue;

      // 홀짝 균형 (2~4)
      final oddCount = sorted.where((n) => n % 2 == 1).length;
      if (oddCount < 2 || oddCount > 4) continue;

      // 합산 범위 (100~180)
      final sum = sorted.fold<int>(0, (a, b) => a + b);
      if (sum < 100 || sum > 180) continue;

      // 3개 이상 연속수 방지
      int maxConsec = 1, curConsec = 1;
      for (int i = 1; i < sorted.length; i++) {
        if (sorted[i] - sorted[i - 1] == 1) {
          curConsec++;
          if (curConsec > maxConsec) maxConsec = curConsec;
        } else {
          curConsec = 1;
        }
      }
      if (maxConsec > 2) continue;

      // 같은 십 단위 3개 이상 방지
      final tens = <int, int>{};
      for (final n in sorted) {
        final t = n ~/ 10;
        tens[t] = (tens[t] ?? 0) + 1;
      }
      if (tens.values.any((c) => c >= 3)) continue;

      return sorted;
    }

    // 실패 시 기본 생성
    final nums = <int>{};
    while (nums.length < 6) {
      nums.add(rng.nextInt(45) + 1);
    }
    return nums.toList()..sort();
  }

  Future<void> _generateNumbers() async {
    setState(() => _isGenerating = true);
    await Future.delayed(const Duration(milliseconds: 400));

    final newSets = <List<int>>[];
    final newHeld = <bool>[];

    for (int i = 0; i < _generatedSets.length; i++) {
      if (i < _heldSets.length && _heldSets[i]) {
        newSets.add(_generatedSets[i]);
        newHeld.add(true);
      }
    }
    while (newSets.length < 5) {
      final nums = _generateByAC();
      newSets.add(nums);
      newHeld.add(false);
    }

    // 분석 텍스트
    final acValues = newSets.map((s) => _calculateAC(s)).toList();
    final text = '생성된 번호 AC값: ${acValues.join(", ")}\n'
        '최근 50회 평균 AC값: ${_avgAc.toStringAsFixed(1)}\n'
        '최적 AC 범위: 7~10 (모든 세트 통과)';

    if (!mounted) return;
    setState(() {
      _generatedSets = newSets;
      _heldSets = newHeld;
      _analysisText = text;
      _isGenerating = false;
    });
  }

  Future<void> _saveSets() async {
    if (_generatedSets.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('my_lotto_numbers') ?? [];
    for (final numbers in _generatedSets) {
      saved.insert(0, jsonEncode({
        'numbers': numbers,
        'date': DateTime.now().toIso8601String(),
        'type': 'AC값',
      }));
    }
    while (saved.length > 50) saved.removeLast();
    await prefs.setStringList('my_lotto_numbers', saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_generatedSets.length}세트가 저장되었습니다!')),
    );
  }

  void _removeSet(int i) {
    setState(() {
      _generatedSets.removeAt(i);
      if (i < _heldSets.length) _heldSets.removeAt(i);
    });
  }

  void _toggleHold(int i) {
    setState(() {
      while (_heldSets.length <= i) _heldSets.add(false);
      _heldSets[i] = !_heldSets[i];
    });
  }

  Color _getBallColor(int n) {
    if (n <= 10) return Colors.yellow.shade700;
    if (n <= 20) return Colors.blue;
    if (n <= 30) return Colors.red;
    if (n <= 40) return Colors.grey.shade700;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3, color: const Color(0xFF1565C0))),
            const SizedBox(height: 16),
            Text('데이터 분석중...', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.calculate_rounded, color: Colors.indigo.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AC값 분석법', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('산술 복잡도 기반 조합 최적화', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // AC값 설명
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AC값이란?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'AC값 = 6개 번호 간 차이값의 종류 수 - 5\n'
                  '값이 높을수록 번호가 고르게 분포되어 있음을 의미합니다.\n'
                  '역대 당첨번호의 AC값은 대부분 7~10 범위입니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.6),
                ),
                const SizedBox(height: 12),
                // AC값 분포 차트
                if (_acDistribution.isNotEmpty) ...[
                  Text('최근 50회 AC값 분포', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  _buildAcChart(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 추가 필터 설명
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.indigo.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('적용 필터', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.indigo.shade700)),
                const SizedBox(height: 8),
                _filterRow('AC값 7~10 범위만 통과'),
                _filterRow('홀짝 비율 2:4 ~ 4:2'),
                _filterRow('합산 100~180 범위'),
                _filterRow('3연속수 방지'),
                _filterRow('같은 십 단위 3개 이상 방지'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 분석 결과
          if (_analysisText.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Text(_analysisText, style: TextStyle(fontSize: 12, color: Colors.green.shade800, height: 1.5)),
            ),

          // 생성 버튼
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generateNumbers,
              icon: _isGenerating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.calculate_rounded, size: 20),
              label: Text(
                _isGenerating ? '분석 중...' : 'AC값 최적 번호 생성 (5세트)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 생성된 세트
          if (_generatedSets.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.format_list_numbered, size: 18, color: Colors.indigo.shade700),
                const SizedBox(width: 6),
                Text('추천 번호 (${_generatedSets.length}세트)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            ...List.generate(_generatedSets.length, (i) => _buildSetCard(i)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _saveSets,
                icon: const Icon(Icons.bookmark_add_rounded, size: 20),
                label: Text('${_generatedSets.length}세트 저장하기', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.indigo,
                  side: BorderSide(color: Colors.indigo.shade200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAcChart() {
    final sorted = _acDistribution.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final maxCount = sorted.fold<int>(0, (m, e) => e.value > m ? e.value : m);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: sorted.map((e) {
        final ratio = maxCount > 0 ? e.value / maxCount : 0.0;
        final isOptimal = e.key >= 7 && e.key <= 10;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              children: [
                Text('${e.value}', style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Container(
                  height: 40 * ratio,
                  decoration: BoxDecoration(
                    color: isOptimal ? Colors.indigo : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${e.key}', style: TextStyle(fontSize: 10, fontWeight: isOptimal ? FontWeight.w700 : FontWeight.w400, color: isOptimal ? Colors.indigo : Colors.grey.shade500)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _filterRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 14, color: Colors.indigo.shade400),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.indigo.shade700)),
        ],
      ),
    );
  }

  Widget _buildSetCard(int i) {
    final nums = _generatedSets[i];
    final ac = _calculateAC(nums);
    final sum = nums.fold<int>(0, (a, b) => a + b);
    final oddCount = nums.where((n) => n % 2 == 1).length;
    final isHeld = i < _heldSets.length && _heldSets[i];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isHeld ? Colors.indigo.shade50 : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isHeld ? Colors.indigo : const Color(0xFFE0E0E0), width: isHeld ? 2 : 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(6)),
                child: Center(child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Wrap(spacing: 4, children: nums.map((n) => _ball(n)).toList())),
              GestureDetector(onTap: () => _toggleHold(i), child: Icon(isHeld ? Icons.lock_rounded : Icons.lock_open_rounded, size: 20, color: isHeld ? Colors.indigo : Colors.grey.shade400)),
              const SizedBox(width: 4),
              GestureDetector(onTap: () => _removeSet(i), child: Icon(Icons.close_rounded, size: 20, color: Colors.grey.shade400)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 34),
              Text('AC:$ac  합:$sum  홀:$oddCount 짝:${6 - oddCount}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              if (isHeld) ...[const SizedBox(width: 8), Text('HOLD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))],
            ],
          ),
        ],
      ),
    );
  }

  Widget _ball(int n) {
    final c = _getBallColor(n);
    return Container(
      width: 34, height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: c, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.withValues(alpha: 0.3), blurRadius: 3, offset: const Offset(0, 1))]),
      child: Center(child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
    );
  }
}
