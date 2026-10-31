// 종합 추천 판매점 — 지방장 · 연구소 · 엔진 · 제미나이 합산
import 'package:flutter_app/screens/combined_store_picks_screen.dart';
import 'package:flutter_app/services/research/agent_research_repository.dart';
import 'package:flutter_app/services/research/hypothesis_track.dart';
import 'package:flutter_test/flutter_test.dart';

AgentDelivery dl(String agent, String code, int rank, double p) =>
    AgentDelivery.fromRow({'target_round': 1248, 'agent_id': agent, 'store_code': code, 'rank': rank, 'p_first': p, 'store_name': code});

void main() {
  test('점수 = 지방장 확률 × 연구소 배수 × 제미나이 배수 · 인터넷 제외 · 제미나이 단독 명당 포함 · 엔진 순위 표시', () {
    final r = combineStorePicks(
      deliveries: [dl('서울|노원구', 'A', 1, 0.03), dl('부산|동구', 'B', 1, 0.02), dl('internet', 'N', 1, 0.09)],
      engineTop: const [AgentCentralStore(storeCode: 'B'), AgentCentralStore(storeCode: 'A')],
      labFactor: (c) => c == 'B' ? 2.0 : 1.0,
      gemini: const [
        TrackStore(code: 'A', name: 'A', pFirst: 0.03, pAdj: 0.036, factor: 1.2),
        TrackStore(code: 'G', name: '제미나이집', region: '대구 달서구', pFirst: 0.01, pAdj: 0.015, factor: 1.5),
      ],
      geminiWhy: (s) => '가설 ${s.code}',
    );
    expect(r.map((p) => p.code), ['B', 'A', 'G']);
    expect(r[0].score, closeTo(0.04, 1e-9));
    expect(r[0].engineRank, 1);
    expect(r[1].score, closeTo(0.036, 1e-9));
    expect(r[1].geminiWhy, '가설 A');
    expect(r[2].agentRank, isNull);
  });
}
