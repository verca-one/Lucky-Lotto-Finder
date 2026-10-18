// 관리자 '연구소' — 연구 화면 모음 (AI 전략기획부 · 명당 가설 · 전국 지방장 · 엔진 복기 · 실전형 재현 기록 · 예측 연구 현황)
import 'package:flutter/material.dart';

import 'admin_agent_replay_screen.dart';
import 'admin_agent_research_screen.dart';
import 'admin_engine_review_screen.dart';
import 'admin_region_research_screen.dart';
import 'admin_research_screen.dart';
import 'admin_strategy_screen.dart';

class ResearchLabEntry {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final WidgetBuilder builder;
  const ResearchLabEntry(this.icon, this.title, this.subtitle, this.color, this.builder);
}

/// 연구소 메뉴 항목 (순서 고정)
final List<ResearchLabEntry> kResearchLabEntries = [
  ResearchLabEntry(Icons.psychology_alt_rounded, 'AI 전략기획부', 'AI 연구 방향 제시 → 가설 생성 → 비서 검증·유지·폐기 (AI는 제안만)',
      const Color(0xFF5B2C9F), (_) => const AdminStrategyScreen()),
  ResearchLabEntry(Icons.travel_explore_rounded, '명당 가설 연구소 · 전국 지역 연구',
      '시·군·구 독립 연구 · 지역 간 전이 · 유명/신흥 명당 · 예측 난이도 · 복합 가설', const Color(0xFF0D47A1),
      (_) => const AdminRegionResearchScreen()),
  ResearchLabEntry(Icons.groups_2_rounded, '전국 지방장 연구소', '시·군·구 지방장 연구 · 중앙 엔진 · 공유 가설 저장소 · 미래 검증 성능',
      const Color(0xFF00695C), (_) => const AdminAgentResearchScreen()),
  ResearchLabEntry(Icons.fact_check_rounded, '엔진 복기 연구소', '중앙 엔진·지방장 238명 회차별 복기 · 공간전이 복기 · 보정 이력 (서버 자동 복기)',
      const Color(0xFF4527A0), (_) => const AdminEngineReviewScreen()),
  ResearchLabEntry(Icons.history_edu_rounded, '지방장 실전형 재현 기록', '회차별 동결 예측 · 사전/사후 브리핑 · 지방장 이력 · 가설 실전 성능 · 누적 성능',
      const Color(0xFF37474F), (_) => const AdminAgentReplayScreen()),
  ResearchLabEntry(Icons.science_rounded, '예측 연구 현황', '추첨예측 · 구매예측 · 판매점 분석 · 예측력 검증 · 서버 연구 실행 상태',
      const Color(0xFF283593), (_) => const AdminResearchScreen()),
];

class AdminResearchLabScreen extends StatelessWidget {
  const AdminResearchLabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        title: const Text('연구소', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('연구·엔진은 서버가 회차마다 자동 실행합니다. 이곳에서는 저장된 연구 결과를 봅니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          for (final e in kResearchLabEntries) ...[
            Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: e.builder)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: e.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Icon(e.icon, color: e.color, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(e.subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
