import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class AdminReportScreen extends StatefulWidget {
  const AdminReportScreen({super.key});

  @override
  State<AdminReportScreen> createState() => _AdminReportScreenState();
}

class _AdminReportScreenState extends State<AdminReportScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;
  String _filterStatus = '';

  final List<String> _statusOptions = ['', 'pending', 'reviewed', 'fixed', 'rejected'];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    final reports = await SupabaseService.getAllReports(
      status: _filterStatus.isEmpty ? null : _filterStatus,
    );
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _isLoading = false;
    });
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return '접수';
      case 'reviewed':
        return '검토중';
      case 'fixed':
        return '처리완료';
      case 'rejected':
        return '반려';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'reviewed':
        return Colors.blue;
      case 'fixed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _changeStatus(String reportId, String currentStatus) async {
    final newStatus = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('상태 변경'),
        children: ['pending', 'reviewed', 'fixed', 'rejected'].map((s) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, s),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _statusColor(s),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _statusLabel(s),
                  style: TextStyle(
                    fontWeight: s == currentStatus ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (s == currentStatus)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.check, size: 16, color: Colors.blue),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (newStatus != null && newStatus != currentStatus) {
      final success = await SupabaseService.updateReportStatus(reportId, newStatus);
      if (success) {
        _loadReports();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('상태가 "${_statusLabel(newStatus)}"로 변경되었습니다')),
          );
        }
      }
    }
  }

  Future<void> _deleteReport(String reportId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('신고 삭제'),
        content: const Text('이 신고를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await SupabaseService.deleteReport(reportId);
      if (success) {
        _loadReports();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('신고가 삭제되었습니다')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade700,
        title: const Text(
          '신고 관리',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // 필터 칩
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _statusOptions.map((s) {
                  final isSelected = _filterStatus == s;
                  final label = s.isEmpty ? '전체' : _statusLabel(s);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label, style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.white : Colors.black87,
                      )),
                      selected: isSelected,
                      selectedColor: s.isEmpty ? Colors.grey.shade700 : _statusColor(s),
                      onSelected: (_) {
                        setState(() => _filterStatus = s);
                        _loadReports();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // 목록
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _reports.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              '신고 내역이 없습니다',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadReports,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _reports.length,
                          itemBuilder: (context, index) => _buildReportCard(_reports[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final id = report['id'] ?? '';
    final code = report['dhlottery_code'] ?? '';
    final reason = report['reason'] ?? '';
    final detail = report['detail'] ?? '';
    final status = report['status'] ?? 'pending';
    final createdAt = report['created_at'] ?? '';

    String dateStr = '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt);
        dateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        dateStr = createdAt;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단: 상태 + 날짜 + 액션
            Row(
              children: [
                InkWell(
                  onTap: () => _changeStatus(id, status),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _statusColor(status).withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _statusLabel(status),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _statusColor(status),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dateStr,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  onPressed: () => _deleteReport(id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 판매점 코드
            Text(
              '판매점: $code',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            // 신고 사유
            Row(
              children: [
                const Icon(Icons.flag, size: 16, color: Colors.red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reason,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
