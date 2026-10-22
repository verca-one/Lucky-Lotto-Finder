import 'dart:async';
import 'round_debrief_view.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/rpa_unified_prediction.dart' show kRpaActiveModelVersion;

import 'admin_lotto_round_screen.dart';
import 'admin_lotto_store_screen.dart';
import 'admin_pension_round_screen.dart';
import 'admin_pension_numbers_input_screen.dart';
import 'admin_pension_store_screen.dart';
import 'admin_coupon_screen.dart';
import 'admin_report_screen.dart';
import 'admin_crawl_status_screen.dart';
import 'admin_review_screen.dart';
import 'admin_badge_status_screen.dart';
import 'admin_rpa_screen.dart';
import 'admin_region_research_screen.dart';
import '../widgets/master_briefing_section.dart';
import '../widgets/pension_briefing_view.dart';
import '../widgets/speetto_briefing_view.dart';
import '../widgets/agent_briefing_section.dart';
import '../widgets/db_usage_card.dart';
import '../services/research/research_scheduler.dart';
import '../services/rpa_monte_carlo_engine.dart';
import 'admin_engine_review_screen.dart';
import 'admin_research_lab_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  void initState() {
    super.initState();
    // 예측 연구는 서버 파이프라인이 실행한다 — 관리자 화면은 저장된 결과·실행 상태만 본다
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
            // ── 엔진 브리핑 직원 (최상단) ──────────────────────────
            _BriefingCard(onDetail: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminRpaScreen()),
              );
            }),
            const SizedBox(height: 8),
            // ── DB 사용량 (Worker 측정값, 경고 시 배너) ─────────────
            const DbUsageCard(),
            const SizedBox(height: 12),

            // ── 핵심 메뉴 ─────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('핵심 메뉴',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildAdminMenuItem(
                      icon: Icons.confirmation_number,
                      title: '로또 당첨회차 생성',
                      subtitle: '회차/날짜/당첨번호 입력 → 발행',
                      color: Colors.purple,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AdminLottoRoundScreen())),
                    ),
                    const SizedBox(height: 8),
                    _buildAdminMenuItem(
                      icon: Icons.card_giftcard,
                      title: '연금복권 당첨번호 입력',
                      subtitle: '회차별 1등 조·6자리·보너스 입력 (과거 회차까지) → 연금 엔진·가설 트랙',
                      color: const Color(0xFFEF6C00),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AdminPensionNumbersInputScreen())),
                    ),
                    const SizedBox(height: 8),
                    _buildAdminMenuItem(
                      icon: Icons.biotech_rounded,
                      title: '연구소',
                      subtitle: 'AI 전략기획부 · 명당 가설 · 지방장 · 엔진 복기 · 예측 연구 현황 · 패턴 분석 · 추천 판매점',
                      color: const Color(0xFF1A237E),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AdminResearchLabScreen())),
                    ),
                    const SizedBox(height: 8),
                    _buildAdminMenuItem(
                      icon: Icons.card_giftcard,
                      title: '쿠폰 관리',
                      subtitle: '쿠폰 생성/관리 (광고제거 등)',
                      color: Colors.deepOrange.shade700,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AdminCouponScreen())),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── 관리평가 (접기/펼치기) ─────────────────────────────
            Card(
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.admin_panel_settings_rounded,
                        color: Colors.blueGrey.shade600, size: 22),
                  ),
                  title: const Text('관리평가',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  subtitle: const Text('데이터 로드 · 지점관리 · 크롤링 현황',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(children: [
                        _buildAdminMenuItem(
                          icon: Icons.storefront,
                          title: '연금 당첨지점 로드',
                          subtitle: '발행된 회차의 연금 당첨지점 로드/발행',
                          color: Colors.teal,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminPensionStoreScreen())),
                        ),
                        const SizedBox(height: 8),
                        _buildAdminMenuItem(
                          icon: Icons.flag,
                          title: '신고접수된 지점',
                          subtitle: '신고 목록 관리/상태 변경',
                          color: Colors.red.shade700,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminReportScreen())),
                        ),
                        const SizedBox(height: 8),
                        _buildAdminMenuItem(
                          icon: Icons.rate_review,
                          title: '지점평가 관리',
                          subtitle: '대기 중 평가 승인/보류/거절',
                          color: Colors.green.shade700,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminReviewScreen())),
                        ),
                        const SizedBox(height: 8),
                        _buildAdminMenuItem(
                          icon: Icons.checklist,
                          title: '크롤링 회차 확인',
                          subtitle: '회차별 크롤링/지점로드 상태 확인',
                          color: Colors.indigo,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminCrawlStatusScreen())),
                        ),
                        const SizedBox(height: 8),
                        _buildAdminMenuItem(
                          icon: Icons.workspace_premium,
                          title: '배지 계산 현황',
                          subtitle: '회차별 배지계산 적용완료/실패 확인',
                          color: Colors.deepPurple,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminBadgeStatusScreen())),
                        ),
                        const SizedBox(height: 8),
                        _buildAdminMenuItem(
                          icon: Icons.store,
                          title: '로또 당첨지점 로드',
                          subtitle: '발행된 회차의 로또 당첨지점 로드/발행',
                          color: Colors.blue,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminLottoStoreScreen())),
                        ),
                        const SizedBox(height: 8),
                        _buildAdminMenuItem(
                          icon: Icons.card_giftcard,
                          title: '연금 당첨회차 생성',
                          subtitle: '연금 회차/날짜/당첨번호 입력 → 발행',
                          color: Colors.orange,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const AdminPensionRoundScreen())),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── 랜덤확률분석엔진 (관리평가 아래) ──────────────────────
            _RpaEngineCard(onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminRpaScreen()),
              );
            }),
            const SizedBox(height: 16),
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

// ══════════════════════════════════════════════════════════
// 랜덤확률분석엔진 전용 카드 (관리자 메뉴에서 강조 표시)
// ══════════════════════════════════════════════════════════

class _RpaEngineCard extends StatefulWidget {
  final VoidCallback onTap;
  const _RpaEngineCard({required this.onTap});

  @override
  State<_RpaEngineCard> createState() => _RpaEngineCardState();
}

class _RpaEngineCardState extends State<_RpaEngineCard> {
  // Gate state = 단일 source of truth
  int _gateRound = 0;
  String _engineStatus = '';
  bool _hasPrediction = false; // gate.round+1 Number Prediction 존재 여부
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // ready/processing 상태면 10초마다 자동 갱신
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      if (_engineStatus == 'ready' || _engineStatus == 'processing' || _gateRound == 0) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final db = Supabase.instance.client;

      // 최신 게이트 (source of truth)
      final gateRaw = await db.from('rpa_round_gate').select()
          .order('round', ascending: false).limit(1).maybeSingle();
      if (gateRaw == null) return;

      final round = gateRaw['round'] as int? ?? 0;
      final status = gateRaw['engine_status'] as String? ?? '';

      // gate.round+1 예측 존재 여부 (gate=completed일 때만 의미 있음)
      bool hasPred = false;
      if (round > 0 && status == 'completed') {
        final predRows = await db
            .from('rpa_prediction_snapshots')
            .select('id')
            .eq('training_end_round', round)
            .eq('target_round', round + 1)
            .eq('model_version', kRpaActiveModelVersion)
            .limit(1);
        hasPred = (predRows as List).isNotEmpty;
      }

      if (mounted) {
        setState(() {
          _gateRound = round;
          _engineStatus = status;
          _hasPrediction = hasPred;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final (badgeLabel, badgeColor) = _badgeInfo();
    final targetRound = _gateRound + 1;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4527A0), Color(0xFF6A1B9A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4527A0).withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.settings_suggest_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('랜덤확률분석엔진',
                  style: TextStyle(color: Colors.white, fontSize: 17,
                      fontWeight: FontWeight.w800)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: badgeColor.withOpacity(0.6)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6,
                    decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(badgeLabel,
                    style: TextStyle(fontSize: 10, color: badgeColor,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Text('번호 · 판매점 · 가설 학습',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Expanded(child: _statusRow(targetRound)),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 12, color: Colors.white54),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _statusRow(int targetRound) {
    if (_gateRound == 0) {
      return const Text('엔진 데이터 로딩 중...',
          style: TextStyle(color: Colors.white70, fontSize: 12));
    }
    switch (_engineStatus) {
      case 'completed':
        return Row(children: [
          const Icon(Icons.check_circle_rounded, size: 13, color: Colors.greenAccent),
          const SizedBox(width: 5),
          Text('✨ ${_gateRound}회 학습 완료',
              style: const TextStyle(color: Colors.white,
                  fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          if (_hasPrediction) ...[
            const Icon(Icons.auto_awesome, size: 13, color: Colors.greenAccent),
            const SizedBox(width: 4),
            Text('→ 🔮 $targetRound회 예측 완료 ✓',
                style: const TextStyle(color: Colors.greenAccent,
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ] else ...[
            const Icon(Icons.warning_amber_rounded, size: 13, color: Colors.amberAccent),
            const SizedBox(width: 4),
            Text('→ $targetRound회 예측 미생성 ⚠',
                style: const TextStyle(color: Colors.amberAccent,
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ]);
      case 'processing':
        return Row(children: [
          const SizedBox(width: 13, height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.amberAccent)),
          const SizedBox(width: 6),
          Text('⚙️ ${_gateRound}회 처리 중... → $targetRound회 예측 생성 중',
              style: const TextStyle(color: Colors.amberAccent,
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]);
      case 'ready':
        return Row(children: [
          const Icon(Icons.play_circle_outline, size: 13, color: Colors.tealAccent),
          const SizedBox(width: 5),
          Text('▶ ${_gateRound}회 실행 대기 → $targetRound회 예측 예정',
              style: const TextStyle(color: Colors.tealAccent,
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]);
      case 'waiting_store':
        return Row(children: [
          Icon(Icons.lock_clock, size: 13, color: Colors.orange.shade300),
          const SizedBox(width: 5),
          Text('🔒 ${_gateRound}회 판매점 크롤링 대기',
              style: TextStyle(color: Colors.orange.shade200,
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]);
      case 'failed':
        return Row(children: [
          const Icon(Icons.error_outline, size: 13, color: Colors.redAccent),
          const SizedBox(width: 5),
          Text('❌ ${_gateRound}회 처리 실패',
              style: const TextStyle(color: Colors.redAccent,
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]);
      default:
        return Row(children: [
          const Icon(Icons.hourglass_top_rounded, size: 13, color: Colors.white54),
          const SizedBox(width: 5),
          Text('⏳ ${_gateRound}회 번호 대기',
              style: const TextStyle(color: Colors.white54,
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]);
    }
  }

  (String, Color) _badgeInfo() {
    switch (_engineStatus) {
      case 'completed': return ('학습 완료', Colors.greenAccent);
      case 'processing': return ('처리 중', Colors.amberAccent);
      case 'waiting_store': return ('판매점 대기', Colors.orange.shade300);
      case 'waiting_number': return ('번호 대기', Colors.orange.shade300);
      case 'failed': return ('오류', Colors.redAccent);
      case 'ready': return ('실행 대기', Colors.tealAccent);
      default: return ('정상', Colors.white70);
    }
  }
}

// ══════════════════════════════════════════════════════════
// 브리핑 데이터 모델
// ══════════════════════════════════════════════════════════

class _BriefingData {
  final int latestRound;
  final String engineStatus;
  final Map<String, int> hypCounts;
  final int recentNewHyp;      // 최근 2회차 이내 신규 가설
  final int acceptedHyp;
  final int weakenedHyp;
  final int rejectedHyp;
  final double? avgCorrEffect; // 최근 10회 보정 효과 평균
  final double? avgTheoryScore;
  final double? avgCorrScore;
  final int jointPatterns;
  final double? jointAccuracy;
  final List<Map<String, dynamic>> recentEvents; // 최근 가설 이벤트

  // ── 예측 연구·명당·MC 통합 (엔진 브리핑 한 곳에서 보고) ──
  final String? mndBriefing;        // 명당 연구소 최신 브리핑 첫 문단
  final int mndBriefingRound;
  final String? researchFreq;       // 번호 빈도 결론
  final String? purchaseStatus;     // 구매예측 검증 상태
  final Map<String, dynamic>? replay; // 가설 순차 재현 요약
  final int registryTarget;         // 사전 등록 대상 회차
  final int registryRegistered;     // 그 회차에 등록된 알고리즘 수
  final int registryVerifiedRounds; // 유효 채점된 회차 수(전체)
  final bool mcBaselineOk;
  final int mcQueued;
  final int mcVerified;
  final _RegionBrief? region; // 전국 지역 연구 (없으면 null)

  const _BriefingData({
    required this.latestRound,
    required this.engineStatus,
    required this.hypCounts,
    required this.recentNewHyp,
    required this.acceptedHyp,
    required this.weakenedHyp,
    required this.rejectedHyp,
    this.avgCorrEffect,
    this.avgTheoryScore,
    this.avgCorrScore,
    required this.jointPatterns,
    this.jointAccuracy,
    required this.recentEvents,
    this.mndBriefing,
    this.mndBriefingRound = 0,
    this.researchFreq,
    this.purchaseStatus,
    this.replay,
    this.registryTarget = 0,
    this.registryRegistered = 0,
    this.registryVerifiedRounds = 0,
    this.mcBaselineOk = false,
    this.mcQueued = 0,
    this.mcVerified = 0,
    this.region,
  });

  bool get isProcessing => engineStatus == 'processing';
  int get totalActive => (hypCounts['discovered'] ?? 0) +
      (hypCounts['observing'] ?? 0) + (hypCounts['validating'] ?? 0) +
      (hypCounts['developing'] ?? 0) + (hypCounts['accepted'] ?? 0);
}

class _BriefingItem {
  final String dot;       // 🔴🟡🟢🔵⚪
  final Color dotColor;
  final String priority;  // '중요' '관찰 필요' '좋은 변화' '새로운 발견' '참고'
  final String title;
  final String plain;     // 쉬운 설명
  final String? techDetail; // 근거 데이터 (숨김)
  final int? regionTab;     // 지역 연구 화면 탭 (탭하면 이동)
  final String? regionId;   // 지역 상세로 이동할 지역

  const _BriefingItem({
    required this.dot, required this.dotColor, required this.priority,
    required this.title, required this.plain, this.techDetail, this.regionTab, this.regionId,
  });
}

/// 전국 지역 연구 브리핑용 데이터 (research_region_* 테이블, 없으면 null)
class _RegionBrief {
  final int round;
  final String runStatus;
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> passed;       // 검증 통과 (지역·판매점 가설)
  final List<Map<String, dynamic>> risingRegions; // 최근 추세 z 상위
  final List<Map<String, dynamic>> emergingStores;
  final Map<String, dynamic>? cycleLatest;       // 최신 체크포인트 주기 가설
  final Map<String, dynamic>? emergingLatest;
  const _RegionBrief({required this.round, required this.runStatus, required this.summary, required this.passed,
      required this.risingRegions, required this.emergingStores, this.cycleLatest, this.emergingLatest});
}

String _rl(String? rid) => rid == null ? '-' : rid.replaceAll('|', ' ');

List<_BriefingItem> _regionItems(_RegionBrief r) {
  final items = <_BriefingItem>[];
  final s = r.summary;
  final rep = Map<String, dynamic>.from(s['transition_replication'] as Map? ?? {});
  final byStatus = Map<String, dynamic>.from(s['by_status'] as Map? ?? {});
  items.add(_BriefingItem(
    dot: r.runStatus == 'completed' ? '🟢' : '🟡', dotColor: r.runStatus == 'completed' ? Colors.green : Colors.orange,
    priority: '지역 연구',
    title: '전국 ${s['units'] ?? '-'}개 시·군·구 연구 ${r.round}회 기준 ${r.runStatus == 'completed' ? '완료' : r.runStatus}',
    plain: '마스터, 전국 ${s['sidos'] ?? '-'}개 시·도 ${s['units'] ?? '-'}개 시·군·구를 독립 단위로 ${(s['rounds_range'] as List?)?.join('~') ?? '-'}회 당첨 기록을 연구했습니다. '
        '가설 ${s['hypotheses'] ?? 0}개 중 검증 통과 ${(byStatus['passed'] ?? 0) + (byStatus['combined'] ?? 0)}개, 연구 중 ${byStatus['researching'] ?? 0}개, '
        '약화 ${byStatus['weakened'] ?? 0}개, 기각 ${byStatus['rejected'] ?? 0}개입니다.',
    techDetail: '체크포인트 ${(s['checkpoints'] as List?)?.join(',') ?? '-'}\n판매점 ${s['stores_total']} · 인터넷 1등 ${s['winners_internet']}건 제외',
    regionTab: 0,
  ));
  final rate = (rep['same_direction_rate'] as num?)?.toDouble();
  items.add(_BriefingItem(
    dot: rate != null && rate > 0.6 ? '🟢' : '🟡', dotColor: rate != null && rate > 0.6 ? Colors.green : Colors.orange,
    priority: rate != null && rate > 0.6 ? '좋은 변화' : '관찰 필요',
    title: '지역 간 공간전이: 재현율 ${rate == null ? '-' : '${(rate * 100).toStringAsFixed(0)}%'} (무작위 50%)',
    plain: rate == null
        ? '마스터, 아직 순방향으로 20회 이상 검증된 지역 전이 후보가 없습니다.'
        : '마스터, 과거에 강하게 보였던 지역 전이 ${rep['tested_n20']}건 중 이후 회차에서 같은 방향으로 나타난 것은 ${rep['same_direction']}건입니다. '
            '${rate > 0.6 ? '무작위보다 높은 재현율입니다.' : '무작위(50%)와 구분되지 않아, 지역 간 당첨 "이동"은 우연한 패턴으로 판단됩니다.'}',
    regionTab: 2,
  ));
  if (r.passed.isNotEmpty) {
    final top = r.passed.take(3).map((h) => h['kind'] == 'emerging_store'
        ? '신흥 명당 지속성(${h['discovered_round']}회 기준)'
        : '${_rl(h['from_region'] as String?)}→${_rl(h['to_region'] as String?)} +${h['horizon']}회').join(', ');
    final live = r.passed.where((h) => h['live_eligible'] == true).length;
    items.add(_BriefingItem(
      dot: '🔵', dotColor: Colors.blue, priority: '검증 통과',
      title: '검증 통과 가설 ${r.passed.length}건 (실전 반영 가능 $live건)',
      plain: '마스터, 순방향 검증을 통과한 가설은 $top 입니다. '
          '${live == 0 ? '다만 판매량 미보정 유형이라 실전 판매점 확률 근거로는 쓰지 않습니다.' : '실전 반영 가능 가설은 추천 판매점 점수에 반영됩니다.'}',
      regionTab: 2,
    ));
  }
  if (r.risingRegions.isNotEmpty) {
    items.add(_BriefingItem(
      dot: '🟡', dotColor: Colors.orange, priority: '지역 변화',
      title: '최근 1등이 늘어난 지역: ${r.risingRegions.take(3).map((s) => _rl(s['region_id'] as String)).join(', ')}',
      plain: '마스터, ${r.risingRegions.take(3).map((s) => '${_rl(s['region_id'] as String)}(최근 50회 ${(((s['recent50_rate'] as num?) ?? 0) * 100).toStringAsFixed(1)}%, 추세 z=${((s['trend_z'] as num?) ?? 0).toStringAsFixed(1)})').join(', ')}에서 최근 100회 1등 비율이 이전보다 유의하게 높아졌습니다. '
          '판매량 증가 가능성을 먼저 의심해야 하며 앞으로의 당첨을 보장하지 않습니다.',
      regionTab: 1, regionId: r.risingRegions.first['region_id'] as String?,
    ));
  }
  if (r.emergingStores.isNotEmpty) {
    items.add(_BriefingItem(
      dot: '🔵', dotColor: Colors.purple, priority: '신흥 명당',
      title: '신흥 명당 후보 ${r.emergingStores.length}곳',
      plain: '마스터, ${r.emergingStores.take(3).map((s) => '${s['store_name']}(${_rl(s['region_id'] as String?)}, 최근 100회 1등 ${s['recent100_first']}회)').join(', ')} 등이 최근 급증했습니다. '
          '${r.emergingLatest == null ? '' : '신흥 명당 지속성 검증(${r.emergingLatest!['discovered_round']}회 기준)은 "${r.emergingLatest!['status']}" 입니다. '}'
          '신규·인기 판매점의 판매량 증가로 설명될 수 있습니다.',
      regionTab: 4,
    ));
  }
  if (r.cycleLatest != null) {
    final c = r.cycleLatest!;
    items.add(_BriefingItem(
      dot: '⚪', dotColor: Colors.grey, priority: '주기 연구',
      title: '유명 명당 주기 예측: ${c['status'] == 'passed' ? '검증 통과' : c['status'] == 'weakened' ? '약화' : c['status'] == 'rejected' ? '기각' : '연구 중'}',
      plain: '마스터, 1등 4회 이상 판매점 ${c['test_n']}곳의 다음 1등이 평균 간격 창에 온 경우는 ${c['test_k']}곳(기대 ${(((c['test_base'] as num?) ?? 0) * 100).toStringAsFixed(0)}%)입니다. '
          '당첨 간격으로 다음 당첨 회차를 맞히는 근거는 확인되지 않았습니다.',
      regionTab: 3,
    ));
  }
  items.add(const _BriefingItem(
    dot: '⚪', dotColor: Colors.grey, priority: '한계',
    title: '판매량 미보정 · 데이터 한계',
    plain: '마스터, 판매점별 판매량 자료가 없어 지역·판매점의 당첨 빈도는 판매량 차이를 그대로 반영합니다. '
        '어떤 결과도 복권 한 장당 당첨확률이 높다는 근거가 아니며, 추천 판매점은 이동 편의와 과거 이력 참고용입니다.',
    regionTab: 0,
  ));
  return items;
}

// ── 브리핑 안건 생성 로직 ──────────────────────────────────────────
List<_BriefingItem> _generateItems(_BriefingData d) {
  final items = <_BriefingItem>[];

  // 엔진 처리 중
  if (d.isProcessing) {
    items.add(_BriefingItem(
      dot: '🔵', dotColor: Colors.blue, priority: '진행 중',
      title: '${d.latestRound}회 데이터 분석 중',
      plain: '현재 새 회차 데이터를 처리하고 있습니다. 완료되면 브리핑이 갱신됩니다.',
    ));
    return items;
  }

  // ── 예측 연구 (엔진 브리핑에 통합) ──────────────────────────
  final rs = ResearchScheduler.instance.status.value;
  if (rs.isRunning) {
    items.add(_BriefingItem(
      dot: '🔵', dotColor: Colors.blue, priority: '진행 중',
      title: '예측 연구 ${rs.label}',
      plain: rs.message,
      techDetail: '단계: ${rs.phase.name} · 대상 ${rs.targetRound}회',
    ));
  }
  if (d.registryTarget > 0) {
    items.add(_BriefingItem(
      dot: d.registryRegistered >= 3 ? '🟢' : '🟡',
      dotColor: d.registryRegistered >= 3 ? Colors.green : Colors.orange,
      priority: d.registryRegistered >= 3 ? '좋은 변화' : '관찰 필요',
      title: '${d.registryTarget}회 사전 예측 ${d.registryRegistered}종 등록·잠금',
      plain: d.registryRegistered >= 3
          ? '번호예측·구매예측·무작위 대조군 예측이 판매 마감 전 등록돼 잠겼습니다. 추첨 후 자동 채점되며, 누적 유효 채점 ${d.registryVerifiedRounds}회차입니다.'
          : '사전 등록이 ${d.registryRegistered}종만 되어 있습니다. 앱을 열면 자동 등록됩니다.',
      techDetail: 'research_predictions · target=${d.registryTarget} · verified rounds=${d.registryVerifiedRounds}',
    ));
  }
  if (d.replay != null) {
    final post = Map<String, dynamic>.from(d.replay!['post_accept'] as Map? ?? {});
    final z = (post['z'] as num?)?.toDouble();
    final n = (post['n'] as num?)?.toInt() ?? 0;
    final rate = (post['rate'] as num?)?.toDouble();
    final base = (post['baseline'] as num?)?.toDouble();
    final good = z != null && z > 1.96;
    items.add(_BriefingItem(
      dot: good ? '🟢' : '🟡', dotColor: good ? Colors.green : Colors.orange,
      priority: good ? '좋은 변화' : '관찰 필요',
      title: '가설 순차 재현 ${d.replay!['start_round']}→${d.replay!['end_round']}회: 채택 후 적중 ${rate == null ? '-' : '${(rate * 100).toStringAsFixed(1)}%'}',
      plain: n == 0
          ? '재현에서 채택 단계에 도달한 가설이 없거나 채택 후 검증이 아직 없습니다. 가설 규칙이 과거 ${d.replay!['rounds_replayed']}회차에서 실전 수준의 적중을 만들지 못했다는 뜻입니다.'
          : '과거를 회차 순서대로 재현했을 때, 채택된 가설이 그 이후 ${n}회 검증에서 ${(rate! * 100).toStringAsFixed(1)}% 적중(무작위 기준 ${((base ?? 0) * 100).toStringAsFixed(1)}%)했습니다. '
              '${good ? '무작위보다 유의하게 높습니다.' : '무작위와 통계적으로 구분되지 않습니다.'}',
      techDetail: '가설 ${d.replay!['hypotheses_total']}개 · 채택 경험 ${d.replay!['ever_accepted']}개 · Holm 유의 ${d.replay!['significant_holm']}개 · post z=${z?.toStringAsFixed(2) ?? '-'}',
    ));
  }
  if (!d.mcBaselineOk || d.mcQueued > 0) {
    items.add(_BriefingItem(
      dot: '🟡', dotColor: Colors.orange, priority: '관찰 필요',
      title: !d.mcBaselineOk ? 'Monte Carlo 기준값 미생성' : 'Monte Carlo 대기 ${d.mcQueued}건',
      plain: !d.mcBaselineOk
          ? '랜덤 대조 기준값이 없어 어떤 가설도 Gate를 통과할 수 없습니다. 시뮬레이션 탭 진입 시 자동 생성됩니다.'
          : '가설 Random Control ${d.mcQueued}건이 대기 중입니다. 시뮬레이션 탭 진입 시 처리됩니다.',
      techDetail: 'rpa_mc_baseline ok=${d.mcBaselineOk} · queued=${d.mcQueued} · verified=${d.mcVerified}',
    ));
  } else if (d.mcVerified > 0) {
    items.add(_BriefingItem(
      dot: '⚪', dotColor: Colors.grey, priority: '참고',
      title: 'Monte Carlo 검증 완료 가설 ${d.mcVerified}건',
      plain: '가설 ${d.mcVerified}건이 랜덤 대조(이항검정)를 거쳤습니다.',
    ));
  }
  if (d.researchFreq != null) {
    items.add(_BriefingItem(
      dot: '⚪', dotColor: Colors.grey, priority: '참고',
      title: '번호별 출현 빈도 검정',
      plain: d.researchFreq!,
    ));
  }
  if (d.purchaseStatus != null) {
    items.add(_BriefingItem(
      dot: '⚪', dotColor: Colors.grey, priority: '참고',
      title: '구매예측 모델: ${d.purchaseStatus}',
      plain: '마스터, 구매예측은 당첨 확률이 아니라 다른 구매자와 번호가 겹칠 위험을 줄이는 기능입니다. '
          '회차별 판매액·4등 당첨자 수로 순방향 검증을 통과했을 때만 번호를 제공하며, 실패하면 휴리스틱으로 대체하지 않고 제공하지 않습니다.',
    ));
  }
  if (d.region != null) items.addAll(_regionItems(d.region!));
  if (d.mndBriefing != null && d.mndBriefing!.isNotEmpty) {
    items.add(_BriefingItem(
      dot: '⚪', dotColor: Colors.grey, priority: '참고',
      title: '명당 연구소 브리핑 (${d.mndBriefingRound}회)',
      plain: d.mndBriefing!,
    ));
  }

  // 보정 효과 이상
  if (d.avgCorrEffect != null) {
    if (d.avgCorrEffect! < -0.015) {
      items.add(_BriefingItem(
        dot: '🔴', dotColor: Colors.red, priority: '중요',
        title: '보정이 오히려 성능을 떨어뜨리고 있습니다',
        plain: '최근 10회 평균으로 보면, 보정 규칙을 적용했을 때 이론 예측보다 결과가 나빠지고 있습니다. '
            '보정 규칙을 점검할 필요가 있습니다.',
        techDetail: '최근 보정 효과 평균: ${(d.avgCorrEffect! * 100).toStringAsFixed(2)}pp\n'
            '이론 점수: ${d.avgTheoryScore != null ? "${(d.avgTheoryScore! * 100).toStringAsFixed(1)}%" : "없음"}\n'
            '보정 점수: ${d.avgCorrScore != null ? "${(d.avgCorrScore! * 100).toStringAsFixed(1)}%" : "없음"}',
      ));
    } else if (d.avgCorrEffect! > 0.015) {
      items.add(_BriefingItem(
        dot: '🟢', dotColor: Colors.green, priority: '좋은 변화',
        title: '보정 규칙이 효과를 내고 있습니다',
        plain: '최근 10회 평균으로 보정 후 예측이 이론보다 개선되고 있습니다.',
        techDetail: '최근 보정 효과 평균: +${(d.avgCorrEffect! * 100).toStringAsFixed(2)}pp\n'
            '이론 점수: ${d.avgTheoryScore != null ? "${(d.avgTheoryScore! * 100).toStringAsFixed(1)}%" : "없음"}\n'
            '보정 점수: ${d.avgCorrScore != null ? "${(d.avgCorrScore! * 100).toStringAsFixed(1)}%" : "없음"}',
      ));
    }
  }

  // 채택된 가설
  if (d.acceptedHyp > 0) {
    items.add(_BriefingItem(
      dot: '🟢', dotColor: Colors.green, priority: '좋은 변화',
      title: '실전 반영 가설 ${d.acceptedHyp}건 활성',
      plain: '${d.acceptedHyp}건의 가설이 충분한 검증을 거쳐 현재 예측에 반영되고 있습니다.',
      techDetail: '채택(accepted) 가설: ${d.acceptedHyp}건\n전체 활성 가설: ${d.totalActive}건',
    ));
  }

  // 최근 신규 가설
  if (d.recentNewHyp > 0) {
    items.add(_BriefingItem(
      dot: '🔵', dotColor: Colors.blue, priority: '새로운 발견',
      title: '최근 새 가설 ${d.recentNewHyp}건 발견',
      plain: '${d.recentNewHyp}건의 새로운 패턴 후보가 발견됐습니다. '
          '아직 관찰 단계이므로 바로 예측에 반영되지는 않습니다.',
      techDetail: '최근 2회차 이내 신규: ${d.recentNewHyp}건\n관찰중: ${d.hypCounts["observing"] ?? 0}건',
    ));
  }

  // 검증 중인 가설 진행 상황
  final validating = (d.hypCounts['validating'] ?? 0) + (d.hypCounts['developing'] ?? 0);
  if (validating > 0) {
    items.add(_BriefingItem(
      dot: '🟡', dotColor: Colors.orange, priority: '관찰 필요',
      title: '검증 중인 가설 $validating건',
      plain: '$validating건의 가설이 실전 채택 기준 심사 중입니다. '
          '앞으로 몇 회차 안에 채택 또는 약화 판정이 납니다.',
      techDetail: '검증중(validating): ${d.hypCounts["validating"] ?? 0}건\n'
          '발전중(developing): ${d.hypCounts["developing"] ?? 0}건',
    ));
  }

  // 약화된 가설
  if (d.weakenedHyp > 0) {
    items.add(_BriefingItem(
      dot: '🟡', dotColor: Colors.orange, priority: '관찰 필요',
      title: '성능이 떨어진 가설 ${d.weakenedHyp}건',
      plain: '${d.weakenedHyp}건의 가설이 최근 검증에서 기준을 밑돌고 있습니다. '
          '계속 실패하면 자동으로 폐기됩니다.',
      techDetail: '약화(weakened): ${d.weakenedHyp}건',
    ));
  }

  // Joint 패턴
  if (d.jointPatterns > 0) {
    final accStr = d.jointAccuracy != null
        ? ' (검증 정확도 ${(d.jointAccuracy! * 100).toStringAsFixed(1)}%)'
        : ' (아직 검증 전)';
    items.add(_BriefingItem(
      dot: '⚪', dotColor: Colors.grey, priority: '참고',
      title: 'Joint 번호×지역 패턴 ${d.jointPatterns}개 분석됨',
      plain: '번호와 판매 지역 사이의 관계를 ${d.jointPatterns}개 분석했습니다$accStr. '
          '표본이 적은 패턴이 많아 높은 수치만 믿으면 과대평가될 수 있습니다.',
      techDetail: 'nrPatternCount: ${d.jointPatterns}\n'
          'jointAccuracy: ${d.jointAccuracy != null ? "${(d.jointAccuracy! * 100).toStringAsFixed(1)}%" : "null"}',
    ));
  }

  // 폐기된 가설 (참고)
  if (d.rejectedHyp > 0) {
    items.add(_BriefingItem(
      dot: '⚪', dotColor: Colors.grey, priority: '참고',
      title: '폐기된 가설 ${d.rejectedHyp}건 누적',
      plain: '${d.rejectedHyp}건의 가설이 반복 검증을 통과하지 못해 폐기됐습니다. '
          '같은 패턴이 재발견되지 않도록 기억하고 있습니다.',
      techDetail: '폐기(rejected): ${d.rejectedHyp}건',
    ));
  }

  if (items.isEmpty) {
    items.add(_BriefingItem(
      dot: '⚪', dotColor: Colors.grey, priority: '참고',
      title: '현재 주목할 연구 결과가 없습니다',
      plain: '새 회차 데이터가 처리되면 가설 연구가 자동으로 진행됩니다.',
    ));
  }

  return items;
}

// ══════════════════════════════════════════════════════════
// 엔진 브리핑 직원 카드
// ══════════════════════════════════════════════════════════

class _BriefingCard extends StatefulWidget {
  const _BriefingCard({required this.onDetail});
  final VoidCallback onDetail;

  @override
  State<_BriefingCard> createState() => _BriefingCardState();
}

class _BriefingCardState extends State<_BriefingCard> {
  static const _staffName = '엔진 브리핑'; // ← 이름 변경 포인트

  _BriefingData? _data;
  bool _loading = true;
  ResearchPhase? _lastPhase;

  @override
  void initState() {
    super.initState();
    _load();
    // 연구 단계가 바뀌면(연구중 → 예측완료 → 완료) 브리핑을 다시 읽는다
    ResearchScheduler.instance.status.addListener(_onResearchStatus);
  }

  @override
  void dispose() {
    ResearchScheduler.instance.status.removeListener(_onResearchStatus);
    super.dispose();
  }

  void _onResearchStatus() {
    final p = ResearchScheduler.instance.status.value.phase;
    if (p != _lastPhase) {
      _lastPhase = p;
      if (mounted) setState(() {});
      if (p == ResearchPhase.done || p == ResearchPhase.predicted) _load();
    }
  }

  Future<void> _load() async {
    try {
      final db = Supabase.instance.client;
      final results = await Future.wait<dynamic>([
        db.from('rpa_round_gate').select('round, engine_status')
            .order('round', ascending: false).limit(1).maybeSingle(),
        db.from('rpa_hypotheses_v3').select('status, created_round'),
        db.from('rpa_round_scores')
            .select('correction_effect, theory_score, correction_score')
            .order('target_round', ascending: false).limit(10),
        db.from('rpa_joint_model_state').select('nr_pattern_count, joint_model_accuracy')
            .eq('id', 1).maybeSingle(),
        db.from('rpa_hypothesis_events').select('event_type, new_status, summary')
            .order('created_at', ascending: false).limit(20),
      ]);

      final gate = results[0] as Map<String, dynamic>?;
      final round = gate?['round'] as int? ?? 0;
      final engineStatus = gate?['engine_status'] as String? ?? '';

      final hypRows = results[1] as List;
      final counts = <String, int>{};
      int recentNew = 0;
      for (final r in hypRows) {
        final s = r['status'] as String? ?? '';
        counts[s] = (counts[s] ?? 0) + 1;
        if ((r['created_round'] as int? ?? 0) >= round - 1 &&
            !['rejected', 'combined', 'weakened'].contains(s)) recentNew++;
      }

      final scoreRows = results[2] as List;
      double? avgEffect, avgTheory, avgCorr;
      if (scoreRows.isNotEmpty) {
        avgEffect = scoreRows.fold<double>(0, (s, r) =>
            s + ((r['correction_effect'] as num?) ?? 0).toDouble()) / scoreRows.length;
        avgTheory = scoreRows.fold<double>(0, (s, r) =>
            s + ((r['theory_score'] as num?) ?? 0).toDouble()) / scoreRows.length;
        avgCorr = scoreRows.fold<double>(0, (s, r) =>
            s + ((r['correction_score'] as num?) ?? 0).toDouble()) / scoreRows.length;
      }

      final joint = results[3] as Map<String, dynamic>?;
      final jointPatterns = joint?['nr_pattern_count'] as int? ?? 0;
      final jointAcc = (joint?['joint_model_accuracy'] as num?)?.toDouble();

      final events = (results[4] as List)
          .map((e) => e as Map<String, dynamic>).toList();

      // ── 예측 연구·명당·MC (각각 실패해도 브리핑은 유지) ──
      String? mndText; int mndRound = 0;
      try {
        final m = await db.from('mnd_briefings').select('round, briefing_text')
            .order('round', ascending: false).limit(1).maybeSingle();
        if (m != null) {
          mndRound = m['round'] as int? ?? 0;
          final full = (m['briefing_text'] as String? ?? '').trim().replaceAll('주인님', '마스터');
          final paras = full.split('\n\n').where((s) => s.trim().isNotEmpty).toList();
          mndText = paras.length > 1 ? paras[1].trim() : full;
          if (mndText.length > 220) mndText = '${mndText.substring(0, 220)}…';
        }
      } catch (_) {}
      String? freqText, purchaseText; Map<String, dynamic>? replay;
      try {
        final rr = await db.from('research_results').select('research_type, payload')
            .order('created_at', ascending: false).limit(40);
        for (final r in List<Map<String, dynamic>>.from(rr as List)) {
          final p = Map<String, dynamic>.from(r['payload'] as Map? ?? {});
          switch (r['research_type']) {
            case 'number_frequency': freqText ??= p['conclusion'] as String?; break;
            case 'purchase_model': purchaseText ??= p['validation_status'] as String?; break;
            case 'hypothesis_replay': replay ??= p; break;
          }
        }
      } catch (_) {}
      int regTarget = 0, regCount = 0, regVerified = 0;
      try {
        final pr = await db.from('research_predictions').select('target_round, status')
            .order('target_round', ascending: false).limit(300);
        final list = List<Map<String, dynamic>>.from(pr as List);
        if (list.isNotEmpty) {
          regTarget = list.first['target_round'] as int;
          regCount = list.where((r) => r['target_round'] == regTarget).length;
          regVerified = list.where((r) => r['status'] == 'verified').map((r) => r['target_round']).toSet().length;
        }
      } catch (_) {}
      _RegionBrief? regionBrief;
      try {
        final rr = await db.from('research_results').select('payload,training_end_round')
            .eq('research_type', 'region_research').eq('model_version', 'rg-1.0')
            .order('training_end_round', ascending: false).limit(1);
        if ((rr as List).isNotEmpty) {
          final summary = Map<String, dynamic>.from((rr.first as Map)['payload'] as Map);
          final rnd = (summary['latest_round'] as num?)?.toInt() ?? 0;
          final run = await db.from('research_region_runs').select('status').eq('model_version', 'rg-1.0')
              .eq('training_end_round', rnd).maybeSingle();
          final passed = List<Map<String, dynamic>>.from(await db.from('research_region_hypotheses')
              .select('kind,from_region,to_region,horizon,discovered_round,live_eligible,status')
              .eq('model_version', 'rg-1.0').inFilter('status', ['passed', 'combined'])
              .order('discovered_round', ascending: false).limit(20) as List);
          final rising = List<Map<String, dynamic>>.from(await db.from('research_region_stats')
              .select('region_id,recent50_rate,trend_z').eq('model_version', 'rg-1.0').eq('training_end_round', rnd)
              .gte('trend_z', 2.0).order('trend_z', ascending: false).limit(5) as List);
          final emerging = List<Map<String, dynamic>>.from(await db.from('research_store_cycles')
              .select('store_name,region_id,recent100_first,emerging_p').eq('model_version', 'rg-1.0')
              .eq('training_end_round', rnd).eq('class', 'emerging').order('emerging_p').limit(10) as List);
          Map<String, dynamic>? latestOf(String kind) {
            final l = passed.where((h) => h['kind'] == kind).toList();
            return l.isEmpty ? null : l.first;
          }
          final cyc = await db.from('research_region_hypotheses').select('status,test_n,test_k,test_base,discovered_round')
              .eq('model_version', 'rg-1.0').eq('kind', 'store_cycle').order('discovered_round', ascending: false).limit(1);
          final emg = await db.from('research_region_hypotheses').select('status,discovered_round')
              .eq('model_version', 'rg-1.0').eq('kind', 'emerging_store').order('discovered_round', ascending: false).limit(1);
          regionBrief = _RegionBrief(
            round: rnd, runStatus: (run?['status'] as String?) ?? 'unknown', summary: summary, passed: passed,
            risingRegions: rising, emergingStores: emerging,
            cycleLatest: (cyc as List).isEmpty ? null : Map<String, dynamic>.from(cyc.first as Map),
            emergingLatest: (emg as List).isEmpty ? latestOf('emerging_store') : Map<String, dynamic>.from(emg.first as Map),
          );
        }
      } catch (_) {} // 테이블 미적용·연구 미실행이면 지역 안건 생략

      bool mcOk = false; int mcQueued = 0, mcVerified = 0;
      try {
        final st = await MonteCarloEngine.instance.getStats();
        mcOk = st.baseline != null && !st.baseline!.isEmpty;
        mcQueued = st.queued + st.running;
        mcVerified = st.totalHypothesesVerified;
      } catch (_) {}

      if (mounted) setState(() {
        _data = _BriefingData(
          latestRound: round, engineStatus: engineStatus, hypCounts: counts,
          recentNewHyp: recentNew, acceptedHyp: counts['accepted'] ?? 0,
          weakenedHyp: counts['weakened'] ?? 0, rejectedHyp: counts['rejected'] ?? 0,
          avgCorrEffect: avgEffect, avgTheoryScore: avgTheory, avgCorrScore: avgCorr,
          jointPatterns: jointPatterns, jointAccuracy: jointAcc, recentEvents: events,
          mndBriefing: mndText, mndBriefingRound: mndRound,
          researchFreq: freqText, purchaseStatus: purchaseText, replay: replay,
          registryTarget: regTarget, registryRegistered: regCount, registryVerifiedRounds: regVerified,
          mcBaselineOk: mcOk, mcQueued: mcQueued, mcVerified: mcVerified,
          region: regionBrief,
        );
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final items = d != null ? _generateItems(d) : <_BriefingItem>[];
    final topItem = items.isNotEmpty ? items.first : null;

    return GestureDetector(
      onTap: () {
        if (d != null) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => BriefingDetailScreen(data: d),
          ));
        } else {
          widget.onDetail();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F0FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD1C4E9)),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 직원 캐릭터
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7B2FF7), Color(0xFF4A00E0)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [BoxShadow(
                color: const Color(0xFF7B2FF7).withOpacity(0.3),
                blurRadius: 8, offset: const Offset(0, 3),
              )],
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text(_staffName,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                      color: Color(0xFF4527A0))),
              const SizedBox(width: 6),
              if (d != null && d.latestRound > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE7F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${d.latestRound}회 기준',
                      style: const TextStyle(fontSize: 9, color: Color(0xFF6A1B9A),
                          fontWeight: FontWeight.w600)),
                ),
              const SizedBox(width: 6),
              // 엔진 연구 상태 3단계: 연구중 / 연구중(다음회차 예측완료) / 완료
              ValueListenableBuilder<ResearchStatus>(
                valueListenable: ResearchScheduler.instance.status,
                builder: (context, s, _) {
                  final running = s.isRunning;
                  final color = running ? const Color(0xFFE65100) : const Color(0xFF00796B);
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    if (running) const SizedBox(width: 10, height: 10,
                        child: CircularProgressIndicator(strokeWidth: 1.6, color: Color(0xFFE65100))),
                    if (running) const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.45)),
                      ),
                      child: Text(s.phase == ResearchPhase.idle ? '연구중' : s.label,
                          style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w800)),
                    ),
                  ]);
                },
              ),
            ]),
            const SizedBox(height: 6),
            // 주요 브리핑: 엔진 추천번호 · 구매예측 번호 · 이번 주 추천 명당
            const MasterBriefingCompact(),
            const SizedBox(height: 8),
            if (_loading)
              const Text('연구 결과 읽는 중...',
                  style: TextStyle(fontSize: 12, color: Color(0xFF888888)))
            else if (topItem != null) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(topItem.dot, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Expanded(child: Text(topItem.plain,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF333333),
                        height: 1.45),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
              if (items.length > 1) ...[
                const SizedBox(height: 6),
                Text('외 ${items.length - 1}건 더 보기',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9575CD),
                        fontWeight: FontWeight.w600)),
              ],
            ],
            const SizedBox(height: 8),
            if (d != null) _buildCountRow(d),
          ])),
          const SizedBox(width: 4),
          const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(height: 4),
            Icon(Icons.chevron_right_rounded, color: Color(0xFF9E9E9E), size: 20),
          ]),
        ]),
      ),
    );
  }

  Widget _buildCountRow(_BriefingData d) {
    final items = [
      ('연구중', (d.hypCounts['discovered'] ?? 0) + (d.hypCounts['observing'] ?? 0), const Color(0xFF42A5F5)),
      ('검증', (d.hypCounts['validating'] ?? 0) + (d.hypCounts['developing'] ?? 0), const Color(0xFF7E57C2)),
      ('채택', d.acceptedHyp, const Color(0xFF4CAF50)),
    ];
    return Row(children: [
      for (int i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        _dot(items[i].$1, items[i].$2, items[i].$3),
      ],
    ]);
  }

  Widget _dot(String label, int count, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 7, height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 3),
      Text('$label $count', style: TextStyle(fontSize: 10,
          color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
    ],
  );
}

// ══════════════════════════════════════════════════════════
// 상세 브리핑 화면
// ══════════════════════════════════════════════════════════

class BriefingDetailScreen extends StatelessWidget {
  final _BriefingData data;
  const BriefingDetailScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final items = _generateItems(data);
    // 탭: 이번 회차 브리핑 · 지난 회차 검증(회차별 보라색 박스)
    // 이번 회차 브리핑 맨 위 회차 검증: 토·일 펼침 → 월·화 보라색 박스 → 수요일부터 '지난 회차 검증' 탭에만
    return DefaultTabController(
      length: 4,
      child: Scaffold(
      backgroundColor: const Color(0xFFF8F5FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4527A0),
        foregroundColor: Colors.white,
        title: const Text('엔진 브리핑', style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
        bottom: const TabBar(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Color(0xFFFFC107),
          labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [Tab(text: '이번 회차 브리핑'), Tab(text: '지난 회차 검증'), Tab(text: '연금복권'), Tab(text: '스피또')],
        ),
      ),
      body: TabBarView(children: [
        ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ManualRecommendCard(),
          const RoundDebriefTop(),
          _buildHeader(context),
          const SizedBox(height: 16),
          const MasterBriefingSection(),
          const SizedBox(height: 16),
          const AgentBriefingSection(),
          const SizedBox(height: 16),
          const EngineReviewBriefingCard(),
          const SizedBox(height: 20),
          _buildSummaryRow(),
          const SizedBox(height: 20),
          const Text('안건 목록',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                  color: Color(0xFF4527A0))),
          const SizedBox(height: 8),
          ...items.asMap().entries.map((e) =>
              _BriefingItemCard(index: e.key + 1, item: e.value)),
          const SizedBox(height: 20),
          _buildTechSummary(),
          const SizedBox(height: 32),
        ],
      ),
        const RoundDebriefHistoryView(),
        const PensionBriefingView(),
        const SpeettoBriefingView(),
      ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF7B2FF7), Color(0xFF4A00E0)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(26),
        ),
        child: const Icon(Icons.person_rounded, color: Colors.white, size: 30),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('마스터, 연구 결과를 보고드리겠습니다.',
            style: TextStyle(color: Colors.white, fontSize: 14,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${data.latestRound}회차까지 분석한 연구 현황입니다.',
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
        const SizedBox(height: 10),
        // 지방장보고 — 지방장별 지난 회차 추천 채점 · 다음 회차 변경점
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('agent_report_button'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF4527A0),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AgentReportScreen())),
            icon: const Icon(Icons.groups_2_rounded, size: 18),
            label: const Text('지방장보고', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ])),
    ]),
  );

  Widget _buildSummaryRow() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFEDE7F6)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('연구 현황 요약',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: Color(0xFF4527A0))),
      const SizedBox(height: 10),
      Row(children: [
        _summaryChip('발견/관찰',
            (data.hypCounts['discovered'] ?? 0) + (data.hypCounts['observing'] ?? 0),
            const Color(0xFF42A5F5)),
        const SizedBox(width: 8),
        _summaryChip('검증/발전',
            (data.hypCounts['validating'] ?? 0) + (data.hypCounts['developing'] ?? 0),
            const Color(0xFF7E57C2)),
        const SizedBox(width: 8),
        _summaryChip('채택', data.acceptedHyp, const Color(0xFF4CAF50)),
        const SizedBox(width: 8),
        _summaryChip('폐기', data.rejectedHyp, const Color(0xFF9E9E9E)),
      ]),
    ]),
  );

  Widget _summaryChip(String label, int count, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
            color: color)),
        Text(label, style: TextStyle(fontSize: 9, color: color,
            fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  Widget _buildTechSummary() {
    if (data.avgCorrEffect == null && data.avgTheoryScore == null) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.analytics_outlined, size: 14, color: Color(0xFF888888)),
          SizedBox(width: 4),
          Text('엔진 성능 (최근 10회 평균)',
              style: TextStyle(fontSize: 11, color: Color(0xFF888888),
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        if (data.avgTheoryScore != null)
          _techRow('이론 점수', '${(data.avgTheoryScore! * 100).toStringAsFixed(1)}%'),
        if (data.avgCorrScore != null)
          _techRow('보정 점수', '${(data.avgCorrScore! * 100).toStringAsFixed(1)}%'),
        if (data.avgCorrEffect != null)
          _techRow('보정 효과',
              '${data.avgCorrEffect! >= 0 ? "+" : ""}${(data.avgCorrEffect! * 100).toStringAsFixed(2)}pp',
              color: data.avgCorrEffect! >= 0 ? Colors.green : Colors.red),
        if (data.jointPatterns > 0)
          _techRow('Joint 패턴', '${data.jointPatterns}개 분석됨'),
        if (data.jointAccuracy != null)
          _techRow('Joint 정확도', '${(data.jointAccuracy! * 100).toStringAsFixed(1)}%'),
      ]),
    );
  }

  Widget _techRow(String label, String value, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF666666)))),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
          color: color ?? const Color(0xFF333333))),
    ]),
  );
}

class _BriefingItemCard extends StatefulWidget {
  final int index;
  final _BriefingItem item;
  const _BriefingItemCard({required this.index, required this.item});

  @override
  State<_BriefingItemCard> createState() => _BriefingItemCardState();
}

class _BriefingItemCardState extends State<_BriefingItemCard> {
  bool _showTech = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final card = _buildCard(item);
    if (item.regionTab == null) return card;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => AdminRegionResearchScreen(initialTab: item.regionTab!, initialRegion: item.regionId))),
      child: card,
    );
  }

  Widget _buildCard(_BriefingItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: item.dotColor.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(item.dot, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: item.dotColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(item.priority,
                    style: TextStyle(fontSize: 10, color: item.dotColor,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Text('안건 ${widget.index}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFFBDBDBD))),
            ]),
            const SizedBox(height: 8),
            Text(item.title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A))),
            const SizedBox(height: 6),
            Text(item.plain,
                style: const TextStyle(fontSize: 12, color: Color(0xFF555555),
                    height: 1.5)),
            if (item.techDetail != null) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _showTech = !_showTech),
                child: Row(children: [
                  Icon(
                    _showTech ? Icons.expand_less : Icons.expand_more,
                    size: 14, color: const Color(0xFF9E9E9E),
                  ),
                  const SizedBox(width: 4),
                  Text(_showTech ? '근거 데이터 숨기기' : '근거 데이터 보기',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E),
                          fontWeight: FontWeight.w600)),
                ]),
              ),
              if (_showTech) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(item.techDetail!,
                      style: const TextStyle(fontSize: 11,
                          color: Color(0xFF666666), fontFamily: 'monospace',
                          height: 1.6)),
                ),
              ],
            ],
          ]),
        ),
      ]),
    );
  }
}
