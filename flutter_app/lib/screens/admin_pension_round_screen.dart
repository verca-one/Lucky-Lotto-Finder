import 'package:flutter/material.dart';

import '../models/pension_winning_number.dart';
import '../services/lotto_winning_service.dart';
import '../services/supabase_service.dart';

class AdminPensionRoundScreen extends StatefulWidget {
  const AdminPensionRoundScreen({super.key});

  @override
  State<AdminPensionRoundScreen> createState() =>
      _AdminPensionRoundScreenState();
}

class _AdminPensionRoundScreenState extends State<AdminPensionRoundScreen> {
  final _formKey = GlobalKey<FormState>();
  final _yearController = TextEditingController();
  final _monthController = TextEditingController();
  final _dayController = TextEditingController();
  final _roundController = TextEditingController();
  final _winningNumberController = TextEditingController();
  final _bonusNumberController = TextEditingController();
  int _selectedGroup = 1;

  bool _isSaving = false;
  bool _isLoadingRounds = true;
  int? _editingRound;
  List<PensionWinningNumber> _rounds = [];
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
    _winningNumberController.dispose();
    _bonusNumberController.dispose();
    super.dispose();
  }

  Future<void> _refreshRounds() async {
    setState(() => _isLoadingRounds = true);
    // 관리자가 생성한 회차만 Supabase에서 조회
    final rounds = await SupabaseService.getAdminPensionRounds();
    if (!mounted) return;
    setState(() {
      _rounds = rounds;
      final tp = _totalPages(rounds.length);
      if (_currentPage > tp) _currentPage = tp;
      _isLoadingRounds = false;
    });
  }

  int _totalPages(int total) {
    if (total == 0) return 1;
    return ((total - 1) ~/ _itemsPerPage) + 1;
  }

  void _fillFormForEdit(PensionWinningNumber item) {
    final parts = item.drawDate.split('-');
    _yearController.text = parts.isNotEmpty ? parts[0] : '';
    _monthController.text = parts.length > 1 ? parts[1] : '';
    _dayController.text = parts.length > 2 ? parts[2] : '';
    _roundController.text = item.round.toString();
    _winningNumberController.text = item.winningNumber;
    _bonusNumberController.text = item.bonusNumber;
    setState(() {
      _selectedGroup = item.winningGroup;
      _editingRound = item.round;
    });
  }

  void _clearForm() {
    _yearController.clear();
    _monthController.clear();
    _dayController.clear();
    _roundController.clear();
    _winningNumberController.clear();
    _bonusNumberController.clear();
    setState(() {
      _selectedGroup = 1;
      _editingRound = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final round = int.tryParse(_roundController.text.trim());
    final year = int.tryParse(_yearController.text.trim());
    final month = int.tryParse(_monthController.text.trim());
    final day = int.tryParse(_dayController.text.trim());
    final winningNumber = _winningNumberController.text.trim();
    final bonusNumber = _bonusNumberController.text.trim();

    if (round == null || year == null || month == null || day == null) {
      _showSnack('입력값을 다시 확인해주세요');
      return;
    }

    if (winningNumber.length != 6 || int.tryParse(winningNumber) == null) {
      _showSnack('1등 번호는 6자리 숫자여야 합니다');
      return;
    }
    if (bonusNumber.length != 6 || int.tryParse(bonusNumber) == null) {
      _showSnack('보너스 번호는 6자리 숫자여야 합니다');
      return;
    }

    final drawDate =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

    setState(() => _isSaving = true);

    final item = PensionWinningNumber(
      drawDate: drawDate,
      round: round,
      winningGroup: _selectedGroup,
      winningNumber: winningNumber,
      bonusNumber: bonusNumber,
    );

    // Supabase에 저장
    await SupabaseService.savePensionWinningNumbers(item);
    await SupabaseService.createPensionRound(item.round);

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _editingRound = null;
    });

    await _refreshRounds();
    _clearForm();
    if (!mounted) return;
    _showSnack('연금복권 ${item.round}회 당첨번호가 저장되었습니다');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          '연금 당첨회차 생성',
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
            // 추첨일
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
                _buildDateField(_dayController, '일', '01',
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
                hintText: '예: 580',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final p = int.tryParse((v ?? '').trim());
                if (p == null || p <= 0) return '회차를 숫자로';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 조 선택
            const Text('1등 당첨 조',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (i) {
                final group = i + 1;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 4 ? 8 : 0),
                    child: ChoiceChip(
                      label: Text('${group}조'),
                      selected: _selectedGroup == group,
                      selectedColor: Colors.orange.shade200,
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedGroup = group);
                      },
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),

            // 1등 번호
            TextFormField(
              controller: _winningNumberController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '1등 번호 (6자리)',
                hintText: '예: 123456',
                border: OutlineInputBorder(),
              ),
              maxLength: 6,
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.length != 6 || int.tryParse(text) == null) {
                  return '6자리 숫자';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // 보너스 번호
            TextFormField(
              controller: _bonusNumberController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '보너스 번호 (6자리)',
                hintText: '예: 654321',
                border: OutlineInputBorder(),
              ),
              maxLength: 6,
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.length != 6 || int.tryParse(text) == null) {
                  return '6자리 숫자';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // 발행 버튼
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submit,
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.orange),
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
            const Text('생성된 연금복권 회차',
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
                child: const Text('생성된 연금복권 회차가 없습니다'),
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

  Widget _buildRoundItem(PensionWinningNumber item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200),
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
              TextButton(
                onPressed: () => _fillFormForEdit(item),
                child: const Text('수정'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${item.winningGroup}조 ${item.winningNumber} | 보너스 ${item.bonusNumber}',
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
