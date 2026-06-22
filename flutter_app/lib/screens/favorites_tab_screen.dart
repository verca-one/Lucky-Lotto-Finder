import 'package:flutter/material.dart';
import 'favorites_screen.dart';
import 'my_numbers_screen.dart';

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
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F4F8),
      child: Column(
        children: [
          // 헤더
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
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
                          Text('즐겨찾기', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
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
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                FavoritesScreen(),
                MyNumbersScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
