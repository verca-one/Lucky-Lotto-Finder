class LottoRound {
  final int round;
  final String status; // "pending" or "published"
  final DateTime createdAt;
  final DateTime? publishedAt;

  LottoRound({
    required this.round,
    required this.status,
    required this.createdAt,
    this.publishedAt,
  });

  factory LottoRound.fromJson(Map<String, dynamic> json) {
    return LottoRound(
      round: json['round'] as int? ?? 0,
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'round': round,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'published_at': publishedAt?.toIso8601String(),
    };
  }
}
