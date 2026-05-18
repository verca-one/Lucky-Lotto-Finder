import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../models/lotto_winning_number.dart';

class AiNumberContent extends StatefulWidget {
  const AiNumberContent({super.key});

  @override
  State<AiNumberContent> createState() => _AiNumberContentState();
}

class _AiNumberContentState extends State<AiNumberContent> {
  List<LottoWinningNumber> _recentWinnings = [];
  bool _isLoading = true;
  bool _isGenerating = false;
  List<List<int>> _generatedSets = [];
  List<bool> _heldSets = [];
  String _analysisText = '';

  // 7183 순환 배열
  static const List<int> _cycle7183 = [7, 1, 8, 3];

  @override
  void initState() {
    super.initState();
    _loadRecentWinnings();
  }

  Future<void> _loadRecentWinnings() async {
    try {
      final results = await SupabaseService.getRecentWinningNumbers(10);
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

  /// 7183 순환 규칙 기반 번호 생성
  List<int> _generate7183Numbers() {
    final rng = Random();

    // Step 1: 현재 위치 파악 - 직전 회차들의 첫수 분석
    int predictedFirst = 7;
    if (_recentWinnings.isNotEmpty) {
      // 직전 회차의 첫수 확인
      final lastFirstNum = _recentWinnings.first.numbers.first;

      // 7183 순환에서 가장 가까운 노드 찾기
      int closestNode = _cycle7183[0];
      int minDist = 45;
      for (final node in _cycle7183) {
        final dist = (lastFirstNum - node).abs();
        if (dist < minDist) {
          minDist = dist;
          closestNode = node;
        }
      }

      // 다음 순환 노드 예측
      final currentIdx = _cycle7183.indexOf(closestNode);
      final nextIdx = (currentIdx + 1) % _cycle7183.length;
      predictedFirst = _cycle7183[nextIdx];
    }

    // Step 2: 첫수 고정 + 변형 (정수회차: 예측값, 허수회차: ±2 범위)
    final firstNum = predictedFirst + (rng.nextInt(3) - 1); // -1~+1 변동
    final clampedFirst = firstNum.clamp(1, 9);

    // Step 3: 번호대 분포 - 각 구간에서 골고루 선택
    // 구간: 1-9, 10-19, 20-29, 30-39, 40-45
    final Set<int> result = {clampedFirst};

    // 십코딩법칙: 첫수 기반으로 10번대 결정
    final tenBase = 10 + (clampedFirst + rng.nextInt(4));
    if (tenBase <= 19) result.add(tenBase);

    // 각 구간에서 1~2개씩 선택 (7: 같은 십단위 2개 이하)
    final zones = [
      [10, 19],
      [20, 29],
      [30, 39],
      [40, 45],
    ];
    for (final zone in zones) {
      if (result.length >= 6) break;
      final candidate = zone[0] + rng.nextInt(zone[1] - zone[0] + 1);
      result.add(candidate);
    }

    // 부족하면 랜덤 추가
    while (result.length < 6) {
      result.add(rng.nextInt(45) + 1);
    }

    // 초과하면 6개로 자르기
    final numbers = result.toList()..sort();
    if (numbers.length > 6) {
      // 첫수 유지하면서 6개 선택
      final keep = <int>{clampedFirst};
      final others = numbers.where((n) => n != clampedFirst).toList()..shuffle(rng);
      keep.addAll(others.take(5));
      return keep.toList()..sort();
    }

    // Step 4: 홀짝 균형 검증 (3:3 또는 4:2)
    final oddCount = numbers.where((n) => n % 2 == 1).length;
    if (oddCount < 2 || oddCount > 4) {
      // 불균형이면 재생성
      return _generate7183Numbers();
    }

    // 합산 검증 (100~180 범위)
    final sum = numbers.fold<int>(0, (a, b) => a + b);
    if (sum < 100 || sum > 180) {
      return _generate7183Numbers();
    }

    return numbers;
  }

  String _buildAnalysis() {
    if (_recentWinnings.isEmpty) return '';

    final latest = _recentWinnings.first;
    final firstNum = latest.numbers.first;

    // 가장 가까운 7183 노드
    int closestNode = _cycle7183[0];
    int minDist = 45;
    for (final node in _cycle7183) {
      final dist = (firstNum - node).abs();
      if (dist < minDist) {
        minDist = dist;
        closestNode = node;
      }
    }
    final currentIdx = _cycle7183.indexOf(closestNode);
    final nextIdx = (currentIdx + 1) % _cycle7183.length;
    final nextNode = _cycle7183[nextIdx];

    final nodeNames = {7: '회귀·기준', 1: '확장·도약', 8: '교량·연결', 3: '압축·집중'};

    return '${latest.round}회 첫수: $firstNum → 순환위치: $closestNode(${nodeNames[closestNode]})\n'
        '다음 예측 노드: $nextNode(${nodeNames[nextNode]})';
  }

  Future<void> _generateNumbers() async {
    setState(() => _isGenerating = true);
    await Future.delayed(const Duration(milliseconds: 500));

    // 홀드된 세트 유지, 나머지만 새로 생성하여 총 5세트
    final newSets = <List<int>>[];
    final newHeld = <bool>[];

    for (int i = 0; i < _generatedSets.length; i++) {
      if (i < _heldSets.length && _heldSets[i]) {
        newSets.add(_generatedSets[i]);
        newHeld.add(true);
      }
    }
    while (newSets.length < 5) {
      newSets.add(_generate7183Numbers());
      newHeld.add(false);
    }

    if (!mounted) return;
    setState(() {
      _generatedSets = newSets;
      _heldSets = newHeld;
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
        'type': '7183',
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
    setState(() {
      _generatedSets.removeAt(index);
      if (index < _heldSets.length) _heldSets.removeAt(index);
    });
  }

  void _toggleHold(int index) {
    setState(() {
      while (_heldSets.length <= index) {
        _heldSets.add(false);
      }
      _heldSets[index] = !_heldSets[index];
    });
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
              Icon(Icons.auto_awesome, color: Colors.purple.shade700, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '7183 법칙 AI 번호 추천',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 7183 설명 카드
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '7183 순환 규칙',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _ruleRow('7', '회귀·기준', '새로운 사이클의 시작점'),
                _ruleRow('1', '확장·도약', '번호 범위를 넓히는 전조'),
                _ruleRow('8', '교량·연결', '중간 지점 힘의 균형'),
                _ruleRow('3', '압축·집중', '앞쪽 쏠림 패턴 유도'),
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
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics, size: 16, color: Colors.indigo.shade700),
                      const SizedBox(width: 6),
                      Text('순환 분석', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_analysisText, style: TextStyle(fontSize: 12, color: Colors.indigo.shade800)),
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
                  : const Icon(Icons.auto_awesome, size: 20),
              label: Text(
                _isGenerating ? '분석 중...' : 'AI 번호 생성 (5세트)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
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
                Icon(Icons.format_list_numbered, size: 20, color: Colors.purple.shade700),
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
              final isHeld = i < _heldSets.length && _heldSets[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isHeld ? Colors.purple.shade100 : Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isHeld ? Colors.purple : Colors.purple.shade200,
                    width: isHeld ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.purple,
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
                          onTap: () => _toggleHold(i),
                          child: Icon(
                            isHeld ? Icons.lock : Icons.lock_open,
                            size: 20,
                            color: isHeld ? Colors.purple : Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(width: 8),
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
                        if (isHeld) ...[
                          const SizedBox(width: 8),
                          Text('HOLD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
                        ],
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
                  foregroundColor: Colors.purple.shade700,
                  side: BorderSide(color: Colors.purple.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ruleRow(String num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.purple,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(num, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
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
