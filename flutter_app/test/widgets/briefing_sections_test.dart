// 브리핑 구역 — '구매할 번호' · '참고(구매 대상 아님)' · 장부 세트 카드 (휴대폰 폭)
import 'package:flutter/material.dart';
import 'package:flutter_app/widgets/master_briefing_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('참고 구역 — 장부 세트 그대로 · 공개 전엔 안내만', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BriefingSection(
      title: '참고 — 구매 대상 아님', subtitle: '비교용', icon: Icons.science_outlined, color: Colors.blueGrey,
      children: [
        LedgerSetsCard(no: '4', title: '1247회 Number 엔진 기본 조합', chip: '연구용 · 최종 추천 아님', color: Colors.grey,
            sets: const [[3, 5, 19, 23, 43, 45]], note: '연구용'),
        LedgerSetsCard(no: '5', title: '1247회 무작위 대조군', chip: '비교 기준 · 엔진 추천 아님', color: Colors.blueGrey,
            sets: null, note: '1247회 번호는 10/21(수) 0시에 공개됩니다'),
      ],
    )))));
    expect(find.text('참고 — 구매 대상 아님'), findsOneWidget);
    expect(find.byKey(const ValueKey('ledger_area_4')), findsOneWidget);
    expect(find.text('23'), findsOneWidget);
    expect(find.text('1247회 번호는 10/21(수) 0시에 공개됩니다'), findsOneWidget);
  });
}
