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
  List<int> _numbers = [];
  bool _isRolling = false;
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
    setState(() => _isRolling = true);
    _animController.reset();
    _animController.forward();

    // 주사위 굴리는 애니메이션 (숫자 깜빡임)
    final rng = Random();
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      setState(() {
        _numbers = _generateNumbers(rng);
      });
    }

    // 최종 번호 생성
    setState(() {
      _numbers = _generateNumbers(rng);
      _numbers.sort();
      _isRolling = false;
    });
  }

  List<int> _generateNumbers(Random rng) {
    final Set<int> nums = {};
    while (nums.length < 6) {
      nums.add(rng.nextInt(45) + 1);
    }
    return nums.toList()..sort();
  }

  Color _getBallColor(int number) {
    if (number <= 10) return Colors.yellow.shade700;
    if (number <= 20) return Colors.blue;
    if (number <= 30) return Colors.red;
    if (number <= 40) return Colors.grey.shade700;
    return Colors.green;
  }

  Future<void> _saveNumbers() async {
    if (_numbers.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('my_lotto_numbers') ?? [];
    final entry = jsonEncode({
      'numbers': _numbers,
      'date': DateTime.now().toIso8601String(),
    });
    saved.insert(0, entry);
    // 최대 50개까지 저장
    if (saved.length > 50) saved.removeLast();
    await prefs.setStringList('my_lotto_numbers', saved);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('번호가 저장되었습니다! 즐겨찾기 > 나의 번호에서 확인하세요')),
    );
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 주사위 아이콘
              Icon(
                Icons.casino,
                size: 60,
                color: _isRolling ? Colors.orange : Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              const Text(
                '주사위를 굴려 행운의 번호를 뽑아보세요!',
                style: TextStyle(fontSize: 15, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // 번호 공 표시
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: _numbers.isEmpty
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(6, (_) => _emptyBall()),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _numbers.map((n) => _ballWidget(n)).toList(),
                      ),
              ),
              const SizedBox(height: 32),

              // 주사위 굴리기 버튼
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isRolling ? null : _rollDice,
                  icon: AnimatedBuilder(
                    animation: _animController,
                    builder: (_, child) => Transform.rotate(
                      angle: _animController.value * 4 * pi,
                      child: child,
                    ),
                    child: const Icon(Icons.casino, size: 24),
                  ),
                  label: Text(
                    _isRolling ? '굴리는 중...' : '주사위 굴리기',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 저장 버튼
              if (_numbers.isNotEmpty && !_isRolling)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _saveNumbers,
                    icon: const Icon(Icons.bookmark_add, size: 20),
                    label: const Text('이 번호 저장하기', style: TextStyle(fontSize: 15)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                      side: BorderSide(color: Colors.orange.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyBall() {
    return Container(
      width: 42,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text('?', style: TextStyle(fontSize: 18, color: Colors.grey)),
      ),
    );
  }

  Widget _ballWidget(int number) {
    final color = _getBallColor(number);
    return Container(
      width: 42,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$number',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
