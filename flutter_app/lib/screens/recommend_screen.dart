import 'package:flutter/material.dart';

import 'lucky_games_screen.dart';

/// 복권재미 탭 — 행운 게임 6개만 (예전 번호 추천 메뉴 · 상단 당첨번호 파란 상자는 뺌, 2026-11-25)
class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key});

  @override
  State<RecommendScreen> createState() => RecommendScreenState();
}

class RecommendScreenState extends State<RecommendScreen> {
  /// 하단 탭을 다시 누르면 부름 (홈 화면) — 게임은 따로 열린 화면이라 닫을 것이 없음
  void resetToMain() {}

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(child: LuckyGamesGrid());
}
