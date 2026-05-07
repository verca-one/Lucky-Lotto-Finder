/// 연금복권720+ 당첨번호 모델
class PensionWinningNumber {
  final String drawDate;
  final int round;
  final int winningGroup;       // 1등 당첨 조 (1~5)
  final String winningNumber;   // 1등 6자리 번호 (예: "123456")
  final String bonusNumber;     // 보너스 6자리 번호

  PensionWinningNumber({
    required this.drawDate,
    required this.round,
    required this.winningGroup,
    required this.winningNumber,
    required this.bonusNumber,
  });

  factory PensionWinningNumber.fromJson(Map<String, dynamic> json) {
    return PensionWinningNumber(
      drawDate: json['drawDate']?.toString() ?? json['draw_date']?.toString() ?? '',
      round: json['round'] is int ? json['round'] : int.tryParse('${json['round']}') ?? 0,
      winningGroup: json['winningGroup'] is int
          ? json['winningGroup']
          : json['winning_group'] is int
              ? json['winning_group']
              : int.tryParse('${json['winningGroup'] ?? json['winning_group']}') ?? 1,
      winningNumber: json['winningNumber']?.toString() ?? json['winning_number']?.toString() ?? '',
      bonusNumber: json['bonusNumber']?.toString() ?? json['bonus_number']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'drawDate': drawDate,
      'round': round,
      'winningGroup': winningGroup,
      'winningNumber': winningNumber,
      'bonusNumber': bonusNumber,
    };
  }
}
