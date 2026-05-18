import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RandomNumberContent extends StatefulWidget {
  const RandomNumberContent({super.key});

  @override
  State<RandomNumberContent> createState() => _RandomNumberContentState();
}

class _RandomNumberContentState extends State<RandomNumberContent>
    with SingleTickerProviderStateMixin {
  List<int> _currentNumbers = [];
  List<List<int>> _pickedSets = [];
  bool _isRolling = false;
  bool _hasRolled = false;
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
      setState(() => _currentNumbers = _generateNumbers(rng));
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
      saved.insert(0, jsonEncode({
        'numbers': numbers,
        'date': DateTime.now().toIso8601String(),
      }));
    }
    while (saved.length > 50) {
      saved.removeLast();
    }
    await prefs.setStringList('my_lotto_numbers', saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_pickedSets.length}세트가 저장되었습니다!')),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
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

          // 번호 공
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: (_currentNumbers.isEmpty && !_isRolling)
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

          // 버튼 행
          if (_pickedSets.length < 5)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: (_isRolling || _hasRolled) ? null : _rollDice,
                      icon: AnimatedBuilder(
                        animation: _animController,
                        builder: (_, child) => Transform.rotate(
                          angle: _animController.value * 4 * pi,
                          child: child,
                        ),
                        child: const Icon(Icons.casino, size: 20),
                      ),
                      label: Text(
                        _isRolling ? '굴리는 중...' : '주사위 굴리기',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _hasRolled ? _pickNumber : null,
                      icon: const Icon(Icons.check_circle, size: 20),
                      label: const Text('이 번호 픽!', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 24),

          // 픽한 번호 세트
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
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        children: nums.map((n) => _ballWidget(n, 32)).toList(),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _pickedSets.removeAt(i)),
                      child: Icon(Icons.close, size: 20, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
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
