// 판매점 화면용 실전 번호 로더
//
// 기본 Number 추천(모든 판매점 공통)과 판매점별 Joint 추천을 분리해서 제공합니다.
// Joint 번호는 번호 Joint Gate를 통과했을 때만 실전(jointLive=true)입니다.

import 'package:supabase_flutter/supabase_flutter.dart';

import 'rpa_unified_prediction.dart';

class RpaLiveNumbers {
  final int targetRound;
  final int? trainingEndRound;
  final String? modelVersion;
  final List<List<int>> baseSets;
  final bool baseLive;          // 활성 버전 + Gate PASS
  final List<List<int>> jointSets;
  final bool jointLive;         // 번호 Joint Gate PASS
  final String? jointRegion;
  final String note;            // 출처/상태 설명

  const RpaLiveNumbers({
    required this.targetRound,
    this.trainingEndRound,
    this.modelVersion,
    this.baseSets = const [],
    this.baseLive = false,
    this.jointSets = const [],
    this.jointLive = false,
    this.jointRegion,
    required this.note,
  });

  static List<List<int>> _sets(dynamic raw) => (raw as List? ?? [])
      .map((s) => s is Map ? s['numbers'] : s)
      .map<List<int>>((s) => (s as List).map<int>((n) => (n as num).toInt()).toList())
      .toList();

  static Future<RpaLiveNumbers> load(int targetRound) async {
    final db = Supabase.instance.client;

    // 1) 통합 결과 (활성 버전, 가장 최근 학습 회차)
    try {
      final rows = await db
          .from('rpa_prediction_results')
          .select('training_end_round,prediction_type,payload,gate_status,evidence')
          .eq('target_round', targetRound)
          .eq('model_version', kRpaActiveModelVersion)
          .inFilter('prediction_type', [RpaPredictionType.numberBase, RpaPredictionType.jointContextual])
          .order('training_end_round', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isNotEmpty) {
        final te = list.first['training_end_round'] as int;
        final nb = list.where((r) => r['training_end_round'] == te &&
            r['prediction_type'] == RpaPredictionType.numberBase).firstOrNull;
        final jc = list.where((r) => r['training_end_round'] == te &&
            r['prediction_type'] == RpaPredictionType.jointContextual).firstOrNull;
        if (nb != null) {
          final jp = Map<String, dynamic>.from(jc?['payload'] as Map? ?? {});
          return RpaLiveNumbers(
            targetRound: targetRound,
            trainingEndRound: te,
            modelVersion: kRpaActiveModelVersion,
            baseSets: _sets((nb['payload'] as Map)['sets']),
            baseLive: nb['gate_status'] == RpaGate.pass,
            jointSets: _sets(jp['joint_sets']),
            jointLive: jc?['gate_status'] == RpaGate.pass,
            jointRegion: jp['predicted_region'] as String?,
            note: '엔진 v$kRpaActiveModelVersion · $te회까지 학습 → $targetRound회 예측',
          );
        }
      }
    } catch (_) {
      // 통합 결과 테이블 미적용 → 아래 Snapshot으로
    }

    // 2) Snapshot (활성 버전 우선, 없으면 이전 버전을 명시)
    try {
      final rows = await db
          .from('rpa_prediction_snapshots')
          .select('training_end_round,model_version,recommended_sets,created_at')
          .eq('target_round', targetRound)
          .order('training_end_round', ascending: false)
          .order('created_at', ascending: false)
          .limit(10);
      final list = List<Map<String, dynamic>>.from(rows as List)
          .where((r) => (r['recommended_sets'] as List? ?? []).isNotEmpty)
          .toList();
      final active = list.where((r) => '${r['model_version']}' == kRpaActiveModelVersion).firstOrNull;
      final pick = active ?? list.firstOrNull;
      if (pick != null) {
        final isActive = active != null;
        return RpaLiveNumbers(
          targetRound: targetRound,
          trainingEndRound: pick['training_end_round'] as int?,
          modelVersion: '${pick['model_version']}',
          baseSets: _sets(pick['recommended_sets']),
          baseLive: isActive,
          note: isActive
              ? '엔진 v$kRpaActiveModelVersion Snapshot · ${pick['training_end_round']}회까지 학습'
              : '이전 버전 v${pick['model_version']} Snapshot — 활성 엔진 v$kRpaActiveModelVersion 결과 미생성 (실전 아님)',
        );
      }
    } catch (_) {}

    return RpaLiveNumbers(
      targetRound: targetRound,
      note: '$targetRound회 엔진 예측이 아직 없습니다. 새 회차 처리 후 자동 생성됩니다.',
    );
  }
}
