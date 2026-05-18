import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../models/lotto_winning_number.dart';

class GoldenWaveContent extends StatefulWidget {
  const GoldenWaveContent({super.key});

  @override
  State<GoldenWaveContent> createState() => _GoldenWaveContentState();
}

class _GoldenWaveContentState extends State<GoldenWaveContent> {
  List<LottoWinningNumber> _recentWinnings = [];
  bool _isLoading = true;
  bool _isGenerating = false;
  List<List<int>> _generatedSets = [];
  String _analysisText = '';

  @override
  void initState() {
    super.initState();
    _loadRecentWinnings();
  }

  Future<void> _loadRecentWinnings() async {
    try {
      final results = await SupabaseService.getRecentWinningNumbers(20);
      if (!mounted) return;
      setState(() {
        _recentWinnings = results;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  /// 번호별 출현 빈도 계산
  Map<int, int> _getFrequencyMap() {
    final freq = <int, int>{};
    for (int i = 1; i <= 45; i++) {
      freq[i] = 0;
    }
    for (final w in _recentWinnings) {
      for (final n in w.numbers) {
        freq[n] = (freq[n] ?? 0) + 1;
      }
    }
    return freq;
  }

  /// 각 번호의 마지막 출현 이후 간격(gap) 계산
  Map<int, int> _getGapMap() {
    final gap = <int, int>{};
    for (int i = 1; i <= 45; i++) {
      gap[i] = _recentWinnings.length; // 안 나왔으면 최대 gap
    }
    for (int round = 0; round < _recentWinnings.length; round++) {
      for (final n in _recentWinnings[round].numbers) {
        if (gap[n] == _recentWinnings.length) {
          gap[n] = round; // 가장 최근 출현 위치
        }
      }
    }
    return gap;
  }

  /// 핫/콜드 분류
  /// 핫: 최근 빈도 상위 15개, 콜드: 하위 15개, 웜: 나머지
  Map<String, List<int>> _classifyNumbers(Map<int, int> freq) {
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final hot = sorted.take(15).map((e) => e.key).toList();
    final cold = sorted.skip(30).map((e) => e.key).toList();
    final warm = sorted.skip(15).take(15).map((e) => e.key).toList();
    return {'hot': hot, 'warm': warm, 'cold': cold};
  }

  /// 황금파동 알고리즘: 핫3 + 웜2 + 콜드1 + gap 보정 + 합산/홀짝 검증
  List<int> _generateGoldenWave() {
    final rng = Random();
    final freq = _getFrequencyMap();
    final gap = _getGapMap();
    final classes = _classifyNumbers(freq);

    final hotList = classes['hot']!..shuffle(rng);
    final warmList = classes['warm']!..shuffle(rng);
    final coldList = classes['cold']!..shuffle(rng);

    // gap 가중치: gap이 큰 번호에 보너스 (오래 안 나온 번호 선호)
    List<int> _weightedPick(List<int> pool, int count) {
      // gap 기반 가중 셔플
      pool.sort((a, b) {
        final gapA = gap[a] ?? 0;
        final gapB = gap[b] ?? 0;
        // gap이 큰 번호 우선 + 약간의 랜덤성
        return (gapB + rng.nextInt(3)).compareTo(gapA + rng.nextInt(3));
      });
      return pool.take(count).toList();
    }

    final Set<int> result = {};

    // 핫 번호 3개
    result.addAll(_weightedPick(hotList, 3));
    // 웜 번호 2개
    result.addAll(_weightedPick(warmList, 2));
    // 콜드 번호 1개 (반전 기대)
    result.addAll(_weightedPick(coldList, 1));

    // 중복 제거 후 부족하면 전체 풀에서 보충
    final allNums = List.generate(45, (i) => i + 1)..shuffle(rng);
    for (final n in allNums) {
      if (result.length >= 6) break;
      result.add(n);
    }

    final numbers = result.take(6).toList()..sort();

    // 홀짝 균형 (2~4)
    final oddCount = numbers.where((n) => n % 2 == 1).length;
    if (oddCount < 2 || oddCount > 4) {
      return _generateGoldenWave();
    }

    // 합산 범위 (100~180)
    final sum = numbers.fold<int>(0, (a, b) => a + b);
    if (sum < 100 || sum > 180) {
      return _generateGoldenWave();
    }

    // 구간 분포: 최소 3개 이상의 구간에 분포
    final zones = <int>{};
    for (final n in numbers) {
      zones.add((n - 1) ~/ 10);
    }
    if (zones.length < 3) {
      return _generateGoldenWave();
    }

    return numbers;
  }

  String _buildAnalysis() {
    if (_recentWinnings.isEmpty) return '';

    final freq = _getFrequencyMap();
    final gap = _getGapMap();
    final classes = _classifyNumbers(freq);

    // 핫 번호 상위 5개
    final topHot = classes['hot']!.take(5).toList();
    // 가장 오래 안 나온 3개
    final gapSorted = gap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final longGap = gapSorted.take(3).map((e) => e.key).toList();

    return '최근 ${_recentWinnings.length}회 분석 결과\n'
        '핫 번호: ${topHot.join(", ")}\n'
        '장기 미출현: ${longGap.join(", ")} (반등 기대)';
  }

  Future<void> _generateNumbers() async {
    setState(() => _isGenerating = true);
    await Future.delayed(const Duration(milliseconds: 500));

    final sets = <List<int>>[];
    for (int i = 0; i < 5; i++) {
      sets.add(_generateGoldenWave());
    }

    if (!mounted) return;
    setState(() {
      _generatedSets = sets;
      _analysisText = _buildAnalysis();
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
        'type': 'golden_wave',
      }));
    }
    while (saved.length > 50) {
      saved.removeLast();
    }
    await prefs.setStringList('my_lotto_numbers', saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_generatedSets.length}세트가 저장되었습니다!')),
    );
  }

  void _removeSet(int index) {
    setState(() => _generatedSets.removeAt(index));
  }

  Color _getBallColor(int number) {
    if (number <= 10) return Colors.yellow.shade700;
    if (number <= 20) return Colors.blue;
    if (number <= 30) return Colors.red;
    if (number <= 40) return Colors.grey.shade700;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Icon(Icons.waves, color: Colors.amber.shade700, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '황금파동 분석법',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 알고리즘 설명
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '황금파동 분석 원리',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _ruleRow(Icons.local_fire_department, Colors.red, '핫 번호 3개', '최근 고빈도 출현 번호'),
                _ruleRow(Icons.thermostat, Colors.orange, '웜 번호 2개', '중간 빈도 안정 번호'),
                _ruleRow(Icons.ac_unit, Colors.blue, '콜드 번호 1개', '장기 미출현 반등 기대'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.tune, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Gap 가중치 + 홀짝균형 + 합산범위 + 구간분포 검증',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 분석 결과
          if (_analysisText.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics, size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 6),
                      Text('파동 분석', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_analysisText, style: TextStyle(fontSize: 12, color: Colors.amber.shade900)),
                ],
              ),
            ),

          const SizedBox(height: 20),

          // 생성 버튼
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generateNumbers,
              icon: _isGenerating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.waves, size: 20),
              label: Text(
                _isGenerating ? '파동 분석 중...' : '황금파동 번호 생성 (5세트)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 생성된 번호 세트
          if (_generatedSets.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.format_list_numbered, size: 20, color: Colors.amber.shade700),
                const SizedBox(width: 6),
                Text(
                  '추천 번호 (${_generatedSets.length}세트)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...List.generate(_generatedSets.length, (i) {
              final nums = _generatedSets[i];
              final sum = nums.fold<int>(0, (a, b) => a + b);
              final oddCount = nums.where((n) => n % 2 == 1).length;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.amber.shade700,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Wrap(
                            spacing: 4,
                            children: nums.map((n) => _ballWidget(n)).toList(),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _removeSet(i),
                          child: Icon(Icons.close, size: 20, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const SizedBox(width: 34),
                        Text(
                          '합:$sum  홀:$oddCount 짝:${6 - oddCount}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _saveSets,
                icon: const Icon(Icons.bookmark_add, size: 20),
                label: Text('${_generatedSets.length}세트 저장하기', style: const TextStyle(fontSize: 15)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amber.shade700,
                  side: BorderSide(color: Colors.amber.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ruleRow(IconData icon, Color color, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(desc, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ),
        ],
      ),
    );
  }

  Widget _ballWidget(int number) {
    final color = _getBallColor(number);
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: Center(
        child: Text(
          '$number',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ),
    );
  }
}
