// 나의 번호 › 구입 기록 — 추가 화면(판매점 · 회차 · 번호) · 판매점 고르기(근처 · 검색 · 즐겨찾기) · 기록 목록(자동 당첨 확인)
//   판매점 상세 팝업의 [여기서 산 번호 기록]으로 열면 판매점이 미리 정해진다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/lottery_store.dart';
import '../models/lotto_winning_number.dart';
import '../services/purchase_records.dart';
import '../services/research/briefing_hit_check.dart' show lottoRank;
import '../services/supabase_service.dart';
import '../widgets/winning_number_boxes.dart' show numberBall, lottoRangeColor;
import 'lotto_qr_scan_screen.dart';

const _c = Color(0xFF1565C0);

/// 구입 기록 추가 — 저장하면 true
Future<bool> openPurchaseRecord(BuildContext context, {LotteryStore? store, bool startQr = false}) async =>
    await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => PurchaseRecordScreen(store: store, startQr: startQr))) ==
    true;

class PurchaseRecordScreen extends StatefulWidget {
  final LotteryStore? store;
  final bool startQr; // 열자마자 QR 카메라
  const PurchaseRecordScreen({super.key, this.store, this.startQr = false});
  @override
  State<PurchaseRecordScreen> createState() => _PurchaseRecordScreenState();
}

class _PurchaseRecordScreenState extends State<PurchaseRecordScreen> {
  LotteryStore? _store;
  int? _round;
  final _games = <List<int>>[];
  List<(List<int>, String)> _saved = const []; // 저장한 번호 (번호, 저장 날짜)

  @override
  void initState() {
    super.initState();
    _store = widget.store;
    _init();
    if (widget.startQr) WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _init() async {
    final latest = await SupabaseService.getLatestNumbersRound('lotto');
    final prefs = await SharedPreferences.getInstance();
    final saved = <(List<int>, String)>[];
    for (final s in prefs.getStringList('my_lotto_numbers') ?? const <String>[]) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        final d = DateTime.tryParse('${m['date']}');
        saved.add(([for (final n in m['numbers'] as List) (n as num).toInt()]..sort(), d == null ? '' : '${d.month}/${d.day}'));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _round ??= latest == null ? null : latest + 1; // 다음 추첨 회차 (QR 이 있으면 QR 회차)
      _saved = saved.reversed.toList();
    });
  }

  Future<void> _scan() async {
    final r = await Navigator.push<(int, List<List<int>>)>(context, MaterialPageRoute(builder: (_) => const LottoQrScanScreen()));
    if (r == null || !mounted) return;
    setState(() {
      _round = r.$1;
      _games
        ..clear()
        ..addAll(r.$2);
    });
  }

  void _addGame(List<int> g) {
    if (_games.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('한 장에 최대 5게임입니다')));
      return;
    }
    setState(() => _games.add([...g]));
  }

  Future<void> _pickStore() async {
    final s = await showStorePicker(context);
    if (s != null && mounted) setState(() => _store = s);
  }

  Future<void> _save() async {
    final s = _store!;
    await PurchaseRecords.add(PurchaseRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(), storeCode: s.dhlotteryCode, storeName: s.storeName,
      storeAddress: s.address, round: _round!, games: _games, createdAt: DateTime.now(),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$_round회 · ${s.storeName} · ${_games.length}게임 기록했습니다')));
    Navigator.pop(context, true);
  }

  Widget _section(String t, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
          ?trailing,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final ok = _store != null && _round != null && _games.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('구입 기록', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: _c,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            key: const ValueKey('purchase_save'),
            style: FilledButton.styleFrom(backgroundColor: _c, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: ok ? _save : null,
            child: Text(ok ? '저장 — $_round회 ${_games.length}게임' : '판매점과 번호를 넣어 주세요',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
        _section('어디서 샀나요'),
        InkWell(
          key: const ValueKey('purchase_store'),
          onTap: _pickStore,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _c.withValues(alpha: 0.3))),
            child: Row(children: [
              const Icon(Icons.storefront_rounded, color: _c),
              const SizedBox(width: 10),
              Expanded(
                child: _store == null
                    ? const Text('판매점 고르기 (근처 · 검색 · 즐겨찾기)', style: TextStyle(fontWeight: FontWeight.w700, color: _c))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_store!.storeName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                        Text(_store!.address, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                      ]),
              ),
              Text(_store == null ? '' : '바꾸기', style: const TextStyle(fontSize: 12, color: _c)),
            ]),
          ),
        ),
        _section('몇 회차인가요', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            onPressed: _round == null || _round! <= 1 ? null : () => setState(() => _round = _round! - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(_round == null ? '-' : '$_round회', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          IconButton(onPressed: _round == null ? null : () => setState(() => _round = _round! + 1), icon: const Icon(Icons.add_circle_outline)),
        ])),
        _section('어떤 번호를 샀나요 (최대 5게임)'),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('purchase_qr'),
            style: FilledButton.styleFrom(backgroundColor: Colors.black87, padding: const EdgeInsets.symmetric(vertical: 12)),
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('로또 용지 QR로 찍기 (회차 · 번호 자동)', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          key: const ValueKey('purchase_saved'),
          isExpanded: true,
          decoration: const InputDecoration(labelText: '저장한 번호 불러오기', border: OutlineInputBorder(), isDense: true),
          items: [
            for (final (i, s) in _saved.indexed)
              DropdownMenuItem(value: i, child: Text('${s.$1.join('  ')}${s.$2.isEmpty ? '' : '   (${s.$2})'}')),
          ],
          onChanged: _saved.isEmpty ? null : (i) => i == null ? null : _addGame(_saved[i].$1),
          hint: Text(_saved.isEmpty ? '저장한 번호가 없습니다' : '골라서 한 게임씩 추가'),
        ),
        const SizedBox(height: 10),
        for (final (i, g) in _games.indexed)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: _c.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              SizedBox(width: 20, child: Text('${'ABCDE'[i]}', style: const TextStyle(fontWeight: FontWeight.w900, color: _c))),
              Expanded(
                child: Wrap(spacing: 5, children: [for (final n in g) numberBall('$n', lottoRangeColor(n), size: 30, fontSize: 12)]),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _games.removeAt(i)),
                icon: Icon(Icons.close_rounded, color: Colors.grey.shade500),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// 판매점 고르기 — 근처 · 검색 · 즐겨찾기 (로또 판매점)
Future<LotteryStore?> showStorePicker(BuildContext context) => showModalBottomSheet<LotteryStore>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: _StorePicker()),
    );

class _StorePicker extends StatefulWidget {
  const _StorePicker();
  @override
  State<_StorePicker> createState() => _StorePickerState();
}

class _StorePickerState extends State<_StorePicker> {
  late final Future<List<(LotteryStore, double?)>> _near = _loadNear();
  late final Future<List<(LotteryStore, double?)>> _fav = _loadFav();
  Future<List<(LotteryStore, double?)>>? _search;

  static Future<List<(LotteryStore, double?)>> _loadNear() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      throw '위치 권한이 없어 근처 판매점을 찾을 수 없습니다 — 검색이나 즐겨찾기에서 골라 주세요';
    }
    final p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium, timeLimit: const Duration(seconds: 12));
    final stores = await SupabaseService.getNearbyStores(latitude: p.latitude, longitude: p.longitude, radiusKm: 2, lotteryType: 'lotto');
    final out = [
      for (final s in stores)
        if (s.latitude != null && s.longitude != null)
          (s, Geolocator.distanceBetween(p.latitude, p.longitude, s.latitude!, s.longitude!)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return out.take(40).toList();
  }

  static Future<List<(LotteryStore, double?)>> _loadFav() async {
    final prefs = await SharedPreferences.getInstance();
    final codes = prefs.getStringList('favorite_stores') ?? const <String>[];
    return [for (final s in await SupabaseService.getStoresByCodes(codes)) if (s.lotteryType == 'lotto') (s, null)];
  }

  static Future<List<(LotteryStore, double?)>> _find(String q) async {
    final rows = await Supabase.instance.client.from('lottery_stores').select()
        .eq('lottery_type', 'lotto').ilike('store_name', '%$q%').limit(40);
    return [for (final r in rows as List) (LotteryStore.fromJson(r as Map<String, dynamic>), null)];
  }

  Widget _list(Future<List<(LotteryStore, double?)>>? f, String empty) => f == null
      ? Center(child: Text(empty, style: TextStyle(color: Colors.grey.shade600)))
      : FutureBuilder<List<(LotteryStore, double?)>>(
          future: f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snap.hasError) {
              return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}', textAlign: TextAlign.center)));
            }
            final l = snap.data ?? const [];
            if (l.isEmpty) return Center(child: Text(empty, style: TextStyle(color: Colors.grey.shade600)));
            return ListView.separated(
              itemCount: l.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final (s, d) = l[i];
                return ListTile(
                  key: ValueKey('pick_store_${s.dhlotteryCode}'),
                  title: Text(s.storeName, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(s.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: d == null ? null : Text(d < 1000 ? '${d.round()}m' : '${(d / 1000).toStringAsFixed(1)}km'),
                  onTap: () => Navigator.pop(context, s),
                );
              },
            );
          },
        );

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(children: [
          const SizedBox(height: 8),
          const Text('구입한 판매점 고르기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const TabBar(labelColor: _c, indicatorColor: _c, tabs: [Tab(text: '근처'), Tab(text: '검색'), Tab(text: '즐겨찾기')]),
          Expanded(
            child: TabBarView(children: [
              _list(_near, '2km 안에 로또 판매점이 없습니다'),
              Column(children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    key: const ValueKey('pick_store_search'),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(hintText: '판매점 이름', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
                    onSubmitted: (q) => setState(() => _search = q.trim().length < 2 ? null : _find(q.trim())),
                  ),
                ),
                Expanded(child: _list(_search, '두 글자 이상 입력 후 검색')),
              ]),
              _list(_fav, '즐겨찾기한 로또 판매점이 없습니다'),
            ]),
          ),
        ]),
      );
}

/// 나의 번호 › 구입 기록 목록 — 그 회차 당첨번호가 있으면 자동으로 맞춰 봄
class PurchaseRecordsSection extends StatefulWidget {
  final Future<List<PurchaseRecord>> Function()? loader;
  final Future<LottoWinningNumber?> Function(int round)? winLoader;
  const PurchaseRecordsSection({super.key, this.loader, this.winLoader});
  @override
  State<PurchaseRecordsSection> createState() => _PurchaseRecordsSectionState();
}

class _PurchaseRecordsSectionState extends State<PurchaseRecordsSection> {
  List<PurchaseRecord>? _records;
  final _wins = <int, LottoWinningNumber?>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await (widget.loader ?? PurchaseRecords.load)();
    for (final round in {for (final x in r) x.round}) {
      if (_wins[round] != null) continue;
      try {
        _wins[round] = await (widget.winLoader ?? SupabaseService.getWinningNumbersForRound)(round);
      } catch (_) {}
    }
    if (mounted) setState(() => _records = r);
  }

  Future<void> _add() async {
    if (await openPurchaseRecord(context)) _load();
  }

  Future<void> _delete(PurchaseRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('구입 기록 삭제'),
        content: Text('${r.round}회 · ${r.storeName} 기록을 지울까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    await PurchaseRecords.remove(r.id);
    _load();
  }

  Widget _card(PurchaseRecord r) {
    final w = _wins[r.round];
    final ranks = [for (final g in r.games) w == null ? null : lottoRank(g, w.numbers, w.bonusNumber)];
    final best = ranks.whereType<int>().fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    final (String status, Color sc) = w == null
        ? ('추첨 전 · 당첨번호 나오면 자동 확인', Colors.blueGrey)
        : best == null
            ? ('낙첨', Colors.grey.shade600)
            : ('$best등 당첨!', const Color(0xFFD84315));
    return Container(
      key: ValueKey('purchase_${r.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: best != null ? const Color(0xFFFFB74D) : Colors.grey.shade200, width: best != null ? 1.6 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${r.round}회', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _c)),
          const SizedBox(width: 8),
          Expanded(child: Text(r.storeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
          GestureDetector(onTap: () => _delete(r), child: Icon(Icons.delete_outline, size: 20, color: Colors.grey.shade400)),
        ]),
        const SizedBox(height: 4),
        Text(status, key: ValueKey('purchase_status_${r.id}'),
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: sc)),
        const SizedBox(height: 6),
        for (final (i, g) in r.games.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(width: 18, child: Text('ABCDE'[i], style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade600))),
              for (final n in g)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  // 추첨 후: 맞은 번호만 색, 나머지는 흐리게
                  child: Opacity(
                    opacity: w == null || w.numbers.contains(n) || (ranks[i] == 2 && n == w.bonusNumber) ? 1 : 0.28,
                    child: numberBall('$n', lottoRangeColor(n), size: 28, fontSize: 11.5),
                  ),
                ),
              const Spacer(),
              if (w != null)
                Text(ranks[i] == null ? '${g.where(w.numbers.contains).length}개' : '${ranks[i]}등',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: ranks[i] == null ? Colors.grey : const Color(0xFFD84315))),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _records;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.receipt_long_rounded, color: _c, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text('구입 기록${r == null ? '' : ' (${r.length})'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        FilledButton.icon(
          key: const ValueKey('purchase_add'),
          style: FilledButton.styleFrom(backgroundColor: _c, visualDensity: VisualDensity.compact),
          onPressed: _add,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('구입 기록', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
      const SizedBox(height: 8),
      if (r == null)
        const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
      else if (r.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('산 번호를 기록해 두면 추첨 뒤 당첨 여부를 자동으로 알려 드립니다.\n판매점 상세 화면의 [여기서 산 번호 기록]이나 위 버튼으로 QR을 찍어 보세요.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.5)),
        )
      else
        ...r.map(_card),
    ]);
  }
}
