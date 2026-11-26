// 7183 에이전트 저장본 (research_results · agent_7183, 서버 research_7183.py) — 읽기만
//   법칙 생태계: 세는 쪽 · 조수는 서버 계산, 꿈(추리 · 새 순환 · 믿는 법칙)은 제미나이. 번호 5세트는 월요일에 한 번 등록 후 고정.
import 'package:supabase_flutter/supabase_flutter.dart';

List<Map<String, dynamic>> _maps(dynamic v) => [for (final x in (v as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
List<num> _nums(dynamic v) => [for (final x in (v as List? ?? const [])) if (x is num) x];

class Agent7183 {
  final int target;

  /// 'gemini' = 제미나이가 꿈을 꿨음 / 'rule' = 계산값만 (제미나이 대기 · 실패)
  final String source;

  /// 'registered' = 사전 등록 · 고정 / 'waiting' = 월요일 공개 전
  final String setsStatus;

  /// 번호를 뽑을 때 제미나이가 참여했나 ('gemini' | 'rule')
  final String? setsBy;
  final String? setsNote, aiError;
  final List<List<int>> sets;

  /// 주중에 제미나이가 답해 추가한 번호 (별도 기록 — 월요일 등록 번호 sets 는 그대로)
  final List<List<int>> lateSets;
  final String? lateSetsAt, lateSetsBy;
  final List<int> goldNumbers;
  final int scanned, aliveTotal;
  final List<Map<String, dynamic>> alive, trusted, cycles, gold, nearest;
  final List<String> completedNow;
  final String dream, notes, newParts;

  /// 복기 성적: 세트 수 · 세트당 평균 맞힌 개수 · 구간
  final Map<String, dynamic> replay;

  /// 실전 누적: 세트 수 · 맞힌 개수 합 · 3개 이상
  final List<num> recordSets;

  /// 황금 숫자 누적: 추천 수 · 적중
  final List<num> recordGold;

  /// 믿은 법칙 누적: 적중 · 예상 수 · 우연 기대
  final List<num> recordTrusted;

  /// 방식별 번호에 실리는 힘 (성적이 우연을 넘은 만큼 · 0 = 우연 이하) — a7183-1.1 부터
  final Map<String, num> modeW;

  /// 이어받기 표 — [{dead: 자리, n: 회차 수, born: {자리: 평소의 몇 배}}] · 지난 회차에 끊긴 자리
  final List<Map<String, dynamic>> handover;
  final List<String> lastDead;

  /// 계산이 고른 법칙(제미나이가 못 답한 주의 규칙)의 복기 성적: 적중 · 예상 수 · 우연 기대
  final List<num> ruleTrust;

  const Agent7183({
    required this.target, this.source = 'rule', this.setsStatus = 'waiting', this.setsBy, this.setsNote, this.aiError,
    this.sets = const [], this.lateSets = const [], this.lateSetsAt, this.lateSetsBy, this.goldNumbers = const [], this.scanned = 0, this.aliveTotal = 0, this.alive = const [],
    this.trusted = const [], this.cycles = const [], this.gold = const [], this.nearest = const [], this.completedNow = const [],
    this.dream = '', this.notes = '', this.newParts = '', this.replay = const {}, this.recordSets = const [],
    this.recordGold = const [], this.recordTrusted = const [],
    this.modeW = const {}, this.handover = const [], this.lastDead = const [], this.ruleTrust = const [],
  });

  bool get byGemini => source == 'gemini';

  /// 꿈(추리)을 AI 가 썼나 — 'claude' 는 제미나이가 못 답한 주에 대신 쓴 것 (서버 research_7183.AI_SOURCES)
  bool get byAi => source == 'gemini' || source == 'claude';

  /// 화면에 적는 이름 — 대행은 대행이라고 적는다
  static String aiNameOf(String? src) => src == 'claude' ? 'Claude(대행)' : '제미나이';
  String get aiName => aiNameOf(source);
  bool get registered => setsStatus == 'registered';

  factory Agent7183.fromPayload(Map<String, dynamic> p) {
    final scout = p['scout'] is Map ? Map<String, dynamic>.from(p['scout'] as Map) : const <String, dynamic>{};
    final sb = p['scoreboard'] is Map ? Map<String, dynamic>.from(p['scoreboard'] as Map) : const <String, dynamic>{};
    final rec = p['record'] is Map ? Map<String, dynamic>.from(p['record'] as Map) : const <String, dynamic>{};
    return Agent7183(
      target: (p['target_round'] as num?)?.toInt() ?? 0,
      source: '${p['source'] ?? 'rule'}',
      setsStatus: '${p['sets_status'] ?? 'waiting'}',
      setsBy: p['sets_by'] as String?, setsNote: p['sets_note'] as String?, aiError: p['ai_error'] as String?,
      sets: [
        for (final s in (p['sets'] as List? ?? const []))
          if (s is List && s.length == 6) ([for (final n in s) (n as num).toInt()]..sort()),
      ],
      lateSets: [
        for (final s in (p['late_sets'] as List? ?? const []))
          if (s is List && s.length == 6) ([for (final n in s) (n as num).toInt()]..sort()),
      ],
      lateSetsAt: p['late_sets_at'] as String?,
      lateSetsBy: p['late_sets_by'] as String?,
      goldNumbers: [for (final n in _nums(p['gold_numbers'])) n.toInt()],
      scanned: (p['scanned'] as num?)?.toInt() ?? 0,
      aliveTotal: (p['alive_total'] as num?)?.toInt() ?? 0,
      alive: _maps(p['alive']), trusted: _maps(p['trusted']), cycles: _maps(p['cycles']),
      gold: _maps(scout['gold']), nearest: _maps(scout['nearest']),
      completedNow: [for (final x in (p['completed_now'] as List? ?? const [])) '$x'],
      dream: '${p['dream'] ?? ''}', notes: '${p['notes'] ?? ''}', newParts: '${p['new_parts'] ?? ''}',
      replay: {...(sb['sets'] is Map ? Map<String, dynamic>.from(sb['sets'] as Map) : const <String, dynamic>{}), 'from': sb['from'], 'to': sb['to']},
      recordSets: _nums(rec['sets']), recordGold: _nums(rec['gold']), recordTrusted: _nums(rec['trusted']),
      modeW: {
        if (sb['mode_w'] is Map)
          for (final e in (sb['mode_w'] as Map).entries)
            if (e.value is num) '${e.key}': e.value as num,
      },
      handover: _maps(sb['handover']),
      lastDead: [for (final x in (sb['last_dead'] as List? ?? const [])) '$x'],
      ruleTrust: _nums(sb['rule_trust']),
    );
  }

  /// 목표 회차의 최신 저장본 (없으면 null)
  static Future<Agent7183?> load(int target) async {
    final rows = await Supabase.instance.client
        .from('research_results')
        .select('payload')
        .eq('research_type', 'agent_7183')
        .eq('target_round', target)
        .order('created_at', ascending: false)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return Agent7183.fromPayload(Map<String, dynamic>.from(rows.first['payload'] as Map));
  }
}
