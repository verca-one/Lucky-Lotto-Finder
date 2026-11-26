import 'package:flutter/material.dart';

import '../widgets/home_round_header.dart' show DragonBlueLayer;
import 'lucky_games_screen.dart';

/// 복권재미 탭 — 머리 파란 상자(흰 선 용 · 붓글씨 제목) + 행운 게임 6개. 바탕은 투명이라 홈 배경 용 그림이 보임
class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key});

  @override
  State<RecommendScreen> createState() => RecommendScreenState();
}

class RecommendScreenState extends State<RecommendScreen> {
  /// 하단 탭을 다시 누르면 부름 (홈 화면) — 게임은 따로 열린 화면이라 닫을 것이 없음
  void resetToMain() {}

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
          child: Stack(
            children: [
              const Positioned.fill(child: DragonBlueLayer()), // 스크롤만큼 옮겨 배경 용과 이어짐
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('행운 게임', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white60, letterSpacing: 1.0)),
                          SizedBox(height: 4),
                          // '복권재미' 붓글씨 (사용자 제공 그림 · 바탕 투명, 흰색으로 칠함)
                          Image(
                            image: AssetImage('assets/fun_title_brush.png'),
                            height: 46,
                            alignment: Alignment.centerLeft,
                            color: Colors.white,
                            colorBlendMode: BlendMode.srcIn,
                            semanticLabel: '복권재미',
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const LuckyGamesGrid(),
      ],
    ),
  );
}
