import 'package:flutter/material.dart';
import '../widgets/home_round_header.dart' show DragonBlueLayer;
import 'favorites_screen.dart';
import 'my_numbers_screen.dart';
import 'tax_calculator_screen.dart';

class FavoritesTabScreen extends StatefulWidget {
  const FavoritesTabScreen({super.key});

  @override
  State<FavoritesTabScreen> createState() => _FavoritesTabScreenState();
}

class _FavoritesTabScreenState extends State<FavoritesTabScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) => Container(
      color: Colors.transparent, // 홈 배경(용 그림)이 보이게
      child: Column(
        children: [
          // 헤더 — 홈과 같은 파란 상자 · 배경 용 그림이 이어지게
          ClipRRect(
            borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
            child: Stack(children: [
              Positioned.fill(child: DragonBlueLayer(height: box.maxHeight)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('나의', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white60, letterSpacing: 1.0)),
                          SizedBox(height: 4),
                          // '즐겨찾기' 붓글씨 (사용자 제공 그림 · 바탕 투명, 파란 바탕 위라 흰색으로 칠함)
                          Image(
                            image: AssetImage('assets/favorites_title_brush.png'),
                            height: 46,
                            alignment: Alignment.centerLeft,
                            color: Colors.white,
                            colorBlendMode: BlendMode.srcIn,
                            semanticLabel: '즐겨찾기',
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.star_rounded, color: Colors.white, size: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 13),
                  tabs: const [
                    Tab(icon: Icon(Icons.star_rounded, size: 18), text: '즐겨찾기'),
                    Tab(icon: Icon(Icons.casino_rounded, size: 18), text: '나의 번호'),
                    Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: '세금계산기'),
                  ],
                ),
              ],
            ),
          ),
            ]),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                FavoritesScreen(),
                MyNumbersScreen(),
                TaxCalculatorContent(),
              ],
            ),
          ),
        ],
      ),
    ));
  }
}
