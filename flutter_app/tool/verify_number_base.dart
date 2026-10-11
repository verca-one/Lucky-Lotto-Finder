// 저장된 Snapshot과 rpa_number_core 재계산 결과가 동일한지 검증합니다.
// 실행: cd flutter_app && dart run tool/verify_number_base.dart [targetRound]

import 'package:flutter_app/services/rpa_number_core.dart';

import 'rpa_rest.dart';

Future<void> main(List<String> args) async {
  final rest = RpaRest.fromApp();
  try {
    final all = await rest.winningNumbers();
    final latest = all.map((w) => w.round).reduce((a, b) => a > b ? a : b);
    final target = args.isNotEmpty ? int.parse(args[0]) : latest + 1;
    final training = all.where((w) => w.round < target).toList();
    final trainingEnd = training.map((w) => w.round).reduce((a, b) => a > b ? a : b);

    final state = await rest.get('rpa_model_state?select=*&state_key=eq.current');
    final rawFlips = state.isNotEmpty ? state.first['active_flips'] : null;
    final flips = <String, bool>{
      for (final id in rpaIndicatorIds)
        id: rawFlips is Map ? (rawFlips[id] as bool? ?? false) : false,
    };

    final base = rpaComputeNumberBase(training, activeFlips: flips);
    final snaps = await rest.get(
        'rpa_prediction_snapshots?select=id,model_version,created_at,final_prediction,candidate_numbers,recommended_sets'
        '&target_round=eq.$target&training_end_round=eq.$trainingEnd&order=created_at.asc');

    print('target=$target trainingEnd=$trainingEnd rounds=${training.length} flips=$flips');
    print('recomputed dirs=${base.finalDirections}');
    print('recomputed sets=${base.recommendedSets}');
    print('recomputed top18=${base.candidates.map((c) => '${c['n']}:${c['s']}').join(' ')}');
    for (final s in snaps) {
      final dirs = (s['final_prediction'] as Map?)?['directions'];
      final cands = (s['candidate_numbers'] as List).map((c) => '${c['n']}:${c['s']}').join(' ');
      final sameSets = s['recommended_sets'].toString() == base.recommendedSets.toString();
      final sameCands = cands == base.candidates.map((c) => '${c['n']}:${c['s']}').join(' ');
      final sameDirs = dirs.toString() == base.finalDirections.toString();
      print('snapshot v${s['model_version']} ${s['created_at']}: '
          'dirs=${sameDirs ? 'SAME' : 'DIFF $dirs'} candidates=${sameCands ? 'SAME' : 'DIFF'} '
          'sets=${sameSets ? 'SAME' : 'DIFF ${s['recommended_sets']}'}');
    }
  } finally {
    rest.close();
  }
}
