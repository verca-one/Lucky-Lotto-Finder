import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_lotto_round_screen.dart';
import 'admin_lotto_store_screen.dart';
import 'admin_pension_round_screen.dart';
import 'admin_pension_store_screen.dart';
import 'admin_coupon_screen.dart';
import 'admin_report_screen.dart';
import 'admin_crawl_status_screen.dart';
import 'admin_review_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _rewardedAdEnabled = false;
  bool _isLoadingConfig = true;

  @override
  void initState() {
    super.initState();
    _loadRewardedAdConfig();
  }

  Future<void> _loadRewardedAdConfig() async {
    try {
      final res = await Supabase.instance.client
          .from('app_config')
          .select('value')
          .eq('key', 'rewarded_ad_enabled')
          .single();
      if (mounted) {
        setState(() {
          _rewardedAdEnabled = res['value'] == 'true';
          _isLoadingConfig = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingConfig = false);
    }
  }

  Future<void> _toggleRewardedAd(bool enabled) async {
    setState(() => _rewardedAdEnabled = enabled);
    try {
      await Supabase.instance.client.from('app_config').upsert({
        'key': 'rewarded_ad_enabled',
        'value': enabled ? 'true' : 'false',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'key');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('보상형 광고 ${enabled ? '활성화' : '비활성화'} 완료')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _rewardedAdEnabled = !enabled);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('설정 저장 실패')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.purple,
        title: const Text(
          '관리자 패널',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '관리 메뉴',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _buildAdminMenuItem(
                      icon: Icons.confirmation_number,
                      title: '로또 당첨회차 생성',
                      subtitle: '회차/날짜/당첨번호 입력 → 발행',
                      color: Colors.purple,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminLottoRoundScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildAdminMenuItem(
                      icon: Icons.store,
                      title: '로또 당첨지점 로드',
                      subtitle: '발행된 회차의 당첨지점 로드/발행',
                      color: Colors.blue,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminLottoStoreScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildAdminMenuItem(
                      icon: Icons.card_giftcard,
                      title: '연금 당첨회차 생성',
                      subtitle: '회차/날짜/당첨번호 입력 → 발행',
                      color: Colors.orange,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminPensionRoundScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildAdminMenuItem(
                      icon: Icons.storefront,
                      title: '연금 당첨지점 로드',
                      subtitle: '발행된 회차의 당첨지점 로드/발행',
                      color: Colors.teal,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminPensionStoreScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildAdminMenuItem(
                      icon: Icons.card_giftcard,
                      title: '쿠폰 관리',
                      subtitle: '쿠폰 생성/관리 (광고제거 등)',
                      color: Colors.deepOrange,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminCouponScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildAdminMenuItem(
                      icon: Icons.flag,
                      title: '신고접수된 지점',
                      subtitle: '신고 목록 관리/상태 변경',
                      color: Colors.red.shade700,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminReportScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildAdminMenuItem(
                      icon: Icons.rate_review,
                      title: '지점평가 관리',
                      subtitle: '대기 중 평가 승인/보류/거절',
                      color: Colors.green.shade700,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminReviewScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildAdminMenuItem(
                      icon: Icons.checklist,
                      title: '크롤링 회차 확인',
                      subtitle: '회차별 크롤링/지점로드 상태 확인',
                      color: Colors.indigo,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminCrawlStatusScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '광고 설정',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.play_circle_outline, color: Colors.amber, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '주변 검색 보상형 광고',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _isLoadingConfig ? '로딩 중...' : (_rewardedAdEnabled ? '활성화됨' : '비활성화됨'),
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        if (_isLoadingConfig)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Switch(
                            value: _rewardedAdEnabled,
                            onChanged: _toggleRewardedAd,
                            activeThumbColor: Colors.amber,
                            activeTrackColor: Colors.amber.withValues(alpha: 0.4),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 28),
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
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
