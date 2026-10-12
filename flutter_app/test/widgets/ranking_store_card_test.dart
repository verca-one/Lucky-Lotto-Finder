import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/badge_service.dart';
import 'package:flutter_app/services/ranking_extras_service.dart';
import 'package:flutter_app/services/research/agent_research_repository.dart';
import 'package:flutter_app/widgets/ranking_store_card.dart';

Map<String, dynamic> _store({
  String code = '11110001',
  String name = '행운복권방',
  String address = '서울 노원구 상계로 1',
  String region = '서울',
  int first = 5,
  int second = 12,
  int? latestFirst = 1180,
  int? latestSecond = 1190,
  String? rankStatus,
  int? rankChange,
}) =>
    {
      'dhlottery_code': code,
      'store_name': name,
      'address': address,
      'region': region,
      'first_count': first,
      'second_count': second,
      'latest_first_win': latestFirst,
      'latest_second_win': latestSecond,
      'rank_status': rankStatus,
      'rank_change': rankChange,
    };

const _score = AgentStoreScore(
  targetRound: 1200,
  storeCode: '11110001',
  agentId: '서울|노원구',
  agentRank: 1,
  agentSize: 88,
  score: 0.0123,
);

List<StoreBadge> _badges(int n) => [
      for (var i = 0; i < n; i++) StoreBadge('배지$i', StoreBadgeType.values[i % StoreBadgeType.values.length]),
    ];

Future<void> _pump(
  WidgetTester tester,
  Widget card, {
  double width = 411,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24), children: [card]),
    ),
  ));
  await tester.pump();
}

RankingStoreCard _card({
  int rank = 4,
  Map<String, dynamic>? store,
  RankingStoreExtras? extras,
  List<StoreBadge> badges = const [],
  List<StoreBadge> highlight = const [],
  bool expanded = false,
  VoidCallback? onTap,
  VoidCallback? onFav,
  Widget? expandedChild,
}) =>
    RankingStoreCard(
      data: RankingCardData.fromStore(rank, store ?? _store()),
      extras: extras,
      badges: badges,
      highlightBadges: highlight,
      isExpanded: expanded,
      latestRound: 1200,
      onTap: onTap,
      onFavoriteTap: onFav,
      expandedChild: expandedChild,
    );

void main() {
  group('순위 메달', () {
    test('rankTierOf: 1 금 · 2 은 · 3 동 · 4+ 기본', () {
      expect(rankTierOf(1), RankTier.gold);
      expect(rankTierOf(2), RankTier.silver);
      expect(rankTierOf(3), RankTier.bronze);
      expect(rankTierOf(4), RankTier.plain);
      expect(rankTierOf(20), RankTier.plain);
    });

    for (final (rank, tier) in [(1, 'gold'), (2, 'silver'), (3, 'bronze'), (4, 'plain'), (17, 'plain')]) {
      testWidgets('$rank위 카드 → $tier 메달', (tester) async {
        await _pump(tester, _card(rank: rank));
        expect(find.byKey(Key('rank_medal_$tier')), findsOneWidget);
        for (final other in ['gold', 'silver', 'bronze', 'plain'].where((t) => t != tier)) {
          expect(find.byKey(Key('rank_medal_$other')), findsNothing);
        }
        // 왕관은 1위만
        expect(find.byKey(const Key('rank_medal_crown')), rank == 1 ? findsOneWidget : findsNothing);
        expect(find.text('$rank'), findsOneWidget);
      });
    }
  });

  group('순위 변동', () {
    test('데이터 없음 → null', () {
      expect(RankChangeInfo.fromData(null, null), isNull);
      expect(RankChangeInfo.fromData('', null), isNull);
    });

    test('DB 값 해석', () {
      expect(RankChangeInfo.fromData('up', 3)!.move, RankMove.up);
      expect(RankChangeInfo.fromData('up', 3)!.amount, 3);
      expect(RankChangeInfo.fromData('down', -2)!.move, RankMove.down);
      expect(RankChangeInfo.fromData('down', -2)!.amount, 2);
      expect(RankChangeInfo.fromData('new', null)!.move, RankMove.isNew);
      expect(RankChangeInfo.fromData('same', 0)!.move, RankMove.same);
      expect(RankChangeInfo.fromData(null, 4)!.move, RankMove.up);
    });

    testWidgets('rank_status / rank_change 가 없으면 표시하지 않는다', (tester) async {
      await _pump(tester, _card(store: _store()));
      expect(find.byKey(const Key('rank_change')), findsNothing);
      expect(find.textContaining('▲'), findsNothing);
      expect(find.textContaining('▼'), findsNothing);
    });

    testWidgets('상승 데이터가 있으면 ▲N', (tester) async {
      await _pump(tester, _card(store: _store(rankStatus: 'up', rankChange: 3)));
      expect(find.byKey(const Key('rank_change')), findsOneWidget);
      expect(find.text('▲3'), findsOneWidget);
    });

    testWidgets('하락 데이터가 있으면 ▼N', (tester) async {
      await _pump(tester, _card(store: _store(rankStatus: 'down', rankChange: -2)));
      expect(find.text('▼2'), findsOneWidget);
    });
  });

  group('사진 없음 · 순위 변동 오른쪽', () {
    testWidgets('판매점 사진 영역을 표시하지 않는다', (tester) async {
      await _pump(tester, _card());
      expect(find.byKey(const Key('store_photo_placeholder')), findsNothing);
      expect(find.byKey(const Key('store_photo_network')), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('순위 변동은 판매점명보다 오른쪽에 크게 표시', (tester) async {
      await _pump(tester, _card(store: _store(rankStatus: 'up', rankChange: 3)));
      final tag = tester.getRect(find.byKey(const Key('rank_change')));
      final name = tester.getRect(find.byKey(const Key('ranking_store_name')));
      expect(tag.left, greaterThan(name.right - 1));
      final text = tester.widget<Text>(find.text('▲3'));
      expect(text.style!.fontSize, greaterThanOrEqualTo(16));
    });
  });

  group('지방장 연구 점수 칸', () {
    testWidgets('점수가 없으면 숨김', (tester) async {
      await _pump(tester, _card(extras: const RankingStoreExtras(gapMean: 40, hypothesisCount: 2)));
      expect(find.byKey(const Key('research_score_tile')), findsNothing);
      expect(find.text('지방장 연구 점수'), findsNothing);
      // 확률 표기 없음
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('extras 자체가 없어도 숨김', (tester) async {
      await _pump(tester, _card());
      expect(find.byKey(const Key('research_score_tile')), findsNothing);
    });

    testWidgets('점수가 있으면 지방장 내 순위와 "확률 아님" 표시', (tester) async {
      await _pump(tester, _card(extras: const RankingStoreExtras(agentScore: _score)));
      expect(find.byKey(const Key('research_score_tile')), findsOneWidget);
      expect(find.text('지방장 연구 점수'), findsOneWidget);
      expect(find.text('노원구 1/88위'), findsOneWidget);
      expect(find.textContaining('확률 아님'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    test('researchRankText: 인터넷 지방장', () {
      const s = AgentStoreScore(
          targetRound: 1, storeCode: 'x', agentId: 'internet', agentRank: 2, agentSize: 5, score: 1);
      expect(researchRankText(s), '인터넷 판매 2/5위');
    });
  });

  group('배지', () {
    testWidgets('4개 초과 → 4개 + "+N"', (tester) async {
      await _pump(tester, _card(badges: _badges(7)));
      for (var i = 0; i < 4; i++) {
        expect(find.text('배지$i'), findsOneWidget);
      }
      for (var i = 4; i < 7; i++) {
        expect(find.text('배지$i'), findsNothing);
      }
      expect(find.byKey(const Key('badge_more')), findsOneWidget);
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('4개 이하 → "+N" 없음', (tester) async {
      await _pump(tester, _card(badges: _badges(4)));
      expect(find.byKey(const Key('badge_more')), findsNothing);
    });

    testWidgets('배지 없음 → 배지 줄 없음', (tester) async {
      await _pump(tester, _card());
      expect(find.byKey(const Key('badge_more')), findsNothing);
      expect(find.byType(StoreBadgeChip), findsNothing);
    });

    testWidgets('펼치면 전체 배지 목록', (tester) async {
      await _pump(tester, _card(badges: _badges(7), expanded: true));
      expect(find.text('전체 배지'), findsOneWidget);
      for (var i = 0; i < 7; i++) {
        expect(find.text('배지$i'), findsWidgets);
      }
    });
  });

  group('레이아웃 (좁은 화면 오버플로 없음)', () {
    final longStore = _store(
      name: '아주아주긴이름의복권판매점로또명당행운가득대박기원본점지점이름이정말로깁니다',
      address: '경기도 남양주시 화도읍 마석우리 아주 긴 도로명 주소 1234-56 상가동 1층 101호 (마석역 3번 출구 앞) 추가 설명 문구',
      rankStatus: 'up',
      rankChange: 12,
    );
    for (final width in [320.0, 340.0, 360.0, 411.0]) {
      testWidgets('긴 이름·주소 + 연구 점수 + 배지 · ${width.toInt()}dp', (tester) async {
        await _pump(
          tester,
          _card(
            rank: 1,
            store: longStore,
            extras: const RankingStoreExtras(
                agentScore: _score, gapMean: 123.4, cycleRoundsSinceLast: 15, hypothesisCount: 1234),
            badges: _badges(9),
            highlight: [StoreBadge('이번 달 3회 당첨 연속 당첨 명당 아주 긴 배지 이름', StoreBadgeType.streak)],
          ),
          width: width,
        );
        expect(tester.takeException(), isNull);
        final name = tester.widget<Text>(find.byKey(const Key('ranking_store_name')));
        expect(name.maxLines, 2);
        expect(name.overflow, TextOverflow.ellipsis);
        final addr = tester.widget<Text>(find.byKey(const Key('ranking_store_address')));
        expect(addr.maxLines, 2);
        expect(addr.overflow, TextOverflow.ellipsis);
      });
    }

    testWidgets('펼친 상태도 320dp 오버플로 없음', (tester) async {
      await _pump(
        tester,
        _card(
          rank: 2,
          store: longStore,
          extras: const RankingStoreExtras(agentScore: _score, gapMean: 40, cycleTrainingEnd: 1190),
          badges: _badges(6),
          expanded: true,
          expandedChild: const Text('기존 상세'),
        ),
        width: 320,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ranking_card_expanded')), findsOneWidget);
      expect(find.text('기존 상세'), findsOneWidget);
    });
  });

  group('하단 통계 바 · 동작', () {
    testWidgets('데이터 없으면 "-" / "기록 없음"', (tester) async {
      await _pump(tester, _card(store: _store(first: 0, second: 0, latestFirst: null, latestSecond: null)));
      expect(find.text('기록 없음'), findsNWidgets(2)); // 최근 당첨 · 마지막 이후
      expect(find.text('-'), findsNWidgets(2)); // 평균 간격 · 주요 가설
    });

    testWidgets('최근 당첨 · 평균 간격 · 마지막 이후 · 주요 가설', (tester) async {
      await _pump(
        tester,
        _card(extras: const RankingStoreExtras(gapMean: 41.6, cycleRoundsSinceLast: 7, hypothesisCount: 3)),
      );
      expect(find.text('1190회 2등'), findsOneWidget);
      expect(find.text('42회'), findsOneWidget);
      expect(find.text('20회'), findsOneWidget); // 1200 - 1180 (최신 회차 기준 직접 계산)
      expect(find.text('3건'), findsOneWidget);
    });

    test('latestWin: 같은 회차면 1등', () {
      final d = RankingCardData.fromStore(1, _store(latestFirst: 1190, latestSecond: 1190));
      expect(d.latestWin, (1190, '1등'));
    });

    test('roundsSinceLastFirst: 최신 회차 모르면 주기 연구 값', () {
      final d = RankingCardData.fromStore(1, _store(latestFirst: null));
      expect(d.roundsSinceLastFirst(1200, const RankingStoreExtras(cycleRoundsSinceLast: 9)), 9);
      expect(d.roundsSinceLastFirst(1200, null), isNull);
    });

    testWidgets('카드 탭 → onTap, 별 탭 → onFavoriteTap', (tester) async {
      var taps = 0, favs = 0;
      await _pump(tester, _card(onTap: () => taps++, onFav: () => favs++));
      await tester.tap(find.byKey(const Key('favorite_star')));
      expect(favs, 1);
      expect(taps, 0);
      await tester.tap(find.byKey(const Key('ranking_store_name')));
      expect(taps, 1);
    });
  });

  test('countHypothesesByStore: 판매점별 고유 가설 수', () {
    final rows = [
      {'hypothesis_id': 'h1', 'related_stores': ['a', 'b']},
      {'hypothesis_id': 'h2', 'related_stores': ['a']},
      {'hypothesis_id': 'h1', 'related_stores': ['a']}, // 중복
      {'hypothesis_id': 'h3', 'related_stores': ['z']}, // 요청 밖
      {'hypothesis_id': 'h4', 'related_stores': null},
    ];
    expect(RankingExtrasService.countHypothesesByStore(rows, ['a', 'b', 'c']), {'a': 2, 'b': 1, 'c': 0});
  });
}
