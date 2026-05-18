import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyNumbersScreen extends StatefulWidget {
  const MyNumbersScreen({super.key});

  @override
  State<MyNumbersScreen> createState() => _MyNumbersScreenState();
}

class _MyNumbersScreenState extends State<MyNumbersScreen> {
  List<Map<String, dynamic>> _savedNumbers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNumbers();
  }

  Future<void> _loadNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('my_lotto_numbers') ?? [];
    final list = saved.map((s) {
      try {
        return jsonDecode(s) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }).whereType<Map<String, dynamic>>().toList();

    if (!mounted) return;
    setState(() {
      _savedNumbers = list;
      _isLoading = false;
    });
  }

  Future<void> _deleteNumber(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('my_lotto_numbers') ?? [];
    if (index < saved.length) {
      saved.removeAt(index);
      await prefs.setStringList('my_lotto_numbers', saved);
    }
    setState(() => _savedNumbers.removeAt(index));
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

    if (_savedNumbers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.casino_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '저장된 번호가 없습니다',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              '추천 메뉴에서 번호를 생성하고 저장해보세요',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _savedNumbers.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.casino, color: Colors.orange.shade700, size: 22),
                const SizedBox(width: 8),
                Text(
                  '나의 번호 (${_savedNumbers.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }

        final item = _savedNumbers[index - 1];
        final numbers = (item['numbers'] as List).cast<int>();
        final dateStr = item['date'] as String?;
        String formattedDate = '';
        if (dateStr != null) {
          final dt = DateTime.tryParse(dateStr);
          if (dt != null) {
            formattedDate = '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: Colors.orange.shade50,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 번호 공들
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: numbers.map((n) => _ballWidget(n)).toList(),
                  ),
                ),
                // 날짜 + 삭제
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formattedDate,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _deleteNumber(index - 1),
                      child: Icon(Icons.delete_outline, size: 20, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _ballWidget(int number) {
    final color = _getBallColor(number);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$number',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
