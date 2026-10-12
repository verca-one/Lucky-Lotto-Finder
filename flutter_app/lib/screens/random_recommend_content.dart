// 일반 모드 '추천번호' — 엔진 개입 없는 랜덤 번호 추천 (5세트, 1~45 중복 없음)
// 관리자 모드(프리미엄)의 랜덤확률분석엔진 추천번호와 무관하며 DB·엔진 결과를 읽지 않는다.
import 'dart:math';

import 'package:flutter/material.dart';

/// 랜덤 추천 세트 생성 (순수 함수, 테스트 대상)
List<List<int>> randomRecommendSets({int count = 5, Random? rng}) {
  final r = rng ?? Random.secure();
  return List.generate(count, (_) {
    final pool = List<int>.generate(45, (i) => i + 1)..shuffle(r);
    return pool.take(6).toList()..sort();
  });
}

class RandomRecommendContent extends StatefulWidget {
  const RandomRecommendContent({super.key});

  @override
  State<RandomRecommendContent> createState() => _RandomRecommendContentState();
}

class _RandomRecommendContentState extends State<RandomRecommendContent> {
  late List<List<int>> _sets;

  @override
  void initState() {
    super.initState();
    _sets = randomRecommendSets();
  }

  Color _ballColor(int n) {
    if (n <= 10) return Colors.yellow.shade700;
    if (n <= 20) return Colors.blue;
    if (n <= 30) return Colors.red;
    if (n <= 40) return Colors.grey.shade700;
    return Colors.green;
  }

  Widget _ball(int n) {
    final c = _ballColor(n);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.3), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      alignment: Alignment.center,
      child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8EDF5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('추천번호', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
            const SizedBox(height: 2),
            Text('1~45 중 무작위로 고른 추천 조합입니다.', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            for (final (i, s) in _sets.indexed)
              Container(
                key: ValueKey('random_set_$i'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1565C0))),
                  ),
                  Expanded(
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: s.map(_ball).toList()),
                  ),
                ]),
              ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => setState(() => _sets = randomRecommendSets()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('다시 추천'),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text('모든 번호 조합의 1등 당첨 확률은 같습니다. 추천번호는 참고용입니다.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ]),
    );
  }
}
