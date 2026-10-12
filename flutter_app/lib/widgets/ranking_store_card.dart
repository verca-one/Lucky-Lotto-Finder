// 홈 랭킹 판매점 카드 (랭킹 TOP N)
//
// * 순위 테마: 1위 금 · 2위 은 · 3위 동 (금속 테두리 + 옅은 배경), 4위 이하 기본
// * 순위 메달(왼쪽 위): 1위 금+왕관 · 2위 은 · 3위 동 · 4위 이하 일반 순위 배지
// * 순위 변동(▲/▼/NEW): lottery_stores.rank_status / rank_change 가 있을 때만 표시
// * 사진: 데이터에 실제 이미지 URL 이 있을 때만 표시. 현재 lottery_stores 에는 이미지 필드가 없으므로
//   항상 복권판매점 아이콘 자리표시를 보여 준다 (다른 판매점·스톡 사진을 쓰지 않는다).
// * 지방장 연구 점수 칸: 실제 점수가 있을 때만 표시. 복권 한 장당 당첨확률이 아니다.
// * 배지: BadgeService(store_badges) 결과만 사용. 최대 [RankingStoreCard.maxBadges]개 + '+N'.
//
// 이 위젯은 네트워크를 호출하지 않는다. 모든 데이터는 화면(목록)에서 일괄 조회해 넘긴다.
import 'package:flutter/material.dart';

import '../models/lottery_store.dart';
import '../services/badge_service.dart';
import '../services/ranking_extras_service.dart';
import '../services/research/agent_research_repository.dart' show AgentStoreScore, agentLabel;
import '../services/route/region_research_repository.dart' show RegionIds;

// ═══════════════════════════════════════════════════════════════════════
// 데이터 (순수 로직, 단위 테스트 대상)
// ═══════════════════════════════════════════════════════════════════════

enum RankTier { gold, silver, bronze, plain }

RankTier rankTierOf(int rank) => switch (rank) {
      1 => RankTier.gold,
      2 => RankTier.silver,
      3 => RankTier.bronze,
      _ => RankTier.plain,
    };

enum RankMove { up, down, same, isNew }

/// 순위 변동 (DB 값 그대로). 데이터가 없으면 [RankChangeInfo.fromData] 가 null.
class RankChangeInfo {
  final RankMove move;
  final int amount;
  const RankChangeInfo(this.move, this.amount);

  /// rank_status('up'|'down'|'same'|'new') / rank_change(양수=상승, 음수=하락).
  /// 둘 다 없으면 null (표시하지 않는다).
  static RankChangeInfo? fromData(String? status, int? change) {
    final s = status?.trim().toLowerCase();
    if ((s == null || s.isEmpty) && change == null) return null;
    if (s == 'new') return const RankChangeInfo(RankMove.isNew, 0);
    final c = change ?? 0;
    if (s == 'up' || (s != 'down' && c > 0)) return RankChangeInfo(RankMove.up, c.abs());
    if (s == 'down' || c < 0) return RankChangeInfo(RankMove.down, c.abs());
    return const RankChangeInfo(RankMove.same, 0);
  }
}

/// 카드 한 장의 표시 데이터 (lottery_stores 행 + 연금복권 집계)
class RankingCardData {
  final int rank;
  final String code;
  final String name;
  final String address;
  final String region;
  final int firstCount;
  final int secondCount;
  final int? latestFirstWin;
  final int? latestSecondWin;
  final RankChangeInfo? rankChange;
  final int pensionFirst;
  final int pensionSecond;

  /// 실제 판매점 이미지 URL. 현재 데이터 모델에 이미지 필드가 없어 항상 null.
  final String? photoUrl;

  const RankingCardData({
    required this.rank,
    required this.code,
    required this.name,
    required this.address,
    required this.region,
    this.firstCount = 0,
    this.secondCount = 0,
    this.latestFirstWin,
    this.latestSecondWin,
    this.rankChange,
    this.pensionFirst = 0,
    this.pensionSecond = 0,
    this.photoUrl,
  });

  factory RankingCardData.fromStore(int rank, Map<String, dynamic> s, {Map<String, dynamic>? pension}) =>
      RankingCardData(
        rank: rank,
        code: (s['dhlottery_code'] ?? '').toString(),
        name: (s['store_name'] ?? '').toString(),
        address: (s['address'] ?? '').toString(),
        region: (s['region'] ?? '').toString(),
        firstCount: _i(s['first_count']) ?? 0,
        secondCount: _i(s['second_count']) ?? 0,
        latestFirstWin: _pos(_i(s['latest_first_win'])),
        latestSecondWin: _pos(_i(s['latest_second_win'])),
        rankChange: RankChangeInfo.fromData(s['rank_status']?.toString(), _i(s['rank_change'])),
        pensionFirst: _i(pension?['first_count']) ?? 0,
        pensionSecond: _i(pension?['second_count']) ?? 0,
      );

  /// 주변·지역 목록의 LotteryStore → 카드 데이터. rank 0 = 순위 없는 목록(메달·순위 테마 없음)
  factory RankingCardData.fromLotteryStore(LotteryStore s, {int rank = 0}) {
    int? latest(int? v, List<int>? wins) {
      if (v != null && v > 0) return v;
      final w = (wins ?? const <int>[]).where((x) => x > 0);
      return w.isEmpty ? null : w.reduce((a, b) => a > b ? a : b);
    }
    return RankingCardData(
      rank: rank,
      code: s.dhlotteryCode,
      name: s.storeName,
      address: s.address,
      region: s.region,
      firstCount: s.firstCount ?? 0,
      secondCount: s.secondCount ?? 0,
      latestFirstWin: latest(s.latestFirstWin, s.firstWins),
      latestSecondWin: latest(s.latestSecondWin, s.secondWins),
      rankChange: RankChangeInfo.fromData(s.rankStatus, s.rankChange),
    );
  }

  RankTier get tier => rankTierOf(rank);

  /// 최근 당첨 (회차, '1등'/'2등'). 같은 회차면 1등. 없으면 null.
  (int, String)? get latestWin {
    final f = latestFirstWin, s = latestSecondWin;
    if (f == null && s == null) return null;
    if (s == null || (f != null && f >= s)) return (f!, '1등');
    return (s, '2등');
  }

  /// 마지막 1등 이후 회차 수.
  /// 최신 회차와 latest_first_win 이 있으면 직접 계산, 없으면 주기 연구(rounds_since_last) 값. 둘 다 없으면 null.
  int? roundsSinceLastFirst(int latestRound, RankingStoreExtras? x) {
    final f = latestFirstWin;
    if (f != null && latestRound > 0 && latestRound >= f) return latestRound - f;
    return x?.cycleRoundsSinceLast;
  }

  static int? _i(dynamic v) => v is num ? v.toInt() : (v == null ? null : int.tryParse('$v'));
  static int? _pos(int? v) => v == null || v <= 0 ? null : v;
}

/// 지방장 표시 이름 ('서울|노원구' → '노원구', 'internet' → '인터넷 판매')
String agentUnitLabel(String agentId) =>
    agentId == 'internet' ? agentLabel(agentId) : (agentId.isEmpty ? '-' : RegionIds.unitOf(agentId));

/// 연구 점수 칸 문구 ('노원구 1/88위')
String researchRankText(AgentStoreScore s) =>
    '${agentUnitLabel(s.agentId)} ${s.agentRank > 0 ? s.agentRank : '-'}/${s.agentSize > 0 ? s.agentSize : '-'}위';

// ═══════════════════════════════════════════════════════════════════════
// 테마
// ═══════════════════════════════════════════════════════════════════════

class _RankTheme {
  final Color border;
  final List<Color>? background;
  final List<Color> medal;
  final Color medalText;
  final Color shadow;
  const _RankTheme({
    required this.border,
    required this.background,
    required this.medal,
    required this.medalText,
    required this.shadow,
  });

  static _RankTheme of(RankTier t) => switch (t) {
        RankTier.gold => const _RankTheme(
            border: Color(0xFFE2B33C),
            background: [Color(0xFFFFFDF5), Color(0xFFFFF5D9)],
            medal: [Color(0xFFFFE885), Color(0xFFF5C518), Color(0xFFC99A06)],
            medalText: Color(0xFF5C4300),
            shadow: Color(0x33E2B33C),
          ),
        RankTier.silver => const _RankTheme(
            border: Color(0xFFB4BCC6),
            background: [Color(0xFFFDFDFE), Color(0xFFEFF2F5)],
            medal: [Color(0xFFF7F9FB), Color(0xFFC9D0D8), Color(0xFF959FAA)],
            medalText: Color(0xFF3B4450),
            shadow: Color(0x2E8C96A3),
          ),
        RankTier.bronze => const _RankTheme(
            border: Color(0xFFD39B6B),
            background: [Color(0xFFFFFBF7), Color(0xFFFBEDE1)],
            medal: [Color(0xFFF7CFA7), Color(0xFFD08A4F), Color(0xFFA2602A)],
            medalText: Colors.white,
            shadow: Color(0x2ECD7F32),
          ),
        RankTier.plain => const _RankTheme(
            border: Color(0xFFE6E9EE),
            background: null,
            medal: [Color(0xFFF1F3F6), Color(0xFFE4E8ED)],
            medalText: Color(0xFF475263),
            shadow: Color(0x0F000000),
          ),
      };
}

const Color _ink = Color(0xFF1A1F2C);
const Color _muted = Color(0xFF6B7380);
const Color _faint = Color(0xFF9AA1AC);

// ═══════════════════════════════════════════════════════════════════════
// 카드
// ═══════════════════════════════════════════════════════════════════════

class RankingStoreCard extends StatelessWidget {
  final RankingCardData data;

  /// 일괄 조회한 부가 정보 (없으면 '-' / 연구 점수 칸 숨김)
  final RankingStoreExtras? extras;

  /// 배지 칩 줄에 표시할 배지 (연속 당첨 강조 배지 제외)
  final List<StoreBadge> badges;

  /// 지점명 아래 강조 칩 (연속 당첨 · 이번 달 N회 당첨 등 기존 계산 결과)
  final List<StoreBadge> highlightBadges;

  final bool isFavorite;
  final bool isExpanded;

  /// 최신 로또 회차 (0 = 모름)
  final int latestRound;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteTap;

  /// 사진 영역 위 작은 지도 버튼 (기존 지도 열기 함수). null 이면 버튼 없음.
  final VoidCallback? onMapTap;

  /// 강조 칩 반짝임 (기존 홈 애니메이션). null 이면 정적 표시.
  final Animation<double>? glow;

  /// 펼쳤을 때 아래에 붙는 기존 상세 영역 (지방장 연구 · 평가 · 지도 · 당첨 이력)
  final Widget? expandedChild;

  /// 엔진·지방장 연구 정보(연구 점수 칸, 주요 가설 칸) 표시 여부 — 관리자 모드 전용
  final bool showResearch;

  /// 순위 메달·금은동 테마 표시 (주변 목록처럼 순위가 아닌 목록은 false)
  final bool showMedal;

  /// 오른쪽(즐겨찾기 아래)에 크게 보일 표시. 예: 주변 목록의 거리. 없으면 순위 변동(▲▼)
  final Widget? trailing;

  /// 지역 칩 줄에 덧붙일 칩 (예: 전국 TOP 순위)
  final List<Widget> extraChips;

  /// 배지 줄 아래에 붙는 추가 영역
  final Widget? extraBody;

  /// 지도 마커 선택 등으로 강조
  final bool selected;

  static const int maxBadges = 4;

  const RankingStoreCard({
    super.key,
    required this.data,
    this.extras,
    this.badges = const [],
    this.highlightBadges = const [],
    this.isFavorite = false,
    this.isExpanded = false,
    this.latestRound = 0,
    this.onTap,
    this.onFavoriteTap,
    this.onMapTap,
    this.glow,
    this.expandedChild,
    this.showResearch = true,
    this.showMedal = true,
    this.trailing,
    this.extraChips = const [],
    this.extraBody,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final tier = showMedal ? data.tier : RankTier.plain;
    final theme = _RankTheme.of(tier);
    final plain = tier == RankTier.plain;
    final radius = BorderRadius.circular(18);
    final highlight = plain && (isExpanded || selected);

    return Container(
      decoration: BoxDecoration(
        color: plain ? Colors.white : null,
        gradient: plain
            ? null
            : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: theme.background!),
        borderRadius: radius,
        border: Border.all(
          color: highlight ? Colors.blue.shade200 : theme.border,
          width: plain ? (selected ? 1.5 : 1) : 1.6,
        ),
        boxShadow: [
          BoxShadow(color: theme.shadow, blurRadius: plain ? 8 : 14, offset: const Offset(0, 3)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, tier == RankTier.gold ? 18 : 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(theme),
                const SizedBox(height: 12),
                _StatTiles(data: data, score: showResearch ? extras?.agentScore : null),
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _BadgeRow(badges: badges, max: maxBadges),
                ],
                if (extraBody != null) ...[
                  const SizedBox(height: 10),
                  extraBody!,
                ],
                const SizedBox(height: 10),
                _BottomStatBar(data: data, extras: extras, latestRound: latestRound, showResearch: showResearch),
                _footer(),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: isExpanded ? _expanded() : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 상단: 메달 · 이름 · 주소 · 칩 | 즐겨찾기 · 순위 변동(크게) ──────────────
  Widget _header(_RankTheme theme) {
    final plain = data.tier == RankTier.plain;
    final medalSize = plain ? 38.0 : 44.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showMedal && data.rank > 0) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: RankMedal(rank: data.rank, size: medalSize),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  data.name,
                  key: const Key('ranking_store_name'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1.5),
                    child: Icon(Icons.place_outlined, size: 13, color: _faint),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      data.address,
                      key: const Key('ranking_store_address'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _muted, height: 1.35),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (data.region.isNotEmpty) _RegionChip(data.region),
                  ...extraChips,
                  for (final b in highlightBadges) _HighlightChip(badge: b, glow: glow),
                  if (data.pensionFirst > 0 || data.pensionSecond > 0)
                    _PensionChip(first: data.pensionFirst, second: data.pensionSecond),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // 오른쪽: 즐겨찾기 · 순위 오르고 내림(크게)
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _FavoriteButton(isFavorite: isFavorite, onTap: onFavoriteTap),
            if (trailing != null) ...[
              const SizedBox(height: 6),
              trailing!,
            ] else if (data.rankChange != null) ...[
              const SizedBox(height: 6),
              RankChangeTag(info: data.rankChange!, large: true),
            ],
          ],
        ),
      ],
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: latestRound > 0
                ? Text(
                    '$latestRound회 당첨적용',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: _faint),
                  )
                : const SizedBox.shrink(),
          ),
          Text(
            isExpanded ? '접기' : '상세 보기',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _muted),
          ),
          Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 18, color: _faint),
        ],
      ),
    );
  }

  Widget _expanded() {
    final all = [...highlightBadges, ...badges];
    final x = extras;
    final cycleParts = <String>[
      if (x?.gapMean != null) '1등 평균 간격 ${x!.gapMean!.toStringAsFixed(1)}회',
      if (x?.cycleRoundsSinceLast != null) '마지막 1등 이후 ${x!.cycleRoundsSinceLast}회',
    ];
    return Column(
      key: const Key('ranking_card_expanded'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Divider(height: 1, color: Colors.grey.shade200),
        if (all.isNotEmpty) ...[
          const SizedBox(height: 10),
          const _SectionTitle('전체 배지'),
          const SizedBox(height: 6),
          Wrap(spacing: 5, runSpacing: 5, children: [for (final b in all) StoreBadgeChip(badge: b)]),
        ],
        const SizedBox(height: 10),
        const _SectionTitle('주기 통계'),
        const SizedBox(height: 4),
        Text(
          cycleParts.isEmpty
              ? '주기 연구 데이터 없음'
              : '${cycleParts.join(' · ')}'
                  '${x?.cycleTrainingEnd != null ? ' (${x!.cycleTrainingEnd}회까지 기준)' : ''}',
          style: const TextStyle(fontSize: 12, color: _muted, height: 1.4),
        ),
        if (expandedChild != null) ...[
          const SizedBox(height: 4),
          expandedChild!,
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 하위 위젯
// ═══════════════════════════════════════════════════════════════════════

/// 원형 순위 메달. 1위 금+왕관, 2위 은, 3위 동, 4위 이하 일반 배지.
class RankMedal extends StatelessWidget {
  final int rank;
  final double size;
  const RankMedal({super.key, required this.rank, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final tier = rankTierOf(rank);
    final t = _RankTheme.of(tier);
    final plain = tier == RankTier.plain;
    final medal = Container(
      key: Key('rank_medal_${tier.name}'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: t.medal),
        border: Border.all(color: plain ? const Color(0xFFD5DAE1) : Colors.white, width: plain ? 1 : 2),
        boxShadow: [
          BoxShadow(
            color: plain ? const Color(0x14000000) : t.border.withValues(alpha: 0.45),
            blurRadius: plain ? 3 : 6,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: size * (rank >= 10 ? 0.38 : 0.44),
          fontWeight: FontWeight.w900,
          color: t.medalText,
          height: 1,
        ),
      ),
    );
    if (tier != RankTier.gold) return Semantics(label: '$rank위', child: medal);
    return Semantics(
      label: '$rank위',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            medal,
            Positioned(
              top: -size * 0.32,
              child: CustomPaint(
                key: const Key('rank_medal_crown'),
                size: Size(size * 0.6, size * 0.4),
                painter: const _CrownPainter(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrownPainter extends CustomPainter {
  const _CrownPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final path = Path()
      ..moveTo(0, h * 0.35)
      ..lineTo(w * 0.27, h * 0.62)
      ..lineTo(w * 0.5, h * 0.05)
      ..lineTo(w * 0.73, h * 0.62)
      ..lineTo(w, h * 0.35)
      ..lineTo(w * 0.88, h)
      ..lineTo(w * 0.12, h)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE885), Color(0xFFE0A800)],
        ).createShader(Offset.zero & s),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFB8860B),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 순위 변동 표시 (▲N / ▼N / NEW / −)
class RankChangeTag extends StatelessWidget {
  final RankChangeInfo info;
  final bool large;
  const RankChangeTag({super.key, required this.info, this.large = false});

  @override
  Widget build(BuildContext context) {
    final (String text, Color fg, Color bg) = switch (info.move) {
      RankMove.up => ('▲${info.amount}', const Color(0xFFD93025), const Color(0xFFFDECEA)),
      RankMove.down => ('▼${info.amount}', const Color(0xFF1A73E8), const Color(0xFFE8F0FE)),
      RankMove.isNew => ('NEW', const Color(0xFF188038), const Color(0xFFE6F4EA)),
      RankMove.same => ('−', _faint, const Color(0xFFF1F3F5)),
    };
    return Container(
      key: const Key('rank_change'),
      padding: large
          ? const EdgeInsets.symmetric(horizontal: 9, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(large ? 9 : 6)),
      child: Text(text,
          style: TextStyle(fontSize: large ? 17 : 10.5, fontWeight: FontWeight.w900, color: fg, height: 1.15)),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback? onTap;
  const _FavoriteButton({required this.isFavorite, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
      child: GestureDetector(
        key: const Key('favorite_star'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 36,
          child: Align(
            alignment: Alignment.topRight,
            child: Icon(
              isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 28,
              color: isFavorite ? const Color(0xFFFFB300) : const Color(0xFFC3C9D2),
            ),
          ),
        ),
      ),
    );
  }
}

class _RegionChip extends StatelessWidget {
  final String region;
  const _RegionChip(this.region);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(region, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _muted)),
    );
  }
}

class _PensionChip extends StatelessWidget {
  final int first;
  final int second;
  const _PensionChip({required this.first, required this.second});

  @override
  Widget build(BuildContext context) {
    final parts = [if (first > 0) '1등 $first', if (second > 0) '2등 $second'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
      child: Text(
        '연금 ${parts.join(' · ')}',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.green.shade700),
      ),
    );
  }
}

/// 연속 당첨 등 강조 칩 (기존 홈 반짝임 효과 유지, [glow] 없으면 정적)
class _HighlightChip extends StatelessWidget {
  final StoreBadge badge;
  final Animation<double>? glow;
  const _HighlightChip({required this.badge, this.glow});

  Widget _chip(double g) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            const Color(0xFFFF6D00).withValues(alpha: 0.12 + 0.1 * g),
            const Color(0xFFFFAB00).withValues(alpha: 0.12 + 0.1 * g),
          ]),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Color.lerp(const Color(0xFFFF8F00), const Color(0xFFFFD600), g)!.withValues(alpha: 0.8),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department, size: 12, color: Color(0xFFE53935)),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                badge.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFE65100)),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final a = glow;
    if (a == null) return _chip(0.5);
    return AnimatedBuilder(
      animation: a,
      builder: (context, _) {
        final t = (a.value * 2) % 1.0;
        final g = (0.4 + 0.6 * (0.5 + 0.5 * (t < 0.5 ? t * 2 : 2 - t * 2))).clamp(0.0, 1.0);
        return _chip(g);
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _ink));
}

// ── 통계 칸 (1등 · 2등 · 지방장 연구 점수) ────────────────────────────

class _StatTiles extends StatelessWidget {
  final RankingCardData data;
  final AgentStoreScore? score;
  const _StatTiles({required this.data, this.score});

  @override
  Widget build(BuildContext context) {
    final first = _StatTile(
      label: '1등',
      value: '${data.firstCount}회',
      caption: data.latestFirstWin != null ? '최근 ${data.latestFirstWin}회' : '최근 기록 없음',
      accent: const Color(0xFFC99A06),
      tint: const Color(0xFFFFF8E1),
    );
    final second = _StatTile(
      label: '2등',
      value: '${data.secondCount}회',
      caption: data.latestSecondWin != null ? '최근 ${data.latestSecondWin}회' : '최근 기록 없음',
      accent: const Color(0xFF7D8794),
      tint: const Color(0xFFF2F4F7),
    );
    final s = score;
    if (s == null) {
      return Row(children: [Expanded(child: first), const SizedBox(width: 8), Expanded(child: second)]);
    }
    final research = _ResearchTile(score: s);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 330) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [Expanded(child: first), const SizedBox(width: 8), Expanded(child: second)]),
            const SizedBox(height: 8),
            research,
          ],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 10, child: first),
            const SizedBox(width: 8),
            Expanded(flex: 10, child: second),
            const SizedBox(width: 8),
            Expanded(flex: 13, child: research),
          ],
        ),
      );
    });
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color accent;
  final Color tint;
  const _StatTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.accent,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent)),
          ]),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _ink, height: 1.2)),
          ),
          Text(caption,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: _muted)),
        ],
      ),
    );
  }
}

/// 지방장 연구 점수 칸 (실제 점수가 있을 때만 생성). 확률이 아니다.
class _ResearchTile extends StatelessWidget {
  final AgentStoreScore score;
  const _ResearchTile({required this.score});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF5B4FCF);
    return Container(
      key: const Key('research_score_tile'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EFFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCD7FA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(children: [
            Icon(Icons.insights_rounded, size: 12, color: accent),
            SizedBox(width: 4),
            Flexible(
              child: Text('지방장 연구 점수',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: accent)),
            ),
          ]),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(researchRankText(score),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _ink, height: 1.25)),
          ),
          Text(
            '점수 ${score.score.toStringAsFixed(4)} · 확률 아님',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: _muted),
          ),
        ],
      ),
    );
  }
}

// ── 배지 ───────────────────────────────────────────────────────────────

class _BadgeRow extends StatelessWidget {
  final List<StoreBadge> badges;
  final int max;
  const _BadgeRow({required this.badges, required this.max});

  @override
  Widget build(BuildContext context) {
    final shown = badges.take(max).toList();
    final rest = badges.length - shown.length;
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final b in shown) StoreBadgeChip(badge: b),
        if (rest > 0)
          Container(
            key: const Key('badge_more'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDDE2E8)),
            ),
            child: Text('+$rest',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _muted)),
          ),
      ],
    );
  }
}

/// store_badges 배지 칩 (색상은 기존 홈 배지와 동일 계열)
class StoreBadgeChip extends StatelessWidget {
  final StoreBadge badge;
  const StoreBadgeChip({super.key, required this.badge});

  static (Color, IconData) styleOf(StoreBadgeType t) => switch (t) {
        StoreBadgeType.hot => (Colors.red, Icons.monetization_on),
        StoreBadgeType.myeongdang => (Colors.amber.shade800, Icons.workspace_premium),
        StoreBadgeType.matjip => (Colors.deepOrange, Icons.local_fire_department),
        StoreBadgeType.first => (Colors.red.shade700, Icons.looks_one_rounded),
        StoreBadgeType.second => (Colors.orange, Icons.looks_two_rounded),
        StoreBadgeType.regional => (Colors.purple, Icons.place_rounded),
        StoreBadgeType.streak => (Colors.blue, Icons.bolt_rounded),
        StoreBadgeType.rank => (Colors.teal, Icons.leaderboard_rounded),
        StoreBadgeType.pattern => (Colors.grey.shade700, Icons.timeline_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final (color, icon) = styleOf(badge.type);
    final hot = badge.type == StoreBadgeType.hot;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: hot ? 0.15 : 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: hot ? 0.5 : 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              badge.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: color, fontWeight: hot ? FontWeight.w800 : FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 하단 통계 바 (최근 당첨 · 평균 간격 · 마지막 이후 · 주요 가설) ─────────

class _BottomStatBar extends StatelessWidget {
  final RankingCardData data;
  final RankingStoreExtras? extras;
  final int latestRound;
  const _BottomStatBar({required this.data, this.extras, required this.latestRound, this.showResearch = true});
  final bool showResearch;

  @override
  Widget build(BuildContext context) {
    final win = data.latestWin;
    final gap = extras?.gapMean;
    final since = data.roundsSinceLastFirst(latestRound, extras);
    final hyp = extras?.hypothesisCount;
    final noFirst = data.firstCount <= 0 && data.latestFirstWin == null;
    final cells = [
      _BarCell(icon: Icons.emoji_events_outlined, label: '최근 당첨', value: win == null ? '기록 없음' : '${win.$1}회 ${win.$2}'),
      _BarCell(icon: Icons.timelapse_rounded, label: '평균 간격', value: gap == null ? '-' : '${gap.toStringAsFixed(0)}회'),
      _BarCell(
          icon: Icons.history_rounded,
          label: '마지막 이후',
          value: since != null ? '$since회' : (noFirst ? '기록 없음' : '-')),
      if (showResearch)
        _BarCell(icon: Icons.lightbulb_outline_rounded, label: '주요 가설', value: hyp == null ? '-' : '$hyp건'),
    ];
    return Container(
      key: const Key('ranking_bottom_bar'),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) Container(width: 1, height: 26, color: const Color(0xFFE3E6EB)),
            Expanded(child: cells[i]),
          ],
        ],
      ),
    );
  }
}

class _BarCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _BarCell({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: _faint),
              const SizedBox(width: 2),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: _muted, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                maxLines: 1, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _ink)),
          ),
        ],
      ),
    );
  }
}


/// 배지를 강조 칩(연속 당첨·이번 달 N회 — 가장 높은 것 하나)과 일반 배지로 나눈다. 홈·주변·지역 공통.
(List<StoreBadge>, List<StoreBadge>) splitStoreBadges(List<StoreBadge> badges) {
  final streak = badges.where((b) => b.type == StoreBadgeType.streak).toList();
  final month = streak.where((b) => b.label.contains('이번 달')).toList();
  final otherStreak = streak.where((b) => !b.label.contains('이번 달')).toList();
  StoreBadge? topMonth;
  if (month.isNotEmpty) {
    int n(StoreBadge b) => int.tryParse(RegExp(r'(\d+)회').firstMatch(b.label)?.group(1) ?? '0') ?? 0;
    topMonth = month.reduce((a, b) => n(a) >= n(b) ? a : b);
  }
  return ([?topMonth, ...otherStreak], badges.where((b) => b.type != StoreBadgeType.streak).toList());
}

/// 주변 목록의 거리 표시 (오른쪽, 크게)
class DistanceTag extends StatelessWidget {
  final double km;
  const DistanceTag({super.key, required this.km});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('distance_tag'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.near_me_rounded, size: 14, color: Color(0xFF2E7D32)),
        const SizedBox(width: 3),
        Text(km < 1 ? '${(km * 1000).round()}m' : '${km.toStringAsFixed(km < 10 ? 2 : 1)}km',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF2E7D32), height: 1.15)),
      ]),
    );
  }
}
