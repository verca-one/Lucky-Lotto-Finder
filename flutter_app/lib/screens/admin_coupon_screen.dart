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
  final _codeController = TextEditingController();
  final _maxUsesController = TextEditingController(text: '1');
  String _selectedType = 'ad_removal';
  DateTime? _expiresAt;
  bool _isCreating = false;
  List<Map<String, dynamic>> _coupons = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCoupons();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _maxUsesController.dispose();
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
    // 4자리씩 하이픈 구분
    return '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8, 12)}';
  }

  Future<void> _createCoupon() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('쿠폰 코드를 입력하세요')),
      );
      return;
    }

    final maxUses = int.tryParse(_maxUsesController.text) ?? 1;

    setState(() => _isCreating = true);

    final success = await SupabaseService.createCoupon(
      code: code,
      type: _selectedType,
      maxUses: maxUses,
      expiresAt: _expiresAt,
    );

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('쿠폰 생성 완료: $code')),
      );
      _codeController.clear();
      _maxUsesController.text = '1';
      _expiresAt = null;
      _loadCoupons();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('쿠폰 생성 실패 (중복 코드일 수 있음)')),
      );
    }
  }

  Future<void> _toggleActive(String code, bool currentActive) async {
    final result = await SupabaseService.toggleCouponActive(code, !currentActive);
    if (result) _loadCoupons();
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() => _expiresAt = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        title: const Text(
          '쿠폰 관리',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 쿠폰 생성 카드
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '쿠폰 생성',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    // 코드 입력 + 자동생성
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeController,
                            decoration: InputDecoration(
                              labelText: '쿠폰 코드',
                              hintText: 'XXXX-XXXX-XXXX',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            _codeController.text = _generateCode();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                          child: const Text('자동생성', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 타입 선택
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: InputDecoration(
                        labelText: '쿠폰 타입',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'ad_removal', child: Text('광고제거')),
                      ],
                      onChanged: (v) => setState(() => _selectedType = v ?? 'ad_removal'),
                    ),
                    const SizedBox(height: 12),

                    // 최대 사용 횟수
                    TextField(
                      controller: _maxUsesController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: '최대 사용 횟수',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 만료일
                    InkWell(
                      onTap: _pickExpiryDate,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: '만료일 (선택)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          suffixIcon: _expiresAt != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setState(() => _expiresAt = null),
                                )
                              : const Icon(Icons.calendar_today, size: 18),
                        ),
                        child: Text(
                          _expiresAt != null
                              ? '${_expiresAt!.year}-${_expiresAt!.month.toString().padLeft(2, '0')}-${_expiresAt!.day.toString().padLeft(2, '0')}'
                              : '만료일 없음',
                          style: TextStyle(
                            color: _expiresAt != null ? Colors.black : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 생성 버튼
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
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('쿠폰 생성', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 쿠폰 목록
            const Text(
              '생성된 쿠폰',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_coupons.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('생성된 쿠폰이 없습니다', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              ..._coupons.map((coupon) => _buildCouponCard(coupon)),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponCard(Map<String, dynamic> coupon) {
    final code = coupon['code'] ?? '';
    final isActive = coupon['is_active'] == true;
    final usedCount = coupon['used_count'] ?? 0;
    final maxUses = coupon['max_uses'] ?? 1;
    final type = coupon['type'] ?? '';
    final expiresAt = coupon['expires_at'];

    String typeLabel = type == 'ad_removal' ? '광고제거' : type;
    bool isExpired = false;
    if (expiresAt != null) {
      isExpired = DateTime.now().isAfter(DateTime.parse(expiresAt));
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isActive && !isExpired ? Colors.white : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    code,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'monospace',
                      color: isActive ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('코드가 복사되었습니다')),
                    );
                  },
                ),
                Switch(
                  value: isActive,
                  onChanged: (v) => _toggleActive(code, isActive),
                  activeColor: Colors.deepOrange,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _infoChip(typeLabel, Colors.blue),
                const SizedBox(width: 6),
                _infoChip('$usedCount / $maxUses 사용', Colors.green),
                if (isExpired) ...[
                  const SizedBox(width: 6),
                  _infoChip('만료됨', Colors.red),
                ] else if (expiresAt != null) ...[
                  const SizedBox(width: 6),
                  _infoChip('~${DateTime.parse(expiresAt).month}/${DateTime.parse(expiresAt).day}', Colors.orange),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
