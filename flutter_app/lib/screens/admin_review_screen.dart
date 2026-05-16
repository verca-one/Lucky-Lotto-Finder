import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key});

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> {
  List<Map<String, dynamic>> _pendingStats = [];
  List<Map<String, dynamic>> _holds = [];
  bool _isLoading = true;
  bool _isApproving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      SupabaseService.getPendingReviewStats(),
      SupabaseService.getReviewHolds(),
    ]);
    if (!mounted) return;
    setState(() {
      _pendingStats = results[0] as List<Map<String, dynamic>>;
      _holds = results[1] as List<Map<String, dynamic>>;
      _isLoading = false;
    });
  }

  Set<String> get _holdCodes => _holds.map((h) => h['dhlottery_code'] as String).toSet();

  Future<void> _approveAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전체 일괄 승인'),
        content: Text('보류 지점 제외 ${_pendingStats.where((s) => !_holdCodes.contains(s['dhlottery_code'])).length}개 지점의 대기 평가를 모두 승인합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('일괄 승인', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isApproving = true);
    final count = await SupabaseService.approveAllPendingReviews();
    if (!mounted) return;
    setState(() => _isApproving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count건 승인 완료')),
    );
    _loadData();
  }

  Future<void> _approveStore(String code, String name) async {
    final count = await SupabaseService.approveStoreReviews(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name: $count건 승인')),
    );
    _loadData();
  }

  Future<void> _rejectStore(String code, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('평가 거절'),
        content: Text('$name의 대기 중인 평가를 모두 삭제합니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('거절', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final count = await SupabaseService.rejectStoreReviews(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name: $count건 거절(삭제)')),
    );
    _loadData();
  }

  Future<void> _toggleHold(String code) async {
    if (_holdCodes.contains(code)) {
      await SupabaseService.removeReviewHold(code);
    } else {
      await SupabaseService.addReviewHold(code);
    }
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        title: const Text('지점평가 관리', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 상단 요약 + 일괄 승인
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.green.shade50,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '대기 중 ${_pendingStats.fold<int>(0, (sum, s) => sum + (s['pending_count'] as int))}건',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_pendingStats.length}개 지점 | 보류 ${_holds.length}개',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isApproving || _pendingStats.isEmpty ? null : _approveAll,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        icon: _isApproving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle, color: Colors.white, size: 18),
                        label: const Text('전체 승인', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                // 보류 목록
                if (_holds.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: Colors.orange.shade50,
                    child: Row(
                      children: [
                        Icon(Icons.pause_circle, size: 18, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Text(
                          '보류 중 ${_holds.length}개 지점',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
                // 지점 목록
                Expanded(
                  child: _pendingStats.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade300),
                              const SizedBox(height: 16),
                              Text('대기 중인 평가가 없습니다', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _pendingStats.length,
                            itemBuilder: (context, index) {
                              final stat = _pendingStats[index];
                              return _buildStoreReviewCard(stat);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStoreReviewCard(Map<String, dynamic> stat) {
    final code = stat['dhlottery_code'] as String;
    final name = stat['store_name'] as String;
    final address = stat['address'] as String;
    final pendingCount = stat['pending_count'] as int;
    final upCount = stat['up_count'] as int;
    final downCount = stat['down_count'] as int;
    final isHeld = _holdCodes.contains(code);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isHeld ? Colors.orange.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 지점 정보
            Row(
              children: [
                if (isHeld) ...[
                  Icon(Icons.pause_circle, size: 16, color: Colors.orange.shade600),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('대기 $pendingCount건', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(address, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            // 수치
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.thumb_up, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text('$upCount', style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.thumb_down, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Text('$downCount', style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                  ]),
                ),
                const Spacer(),
                // 보류 토글
                SizedBox(
                  height: 30,
                  child: OutlinedButton(
                    onPressed: () => _toggleHold(code),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isHeld ? Colors.green : Colors.orange,
                      side: BorderSide(color: isHeld ? Colors.green : Colors.orange),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: Text(isHeld ? '보류 해제' : '보류', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 6),
                // 승인
                SizedBox(
                  height: 30,
                  child: ElevatedButton(
                    onPressed: () => _approveStore(code, name),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('승인', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 6),
                // 거절
                SizedBox(
                  height: 30,
                  child: ElevatedButton(
                    onPressed: () => _rejectStore(code, name),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('거절', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
