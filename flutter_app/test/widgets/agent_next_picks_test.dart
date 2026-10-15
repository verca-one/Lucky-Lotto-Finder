// 지방장 다음 회차 추천 판매점 — 지역 매칭 · 지역 선택 화면
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/agent_research_repository.dart';
import 'package:flutter_app/widgets/agent_next_picks.dart';
import 'package:flutter_test/flutter_test.dart';

AgentDelivery d(String agent, int rank, String code, String name, {int first = 3, int second = 9}) => AgentDelivery.fromRow({
      'target_round': 1246, 'agent_id': agent, 'store_code': code, 'mode': 'live', 'rank': rank, 'score': 0.1 / rank,
      'store_name': name, 'address': '$agent 주소 $rank',
      'history': {'first': first, 'second': second, 'rounds_since_last': 12},
    });

AgentNextPicks picks() => AgentNextPicks(1246, 'ag-1.1', {
      '서울|노원구': [d('서울|노원구', 1, 'A1', '스파'), d('서울|노원구', 2, 'A2', '노원로또')],
      '충남|천안시': [d('충남|천안시', 1, 'B1', '천안명당')],
      '경기|수원시': [d('경기|수원시', 1, 'C1', '수원복권')],
      '광주|광산구': [d('광주|광산구', 1, 'G1', '광산복권')],
      '전남|여수시': [d('전남|여수시', 1, 'J1', '여수복권')],
      '세종|세종시': [d('세종|세종시', 1, 'S1', '세종복권')],
      'internet': [d('internet', 1, 'I1', '인터넷 복권판매사이트')],
    });

void main() {
  test('지역 이름 → 지방장 (구·시 하위 구 포함)', () {
    final p = picks();
    expect(p.agentFor('서울 노원구'), '서울|노원구');
    expect(p.agentFor('충남 천안시 서북구'), '충남|천안시');
    expect(p.agentFor('경기 수원시 팔달구'), '경기|수원시');
    expect(p.agentFor('부산 해운대구'), isNull); // 데이터 없는 지역은 표시하지 않음
    expect(p.agentFor('서울'), isNull);
    expect(p.agentFor('전남광주 광산구'), '광주|광산구'); // 통합 행정명 주소
    expect(p.agentFor('전남광주 여수시'), '전남|여수시');
    expect(p.agentFor('세종'), '세종|세종시');
  });

  testWidgets('시·도 → 시·군·구 선택 시 그 지방장의 TOP5 표시', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AgentNextPicksScreen(loader: () async => picks())));
    await tester.pumpAndSettle();
    expect(find.text('1246회 지방장 추천 판매점'), findsOneWidget);
    expect(find.byKey(const ValueKey('sido_internet')), findsNothing); // 인터넷은 지역 선택에서 제외
    await tester.tap(find.byKey(const ValueKey('sido_서울')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('unit_서울|노원구')));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('agent_picks_서울|노원구'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('스파')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('노원로또')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('1등 3회 · 2등 9회 · 마지막 당첨 후 12회')), findsNWidgets(2));
  });

  testWidgets('처음 지역을 넘기면 바로 그 지역 추천', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AgentNextPicksScreen(initialRegion: '충남 천안시 동남구', loader: () async => picks())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent_picks_충남|천안시')), findsOneWidget);
    expect(find.text('천안명당'), findsOneWidget);
  });
}
