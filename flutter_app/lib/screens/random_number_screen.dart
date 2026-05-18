import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RandomNumberScreen extends StatefulWidget {
  const RandomNumberScreen({super.key});

  @override
  State<RandomNumberScreen> createState() => _RandomNumberScreenState();
}

class _RandomNumberScreenState extends State<RandomNumberScreen>
    with SingleTickerProviderStateMixin {
  List<int> _currentNumbers = [];
  List<List<int>> _pickedSets = []; // 최대 5세트
  bool _isRolling = false;
  bool _hasRolled = false; // 굴린 후 픽 대기 상태
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _rollDice() async {
    if (_isRolling) return;
    setState(() {
      _isRolling = true;
      _hasRolled = false;
    });
    _animController.reset();
    _animController.forward();

    final rng = Random();
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      setState(() {
        _currentNumbers = _generateNumbers(rng);
      });
    }

    setState(() {
      _currentNumbers = _generateNumbers(rng);
      _currentNumbers.sort();
      _isRolling = false;
      _hasRolled = true;
    });
  }

  List<int> _generateNumbers(Random rng) {
    final Set<int> nums = {};
    while (nums.length < 6) {
      nums.add(rng.nextInt(45) + 1);
    }
    return nums.toList()..sort();
  }

  void _pickNumber() {
    if (_currentNumbers.isEmpty) return;
    setState(() {
      _pickedSets.add(List.from(_currentNumbers));
      _hasRolled = false;
      _currentNumbers = [];
    });

    // 5개 채워지면 안내
    if (_pickedSets.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('5세트가 모두 채워졌습니다! 저장하거나 초기화하세요')),
      );
    }
  }

  Future<void> _saveAllNumbers() async {
    if (_pickedSets.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('my_lotto_numbers') ?? [];

    for (final numbers in _pickedSets) {
      final entry = jsonEncode({
        'numbers': numbers,
        'date': DateTime.now().toIso8601String(),
      });
      saved.insert(0, entry);
    }
    // 최대 50개까지 저장
    while (saved.length > 50) {
      saved.removeLast();
    }
    await prefs.setStringList('my_lotto_numbers', saved);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_pickedSets.length}세트가 저장되었습니다! 즐겨찾기 > 나의 번호에서 확인하세요')),
    );

    setState(() {
      _pickedSets = [];
      _currentNumbers = [];
      _hasRolled = false;
    });
  }

  void _resetAll() {
    setState(() {
      _pickedSets = [];
      _currentNumbers = [];
      _hasRolled = false;
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          '번호 생성',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 주사위 아이콘
            Icon(
              Icons.casino,
              size: 50,
              color: _isRolling ? Colors.orange : Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              '주사위를 굴려 행운의 번호를 뽑아보세요!',
              style: TextStyle(fontSize: 15, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // 현재 번호 공 표시
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: _currentNumbers.isEmpty && !_isRolling
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (_) => _emptyBall()),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _currentNumbers.map((n) => _ballWidget(n, 40)).toList(),
                    ),
            ),
            const SizedBox(height: 20),

            // 주사위 굴리기 버튼
            if (_pickedSets.length < 5)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: (_isRolling || _hasRolled) ? null : _rollDice,
                  icon: AnimatedBuilder(
                    animation: _animController,
                    builder: (_, child) => Transform.rotate(
                      angle: _animController.value * 4 * pi,
                      child: child,
                    ),
                    child: const Icon(Icons.casino, size: 22),
                  ),
                  label: Text(
                    _isRolling ? '굴리는 중...' : '주사위 굴리기',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

            // 이 번호 픽! 버튼
            if (_hasRolled && _pickedSets.length < 5) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _pickNumber,
                  icon: const Icon(Icons.check_circle, size: 22),
                  label: const Text('이 번호 픽!', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // 픽한 번호 세트 목록
            if (_pickedSets.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.format_list_numbered, size: 20, color: Colors.orange.shade700),
                  const SizedBox(width: 6),
                  Text(
                    '픽한 번호 (${_pickedSets.length}/5)',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...List.generate(_pickedSets.length, (i) {
                final nums = _pickedSets[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.orange,
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
                      ...nums.map((n) => _ballWidget(n, 32)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),

              // 저장 버튼
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _saveAllNumbers,
                  icon: const Icon(Icons.bookmark_add, size: 20),
                  label: Text('${_pickedSets.length}세트 저장하기', style: const TextStyle(fontSize: 15)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade700,
                    side: BorderSide(color: Colors.orange.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 초기화 버튼
              SizedBox(
                width: double.infinity,
                height: 40,
                child: TextButton(
                  onPressed: _resetAll,
                  child: Text('초기화', style: TextStyle(color: Colors.grey.shade600)),
                ),
              ),
            ],

            const SizedBox(height: 16),
            // 안내문
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.blue.shade400),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '최대 5세트까지 번호를 픽할 수 있습니다. 5세트가 채워지면 저장 후 초기화됩니다.',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBall() {
    return Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text('?', style: TextStyle(fontSize: 16, color: Colors.grey)),
      ),
    );
  }

  Widget _ballWidget(int number, double size) {
    final color = _getBallColor(number);
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$number',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.35,
          ),
        ),
      ),
    );
  }
}
