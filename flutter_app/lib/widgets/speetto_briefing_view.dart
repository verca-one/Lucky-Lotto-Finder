// 스피또 화면 — 관리자 엔진 브리핑 '스피또' 탭 · 일반 모드 복권연구 '스피또' 탭
//  ① 게임별(스피또2000 · 1000 · 500) 1등 판매점 (서버 sp-1.0 · ★ 즐겨찾기 저장)  ② 게임별 판매 현황(출고율 · 남은 1등) — 수집 전
// 서버 계산이 '데이터 정리 필요'(예전 크롤러가 차수마다 같은 목록을 저장)로 판정하면 판매점을 보여 주지 않는다.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'briefing_store_widgets.dart' show FavoriteStoreStar;

const kSpeettoColor = Color(0xFF00897B);

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

class SpeettoBriefing {
  final List<SpeettoGame> games;
  final String disclaimer;
  const SpeettoBriefing(this.games, {this.disclaimer = ''});
  factory SpeettoBriefing.fromPayload(Map<String, dynamic> p) => SpeettoBriefing(
        [for (final g in (p['games'] as List? ?? const [])) SpeettoGame.fromJson(Map<String, dynamic>.from(g as Map))],
        disclaimer: '${p['disclaimer'] ?? ''}',
      );

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
  const SpeettoBriefingView({super.key, this.admin = true, this.loader});
  @override
  State<SpeettoBriefingView> createState() => _SpeettoBriefingViewState();
}

class _SpeettoBriefingViewState extends State<SpeettoBriefingView> {
  late Future<SpeettoBriefing?> _f;

  @override
  void initState() {
    super.initState();
    _f = (widget.loader ?? (widget.admin ? SpeettoBriefing.loadAdmin : SpeettoBriefing.loadPublic))();
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
          if (snap.connectionState != ConnectionState.done)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else ...[
            _storesArea(b),
            const SizedBox(height: 12),
            _area('2', '게임별 판매 현황 (출고율 · 남은 1등)', Text(
                widget.admin
                    ? '데이터 미확보 — 출고율이 높은데 1등이 많이 남은 게임일수록 한 장의 기대가 올라갑니다. 서버 수집 승인 후 표시합니다.'
                    : '게임별 남은 1등 정보를 준비하고 있습니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.45))),
            if (widget.admin) ...[
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
              Text('1등 ${e.value.first}${e.value.second > 0 ? ' · 2등 ${e.value.second}' : ''}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
              if (e.value.code.isNotEmpty) FavoriteStoreStar(code: e.value.code, name: e.value.name),
            ]),
          ),
      ],
    ]));
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
