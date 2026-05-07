class LottoWinningNumber {
  final String drawDate;
  final int round;
  final List<int> numbers;
  final int bonusNumber;

  LottoWinningNumber({
    required this.drawDate,
    required this.round,
    required this.numbers,
    required this.bonusNumber,
  });

  factory LottoWinningNumber.fromJson(Map<String, dynamic> json) {
    final numberList = (json['numbers'] as List<dynamic>? ?? [])
        .map((e) => e is int ? e : int.tryParse('$e') ?? 0)
        .toList();

    return LottoWinningNumber(
      drawDate: json['drawDate']?.toString() ?? '',
      round: json['round'] is int ? json['round'] : int.tryParse('${json['round']}') ?? 0,
      numbers: numberList,
      bonusNumber: json['bonusNumber'] is int
          ? json['bonusNumber']
          : int.tryParse('${json['bonusNumber']}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'drawDate': drawDate,
      'round': round,
      'numbers': numbers,
      'bonusNumber': bonusNumber,
    };
  }
}
