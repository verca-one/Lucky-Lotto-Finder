import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/supabase_service.dart';

class AdminCouponScreen extends StatefulWidget {
  const AdminCouponScreen({super.key});

  @override
  State<AdminCouponScreen> createState() => _AdminCouponScreenState();
}

class _AdminCouponScreenState extends State<AdminCouponScreen> {
  final _codeController     = TextEditingController();
  final _nameController     = TextEditingController();
  final _maxUsesController  = TextEditingController(text: '1');
  final _customDaysController = TextEditingController();

  bool _isCreating  = false;
  List<Map<String, dynamic>> _coupons = [];
  bool _isLoading   = true;
  bool _expiredExpanded = false;
  bool _isDeletingExpired = false;

  // 앱 선택
  String _targetApp = 'lottery'; // 'lottery' | 'cartdamda' | 'naedon' | 'berwrite' | 'all'

  // 쿠폰 종류 (cartdamda 한정)
  String _couponType = 'duration'; // 'duration' | 'master'

  // 기간 선택 옵션
  String _durationOption = '30'; // '1' | '7' | '30' | '180' | 'custom'
  static const _durationOptions = [
    ('1',      '1일'),
    ('7',      '7일'),
    ('30',     '한달'),
    ('180',    '6개월'),
    ('custom', '직접입력'),
  ];

  // 등록 마감일 (expires_at — 쿠폰 코드 입력 가능 기한)
  String _registrationDeadline = '30days'; // '7days'|'30days'|'90days'|'permanent'
  static const _deadlineOptions = [
    ('7days',    '7일 후'),
    ('30days',   '한달 후'),
    ('90days',   '3개월 후'),
    ('permanent','무기한'),
  ];

  @override
  void initState() {
    super.initState();
    _loadCoupons();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _maxUsesController.dispose();
    _customDaysController.dispose();
    super.dispose();
  }

  Future<void> _loadCoupons() async {
    setState(() => _isLoading = true);
    final coupons = await SupabaseService.getAllCoupons();
    if (!mounted) return;
    setState(() {
      _coupons = coupons;
      _isLoading = false;
    });
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final code = List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
    return '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8, 12)}';
  }

  bool get _showCouponTypeSelector =>
      _targetApp == 'cartdamda' || _targetApp == 'naedon' || _targetApp == 'berwrite' || _targetApp == 'all';

  int? _effectiveDurationDays() {
    if (_targetApp == 'lottery') return null; // 복권명당은 duration_days 미사용
    if (_couponType == 'master')  return null;
    if (_durationOption == 'custom') {
      return int.tryParse(_customDaysController.text.trim());
    }
    return int.tryParse(_durationOption);
  }

  DateTime? _registrationExpiresAt() {
    if (_registrationDeadline == 'permanent') return null;
    final days = switch (_registrationDeadline) {
      '7days'  => 7,
      '30days' => 30,
      '90days' => 90,
      _        => 30,
    };
    return DateTime.now().add(Duration(days: days));
  }

  Future<void> _createCoupon() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _snack('쿠폰 코드를 입력하세요');
      return;
    }

    // 카트담다 기간형: duration_days 필요
    if (_targetApp == 'cartdamda' && _couponType == 'duration') {
      final days = _effectiveDurationDays();
      if (days == null || days <= 0) {
        _snack('혜택 기간(일수)을 입력하세요');
        return;
      }
    }

    final maxUses = int.tryParse(_maxUsesController.text) ?? 1;

    setState(() => _isCreating = true);
    final success = await SupabaseService.createCoupon(
      code:         code,
      type:         'interstitial_removal', // 레거시 호환
      maxUses:      maxUses,
      expiresAt:    _registrationExpiresAt(),
      targetApp:    _targetApp,
      couponName:   _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      couponType:   _showCouponTypeSelector ? _couponType : 'duration',
      benefitType:  'interstitial_ad_free',
      durationDays: _effectiveDurationDays(),
    );
    if (!mounted) return;
    setState(() => _isCreating = false);

    if (success) {
      _snack('쿠폰 생성 완료: $code');
      _codeController.clear();
      _nameController.clear();
      _maxUsesController.text = '1';
      _customDaysController.clear();
      _loadCoupons();
    } else {
      _snack('쿠폰 생성 실패 (중복 코드일 수 있음)');
    }
  }

  Future<void> _toggleActive(String code, bool current) async {
    final ok = await SupabaseService.toggleCouponActive(code, !current);
    if (ok) _loadCoupons();
  }

  Future<void> _deleteCoupon(String code) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('쿠폰 삭제'),
        content: Text('$code\n이 쿠폰을 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await SupabaseService.deleteCoupon(code);
    if (!mounted) return;
    _snack(deleted ? '쿠폰이 삭제되었습니다' : '삭제 실패');
    if (deleted) _loadCoupons();
  }

  Future<void> _deleteAllExpired() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('만료된 쿠폰 모두 삭제'),
        content: const Text('등록기한이 지난 쿠폰을 모두 삭제하시겠습니까?\n'
            '사용 완료 쿠폰은 사용자 혜택 기록을 지키기 위해 지우지 않습니다 (필요하면 하나씩 삭제).\n'
            '이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('모두 삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _isDeletingExpired = true);
    final deleted = await SupabaseService.deleteExpiredCoupons();
    if (!mounted) return;
    setState(() { _isDeletingExpired = false; _expiredExpanded = false; });
    _snack(deleted ? '만료된 쿠폰이 모두 삭제되었습니다' : '삭제 실패');
    if (deleted) _loadCoupons();
  }

  bool _isExpired(Map<String, dynamic> c) {
    final e = c['expires_at'];
    if (e == null) return false;
    return DateTime.now().isAfter(DateTime.parse(e));
  }

  /// 사용 횟수를 다 쓴 쿠폰 (예: 1회용 1/1 사용) — 더 쓸 수 없으므로 만료 쪽으로
  bool _isUsedUp(Map<String, dynamic> c) {
    final used = (c['used_count'] as num?)?.toInt() ?? 0;
    final max = (c['max_uses'] as num?)?.toInt() ?? 1;
    return max > 0 && used >= max;
  }

  bool _isClosed(Map<String, dynamic> c) => _isExpired(c) || _isUsedUp(c);

  String _formatDate(String iso) {
    final d = DateTime.parse(iso);
    return '${d.year}.${d.month.toString().padLeft(2,'0')}.${d.day.toString().padLeft(2,'0')}';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final activeCoupons  = _coupons.where((c) => !_isClosed(c)).toList();
    final expiredCoupons = _coupons.where(_isClosed).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        title: const Text('쿠폰 관리',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _loadCoupons),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── 쿠폰 생성 카드 ──────────────────────────────────────────
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('쿠폰 생성',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    // ── 앱 선택 ──────────────────────────────────────────
                    _sectionBox(
                      label: '적용 대상 앱',
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _appTab('복권명당', 'lottery'),
                              const SizedBox(width: 6),
                              _appTab('카트담다', 'cartdamda'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _appTab('내돈', 'naedon'),
                              const SizedBox(width: 6),
                              _appTab('베르와이트', 'berwrite'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _appTab('전체 앱', 'all'),
                              const SizedBox(width: 6),
                              const Expanded(child: SizedBox()),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── 쿠폰명 ────────────────────────────────────────────
                    TextField(
                      controller: _nameController,
                      decoration: _inputDeco('쿠폰 이름 (선택)', '예: 7일 전면광고 해제 쿠폰'),
                    ),
                    const SizedBox(height: 12),

                    // ── 쿠폰 코드 ─────────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeController,
                            decoration: _inputDeco('쿠폰 코드', 'XXXX-XXXX-XXXX'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _codeController.text = _generateCode(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                          child: const Text('자동생성',
                              style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── 카트담다/내돈/전체앱: 쿠폰 종류 ─────────────────
                    if (_showCouponTypeSelector) ...[
                      _sectionBox(
                        label: '쿠폰 종류',
                        child: Row(
                          children: [
                            _typeToggle('기간형', 'duration'),
                            const SizedBox(width: 8),
                            _typeToggle('마스터 (평생)', 'master'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 기간형이면 혜택 기간 선택
                      if (_couponType == 'duration') ...[
                        _sectionBox(
                          label: '혜택 기간',
                          child: Column(
                            children: [
                              Wrap(
                                spacing: 4,
                                children: _durationOptions.map((opt) {
                                  final (val, lbl) = opt;
                                  return ChoiceChip(
                                    label: Text(lbl),
                                    selected: _durationOption == val,
                                    onSelected: (_) => setState(() {
                                      _durationOption = val;
                                      if (val != 'custom') _customDaysController.clear();
                                    }),
                                    selectedColor: Colors.deepOrange.withValues(alpha: 0.2),
                                    labelStyle: TextStyle(
                                      fontSize: 12,
                                      color: _durationOption == val
                                          ? Colors.deepOrange
                                          : Colors.black87,
                                      fontWeight: _durationOption == val
                                          ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  );
                                }).toList(),
                              ),
                              if (_durationOption == 'custom') ...[
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _customDaysController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: _inputDeco('일수 직접입력', '예: 14'),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],

                    // ── 혜택 종류 (고정: 전면광고 해제) ────────────────────
                    _sectionBox(
                      label: '혜택',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.block, size: 16, color: Colors.deepOrange),
                            const SizedBox(width: 6),
                            const Text('전면광고 해제 (interstitial_ad_free)',
                                style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── 등록 마감일 ────────────────────────────────────────
                    _sectionBox(
                      label: '코드 입력 마감일',
                      child: Wrap(
                        spacing: 4,
                        children: _deadlineOptions.map((opt) {
                          final (val, lbl) = opt;
                          return ChoiceChip(
                            label: Text(lbl),
                            selected: _registrationDeadline == val,
                            onSelected: (_) => setState(() => _registrationDeadline = val),
                            selectedColor: Colors.blue.withValues(alpha: 0.15),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: _registrationDeadline == val ? Colors.blue : Colors.black87,
                              fontWeight: _registrationDeadline == val
                                  ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── 최대 사용 횟수 ──────────────────────────────────────
                    TextField(
                      controller: _maxUsesController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _inputDeco('최대 사용 횟수', '1'),
                    ),
                    const SizedBox(height: 16),

                    // ── 생성 버튼 ────────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isCreating ? null : _createCoupon,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isCreating
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('쿠폰 생성',
                                style: TextStyle(color: Colors.white, fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── 쿠폰 목록 헤더 ─────────────────────────────────────────────
            Row(
              children: [
                const Text('생성된 쿠폰',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text('(${activeCoupons.length}건)',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 12),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (activeCoupons.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('생성된 쿠폰이 없습니다',
                      style: TextStyle(color: Colors.grey.shade500)),
                ),
              )
            else
              ...activeCoupons.map((c) => _buildCouponCard(c, expired: false)),

            const SizedBox(height: 24),

            // ── 만료된 쿠폰 ──────────────────────────────────────────────────
            if (expiredCoupons.isNotEmpty) ...[
              GestureDetector(
                onTap: () => setState(() => _expiredExpanded = !_expiredExpanded),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule_outlined, size: 18, color: Colors.red.shade400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('만료·사용 완료 쿠폰 (${expiredCoupons.length}건)',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                                color: Colors.red.shade700)),
                      ),
                      Icon(_expiredExpanded ? Icons.expand_less : Icons.expand_more,
                          color: Colors.red.shade400),
                    ],
                  ),
                ),
              ),

              if (_expiredExpanded) ...[
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red.shade100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isDeletingExpired ? null : _deleteAllExpired,
                            icon: _isDeletingExpired
                                ? const SizedBox(width: 14, height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.delete_sweep, size: 18, color: Colors.red),
                            label: const Text('등록기한 지난 쿠폰 모두 삭제',
                                style: TextStyle(color: Colors.red)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ...expiredCoupons.map((c) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: _buildCouponCard(c, expired: true),
                      )),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ],
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── 헬퍼 위젯 ─────────────────────────────────────────────────────────────

  Widget _appTab(String label, String value) {
    final selected = _targetApp == value;
    final activeColor = switch (value) {
      'naedon'   => Colors.green.shade600,
      'berwrite' => Colors.brown.shade500,
      'all'      => Colors.blueGrey.shade600,
      _          => Colors.deepOrange,
    };
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _targetApp = value;
          if (value == 'lottery') _couponType = 'duration';
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? activeColor : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? activeColor : Colors.grey.shade300),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : Colors.grey.shade700,
              )),
        ),
      ),
    );
  }

  Widget _typeToggle(String label, String value) {
    final selected = _couponType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _couponType = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.deepPurple.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? Colors.deepPurple : Colors.grey.shade300),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.deepPurple : Colors.grey.shade700,
              )),
        ),
      ),
    );
  }

  Widget _sectionBox({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );

  Widget _buildCouponCard(Map<String, dynamic> coupon, {required bool expired}) {
    final code       = coupon['code']        as String? ?? '';
    final isActive   = coupon['is_active']   == true;
    final usedCount  = coupon['used_count']  ?? 0;
    final maxUses    = coupon['max_uses']    ?? 1;
    final couponName = coupon['coupon_name'] as String?;
    final targetApp  = coupon['target_app']  as String? ?? 'lottery';
    final couponType = coupon['coupon_type'] as String? ?? 'duration';
    final durationDays = coupon['duration_days'] as int?;
    final expiresAt  = coupon['expires_at']  as String?;

    final usedUp = _isUsedUp(coupon);
    final expiryLabel = usedUp
        ? '사용 완료'
        : expiresAt == null
            ? '무기한 등록 가능'
            : expired
                ? '등록기한 만료: ${_formatDate(expiresAt)}'
                : '등록기한: ~${_formatDate(expiresAt)}';

    final (appColor, appLabel) = switch (targetApp) {
      'cartdamda' => (Colors.deepPurple, '카트담다'),
      'naedon'    => (Colors.green.shade700, '내돈'),
      'berwrite'  => (Colors.brown.shade600, '베르와이트'),
      'all'       => (Colors.blueGrey, '전체 앱'),
      _           => (Colors.indigo, '복권명당'),
    };

    final typeLabel = switch (couponType) {
      'master'   => '마스터 (평생)',
      'duration' => durationDays != null ? '$durationDays일권' : '기간형',
      _          => couponType,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: expired ? Colors.grey.shade100 : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (couponName != null && couponName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(couponName,
                              style: const TextStyle(fontSize: 13,
                                  fontWeight: FontWeight.bold, color: Colors.black87)),
                        ),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: code));
                          _snack('코드가 복사되었습니다');
                        },
                        child: Text(code,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              fontFamily: 'monospace',
                              color: expired ? Colors.grey : Colors.black87,
                            )),
                      ),
                    ],
                  ),
                ),
                if (!expired)
                  Switch(
                    value: isActive,
                    onChanged: (_) => _toggleActive(code, isActive),
                    activeTrackColor: Colors.deepOrange,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                  tooltip: '삭제',
                  onPressed: () => _deleteCoupon(code),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                _chip(appLabel, appColor),
                _chip(typeLabel, Colors.teal),
                _chip('전면광고 해제', Colors.blue),
                _chip('$usedCount / $maxUses 사용', Colors.green),
                _chip(expiryLabel, expired ? Colors.red : Colors.orange),
                if (!expired && !isActive) _chip('비활성', Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
