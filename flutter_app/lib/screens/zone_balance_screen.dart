import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../models/lotto_winning_number.dart';

/// 구간밸런스 분석법: 1~45를 5구간으로 나눠 역대 당첨번호의 구간 출현 빈도를 분석,
/// 최적 분포 비율에 맞는 번호 조합만 생성
class ZoneBalanceContent extends StatefulWidget {
  const ZoneBalanceContent({super.key});

  @override
  State<ZoneBalanceContent> createState() => _ZoneBalanceContentState();
}

class _ZoneBalanceContentState extends State<ZoneBalanceContent> {
  static const List<String> _zoneNames = ['1~9', '10~19', '20~29', '30~39', '40~45'];
  static const List<List<int>> _zoneRanges = [
    [1, 9],
    [10, 19],
    [20, 29],
    [30, 39],
    [40, 45],
  ];
  static const List<Color> _zoneColors = [
    Color(0xFFFFB300), // 노랑
    Color(0xFF1E88E5), // 파랑
    Color(0xFFE53935), // 빨강
    Color(0xFF757575), // 회색
    Color(0xFF43A047), // 초록
  ];

  List<LottoWinningNumber> _recentWinnings = [];
  bool _isLoading = true;
  bool _isGenerating = false;
  List<List<int>> _generatedSets = [];
  List<bool> _heldSets = [];
  String _analysisText = '';

  // 구간별 출현 빈도 (최근 50회 기준)
  List<double> _zoneRatios = [0, 0, 0, 0, 0];
  // 구간별 최적 개수 범위
  List<List<int>> _optimalCounts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await SupabaseService.getRecentWinningNumbers(50);
      if (!mounted) return;

      // 구간별 출현 횟수 집계
      final zoneTotals = [0, 0, 0, 0, 0];
      for (final w in results) {
        for (final n in w.numbers) {
          zoneTotals[_getZone(n)]++;
        }
      }

      final total = zoneTotals.fold<int>(0, (a, b) => a + b);
      final ratios = zoneTotals.map((c) => total > 0 ? c / total : 0.2).toList();

      // 최적 개수 범위: 비율 기반 (6개 중)
      final optimal = <List<int>>[];
      for (final r in ratios) {
        final expected = r * 6;
        final low = max(0, (expected - 0.8).floor());
        final high = min(6, (expected + 0.8).ceil());
        optimal.add([low, high]);
      }

      setState(() {
        _recentWinnings = results;
        _zoneRatios = ratios.cast<double>();
        _optimalCounts = optimal;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  int _getZone(int n) {
    if (n <= 9) return 0;
    if (n <= 19) return 1;
    if (n <= 29) return 2;
    if (n <= 39) return 3;
    return 4;
  }

  /// 구간 밸런스 + 추가 필터를 만족하는 번호 생성
  List<int> _generateBalanced() {
    final rng = Random();
    int attempts = 0;

    while (attempts < 500) {
      attempts++;
      final nums = <int>{};
      while (nums.length < 6) {
        nums.add(rng.nextInt(45) + 1);
      }
      final sorted = nums.toList()..sort();

      // 구간 분포 체크
      final zoneCounts = [0, 0, 0, 0, 0];
      for (final n in sorted) {
        zoneCounts[_getZone(n)]++;
      }

      bool zoneOk = true;
      for (int z = 0; z < 5; z++) {
        if (_optimalCounts.isNotEmpty) {
          if (zoneCounts[z] < _optimalCounts[z][0] || zoneCounts[z] > _optimalCounts[z][1]) {
            zoneOk = false;
            break;
          }
        }
      }
      if (!zoneOk) continue;

      // 최소 3개 이상 구간 사용
      final usedZones = zoneCounts.where((c) => c > 0).length;
      if (usedZones < 3) continue;

      // 홀짝 균형 (2~4)
      final oddCount = sorted.where((n) => n % 2 == 1).length;
      if (oddCount < 2 || oddCount > 4) continue;

      // 합산 범위 (100~180)
      final sum = sorted.fold<int>(0, (a, b) => a + b);
      if (sum < 100 || sum > 180) continue;

      // 3연속수 방지
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

      // 저번호(1~22) / 고번호(23~45) 비율 2~4
      final lowCount = sorted.where((n) => n <= 22).length;
      if (lowCount < 2 || lowCount > 4) continue;

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
      newSets.add(_generateBalanced());
      newHeld.add(false);
    }

    // 분석 텍스트
    final buf = StringBuffer();
    for (int si = 0; si < newSets.length; si++) {
      final zc = [0, 0, 0, 0, 0];
      for (final n in newSets[si]) zc[_getZone(n)]++;
      buf.write('세트${si + 1}: ');
      for (int z = 0; z < 5; z++) {
        buf.write('${_zoneNames[z]}(${zc[z]}) ');
      }
      buf.writeln();
    }
    buf.writeln('구간 분포가 균일한 최적 조합입니다.');

    if (!mounted) return;
    setState(() {
      _generatedSets = newSets;
      _heldSets = newHeld;
      _analysisText = buf.toString().trim();
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
        'type': '구간밸런스',
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
            Text('구간 분석중...', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
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
                decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.equalizer_rounded, color: Colors.teal.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('구간밸런스 분석법', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('5구간 분포 최적화 기반 번호 생성', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 구간 설명
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
                const Text('구간밸런스란?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  '1~45를 5구간(1~9, 10~19, 20~29, 30~39, 40~45)으로 나누어\n'
                  '역대 당첨번호의 구간별 출현 빈도를 분석합니다.\n'
                  '최적 분포에 맞는 균형 잡힌 조합만 생성합니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.6),
                ),
                const SizedBox(height: 14),
                // 구간별 출현 비율 차트
                Text('최근 50회 구간별 출현 비율', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                const SizedBox(height: 10),
                _buildZoneChart(),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 필터 설명
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('적용 필터', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.teal.shade700)),
                const SizedBox(height: 8),
                _filterRow('구간별 최적 개수 범위 준수'),
                _filterRow('최소 3개 이상 구간 사용'),
                _filterRow('홀짝 비율 2:4 ~ 4:2'),
                _filterRow('합산 100~180 범위'),
                _filterRow('3연속수 방지'),
                _filterRow('저/고번호 비율 2:4 ~ 4:2'),
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
              child: Text(_analysisText, style: TextStyle(fontSize: 11, color: Colors.green.shade800, height: 1.5)),
            ),

          // 생성 버튼
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generateNumbers,
              icon: _isGenerating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.equalizer_rounded, size: 20),
              label: Text(
                _isGenerating ? '분석 중...' : '구간밸런스 번호 생성 (5세트)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
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
                Icon(Icons.format_list_numbered, size: 18, color: Colors.teal.shade700),
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
                  foregroundColor: Colors.teal,
                  side: BorderSide(color: Colors.teal.shade200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildZoneChart() {
    return Column(
      children: List.generate(5, (z) {
        final pct = (_zoneRatios[z] * 100);
        final optText = _optimalCounts.isNotEmpty ? '${_optimalCounts[z][0]}~${_optimalCounts[z][1]}개' : '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Text(_zoneNames[z], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _zoneColors[z])),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 18,
                      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                    ),
                    FractionallySizedBox(
                      widthFactor: _zoneRatios[z].clamp(0, 1),
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(color: _zoneColors[z].withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: Text('${pct.toStringAsFixed(1)}% ($optText)', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _filterRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 14, color: Colors.teal.shade400),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
        ],
      ),
    );
  }

  Widget _buildSetCard(int i) {
    final nums = _generatedSets[i];
    final sum = nums.fold<int>(0, (a, b) => a + b);
    final oddCount = nums.where((n) => n % 2 == 1).length;
    final isHeld = i < _heldSets.length && _heldSets[i];

    // 구간 분포
    final zc = [0, 0, 0, 0, 0];
    for (final n in nums) zc[_getZone(n)]++;
    final usedZones = zc.where((c) => c > 0).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isHeld ? Colors.teal.shade50 : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isHeld ? Colors.teal : const Color(0xFFE0E0E0), width: isHeld ? 2 : 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(6)),
                child: Center(child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Wrap(spacing: 4, children: nums.map((n) => _ball(n)).toList())),
              GestureDetector(onTap: () => _toggleHold(i), child: Icon(isHeld ? Icons.lock_rounded : Icons.lock_open_rounded, size: 20, color: isHeld ? Colors.teal : Colors.grey.shade400)),
              const SizedBox(width: 4),
              GestureDetector(onTap: () => _removeSet(i), child: Icon(Icons.close_rounded, size: 20, color: Colors.grey.shade400)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 34),
              Text('합:$sum  홀:$oddCount 짝:${6 - oddCount}  구간:$usedZones개', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              if (isHeld) ...[const SizedBox(width: 8), Text('HOLD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal.shade700))],
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
