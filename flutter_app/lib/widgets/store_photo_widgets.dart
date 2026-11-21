// 판매점 사진 — 올리기(갤러리 · 카메라 → 승인 대기) · 브리핑 상황판 통계 한 줄
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/admin_store_photos_screen.dart';
import '../services/store_photos.dart';

/// 사진 고르기 → 올리기. 사용자는 '승인 대기', 관리자(adminKey 있음)는 올리고 바로 승인. 올렸으면 true
Future<bool> pickAndUploadStorePhoto(BuildContext context, {required String code, required String name, String? adminKey}) async {
  // 사진 올리기 권한 = 프로필 로그인 (카메라 버튼과 같은 조건) · 관리자 직접 올리기는 승인 키
  if (adminKey == null && ((await SharedPreferences.getInstance()).getString('userId') ?? '').isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('프로필 로그인 후 사진을 올릴 수 있습니다')));
    }
    return false;
  }
  if (!context.mounted) return false;
  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text('$name 사진 올리기', style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(adminKey == null ? '관리자 승인 후 업로드됩니다' : '관리자 — 올리면 바로 승인됩니다'),
        ),
        ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('갤러리에서 고르기'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
        ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('카메라로 찍기'), onTap: () => Navigator.pop(c, ImageSource.camera)),
      ]),
    ),
  );
  if (src == null) return false;
  final f = await StorePhotos.pick(src);
  if (f == null) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final p = await StorePhotos.upload(code: code, storeName: name, bytes: await f.readAsBytes(), admin: adminKey != null);
    if (adminKey != null) await StorePhotos.review(p.id, 'approved', adminKey);
    messenger?.showSnackBar(SnackBar(content: Text(adminKey == null ? '사진을 보냈습니다 — 관리자 승인 후 업로드됩니다' : '사진을 올리고 승인했습니다')));
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('사진 올리기 실패: $e')));
    return false;
  }
}

/// 브리핑 상황판 — 판매점 사진 승인 · 대기 · 거절 장수 (누르면 승인 화면)
class StorePhotoStatsLine extends StatefulWidget {
  final Future<Map<String, int>> Function()? loader;
  const StorePhotoStatsLine({super.key, this.loader});
  @override
  State<StorePhotoStatsLine> createState() => _StorePhotoStatsLineState();
}

class _StorePhotoStatsLineState extends State<StorePhotoStatsLine> {
  late final Future<Map<String, int>> _f = (widget.loader ?? StorePhotos.counts)();

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, int>>(
        future: _f,
        builder: (context, snap) {
          final m = snap.data;
          if (m == null) return const SizedBox.shrink(); // 표 없음(SQL 미적용) · 읽기 실패면 숨김
          final pending = m['pending'] ?? 0;
          final c = pending > 0 ? const Color(0xFFE65100) : const Color(0xFF455A64);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                key: const ValueKey('store_photo_stats'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminStorePhotosScreen())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.photo_library_rounded, size: 18, color: c),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('판매점 사진 — 승인 ${m['approved'] ?? 0} · 대기 $pending · 거절 ${m['rejected'] ?? 0}',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: c)),
                    ),
                    if (pending > 0)
                      Text('승인하러 가기', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
                    Icon(Icons.chevron_right_rounded, color: c, size: 18),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}
