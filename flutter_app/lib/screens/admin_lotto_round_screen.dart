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
  final _yearController = TextEditingController();
  final _monthController = TextEditingController();
  final _dayController = TextEditingController();
  final _roundController = TextEditingController();
  final _bonusController = TextEditingController();
  final List<TextEditingController> _numberControllers =
      List.generate(6, (_) => TextEditingController());

  bool _isSaving = false;
  bool _isLoadingRounds = true;
  int? _editingRound;
  List<LottoWinningNumber> _rounds = [];
  static const int _itemsPerPage = 10;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _refreshRounds();
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    _roundController.dispose();
    _bonusController.dispose();
    for (final c in _numberControllers) {
      c.dispose();
    }
    super.dispose();
  }

  int? _parseNum(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 1 || parsed > 45) return null;
    return parsed;
  }

  Future<void> _refreshRounds() async {
    setState(() => _isLoadingRounds = true);
    // Supabase에서 전체 당첨번호 조회 (1219~1회 포함)
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
    _yearController.text = parts.isNotEmpty ? parts[0] : '';
    _monthController.text = parts.length > 1 ? parts[1] : '';
    _dayController.text = parts.length > 2 ? parts[2] : '';
    _roundController.text = item.round.toString();
    _bonusController.text = item.bonusNumber.toString();
    for (int i = 0; i < 6; i++) {
      _numberControllers[i].text =
          i < item.numbers.length ? item.numbers[i].toString() : '';
    }
    setState(() => _editingRound = item.round);
  }

  void _clearForm() {
    _yearController.clear();
    _monthController.clear();
    _dayController.clear();
    _roundController.clear();
    _bonusController.clear();
    for (final c in _numberControllers) {
      c.clear();
    }
    setState(() => _editingRound = null);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final numbers = _numberControllers
        .map((e) => _parseNum(e.text))
        .whereType<int>()
        .toList();
    final bonus = _parseNum(_bonusController.text);
    final round = int.tryParse(_roundController.text.trim());
    final year = int.tryParse(_yearController.text.trim());
    final month = int.tryParse(_monthController.text.trim());
    final day = int.tryParse(_dayController.text.trim());

    if (round == null ||
        year == null ||
        month == null ||
        day == null ||
        bonus == null ||
        numbers.length != 6) {
      _showSnack('입력값을 다시 확인해주세요');
      return;
    }

    if (year < 2002 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) {
      _showSnack('날짜를 올바르게 입력해주세요');
      return;
    }

    final drawDate =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

    final unique = numbers.toSet();
    if (unique.length != 6) {
      _showSnack('당첨번호 6개는 중복 없이 입력해주세요');
      return;
    }
    if (unique.contains(bonus)) {
      _showSnack('보너스 번호는 당첨번호와 달라야 합니다');
      return;
    }

    setState(() => _isSaving = true);

    final item = LottoWinningNumber(
      drawDate: drawDate,
      round: round,
      numbers: numbers,
      bonusNumber: bonus,
    );

    // Supabase에 저장 (로컬도 동기화)
    await SupabaseService.saveWinningNumbers(item);
    await SupabaseService.createOrUpdateLottoRound(item.round, 'pending');
    await LottoWinningService().saveRound(item);

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _editingRound = null;
    });

    await _refreshRounds();
    _clearForm();
    if (!mounted) return;
    _showSnack('로또 ${item.round}회 당첨번호가 저장되었습니다');
  }

  Future<void> _deleteRound(LottoWinningNumber item) async {
    await LottoWinningService().deleteRound(item.round);
    await _refreshRounds();
    if (_editingRound == item.round) _clearForm();
    if (!mounted) return;
    _showSnack('${item.round}회차가 삭제되었습니다');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.purple,
        title: const Text(
          '로또 당첨회차 생성',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
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
            // 날짜 입력
            const Text('추첨일', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildDateField(_yearController, '년', '2026',
                    (v) => _validateRange(v, 2002, 2100, '년')),
                const SizedBox(width: 8),
                _buildDateField(_monthController, '월', '05',
                    (v) => _validateRange(v, 1, 12, '월')),
                const SizedBox(width: 8),
                _buildDateField(_dayController, '일', '03',
                    (v) => _validateRange(v, 1, 31, '일')),
              ],
            ),
            const SizedBox(height: 12),

            // 회차
            TextFormField(
              controller: _roundController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '회차',
                hintText: '예: 1160',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final p = int.tryParse((v ?? '').trim());
                if (p == null || p <= 0) return '회차를 숫자로 입력';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 당첨번호 6개
            const Text('당첨번호 6개',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(6, (i) {
                return SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: _numberControllers[i],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '${i + 1}번',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => _parseNum(v) == null ? '1~45' : null,
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),

            // 보너스
            SizedBox(
              width: 120,
              child: TextFormField(
                controller: _bonusController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '보너스',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _parseNum(v) == null ? '1~45' : null,
              ),
            ),
            const SizedBox(height: 24),

            // 발행 버튼
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _editingRound != null ? '수정 적용' : '발행',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // 생성된 회차 목록
            const Text('생성된 당첨회차',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (_isLoadingRounds)
              const Center(child: CircularProgressIndicator())
            else if (_rounds.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text('생성된 당첨회차가 없습니다'),
              )
            else
              ..._rounds
                  .skip((_currentPage - 1) * _itemsPerPage)
                  .take(_itemsPerPage)
                  .map(_buildRoundItem),
            if (_rounds.isNotEmpty) _buildPagination(),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField(TextEditingController ctrl, String label, String hint,
      String? Function(String?) validator) {
    return Expanded(
      child: TextFormField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        validator: validator,
      ),
    );
  }

  String? _validateRange(String? v, int min, int max, String label) {
    final p = int.tryParse((v ?? '').trim());
    if (p == null || p < min || p > max) return label;
    return null;
  }

  Widget _buildRoundItem(LottoWinningNumber item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${item.round}회 (${item.drawDate})',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _fillFormForEdit(item),
                    child: const Text('수정'),
                  ),
                  TextButton(
                    onPressed: () => _deleteRound(item),
                    child:
                        const Text('삭제', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '당첨번호: ${item.numbers.join(', ')} + 보너스 ${item.bonusNumber}',
            style: const TextStyle(fontSize: 13),
          ),
        ],
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
            onPressed:
                _currentPage > 1 ? () => setState(() => _currentPage--) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('$_currentPage / $totalPages',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            onPressed: _currentPage < totalPages
                ? () => setState(() => _currentPage++)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
