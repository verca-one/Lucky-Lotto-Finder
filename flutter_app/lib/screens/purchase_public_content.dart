// 일반 모드 '구매예측번호' — 서버 Worker가 저장한 공개 요약만 읽는다 (research_v8_public.sql).
// 공개 전용 테이블(research_public_purchase, research_public_study)만 조회하며, 연구 원본·엔진은 읽지 않는다.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PublicPurchaseSet {
  final List<int> numbers;
  final double? salesRatio; // 평균 조합 대비 예상 판매 비율 (1.0 = 평균)
  const PublicPurchaseSet(this.numbers, this.salesRatio);
}

class PublicPurchase {
  final int targetRound;
  final String validationStatus;
  final String validationSummary;
  final List<PublicPurchaseSet> sets;
  final DateTime? researchUpdatedAt;
  const PublicPurchase({
    required this.targetRound,
    required this.validationStatus,
    required this.validationSummary,
    required this.sets,
    this.researchUpdatedAt,
  });

  factory PublicPurchase.fromJson(Map<String, dynamic> j) => PublicPurchase(
        targetRound: (j['target_round'] as num).toInt(),
        validationStatus: (j['validation_status'] ?? '').toString(),
        validationSummary: (j['validation_summary'] ?? '').toString(),
        sets: [
          for (final s in (j['sets'] as List? ?? const []))
            PublicPurchaseSet(
              [for (final n in (s['numbers'] as List)) (n as num).toInt()],
              (s['sales_ratio'] as num?)?.toDouble(),
            ),
        ],
        researchUpdatedAt: DateTime.tryParse((j['research_updated_at'] ?? '').toString()),
      );
}

class PublicStudy {
  final String id;
  final String sourceResearchId;
  final String title;
  final String status;
  final bool appliedToNumbers;
  final String? purpose, method, progress, observation, limitation;
  final DateTime? updatedAt;
  const PublicStudy({
    required this.id,
    required this.sourceResearchId,
    required this.title,
    required this.status,
    required this.appliedToNumbers,
    this.purpose,
    this.method,
    this.progress,
    this.observation,
    this.limitation,
    this.updatedAt,
  });

  static String? _s(dynamic v) => v == null || v.toString().trim().isEmpty ? null : v.toString();

  factory PublicStudy.fromJson(Map<String, dynamic> j) => PublicStudy(
        id: j['id'].toString(),
        sourceResearchId: j['source_research_id'].toString(),
        title: j['title'].toString(),
        status: j['status'].toString(),
        appliedToNumbers: j['applied_to_numbers'] == true,
        purpose: _s(j['purpose']),
        method: _s(j['method']),
        progress: _s(j['progress']),
        observation: _s(j['observation']),
        limitation: _s(j['limitation']),
        updatedAt: DateTime.tryParse((j['research_updated_at'] ?? j['updated_at'] ?? '').toString()),
      );
}

class PublicPurchaseData {
  final PublicPurchase? purchase;
  final PublicStudy? study;
  const PublicPurchaseData(this.purchase, this.study);
}

/// 공개 테이블 조회 (anon: 공개 승인 행만 SELECT 가능)
class PublicPurchaseService {
  static Future<PublicPurchaseData> load() async {
    final db = Supabase.instance.client;
    final p = await db
        .from('research_public_purchase')
        .select('target_round, validation_status, validation_summary, sets, research_updated_at')
        .order('target_round', ascending: false)
        .limit(1);
    if ((p as List).isEmpty) return const PublicPurchaseData(null, null);
    final purchase = PublicPurchase.fromJson(p.first);
    final s = await db
        .from('research_public_study')
        .select('id, source_research_id, title, purpose, method, progress, observation, status, '
            'applied_to_numbers, limitation, research_updated_at, updated_at')
        .eq('target_round', purchase.targetRound)
        .eq('is_active', true)
        .limit(1);
    return PublicPurchaseData(purchase, (s as List).isEmpty ? null : PublicStudy.fromJson(s.first));
  }
}

class PurchasePublicContent extends StatefulWidget {
  /// 테스트용 데이터 주입 (null = 서버 조회)
  final Future<PublicPurchaseData> Function()? loader;
  const PurchasePublicContent({super.key, this.loader});

  @override
  State<PurchasePublicContent> createState() => _PurchasePublicContentState();
}

class _PurchasePublicContentState extends State<PurchasePublicContent> {
  PublicPurchaseData? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    (widget.loader ?? PublicPurchaseService.load)().then((d) {
      if (mounted) setState(() => _data = d);
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  static String _date(DateTime? t) {
    if (t == null) return '';
    final l = t.toLocal();
    return '${l.year}.${l.month.toString().padLeft(2, '0')}.${l.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return _center('구매예측번호를 불러오지 못했습니다. 잠시 후 다시 열어 주세요.');
    final d = _data;
    if (d == null) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final p = d.purchase;
    if (p == null) return _center('이번 회차 구매예측번호를 준비 중입니다.');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _setsCard(p),
        const SizedBox(height: 12),
        _summaryCard(p),
        const SizedBox(height: 12),
        _studyCard(d.study),
        const SizedBox(height: 12),
        Text('모든 번호 조합의 1등 당첨 확률은 같습니다. 구매예측번호는 당첨을 보장하지 않습니다.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ]),
    );
  }

  Widget _setsCard(PublicPurchase p) => _box(
        key: const ValueKey('public_purchase_sets'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p.targetRound}회 구매예측번호',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 2),
          Text('다른 구매자들이 덜 사는 번호 조합', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          if (p.sets.isEmpty)
            Text('이번 회차는 검증을 통과하지 못해 번호를 제공하지 않습니다.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700))
          else
            for (final (i, s) in p.sets.indexed)
              Container(
                key: ValueKey('public_set_$i'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                decoration: BoxDecoration(color: const Color(0xFFF2FAF8), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    SizedBox(
                      width: 22,
                      child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF00897B))),
                    ),
                    Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: s.numbers.map(_ball).toList())),
                  ]),
                  if (s.salesRatio != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      s.salesRatio! < 1
                          ? '평균 조합보다 약 ${((1 - s.salesRatio!) * 100).round()}% 덜 팔릴 것으로 추정'
                          : '평균 조합 수준으로 팔릴 것으로 추정',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ],
                ]),
              ),
        ]),
      );

  Widget _summaryCard(PublicPurchase p) {
    final passed = p.validationStatus == '검증 통과';
    return _box(
      key: const ValueKey('public_purchase_summary'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('구매예측 연구 결과 요약', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          _chip(p.validationStatus, passed ? const Color(0xFF1E7D4C) : const Color(0xFFC62828),
              passed ? const Color(0xFFE3F6EA) : const Color(0xFFFDE4E4)),
        ]),
        const SizedBox(height: 8),
        Text(p.validationSummary, style: TextStyle(fontSize: 12.5, height: 1.5, color: Colors.grey.shade800)),
        if (p.researchUpdatedAt != null) ...[
          const SizedBox(height: 6),
          Text('연구 업데이트 ${_date(p.researchUpdatedAt)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ]),
    );
  }

  Widget _studyCard(PublicStudy? s) {
    if (s == null) {
      return _box(
        key: const ValueKey('public_study_none'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('이번 주 공개 연구', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('현재 공개 중인 연구가 없습니다.', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
        ]),
      );
    }
    final lines = [s.purpose, s.method, s.progress, s.observation].whereType<String>().toList();
    return _box(
      key: ValueKey('public_study_${s.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('이번 주 공개 연구', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          _chip(s.status, const Color(0xFF1565C0), const Color(0xFFE3F0FF)),
        ]),
        const SizedBox(height: 8),
        Text(s.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(l, style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.grey.shade800)),
          ),
        const SizedBox(height: 4),
        Text(s.appliedToNumbers ? '추천번호에 적용 중' : '추천번호에 적용하지 않음',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
        if (s.limitation != null)
          Text(s.limitation!, style: TextStyle(fontSize: 11.5, height: 1.4, color: Colors.grey.shade600)),
        if (s.updatedAt != null) ...[
          const SizedBox(height: 6),
          Text('마지막 연구 업데이트 ${_date(s.updatedAt)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ]),
    );
  }

  Widget _chip(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
      );

  Widget _ball(int n) {
    final c = n <= 10
        ? Colors.yellow.shade700
        : n <= 20
            ? Colors.blue
            : n <= 30
                ? Colors.red
                : n <= 40
                    ? Colors.grey.shade700
                    : Colors.green;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }

  Widget _box({Key? key, required Widget child}) => Container(
        key: key,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8EDF5)),
        ),
        child: child,
      );

  Widget _center(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(msg, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ),
      );
}
