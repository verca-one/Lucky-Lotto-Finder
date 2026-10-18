// 주변 지역 지방장 추천 — 수원 기준 반경 안 이웃 지역(용인·오산·안양)을 가까운 순으로
import 'package:flutter_app/services/research/agent_research_repository.dart';
import 'package:flutter_app/widgets/agent_next_picks.dart';
import 'package:flutter_app/widgets/nearby_agent_picks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

AgentDelivery d(String agent, String code, double lat, double lng) => AgentDelivery.fromRow({
      'target_round': 1247, 'agent_id': agent, 'store_code': code, 'mode': 'live', 'rank': 1, 'score': 0.1,
      'store_name': code, 'address': agent, 'lat': lat, 'lng': lng, 'history': {'first': 1, 'second': 1},
    });

void main() {
  test('수원 시청 기준 — 반경 20km 안 이웃 지역 포함, 멀리 있는 곳 제외, 가까운 순', () {
    final p = AgentNextPicks(1247, 'ag-1.1', {
      '경기|수원시': [d('경기|수원시', 'S', 37.2636, 127.0286)],
      '경기|용인시': [d('경기|용인시', 'Y', 37.3220, 127.0980)],   // 수지·기흥 쪽
      '경기|오산시': [d('경기|오산시', 'O', 37.1498, 127.0772)],
      '경기|안양시': [d('경기|안양시', 'A', 37.3943, 126.9568)],
      '부산|해운대구': [d('부산|해운대구', 'B', 35.1631, 129.1635)],
      'internet': [d('internet', 'I', 37.26, 127.03)],
    });
    final me = const LatLng(37.2636, 127.0286); // 수원시청
    final list = nearbyAgents(p, me, 20);
    expect(list.map((a) => a.agentId), ['경기|수원시', '경기|용인시', '경기|오산시', '경기|안양시']);
    expect(nearbyAgents(p, me, 10).map((a) => a.agentId), ['경기|수원시', '경기|용인시']);
    expect(list.any((a) => a.agentId == 'internet'), isFalse);
  });
}
