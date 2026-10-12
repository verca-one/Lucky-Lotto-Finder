// 판매점 카드 하단 [네이버 지도] [카카오맵] 버튼
import 'package:flutter/material.dart';

import '../services/store_map_launcher.dart';

const Color kNaverGreen = Color(0xFF03C75A);
const Color kKakaoYellow = Color(0xFFFEE500);

class StoreMapButtons extends StatelessWidget {
  final StoreMapTarget target;
  const StoreMapButtons({super.key, required this.target});

  Future<void> _open(BuildContext context, StoreMapService s) async {
    final r = await openStoreOnMap(s, target);
    if (r == 'failed' && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text('${s == StoreMapService.naver ? '네이버 지도' : '카카오맵'}를 열 수 없습니다.'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: _MapButton(
          key: ValueKey('naver_${target.storeId}'),
          label: '네이버 지도',
          background: kNaverGreen,
          foreground: Colors.white,
          badge: 'N',
          onTap: () => _open(context, StoreMapService.naver),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _MapButton(
          key: ValueKey('kakao_${target.storeId}'),
          label: '카카오맵',
          background: kKakaoYellow,
          foreground: const Color(0xFF3C1E1E),
          badge: 'K',
          onTap: () => _open(context, StoreMapService.kakao),
        ),
      ),
    ]);
  }
}

class _MapButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final String badge;
  final VoidCallback onTap;
  const _MapButton({super.key, required this.label, required this.background, required this.foreground,
      required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 18, height: 18, alignment: Alignment.center,
              decoration: BoxDecoration(color: foreground.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5)),
              child: Icon(Icons.place_rounded, size: 13, color: foreground),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: foreground)),
            ),
          ]),
        ),
      ),
    );
  }
}
