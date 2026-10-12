import 'package:flutter/material.dart';

import '../models/lotto_winning_number.dart';
import '../services/lotto_winning_service.dart';
import '../services/supabase_service.dart';

class AdminLottoRoundScreen extends StatefulWidget {
  const AdminLottoRoundScreen({super.key});

  @override
  State<AdminLottoRoundScreen> createState() => _AdminLottoRoundScreenState();
}

class _AdminLottoRoundScreenState extends State<AdminLottoRoundScreen> {
  final _formKey = GlobalKey<FormState>();
  final _roundController    = TextEditingController();
  final _bonusController    = TextEditingController();
  final List<TextEditingController> _numberControllers =
      List.generate(6, (_) => TextEditingController());

  DateTime? _selectedDate;
  bool _isSaving = false;
  bool _isLoadingRounds = true;
  int? _editingRound;
  List<LottoWinningNumber> _rounds = [];
  static const int _itemsPerPage = 10;
  int _currentPage = 1;

  // 당첨번호 색상 (로또 공식 색상)
  Color _ballColor(int n) {
    if (n <= 10) return const Color(0xFFFFB300);   // 노랑
    if (n <= 20) return const Color(0xFF42A5F5);   // 파랑
    if (n <= 30) return const Color(0xFFEF5350);   // 빨강
    if (n <= 40) return const Color(0xFF616161);   // 회색
    return const Color(0xFF66BB6A);                // 초록
  }

  @override
  void initState() {
    super.initState();
    _refreshRounds();
  }

  @override
  void dispose() {
    _roundController.dispose();
    _bonusController.dispose();
    for (final c in _numberControllers) c.dispose();
    super.dispose();
  }

  int? _parseNum(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 1 || parsed > 45) return null;
    return parsed;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2002),
      lastDate: DateTime(2100),
      locale: const Locale('ko'),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _refreshRounds() async {
    setState(() => _isLoadingRounds = true);
    final rounds = await SupabaseService.getAllWinningNumbers();
    if (!mounted) return;
    setState(() {
      _rounds = rounds;
      final totalPages = _totalPages(rounds.length);
      if (_currentPage > totalPages) _currentPage = totalPages;
      _isLoadingRounds = false;
    });
  }

  int _totalPages(int total) {
    if (total == 0) return 1;
    return ((total - 1) ~/ _itemsPerPage) + 1;
  }

  void _fillFormForEdit(LottoWinningNumber item) {
    final parts = item.drawDate.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) {
        _selectedDate = DateTime(y, m, d);
      }
    }
    _roundController.text = item.round.toString();
    _bonusController.text = item.bonusNumber.toString();
    for (int i = 0; i < 6; i++) {
      _numberControllers[i].text =
          i < item.numbers.length ? item.numbers[i].toString() : '';
    }
    setState(() => _editingRound = item.round);
  }

  void _clearForm() {
    _selectedDate = null;
    _roundController.clear();
    _bonusController.clear();
    for (final c in _numberControllers) c.clear();
    setState(() => _editingRound = null);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      _showSnack('추첨일을 선택해주세요');
      return;
    }

    final numbers = _numberControllers
        .map((e) => _parseNum(e.text))
        .whereType<int>()
        .toList();
    final bonus = _parseNum(_bonusController.text);
    final round = int.tryParse(_roundController.text.trim());

    if (round == null || bonus == null || numbers.length != 6) {
      _showSnack('입력값을 다시 확인해주세요');
      return;
    }

    final unique = numbers.toSet();
    if (unique.length != 6) {
      _showSnack('당첨번호 6개는 중복 없이 입력해주세요');
      return;
    }
    if (unique.contains(bonus)) {
      _showSnack('보너스 번호는 당첨번호와 달라야 합니다');
      return;
    }

    final d = _selectedDate!;
    final drawDate =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    setState(() => _isSaving = true);

    final item = LottoWinningNumber(
      drawDate: drawDate,
      round: round,
      numbers: numbers,
      bonusNumber: bonus,
    );

    await SupabaseService.saveWinningNumbers(item);
    await SupabaseService.createOrUpdateLottoRound(item.round, 'pending');
    await LottoWinningService().saveRound(item);

    // 랜덤확률분석엔진 자동 처리 (검증 → 보정 → 다음 회차 예측)
    _triggerRpaProcess(item);

    if (!mounted) return;
    setState(() { _isSaving = false; _editingRound = null; });
    await _refreshRounds();
    _clearForm();
    if (!mounted) return;
    _showSnack('로또 ${item.round}회 당첨번호가 저장되었습니다');
  }

  // 랜덤확률분석엔진 처리는 서버 파이프라인이 한다 (당첨번호·1등 판매점 준비 후 자동 실행)
  void _triggerRpaProcess(LottoWinningNumber item) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.round}회 당첨번호 저장 완료. 1등 판매점 데이터가 준비되면 서버가 엔진을 자동 실행합니다.'),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _deleteRound(LottoWinningNumber item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('${item.round}회차를 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LottoWinningService().deleteRound(item.round);
    await _refreshRounds();
    if (_editingRound == item.round) _clearForm();
    if (!mounted) return;
    _showSnack('${item.round}회차가 삭제되었습니다');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── 번호 입력 필드 (작은 원형 스타일) ────────────────────────
  Widget _buildNumberField(TextEditingController ctrl, {bool isBonus = false, double width = 52}) {
    final color = isBonus ? Colors.green.shade600 : Colors.purple;
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 2,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: color,
        ),
        decoration: InputDecoration(
          counterText: '',
          hintText: isBonus ? 'B' : '?',
          hintStyle: TextStyle(color: color.withValues(alpha: 0.4), fontSize: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: color, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
          filled: true,
          fillColor: color.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          errorStyle: const TextStyle(height: 0, fontSize: 0),
        ),
        validator: (v) => _parseNum(v) == null ? '' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _editingRound != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.purple,
        title: const Text(
          '로또 당첨회차 생성',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isLoadingRounds ? null : _refreshRounds,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [

            // ── 입력 카드 ─────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // 카드 헤더
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.edit_note_rounded, color: Colors.purple, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isEditing ? '$_editingRound회 수정 중' : '새 당첨회차 입력',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isEditing ? Colors.orange.shade700 : Colors.purple,
                      ),
                    ),
                    if (isEditing) ...[
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _clearForm,
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('취소'),
                        style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 20),

                  // 회차 + 추첨일 (한 줄)
                  Row(children: [
                    // 회차
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _roundController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '회차',
                          hintText: '1237',
                          prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          filled: true,
                          fillColor: const Color(0xFFF6F7FB),
                        ),
                        validator: (v) {
                          final p = int.tryParse((v ?? '').trim());
                          if (p == null || p <= 0) return '회차 입력';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 추첨일 (달력 선택)
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F7FB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Row(children: [
                            Icon(Icons.calendar_today_rounded, size: 20,
                                color: _selectedDate != null ? Colors.purple : Colors.grey.shade500),
                            const SizedBox(width: 8),
                            Text(
                              _selectedDate != null
                                  ? '${_selectedDate!.year}.${_selectedDate!.month.toString().padLeft(2, '0')}.${_selectedDate!.day.toString().padLeft(2, '0')}'
                                  : '추첨일 선택',
                              style: TextStyle(
                                fontSize: 15,
                                color: _selectedDate != null ? Colors.black87 : Colors.grey.shade500,
                                fontWeight: _selectedDate != null ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // 당첨번호 레이블
                  const Text('당첨번호', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                  const SizedBox(height: 10),

                  // 번호 6개 + 구분선 + 보너스
                  LayoutBuilder(builder: (ctx, constraints) {
                    // 가용 너비에서 '+' 텍스트(14) + 여백(8) 제외 후 7칸으로 나눔
                    final fieldW = ((constraints.maxWidth - 22) / 7).floorToDouble().clamp(36.0, 52.0);
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ...List.generate(6, (i) => _buildNumberField(_numberControllers[i], width: fieldW)),
                        const SizedBox(width: 4),
                        Text('+', style: TextStyle(fontSize: 16, color: Colors.grey.shade400, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        _buildNumberField(_bonusController, isBonus: true, width: fieldW),
                      ],
                    );
                  }),
                  const SizedBox(height: 24),

                  // 저장 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isEditing ? Colors.orange.shade600 : Colors.purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(isEditing ? Icons.save_rounded : Icons.check_circle_outline_rounded, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                isEditing ? '$_editingRound회 수정 저장' : '발행',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ]),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 생성된 회차 목록 헤더 ───────────────────────────
            Row(children: [
              const Text('생성된 당첨회차', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              if (!_isLoadingRounds)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${_rounds.length}개',
                      style: const TextStyle(fontSize: 12, color: Colors.purple, fontWeight: FontWeight.w600)),
                ),
            ]),
            const SizedBox(height: 10),

            if (_isLoadingRounds)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (_rounds.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Center(child: Text('생성된 당첨회차가 없습니다', style: TextStyle(color: Colors.grey))),
              )
            else
              ..._rounds
                  .skip((_currentPage - 1) * _itemsPerPage)
                  .take(_itemsPerPage)
                  .map(_buildRoundItem),

            if (_rounds.isNotEmpty) _buildPagination(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundItem(LottoWinningNumber item) {
    final isEditing = _editingRound == item.round;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEditing ? Colors.orange.shade300 : Colors.grey.shade200,
          width: isEditing ? 2 : 1,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              // 회차 뱃지
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${item.round}회',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple)),
              ),
              const SizedBox(width: 8),
              Text(item.drawDate, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const Spacer(),
              // 수정 버튼
              SizedBox(
                height: 30,
                child: TextButton(
                  onPressed: () => _fillFormForEdit(item),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    foregroundColor: Colors.purple,
                  ),
                  child: const Text('수정', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 2),
              // 삭제 버튼
              SizedBox(
                height: 30,
                child: TextButton(
                  onPressed: () => _deleteRound(item),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    foregroundColor: Colors.red,
                  ),
                  child: const Text('삭제', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 번호 공들
          Row(
            children: [
              ...item.numbers.map((n) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildBall(n),
                  )),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('+', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
              _buildBall(item.bonusNumber, isBonus: true),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _buildBall(int n, {bool isBonus = false}) {
    final color = isBonus ? Colors.green.shade500 : _ballColor(n);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Center(
        child: Text(
          '$n',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    final totalPages = _totalPages(_rounds.length);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$_currentPage / $totalPages',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.purple)),
          ),
          IconButton(
            onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
