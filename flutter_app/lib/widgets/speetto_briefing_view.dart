// 스피또 화면 — 관리자 엔진 브리핑 '스피또' 탭 · 일반 모드 복권연구 '스피또' 탭
//  ① 게임별(스피또2000 · 1000 · 500) 1등 판매점 (서버 sp-1.0 · ★ 즐겨찾기 저장)  ② 판매 중 게임 · 남은 1등 (출고율 · 남은 매수, 매일 수집)
// 서버 계산이 '데이터 정리 필요'(예전 크롤러가 차수마다 같은 목록을 저장)로 판정하면 판매점을 보여 주지 않는다.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'agent_extra_section.dart';
import 'briefing_store_widgets.dart' show FavoriteStoreStar;
import 'package:geolocator/geolocator.dart';
import '../models/lottery_store.dart';
import '../services/store_map_launcher.dart' show StoreMapTarget;
import '../services/supabase_service.dart';
import 'store_map_buttons.dart';

const kSpeettoColor = Color(0xFF00897B);

/// 3707543 → '371만'
String manWon(int n) => n >= 10000 ? '${(n / 10000).round()}만' : '$n';

String ymdOf(String? iso) => (iso ?? '').length >= 10 ? iso!.substring(0, 10) : (iso ?? '-');

/// 엔진 브리핑 맨 위 — 출고율 95% 이상 스피또 차수 (사진 · 판매 기간 · 남은 1등 · 1장당 1등 확률)
class SpeettoAlertCard extends StatefulWidget {
  final Future<SpeettoBriefing?> Function()? loader;
  const SpeettoAlertCard({super.key, this.loader});
  @override
  State<SpeettoAlertCard> createState() => _SpeettoAlertCardState();
}

class _SpeettoAlertCardState extends State<SpeettoAlertCard> {
  late final Future<SpeettoBriefing?> _f = () async {
    try {
      return await (widget.loader ?? SpeettoBriefing.loadAdmin)();
    } catch (_) {
      return null;
    }
  }();

  @override
  Widget build(BuildContext context) => FutureBuilder<SpeettoBriefing?>(
        future: _f,
        builder: (context, s) {
          final alerts = s.data?.alerts ?? const <SpeettoEdition>[];
          if (alerts.isEmpty) return const SizedBox.shrink();
          return Container(
            key: const ValueKey('speetto_alert'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFD84315), Color(0xFFFF7043)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.local_fire_department_rounded, color: Colors.white),
                const SizedBox(width: 6),
                Expanded(child: Text('스피또 출고율 95% 이상 — ${s.data?.statusDate ?? ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900))),
              ]),
              const SizedBox(height: 8),
              for (final e in alerts) _row(e),
              const Text('남은 1등이 아직 안 팔린 표에 있다고 보고 계산한 추정입니다. 이미 팔렸지만 찾아가지 않은 1등이 있으면 실제 확률은 더 낮습니다.',
                  style: TextStyle(color: Colors.white70, fontSize: 10, height: 1.4)),
            ]),
          );
        },
      );

  Widget _row(SpeettoEdition e) => Container(
        key: ValueKey('speetto_alert_${e.game}_${e.edition}'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 72, height: 72,
              child: e.image == null
                  ? Container(color: const Color(0xFFE0F2F1), child: const Icon(Icons.style_rounded, color: kSpeettoColor, size: 36))
                  : Image.network(e.image!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: const Color(0xFFE0F2F1),
                          child: const Icon(Icons.style_rounded, color: kSpeettoColor, size: 36))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${e.label} ${e.edition}회', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: e.recommend ? const Color(0xFF2E7D32) : Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(e.recommend ? '구매 추천' : '확률 낮아짐',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                ),
              ]),
              Text('판매 ${ymdOf(e.saleStart)} ~ ${ymdOf(e.saleEnd)} · 출고율 ${(e.shipRate ?? 0).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              const SizedBox(height: 3),
              Text('1등${e.prize1 == null ? '' : '(${e.prize1})'} ${e.rnk1Left ?? '-'}장 남음 / 전체 ${e.rnk1Total ?? '-'}장',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              if (e.soldRate != null)
                Text('추정 판매율 ${e.soldRate!.toStringAsFixed(1)}% · 안 팔린 표 약 ${manWon(e.unsoldTickets ?? 0)}장',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
              if (e.p1Now != null)
                Text('1장당 1등 1/${manWon(e.p1Now!)} (처음 1/${manWon(e.p1Start ?? 0)} · ${(e.boost ?? 0).toStringAsFixed(2)}배)',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800,
                        color: e.recommend ? const Color(0xFF2E7D32) : Colors.grey.shade700)),
            ]),
          ),
        ]),
      );
}

class SpeettoStore {
  final String code, name, region;
  final int first, second, lastEdition;
  const SpeettoStore(this.code, this.name, this.region, this.first, this.second, this.lastEdition);
  factory SpeettoStore.fromJson(Map<String, dynamic> j) => SpeettoStore('${j['store_code'] ?? ''}', '${j['name'] ?? ''}',
      '${j['region'] ?? ''}', (j['first'] as num?)?.toInt() ?? 0, (j['second'] as num?)?.toInt() ?? 0,
      (j['last_edition'] as num?)?.toInt() ?? 0);
}

class SpeettoGame {
  final String game, label, status;
  final int? latestEdition;
  final double? sameRatio;
  final String? note;
  final List<SpeettoStore> stores;
  const SpeettoGame(this.game, this.label, this.status, this.latestEdition, this.sameRatio, this.note, this.stores);
  factory SpeettoGame.fromJson(Map<String, dynamic> j) => SpeettoGame(
        '${j['game'] ?? ''}', '${j['label'] ?? ''}', '${j['status'] ?? ''}', (j['latest_edition'] as num?)?.toInt(),
        (j['same_ratio'] as num?)?.toDouble(), j['note'] as String?,
        [for (final s in (j['stores'] as List? ?? const [])) SpeettoStore.fromJson(Map<String, dynamic>.from(s as Map))],
      );
  bool get ok => status == 'ok';
}

/// 판매 중 차수 한 개의 판매 현황 (출고율 · 남은 매수)
class SpeettoEdition {
  final String game;
  final int edition;
  final double? shipRate, index;
  final int? rnk1Total, rnk1Left, rnk2Total, rnk2Left;
  final String? prize1, prize2, saleEnd, saleStart, image;

  /// 판매율 추정(%) · 발행 · 안 팔린 장수 · 1장당 1등 확률 분모(처음 · 지금) · 좋아진 배수
  final double? soldRate, boost;
  final int? totalTickets, unsoldTickets, p1Start, p1Now;

  /// 출고율 95% 이상 · 1등 남음 → 브리핑 맨 위
  final bool alert;
  const SpeettoEdition({required this.game, required this.edition, this.shipRate, this.index, this.rnk1Total, this.rnk1Left,
      this.rnk2Total, this.rnk2Left, this.prize1, this.prize2, this.saleEnd, this.saleStart, this.image, this.soldRate,
      this.boost, this.totalTickets, this.unsoldTickets, this.p1Start, this.p1Now, this.alert = false});

  /// 처음보다 1장당 1등 확률이 좋아졌으면 구매 추천
  bool get recommend => alert && (boost ?? 0) >= 1.0;

  /// 출고율 95% 이상 — 남은 1등 지수를 쓰지 않음
  bool get nearEnd => (shipRate ?? 0) >= 95;
  factory SpeettoEdition.fromJson(Map<String, dynamic> j) => SpeettoEdition(
        game: '${j['game'] ?? ''}', edition: (j['edition'] as num?)?.toInt() ?? 0,
        shipRate: (j['ship_rate'] as num?)?.toDouble(), index: (j['index'] as num?)?.toDouble(),
        rnk1Total: (j['rnk1_total'] as num?)?.toInt(), rnk1Left: (j['rnk1_left'] as num?)?.toInt(),
        rnk2Total: (j['rnk2_total'] as num?)?.toInt(), rnk2Left: (j['rnk2_left'] as num?)?.toInt(),
        prize1: j['prize1'] as String?, prize2: j['prize2'] as String?, saleEnd: j['sale_end'] as String?,
        saleStart: j['sale_start'] as String?, image: j['image'] as String?,
        soldRate: (j['sold_rate'] as num?)?.toDouble(), boost: (j['boost'] as num?)?.toDouble(),
        totalTickets: (j['total_tickets'] as num?)?.toInt(), unsoldTickets: (j['unsold_tickets'] as num?)?.toInt(),
        p1Start: (j['p1_start'] as num?)?.toInt(), p1Now: (j['p1_now'] as num?)?.toInt(), alert: j['alert'] == true,
      );
  String get label => {'SP500': '스피또500', 'SP1000': '스피또1000', 'SP2000': '스피또2000'}[game] ?? game;
}

class SpeettoBriefing {
  final List<SpeettoGame> games;
  final String disclaimer;

  /// 판매 현황 (가장 최근 수집일) — 남은 1등 지수 높은 순
  final List<SpeettoEdition> editions;

  /// 출고율 95% 이상 차수 (브리핑 맨 위)
  List<SpeettoEdition> get alerts => editions.where((e) => e.alert).toList();
  final String? statusDate, statusNote;
  const SpeettoBriefing(this.games, {this.disclaimer = '', this.editions = const [], this.statusDate, this.statusNote});
  factory SpeettoBriefing.fromPayload(Map<String, dynamic> p) {
    final st = p['status'] is Map ? Map<String, dynamic>.from(p['status']) : const <String, dynamic>{};
    return SpeettoBriefing(
      [for (final g in (p['games'] as List? ?? const [])) SpeettoGame.fromJson(Map<String, dynamic>.from(g as Map))],
      disclaimer: '${p['disclaimer'] ?? ''}',
      editions: [for (final e in (st['editions'] as List? ?? const [])) SpeettoEdition.fromJson(Map<String, dynamic>.from(e as Map))],
      statusDate: st['snap_date'] as String?, statusNote: st['note'] as String?,
    );
  }

  static Future<SpeettoBriefing?> loadAdmin() async {
    final rows = await Supabase.instance.client.from('research_results').select('payload')
        .eq('research_type', 'speetto_briefing').order('target_round', ascending: false).limit(1);
    if ((rows as List).isEmpty) return null;
    return SpeettoBriefing.fromPayload(Map<String, dynamic>.from(rows.first['payload'] as Map));
  }

  /// 공개 승인된 행만 읽힌다 (데이터 정리 필요 판정이면 공개 안 됨 → null)
  static Future<SpeettoBriefing?> loadPublic() async {
    final rows = await Supabase.instance.client.from('research_public_extra').select('payload')
        .eq('lottery', 'speetto').order('target_round', ascending: false).limit(1);
    if ((rows as List).isEmpty) return null;
    return SpeettoBriefing.fromPayload(Map<String, dynamic>.from(rows.first['payload'] as Map));
  }
}

class SpeettoBriefingView extends StatefulWidget {
  final bool admin;
  final Future<SpeettoBriefing?> Function()? loader;

  /// 지방장 영역 (테스트용)
  final Future<AgentExtraData?> Function()? agentLoader;
  const SpeettoBriefingView({super.key, this.admin = true, this.loader, this.agentLoader});
  @override
  State<SpeettoBriefingView> createState() => _SpeettoBriefingViewState();
}

class _SpeettoBriefingViewState extends State<SpeettoBriefingView> {
  late Future<SpeettoBriefing?> _f;
  Map<String, LotteryStore> _info = const {}; // 판매점 코드 → 주소 · 좌표 (지도 버튼용)

  @override
  void initState() {
    super.initState();
    _f = (widget.loader ?? (widget.admin ? SpeettoBriefing.loadAdmin : SpeettoBriefing.loadPublic))();
    _f.then((b) async {
      final codes = {for (final g in b?.games ?? const <SpeettoGame>[]) for (final s in g.stores) if (s.code.isNotEmpty) s.code};
      if (codes.isEmpty) return;
      final l = await SupabaseService.getStoresByCodes(codes.toList());
      if (mounted) setState(() => _info = {for (final s in l) s.dhlotteryCode: s});
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SpeettoBriefing?>(
      future: _f,
      builder: (context, snap) {
        final b = snap.connectionState == ConnectionState.done && !snap.hasError ? snap.data : null;
        return ListView(padding: const EdgeInsets.all(16), children: [
          _hero(),
          const SizedBox(height: 12),
          if (widget.admin) ...[
            SpeettoNearbyCard(games: b?.games ?? const [], info: _info, onMap: _showMap),
            const SizedBox(height: 12),
          ],
          if (snap.connectionState != ConnectionState.done)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else ...[
            _storesArea(b),
            const SizedBox(height: 12),
            _statusArea(b),
            if (widget.admin) ...[
              const SizedBox(height: 12),
              AgentExtraSection(lottery: 'speetto', color: kSpeettoColor, loader: widget.agentLoader),
              const SizedBox(height: 12),
              _area('3', '스피또 가설 트랙 — 제미나이', Text('판매점·판매 현황 데이터가 갖춰지면 제미나이 스피또 가설로 게임·판매점을 고릅니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.45))),
            ],
            const SizedBox(height: 12),
            Text(b?.disclaimer.isNotEmpty == true ? b!.disclaimer : '스피또 판매점 기록은 참고용입니다. 어느 판매점에서 사도 한 장의 당첨 확률은 같습니다.',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
          ],
        ]);
      },
    );
  }

  /// 판매점 지도 — 이름 · 주소 + 네이버 지도 / 카카오맵 (좌표 없으면 이름+주소 검색)
  Future<void> _showMap(String code, String name, LotteryStore? s) => showModalBottomSheet(
        context: context,
        builder: (c) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(s?.address.isNotEmpty == true ? s!.address : '주소 정보 없음 — 이름으로 검색합니다',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              StoreMapButtons(target: StoreMapTarget(storeId: code, name: name, address: s?.address ?? '', lat: s?.latitude, lng: s?.longitude)),
            ]),
          ),
        ),
      );

  Widget _mapButton(String code, String name, LotteryStore? s) => IconButton(
        key: ValueKey('speetto_map_$code'),
        visualDensity: VisualDensity.compact,
        tooltip: '지도',
        icon: const Icon(Icons.map_rounded, color: kSpeettoColor, size: 20),
        onPressed: () => _showMap(code, name, s),
      );

  Widget _hero() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF00897B), Color(0xFF26A69A)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('스피또 2000 · 1000 · 500', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
          Text('스피또 판매점', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        ]),
      );

  Widget _storesArea(SpeettoBriefing? b) {
    final games = b?.games ?? const <SpeettoGame>[];
    final okGames = games.where((g) => g.ok && g.stores.isNotEmpty).toList();
    if (okGames.isEmpty) {
      final bad = games.where((g) => g.status == 'data_invalid').toList();
      return _area('1', '게임별 1등 판매점', Text(
          widget.admin
              ? (bad.isNotEmpty
                  ? '데이터 정리 필요 — 저장된 스피또 1등 판매점 기록이 차수마다 같은 목록입니다 '
                      '(${bad.map((g) => '${g.label} ${((g.sameRatio ?? 0) * 100).round()}%').join(' · ')}). '
                      '스피또 크롤러는 고쳤고, 예전 기록을 정리한 뒤 다시 모으면 자동으로 표시됩니다.'
                  : '스피또 판매점 계산 결과가 아직 없습니다 (서버 매일 17시).')
              : '스피또 판매점 정보를 준비하고 있습니다.',
          key: const ValueKey('speetto_stores_waiting'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.45)));
    }
    return _area('1', '게임별 1등 판매점', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('스피또 1·2등이 나온 판매점 · ★를 누르면 즐겨찾기에 저장됩니다', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
      for (final g in okGames) ...[
        const SizedBox(height: 10),
        Text('${g.label}${g.latestEdition == null ? '' : ' · 최근 ${g.latestEdition}차'}',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: kSpeettoColor)),
        const SizedBox(height: 4),
        for (final e in g.stores.asMap().entries)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
            decoration: BoxDecoration(color: kSpeettoColor.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              SizedBox(width: 22, child: Text('${e.key + 1}', style: const TextStyle(fontWeight: FontWeight.w900, color: kSpeettoColor))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.value.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  Text('${e.value.region.isEmpty ? '-' : e.value.region} · 최근 당첨 ${e.value.lastEdition}차',
                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
                ]),
              ),
              Text('역대 1등 ${e.value.first}회${e.value.second > 0 ? ' · 2등 ${e.value.second}회' : ''}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
              if (e.value.code.isNotEmpty) _mapButton(e.value.code, e.value.name, _info[e.value.code]),
              if (e.value.code.isNotEmpty) FavoriteStoreStar(code: e.value.code, name: e.value.name),
            ]),
          ),
      ],
    ]));
  }

  Widget _statusArea(SpeettoBriefing? b) {
    final eds = b?.editions ?? const <SpeettoEdition>[];
    if (eds.isEmpty) {
      return _area('2', '판매 중 게임 · 남은 1등', Text(
          widget.admin
              ? '판매 현황 수집 전 — ${b?.statusNote ?? '매일 10시 서버 수집 (research_v17_speetto_status.sql 필요)'}'
              : '게임별 남은 1등 정보를 준비하고 있습니다.',
          key: const ValueKey('speetto_status_waiting'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.45)));
    }
    return _area('2', '판매 중 게임 · 남은 1등', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${b?.statusDate ?? ''} 동행복권 판매 현황 · 출고된 만큼보다 1등이 많이 남은 순서',
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
      const SizedBox(height: 8),
      for (final e in eds) _editionRow(e),
      Text('남은 1등 지수 = 남은 1등 비율 ÷ 아직 출고 안 된 비율. 1보다 크면 출고된 만큼보다 1등이 많이 남았다는 뜻입니다 '
          '(출고율은 판매점으로 나간 비율이라 실제 판매와 다를 수 있습니다).',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.4)),
    ]));
  }

  Widget _editionRow(SpeettoEdition e) {
    final ship = (e.shipRate ?? 0).clamp(0, 100) / 100;
    final good = (e.index ?? 0) > 1.0;
    return Container(
      key: ValueKey('speetto_edition_${e.game}_${e.edition}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: good ? const Color(0xFFE0F2F1) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: good ? kSpeettoColor : Colors.grey.shade300, width: good ? 1.4 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${e.label} ${e.edition}회', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900))),
          if (e.nearEnd)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.orange.shade700, borderRadius: BorderRadius.circular(12)),
              child: const Text('출고 거의 끝', style: TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w800)),
            )
          else if (e.index != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: good ? kSpeettoColor : Colors.grey.shade400, borderRadius: BorderRadius.circular(12)),
              child: Text('남은 1등 지수 ${e.index!.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w800)),
            ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Text('출고율 ${(e.shipRate ?? 0).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(child: LinearProgressIndicator(value: ship.toDouble(), minHeight: 6, color: kSpeettoColor,
              backgroundColor: Colors.white, borderRadius: BorderRadius.circular(3))),
        ]),
        const SizedBox(height: 6),
        if (e.nearEnd)
          Text('판매점으로 거의 다 나간 차수입니다. 남은 1등은 판매점 재고이거나, 이미 팔렸지만 아직 찾아가지 않은 표일 수 있습니다.',
              style: TextStyle(fontSize: 10.5, color: Colors.orange.shade900)),
        if (e.soldRate != null)
          Text('추정 판매율 ${e.soldRate!.toStringAsFixed(1)}%${e.p1Now != null ? ' · 1장당 1등 1/${manWon(e.p1Now!)} (처음 1/${manWon(e.p1Start ?? 0)})' : ''}',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
        Text('1등${e.prize1 == null ? '' : '(${e.prize1})'} 남은 ${e.rnk1Left ?? '-'} / ${e.rnk1Total ?? '-'}장'
            '   ·   2등${e.prize2 == null ? '' : '(${e.prize2})'} 남은 ${e.rnk2Left ?? '-'} / ${e.rnk2Total ?? '-'}장',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800)),
      ]),
    );
  }

  Widget _area(String no, String title, Widget child) => Container(
        key: ValueKey('speetto_area_$no'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kSpeettoColor.withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 26, height: 26, alignment: Alignment.center,
              decoration: BoxDecoration(color: kSpeettoColor, borderRadius: BorderRadius.circular(8)),
              child: Text(no, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      );
}

/// 내 주변 1등 판매점 — 게임별(2000 · 1000 · 500) 원래 순위를 그대로 두고 [radiusM] 안에 있는 곳만 (순수 함수)
///   반환: 게임 → [(원래 순위, 판매점, 거리 m)] (순위 순)
List<(SpeettoGame, List<(int, SpeettoStore, double)>)> nearbyRanked(
    List<SpeettoGame> games, Map<String, LotteryStore> info, double lat, double lng, {double radiusM = 20000}) {
  return [
    for (final g in games.where((g) => g.ok && g.stores.isNotEmpty))
      (g, [
        for (final (i, s) in g.stores.indexed)
          if (info[s.code]?.latitude != null && info[s.code]?.longitude != null)
            if (Geolocator.distanceBetween(lat, lng, info[s.code]!.latitude!, info[s.code]!.longitude!) case final d when d <= radiusM)
              (i + 1, s, d),
      ]),
  ];
}

/// 스피또 탭 맨 위 — 내 주변 스피또 1등 판매점 (게임별 · 원래 순위 유지 · 거리 · 지도)
class SpeettoNearbyCard extends StatefulWidget {
  final List<SpeettoGame> games;
  final Map<String, LotteryStore> info; // 판매점 코드 → 주소 · 좌표
  final Future<void> Function(String code, String name, LotteryStore? s) onMap;

  /// 테스트용: 내 위치 (위도, 경도)
  final Future<(double, double)> Function()? locate;
  const SpeettoNearbyCard({super.key, required this.games, required this.info, required this.onMap, this.locate});
  @override
  State<SpeettoNearbyCard> createState() => _SpeettoNearbyCardState();
}

class _SpeettoNearbyCardState extends State<SpeettoNearbyCard> {
  static const _radiusKm = 20;
  Future<(double, double)>? _f;

  static Future<(double, double)> _locate() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw '위치 권한이 없어 주변 판매점을 찾을 수 없습니다';
    final p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium, timeLimit: const Duration(seconds: 12));
    return (p.latitude, p.longitude);
  }

  String _dist(double m) => m < 1000 ? '${m.round()}m' : '${(m / 1000).toStringAsFixed(1)}km';

  Widget _result(double lat, double lng) {
    final groups = nearbyRanked(widget.games, widget.info, lat, lng, radiusM: _radiusKm * 1000);
    if (groups.isEmpty) {
      return Padding(padding: const EdgeInsets.only(top: 8), child: Text('게임별 1등 판매점 자료가 아직 없습니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (g, rows) in groups) ...[
        const SizedBox(height: 10),
        Text('${g.label} · 내 주변 ${_radiusKm}km ${rows.length}곳',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: kSpeettoColor)),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          Text('${_radiusKm}km 안에 ${g.label} 1등 판매점이 없습니다.', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        for (final (rank, s, d) in rows)
          Container(
            key: ValueKey('speetto_near_${g.game}_${s.code}'),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
            decoration: BoxDecoration(color: kSpeettoColor.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              SizedBox(width: 22, child: Text('$rank', style: const TextStyle(fontWeight: FontWeight.w900, color: kSpeettoColor))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  Text('${_dist(d)} · ${s.region.isEmpty ? '-' : s.region} · 역대 1등 ${s.first}회${s.second > 0 ? ' · 2등 ${s.second}회' : ''}',
                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                ]),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '지도',
                icon: const Icon(Icons.map_rounded, color: kSpeettoColor, size: 20),
                onPressed: () => widget.onMap(s.code, s.name, widget.info[s.code]),
              ),
              FavoriteStoreStar(code: s.code, name: s.name),
            ]),
          ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('speetto_nearby'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kSpeettoColor.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.near_me_rounded, color: kSpeettoColor, size: 20),
            const SizedBox(width: 6),
            const Expanded(child: Text('내 주변 스피또 1등 판매점', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
            FilledButton.icon(
              key: const ValueKey('speetto_nearby_search'),
              style: FilledButton.styleFrom(backgroundColor: kSpeettoColor, visualDensity: VisualDensity.compact),
              onPressed: () => setState(() {
                _f = (widget.locate ?? _locate)();
              }),
              icon: const Icon(Icons.my_location_rounded, size: 16),
              label: Text(_f == null ? '주변 검색' : '다시 검색', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
          if (_f == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('아래 게임별 1등 판매점 중 내 위치 ${_radiusKm}km 안에 있는 곳을 순위 그대로 보여줍니다 (2000 · 1000 · 500).',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
            )
          else
            FutureBuilder<(double, double)>(
              future: _f,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) {
                  return Padding(padding: const EdgeInsets.only(top: 8), child: Text('${snap.error}', style: TextStyle(fontSize: 12, color: Colors.orange.shade900)));
                }
                return _result(snap.data!.$1, snap.data!.$2);
              },
            ),
        ]),
      );
}
