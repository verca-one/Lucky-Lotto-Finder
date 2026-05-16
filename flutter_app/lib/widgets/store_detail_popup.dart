import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import '../models/lottery_store.dart';
import '../services/supabase_service.dart';
import '../services/badge_service.dart';

/// 평가 항목 정의
class ReviewItem {
  final String key;
  final String label;
  final IconData icon;

  const ReviewItem({required this.key, required this.label, required this.icon});
}

const List<ReviewItem> reviewItems = [
  ReviewItem(key: 'parking_easy', label: '주차가 쉽다', icon: Icons.local_parking),
  ReviewItem(key: 'bank_transfer_available', label: '계좌이체 가능하다', icon: Icons.account_balance),
  ReviewItem(key: 'easy_to_find', label: '지점을 찾기 쉬워요', icon: Icons.explore),
  ReviewItem(key: 'friendly', label: '친절해요', icon: Icons.sentiment_satisfied),
  ReviewItem(key: 'saturday_good', label: '토요일에 로또구매하기 좋아요', icon: Icons.calendar_today),
  ReviewItem(key: 'indoor_purchase', label: '가게안에서 구매할수 있어요', icon: Icons.store),
];

/// 신고 사유
const List<String> reportReasons = [
  '지점이 없어요',
  '계좌이체가 안돼요',
  '이름이 달라요',
  '주소가 달라요',
  '폐점된 것 같아요',
  '기타',
];

/// 판매점 상세 팝업을 보여주는 함수
Future<void> showStoreDetailPopup({
  required BuildContext context,
  required LotteryStore store,
  required Set<String> favorites,
  required Future<void> Function(String code) onToggleFavorite,
  double? distanceKm,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _StoreDetailSheet(
      store: store,
      favorites: favorites,
      onToggleFavorite: onToggleFavorite,
      distanceKm: distanceKm,
    ),
  );
}

class _StoreDetailSheet extends StatefulWidget {
  final LotteryStore store;
  final Set<String> favorites;
  final Future<void> Function(String code) onToggleFavorite;
  final double? distanceKm;

  const _StoreDetailSheet({
    required this.store,
    required this.favorites,
    required this.onToggleFavorite,
    this.distanceKm,
  });

  @override
  State<_StoreDetailSheet> createState() => _StoreDetailSheetState();
}

class _StoreDetailSheetState extends State<_StoreDetailSheet> {
  Map<String, Map<String, int>> _summary = {};
  Map<String, String> _myVotes = {};
  Map<String, int> _top30Ranks = {};
  bool _isLoadingReviews = true;
  late bool _isFavorite;
  String _deviceId = '';

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.favorites.contains(widget.store.dhlotteryCode);
    _loadTop30Ranks();
    _loadDeviceId();
  }

  Future<void> _loadTop30Ranks() async {
    final prefs = await SharedPreferences.getInstance();
    final rankList = prefs.getStringList('prev_ranking') ?? [];
    final Map<String, int> ranks = {};
    for (int i = 0; i < rankList.length; i++) {
      ranks[rankList[i]] = i + 1;
    }
    if (mounted) setState(() => _top30Ranks = ranks);
  }

  Future<void> _loadDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}_${UniqueKey().hashCode}';
      await prefs.setString('device_id', deviceId);
    }
    _deviceId = deviceId;
    await _loadReviews();
  }

  Future<void> _loadReviews() async {
    final code = widget.store.dhlotteryCode;
    final results = await Future.wait([
      SupabaseService.getReviewSummary(code),
      SupabaseService.getMyVotes(dhlotteryCode: code, deviceId: _deviceId),
    ]);

    if (!mounted) return;
    setState(() {
      _summary = results[0] as Map<String, Map<String, int>>;
      _myVotes = results[1] as Map<String, String>;
      _isLoadingReviews = false;
    });
  }

  Future<void> _handleVote(String reviewKey, String voteType) async {
    final code = widget.store.dhlotteryCode;
    final currentVote = _myVotes[reviewKey];

    // 낙관적 UI 업데이트
    setState(() {
      final counts = _summary[reviewKey] ?? {'up': 0, 'down': 0};
      int up = counts['up'] ?? 0;
      int down = counts['down'] ?? 0;

      if (currentVote == voteType) {
        // 취소
        if (voteType == 'up') up--;
        else down--;
        _myVotes.remove(reviewKey);
      } else {
        // 기존 투표 제거
        if (currentVote == 'up') up--;
        if (currentVote == 'down') down--;
        // 새 투표 추가
        if (voteType == 'up') up++;
        else down++;
        _myVotes[reviewKey] = voteType;
      }

      _summary[reviewKey] = {'up': up < 0 ? 0 : up, 'down': down < 0 ? 0 : down};
    });

    await SupabaseService.vote(
      dhlotteryCode: code,
      reviewKey: reviewKey,
      deviceId: _deviceId,
      voteType: voteType,
    );
  }

  Future<void> _handleToggleFavorite() async {
    await widget.onToggleFavorite(widget.store.dhlotteryCode);
    if (!mounted) return;
    setState(() => _isFavorite = !_isFavorite);
  }

  Future<void> _showReportDialog() async {
    String? selectedReason;
    final detailController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('판매점 신고', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('신고 사유를 선택하세요', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 12),
                ...reportReasons.map((reason) => RadioListTile<String>(
                  title: Text(reason, style: const TextStyle(fontSize: 14)),
                  value: reason,
                  groupValue: selectedReason,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setDialogState(() => selectedReason = v),
                )),
                const SizedBox(height: 8),
                TextField(
                  controller: detailController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: '추가 설명 (선택)',
                    hintStyle: const TextStyle(fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: selectedReason == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('신고', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedReason != null && mounted) {
      final resp = await SupabaseService.createReport(
        dhlotteryCode: widget.store.dhlotteryCode,
        deviceId: _deviceId,
        reason: selectedReason!,
        detail: detailController.text.trim().isEmpty ? null : detailController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp['message'] ?? '')),
        );
      }
    }
  }

  Future<void> _openMap(String mapType) async {
    final store = widget.store;
    String url;
    if (store.latitude != null && store.longitude != null) {
      final name = Uri.encodeComponent(store.storeName);
      if (mapType == 'naver') {
        url = 'nmap://map?lat=${store.latitude}&lng=${store.longitude}&label=$name&appname=com.luckylotto.finder';
      } else {
        url = 'https://map.kakao.com/link/map/$name,${store.latitude},${store.longitude}';
      }
    } else {
      final query = Uri.encodeComponent(store.address);
      if (mapType == 'naver') {
        url = 'https://map.naver.com/v5/search/$query';
      } else {
        url = 'https://map.kakao.com/link/search/$query';
      }
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      final fallbackQuery = Uri.encodeComponent(store.address);
      final fallbackUrl = mapType == 'naver'
          ? 'https://map.naver.com/v5/search/$fallbackQuery'
          : 'https://map.kakao.com/link/search/$fallbackQuery';
      await launchUrl(Uri.parse(fallbackUrl), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final badges = BadgeService.getBadges(store.dhlotteryCode);
    final top30Rank = _top30Ranks[store.dhlotteryCode];

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // 핸들
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── 상단: 즐겨찾기 + 신고 ──
            Row(
              children: [
                // 즐겨찾기 버튼
                InkWell(
                  onTap: _handleToggleFavorite,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _isFavorite ? Icons.star : Icons.star_border,
                      color: _isFavorite ? Colors.amber : Colors.grey,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    store.storeName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.distanceKm != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${widget.distanceKm!.toStringAsFixed(2)}km',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                const SizedBox(width: 8),
                // 신고 버튼
                TextButton.icon(
                  onPressed: _showReportDialog,
                  icon: const Icon(Icons.flag, size: 16, color: Colors.red),
                  label: const Text('신고', style: TextStyle(fontSize: 12, color: Colors.red)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ── 주소 ──
            Text(
              store.address,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),

            // ── 배지 ──
            if (badges.isNotEmpty || top30Rank != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (top30Rank != null) _buildTop30Badge(top30Rank),
                  ...badges.map((b) => _buildBadgeChip(b)),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // ── 지도 버튼 ──
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openMap('naver'),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('네이버지도'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openMap('kakao'),
                    icon: const Icon(Icons.place_outlined, size: 18),
                    label: const Text('카카오지도'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // ── 평가 카드 ──
            const Text(
              '판매점 평가',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '이 판매점에 대한 의견을 남겨주세요',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),

            if (_isLoadingReviews)
              const Center(child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 2),
              ))
            else
              ...reviewItems.map((item) => _buildReviewRow(item)),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewRow(ReviewItem item) {
    final myVote = _myVotes[item.key];
    final counts = _summary[item.key] ?? {'up': 0, 'down': 0};
    final upCount = counts['up'] ?? 0;
    final downCount = counts['down'] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(item.icon, size: 20, color: Colors.grey.shade600),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            // 엄지업
            _voteButton(
              icon: Icons.thumb_up,
              count: upCount,
              isSelected: myVote == 'up',
              selectedColor: Colors.blue,
              onTap: () => _handleVote(item.key, 'up'),
            ),
            const SizedBox(width: 6),
            // 엄지다운
            _voteButton(
              icon: Icons.thumb_down,
              count: downCount,
              isSelected: myVote == 'down',
              selectedColor: Colors.red,
              onTap: () => _handleVote(item.key, 'down'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voteButton({
    required IconData icon,
    required int count,
    required bool isSelected,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? selectedColor : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? selectedColor : Colors.grey,
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? selectedColor : Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTop30Badge(int rank) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300, width: 1),
      ),
      child: Text(
        '복권명당 TOP30:$rank위',
        style: TextStyle(
          fontSize: 10,
          color: Colors.amber.shade800,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBadgeChip(StoreBadge badge) {
    Color color;
    switch (badge.type) {
      case StoreBadgeType.hot:
        color = Colors.red;
        break;
      case StoreBadgeType.first:
        color = Colors.red.shade700;
        break;
      case StoreBadgeType.second:
        color = Colors.orange;
        break;
      case StoreBadgeType.regional:
        color = Colors.purple;
        break;
      case StoreBadgeType.streak:
        color = Colors.blue;
        break;
      case StoreBadgeType.rank:
        color = Colors.teal;
        break;
      case StoreBadgeType.pattern:
        color = Colors.grey.shade700;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badge.type == StoreBadgeType.hot
            ? color.withValues(alpha: 0.15)
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: badge.type == StoreBadgeType.hot
            ? Border.all(color: color.withValues(alpha: 0.5), width: 1)
            : null,
      ),
      child: Text(
        badge.label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: badge.type == StoreBadgeType.hot ? FontWeight.bold : FontWeight.w600,
        ),
      ),
    );
  }
}
