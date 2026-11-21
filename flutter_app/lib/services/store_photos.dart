// 판매점 사진 — 사용자가 올리고(승인 대기) 관리자가 승인한 것만 앱에 표시 (store_photos.sql)
//   파일: Storage 버킷 store-photos · 목록: store_photos (앱은 승인된 것만 읽음)
//   승인 · 거절 · 대기 목록은 서버 함수 + 승인 키 (키는 앱에 없음 — 관리자 화면에서 한 번 입력해 폰에 기억)
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kStorePhotoBucket = 'store-photos';
const kStorePhotoKeyPref = 'store_photo_admin_key';

class StorePhoto {
  final String id, code, storeName, path, status, source;
  final DateTime? createdAt;
  const StorePhoto({required this.id, required this.code, this.storeName = '', required this.path, required this.status,
      this.source = 'user', this.createdAt});
  factory StorePhoto.fromJson(Map<String, dynamic> j) => StorePhoto(
        id: '${j['id']}', code: '${j['dhlottery_code'] ?? ''}', storeName: '${j['store_name'] ?? ''}', path: '${j['path']}',
        status: '${j['status'] ?? 'pending'}', source: '${j['source'] ?? 'user'}',
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal(),
      );
  String get url => StorePhotos.publicUrl(path);
}

class StorePhotos {
  static SupabaseClient get _db => Supabase.instance.client;

  static String publicUrl(String path) => _db.storage.from(kStorePhotoBucket).getPublicUrl(path);

  /// 판매점별 가장 최근 승인 사진 주소 (승인된 것만 읽힘)
  static Future<Map<String, String>> approvedFor(List<String> codes) async {
    if (codes.isEmpty) return const {};
    final rows = await _db.from('store_photos').select('dhlottery_code,path,reviewed_at')
        .eq('status', 'approved').inFilter('dhlottery_code', codes).order('reviewed_at', ascending: false);
    final out = <String, String>{};
    for (final r in rows as List) {
      out.putIfAbsent('${r['dhlottery_code']}', () => publicUrl('${r['path']}'));
    }
    return out;
  }

  /// 갤러리 · 카메라에서 한 장 (긴 변 1280 · 품질 80 으로 줄여서)
  static Future<XFile?> pick(ImageSource source) =>
      ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);

  /// 올리기 — 항상 '승인 대기'로 들어감 (관리자 직접 올리기는 이어서 review 로 승인)
  static Future<StorePhoto> upload({required String code, required String storeName, required Uint8List bytes, bool admin = false}) async {
    final path = 'stores/$code/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage.from(kStorePhotoBucket).uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    final row = await _db.from('store_photos').insert({
      'dhlottery_code': code, 'store_name': storeName, 'path': path, 'status': 'pending', 'source': admin ? 'admin' : 'user',
    }).select().single();
    return StorePhoto.fromJson(row);
  }

  /// 상태별 장수 (승인 · 대기 · 거절) — 누구나
  static Future<Map<String, int>> counts() async {
    final rows = await _db.rpc('store_photo_counts');
    return {for (final r in rows as List) '${r['status']}': (r['n'] as num).toInt()};
  }

  static Future<String?> savedKey() async => (await SharedPreferences.getInstance()).getString(kStorePhotoKeyPref);
  static Future<void> saveKey(String? k) async {
    final p = await SharedPreferences.getInstance();
    k == null ? await p.remove(kStorePhotoKeyPref) : await p.setString(kStorePhotoKeyPref, k);
  }

  /// 상태별 목록 — 승인 키 필요 (틀리면 오류)
  static Future<List<StorePhoto>> list(String key, String status) async {
    final rows = await _db.rpc('list_store_photos', params: {'p_key': key, 'p_status': status});
    return [for (final r in rows as List) StorePhoto.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  /// 목록에서 삭제 (승인 키 필요) — shortcut: 보관함 파일은 남음(앱에 파일 삭제 권한을 열지 않으려고), Supabase 화면에서 정리
  static Future<void> delete(String id, String key) => _db.rpc('delete_store_photo', params: {'p_id': id, 'p_key': key});

  static Future<void> review(String id, String status, String key) =>
      _db.rpc('review_store_photo', params: {'p_id': id, 'p_status': status, 'p_key': key});
}
