// 서버 이관 동등성 검증 — 같은 입력(학습 ~N회)으로 서버(헤드리스) 계산 결과가 저장된 앱 계산 결과와 같은지 비교.
// 쓰기 없음 (ResearchRuntime.serverWriter = false 유지).
//   PARITY_TARGET=1246 flutter test tool/server/purchase_parity_test.dart
import 'package:flutter_app/services/research/prize_stats_service.dart';
import 'package:flutter_app/services/research/purchase_prediction_engine.dart';
import 'package:flutter_app/services/research/research_runtime.dart';
import 'package:flutter_app/services/rpa_store_engine.dart';
import 'package:flutter_app/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'server_env.dart';

void main() {
  test('구매예측 서버 계산 = 저장된 결과', () async {
    await initServerSupabase();
    expect(ResearchRuntime.serverWriter, isFalse);
    final target = int.parse(envOr('PARITY_TARGET', '1246'));
    final stored = (await Supabase.instance.client
            .from('research_results')
            .select('id,training_end_round,payload')
            .eq('research_type', 'purchase_model')
            .eq('model_version', kPurchaseModelVersion)
            .eq('target_round', target)
            .order('training_end_round', ascending: false)
            .limit(1) as List)
        .first as Map<String, dynamic>;
    final te = (stored['training_end_round'] as num).toInt();

    final all = await SupabaseService.getAllWinningNumbers();
    final hist = await StoreModelEngine.instance.loadWinHistory();
    final stats = await PrizeStatsService.instance.loadAll();
    final report = PurchasePredictionEngine.instance
        .buildReport(allData: all, history: hist, targetRound: target, trainingEnd: te, prizeStats: stats);

    final p = stored['payload'] as Map<String, dynamic>;
    final storedSets = [for (final r in p['recommendations'] as List) List<int>.from((r as Map)['numbers'] as List)];
    final serverSets = [for (final r in report.recommendations) r.numbers];
    // ignore: avoid_print
    print('stored id=${stored['id']} te=$te target=$target prize_rounds stored=${p['prize_stats_rounds']} server=${report.prizeStatsRounds}');
    // ignore: avoid_print
    print('stored sets=$storedSets');
    // ignore: avoid_print
    print('server sets=$serverSets');
    // ignore: avoid_print
    print('stored gate=${(p['popularity'] as Map)['gate_reason']}');
    // ignore: avoid_print
    print('server gate=${report.popularity.gateReason}');
    expect(report.popularity.gatePass, (p['popularity'] as Map)['gate_pass']);
    expect(serverSets, storedSets);
    // 관리자 화면 경로 (저장본 → 보고서) 도 같은 5세트
    final viaApp = await PurchasePredictionEngine.instance.loadStoredReport(target);
    expect([for (final r in viaApp!.recommendations) r.numbers], storedSets);
    expect(viaApp.validated, report.validated);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
