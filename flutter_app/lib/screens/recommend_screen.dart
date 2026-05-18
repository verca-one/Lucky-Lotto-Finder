import 'package:flutter/material.dart';
import 'random_number_screen.dart';

class RecommendScreen extends StatelessWidget {
  const RecommendScreen({super.key});

  @override
  Widget build(BuildContext context) {
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

          // AI 조합번호 생성
          _buildMenuCard(
            context,
            icon: Icons.auto_awesome,
            iconColor: Colors.purple,
            bgColor: Colors.purple.shade50,
            borderColor: Colors.purple.shade200,
            title: 'AI 조합번호 생성',
            subtitle: 'AI가 분석한 확률 기반 번호 추천',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('준비 중입니다')),
              );
            },
          ),
          const SizedBox(height: 16),

          // 나만의 번호 생성
          _buildMenuCard(
            context,
            icon: Icons.casino,
            iconColor: Colors.orange,
            bgColor: Colors.orange.shade50,
            borderColor: Colors.orange.shade200,
            title: '나만의 번호 생성',
            subtitle: '주사위를 굴려 랜덤 번호 조합',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RandomNumberScreen()),
              );
            },
          ),
          const SizedBox(height: 16),

          // 번호별 의미
          _buildMenuCard(
            context,
            icon: Icons.menu_book,
            iconColor: Colors.teal,
            bgColor: Colors.teal.shade50,
            borderColor: Colors.teal.shade200,
            title: '번호별 의미',
            subtitle: '각 번호가 가진 의미와 통계 확인',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('준비 중입니다')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
