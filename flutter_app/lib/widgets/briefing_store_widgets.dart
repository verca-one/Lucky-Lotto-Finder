// 엔진 브리핑 ④ 이번 주 엔진 추천 명당 — 당첨 이력 패널 · 즐겨찾기(일반 모드와 같은 목록)
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lottery_store.dart';
import '../screens/favorites_screen.dart';
import '../services/favorites_notifier.dart';
import '../services/research/store_hit_ranking.dart';
import '../services/route/region_research_repository.dart' show StoreWinHistory;
import '../services/supabase_service.dart';

const _gold = Color(0xFFC77700);
const _silver = Color(0xFF607D8B);
const _star = Color(0xFFFFB300);

/// 일반 모드 즐겨찾기와 같은 저장소 (SharedPreferences 'favorite_stores' = 동행복권 판매점 코드)
class BriefingFavorites {
  static const key = 'favorite_stores';

  static Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? []).toSet();
  }

  /// 토글 후 새 상태(즐겨찾기 여부) 반환 · 일반 모드 화면에도 알림
  static Future<bool> toggle(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(key) ?? []).toSet();
    final added = !set.contains(code);
    added ? set.add(code) : set.remove(code);
    await prefs.setStringList(key, set.toList());
    notifyFavoritesChanged();
    return added;
  }

  /// 판매점 정보 조회 (테스트에서 교체)
  static Future<List<LotteryStore>> Function(List<String> codes) fetchStores = SupabaseService.getStoresByCodes;
}

/// 판매점 당첨 이력 — 1등·2등 횟수 배지 · 최근 1등 회차 · 1등 회차 목록 · 구매 방식
class StoreWinHistoryPanel extends StatelessWidget {
  final StoreWinHistory history;
  final int firstCount, secondCount;

  /// 최근 추첨 회차 (몇 회 전인지 계산용)
  final int? latestRound;
  const StoreWinHistoryPanel(
      {super.key, required this.history, required this.firstCount, required this.secondCount, this.latestRound});

  static const _maxChips = 8;

  @override
  Widget build(BuildContext context) {
    final rounds = history.firstRounds;
    final last = rounds.isEmpty ? null : rounds.first;
    final ago = last != null && latestRound != null ? latestRound! - last : null;
    final pm = history.purchaseMethods.entries.where((e) => e.value > 0 && e.key != '미상').toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      key: const ValueKey('store_win_history'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.emoji_events_rounded, size: 16, color: _gold),
          const SizedBox(width: 4),
          const Text('당첨 이력', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _gold)),
          const Spacer(),
          if (last != null)
            Text('최근 1등 $last회${ago == null ? '' : (ago <= 0 ? ' (지난 회차)' : ' ($ago회 전)')}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF5D4037))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _tier('1등', firstCount, _gold)),
          const SizedBox(width: 8),
          Expanded(child: _tier('2등', secondCount, _silver)),
        ]),
        if (rounds.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('1등 회차', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.brown.shade700)),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final r in rounds.take(_maxChips)) _roundChip(r, recent: latestRound != null && latestRound! - r < 52),
            if (rounds.length > _maxChips)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('외 ${rounds.length - _maxChips}회',
                    style: TextStyle(fontSize: 10.5, color: Colors.brown.shade600, fontWeight: FontWeight.w700)),
              ),
          ]),
        ],
        if (pm.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('당첨 구매 방식: ${pm.map((e) => '${e.key} ${e.value}').join(' · ')}',
              style: TextStyle(fontSize: 10.5, color: Colors.brown.shade700)),
        ],
      ]),
    );
  }

  Widget _tier(String label, int n, Color c) => Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: n > 0 ? c.withValues(alpha: 0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: n > 0 ? c : Colors.grey)),
          const SizedBox(width: 6),
          Text('$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: n > 0 ? c : Colors.grey)),
          Text('회', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: n > 0 ? c : Colors.grey)),
        ]),
      );

  Widget _roundChip(int r, {required bool recent}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: recent ? _gold : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withValues(alpha: recent ? 1 : 0.4)),
        ),
        child: Text('$r회',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: recent ? Colors.white : const Color(0xFF5D4037))),
      );
}

/// 즐겨찾기 별 — 누르면 일반 모드 즐겨찾기에 추가/해제
class FavoriteStoreStar extends StatefulWidget {
  final String code;
  final String name;
  const FavoriteStoreStar({super.key, required this.code, required this.name});
  @override
  State<FavoriteStoreStar> createState() => _FavoriteStoreStarState();
}

class _FavoriteStoreStarState extends State<FavoriteStoreStar> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    _sync();
    favoritesNotifier.addListener(_sync);
  }

  @override
  void dispose() {
    favoritesNotifier.removeListener(_sync);
    super.dispose();
  }

  Future<void> _sync() async {
    final s = await BriefingFavorites.load();
    if (mounted) setState(() => _on = s.contains(widget.code));
  }

  Future<void> _toggle() async {
    final added = await BriefingFavorites.toggle(widget.code);
    if (!mounted) return;
    setState(() => _on = added);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(added ? '${widget.name} — 즐겨찾기에 추가했습니다' : '${widget.name} — 즐겨찾기에서 뺐습니다')));
  }

  @override
  Widget build(BuildContext context) => IconButton(
        key: ValueKey('fav_star_${widget.code}'),
        tooltip: _on ? '즐겨찾기 해제' : '즐겨찾기 추가',
        visualDensity: VisualDensity.compact,
        onPressed: _toggle,
        icon: Icon(_on ? Icons.star_rounded : Icons.star_outline_rounded, color: _on ? _star : Colors.grey, size: 26),
      );
}

/// 내 즐겨찾기 판매점 — 일반 모드에서 ★ 누른 판매점 (이번 주 추천 명당이면 표시)
class BriefingFavoriteStores extends StatefulWidget {
  /// 이번 주 추천 명당 코드
  final Set<String> pickCodes;
  const BriefingFavoriteStores({super.key, this.pickCodes = const {}});
  @override
  State<BriefingFavoriteStores> createState() => _BriefingFavoriteStoresState();
}

class _BriefingFavoriteStoresState extends State<BriefingFavoriteStores> {
  List<LotteryStore>? _stores;
  bool _expanded = false;
  static const _preview = 5;

  @override
  void initState() {
    super.initState();
    _load();
    favoritesNotifier.addListener(_load);
  }

  @override
  void dispose() {
    favoritesNotifier.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final codes = await BriefingFavorites.load();
    final list = codes.isEmpty ? <LotteryStore>[] : await BriefingFavorites.fetchStores(codes.toList());
    final seen = <String>{};
    final uniq = list.where((s) => codes.contains(s.dhlotteryCode) && seen.add(s.dhlotteryCode)).toList()
      ..sort((a, b) {
        final pa = widget.pickCodes.contains(a.dhlotteryCode) ? 0 : 1, pb = widget.pickCodes.contains(b.dhlotteryCode) ? 0 : 1;
        if (pa != pb) return pa.compareTo(pb);
        final f = (b.firstCount ?? 0).compareTo(a.firstCount ?? 0);
        return f != 0 ? f : (b.secondCount ?? 0).compareTo(a.secondCount ?? 0);
      });
    if (mounted) setState(() => _stores = uniq);
  }

  @override
  Widget build(BuildContext context) {
    final s = _stores;
    final inPicks = s?.where((x) => widget.pickCodes.contains(x.dhlotteryCode)).length ?? 0;
    final shown = s == null ? const <LotteryStore>[] : (_expanded ? s : s.take(_preview).toList());
    return Container(
      key: const ValueKey('briefing_favorites'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDE7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _star.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.star_rounded, color: _star, size: 20),
          const SizedBox(width: 4),
          Text('내 즐겨찾기 판매점${s == null ? '' : ' ${s.length}곳'}',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)),
          const Spacer(),
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => Scaffold(appBar: AppBar(title: const Text('즐겨찾기 판매점')), body: const FavoritesScreen()),
            )),
            child: const Text('전체 화면', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ]),
        Text(
            inPicks > 0
                ? '일반 모드 즐겨찾기와 같은 목록 · 이번 주 추천 명당과 겹치는 곳 $inPicks곳'
                : '일반 모드 즐겨찾기와 같은 목록 · 위 추천 명당의 ★로도 추가할 수 있습니다',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        if (s == null)
          const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
        else if (s.isEmpty)
          Text('아직 즐겨찾기한 판매점이 없습니다. 일반 모드나 위 추천 명당에서 ★를 누르면 여기에 모입니다.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700))
        else ...[
          for (final x in shown) _row(x),
          if (s.length > _preview)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '접기' : '${s.length - _preview}곳 더 보기', style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _row(LotteryStore x) {
    final pick = widget.pickCodes.contains(x.dhlotteryCode);
    final f = x.firstCount ?? 0, sc = x.secondCount ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: pick ? const Color(0xFFE65100) : Colors.grey.shade300, width: pick ? 1.4 : 1),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(x.storeName, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              if (pick)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFE65100), borderRadius: BorderRadius.circular(8)),
                  child: const Text('이번 주 추천', style: TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w800)),
                ),
            ]),
            Text(x.address, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ]),
        ),
        const SizedBox(width: 6),
        _count('1등', f, _gold),
        const SizedBox(width: 4),
        _count('2등', sc, _silver),
        FavoriteStoreStar(code: x.dhlotteryCode, name: x.storeName),
      ]),
    );
  }

  Widget _count(String label, int n, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: n > 0 ? c.withValues(alpha: 0.12) : Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
        child: Text('$label $n', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: n > 0 ? c : Colors.grey)),
      );
}

String pct(double p) => '${(p * 100).toStringAsFixed(p >= 0.01 ? 2 : 3)}%';

/// 추천 명당 한 곳의 적중 예측 줄 — 지방장 1등 추정 확률 × 검증 가설 배수
class StoreHitLine extends StatelessWidget {
  final double? pFirst;
  final double factor;
  final List<StoreHitHypothesis> hypotheses;
  const StoreHitLine({super.key, required this.pFirst, this.factor = 1, this.hypotheses = const []});

  @override
  Widget build(BuildContext context) {
    if (pFirst == null) return const SizedBox.shrink();
    final adj = pFirst! * factor;
    return Container(
      key: const ValueKey('store_hit_line'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.trending_up_rounded, size: 16, color: Color(0xFF2E7D32)),
          const SizedBox(width: 4),
          const Text('다음 회차 1등 예측', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF2E7D32))),
          const Spacer(),
          Text(pct(adj), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1B5E20))),
        ]),
        Text(
            factor > 1
                ? '지방장 추정 ${pct(pFirst!)} × 검증 가설 ×${factor.toStringAsFixed(2)}'
                : '지방장 추정 ${pct(pFirst!)} · 맞는 검증 가설 없음',
            style: TextStyle(fontSize: 10.5, color: Colors.green.shade900)),
        for (final h in hypotheses.take(2))
          Text('· ${h.label} (${h.outcomeLabel} 실제÷기대 ×${h.factor.toStringAsFixed(2)})',
              style: TextStyle(fontSize: 10, color: Colors.green.shade800)),
      ]),
    );
  }
}

/// 전국 판매점 적중 예측 높은 순 (hs-apply) — 지방장 1등 추정 확률 × 검증 통과 판매점 가설 배수
class StoreHitRankingCard extends StatefulWidget {
  final StoreHitRanking? ranking;
  final int targetRound;

  /// 이번 주 추천 명당 코드 (목록에 표시)
  final Set<String> pickCodes;
  const StoreHitRankingCard({super.key, required this.ranking, required this.targetRound, this.pickCodes = const {}});
  @override
  State<StoreHitRankingCard> createState() => _StoreHitRankingCardState();
}

class _StoreHitRankingCardState extends State<StoreHitRankingCard> {
  bool _all = false;
  bool _online = false;
  static const _preview = 20;
  static const _green = Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    final r = widget.ranking;
    final box = BoxDecoration(
      color: const Color(0xFFF1F8E9),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF558B2F).withValues(alpha: 0.4)),
    );
    if (r == null || r.targetRound != widget.targetRound || r.ranking.isEmpty) {
      return Container(
        key: const ValueKey('store_hit_ranking_empty'),
        width: double.infinity, padding: const EdgeInsets.all(12), decoration: box,
        child: Text('${widget.targetRound}회 적중 예측 순위는 서버 계산 후 표시됩니다 (가설 공장 실행 뒤 · 매일 17시).',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
      );
    }
    final list = r.ranking.where((e) => _online || !e.isOnline).toList();
    final shown = _all ? list : list.take(_preview).toList();
    final moved = r.ranking.where((e) => e.rank != e.baseRank).length;
    return Container(
      key: const ValueKey('store_hit_ranking'),
      width: double.infinity, padding: const EdgeInsets.all(12), decoration: box,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.leaderboard_rounded, color: _green, size: 20),
          const SizedBox(width: 4),
          Expanded(child: Text('적중 예측 높은 순 — ${r.targetRound}회 전국',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: _green))),
        ]),
        const SizedBox(height: 2),
        Text('지방장 1등 추정 확률 × 검증 통과 판매점 가설 배수(여러 개면 가장 큰 것) · ${r.storesScored}곳 계산 · '
            '가설 반영으로 순위가 바뀐 곳 $moved곳 (상위 ${r.ranking.length}곳 중)',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800)),
        const SizedBox(height: 6),
        _hypBox(r),
        const SizedBox(height: 8),
        Row(children: [
          Text('순위', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.grey.shade700)),
          const Spacer(),
          FilterChip(
            key: const ValueKey('hit_online_filter'),
            label: const Text('인터넷 판매 포함', style: TextStyle(fontSize: 10.5)),
            selected: _online, visualDensity: VisualDensity.compact,
            onSelected: (v) => setState(() => _online = v),
          ),
        ]),
        for (final e in shown) _row(e),
        if (list.length > _preview)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _all = !_all),
              child: Text(_all ? '접기' : '${list.length - _preview}곳 더 보기', style: const TextStyle(fontSize: 12)),
            ),
          ),
        Text('확률은 지방장 모델 추정값입니다. 판매점별 판매량 자료가 없어, 많이 파는 가게일수록 높게 나옵니다. '
            '이 가게에서 산 복권 한 장의 1등 확률(1/8,145,060)은 어디서 사도 같습니다.',
            style: TextStyle(fontSize: 10, height: 1.4, color: Colors.grey.shade700)),
      ]),
    );
  }

  Widget _hypBox(StoreHitRanking r) {
    if (r.hypotheses.isEmpty) {
      return Text('반영된 검증 가설 없음 — 지방장 확률 그대로 순위', style: TextStyle(fontSize: 11, color: Colors.grey.shade700));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('반영한 검증 가설 ${r.hypotheses.length}개 (가설 공장 · 확인 구간 1001회~ 실제÷기대)',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        for (final h in r.hypotheses)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('×${h.factor.toStringAsFixed(2)}  ${h.label} → ${h.outcomeLabel} · 지금 해당 ${h.storesNow}곳'
                '${h.simHyp != null && h.simBase != null ? ' · 과거 모의 적중 ${h.simHyp} vs ${h.simBase}' : ''}',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800)),
          ),
        const SizedBox(height: 3),
        Text(
            r.simRaisedCount > 0
                ? '과거 모의에서 적중이 오른 가설 ${r.simRaisedCount}개'
                : '과거 모의(시·군·구 TOP5)에서는 이 가설들로 1등 적중이 늘지 않았습니다 — 유명 명당은 이미 이력 점수로 상위라 순위 변화가 적습니다.',
            style: TextStyle(fontSize: 10, color: r.simRaisedCount > 0 ? Colors.green.shade800 : Colors.brown.shade600)),
      ]),
    );
  }

  Widget _row(StoreHitEntry e) {
    final pick = widget.pickCodes.contains(e.code);
    final up = e.baseRank - e.rank;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: pick ? const Color(0xFFE65100) : Colors.grey.shade300, width: pick ? 1.4 : 1),
      ),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: Text('${e.rank}', textAlign: TextAlign.center,
              style: TextStyle(fontSize: e.rank <= 3 ? 16 : 13.5, fontWeight: FontWeight.w900,
                  color: e.rank <= 3 ? _gold : Colors.grey.shade800)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 4, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(e.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              if (pick) _tag('이번 주 추천', const Color(0xFFE65100)),
              if (e.boosted) _tag('가설 ×${e.factor.toStringAsFixed(2)}', const Color(0xFF2E7D32)),
              if (up != 0) _tag(up > 0 ? '▲$up' : '▼${-up}', up > 0 ? const Color(0xFF1565C0) : Colors.grey),
            ]),
            Text('${e.region.isEmpty ? e.address : e.region} · 1등 ${e.first} · 2등 ${e.second}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(pct(e.pAdj), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: _green)),
          if (e.boosted) Text('기본 ${pct(e.pFirst)}', style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600)),
        ]),
        FavoriteStoreStar(code: e.code, name: e.name),
      ]),
    );
  }

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w800)),
      );
}
