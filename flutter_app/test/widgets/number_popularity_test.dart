// 번호 인기도 (pop-1.0) — 서버 저장본 해석 · 공식 세트 인기도 표시 · 비인기 추천 카드
import 'package:flutter/material.dart';
import 'package:flutter_app/services/research/number_popularity.dart';
import 'package:flutter_app/widgets/master_briefing_section.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> row() => {
      'target_round': 1246,
      'training_end_round': 1245,
      'payload': {
        'validation': {
          'passed': true,
          'test_spearman': {'R4': 0.5914, 'R3': 0.4445, 'R1': 0.1323},
          'rank1_actual_over_expected': {'pred_low_third': 0.931, 'pred_high_third': 1.103},
        },
        'official': [
          {'set': [3, 12, 19, 42, 43, 45], 'popularity_pct': 13.5, 'share_vs_random': 1.087},
          {'set': [1, 2, 5, 12, 23, 43], 'popularity_pct': 95.3, 'share_vs_random': 0.861},
          {'set': [3, 5, 6, 23, 29, 42], 'popularity_pct': 67.5, 'share_vs_random': 0.966},
        ],
        'picks': [
          {'set': [13, 14, 17, 40, 42, 45], 'popularity_pct': 0.0, 'share_vs_random': 1.282},
          {'set': [15, 27, 28, 41, 42, 43], 'popularity_pct': 0.0, 'share_vs_random': 1.271},
        ],
        'picks_status': 'registered',
        'pick_rule': '인기도 하위 5%',
      },
    };

void main() {
  test('저장본 해석 · 공식 세트 매칭 · 라벨', () {
    final p = NumberPopularity.fromRow(row());
    expect(p.passed, isTrue);
    expect(p.picks.length, 2);
    expect(p.scoreOf([43, 23, 12, 5, 2, 1])!.label, '인기 상위 5%'); // 순서 무관 매칭
    expect(p.scoreOf([1, 2, 5, 12, 23, 43])!.shareLabel, '몫 −14%');
    expect(p.scoreOf([3, 12, 19, 42, 43, 45])!.label, '비인기 하위 14%');
    expect(p.scoreOf([3, 12, 19, 42, 43, 45])!.shareLabel, '몫 +9%');
    expect(p.scoreOf([3, 5, 6, 23, 29, 42])!.tier, 1);
    expect(p.picks.first.label, '비인기 최하위권');
    expect(p.scoreOf([1, 2, 3, 4, 5, 6]), isNull);
    expect(p.validationLine, contains('4등 쏠림 상관 0.59'));
  });

  testWidgets('비인기 추천 카드 — 등록 상태 · 세트 · 몫 표시', (tester) async {
    final p = NumberPopularity.fromRow(row());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: PopularityPicksCard(no: '2', target: 1246, pop: p)))));
    expect(find.text('1246회 비인기 추천조합'), findsOneWidget);
    expect(find.text('사전 등록 완료'), findsOneWidget);
    expect(find.text('비인기 최하위권 · 몫 +28%'), findsOneWidget);
    expect(find.text('비인기 최하위권 · 몫 +27%'), findsOneWidget);
  });
}
