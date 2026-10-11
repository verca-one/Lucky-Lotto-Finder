import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class AdminBadgeStatusScreen extends StatefulWidget {
  const AdminBadgeStatusScreen({super.key});

  @override
  State<AdminBadgeStatusScreen> createState() => _AdminBadgeStatusScreenState();
}

class _AdminBadgeStatusScreenState extends State<AdminBadgeStatusScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _statuses = [];

  static const _typeLabels = {
    'lotto': '로또',
    'pension': '연금',
    'speedlotto_2000': '스피또2000',
    'speedlotto_1000': '스피또1000',
    'speedlotto_500': '스피또500',
  };

  static const _typeColors = {
    'lotto': Colors.purple,
    'pension': Colors.orange,
    'speedlotto_2000': Colors.teal,
    'speedlotto_1000': Colors.teal,
    'speedlotto_500': Colors.teal,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final result = await SupabaseService.getBadgeCalculationStatus();
      if (mounted) setState(() { _statuses = result; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('조회 오류: $e')));
      }
    }
  }

  String _formatDateTime(String? iso) {
    if (iso == null) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')} '
          '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        title: const Text('배지 계산 현황',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _isLoading ? null : _load),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 안내
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '배지 계산이 최신 회차 크롤링 이후에 실행됐으면 적용완료, 아니면 적용실패로 표시됩니다.',
                            style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._statuses.map((s) => _buildCard(s)).toList(),
                ],
              ),
            ),
    );
  }

  Widget _buildCard(Map<String, dynamic> s) {
    final lt = s['lottery_type'] as String;
    final round = s['latest_round'] as int;
    final badgeCount = s['badge_count'] as int;
    final calculatedAt = s['calculated_at'] as String?;
    final isApplied = s['is_applied'] as bool;
    final hasError = s.containsKey('error');

    final label = _typeLabels[lt] ?? lt;
    final color = _typeColors[lt] ?? Colors.grey;

    final statusColor = hasError
        ? Colors.red
        : isApplied
            ? Colors.green
            : Colors.red;
    final statusIcon = hasError
        ? Icons.error_outline
        : isApplied
            ? Icons.check_circle
            : Icons.cancel_outlined;
    final statusText = round > 0
        ? '${round}회차 배지계산 ${isApplied ? '적용완료' : '적용실패'}'
        : '데이터 없음';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 타입 + 상태 한 줄
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(label,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                ),
                const SizedBox(width: 10),
                Icon(statusIcon, size: 18, color: statusColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 상세
            _detailRow(Icons.badge_outlined, '배지 수', '$badgeCount개'),
            _detailRow(Icons.access_time, '계산 시각', _formatDateTime(calculatedAt)),
            if (hasError)
              _detailRow(Icons.error, '오류', s['error'] as String, color: Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color ?? Colors.grey.shade500),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color ?? Colors.black87),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
