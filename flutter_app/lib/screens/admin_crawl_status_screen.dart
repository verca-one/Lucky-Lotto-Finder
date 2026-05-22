import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class AdminCrawlStatusScreen extends StatefulWidget {
  const AdminCrawlStatusScreen({super.key});

  @override
  State<AdminCrawlStatusScreen> createState() => _AdminCrawlStatusScreenState();
}

class _AdminCrawlStatusScreenState extends State<AdminCrawlStatusScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<_RoundStatus> _items = [];
  List<Map<String, dynamic>> _crawlLogs = [];
  final Set<int> _expandedIndices = {};
  final Set<int> _refreshingIndices = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);

    try {
      // 병렬로 데이터 조회
      final results = await Future.wait([
        SupabaseService.getAllWinningNumbers(),        // 0: 로또 당첨번호
        SupabaseService.getAllPensionWinningNumbers(),  // 1: 연금 당첨번호
        SupabaseService.getLottoStoreCountsByRound(),   // 2: 로또 지점 수
        SupabaseService.getPensionStoreCountsByRound(), // 3: 연금 지점 수
        SupabaseService.getAllLottoRounds(),             // 4: lottery_rounds
        SupabaseService.getAllPensionRounds(),           // 5: pension_rounds
        SupabaseService.getSpeetoStoreCountsByRound(),  // 6: 스피또 지점 수
        SupabaseService.getSpeetoRounds(),              // 7: 스피또 회차
        SupabaseService.getCrawlLogs(limit: 50),        // 8: 크롤링 로그
      ]);

      final lottoWinnings = results[0] as List;
      final pensionWinnings = results[1] as List;
      final lottoStoreCounts = results[2] as Map<int, Map<String, int>>;
      final pensionStoreCounts = results[3] as Map<int, Map<String, int>>;
      final lottoRounds = results[4] as List<Map<String, dynamic>>;
      final pensionRounds = results[5] as List<Map<String, dynamic>>;
      final speetoStoreCounts = results[6] as Map<int, Map<String, int>>;
      final speetoRounds = results[7] as List<Map<String, dynamic>>;
      final crawlLogs = results[8] as List<Map<String, dynamic>>;

      // lottery_rounds → Map
      final lottoRoundMap = <int, Map<String, dynamic>>{};
      for (var r in lottoRounds) {
        lottoRoundMap[r['round'] as int] = r;
      }

      // pension_rounds → Map
      final pensionRoundMap = <int, Map<String, dynamic>>{};
      for (var r in pensionRounds) {
        pensionRoundMap[r['round'] as int] = r;
      }

      final List<_RoundStatus> items = [];

      // 로또 회차
      for (var w in lottoWinnings) {
        final round = w.round as int;
        final storeCounts = lottoStoreCounts[round];
        final roundInfo = lottoRoundMap[round];

        items.add(_RoundStatus(
          type: '로또',
          typeColor: Colors.purple,
          round: round,
          drawDate: w.drawDate,
          hasWinningNumbers: true,
          storeTotal: storeCounts?['total'] ?? 0,
          storeFirst: storeCounts?['first'] ?? 0,
          storeSecond: storeCounts?['second'] ?? 0,
          isPublished: roundInfo?['status'] == 'published',
          publishedAt: roundInfo?['published_at'],
          createdAt: roundInfo?['created_at'],
          lotteryType: 'lotto',
        ));
      }

      // 연금 회차
      for (var w in pensionWinnings) {
        final round = w.round as int;
        final storeCounts = pensionStoreCounts[round];
        final roundInfo = pensionRoundMap[round];

        items.add(_RoundStatus(
          type: '연금',
          typeColor: Colors.orange,
          round: round,
          drawDate: w.drawDate,
          hasWinningNumbers: true,
          storeTotal: storeCounts?['total'] ?? 0,
          storeFirst: storeCounts?['first'] ?? 0,
          storeSecond: storeCounts?['second'] ?? 0,
          isPublished: roundInfo?['stores_published'] == true,
          publishedAt: roundInfo?['published_at'],
          createdAt: roundInfo?['created_at'],
          lotteryType: 'pension',
        ));
      }

      // 스피또 회차
      for (var r in speetoRounds) {
        final round = r['round'] as int;
        final storeCounts = speetoStoreCounts[round];

        items.add(_RoundStatus(
          type: '스피또',
          typeColor: Colors.teal,
          round: round,
          drawDate: '',
          hasWinningNumbers: (storeCounts?['total'] ?? 0) > 0,
          storeTotal: storeCounts?['total'] ?? 0,
          storeFirst: storeCounts?['first'] ?? 0,
          storeSecond: storeCounts?['second'] ?? 0,
          isPublished: (storeCounts?['total'] ?? 0) > 0,
          publishedAt: null,
          createdAt: null,
          lotteryType: 'speeto',
        ));
      }

      // 최신 회차 → 위로 (type 같으면 round 내림차순)
      items.sort((a, b) {
        final cmp = b.round.compareTo(a.round);
        if (cmp != 0) return cmp;
        return a.type.compareTo(b.type);
      });

      if (!mounted) return;
      setState(() {
        _items = items;
        _crawlLogs = crawlLogs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('조회 오류: $e')),
      );
    }
  }

  Future<void> _refreshItem(int index) async {
    setState(() => _refreshingIndices.add(index));

    final item = _items[index];
    try {
      if (item.lotteryType == 'lotto') {
        final storeCounts = await SupabaseService.getLottoStoreCountsByRound();
        final rounds = await SupabaseService.getAllLottoRounds();
        final sc = storeCounts[item.round];
        final ri = rounds.firstWhere(
          (r) => r['round'] == item.round,
          orElse: () => <String, dynamic>{},
        );

        if (!mounted) return;
        setState(() {
          _items[index] = item.copyWith(
            storeTotal: sc?['total'] ?? 0,
            storeFirst: sc?['first'] ?? 0,
            storeSecond: sc?['second'] ?? 0,
            isPublished: ri['status'] == 'published',
            publishedAt: ri['published_at'],
          );
        });
      } else if (item.lotteryType == 'pension') {
        final storeCounts = await SupabaseService.getPensionStoreCountsByRound();
        final rounds = await SupabaseService.getAllPensionRounds();
        final sc = storeCounts[item.round];
        final ri = rounds.firstWhere(
          (r) => r['round'] == item.round,
          orElse: () => <String, dynamic>{},
        );

        if (!mounted) return;
        setState(() {
          _items[index] = item.copyWith(
            storeTotal: sc?['total'] ?? 0,
            storeFirst: sc?['first'] ?? 0,
            storeSecond: sc?['second'] ?? 0,
            isPublished: ri['stores_published'] == true,
            publishedAt: ri['published_at'],
          );
        });
      } else {
        // speeto
        final storeCounts = await SupabaseService.getSpeetoStoreCountsByRound();
        final sc = storeCounts[item.round];

        if (!mounted) return;
        setState(() {
          _items[index] = item.copyWith(
            storeTotal: sc?['total'] ?? 0,
            storeFirst: sc?['first'] ?? 0,
            storeSecond: sc?['second'] ?? 0,
            isPublished: (sc?['total'] ?? 0) > 0,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('새로고침 오류: $e')),
        );
      }
    }

    if (!mounted) return;
    setState(() => _refreshingIndices.remove(index));
  }

  Future<void> _deleteItem(int index) async {
    final item = _items[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${item.type} ${item.round}회 삭제'),
        content: const Text('당첨번호, 회차 정보, 지점 데이터가 모두 삭제됩니다.\n계속하시겠습니까?'),
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

    if (confirm != true) return;

    bool success;
    if (item.lotteryType == 'lotto') {
      success = await SupabaseService.deleteLottoRound(item.round);
    } else if (item.lotteryType == 'pension') {
      success = await SupabaseService.deletePensionRound(item.round);
    } else {
      // 스피또는 삭제 미지원 (필요시 추가)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('스피또 회차 삭제는 미지원입니다')),
      );
      return;
    }

    if (success && mounted) {
      setState(() => _items.removeAt(index));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.type} ${item.round}회가 삭제되었습니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        title: const Text(
          '크롤링 회차 확인',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: '회차 현황'),
            Tab(text: '크롤링 로그'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRoundsTab(),
                _buildLogsTab(),
              ],
            ),
    );
  }

  Widget _buildRoundsTab() {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('등록된 회차가 없습니다', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (context, index) => _buildCard(index),
      ),
    );
  }

  Widget _buildLogsTab() {
    if (_crawlLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('크롤링 실행 기록이 없습니다', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _crawlLogs.length,
        itemBuilder: (context, index) => _buildLogCard(_crawlLogs[index]),
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final status = log['status'] as String? ?? 'unknown';
    final lotteryType = log['lottery_type'] as String? ?? '';
    final startedAt = log['started_at'] as String?;
    final completedAt = log['completed_at'] as String?;
    final duration = log['duration_seconds'] as int?;
    final errorMsg = log['error_message'] as String?;
    final runId = log['workflow_run_id'] as String?;

    Color statusColor;
    IconData statusIcon;
    String statusText;
    switch (status) {
      case 'success':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = '성공';
        break;
      case 'failure':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusText = '실패';
        break;
      case 'running':
        statusColor = Colors.blue;
        statusIcon = Icons.sync;
        statusText = '실행중';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
        statusText = status;
    }

    String typeLabel;
    Color typeColor;
    switch (lotteryType) {
      case 'lotto':
        typeLabel = '로또';
        typeColor = Colors.purple;
        break;
      case 'pension':
        typeLabel = '연금';
        typeColor = Colors.orange;
        break;
      case 'speeto':
        typeLabel = '스피또';
        typeColor = Colors.teal;
        break;
      default:
        typeLabel = lotteryType;
        typeColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단: 타입 + 상태
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: typeColor),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(statusIcon, size: 16, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  statusText,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: statusColor),
                ),
                const Spacer(),
                if (duration != null)
                  Text(
                    '${duration}초',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // 시간 정보
            if (startedAt != null)
              Text(
                '시작: ${_formatDateTime(startedAt)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            if (completedAt != null)
              Text(
                '완료: ${_formatDateTime(completedAt)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            // 에러 메시지
            if (errorMsg != null && errorMsg.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  errorMsg,
                  style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                ),
              ),
            ],
            // Run ID
            if (runId != null && runId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Run: $runId',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(int index) {
    final item = _items[index];
    final isExpanded = _expandedIndices.contains(index);
    final isRefreshing = _refreshingIndices.contains(index);

    // 상태 판별
    final hasStores = item.storeTotal > 0;
    final allGreen = item.hasWinningNumbers && hasStores && item.isPublished;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: allGreen ? Colors.green.shade200 : Colors.grey.shade300,
          width: allGreen ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // 메인 카드 영역
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedIndices.remove(index);
                } else {
                  _expandedIndices.add(index);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  // 상태 아이콘
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: allGreen
                          ? Colors.green
                          : hasStores
                              ? Colors.orange
                              : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 메인 정보
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 타입 + 회차
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: item.typeColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.type,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: item.typeColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${item.round}회',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 상태 요약
                        Row(
                          children: [
                            _statusChip(
                              hasStores ? '지점로드 완료' : '지점 미로드',
                              hasStores ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            _statusChip(
                              item.isPublished ? '발행완료' : '미발행',
                              item.isPublished ? Colors.green : Colors.grey,
                            ),
                          ],
                        ),
                        if (item.drawDate.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.drawDate,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 우측 버튼들
                  if (isRefreshing)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      color: Colors.blue,
                      onPressed: () => _refreshItem(index),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: '새로고침',
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: Colors.red.shade400,
                    onPressed: () => _deleteItem(index),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    tooltip: '삭제',
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // 펼치기 영역
          if (isExpanded) _buildExpandedSection(item),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildExpandedSection(_RoundStatus item) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          // 상세 정보
          _detailRow('당첨번호', item.hasWinningNumbers ? '등록됨' : '미등록', item.hasWinningNumbers),
          _detailRow('수집 지점 수', '${item.storeTotal}개', item.storeTotal > 0),
          _detailRow('1등 지점', '${item.storeFirst}개', item.storeFirst > 0),
          _detailRow('2등 지점', '${item.storeSecond}개', item.storeSecond > 0),
          _detailRow('발행 상태', item.isPublished ? '발행완료' : '미발행', item.isPublished),
          if (item.publishedAt != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  '발행: ${_formatDateTime(item.publishedAt!)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
          if (item.createdAt != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  '생성: ${_formatDateTime(item.createdAt!)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, bool isOk) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: isOk ? Colors.green : Colors.grey.shade400,
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isOk ? Colors.black87 : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }
}

/// 회차 상태 데이터 모델
class _RoundStatus {
  final String type;
  final Color typeColor;
  final int round;
  final String drawDate;
  final bool hasWinningNumbers;
  final int storeTotal;
  final int storeFirst;
  final int storeSecond;
  final bool isPublished;
  final String? publishedAt;
  final String? createdAt;
  final String lotteryType;

  _RoundStatus({
    required this.type,
    required this.typeColor,
    required this.round,
    required this.drawDate,
    required this.hasWinningNumbers,
    required this.storeTotal,
    required this.storeFirst,
    required this.storeSecond,
    required this.isPublished,
    this.publishedAt,
    this.createdAt,
    required this.lotteryType,
  });

  _RoundStatus copyWith({
    int? storeTotal,
    int? storeFirst,
    int? storeSecond,
    bool? isPublished,
    String? publishedAt,
  }) {
    return _RoundStatus(
      type: type,
      typeColor: typeColor,
      round: round,
      drawDate: drawDate,
      hasWinningNumbers: hasWinningNumbers,
      storeTotal: storeTotal ?? this.storeTotal,
      storeFirst: storeFirst ?? this.storeFirst,
      storeSecond: storeSecond ?? this.storeSecond,
      isPublished: isPublished ?? this.isPublished,
      publishedAt: publishedAt ?? this.publishedAt,
      createdAt: createdAt,
      lotteryType: lotteryType,
    );
  }
}
