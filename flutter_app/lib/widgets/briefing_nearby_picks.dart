// ④ 이번 주 엔진 추천 명당 — [내 위치] 누르면 추천 명당(④ 선정 · 제미나이 가설 명당 · 적중 예측 순위) 중 내 위치와 가까운 곳을 따로 보여줌
//   좌표가 없는 곳은 lottery_stores 에서 읽기만 한다.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/research/hypothesis_track.dart';
import '../services/store_map_launcher.dart' show StoreMapTarget;
import '../services/supabase_service.dart';
import 'briefing_store_widgets.dart' show FavoriteStoreStar;
import 'store_map_buttons.dart' show showStoreMapSheet;

/// 추천 명당 후보 하나 (코드 · 이름 · 주소 · 좌표 · 어디서 추천했나)
typedef NearbyPick = ({String code, String name, String address, double? lat, double? lng, String tag});

/// 같은 판매점은 한 줄 (추천 출처는 합침) · 거리 순 · 최대 [max]곳 (순수 함수)
List<(NearbyPick, double)> nearestPicks(List<NearbyPick> picks, double lat, double lng, {int max = 10}) {
  final byCode = <String, NearbyPick>{};
  for (final p in picks) {
    final o = byCode[p.code];
    byCode[p.code] = o == null
        ? p
        : (code: o.code, name: o.name, address: o.address.isEmpty ? p.address : o.address,
            lat: o.lat ?? p.lat, lng: o.lng ?? p.lng, tag: o.tag.contains(p.tag) ? o.tag : '${o.tag} · ${p.tag}');
  }
  final out = [
    for (final p in byCode.values)
      if (p.lat != null && p.lng != null) (p, Geolocator.distanceBetween(lat, lng, p.lat!, p.lng!)),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return out.take(max).toList();
}

class BriefingNearbyPicks extends StatefulWidget {
  final int target;
  final List<NearbyPick> picks; // ④ 선정 · 적중 예측 순위 (가설 명당은 여기서 읽음)
  final Color color;

  /// 테스트용
  final Future<(double, double)> Function()? locate;
  final Future<HypothesisTrack?> Function(int target)? trackLoader;
  const BriefingNearbyPicks({super.key, required this.target, required this.picks, required this.color, this.locate, this.trackLoader});
  @override
  State<BriefingNearbyPicks> createState() => _BriefingNearbyPicksState();
}

class _BriefingNearbyPicksState extends State<BriefingNearbyPicks> {
  Future<List<(NearbyPick, double)>>? _f;

  static Future<(double, double)> _locate() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw '위치 권한이 없어 가까운 명당을 찾을 수 없습니다';
    final p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium, timeLimit: const Duration(seconds: 12));
    return (p.latitude, p.longitude);
  }

  Future<List<(NearbyPick, double)>> _load() async {
    final here = await (widget.locate ?? _locate)();
    final picks = [...widget.picks];
    try {
      final t = await (widget.trackLoader ?? HypothesisTrack.load)(widget.target);
      for (final s in t?.stores ?? const <TrackStore>[]) {
        picks.add((code: s.code, name: s.name, address: s.address, lat: null, lng: null, tag: '제미나이 가설 명당'));
      }
    } catch (_) {}
    // 좌표 없는 곳 — 판매점 표에서 읽기만
    final need = {for (final p in picks) if (p.lat == null || p.lng == null) p.code}.toList();
    if (need.isNotEmpty) {
      final info = {for (final s in await SupabaseService.getStoresByCodes(need)) s.dhlotteryCode: s};
      for (var i = 0; i < picks.length; i++) {
        final p = picks[i], s = info[p.code];
        if ((p.lat == null || p.lng == null) && s != null) {
          picks[i] = (code: p.code, name: p.name, address: p.address.isEmpty ? s.address : p.address, lat: s.latitude, lng: s.longitude, tag: p.tag);
        }
      }
    }
    return nearestPicks(picks, here.$1, here.$2);
  }

  String _dist(double m) => m < 1000 ? '${m.round()}m' : '${(m / 1000).toStringAsFixed(1)}km';

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledButton.icon(
        key: const ValueKey('briefing_nearby_button'),
        style: FilledButton.styleFrom(backgroundColor: c, visualDensity: VisualDensity.compact),
        onPressed: () => setState(() {
          _f = _load();
        }),
        icon: const Icon(Icons.my_location, size: 18),
        label: Text(_f == null ? '내 위치 — 가까운 추천 명당 보기' : '내 위치 — 다시 찾기', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      if (_f != null)
        Container(
          key: const ValueKey('briefing_nearby_box'),
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.3))),
          child: FutureBuilder<List<(NearbyPick, double)>>(
            future: _f,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) return Text('${snap.error}', style: TextStyle(fontSize: 12, color: Colors.orange.shade900));
              final l = snap.data ?? const [];
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('내 위치에서 가까운 추천 명당 ${l.length}곳', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: c)),
                Text('④ 이번 주 추천 · 제미나이 가설 명당 · 적중 예측 순위 중 가까운 순', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                if (l.isEmpty) Text('위치를 아는 추천 명당이 없습니다.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                for (final (p, d) in l)
                  Container(
                    key: ValueKey('nearby_pick_${p.code}'),
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      SizedBox(width: 54, child: Text(_dist(d), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: c))),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                          Text(p.tag, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                        ]),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '지도',
                        icon: Icon(Icons.map_rounded, color: c, size: 20),
                        onPressed: () => showStoreMapSheet(context, StoreMapTarget(storeId: p.code, name: p.name, address: p.address, lat: p.lat, lng: p.lng)),
                      ),
                      FavoriteStoreStar(code: p.code, name: p.name),
                    ]),
                  ),
              ]);
            },
          ),
        ),
    ]);
  }
}
