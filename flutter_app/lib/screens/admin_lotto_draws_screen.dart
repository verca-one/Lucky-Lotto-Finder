import 'package:flutter/material.dart';
import 'dart:ui' show FontFeature;
import '../models/lotto_winning_number.dart';
import '../services/firestore_service.dart';

class AdminLottoDrawsScreen extends StatefulWidget {
  const AdminLottoDrawsScreen({super.key});

  @override
  State<AdminLottoDrawsScreen> createState() => _AdminLottoDrawsScreenState();
}

class _AdminLottoDrawsScreenState extends State<AdminLottoDrawsScreen> {
  List<LottoWinningNumber> _draws = [];
  bool _isLoading = true;
  String? _error;

  // 페이지네이션
  static const int _pageSize = 20;
  int _currentPage = 0; // 0-based

  // 입력 폼
  final _formKey = GlobalKey<FormState>();
  final _roundController = TextEditingController();
  final _yearController  = TextEditingController();
  final _monthController = TextEditingController();
  final _dayController   = TextEditingController();
  final _bonusController = TextEditingController();
  final List<TextEditingController> _numControllers =
      List.generate(6, (_) => TextEditingController());
  bool _isSaving = false;
  bool _inputExpanded = false;
  final _inputCardKey = GlobalKey();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _roundController.dispose();
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    _bonusController.dispose();
    for (final c in _numControllers) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final draws = await FirestoreService.getAllLottoDraws();
      // 최신 회차 먼저
      draws.sort((a, b) => b.round.compareTo(a.round));
      if (!mounted) return;
      setState(() { _draws = draws; _isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  int? _parseNum(String? v) {
    final n = int.tryParse((v ?? '').trim());
    return (n != null && n >= 1 && n <= 45) ? n : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final round  = int.tryParse(_roundController.text.trim());
    final year   = int.tryParse(_yearController.text.trim());
    final month  = int.tryParse(_monthController.text.trim());
    final day    = int.tryParse(_dayController.text.trim());
    final nums   = _numControllers.map((c) => _parseNum(c.text)).whereType<int>().toList();
    final bonus  = _parseNum(_bonusController.text);

    if (round == null || year == null || month == null || day == null ||
        bonus == null || nums.length != 6) {
      _snack('입력값을 다시 확인해주세요'); return;
    }
    if (nums.toSet().length != 6) { _snack('번호 6개는 중복 없이 입력해주세요'); return; }
    if (nums.contains(bonus))     { _snack('보너스는 당첨번호와 달라야 합니다'); return; }

    final drawDate =
        '${year.toString().padLeft(4,'0')}-${month.toString().padLeft(2,'0')}-${day.toString().padLeft(2,'0')}';
    setState(() => _isSaving = true);
    try {
      await FirestoreService.saveLottoDraw(LottoWinningNumber(
        round: round, numbers: nums, bonusNumber: bonus, drawDate: drawDate,
      ));
      if (!mounted) return;
      _snack('$round회 저장 완료');
      for (final c in [_roundController,_yearController,_monthController,
                        _dayController,_bonusController,..._numControllers]) c.clear();
      setState(() { _isSaving = false; _inputExpanded = false; });
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack('저장 실패: $e');
      setState(() => _isSaving = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  void _openInput() {
    setState(() => _inputExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _inputCardKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    });
  }

  // ── 페이지 데이터 ───────────────────────────────────────
  List<LottoWinningNumber> get _paginated {
    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, _draws.length);
    return _draws.sublist(start, end);
  }
  int get _totalPages => (_draws.length / _pageSize).ceil();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      appBar: AppBar(
        title: const Text('당첨번호 목록', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _openInput,
            icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
            label: const Text('번호 입력',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.error_outline, size: 48, color: Colors.red),
      const SizedBox(height: 12),
      Text(_error!, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: _load, child: const Text('다시 시도')),
    ]),
  );

  Widget _buildBody() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // ── 입력 카드 ──────────────────────────────────────
        _buildInputCard(),
        const SizedBox(height: 16),
        // ── 통계 요약 ──────────────────────────────────────
        _buildSummaryRow(),
        const SizedBox(height: 12),
        // ── 목록 ──────────────────────────────────────────
        _buildDrawsList(),
        const SizedBox(height: 12),
        // ── 페이지네이션 ────────────────────────────────────
        if (_totalPages > 1) _buildPagination(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSummaryRow() {
    return Row(children: [
      _summaryChip('전체', '${_draws.length}회', const Color(0xFF1565C0)),
      const SizedBox(width: 8),
      _summaryChip('최신', _draws.isNotEmpty ? '${_draws.first.round}회' : '-', Colors.green),
      const SizedBox(width: 8),
      _summaryChip('최초', _draws.isNotEmpty ? '${_draws.last.round}회' : '-', Colors.grey),
    ]);
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
        Text(value, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w900,
            fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
  }

  // ── 목록 ────────────────────────────────────────────────
  Widget _buildDrawsList() {
    final page = _paginated;
    if (page.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('저장된 당첨번호가 없습니다', style: TextStyle(color: Colors.grey)),
      ));
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              SizedBox(width: 52,
                  child: Text('회차', style: _headerStyle())),
              Expanded(child: Text('당첨번호', style: _headerStyle())),
              SizedBox(width: 44,
                  child: Text('보너스', style: _headerStyle(), textAlign: TextAlign.center)),
              SizedBox(width: 72,
                  child: Text('추첨일', style: _headerStyle(), textAlign: TextAlign.right)),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          // 행들
          ...page.asMap().entries.map((e) {
            final idx = e.key;
            final draw = e.value;
            final isLast = idx == page.length - 1;
            return Column(children: [
              _buildDrawRow(draw),
              if (!isLast) const Divider(height: 1, indent: 16, endIndent: 16,
                  color: Color(0xFFF5F5F5)),
            ]);
          }),
        ],
      ),
    );
  }

  TextStyle _headerStyle() => const TextStyle(
      fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF999999), letterSpacing: .3);

  Widget _buildDrawRow(LottoWinningNumber draw) {
    return InkWell(
      onLongPress: () => _confirmDelete(draw),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // 회차
            SizedBox(
              width: 52,
              child: Text(
                '${draw.round}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                    color: Color(0xFF1565C0),
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
            // 번호 볼
            Expanded(
              child: Wrap(
                spacing: 4,
                children: draw.numbers.map((n) => _miniball(n)).toList(),
              ),
            ),
            // 보너스
            SizedBox(
              width: 44,
              child: Center(child: draw.bonusNumber > 0
                  ? _miniball(draw.bonusNumber, bonus: true)
                  : const Text('-', style: TextStyle(color: Colors.grey))),
            ),
            // 날짜
            SizedBox(
              width: 72,
              child: Text(
                draw.drawDate.length >= 10
                    ? draw.drawDate.substring(2) // YY-MM-DD
                    : draw.drawDate,
                style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniball(int n, {bool bonus = false}) {
    final bg = bonus ? Colors.orange.shade600 : _ballColor(n);
    return Container(
      width: 26, height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: bonus ? Border.all(color: Colors.orange.shade300, width: 1.5) : null,
      ),
      child: Text('$n',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)),
    );
  }

  Color _ballColor(int n) {
    if (n <= 10) return const Color(0xFFFFB300);
    if (n <= 20) return const Color(0xFF42A5F5);
    if (n <= 30) return const Color(0xFFEF5350);
    if (n <= 40) return const Color(0xFF9E9E9E);
    return const Color(0xFF66BB6A);
  }

  // ── 페이지네이션 ─────────────────────────────────────────
  Widget _buildPagination() {
    // 최대 7개 페이지 버튼 표시 (앞뒤 화살표 포함)
    final total = _totalPages;
    final cur = _currentPage;

    // 표시할 페이지 범위 계산
    int start = (cur - 3).clamp(0, total - 1);
    int end   = (start + 6).clamp(0, total - 1);
    start = (end - 6).clamp(0, total - 1);

    return Center(
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          // 처음
          _pageBtn('«', cur > 0, () => _goPage(0)),
          // 이전
          _pageBtn('‹', cur > 0, () => _goPage(cur - 1)),
          // 숫자 버튼
          ...List.generate(end - start + 1, (i) {
            final p = start + i;
            return _pageNumBtn(p);
          }),
          // 다음
          _pageBtn('›', cur < total - 1, () => _goPage(cur + 1)),
          // 마지막
          _pageBtn('»', cur < total - 1, () => _goPage(total - 1)),
        ],
      ),
    );
  }

  void _goPage(int page) {
    setState(() => _currentPage = page);
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Widget _pageBtn(String label, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36, height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDDDDDD)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: enabled ? const Color(0xFF444444) : const Color(0xFFCCCCCC))),
      ),
    );
  }

  Widget _pageNumBtn(int page) {
    final isCur = page == _currentPage;
    return GestureDetector(
      onTap: () => _goPage(page),
      child: Container(
        width: 36, height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isCur ? const Color(0xFF1565C0) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isCur ? const Color(0xFF1565C0) : const Color(0xFFDDDDDD)),
        ),
        child: Text('${page + 1}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isCur ? Colors.white : const Color(0xFF555555),
                fontFeatures: [FontFeature.tabularFigures()])),
      ),
    );
  }

  // ── 삭제 확인 ────────────────────────────────────────────
  void _confirmDelete(LottoWinningNumber draw) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${draw.round}회 삭제'),
        content: const Text('이 당첨번호를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirestoreService.deleteLottoDraw(draw.round);
              _snack('${draw.round}회 삭제됨');
              await _load();
            },
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── 입력 카드 ────────────────────────────────────────────
  Widget _buildInputCard() {
    return Container(
      key: _inputCardKey,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _inputExpanded = !_inputExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B2FF7), Color(0xFFDA22FF)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('당첨번호 입력',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A1A))),
                  Text('회차 · 날짜 · 번호 6개 + 보너스',
                      style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
                ]),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(
                  _inputExpanded ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey, size: 20,
                ),
              ),
            ]),
          ),
        ),
        if (_inputExpanded) ...[
          Container(height: 1, color: const Color(0xFFF3F3F3)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // 회차 + 날짜
                Row(children: [
                  Expanded(flex: 3, child: _compactField(
                    controller: _roundController, label: '회차', hint: '1198',
                    icon: Icons.tag_rounded, iconColor: const Color(0xFF7B2FF7),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      return (n == null || n <= 0) ? '!' : null;
                    },
                  )),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: _compactField(
                    controller: _yearController, label: '년도', hint: '2026',
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      return (n == null || n < 2002) ? '!' : null;
                    },
                  )),
                  const SizedBox(width: 6),
                  Expanded(flex: 2, child: _compactField(
                    controller: _monthController, label: '월', hint: '08',
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      return (n == null || n < 1 || n > 12) ? '!' : null;
                    },
                  )),
                  const SizedBox(width: 6),
                  Expanded(flex: 2, child: _compactField(
                    controller: _dayController, label: '일', hint: '09',
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      return (n == null || n < 1 || n > 31) ? '!' : null;
                    },
                  )),
                ]),
                const SizedBox(height: 16),

                // 번호 6개
                Row(children: [
                  const Text('번호', style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF555555))),
                  const SizedBox(width: 8),
                  ...List.generate(6, (i) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
                      child: _ballInputField(_numControllers[i]),
                    ),
                  )),
                ]),
                const SizedBox(height: 10),

                // 보너스
                Row(children: [
                  const Text('보너스', style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF555555))),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    child: TextFormField(
                      controller: _bonusController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                          color: Color(0xFFE65100)),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFFFF3E0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFFFCC80))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFFFCC80))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFFF9800), width: 2)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                        hintText: '+',
                        hintStyle: TextStyle(color: Colors.orange.shade300, fontSize: 18),
                      ),
                      validator: (v) => _parseNum(v) == null ? '!' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('보너스 번호 (1~45)',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400))),
                ]),
                const SizedBox(height: 18),

                // 저장 버튼
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B2FF7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.cloud_upload_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('Firestore에 저장',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          ]),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _compactField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
    Color? iconColor,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 11),
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade300),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF7B2FF7), width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      prefixIcon: icon != null ? Icon(icon, size: 16, color: iconColor ?? Colors.grey) : null,
    ),
    validator: validator,
  );

  Widget _ballInputField(TextEditingController controller) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white),
    decoration: InputDecoration(
      filled: true,
      fillColor: const Color(0xFF1565C0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF42A5F5), width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      hintText: '·',
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 20),
      errorStyle: const TextStyle(fontSize: 0, height: 0),
    ),
    validator: (v) => _parseNum(v) == null ? '!' : null,
  );
}
