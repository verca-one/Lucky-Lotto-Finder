import 'package:flutter/material.dart';

import '../models/lotto_winning_number.dart';
import '../models/lottery_store.dart';
import '../services/lotto_winning_service.dart';
import '../services/supabase_service.dart';

class AdminLottoWinningFormScreen extends StatefulWidget {
  const AdminLottoWinningFormScreen({super.key});

  @override
  State<AdminLottoWinningFormScreen> createState() => _AdminLottoWinningFormScreenState();
}

class _AdminLottoWinningFormScreenState extends State<AdminLottoWinningFormScreen> {
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
  final Map<int, int> _loadedStoreCountByRound = {};
  final Set<int> _loadingRoundSet = <int>{};
  static const int _itemsPerPage = 5;
  int _currentPage = 1;

  // 미리보기용
  int? _previewRound;
  LottoWinningNumber? _previewWinningNumber;
  List<LotteryStore> _previewWinningStores = [];
  bool _isPreviewLoading = false;
  Map<String, bool> _publishedStatus = {};

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
    for (final controller in _numberControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _parseAndValidateNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 1 || parsed > 45) return null;
    return parsed;
  }

  Future<void> _refreshRounds() async {
    final service = LottoWinningService();
    final rounds = await service.getAllRounds();
    final Map<int, int> loadedCount = {};
    for (final item in rounds) {
      final loaded = await service.getLoadedStoresForRound(item.round);
      loadedCount[item.round] = loaded.length;
    }

    if (!mounted) return;
    setState(() {
      _rounds = rounds;
      _loadedStoreCountByRound
        ..clear()
        ..addAll(loadedCount);
      final totalPages = _totalPagesFor(rounds.length);
      if (_currentPage > totalPages) {
        _currentPage = totalPages;
      }
      _isLoadingRounds = false;
    });
  }

  int _totalPagesFor(int totalItems) {
    if (totalItems == 0) return 1;
    return ((totalItems - 1) ~/ _itemsPerPage) + 1;
  }

  void _fillFormForEdit(LottoWinningNumber item) {
    final parts = item.drawDate.split('-');
    _yearController.text = parts.isNotEmpty ? parts[0] : '';
    _monthController.text = parts.length > 1 ? parts[1] : '';
    _dayController.text = parts.length > 2 ? parts[2] : '';
    _roundController.text = item.round.toString();
    _bonusController.text = item.bonusNumber.toString();
    for (int i = 0; i < 6; i++) {
      _numberControllers[i].text = i < item.numbers.length ? item.numbers[i].toString() : '';
    }
    setState(() {
      _editingRound = item.round;
    });
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
    setState(() {
      _editingRound = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final numbers = _numberControllers
        .map((e) => _parseAndValidateNumber(e.text))
        .whereType<int>()
        .toList();

    final bonus = _parseAndValidateNumber(_bonusController.text);
    final round = int.tryParse(_roundController.text.trim());
    final year = int.tryParse(_yearController.text.trim());
    final month = int.tryParse(_monthController.text.trim());
    final day = int.tryParse(_dayController.text.trim());

    if (round == null || year == null || month == null || day == null || bonus == null || numbers.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('입력값을 다시 확인해주세요')),
      );
      return;
    }

    if (year < 2002 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('날짜를 올바르게 입력해주세요')),
      );
      return;
    }

    final drawDate =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

    final unique = numbers.toSet();
    if (unique.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('당첨번호 6개는 중복 없이 입력해주세요')),
      );
      return;
    }

    if (unique.contains(bonus)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('보너스 번호는 당첨번호와 달라야 합니다')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final item = LottoWinningNumber(
      drawDate: drawDate,
      round: round,
      numbers: numbers,
      bonusNumber: bonus,
    );

    await LottoWinningService().saveRound(item);

    // Supabase lotto_winning_numbers에도 저장
    await SupabaseService.saveWinningNumbers(item);

    // 회차 페이지 생성 (status=pending)
    await SupabaseService.createOrUpdateLottoRound(item.round, 'pending');

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _editingRound = null;
    });

    await _refreshRounds();
    _clearForm();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('로또 ${item.round}회 당첨번호가 저장되었습니다')),
    );
  }

  Future<void> _deleteRound(LottoWinningNumber item) async {
    await LottoWinningService().deleteRound(item.round);
    await _refreshRounds();
    if (_editingRound == item.round) {
      _clearForm();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.round}회차가 삭제되었습니다')),
    );
  }

  Future<void> _loadWinningStores(LottoWinningNumber item) async {
    setState(() {
      _loadingRoundSet.add(item.round);
    });

    final stores = await SupabaseService.getStoresByRound(
      round: item.round,
      lotteryType: 'lotto',
    );
    final allByRound = await SupabaseService.getStoresByRound(round: item.round);
    await LottoWinningService().saveLoadedStoresForRound(item.round, stores);

    if (!mounted) return;
    setState(() {
      _loadingRoundSet.remove(item.round);
      _loadedStoreCountByRound[item.round] = stores.length;
    });

    if (stores.isEmpty) {
      final message = allByRound.isEmpty
          ? '${item.round}회차 데이터가 Supabase에 없습니다'
          : '${item.round}회차 데이터는 있으나 lotto 타입이 없어 로드되지 않았습니다';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.round}회차 당첨지점 ${stores.length}건 로드 완료')),
    );
  }

  // 미리보기 로드
  Future<void> _loadPreview(LottoWinningNumber item) async {
    setState(() {
      _isPreviewLoading = true;
    });

    final stores = await SupabaseService.getLottoWinningStoresForRound(item.round);

    if (!mounted) return;
    setState(() {
      _previewRound = item.round;
      _previewWinningNumber = item;
      _previewWinningStores = stores;
      _isPreviewLoading = false;
    });
  }

  // 발행
  Future<void> _publishRound(int round) async {
    await SupabaseService.publishLottoRound(round);
    if (!mounted) return;

    setState(() {
      _publishedStatus[round.toString()] = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$round회차가 발행되었습니다!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.purple,
        title: const Text(
          '로또 당첨번호 입력',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              enabled: false,
              decoration: const InputDecoration(
                labelText: '날짜',
                hintText: '년 / 월 / 일 입력',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '년',
                      hintText: '2026',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final parsed = int.tryParse((value ?? '').trim());
                      if (parsed == null || parsed < 2002 || parsed > 2100) {
                        return '년';
                      }
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
                      labelText: '월',
                      hintText: '04',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final parsed = int.tryParse((value ?? '').trim());
                      if (parsed == null || parsed < 1 || parsed > 12) {
                        return '월';
                      }
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
                      labelText: '일',
                      hintText: '26',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final parsed = int.tryParse((value ?? '').trim());
                      if (parsed == null || parsed < 1 || parsed > 31) {
                        return '일';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _roundController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '회차',
                hintText: '예: 1160',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final parsed = int.tryParse((value ?? '').trim());
                if (parsed == null || parsed <= 0) return '회차를 숫자로 입력해주세요';
                return null;
              },
            ),
            const SizedBox(height: 16),
            const Text(
              '당첨번호 6개',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(6, (index) {
                return SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: _numberControllers[index],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '${index + 1}번',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (_parseAndValidateNumber(value) == null) {
                        return '1~45';
                      }
                      return null;
                    },
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 120,
              child: TextFormField(
                controller: _bonusController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '보너스',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (_parseAndValidateNumber(value) == null) return '1~45';
                  return null;
                },
              ),
            ),
            const SizedBox(height: 24),
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
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '적용',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            // 미리보기 섹션
            if (_previewRound != null) ...[
              const Text(
                '📋 페이지 미리보기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_previewRound회차',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    // 당첨번호
                    if (_previewWinningNumber != null) ...[
                      Text(
                        '당첨번호: ${_previewWinningNumber!.numbers.join(', ')} + 보너스 ${_previewWinningNumber!.bonusNumber}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // 당첨지점 (1등)
                    const Text(
                      '1등 당첨지점',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                    const SizedBox(height: 8),
                    ..._previewWinningStores
                        .where((store) => store.prizeTier == 'first')
                        .take(10)
                        .map((store) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '🏪 ${store.storeName} (${store.region})',
                                style: const TextStyle(fontSize: 12),
                              ),
                            )),
                    if (_previewWinningStores.where((s) => s.prizeTier == 'first').length > 10)
                      Text(
                        '+${_previewWinningStores.where((s) => s.prizeTier == 'first').length - 10}개',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    const SizedBox(height: 16),
                    // 당첨지점 (2등)
                    const Text(
                      '2등 당첨지점',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                    const SizedBox(height: 8),
                    ..._previewWinningStores
                        .where((store) => store.prizeTier == 'second')
                        .take(10)
                        .map((store) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '🏪 ${store.storeName} (${store.region})',
                                style: const TextStyle(fontSize: 12),
                              ),
                            )),
                    if (_previewWinningStores.where((s) => s.prizeTier == 'second').length > 10)
                      Text(
                        '+${_previewWinningStores.where((s) => s.prizeTier == 'second').length - 10}개',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    const SizedBox(height: 20),
                    // 발행 버튼
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: (_publishedStatus[_previewRound.toString()] ?? false)
                            ? null
                            : () => _publishRound(_previewRound!),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: Text(
                          (_publishedStatus[_previewRound.toString()] ?? false) ? '✅ 발행됨' : '📢 발행하기',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            Row(
              children: [
                const Text(
                  '생성된 당첨회차',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    onPressed: _isLoadingRounds
                        ? null
                        : () {
                            setState(() => _isLoadingRounds = true);
                            _refreshRounds();
                          },
                    icon: _isLoadingRounds
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, color: Colors.purple),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_isLoadingRounds)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
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
                  .map((item) {
                final loadedCount = _loadedStoreCountByRound[item.round] ?? 0;
                final isLoading = _loadingRoundSet.contains(item.round);
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
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => _fillFormForEdit(item),
                                child: const Text('수정'),
                              ),
                              TextButton(
                                onPressed: () => _deleteRound(item),
                                child: const Text('삭제'),
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
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: OutlinedButton(
                                onPressed: isLoading ? null : () => _loadWinningStores(item),
                                child: isLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('당첨지점 로드'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            height: 40,
                            child: ElevatedButton(
                              onPressed: loadedCount > 0 ? () => _loadPreview(item) : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                              ),
                              child: const Text(
                                '미리보기',
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (loadedCount > 0)
                            Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
                          if (loadedCount == 0)
                            Icon(Icons.radio_button_unchecked, size: 16, color: Colors.grey.shade400),
                          const SizedBox(width: 6),
                          Text(
                            loadedCount > 0
                                ? '당첨지점 $loadedCount건 로드됨'
                                : '당첨지점 로드 대기중',
                            style: TextStyle(
                              fontSize: 12,
                              color: loadedCount > 0 ? Colors.green.shade700 : Colors.grey.shade700,
                              fontWeight: loadedCount > 0 ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton(
                          onPressed: (_publishedStatus[item.round.toString()] ?? false)
                              ? null
                              : () => _publishRound(item.round),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          child: Text(
                            (_publishedStatus[item.round.toString()] ?? false) ? '✅ 발행됨' : '📢 발행하기',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            if (_rounds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final totalPages = _totalPagesFor(_rounds.length);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: _currentPage > 1
                            ? () => setState(() => _currentPage--)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        '$_currentPage / $totalPages',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        onPressed: _currentPage < totalPages
                            ? () => setState(() => _currentPage++)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
