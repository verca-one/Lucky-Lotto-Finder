// 연금 · 스피또 지방장 (ax-1.0) — 시·군·구 지방장이 복권마다 따로 낸 TOP5 · 최근 성적 (연구소 연금 연구 · 스피또 연구 화면)
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'briefing_store_widgets.dart' show FavoriteStoreStar;

class AgentExtraStore {
  final String code, name, address;
  final int first, second, last;
  const AgentExtraStore(this.code, this.name, this.address, this.first, this.second, this.last);
  factory AgentExtraStore.fromJson(Map<String, dynamic> j) => AgentExtraStore('${j['store_code'] ?? ''}', '${j['name'] ?? ''}',
      '${j['address'] ?? ''}', (j['first'] as num?)?.toInt() ?? 0, (j['second'] as num?)?.toInt() ?? 0, (j['last'] as num?)?.toInt() ?? 0);
}

class AgentExtraRegion {
  final String id;
  final List<AgentExtraStore> top;
  final int stores, events, backHits, backEvents;
  const AgentExtraRegion(this.id, this.top, this.stores, this.events, this.backHits, this.backEvents);
  factory AgentExtraRegion.fromJson(String id, Map<String, dynamic> j) => AgentExtraRegion(
        id,
        [for (final s in (j['top'] as List? ?? const [])) AgentExtraStore.fromJson(Map<String, dynamic>.from(s as Map))],
        (j['stores'] as num?)?.toInt() ?? 0, (j['events'] as num?)?.toInt() ?? 0,
        (j['back_hits'] as num?)?.toInt() ?? 0, (j['back_events'] as num?)?.toInt() ?? 0,
      );
  String get label => id.replaceAll('|', ' ');
}

/// 한 복권(연금 또는 스피또 게임 하나)의 지방장 결과
class AgentExtraBoard {
  final String title, status, unit; // unit: 회 · 차
  final int? latest;
  final List<AgentExtraRegion> regions; // 기록 많은 지역 순
  final int backHits, backEvents;
  const AgentExtraBoard(this.title, this.status, this.unit, this.latest, this.regions, this.backHits, this.backEvents);

  static AgentExtraBoard fromJson(String title, String unit, Map<String, dynamic> j, String latestKey) {
    final regs = <AgentExtraRegion>[
      for (final e in (j['regions'] as Map? ?? const {}).entries)
        AgentExtraRegion.fromJson('${e.key}', Map<String, dynamic>.from(e.value as Map)),
    ]..sort((a, b) => b.events.compareTo(a.events));
    final bt = j['backtest'] is Map ? Map<String, dynamic>.from(j['backtest']) : const <String, dynamic>{};
    return AgentExtraBoard(title, '${j['status'] ?? ''}', unit, (j[latestKey] as num?)?.toInt(), regs,
        (bt['hits'] as num?)?.toInt() ?? 0, (bt['events'] as num?)?.toInt() ?? 0);
  }
}

class AgentExtraData {
  final AgentExtraBoard? pension;
  final List<AgentExtraBoard> speetto;
  const AgentExtraData(this.pension, this.speetto);

  factory AgentExtraData.fromPayload(Map<String, dynamic> p) {
    final pen = p['pension'] is Map ? Map<String, dynamic>.from(p['pension']) : null;
    final sp = p['speetto'] is Map ? Map<String, dynamic>.from(p['speetto']) : const <String, dynamic>{};
    final games = sp['games'] is Map ? Map<String, dynamic>.from(sp['games']) : const <String, dynamic>{};
    return AgentExtraData(
      pen == null ? null : AgentExtraBoard.fromJson('연금복권', '회', pen, 'latest_round'),
      [
        for (final e in games.entries)
          AgentExtraBoard.fromJson('${(e.value as Map)['label'] ?? e.key}', '차', Map<String, dynamic>.from(e.value as Map), 'latest_edition'),
      ],
    );
  }

  static Future<AgentExtraData?> load() async {
    final rows = await Supabase.instance.client.from('research_results').select('payload')
        .eq('research_type', 'agent_extra').order('target_round', ascending: false).limit(1);
    if ((rows as List).isEmpty) return null;
    return AgentExtraData.fromPayload(Map<String, dynamic>.from(rows.first['payload'] as Map));
  }
}

/// 지방장 영역 — lottery: 'pension' | 'speetto'
class AgentExtraSection extends StatefulWidget {
  final String lottery;
  final Color color;
  final Future<AgentExtraData?> Function()? loader;
  const AgentExtraSection({super.key, required this.lottery, required this.color, this.loader});
  @override
  State<AgentExtraSection> createState() => _AgentExtraSectionState();
}

class _AgentExtraSectionState extends State<AgentExtraSection> {
  late final Future<AgentExtraData?> _f = () async {
    try {
      return await (widget.loader ?? AgentExtraData.load)();
    } catch (_) {
      return null;
    }
  }();
  final Map<String, String> _pick = {};

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AgentExtraData?>(
      future: _f,
      builder: (context, s) {
        final d = s.data;
        final boards = d == null ? const <AgentExtraBoard>[] : (widget.lottery == 'pension' ? [if (d.pension != null) d.pension!] : d.speetto);
        return Container(
          key: ValueKey('agent_extra_${widget.lottery}'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: widget.color.withValues(alpha: 0.25))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.groups_2_rounded, color: widget.color),
              const SizedBox(width: 6),
              const Expanded(child: Text('지방장 (시·군·구별)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
            ]),
            Text('로또 지방장과 같은 시·군·구 지방장이 이 복권만 따로 연구한 TOP5 · 최근 다시 뽑아 본 성적',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            if (s.connectionState != ConnectionState.done)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
            else if (boards.isEmpty)
              Text('지방장 연구 결과가 아직 없습니다 (서버 매일 17시).', style: TextStyle(fontSize: 12, color: Colors.orange.shade900))
            else
              for (final b in boards) _board(b),
          ]),
        );
      },
    );
  }

  Widget _board(AgentExtraBoard b) {
    if (b.status != 'ok' || b.regions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('${b.title}: ${b.status == 'data_invalid' ? '예전 기록 정리 필요' : '기록 없음 — 다시 수집 중'}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      );
    }
    final sel = b.regions.firstWhere((r) => r.id == _pick[b.title], orElse: () => b.regions.first);
    final rate = b.backEvents == 0 ? 0 : (100 * b.backHits / b.backEvents).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${b.title} · 지방장 ${b.regions.length}명${b.latest == null ? '' : ' · ${b.latest}${b.unit}까지'}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: widget.color)),
        Text('전체 성적: 지역 1·2등 ${b.backEvents}건 중 ${b.backHits}건이 그 지역 TOP5 안 ($rate%)',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        DropdownButton<String>(
          key: ValueKey('agent_extra_pick_${b.title}'),
          isExpanded: true,
          value: sel.id,
          items: [
            for (final r in b.regions)
              DropdownMenuItem(value: r.id, child: Text('${r.label} · 기록 ${r.events}건 · 판매점 ${r.stores}곳', style: const TextStyle(fontSize: 12.5))),
          ],
          onChanged: (v) => setState(() => _pick[b.title] = v ?? sel.id),
        ),
        Text('이 지방장 성적: 지역 1·2등 ${sel.backEvents}건 중 ${sel.backHits}건 TOP5 안',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
        for (final e in sel.top.asMap().entries)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
            decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              SizedBox(width: 22, child: Text('${e.key + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: widget.color))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.value.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  Text('${e.value.address} · 최근 ${e.value.last}${b.unit}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
                ]),
              ),
              Text('역대 1등 ${e.value.first}회 · 2등 ${e.value.second}회', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
              if (e.value.code.isNotEmpty) FavoriteStoreStar(code: e.value.code, name: e.value.name),
            ]),
          ),
      ]),
    );
  }
}
