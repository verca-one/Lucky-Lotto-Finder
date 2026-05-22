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
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF1565C0),
            unselectedLabelColor: const Color(0xFFAAAAAA),
            indicatorColor: const Color(0xFF1565C0),
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.star_rounded, size: 20), text: '즐겨찾기'),
              Tab(icon: Icon(Icons.casino_rounded, size: 20), text: '나의 번호'),
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
    );
  }
}
