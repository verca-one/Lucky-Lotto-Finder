import 'package:flutter/material.dart';
import '../models/lotto_winning_number.dart';
import '../services/firestore_service.dart';

// ── 분석 결과 모델 ──────────────────────────────────────────────
class PatternResult {
  final List<int> targetNumbers;
  final int supportCount;
  final int triggerCount;
  final double conditionalRate;
  final double baseRate;
  final double lift;
  final String confidenceLevel;

  PatternResult({
    required this.targetNumbers,
    required this.supportCount,
    required this.triggerCount,
    required this.conditionalRate,
    required this.baseRate,
    required this.lift,
    required this.confidenceLevel,
  });

  Map<String, dynamic> toJson() => {
        'targetNumbers': targetNumbers,
        'supportCount': supportCount,
        'triggerCount': triggerCount,
        'conditionalRate': conditionalRate,
        'baseRate': baseRate,
        'lift': lift,
        'confidenceLevel': confidenceLevel,
      };
}

// ── 분석 엔진 ────────────────────────────────────────────────────
class PatternAnalysisEngine {
  final List<LottoWinningNumber> _sorted; // round ascending

  PatternAnalysisEngine(List<LottoWinningNumber> rounds)
      : _sorted = [...rounds]..sort((a, b) => a.round.compareTo(b.round));

  List<int> get _all => _sorted.isEmpty ? [] : [];

  // 숫자 추출 (보너스 포함 여부)
  List<int> _nums(LottoWinningNumber r, bool bonus) =>
      bonus ? [...r.numbers, r.bonusNumber] : [...r.numbers];

  // 트리거 조건에 맞는 회차 인덱스 목록
  List<int> _triggerIndices(List<int> trigger, bool bonus) {
    final result = <int>[];
    for (int i = 0; i < _sorted.length - 1; i++) {
      final nums = _nums(_sorted[i], bonus);
      if (trigger.every((t) => nums.contains(t))) {
        result.add(i);
      }
    }
    return result;
  }

  // 전체 출현률 계산
  Map<int, double> _baseRates(bool bonus) {
    final counts = <int, int>{};
    for (final r in _sorted) {
      for (final n in _nums(r, bonus)) {
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    final total = _sorted.length.toDouble();
    return counts.map((k, v) => MapEntry(k, v / total));
  }

  // 전체 페어 출현률
  Map<String, double> _basePairRates() {
    final counts = <String, int>{};
    for (final r in _sorted) {
      final nums = r.numbers;
      for (int i = 0; i < nums.length; i++) {
        for (int j = i + 1; j < nums.length; j++) {
          final key = '${nums[i]},${nums[j]}';
          counts[key] = (counts[key] ?? 0) + 1;
        }
      }
    }
    final total = _sorted.length.toDouble();
    return counts.map((k, v) => MapEntry(k, v / total));
  }

  String _confidence(int support) {
    if (support >= 30) return 'high';
    if (support >= 10) return 'medium';
    return 'low';
  }

  // ── 단일/다중 숫자 분석 ──────────────────────────────────────
  List<PatternResult> analyzeNumbers({
    required List<int> triggerNumbers,
    required bool includeBonus,
    required int minSupport,
    required double minLift,
    required int topN,
  }) {
    if (_sorted.isEmpty) return [];
    final indices = _triggerIndices(triggerNumbers, includeBonus);
    final triggerCount = indices.length;
    if (triggerCount == 0) return [];

    final baseRates = _baseRates(includeBonus);
    final nextCounts = <int, int>{};

    for (final idx in indices) {
      for (final n in _nums(_sorted[idx + 1], includeBonus)) {
        nextCounts[n] = (nextCounts[n] ?? 0) + 1;
      }
    }

    final results = <PatternResult>[];
    for (final entry in nextCounts.entries) {
      final support = entry.value;
      if (support < minSupport) continue;
      final condRate = support / triggerCount;
      final base = baseRates[entry.key] ?? 0;
      final lift = base > 0 ? condRate / base : 0.0;
      if (lift < minLift) continue;

      results.add(PatternResult(
        targetNumbers: [entry.key],
        supportCount: support,
        triggerCount: triggerCount,
        conditionalRate: condRate,
        baseRate: base,
        lift: lift,
        confidenceLevel: _confidence(support),
      ));
    }

    results.sort((a, b) => b.lift.compareTo(a.lift));
    return topN > 0 ? results.take(topN).toList() : results;
  }

  // ── 후속 조합(페어) 분석 ──────────────────────────────────────
  List<PatternResult> analyzePairs({
    required List<int> triggerNumbers,
    required bool includeBonus,
    required int minSupport,
    required double minLift,
    required int topN,
  }) {
    if (_sorted.isEmpty) return [];
    final indices = _triggerIndices(triggerNumbers, includeBonus);
    final triggerCount = indices.length;
    if (triggerCount == 0) return [];

    final basePairRates = _basePairRates();
    final pairCounts = <String, int>{};

    for (final idx in indices) {
      final nextNums = _sorted[idx + 1].numbers;
      for (int i = 0; i < nextNums.length; i++) {
        for (int j = i + 1; j < nextNums.length; j++) {
          final key = '${nextNums[i]},${nextNums[j]}';
          pairCounts[key] = (pairCounts[key] ?? 0) + 1;
        }
      }
    }

    final results = <PatternResult>[];
    for (final entry in pairCounts.entries) {
      final support = entry.value;
      if (support < minSupport) continue;
      final condRate = support / triggerCount;
      final base = basePairRates[entry.key] ?? 0;
      final lift = base > 0 ? condRate / base : 0.0;
      if (lift < minLift) continue;

      final parts = entry.key.split(',').map(int.parse).toList();
      results.add(PatternResult(
        targetNumbers: parts,
        supportCount: support,
        triggerCount: triggerCount,
        conditionalRate: condRate,
        baseRate: base,
        lift: lift,
        confidenceLevel: _confidence(support),
      ));
    }

    results.sort((a, b) => b.lift.compareTo(a.lift));
    return topN > 0 ? results.take(topN).toList() : results;
  }

  // ── 이번주 추천번호 (최신 회차 기반) ──────────────────────────
  List<PatternResult> weeklyRecommendation({bool includeBonus = false}) {
    if (_sorted.length < 2) return [];
    final latest = _sorted.last;
    return analyzeNumbers(
      triggerNumbers: latest.numbers,
      includeBonus: includeBonus,
      minSupport: 5,
      minLift: 1.1,
      topN: 10,
    );
  }

  LottoWinningNumber? get latestRound =>
      _sorted.isEmpty ? null : _sorted.last;

  int get totalRounds => _sorted.length;
}

// ── 메인 화면 ─────────────────────────────────────────────────────
class AdminPatternAnalysisScreen extends StatefulWidget {
  const AdminPatternAnalysisScreen({super.key});

  @override
  State<AdminPatternAnalysisScreen> createState() =>
      _AdminPatternAnalysisScreenState();
}

class _AdminPatternAnalysisScreenState
    extends State<AdminPatternAnalysisScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<LottoWinningNumber> _allRounds = [];
  bool _isLoading = true;
  String? _error;
  PatternAnalysisEngine? _engine;

  // ── 당첨번호 입력 폼 ──────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _roundController = TextEditingController();
  final _yearController = TextEditingController();
  final _monthController = TextEditingController();
  final _dayController = TextEditingController();
  final _bonusController = TextEditingController();
  final List<TextEditingController> _numControllers =
      List.generate(6, (_) => TextEditingController());
  bool _isSaving = false;
  bool _inputExpanded = true;

  // 설정
  final Set<int> _triggerNumbers = {};
  bool _includeBonus = false;
  int _minSupport = 10;
  double _minLift = 1.1;
  int _topN = 20;

  // 결과
  List<PatternResult> _numberResults = [];
  List<PatternResult> _pairResults = [];
  bool _isAnalyzing = false;
  bool _hasAnalyzed = false;

  // 이번주 추천
  List<PatternResult> _weeklyRec = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _roundController.dispose();
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    _bonusController.dispose();
    for (final c in _numControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Firestore lotto_draws 컬렉션 → 단일 진실 공급원
      final rounds = await FirestoreService.getAllLottoDraws();
      final engine = PatternAnalysisEngine(rounds);
      final weekly = engine.weeklyRecommendation();
      if (!mounted) return;
      setState(() {
        _allRounds = rounds;
        _engine = engine;
        _weeklyRec = weekly;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _analyze() {
    final engine = _engine;
    if (engine == null || _triggerNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('분석할 숫자를 1개 이상 선택해주세요')),
      );
      return;
    }
    setState(() => _isAnalyzing = true);

    final trigger = _triggerNumbers.toList()..sort();
    final numResults = engine.analyzeNumbers(
      triggerNumbers: trigger,
      includeBonus: _includeBonus,
      minSupport: _minSupport,
      minLift: _minLift,
      topN: _topN,
    );
    final pairResults = engine.analyzePairs(
      triggerNumbers: trigger,
      includeBonus: _includeBonus,
      minSupport: _minSupport,
      minLift: _minLift,
      topN: _topN,
    );

    setState(() {
      _numberResults = numResults;
      _pairResults = pairResults;
      _isAnalyzing = false;
      _hasAnalyzed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      appBar: AppBar(
        title: const Text('패턴 분석', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text('데이터를 불러올 수 없습니다\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWinningNumberInputCard(),
          const SizedBox(height: 16),
          _buildWeeklyRecommendCard(),
          const SizedBox(height: 16),
          _buildSettingsCard(),
          const SizedBox(height: 12),
          _buildAnalyzeButton(),
          if (_hasAnalyzed) ...[
            const SizedBox(height: 16),
            _buildResultsSection(),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── 당첨번호 저장 ────────────────────────────────────────────
  int? _parseNum(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null || n < 1 || n > 45) return null;
    return n;
  }

  Future<void> _saveWinningNumber() async {
    if (!_formKey.currentState!.validate()) return;

    final round = int.tryParse(_roundController.text.trim());
    final year = int.tryParse(_yearController.text.trim());
    final month = int.tryParse(_monthController.text.trim());
    final day = int.tryParse(_dayController.text.trim());
    final numbers = _numControllers.map((c) => _parseNum(c.text)).whereType<int>().toList();
    final bonus = _parseNum(_bonusController.text);

    if (round == null || year == null || month == null || day == null ||
        bonus == null || numbers.length != 6) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('입력값을 다시 확인해주세요')));
      return;
    }
    if (numbers.toSet().length != 6) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('당첨번호 6개는 중복 없이 입력해주세요')));
      return;
    }
    if (numbers.contains(bonus)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('보너스 번호는 당첨번호와 달라야 합니다')));
      return;
    }

    final drawDate =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

    setState(() => _isSaving = true);
    try {
      final item = LottoWinningNumber(
        drawDate: drawDate,
        round: round,
        numbers: numbers,
        bonusNumber: bonus,
      );
      // Firestore lotto_draws에 저장 (단일 진실 공급원)
      await FirestoreService.saveLottoDraw(item);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$round회 당첨번호가 Firestore에 저장됐습니다. 분석 데이터 갱신 중...')));

      // 폼 초기화
      _roundController.clear();
      _yearController.clear();
      _monthController.clear();
      _dayController.clear();
      _bonusController.clear();
      for (final c in _numControllers) {
        c.clear();
      }
      setState(() {
        _inputExpanded = false;
        _isSaving = false;
      });

      // 분석 엔진 새로 로드
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      setState(() => _isSaving = false);
    }
  }

  // ── 당첨번호 입력 카드 ────────────────────────────────────────
  Widget _buildWinningNumberInputCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 헤더 (펼치기/접기)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _inputExpanded = !_inputExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_note_rounded, color: Colors.purple, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('당첨번호 입력',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A1A))),
                        Text('회차 · 날짜 · 번호 입력 후 저장',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Icon(
                    _inputExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          // 폼 (접기 가능)
          if (_inputExpanded) ...[
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 회차
                    TextFormField(
                      controller: _roundController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '회차',
                        hintText: '예: 1160',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n <= 0) return '회차를 입력해주세요';
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    // 날짜
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _yearController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: '년',
                              hintText: '2026',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            validator: (v) {
                              final n = int.tryParse((v ?? '').trim());
                              if (n == null || n < 2002 || n > 2100) return '년';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _monthController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: '월',
                              hintText: '08',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            validator: (v) {
                              final n = int.tryParse((v ?? '').trim());
                              if (n == null || n < 1 || n > 12) return '월';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _dayController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: '일',
                              hintText: '09',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            validator: (v) {
                              final n = int.tryParse((v ?? '').trim());
                              if (n == null || n < 1 || n > 31) return '일';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('당첨번호 6개',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF333333))),
                    const SizedBox(height: 8),
                    // 번호 6개 — 2행 3열
                    Column(
                      children: [
                        Row(
                          children: List.generate(3, (i) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                              child: _buildNumField(_numControllers[i], i + 1),
                            ),
                          )),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: List.generate(3, (i) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                              child: _buildNumField(_numControllers[i + 3], i + 4),
                            ),
                          )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 보너스
                    SizedBox(
                      width: 120,
                      child: TextFormField(
                        controller: _bonusController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '보너스',
                          hintText: '1~45',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.orange),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        validator: (v) {
                          if (_parseNum(v) == null) return '1~45';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveWinningNumber,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(_isSaving ? '저장 중...' : '저장하기'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNumField(TextEditingController controller, int index) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        labelText: '$index번',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      validator: (v) {
        if (_parseNum(v) == null) return '!';
        return null;
      },
    );
  }

  // ── 이번주 추천번호 카드 ─────────────────────────────────────
  Widget _buildWeeklyRecommendCard() {
    final engine = _engine;
    final latest = engine?.latestRound;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.amber, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '패턴 기반 이번주 추천번호',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${engine?.totalRounds ?? 0}회 분석',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white70),
                ),
              ),
            ],
          ),
          if (latest != null) ...[
            const SizedBox(height: 8),
            Text(
              '기준: ${latest.round}회 당첨번호',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: latest.numbers.map((n) => _numBall(n, small: true)).toList(),
            ),
          ],
          const SizedBox(height: 14),
          if (_weeklyRec.isEmpty)
            const Text('추천 데이터 부족 (당첨번호를 더 입력해주세요)',
                style: TextStyle(color: Colors.white60, fontSize: 13))
          else ...[
            const Text('후속 패턴 TOP 추천',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _weeklyRec.take(10).map((r) {
                final n = r.targetNumbers.first;
                return _buildRecChip(n, r.lift, r.confidenceLevel);
              }).toList(),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '※ 이 추천은 과거 데이터의 통계적 패턴을 보여드리는 것이며,\n   실제 당첨 확률을 보장하지 않습니다.',
              style: TextStyle(fontSize: 11, color: Colors.white60, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecChip(int num, double lift, String confidence) {
    final color = confidence == 'high'
        ? Colors.greenAccent
        : confidence == 'medium'
            ? Colors.amberAccent
            : Colors.white54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(
        children: [
          Text(
            num.toString().padLeft(2, '0'),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          Text(
            'Lift ${lift.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 9, color: color),
          ),
        ],
      ),
    );
  }

  // ── 설정 카드 ──────────────────────────────────────────────────
  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('분석 설정',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1565C0))),
          const SizedBox(height: 14),
          // 트리거 숫자 선택
          const Text('지난 회차 기준 숫자 선택 (복수 가능)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            _triggerNumbers.isEmpty
                ? '숫자를 선택하면 해당 숫자가 포함된 과거 회차 다음 회차를 분석합니다'
                : '선택: ${(_triggerNumbers.toList()..sort()).join(", ")}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          _buildNumberGrid(),
          const SizedBox(height: 12),
          // 옵션들
          _buildOptionRow('보너스번호 포함', _includeBonus,
              (v) => setState(() => _includeBonus = v)),
          const Divider(height: 20),
          _buildMinSupportRow(),
          const SizedBox(height: 8),
          _buildMinLiftRow(),
          const SizedBox(height: 8),
          _buildTopNRow(),
        ],
      ),
    );
  }

  Widget _buildNumberGrid() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        GestureDetector(
          onTap: () => setState(() => _triggerNumbers.clear()),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _triggerNumbers.isEmpty
                  ? const Color(0xFF1565C0)
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '전체 해제',
              style: TextStyle(
                fontSize: 11,
                color: _triggerNumbers.isEmpty ? Colors.white : Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        ...List.generate(45, (i) {
          final n = i + 1;
          final selected = _triggerNumbers.contains(n);
          return GestureDetector(
            onTap: () => setState(() {
              if (selected) {
                _triggerNumbers.remove(n);
              } else {
                _triggerNumbers.add(n);
              }
            }),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? _ballColor(n) : const Color(0xFFF5F5F5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _ballColor(n) : const Color(0xFFE0E0E0),
                ),
              ),
              child: Text(
                '$n',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildOptionRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF1565C0),
        ),
      ],
    );
  }

  Widget _buildMinSupportRow() {
    const options = [5, 10, 20, 30];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('최소 표본 수: $_minSupport회',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          children: options.map((v) {
            final sel = _minSupport == v;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _minSupport = v),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFF1565C0) : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$v회',
                      style: TextStyle(
                          fontSize: 12,
                          color: sel ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMinLiftRow() {
    const options = [1.0, 1.1, 1.2, 1.5];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('최소 Lift: $_minLift',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          children: options.map((v) {
            final sel = _minLift == v;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _minLift = v),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFF1565C0) : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$v',
                      style: TextStyle(
                          fontSize: 12,
                          color: sel ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTopNRow() {
    final options = {'TOP 10': 10, 'TOP 20': 20, 'TOP 30': 30, '전체': 0};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('결과 개수',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          children: options.entries.map((e) {
            final sel = _topN == e.value;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _topN = e.value),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFF1565C0) : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(e.key,
                      style: TextStyle(
                          fontSize: 12,
                          color: sel ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── 분석 버튼 ─────────────────────────────────────────────────
  Widget _buildAnalyzeButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isAnalyzing ? null : _analyze,
        icon: _isAnalyzing
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.analytics_rounded),
        label: Text(_isAnalyzing ? '분석 중...' : '패턴 분석하기'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ── 결과 섹션 ─────────────────────────────────────────────────
  Widget _buildResultsSection() {
    final trigger = _triggerNumbers.toList()..sort();
    final engine = _engine;
    if (engine == null) return const SizedBox.shrink();

    final idx = engine._triggerIndices(trigger, _includeBonus);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 조건 요약
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF90CAF9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: Color(0xFF1565C0)),
                  const SizedBox(width: 6),
                  const Text('분석 조건',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1565C0))),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: trigger
                    .map((n) => _numBall(n, small: true))
                    .toList(),
              ),
              const SizedBox(height: 6),
              Text(
                '조건 충족 회차: ${idx.length}회 / 전체 ${engine.totalRounds}회',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 탭
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF1565C0),
                unselectedLabelColor: Colors.grey,
                indicatorColor: const Color(0xFF1565C0),
                tabs: const [
                  Tab(text: '후속 숫자'),
                  Tab(text: '후속 조합'),
                ],
              ),
              SizedBox(
                height: _numberResults.isEmpty && _pairResults.isEmpty
                    ? 100
                    : 600,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildNumberResults(),
                    _buildPairResults(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNumberResults() {
    if (_numberResults.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('조건을 충족하는 결과가 없습니다.\n최소 표본 수나 Lift를 낮춰보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _numberResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _buildNumberResultCard(_numberResults[i], i + 1),
    );
  }

  Widget _buildNumberResultCard(PatternResult r, int rank) {
    final n = r.targetNumbers.first;
    final isHigh = r.confidenceLevel == 'high';
    final isMed = r.confidenceLevel == 'medium';
    final confidenceColor =
        isHigh ? Colors.green : isMed ? Colors.orange : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          // 순위
          SizedBox(
            width: 28,
            child: Text('$rank위',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w600)),
          ),
          // 번호 볼
          _numBall(n),
          const SizedBox(width: 12),
          // 통계
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _statChip(
                        '출현 ${r.supportCount}회', const Color(0xFF1565C0)),
                    const SizedBox(width: 4),
                    _statChip(
                        'Lift ${r.lift.toStringAsFixed(2)}',
                        r.lift >= 1.5
                            ? Colors.red.shade700
                            : r.lift >= 1.2
                                ? Colors.orange.shade700
                                : const Color(0xFF555555)),
                    const SizedBox(width: 4),
                    if (r.confidenceLevel == 'low')
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Text('표본 부족 ⚠️',
                            style: TextStyle(
                                fontSize: 10, color: Colors.deepOrange)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '조건부 ${(r.conditionalRate * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF444444)),
                    ),
                    const Text(' · ',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      '전체 ${(r.baseRate * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500),
                    ),
                    const Text(' · ',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      '표본 ${r.triggerCount}회',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 신뢰도 표시
          Container(
            width: 8, height: 36,
            decoration: BoxDecoration(
              color: confidenceColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairResults() {
    if (_pairResults.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('조건을 충족하는 조합 결과가 없습니다.\n최소 표본 수를 낮춰보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _pairResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _buildPairResultCard(_pairResults[i], i + 1),
    );
  }

  Widget _buildPairResultCard(PatternResult r, int rank) {
    final isHigh = r.confidenceLevel == 'high';
    final isMed = r.confidenceLevel == 'medium';
    final confidenceColor =
        isHigh ? Colors.green : isMed ? Colors.orange : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$rank위',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w600)),
          ),
          Wrap(
            spacing: 4,
            children: r.targetNumbers.map((n) => _numBall(n)).toList(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _statChip('출현 ${r.supportCount}회', const Color(0xFF1565C0)),
                    const SizedBox(width: 4),
                    _statChip(
                        'Lift ${r.lift.toStringAsFixed(2)}',
                        r.lift >= 1.5
                            ? Colors.red.shade700
                            : r.lift >= 1.2
                                ? Colors.orange.shade700
                                : const Color(0xFF555555)),
                    if (r.confidenceLevel == 'low') ...[
                      const SizedBox(width: 4),
                      const Text('⚠️',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '조건부 ${(r.conditionalRate * 100).toStringAsFixed(1)}% · 전체 ${(r.baseRate * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Container(
            width: 8, height: 36,
            decoration: BoxDecoration(
              color: confidenceColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  // ── 공통 위젯 ────────────────────────────────────────────────
  Color _ballColor(int n) {
    if (n <= 10) return const Color(0xFFFFB300);
    if (n <= 20) return const Color(0xFF42A5F5);
    if (n <= 30) return const Color(0xFFEF5350);
    if (n <= 40) return const Color(0xFF9E9E9E);
    return const Color(0xFF66BB6A);
  }

  Widget _numBall(int n, {bool small = false}) {
    final size = small ? 26.0 : 32.0;
    final fontSize = small ? 11.0 : 13.0;
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _ballColor(n),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$n',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _statChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
