import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class AdminCrawlStatusScreen extends StatefulWidget {
  const AdminCrawlStatusScreen({super.key});

  @override
  State<AdminCrawlStatusScreen> createState() => _AdminCrawlStatusScreenState();
}

class _AdminCrawlStatusScreenState extends State<AdminCrawlStatusScreen> {
  bool _isLoading = true;
  List<_RoundStatus> _items = [];
  final Set<int> _expandedIndices = {};
  final Set<int> _refreshingIndices = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
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
      ]);

      final lottoWinnings = results[0] as List;
      final pensionWinnings = results[1] as List;
      final lottoStoreCounts = results[2] as Map<int, Map<String, int>>;
      final pensionStoreCounts = results[3] as Map<int, Map<String, int>>;
      final lottoRounds = results[4] as List<Map<String, dynamic>>;
      final pensionRounds = results[5] as List<Map<String, dynamic>>;

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

      // 최신 회차 → 위로 (type 같으면 round 내림차순)
      items.sort((a, b) {
        final cmp = b.round.compareTo(a.round);
        if (cmp != 0) return cmp;
        return a.type.compareTo(b.type);
      });

      if (!mounted) return;
      setState(() {
        _items = items;
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
      } else {
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
    } else {
      success = await SupabaseService.deletePensionRound(item.round);
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('등록된 회차가 없습니다', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    itemBuilder: (context, index) => _buildCard(index),
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
                        const SizedBox(height: 2),
                        Text(
                          item.drawDate,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
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
