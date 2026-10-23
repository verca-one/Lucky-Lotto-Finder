// 연금복권720+ 브리핑 화면 — 관리자 엔진 브리핑 '연금복권' 탭 · 일반 모드 추천 '연금' 탭 (같은 화면, 데이터 출처만 다름)
//  ① 연금 번호 엔진 · ② 연금 명당 · ③ 연금 가설 트랙
import 'package:flutter/material.dart';

import '../screens/admin_pension_numbers_input_screen.dart';
import '../services/research/pension_briefing.dart';
import 'briefing_store_widgets.dart' show FavoriteStoreStar;
import 'winning_number_boxes.dart';

const kPensionColor = Color(0xFFEF6C00);

/// 연금 티켓 한 장: [3조] 1 2 3 4 5 6
Widget pensionTicket(PensionTicket t, {Color color = kPensionColor}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
          child: Text('${t.group}조', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        for (final ch in t.number.split(''))
          Container(
            width: 30, height: 34, margin: const EdgeInsets.only(right: 4), alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300)),
            child: Text(ch, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
      ]),
    );

class PensionBriefingView extends StatefulWidget {
  /// true = 관리자(연구 저장본 · 입력 메뉴 바로가기 · 명당 · 가설 트랙) / false = 일반 모드(당첨번호 + 연금 번호 엔진만)
  final bool admin;
  final Future<PensionBriefing?> Function()? loader;

  /// 일반 모드 상단 당첨번호 (테스트용)
  final Future<PensionLatestWinning?> Function()? winningLoader;
  const PensionBriefingView({super.key, this.admin = true, this.loader, this.winningLoader});
  @override
  State<PensionBriefingView> createState() => _PensionBriefingViewState();
}

class _PensionBriefingViewState extends State<PensionBriefingView> {
  late Future<PensionBriefing?> _f;

  @override
  void initState() {
    super.initState();
    _f = (widget.loader ?? (widget.admin ? PensionBriefing.loadAdmin : PensionBriefing.loadPublic))();
  }

  Future<void> _reload() async {
    setState(() => _f = (widget.loader ?? (widget.admin ? PensionBriefing.loadAdmin : PensionBriefing.loadPublic))());
    await _f;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<PensionBriefing?>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final b = snap.data;
          if (!widget.admin) return _public(b, snap.hasError);
          return ListView(padding: const EdgeInsets.all(16), children: [
            _hero(b),
            const SizedBox(height: 12),
            if (snap.hasError)
              _note('불러오지 못했습니다: ${snap.error}')
            else if (b == null)
              _note(widget.admin
                  ? '연금 브리핑 저장본이 아직 없습니다 — 서버가 매일 17시(가설 공장 뒤)에 만듭니다.'
                  : '연금복권 추천을 준비하고 있습니다.')
            else ...[
              _engine(b),
              const SizedBox(height: 12),
              _stores(b),
              const SizedBox(height: 12),
              _track(b),
              const SizedBox(height: 12),
              Text(b.disclaimer.isNotEmpty ? b.disclaimer : '모든 추천은 과거 기록·가설에 기반한 참고용입니다. 연금복권 한 장의 1등 확률(1/5,000,000)은 어떤 번호든 같습니다.',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
            ],
            const SizedBox(height: 24),
          ]);
        },
      ),
    );
  }

  /// 일반 모드: 최신 당첨번호(상단) → 연금 번호 엔진
  Widget _public(PensionBriefing? b, bool error) => ListView(padding: EdgeInsets.zero, children: [
        PensionWinningHeader(loader: widget.winningLoader),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (b == null || error)
              _note('연금복권 추천번호를 준비하고 있습니다.')
            else ...[
              _engine(b),
              const SizedBox(height: 12),
              _stores(b),
            ],
            const SizedBox(height: 12),
            Text(b?.disclaimer.isNotEmpty == true ? b!.disclaimer : '추천번호는 과거 당첨번호 기록에 기반한 참고용입니다. 연금복권 한 장의 1등 확률(1/5,000,000)은 어떤 번호든 같습니다.',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4)),
          ]),
        ),
      ]);

  Widget _hero(PensionBriefing? b) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFEF6C00), Color(0xFFFFA726)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('연금복권720+', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
          Text(b == null ? '이번 회차 추천' : '${b.targetRound}회 추천 · ${b.drawDate} (목)',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          if (widget.admin && b != null)
            Text('당첨번호 입력 ${b.numbersEntered}회 · 명당 기록 ${b.latestRound}회까지',
                style: const TextStyle(color: Colors.white, fontSize: 11.5)),
        ]),
      );

  Widget _card(String no, String title, Widget child, {Widget? chip}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kPensionColor.withValues(alpha: 0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 26, height: 26, alignment: Alignment.center,
              decoration: BoxDecoration(color: kPensionColor, borderRadius: BorderRadius.circular(8)),
              child: Text(no, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
            if (chip != null) chip,
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      );

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
      );

  Widget _note(String s) => Text(s, style: TextStyle(fontSize: 12, color: Colors.orange.shade900));

  Widget _small(String s) => Text(s, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, height: 1.4));

  Widget _engine(PensionBriefing b) => _card(
        '1',
        widget.admin ? '연금 번호 엔진' : '추천번호',
        b.engineStatus == 'ok'
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final t in b.engineTickets) Padding(padding: const EdgeInsets.only(bottom: 6), child: pensionTicket(t)),
                if (b.engineRule != null) _small(b.engineRule!),
                if (b.groupCounts.isNotEmpty)
                  _small('최근 1등 조 빈도: ${b.groupCounts.entries.map((e) => '${e.key}조 ${e.value}').join(' · ')}'),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _note(widget.admin ? (b.engineNote ?? '당첨번호 데이터를 모으는 중입니다.') : '연금 번호 엔진을 준비하고 있습니다 (당첨번호 기록을 모으는 중).'),
                if (widget.admin) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('pension_input_shortcut'),
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminPensionNumbersInputScreen())).then((_) => _reload()),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('연금복권 당첨번호 입력'),
                  ),
                ],
              ]),
        chip: _chip(b.engineStatus == 'ok' ? '가동' : '대기', b.engineStatus == 'ok' ? Colors.green.shade700 : Colors.grey.shade700),
      );

  Widget _stores(PensionBriefing b) => _card(
        '2',
        widget.admin ? '연금 명당 TOP${b.stores.length}' : '연금 판매점',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!widget.admin) _small('연금복권 1·2등이 나온 판매점 · ★를 누르면 즐겨찾기에 저장됩니다'),
          if (b.stores.isEmpty) _note(widget.admin ? '연금 명당 기록 없음' : '연금 판매점 정보를 준비하고 있습니다.'),
          for (final e in b.stores.asMap().entries)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: kPensionColor.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                SizedBox(width: 24, child: Text('${e.key + 1}', style: const TextStyle(fontWeight: FontWeight.w900, color: kPensionColor))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.value.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    Text('${e.value.region} · 최근 당첨 ${e.value.lastRound}회', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('1등 ${e.value.first} · 2등 ${e.value.second}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                  if (widget.admin && e.value.pNext != null)
                    Text('다음 회차 1·2등 추정 ${(e.value.pNext! * 100).toStringAsFixed(2)}%', style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600)),
                ]),
                if (e.value.code.isNotEmpty) FavoriteStoreStar(code: e.value.code, name: e.value.name),
              ]),
            ),
          if (widget.admin && b.storeRule != null) _small(b.storeRule!),
        ]),
      );

  Widget _track(PensionBriefing b) => _card(
        '3',
        '연금 가설 트랙 — 제미나이',
        b.trackStatus == 'ok'
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final t in b.trackTickets)
                  Padding(padding: const EdgeInsets.only(bottom: 6), child: pensionTicket(t, color: const Color(0xFF6A1B9A))),
                if (b.trackHyps.isEmpty)
                  _small('이번 회차 조건에 맞는 가설이 없어 방향 없이 고른 번호입니다.')
                else ...[
                  const Text('사용한 가설', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                  for (final h in b.trackHyps)
                    _small('· ${h.statement}${h.z != null ? ' — 최근 z ${h.z!.toStringAsFixed(2)}' : ''}${h.m != null ? ' · 성적 ×${h.m!.toStringAsFixed(2)}' : ''}'),
                ],
                _small('검증 전 가설 기반 예측입니다.'),
              ])
            : _note(b.trackNote ?? '연금 가설을 준비하고 있습니다.'),
        chip: _chip('가설 기반', const Color(0xFF6A1B9A)),
      );
}
