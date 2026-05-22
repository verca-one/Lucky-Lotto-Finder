import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

/// 로또 세금계산기
/// 1등~3등 당첨금에 대한 세금(소득세+주민세) 계산
class TaxCalculatorContent extends StatefulWidget {
  const TaxCalculatorContent({super.key});

  @override
  State<TaxCalculatorContent> createState() => _TaxCalculatorContentState();
}

class _TaxCalculatorContentState extends State<TaxCalculatorContent> {
  final TextEditingController _amountController = TextEditingController();
  String? _selectedRank;
  bool _calculated = false;

  int _winAmount = 0;
  int _taxableAmount = 0;
  int _incomeTax = 0;
  int _localTax = 0;
  int _totalTax = 0;
  int _netAmount = 0;
  double _taxRate = 0;

  // 등수별 예시 금액
  static const Map<String, int> _exampleAmounts = {
    '1등': 2000000000,
    '2등': 60000000,
    '3등': 1500000,
  };

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _onRankSelected(String rank) {
    setState(() {
      _selectedRank = rank;
      _amountController.text = _formatNumber(_exampleAmounts[rank]!);
    });
    _calculate();
  }

  String _formatNumber(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  String _formatKoreanMoney(int n) {
    if (n >= 100000000) {
      final eok = n ~/ 100000000;
      final remainder = n % 100000000;
      if (remainder >= 10000) {
        final man = remainder ~/ 10000;
        return '$eok억 ${_formatNumber(man)}만원';
      } else if (remainder > 0) {
        return '$eok억 ${_formatNumber(remainder)}원';
      }
      return '$eok억원';
    } else if (n >= 10000) {
      final man = n ~/ 10000;
      final remainder = n % 10000;
      if (remainder > 0) {
        return '${_formatNumber(man)}만 ${_formatNumber(remainder)}원';
      }
      return '${_formatNumber(man)}만원';
    }
    return '${_formatNumber(n)}원';
  }

  void _calculate() {
    final text = _amountController.text.replaceAll(',', '').replaceAll(' ', '');
    final amount = int.tryParse(text);
    if (amount == null || amount <= 0) {
      if (_calculated) setState(() => _calculated = false);
      return;
    }

    // 비과세 기준: 5만원 이하 비과세
    // 200만원 이하: 필요경비 없음 → 전액 과세 (실제론 5만원 비과세)
    // 3억 이하: 소득세 22% (소득세 20% + 주민세 2%)
    // 3억 초과분: 소득세 33% (소득세 30% + 주민세 3%)

    int taxable = amount;
    int incomeTax = 0;
    int localTax = 0;

    if (amount <= 50000) {
      // 비과세
      taxable = 0;
      incomeTax = 0;
      localTax = 0;
    } else {
      taxable = amount;
      if (taxable <= 300000000) {
        // 3억 이하: 20% 소득세 + 2% 주민세
        incomeTax = (taxable * 0.20).round();
        localTax = (incomeTax * 0.10).round(); // 주민세 = 소득세의 10%
      } else {
        // 3억 이하 부분: 20%
        final under3 = 300000000;
        final over3 = taxable - under3;
        final tax1 = (under3 * 0.20).round();
        final tax2 = (over3 * 0.30).round();
        incomeTax = tax1 + tax2;
        localTax = (incomeTax * 0.10).round();
      }
    }

    final totalTax = incomeTax + localTax;
    final net = amount - totalTax;

    setState(() {
      _winAmount = amount;
      _taxableAmount = taxable;
      _incomeTax = incomeTax;
      _localTax = localTax;
      _totalTax = totalTax;
      _netAmount = net;
      _taxRate = amount > 0 ? (totalTax / amount * 100) : 0;
      _calculated = true;
    });
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.receipt_long_rounded, color: Colors.blue.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('로또 세금계산기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('당첨금 실수령액을 계산해보세요', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 세금 기준 안내
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('세금 기준', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                _taxInfoRow('5만원 이하', '비과세', Colors.green),
                _taxInfoRow('5만원 초과 ~ 3억원', '22% (소득세 20% + 주민세 2%)', Colors.orange),
                _taxInfoRow('3억원 초과분', '33% (소득세 30% + 주민세 3%)', Colors.red),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 등수 빠른 선택
          const Text('등수 선택 (예시 금액)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF666666))),
          const SizedBox(height: 10),
          Row(
            children: [
              _rankChip('1등', Colors.amber, Icons.emoji_events_rounded),
              const SizedBox(width: 8),
              _rankChip('2등', Colors.grey.shade400, Icons.emoji_events_rounded),
              const SizedBox(width: 8),
              _rankChip('3등', Colors.brown.shade300, Icons.emoji_events_rounded),
            ],
          ),
          const SizedBox(height: 20),

          // 금액 입력
          const Text('당첨금액 (원)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF666666))),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              _ThousandsSeparatorFormatter(),
            ],
            decoration: InputDecoration(
              hintText: '당첨금액을 입력하세요',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              prefixIcon: Icon(Icons.monetization_on_rounded, color: Colors.blue.shade300),
              suffixText: '원',
              suffixStyle: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            onChanged: (_) => _calculate(),
          ),
          const SizedBox(height: 16),

          // 계산 버튼
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _calculate,
              icon: const Icon(Icons.calculate_rounded, size: 20),
              label: const Text('세금 계산하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 결과
          if (_calculated) ...[
            // 실수령액 메인 카드
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade700, Colors.blue.shade500],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade200.withValues(alpha: 0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text('실수령액', style: TextStyle(fontSize: 14, color: Colors.white70)),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _formatKoreanMoney(_netAmount),
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatNumber(_netAmount)}원',
                    style: const TextStyle(fontSize: 13, color: Colors.white60),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 상세 내역
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('세금 상세', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  _detailRow('당첨금액', _formatNumber(_winAmount), isTotal: false),
                  const Divider(height: 20),
                  _detailRow('소득세 (${_winAmount > 300000000 ? "20%+30%" : "20%"})', '- ${_formatNumber(_incomeTax)}', isNegative: true),
                  const SizedBox(height: 6),
                  _detailRow('주민세 (소득세의 10%)', '- ${_formatNumber(_localTax)}', isNegative: true),
                  const Divider(height: 20),
                  _detailRow('총 세금', '- ${_formatNumber(_totalTax)}', isNegative: true, isBold: true),
                  const SizedBox(height: 6),
                  _detailRow('실수령액', _formatNumber(_netAmount), isTotal: true, isBold: true),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 세율 요약
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _taxRate > 25 ? Colors.red.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _taxRate > 25 ? Colors.red.shade200 : Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.pie_chart_rounded,
                    size: 20,
                    color: _taxRate > 25 ? Colors.red.shade700 : Colors.orange.shade700,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '실효세율: ${_taxRate.toStringAsFixed(1)}%  |  세금 비중: ${_formatKoreanMoney(_totalTax)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _taxRate > 25 ? Colors.red.shade700 : Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 시각적 비율 바
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('당첨금 구성', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 28,
                      child: Row(
                        children: [
                          Expanded(
                            flex: max(1, ((_netAmount / _winAmount) * 100).round()),
                            child: Container(
                              color: Colors.blue.shade500,
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    '실수령 ${(100 - _taxRate).toStringAsFixed(1)}%',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_totalTax > 0)
                            Expanded(
                              flex: max(1, (_taxRate).round()),
                              child: Container(
                                color: Colors.red.shade400,
                                alignment: Alignment.center,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      '세금 ${_taxRate.toStringAsFixed(1)}%',
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _taxInfoRow(String label, String desc, Color dotColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8, height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          ),
          Expanded(child: Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        ],
      ),
    );
  }

  Widget _rankChip(String label, Color color, IconData icon) {
    final isSelected = _selectedRank == label;
    return Expanded(
      child: InkWell(
        onTap: () => _onRankSelected(label),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? color : const Color(0xFFE0E0E0), width: isSelected ? 2 : 1),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: isSelected ? color : Colors.grey.shade400),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isSelected ? color : Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isNegative = false, bool isTotal = false, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(
          fontSize: isBold ? 14 : 13,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          color: isTotal ? const Color(0xFF1565C0) : Colors.grey.shade700,
        )),
        Text('$value원', style: TextStyle(
          fontSize: isBold ? 15 : 13,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          color: isNegative ? Colors.red.shade600 : (isTotal ? const Color(0xFF1565C0) : Colors.grey.shade800),
        )),
      ],
    );
  }
}

/// 천 단위 콤마 자동 포맷터
class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    final digits = newValue.text.replaceAll(',', '');
    if (digits.isEmpty) return newValue;

    final number = int.tryParse(digits);
    if (number == null) return oldValue;

    final formatted = _format(number);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _format(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
