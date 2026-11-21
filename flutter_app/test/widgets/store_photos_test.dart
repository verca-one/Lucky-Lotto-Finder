// 판매점 사진 — 브리핑 통계 한 줄 · 홈 순위 카드 사진(승인된 것만 · 없으면 그대로)
import 'package:flutter/material.dart';
import 'package:flutter_app/widgets/ranking_store_card.dart';
import 'package:flutter_app/widgets/store_photo_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('홈 순위 카드 — 승인된 사진 있으면 배지 아래 네모 사진 · 로그인했을 때만 카메라', (t) async {
    Widget card(String? url, {VoidCallback? onPhoto}) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RankingStoreCard(
        onPhotoTap: onPhoto,
        onQrTap: () {},
        data: RankingCardData.fromStore(1, {'dhlottery_code': 'A', 'store_name': '스파', 'address': '서울', 'region': '서울', 'first_count': 45},
            photoUrl: url)))));
    await t.pumpWidget(card(null));
    await t.pump();
    expect(find.byKey(const Key('ranking_store_photo')), findsNothing);
    expect(find.byKey(const Key('ranking_photo_upload')), findsNothing); // 로그인 안 함 → 카메라 없음
    var tapped = 0;
    await t.pumpWidget(card('https://example.com/a.jpg', onPhoto: () => tapped++));
    await t.pump();
    expect(find.byKey(const Key('ranking_store_photo')), findsOneWidget);
    await t.tap(find.byKey(const Key('ranking_photo_upload'))); // 로그인 → 배지 아래 카메라
    expect(tapped, 1);
    expect(find.byKey(const Key('ranking_purchase_qr')), findsOneWidget); // QR 은 펼치지 않아도 맨 아래 줄
  });

  testWidgets('사진 올리기 권한 = 프로필 로그인 — 로그인 안 했으면 고르기 창 없이 안내만', (t) async {
    SharedPreferences.setMockInitialValues({});
    bool? r;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => TextButton(
        onPressed: () async => r = await pickAndUploadStorePhoto(c, code: 'A', name: '스파'), child: const Text('올리기'))))));
    await t.tap(find.text('올리기'));
    await t.pumpAndSettle();
    expect(r, isFalse);
    expect(find.text('프로필 로그인 후 사진을 올릴 수 있습니다'), findsOneWidget);
    expect(find.text('갤러리에서 고르기'), findsNothing);
    // 관리자는 프로필 로그인 없이도 올리기 창이 열림
    SharedPreferences.setMockInitialValues({'isAdmin': true});
    await t.tap(find.text('올리기'));
    await t.pumpAndSettle();
    expect(find.text('갤러리에서 고르기'), findsOneWidget);
  });
}
