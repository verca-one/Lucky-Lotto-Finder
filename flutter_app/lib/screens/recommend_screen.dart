import 'package:flutter/material.dart';
import '../services/admin_gate.dart';
import 'random_number_screen.dart';
import 'ai_number_screen.dart';
import 'golden_wave_screen.dart';
import 'saju_number_screen.dart';
import 'number_meaning_screen.dart';
import 'ac_value_screen.dart';
import 'zone_balance_screen.dart';
import 'tax_calculator_screen.dart';
import 'recommend_numbers_content.dart';
import 'random_recommend_content.dart';
import '../models/lotto_winning_number.dart';
import '../services/research/research_scheduler.dart';
import '../services/supabase_service.dart';

/// 추천 탭 '번호 추천' 메뉴 항목
class RecommendMenuItem {
  final String sub; // _currentSub 값
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  const RecommendMenuItem(this.sub, this.icon, this.iconColor, this.title, this.subtitle);
}

/// 추천 탭 '번호 추천' 메뉴 — 일반·관리자 모드 동일.
/// '자리별 패턴 분석'·'구매예측'은 추천 탭에 두지 않는다 (관리자 메뉴의 '패턴 분석'·'예측 연구 현황'에만 있음).
/// '번호 추천' 메뉴 (모드 공통). '추천번호' 내용은 모드에 따라 다르다:
///   일반 모드 — 엔진 개입 없는 랜덤 추천 (RandomRecommendContent)
///   관리자 모드(프리미엄) — 랜덤확률분석엔진 최종 추천번호 (RecommendNumbersContent)
const List<RecommendMenuItem> kRecommendNumberMenu = [
  RecommendMenuItem('ai_sub', Icons.auto_awesome, Colors.purple, 'AI 조합번호 생성', 'AI 법칙 기반 번호 추천'),
  RecommendMenuItem('random', Icons.casino, Colors.orange, '나만의 번호 생성', '주사위를 굴려 랜덤 번호 조합'),
  RecommendMenuItem('numbers', Icons.confirmation_number_rounded, Colors.deepPurple, '추천번호', '이번 회차 추천번호'),
  RecommendMenuItem('meaning', Icons.menu_book, Colors.teal, '번호별 의미', '1~45 각 번호의 상징과 법칙 연계'),
];

List<RecommendMenuItem> recommendNumberMenuFor({required bool admin}) => kRecommendNumberMenu;

class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key});

  @override
  State<RecommendScreen> createState() => RecommendScreenState();
}

class RecommendScreenState extends State<RecommendScreen> {
  // null: 메인메뉴, 'tax': 세금계산기, 'ai_sub': AI하위메뉴, ...
  String? _currentSub;

  LottoWinningNumber? _latestRound;
  DateTime?           _loadedAt;

  /// 관리자 모드(프리미엄) 여부 — 탭을 다시 열 때마다 갱신
  bool _isAdmin = false;

  /// '추천번호' 화면을 열 때의 모드 (true = 엔진 추천번호를 보여 주는 중)
  bool _shownEngine = false;

  @override
  void initState() {
    super.initState();
    _loadLatestRound();
    _refreshAdmin();
  }

  @override
  void didUpdateWidget(covariant RecommendScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshAdmin();
  }

  Future<void> _refreshAdmin() async {
    final v = await AdminGate.isAdmin();
    if (!mounted) return;
    if (v != _isAdmin) setState(() => _isAdmin = v);
    // 모드가 바뀌면 열려 있던 '추천번호'는 메뉴로 (일반↔엔진 내용이 섞이지 않게)
    if (_currentSub == 'numbers' && v != _shownEngine) setState(() => _currentSub = null);
  }

  Future<void> _loadLatestRound() async {
    try {
      final list = await SupabaseService.getRecentWinningNumbers(1);
      if (!mounted) return;
      if (list.isNotEmpty) {
        setState(() { _latestRound = list.first; _loadedAt = DateTime.now(); });
      }
    } catch (_) {}
    // 예측 연구: 마감 전 다음 회차 예측 등록·미채점 예측 채점 (세션당 최신 회차 1회)
    ResearchScheduler.instance.runIfNeeded().ignore();
  }

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
    if (_currentSub == 'numbers' && !_isAdmin) {
      return _wrapWithBack(const RandomRecommendContent(), '번호 추천', null);
    }
    if (_currentSub == 'numbers' && _isAdmin) {
      return _wrapWithBack(const RecommendNumbersContent(), '번호 추천', null);
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
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_rounded, size: 26, color: Color(0xFF1565C0)),
                      const SizedBox(width: 8),
                      Text(backLabel, style: const TextStyle(fontSize: 16, color: Color(0xFF333333), fontWeight: FontWeight.w700)),
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
      color: Colors.transparent, // 홈 화면 배경 이미지가 추천 탭에서도 보이도록
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 최신 당첨번호 헤더 ──────────────────────────────
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: _latestRound == null
                  ? _buildHeaderSkeleton()
                  : _buildLatestWinningHeader(_latestRound!),
            ),
            // 메뉴 목록
            Padding(
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
                  for (final (i, m) in recommendNumberMenuFor(admin: _isAdmin).indexed) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _buildMenuCard(
                      icon: m.icon,
                      iconColor: m.iconColor,
                      bgColor: Colors.white,
                      borderColor: const Color(0xFFE8EDF5),
                      title: m.title,
                      subtitle: m.subtitle,
                      onTap: () => setState(() {
                        _currentSub = m.sub;
                        _shownEngine = _isAdmin;
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E)),
    );
  }

  // ── 헤더: 로딩 중 스켈레톤 ────────────────────────────────────
  Widget _buildHeaderSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('최신 당첨번호',
            style: TextStyle(fontSize: 12, color: Colors.white60, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        Row(
          children: List.generate(7, (i) => Container(
            margin: EdgeInsets.only(right: i < 6 ? 6 : 0),
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
          )),
        ),
        const SizedBox(height: 8),
        Container(height: 10, width: 120,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            )),
      ],
    );
  }

  // ── 헤더: 최신 당첨번호 표시 ─────────────────────────────────
  Widget _buildLatestWinningHeader(LottoWinningNumber r) {
    final nums = [...r.numbers]..sort();
    final loadedStr = _loadedAt == null ? '' : _formatLoadedAt(_loadedAt!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${r.round}회 당첨번호',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800,
                    color: Colors.white, letterSpacing: 0.3),
              ),
            ),
            if (loadedStr.isNotEmpty)
              Text(loadedStr,
                  style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ],
        ),
        const SizedBox(height: 6),
        Text(r.drawDate,
            style: const TextStyle(fontSize: 11, color: Colors.white60)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ...nums.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _lottoball(e.value),
            )),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('+', style: TextStyle(color: Colors.white54, fontSize: 18,
                  fontWeight: FontWeight.w300)),
            ),
            _lottoball(r.bonusNumber, bonus: true),
          ],
        ),
      ],
    );
  }

  Color _ballColor(int n) {
    if (n <= 10) return const Color(0xFFFFB300);
    if (n <= 20) return const Color(0xFF42A5F5);
    if (n <= 30) return const Color(0xFFEF5350);
    if (n <= 40) return const Color(0xFF9E9E9E);
    return const Color(0xFF66BB6A);
  }

  Widget _lottoball(int n, {bool bonus = false}) {
    final bg = bonus ? Colors.orange.shade600 : _ballColor(n);
    return Container(
      width: 38, height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: bg.withValues(alpha: 0.45), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Text('$n',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
    );
  }

  String _formatLoadedAt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '방금 업데이트';
    if (diff.inHours < 1)   return '${diff.inMinutes}분 전 업데이트';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')} 업데이트';
  }

  /// AI 조합번호 하위 메뉴
  Widget _buildAiSubMenu() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 뒤로가기 헤더
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _currentSub = null),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_back_rounded, size: 26, color: Color(0xFF1565C0)),
                        const SizedBox(width: 8),
                        const Text('도구', style: TextStyle(fontSize: 16, color: Color(0xFF333333), fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // pig.png 이미지 + 메뉴
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
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
