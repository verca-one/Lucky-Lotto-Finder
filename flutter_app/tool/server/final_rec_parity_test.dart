// 서버 이관 동등성 검증 — 공식 최종 추천번호(fr-1.0)를 같은 저장 입력으로 다시 계산해 저장된 스냅샷과 비교 (쓰기 없음)
//   PARITY_TARGET=1246 flutter test tool/server/final_rec_parity_test.dart
import 'package:flutter_app/services/research/final_recommendation_engine.dart';
import 'package:flutter_app/services/research/research_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'server_env.dart';

void main() {
  test('공식 최종 추천번호 서버 계산 = 저장된 스냅샷', () async {
    await initServerSupabase();
    expect(ResearchRuntime.serverWriter, isFalse);
    final target = int.parse(envOr('PARITY_TARGET', '1246'));
    final engine = FinalRecommendationEngine.instance;
    final computed = await engine.compute(target);
    expect(computed, isNotNull);
    final stored = await engine.loadStored(target, trainingEndRound: computed!.trainingEndRound);
    expect(stored, isNotNull, reason: '같은 학습 회차 저장 스냅샷 없음');
    // ignore: avoid_print
    print('snapshot=${stored!.snapshotId} training=${stored.trainingEndRound} target=$target');
    // ignore: avoid_print
    print('stored sets=${stored.sets}');
    // ignore: avoid_print
    print('server sets=${computed.sets}');
    expect(computed.trainingEndRound, stored.trainingEndRound);
    expect(computed.pool, stored.pool);
    expect(computed.sets, stored.sets);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
