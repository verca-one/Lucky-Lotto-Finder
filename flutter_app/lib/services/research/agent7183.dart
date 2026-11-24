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

  const Agent7183({
    required this.target, this.source = 'rule', this.setsStatus = 'waiting', this.setsBy, this.setsNote, this.aiError,
    this.sets = const [], this.goldNumbers = const [], this.scanned = 0, this.aliveTotal = 0, this.alive = const [],
    this.trusted = const [], this.cycles = const [], this.gold = const [], this.nearest = const [], this.completedNow = const [],
    this.dream = '', this.notes = '', this.newParts = '', this.replay = const {}, this.recordSets = const [],
    this.recordGold = const [], this.recordTrusted = const [],
  });

  bool get byGemini => source == 'gemini';
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
      goldNumbers: [for (final n in _nums(p['gold_numbers'])) n.toInt()],
      scanned: (p['scanned'] as num?)?.toInt() ?? 0,
      aliveTotal: (p['alive_total'] as num?)?.toInt() ?? 0,
      alive: _maps(p['alive']), trusted: _maps(p['trusted']), cycles: _maps(p['cycles']),
      gold: _maps(scout['gold']), nearest: _maps(scout['nearest']),
      completedNow: [for (final x in (p['completed_now'] as List? ?? const [])) '$x'],
      dream: '${p['dream'] ?? ''}', notes: '${p['notes'] ?? ''}', newParts: '${p['new_parts'] ?? ''}',
      replay: {...(sb['sets'] is Map ? Map<String, dynamic>.from(sb['sets'] as Map) : const <String, dynamic>{}), 'from': sb['from'], 'to': sb['to']},
      recordSets: _nums(rec['sets']), recordGold: _nums(rec['gold']), recordTrusted: _nums(rec['trusted']),
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
