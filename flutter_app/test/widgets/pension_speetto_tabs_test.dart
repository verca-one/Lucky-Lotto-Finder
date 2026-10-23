// 연금복권 · 스피또 탭 — 관리자 브리핑 · 일반 모드 추천
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/pension_briefing.dart';
import 'package:flutter_app/widgets/pension_briefing_view.dart';
import 'package:flutter_app/widgets/speetto_briefing_view.dart';
import 'package:flutter_app/widgets/winning_number_boxes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _waiting = <String, dynamic>{
  'target_round': 338, 'latest_round': 337, 'draw_date': '2026-10-22', 'numbers_entered': 1,
  'engine': {'status': 'waiting', 'note': '당첨번호 1회 입력 — 50회부터 가동 (관리자 → 연금복권 당첨번호 입력)'},
  'stores': {'status': 'ok', 'rule': '연금 1·2등 판매점 기록 반감기 100회 감쇠', 'stores': [
    {'name': '하당복권방', 'region': '전남광주 목포시', 'first': 3, 'second': 2, 'last_round': 336, 'p_next': 0.0273},
  ]},
  'track': {'status': 'waiting', 'note': '제미나이 연금 가설이 아직 없습니다 (매일 17시 AI 전략기획부)'},
};

final _ok = <String, dynamic>{
  'target_round': 338, 'draw_date': '2026-10-22',
  'engine': {'status': 'ok', 'tickets': [{'group': 4, 'number': '586358'}], 'rule': '최근 당첨번호 자리별 숫자 빈도 기반 추천'},
  'stores': [{'store_code': '74660469', 'name': '하당복권방', 'region': '전남광주 목포시', 'first': 3, 'second': 2, 'last_round': 336}],
  'track': {'status': 'ok', 'tickets': [{'group': 2, 'number': '147599'}],
    'hypotheses': ['직전 1등 번호에 같은 숫자 반복일 때 1등 번호 5~9 숫자 개수가 높다']},
  'disclaimer': '모든 추천은 참고용입니다.',
};

void main() {
  testWidgets('관리자 연금 탭 — 엔진 대기(입력 바로가기) · 명당 · 가설 대기', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PensionBriefingView(
        loader: () async => PensionBriefing.fromPayload(_waiting)))));
    await tester.pumpAndSettle();
    expect(find.text('338회 추천 · 2026-10-22 (목)'), findsOneWidget);
    expect(find.textContaining('50회부터 가동'), findsOneWidget);
    expect(find.byKey(const ValueKey('pension_input_shortcut')), findsOneWidget);
    expect(find.text('하당복권방'), findsOneWidget);
    expect(find.text('다음 회차 1·2등 추정 2.73%'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('제미나이 연금 가설이 아직 없습니다'), 200);
    expect(find.textContaining('제미나이 연금 가설이 아직 없습니다'), findsOneWidget);
  });

  testWidgets('일반 모드 연금 탭 — 상단 당첨번호 → ① 추천번호 · ② 연금 판매점(★ 저장) · 가설 트랙 없음', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PensionBriefingView(
        admin: false, loader: () async => PensionBriefing.fromPublic(_ok),
        winningLoader: () async => const PensionLatestWinning(337, 2, '060727', '293160', '2026-10-15')))));
    await tester.pumpAndSettle();
    expect(find.text('연금복권720+ 337회 당첨번호'), findsOneWidget);
    expect(find.text('2조'), findsOneWidget);
    expect(find.text('각조'), findsOneWidget);
    expect(find.text('4조'), findsOneWidget);
    expect(find.text('추천번호'), findsOneWidget);
    expect(find.text('연금 번호 엔진'), findsNothing);
    await tester.scrollUntilVisible(find.text('하당복권방'), 200);
    expect(find.text('연금 판매점'), findsOneWidget);
    expect(find.byKey(const ValueKey('fav_star_74660469')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fav_star_74660469')));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getStringList('favorite_stores'), ['74660469']);
    expect(find.textContaining('제미나이'), findsNothing);
    expect(find.textContaining('같은 숫자 반복일 때'), findsNothing);
    expect(find.byKey(const ValueKey('pension_input_shortcut')), findsNothing);
  });

  testWidgets('로또 당첨번호 공 — 6개 + 보너스', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LottoWinningBoxes(numbers: [44, 2, 13, 3, 41, 5], bonus: 7))));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('44'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);
  });

  testWidgets('스피또 탭 — 데이터 정리 필요면 관리자는 사유 · 일반은 준비 중 · 정상이면 게임별 판매점 ★', (tester) async {
    final bad = SpeettoBriefing.fromPayload({'games': [
      {'game': 'speedlotto_1000', 'label': '스피또1000', 'status': 'data_invalid', 'same_ratio': 0.99, 'stores': []}]});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SpeettoBriefingView(key: const ValueKey('s1'), loader: () async => bad))));
    await tester.pumpAndSettle();
    expect(find.textContaining('데이터 정리 필요'), findsOneWidget);
    expect(find.textContaining('스피또1000 99%'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SpeettoBriefingView(key: const ValueKey('s2'), admin: false, loader: () async => null))));
    await tester.pumpAndSettle();
    expect(find.text('스피또 판매점 정보를 준비하고 있습니다.'), findsOneWidget);
    expect(find.textContaining('제미나이'), findsNothing);

    SharedPreferences.setMockInitialValues({});
    final ok = SpeettoBriefing.fromPayload({'games': [
      {'game': 'speedlotto_1000', 'label': '스피또1000', 'status': 'ok', 'latest_edition': 110, 'stores': [
        {'store_code': '71161762', 'name': '행운복권방', 'region': '서울 서대문구', 'first': 3, 'second': 0, 'last_edition': 110}]}]});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SpeettoBriefingView(key: const ValueKey('s3'), admin: false, loader: () async => ok))));
    await tester.pumpAndSettle();
    expect(find.text('스피또1000 · 최근 110차'), findsOneWidget);
    expect(find.text('행운복권방'), findsOneWidget);
    expect(find.byKey(const ValueKey('fav_star_71161762')), findsOneWidget);
  });

  testWidgets('스피또 판매 현황 — 남은 1등 지수 · 출고율 · 남은 매수', (tester) async {
    final b = SpeettoBriefing.fromPayload({'games': [], 'status': {'status': 'ok', 'snap_date': '2026-10-24', 'editions': [
      {'game': 'SP500', 'edition': 48, 'ship_rate': 58, 'rnk1_total': 5, 'rnk1_left': 3, 'rnk2_total': 100, 'rnk2_left': 48,
        'prize1': '2억원', 'prize2': '1백만원', 'index': 1.429},
      {'game': 'SP2000', 'edition': 70, 'ship_rate': 28, 'rnk1_total': 8, 'rnk1_left': 8, 'rnk2_total': 24, 'rnk2_left': 21,
        'prize1': '10억원', 'index': 1.389},
      {'game': 'SP2000', 'edition': 69, 'ship_rate': 99, 'rnk1_total': 10, 'rnk1_left': 1, 'near_end': true},
    ]}});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SpeettoBriefingView(admin: false, loader: () async => b))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('speetto_edition_SP500_48')), 200);
    expect(find.text('스피또500 48회'), findsOneWidget);
    expect(find.text('남은 1등 지수 1.43'), findsOneWidget);
    expect(find.text('출고율 58%'), findsOneWidget);
    expect(find.textContaining('1등(2억원) 남은 3 / 5장'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('speetto_edition_SP2000_69')), 200);
    expect(find.text('출고 거의 끝'), findsOneWidget);
  });
}
