import 'package:flutter/material.dart';

import '../models/lotto_winning_number.dart';
import '../services/supabase_service.dart';
import '../widgets/winning_number_boxes.dart';
import 'lucky_games_screen.dart';
import 'past_winning_numbers_screen.dart';

/// 복권연구 탭 — 최신 당첨번호(공만) + 행운 게임 6개 (예전 번호 추천 메뉴는 뺌, 2026-11-25)
class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key});

  @override
  State<RecommendScreen> createState() => RecommendScreenState();
}

class RecommendScreenState extends State<RecommendScreen> {
  LottoWinningNumber? _latestRound;

  @override
  void initState() {
    super.initState();
    _loadLatestRound();
  }

  Future<void> _loadLatestRound() async {
    try {
      final list = await SupabaseService.getRecentWinningNumbers(1);
      if (mounted && list.isNotEmpty) setState(() => _latestRound = list.first);
    } catch (_) {}
  }

  /// 하단 탭을 다시 누르면 맨 위로 (홈 화면이 부름 — 게임은 따로 열린 화면이라 닫을 것이 없음)
  void resetToMain() {}

  @override
  Widget build(BuildContext context) {
    final r = _latestRound;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF1565C0), Color(0xFF1E88E5)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: r == null
              ? Row(children: List.generate(7, (i) => Container(
                  margin: EdgeInsets.only(right: i < 6 ? 6 : 0), width: 38, height: 38,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle))))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  LottoWinningBoxes(numbers: [...r.numbers]..sort(), bonus: r.bonusNumber),
                  const PastRoundsButton(type: 'lotto'),
                ]),
        ),
        const LuckyGamesGrid(),
      ]),
    );
  }
}

