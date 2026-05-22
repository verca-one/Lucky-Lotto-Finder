import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../models/lotto_winning_number.dart';

class AiNumberContent extends StatefulWidget {
  const AiNumberContent({super.key});

  @override
  State<AiNumberContent> createState() => _AiNumberContentState();
}

class _AiNumberContentState extends State<AiNumberContent> {
  List<LottoWinningNumber> _recentWinnings = [];
  bool _isLoading = true;
  bool _isGenerating = false;
  List<List<int>> _generatedSets = [];
  List<bool> _heldSets = [];

  // 7381 순환 배열
  static const List<int> _cycle7381 = [7, 3, 8, 1];
  static const Map<int, String> _stageNames = {
    7: '저번호 분산형',
    3: '연결형',
    8: '고번호 중심형',
    1: '마무리형',
  };
  static const Map<int, String> _stageDesc = {
    7: '1~15 저번호 활성, 번호가 넓게 퍼짐',
    3: '20번대 중심, 균형형 구조',
    8: '30번대 강세, 연속수 자주 등장',
    1: '40번대 강화, 끝번호 강세',
  };
  static const Map<int, Color> _stageColors = {
    7: Color(0xFF1565C0),
    3: Color(0xFF2E7D32),
    8: Color(0xFFE65100),
    1: Color(0xFF6A1B9A),
  };

  // 번호 입력
  final List<TextEditingController> _numControllers =
      List.generate(6, (_) => TextEditingController());
  final TextEditingController _bonusController = TextEditingController();

  // 고정 번호 (슬롯 인덱스 → 번호, null이면 비고정)
  final Map<int, int?> _fixedSlots = {}; // 0~5 슬롯

  // 분석 결과
  int? _currentStage;
  int? _nextStage;
  int? _inputRound;
  String _analysisDetail = '';
  bool _analyzed = false;

  @override
  void initState() {
    super.initState();
    _loadRecentWinnings();
  }

  @override
  void dispose() {
    for (final c in _numControllers) {
      c.dispose();
    }
    _bonusController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentWinnings() async {
    try {
      final results = await SupabaseService.getRecentWinningNumbers(20);
      if (!mounted) return;
      setState(() {
        _recentWinnings = results;
        _isLoading = false;
      });
      // 최근 회차 번호를 자동으로 입력란에 채우기
      if (results.isNotEmpty) {
        final latest = results.first;
        for (int i = 0; i < 6 && i < latest.numbers.length; i++) {
          _numControllers[i].text = '${latest.numbers[i]}';
        }
        _bonusController.text = '${latest.bonusNumber}';
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  /// 입력된 번호 파싱
  List<int>? _parseInputNumbers() {
    final nums = <int>[];
    for (final c in _numControllers) {
      final v = int.tryParse(c.text.trim());
      if (v == null || v < 1 || v > 45) return null;
      nums.add(v);
    }
    if (nums.toSet().length != 6) return null;
    return nums..sort();
  }

  int? _parseBonusNumber() {
    final v = int.tryParse(_bonusController.text.trim());
    if (v == null || v < 1 || v > 45) return null;
    return v;
  }

  /// 7381 분석 실행
  void _analyze() {
    final nums = _parseInputNumbers();
    final bonus = _parseBonusNumber();
    if (nums == null || bonus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('1~45 범위의 중복 없는 6개 번호 + 보너스를 입력하세요')),
      );
      return;
    }

    // 번호 분포 분석
    final low = nums.where((n) => n >= 1 && n <= 15).length;     // 저번호
    final mid = nums.where((n) => n >= 16 && n <= 29).length;    // 중번호 (20번대 중심)
    final high30 = nums.where((n) => n >= 30 && n <= 39).length; // 30번대
    final high40 = nums.where((n) => n >= 40 && n <= 45).length; // 40번대

    // 연속수 체크
    int consecutive = 0;
    for (int i = 0; i < nums.length - 1; i++) {
      if (nums[i + 1] - nums[i] == 1) consecutive++;
    }

    // 현재 단계 판정
    int stage;
    String detail;

    if (low >= 2 && high40 == 0 && high30 <= 1) {
      stage = 7;
      detail = '저번호(1~15) ${low}개 활성, 분산형 패턴\n'
          '고번호(40+) 없음 → 7단계(저번호 분산형) 판정';
    } else if (mid >= 2 && (low + high40) <= 2) {
      stage = 3;
      detail = '중번호(16~29) ${mid}개 중심, 균형 구조\n'
          '양쪽 극단 약함 → 3단계(연결형) 판정';
    } else if (high30 >= 2 || consecutive >= 2) {
      stage = 8;
      detail = '30번대 ${high30}개 강세${consecutive > 0 ? ", 연속수 ${consecutive}쌍" : ""}\n'
          '고번호 집중 → 8단계(고번호 중심형) 판정';
    } else if (high40 >= 1 && nums.last >= 41) {
      stage = 1;
      detail = '40번대 ${high40}개 포함, 끝번호(${nums.last}) 강세\n'
          '고점 마무리 → 1단계(마무리형) 판정';
    } else {
      // 종합 점수로 판정
      final scores = {7: low * 2.0, 3: mid * 1.5, 8: high30 * 2.0 + consecutive, 1: high40 * 2.5};
      stage = scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      detail = '저:$low 중:$mid 30대:$high30 40대:$high40 연속:$consecutive\n'
          '종합 분석 → ${stage}단계(${_stageNames[stage]}) 판정';
    }

    // 다음 단계 예측
    final currentIdx = _cycle7381.indexOf(stage);
    final nextIdx = (currentIdx + 1) % _cycle7381.length;
    final nextStage = _cycle7381[nextIdx];

    // 회차 매핑 (최근 데이터에서)
    int? round;
    if (_recentWinnings.isNotEmpty) {
      round = _recentWinnings.first.round;
    }

    setState(() {
      _currentStage = stage;
      _nextStage = nextStage;
      _inputRound = round;
      _analysisDetail = detail;
      _analyzed = true;
    });
  }

  /// 7381 법칙 기반 번호 생성 (다음 단계 성향 반영 + 고정번호)
  List<int> _generateByStage(int stage) {
    final rng = Random();
    final fixed = <int>{};

    // 고정 번호 수집
    for (final entry in _fixedSlots.entries) {
      if (entry.value != null) {
        fixed.add(entry.value!);
      }
    }

    final result = <int>{...fixed};

    switch (stage) {
      case 7: // 저번호 분산형: 1~15에서 2~3개, 나머지 분산
        _addFromRange(result, 1, 15, max(0, 2 - fixed.where((n) => n <= 15).length), rng);
        _addFromRange(result, 16, 25, 1, rng);
        _addFromRange(result, 26, 35, 1, rng);
        _addFromRange(result, 36, 45, max(0, 1 - fixed.where((n) => n >= 36).length), rng);
        break;
      case 3: // 연결형: 20번대 중심 2~3개
        _addFromRange(result, 1, 15, max(0, 1 - fixed.where((n) => n <= 15).length), rng);
        _addFromRange(result, 16, 29, max(0, 3 - fixed.where((n) => n >= 16 && n <= 29).length), rng);
        _addFromRange(result, 30, 39, 1, rng);
        _addFromRange(result, 40, 45, max(0, 1 - fixed.where((n) => n >= 40).length), rng);
        break;
      case 8: // 고번호 중심: 30번대 2~3개 + 연속수
        _addFromRange(result, 1, 15, 1, rng);
        _addFromRange(result, 16, 29, 1, rng);
        // 30번대에서 연속수 포함
        final base30 = 30 + rng.nextInt(8); // 30~37
        if (!result.contains(base30)) result.add(base30);
        if (!result.contains(base30 + 1) && base30 + 1 <= 39) result.add(base30 + 1);
        _addFromRange(result, 30, 39, max(0, 3 - result.where((n) => n >= 30 && n <= 39).length), rng);
        break;
      case 1: // 마무리형: 40번대 1~2개 + 끝번호
        _addFromRange(result, 1, 15, 1, rng);
        _addFromRange(result, 16, 29, 1, rng);
        _addFromRange(result, 30, 39, 1, rng);
        _addFromRange(result, 40, 45, max(0, 2 - fixed.where((n) => n >= 40).length), rng);
        break;
    }

    // 부족하면 랜덤 채우기
    while (result.length < 6) {
      final n = rng.nextInt(45) + 1;
      result.add(n);
    }

    // 6개로 맞추기 (고정 번호 유지)
    final sorted = result.toList()..sort();
    if (sorted.length > 6) {
      final keep = <int>{...fixed};
      final others = sorted.where((n) => !fixed.contains(n)).toList()..shuffle(rng);
      keep.addAll(others.take(6 - keep.length));
      final final6 = keep.toList()..sort();
      return final6.take(6).toList();
    }

    // 홀짝 검증
    final oddCount = sorted.where((n) => n % 2 == 1).length;
    if (oddCount < 2 || oddCount > 4) {
      return _generateByStage(stage);
    }

    // 합산 검증
    final sum = sorted.take(6).fold<int>(0, (a, b) => a + b);
    if (sum < 80 || sum > 200) {
      return _generateByStage(stage);
    }

    return sorted.take(6).toList();
  }

  void _addFromRange(Set<int> result, int lo, int hi, int count, Random rng) {
    if (count <= 0 || result.length >= 6) return;
    final pool = List.generate(hi - lo + 1, (i) => lo + i)
      ..removeWhere((n) => result.contains(n));
    pool.shuffle(rng);
    for (int i = 0; i < count && i < pool.length && result.length < 6; i++) {
      result.add(pool[i]);
    }
  }

  Future<void> _generateNumbers() async {
    if (_nextStage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 번호를 입력하고 분석을 실행하세요')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    await Future.delayed(const Duration(milliseconds: 400));

    final newSets = <List<int>>[];
    final newHeld = <bool>[];

    for (int i = 0; i < _generatedSets.length; i++) {
      if (i < _heldSets.length && _heldSets[i]) {
        newSets.add(_generatedSets[i]);
        newHeld.add(true);
      }
    }
    while (newSets.length < 5) {
      newSets.add(_generateByStage(_nextStage!));
      newHeld.add(false);
    }

    if (!mounted) return;
    setState(() {
      _generatedSets = newSets;
      _heldSets = newHeld;
      _isGenerating = false;
    });
  }

  Future<void> _saveSets() async {
    if (_generatedSets.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('my_lotto_numbers') ?? [];
    for (final numbers in _generatedSets) {
      saved.insert(0, jsonEncode({
        'numbers': numbers,
        'date': DateTime.now().toIso8601String(),
        'type': '7381',
      }));
    }
    while (saved.length > 50) {
      saved.removeLast();
    }
    await prefs.setStringList('my_lotto_numbers', saved);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_generatedSets.length}세트가 저장되었습니다!')),
    );
  }

  void _removeSet(int index) {
    setState(() {
      _generatedSets.removeAt(index);
      if (index < _heldSets.length) _heldSets.removeAt(index);
    });
  }

  void _toggleHold(int index) {
    setState(() {
      while (_heldSets.length <= index) {
        _heldSets.add(false);
      }
      _heldSets[index] = !_heldSets[index];
    });
  }

  Color _getBallColor(int number) {
    if (number <= 10) return Colors.yellow.shade700;
    if (number <= 20) return Colors.blue;
    if (number <= 30) return Colors.red;
    if (number <= 40) return Colors.grey.shade700;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3, color: const Color(0xFF1565C0))),
            const SizedBox(height: 16),
            Text('데이터 로딩중...', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_awesome, color: Colors.purple.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('7381 법칙 분석', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('회차 흐름의 성격을 분석합니다', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 7381 순환 시각화
          _buildCycleVisual(),
          const SizedBox(height: 20),

          // 번호 입력 섹션
          _buildInputSection(),
          const SizedBox(height: 16),

          // 분석 버튼
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _analyze,
              icon: const Icon(Icons.analytics_rounded, size: 20),
              label: const Text('분석하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 분석 결과
          if (_analyzed) ...[
            _buildAnalysisResult(),
            const SizedBox(height: 20),

            // 번호 고정 섹션
            _buildFixedNumberSection(),
            const SizedBox(height: 16),

            // 생성 버튼
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generateNumbers,
                icon: _isGenerating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome, size: 20),
                label: Text(
                  _isGenerating ? '생성 중...' : '${_stageNames[_nextStage]} 기반 5세트 생성',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _stageColors[_nextStage] ?? Colors.purple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // 생성된 번호 세트
          if (_generatedSets.isNotEmpty) ...[
            _buildGeneratedSets(),
          ],
        ],
      ),
    );
  }

  /// 7381 순환 시각화
  Widget _buildCycleVisual() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('7381 순환 규칙', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('7 → 3 → 8 → 1 → 7 → ...  반복', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 14),
          Row(
            children: [
              for (int i = 0; i < _cycle7381.length; i++) ...[
                Expanded(child: _buildStageBox(_cycle7381[i], isActive: _currentStage == _cycle7381[i], isNext: _nextStage == _cycle7381[i])),
                if (i < _cycle7381.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey.shade400),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStageBox(int stage, {bool isActive = false, bool isNext = false}) {
    final color = _stageColors[stage]!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: isNext ? color.withValues(alpha: 0.15) : (isActive ? color.withValues(alpha: 0.08) : Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isNext ? color : (isActive ? color.withValues(alpha: 0.5) : const Color(0xFFE0E0E0)),
          width: isNext ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            '$stage',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            _stageNames[stage]!.replaceAll(' ', '\n'),
            style: TextStyle(fontSize: 9, color: isActive || isNext ? color : Colors.grey.shade600, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
          if (isActive)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                child: const Text('현재', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          if (isNext)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                child: const Text('예측', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  /// 번호 입력 섹션
  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF1565C0)),
              const SizedBox(width: 6),
              const Text('당첨 번호 입력', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_recentWinnings.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    final latest = _recentWinnings.first;
                    for (int i = 0; i < 6 && i < latest.numbers.length; i++) {
                      _numControllers[i].text = '${latest.numbers[i]}';
                    }
                    _bonusController.text = '${latest.bonusNumber}';
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '최근 회차 불러오기',
                      style: TextStyle(fontSize: 11, color: const Color(0xFF1565C0), fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 6개 번호 입력
          Row(
            children: List.generate(6, (i) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 5 ? 6 : 0),
                  child: _buildNumInput(_numControllers[i], '${i + 1}'),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          // 보너스 번호
          Row(
            children: [
              Text('보너스', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                child: _buildNumInput(_bonusController, 'B'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumInput(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(2),
      ],
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400, fontWeight: FontWeight.w400),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
        ),
      ),
    );
  }

  /// 분석 결과
  Widget _buildAnalysisResult() {
    if (_currentStage == null || _nextStage == null) return const SizedBox.shrink();

    final curColor = _stageColors[_currentStage]!;
    final nextColor = _stageColors[_nextStage]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [curColor.withValues(alpha: 0.05), nextColor.withValues(alpha: 0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: curColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_rounded, size: 18, color: curColor),
              const SizedBox(width: 6),
              const Text('분석 결과', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          // 현재 단계
          _buildStageResultRow('현재 회차 성격', _currentStage!, curColor),
          const SizedBox(height: 10),
          // 분석 상세
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _analysisDetail,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          // 다음 예측
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: nextColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: nextColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.arrow_forward_rounded, size: 16, color: nextColor),
                    const SizedBox(width: 6),
                    Text('다음 회차 예측', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: nextColor)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${_nextStage}단계: ${_stageNames[_nextStage]}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: nextColor),
                ),
                const SizedBox(height: 4),
                Text(
                  _stageDesc[_nextStage]!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageResultRow(String label, int stage, Color color) {
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(
            '$stage단계 ${_stageNames[stage]}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }

  /// 번호 고정 섹션
  Widget _buildFixedNumberSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.push_pin_rounded, size: 16, color: Color(0xFFFF8F00)),
              const SizedBox(width: 6),
              const Text('번호 고정', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _fixedSlots.clear()),
                child: Text('전체 해제', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('특정 자리에 원하는 번호를 고정합니다', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 12),
          Row(
            children: List.generate(6, (i) {
              final fixedVal = _fixedSlots[i];
              final hasValue = fixedVal != null;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 5 ? 6 : 0),
                  child: GestureDetector(
                    onTap: () => _showFixDialog(i),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: hasValue ? const Color(0xFFFFF3E0) : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hasValue ? const Color(0xFFFF8F00) : const Color(0xFFE0E0E0),
                          width: hasValue ? 1.5 : 1,
                        ),
                      ),
                      child: Center(
                        child: hasValue
                            ? Text('$fixedVal', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFE65100)))
                            : Icon(Icons.add_rounded, size: 18, color: Colors.grey.shade400),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  void _showFixDialog(int slotIndex) {
    final controller = TextEditingController(
      text: _fixedSlots[slotIndex] != null ? '${_fixedSlots[slotIndex]}' : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${slotIndex + 1}번째 자리 고정', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '1~45',
                hintStyle: TextStyle(fontSize: 18, color: Colors.grey.shade400),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _fixedSlots.remove(slotIndex));
              Navigator.pop(ctx);
            },
            child: const Text('해제'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v != null && v >= 1 && v <= 45) {
                setState(() => _fixedSlots[slotIndex] = v);
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
            child: const Text('확인', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// 생성된 번호 세트
  Widget _buildGeneratedSets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.format_list_numbered, size: 18, color: _stageColors[_nextStage] ?? Colors.purple),
            const SizedBox(width: 6),
            Text(
              '추천 번호 (${_generatedSets.length}세트)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(_generatedSets.length, (i) {
          final nums = _generatedSets[i];
          final sum = nums.fold<int>(0, (a, b) => a + b);
          final oddCount = nums.where((n) => n % 2 == 1).length;
          final isHeld = i < _heldSets.length && _heldSets[i];
          final stageColor = _stageColors[_nextStage] ?? Colors.purple;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isHeld ? stageColor.withValues(alpha: 0.12) : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isHeld ? stageColor : const Color(0xFFE0E0E0),
                width: isHeld ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: stageColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        children: nums.map((n) {
                          final isFixed = _fixedSlots.values.contains(n);
                          return _ballWidget(n, highlighted: isFixed);
                        }).toList(),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _toggleHold(i),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isHeld ? Icons.lock_rounded : Icons.lock_open_rounded,
                          size: 20,
                          color: isHeld ? stageColor : Colors.grey.shade400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _removeSet(i),
                      child: Icon(Icons.close_rounded, size: 20, color: Colors.grey.shade400),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const SizedBox(width: 34),
                    Text(
                      '합:$sum  홀:$oddCount 짝:${6 - oddCount}',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                    if (isHeld) ...[
                      const SizedBox(width: 8),
                      Text('HOLD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: stageColor)),
                    ],
                  ],
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _saveSets,
            icon: const Icon(Icons.bookmark_add_rounded, size: 20),
            label: Text('${_generatedSets.length}세트 저장하기', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1565C0),
              side: const BorderSide(color: Color(0xFFBBDEFB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ballWidget(int number, {bool highlighted = false}) {
    final color = _getBallColor(number);
    return Container(
      width: 34, height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: highlighted ? Border.all(color: const Color(0xFFFF8F00), width: 2.5) : null,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      child: Center(
        child: Text(
          '$number',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ),
    );
  }
}
