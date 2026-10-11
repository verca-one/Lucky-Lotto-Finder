import 'package:flutter/material.dart';

// 랜덤확률분석엔진이 실제 계산에 개입한 결과임을 명시하는 공통 배지.
// 단순 통계 조회, 로컬 계산, 과거 데이터 표시에는 사용하지 않는다.
class EngineReflectionBadge extends StatelessWidget {
  final int? trainingRound;   // 학습 기준 회차 (예: 1244)
  final int? targetRound;     // 예측 대상 회차 (예: 1245)
  final String? modelVersion; // 엔진 model_version (예: 2.1)
  final bool compact;         // true = 한 줄 축약형

  const EngineReflectionBadge({
    super.key,
    this.trainingRound,
    this.targetRound,
    this.modelVersion,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasRounds = trainingRound != null && targetRound != null;
    final ver = modelVersion != null ? ' v$modelVersion' : '';

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2A4A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.memory_rounded, size: 11, color: Color(0xFF7EC8E3)),
          const SizedBox(width: 4),
          Text(
            hasRounds
                ? '엔진$ver 반영 · $trainingRound회→$targetRound회'
                : '엔진$ver 반영',
            style: const TextStyle(
              fontSize: 10, color: Color(0xFF7EC8E3),
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Row(children: [
        const Icon(Icons.memory_rounded, size: 14, color: Color(0xFF7EC8E3)),
        const SizedBox(width: 6),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('엔진$ver 반영',
                style: const TextStyle(
                  fontSize: 11, color: Color(0xFF7EC8E3),
                  fontWeight: FontWeight.w800,
                )),
            if (hasRounds)
              Text('$trainingRound회까지 학습 → $targetRound회 예측',
                  style: const TextStyle(
                    fontSize: 10, color: Color(0xFF4A7FA5),
                  )),
          ],
        )),
      ]),
    );
  }
}
