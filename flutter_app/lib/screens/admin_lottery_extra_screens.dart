// 관리자 연구소 — 연금 연구 · 스피또 연구 (로또 연구처럼 따로 들어가는 화면)
import 'package:flutter/material.dart';

import '../widgets/pension_briefing_view.dart';
import '../widgets/speetto_briefing_view.dart';

class AdminPensionResearchScreen extends StatelessWidget {
  const AdminPensionResearchScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFFFF8F1),
        appBar: AppBar(
          backgroundColor: kPensionColor,
          foregroundColor: Colors.white,
          title: const Text('연금 연구', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: const PensionBriefingView(),
      );
}

class AdminSpeettoResearchScreen extends StatelessWidget {
  const AdminSpeettoResearchScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF1FAF8),
        appBar: AppBar(
          backgroundColor: kSpeettoColor,
          foregroundColor: Colors.white,
          title: const Text('스피또 연구', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: const SpeettoBriefingView(),
      );
}
