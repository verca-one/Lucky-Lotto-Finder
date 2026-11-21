// 판매점 사진 — 브리핑 통계 한 줄 · 홈 순위 카드 사진(승인된 것만 · 없으면 그대로)
import 'package:flutter/material.dart';
import 'package:flutter_app/widgets/ranking_store_card.dart';
import 'package:flutter_app/widgets/store_photo_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('브리핑 통계 — 승인 · 대기 · 거절 장수 (표 없으면 숨김)', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StorePhotoStatsLine(loader: () async => {'approved': 3, 'pending': 2}))));
    await t.pumpAndSettle();
    expect(find.text('판매점 사진 — 승인 3 · 대기 2 · 거절 0'), findsOneWidget);
    expect(find.text('승인하러 가기'), findsOneWidget);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: StorePhotoStatsLine(key: const ValueKey('b'), loader: () async => throw 'no table'))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('store_photo_stats')), findsNothing);
  });

  testWidgets('홈 순위 카드 — 승인된 사진 있으면 배지 아래 네모 사진 · 없으면 없음', (t) async {
    Widget card(String? url) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RankingStoreCard(
        data: RankingCardData.fromStore(1, {'dhlottery_code': 'A', 'store_name': '스파', 'address': '서울', 'region': '서울', 'first_count': 45},
            photoUrl: url)))));
    await t.pumpWidget(card(null));
    await t.pump();
    expect(find.byKey(const Key('ranking_store_photo')), findsNothing);
    await t.pumpWidget(card('https://example.com/a.jpg'));
    await t.pump();
    expect(find.byKey(const Key('ranking_store_photo')), findsOneWidget);
  });
}
