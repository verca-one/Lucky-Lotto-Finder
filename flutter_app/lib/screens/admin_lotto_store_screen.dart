import 'package:flutter/material.dart';

import '../models/lotto_winning_number.dart';
import '../models/lottery_store.dart';
import '../services/lotto_winning_service.dart';
import '../services/supabase_service.dart';

class AdminLottoStoreScreen extends StatefulWidget {
  const AdminLottoStoreScreen({super.key});

  @override
  State<AdminLottoStoreScreen> createState() => _AdminLottoStoreScreenState();
}

class _AdminLottoStoreScreenState extends State<AdminLottoStoreScreen> {
  bool _isLoading = true;
  List<LottoWinningNumber> _rounds = [];
  final Map<int, int> _loadedStoreCount = {};
  final Map<int, bool> _publishedStatus = {};
  final Set<int> _loadingSet = {};
  final Set<int> _publishingSet = {};

  static const int _itemsPerPage = 10;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);

    // Supabase에서 전체 회차만 조회 (지점 수는 로드 시 확인)
    final rounds = await SupabaseService.getAllWinningNumbers();

    if (!mounted) return;
    setState(() {
      _rounds = rounds;
      final tp = _totalPages(rounds.length);
      if (_currentPage > tp) _currentPage = tp;
      _isLoading = false;
    });
  }

  int _totalPages(int total) {
    if (total == 0) return 1;
    return ((total - 1) ~/ _itemsPerPage) + 1;
  }

  Future<void> _loadStores(LottoWinningNumber item) async {
    setState(() => _loadingSet.add(item.round));

    final stores = await SupabaseService.getStoresByRound(
      round: item.round,
      lotteryType: 'lotto',
    );
    await LottoWinningService().saveLoadedStoresForRound(item.round, stores);

    if (!mounted) return;
    setState(() {
      _loadingSet.remove(item.round);
      _loadedStoreCount[item.round] = stores.length;
    });

    if (stores.isEmpty) {
      _showSnack('${item.round}회차 당첨지점 데이터가 없습니다');
    } else {
      _showSnack('${item.round}회차 당첨지점 ${stores.length}건 로드 완료');
    }
  }

  Future<void> _publish(int round) async {
    setState(() => _publishingSet.add(round));
    await SupabaseService.publishLottoRound(round);
    if (!mounted) return;
    setState(() {
      _publishingSet.remove(round);
      _publishedStatus[round] = true;
    });
    _showSnack('$round회차가 발행되었습니다!');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text(
          '로또 당첨지점 로드',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isLoading ? null : _refresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rounds.isEmpty
              ? const Center(child: Text('발행된 회차가 없습니다'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      '발행된 회차 목록',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '지점로드 → 발행 순서로 진행하세요',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    ..._rounds
                        .skip((_currentPage - 1) * _itemsPerPage)
                        .take(_itemsPerPage)
                        .map(_buildRoundCard),
                    if (_rounds.isNotEmpty) _buildPagination(),
                  ],
                ),
    );
  }

  Widget _buildRoundCard(LottoWinningNumber item) {
    final loadedCount = _loadedStoreCount[item.round] ?? 0;
    final isLoading = _loadingSet.contains(item.round);
    final isPublishing = _publishingSet.contains(item.round);
    final isPublished = _publishedStatus[item.round] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 회차 정보
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${item.round}회 (${item.drawDate})',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '당첨번호: ${item.numbers.join(', ')} + ${item.bonusNumber}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          // 상태 표시
          if (loadedCount > 0)
            Row(
              children: [
                Icon(Icons.cloud_done, size: 14, color: Colors.blue.shade600),
                const SizedBox(width: 4),
                Text(
                  '로드됨 ($loadedCount건)',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade600, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          if (loadedCount == 0)
            Row(
              children: [
                Icon(Icons.hourglass_empty, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  '대기중',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          if (isPublished)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '발행완료',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade600, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),

          // 버튼 row
          Row(
            children: [
              // 지점로드 버튼
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: isLoading ? null : () => _loadStores(item),
                    icon: isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download, size: 18),
                    label: Text(
                      loadedCount > 0 ? '재로드' : '지점로드',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 발행 버튼
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: (loadedCount > 0 && !isPublished && !isPublishing)
                        ? () => _publish(item.round)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    icon: isPublishing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(
                            isPublished ? Icons.check : Icons.publish,
                            size: 18,
                            color: Colors.white,
                          ),
                    label: Text(
                      isPublished ? '발행됨' : '발행',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    final totalPages = _totalPages(_rounds.length);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed:
                _currentPage > 1 ? () => setState(() => _currentPage--) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('$_currentPage / $totalPages',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            onPressed: _currentPage < totalPages
                ? () => setState(() => _currentPage++)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
