// 연금복권720+ 브리핑 (pn-1.0) — 서버 저장본만 읽는다.
//  관리자: research_results(pension_briefing) · 일반 모드: research_public_extra(lottery = pension, 공개 요약)
import 'package:supabase_flutter/supabase_flutter.dart';

double? _dn(dynamic v) => (v as num?)?.toDouble();
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
List<Map<String, dynamic>> _maps(dynamic v) => [for (final x in (v as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class PensionTicket {
  final int group;
  final String number;
  const PensionTicket(this.group, this.number);
  factory PensionTicket.fromJson(Map<String, dynamic> j) => PensionTicket(_i(j['group']), '${j['number'] ?? ''}');
}

class PensionStore {
  final String name, region;
  final int first, second, lastRound;
  final double? pNext;
  final List<int> rounds;
  const PensionStore({required this.name, this.region = '', this.first = 0, this.second = 0, this.lastRound = 0, this.pNext,
      this.rounds = const []});
  factory PensionStore.fromJson(Map<String, dynamic> j) => PensionStore(
        name: '${j['name'] ?? ''}', region: '${j['region'] ?? ''}', first: _i(j['first']), second: _i(j['second']),
        lastRound: _i(j['last_round']), pNext: _dn(j['p_next']),
        rounds: [for (final r in (j['rounds'] as List? ?? const [])) (r as num).toInt()],
      );
}

class PensionHyp {
  final String statement, status;
  final double? z, m;
  const PensionHyp(this.statement, this.status, this.z, this.m);
}

class PensionBriefing {
  final int targetRound, latestRound, numbersEntered;
  final String drawDate;

  /// 번호 엔진: ok | waiting
  final String engineStatus;
  final String? engineNote, engineRule;
  final List<PensionTicket> engineTickets;
  final Map<String, int> groupCounts;

  final List<PensionStore> stores;
  final String? storeRule;
  final double? eventsPerRound;

  /// 가설 트랙: ok | waiting
  final String trackStatus;
  final String? trackNote;
  final List<PensionTicket> trackTickets;
  final List<PensionHyp> trackHyps;
  final int trackTotal;
  final String disclaimer;
  const PensionBriefing({
    required this.targetRound, this.latestRound = 0, this.numbersEntered = 0, this.drawDate = '',
    this.engineStatus = 'waiting', this.engineNote, this.engineRule, this.engineTickets = const [], this.groupCounts = const {},
    this.stores = const [], this.storeRule, this.eventsPerRound,
    this.trackStatus = 'waiting', this.trackNote, this.trackTickets = const [], this.trackHyps = const [], this.trackTotal = 0,
    this.disclaimer = '',
  });

  /// 관리자 저장본 (research_results.payload)
  factory PensionBriefing.fromPayload(Map<String, dynamic> p) {
    final e = _map(p['engine']), s = _map(p['stores']), t = _map(p['track']);
    return PensionBriefing(
      targetRound: _i(p['target_round']), latestRound: _i(p['latest_round']), numbersEntered: _i(p['numbers_entered']),
      drawDate: '${p['draw_date'] ?? ''}',
      engineStatus: '${e['status'] ?? 'waiting'}', engineNote: e['note'] as String?, engineRule: e['rule'] as String?,
      engineTickets: _maps(e['tickets']).map(PensionTicket.fromJson).toList(),
      groupCounts: {for (final x in _map(e['group_counts']).entries) x.key: (x.value as num).toInt()},
      stores: _maps(s['stores']).map(PensionStore.fromJson).toList(), storeRule: s['rule'] as String?,
      eventsPerRound: _dn(s['events_per_round']),
      trackStatus: '${t['status'] ?? 'waiting'}', trackNote: t['note'] as String?,
      trackTickets: _maps(t['tickets']).map(PensionTicket.fromJson).toList(),
      trackHyps: [
        for (final u in _maps(t['used'])) PensionHyp('${u['statement'] ?? ''}'.replaceFirst('[연금] ', ''), '${u['status'] ?? ''}', _dn(u['z']), _dn(u['m'])),
      ],
      trackTotal: _i(t['hypotheses_total']),
    );
  }

  /// 일반 모드 공개 요약 (research_public_extra.payload)
  factory PensionBriefing.fromPublic(Map<String, dynamic> p) {
    final e = _map(p['engine']), t = _map(p['track']);
    return PensionBriefing(
      targetRound: _i(p['target_round']), drawDate: '${p['draw_date'] ?? ''}',
      engineStatus: '${e['status'] ?? 'waiting'}', engineNote: e['note'] as String?, engineRule: e['rule'] as String?,
      engineTickets: _maps(e['tickets']).map(PensionTicket.fromJson).toList(),
      stores: _maps(p['stores']).map(PensionStore.fromJson).toList(),
      trackStatus: '${t['status'] ?? 'waiting'}', trackNote: t['note'] as String?,
      trackTickets: _maps(t['tickets']).map(PensionTicket.fromJson).toList(),
      trackHyps: [for (final h in (t['hypotheses'] as List? ?? const [])) PensionHyp('$h', '', null, null)],
      disclaimer: '${p['disclaimer'] ?? ''}',
    );
  }

  static Future<PensionBriefing?> loadAdmin() async {
    final rows = await Supabase.instance.client.from('research_results').select('payload')
        .eq('research_type', 'pension_briefing').order('target_round', ascending: false).order('created_at', ascending: false).limit(1);
    if ((rows as List).isEmpty) return null;
    return PensionBriefing.fromPayload(Map<String, dynamic>.from(rows.first['payload'] as Map));
  }

  static Future<PensionBriefing?> loadPublic() async {
    final rows = await Supabase.instance.client.from('research_public_extra').select('payload')
        .eq('lottery', 'pension').order('target_round', ascending: false).limit(1);
    if ((rows as List).isEmpty) return null;
    return PensionBriefing.fromPublic(Map<String, dynamic>.from(rows.first['payload'] as Map));
  }
}
