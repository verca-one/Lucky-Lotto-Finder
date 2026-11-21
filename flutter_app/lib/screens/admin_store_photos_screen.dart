// 관리자 › 판매점 사진 승인 — 대기 · 승인됨 · 거절 (승인 키 필요: store_photos.sql 에서 정한 키, 처음 한 번 입력)
//   승인한 사진만 홈 순위 카드 등 앱에 표시된다. 관리자는 판매점을 골라 직접 올릴 수도 있다(바로 승인).
import 'package:flutter/material.dart';

import '../services/store_photos.dart';
import '../widgets/store_photo_widgets.dart' show pickAndUploadStorePhoto;
import 'purchase_record_screen.dart' show showStorePicker;

const _c = Color(0xFF6A1B9A);

class AdminStorePhotosScreen extends StatefulWidget {
  const AdminStorePhotosScreen({super.key});
  @override
  State<AdminStorePhotosScreen> createState() => _AdminStorePhotosScreenState();
}

class _AdminStorePhotosScreenState extends State<AdminStorePhotosScreen> {
  String? _key;
  bool _keyLoaded = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    StorePhotos.savedKey().then((k) {
      if (!mounted) return;
      setState(() {
        _key = k;
        _keyLoaded = true;
      });
    });
  }

  Future<void> _askKey({String? error}) async {
    final ctl = TextEditingController();
    final k = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('승인 키 입력'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (error != null) Text(error, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
          const Text('store_photos.sql 에서 정한 승인 키 (이 폰에 기억됩니다)', style: TextStyle(fontSize: 12)),
          TextField(controller: ctl, obscureText: true, autofocus: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('확인')),
        ],
      ),
    );
    if (k == null || k.isEmpty) return;
    await StorePhotos.saveKey(k);
    if (!mounted) return;
    setState(() {
      _key = k;
      _gen++;
    });
  }

  Future<void> _review(StorePhoto p, String status) async {
    try {
      await StorePhotos.review(p.id, status, _key!);
      if (mounted) setState(() => _gen++);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('처리 실패: $e')));
    }
  }

  Future<void> _uploadAsAdmin() async {
    final s = await showStorePicker(context);
    if (s == null || !mounted) return;
    if (await pickAndUploadStorePhoto(context, code: s.dhlotteryCode, name: s.storeName, adminKey: _key) && mounted) {
      setState(() => _gen++);
    }
  }

  Widget _list(String status) => FutureBuilder<List<StorePhoto>>(
        key: ValueKey('$status$_gen'),
        future: StorePhotos.list(_key!, status),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            final keyErr = '${snap.error}'.contains('승인 키');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(keyErr ? '승인 키가 맞지 않습니다.' : '불러오지 못했습니다 (store_photos.sql 실행 필요할 수 있음)\n${snap.error}',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  if (keyErr) FilledButton(onPressed: () => _askKey(error: '키를 다시 입력해 주세요'), child: const Text('키 다시 입력')),
                ]),
              ),
            );
          }
          final l = snap.data ?? const [];
          if (l.isEmpty) return Center(child: Text({'pending': '승인 대기 사진이 없습니다', 'approved': '승인한 사진이 없습니다'}[status] ?? '거절한 사진이 없습니다'));
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: l.length,
            itemBuilder: (context, i) {
              final p = l[i];
              return Card(
                key: ValueKey('photo_${p.id}'),
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Image.network(p.url, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, size: 40))),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Text('${p.storeName.isEmpty ? p.code : p.storeName} · ${p.source == 'admin' ? '관리자' : '사용자'} · '
                        '${p.createdAt == null ? '' : '${p.createdAt!.month}/${p.createdAt!.day} ${p.createdAt!.hour.toString().padLeft(2, '0')}:${p.createdAt!.minute.toString().padLeft(2, '0')}'}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  OverflowBar(alignment: MainAxisAlignment.end, children: [
                    if (status != 'rejected')
                      TextButton(key: ValueKey('reject_${p.id}'), onPressed: () => _review(p, 'rejected'),
                          child: Text(status == 'approved' ? '승인 취소(거절)' : '거절', style: TextStyle(color: Colors.red.shade700))),
                    if (status != 'approved')
                      FilledButton(key: ValueKey('approve_${p.id}'), style: FilledButton.styleFrom(backgroundColor: _c),
                          onPressed: () => _review(p, 'approved'), child: const Text('승인')),
                  ]),
                ]),
              );
            },
          );
        },
      );

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('판매점 사진 승인', style: TextStyle(fontWeight: FontWeight.w800)),
            backgroundColor: _c,
            foregroundColor: Colors.white,
            actions: [IconButton(tooltip: '승인 키 바꾸기', onPressed: _askKey, icon: const Icon(Icons.key_rounded))],
            bottom: const TabBar(labelColor: Colors.white, unselectedLabelColor: Colors.white70, indicatorColor: Colors.amber,
                tabs: [Tab(text: '승인 대기'), Tab(text: '승인됨'), Tab(text: '거절')]),
          ),
          floatingActionButton: _key == null
              ? null
              : FloatingActionButton.extended(
                  key: const ValueKey('admin_photo_upload'),
                  backgroundColor: _c,
                  foregroundColor: Colors.white,
                  onPressed: _uploadAsAdmin,
                  icon: const Icon(Icons.add_a_photo_rounded),
                  label: const Text('직접 올리기'),
                ),
          body: !_keyLoaded
              ? const Center(child: CircularProgressIndicator())
              : _key == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('사진 승인에는 승인 키가 필요합니다.\n(store_photos.sql 맨 아래에서 정한 키)', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(key: const ValueKey('photo_key_enter'), onPressed: _askKey, child: const Text('승인 키 입력')),
                        ]),
                      ),
                    )
                  : TabBarView(children: [_list('pending'), _list('approved'), _list('rejected')]),
        ),
      );
}
