import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SajuNumberContent extends StatefulWidget {
  const SajuNumberContent({super.key});

  @override
  State<SajuNumberContent> createState() => _SajuNumberContentState();
}

class _SajuNumberContentState extends State<SajuNumberContent> {
  // 입력값
  int _year = 1990;
  int _month = 1;
  int _day = 1;
  int _hour = 12;
  int _minute = 0;
  bool _isLunar = false;

  bool _isGenerating = false;
  List<List<int>> _generatedSets = [];
  List<bool> _heldSets = [];
  Map<String, String> _sajuResult = {};

  // 천간 (天干)
  static const List<String> _chunGan = ['갑', '을', '병', '정', '무', '기', '경', '신', '임', '계'];
  // 지지 (地支)
  static const List<String> _jiJi = ['자', '축', '인', '묘', '진', '사', '오', '미', '신', '유', '술', '해'];
  // 오행 (五行)
  static const List<String> _oHaeng = ['목', '화', '토', '금', '수'];
  // 천간 → 오행 매핑 (갑을=목, 병정=화, 무기=토, 경신=금, 임계=수)
  static const List<int> _ganToOhaeng = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4];
  // 지지 → 오행 매핑
  static const List<int> _jiToOhaeng = [4, 2, 0, 0, 2, 1, 1, 2, 3, 3, 2, 4];

  // 오행별 행운 번호 범위
  static const Map<int, List<int>> _ohaengNumbers = {
    0: [1, 2, 11, 12, 21, 22, 31, 32, 41, 42], // 목
    1: [3, 4, 13, 14, 23, 24, 33, 34, 43, 44], // 화
    2: [5, 6, 15, 16, 25, 26, 35, 36, 45],     // 토
    3: [7, 8, 17, 18, 27, 28, 37, 38],         // 금
    4: [9, 10, 19, 20, 29, 30, 39, 40],        // 수
  };

  // 오행 색상
  static const Map<int, Color> _ohaengColors = {
    0: Color(0xFF4CAF50), // 목 - 초록
    1: Color(0xFFF44336), // 화 - 빨강
    2: Color(0xFFFF9800), // 토 - 황토
    3: Color(0xFFFFFFFF), // 금 - 흰색(테두리)
    4: Color(0xFF2196F3), // 수 - 파랑
  };

  // 시주 계산 (시간 → 지지)
  int _hourToJiji(int hour) {
    // 자시(23~01), 축시(01~03), ... 해시(21~23)
    final idx = ((hour + 1) % 24) ~/ 2;
    return idx % 12;
  }

  // 연주 천간/지지
  int _yearGan(int year) => (year - 4) % 10;
  int _yearJi(int year) => (year - 4) % 12;

  // 월주 천간 (연간 기준)
  int _monthGan(int yearGan, int month) => (yearGan * 2 + month) % 10;
  int _monthJi(int month) => (month + 1) % 12;

  // 일주 (간략 계산 - 실제로는 만세력 필요하나 근사치 사용)
  int _dayGan(int year, int month, int day) {
    // 간략 공식
    final total = year * 365 + (year ~/ 4) - (year ~/ 100) + (year ~/ 400) + _dayOfYear(month, day);
    return total % 10;
  }

  int _dayJi(int year, int month, int day) {
    final total = year * 365 + (year ~/ 4) - (year ~/ 100) + (year ~/ 400) + _dayOfYear(month, day);
    return total % 12;
  }

  int _dayOfYear(int month, int day) {
    const days = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
    return days[month - 1] + day;
  }

  Map<String, String> _calculateSaju() {
    final yGan = _yearGan(_year);
    final yJi = _yearJi(_year);
    final mGan = _monthGan(yGan, _month);
    final mJi = _monthJi(_month);
    final dGan = _dayGan(_year, _month, _day);
    final dJi = _dayJi(_year, _month, _day);
    final hJi = _hourToJiji(_hour);
    final hGan = (dGan * 2 + hJi) % 10;

    // 일간(일주 천간)이 본인의 오행
    final myOhaeng = _ganToOhaeng[dGan];

    // 오늘 날짜 기반 운세 오행
    final now = DateTime.now();
    final todayGan = _dayGan(now.year, now.month, now.day);
    final todayOhaeng = _ganToOhaeng[todayGan];

    // 상생 관계 계산
    // 목→화→토→금→수→목 (상생)
    final supportOhaeng = (myOhaeng + 1) % 5; // 내가 생하는 오행
    final helpOhaeng = (myOhaeng + 4) % 5;    // 나를 생하는 오행

    return {
      'yearPillar': '${_chunGan[yGan]}${_jiJi[yJi]}',
      'monthPillar': '${_chunGan[mGan]}${_jiJi[mJi]}',
      'dayPillar': '${_chunGan[dGan]}${_jiJi[dJi]}',
      'hourPillar': '${_chunGan[hGan]}${_jiJi[hJi]}',
      'myOhaeng': _oHaeng[myOhaeng],
      'todayOhaeng': _oHaeng[todayOhaeng],
      'supportOhaeng': _oHaeng[supportOhaeng],
      'helpOhaeng': _oHaeng[helpOhaeng],
      'myOhaengIdx': '$myOhaeng',
      'supportOhaengIdx': '$supportOhaeng',
      'helpOhaengIdx': '$helpOhaeng',
      'todayOhaengIdx': '$todayOhaeng',
      'calendar': _isLunar ? '음력' : '양력',
    };
  }

  List<int> _generateSajuNumbers(Map<String, String> saju) {
    final rng = Random();
    final myIdx = int.parse(saju['myOhaengIdx']!);
    final supportIdx = int.parse(saju['supportOhaengIdx']!);
    final helpIdx = int.parse(saju['helpOhaengIdx']!);
    final todayIdx = int.parse(saju['todayOhaengIdx']!);

    // 본인 오행 번호 2개
    final myNums = List<int>.from(_ohaengNumbers[myIdx]!)..shuffle(rng);
    // 상생 오행 번호 2개
    final supportNums = List<int>.from(_ohaengNumbers[supportIdx]!)..shuffle(rng);
    // 나를 도와주는 오행 1개
    final helpNums = List<int>.from(_ohaengNumbers[helpIdx]!)..shuffle(rng);
    // 오늘 운세 오행 1개
    final todayNums = List<int>.from(_ohaengNumbers[todayIdx]!)..shuffle(rng);

    final Set<int> result = {};
    // 본인 오행 2개
    for (final n in myNums) {
      if (result.length >= 2) break;
      result.add(n);
    }
    // 상생 오행 2개
    for (final n in supportNums) {
      if (result.length >= 4) break;
      result.add(n);
    }
    // 도움 오행 1개
    for (final n in helpNums) {
      if (result.length >= 5) break;
      result.add(n);
    }
    // 오늘 운세 1개
    for (final n in todayNums) {
      if (result.length >= 6) break;
      result.add(n);
    }

    // 부족하면 랜덤 보충
    final allNums = List.generate(45, (i) => i + 1)..shuffle(rng);
    for (final n in allNums) {
      if (result.length >= 6) break;
      result.add(n);
    }

    final numbers = result.take(6).toList()..sort();

    // 합산 검증 (100~180)
    final sum = numbers.fold<int>(0, (a, b) => a + b);
    if (sum < 80 || sum > 200) {
      return _generateSajuNumbers(saju);
    }

    return numbers;
  }

  Future<void> _generate() async {
    setState(() => _isGenerating = true);
    await Future.delayed(const Duration(milliseconds: 400));

    final saju = _calculateSaju();
    final newSets = <List<int>>[];
    final newHeld = <bool>[];

    for (int i = 0; i < _generatedSets.length; i++) {
      if (i < _heldSets.length && _heldSets[i]) {
        newSets.add(_generatedSets[i]);
        newHeld.add(true);
      }
    }
    while (newSets.length < 5) {
      newSets.add(_generateSajuNumbers(saju));
      newHeld.add(false);
    }

    if (!mounted) return;
    setState(() {
      _sajuResult = saju;
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
        'type': 'saju',
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Icon(Icons.auto_graph, color: Colors.deepPurple.shade700, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '오늘의 사주 로또번호',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '생년월일시를 입력하면 사주 오행 기반 번호를 추천합니다',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // 생년월일 입력
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.deepPurple.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('생년월일시', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                // 년 / 월 / 일
                Row(
                  children: [
                    Expanded(child: _buildNumberField('년', _year, 1920, 2026, (v) => _year = v)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumberField('월', _month, 1, 12, (v) => _month = v)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumberField('일', _day, 1, 31, (v) => _day = v)),
                  ],
                ),
                const SizedBox(height: 10),

                // 시 / 분
                Row(
                  children: [
                    Expanded(child: _buildNumberField('시', _hour, 0, 23, (v) => _hour = v)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildNumberField('분', _minute, 0, 59, (v) => _minute = v)),
                    const SizedBox(width: 8),
                    // 음력/양력
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('역법', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.deepPurple.shade200),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _isLunar = false),
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: !_isLunar ? Colors.deepPurple : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '양력',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: !_isLunar ? Colors.white : Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _isLunar = true),
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _isLunar ? Colors.deepPurple : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '음력',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: _isLunar ? Colors.white : Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 생성 버튼
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generate,
              icon: _isGenerating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_graph, size: 20),
              label: Text(
                _isGenerating ? '사주 분석 중...' : '사주 번호 생성 (5세트)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 사주 분석 결과
          if (_sajuResult.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.stars, size: 16, color: Colors.deepPurple.shade700),
                      const SizedBox(width: 6),
                      Text('사주 분석 결과', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 사주 네기둥
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _pillarWidget('시주', _sajuResult['hourPillar']!),
                      _pillarWidget('일주', _sajuResult['dayPillar']!),
                      _pillarWidget('월주', _sajuResult['monthPillar']!),
                      _pillarWidget('연주', _sajuResult['yearPillar']!),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 오행 정보
                  _ohaengRow('나의 오행', _sajuResult['myOhaeng']!, int.parse(_sajuResult['myOhaengIdx']!)),
                  _ohaengRow('오늘 기운', _sajuResult['todayOhaeng']!, int.parse(_sajuResult['todayOhaengIdx']!)),
                  _ohaengRow('상생 오행', _sajuResult['supportOhaeng']!, int.parse(_sajuResult['supportOhaengIdx']!)),
                  _ohaengRow('도움 오행', _sajuResult['helpOhaeng']!, int.parse(_sajuResult['helpOhaengIdx']!)),
                  const SizedBox(height: 8),
                  Text(
                    '${_sajuResult['calendar']} 기준 · ${_sajuResult['myOhaeng']}(본인) → ${_sajuResult['supportOhaeng']}(상생) 흐름 반영',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 생성된 번호
          if (_generatedSets.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.format_list_numbered, size: 20, color: Colors.deepPurple.shade700),
                const SizedBox(width: 6),
                Text(
                  '사주 추천 번호 (${_generatedSets.length}세트)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...List.generate(_generatedSets.length, (i) {
              final nums = _generatedSets[i];
              final sum = nums.fold<int>(0, (a, b) => a + b);
              final oddCount = nums.where((n) => n % 2 == 1).length;
              final isHeld = i < _heldSets.length && _heldSets[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isHeld ? Colors.deepPurple.shade100 : Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isHeld ? Colors.deepPurple : Colors.deepPurple.shade200,
                    width: isHeld ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.deepPurple,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Wrap(
                            spacing: 4,
                            children: nums.map((n) => _ballWidget(n)).toList(),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _toggleHold(i),
                          child: Icon(
                            isHeld ? Icons.lock : Icons.lock_open,
                            size: 20,
                            color: isHeld ? Colors.deepPurple : Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _removeSet(i),
                          child: Icon(Icons.close, size: 20, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const SizedBox(width: 34),
                        Text(
                          '합:$sum  홀:$oddCount 짝:${6 - oddCount}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                        if (isHeld) ...[
                          const SizedBox(width: 8),
                          Text('HOLD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
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
                icon: const Icon(Icons.bookmark_add, size: 20),
                label: Text('${_generatedSets.length}세트 저장하기', style: const TextStyle(fontSize: 15)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepPurple.shade700,
                  side: BorderSide(color: Colors.deepPurple.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          // 안내
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.deepPurple.shade300),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '사주 오행(목·화·토·금·수) 기반으로 본인 오행 2개, 상생 오행 2개, 도움 오행 1개, 오늘 운세 1개를 조합합니다.',
                    style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberField(String label, int value, int min, int max, Function(int) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        SizedBox(
          height: 44,
          child: TextField(
            controller: TextEditingController(text: '$value'),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.deepPurple.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.deepPurple.shade400, width: 2),
              ),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
            ),
            onChanged: (text) {
              final v = int.tryParse(text);
              if (v != null && v >= min && v <= max) {
                setState(() => onChanged(v));
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _pillarWidget(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.deepPurple.shade200),
          ),
          child: Column(
            children: [
              Text(
                value[0],
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700),
              ),
              const SizedBox(height: 2),
              Container(width: 20, height: 1, color: Colors.deepPurple.shade100),
              const SizedBox(height: 2),
              Text(
                value[1],
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade400),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ohaengRow(String label, String ohaeng, int idx) {
    final ohaengEmoji = ['🌳', '🔥', '🏔️', '⚙️', '💧'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Text(ohaengEmoji[idx], style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            '$ohaeng (${_oHaeng[idx]})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            '→ ${_ohaengNumbers[idx]!.take(5).join(", ")}...',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _ballWidget(int number) {
    final color = _getBallColor(number);
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
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
