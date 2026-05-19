import 'package:flutter/material.dart';
import 'random_number_screen.dart';
import 'ai_number_screen.dart';
import 'golden_wave_screen.dart';
import 'saju_number_screen.dart';
import 'number_meaning_screen.dart';

class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key});

  @override
  State<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends State<RecommendScreen> {
  // null: 메인메뉴, 'ai_sub': AI하위메뉴, 'ai_7183', 'ai_golden', 'random', 'meaning'
  String? _currentSub;

  @override
  Widget build(BuildContext context) {
    if (_currentSub == 'ai_7183') {
      return _wrapWithBack(const AiNumberContent(), 'AI 조합번호 생성', 'ai_sub');
    }
    if (_currentSub == 'ai_golden') {
      return _wrapWithBack(const GoldenWaveContent(), 'AI 조합번호 생성', 'ai_sub');
    }
    if (_currentSub == 'ai_saju') {
      return _wrapWithBack(const SajuNumberContent(), 'AI 조합번호 생성', 'ai_sub');
    }
    if (_currentSub == 'random') {
      return _wrapWithBack(const RandomNumberContent(), '번호 추천', null);
    }
    if (_currentSub == 'meaning') {
      return _wrapWithBack(const NumberMeaningContent(), '번호 추천', null);
    }
    if (_currentSub == 'ai_sub') {
      return _buildAiSubMenu();
    }
    return _buildMenu();
  }

  Widget _wrapWithBack(Widget child, String backLabel, String? backTo) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _currentSub = backTo),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back_ios_rounded, size: 18, color: Color(0xFF666666)),
                    const SizedBox(width: 4),
                    Text(backLabel, style: const TextStyle(fontSize: 14, color: Color(0xFF666666), fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  /// 메인 메뉴: AI 조합번호 생성 / 나만의 번호 생성 / 번호별 의미
  Widget _buildMenu() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '번호 추천',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '나만의 행운 번호를 만들어보세요',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),

          _buildMenuCard(
            icon: Icons.auto_awesome,
            iconColor: Colors.purple,
            bgColor: Colors.purple.shade50,
            borderColor: Colors.purple.shade200,
            title: 'AI 조합번호 생성',
            subtitle: 'AI 법칙 기반 번호 추천',
            onTap: () => setState(() => _currentSub = 'ai_sub'),
          ),
          const SizedBox(height: 16),

          _buildMenuCard(
            icon: Icons.casino,
            iconColor: Colors.orange,
            bgColor: Colors.orange.shade50,
            borderColor: Colors.orange.shade200,
            title: '나만의 번호 생성',
            subtitle: '주사위를 굴려 랜덤 번호 조합',
            onTap: () => setState(() => _currentSub = 'random'),
          ),
          const SizedBox(height: 16),

          _buildMenuCard(
            icon: Icons.menu_book,
            iconColor: Colors.teal,
            bgColor: Colors.teal.shade50,
            borderColor: Colors.teal.shade200,
            title: '번호별 의미',
            subtitle: '1~45 각 번호의 상징과 법칙 연계',
            onTap: () => setState(() => _currentSub = 'meaning'),
          ),
        ],
      ),
    );
  }

  /// AI 조합번호 하위 메뉴: 7183 법칙 / 황금파동
  Widget _buildAiSubMenu() {
    return Column(
      children: [
        // 뒤로가기 헤더
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _currentSub = null),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back_ios_rounded, size: 18, color: Color(0xFF666666)),
                    const SizedBox(width: 4),
                    const Text('번호 추천', style: TextStyle(fontSize: 14, color: Color(0xFF666666), fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI 조합번호 생성',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'AI 법칙을 선택하여 번호를 생성하세요',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),

                _buildMenuCard(
                  icon: Icons.auto_awesome,
                  iconColor: Colors.purple,
                  bgColor: Colors.purple.shade50,
                  borderColor: Colors.purple.shade200,
                  title: '7183 법칙 생성',
                  subtitle: '7183 순환 규칙 기반 번호 생성',
                  onTap: () => setState(() => _currentSub = 'ai_7183'),
                ),
                const SizedBox(height: 16),

                _buildMenuCard(
                  icon: Icons.waves,
                  iconColor: Colors.amber.shade700,
                  bgColor: Colors.amber.shade50,
                  borderColor: Colors.amber.shade200,
                  title: '황금파동 분석법',
                  subtitle: '핫/콜드 빈도 + Gap 가중치 AI 분석',
                  onTap: () => setState(() => _currentSub = 'ai_golden'),
                ),
                const SizedBox(height: 16),

                _buildMenuCard(
                  icon: Icons.auto_graph,
                  iconColor: Colors.deepPurple,
                  bgColor: Colors.deepPurple.shade50,
                  borderColor: Colors.deepPurple.shade200,
                  title: '오늘의 사주 로또번호',
                  subtitle: '생년월일시 오행 기반 번호 추천',
                  onTap: () => setState(() => _currentSub = 'ai_saju'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFBBBBBB)),
          ],
        ),
      ),
    );
  }
}
