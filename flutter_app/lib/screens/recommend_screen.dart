import 'package:flutter/material.dart';
import 'random_number_screen.dart';
import 'ai_number_screen.dart';
import 'golden_wave_screen.dart';
import 'saju_number_screen.dart';
import 'number_meaning_screen.dart';
import 'ac_value_screen.dart';
import 'zone_balance_screen.dart';
import 'tax_calculator_screen.dart';

class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key});

  @override
  State<RecommendScreen> createState() => RecommendScreenState();
}

class RecommendScreenState extends State<RecommendScreen> {
  // null: 메인메뉴, 'tax': 세금계산기, 'ai_sub': AI하위메뉴, ...
  String? _currentSub;

  /// 메인 메뉴로 초기화
  void resetToMain() {
    setState(() => _currentSub = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_currentSub == 'tax') {
      return _wrapWithBack(const TaxCalculatorContent(), '도구', null);
    }
    if (_currentSub == 'ai_7183') {
      return _wrapWithBack(const AiNumberContent(), 'AI 조합번호 생성', 'ai_sub');
    }
    if (_currentSub == 'ai_golden') {
      return _wrapWithBack(const GoldenWaveContent(), 'AI 조합번호 생성', 'ai_sub');
    }
    if (_currentSub == 'ai_saju') {
      return _wrapWithBack(const SajuNumberContent(), 'AI 조합번호 생성', 'ai_sub');
    }
    if (_currentSub == 'ai_ac') {
      return _wrapWithBack(const AcValueContent(), 'AI 조합번호 생성', 'ai_sub');
    }
    if (_currentSub == 'ai_zone') {
      return _wrapWithBack(const ZoneBalanceContent(), 'AI 조합번호 생성', 'ai_sub');
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
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              InkWell(
                onTap: () => setState(() => _currentSub = backTo),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_rounded, size: 20, color: Color(0xFF1565C0)),
                      const SizedBox(width: 6),
                      Text(backLabel, style: const TextStyle(fontSize: 14, color: Color(0xFF333333), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  /// 메인 메뉴: 세금계산기 / 번호 추천
  Widget _buildMenu() {
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
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('번호 추천', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white60, letterSpacing: 1.0)),
                      SizedBox(height: 4),
                      Text('도구', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5, height: 1.1)),
                      SizedBox(height: 4),
                      Text('당첨금 계산 · 나만의 번호', style: TextStyle(fontSize: 13, color: Colors.white70)),
                    ],
                  ),
                ),
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
          // 메뉴 목록
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionLabel('도구'),
                  const SizedBox(height: 10),
                  _buildMenuCard(
                    icon: Icons.receipt_long_rounded,
                    iconColor: const Color(0xFF1565C0),
                    bgColor: Colors.white,
                    borderColor: const Color(0xFFE8EDF5),
                    title: '로또 세금계산기',
                    subtitle: '당첨금 실수령액 계산',
                    onTap: () => setState(() => _currentSub = 'tax'),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionLabel('번호 추천'),
                  const SizedBox(height: 10),
                  _buildMenuCard(
                    icon: Icons.auto_awesome,
                    iconColor: Colors.purple,
                    bgColor: Colors.white,
                    borderColor: const Color(0xFFE8EDF5),
                    title: 'AI 조합번호 생성',
                    subtitle: 'AI 법칙 기반 번호 추천',
                    onTap: () => setState(() => _currentSub = 'ai_sub'),
                  ),
                  const SizedBox(height: 12),
                  _buildMenuCard(
                    icon: Icons.casino,
                    iconColor: Colors.orange,
                    bgColor: Colors.white,
                    borderColor: const Color(0xFFE8EDF5),
                    title: '나만의 번호 생성',
                    subtitle: '주사위를 굴려 랜덤 번호 조합',
                    onTap: () => setState(() => _currentSub = 'random'),
                  ),
                  const SizedBox(height: 12),
                  _buildMenuCard(
                    icon: Icons.menu_book,
                    iconColor: Colors.teal,
                    bgColor: Colors.white,
                    borderColor: const Color(0xFFE8EDF5),
                    title: '번호별 의미',
                    subtitle: '1~45 각 번호의 상징과 법칙 연계',
                    onTap: () => setState(() => _currentSub = 'meaning'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E)),
    );
  }

  /// AI 조합번호 하위 메뉴
  Widget _buildAiSubMenu() {
    return Column(
      children: [
        // 뒤로가기 헤더
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              InkWell(
                onTap: () => setState(() => _currentSub = null),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_rounded, size: 20, color: Color(0xFF1565C0)),
                      const SizedBox(width: 6),
                      const Text('도구', style: TextStyle(fontSize: 14, color: Color(0xFF333333), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // pig.png 이미지
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/pig.png',
                    width: double.infinity,
                    fit: BoxFit.fitWidth,
                  ),
                ),
                const SizedBox(height: 16),

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
                const SizedBox(height: 16),

                _buildMenuCard(
                  icon: Icons.calculate_rounded,
                  iconColor: Colors.indigo,
                  bgColor: Colors.indigo.shade50,
                  borderColor: Colors.indigo.shade200,
                  title: 'AC값 분석법',
                  subtitle: '산술 복잡도 기반 조합 최적화',
                  onTap: () => setState(() => _currentSub = 'ai_ac'),
                ),
                const SizedBox(height: 16),

                _buildMenuCard(
                  icon: Icons.equalizer_rounded,
                  iconColor: Colors.teal,
                  bgColor: Colors.teal.shade50,
                  borderColor: Colors.teal.shade200,
                  title: '구간밸런스 분석법',
                  subtitle: '5구간 분포 최적화 기반 번호 생성',
                  onTap: () => setState(() => _currentSub = 'ai_zone'),
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
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
