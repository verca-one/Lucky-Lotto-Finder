// 일반 모드 '구매예측번호' — 공개 요약만 표시 (3세트 + 요약 + 공개 연구 최대 1개)
import 'package:flutter/material.dart';
import 'package:flutter_app/screens/purchase_public_content.dart';
import 'package:flutter_test/flutter_test.dart';

final purchaseJson = {
  'target_round': 1246,
  'validation_status': '검증 통과',
  'validation_summary': '다른 구매자들이 상대적으로 덜 사는 번호 조합을 고른 추천입니다.',
  'sets': [
    {'numbers': [21, 22, 23, 29, 35, 36], 'sales_ratio': 0.83},
    {'numbers': [16, 22, 36, 43, 44, 45], 'sales_ratio': 0.84},
    {'numbers': [1, 15, 29, 30, 43, 44], 'sales_ratio': 0.84},
  ],
  'research_updated_at': '2026-10-11T11:32:27Z',
};

Future<void> pumpWith(WidgetTester tester, PublicPurchaseData data) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: PurchasePublicContent(loader: () async => data))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('3세트·요약 표시, 공개 연구 없으면 안내', (tester) async {
    await pumpWith(tester, PublicPurchaseData(PublicPurchase.fromJson(purchaseJson), null));
    expect(find.text('1246회 구매예측번호'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('public_set_$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('public_set_3')), findsNothing);
    expect(find.text('평균 조합보다 약 17% 덜 팔릴 것으로 추정'), findsOneWidget);
    expect(find.text('검증 통과'), findsOneWidget);
    expect(find.text('현재 공개 중인 연구가 없습니다.'), findsOneWidget);
  });

  testWidgets('공개 연구는 1개, 실제 상태·적용 여부 그대로', (tester) async {
    final study = PublicStudy.fromJson({
      'id': 'a1', 'source_research_id': 'r1', 'title': '수동 선택 비율 연구', 'status': '연구 중',
      'applied_to_numbers': false, 'purpose': '목적', 'method': '방법', 'progress': '학습 10건',
      'observation': null, 'limitation': '추천번호에는 적용하지 않습니다.',
      'research_updated_at': '2026-10-11T11:32:27Z',
    });
    await pumpWith(tester, PublicPurchaseData(PublicPurchase.fromJson(purchaseJson), study));
    expect(find.byKey(const ValueKey('public_study_a1')), findsOneWidget);
    expect(find.text('연구 중'), findsOneWidget);
    expect(find.text('추천번호에 적용하지 않음'), findsOneWidget);
    expect(find.text('현재 공개 중인 연구가 없습니다.'), findsNothing);
    // 연구 중인 연구를 '검증 통과'로 표시하지 않음 (요약 칩만 '검증 통과')
    expect(find.descendant(of: find.byKey(const ValueKey('public_study_a1')), matching: find.text('검증 통과')),
        findsNothing);
  });

  testWidgets('검증 실패 회차는 번호 미제공', (tester) async {
    await pumpWith(
        tester,
        PublicPurchaseData(
            PublicPurchase.fromJson({
              ...purchaseJson,
              'validation_status': '검증 실패',
              'validation_summary': '검증을 통과하지 못해 번호를 제공하지 않습니다.',
              'sets': [],
            }),
            null));
    expect(find.byKey(const ValueKey('public_set_0')), findsNothing);
    expect(find.text('이번 회차는 검증을 통과하지 못해 번호를 제공하지 않습니다.'), findsOneWidget);
  });

  testWidgets('공개 행이 없으면 준비 중', (tester) async {
    await pumpWith(tester, const PublicPurchaseData(null, null));
    expect(find.text('이번 회차 구매예측번호를 준비 중입니다.'), findsOneWidget);
  });
}
