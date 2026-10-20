// 엔진 브리핑 ④ — 당첨 이력 패널 · 즐겨찾기 (일반 모드와 같은 'favorite_stores')
import 'package:flutter/material.dart';
import 'package:flutter_app/models/lottery_store.dart';
import 'package:flutter_app/services/route/region_research_repository.dart';
import 'package:flutter_app/widgets/briefing_store_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LotteryStore _store(String code, String name, int f, int s) => LotteryStore.fromJson({
      'dhlottery_code': code, 'store_name': name, 'address': '경기 수원시 $name', 'lottery_type': 'lotto',
      'first_count': f, 'second_count': s,
    });

void main() {
  testWidgets('당첨 이력 — 1·2등 횟수 · 최근 1등 · 회차 칩(8개+외 N회)', (tester) async {
    final rounds = [1240, 1200, 1150, 1100, 1050, 1000, 950, 900, 850, 800];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StoreWinHistoryPanel(
      history: StoreWinHistory(firstRounds: rounds, secondRounds: const [1230], purchaseMethods: const {'자동': 7, '수동': 3, '미상': 1}),
      firstCount: 10, secondCount: 25, latestRound: 1246,
    ))));
    expect(find.text('최근 1등 1240회 (6회 전)'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
    expect(find.text('1240회'), findsOneWidget);
    expect(find.text('900회'), findsOneWidget);
    expect(find.text('850회'), findsNothing);
    expect(find.text('외 2회'), findsOneWidget);
    expect(find.text('당첨 구매 방식: 자동 7 · 수동 3'), findsOneWidget);
  });

  testWidgets('추천 명당 ★ → 일반 모드 즐겨찾기에 추가 · 즐겨찾기 목록에 이번 주 추천 표시', (tester) async {
    SharedPreferences.setMockInitialValues({'favorite_stores': ['B']});
    final db = {'A': _store('A', '행운복권', 12, 30), 'B': _store('B', '대박마트', 1, 4)};
    BriefingFavorites.fetchStores = (codes) async => [for (final c in codes) if (db[c] != null) db[c]!];
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: Column(children: [
      FavoriteStoreStar(code: 'A', name: '행운복권'),
      BriefingFavoriteStores(pickCodes: {'A'}),
    ])))));
    await tester.pumpAndSettle();
    expect(find.text('내 즐겨찾기 판매점 1곳'), findsOneWidget);
    expect(find.text('대박마트'), findsOneWidget);
    expect(find.text('이번 주 추천'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('fav_star_A')).first);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('favorite_stores')!.toSet(), {'A', 'B'});
    expect(find.text('내 즐겨찾기 판매점 2곳'), findsOneWidget);
    expect(find.text('이번 주 추천'), findsOneWidget);
    expect(find.textContaining('겹치는 곳 1곳'), findsOneWidget);

    // 목록에서 ★ 해제
    await tester.tap(find.byKey(const ValueKey('fav_star_B')));
    await tester.pumpAndSettle();
    expect(prefs.getStringList('favorite_stores')!.toSet(), {'A'});
    expect(find.text('대박마트'), findsNothing);
  });
}
