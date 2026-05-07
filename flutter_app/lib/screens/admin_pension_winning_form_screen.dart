import 'package:flutter/material.dart';

import '../models/pension_winning_number.dart';
import '../models/lottery_store.dart';
import '../services/supabase_service.dart';

class AdminPensionWinningFormScreen extends StatefulWidget {
  const AdminPensionWinningFormScreen({super.key});

  @override
  State<AdminPensionWinningFormScreen> createState() => _AdminPensionWinningFormScreenState();
}

class _AdminPensionWinningFormScreenState extends State<AdminPensionWinningFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _yearController = TextEditingController();
  final _monthController = TextEditingController();
  final _dayController = TextEditingController();
  final _roundController = TextEditingController();
  final _winningNumberController = TextEditingController();
  final _bonusNumberController = TextEditingController();
  int _selectedGroup = 1; // 1~5조

  bool _isSaving = false;
  bool _isLoadingRounds = true;
  List<PensionWinningNumber> _rounds = [];
  static const int _itemsPerPage = 5;
  int _currentPage = 1;

  // 미리보기
  int? _previewRound;
  PensionWinningNumber? _previewWinning;
  List<LotteryStore> _previewStores = [];
  bool _isPreviewLoading = false;

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
    final rounds = await SupabaseService.getAllPensionWinningNumbers();
    if (!mounted) return;
    setState(() {
      _rounds = rounds;
      _isLoadingRounds = false;
    });
  }

  int _totalPagesFor(int totalItems) {
    if (totalItems == 0) return 1;
    return ((totalItems - 1) ~/ _itemsPerPage) + 1;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('입력값을 다시 확인해주세요')),
      );
      return;
    }

    if (winningNumber.length != 6 || int.tryParse(winningNumber) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('1등 번호는 6자리 숫자여야 합니다')),
      );
      return;
    }

    if (bonusNumber.length != 6 || int.tryParse(bonusNumber) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('보너스 번호는 6자리 숫자여야 합니다')),
      );
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

    await SupabaseService.savePensionWinningNumbers(item);

    if (!mounted) return;
    setState(() => _isSaving = false);

    await _refreshRounds();
    _clearForm();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('연금복권 ${item.round}회 당첨번호가 저장되었습니다')),
    );
  }

  Future<void> _loadPreview(PensionWinningNumber item) async {
    setState(() => _isPreviewLoading = true);

    final stores = await SupabaseService.getPensionWinningStoresForRound(item.round);

    if (!mounted) return;
    setState(() {
      _previewRound = item.round;
      _previewWinning = item;
      _previewStores = stores;
      _isPreviewLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          '연금복권 당첨번호 입력',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
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
                Expanded(
                  child: TextFormField(
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '년', hintText: '2026', border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final p = int.tryParse((v ?? '').trim());
                      if (p == null || p < 2002 || p > 2100) return '년';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _monthController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '월', hintText: '05', border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final p = int.tryParse((v ?? '').trim());
                      if (p == null || p < 1 || p > 12) return '월';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _dayController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '일', hintText: '01', border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final p = int.tryParse((v ?? '').trim());
                      if (p == null || p < 1 || p > 31) return '일';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 회차
            TextFormField(
              controller: _roundController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '회차', hintText: '예: 580', border: OutlineInputBorder(),
              ),
              validator: (v) {
                final p = int.tryParse((v ?? '').trim());
                if (p == null || p <= 0) return '회차를 숫자로';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 조 선택
            const Text('1등 당첨 조', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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

            // 1등 번호 (6자리)
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
                if (text.length != 6 || int.tryParse(text) == null) return '6자리 숫자';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // 보너스 번호 (6자리)
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
                if (text.length != 6 || int.tryParse(text) == null) return '6자리 숫자';
                return null;
              },
            ),
            const SizedBox(height: 24),

            // 저장 버튼
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: _isSaving
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('저장', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),

            // 미리보기
            if (_previewRound != null && _previewWinning != null) ...[
              const Text('미리보기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$_previewRound회차', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      '${_previewWinning!.winningGroup}조 ${_previewWinning!.winningNumber}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                    Text('보너스: ${_previewWinning!.bonusNumber}', style: const TextStyle(fontSize: 14)),
                    if (_previewStores.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('당첨지점', style: TextStyle(fontWeight: FontWeight.bold)),
                      ..._previewStores.take(10).map((store) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('${store.storeName} (${store.region})', style: const TextStyle(fontSize: 12)),
                      )),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 생성된 회차 목록
            Row(
              children: [
                const Text('생성된 연금복권 회차', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                SizedBox(
                  width: 32, height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero, iconSize: 20,
                    onPressed: _isLoadingRounds ? null : () {
                      setState(() => _isLoadingRounds = true);
                      _refreshRounds();
                    },
                    icon: _isLoadingRounds
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, color: Colors.orange),
                  ),
                ),
              ],
            ),
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
                  .map((item) {
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
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => _fillFormForEdit(item),
                                child: const Text('수정'),
                              ),
                              TextButton(
                                onPressed: () => _loadPreview(item),
                                child: const Text('미리보기'),
                              ),
                            ],
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
              }),
            if (_rounds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final totalPages = _totalPagesFor(_rounds.length);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('$_currentPage / $totalPages', style: const TextStyle(fontWeight: FontWeight.w600)),
                    IconButton(
                      onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
